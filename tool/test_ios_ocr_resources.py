import hashlib
from pathlib import Path
import tempfile
import unittest
import zipfile

from prepare_ios_ocr_resources import extract_bundle


class OcrResourcesTest(unittest.TestCase):
    def test_checksum_and_model_payload_are_required(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive = root / "models.zip"
            name = "ChineseOCRResources.bundle"
            with zipfile.ZipFile(archive, "w") as zipped:
                zipped.writestr(f"{name}/model.bincfg", b"synthetic")
            checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
            with self.assertRaisesRegex(ValueError, "checksum"):
                extract_bundle(archive, root / "output", name, "wrong")
            result = extract_bundle(archive, root / "output", name, checksum)
            self.assertEqual((result / "model.bincfg").read_bytes(), b"synthetic")

    def test_archive_cannot_escape_its_destination(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive = root / "bad.zip"
            with zipfile.ZipFile(archive, "w") as zipped:
                zipped.writestr("../outside", b"synthetic")
            checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
            with self.assertRaisesRegex(ValueError, "Unsafe"):
                extract_bundle(archive, root / "output", "ChineseOCRResources.bundle", checksum)
            self.assertFalse((root / "outside").exists())


if __name__ == "__main__":
    unittest.main()
