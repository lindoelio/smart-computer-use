#!/usr/bin/env bash
# Report computer-use and OS permission status. Never changes grants.
set -euo pipefail


JSON=0
INSTALL_DIR="${COMPUTER_USE_INSTALL_DIR:-${HOME}/.local/bin}"
BINARY_NAME="computer-use"
TMP_ROOT=""
PREFERRED_VERSION="0.3.0"

CHECK_NAMES=()
CHECK_STATUS=()
CHECK_DETAILS=()

ACCESSIBILITY_HINT="Enable Accessibility in System Settings > Privacy & Security > Accessibility."
SCREEN_RECORDING_HINT="Enable Screen Recording in System Settings > Privacy & Security > Screen Recording."
NO_DISPLAY_HINT="Screen Recording is likely not granted to the host app (terminal/agent). Enable it in System Settings > Privacy & Security > Screen Recording and restart the host app."

usage() {
  cat <<'EOF'
Usage: check-deps.sh [--json] [--help]

Report whether the computer-use CLI is installed and, on macOS, whether
Accessibility and Screen Recording look usable. Linux checks report the
display session and optional tools. The script does not change permissions.

  --json    Print one JSON object on stdout.
  --help    Show this help.

Exit 0 when the CLI is present and no required check is denied.
Exit 1 when the CLI is missing, a permission is denied, or the session
is an unsupported display server. Exit 2 on a bad argument.
EOF
}

die() {
  printf 'smart-computer-use: %s\n' "$*" >&2
  exit 2
}

cleanup() {
  if [[ -n "${TMP_ROOT}" && -d "${TMP_ROOT}" ]]; then
    rm -rf "${TMP_ROOT}"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        usage
        exit 0
        ;;
      --json)
        JSON=1
        shift
        ;;
      *)
        die "unknown argument: $1 (try --help)"
        ;;
    esac
  done
}

ensure_tmp() {
  if [[ -z "${TMP_ROOT}" ]]; then
    TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/smart-computer-use-deps.XXXXXX")
  fi
}

