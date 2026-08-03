#!/usr/bin/env bash
set -euo pipefail

repository="${UPSTREAM_REPOSITORY:-openai/codex}"
tag=""
destination=""

usage() {
  cat >&2 <<'EOF'
Usage: fetch-upstream.sh --tag TAG --destination DIR [--repository OWNER/REPO]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      tag="$2"
      shift 2
      ;;
    --destination)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      destination="$2"
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
[[ -n "${destination}" ]] || { echo "--destination is required" >&2; exit 2; }
[[ "${tag}" != *[[:space:]]* ]] || { echo "tag must not contain whitespace" >&2; exit 2; }
git check-ref-format "refs/tags/${tag}" >/dev/null
[[ ! -e "${destination}" ]] || {
  echo "destination already exists: ${destination}; remove it before fetching" >&2
  exit 1
}

mkdir -p "$(dirname "${destination}")"
git clone --filter=blob:none --no-checkout --no-tags --depth=1 \
  "https://github.com/${repository}.git" "${destination}"
git -C "${destination}" fetch --depth=1 origin \
  "refs/tags/${tag}:refs/tags/${tag}"
git -C "${destination}" checkout --detach "refs/tags/${tag}^{commit}"

expected_commit="$(git -C "${destination}" rev-parse "refs/tags/${tag}^{commit}")"
actual_commit="$(git -C "${destination}" rev-parse HEAD)"
[[ "${expected_commit}" == "${actual_commit}" ]] || {
  echo "checked out commit does not match tag ${tag}" >&2
  exit 1
}

printf 'repository=%s\n' "${repository}"
printf 'tag=%s\n' "${tag}"
printf 'commit=%s\n' "${actual_commit}"
printf 'source=%s\n' "${destination}"
