#!/usr/bin/env bash
# Download the LLM GGUF declared in scripts/llm-gguf.lock into
# Volocal/Resources/LLM/ and verify its SHA-256.
#
# Xcode runs this as a pre-build phase (see project.yml) before Copy
# Bundle Resources, so the file is inside the app bundle and covered
# by code signing. A matching file on disk is left untouched.
#
#   ./scripts/fetch_llm_gguf.sh           # fetch if needed
#   ./scripts/fetch_llm_gguf.sh --check   # lockfile + ModelRegistry only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -n "${SRCROOT:-}" ]]; then
  ROOT="${SRCROOT}"
fi

LOCK="${ROOT}/scripts/llm-gguf.lock"
DEST_DIR="${ROOT}/Volocal/Resources/LLM"
REGISTRY="${ROOT}/Volocal/Models/ModelRegistry.swift"

if [[ ! -f "${LOCK}" ]]; then
  echo "error: missing ${LOCK}" >&2
  exit 1
fi

filename=""
url=""
sha256=""
bytes=""
while IFS= read -r line || [[ -n "${line}" ]]; do
  case "${line}" in
    ''|\#*) continue ;;
  esac
  key="${line%%=*}"
  value="${line#*=}"
  case "${key}" in
    filename) filename="${value}" ;;
    url) url="${value}" ;;
    sha256) sha256="${value}" ;;
    bytes) bytes="${value}" ;;
    *) echo "error: unknown key '${key}' in ${LOCK}" >&2; exit 1 ;;
  esac
done < "${LOCK}"

if [[ -z "${filename}" || -z "${url}" || -z "${sha256}" || -z "${bytes}" ]]; then
  echo "error: ${LOCK} must set filename, url, sha256, and bytes" >&2
  exit 1
fi

if [[ ! "${sha256}" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "error: sha256 in ${LOCK} is not 64 hex characters" >&2
  exit 1
fi
sha256="$(printf '%s' "${sha256}" | tr '[:upper:]' '[:lower:]')"

if [[ ! -f "${REGISTRY}" ]]; then
  echo "error: missing ${REGISTRY}" >&2
  exit 1
fi
if ! grep -q "static let llmFilename = \"${filename}\"" "${REGISTRY}"; then
  echo "error: ModelRegistry.llmFilename is not \"${filename}\"" >&2
  echo "       keep Volocal/Models/ModelRegistry.swift in sync with scripts/llm-gguf.lock" >&2
  exit 1
fi

if [[ "${1:-}" == "--check" ]]; then
  echo "llm-gguf.lock ok: ${filename} (${bytes} bytes)"
  exit 0
fi

mkdir -p "${DEST_DIR}"
dest="${DEST_DIR}/${filename}"

file_size() {
  if stat -c%s "$1" >/dev/null 2>&1; then
    stat -c%s "$1"
  else
    stat -f%z "$1"
  fi
}

file_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

if [[ -f "${dest}" ]]; then
  actual_bytes="$(file_size "${dest}")"
  if [[ "${actual_bytes}" == "${bytes}" ]]; then
    actual_sha="$(file_sha256 "${dest}")"
    if [[ "${actual_sha}" == "${sha256}" ]]; then
      echo "Bundled LLM already present: ${filename}"
      exit 0
    fi
    echo "warning: ${filename} checksum mismatch (${actual_sha}); re-downloading" >&2
  else
    echo "warning: ${filename} size ${actual_bytes} != ${bytes}; re-downloading" >&2
  fi
  rm -f "${dest}"
fi

tmp="${DEST_DIR}/.${filename}.partial"
rm -f "${tmp}"
trap 'rm -f "${tmp}"' EXIT

echo "Downloading ${filename}"
echo "  ${url}"
curl --fail --location --retry 5 --retry-delay 2 --output "${tmp}" "${url}"

actual_bytes="$(file_size "${tmp}")"
if [[ "${actual_bytes}" != "${bytes}" ]]; then
  echo "error: downloaded ${actual_bytes} bytes, expected ${bytes}" >&2
  exit 1
fi

actual_sha="$(file_sha256 "${tmp}")"
if [[ "${actual_sha}" != "${sha256}" ]]; then
  echo "error: SHA-256 mismatch" >&2
  echo "  expected ${sha256}" >&2
  echo "  actual   ${actual_sha}" >&2
  exit 1
fi

mv "${tmp}" "${dest}"
trap - EXIT
echo "Bundled LLM ready: ${dest}"
