#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repository="${UPSTREAM_REPOSITORY:-openai/codex}"
tag=""
target=""
source_dir=""
work_dir=""
output_dir=""
binaries=""
bundle="all"
include_bwrap="auto"

usage() {
  cat >&2 <<'EOF'
Usage: build-patched.sh --tag TAG --target TARGET --work-dir DIR --output-dir DIR
                        [--source-dir DIR] [--repository OWNER/REPO]
                        [--binaries "BINARIES"] [--bundle primary|app-server|all]

The source directory may be prepared ahead of time with fetch-upstream.sh and
apply-patches.sh. When omitted, this script fetches and patches the exact tag.
The package archives are produced by the vendored upstream
build-codex-package-archive.sh helper.
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
    --source-dir)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      source_dir="$2"
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
    --bundle)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      bundle="$2"
      shift 2
      ;;
    --include-bwrap)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      include_bwrap="$2"
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
[[ -n "${binaries}" ]] || {
  echo "--binaries is required; use the upstream release matrix" >&2
  exit 2
}
case "${bundle}" in
  primary|app-server|all) ;;
  *) echo "--bundle must be primary, app-server, or all" >&2; exit 2 ;;
esac
case "${include_bwrap}" in
  true|false|auto) ;;
  *) echo "--include-bwrap must be true, false, or auto" >&2; exit 2 ;;
esac

if [[ -z "${source_dir}" ]]; then
  source_dir="${work_dir}/upstream"
  "${repository_root}/scripts/fetch-upstream.sh" \
    --repository "${repository}" --tag "${tag}" --destination "${source_dir}"
  "${repository_root}/scripts/apply-patches.sh" --source-dir "${source_dir}"
fi
[[ -d "${source_dir}/.git" ]] || {
  echo "source directory is not a Git checkout: ${source_dir}" >&2
  exit 1
}

mkdir -p "${work_dir}" "${output_dir}"
runner_temp="${RUNNER_TEMP:-${work_dir}/runner-temp}"
mkdir -p "${runner_temp}"

if [[ "${include_bwrap}" == "auto" ]]; then
  include_bwrap="false"
  [[ "${target}" == *-linux-* ]] && include_bwrap="true"
fi

read -r -a binary_names <<<"${binaries}"
(( ${#binary_names[@]} > 0 )) || { echo "binary list is empty" >&2; exit 2; }
for binary in "${binary_names[@]}"; do
  [[ "${binary}" != -* && "${binary}" != */* ]] || {
    echo "invalid binary name: ${binary}" >&2
    exit 2
  }
done

export CARGO_NET_GIT_FETCH_WITH_CLI="${CARGO_NET_GIT_FETCH_WITH_CLI:-true}"
if [[ "${target}" == "x86_64-pc-windows-msvc" ]]; then
  export LIBSQLITE3_FLAGS="${LIBSQLITE3_FLAGS:-SQLITE_DISABLE_INTRINSIC}"
  export RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=/NODEFAULTLIB:libucrt.lib -C link-arg=/NODEFAULTLIB:ucrt.lib"
fi

export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-${work_dir}/cargo-target}"
manifest="${source_dir}/codex-rs/Cargo.toml"
release_dir="${CARGO_TARGET_DIR}/${target}/release"
mkdir -p "${release_dir}"

if [[ "${include_bwrap}" == "true" ]]; then
  cargo build --manifest-path "${manifest}" --release --target "${target}" --bin bwrap
  bwrap_path="${release_dir}/bwrap"
  [[ -f "${bwrap_path}" ]] || { echo "bwrap was not built: ${bwrap_path}" >&2; exit 1; }
  strip --strip-debug --strip-unneeded "${bwrap_path}"
  bwrap_digest="$(
    python3 - "${bwrap_path}" <<'PY'
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
  [[ "${binary}" == "bwrap" ]] && continue
  build_args+=(--bin "${binary}")
done
cargo build --manifest-path "${manifest}" --release --target "${target}" "${build_args[@]}"

package_script="${repository_root}/vendor/openai-codex/scripts/build-codex-package-archive.sh"
package_args=()
case "${bundle}" in
  primary|app-server) package_args+=("${bundle}") ;;
  all) package_args+=(primary app-server) ;;
esac
for package_bundle in "${package_args[@]}"; do
  GITHUB_WORKSPACE="${source_dir}" RUNNER_TEMP="${runner_temp}" \
    bash "${package_script}" \
      --target "${target}" \
      --bundle "${package_bundle}" \
      --entrypoint-dir "${release_dir}" \
      --archive-dir "${output_dir}"
done

upstream_commit="$(git -C "${source_dir}" rev-parse HEAD)"
{
  printf 'Upstream repository: %s\n' "${repository}"
  printf 'Upstream tag: %s\n' "${tag}"
  printf 'Upstream commit: %s\n' "${upstream_commit}"
  printf 'Patch files:\n'
  for patch_file in "${repository_root}"/patches/*.patch; do
    basename "${patch_file}"
  done | LC_ALL=C sort
  printf 'Release artifacts are unsigned and unnotarized.\n'
} > "${output_dir}/BUILD-METADATA-${target}.txt"

(
  cd "${output_dir}"
  manifest="SHA256SUMS-${target}"
  : > "${manifest}"
  for file in *; do
    [[ "${file}" == "${manifest}" ]] && continue
    if command -v sha256sum >/dev/null 2>&1; then
      sha256sum -- "${file}" >> "${manifest}"
    else
      shasum -a 256 -- "${file}" >> "${manifest}"
    fi
  done
)
