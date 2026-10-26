#!/usr/bin/env bash
# Download the speech models declared in scripts/audio-models.lock into
# Volocal/Resources/Audio/ and verify each SHA-256.
#
# Xcode runs this as a pre-build phase (see project.yml) before Copy
# Bundle Resources. A file that already matches size and checksum is
# left untouched. Zero-byte files are created locally because Hugging
# Face often returns an error for empty blobs.
#
#   ./scripts/fetch_audio_models.sh           # fetch if needed
#   ./scripts/fetch_audio_models.sh --check   # lockfile + ModelRegistry only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -n "${SRCROOT:-}" ]]; then
  ROOT="${SRCROOT}"
fi

LOCK="${ROOT}/scripts/audio-models.lock"
DEST_ROOT="${ROOT}/Volocal/Resources/Audio"
REGISTRY="${ROOT}/Volocal/Models/ModelRegistry.swift"

if [[ ! -f "${LOCK}" ]]; then
  echo "error: missing ${LOCK}" >&2
  exit 1
fi

if [[ ! -f "${REGISTRY}" ]]; then
  echo "error: missing ${REGISTRY}" >&2
  exit 1
fi

if ! grep -q 'static let parakeetBundleRelativePath = "Audio/STT/parakeet-eou-streaming/320ms"' "${REGISTRY}"; then
  echo "error: ModelRegistry.parakeetBundleRelativePath is out of sync with scripts/audio-models.lock" >&2
  exit 1
fi
if ! grep -q 'static let pocketTtsBundleRelativePath = "Audio/TTS"' "${REGISTRY}"; then
  echo "error: ModelRegistry.pocketTtsBundleRelativePath is out of sync with scripts/audio-models.lock" >&2
  exit 1
fi

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

declare -a DEST_LIST=()
declare -a URL_LIST=()
declare -a SHA_LIST=()
declare -a BYTE_LIST=()

flush_record() {
  if [[ -z "${dest}" && -z "${url}" && -z "${sha256}" && -z "${bytes}" ]]; then
    return 0
  fi
  if [[ -z "${dest}" || -z "${sha256}" || -z "${bytes}" ]]; then
    echo "error: incomplete record in ${LOCK} (dest=${dest:-})" >&2
    exit 1
  fi
  if [[ "${bytes}" != "0" && -z "${url}" ]]; then
    echo "error: ${dest} is missing a url" >&2
    exit 1
  fi
  if [[ ! "${sha256}" =~ ^[0-9a-fA-F]{64}$ ]]; then
    echo "error: sha256 for ${dest} is not 64 hex characters" >&2
    exit 1
  fi
  if [[ ! "${bytes}" =~ ^[0-9]+$ ]]; then
    echo "error: bytes for ${dest} is not an integer" >&2
    exit 1
  fi
  case "${dest}" in
    /*|../*|*/../*|*/..|*..*)
      echo "error: unsafe dest path ${dest}" >&2
      exit 1
      ;;
  esac
  DEST_LIST+=("${dest}")
  URL_LIST+=("${url}")
  SHA_LIST+=("$(printf '%s' "${sha256}" | tr '[:upper:]' '[:lower:]')")
  BYTE_LIST+=("${bytes}")
  dest=""
  url=""
  sha256=""
  bytes=""
}

dest=""
url=""
sha256=""
bytes=""
while IFS= read -r line || [[ -n "${line}" ]]; do
  case "${line}" in
    ''|\#*)
      flush_record
      continue
      ;;
  esac
  key="${line%%=*}"
  value="${line#*=}"
  case "${key}" in
    dest) dest="${value}" ;;
    url) url="${value}" ;;
    sha256) sha256="${value}" ;;
    bytes) bytes="${value}" ;;
    *) echo "error: unknown key '${key}' in ${LOCK}" >&2; exit 1 ;;
  esac
done < "${LOCK}"
flush_record

count="${#DEST_LIST[@]}"
if [[ "${count}" -eq 0 ]]; then
  echo "error: ${LOCK} has no file records" >&2
  exit 1
fi

require_dest() {
  local needle="$1"
  local i
  for ((i = 0; i < count; i++)); do
    if [[ "${DEST_LIST[$i]}" == "${needle}" ]]; then
      return 0
    fi
  done
  echo "error: ${LOCK} is missing ${needle}" >&2
  exit 1
}

