import json
import logging
import queue
import socket
import threading

from flask import Flask, Response, render_template, stream_with_context
from werkzeug.serving import make_server, WSGIRequestHandler

app = Flask(__name__)

_subscribers: list[queue.Queue] = []
_subscribers_lock = threading.Lock()


class QuietHandler(WSGIRequestHandler):
    """WSGIRequestHandler that routes logs to Python's logging module
    instead of writing directly to stderr."""

    def log(self, type: str, message: str, *args) -> None:
        """Override werkzeug's default stderr logging."""
        getattr(logging, type)(message, *args)


def start_plot_server(port: int = 5000, limit: int = 6000) -> str|None:
    """Start the Flask server in a background daemon thread.

    Parameters
    ----------
    port : int
        Port to listen on. Defaults to 5000.
    """
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


def push_image(img_data: str, mime: str, message: dict) -> None:
    """Push image data to all connected SSE clients.

    Parameters
    ----------
    img_data : str
        The image data; base64-encoded for raster formats, raw XML for image/svg+xml.
    mime : str
        The MIME type of the image, e.g. 'image/png', 'image/svg+xml'.
    message : dict
        The originating Lua message for the cell execution that produced the image.
    """

    with _subscribers_lock:
        for q in _subscribers:
            q.put({'img': img_data, 'mime': mime, 'message': message})


@app.route('/stream')
def stream():
    """SSE endpoint that streams image data to connected clients.

    Each client connection gets its own queue. Images pushed via push_image
    are broadcast to all active queues. The queue is removed when the client
    disconnects.
    """
    q = queue.Queue()
    with _subscribers_lock:
        _subscribers.append(q)

    def generate():
        try:
            while True:
                data_str = json.dumps(q.get())
                yield f'data: {data_str}\n\n'
        finally:
            with _subscribers_lock:
                _subscribers.remove(q)

    return Response(stream_with_context(generate()), mimetype='text/event-stream')


@app.route('/')
def index():
    return render_template('index.html')


if __name__ == '__main__':
    app.run(debug=True, threaded=True)
