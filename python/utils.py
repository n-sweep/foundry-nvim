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
    """Clean and format traceback for output.

    Converts traceback list to both plain text (ANSI codes removed) and
    ANSI-formatted versions, replacing control characters with newlines.

    Parameters
    ----------
    tb : list
        List of traceback strings from Jupyter error message.

    Returns
    -------
    dict
        Dictionary with 'tb_clean' and 'tb_ANSI' keys, each containing
        a list of traceback lines.
    """
    text = "\n".join(tb).replace("^@", "\n")
    output = {
        "tb_clean": strip_ansi(str(text)).split("\n"),
        "tb_ANSI": text.split("\n"),
    }
    return output


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
