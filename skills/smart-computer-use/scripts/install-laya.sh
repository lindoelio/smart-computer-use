#!/usr/bin/env bash
# Optional, experimental Laya installer. Never required for computer-use.
set -euo pipefail

METHOD=""
ASSUME_YES=0
VERBOSE=0
CONFIG_DIR="${HOME}/.config/smart-computer-use"
CONFIG_FILE="${CONFIG_DIR}/config.json"

ENABLED="false"
ENDPOINT=""
MODEL=""
WEIGHTS_PATH=""
RESOLVED_METHOD=""

usage() {
  cat <<'EOF'
Usage: install-laya.sh [--method ollama|pip] [--yes] [--verbose] [--help]

Laya is optional and experimental. smart-computer-use works without it.
This script exits 0 even when Laya cannot be installed. A bad argument
exits 2.

  --method ollama   Run: ollama pull laya
  --method pip      Run: pip install --user laya
  --yes             Do not prompt. With no --method, prefer ollama, then pip.
  --verbose         Print installer output.
  --help            Show this help.

Detection:
  ollama list shows a model named laya or laya:<tag>
  a laya executable is on PATH
  LAYA_MODEL_PATH is a directory

Config is written to ~/.config/smart-computer-use/config.json.
EOF
}

log() {
  if [[ "${VERBOSE}" -eq 1 ]]; then
    printf '%s\n' "$*" >&2
  fi
}

warn() {
  printf 'smart-computer-use: %s\n' "$*" >&2
}

die() {
  printf 'smart-computer-use: %s\n' "$*" >&2
  exit 2
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        usage
        exit 0
        ;;
      --verbose|-v)
        VERBOSE=1
        shift
        ;;
      --yes|-y)
        ASSUME_YES=1
        shift
        ;;
      --method)
        if [[ $# -lt 2 ]]; then
          die "--method needs ollama or pip"
        fi
        METHOD=$2
        shift 2
        ;;
      --method=*)
        METHOD=${1#--method=}
        shift
        ;;
      *)
        die "unknown argument: $1 (try --help)"
        ;;
    esac
  done
  case "${METHOD}" in
    ""|ollama|pip) ;;
    *) die "--method must be ollama or pip" ;;
  esac
}

run_timeout() {
  local seconds=$1
  shift
  local pid elapsed status
  "$@" &
  pid=$!
  elapsed=0
  while kill -0 "${pid}" 2>/dev/null; do
    if [[ "${elapsed}" -ge "${seconds}" ]]; then
      kill "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  if wait "${pid}"; then
    return 0
  fi
  status=$?
  return "${status}"
}

json_escape() {
  local s=$1
  local i c out len bs dq nl cr tab
  bs=$'\134'
  dq='"'
  nl=$'\n'
  cr=$'\r'
  tab=$'\t'
  len=${#s}
  out=""
  for ((i = 0; i < len; i++)); do
    c=${s:i:1}
    if [[ "${c}" == "${bs}" ]]; then
      out+="${bs}${bs}"
    elif [[ "${c}" == "${dq}" ]]; then
      out+="${bs}${dq}"
    elif [[ "${c}" == "${nl}" ]]; then
      out+="${bs}n"
    elif [[ "${c}" == "${cr}" ]]; then
      out+="${bs}r"
    elif [[ "${c}" == "${tab}" ]]; then
      out+="${bs}t"
    elif [[ "${c}" == *[[:cntrl:]]* ]]; then
      out+='?'
    else
      out+="${c}"
    fi
  done
  printf '%s' "${out}"
}

have_pip() {
  if command -v pip3 >/dev/null 2>&1; then
    return 0
  fi
  if command -v pip >/dev/null 2>&1; then
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

detect_ollama_model() {
  local list line name
  if ! command -v ollama >/dev/null 2>&1; then
    return 1
  fi
  if ! list=$(run_timeout 20 ollama list 2>/dev/null); then
    return 1
  fi
  while IFS= read -r line || [[ -n "${line}" ]]; do
    name=${line%%[[:space:]]*}
    case "${name}" in
      NAME|"") ;;
      laya|laya:*) return 0 ;;
    esac
  done <<< "${list}"
  return 1
}

