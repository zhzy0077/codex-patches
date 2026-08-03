#!/usr/bin/env python3
"""Package the staged primary Codex binaries for one target."""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import tarfile
import zipfile


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage-dir", type=pathlib.Path, required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--output-dir", type=pathlib.Path, required=True)
    args = parser.parse_args()

    if not args.stage_dir.is_dir():
        parser.error(f"stage directory does not exist: {args.stage_dir}")
    files = sorted(path for path in args.stage_dir.iterdir() if path.is_file())
    if not files:
        parser.error(f"stage directory is empty: {args.stage_dir}")
    args.output_dir.mkdir(parents=True, exist_ok=True)

    if "windows" in args.target:
        archive = args.output_dir / f"codex-patched-{args.target}.zip"
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as output:
            for path in files:
                output.write(path, arcname=path.name)
    else:
        archive = args.output_dir / f"codex-patched-{args.target}.tar.gz"
        with tarfile.open(archive, "w:gz") as output:
            for path in files:
                output.add(path, arcname=path.name)

    checksums = args.output_dir / "SHA256SUMS"
    checksums.write_text(f"{sha256(archive)}  {archive.name}\n", encoding="utf-8")
    print(archive)
    print(checksums)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
