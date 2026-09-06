from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from main import StreamIO

import logging
import nbformat
import zmq

from jupyter_client.manager import KernelManager as KM


class Kernel:
    def __init__(self, metadata: dict, image_server: str|None = None) -> None:
        self.metadata = metadata
        self.vim_pid = metadata["pid"]
        self.file = metadata["file"]
        self.image_server = image_server

        self.execution_count = 0
        self.status = "idle"
        self._info = None

        self.mgr = KM()
        venv = metadata.get('venv')
        if venv:
            self.mgr.kernel_spec.argv[0] = venv
        self.mgr.start_kernel()

        self.client = self.mgr.client()
        self.client.start_channels()
        self.client.wait_for_ready()

        self.sockets = {
            self.client.control_channel.socket: {
                'func': self._on_control,
                'chan': self.client.control_channel
            },
            self.client.iopub_channel.socket: {
                'func': self._on_iopub,
                'chan': self.client.iopub_channel
            },
            self.client.shell_channel.socket: {
                'func': self._on_shell,
                'chan': self.client.shell_channel
            },
            self.client.stdin_channel.socket: {
                'func': self._on_stdin,
                'chan': self.client.stdin_channel
            },
        }

        self.poller = zmq.Poller()
        for sock in self.sockets.keys():
            self.poller.register(sock, zmq.POLLIN)

        logging.info(self.banner)
        logging.info("Kernel Ready")

    @property
    def info(self) -> dict:
        """Return ipython info"""
        if self._info is None:
            mid = self.client.kernel_info()
            msg = self._retrieve_messages(mid, {})
            self._info = msg['data']['content']
            self._info['runtime'] = {
                'connection_file': self.mgr.connection_file,
                'kernel_id': self.mgr.kernel_id,
                'kernel_pid': self.mgr.provisioner.pid,
            }
            self._info['image_server'] = self.image_server

        return self._info

    @property
    def banner(self) -> str:
        """Return ipython banner"""
        sep = "=" * 80
        file = f"Kernel: {self.file} ({self.vim_pid})"
        exc = f"Execution Count: {self.execution_count + 1}"
        banner = self.info['banner']
        output = [ "", sep, file, exc, banner + sep ]
        return "\n".join(output)

    def _on_control(self, msg: dict, output: dict) -> None:
        """Handle control messages"""
        # logging.info(f"Control msg: {msg}")
        logging.warning(f"Unhandled CNTRL message type: {msg['header']['msg_type']}")

    def _on_iopub(self, msg: dict, output: dict) -> None:
        """Handle IOpub messages"""

        msg_type = msg['header']['msg_type']
        match msg_type:

            case 'status':
                self.status = msg['content']['execution_state']
                if self.status == 'idle':
                    # logging.info('kernel idle')
                    pass
                elif self.status == 'busy':
                    # logging.info('kernel busy')
                    pass
                else:
                    logging.warning(f"Unhandled iopub status: {self.status}")
                    logging.info(f"IOPub msg: {msg}")

            case 'execute_input':
                logging.info(f"input received: {repr(msg['content']['code'])}")

            case 'execute_result' | 'stream':
                fmt_output = nbformat.v4.output_from_msg(msg)
                output['outputs'].append(fmt_output)

                logging.info(f"output message: {msg_type}")

            case 'display_data':
                fmt_output = nbformat.v4.output_from_msg(msg)
                output['outputs'].append(fmt_output)

                logging.info(f"output message: {msg_type}")

                # display_data
                for mime in ('image/png', 'image/jpeg', 'image/gif', 'image/svg+xml'):
                    img = fmt_output.get('data', {}).get(mime)

                    if img is None:
                        continue

                    if self.image_server is None:
                        logging.warning(f"no image server available for {mime} data")
                        break

                    from server.run import push_image
                    push_image(img, mime, output['data']['message'])
                    break

            case 'error':
                output['status'] = 'error'
                fmt_output = nbformat.v4.output_from_msg(msg)
                output['outputs'].append(fmt_output)

                logging.error(f"{'\n'.join(fmt_output['traceback'])}")

            case _:
                logging.warning(f"Unhandled IOPUB message type: {msg['header']['msg_type']}")
                # logging.info(f"IOPub msg: {msg}")

    def _on_shell(self, msg: dict, output: dict) -> None:
        """Handle shell messages"""
        msg_type = msg['header']['msg_type']

        if msg_type.endswith('_reply'):
            self._awaiting_reply = False

        match msg_type:

            case 'execute_reply':
                c = msg['content']
                output['status'] = c['status']
                self.execution_count = c['execution_count']

            case 'kernel_info_reply':
                output['data'] = msg

            case _:
                logging.warning(f"Unhandled SHELL message type: {msg['header']['msg_type']}")
                # logging.info(f"IOPub msg: {msg}")

    def _on_stdin(self, msg: dict, output: dict) -> None:
        """Handle stdin messages"""
        # logging.info(f"Stdin msg: {msg}")
        logging.warning(f"Unhandled STDIN message type: {msg['header']['msg_type']}")

    def _retrieve_messages(self, exe_id: str, message: dict) -> dict:
        """Retreive messages from the kernel sockets"""
        output = {
            "outputs": [],
            "status": 'ok',
            "data": {
                "message": message
            },
        }

        self._awaiting_reply = True
        self.status = 'start_polling'
        while (self.status != 'idle') or self._awaiting_reply:
            socks = dict(self.poller.poll())
            for sock in socks:
                socket = self.sockets[sock]
                msg = socket['chan'].get_msg(timeout=0)
                if msg["parent_header"].get("msg_id") == exe_id:
                    socket['func'](msg, output)
                else:
                    logging.warning(f"message id mismatch: {msg}")

        output['execution_count'] = self.execution_count

        return output

    def execute(self, message: dict) -> dict:
        """Execute code in the kernel and collect all outputs.

        Parameters
        ----------
        message
            the message sent from lua to be executed

        Returns
        -------
        dict
            Execution results with status, execution_count, and messages list.
        """

        # no `input()` allowed
        # kwargs.setdefault('allow_stdin', False)

        msg_id = self.client.execute(message['code'], allow_stdin=False)
        return self._retrieve_messages(msg_id, message)

    def shutdown(self) -> None:
        """Shut down the kernel and stop all communication channels."""
        if self.status == "down":
            return

        logging.info(f"Shutting down kernel {self.file} ({self.vim_pid})")

        self.status = "down"
        self.client.stop_channels()
        self.mgr.shutdown_kernel()


