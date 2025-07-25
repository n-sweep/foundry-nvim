import logging
from jupyter_client.manager import KernelManager


class Kernel:
    def __init__(self) -> None:
        self.execution_count = 0
        self._startup()

    def _startup(self) -> None:
        self.manager = KernelManager()
        self.manager.start_kernel()

        self.client = self.manager.client()
        self.client.start_channels()
        self.client.wait_for_ready()

        self.status = 'idle'

        logging.info('Kernel ready')

    def shutdown(self) -> None:
        logging.info('Shutting down...')
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
            except Exception:
                logging.info('no messages')
                return {'error': 'Error: no messages'}

            msg_type = msg['header']['msg_type']

            if msg_type in output['messages']:
                output['messages'][msg_type].append(msg)
            else:
                output['messages'][msg_type] = [msg]

            if msg_type == 'status':
                self.status = (status:=msg['content']['execution_state'])

                logging.info(f'Status: {status}')

                if status == 'idle':
                    output['execution_count'] = self.execution_count
                    return output

            elif msg_type == 'execute_input':
                content = msg['content']
                output['input'] = content
                self.execution_count = content['execution_count']
                logging.info(f"Input [{self.execution_count}]\n{content['code']}")

            elif msg_type == 'execute_result':
                content = msg['content']
                output['output'] = content
                logging.info(f"Result: {content['data']}")

            elif msg_type == 'display_data':
                # "Rich output like images, plots, etc. (e.g. from matplotlib, IPython.display)"
                logging.info(f'Rich display: {str(msg)}')

            elif msg_type == 'stream':
                logging.info(f"STDOUT: {msg['content']['text']}")

            elif msg_type == 'error':
                content = msg['content']

                output['status'] = 'error'
                output['output'] = content['traceback']

                tb = '\n'.join(content['traceback'])
                logging.error(f"{content['ename']} {content['evalue']}\n{tb}")
