import jupytext
import nbformat
import logging
import sys
import traceback
from kernel_manager import KernelManager

if len(sys.argv) > 1:
    pid = sys.argv[1]
    logfile = f"{sys.argv[2]}/foundry-nvim-py.log"

    logging.basicConfig(
        filename=logfile,
        format="%(asctime)s %(levelname)s:%(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        encoding="utf-8",
        level=logging.INFO,
    )


def main():
    km = KernelManager(pid)
    try:
        km.read()
    except Exception:
        logging.error(traceback.format_exc())
    finally:
        km.shutdown_all()


def _main():
    km = KernelManager(pid)

    # nb = jupytext.read('test.ipynb')
    # for cell in nb.cells:
    #     print(cell, '\n\n')


if __name__ == "__main__":
    main()
