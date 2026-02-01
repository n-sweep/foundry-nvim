import json
import logging
import sys

from jupyter_client.manager import KernelManager as KM
from queue import Empty
from time import sleep

from utils import clean_traceback, handle_datetimes


class Kernel:
    """Manages a single Jupyter kernel instance.

    Handles kernel lifecycle, code execution, and message collection from
    the Jupyter messaging protocol.

    Parameters
    ----------
    metadata : dict
        Kernel metadata containing 'pid' and 'file' keys.

    Attributes
    ----------
    metadata : dict
        The original metadata dictionary.
    vim_pid : str
        The Neovim process ID.
    file : str
        The file path associated with this kernel.
    execution_count : int
        Counter for code executions.
    mgr : KernelManager
        The Jupyter kernel manager instance.
    client : KernelClient
        The Jupyter kernel client for communication.
    info : dict
        Kernel info reply containing banner, language info, etc.
    status : str
        Current kernel status.
    """

    def __init__(self, metadata: dict) -> None:
        self.metadata = metadata
        self.vim_pid = metadata["pid"]
        self.file = metadata["file"]
        self.execution_count = 0
        self.status = "idle"

        self.mgr = KM()
        self.mgr.start_kernel()

        self.client = self.mgr.client()
        self.client.start_channels()
        self.client.wait_for_ready()

        logging.info("Kernel Ready")

        # Get kernel info (sends a message and gets reply from shell channel)
        _ = self.client.kernel_info()
        self.info = self.client.get_shell_msg(timeout=5)

        logging.info(self.banner)

    @property
    def banner(self) -> str:
        output = [
            "",
            f"Kernel: {self.file} ({self.vim_pid})",
            f"Execution Count: {self.execution_count}",
            "=" * 80,
            f"{self.info['content']['banner']}",
            "=" * 80,
            "",
        ]
        return "\n".join(output)

    def shutdown(self) -> None:
        """Shut down the kernel and stop all communication channels.

        If the kernel is already down, this method does nothing.
        """
        if self.status == "down":
            return

        logging.info(f"Shutting down kernel {self.file} ({self.vim_pid})")

        self.status = "down"
        self.client.stop_channels()
        self.mgr.shutdown_kernel()

    def execute(self, *args, **kwargs) -> dict:
        """Execute code in the kernel and collect all outputs.

        Parameters
        ----------
        *args
            Positional arguments passed to the kernel client's execute method.
        **kwargs
            Keyword arguments passed to the kernel client's execute method.

        Returns
        -------
        dict
            Execution results with status, execution_count, and messages list.
        """
        msg_id = self.client.execute(*args, **kwargs)
        return self._retrieve_messages(msg_id)

    def _retrieve_messages(self, msg_id: str) -> dict:
        """Retrieve and process all IOPub messages for a given execution.

        Collects messages from the IOPub channel until the kernel reports idle
        status, then retrieves the execute_reply from the shell channel for
        authoritative execution status.

        Parameters
        ----------
        msg_id : str
            The message ID of the execution request to filter messages.

        Returns
        -------
        dict
            Dictionary containing:
            - messages : list of dict
                List of output messages in nbformat style, each with an
                'output_type' field and a 'raw' field containing the
                complete Jupyter message.
            - status : str or None
                Execution status ('ok', 'error', or 'abort'), or None if
                shell reply was not received.
            - execution_count : int
                The execution counter from the kernel.
        """
        output = {"messages": [], "status": None, "execution_count": 0}

        while True:
            # collect iopub messages until idle
            try:
                msg = self.client.get_iopub_msg(timeout=1)
            except Empty:
                sleep(0.25)
                continue

            # filter by msg_id
            if msg["parent_header"].get("msg_id") != msg_id:
                continue

            msg_type = msg["header"]["msg_type"]
            content = msg["content"]
            logging.info(f"Message: {msg_type}")

            if msg_type == "status":
                # reaching idle means the process is complete and we can return the messages
                if content["execution_state"] == "idle":
                    break

            elif msg_type == "update_display_data":
                """update_display_data messages are for updating previously
                displayed output in place, such as progress bars"""
                logging.debug(f"update_display_data message content: {content}")

            elif msg_type.startswith("comm_"):
                """comm messages are for bidirectional communication between
                the kernel and frontend, ie interactive widgets like
                ipywidgets"""
                logging.debug(f"Comm message content: {content}")

            else:  # types: [clear_output, display_data, error, execute_input, execute_result, stream]
                data = {"output_type": msg_type, **content, "raw": msg}
                if msg_type == "error":
                    data["traceback"] = clean_traceback(content["traceback"])
                output["messages"].append(data)

            # also watch for stdin; just logging for now
            try:
                msg = self.client.get_stdin_msg(timeout=0.1)
                msg_type = msg["header"]["msg_type"]
                content = msg["content"]
                logging.info(f"Received stdin message: {msg_type}")
                logging.debug(f"Stdin message content: {content}")
            except Empty:
                continue

        # get the execute_reply from shell channel
        try:
            shell_reply = self.client.get_shell_msg(timeout=5)
            srid = shell_reply["parent_header"].get("msg_id")
            if srid == msg_id:
                output["status"] = shell_reply["content"]["status"]
                ec = shell_reply["content"]["execution_count"]
                output["execution_count"] = ec
                self.execution_count = ec
            else:
                logging.error(
                    f"Shell reply msg_id mismatch: expected {msg_id}, got {srid}"
                )
        except Empty:
            logging.error(f"Timeout waiting for shell reply. msg_id: {msg_id}")

        return output


