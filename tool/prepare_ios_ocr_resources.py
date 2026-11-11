"""Copy checksum-pinned ML Kit Chinese/Latin models and original privacy files."""
import argparse
import hashlib
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import zipfile

from copy_ios_privacy_manifests import copy_manifests

VERSION = "9.0.2"
BUNDLES = {
    "ChineseOCRResources.bundle": "570404236a24d0064ff048e2dba28caac2c273df4c9098ae264776af2368c7a7",
    "LatinOCRResources.bundle": "c790283599f67708c06fd93de61d96823ce2ad984ad00bfda5922afda0861758",
}


def extract_bundle(archive, destination, name, expected):
    if hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
        raise ValueError(f"OCR resource checksum mismatch: {name}")
    with zipfile.ZipFile(archive) as zipped:
        for item in zipped.infolist():
            path = Path(item.filename)
            if path.is_absolute() or ".." in path.parts or stat.S_ISLNK(item.external_attr >> 16):
                raise ValueError("Unsafe OCR archive member")
        zipped.extractall(destination)
    source = destination / name
    if not source.is_dir() or not any(p.stat().st_size for p in source.rglob("*.bincfg")):
        raise ValueError(f"Missing OCR models: {name}")
    return source


def prepare(cache, app, artifacts):
    cache.mkdir(parents=True, exist_ok=True)
    app.mkdir(parents=True, exist_ok=True)
    for name, expected in BUNDLES.items():
        archive = cache / f"{name}.zip"
        if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
            temporary = archive.with_suffix(".download")
            subprocess.run(["curl", "--fail", "--location", "--retry", "3", "--connect-timeout", "20",
                            f"https://github.com/d-date/google-mlkit-swiftpm/releases/download/{VERSION}/{name}.zip",
                            "--output", str(temporary)], check=True)
            if hashlib.sha256(temporary.read_bytes()).hexdigest() != expected:
                temporary.unlink()
                raise ValueError(f"OCR resource checksum mismatch: {name}")
            temporary.replace(archive)
        with tempfile.TemporaryDirectory(dir=cache) as temp:
            source = extract_bundle(archive, Path(temp), name, expected)
            target = app / name
            if target.exists():
                shutil.rmtree(target)
            shutil.copytree(source, target)
    copy_manifests(artifacts, app)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--app", type=Path, required=True)
    args = parser.parse_args()
    prepare(args.cache, args.app, args.artifacts)
