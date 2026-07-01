import argparse
import json
import logging
import nbformat
import sys
import traceback

from kernel_manager import KernelManager

parser = argparse.ArgumentParser()
parser.add_argument("pid")
parser.add_argument("log_loc")
subparsers = parser.add_subparsers(dest="command", required=True)

kernel_parser = subparsers.add_parser("kernel")

nb_read_parser = subparsers.add_parser("read")
nb_read_parser.add_argument("file")

nb_write_parser = subparsers.add_parser("write")
nb_write_parser.add_argument("json")
nb_write_parser.add_argument("file")


def main():
    args = parser.parse_args()

    if args.log_loc:
        logfile = f"{args.log_loc}/foundry-nvim-py.log"
        logging.basicConfig(
            filename=logfile,
            format="%(asctime)s %(levelname)s:%(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
            encoding="utf-8",
            level=logging.INFO,
        )

    if args.command == "kernel":
        km = KernelManager(args.pid)
        try:
            km.read()
        except Exception:
            logging.error(traceback.format_exc())
        finally:
            km.shutdown_all()

    if args.command == "read":
        with open(args.file, 'r') as f:
            nb = nbformat.read(f, as_version=4)

        data = {'cells': nb.cells, 'meta': {'type': 'read'}}

        sys.stdout.write(json.dumps(data) + "\n")
        sys.stdout.flush()

    if args.command == "write":
        nb = nbformat.read(args.file, as_version=4)
        nb.cells = args.cells
        try:
            nbformat.validate(nb)
            nbformat.write(nb, args.file)
        except nbformat.validator.NotebookValidationError:
            logging.warning(f'notebook {args.file} is invalid')


if __name__ == "__main__":
    main()
