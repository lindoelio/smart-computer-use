#!/usr/bin/env bash
# Prove that the drift alarm works.
#
# A linter nobody has seen fail is a linter nobody can trust. This test copies
# the skill into a sandbox, injects each kind of drift the linter is supposed
# to catch, and asserts that the linter fails on every one of them.
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd -- "${SCRIPT_DIR}/../../.." && pwd -P)
LINT="${SCRIPT_DIR}/lint-skill.py"

PASS=0
FAIL=0

pass() {
  PASS=$((PASS + 1))
  printf 'ok   %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL %s\n' "$1"
  if [[ -n "${2:-}" ]]; then
    printf '     %s\n' "$2"
  fi
}

# Copy the skill into a sandbox and run the linter there. The linter exits
# non-zero when it finds a problem, and `pipefail` would leak that into a
# pipeline, so the output is captured first and matched afterwards.
# $1: the sandbox root
lint_sandbox() {
  python3 "${LINT}" --root "$1" 2>&1 || true
}

# $1: sandbox name
new_sandbox() {
  local root
  root=$(mktemp -d "${TMPDIR:-/tmp}/lint-test.XXXXXX")
  cp -R "${REPO_ROOT}/skills" "${root}/skills"
  cp -R "${REPO_ROOT}/.github" "${root}/.github" 2>/dev/null || true
  printf '%s\n' "${root}"
}

# 1. A clean copy must pass.
ROOT=$(new_sandbox)
OUTPUT=$(lint_sandbox "${ROOT}")
if grep -qF "ok: the skill matches" <<<"${OUTPUT}"; then
  pass "a clean copy passes the linter"
else
  fail "a clean copy passes the linter" "$(head -3 <<<"${OUTPUT}")"
fi
rm -rf "${ROOT}"

# 2. A command that does not exist must fail.
ROOT=$(new_sandbox)
python3 - "${ROOT}" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1]) / "skills/smart-computer-use/SKILL.md"
text = path.read_text(encoding="utf-8")
path.write_text(
    text.replace(
        "computer-use list-apps",
        "computer-use list-applications",
        1,
    ),
    encoding="utf-8",
)
PY
OUTPUT=$(lint_sandbox "${ROOT}")
if grep -qF "not a command of the pinned binary" <<<"${OUTPUT}"; then
  pass "a command that does not exist is caught"
else
  fail "a command that does not exist is caught" "$(head -3 <<<"${OUTPUT}")"
fi
rm -rf "${ROOT}"

# 3. A mutating example without a session must fail.
ROOT=$(new_sandbox)
python3 - "${ROOT}" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1]) / "skills/smart-computer-use/SKILL.md"
text = path.read_text(encoding="utf-8")
path.write_text(
    re.sub(r"press --session notes", "press", text, count=1),
    encoding="utf-8",
)
PY
OUTPUT=$(lint_sandbox "${ROOT}")
if grep -qF "no --session" <<<"${OUTPUT}"; then
  pass "a mutating example without --session is caught"
else
  fail "a mutating example without --session is caught" "$(head -3 <<<"${OUTPUT}")"
fi
rm -rf "${ROOT}"

# 4. A version that drifted must fail.
ROOT=$(new_sandbox)
python3 - "${ROOT}" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1]) / "skills/smart-computer-use/SKILL.md"
text = path.read_text(encoding="utf-8")
path.write_text(text.replace('version: "0.3.1"', 'version: "0.2.0"', 1), encoding="utf-8")
PY
OUTPUT=$(lint_sandbox "${ROOT}")
if grep -qF "targets 0.2.0" <<<"${OUTPUT}"; then
  pass "a version that drifted is caught"
else
  fail "a version that drifted is caught" "$(head -3 <<<"${OUTPUT}")"
fi
rm -rf "${ROOT}"

# 5. A command the binary has but the reference forgot must fail.
ROOT=$(new_sandbox)
python3 - "${ROOT}" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1]) / "skills/smart-computer-use/references/cli-reference.md"
text = path.read_text(encoding="utf-8")
path.write_text(
    text.replace("| `batch` | loop |", "| `batch-removed` | loop |", 1),
    encoding="utf-8",
)
PY
OUTPUT=$(lint_sandbox "${ROOT}")
if grep -qF "batch" <<<"${OUTPUT}"; then
  pass "a command the reference forgot is caught"
else
  fail "a command the reference forgot is caught" "$(head -3 <<<"${OUTPUT}")"
fi
rm -rf "${ROOT}"

# 6. A skill that grew past the word ceiling must fail.
ROOT=$(new_sandbox)
python3 - "${ROOT}" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1]) / "skills/smart-computer-use/SKILL.md"
text = path.read_text(encoding="utf-8")
path.write_text(text + ("\n" + "filler word " * 300 + "\n"), encoding="utf-8")
PY
OUTPUT=$(lint_sandbox "${ROOT}")
if grep -qF "ceiling" <<<"${OUTPUT}"; then
  pass "a skill past the word ceiling is caught"
else
  fail "a skill past the word ceiling is caught" "$(head -3 <<<"${OUTPUT}")"
fi
rm -rf "${ROOT}"

# 7. A missing sensitive action must fail.
ROOT=$(new_sandbox)
python3 - "${ROOT}" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1]) / "skills/smart-computer-use/SKILL.md"
text = path.read_text(encoding="utf-8")
path.write_text(text.replace("`cmd+q`", "`cmd+shift+q`", 1), encoding="utf-8")
PY
OUTPUT=$(lint_sandbox "${ROOT}")
if grep -qF "cmd+q" <<<"${OUTPUT}"; then
  pass "a missing sensitive action is caught"
else
  fail "a missing sensitive action is caught" "$(head -3 <<<"${OUTPUT}")"
fi
rm -rf "${ROOT}"

printf '\n%s passed, %s failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
