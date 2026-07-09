import logging
import nbformat
import zmq

from jupyter_client.manager import KernelManager as KM


class Kernel:
    def __init__(self, metadata: dict) -> None:
        self.metadata = metadata
        self.vim_pid = metadata["pid"]
        self.file = metadata["file"]
        self.execution_count = 0
        self.status = "idle"
        self._info = None

        self.mgr = KM()
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
        if self._info is None:
            mid = self.client.kernel_info()
            msg = self._retrieve_messages(mid)
            self._info = msg['data']['content']
            self._info['runtime'] = {
                'connection_file': self.mgr.connection_file,
                'kernel_id': self.mgr.kernel_id,
                'kernel_pid': self.mgr.provisioner.pid,
            }

        return self._info

    @property
    def banner(self) -> str:
        sep = "=" * 80
        file = f"Kernel: {self.file} ({self.vim_pid})"
        exc = f"Execution Count: {self.execution_count + 1}"
        banner = self.info['banner']
        output = [ "", sep, file, exc, banner + sep ]
        return "\n".join(output)

    def _on_control(self, msg: dict, output: dict) -> None:
        # logging.info(f"Control msg: {msg}")
        logging.warning(f"Unhandled CNTRL message type: {msg['header']['msg_type']}")

    def _on_iopub(self, msg: dict, output: dict) -> None:

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

            case 'execute_result' | 'stream' | 'display_data' | 'error':
                fmt_output = nbformat.v4.output_from_msg(msg)
                logging.info(f"output message: {fmt_output}")
                output['outputs'].append(fmt_output)

            case _:
                logging.warning(f"Unhandled IOPUB message type: {msg['header']['msg_type']}")
                # logging.info(f"IOPub msg: {msg}")

    def _on_shell(self, msg: dict, output: dict) -> None:
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
        # logging.info(f"Stdin msg: {msg}")
        logging.warning(f"Unhandled STDIN message type: {msg['header']['msg_type']}")

    def _retrieve_messages(self, exe_id: str|None = None) -> dict:
        """ """
        output = {
            "outputs": [],
            "status": 'ok',
            "data": {},
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

        # no `input()` allowed
        kwargs.setdefault('allow_stdin', False)

        msg_id = self.client.execute(*args, **kwargs)
        return self._retrieve_messages(msg_id)

    def shutdown(self) -> None:
        """Shut down the kernel and stop all communication channels."""
        if self.status == "down":
            return

        logging.info(f"Shutting down kernel {self.file} ({self.vim_pid})")

        self.status = "down"
        self.client.stop_channels()
        self.mgr.shutdown_kernel()
