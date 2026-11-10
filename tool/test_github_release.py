import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from prepare_github_release import prepare
from publish_update_feed import publish


class GitHubReleaseTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.notes = self.root / "release-notes.md"
        self.notes.write_text("# 本次更新\n\n修复与改进。\n", encoding="utf-8")
        for abi in ("universal", "arm64-v8a", "armeabi-v7a", "x86_64"):
            (self.root / f"fknotes-0.1.0+1-{abi}-release.apk").write_bytes(abi.encode())

    def prepare(self):
        return prepare(self.root, "owner/repo", "0.1.0", 1, self.notes,
                       "2026-11-10", False)

    def test_manifest_and_checksums_reference_actual_github_assets(self):
        manifest = self.prepare()
        self.assertEqual(manifest["changelog"],
                         "https://github.com/owner/repo/releases/download/v0.1.0/notes.md")
        for key, artifact in manifest["artifacts"].items():
            abi = key.removeprefix("android-")
            self.assertEqual(artifact["size"], len(abi.encode()))
            self.assertEqual(artifact["sha256"], hashlib.sha256(abi.encode()).hexdigest())
            self.assertIn(f"fknotes-0.1.0%2B1-{abi}-release.apk", artifact["url"])
        for line in (self.root / "SHA256SUMS.txt").read_text().splitlines():
            checksum, filename = line.split("  ")
            self.assertEqual(checksum, hashlib.sha256((self.root / filename).read_bytes()).hexdigest())

    def test_missing_required_apk_and_empty_notes_fail_before_manifest(self):
        required = self.root / "fknotes-0.1.0+1-universal-release.apk"
        required.unlink()
        with self.assertRaises(FileNotFoundError):
            self.prepare()
        self.assertFalse((self.root / "latest.json").exists())
        required.write_bytes(b"universal")
        self.notes.write_text(" \n")
        with self.assertRaises(ValueError):
            self.prepare()

    def test_local_export_can_omit_optional_split_apks(self):
        for abi in ("armeabi-v7a", "x86_64"):
            (self.root / f"fknotes-0.1.0+1-{abi}-release.apk").unlink()
        self.assertEqual(set(self.prepare()["artifacts"]),
                         {"android-universal", "android-arm64-v8a"})

    def test_noncanonical_date_is_rejected_by_generator(self):
        with self.assertRaises(ValueError):
            prepare(self.root, "owner/repo", "0.1.0", 1, self.notes,
                    "20261110", False)

    def test_feed_publication_is_atomic_monotonic_and_preserves_checkout(self):
        self.prepare()
        remote = self.root / "remote.git"
        checkout = self.root / "checkout"
        subprocess.run(["git", "init", "--bare", str(remote)], check=True, capture_output=True)
        subprocess.run(["git", "init", str(checkout)], check=True, capture_output=True)
        subprocess.run(["git", "-C", str(checkout), "remote", "add", "origin", str(remote)], check=True)
        old_cwd = Path.cwd()
        os.chdir(checkout)
        self.addCleanup(os.chdir, old_cwd)
        manifest_path = self.root / "latest.json"
        publish(manifest_path)
        head = subprocess.check_output(["git", "--git-dir", str(remote), "rev-parse", "updates"])
        publish(manifest_path)
        self.assertEqual(head, subprocess.check_output(["git", "--git-dir", str(remote), "rev-parse", "updates"]))
        manifest = json.loads(manifest_path.read_text())
        manifest["versionCode"] = 2
        manifest_path.write_text(json.dumps(manifest))
        publish(manifest_path)
        manifest["versionCode"] = 1
        manifest_path.write_text(json.dumps(manifest))
        publish(manifest_path)
        published = json.loads(subprocess.check_output(
            ["git", "--git-dir", str(remote), "show", "updates:android/latest.json"]))
        self.assertEqual(published["versionCode"], 2)
        manifest["versionCode"] = 2
        manifest["mandatory"] = True
        manifest_path.write_text(json.dumps(manifest))
        with self.assertRaises(ValueError):
            publish(manifest_path)
        self.assertFalse((checkout / "android").exists())
        self.assertFalse((checkout / ".git/index").exists())

    def test_network_failure_never_creates_a_replacement_feed(self):
        self.prepare()
        with patch("publish_update_feed.git", side_effect=subprocess.CalledProcessError(1, "git")) as git:
            with self.assertRaises(subprocess.CalledProcessError):
                publish(self.root / "latest.json")
            git.assert_called_once_with("ls-remote", "--heads", "origin", "refs/heads/updates")


if __name__ == "__main__":
    unittest.main()
