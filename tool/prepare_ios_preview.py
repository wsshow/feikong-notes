"""Prepare an isolated simulator UI preview; never change production dependencies.

Run flutter pub get at the repository root first. The generated workspace uses
the current tracked working files, not an older Git commit. OCR explicitly fails
in this preview because the locked ML Kit binaries lack ARM64 simulator support.
MNN retains its existing unavailable-runtime implementation on the simulator.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PREVIEW_ID = "com.fknotes.app.preview"


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"Preview recipe no longer matches source: {old}")
    return text.replace(old, new, 1)


def simulator_app(developer):
    # Xcode 27 moved simulator UI into Device Hub; older Xcodes use Simulator.
    for path in [developer.parent / "Applications/DeviceHub.app",
                 developer / "Applications/Simulator.app"]:
        if path.is_dir():
            return path
    raise FileNotFoundError("No Device Hub or Simulator app in the selected Xcode")


def make_plugin(source, destination, name, class_name, channel):
    # Copy upstream Dart API and license; only the generated native adapter is
    # replaced. No Pub-cache mutation and no successful fake recognition result.
    shutil.copytree(source, destination, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns("example", "test", ".dart_tool", "build", "ios"))
    ios = destination / "ios"
    classes = ios / "Classes"
    classes.mkdir(parents=True, exist_ok=True)
    (classes / f"{class_name}.h").write_text(
        f"#import <Flutter/Flutter.h>\n@interface {class_name} : NSObject<FlutterPlugin>\n@end\n")
    (classes / f"{class_name}.m").write_text(f'''#import "{class_name}.h"
#import <TargetConditionals.h>
#if !TARGET_OS_SIMULATOR
#error This generated preview adapter must never be built for a device.
#endif
@implementation {class_name}
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {{
  FlutterMethodChannel *channel = [FlutterMethodChannel methodChannelWithName:@"{channel}" binaryMessenger:registrar.messenger];
  [registrar addMethodCallDelegate:[[{class_name} alloc] init] channel:channel];
}}
- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {{
  if ([call.method isEqualToString:@"vision#closeTextRecognizer"]) {{ result(nil); return; }}
  result([FlutterError errorWithCode:@"simulator_preview_unavailable" message:@"模拟器预览版不提供 OCR，请在真机验证。OCR is unavailable in this simulator preview." details:nil]);
}}
@end
''')
    (ios / f"{name}.podspec").write_text(f'''Pod::Spec.new do |s|
  s.name = '{name}'
  s.version = '0.0.1'
  s.summary = 'Generated simulator-only UI preview adapter'
  s.description = s.summary
  s.homepage = 'https://github.com/flutter-ml/google_ml_kit_flutter'
  s.license = {{ :file => '../LICENSE' }}
  s.author = 'Feikong Notes'
  s.source = {{ :path => '.' }}
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.static_framework = true
  s.pod_target_xcconfig = {{ 'DEFINES_MODULE' => 'YES' }}
end
''')


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
    plugins = json.loads((root / ".flutter-plugins-dependencies").read_text())["plugins"]["ios"]
    overrides = ""
    for name, class_name, channel in [
        ("google_mlkit_commons", "GoogleMlKitCommonsPlugin", "google_mlkit_commons"),
        ("google_mlkit_text_recognition", "GoogleMlKitTextRecognitionPlugin", "google_mlkit_text_recognizer"),
    ]:
        source = Path(next(p["path"] for p in plugins if p["name"] == name))
        make_plugin(source, workspace / "preview_plugins" / name, name, class_name, channel)
        overrides += f"  {name}:\n    path: preview_plugins/{name}\n"
    pubspec = workspace / "pubspec.yaml"
    pubspec.write_text(replace_once(pubspec.read_text(), "dependency_overrides:\n", "dependency_overrides:\n" + overrides))
    podfile = workspace / "ios/Podfile"
    podfile.write_text(replace_once(podfile.read_text(), "  pod 'GoogleMLKit/TextRecognitionChinese', '~> 6.0.0'\n", ""))
    project = workspace / "ios/Runner.xcodeproj/project.pbxproj"
    text = project.read_text()
    if "FKNOTES_BUNDLE_ID = com.fknotes.app;" not in text:
        raise ValueError("Preview recipe cannot locate the production bundle identifier")
    text = text.replace("FKNOTES_BUNDLE_ID = com.fknotes.app;", f"FKNOTES_BUNDLE_ID = {PREVIEW_ID};")
    # Remove only the preview's vendor-copy build phase; no fabricated manifests.
    text = replace_once(text, "\t\t\t\t76536BA2D647F7874F32FEFE /* Preserve Static SDK Privacy Manifests */,\n", "")
    text = replace_once(text, "\t\t\t\tA11C0DE10000000000000003 /* Prepare MNN Runtime */,\n", "")
    project.write_text(text)
    for path in [workspace / "ios/Runner/Info.plist", workspace / "ios/ShareExtension/Info.plist"]:
        data = plistlib.loads(path.read_bytes())
        data["CFBundleDisplayName"] = "非空笔记预览"
        path.write_bytes(plistlib.dumps(data, sort_keys=False))
    for language, title in [("en", "Feikong Preview"), ("zh-Hans", "非空笔记预览")]:
        path = workspace / f"ios/Runner/{language}.lproj/InfoPlist.strings"
        path.write_text(re.sub(r'"CFBundleDisplayName" = "[^"]*";', f'"CFBundleDisplayName" = "{title}";', path.read_text()))
    # Prevent inherited x86_64 exclusions from the previous native Pod resolution.
    (workspace / "ios/Podfile.lock").unlink(missing_ok=True)
    print(workspace)
    print(f"Build only with --simulator and FLUTTER_XCODE_FKNOTES_BUNDLE_ID={PREVIEW_ID}")
    print("OCR and MNN are unavailable. This is not a device acceptance build.")
    return workspace


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", help="Install and open on this booted simulator (or 'booted')")
    parser.add_argument("--flutter", default="flutter")
    args = parser.parse_args()
    workspace = prepare()
    if args.device:
        # The simulator-only native adapter also fails compilation for iphoneos.
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
