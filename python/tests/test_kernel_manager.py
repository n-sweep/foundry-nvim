import io
import json
import pytest

from unittest.mock import patch

from python.kernel_manager import KernelManager


@pytest.fixture(scope="module")
def km():
    k = KernelManager('12345')
    return k

def test_read_dispatches_exec(km):
    meta = {"pid": "10001", "file": "/path/to/file.py"}

    messages = [
        {"type": "exec", "meta": meta, "code": "1+1", "cell_id": "1"},
        {"type": "shutdown", "target": "all"},
    ]
    stdin = io.StringIO("\n".join(json.dumps(m) for m in messages) + "\n")

    with patch("sys.stdin", stdin), patch.object(km, 'handle_kernel_message') as handle:
        km.read()
        handle.assert_called_once()
        assert handle.call_args[0][0]['type'] == 'exec'
