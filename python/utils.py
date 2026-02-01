import re
from datetime import datetime

ansi_escape = re.compile(
    r"\x1b\[[0-9;]+m"  # ]] neovim treats the unclosed brackets strangely
)


def strip_ansi(text: str) -> str:
    """Remove ANSI escape sequences from text.

    Parameters
    ----------
    text : str
        The text containing ANSI escape codes

    Returns
    -------
    str
        The text with ANSI codes removed and whitespace stripped
    """
    return ansi_escape.sub("", text).strip()


def clean_traceback(tb: list) -> dict:
    text = "\n".join(tb).replace("^@", "\n")
    output = {
        "text/plain": strip_ansi(str(text)).split("\n"),
        "text/ANSI": text.split("\n"),
    }
    return output


def handle_datetimes(inp: dict) -> dict:
    """Recursively convert between datetime objects and iso format strings for JSON un/serialization.

    Parameters
    ----------
    inp : dict
        Dictionary potentially containing datetime objects

    Returns
    -------
    dict
        Dictionary with datetime objects converted to/from ISO format strings
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

    for key, messages in inp.items():
        for msg in messages:
            inp[key] = rfunc(msg)

    return inp
