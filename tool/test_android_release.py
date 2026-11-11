"""Verify release identity using synthetic SDK output, never online services."""

from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

from check_android_release import identity, verify_identity


class AndroidReleaseIdentityTests(unittest.TestCase):
    def setUp(self):
        for name, value in [("aapt_path", "synthetic-aapt"), ("bundletool_path", Path("synthetic-bundletool.jar"))]:
            mock = patch(f"check_android_release.{name}", return_value=value)
            mock.start()
            self.addCleanup(mock.stop)

    def test_split_and_universal_accept_exact_shared_version(self):
        for abi in ["universal", "arm64-v8a", "armeabi-v7a", "x86_64"]:
            with self.subTest(abi=abi), patch("check_android_release.subprocess.check_output", return_value=
                    "package: name='com.fknotes.app' versionCode='3' versionName='0.2.1' platformBuildVersionCode='36'\n"):
                self.assertEqual(verify_identity(Path(f"{abi}.apk"), "0.2.1", 3), ("com.fknotes.app", "0.2.1", 3))

    def test_wrong_package_name_version_or_abi_offset_are_rejected(self):
        for package, version, code in [("com.example.other", "0.2.1", 3), ("com.fknotes.app", "0.2.0", 3),
                                       ("com.fknotes.app", "0.2.1", 1003), ("com.fknotes.app", "0.2.1", 2003),
                                       ("com.fknotes.app", "0.2.1", 4003)]:
            with self.subTest(code=code), patch("check_android_release.subprocess.check_output", return_value=
                    f"package: name='{package}' versionCode='{code}' versionName='{version}'\n"):
                with self.assertRaises(ValueError):
                    verify_identity(Path("app.apk"), "0.2.1", 3)

    def test_aab_reads_decoded_base_manifest_and_rejects_wrong_build(self):
        xml = '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.fknotes.app" android:versionName="0.2.1" android:versionCode="3" />'
        with patch("check_android_release.subprocess.check_output", return_value=xml) as run:
            self.assertEqual(verify_identity(Path("app.aab"), "0.2.1", 3)[2], 3)
            self.assertIn("--bundle=app.aab", run.call_args.args[0])
            with self.assertRaises(ValueError):
                verify_identity(Path("app.aab"), "0.2.1", 4)

    def test_malformed_manifest_and_sdk_failure_do_not_pass(self):
        with patch("check_android_release.subprocess.check_output", return_value="not a manifest"):
            with self.assertRaises(ValueError):
                identity(Path("app.apk"))
        with patch("check_android_release.subprocess.check_output", side_effect=subprocess.CalledProcessError(1, "aapt")):
            with self.assertRaises(subprocess.CalledProcessError):
                identity(Path("app.apk"))

    def test_out_of_range_android_build_is_rejected(self):
        for code in [0, -1, 2100000001]:
            with self.assertRaises(ValueError):
                verify_identity(Path("app.apk"), "0.2.1", code)


if __name__ == "__main__":
    unittest.main()
