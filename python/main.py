import sys
import json
import logging
import traceback
from datetime import datetime
from kernel import Kernel

logging.basicConfig(
    filename='./logs/python.log',
    # format="%(levelname)s:%(message)s",
    encoding='utf-8',
    level=logging.INFO
)


def recursive_convert_datetime(inp: dict) -> dict:
    """Recursively convert between datetime objects and iso format strings for JSON un/serialization"""
    for key, val in inp.items():
        if key == 'date':
            if isinstance(val, str):
                inp[key] = datetime.fromisoformat(val)
            else:
                inp[key] = val.isoformat()
        elif isinstance(val, dict):
            inp[key] = recursive_convert_datetime(val)

    return inp


def handle_datetimes(inp: dict) -> dict:
    for key, messages in inp['messages'].items():
        for msg in messages:
            inp['messages'][key] = recursive_convert_datetime(msg)

    return inp


def main():
    output = {}
    kn = Kernel()

    try:
        while True:
            # read requests from lua
            req = json.loads(sys.stdin.readline())
            if req is None:
                break

            if req['type'] == 'exec':
                code = req['code']
                result = kn.execute(code)
                result['id'] = req['id']
                output = handle_datetimes(result)

                # write the result to stdout
                sys.stdout.write(json.dumps(output) + '\n')
                sys.stdout.flush()

            elif req['type'] == 'shutdown':
                kn.shutdown()
                break

    except Exception:
        logging.info(str(output))
        logging.error(traceback.format_exc())

    finally:
        if kn.status != 'down':
            kn.shutdown()


if __name__ == "__main__":
    main()
