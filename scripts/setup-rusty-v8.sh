#!/usr/bin/env bash
set -euo pipefail

source_dir=""
target=""
cache_dir=""
env_file=""

usage() {
  cat >&2 <<'EOF'
Usage: setup-rusty-v8.sh --source-dir UPSTREAM_CHECKOUT --target TARGET
                         --cache-dir DIR --env-file FILE
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-dir)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      source_dir="$2"
      shift 2
      ;;
    --target)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      target="$2"
      shift 2
      ;;
    --cache-dir)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      cache_dir="$2"
      shift 2
      ;;
    --env-file)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      env_file="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

[[ -d "${source_dir}" ]] || { echo "upstream source does not exist: ${source_dir}" >&2; exit 1; }
[[ -n "${target}" ]] || { echo "--target is required" >&2; exit 2; }
[[ -n "${cache_dir}" ]] || { echo "--cache-dir is required" >&2; exit 2; }
[[ -n "${env_file}" ]] || { echo "--env-file is required" >&2; exit 2; }

python_bin="${PYTHON_BIN:-}"
if [[ -z "${python_bin}" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    python_bin="python3"
  elif command -v python >/dev/null 2>&1; then
    python_bin="python"
  else
    echo "python3 or python is required to verify V8 artifacts" >&2
    exit 1
  fi
fi

version="$("${python_bin}" "${source_dir}/.github/scripts/rusty_v8_bazel.py" \
  resolved-v8-crate-version)"
artifact_profile="ptrcomp_sandbox_release"
release_url="https://github.com/openai/codex/releases/download/rusty-v8-v${version}"
mkdir -p "${cache_dir}"

if [[ "${target}" == *-pc-windows-msvc ]]; then
  archive_name="rusty_v8_${artifact_profile}_${target}.lib.gz"
else
  archive_name="librusty_v8_${artifact_profile}_${target}.a.gz"
fi
binding_name="src_binding_${artifact_profile}_${target}.rs"
checksums_name="rusty_v8_${artifact_profile}_${target}.sha256"
archive_path="${cache_dir}/${archive_name}"
binding_path="${cache_dir}/${binding_name}"
checksums_path="${cache_dir}/${checksums_name}"

curl --fail --show-error --silent --location --retry 3 --retry-delay 2 \
  "${release_url}/${archive_name}" -o "${archive_path}"
curl --fail --show-error --silent --location --retry 3 --retry-delay 2 \
  "${release_url}/${binding_name}" -o "${binding_path}"
curl --fail --show-error --silent --location --retry 3 --retry-delay 2 \
  "${release_url}/${checksums_name}" -o "${checksums_path}"

"${python_bin}" - "${checksums_path}" "${archive_path}" "${binding_path}" <<'PY'
import hashlib
import pathlib
import sys

manifest, *artifacts = map(pathlib.Path, sys.argv[1:])
expected = {}
for line in manifest.read_text(encoding="utf-8").splitlines():
    fields = line.split()
    if len(fields) != 2:
        raise SystemExit(f"invalid checksum line in {manifest}: {line!r}")
    digest, filename = fields
    if len(digest) != 64 or any(character not in "0123456789abcdef" for character in digest):
        raise SystemExit(f"invalid SHA-256 digest in {manifest}: {digest!r}")
    if filename in expected:
        raise SystemExit(f"duplicate checksum entry in {manifest}: {filename}")
    expected[filename] = digest

if set(expected) != {artifact.name for artifact in artifacts}:
    raise SystemExit(
        f"checksum manifest names do not match downloaded artifacts: "
        f"{sorted(expected)} != {sorted(artifact.name for artifact in artifacts)}"
    )

for artifact in artifacts:
    digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
    if digest != expected[artifact.name]:
        raise SystemExit(f"checksum mismatch for {artifact}")
PY

mkdir -p "$(dirname "${env_file}")"
printf 'RUSTY_V8_ARCHIVE=%s\n' "${archive_path}" > "${env_file}"
printf 'RUSTY_V8_SRC_BINDING_PATH=%s\n' "${binding_path}" >> "${env_file}"
printf 'RUSTY_V8_VERSION=%s\n' "${version}" >> "${env_file}"
