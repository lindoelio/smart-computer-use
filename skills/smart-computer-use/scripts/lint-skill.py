#!/usr/bin/env python3
"""Check the skill against the CLI it drives.

The checks are the ones an agent would otherwise discover the hard way: a
command that does not exist, a flag the reference forgot, an example that
reads the wrong field, a version that drifted.

    scripts/lint-skill.py --root . --surface references/cli-surface.json
    scripts/lint-skill.py --root . --binary /path/to/computer-use

Every check prints the problems it found and exits non-zero when there is
at least one.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

# Commands that the loop needs but that a name-only scan cannot see, because
# they appear in a sentence rather than in a command position.
COMMAND_LIKE = re.compile(r"(?:^|[`\s])computer-use\s+([a-z][a-z0-9-]*)")

# The action names the protocol accepts that look like other things.
NOT_A_COMMAND = {
    "action",
    "actions",
    "app",
    "adapter",
    "await",
    "browser",
    "build",
    "doctor",
    "element",
    "exec",
    "help",
    "json",
    "note",
    "one",
    "or",
    "policy",
    "serve",
    "the",
    "tree",
    "use",
    "with",
    "and",
    "not",
    "per",
    "the",
    "then",
    "this",
    "that",
    "when",
    "which",
    "while",
    "will",
    "with",
}

# The error codes the CLI can emit. The crate's own CI proves the list is
# real; this linter proves the skill documents every one of them.
ERROR_CODES = [
    "app_not_found",
    "blocked_url",
    "cdp_unavailable",
    "confirm_denied",
    "confirm_required",
    "display_unavailable",
    "element_not_found",
    "execution_failed",
    "invalid_arguments",
    "io_error",
    "paused",
    "permission_required",
    "policy_denied",
    "stale_element",
    "unsupported",
    "window_not_found",
]

# Actions that need the confirm hook.
SENSITIVE = ["quit", "clipboard set", "cmd+q", "alt+F4"]

# The always-loaded context has a word ceiling.
SKILL_WORD_CEILING = 2400


class Report:
    def __init__(self) -> None:
        self.problems: list[str] = []
        self.notes: list[str] = []

    def fail(self, message: str) -> None:
        self.problems.append(message)

    def note(self, message: str) -> None:
        self.notes.append(message)

    def ok(self) -> bool:
        return not self.problems


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def skill_files(root: Path) -> list[Path]:
    skill = root / "skills" / "smart-computer-use"
    files = [skill / "SKILL.md"]
    files += sorted((skill / "references").glob("*.md"))
    files += sorted((skill / "assets").glob("*.md"))
    return [path for path in files if path.is_file()]


def check_surface(root: Path, binary: str | None, golden_path: Path, report: Report) -> None:
    golden = json.loads(read(golden_path))
    if binary:
        result = subprocess.run(
            [
                sys.executable,
                str(root / "skills" / "smart-computer-use" / "scripts" / "gen-cli-surface.py"),
                binary,
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            report.fail(f"the surface generator failed: {result.stderr.strip()}")
            return
        actual = json.loads(result.stdout)
    else:
        actual = golden
        report.note("no binary given: the surface was not compared with a build")

    for key in ("cli_version", "commands", "global_flags", "json_actions"):
        if actual.get(key) != golden.get(key):
            report.fail(
                f"the CLI surface changed: {key}\n"
                f"  golden: {golden.get(key)}\n"
                f"  binary: {actual.get(key)}\n"
                f"  regenerate with: scripts/gen-cli-surface.py <binary> --output references/cli-surface.json"
            )


def check_docs(root: Path, golden_path: Path, report: Report) -> None:
    skill = root / "skills" / "smart-computer-use"
    reference = read(skill / "references" / "cli-reference.md")
    skill_md = read(skill / "SKILL.md")
    golden = json.loads(read(golden_path))

    # Every command and flag the binary accepts is documented.
    for command in golden["commands"]:
        if command == "help":
            continue
        if f"`{command}" not in reference:
            report.fail(f"the command `{command}` is not in references/cli-reference.md")
    for flag in golden["global_flags"]:
        if flag not in reference:
            report.fail(f"the flag `{flag}` is not in references/cli-reference.md")

    # Every JSON action the protocol accepts is documented.
    for action in golden["json_actions"]:
        if f"`{action}`" not in reference and f'"{action}"' not in reference:
            report.fail(f"the JSON action `{action}` is not in references/cli-reference.md")

    # Every error code is documented.
    for code in ERROR_CODES:
        if code not in reference:
            report.fail(f"the error code `{code}` is not in references/cli-reference.md")

    # Every command is classified as taught or deliberately out of the loop.
    coverage = reference.split("## Command coverage", 1)
    coverage_rows = coverage[1].split("## ", 1)[0] if len(coverage) > 1 else ""
    for command in golden["commands"]:
        if command == "help":
            continue
        if f"| `{command}` |" not in coverage_rows:
            report.fail(
                f"the command `{command}` has no row in the command coverage table"
            )

    # No command that does not exist is mentioned in the skill.
    known = set(golden["commands"])
    for path in skill_files(root):
        for match in COMMAND_LIKE.finditer(read(path)):
            name = match.group(1)
            if name in NOT_A_COMMAND or name in known:
                continue
            report.fail(
                f"{path.relative_to(root)} mentions `computer-use {name}`, "
                "which is not a command of the pinned binary"
            )

    # The sensitive surface is complete.
    for item in SENSITIVE:
        if item not in skill_md:
            report.fail(f"SKILL.md does not mention the sensitive action `{item}`")


def check_loop(root: Path, report: Report) -> None:
    skill = root / "skills" / "smart-computer-use"
    skill_md = read(skill / "SKILL.md")

    # The always-loaded context has a ceiling.
    words = len(skill_md.split())
    if words > SKILL_WORD_CEILING:
        report.fail(
            f"SKILL.md is {words} words; the ceiling is {SKILL_WORD_CEILING}. "
            "The always-loaded context grew too large."
        )

    # Mutating examples carry a session, or the baseline dies between calls.
    mutating = re.compile(
        r"computer-use\s+(press|set-value|select-text|perform-action|focus|"
        r"click|type|key|hold-key|drag|mouse-down|mouse-up|scroll-to|zoom|"
        r"move|scroll|launch|activate|quit)\b[^\n`]*"
    )
    for path in skill_files(root):
        for line in read(path).splitlines():
            if line.lstrip().startswith(">") or "NOT-A-COMMAND" in line:
                continue
            for match in mutating.finditer(line):
                command = match.group(0)
                if "--session" not in command:
                    report.fail(
                        f"{path.relative_to(root)}: a mutating example has no "
                        f"--session: {command.strip()}"
                    )

    # The loop reads the delta, never the full tree. A line that names
    # `state.tree` in order to warn against it is fine.
    negated = ("not ", "never", "ignore", "omit", "instead", "without")
    reads = re.compile(r"read[^\n]*state\.tree", re.IGNORECASE)
    for path in skill_files(root):
        for line in read(path).splitlines():
            if not reads.search(line):
                continue
            if any(word in line.lower() for word in negated):
                continue
            report.fail(
                f"{path.relative_to(root)}: the skill tells the agent to "
                f"read state.tree: {line.strip()}"
            )


def check_freshness(root: Path, golden_path: Path, report: Report) -> None:
    skill = root / "skills" / "smart-computer-use"
    skill_md = read(skill / "SKILL.md")
    golden = json.loads(read(golden_path))
    match = re.search(r'version:\s*"([^"]+)"', skill_md)
    if not match:
        report.fail("SKILL.md has no metadata.version")
        return
    if match.group(1) != golden["cli_version"]:
        report.fail(
            f"SKILL.md targets {match.group(1)} but the pinned CLI is "
            f"{golden['cli_version']}"
        )
    for path in (root / "skills" / "smart-computer-use" / "references").glob("*.md"):
        text = read(path)
        for stale in re.findall(r"targets \*\*(\d+\.\d+\.\d+)\*\*", text):
            if stale != golden["cli_version"]:
                report.fail(
                    f"{path.relative_to(root)} targets {stale} but the pinned CLI "
                    f"is {golden['cli_version']}"
                )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".", help="the skill repository root")
    parser.add_argument(
        "--surface",
        default="references/cli-surface.json",
        help="the golden surface file, relative to the skill directory",
    )
    parser.add_argument(
        "--binary",
        help="a computer-use binary to compare the golden surface against",
    )
    parser.add_argument(
        "--check",
        action="append",
        choices=["surface", "docs", "loop", "freshness"],
        help="run only this check (default: all)",
    )
    args = parser.parse_args()

    root = Path(args.root).resolve()
    skill = root / "skills" / "smart-computer-use"
    golden_path = skill / args.surface
    if not golden_path.is_file():
        print(f"missing golden surface file: {golden_path}", file=sys.stderr)
        return 2

    wanted = args.check or ["surface", "docs", "loop", "freshness"]
    report = Report()
    if "surface" in wanted:
        check_surface(root, args.binary, golden_path, report)
    if "docs" in wanted:
        check_docs(root, golden_path, report)
    if "loop" in wanted:
        check_loop(root, report)
    if "freshness" in wanted:
        check_freshness(root, golden_path, report)

    for note in report.notes:
        print(f"note: {note}")
    for problem in report.problems:
        print(f"problem: {problem}")
    if report.ok():
        print("ok: the skill matches the pinned CLI")
        return 0
    print(f"\n{len(report.problems)} problem(s)", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
