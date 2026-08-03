# Patched Codex releases

This repository contains patch files only. Releases fetch an exact
`openai/codex` tag, apply every patch in `patches/`, and build the patched
checkout on public GitHub-hosted runners.

## Vendored upstream release flow

`vendor/openai-codex/` records the upstream tag and commit in `SOURCE.yaml` and
retains the complete upstream `rust-release.yml` and
`rust-release-windows.yml`, plus the upstream rusty_v8, musl, symbol, and
package helpers. The active `.github/workflows/build-release.yml` is only a
daily/manual discover-and-publish wrapper; it calls the adapted reusable
`.github/workflows/rust-release-public.yml`, which follows that vendored
matrix and invokes the vendored upstream helpers.

Refresh the vendored snapshot when adopting a new upstream release:

```bash
scripts/refresh-upstream-release-workflow.sh --tag rust-v0.146.0
```

Review the resulting `SOURCE.yaml` and workflow diff. The build still fetches
the exact tag independently, so the vendored workflow snapshot cannot
silently select source from another revision.

## Public-runner adaptations

The official workflows require private runner labels and signing services.
This repository intentionally:

- uses public `ubuntu-24.04`, `macos-14`, `macos-13`, and `windows-2022` runners;
- removes signing, notarization, Linux cosign, R2, npm, DotSlash publication,
  and private-runner jobs;
- combines upstream primary/app-server/helper builds per public runner while
  retaining the upstream binary set;
- preserves the MSVC linker workaround
  `/NODEFAULTLIB:libucrt.lib` plus `ucrt.lib`;
- publishes unsigned `tar.gz` package archives, metadata, and per-target
  SHA-256 manifests as GitHub release assets.

Artifacts are community builds, not OpenAI releases. They are unsigned,
unnotarized, and have no OpenAI provenance or support. SDK wheels, symbols,
desktop applications, and private signing infrastructure are intentionally
not published.

## Release behavior

The schedule runs daily and `workflow_dispatch` is available. The latest
upstream release is resolved through GitHub, then released as
`<upstream-tag>-patched.1`. If that release already exists it is left
unchanged; a failed build can be rerun without overwriting an existing
release.

## Local validation/build

Requirements are Bash, Git, curl, Python 3, Cargo, and the platform toolchain.
The local wrapper uses the same upstream package helper:

```bash
tag="$(scripts/latest-upstream-tag.sh)"
scripts/build-patched.sh \
  --tag "$tag" \
  --target x86_64-unknown-linux-musl \
  --binaries "codex codex-code-mode-host codex-responses-api-proxy codex-app-server bwrap" \
  --work-dir .build/linux-x86_64 \
  --output-dir dist/linux-x86_64
```

Linux musl builds additionally need Zig 0.14, a working C toolchain, and the
dependencies installed by the vendored upstream musl helper. macOS and
Windows builds should run on native hosts. Use a new work directory for each
attempt.

Patch maintenance is intentionally separate from workflow refresh:

```bash
scripts/fetch-upstream.sh --tag TAG --destination .build/upstream
scripts/apply-patches.sh --source-dir .build/upstream
```

Patch files are checked and applied in bytewise filename order with strict
whitespace validation.