class KernelManager:
    """Manages multiple kernel instances and handles message I/O.

    Provides a central manager for creating, accessing, and controlling
    multiple Jupyter kernels, typically one per file.

    Parameters
    ----------
    pid : str
        The process ID of the managing process.

    Attributes
    ----------
    pid : str
        The process ID.
    kernels : dict
        Dictionary mapping file paths to Kernel instances.
    """

    def __init__(self, pid: str) -> None:
        self.pid = pid
        self.kernels = {}

        logging.info(f"Kernel manager {pid} initialized")

    def get(self, metadata: dict) -> Kernel:
        """Get or create a kernel for the specified file.

        Parameters
        ----------
        metadata : dict
            Metadata containing 'file' key and other kernel initialization data.

        Returns
        -------
        Kernel
            The kernel instance associated with the file.
        """
        fn = metadata["file"]
        if fn not in self.kernels:
            self.kernels[fn] = Kernel(metadata)
        return self.kernels[fn]

    def shutdown_kernel(self, kn: Kernel) -> None:
        """Shut down the specified kernel and remove it from the manager.

        Parameters
        ----------
        kn : Kernel
            The kernel instance to shut down.
        """
        kn.shutdown()
        del self.kernels[kn.file]
        logging.info(f"Kernel {kn.file} shut down")

    def restart_kernel(self, kn: Kernel) -> None:
        """Restart the specified kernel.

        Shuts down the existing kernel and creates a new one with the same
        metadata.

        Parameters
        ----------
        kn : Kernel
            The kernel instance to restart.
        """
        kn.shutdown()
        self.kernels[kn.file] = Kernel(kn.metadata)
        logging.info(f"Kernel {kn.file} restarted")

    def shutdown_all(self) -> None:
        """Shut down all kernels and write confirmation to stdout."""
        for kn in self.kernels.values():
            kn.shutdown()
        self.kernels = {}
        self.write({"type": "shutdown_all", "status": "ok"})
        logging.info(f"Kernel manager {self.pid} shut down")

    def write(self, message: dict) -> None:
        """Write a dictionary to stdout as JSON.

        Handles datetime serialization for messages containing Jupyter message
        data.

        Parameters
        ----------
        message : dict
            The message dictionary to serialize and write.
        """
        # datetime objects are not json serializable
        if "messages" in message:
            message["messages"] = handle_datetimes(message["messages"])

        sys.stdout.write(json.dumps(message) + "\n")
        sys.stdout.flush()

    def handle_kernel_message(self, message: dict) -> None:
        """Handle kernel-specific messages.

        Processes execution, restart, and shutdown requests for kernels.

        Parameters
        ----------
        message : dict
            Message containing 'type', 'meta', and other request data.
        """
        kn = self.get(message["meta"])

        if message["type"] == "exec":
            output = {"cell_id": message["cell_id"], **kn.execute(message["code"])}

            self.write(output)

        elif message["type"] == "restart":
            self.restart_kernel(kn)

        elif message["type"] == "shutdown":
            self.shutdown_kernel(kn)

    def read(self) -> None:
        """Read messages from stdin and dispatch to handlers.

        Continuously reads JSON messages from stdin and processes them until
        a shutdown command is received.
        """
        while True:
            # read requests from lua
            req = json.loads(sys.stdin.readline())
            if req is None:
                continue

            elif req["type"] == "shutdown" and req["target"] == "all":
                logging.info("Shutdown received from nvim")
                break

            elif not req["meta"].get("file"):
                logging.warning("`file` is missing?")
                logging.warning(req)
                continue

            self.handle_kernel_message(req)
