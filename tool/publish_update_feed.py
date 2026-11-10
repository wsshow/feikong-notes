"""Commit an already published release manifest to the GitHub updates branch."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile


FEED_REF = "refs/heads/updates"
FEED_PATH = "android/latest.json"


def git(*args, **kwargs):
    return subprocess.check_output(["git", *args], text=True, **kwargs).strip()


def publish(manifest_path):
    text = manifest_path.read_text(encoding="utf-8")
    incoming = json.loads(text)
    # ls-remote must succeed; a network failure is not an absent branch.
    remote = git("ls-remote", "--heads", "origin", FEED_REF)
    parent = None
    if remote:
        git("fetch", "--no-tags", "origin", FEED_REF)
        parent = git("rev-parse", "FETCH_HEAD")
        current = json.loads(git("show", f"{parent}:{FEED_PATH}"))
        if current["versionCode"] > incoming["versionCode"]:
            print("A newer build is already published; keeping the current update feed.")
            return
        if current["versionCode"] == incoming["versionCode"]:
            if current != incoming:
                raise ValueError("A published build number cannot be reused with different metadata.")
            print("Update feed already matches this release.")
            return
    with tempfile.TemporaryDirectory(prefix="fknotes-feed-") as temporary:
        env = {
            **os.environ,
            "GIT_INDEX_FILE": str(Path(temporary) / "index"),
            "GIT_AUTHOR_NAME": "github-actions[bot]",
            "GIT_AUTHOR_EMAIL": "41898282+github-actions[bot]@users.noreply.github.com",
            "GIT_COMMITTER_NAME": "github-actions[bot]",
            "GIT_COMMITTER_EMAIL": "41898282+github-actions[bot]@users.noreply.github.com",
        }
        git("read-tree", parent if parent else "--empty", env=env)
        blob = git("hash-object", "-w", "--stdin", input=text)
        git("update-index", "--add", "--cacheinfo", f"100644,{blob},{FEED_PATH}", env=env)
        tree = git("write-tree", env=env)
        parents = ["-p", parent] if parent else []
        commit = git("commit-tree", tree, *parents, "-m",
                     f"Publish Android {incoming['version']}+{incoming['versionCode']}", env=env)
        # A concurrent publication is rejected by the normal fast-forward check.
        git("push", "origin", f"{commit}:{FEED_REF}")
    print("Published Android update feed.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    publish(parser.parse_args().manifest)
