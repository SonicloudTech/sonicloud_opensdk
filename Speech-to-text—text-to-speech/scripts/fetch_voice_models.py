#!/usr/bin/env python3
"""Download and verify the pinned SoniCloud Voice Engine model bundle."""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import tarfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "models"
MANIFEST = MODELS / "manifest.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_extract(bundle: tarfile.TarFile, destination: Path) -> None:
    """Extract a model archive without relying on Python 3.12's filter API."""
    root = destination.resolve()
    for member in bundle.getmembers():
        # Model archives should contain regular files and directories only.
        if member.issym() or member.islnk() or member.isdev():
            raise RuntimeError(f"Archive contains an unsupported link/device: {member.name}")
        target = (destination / member.name).resolve()
        if target != root and root not in target.parents:
            raise RuntimeError(f"Archive member escapes extraction directory: {member.name}")
        bundle.extract(member, path=destination)


def fetch(name: str) -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    spec = manifest["models"][name]
    archive = MODELS / spec["archive"]
    target = MODELS / spec["directory"]
    if target.exists() and all(
        (target / value).exists()
        for value in (spec.get("model_file"), spec.get("tokens_file"), spec.get("voices_file"))
        if value
    ):
        print(f"{name}: already installed at {target}")
        return

    MODELS.mkdir(parents=True, exist_ok=True)
    if not archive.exists():
        print(f"Downloading {spec['archive']} ...")
        urllib.request.urlretrieve(spec["url"], archive)
    actual = sha256(archive)
    if actual != spec["sha256"]:
        archive.unlink(missing_ok=True)
        raise RuntimeError(
            f"SHA-256 mismatch for {archive.name}: expected {spec['sha256']}, got {actual}"
        )

    temp = MODELS / f".{spec['directory']}.extracting"
    if temp.exists():
        shutil.rmtree(temp)
    temp.mkdir()
    try:
        with tarfile.open(archive, "r:bz2") as bundle:
            safe_extract(bundle, temp)
        extracted = temp / spec["directory"]
        if not extracted.is_dir():
            raise RuntimeError(f"Archive does not contain {spec['directory']}/")
        if target.exists():
            shutil.rmtree(target)
        extracted.rename(target)
    finally:
        shutil.rmtree(temp, ignore_errors=True)
    print(f"Installed {name} at {target}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--all", action="store_true", help="Install ASR and TTS models")
    parser.add_argument("--asr", action="store_true", help="Install the ASR model")
    parser.add_argument("--tts", action="store_true", help="Install the TTS model")
    args = parser.parse_args()
    selected = []
    if args.all or args.asr:
        selected.append("asr_sensevoice")
    if args.all or args.tts:
        selected.append("tts_kokoro_multilingual")
    if not selected:
        parser.error("choose --all, --asr, or --tts")
    for name in selected:
        fetch(name)


if __name__ == "__main__":
    main()
