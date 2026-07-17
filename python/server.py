import queue
import threading
from flask import Flask, Response, render_template, stream_with_context

app = Flask(__name__)

_image_queue: queue.Queue = queue.Queue()


def push_image(img_b64: str) -> None:
    """Push a base64-encoded PNG string to all connected SSE clients.

    Parameters
    ----------
    img_b64 : str
        The raw base64 string from msg['data']['image/png'].
    """

    _image_queue.put(img_b64)


def start_server(port: int = 5000) -> None:
    """Start the Flask server in a background daemon thread.

    Parameters
    ----------
    port : int
        Port to listen on. Defaults to 5000.
    """
    thread = threading.Thread(
        target=lambda: app.run(port=port, threaded=True),
        daemon=True,
    )
    thread.start()


@app.route('/')
def index():
    return render_template('index.html')


@app.route('/stream')
def stream():
    def generate():
        while True:
            img_b64 = _image_queue.get()
            yield f'data: {img_b64}\n\n'

    return Response(stream_with_context(generate()), mimetype='text/event-stream')


if __name__ == '__main__':
    app.run(debug=True, threaded=True)
