import argparse
import json
import logging
import nbformat
import sys
import traceback

from pathlib import Path
from nbformat.notebooknode import NotebookNode
from kernel.kernel_manager import KernelManager
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


def read_notebook(args):
    """Read a provided ipynb file"""
    nb = nbformat.read(args.file, as_version=4)
    data = {'cells': nb.cells, 'meta': {'type': 'read'}}
    sys.stdout.write(json.dumps(data) + "\n")
    sys.stdout.flush()


def write_notebook(args):
    """Write the provided notebook data to the provided file"""
    status = 'ok'
    try:
        if Path(args.file).exists():
            nb = nbformat.read(args.file, as_version=4)
        else:
            nb = nbformat.v4.new_notebook()

        nb.cells = json.loads(args.json, object_hook=NotebookNode)
        nbformat.validate(nb)
        nbformat.write(nb, args.file)

    except nbformat.validator.NotebookValidationError:
        logging.error(f'notebook {args.file} is invalid')
        logging.error(traceback.format_exc())
        status = 'error'

    except Exception:
        logging.error(f'write failed:\n' + traceback.format_exc())
        status = 'error'

    finally:
        sys.stdout.flush()
        sys.stdout.write(json.dumps({'status': status}) + "\n")


def create_new_notebook(_):
    """Create a new empty notebook"""
    data = {'cells': [nbformat.v4.new_code_cell("")], 'meta': {'type': 'create'}}
    sys.stdout.write(json.dumps(data) + "\n")
    sys.stdout.flush()


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
