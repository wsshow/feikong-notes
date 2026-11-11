import hashlib
import io
from pathlib import Path
import tarfile
import tempfile
import unittest

from prepare_mnn_ios_simulator import extract_source, VERSION


class MnnSourceTest(unittest.TestCase):
    def archive(self, root, name, link=False):
        archive = root / "source.tar.gz"
        with tarfile.open(archive, "w:gz") as target:
            member = tarfile.TarInfo(name)
            if link:
                member.type = tarfile.SYMTYPE
                member.linkname = "../../outside"
                target.addfile(member)
            else:
                member.size = 9
                target.addfile(member, io.BytesIO(b"synthetic"))
        return archive, hashlib.sha256(archive.read_bytes()).hexdigest()

    def test_changed_download_is_rejected_before_extraction(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive, checksum = self.archive(root, f"MNN-{VERSION}/LICENSE")
            with self.assertRaisesRegex(ValueError, "checksum"):
                extract_source(archive, root / "out", "wrong")
            self.assertFalse((root / "out").exists())
            extract_source(archive, root / "out", checksum)
            self.assertEqual((root / f"out/MNN-{VERSION}/LICENSE").read_bytes(), b"synthetic")

    def test_archive_cannot_write_outside_build_cache(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive, checksum = self.archive(root, f"MNN-{VERSION}/../../outside")
            with self.assertRaisesRegex(ValueError, "Unsafe"):
                extract_source(archive, root / "out", checksum)
            self.assertFalse((root / "outside").exists())

    def test_documentation_symlinks_are_not_materialized(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive, checksum = self.archive(root, f"MNN-{VERSION}/docs/link", link=True)
            extract_source(archive, root / "out", checksum)
            self.assertFalse((root / f"out/MNN-{VERSION}/docs/link").is_symlink())


if __name__ == "__main__":
    unittest.main()
