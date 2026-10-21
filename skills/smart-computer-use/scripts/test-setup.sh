#!/usr/bin/env bash
# Exercise setup.sh without touching the network.
#
# The test puts a fake `computer-use` and a fake `curl` on PATH. The fake curl
# records that it was called and then fails, so the script never reaches the
# network. What the test asserts is the decision the script makes: an
# acceptable version skips the download, an old one does not.
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
SETUP="${SCRIPT_DIR}/setup.sh"

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

# Build a sandbox with a fake binary, a fake curl, and a fake cargo.
# $1: version the fake computer-use reports
make_sandbox() {
  local version=$1 root=$2
  mkdir -p "${root}/bin" "${root}/install"
  cat >"${root}/bin/computer-use" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then
  printf 'computer-use %s\n' "${version}"
  exit 0
fi
printf '{"ok":true}\n'
EOF
  chmod +x "${root}/bin/computer-use"
  cat >"${root}/bin/curl" <<EOF
#!/usr/bin/env bash
printf 'called %s\n' "\$*" >>"${root}/curl.calls"
exit 22
EOF
  chmod +x "${root}/bin/curl"
  cat >"${root}/bin/cargo" <<'EOF'
#!/usr/bin/env bash
printf 'called %s\n' "$*" >>"${CARGO_CALL_LOG:-/dev/null}"
exit 1
EOF
  chmod +x "${root}/bin/cargo"
}

# A release probe is a curl call too. Only an asset download counts. The
# download URL is either `releases/download/<tag>/<asset>` or
# `releases/latest/download/<asset>`.
downloaded() {
  local root=$1
  [[ -f "${root}/curl.calls" ]] && grep -q "releases/.*download" "${root}/curl.calls"
}

run_setup() {
  local root=$1
  shift
  env PATH="${root}/bin:${PATH}" \
    COMPUTER_USE_INSTALL_DIR="${root}/install" \
    CARGO_CALL_LOG="${root}/cargo.calls" \
    HOME="${root}" \
    "${SETUP}" "$@" >"${root}/setup.out" 2>"${root}/setup.err"
}

# 1. An acceptable version is left alone and nothing is downloaded.
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/setup-test.XXXXXX")
make_sandbox "0.3.1" "${ROOT}"
run_setup "${ROOT}"
if ! downloaded "${ROOT}"; then
  pass "an acceptable version skips the download"
else
  fail "an acceptable version skips the download" "$(cat "${ROOT}/curl.calls")"
fi

# 2. An old version is replaced, so the download is attempted.
ROOT2=$(mktemp -d "${TMPDIR:-/tmp}/setup-test.XXXXXX")
make_sandbox "0.1.0" "${ROOT2}"
run_setup "${ROOT2}"
if downloaded "${ROOT2}"; then
  pass "an old version triggers a download"
else
  fail "an old version triggers a download" "no asset download was attempted"
fi

# 3. The install directory wins over PATH, so a stale PATH binary does not
#    make the script think the install is current.
ROOT3=$(mktemp -d "${TMPDIR:-/tmp}/setup-test.XXXXXX")
make_sandbox "0.1.0" "${ROOT3}"
make_sandbox "0.3.1" "${ROOT3}/install" 2>/dev/null || true
mkdir -p "${ROOT3}/install"
cat >"${ROOT3}/install/computer-use" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  printf 'computer-use 0.3.1\n'
  exit 0
fi
printf '{"ok":true}\n'
EOF
chmod +x "${ROOT3}/install/computer-use"
run_setup "${ROOT3}"
if ! downloaded "${ROOT3}"; then
  pass "the install directory wins over PATH"
else
  fail "the install directory wins over PATH" "an asset download was attempted"
fi

# 4. --force reinstalls even when the version is acceptable.
ROOT4=$(mktemp -d "${TMPDIR:-/tmp}/setup-test.XXXXXX")
make_sandbox "0.3.1" "${ROOT4}"
run_setup "${ROOT4}" --force
if downloaded "${ROOT4}"; then
  pass "--force reinstalls an acceptable version"
else
  fail "--force reinstalls an acceptable version" "no asset download was attempted"
fi

# 5. A pinned version must match exactly.
ROOT5=$(mktemp -d "${TMPDIR:-/tmp}/setup-test.XXXXXX")
make_sandbox "0.3.1" "${ROOT5}"
env PATH="${ROOT5}/bin:${PATH}" \
  COMPUTER_USE_INSTALL_DIR="${ROOT5}/install" \
  HOME="${ROOT5}" \
  COMPUTER_USE_VERSION="0.4.0" \
  "${SETUP}" >"${ROOT5}/setup.out" 2>"${ROOT5}/setup.err"
if downloaded "${ROOT5}"; then
  pass "a pinned version that does not match triggers a download"
else
  fail "a pinned version that does not match triggers a download" "no asset download was attempted"
fi

# 6. A pinned version that matches is left alone.
ROOT6=$(mktemp -d "${TMPDIR:-/tmp}/setup-test.XXXXXX")
make_sandbox "0.3.1" "${ROOT6}"
env PATH="${ROOT6}/bin:${PATH}" \
  COMPUTER_USE_INSTALL_DIR="${ROOT6}/install" \
  HOME="${ROOT6}" \
  COMPUTER_USE_VERSION="0.3.1" \
  "${SETUP}" >"${ROOT6}/setup.out" 2>"${ROOT6}/setup.err"
if ! downloaded "${ROOT6}"; then
  pass "a pinned version that matches is left alone"
else
  fail "a pinned version that matches is left alone" "an asset download was attempted"
fi

# 7. A failed download must not leave a binary behind.
ROOT7=$(mktemp -d "${TMPDIR:-/tmp}/setup-test.XXXXXX")
make_sandbox "0.1.0" "${ROOT7}"
run_setup "${ROOT7}"
if [[ ! -x "${ROOT7}/install/computer-use" ]]; then
  pass "a failed download installs nothing"
else
  fail "a failed download installs nothing" "a binary appeared in the install directory"
fi

# 8. The script exits non-zero when it cannot install an acceptable version.
ROOT8=$(mktemp -d "${TMPDIR:-/tmp}/setup-test.XXXXXX")
make_sandbox "0.1.0" "${ROOT8}"
if ! run_setup "${ROOT8}"; then
  pass "the script exits non-zero when the install fails"
else
  fail "the script exits non-zero when the install fails" "exit code was 0"
fi

rm -rf "${ROOT}" "${ROOT2}" "${ROOT3}" "${ROOT4}" "${ROOT5}" "${ROOT6}" "${ROOT7}" "${ROOT8}"

printf '\n%s passed, %s failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
