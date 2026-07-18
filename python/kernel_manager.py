import json
import logging
import sys

from kernel import Kernel
from utils import handle_datetimes


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
            result = kn.execute(message)
            ok = result['status'] == 'ok'

            output = {
                "type": "execution_result" if ok else "error",
                "cell_id": message["cell_id"],
                **result
            }

            self.write(output)

        elif message["type"] == "info":
            self.write({"type": "info", **kn.info})

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
        if "outputs" in message:
            message["outputs"] = handle_datetimes(message["outputs"])

        sys.stdout.write(json.dumps(message) + "\n\n")
        sys.stdout.flush()

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
