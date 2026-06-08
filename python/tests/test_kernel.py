import pytest

from python.kernel import Kernel


@pytest.fixture(scope="module")
def kernel():
    """Create a single kernel for all tests in this module."""
    k = Kernel({"pid": "12345", "file": "/path/to/file.py"})
    yield k
    k.shutdown()
    assert k.status == 'down'


def test_kernel_execution(kernel):

    # calling .info() at initialization starts the execution count at 1
    assert kernel.execution_count == 0

    result = kernel.execute("print('test')")
    assert kernel.execution_count == 1
    assert result["status"] == "ok"
    assert result["text"] == "test\n"

    result = kernel.execute("1 + 1")
    assert kernel.execution_count == 2
    assert result["status"] == "ok"
    assert result["text"] == "2"

    result = kernel.execute("print('test')\n1 + 1")
    assert kernel.execution_count == 3
    assert result["status"] == "ok"
    assert result["text"] == "test\n2"

    result = kernel.execute("1 + 1\nprint('test')")
    assert kernel.execution_count == 4
    assert result["status"] == "ok"
    assert result["text"] == "test\n"
