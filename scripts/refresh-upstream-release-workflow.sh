#!/usr/bin/env bash
set -euo pipefail

repository="${UPSTREAM_REPOSITORY:-openai/codex}"
tag=""
output_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../vendor/openai-codex" && pwd)"

usage() {
  cat >&2 <<'EOF'
Usage: refresh-upstream-release-workflow.sh --tag TAG [--repository OWNER/REPO]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      tag="$2"
      shift 2
      ;;
    --repository)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      repository="$2"
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
git check-ref-format "refs/tags/${tag}" >/dev/null

commit="$(
  git ls-remote "https://github.com/${repository}.git" \
    "refs/tags/${tag}^{}" | awk 'NR == 1 { print $1 }'
)"
[[ -n "${commit}" ]] || {
  echo "Unable to resolve ${repository} tag ${tag}" >&2
  exit 1
}

base="https://raw.githubusercontent.com/${repository}/${commit}"
files=(
  .github/workflows/rust-release.yml
  .github/workflows/rust-release-windows.yml
  .github/actions/setup-rusty-v8/action.yml
  .github/scripts/archive-release-symbols-and-strip-binaries.sh
  .github/scripts/build-codex-package-archive.sh
  .github/scripts/install-musl-build-tools.sh
  .github/scripts/rusty_v8_bazel.py
)

mkdir -p "${output_root}/workflows" "${output_root}/actions/setup-rusty-v8" "${output_root}/scripts"
for file in "${files[@]}"; do
  case "${file}" in
    .github/workflows/*) destination="${output_root}/workflows/${file##*/}" ;;
    .github/actions/setup-rusty-v8/*) destination="${output_root}/actions/setup-rusty-v8/${file##*/}" ;;
    .github/scripts/*) destination="${output_root}/scripts/${file##*/}" ;;
  esac
  curl --fail --silent --show-error --location \
    "${base}/${file}" -o "${destination}"
done
chmod +x "${output_root}/scripts/"*.sh

cat > "${output_root}/SOURCE.yaml" <<EOF
repository: ${repository}
tag: ${tag}
commit: ${commit}
retrieved: $(date -u +%F)
files:
  - workflows/rust-release.yml
  - workflows/rust-release-windows.yml
  - actions/setup-rusty-v8/action.yml
  - scripts/archive-release-symbols-and-strip-binaries.sh
  - scripts/build-codex-package-archive.sh
  - scripts/install-musl-build-tools.sh
  - scripts/rusty_v8_bazel.py
EOF
echo "Refreshed ${repository}@${tag} (${commit}) in ${output_root}"
