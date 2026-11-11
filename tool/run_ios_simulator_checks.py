"""Run real OCR/MNN checks in a separate ARM64 simulator validation app."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import subprocess

from prepare_ios_mnn_smoke import prepare, VALIDATION_ID

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default="booted")
    parser.add_argument("--flutter", default="flutter")
    args = parser.parse_args()
    devices = json.loads(subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "booted", "--json"], text=True))
    matches = [device["udid"] for group in devices["devices"].values() for device in group
               if args.device in ("booted", device["udid"])]
    if len(matches) != 1:
        parser.error("Choose exactly one booted iOS simulator using --device <UUID>")
    device = matches[0]
    env = {**os.environ, "PUB_HOSTED_URL": "https://pub.dev", "FLUTTER_XCODE_ARCHS": "arm64",
           "FLUTTER_XCODE_FKNOTES_BUNDLE_ID": VALIDATION_ID,
           "FLUTTER_XCODE_FKNOTES_APP_GROUP": f"group.{VALIDATION_ID}"}

    def flutter(*arguments):
        subprocess.run([args.flutter, *arguments], cwd=ROOT, env=env, check=True)

    flutter("pub", "get", "--enforce-lockfile")
    flutter("build", "ios", "--simulator", "--debug", "--no-pub",
            "--target", "integration_test/ios_mnn_smoke_test.dart")
    app = ROOT / "build/ios/iphonesimulator/Runner.app"
    info = plistlib.loads((app / "Info.plist").read_bytes())
    if info.get("DTPlatformName") != "iphonesimulator" or info.get("CFBundleIdentifier") != VALIDATION_ID:
        raise SystemExit("Refusing to install a non-validation or non-simulator app")
    subprocess.run(["xcrun", "simctl", "install", device, str(app)], check=True)
    prepare(ROOT / "build/mnn-smoke-model", device)
    for name in ["ios_mnn_smoke_test.dart", "ios_ocr_smoke_test.dart"]:
        flutter("test", f"integration_test/{name}", "-d", device, "--no-pub", "--no-uninstall")
    print("PASS: simulator MNN CPU lifecycle and Chinese/English OCR. No device acceptance implied.")


if __name__ == "__main__":
    main()