require_dest "STT/parakeet-eou-streaming/320ms/vocab.json"
require_dest "STT/parakeet-eou-streaming/320ms/streaming_encoder.mlmodelc/weights/weight.bin"
require_dest "STT/parakeet-eou-streaming/320ms/decoder.mlmodelc/weights/weight.bin"
require_dest "STT/parakeet-eou-streaming/320ms/joint_decision.mlmodelc/weights/weight.bin"
require_dest "TTS/Models/pocket-tts/cond_step.mlmodelc/weights/weight.bin"
require_dest "TTS/Models/pocket-tts/flowlm_step.mlmodelc/weights/weight.bin"
require_dest "TTS/Models/pocket-tts/flow_decoder.mlmodelc/weights/weight.bin"
require_dest "TTS/Models/pocket-tts/mimi_decoder_v2.mlmodelc/weights/weight.bin"
require_dest "TTS/Models/pocket-tts/constants_bin/tokenizer.model"
require_dest "TTS/Models/pocket-tts/constants_bin/bos_emb.bin"
require_dest "TTS/Models/pocket-tts/constants_bin/text_embed_table.bin"
require_dest "TTS/Models/pocket-tts/constants_bin/manifest.json"
require_dest "TTS/Models/pocket-tts/constants_bin/alba_audio_prompt.bin"
require_dest "TTS/Models/pocket-tts/constants_bin/marius_audio_prompt.bin"
require_dest "TTS/Models/pocket-tts/constants_bin/javert_audio_prompt.bin"
require_dest "TTS/Models/pocket-tts/constants_bin/jean_audio_prompt.bin"
require_dest "TTS/Models/pocket-tts/constants_bin/fantine_audio_prompt.bin"
require_dest "TTS/Models/pocket-tts/constants_bin/cosette_audio_prompt.bin"
require_dest "TTS/Models/pocket-tts/constants_bin/eponine_audio_prompt.bin"
require_dest "TTS/Models/pocket-tts/constants_bin/azelma_audio_prompt.bin"

total_bytes=0
for ((i = 0; i < count; i++)); do
  total_bytes=$((total_bytes + BYTE_LIST[i]))
done

if [[ "${1:-}" == "--check" ]]; then
  echo "audio-models.lock ok: ${count} files, ${total_bytes} bytes"
  exit 0
fi

mkdir -p "${DEST_ROOT}"

for ((i = 0; i < count; i++)); do
  rel="${DEST_LIST[$i]}"
  url="${URL_LIST[$i]}"
  sha256="${SHA_LIST[$i]}"
  bytes="${BYTE_LIST[$i]}"
  dest="${DEST_ROOT}/${rel}"
  mkdir -p "$(dirname "${dest}")"

  if [[ -f "${dest}" ]]; then
    actual_bytes="$(file_size "${dest}")"
    if [[ "${actual_bytes}" == "${bytes}" ]]; then
      actual_sha="$(file_sha256 "${dest}")"
      if [[ "${actual_sha}" == "${sha256}" ]]; then
        continue
      fi
      echo "warning: ${rel} checksum mismatch; re-fetching" >&2
    else
      echo "warning: ${rel} size ${actual_bytes} != ${bytes}; re-fetching" >&2
    fi
    rm -f "${dest}"
  fi

  if [[ "${bytes}" == "0" ]]; then
    : > "${dest}"
  else
    tmp="${dest}.partial"
    rm -f "${tmp}"
    echo "Downloading ${rel}"
    curl --fail --location --retry 5 --retry-delay 2 --silent --show-error --output "${tmp}" "${url}"
    mv "${tmp}" "${dest}"
  fi

  actual_bytes="$(file_size "${dest}")"
  if [[ "${actual_bytes}" != "${bytes}" ]]; then
    echo "error: ${rel} is ${actual_bytes} bytes, expected ${bytes}" >&2
    rm -f "${dest}"
    exit 1
  fi
  actual_sha="$(file_sha256 "${dest}")"
  if [[ "${actual_sha}" != "${sha256}" ]]; then
    echo "error: SHA-256 mismatch for ${rel}" >&2
    echo "  expected ${sha256}" >&2
    echo "  actual   ${actual_sha}" >&2
    rm -f "${dest}"
    exit 1
  fi
done

echo "Bundled speech models ready: ${count} files, ${total_bytes} bytes"
