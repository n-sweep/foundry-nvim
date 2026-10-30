import base64
import logging
import os
import queue
import socket
import sqlite3
import threading
from datetime import datetime, timezone
from typing import Generator

from flask import Flask, Response, abort, render_template, stream_with_context
from werkzeug.serving import make_server, WSGIRequestHandler

app = Flask(__name__)

PLOTLY_MIME = 'application/vnd.plotly.v1+json'

# read-side column list; image bytes are never loaded here, so `data` is the
# figure JSON for plotly rows and NULL for everything else
PLOT_COLS = (
    'id, mime, created_at, cell_id, '
    f"CASE WHEN mime = '{PLOTLY_MIME}' THEN data END AS data"
)

class QuietHandler(WSGIRequestHandler):
    """WSGIRequestHandler that routes logs to Python's logging module
    instead of writing directly to stderr."""

    def log(self, type: str, message: str, *args) -> None:
        """Override werkzeug's default stderr logging."""
        getattr(logging, type)(message, *args)


def default_db_path() -> str:
    """return the default plot database path under the XDG data directory."""
    data_home = os.environ.get('XDG_DATA_HOME') or os.path.expanduser('~/.local/share')
    return os.path.join(data_home, 'foundry-nvim', 'plots.sqlite3')


def init_db() -> None:
    """create the database directory and the plot table if they do not exist."""
    db_file = app.config['db_file']
    os.makedirs(os.path.dirname(db_file), exist_ok=True)
    with sqlite3.connect(db_file) as con:
        con.execute(
            """
            CREATE TABLE IF NOT EXISTS plot (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                mime       TEXT NOT NULL,
                data       BLOB NOT NULL,
                created_at TEXT NOT NULL,
                cell_id    TEXT NOT NULL
            )
            """
        )


def create_plot(data: str | bytes, mime: str = PLOTLY_MIME, cell_id: str = '') -> dict:
    """insert a new plot and return it as a dict.

    Parameters
    ----------
    data : str or bytes
        raw plotly figure JSON string, or decoded image bytes
    mime : str, optional
        mime type of the data, by default the plotly figure type
    cell_id : str, optional
        id of the cell execution that produced the plot, by default ''

    Returns
    -------
    dict
        the newly created plot row with keys id, mime, created_at, cell_id,
        data; data is None for non-plotly rows
    """
    now = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')
    with sqlite3.connect(app.config['db_file']) as con:
        cur = con.execute(
            'INSERT INTO plot (mime, data, created_at, cell_id) VALUES (?, ?, ?, ?)',
            (mime, data, now, cell_id),
        )
        con.commit()
        cur = con.execute(
            f'SELECT {PLOT_COLS} FROM plot WHERE id = ?', (cur.lastrowid,)
        )
        cols = [desc[0] for desc in cur.description]
        return dict(zip(cols, cur.fetchone()))


def get_recent_plots(n: int = 20) -> list[dict]:
    """return the n most recent plots ordered newest first.

    Parameters
    ----------
    n : int, optional
        number of plots to return, by default 20

    Returns
    -------
    list[dict]
        list of plot rows with keys id, mime, created_at, cell_id, data;
        data is None for non-plotly rows
    """
    with sqlite3.connect(app.config['db_file']) as con:
        cur = con.execute(
            f'SELECT {PLOT_COLS} FROM plot ORDER BY created_at DESC LIMIT ?', (n,)
        )
        cols = [desc[0] for desc in cur.description]
        return [dict(zip(cols, row)) for row in cur.fetchall()]


def get_plot(plot_id: int) -> dict | None:
    """return a single plot by id, or None if not found.

    Parameters
    ----------
    plot_id : int
        primary key of the plot to fetch

    Returns
    -------
    dict or None
        plot row with keys id, mime, data, created_at, cell_id, or None if no
        row has that id; data is the stored value as-is: the figure JSON str
        for plotly rows, bytes for images
    """
    with sqlite3.connect(app.config['db_file']) as con:
        cur = con.execute(
            'SELECT id, mime, data, created_at, cell_id FROM plot WHERE id = ?',
            (plot_id,),
        )
        row = cur.fetchone()
        if row is None:
            return None
        cols = [desc[0] for desc in cur.description]
        return dict(zip(cols, row))


