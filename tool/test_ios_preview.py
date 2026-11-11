"""Preview isolation must not silently modify or replace a production build."""
from contextlib import redirect_stdout
import io
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

from prepare_ios_preview import prepare, replace_once, simulator_app


class IosPreviewTest(unittest.TestCase):
    def test_simulator_ui_supports_current_and_legacy_xcode(self):
        with tempfile.TemporaryDirectory() as temp:
            developer = Path(temp) / "Contents/Developer"
            legacy = developer / "Applications/Simulator.app"
            legacy.mkdir(parents=True)
            self.assertEqual(simulator_app(developer), legacy)
            current = developer.parent / "Applications/DeviceHub.app"
            current.mkdir(parents=True)
            self.assertEqual(simulator_app(developer), current)

    def test_recipe_fails_when_source_layout_has_changed(self):
        with self.assertRaises(ValueError):
            replace_once("unrelated", "expected", "replacement")

    def test_preview_uses_working_files_and_preserves_source(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source_files = {
                "pubspec.yaml": "name: synthetic\ndependency_overrides:\n  existing_pin: 1.0.0\n",
                "ios/Podfile": "  pod 'GoogleMLKit/TextRecognitionChinese', '~> 6.0.0'\n",
                "ios/Podfile.lock": "synthetic production lock",
                "ios/Runner.xcodeproj/project.pbxproj": "FKNOTES_BUNDLE_ID = com.fknotes.app;\n\t\t\t\t76536BA2D647F7874F32FEFE /* Preserve Static SDK Privacy Manifests */,\n\t\t\t\tA11C0DE10000000000000003 /* Prepare MNN Runtime */,\n",
                "ios/Runner/en.lproj/InfoPlist.strings": '"CFBundleDisplayName" = "Synthetic";',
                "ios/Runner/zh-Hans.lproj/InfoPlist.strings": '"CFBundleDisplayName" = "合成";',
                "lib/main.dart": "old content",
            }
            for relative, content in source_files.items():
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
            for relative in ["ios/Runner/Info.plist", "ios/ShareExtension/Info.plist"]:
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(plistlib.dumps({"CFBundleDisplayName": "Synthetic"}))
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            (root / "lib/main.dart").write_text("latest working content")
            with redirect_stdout(io.StringIO()):
                workspace = prepare(root)
            self.assertEqual((workspace / "lib/main.dart").read_text(), "latest working content")
            self.assertEqual((root / "pubspec.yaml").read_text(), source_files["pubspec.yaml"])
            self.assertEqual((root / "ios/Podfile.lock").read_text(), "synthetic production lock")
            self.assertIn("com.fknotes.app.preview", (workspace / "ios/Runner.xcodeproj/project.pbxproj").read_text())
            self.assertIn("existing_pin: 1.0.0", (workspace / "pubspec.yaml").read_text())
            self.assertEqual((workspace / "ios/Podfile.lock").read_text(), "synthetic production lock")
            self.assertEqual((workspace / "pubspec.yaml").read_text(), source_files["pubspec.yaml"])
            self.assertFalse((workspace / "preview_plugins").exists())


if __name__ == "__main__":
    unittest.main()
