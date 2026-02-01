import pytest
from unittest.mock import MagicMock, patch
from queue import Empty

from python.kernel import Kernel


@pytest.fixture(scope="module")
def kernel():
    """Create a single kernel for all tests in this module."""
    k = Kernel({"pid": "12345", "file": "/path/to/file.py"})
    yield k
    k.shutdown()


class TestKernel:
    """Integration tests for Kernel class using a real Jupyter kernel."""

    def test_basic_execution(self, kernel):
        """Verify stream, execute_result, and error outputs work."""

        # Test stream output
        result = kernel.execute("print('test')")
        assert result["status"] == "ok"
        stream_msgs = [m for m in result["messages"] if m["output_type"] == "stream"]
        assert len(stream_msgs) == 1
        assert "test" in stream_msgs[0]["text"]

        # Test execute_result
        result = kernel.execute("42")
        assert result["status"] == "ok"
        exec_msgs = [
            m for m in result["messages"] if m["output_type"] == "execute_result"
        ]
        assert len(exec_msgs) == 1
        assert "42" in exec_msgs[0]["data"]["text/plain"]

        # Test error output
        result = kernel.execute("raise ValueError('test error')")
        assert result["status"] == "error"
        error_msgs = [m for m in result["messages"] if m["output_type"] == "error"]
        assert len(error_msgs) == 1
        assert error_msgs[0]["ename"] == "ValueError"
        assert "test error" in error_msgs[0]["evalue"]

    def test_msg_id_filtering(self, kernel):
        """Verify messages from sequential executions don't mix."""
        # Execute code that produces output
        result1 = kernel.execute("print('first')")
        result2 = kernel.execute("print('second')")

        # Verify each result only contains its own output
        stream_msgs_1 = [m for m in result1["messages"] if m["output_type"] == "stream"]
        stream_msgs_2 = [m for m in result2["messages"] if m["output_type"] == "stream"]

        assert len(stream_msgs_1) == 1
        assert "first" in stream_msgs_1[0]["text"]
        assert "second" not in stream_msgs_1[0]["text"]

        assert len(stream_msgs_2) == 1
        assert "second" in stream_msgs_2[0]["text"]
        assert "first" not in stream_msgs_2[0]["text"]

    @patch("python.kernel.KM")
    @patch("python.kernel.sleep")
    def test_empty_queue_retry(self, mock_sleep, mock_km_class):
        """Verify Empty exception causes sleep and retry."""
        mock_mgr = MagicMock()
        mock_client = MagicMock()
        mock_km_class.return_value = mock_mgr
        mock_mgr.client.return_value = mock_client

        # Simulate kernel startup (kernel_info request/reply)
        mock_client.get_shell_msg.side_effect = [
            {"content": {"banner": "test"}},  # kernel_info reply
            {
                "parent_header": {"msg_id": "msg_123"},
                "content": {"status": "ok", "execution_count": 1},
            },  # execute_reply
        ]

        # First iopub call raises Empty, second returns status message
        mock_client.get_iopub_msg.side_effect = [
            Empty(),
            {
                "parent_header": {"msg_id": "msg_123"},
                "header": {"msg_type": "status"},
                "content": {"execution_state": "idle"},
            },
        ]

        kernel = Kernel({"pid": "12345", "file": "/path/to/file.py"})
        result = kernel._retrieve_messages("msg_123")

        mock_sleep.assert_called_with(0.25)
        assert result["status"] == "ok"
        kernel.shutdown()
