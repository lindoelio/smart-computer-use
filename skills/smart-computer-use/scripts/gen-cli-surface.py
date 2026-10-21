#!/usr/bin/env python3
"""Extract the CLI surface from a `computer-use` binary.

The binary is the source of truth. This script asks it what it accepts and
prints the answer as JSON, so the skill's reference can be checked against a
real build instead of a hand-maintained copy.

    scripts/gen-cli-surface.py /path/to/computer-use

Output keys:

    cli_version   the reported version
    commands      every subcommand the binary accepts
    global_flags  every top-level flag
    json_actions  every action name the JSON protocol accepts

The JSON action list comes from the binary itself: an unknown action makes it
answer with the list of variants it expected.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from typing import Any


def run(binary: str, *args: str) -> str:
    result = subprocess.run(
        [binary, *args],
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )
    return result.stdout


def parse_version(binary: str) -> str:
    out = run(binary, "--version")
    match = re.search(r"(\d+\.\d+\.\d+)", out)
    if not match:
        raise SystemExit(f"could not read a version from {binary!r}")
    return match.group(1)


def parse_commands(help_text: str) -> list[str]:
    commands: list[str] = []
    in_commands = False
    for line in help_text.splitlines():
        if line.startswith("Commands:"):
            in_commands = True
            continue
        if in_commands:
            if not line.strip():
                break
            match = re.match(r"^\s{2}([a-z][a-z0-9-]*)\s", line)
            if match:
                commands.append(match.group(1))
    return sorted(set(commands))


def parse_global_flags(help_text: str) -> list[str]:
    flags: list[str] = []
    in_options = False
    for line in help_text.splitlines():
        if line.startswith("Options:"):
            in_options = True
            continue
        if not in_options:
            continue
        if not line.strip():
            # A blank line separates one option from the next. The section
            # ends at a line that is not indented.
            continue
        if not line[0].isspace():
            break
        match = re.match(r"^\s+(--[a-z0-9-]+)", line)
        if match:
            flags.append(match.group(1))
    return sorted(set(flags))


def parse_json_actions(binary: str) -> list[str]:
    """Ask the binary for the action names it expects."""
    out = run(binary, "exec", '{"action":"__not_a_real_action__"}')
    match = re.search(r"expected one of (.+?)(?:['\"]?$|['\"]?\s*\})", out, re.S)
    if not match:
        raise SystemExit("the binary did not report its JSON action names")
    names = re.findall(r"`([^`]+)`", match.group(1))
    if not names:
        raise SystemExit("the binary reported no JSON action names")
    return sorted(set(names))


def surface(binary: str) -> dict[str, Any]:
    help_text = run(binary, "--help")
    if not help_text:
        raise SystemExit(f"{binary!r} printed no help")
    return {
        "cli_version": parse_version(binary),
        "commands": parse_commands(help_text),
        "global_flags": parse_global_flags(help_text),
        "json_actions": parse_json_actions(binary),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", help="path to a computer-use binary")
    parser.add_argument(
        "--output",
        help="write the JSON here instead of stdout",
    )
    args = parser.parse_args()
    data = surface(args.binary)
    text = json.dumps(data, indent=2, sort_keys=True) + "\n"
    if args.output:
        with open(args.output, "w", encoding="utf-8") as handle:
            handle.write(text)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
