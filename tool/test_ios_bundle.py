"""Regression checks prevent a stub-only build from passing native verification."""

from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

import verify_ios_bundle


class IosBundleTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="fknotes-bundle-test-")
        self.addCleanup(self.temporary.cleanup)
        self.app = Path(self.temporary.name)
        info = {
            "DTPlatformName": "iphoneos", "MinimumOSVersion": "15.0", "CFBundleExecutable": "Runner",
            "NSMicrophoneUsageDescription": "Synthetic test", "NSCameraUsageDescription": "Synthetic test",
            "NSPhotoLibraryUsageDescription": "Synthetic test", "NSFaceIDUsageDescription": "Synthetic test",
        }
        (self.app / "Info.plist").write_bytes(plistlib.dumps(info))
        (self.app / "ChineseOCRResources.bundle").mkdir()
        self.ocr = self.app / "ChineseOCRResources.bundle/model.bincfg"
        self.ocr.write_bytes(b"synthetic model")
        self.runner = {
            "_fk_mnn_is_available", "_fk_mnn_runtime_version", "_fk_mnn_load_async",
            "_fk_mnn_generate_async", "_fk_mnn_cancel", "_fk_mnn_unload_async", "_fk_mnn_free",
            "__ZN3MNN11Transformer3Llm9createLLM_test",
            "_OBJC_CLASS_$_MLKChineseTextRecognizerOptions",
        }
        self.speech = {
            "_SherpaOnnxCreateOfflineRecognizer", "_SherpaOnnxCreateOnlineRecognizer",
            "_SherpaOnnxCreateOfflineTts", "_SherpaOnnxDestroyOfflineRecognizer",
            "_SherpaOnnxDestroyOnlineRecognizer", "_SherpaOnnxDestroyOfflineTts",
        }
        tool = patch.object(verify_ios_bundle.subprocess, "check_output", return_value="arm64\n")
        tool.start()
        self.addCleanup(tool.stop)
        symbol_reader = patch.object(verify_ios_bundle, "symbols", side_effect=
                                    lambda path: self.runner if path.name == "Runner" else self.speech)
        symbol_reader.start()
        self.addCleanup(symbol_reader.stop)

    def test_complete_capabilities_pass(self):
        verify_ios_bundle.verify(self.app)

    def test_bridge_without_mnn_implementation_fails(self):
        self.runner.remove("__ZN3MNN11Transformer3Llm9createLLM_test")
        with self.assertRaisesRegex(ValueError, "bridge alone"):
            verify_ios_bundle.verify(self.app)

    def test_missing_speech_lifecycle_symbol_fails(self):
        self.speech.remove("_SherpaOnnxDestroyOfflineTts")
        with self.assertRaisesRegex(ValueError, "Speech/TTS"):
            verify_ios_bundle.verify(self.app)

    def test_missing_ocr_model_fails(self):
        self.ocr.unlink()
        with self.assertRaisesRegex(ValueError, "resources"):
            verify_ios_bundle.verify(self.app)


if __name__ == "__main__":
    unittest.main()
