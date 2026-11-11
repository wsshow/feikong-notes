"""Preserve vendor manifests from static ML Kit frameworks in resource bundles.

SwiftPM links these static frameworks but does not embed their framework
directories. Copy the original privacy declarations without changing them.
"""
import argparse
from pathlib import Path
import plistlib
import shutil

SDK_NAMES = ("MLKitCommon", "MLKitTextRecognitionCommon", "MLKitBarcodeScanning")


def copy_manifests(artifacts, app):
    for name in SDK_NAMES:
        candidates = sorted(artifacts.glob(f"{name}/{name}.xcframework/*/{name}.framework/PrivacyInfo.xcprivacy"))
        if not candidates:
            raise ValueError(f"Missing pinned SwiftPM privacy metadata for {name}")
        source = candidates[0]
        if any(path.read_bytes() != source.read_bytes() for path in candidates[1:]):
            raise ValueError(f"Privacy declarations differ between {name} slices")
        plistlib.loads(source.read_bytes())  # Fail on missing/malformed SDK metadata.
        bundle = app / f"{name}_Privacy.bundle"
        bundle.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, bundle / source.name)
        (bundle / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": f"com.fknotes.sdk-privacy.{name}",
            "CFBundleName": f"{name}_Privacy", "CFBundlePackageType": "BNDL",
            "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
        }))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--app", type=Path, required=True)
    args = parser.parse_args()
    copy_manifests(args.artifacts, args.app)
