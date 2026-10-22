#!/usr/bin/env bash
# Install the computer-use CLI into ~/.local/bin.
# Idempotent and quiet. See --help.
set -euo pipefail

PREFERRED_VERSION="0.3.2"
REPO="lindoelio/computer-use"
REPO_URL="https://github.com/${REPO}"
API_URL="https://api.github.com/repos/${REPO}"
INSTALL_DIR="${COMPUTER_USE_INSTALL_DIR:-${HOME}/.local/bin}"
BINARY_NAME="computer-use"
APP_NAME="Computer Use.app"
APP_DIR="${HOME}/Applications"

VERBOSE=0
WITH_LAYA=0
FORCE=0
ASSET_NAME=""
APP_ASSET_NAME=""
TMP_ROOT=""
RESOLVED_TAG=""

usage() {
  cat <<'EOF'
Usage: setup.sh [--with-laya] [--force] [--verbose] [--help]

Install the computer-use CLI into ~/.local/bin.

  --with-laya   Also run install-laya.sh (optional and experimental).
  --force       Reinstall even when an acceptable version is already present.
  --verbose     Print progress to stderr.
  --help        Show this help.

Environment:
  COMPUTER_USE_VERSION      Release tag to pin, for example v0.3.2 or 0.3.2.
                            Default: v0.3.2 when that release exists, otherwise
                            the latest GitHub release.
  COMPUTER_USE_INSTALL_DIR  Install directory. Default: ~/.local/bin.

Release selection:
  v0.3.2 is preferred. The script probes the GitHub releases API (no auth
  required) and installs v0.3.2 when it is published. When it is not, the
  script falls back to the latest published release instead of failing.

If computer-use is already in the install directory or on PATH at an
acceptable version, the download is skipped. Acceptable means >= 0.3.2, or
exactly COMPUTER_USE_VERSION when that variable is set. A binary older than
v0.3.2 is replaced, because the tree, element targeting, batch, browser, and
--state-diff surface needs it.

Supported release assets:
  darwin arm64  -> computer-use-macos-arm64.tar.gz
                   computer-use-macos-arm64-app-unsigned.zip
  linux x86_64  -> computer-use-linux-x64.tar.gz

On macOS the app bundle is preferred when the release ships one. It is
extracted to ~/Applications and the install directory holds a symlink to it,
so the binary keeps a stable bundle id and its macOS permission grant does
not depend on which program started it. The bundle is ad-hoc signed and not
notarized.

Other systems try: cargo install computer-use --locked
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
      --verbose|-v)
        VERBOSE=1
        shift
        ;;
      --with-laya)
        WITH_LAYA=1
        shift
        ;;
      --force)
        FORCE=1
        shift
        ;;
      *)
        die "unknown argument: $1 (try --help)"
        ;;
    esac
  done
}

