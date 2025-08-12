import re
import logging
from time import sleep
from queue import Empty
from jupyter_client.manager import KernelManager

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
    def __init__(self, metadata: dict) -> None:
        self.metadata = metadata
        self.vim_pid = metadata['pid']
        self.file = metadata['file']
        self.execution_count = 0

        self.manager = KernelManager()
        self.manager.start_kernel()

        self.client = self.manager.client()
        self.client.start_channels()
        self.client.wait_for_ready()

        self.status = 'idle'

        logging.info(f'Kernel ready: {self.file} ({self.vim_pid})')

    def shutdown(self) -> None:
        if self.status == 'down':
            return

        logging.info(f'Shutting down kernel {self.file} ({self.vim_pid})')

        self.status = 'down'
        self.client.stop_channels()
        self.manager.shutdown_kernel()

    def execute(self, *args, **kwargs) -> dict:
        self.client.execute(*args, **kwargs)
        return self._retrieve_messages()

    def _retrieve_messages(self) -> dict:
        output = {
            'status': 'ok',
            'messages': {},
            'text': ''
        }

        while True:

            try:
                msg = self.client.get_iopub_msg(timeout=1)
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
