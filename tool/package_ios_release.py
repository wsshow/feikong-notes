"""Package a verified device archive for user re-signing; never sign or upload."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import tempfile
import zipfile

from verify_ios_bundle import verify


def validate_unsigned(app, version, build_number):
    info = plistlib.loads((app / "Info.plist").read_bytes())
    if info.get("CFBundleShortVersionString") != version or info.get("CFBundleVersion") != str(build_number):
        raise ValueError("Archive version/build does not match the release; rebuild the archive")
    if info.get("DTPlatformName") != "iphoneos":
        raise ValueError("A simulator app cannot be distributed as a device IPA")
    for path in app.rglob("*"):
        if path.is_symlink() or not (path.is_file() or path.is_dir()):
            raise ValueError(f"Unsupported archive entry: {path.relative_to(app)}")
        if path.suffix in {".mobileprovision", ".p12", ".pfx", ".jks", ".keystore"}:
            raise ValueError("Signing credentials or provisioning profiles must not be packaged")
    # Preserve vendor framework signatures. The user must re-sign all embedded
    # code; neither the main app nor our extension may carry a developer identity.
    for bundle in [app, *app.glob("PlugIns/*.appex")]:
        if (bundle / "_CodeSignature").exists():
            raise ValueError("Expected an unsigned app and extension")
        result = subprocess.run(["codesign", "--display", str(bundle)], capture_output=True, text=True)
        if result.returncode != 1 or "not signed at all" not in result.stderr:
            raise ValueError(f"Could not confirm unsigned bundle: {bundle.name}")
    return info


def write_ipa(app, output):
    # ZipInfo carries Unix executable permissions, including the extension and
    # nested frameworks. No machine paths, dSYMs or archive metadata are included.
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(app.rglob("*")):
            if path.is_symlink():
                raise ValueError("Symbolic links are not supported in the release bundle")
            archive.write(path, Path("Payload") / app.name / path.relative_to(app))
    with zipfile.ZipFile(output) as archive:
        bad = archive.testzip()
        if bad:
            raise ValueError(f"Corrupt IPA member: {bad}")
        executable = plistlib.loads((app / "Info.plist").read_bytes())["CFBundleExecutable"]
        member = archive.getinfo(f"Payload/{app.name}/{executable}")
        if not (member.external_attr >> 16) & stat.S_IXUSR:
            raise ValueError("IPA lost executable permissions")


def package(archive, dist, version, build_number, source_commit, tooling_commit):
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?", version) or build_number < 1:
        raise ValueError("Invalid release version/build")
    if not all(re.fullmatch(r"[a-f0-9]{40}", value) for value in [source_commit, tooling_commit]):
        raise ValueError("Full source and tooling commit hashes are required")
    app = archive / "Products/Applications/Runner.app"
    info = validate_unsigned(app, version, build_number)
    verify(app)
    dist.mkdir(parents=True, exist_ok=True)
    name = f"fknotes-{version}-ios-unsigned.ipa"
    with tempfile.TemporaryDirectory(prefix=".ios-package-", dir=dist) as temporary:
        staging = Path(temporary)
        ipa = staging / name
        write_ipa(app, ipa)
        digest = hashlib.sha256()
        with ipa.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        metadata = {
            "version": version, "buildNumber": build_number,
            "sourceCommit": source_commit, "toolingCommit": tooling_commit,
            "bundleIdentifier": info["CFBundleIdentifier"],
            "minimumOSVersion": info["MinimumOSVersion"],
            "appGroup": info["FKNotesAppGroup"], "signed": False,
            "experimental": True, "deviceValidated": False,
            "ipa": name, "sha256": digest.hexdigest(),
        }
        (staging / "ios-build-info.json").write_text(json.dumps(metadata, indent=2) + "\n")
        for path in staging.iterdir():
            os.replace(path, dist / path.name)
    print(f"Packaged {dist / name}; experimental, unsigned, no device validation.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--dist", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", type=int, required=True)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--tooling-commit", required=True)
    args = parser.parse_args()
    package(args.archive, args.dist, args.version, args.build_number,
            args.source_commit, args.tooling_commit)


if __name__ == "__main__":
    main()
