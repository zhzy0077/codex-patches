# Patched Codex builds

This repository applies a small, reviewable patch set to tagged releases of
[openai/codex](https://github.com/openai/codex). The current patch allows a
provider that advertises GPT-5.6 Responses Lite hosted tools to receive hosted
`web_search` in `/responses`. Guardian-reviewer sessions remain excluded, and
the standalone `/alpha/search` path is unchanged.

## Releases and usage

The scheduled workflow runs daily and can also be started with
`workflow_dispatch`. It reads the latest upstream GitHub release, builds it only
when the corresponding `UPSTREAM_TAG-patched.1` release does not already exist,
and publishes four unsigned platform artifacts containing the same executable
families as the upstream release:

- Linux x86_64 (`x86_64-unknown-linux-musl`)
- macOS arm64 (`aarch64-apple-darwin`)
- macOS x86_64 (`x86_64-apple-darwin`)
- Windows x86_64 (`x86_64-pc-windows-msvc`)

Extract the platform archive from the matching GitHub release and put
`codex` (or `codex.exe`) on `PATH`. Archives also contain `codex-app-server`,
the code-mode host, Responses API proxy, and the Linux `bwrap` helper where
applicable. Windows archives also contain the Windows sandbox helpers. Verify
`SHA256SUMS` before use. These are community builds: this repository does not
provide official signing, notarization, provenance, or support from OpenAI.

The workflow uses only public upstream sources and the repository's
`GITHUB_TOKEN`; no application secrets are required. Existing releases are
never overwritten. If a build fails before publishing, rerunning the workflow
rebuilds the missing release. Release numbering currently reserves `.1` for
the single patch revision; use a new patch revision in the workflow and
release tag if the patch set changes incompatibly.

## Local build

The scripts use Bash, Git, curl, Python 3, and Cargo. Build from this
repository:

```bash
tag="$(scripts/latest-upstream-tag.sh)"
scripts/build-patched.sh \
  --tag "$tag" \
  --target x86_64-unknown-linux-musl \
  --work-dir .build/linux-x86_64 \
  --output-dir dist/linux-x86_64
```

The Linux musl build additionally needs a working C toolchain, `pkg-config`,
`libcap` development files, Zig 0.14, and permission to install the upstream
musl build dependencies. macOS and Windows should be built on their native
runner/host with the target triple shown above. Builds download the exact
prebuilt `rusty_v8` archive and binding for the checked-out `Cargo.lock`
version, and verify their SHA-256 manifest.

Set `CODEX_PRIMARY_BINARIES` or pass `--binaries` to select a different
space-separated Cargo binary list. `CODEX_INCLUDE_BWRAP=false` omits the Linux
helper; it defaults to included for Linux targets. A work directory is
intentionally required to be new so a failed or partially patched checkout
cannot be reused accidentally.

## Patch maintenance

Patch files in `patches/` are applied in bytewise filename order with
`git apply --unidiff-zero --check --whitespace=error` before each application.
To update:

1. Choose the new upstream release tag.
2. Fetch it with `scripts/fetch-upstream.sh`.
3. Edit the upstream checkout, keeping the change focused.
4. Generate or refresh a numbered patch with `git diff`.
5. Validate it against a clean checkout using
   `scripts/apply-patches.sh`.

The current patch intentionally changes only the hosted tool-spec gate in
`codex-rs/core/src/tools/spec_plan.rs`; do not broaden it to alter standalone
search routing.

## Limitations

- The workflow follows the latest published upstream release, not arbitrary
  commits or prereleases.
- It builds the upstream release's executable families for each supported
  platform, not SDK, package-manager artifacts, symbol archives, or desktop
  applications.
- Artifacts are unsigned and unnotarized. Users must independently assess
  whether a community binary is appropriate for their environment.
- Upstream dependencies, release assets, runner images, and build requirements
  can change. A clean failure is preferred over silently producing a partial
  artifact.
