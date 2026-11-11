"""Build an unsigned review archive, or a locally signed IPA. Never upload."""
import argparse
import datetime
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import time

from ios_privacy_report import report
from verify_ios_bundle import verify

ROOT = Path(__file__).resolve().parents[1]


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    mode = result.add_mutually_exclusive_group(required=True)
    mode.add_argument("--unsigned", action="store_true", help="Archive without signing or IPA export")
    mode.add_argument("--team", help="Apple Team ID; local signing/profile setup is required")
    result.add_argument("--bundle-id", default="com.fknotes.app")
    result.add_argument("--app-group", help="Defaults to group.<bundle-id>")
    result.add_argument("--export-method", choices=["app-store-connect", "release-testing", "debugging"], default="app-store-connect")
    result.add_argument("--build-name")
    result.add_argument("--build-number")
    result.add_argument("--flutter", default="flutter")
    result.add_argument("--dry-run", action="store_true", help="Print the reviewed command without building")
    return result


def configuration(args, export_path):
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", args.bundle_id):
        raise ValueError("--bundle-id must be a concrete reverse-DNS identifier")
    group = args.app_group or f"group.{args.bundle_id}"
    if not re.fullmatch(r"group\.[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", group):
        raise ValueError("--app-group must be a concrete group identifier")
    if args.team and not re.fullmatch(r"[A-Z0-9]{10}", args.team):
        raise ValueError("--team must be a 10-character Apple Team ID")
    if args.build_name and not re.fullmatch(r"\d+\.\d+\.\d+", args.build_name):
        raise ValueError("--build-name must be major.minor.patch")
    if args.build_number and not re.fullmatch(r"[1-9]\d*", args.build_number):
        raise ValueError("--build-number must be a positive integer")
    command = [args.flutter, "build", "ipa", "--release", "--no-pub"]
    settings = {"FLUTTER_XCODE_FKNOTES_BUNDLE_ID": args.bundle_id,
                "FLUTTER_XCODE_FKNOTES_APP_GROUP": group}
    options = None
    if args.unsigned:
        command.append("--no-codesign")
    else:
        settings["FLUTTER_XCODE_DEVELOPMENT_TEAM"] = args.team
        settings["FLUTTER_XCODE_CODE_SIGN_STYLE"] = "Automatic"
        command.extend(["--export-options-plist", str(export_path)])
        options = {"method": args.export_method, "teamID": args.team,
                   "signingStyle": "automatic", "destination": "export",
                   "manageAppVersionAndBuildNumber": False}
    for flag, value in [("--build-name", args.build_name), ("--build-number", args.build_number)]:
        if value:
            command.extend([flag, value])
    return command, settings, options


def main():
    args = parser().parse_args()
    with tempfile.TemporaryDirectory(prefix="fknotes-ios-export-") as temp:
        export_path = Path(temp) / "ExportOptions.plist"
        try:
            command, settings, options = configuration(args, export_path)
        except ValueError as error:
            raise SystemExit(str(error)) from error
        if args.dry_run:
            print(json.dumps({"command": command, "settings": settings,
                              "exportOptions": options, "uploads": False}, indent=2))
            return
        if options:
            export_path.write_bytes(plistlib.dumps(options))
        env = {**os.environ, **settings, "PUB_HOSTED_URL": "https://pub.dev"}
        subprocess.run([args.flutter, "pub", "get", "--enforce-lockfile"], cwd=ROOT, env=env, check=True)
        subprocess.run(["pod", "install", "--deployment"], cwd=ROOT / "ios", env=env, check=True)
        timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
        started = time.time()
        subprocess.run(command + [f"--dart-define=FKNOTES_BUILD_TIME={timestamp}"], cwd=ROOT, env=env, check=True)
        app = ROOT / "build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app"
        verify(app)
        info = plistlib.loads((app / "Info.plist").read_bytes())
        if info["CFBundleIdentifier"] != args.bundle_id or info["FKNotesAppGroup"] != settings["FLUTTER_XCODE_FKNOTES_APP_GROUP"]:
            raise SystemExit("Archived bundle identifiers do not match the requested signing configuration")
        if args.team:
            # Flutter can leave a valid archive even when IPA export fails.
            # Never mistake a stale IPA from an earlier build for this export.
            outputs = [p for p in (ROOT / "build/ios/ipa").glob("*.ipa") if p.stat().st_mtime >= started]
            if not outputs:
                raise SystemExit("No fresh signed IPA was exported; inspect the archive/export diagnostics")
            subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
        output = ROOT / "build/ios/privacy-report.json"
        output.write_text(json.dumps(report(app), ensure_ascii=False, indent=2) + "\n")
        print("Archive verified. Nothing was uploaded. Review build/ios/privacy-report.json before distribution.")


if __name__ == "__main__":
    main()
