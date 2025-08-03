import sys
import json
import logging
import traceback
from datetime import datetime
from kernel import KernelManager

if len(sys.argv) > 1:
    logfile = f"{sys.argv[1]}/foundry-nvim-py.log"
else:
    logfile = './logs/foundry-nvim-py.log'

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


def write_to_lua(message: dict) -> None:
    """write a dictionary to stdout as json"""

    # datetime objects are not json serializable
    if 'messages' in message:
        message['messages'] = handle_datetimes(message['messages'])

    sys.stdout.write(json.dumps(message) + '\n')
    sys.stdout.flush()


def main():
    output = {}
    kernel_mgr = KernelManager()

    logging.info('Kernel manager initialized')

    try:
        while True:
            # read requests from lua
            req = json.loads(sys.stdin.readline())
            if req is None:
                logging.error('Something is wrong! `req` is None')
                break

            kn = kernel_mgr.get(req['id'])

            if req['type'] == 'exec':

                output = {
                    'cell_id': req['cell_id'],
                    **kn.execute(req['code'])
                }

                write_to_lua(output)

            elif req['type'] == 'shutdown':
                logging.info('Shutdown received from nvim')

                kn.shutdown()

            elif req['type'] == 'shutdown_all':
                break

    except Exception:
        logging.error(traceback.format_exc())

    finally:
        kernel_mgr.shutdown_all()


if __name__ == "__main__":
    main()
