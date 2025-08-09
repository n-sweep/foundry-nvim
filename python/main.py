import sys
import json
import logging
import traceback
from datetime import datetime
from kernel import Kernel

pid = sys.argv[1]
logfile = f"{sys.argv[2]}/foundry-nvim-py.log"

logging.basicConfig(
    filename=logfile,
    format="%(asctime)s %(levelname)s:%(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    encoding='utf-8',
    level=logging.INFO
)


def handle_datetimes(inp: dict) -> dict:
    """Recursively convert between datetime objects and iso format strings for JSON un/serialization"""

    def rfunc(inp: dict) -> dict:
        for key, val in inp.items():
            if key == 'date':
                if isinstance(val, str):
                    inp[key] = datetime.fromisoformat(val)
                else:
                    inp[key] = val.isoformat()
            elif isinstance(val, dict):
                inp[key] = rfunc(val)
        return inp

    for key, messages in inp.items():
        for msg in messages:
            inp[key] = rfunc(msg)

    return inp


class KernelManager:
    def __init__(self, pid: str) -> None:
        self.pid = pid
        self.kernels = {}

        logging.info(f'Kernel manager {pid} initialized')

    def get(self, metadata: dict) -> Kernel:
        fn = metadata['file']
        if fn not in self.kernels:
            self.kernels[fn] = Kernel(metadata)
        return self.kernels[fn]

    def shutdown_kernel(self, kn: Kernel) -> None:
        """Shut down the provided kernel and remove it from self.kernels"""
        kn.shutdown()
        del self.kernels[kn.file]
        logging.info(f"Kernel {kn.file} shut down")

    def restart_kernel(self, kn: Kernel) -> None:
        """Restart the provided kernel"""
        kn.shutdown()
        self.kernels[kn.file] = Kernel(kn.metadata)
        logging.info(f"Kernel {kn.file} restarted")

    def shutdown_all(self) -> None:
        """Shut down all kernels and write confirmation to stdout"""
        for kn in self.kernels.values():
            kn.shutdown()
        self.kernels = {}
        self.write({'type': 'shutdown_all', 'status': 'ok'})
        logging.info(f'Kernel manager {self.pid} shut down')

    def write(self, message: dict) -> None:
        """write a dictionary to stdout as json"""

        # datetime objects are not json serializable
        if 'messages' in message:
            message['messages'] = handle_datetimes(message['messages'])

        sys.stdout.write(json.dumps(message) + '\n')
        sys.stdout.flush()

    def handle_kernel_message(self, message: dict) -> None:
        """Handle kernel-specific messages"""
        kn = self.get(message['meta'])
        output = {}

        if message['type'] == 'exec':

            output = {
                'cell_id': message['cell_id'],
                **kn.execute(message['code'])
            }

            self.write(output)

        elif message['type'] == 'restart':
            self.restart_kernel(kn)

        elif message['type'] == 'shutdown':
            self.shutdown_kernel(kn)

    def read(self) -> None:
        """Read messages from stdin"""
        while True:
            # read requests from lua
            req = json.loads(sys.stdin.readline())
            if req is None:
                continue

            elif req['type'] == 'shutdown' and req['target'] == 'all':
                logging.info('Shutdown received from nvim')
                break

            elif not req['meta'].get('file'):
                logging.warning('`file` is missing?')
                logging.warning(req)
                continue

            self.handle_kernel_message(req)


def main():
    km = KernelManager(pid)
    try:
        km.read()
    except Exception:
        logging.error(traceback.format_exc())
    finally:
        km.shutdown_all()


if __name__ == "__main__":
    main()
