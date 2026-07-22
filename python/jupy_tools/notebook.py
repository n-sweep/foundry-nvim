import json
import logging
import nbformat
import sys
import traceback

from pathlib import Path
from nbformat.notebooknode import NotebookNode


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


