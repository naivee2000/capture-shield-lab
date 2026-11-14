#!/usr/bin/env python3
"""Reject a successful tool exit when Swift Testing did not finish its runs."""
from pathlib import Path
import re
import sys


def completed(text):
    text = re.sub(r"\x1b\[[0-9;]*m", "", text)
    started = len(re.findall(r"^◇ Test run started\.$", text, re.MULTILINE))
    counts = re.findall(r"^✔ Test run with (\d+) tests?(?: in \d+ suites?)? passed after .+$", text, re.MULTILINE)
    return started > 0 and len(counts) == started and all(int(count) > 0 for count in counts)


if __name__ == "__main__":
    if len(sys.argv) != 2 or not completed(Path(sys.argv[1]).read_text(errors="replace")):
        sys.exit("Native tests did not report complete, nonzero successful runs. Exit code 0 alone is insufficient.")
