from datetime import datetime


def handle_datetimes(messages: list) -> list:
    """Recursively convert between datetime objects and iso format strings for JSON un/serialization.

    Parameters
    ----------
    messages : list
        List of message dictionaries potentially containing datetime objects

    Returns
    -------
    list
        List of message dictionaries with datetime objects converted to/from ISO format strings
    """

    def rfunc(inp: dict) -> dict:
        for key, val in inp.items():
            if key == "date":
                if isinstance(val, str):
                    inp[key] = datetime.fromisoformat(val)
                else:
                    inp[key] = val.isoformat()
            elif isinstance(val, dict):
                inp[key] = rfunc(val)
        return inp

    return [rfunc(msg) for msg in messages]
