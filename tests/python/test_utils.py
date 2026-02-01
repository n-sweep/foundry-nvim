from datetime import datetime

import pytest

from python.utils import clean_traceback, handle_datetimes, strip_ansi


@pytest.mark.parametrize("input,expected", [
    ("\x1b[31mRed\x1b[0m", "Red"),  # ]]
    ("Plain", "Plain"),
    ("", ""),
])
def test_strip_ansi(input, expected):
    assert strip_ansi(input) == expected


def test_clean_traceback_basic():
    tb = ["Traceback (most recent call last):", "  File ...", "ValueError: bad"]
    result = clean_traceback(tb)

    assert "text/plain" in result
    assert "text/ANSI" in result
    assert isinstance(result["text/plain"], list)
    assert isinstance(result["text/ANSI"], list)


def test_clean_traceback_with_ansi():
    tb = ["\x1b[31mError\x1b[0m: something failed"]  # ]
    result = clean_traceback(tb)

    assert result["text/plain"][0] == "Error: something failed"
    assert "\x1b[31m" in result["text/ANSI"][0]


def test_clean_traceback_control_chars():
    tb = ["line1^@line2"]
    result = clean_traceback(tb)

    assert len(result["text/plain"]) == 2


def test_clean_traceback_preserves_ansi_in_ansi_output():
    """Test clean_traceback preserves ANSI codes in text/ANSI output."""
    tb = ["\x1b[1;31mError\x1b[0m: \x1b[32mdetails\x1b[0m"]  # ]]
    result = clean_traceback(tb)

    # ANSI version should preserve codes
    assert tb[0] == result["text/ANSI"][0]

    # Plain version should not have codes
    assert "\x1b[" not in result["text/plain"][0]  # ]


def test_handle_datetimes_to_iso():
    dt = datetime(2026, 2, 1, 12, 0, 0)
    messages = [{"raw": {"header": {"date": dt}}}]

    result = handle_datetimes(messages)
    assert isinstance(result[0]["raw"]["header"]["date"], str)
    assert "2026-02-01T12:00:00" in result[0]["raw"]["header"]["date"]


def test_handle_datetimes_from_iso():
    messages = [{"raw": {"header": {"date": "2026-02-01T12:00:00"}}}]

    result = handle_datetimes(messages)
    assert isinstance(result[0]["raw"]["header"]["date"], datetime)


def test_handle_datetimes_roundtrip():
    """Test handle_datetimes can convert to ISO and back."""
    original_dt = datetime(2026, 2, 1, 12, 0, 0)
    messages = [{"raw": {"header": {"date": original_dt}}}]

    # Convert to ISO
    to_iso = handle_datetimes(messages)
    assert isinstance(to_iso[0]["raw"]["header"]["date"], str)

    # Convert back to datetime
    from_iso = handle_datetimes(to_iso)
    assert isinstance(from_iso[0]["raw"]["header"]["date"], datetime)
    assert from_iso[0]["raw"]["header"]["date"] == original_dt
