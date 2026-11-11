"""Prepare GitHub Release assets and the Android update manifest."""

import argparse
from datetime import date
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import quote

from check_android_release import verify_identity


DEFAULT_REPOSITORY = "wsshow/feikong-notes"
ABIS = ("universal", "arm64-v8a", "armeabi-v7a", "x86_64")


def repository_name(value):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", value):
        raise ValueError("GitHub repository must use owner/repository syntax.")
    return value


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def prepare(dist, repository, version, build_number, notes, release_date, mandatory, require_ios=False):
    repository_name(repository)
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?", version):
        raise ValueError("Invalid release version.")
    if build_number < 1:
        raise ValueError("Build number must be positive.")
    if date.fromisoformat(release_date).isoformat() != release_date:
        raise ValueError("Release date must use YYYY-MM-DD.")
    notes_text = notes.read_text(encoding="utf-8").strip()
    if not notes_text:
        raise ValueError("Release notes must not be empty.")
    ios_files = [dist / f"fknotes-{version}-ios-unsigned.ipa",
                 dist / "ios-installation.md", dist / "ios-build-info.json",
                 dist / "ios-signing-entitlements.plist"]
    if require_ios or any(path.exists() for path in ios_files):
        if any(not path.is_file() or path.stat().st_size == 0 for path in ios_files):
            raise ValueError("The unsigned IPA, installation guide, build info and entitlement template are required")
        ios = json.loads(ios_files[2].read_text())
        if (ios.get("version") != version or ios.get("buildNumber") != build_number
                or ios.get("ipa") != ios_files[0].name
                or ios.get("sha256") != sha256(ios_files[0])
                or ios.get("signed") is not False or ios.get("experimental") is not True
                or ios.get("deviceValidated") is not False):
            raise ValueError("iOS metadata does not match the experimental unsigned release")
    else:
        ios_files = []
    base = f"https://github.com/{repository}/releases/download/v{version}"
    artifacts = {}
    for abi in ABIS:
        apk = dist / f"fknotes-{version}+{build_number}-{abi}-release.apk"
        if not apk.exists() and abi not in ("universal", "arm64-v8a"):
            continue
        if apk.stat().st_size == 0:
            raise ValueError(f"Empty APK: {apk.name}")
        verify_identity(apk, version, build_number)
        artifacts[f"android-{abi}"] = {
            "url": f"{base}/{quote(apk.name, safe='')}",
            "size": apk.stat().st_size,
            "sha256": sha256(apk),
        }
    for aab in dist.glob("*.aab"):
        verify_identity(aab, version, build_number)
    manifest = {
        "app": "fknotes",
        "version": version,
        "versionCode": build_number,
        "releaseDate": release_date,
        "mandatory": mandatory,
        "changelog": f"{base}/notes.md",
        "artifacts": artifacts,
    }
    (dist / "notes.md").write_text(notes_text + "\n", encoding="utf-8")
    (dist / "latest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    files = sorted([*dist.glob("*.apk"), *dist.glob("*.aab")])
    files += ios_files + [dist / "latest.json", dist / "notes.md"]
    (dist / "SHA256SUMS.txt").write_text(
        "".join(f"{sha256(path)}  {path.name}\n" for path in files), encoding="utf-8"
    )
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dist", type=Path, required=True)
    parser.add_argument("--repository", default=DEFAULT_REPOSITORY)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", type=int, required=True)
    parser.add_argument("--notes", type=Path, required=True)
    parser.add_argument("--date", default=date.today().isoformat())
    parser.add_argument("--mandatory", choices=("true", "false"), default="false")
    parser.add_argument("--require-ios", action="store_true")
    args = parser.parse_args()
    prepare(args.dist, args.repository, args.version, args.build_number,
            args.notes, args.date, args.mandatory == "true", args.require_ios)


if __name__ == "__main__":
    main()
