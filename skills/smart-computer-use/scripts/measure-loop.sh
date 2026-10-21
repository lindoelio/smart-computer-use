#!/usr/bin/env bash
# Measure what one step of the loop costs.
#
# The loop claims that a step is one command and a small payload. This script
# measures both against a real window:
#
#   scripts/measure-loop.sh --app "Google Chrome" --window 0
#
# It runs the same no-op action twice, once with --state and once with
# --state-diff, and prints the response sizes. A mouse move to the current
# position changes nothing on screen, so the measurement is safe to repeat.
set -uo pipefail

APP=""
WINDOW=""
SESSION="measure"
STEPS=3

usage() {
  cat <<'EOF'
Usage: measure-loop.sh --app <NAME> [--window <N>] [--steps <N>]

Measure the payload of one loop step: the full post-action state against the
post-action delta.

  --app <NAME>    the application to measure against
  --window <N>    the window index (default: the app's key window)
  --steps <N>     how many steps to measure (default: 3)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP=$2; shift 2 ;;
    --window) WINDOW=$2; shift 2 ;;
    --steps) STEPS=$2; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [[ -z "${APP}" ]]; then
  usage >&2
  exit 2
fi

if ! command -v computer-use >/dev/null 2>&1; then
  printf 'computer-use is not on PATH\n' >&2
  exit 1
fi

CURSOR=$(computer-use exec '{"action":"cursor_position"}' 2>/dev/null |
  python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["x"], d["y"])')
if [[ -z "${CURSOR}" ]]; then
  printf 'could not read the pointer position\n' >&2
  exit 1
fi
read -r X Y <<<"${CURSOR}"

measure() {
  local flag=$1
  local index=$2
  local out
  local -a target=(--app "${APP}")
  if [[ -n "${WINDOW}" ]]; then
    target+=(--window "${WINDOW}")
  fi
  out=$(computer-use move "${target[@]}" \
    --x "${X}" --y "${Y}" --session "${SESSION}-${flag}" "${flag}" 2>/dev/null)
  printf '%s' "${out}" | python3 -c '
import json
import sys

try:
    payload = sys.stdin.read()
    report = json.loads(payload)
except Exception:
    print("0\t0\t0")
    raise SystemExit(0)

state = report.get("state") or {}
tree = state.get("tree")
diff = state.get("diff")
print(
    len(payload),
    len(tree) if isinstance(tree, str) else 0,
    len(diff) if isinstance(diff, str) else 0,
)
'
}

printf 'step\tmode\tresponse bytes\ttree chars\tdiff chars\n'
index=0
while [[ "${index}" -lt "${STEPS}" ]]; do
  index=$((index + 1))
  for mode in --state --state-diff; do
    read -r bytes tree_chars diff_chars < <(measure "${mode}" "${index}")
    printf '%s\t%s\t%s\t%s\t%s\n' "${index}" "${mode}" "${bytes:-0}" "${tree_chars:-0}" "${diff_chars:-0}"
  done
done

printf '\nThe response bytes are what the agent pays for in context. The tree\n'
printf 'is the expensive half; the delta is what the loop reads.\n'
