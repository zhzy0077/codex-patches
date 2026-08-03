# Vendored upstream release material

The files in this directory are copied from
`openai/codex@rust-v0.146.0` (`e363b08c9175ac1cbe5893615dd2cb9ddf95043b`).
The complete upstream release workflows are retained for auditability; the
active public workflow is an adapted reusable workflow in
`.github/workflows/rust-release-public.yml`.

Refresh the snapshot with:

```bash
scripts/refresh-upstream-release-workflow.sh --tag rust-v0.146.0
```

The active workflow intentionally keeps upstream build, rusty_v8 verification,
musl setup, and package archive logic while removing private runner labels,
signing/notarization, R2, npm, and DotSlash publication jobs.
