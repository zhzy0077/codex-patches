#!/usr/bin/env bash
set -euo pipefail

repository="${UPSTREAM_REPOSITORY:-openai/codex}"
api_url="https://api.github.com/repos/${repository}/releases/latest"
python_bin="${PYTHON_BIN:-}"

if [[ -z "${python_bin}" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    python_bin="python3"
  elif command -v python >/dev/null 2>&1; then
    python_bin="python"
  else
    echo "python3 or python is required to parse the GitHub API response" >&2
    exit 1
  fi
fi

headers=(-H "Accept: application/vnd.github+json")
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

payload="$(curl --fail --show-error --silent --location --retry 3 --retry-delay 2 \
  "${headers[@]}" "${api_url}")"
tag="$("${python_bin}" -c '
import json
import sys

release = json.load(sys.stdin)
tag = release.get("tag_name")
if not isinstance(tag, str) or not tag or tag != tag.strip() or any(
    character.isspace() for character in tag
):
    raise SystemExit("GitHub latest release response has no valid tag_name")
print(tag)
' <<<"${payload}")"

printf '%s\n' "${tag}"
