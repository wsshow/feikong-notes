"""Regression checks prevent a stub-only build from passing native verification."""

from pathlib import Path
import plistlib
import tempfile
import unittest
import subprocess
from unittest.mock import patch

import verify_ios_bundle


class IosExportSymbolsTest(unittest.TestCase):
    def test_loader_exports_ignore_headers_and_weak_annotations(self):
        output = "Runner [arm64]:\n    -exports:\n offset symbol\n 0x00004000 _fk_mnn_is_available\n 0x00004100 _weak_symbol [weak-def]\n"
        with patch.object(verify_ios_bundle.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, stdout=output)) as run:
            self.assertEqual(verify_ios_bundle.symbols(Path("Runner")), {"_fk_mnn_is_available", "_weak_symbol"})
            self.assertEqual(run.call_args.args[0][1:3], ["dyld_info", "-exports"])


class IosBundleTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="fknotes-bundle-test-")
        self.addCleanup(self.temporary.cleanup)
        self.app = Path(self.temporary.name)
        info = {
            "FKNotesAppGroup": "group.test.synthetic", "CFBundleIdentifier": "test.synthetic",
            "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0.0",
            "DTPlatformName": "iphoneos", "MinimumOSVersion": "15.0", "CFBundleExecutable": "Runner",
            "NSMicrophoneUsageDescription": "Synthetic test", "NSCameraUsageDescription": "Synthetic test",
            "NSPhotoLibraryUsageDescription": "Synthetic test", "NSFaceIDUsageDescription": "Synthetic test",
        }
        (self.app / "Info.plist").write_bytes(plistlib.dumps(info))
        extension = self.app / "PlugIns/ShareExtension.appex"
        extension.mkdir(parents=True)
        (extension / "Info.plist").write_bytes(plistlib.dumps({
            "NSExtension": {"NSExtensionPointIdentifier": "com.apple.share-services"},
            "FKNotesAppGroup": "group.test.synthetic", "CFBundleIdentifier": "test.synthetic.ShareExtension",
            "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0.0",
        }))
        for language in ["en", "zh-Hans"]:
            (extension / f"{language}.lproj").mkdir()
            (extension / f"{language}.lproj/Localizable.strings").write_text("synthetic")
        privacy = {"NSPrivacyAccessedAPITypes": [
            {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults", "NSPrivacyAccessedAPITypeReasons": ["CA92.1", "1C8F.1"]},
            {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryFileTimestamp", "NSPrivacyAccessedAPITypeReasons": ["C617.1", "3B52.1"]},
        ]}
        for bundle in [self.app, extension]:
            (bundle / "PrivacyInfo.xcprivacy").write_bytes(plistlib.dumps(privacy))
            for language in ["en", "zh-Hans"]:
                (bundle / f"{language}.lproj").mkdir(exist_ok=True)
                (bundle / f"{language}.lproj/InfoPlist.strings").write_text("synthetic")
        for sdk in ["MLKitCommon", "MLKitTextRecognitionCommon", "MLKitBarcodeScanning"]:
            folder = self.app / f"{sdk}_Privacy.bundle"
            folder.mkdir()
            (folder / "PrivacyInfo.xcprivacy").write_bytes(plistlib.dumps({}))
        (self.app / "LatinOCRResources.bundle").mkdir()
        (self.app / "LatinOCRResources.bundle/model.bincfg").write_bytes(b"synthetic latin model")
        (self.app / "ChineseOCRResources.bundle").mkdir()
        self.ocr = self.app / "ChineseOCRResources.bundle/model.bincfg"
        self.ocr.write_bytes(b"synthetic model")
        self.runner = {
            "_fk_mnn_is_available", "_fk_mnn_backend_mask", "_fk_mnn_runtime_version", "_fk_mnn_load_async",
            "_fk_mnn_generate_async", "_fk_mnn_cancel", "_fk_mnn_unload_async", "_fk_mnn_free",
            "__ZN3MNN11Transformer3Llm9createLLM_test",
            "_OBJC_CLASS_$_MLKChineseTextRecognizerOptions",
        }
        self.litert = {
            "_litert_lm_engine_create", "_litert_lm_engine_delete",
            "_litert_lm_conversation_create", "_litert_lm_conversation_delete",
            "_litert_lm_conversation_cancel_process",
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
                                    lambda path: self.runner if path.name == "Runner" else self.litert if path.name == "CLiteRTLM" else self.speech)
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

    def test_mismatched_share_group_fails(self):
        path = self.app / "PlugIns/ShareExtension.appex/Info.plist"
        info = plistlib.loads(path.read_bytes())
        info["FKNotesAppGroup"] = "group.other"
        path.write_bytes(plistlib.dumps(info))
        with self.assertRaisesRegex(ValueError, "App Group"):
            verify_ios_bundle.verify(self.app)

    def test_missing_static_sdk_privacy_fails(self):
        (self.app / "MLKitCommon_Privacy.bundle/PrivacyInfo.xcprivacy").unlink()
        with self.assertRaisesRegex(ValueError, "ML Kit privacy"):
            verify_ios_bundle.verify(self.app)

    def test_missing_litert_cancellation_fails(self):
        self.litert.remove("_litert_lm_conversation_cancel_process")
        with self.assertRaisesRegex(ValueError, "LiteRT-LM"):
            verify_ios_bundle.verify(self.app)

    def test_missing_ocr_model_fails(self):
        self.ocr.unlink()
        with self.assertRaisesRegex(ValueError, "resources"):
            verify_ios_bundle.verify(self.app)


if __name__ == "__main__":
    unittest.main()
