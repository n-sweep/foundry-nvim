import json
import logging
import sys

from jupyter_client.manager import KernelManager as KM
from queue import Empty
from time import sleep

from utils import clean_traceback, handle_datetimes


class Kernel:
    def __init__(self, metadata: dict) -> None:
        self.metadata = metadata
        self.vim_pid = metadata["pid"]
        self.file = metadata["file"]
        self.execution_count = 0

        self.mgr = KM()
        self.mgr.start_kernel()

        self.client = self.mgr.client()
        self.client.start_channels()
        self.client.wait_for_ready()

        self.status = "idle"

        logging.info(f"Kernel ready: {self.file} ({self.vim_pid})")

    def shutdown(self) -> None:
        if self.status == "down":
            return

        logging.info(f"Shutting down kernel {self.file} ({self.vim_pid})")

        self.status = "down"
        self.client.stop_channels()
        self.mgr.shutdown_kernel()

    def execute(self, *args, **kwargs) -> dict:
        msg_id = self.client.execute(*args, **kwargs)
        return self._retrieve_messages(msg_id)

    def _retrieve_messages(self, msg_id: str) -> dict:
        output = {
            'status': 'ok',
            'messages': {},
            'text': ''
        }

        while True:

            try:
                msg = self.client.get_iopub_msg(timeout=1)
                if msg['parent_header'].get('msg_id') != msg_id:
                    continue
            except Empty:
                sleep(0.25)
                continue

            msg_type = msg['header']['msg_type']
            logging.info(f'Message: {msg_type}')

            # add message to output
            if msg_type in output['messages']:
                output['messages'][msg_type].append(msg)
            else:
                output['messages'][msg_type] = [msg]

            # status control flow
            if msg_type == 'status':
                self.status = (status:=msg['content']['execution_state'])

                logging.info(f'Status: {status}')

                # when status becomes idle again, execution is complete
                if status == 'idle':
                    output['execution_count'] = self.execution_count
                    output['type'] = output['type'] if 'type' in output else 'execute_result'
                    return output

            elif msg_type == 'execute_input':
                content = msg['content']
                output['input'] = content
                self.execution_count = content['execution_count']

            elif msg_type == 'execute_result':
                content = msg['content']
                output['result'] = content
                output['type'] = msg_type

                output['text'] = '\n'.join([ output['text'], content['data']['text/plain'] ]).strip('\n')

            elif msg_type == 'display_data':
                # "Rich output like images, plots, etc. (e.g. from matplotlib, IPython.display)"
                logging.info(f'Rich display: {str(msg)}')

            elif msg_type == 'stream':
                content = msg['content']
                output['result'] = content
                output['type'] = msg_type
                output['text'] = '\n'.join([ output['text'], content['text'] ]).strip('\n')

            elif msg_type == 'error':
                content = msg['content']

                output['status'] = 'error'
                output['result'] = {
                    'ename': content['ename'],
                    'evalue': content['evalue'],
                    'traceback': clean_traceback(content['traceback']),
                }

                tb = '\n'.join(content['traceback'])
                logging.error(f"{content['ename']} {content['evalue']}\n{tb}")


class KernelManager:
    def __init__(self, pid: str) -> None:
        self.pid = pid
        self.kernels = {}

        logging.info(f"Kernel manager {pid} initialized")

    def get(self, metadata: dict) -> Kernel:
        fn = metadata["file"]
        if fn not in self.kernels:
            self.kernels[fn] = Kernel(metadata)
        return self.kernels[fn]

    def shutdown_kernel(self, kn: Kernel) -> None:
        kn.shutdown()
        del self.kernels[kn.file]
        logging.info(f"Kernel {kn.file} shut down")

    def restart_kernel(self, kn: Kernel) -> None:
        kn.shutdown()
        self.kernels[kn.file] = Kernel(kn.metadata)
        logging.info(f"Kernel {kn.file} restarted")

    def shutdown_all(self) -> None:
        for kn in self.kernels.values():
            kn.shutdown()
        self.kernels = {}
        self.write({"type": "shutdown_all", "status": "ok"})
        logging.info(f"Kernel manager {self.pid} shut down")

    def write(self, message: dict) -> None:
        # datetime objects are not json serializable
        if "messages" in message:
            message["messages"] = handle_datetimes(message["messages"])

        sys.stdout.write(json.dumps(message) + "\n")
        sys.stdout.flush()

    def handle_kernel_message(self, message: dict) -> None:
        kn = self.get(message["meta"])
        output = {}

        if message["type"] == "exec":
            output = {"cell_id": message["cell_id"], **kn.execute(message["code"])}

            self.write(output)

        elif message["type"] == "restart":
            self.restart_kernel(kn)

        elif message["type"] == "shutdown":
            self.shutdown_kernel(kn)

    def read(self) -> None:
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
