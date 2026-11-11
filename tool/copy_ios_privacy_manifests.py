"""Preserve vendor manifests from static ML Kit frameworks in resource bundles.

CocoaPods links these static frameworks but does not embed their framework
directories. Copy the original privacy declarations without changing them.
"""
import argparse
from pathlib import Path
import plistlib
import shutil

SDK_NAMES = ("MLKitCommon", "MLKitTextRecognitionCommon")


def copy_manifests(pods, app):
    for name in SDK_NAMES:
        source = pods / name / "Frameworks" / f"{name}.framework" / "PrivacyInfo.xcprivacy"
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
    parser.add_argument("--pods", type=Path, required=True)
    parser.add_argument("--app", type=Path, required=True)
    args = parser.parse_args()
    copy_manifests(args.pods, args.app)
