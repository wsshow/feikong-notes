"""Run the production shared inbox against synthetic files on macOS."""
from pathlib import Path
import platform
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(platform.system() == "Darwin", "requires the Apple Swift SDK")
class ShareInboxTests(unittest.TestCase):
    def test_atomic_bounded_inbox(self):
        with tempfile.TemporaryDirectory() as temp:
            executable = str(Path(temp) / "share-inbox")
            compiled = subprocess.run([
                "xcrun", "swiftc", "-o", executable,
                str(ROOT / "ios/Runner/ShareInbox.swift"),
                str(ROOT / "tool/ios_share_inbox_test.swift"),
            ], capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            result = subprocess.run([executable], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
