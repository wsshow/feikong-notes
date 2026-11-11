"""Verify native capabilities are linked/bundled, without claiming device inference."""

import argparse
from pathlib import Path
import plistlib
import re
import subprocess


def symbols(binary):
    result = subprocess.run(
        ["xcrun", "dyld_info", "-exports", str(binary)], check=True, capture_output=True, text=True
    )
    # Check the loader's exports, not a debug symbol table. Archive stripping
    # can leave code/dSYM symbols present while making Dart dlsym fail.
    return {match.group(1) for match in re.finditer(
        r"^\s*0x[0-9a-fA-F]+\s+(\S+)", result.stdout, re.MULTILINE
    )}


def verify(app):
    with (app / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("DTPlatformName") != "iphoneos":
        raise ValueError("Expected an iPhone device build, not a simulator build")
    if tuple(map(int, info["MinimumOSVersion"].split("."))) < (15, 5):
        raise ValueError("The app must target iOS 15.5 or later (ML Kit requirement)")
    extension = app / "PlugIns/ShareExtension.appex"
    with (extension / "Info.plist").open("rb") as stream:
        share = plistlib.load(stream)
    if share.get("NSExtension", {}).get("NSExtensionPointIdentifier") != "com.apple.share-services":
        raise ValueError("Share extension activation is missing")
    group = info.get("FKNotesAppGroup", "")
    if not group.startswith("group.") or "$" in group or share.get("FKNotesAppGroup") != group:
        raise ValueError("Runner and share extension must use the same resolved App Group")
    if share.get("CFBundleVersion") != info.get("CFBundleVersion") or share.get("CFBundleShortVersionString") != info.get("CFBundleShortVersionString"):
        raise ValueError("Share extension version must match the app")
    if share.get("CFBundleIdentifier") != info.get("CFBundleIdentifier", "") + ".ShareExtension":
        raise ValueError("Share extension identifier must match the app prefix")
    for language in ["en", "zh-Hans"]:
        if not (extension / f"{language}.lproj/Localizable.strings").is_file():
            raise ValueError("Share extension localized UI is missing")
    for bundle in [app, extension]:
        privacy = plistlib.loads((bundle / "PrivacyInfo.xcprivacy").read_bytes())
        reasons = {entry["NSPrivacyAccessedAPIType"]: set(entry["NSPrivacyAccessedAPITypeReasons"])
                   for entry in privacy.get("NSPrivacyAccessedAPITypes", [])}
        if not {"CA92.1", "1C8F.1"}.issubset(reasons.get("NSPrivacyAccessedAPICategoryUserDefaults", set())):
            raise ValueError("App and App Group preferences require privacy reasons")
        if not {"C617.1", "3B52.1"}.issubset(reasons.get("NSPrivacyAccessedAPICategoryFileTimestamp", set())):
            raise ValueError("Managed and user-selected file metadata require privacy reasons")
        for language in ["en", "zh-Hans"]:
            localized = bundle / f"{language}.lproj/InfoPlist.strings"
            if not localized.is_file():
                raise ValueError("Localized permission purposes are absent")
    for sdk in ["MLKitCommon", "MLKitTextRecognitionCommon", "MLKitBarcodeScanning"]:
        if not (app / f"{sdk}_Privacy.bundle/PrivacyInfo.xcprivacy").is_file():
            raise ValueError("Static ML Kit privacy manifests are absent")
    binary = app / info["CFBundleExecutable"]
    architectures = subprocess.check_output(["xcrun", "lipo", "-archs", str(binary)], text=True)
    if "arm64" not in architectures.split():
        raise ValueError("The app has no ARM64 executable")

    runner_symbols = symbols(binary)
    mnn_functions = {
        "_fk_mnn_is_available", "_fk_mnn_backend_mask", "_fk_mnn_runtime_version", "_fk_mnn_load_async",
        "_fk_mnn_generate_async", "_fk_mnn_cancel", "_fk_mnn_unload_async", "_fk_mnn_free",
    }
    missing = mnn_functions - runner_symbols
    if missing:
        raise ValueError(f"MNN FFI symbols missing: {sorted(missing)}")
    # Bridge symbols alone also exist in the unavailable-runtime stub.
    if not any("MNN" in name and "createLLM" in name for name in runner_symbols):
        raise ValueError("MNN LLM implementation is absent; the bridge alone is insufficient")

    litert = app / "Frameworks/CLiteRTLM.framework/CLiteRTLM"
    litert_functions = {
        "_litert_lm_engine_create", "_litert_lm_engine_delete",
        "_litert_lm_conversation_create", "_litert_lm_conversation_delete",
        "_litert_lm_conversation_cancel_process",
    }
    missing = litert_functions - symbols(litert)
    if missing:
        raise ValueError(f"LiteRT-LM lifecycle symbols missing: {sorted(missing)}")

    speech = app / "Frameworks/sherpa_onnx.framework/sherpa_onnx"
    speech_functions = {
        "_SherpaOnnxCreateOfflineRecognizer", "_SherpaOnnxCreateOnlineRecognizer",
        "_SherpaOnnxCreateOfflineTts", "_SherpaOnnxDestroyOfflineRecognizer",
        "_SherpaOnnxDestroyOnlineRecognizer", "_SherpaOnnxDestroyOfflineTts",
    }
    missing = speech_functions - symbols(speech)
    if missing:
        raise ValueError(f"Speech/TTS native symbols missing: {sorted(missing)}")

    if "_OBJC_CLASS_$_MLKChineseTextRecognizerOptions" not in runner_symbols:
        raise ValueError("Chinese OCR native implementation is absent")
    for name in ["ChineseOCRResources.bundle", "LatinOCRResources.bundle"]:
        ocr = app / name
        if not ocr.is_dir() or not any(p.stat().st_size > 0 for p in ocr.rglob("*.bincfg")):
            raise ValueError(f"Bundled OCR resources are absent: {name}")
    for key in ["NSMicrophoneUsageDescription", "NSCameraUsageDescription",
                "NSPhotoLibraryUsageDescription", "NSFaceIDUsageDescription"]:
        if not info.get(key):
            raise ValueError(f"Missing permission purpose: {key}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", nargs="?", type=Path,
                        default=Path(__file__).resolve().parents[1] / "build/ios/iphoneos/Runner.app")
    arguments = parser.parse_args()
    verify(arguments.app)
    print("PASS: iPhone ARM64 bundle, MNN LLM/FFI, LiteRT-LM, sherpa ASR/TTS, Chinese OCR and permission purposes.")
    print("This verifies packaging only; device inference, permissions and UI remain unverified.")


if __name__ == "__main__":
    main()