detect_existing() {
  if detect_ollama_model; then
    RESOLVED_METHOD="ollama"
    ENDPOINT="http://127.0.0.1:11434"
    MODEL="laya"
    ENABLED="true"
    if [[ -n "${LAYA_MODEL_PATH:-}" && -d "${LAYA_MODEL_PATH}" ]]; then
      WEIGHTS_PATH=${LAYA_MODEL_PATH}
    fi
    return 0
  fi
  if command -v laya >/dev/null 2>&1; then
    RESOLVED_METHOD="cli"
    MODEL="laya"
    ENABLED="true"
    if [[ -n "${LAYA_MODEL_PATH:-}" && -d "${LAYA_MODEL_PATH}" ]]; then
      WEIGHTS_PATH=${LAYA_MODEL_PATH}
    fi
    return 0
  fi
  if [[ -n "${LAYA_MODEL_PATH:-}" && -d "${LAYA_MODEL_PATH}" ]]; then
    RESOLVED_METHOD="weights"
    WEIGHTS_PATH=${LAYA_MODEL_PATH}
    MODEL="laya"
    ENABLED="true"
    return 0
  fi
  return 1
}

choose_method() {
  local choice
  if [[ -n "${METHOD}" ]]; then
    return 0
  fi
  if [[ "${ASSUME_YES}" -eq 1 ]]; then
    if command -v ollama >/dev/null 2>&1; then
      METHOD="ollama"
    elif have_pip; then
      METHOD="pip"
    fi
    return 0
  fi
  if [[ ! -t 0 ]]; then
    warn "Laya is optional and experimental. Re-run with --method ollama or --method pip, and --yes, to install it."
    return 0
  fi
  printf '%s\n' "Laya is optional and experimental. The skill works without it." >&2
  printf '%s\n' "1) ollama pull laya" >&2
  printf '%s\n' "2) pip install laya" >&2
  printf '%s\n' "3) skip" >&2
  IFS= read -r choice || true
  case "${choice}" in
    1|ollama) METHOD="ollama" ;;
    2|pip) METHOD="pip" ;;
    *) METHOD="" ;;
  esac
}

run_logged() {
  local logf
  logf=$(mktemp "${TMPDIR:-/tmp}/smart-computer-use-laya.XXXXXX")
  if [[ "${VERBOSE}" -eq 1 ]]; then
    if "$@"; then
      rm -f "${logf}"
      return 0
    fi
    rm -f "${logf}"
    return 1
  fi
  if "$@" >"${logf}" 2>&1; then
    rm -f "${logf}"
    return 0
  fi
  cat "${logf}" >&2
  rm -f "${logf}"
  return 1
}

install_ollama() {
  if ! command -v ollama >/dev/null 2>&1; then
    warn "ollama is not on PATH. Install Ollama from https://ollama.com/download, then run: ollama pull laya"
    return 1
  fi
  log "running ollama pull laya"
  if ! run_logged ollama pull laya; then
    warn "ollama pull laya failed. Laya is optional; continuing without it."
    return 1
  fi
  RESOLVED_METHOD="ollama"
  ENDPOINT="http://127.0.0.1:11434"
  MODEL="laya"
  ENABLED="true"
}

install_pip() {
  local -a cmd
  if command -v pip3 >/dev/null 2>&1; then
    cmd=(pip3 install --user laya)
  elif command -v pip >/dev/null 2>&1; then
    cmd=(pip install --user laya)
  elif command -v python3 >/dev/null 2>&1; then
    cmd=(python3 -m pip install --user laya)
  else
    warn "pip was not found. Install Python 3 and run: pip install laya"
    return 1
  fi
  log "running ${cmd[*]}"
  if ! run_logged "${cmd[@]}"; then
    warn "pip install laya failed. Laya is optional; continuing without it."
    return 1
  fi
  RESOLVED_METHOD="pip"
  MODEL="laya"
  ENABLED="true"
}

