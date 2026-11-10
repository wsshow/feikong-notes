"""Synthetic AVFoundation decoding checks on macOS; no microphone or model."""

import math
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
import wave


@unittest.skipUnless(sys.platform == "darwin", "Requires macOS AVFoundation")
class IosAudioDecodeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workspace = tempfile.TemporaryDirectory(prefix="fknotes-audio-test-")
        cls.root = Path(cls.workspace.name)
        cls.binary = cls.root / "decode"
        repo = Path(__file__).resolve().parents[1]
        subprocess.run([
            "xcrun", "swiftc", "-parse-as-library",
            str(repo / "ios/Runner/AudioFileDecoder.swift"),
            str(repo / "tool/ios_audio_decode_test.swift"),
            "-o", str(cls.binary),
        ], check=True, capture_output=True, text=True)

    @classmethod
    def tearDownClass(cls):
        cls.workspace.cleanup()

    def test_m4a_resamples_mono_and_stereo_without_changing_source(self):
        for channels in [1, 2]:
            with self.subTest(channels=channels):
                original = self.root / f"tone-{channels}.wav"
                m4a = self.root / f"tone-{channels}.m4a"
                output = self.root / f"decoded-{channels}.wav"
                with wave.open(str(original), "wb") as stream:
                    stream.setparams((channels, 2, 44100, 0, "NONE", "not compressed"))
                    stream.writeframes(b"".join(
                        struct.pack("<h", int(10000 * math.sin(i * 2 * math.pi * 440 / 44100))) * channels
                        for i in range(44100)
                    ))
                subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "96000",
                                str(original), str(m4a)], check=True, capture_output=True)
                source_bytes = m4a.read_bytes()
                subprocess.run([str(self.binary), str(m4a), str(output)], check=True)
                self.assertEqual(m4a.read_bytes(), source_bytes)
                with wave.open(str(output), "rb") as stream:
                    self.assertEqual((stream.getnchannels(), stream.getsampwidth(), stream.getframerate()), (1, 2, 16000))
                    self.assertAlmostEqual(stream.getnframes() / 16000, 1.0, delta=0.1)
                    samples = struct.unpack(f"<{stream.getnframes()}h", stream.readframes(stream.getnframes()))
                    self.assertGreater(max(abs(x) for x in samples), 1000)

    def test_failure_and_cancellation_do_not_leave_output(self):
        source = self.root / "invalid.m4a"
        source.write_bytes(b"synthetic invalid audio")
        for mode in [[], ["cancel"]]:
            output = self.root / "failed.wav"
            result = subprocess.run([str(self.binary), str(source), str(output), *mode])
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())
            self.assertEqual(source.read_bytes(), b"synthetic invalid audio")

    def test_source_cannot_be_overwritten(self):
        source = self.root / "protected.m4a"
        source.write_bytes(b"preserve original")
        result = subprocess.run([str(self.binary), str(source), str(source)])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(source.read_bytes(), b"preserve original")


if __name__ == "__main__":
    unittest.main()