script_dir() {
  local source dir
  source=${BASH_SOURCE[0]}
  while [[ -L "${source}" ]]; do
    dir=$(dirname -- "${source}")
    dir=$(CDPATH='' cd -- "${dir}" && pwd) || exit 1
    source=$(readlink "${source}")
    case "${source}" in
      /*) ;;
      *) source="${dir}/${source}" ;;
    esac
  done
  dir=$(dirname -- "${source}")
  (CDPATH='' cd -- "${dir}" && pwd -P)
}

normalize_version() {
  local raw=$1
  raw=${raw##* }
  raw=${raw#v}
  raw=${raw%%[^0-9.]*}
  printf '%s\n' "${raw}"
}

version_ge() {
  local left right i ln rn max
  local -a la=()
  local -a ra=()
  left=$(normalize_version "$1")
  right=$(normalize_version "$2")
  IFS='.' read -r -a la <<< "${left}" || true
  IFS='.' read -r -a ra <<< "${right}" || true
  max=${#la[@]}
  if [[ ${#ra[@]} -gt ${max} ]]; then
    max=${#ra[@]}
  fi
  i=0
  while [[ ${i} -lt ${max} ]]; do
    ln=0
    rn=0
    if [[ ${i} -lt ${#la[@]} ]]; then
      ln=${la[${i}]}
    fi
    if [[ ${i} -lt ${#ra[@]} ]]; then
      rn=${ra[${i}]}
    fi
    ln=${ln%%[^0-9]*}
    rn=${rn%%[^0-9]*}
    ln=${ln:-0}
    rn=${rn:-0}
    if [[ $((10#${ln})) -gt $((10#${rn})) ]]; then
      return 0
    fi
    if [[ $((10#${ln})) -lt $((10#${rn})) ]]; then
      return 1
    fi
    i=$((i + 1))
  done
  return 0
}

version_is_acceptable() {
  local ver=$1
  local want
  if [[ -z "${ver}" ]]; then
    return 1
  fi
  if [[ -n "${COMPUTER_USE_VERSION:-}" ]]; then
    want=$(normalize_version "${COMPUTER_USE_VERSION}")
    [[ "${ver}" == "${want}" ]]
    return
  fi
  # The preferred version is the floor: an older binary does not have the
  # tree, element targeting, batch, browser, or --state-diff surface, and
  # leaving it in place is what strands an agent on a dead command.
  version_ge "${ver}" "${PREFERRED_VERSION}"
}

installed_version() {
  local bin=$1
  local out
  if ! out=$(run_timeout 10 "${bin}" --version 2>/dev/null); then
    return 1
  fi
  out=${out%%$'\n'*}
  normalize_version "${out}"
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
  # The install directory wins over PATH. A stale binary earlier on PATH
  # would otherwise shadow the one this script manages.
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

detect_target() {
  local os arch
  os=$(uname -s)
  arch=$(uname -m)
  case "${os}:${arch}" in
    Darwin:arm64)
      ASSET_NAME="computer-use-macos-arm64.tar.gz"
      APP_ASSET_NAME="computer-use-macos-arm64-app-unsigned.zip"
      ;;
    Darwin:x86_64)
      ASSET_NAME=""
      APP_ASSET_NAME=""
      warn "no release asset for macOS on Intel. The published assets are arm64 only."
      return 1
      ;;
    Linux:x86_64|Linux:amd64)
      ASSET_NAME="computer-use-linux-x64.tar.gz"
      ;;
    Linux:aarch64|Linux:arm64)
      ASSET_NAME=""
      warn "no release asset for Linux on arm64. The published assets are x86_64 only."
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

release_base() {
  local tag
  if [[ -n "${COMPUTER_USE_VERSION:-}" ]]; then
    tag=${COMPUTER_USE_VERSION}
    case "${tag}" in
      v*) ;;
      *) tag="v${tag}" ;;
    esac
    printf '%s\n' "${REPO_URL}/releases/download/${tag}"
  elif [[ -n "${RESOLVED_TAG}" ]]; then
    printf '%s\n' "${REPO_URL}/releases/download/${RESOLVED_TAG}"
  else
    printf '%s\n' "${REPO_URL}/releases/latest/download"
  fi
}

# Probe the GitHub releases API for one tag. Public endpoint, no auth.
# Prints the tag on a 200 and returns 1 on anything else. A missing release,
# a rate limit, or no network all look the same to the caller: fall back.
probe_release_tag() {
  local tag=$1 code
  if ! command -v curl >/dev/null 2>&1; then
    return 1
  fi
  if ! code=$(curl -fsSL -o /dev/null -w '%{http_code}' --max-time 15 \
    -H 'Accept: application/vnd.github+json' \
    "${API_URL}/releases/tags/${tag}" 2>/dev/null); then
    return 1
  fi
  if [[ "${code}" != "200" ]]; then
    return 1
  fi
  printf '%s\n' "${tag}"
}

resolve_release_tag() {
  local tag
  if [[ -n "${COMPUTER_USE_VERSION:-}" || -n "${RESOLVED_TAG}" ]]; then
    return 0
  fi
  if tag=$(probe_release_tag "v${PREFERRED_VERSION}"); then
    RESOLVED_TAG="${tag}"
    log "release ${RESOLVED_TAG} is published; installing it"
    return 0
  fi
  log "release v${PREFERRED_VERSION} is not published yet; using the latest release"
}

warn_if_older_than_preferred() {
  local ver=$1
  if [[ -z "${ver}" ]] || version_ge "${ver}" "${PREFERRED_VERSION}"; then
    return 0
  fi
  warn "computer-use ${ver} is installed at a version older than ${PREFERRED_VERSION}. The tree, element targeting, batch, browser, and --state-diff surface need ${PREFERRED_VERSION}. Run scripts/setup.sh --force, or cargo install computer-use --locked."
}

download_to() {
  local url=$1 dest=$2
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 --retry-delay 1 -o "${dest}" "${url}"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "${dest}" "${url}"
  else
    return 1
  fi
}

expected_hash() {
  local sumfile=$1
  awk '
    BEGIN { found = 0 }
    {
      gsub(/\r/, "")
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^[0-9A-Fa-f]{64}$/) {
          print $i
          found = 1
          exit 0
        }
      }
    }
    END {
      if (found == 0) exit 1
    }
  ' "${sumfile}"
}

verify_archive() {
  local archive=$1 sumfile=$2
  local dir base expected canon
  dir=$(dirname -- "${archive}")
  base=$(basename -- "${archive}")
  if ! expected=$(expected_hash "${sumfile}"); then
    warn "checksum file has no sha256"
    return 1
  fi
  expected=$(printf '%s' "${expected}" | tr '[:upper:]' '[:lower:]')
  canon="${dir}/${base}.sha256"
  printf '%s  %s\n' "${expected}" "${base}" > "${canon}"
  if command -v sha256sum >/dev/null 2>&1; then
    if [[ "${VERBOSE}" -eq 1 ]]; then
      (cd "${dir}" && sha256sum -c "${base}.sha256") || return 1
    else
      (cd "${dir}" && sha256sum -c "${base}.sha256" >/dev/null) || return 1
    fi
  elif command -v shasum >/dev/null 2>&1; then
    if [[ "${VERBOSE}" -eq 1 ]]; then
      (cd "${dir}" && shasum -a 256 -c "${base}.sha256") || return 1
    else
      (cd "${dir}" && shasum -a 256 -c "${base}.sha256" >/dev/null) || return 1
    fi
  else
    warn "neither sha256sum nor shasum is available"
    return 1
  fi
}

pick_binary() {
  local root=$1
  local candidate found
  candidate="${root}/${BINARY_NAME}"
  if [[ -f "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi
  found=""
  while IFS= read -r candidate; do
    if [[ -n "${candidate}" && -f "${candidate}" ]]; then
      found=${candidate}
      break
    fi
  done < <(find "${root}" -type f -name "${BINARY_NAME}")
  if [[ -z "${found}" ]]; then
    return 1
  fi
  printf '%s\n' "${found}"
}

install_binary() {
  local src=$1
  mkdir -p "${INSTALL_DIR}" || return 1
  # `mv` replaces the file in one step. `cp -f` over a running binary fails
  # with ETXTBSY on Linux.
  if ! mv -f "${src}" "${INSTALL_DIR}/${BINARY_NAME}.new" 2>/dev/null; then
    cp -f "${src}" "${INSTALL_DIR}/${BINARY_NAME}.new" || return 1
  fi
  chmod 755 "${INSTALL_DIR}/${BINARY_NAME}.new" || return 1
  if [[ "$(uname -s)" == "Darwin" ]]; then
    xattr -d com.apple.quarantine "${INSTALL_DIR}/${BINARY_NAME}.new" 2>/dev/null || true
  fi
  mv -f "${INSTALL_DIR}/${BINARY_NAME}.new" "${INSTALL_DIR}/${BINARY_NAME}" || return 1
}

# Extract the macOS app bundle and point the install directory at it. The
# bundle carries a stable bundle id, so the macOS permission grant belongs to
# the app and not to whichever program happened to start the binary.
install_app_bundle() {
  local base=$1 archive sumfile extract appdir binary target
  archive="${TMP_ROOT}/${APP_ASSET_NAME}"
  sumfile="${TMP_ROOT}/${APP_ASSET_NAME}.sha256.download"
  log "downloading ${base}/${APP_ASSET_NAME}"
  download_to "${base}/${APP_ASSET_NAME}" "${archive}" || return 1
  download_to "${base}/${APP_ASSET_NAME}.sha256" "${sumfile}" || return 1
  verify_archive "${archive}" "${sumfile}" || return 1
  extract="${TMP_ROOT}/app"
  mkdir -p "${extract}" || return 1
  unzip -q -o "${archive}" -d "${extract}" || return 1
  appdir=$(find "${extract}" -maxdepth 2 -name "${APP_NAME}" -type d | head -n 1)
  if [[ -z "${appdir}" ]]; then
    warn "the app archive did not contain ${APP_NAME}"
    return 1
  fi
  binary="${appdir}/Contents/MacOS/${BINARY_NAME}"
  if [[ ! -x "${binary}" ]]; then
    warn "the app bundle did not contain an executable at ${binary}"
    return 1
  fi
  mkdir -p "${APP_DIR}" || return 1
  rm -rf "${APP_DIR:?}/${APP_NAME}" || return 1
  mv "${appdir}" "${APP_DIR}/${APP_NAME}" || return 1
  xattr -d com.apple.quarantine "${APP_DIR}/${APP_NAME}" 2>/dev/null || true
  mkdir -p "${INSTALL_DIR}" || return 1
  target="${INSTALL_DIR}/${BINARY_NAME}"
  rm -f "${target}" || return 1
  ln -sfn "${APP_DIR}/${APP_NAME}/Contents/MacOS/${BINARY_NAME}" "${target}" || return 1
  log "installed ${APP_NAME} in ${APP_DIR} and linked ${target}"
}

warn_if_dir_not_on_path() {
  local dir=$1
  case ":${PATH}:" in
    *":${dir}:"*) ;;
    *)
      warn "${dir} is not on PATH. Add it with: export PATH=\"${dir}:\$PATH\""
      ;;
  esac
}

install_release() {
  local base archive sumfile extract src
  if ! detect_target; then
    return 1
  fi
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    warn "curl or wget is required to download a release"
    return 1
  fi
  base=$(release_base)
  if [[ -n "${APP_ASSET_NAME}" ]]; then
    if install_app_bundle "${base}"; then
      return 0
    fi
    warn "the app bundle could not be installed; falling back to the plain binary"
  fi
  archive="${TMP_ROOT}/${ASSET_NAME}"
  sumfile="${TMP_ROOT}/${ASSET_NAME}.sha256.download"
  log "downloading ${base}/${ASSET_NAME}"
  download_to "${base}/${ASSET_NAME}" "${archive}" || return 1
  download_to "${base}/${ASSET_NAME}.sha256" "${sumfile}" || return 1
  verify_archive "${archive}" "${sumfile}" || return 1
  extract="${TMP_ROOT}/extract"
  mkdir -p "${extract}" || return 1
  tar -xzf "${archive}" -C "${extract}" || return 1
  src=$(pick_binary "${extract}") || return 1
  install_binary "${src}" || return 1
}

cargo_install() {
  local ver
  local -a args
  local logf
  if ! command -v cargo >/dev/null 2>&1; then
    return 1
  fi
  args=(install computer-use --locked)
  if [[ -n "${COMPUTER_USE_VERSION:-}" ]]; then
    ver=$(normalize_version "${COMPUTER_USE_VERSION}")
    args+=(--version "${ver}")
  fi
  log "running cargo ${args[*]}"
  logf="${TMP_ROOT}/cargo-install.log"
  if [[ "${VERBOSE}" -eq 1 ]]; then
    cargo "${args[@]}" || return 1
  else
    if ! cargo "${args[@]}" >"${logf}" 2>&1; then
      cat "${logf}" >&2
      return 1
    fi
  fi
}

print_manual_install() {
  cat >&2 <<EOF
Could not install the computer-use CLI.

Download a release from:
  ${REPO_URL}/releases
Assets: computer-use-linux-x64.tar.gz, computer-use-macos-arm64.tar.gz,
computer-use-windows-x64.zip. Each has a matching .sha256 file.

Or, with Rust 1.91 or newer:
  cargo install computer-use --locked

Put the computer-use binary on PATH, for example ${INSTALL_DIR}.
EOF
}

do_install() {
  if detect_target; then
    if install_release; then
      return 0
    fi
    warn "release download or checksum failed; trying cargo install computer-use --locked"
  else
    warn "no release asset for $(uname -s) $(uname -m); trying cargo install computer-use --locked"
  fi
  if cargo_install; then
    return 0
  fi
  print_manual_install
  return 1
}

run_laya() {
  local dir script
  local -a args
  dir=$(script_dir) || return 0
  script="${dir}/install-laya.sh"
  if [[ ! -f "${script}" ]]; then
    warn "install-laya.sh was not found; skipping Laya"
    return 0
  fi
  args=(--yes)
  if [[ "${VERBOSE}" -eq 1 ]]; then
    args+=(--verbose)
  fi
  if ! bash "${script}" "${args[@]}"; then
    warn "Laya install did not succeed; continuing without it"
  fi
}

run_check_deps() {
  local dir script
  dir=$(script_dir) || return 0
  script="${dir}/check-deps.sh"
  if [[ ! -f "${script}" ]]; then
    warn "check-deps.sh was not found"
    return 0
  fi
  bash "${script}" || true
}

main() {
  local bin ver need_install status
  parse_args "$@"
  TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/smart-computer-use.XXXXXX")
  trap cleanup EXIT

  resolve_release_tag

  need_install=1
  status=0
  if [[ "${FORCE}" -eq 1 ]]; then
    log "forced reinstall requested"
  elif bin=$(find_binary); then
    if ver=$(installed_version "${bin}"); then
      if version_is_acceptable "${ver}"; then
        log "computer-use ${ver} already installed at ${bin}"
        need_install=0
      else
        log "computer-use ${ver:-unknown} at ${bin} is not an acceptable version; reinstalling"
      fi
    else
      log "found ${bin} but could not read its version; reinstalling"
    fi
  fi

  if [[ "${need_install}" -eq 1 ]]; then
    if ! do_install; then
      status=1
    else
      hash -r || true
      printf 'installed computer-use into %s or cargo bin\n' "${INSTALL_DIR}"
    fi
  fi

  hash -r || true
  if bin=$(find_binary); then
    warn_if_dir_not_on_path "$(dirname -- "${bin}")"
    if ver=$(installed_version "${bin}"); then
      if ! version_is_acceptable "${ver}"; then
        warn "computer-use ${ver} at ${bin} is still not an acceptable version"
        status=1
      else
        warn_if_older_than_preferred "${ver}"
      fi
    fi
  else
    status=1
  fi

  if [[ "${WITH_LAYA}" -eq 1 ]]; then
    run_laya
  fi
  run_check_deps
  cleanup
  exit "${status}"
}

main "$@"