write_config() {
  local enabled_py path_py method_py model_py endpoint_py
  mkdir -p "${CONFIG_DIR}"
  if command -v python3 >/dev/null 2>&1; then
    if LAYA_CONFIG_PATH="${CONFIG_FILE}" \
      LAYA_ENABLED_VALUE="${ENABLED}" \
      LAYA_ENDPOINT_VALUE="${ENDPOINT}" \
      LAYA_MODEL_VALUE="${MODEL}" \
      LAYA_PATH_VALUE="${WEIGHTS_PATH}" \
      LAYA_METHOD_VALUE="${RESOLVED_METHOD}" \
      python3 - <<'PY'
import json
import os

path = os.environ["LAYA_CONFIG_PATH"]
data = {}
if os.path.exists(path):
    try:
        with open(path, encoding="utf-8") as handle:
            loaded = json.load(handle)
        if isinstance(loaded, dict):
            data = loaded
    except (OSError, json.JSONDecodeError):
        data = {}
laya = data.get("laya")
if not isinstance(laya, dict):
    laya = {}
laya["enabled"] = os.environ["LAYA_ENABLED_VALUE"] == "true"
laya["experimental"] = True
laya["endpoint"] = os.environ["LAYA_ENDPOINT_VALUE"]
laya["model"] = os.environ["LAYA_MODEL_VALUE"]
laya["path"] = os.environ["LAYA_PATH_VALUE"]
laya["method"] = os.environ["LAYA_METHOD_VALUE"]
data["laya"] = laya
directory = os.path.dirname(path)
if directory:
    os.makedirs(directory, exist_ok=True)
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY
    then
      return 0
    fi
    warn "could not merge config with python3; rewriting ${CONFIG_FILE}"
  fi
  enabled_py="false"
  if [[ "${ENABLED}" == "true" ]]; then
    enabled_py="true"
  fi
  endpoint_py=$(json_escape "${ENDPOINT}")
  model_py=$(json_escape "${MODEL}")
  path_py=$(json_escape "${WEIGHTS_PATH}")
  method_py=$(json_escape "${RESOLVED_METHOD}")
  cat > "${CONFIG_FILE}" <<EOF
{
  "laya": {
    "enabled": ${enabled_py},
    "experimental": true,
    "endpoint": "${endpoint_py}",
    "model": "${model_py}",
    "path": "${path_py}",
    "method": "${method_py}"
  }
}
EOF
}

print_hints() {
  local laya_flag=0
  if [[ "${ENABLED}" == "true" ]]; then
    laya_flag=1
  fi
  cat <<EOF
Laya is optional and experimental. smart-computer-use works without it.
Config: ${CONFIG_FILE}

export SMART_COMPUTER_USE_LAYA=${laya_flag}
export SMART_COMPUTER_USE_LAYA_MODEL=${MODEL:-laya}
export SMART_COMPUTER_USE_LAYA_ENDPOINT=${ENDPOINT:-http://127.0.0.1:11434}
export SMART_COMPUTER_USE_LAYA_PATH=${WEIGHTS_PATH}
EOF
}

main() {
  parse_args "$@"
  printf '%s\n' "Laya is optional and experimental." >&2
  if detect_existing; then
    log "found an existing Laya runtime (${RESOLVED_METHOD})"
    write_config
    print_hints
    exit 0
  fi
  choose_method
  case "${METHOD}" in
    ollama)
      install_ollama || true
      ;;
    pip)
      install_pip || true
      ;;
    "")
      warn "Laya was not installed. The CLI setup is unchanged."
      ;;
  esac
  write_config
  print_hints
  exit 0
}

main "$@"
