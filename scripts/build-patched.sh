#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repository="${UPSTREAM_REPOSITORY:-openai/codex}"
tag=""
target=""
work_dir=""
output_dir=""
binaries="${CODEX_PRIMARY_BINARIES:-codex codex-code-mode-host codex-responses-api-proxy codex-app-server}"
include_bwrap="${CODEX_INCLUDE_BWRAP:-auto}"

usage() {
  cat >&2 <<'EOF'
Usage: build-patched.sh --tag TAG --target TARGET --work-dir DIR --output-dir DIR
                        [--repository OWNER/REPO] [--binaries "BINARIES"]

The default binary list is:
  codex codex-code-mode-host codex-responses-api-proxy codex-app-server

Pass platform-specific helper binaries with --binaries when needed:
  codex-windows-sandbox-setup codex-command-runner

Linux targets also include bwrap by default because it is bundled by Codex's
primary Linux release.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      tag="$2"
      shift 2
      ;;
    --target)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      target="$2"
      shift 2
      ;;
    --work-dir)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      work_dir="$2"
      shift 2
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      output_dir="$2"
      shift 2
      ;;
    --repository)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      repository="$2"
      shift 2
      ;;
    --binaries)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      binaries="$2"
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

[[ -n "${tag}" ]] || { echo "--tag is required" >&2; exit 2; }
[[ -n "${target}" ]] || { echo "--target is required" >&2; exit 2; }
[[ -n "${work_dir}" ]] || { echo "--work-dir is required" >&2; exit 2; }
[[ -n "${output_dir}" ]] || { echo "--output-dir is required" >&2; exit 2; }

read -r -a binary_names <<<"${binaries}"
(( ${#binary_names[@]} > 0 )) || { echo "binary list is empty" >&2; exit 2; }
for binary in "${binary_names[@]}"; do
  [[ "${binary}" != -* && "${binary}" != */* ]] || {
    echo "invalid binary name: ${binary}" >&2
    exit 2
  }
done

[[ ! -e "${work_dir}" ]] || {
  echo "work directory already exists: ${work_dir}; remove it before rebuilding" >&2
  exit 1
}
mkdir -p "${work_dir}" "${output_dir}"
source_dir="${work_dir}/upstream"

"${repository_root}/scripts/fetch-upstream.sh" \
  --repository "${repository}" --tag "${tag}" --destination "${source_dir}"
"${repository_root}/scripts/apply-patches.sh" --source-dir "${source_dir}"

if [[ "${include_bwrap}" == "auto" ]]; then
  include_bwrap="false"
  [[ "${target}" == *-linux-* ]] && include_bwrap="true"
fi
case "${include_bwrap}" in
  true|false) ;;
  *) echo "CODEX_INCLUDE_BWRAP must be true, false, or auto" >&2; exit 2 ;;
esac

if [[ "${target}" == *-linux-* ]]; then
  linux_env_file="${work_dir}/linux-build.env"
  : > "${linux_env_file}"
  if [[ "${target}" == *-unknown-linux-musl ]]; then
    runner_temp="${work_dir}/runner-temp"
    mkdir -p "${runner_temp}"
    TARGET="${target}" GITHUB_ENV="${linux_env_file}" RUNNER_TEMP="${runner_temp}" \
      bash "${source_dir}/.github/scripts/install-musl-build-tools.sh"
    while IFS= read -r line; do
      [[ "${line}" == *=* ]] || { echo "invalid environment line: ${line}" >&2; exit 1; }
      export "${line}"
    done < "${linux_env_file}"
  fi
fi

v8_env_file="${work_dir}/rusty-v8.env"
"${repository_root}/scripts/setup-rusty-v8.sh" \
  --source-dir "${source_dir}" \
  --target "${target}" \
  --cache-dir "${work_dir}/rusty-v8" \
  --env-file "${v8_env_file}"
while IFS= read -r line; do
  [[ "${line}" == *=* ]] || { echo "invalid environment line: ${line}" >&2; exit 1; }
  export "${line}"
done < "${v8_env_file}"

export CARGO_NET_GIT_FETCH_WITH_CLI="${CARGO_NET_GIT_FETCH_WITH_CLI:-true}"
if [[ "${target}" == "x86_64-pc-windows-msvc" ]]; then
  export LIBSQLITE3_FLAGS="${LIBSQLITE3_FLAGS:-SQLITE_DISABLE_INTRINSIC}"
  export RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=/NODEFAULTLIB:libucrt.lib -C link-arg=ucrt.lib"
fi

cargo_target_dir="${work_dir}/cargo-target"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-${cargo_target_dir}}"
manifest="${source_dir}/codex-rs/Cargo.toml"
release_dir="${CARGO_TARGET_DIR}/${target}/release"
mkdir -p "${release_dir}"

if [[ "${include_bwrap}" == "true" ]]; then
  cargo build --manifest-path "${manifest}" --release --target "${target}" --bin bwrap
  bwrap_path="${release_dir}/bwrap"
  [[ -f "${bwrap_path}" ]] || { echo "bwrap was not built: ${bwrap_path}" >&2; exit 1; }
  strip --strip-debug --strip-unneeded "${bwrap_path}"
  python_bin="${PYTHON_BIN:-}"
  if [[ -z "${python_bin}" ]]; then
    if command -v python3 >/dev/null 2>&1; then
      python_bin="python3"
    elif command -v python >/dev/null 2>&1; then
      python_bin="python"
    else
      echo "python3 or python is required to hash bwrap" >&2
      exit 1
    fi
  fi
  bwrap_digest="$("${python_bin}" - "${bwrap_path}" <<'PY'
import hashlib
import pathlib
import sys

print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())
PY
)"
  export CODEX_BWRAP_SHA256="${bwrap_digest}"
fi

build_args=()
for binary in "${binary_names[@]}"; do
  build_args+=(--bin "${binary}")
done
cargo build --manifest-path "${manifest}" --release --target "${target}" "${build_args[@]}"

stage_dir="${work_dir}/stage/${target}"
mkdir -p "${stage_dir}"
all_binaries=("${binary_names[@]}")
if [[ "${include_bwrap}" == "true" ]]; then
  all_binaries+=(bwrap)
fi
for binary in "${all_binaries[@]}"; do
  suffix=""
  [[ "${target}" == *-windows-* ]] && suffix=".exe"
  binary_path="${release_dir}/${binary}${suffix}"
  [[ -f "${binary_path}" ]] || { echo "missing built binary: ${binary_path}" >&2; exit 1; }
  cp "${binary_path}" "${stage_dir}/${binary}${suffix}"
done

cat > "${stage_dir}/BUILD-METADATA.txt" <<EOF
Upstream repository: ${repository}
Upstream tag: ${tag}
Upstream commit: $(git -C "${source_dir}" rev-parse HEAD)
Patch files:
$(for patch_file in "${repository_root}"/patches/*.patch; do basename "${patch_file}"; done | LC_ALL=C sort)
EOF

python_bin="${PYTHON_BIN:-}"
if [[ -z "${python_bin}" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    python_bin="python3"
  elif command -v python >/dev/null 2>&1; then
    python_bin="python"
  else
    echo "python3 or python is required for packaging" >&2
    exit 1
  fi
fi
"${python_bin}" "${repository_root}/scripts/package-artifacts.py" \
  --stage-dir "${stage_dir}" --target "${target}" --output-dir "${output_dir}"