class KernelManager:
    """Provides a central manager for creating, accessing, and controlling
    multiple Jupyter kernels, typically one per file.

    Parameters
    ----------
    data : dict
        Initialization data containing 'pid' (the managing process ID) and
        'server' (the plot server URL, or None if unavailable).

    Attributes
    ----------
    pid : str
        The process ID of the managing process.
    image_server : str | None
        URL of the plot server, or None if it failed to start.
    kernels : dict
        Dictionary mapping file paths to Kernel instances.
    """

    def __init__(self, io_handler: StreamIO, data: dict) -> None:
        self.pid = data['pid']
        self.image_server = data['server']
        self.kernels = {}
        self.write = io_handler.write
        io_handler.add_hook(self.handle_kernel_message)

        logging.info(f"Kernel manager {self.pid} initialized")

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
            self.kernels[fn] = Kernel(metadata, self.image_server)
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

        elif message["type"] == "interrupt":
            logging.info(f'>>>> INTERRUPT')
            kn.mgr.interrupt_kernel()

        elif message["type"] == "restart":
            self.restart_kernel(kn)

        elif message["type"] == "shutdown":
            self.shutdown_kernel(kn)

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
        self.kernels[kn.file] = Kernel(kn.metadata, self.image_server)
        logging.info(f"Kernel {kn.file} restarted")

    def shutdown_all(self) -> None:
        """Shut down all kernels and write confirmation to stdout."""
        for kn in self.kernels.values():
            kn.shutdown()
        self.kernels = {}
        self.write({"type": "shutdown_all", "status": "ok"})
        logging.info(f"Kernel manager {self.pid} shut down")
        logging.info("-" * 19)
        logging.info(" ")