add_check() {
  local name=$1 status=$2 detail=$3
  detail=${detail//$'\n'/ }
  detail=${detail//$'\r'/ }
  if [[ ${#detail} -gt 300 ]]; then
    detail=${detail:0:300}
  fi
  CHECK_NAMES+=("${name}")
  CHECK_STATUS+=("${status}")
  CHECK_DETAILS+=("${detail}")
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

json_string_or_null() {
  local value=$1
  if [[ -z "${value}" ]]; then
    printf 'null'
  else
    printf '"%s"' "$(json_escape "${value}")"
  fi
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

find_binary() {
  local candidate
  # The install directory wins over PATH, so the binary this skill manages is
  # the one that gets reported.
  candidate="${INSTALL_DIR}/${BINARY_NAME}"
  if [[ -x "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi
  if candidate=$(command -v "${BINARY_NAME}" 2>/dev/null); then
    if [[ -n "${candidate}" && -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  fi
  candidate="${HOME}/.cargo/bin/${BINARY_NAME}"
  if [[ -x "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi
  return 1
}

read_version() {
  local bin=$1
  local out
  if ! out=$(run_timeout 10 "${bin}" --version 2>/dev/null); then
    return 1
  fi
  out=${out%%$'\n'*}
  out=${out##* }
  out=${out#v}
  printf '%s\n' "${out}"
}

# True when $1 is a parseable version strictly older than $2.
version_older_than() {
  local have=$1 want=$2
  local -a hv=() wv=()
  local i hn wn max
  [[ -n "${have}" ]] || return 1
  IFS='.' read -r -a hv <<< "${have}" || true
  IFS='.' read -r -a wv <<< "${want}" || true
  max=${#hv[@]}
  if [[ ${#wv[@]} -gt ${max} ]]; then
    max=${#wv[@]}
  fi
  i=0
  while [[ ${i} -lt ${max} ]]; do
    hn=0
    wn=0
    if [[ ${i} -lt ${#hv[@]} ]]; then
      hn=${hv[${i}]//[^0-9]/}
      hn=${hn:-0}
    fi
    if [[ ${i} -lt ${#wv[@]} ]]; then
      wn=${wv[${i}]//[^0-9]/}
      wn=${wn:-0}
    fi
    if [[ ${hn} -lt ${wn} ]]; then
      return 0
    fi
    if [[ ${hn} -gt ${wn} ]]; then
      return 1
    fi
    i=$((i + 1))
  done
  return 1
}

lower_copy() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

permission_text_denied() {
  local lower
  lower=$(lower_copy "$1")
  case "${lower}" in
    *"does not have the permission"*|*"permission to simulate input"*|*"not trusted"*|*"accessibility permission"*|*"not allowed"*|*"not authorized"*|*"assistive"*)
      return 0
      ;;
  esac
  return 1
}

detail_contains_ci() {
  local hay needle
  hay=$(lower_copy "$1")
  needle=$(lower_copy "$2")
  [[ "${hay}" == *"${needle}"* ]]
}

append_hint() {
  local detail=$1 hint=$2 needle=$3
  if detail_contains_ci "${detail}" "${needle}"; then
    printf '%s' "${detail}"
    return
  fi
  if [[ -z "${detail}" ]]; then
    printf '%s' "${hint}"
    return
  fi
  case "${detail}" in
    *.|*"!"|*"?") ;;
    *) detail="${detail}." ;;
  esac
  printf '%s %s' "${detail}" "${hint}"
}

join_details() {
  local a=$1 b=$2
  a=${a//$'\n'/ }
  b=${b//$'\n'/ }
  if [[ -z "${a}" ]]; then
    printf '%s' "${b}"
  elif [[ -z "${b}" || "${a}" == "${b}" || "${a}" == *"${b}"* ]]; then
    printf '%s' "${a}"
  elif [[ "${b}" == *"${a}"* ]]; then
    printf '%s' "${b}"
  else
    printf '%s %s' "${a}" "${b}"
  fi
}

extract_json_string_value() {
  local blob=$1 key=$2
  local len i c n klen out esc
  len=${#blob}
  klen=${#key}
  i=0
  while [[ ${i} -lt ${len} ]]; do
    if [[ "${blob:i:1}" == '"' && $((i + klen + 1)) -le ${len} && "${blob:i+1:klen}" == "${key}" && "${blob:i+klen+1:1}" == '"' ]]; then
      n=$((i + klen + 2))
      while [[ ${n} -lt ${len} ]]; do
        c=${blob:n:1}
        case "${c}" in
          ' '|$'\t') n=$((n + 1)) ;;
          *) break ;;
        esac
      done
      if [[ ${n} -ge ${len} || "${blob:n:1}" != ':' ]]; then
        i=$((i + 1))
        continue
      fi
      n=$((n + 1))
      while [[ ${n} -lt ${len} ]]; do
        c=${blob:n:1}
        case "${c}" in
          ' '|$'\t') n=$((n + 1)) ;;
          *) break ;;
        esac
      done
      if [[ ${n} -ge ${len} || "${blob:n:1}" != '"' ]]; then
        printf ''
        return 0
      fi
      n=$((n + 1))
      out=""
      esc=0
      while [[ ${n} -lt ${len} ]]; do
        c=${blob:n:1}
        if [[ ${esc} -eq 1 ]]; then
          case "${c}" in
            n) out+=$'\n' ;;
            r) out+=$'\r' ;;
            t) out+=$'\t' ;;
            *) out+="${c}" ;;
          esac
          esc=0
        elif [[ "${c}" == $'\134' ]]; then
          esc=1
        elif [[ "${c}" == '"' ]]; then
          printf '%s' "${out}"
          return 0
        else
          out+="${c}"
        fi
        n=$((n + 1))
      done
      printf '%s' "${out}"
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

extract_balanced_object() {
  local s=$1
  local len i c depth out instr esc
  len=${#s}
  depth=0
  instr=0
  esc=0
  out=""
  for ((i = 0; i < len; i++)); do
    c=${s:i:1}
    out+="${c}"
    if [[ ${instr} -eq 1 ]]; then
      if [[ ${esc} -eq 1 ]]; then
        esc=0
      elif [[ "${c}" == $'\134' ]]; then
        esc=1
      elif [[ "${c}" == '"' ]]; then
        instr=0
      fi
      continue
    fi
    if [[ "${c}" == '"' ]]; then
      instr=1
    elif [[ "${c}" == '{' ]]; then
      depth=$((depth + 1))
    elif [[ "${c}" == '}' ]]; then
      depth=$((depth - 1))
      if [[ ${depth} -eq 0 ]]; then
        printf '%s' "${out}"
        return 0
      fi
    fi
  done
  return 1
}

object_has_positive_ax() {
  local obj=$1 rest
  rest=${obj}
  while [[ "${rest}" == *'"role":"'* ]]; do
    rest=${rest#*'"role":"'}
    if [[ -n "${rest}" && "${rest}" != '"'* ]]; then
      return 0
    fi
  done
  rest=${obj}
  while [[ "${rest}" == *'"title":"'* ]]; do
    rest=${rest#*'"title":"'}
    if [[ -n "${rest}" && "${rest}" != '"'* ]]; then
      return 0
    fi
  done
  rest=${obj}
  while [[ "${rest}" == *'"children":['* ]]; do
    rest=${rest#*'"children":['}
    if [[ "${rest}" != ']'* ]]; then
      return 0
    fi
  done
  return 1
}

tree_kind_from_compact() {
  local blob=$1 rest obj
  if [[ "${blob}" != *'"accessibility":'* ]]; then
    printf 'unknown'
    return 0
  fi
  rest=${blob#*'"accessibility":'}
  if [[ "${rest}" == null* ]]; then
    printf 'absent'
    return 0
  fi
  if [[ "${rest}" != '{'* ]]; then
    printf 'unknown'
    return 0
  fi
  if ! obj=$(extract_balanced_object "${rest}"); then
    printf 'unknown'
    return 0
  fi
  if object_has_positive_ax "${obj}"; then
    printf 'positive'
  else
    printf 'empty'
  fi
}

bash_parse_cli_json() {
  local file=$1
  local raw compact note message code tree ok_val acc_kind
  raw=$(tr '\r\n' '  ' < "${file}")
  compact=$(printf '%s' "${raw}" | tr -d '[:space:]')
  note=$(extract_json_string_value "${raw}" "note" || true)
  message=$(extract_json_string_value "${raw}" "message" || true)
  code=$(extract_json_string_value "${raw}" "code" || true)
  note=${note//$'\t'/ }
  note=${note//$'\n'/ }
  note=${note//$'\r'/ }
  message=${message//$'\t'/ }
  message=${message//$'\n'/ }
  message=${message//$'\r'/ }
  code=${code//$'\t'/ }
  if [[ "${compact}" == *'"ok":true'* ]]; then
    ok_val="true"
  else
    ok_val="false"
  fi
  if [[ "${compact}" == *'"accessibility":null'* ]]; then
    acc_kind="null"
  elif [[ "${compact}" == *'"accessibility":'* ]]; then
    acc_kind="present"
  else
    acc_kind="unknown"
  fi
  tree=$(tree_kind_from_compact "${compact}")
  printf 'ok\t%s\n' "${ok_val}"
  printf 'accessibility\t%s\n' "${acc_kind}"
  printf 'tree\t%s\n' "${tree}"
  printf 'note\t%s\n' "${note}"
  printf 'error_code\t%s\n' "${code}"
  printf 'error_message\t%s\n' "${message}"
}

parse_cli_json() {
  local file=$1
  if command -v python3 >/dev/null 2>&1; then
    python3 - "${file}" <<'PY'
import json
import sys

path = sys.argv[1]

def clean(value, limit):
    text = "" if value is None else str(value)
    text = text.replace("\t", " ").replace("\r", " ").replace("\n", " ")
    return text[:limit]

def present_value(value):
    if value is None:
        return False
    if isinstance(value, str):
        return value.strip() != ""
    return True

def nonempty_children(value):
    if isinstance(value, list):
        return len(value) > 0
    return value is not None and value != ""

def node_positive(node):
    if not isinstance(node, dict):
        return False
    if present_value(node.get("role")) or present_value(node.get("title")):
        return True
    return nonempty_children(node.get("children"))

def tree_kind(acc):
    if acc is None:
        return "absent"
    if not isinstance(acc, dict):
        return "unknown"
    nodes = [acc]
    window = acc.get("window")
    if isinstance(window, dict):
        nodes.append(window)
    for node in nodes:
        if node_positive(node):
            return "positive"
    return "empty"

try:
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
except Exception as exc:
    print("ok\tfalse")
    print("accessibility\tunknown")
    print("tree\tunknown")
    print("note\t" + clean(exc, 300))
    print("error_code\t")
    print("error_message\t")
    raise SystemExit(0)

note = data.get("note")
acc = data.get("accessibility")
error = data.get("error") if isinstance(data.get("error"), dict) else {}
if acc is None:
    acc_kind = "null"
elif isinstance(acc, dict):
    acc_kind = "present"
else:
    acc_kind = "unknown"
print("ok\t" + ("true" if data.get("ok") else "false"))
print("accessibility\t" + acc_kind)
print("tree\t" + tree_kind(acc))
print("note\t" + clean(note, 500))
print("error_code\t" + clean(error.get("code"), 80))
print("error_message\t" + clean(error.get("message"), 300))
PY
    return
  fi
  bash_parse_cli_json "${file}"
}

field_from_tsv() {
  local tsv=$1 key=$2
  local line k v
  while IFS= read -r line || [[ -n "${line}" ]]; do
    k=${line%%$'\t'*}
    v=${line#*$'\t'}
    if [[ "${k}" == "${key}" ]]; then
      printf '%s' "${v}"
      return 0
    fi
  done <<< "${tsv}"
  return 1
}

classify_state_accessibility() {
  local tree=$1 note=$2 err=$3
  local text lower
  text="${note}"
  if [[ -n "${err}" ]]; then
    if [[ -n "${text}" ]]; then
      text="${text} ${err}"
    else
      text="${err}"
    fi
  fi
  text=${text//$'\n'/ }
  # Permission text wins over a populated tree. An empty window is not a grant.
  if permission_text_denied "${text}"; then
    printf 'denied\t%s\n' "${text}"
    return
  fi
  lower=$(lower_copy "${text}")
  case "${lower}" in
    *"not available on linux"*|*"not available on windows"*|*"at-spi"*)
      printf 'unsupported\t%s\n' "${text:-accessibility tree is not available on this platform}"
      return
      ;;
  esac
  case "${tree}" in
    positive)
      if [[ -n "${note}" ]]; then
        printf 'ok\t%s\n' "${note}"
      else
        printf 'ok\taccessibility tree includes a role, title, or children\n'
      fi
      ;;
    empty)
      if [[ -n "${text}" ]]; then
        printf 'denied\taccessibility tree is empty (window role and title are null and there are no children). %s\n' "${text}"
      else
        printf 'denied\taccessibility tree is empty (window role and title are null and there are no children)\n'
      fi
      ;;
    *)
      if [[ -n "${text}" ]]; then
        printf 'unknown\t%s\n' "${text}"
      else
        printf 'unknown\tget-state returned no accessibility evidence\n'
      fi
      ;;
  esac
}

combine_probe_status() {
  local s1=$1 d1=$2 s2=$3 d2=$4
  local detail
  if [[ "${s1}" == "denied" || "${s2}" == "denied" ]]; then
    detail=""
    if [[ "${s1}" == "denied" ]]; then
      detail="${d1}"
    fi
    if [[ "${s2}" == "denied" ]]; then
      detail=$(join_details "${detail}" "${d2}")
    fi
    printf 'denied\t%s\n' "${detail}"
    return
  fi
  if [[ "${s1}" == "ok" || "${s2}" == "ok" ]]; then
    if [[ "${s1}" == "ok" && "${s2}" == "ok" ]]; then
      printf 'ok\t%s\n' "$(join_details "${d1}" "${d2}")"
    elif [[ "${s1}" == "ok" ]]; then
      printf 'ok\t%s\n' "${d1}"
    else
      printf 'ok\t%s\n' "${d2}"
    fi
    return
  fi
  if [[ "${s1}" == "unsupported" || "${s2}" == "unsupported" ]]; then
    if [[ "${s1}" == "unsupported" ]]; then
      printf 'unsupported\t%s\n' "${d1}"
    else
      printf 'unsupported\t%s\n' "${d2}"
    fi
    return
  fi
  printf 'unknown\t%s\n' "$(join_details "${d1}" "${d2}")"
}

classify_failure_text() {
  local text=$1
  local lower
  lower=$(lower_copy "${text}")
  case "${lower}" in
    *"timed out"*|*"timeout"*)
      printf 'unknown'
      ;;
    *"permission"*|*"denied"*|*"not authorized"*|*"not allowed"*|*"screen recording"*|*"tcc"*|*"privacy"*)
      printf 'denied'
      ;;
    *)
      printf 'unknown'
      ;;
  esac
}

is_png() {
  local file=$1
  local sig
  if [[ ! -s "${file}" ]]; then
    return 1
  fi
  sig=$(od -An -N 8 -t x1 "${file}" 2>/dev/null | tr -d '[:space:]' || true)
  [[ "${sig}" == "89504e470d0a1a0a" ]]
}

macos_osascript() {
  local out status lower
  status=0
  out=$(run_timeout 8 osascript -e 'tell application "System Events" to get UI elements enabled' 2>&1) || status=$?
  out=${out//$'\n'/ }
  out=${out//$'\r'/ }
  out=${out#"${out%%[![:space:]]*}"}
  out=${out%"${out##*[![:space:]]}"}
  if [[ "${status}" -eq 124 ]]; then
    printf 'unknown\tosascript timed out before reporting Accessibility\n'
    return
  fi
  lower=$(lower_copy "${out}")
  case "${lower}" in
    true)
      printf 'ok\tSystem Events reports UI elements enabled.\n'
      ;;
    false)
      printf 'denied\tSystem Events reports UI elements enabled is false.\n'
      ;;
    *"not allowed"*|*"not authorized"*|*"assistive"*|*"-1743"*|*"-25211"*|*"1002"*)
      printf 'denied\tSystem Events cannot use Accessibility (%s).\n' "${out}"
      ;;
    *)
      printf 'unknown\t%s\n' "${out:-osascript returned no output}"
      ;;
  esac
}

probe_get_state() {
  local bin=$1
  local out err status tsv tree note message
  ensure_tmp
  out="${TMP_ROOT}/get-state.json"
  err="${TMP_ROOT}/get-state.err"
  status=0
  run_timeout 20 "${bin}" get-state >"${out}" 2>"${err}" || status=$?
  if [[ "${status}" -eq 124 ]]; then
    printf 'unknown\tcomputer-use get-state timed out\n'
    return
  fi
  if [[ ! -s "${out}" ]]; then
    message=$(tr '\n' ' ' < "${err}" || true)
    if permission_text_denied "${message}"; then
      printf 'denied\t%s\n' "${message}"
      return
    fi
    printf 'unknown\t%s\n' "${message:-computer-use get-state produced no JSON}"
    return
  fi
  tsv=$(parse_cli_json "${out}")
  tree=$(field_from_tsv "${tsv}" tree || true)
  note=$(field_from_tsv "${tsv}" note || true)
  message=$(field_from_tsv "${tsv}" error_message || true)
  classify_state_accessibility "${tree}" "${note}" "${message}"
}

probe_screenshot() {
  local bin=$1
  local out err shot status tsv message kind lower hinted
  ensure_tmp
  out="${TMP_ROOT}/screenshot.json"
  err="${TMP_ROOT}/screenshot.err"
  shot="${TMP_ROOT}/screen.png"
  status=0
  run_timeout 20 "${bin}" screenshot --output "${shot}" --format png --max-width 32 >"${out}" 2>"${err}" || status=$?
  if [[ "${status}" -eq 124 ]]; then
    printf 'unknown\tcomputer-use screenshot timed out\n'
    return
  fi
  if [[ "${status}" -eq 0 ]] && is_png "${shot}"; then
    printf 'ok\tscreenshot wrote a PNG. A fully blank image can still mean Screen Recording is off\n'
    return
  fi
  message=""
  if [[ -s "${out}" ]]; then
    tsv=$(parse_cli_json "${out}")
    message=$(field_from_tsv "${tsv}" error_message || true)
  fi
  if [[ -z "${message}" && -s "${err}" ]]; then
    message=$(tr '\n' ' ' < "${err}" || true)
  fi
  message=${message//$'\n'/ }
  lower=$(lower_copy "${message}")
  case "${lower}" in
    *"timed out"*|*"timeout"*)
      printf 'unknown\t%s\n' "${message:-computer-use screenshot timed out}"
      return
      ;;
  esac
  # On a logged-in Mac, CGWindow/xcap returns no displays when Screen Recording is off.
  if [[ "$(platform_name)" == "macos" && "${lower}" == *"no display available"* ]]; then
    if detail_contains_ci "${message}" "privacy & security > screen recording"; then
      printf 'denied\t%s\n' "${message}"
    elif [[ -n "${message}" ]]; then
      printf 'denied\t%s. %s\n' "${message%.}" "${NO_DISPLAY_HINT}"
    else
      printf 'denied\t%s\n' "${NO_DISPLAY_HINT}"
    fi
    return
  fi
  kind=$(classify_failure_text "${message}")
  if [[ "${kind}" == "denied" ]]; then
    hinted=$(append_hint "${message}" "${SCREEN_RECORDING_HINT}" "privacy & security > screen recording")
    printf 'denied\t%s\n' "${hinted}"
    return
  fi
  printf 'unknown\t%s\n' "${message:-screenshot did not write a PNG}"
}

check_linux_libs() {
  local bin=$1
  local missing
  if ! command -v ldd >/dev/null 2>&1; then
    return 0
  fi
  missing=$(ldd "${bin}" 2>/dev/null | grep 'not found' || true)
  if [[ -n "${missing}" ]]; then
    missing=${missing//$'\n'/; }
    add_check "libraries" "missing" "loader could not find libraries: ${missing}. On Debian/Ubuntu the build packages are pkg-config libxdo-dev libx11-dev libxcb1-dev libxrandr-dev libdbus-1-dev libxkbcommon-dev."
  else
    add_check "libraries" "ok" "ldd did not report missing libraries"
  fi
}

platform_name() {
  case "$(uname -s)" in
    Darwin) printf 'macos' ;;
    Linux) printf 'linux' ;;
    MINGW*|MSYS*|CYGWIN*) printf 'windows' ;;
    *) printf 'unknown' ;;
  esac
}

emit_json() {
  local ok_json=$1 platform=$2 cli_path=$3 cli_version=$4
  local present_json i comma
  if [[ -n "${cli_path}" ]]; then
    present_json=true
  else
    present_json=false
  fi
  printf '{\n'
  printf '  "ok": %s,\n' "${ok_json}"
  printf '  "platform": "%s",\n' "$(json_escape "${platform}")"
  printf '  "cli": {"present": %s, "path": %s, "version": %s},\n' \
    "${present_json}" \
    "$(json_string_or_null "${cli_path}")" \
    "$(json_string_or_null "${cli_version}")"
  printf '  "checks": [\n'
  if [[ ${#CHECK_NAMES[@]} -eq 0 ]]; then
    printf '  ]\n}\n'
    return
  fi
  i=0
  while [[ ${i} -lt ${#CHECK_NAMES[@]} ]]; do
    comma=','
    if [[ $((i + 1)) -eq ${#CHECK_NAMES[@]} ]]; then
      comma=''
    fi
    printf '    {"name": "%s", "status": "%s", "detail": "%s"}%s\n' \
      "$(json_escape "${CHECK_NAMES[${i}]}")" \
      "$(json_escape "${CHECK_STATUS[${i}]}")" \
      "$(json_escape "${CHECK_DETAILS[${i}]}")" \
      "${comma}"
    i=$((i + 1))
  done
  printf '  ]\n}\n'
}

emit_human() {
  local platform=$1
  local i
  printf 'platform: %s\n' "${platform}"
  i=0
  while [[ ${i} -lt ${#CHECK_NAMES[@]} ]]; do
    printf '%s: %s — %s\n' "${CHECK_NAMES[${i}]}" "${CHECK_STATUS[${i}]}" "${CHECK_DETAILS[${i}]}"
    i=$((i + 1))
  done
}

# Report whether the binary runs inside the app bundle. Inside the bundle the
# macOS permission grant belongs to `ai.lindoelio.computer-use`; outside it,
# the grant belongs to whichever program started the binary.
check_identity() {
  local bin=$1 line bundled bundle_id
  line=$(run_timeout 20 "${bin}" doctor 2>/dev/null | parse_doctor_identity)
  if [[ -z "${line}" ]]; then
    add_check "identity" "unknown" "The CLI did not report a TCC identity."
    return 0
  fi
  bundled=${line%%$'\t'*}
  bundle_id=${line#*$'\t'}
  if [[ "${bundled}" == "true" ]]; then
    add_check "identity" "ok" "The binary runs inside the app bundle (${bundle_id:-unknown bundle id}). The macOS permission grant belongs to the app, not to the program that started it."
  else
    add_check "identity" "warn" "The binary runs outside the app bundle, so the macOS permission grant belongs to the program that started it and changes with the host. Run scripts/setup.sh to install the bundle and keep the grant stable."
  fi
}

# Read identity.bundled and identity.bundle_id out of the doctor report.
parse_doctor_identity() {
  local file
  ensure_tmp
  file="${TMP_ROOT}/doctor-identity.json"
  if ! cat >"${file}"; then
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    return 0
  fi
  python3 - "${file}" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        report = json.load(handle)
except Exception:
    sys.exit(0)

identity = report.get("identity") or {}
bundled = identity.get("bundled")
bundle_id = identity.get("bundle_id") or ""
print(f"{str(bool(bundled)).lower()}\t{bundle_id}")
PY
}

should_fail() {
  local cli_path=$1
  local i name status
  if [[ -z "${cli_path}" ]]; then
    return 0
  fi
  i=0
  while [[ ${i} -lt ${#CHECK_NAMES[@]} ]]; do
    name=${CHECK_NAMES[${i}]}
    status=${CHECK_STATUS[${i}]}
    if [[ "${status}" == "denied" ]]; then
      return 0
    fi
    if [[ "${name}" == "session" && "${status}" == "unsupported" ]]; then
      return 0
    fi
    if [[ "${name}" == "libraries" && "${status}" == "missing" ]]; then
      return 0
    fi
    if [[ "${name}" == "cli" && "${status}" == "outdated" ]]; then
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

main() {
  local platform bin version cli_path probe_status probe_detail osa_line osa_status osa_detail
  local state_line state_status state_detail combined session
  parse_args "$@"
  trap cleanup EXIT

  platform=$(platform_name)
  cli_path=""
  version=""
  if bin=$(find_binary); then
    cli_path=${bin}
    if version=$(read_version "${bin}"); then
      :
    else
      version=""
    fi
    if [[ -n "${version}" ]] && version_older_than "${version}" "${PREFERRED_VERSION}"; then
      add_check "cli" "outdated" "computer-use ${version} at ${cli_path}. ${PREFERRED_VERSION} is required: the tree, element targeting, batch, browser, and --state-diff surface need it. Run scripts/setup.sh to upgrade."
    else
      add_check "cli" "ok" "computer-use ${version:-unknown} at ${cli_path}"
    fi
  else
    add_check "cli" "missing" "computer-use was not found on PATH or in ${INSTALL_DIR}. Run scripts/setup.sh."
  fi

  case "${platform}" in
    macos)
      if [[ -z "${cli_path}" ]]; then
        add_check "accessibility" "unknown" "CLI is not installed, so Accessibility was not checked. Enable it in System Settings > Privacy & Security > Accessibility."
        add_check "screen_recording" "unknown" "CLI is not installed, so Screen Recording was not checked. Enable it in System Settings > Privacy & Security > Screen Recording."
      else
        state_line=$(probe_get_state "${cli_path}")
        state_status=${state_line%%$'\t'*}
        state_detail=${state_line#*$'\t'}
        if command -v osascript >/dev/null 2>&1; then
          osa_line=$(macos_osascript)
          osa_status=${osa_line%%$'\t'*}
          osa_detail=${osa_line#*$'\t'}
        else
          osa_status="unknown"
          osa_detail="osascript is not available"
        fi
        # Denied wins: a permission failure overrides a populated tree or an osascript true.
        combined=$(combine_probe_status "${osa_status}" "${osa_detail}" "${state_status}" "${state_detail}")
        probe_status=${combined%%$'\t'*}
        probe_detail=${combined#*$'\t'}
        if [[ "${probe_status}" == "denied" || "${probe_status}" == "unknown" ]]; then
          probe_detail=$(append_hint "${probe_detail}" "${ACCESSIBILITY_HINT}" "privacy & security > accessibility")
        fi
        add_check "accessibility" "${probe_status}" "${probe_detail}"
        probe_status=$(probe_screenshot "${cli_path}")
        probe_detail=${probe_status#*$'\t'}
        probe_status=${probe_status%%$'\t'*}
        if [[ "${probe_status}" == "unknown" ]]; then
          probe_detail=$(append_hint "${probe_detail}" "${SCREEN_RECORDING_HINT}" "privacy & security > screen recording")
        fi
        add_check "screen_recording" "${probe_status}" "${probe_detail}"
      fi
      if [[ -n "${cli_path}" ]]; then
        check_identity "${cli_path}"
      fi
      ;;
    linux)
      if [[ -n "${WAYLAND_DISPLAY:-}" && -z "${DISPLAY:-}" ]]; then
        session="wayland"
      elif [[ -n "${WAYLAND_DISPLAY:-}" && -n "${DISPLAY:-}" ]]; then
        session="wayland-with-xwayland"
      elif [[ -n "${DISPLAY:-}" ]]; then
        session="x11"
      else
        session="none"
      fi
      case "${session}" in
        x11)
          add_check "session" "ok" "DISPLAY is set. The CLI targets X11."
          ;;
        wayland)
          add_check "session" "unsupported" "Wayland is not a supported target. An X11 session with DISPLAY set is required."
          ;;
        wayland-with-xwayland)
          add_check "session" "unknown" "WAYLAND_DISPLAY and DISPLAY are both set. XWayland may work; the CLI does not support native Wayland."
          ;;
        *)
          add_check "session" "missing" "DISPLAY is unset. Start an X11 session before using computer-use."
          ;;
      esac
      if command -v xdotool >/dev/null 2>&1; then
        add_check "xdotool" "ok" "xdotool is on PATH. It improves the frontmost-window lookup."
      else
        add_check "xdotool" "missing" "xdotool is not on PATH. The frontmost window title is weaker without it. This tool is optional."
      fi
      if [[ -n "${cli_path}" ]]; then
        check_linux_libs "${cli_path}"
      fi
      ;;
    windows)
      add_check "session" "unknown" "Run computer-use in an interactive desktop session, not Session 0. The accessibility tree is null in this build."
      ;;
    *)
      add_check "session" "unknown" "Unrecognized operating system $(uname -s)."
      ;;
  esac

  if should_fail "${cli_path}"; then
    if [[ "${JSON}" -eq 1 ]]; then
      emit_json false "${platform}" "${cli_path}" "${version}"
    else
      emit_human "${platform}"
    fi
    cleanup
    exit 1
  fi
  if [[ "${JSON}" -eq 1 ]]; then
    emit_json true "${platform}" "${cli_path}" "${version}"
  else
    emit_human "${platform}"
  fi
  cleanup
}

main "$@"
