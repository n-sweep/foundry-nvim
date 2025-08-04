import re
import logging
from time import sleep
from queue import Empty
from jupyter_client.manager import KernelManager as KM

ansi_escape = re.compile(r'\x1b\[[0-9;]+m')  # ]]


def strip_ansi(text: str) -> str:
    return ansi_escape.sub('', text).strip()


def clean_traceback(tb: list) -> dict:
    text = '\n'.join(tb).replace('^@', '\n')
    output = {
        'text/plain': strip_ansi(str(text)).split('\n'),
        'text/ANSI': text.split('\n'),
    }
    return output


class Kernel:
    def __init__(self, data: dict) -> None:
        self.vim_pid = data['pid']
        self.buf = data['buffer']
        self.file = data['file']
        self.execution_count = 0
        self._startup()

    def _startup(self) -> None:
        self.manager = KM()
        self.manager.start_kernel()

        self.client = self.manager.client()
        self.client.start_channels()
        self.client.wait_for_ready()

        self.status = 'idle'

        logging.info(f'Kernel ready: {self.vim_pid}_{self.buf} ({self.file})')

    def shutdown(self) -> None:
        logging.info(f'Shutting down {self.vim_pid}_{self.buf} ({self.file})')
        self.client.stop_channels()
        self.manager.shutdown_kernel()
        self.status = 'down'

    def execute(self, *args, **kwargs) -> dict:
        self.client.execute(*args, **kwargs)
        return self._retrieve_messages()

    def _retrieve_messages(self) -> dict:
        output = {
            'status': 'ok',
            'messages': {}
        }

        while True:

            try:
                msg = self.client.get_iopub_msg(timeout=1)
            except Empty:
                sleep(0.25)
                continue

            msg_type = msg['header']['msg_type']

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
                    return output

            elif msg_type == 'execute_input':
                content = msg['content']
                output['input'] = content
                self.execution_count = content['execution_count']
                logging.info(f"Input: {content}")

            elif msg_type == 'execute_result':
                content = msg['content']
                output['output'] = content
                output['type'] = msg_type
                logging.info(f"Result: {content['data']}")

            elif msg_type == 'display_data':
                # "Rich output like images, plots, etc. (e.g. from matplotlib, IPython.display)"
                logging.info(f'Rich display: {str(msg)}')

            elif msg_type == 'stream':
                output['output'] = msg['content']['text']
                output['type'] = msg_type
                logging.info(f"STDOUT: {msg['content']['text']}")

            elif msg_type == 'error':
                content = msg['content']

                output['status'] = 'error'
                output['output'] = {
                    'ename': content['ename'],
                    'evalue': content['evalue'],
                    'traceback': clean_traceback(content['traceback']),
                }

                tb = '\n'.join(content['traceback'])
                logging.error(f"{content['ename']} {content['evalue']}\n{tb}")


class KernelManager:
    def __init__(self) -> None:
        self.kernels = {}

    def get(self, id_data: dict) -> Kernel:
        kid = f"{id_data['pid']}_{id_data['buffer']}"

        if kid not in self.kernels:
            self.kernels[kid] = Kernel(id_data)

        return self.kernels[kid]

    def shutdown_all(self) -> None:
        for kn in self.kernels.values():
            if kn.status != 'down':
                kn.shutdown()