def start_plot_server(
    port: int = 5000, limit: int = 6000, db_path: str | None = None
) -> str|None:
    """Start the Flask server in a background daemon thread.

    Parameters
    ----------
    port : int
        Port to listen on. Defaults to 5000.
    limit : int
        Port to stop searching at. Defaults to 6000.
    db_path : str, optional
        Path of the plot database. Defaults to default_db_path().
    """
    app.config['db_file'] = db_path or default_db_path()
    init_db()

    starting_port = port
    host = '127.0.0.1'
    sock = None

    while port < limit:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

        try:
            s.bind((host, port))
            s.listen(1)
            sock = s
            break
        except OSError:
            logging.warning(f'Port {port} in use, incrementing by 1...')
            s.close()
            port += 1

    if sock is None:
        logging.error(f'No available port found in range {starting_port}-{limit-1}')
        return

    server = make_server(
        host, port, app,
        fd=sock.fileno(),
        request_handler=QuietHandler,
        threaded=True
    )
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    url = f'http://{host}:{port}'

    logging.info(f'Plot server started at {url}')

    return url


class SSEBroker:
    """in-process pub/sub broker for server-sent events."""

    def __init__(self) -> None:
        self.clients: list[queue.Queue] = []
        self.lock = threading.Lock()

    def subscribe(self) -> queue.Queue:
        """register a new subscriber and return its queue."""
        q: queue.Queue = queue.Queue()
        with self.lock:
            self.clients.append(q)
        return q

    def unsubscribe(self, q: queue.Queue) -> None:
        """remove a subscriber queue."""
        with self.lock:
            self.clients.remove(q)

    def publish(self, event_type: str, data: dict) -> None:
        """broadcast an event to all subscribers."""
        with self.lock:
            for q in self.clients:
                q.put((event_type, data))


broker = SSEBroker()


def push_image(img_data: str, mime: str, message: dict) -> None:
    """Store image data and push it to all connected SSE clients.

    Parameters
    ----------
    img_data : str
        The image data; base64-encoded for raster formats, raw XML for
        image/svg+xml, the figure JSON for the plotly mime type.
    mime : str
        The MIME type of the image, e.g. 'image/png', 'image/svg+xml'.
    message : dict
        The originating Lua message for the cell execution that produced the image.
    """

    logging.info('pushing image to plot server: %s', message)

    try:
        if mime == PLOTLY_MIME:
            data = img_data
        elif mime == 'image/svg+xml':
            data = img_data.encode('utf-8')
        else:
            data = base64.b64decode(img_data)

        plot = create_plot(data, mime, message.get('cell_id', ''))
        broker.publish('new-plot', plot)
    except Exception:
        logging.exception('failed to store plot')


@app.route('/')
def index():
    plots = get_recent_plots()
    return render_template('index.html', plots=plots)


@app.get('/plot/<int:plot_id>/')
def plot(plot_id: int) -> str:
    """render the detail partial for a single plot."""
    p = get_plot(plot_id)
    if p is None:
        abort(404)
    return render_template('partials/plot.html', plot=p)


@app.get('/plot/<int:plot_id>/image')
def plot_image(plot_id: int) -> Response:
    """serve the stored bytes of an image plot."""
    p = get_plot(plot_id)
    if p is None or not p['mime'].startswith('image/'):
        abort(404)
    return Response(
        p['data'],
        mimetype=p['mime'],
        headers={
            'Cache-Control': 'public, max-age=31536000, immutable',
            'X-Content-Type-Options': 'nosniff',
            'Content-Security-Policy': 'sandbox',
        },
    )


@app.get('/events/')
def sse_stream() -> Response:
    """SSE endpoint that streams rendered plot list items to connected clients."""

    @stream_with_context
    def event_generator() -> Generator[str, None, None]:
        q = broker.subscribe()
        yield ': connected\n\n'
        try:
            while True:
                try:
                    event_type, plot = q.get(timeout=1)
                except queue.Empty:
                    continue
                html = render_template('partials/plot_list_item.html', plot=plot)
                data_lines = '\n'.join(f'data: {line}' for line in html.splitlines())
                yield f'event: {event_type}\n{data_lines}\n\n'
        finally:
            broker.unsubscribe(q)

    return Response(
        event_generator(),
        mimetype='text/event-stream',
        headers={'Cache-Control': 'no-cache', 'X-Accel-Buffering': 'no'},
    )


if __name__ == '__main__':
    app.run(debug=True, threaded=True)
