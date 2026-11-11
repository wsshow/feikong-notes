"""Regression checks for unsigned IPA contents and release identity boundaries."""

import json
from pathlib import Path
import plistlib
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from package_ios_release import package, validate_unsigned


class IosPackageTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.archive = self.root / "Runner.xcarchive"
        self.app = self.archive / "Products/Applications/Runner.app"
        self.app.mkdir(parents=True)
        self.info = {"CFBundleShortVersionString": "0.2.0", "CFBundleVersion": "2",
                     "CFBundleIdentifier": "com.example.synthetic", "CFBundleExecutable": "Runner",
                     "DTPlatformName": "iphoneos", "MinimumOSVersion": "15.5",
                     "FKNotesAppGroup": "group.com.example.synthetic"}
        (self.app / "Info.plist").write_bytes(plistlib.dumps(self.info))
        (self.app / "Runner").write_bytes(b"synthetic executable")
        (self.app / "Runner").chmod(0o755)
        extension = self.app / "PlugIns/ShareExtension.appex"
        extension.mkdir(parents=True)
        (extension / "ShareExtension").write_bytes(b"synthetic extension")
        (extension / "ShareExtension").chmod(0o755)
        (self.app / "Frameworks/Synthetic.framework").mkdir(parents=True)
        (self.app / "Frameworks/Synthetic.framework/PrivacyInfo.xcprivacy").write_bytes(b"vendor privacy")
        self.guide = self.root / "guide.md"
        self.guide.write_text("Experimental: sign before installing.")
        self.dist = self.root / "dist"
        mock = patch("package_ios_release.subprocess.run", return_value=subprocess.CompletedProcess(
            [], 1, "", "code object is not signed at all"))
        self.codesign = mock.start()
        self.addCleanup(mock.stop)

    def package(self):
        with patch("package_ios_release.verify") as verify:
            package(self.archive, self.dist, "0.2.0", 2, "a" * 40, "b" * 40)
            verify.assert_called_once_with(self.app)

    def test_payload_keeps_extension_resources_and_executable_mode(self):
        self.package()
        with zipfile.ZipFile(self.dist / "fknotes-0.2.0-ios-unsigned.ipa") as ipa:
            self.assertIsNone(ipa.testzip())
            self.assertTrue(all(name.startswith("Payload/Runner.app/") for name in ipa.namelist()))
            for name in ["Runner", "PlugIns/ShareExtension.appex/ShareExtension"]:
                entry = ipa.getinfo(f"Payload/Runner.app/{name}")
                self.assertTrue((entry.external_attr >> 16) & stat.S_IXUSR)
            self.assertEqual(ipa.read("Payload/Runner.app/Frameworks/Synthetic.framework/PrivacyInfo.xcprivacy"), b"vendor privacy")
        metadata = json.loads((self.dist / "ios-build-info.json").read_text())
        self.assertEqual(metadata["sourceCommit"], "a" * 40)
        self.assertEqual(metadata["toolingCommit"], "b" * 40)
        self.assertFalse(metadata["signed"])
        self.assertFalse(metadata["deviceValidated"])
        self.assertEqual({p.name for p in self.dist.iterdir()},
                         {"fknotes-0.2.0-ios-unsigned.ipa", "ios-build-info.json"})

    def test_stale_archive_and_simulator_are_rejected(self):
        for key, value in [("CFBundleVersion", "1"), ("CFBundleShortVersionString", "0.1.0"),
                           ("DTPlatformName", "iphonesimulator")]:
            (self.app / "Info.plist").write_bytes(plistlib.dumps({**self.info, key: value}))
            with self.assertRaises(ValueError):
                self.package()
            self.assertFalse(self.dist.exists())

    def test_embedded_profile_and_external_symlink_are_rejected(self):
        profile = self.app / "PlugIns/ShareExtension.appex/embedded.mobileprovision"
        profile.write_bytes(b"synthetic profile")
        with self.assertRaises(ValueError):
            validate_unsigned(self.app, "0.2.0", 2)
        profile.unlink()
        (self.app / "external").symlink_to(self.guide)
        with self.assertRaises(ValueError):
            validate_unsigned(self.app, "0.2.0", 2)

    def test_signed_bundle_or_unknown_codesign_error_is_rejected(self):
        for code, message in [(0, "signed"), (1, "unrecognized bundle")]:
            self.codesign.return_value = subprocess.CompletedProcess([], code, "", message)
            with self.assertRaises(ValueError):
                validate_unsigned(self.app, "0.2.0", 2)


if __name__ == "__main__":
    unittest.main()
