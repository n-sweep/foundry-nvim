import nbformat
import pytest

from nbclient import NotebookClient

from python.kernel import Kernel


@pytest.fixture(scope="function")
def kernel():
    k = Kernel({"pid": "12345", "file": "/path/to/file.py"})
    yield k
    k.shutdown()
    assert k.status == 'down'


@pytest.fixture(scope="module")
def notebook():
    nb = nbformat.v4.new_notebook()
    nb['cells'] = [
        nbformat.v4.new_code_cell("print('hello world')"),
        nbformat.v4.new_code_cell("1 + 1"),
        nbformat.v4.new_code_cell("print('hello world')\n1 + 1"),
        nbformat.v4.new_code_cell("1 + 1\nprint('hello world')")
    ]

    client = NotebookClient(nb)
    client.execute()

    return nb


def test_kernel_execution(kernel, notebook):
    for cell in notebook.cells:
        code = cell['source']
        result = kernel.execute(code)
        assert result["status"] == "ok"
        assert result["outputs"] == cell["outputs"]
