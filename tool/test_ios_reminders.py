"""Exercise the production SQLite projection without an iPhone."""
from pathlib import Path
import platform
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(platform.system() == "Darwin", "requires the Apple Swift SDK")
class ReminderStoreTests(unittest.TestCase):
    def test_read_only_projection(self):
        with tempfile.TemporaryDirectory() as temp:
            executable = str(Path(temp) / "reminders")
            subprocess.run([
                "xcrun", "swiftc", "-o", executable,
                str(ROOT / "ios/Runner/ReminderStore.swift"),
                str(ROOT / "tool/ios_reminder_store_test.swift"),
            ], check=True, capture_output=True, text=True)
            subprocess.run([executable], check=True, capture_output=True, text=True)


if __name__ == "__main__":
    unittest.main()
