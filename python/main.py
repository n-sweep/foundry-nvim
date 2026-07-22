import argparse
import logging
import traceback

from jupy_tools.kernel_manager import KernelManager
from jupy_tools.notebook import create_new_notebook, read_notebook, write_notebook
from server.run import start_plot_server


def start_server(args):
    """Start the kernel manager and plot viewing server"""

    server = None
    try:
        server = start_plot_server()
    except Exception as e:
        logging.error(f'Plot server failed to start: {e}')

    # start kernel manager
    km = KernelManager({'pid': args.pid, 'server': server})
    try:
        km.read()
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
    data = {

        "kernel": {"func": start_server},

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
        },

    }

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
