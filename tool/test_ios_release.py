"""Validate archive signing boundaries and preserve upstream privacy metadata."""
from pathlib import Path
import plistlib
import tempfile
import unittest

import build_ios_archive
from copy_ios_privacy_manifests import copy_manifests, SDK_NAMES
from ios_privacy_report import report


class IosArchiveTests(unittest.TestCase):
    def test_unsigned_archive_has_no_signing_or_export(self):
        args = build_ios_archive.parser().parse_args(["--unsigned"])
        command, settings, options = build_ios_archive.configuration(args, Path("export.plist"))
        self.assertIn("--no-codesign", command)
        self.assertNotIn("--export-options-plist", command)
        self.assertNotIn("FLUTTER_XCODE_DEVELOPMENT_TEAM", settings)
        self.assertIsNone(options)

    def test_signed_export_never_uploads_and_binds_both_targets(self):
        args = build_ios_archive.parser().parse_args(["--team", "TESTTEAM01", "--bundle-id", "com.example.synthetic", "--build-number", "7"])
        command, settings, options = build_ios_archive.configuration(args, Path("export.plist"))
        self.assertEqual(settings["FLUTTER_XCODE_FKNOTES_APP_GROUP"], "group.com.example.synthetic")
        self.assertEqual(options["destination"], "export")
        self.assertEqual(options["method"], "app-store-connect")
        self.assertFalse(options["manageAppVersionAndBuildNumber"])
        self.assertNotIn("--no-codesign", command)

    def test_invalid_identifiers_fail_before_building(self):
        for flag, value in [("--bundle-id", "com.example.*"), ("--app-group", "other.group"), ("--build-number", "0")]:
            args = build_ios_archive.parser().parse_args(["--unsigned", flag, value])
            with self.assertRaises(ValueError):
                build_ios_archive.configuration(args, Path("export.plist"))

    def test_vendor_manifest_is_not_replaced_with_no_collection(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            pods, app = root / "Pods", root / "Runner.app"
            payload = plistlib.dumps({"NSPrivacyTracking": False, "NSPrivacyCollectedDataTypes": [{"NSPrivacyCollectedDataType": "synthetic-type"}]})
            for name in SDK_NAMES:
                path = pods / name / f"{name}.xcframework/ios-arm64/{name}.framework/PrivacyInfo.xcprivacy"
                path.parent.mkdir(parents=True)
                path.write_bytes(payload)
            copy_manifests(pods, app)
            for name in SDK_NAMES:
                self.assertEqual((app / f"{name}_Privacy.bundle/PrivacyInfo.xcprivacy").read_bytes(), payload)
            missing = app / "Frameworks/Synthetic.framework"
            missing.mkdir(parents=True)
            inventory = report(app)
            self.assertEqual(len(inventory["manifests"]), len(SDK_NAMES))
            self.assertIn("Frameworks/Synthetic.framework", inventory["frameworksWithoutBundledManifest"])


if __name__ == "__main__":
    unittest.main()
