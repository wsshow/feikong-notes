"""Verify native capabilities are linked/bundled, without claiming device inference."""

import argparse
from pathlib import Path
import plistlib
import subprocess


def symbols(binary):
    result = subprocess.run(
        ["xcrun", "nm", "-gU", str(binary)], check=True, capture_output=True, text=True
    )
    return {line.split()[-1] for line in result.stdout.splitlines() if line.split()}


def verify(app):
    with (app / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("DTPlatformName") != "iphoneos":
        raise ValueError("Expected an iPhone device build, not a simulator build")
    if tuple(map(int, info["MinimumOSVersion"].split("."))) < (15, 0):
        raise ValueError("The app must target iOS 15.0 or later")
    binary = app / info["CFBundleExecutable"]
    architectures = subprocess.check_output(["xcrun", "lipo", "-archs", str(binary)], text=True)
    if "arm64" not in architectures.split():
        raise ValueError("The app has no ARM64 executable")

    runner_symbols = symbols(binary)
    mnn_functions = {
        "_fk_mnn_is_available", "_fk_mnn_runtime_version", "_fk_mnn_load_async",
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

    ocr = app / "ChineseOCRResources.bundle"
    if "_OBJC_CLASS_$_MLKChineseTextRecognizerOptions" not in runner_symbols:
        raise ValueError("Chinese OCR native implementation is absent")
    if not ocr.is_dir() or not any(p.stat().st_size > 0 for p in ocr.rglob("*.bincfg")):
        raise ValueError("Bundled Chinese OCR resources are absent")
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
