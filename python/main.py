import argparse
import json
import logging
import sys
import traceback

from datetime import datetime
from typing import Callable

from kernel import KernelManager
from notebook import create_new_notebook, read_notebook, write_notebook


class StreamIO:
    """Handles message I/O over stdin/stdout/stderr"""

    def __init__(self) -> None:
        self.hooks = set()

    def add_hook(self, func: Callable) -> None:
        """Add a hook function to be called when a read happens"""
        self.hooks.add(func)

    def read(self) -> None:
        """Read messages from stdin and dispatch to handlers."""
        logging.info("StreamIO: Reading stdin...")
        while True:
            # read requests from lua
            req = json.loads(sys.stdin.readline())
            if req is None:
                continue

            elif req["type"] == "ping":
                logging.info('ping, pong')
                self.write({"type": "pong"})

            elif req["type"] == "shutdown" and req["target"] == "all":
                logging.info("Shutdown received from nvim")
                break

            for func in self.hooks:
                func(req)

    def write(self, message: dict) -> None:
        """Write a message to stdout as a JSON string.

        Parameters
        ----------
        message : dict
            The message dictionary to serialize and write. If the message contains
            an 'outputs' key, datetime objects within it are converted to ISO format
            strings before serialization.
        """

        if "outputs" in message:

            def recurse(inp: dict) -> dict:
                """Recursive function to handle unserializable datetimes"""
                for key, val in inp.items():
                    if key == "date":
                        if isinstance(val, str):
                            inp[key] = datetime.fromisoformat(val)
                        else:
                            inp[key] = val.isoformat()
                    elif isinstance(val, dict):
                        inp[key] = recurse(val)
                return inp

            message["outputs"] = [recurse(msg) for msg in message["outputs"]]

        sys.stdout.write(json.dumps(message) + "\n\n")
        sys.stdout.flush()


def start_server(args):
    """Start the kernel manager and plot viewing server"""

    stream = StreamIO()

    server = None
    try:
        from server.run import start_plot_server
        server = start_plot_server()
    except Exception as e:
        logging.error(f'Plot server failed to start:\n{traceback.format_exc()}')

    # start kernel manager
    km = KernelManager(stream, {'pid': args.pid, 'server': server})
    try:
        stream.read()
    except Exception:
        logging.error(traceback.format_exc())
    finally:
        km.shutdown_all()


def create_parser(parser_data: dict):
    """Create and return a parser"""

    parser = argparse.ArgumentParser()
    parser.add_argument("pid")
    parser.add_argument("log_loc")
    subparsers = parser.add_subparsers(dest="command", required=True)

    for name, data in parser_data.items():
        p = subparsers.add_parser(name)
        p.set_defaults(func=data["func"])
        for arg in data.get("args", []):
            p.add_argument(arg)

    return parser


def main():

    # parser configuration
    data = {

        "start": {"func": start_server},

        "read": {
            "func": read_notebook,
            "args": ["file"]
        },

        "create": {
            "func": create_new_notebook,
            "args": ["file"]
        },

        "write": {
            "func": write_notebook,
            "args": ["json", "file"]
        }

    }

    # set up parsers
    parser = create_parser(data)
    args = parser.parse_args()

    # set up logging
    if args.log_loc:
        logfile = f"{args.log_loc}/foundry-nvim-py.log"
        logging.basicConfig(
            filename=logfile,
            format="%(asctime)s %(levelname)s:%(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
            encoding="utf-8",
            level=logging.INFO,
        )
        logging.getLogger('werkzeug').handlers = []
        logging.getLogger('werkzeug').propagate = True

    # handle the provided command
    args.func(args)


if __name__ == "__main__":
    main()
