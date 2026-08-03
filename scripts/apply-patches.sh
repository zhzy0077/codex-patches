#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir=""

usage() {
  cat >&2 <<'EOF'
Usage: apply-patches.sh --source-dir UPSTREAM_CHECKOUT
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-dir)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      source_dir="$2"
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

[[ -d "${source_dir}/.git" ]] || {
  echo "source directory is not a Git checkout: ${source_dir}" >&2
  exit 1
}

patch_files=()
while IFS= read -r patch_file; do
  patch_files+=("${patch_file}")
done < <(
  LC_ALL=C find "${repository_root}/patches" -maxdepth 1 -type f -name '*.patch' -print |
    LC_ALL=C sort
)
(( ${#patch_files[@]} > 0 )) || {
  echo "no patch files found in ${repository_root}/patches" >&2
  exit 1
}

for patch_file in "${patch_files[@]}"; do
  echo "Checking ${patch_file}"
  git -C "${source_dir}" apply --unidiff-zero --check --whitespace=error "${patch_file}"
  echo "Applying ${patch_file}"
  git -C "${source_dir}" apply --unidiff-zero --whitespace=error "${patch_file}"
done
