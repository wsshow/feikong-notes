"""Prepare an isolated simulator UI preview; never change production dependencies.

Run flutter pub get at the repository root first. The generated workspace uses
the current tracked working files, not an older Git commit. OCR uses the same Chinese ML Kit runtime as the device build.
MNN uses the pinned source-built ARM64 CPU runtime on the simulator.
"""
import argparse
import datetime
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PREVIEW_ID = "com.fknotes.app.preview"


def simulator_app(developer):
    # Xcode 27 moved simulator UI into Device Hub; older Xcodes use Simulator.
    for path in [developer.parent / "Applications/DeviceHub.app",
                 developer / "Applications/Simulator.app"]:
        if path.is_dir():
            return path
    raise FileNotFoundError("No Device Hub or Simulator app in the selected Xcode")


def prepare(root=ROOT):
    workspace = root / "build/ios-preview/workspace"
    workspace.mkdir(parents=True, exist_ok=True)
    files = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")
    for relative in filter(None, files):
        source = root / relative
        if not source.is_file():
            continue
        destination = workspace / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    project = workspace / "ios/Runner.xcodeproj/project.pbxproj"
    text = project.read_text()
    if "FKNOTES_BUNDLE_ID = com.fknotes.app;" not in text:
        raise ValueError("Preview recipe cannot locate the production bundle identifier")
    text = text.replace("FKNOTES_BUNDLE_ID = com.fknotes.app;", f"FKNOTES_BUNDLE_ID = {PREVIEW_ID};")
    project.write_text(text)
    for path in [workspace / "ios/Runner/Info.plist", workspace / "ios/ShareExtension/Info.plist"]:
        data = plistlib.loads(path.read_bytes())
        data["CFBundleDisplayName"] = "非空笔记预览"
        path.write_bytes(plistlib.dumps(data, sort_keys=False))
    for language, title in [("en", "Feikong Preview"), ("zh-Hans", "非空笔记预览")]:
        path = workspace / f"ios/Runner/{language}.lproj/InfoPlist.strings"
        path.write_text(re.sub(r'"CFBundleDisplayName" = "[^"]*";', f'"CFBundleDisplayName" = "{title}";', path.read_text()))
    print(workspace)
    print(f"Build only with --simulator and FLUTTER_XCODE_FKNOTES_BUNDLE_ID={PREVIEW_ID}")
    # Reuse the verified source build across preview copies; no SDK binaries
    # or absolute host paths are committed. The builder resolves this symlink.
    cache = root / "build/mnn-ios-simulator"
    cache.mkdir(parents=True, exist_ok=True)
    preview_cache = workspace / "build/mnn-ios-simulator"
    preview_cache.parent.mkdir(parents=True, exist_ok=True)
    if not preview_cache.exists() and not preview_cache.is_symlink():
        preview_cache.symlink_to(cache.resolve(), target_is_directory=True)
    print("OCR and MNN CPU are enabled. This is not a device acceptance build.")
    return workspace


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", help="Install and open on this booted simulator (or 'booted')")
    parser.add_argument("--flutter", default="flutter")
    args = parser.parse_args()
    workspace = prepare()
    if args.device:
        env = {**os.environ, "PUB_HOSTED_URL": "https://pub.dev",
               "FLUTTER_XCODE_ARCHS": "arm64",
               "FLUTTER_XCODE_FKNOTES_BUNDLE_ID": PREVIEW_ID,
               "FLUTTER_XCODE_FKNOTES_APP_GROUP": f"group.{PREVIEW_ID}"}
        subprocess.run([args.flutter, "pub", "get"], cwd=workspace, env=env, check=True)
        timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
        subprocess.run([args.flutter, "build", "ios", "--simulator", "--debug", "--no-pub",
                        f"--dart-define=FKNOTES_BUILD_TIME={timestamp}"], cwd=workspace, env=env, check=True)
        app = workspace / "build/ios/iphonesimulator/Runner.app"
        info = plistlib.loads((app / "Info.plist").read_bytes())
        if info.get("DTPlatformName") != "iphonesimulator" or info.get("CFBundleIdentifier") != PREVIEW_ID:
            raise SystemExit("Refusing to install a non-preview or non-simulator bundle")
        subprocess.run(["xcrun", "simctl", "bootstatus", args.device, "-b"], check=True)
        subprocess.run(["xcrun", "simctl", "install", args.device, str(app)], check=True)
        developer = Path(subprocess.check_output(["xcode-select", "--print-path"], text=True).strip())
        subprocess.run(["open", "-a", str(simulator_app(developer))], check=True)
        subprocess.run(["xcrun", "simctl", "launch", "--terminate-running-process", args.device, PREVIEW_ID], check=True)
