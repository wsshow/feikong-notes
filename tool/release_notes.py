"""Read release notes from GitHub, falling back to the actual Git commit range."""

import argparse
import html
import json
from pathlib import Path
import re
import subprocess

from prepare_github_release import DEFAULT_REPOSITORY, repository_name


RELEASE_TAG = re.compile(r"v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?")


def github_releases(repository):
    # Unlike the by-tag endpoint, listing releases includes accessible drafts.
    # Do not turn authentication, network, or API failures into "no draft".
    repository_name(repository)
    try:
        result = subprocess.run(
            ["gh", "api", "--paginate", "--slurp",
             f"repos/{repository}/releases?per_page=100"],
            check=True, capture_output=True, text=True, encoding="utf-8",
        )
    except FileNotFoundError as error:
        raise RuntimeError("Install GitHub CLI (gh) and sign in with repository write access.") from error
    except subprocess.CalledProcessError as error:
        detail = (error.stderr or "GitHub API request failed").strip()
        raise RuntimeError(f"Cannot read GitHub releases: {detail}") from error
    pages = json.loads(result.stdout)
    if not isinstance(pages, list) or any(not isinstance(page, list) for page in pages):
        raise ValueError("GitHub returned an invalid release list.")
    releases = [release for page in pages for release in page]
    for release in releases:
        if (not isinstance(release, dict)
                or not isinstance(release.get("tag_name"), str)
                or not isinstance(release.get("draft"), bool)
                or not isinstance(release.get("body"), (str, type(None)))):
            raise ValueError("GitHub returned invalid release metadata.")
    return releases


def git(root, *args):
    return subprocess.check_output(
        ["git", "-C", str(root), *args], text=True, encoding="utf-8", stderr=subprocess.PIPE,
    ).strip()


def markdown_text(value):
    value = html.escape(value, quote=False)
    return re.sub(r"([\\`*_{}\[\]()#+.!|~])", r"\\\1", value)


def commit_notes(root, tag, target, releases):
    if git(root, "rev-parse", "--is-shallow-repository") == "true":
        raise ValueError("Commit fallback requires full history; fetch history and tags first.")
    target_sha = git(root, "rev-parse", "--verify", f"{target}^{{commit}}")
    # Topological order selects the nearest reachable published release, ignoring
    # unrelated branches, arbitrary non-release tags, drafts, and the target tag.
    history = git(root, "rev-list", "--topo-order", target_sha).splitlines()
    positions = {sha: index for index, sha in enumerate(history)}
    candidates = []
    for release in releases:
        previous = release["tag_name"]
        if release["draft"] or previous == tag or not RELEASE_TAG.fullmatch(previous):
            continue
        try:
            sha = git(root, "rev-parse", "--verify", f"refs/tags/{previous}^{{commit}}")
        except subprocess.CalledProcessError as error:
            raise ValueError(f"Missing published tag {previous}; fetch all tags first.") from error
        if sha in positions:
            candidates.append((positions[sha], previous, sha))
    previous = min(candidates) if candidates else None
    revision = f"{previous[2]}..{target_sha}" if previous else target_sha
    commits = git(root, "log", "--reverse", "--format=%h %s", revision).splitlines()
    scope = (f"从 {previous[1]} 到 {tag} 的提交记录。" if previous else
             f"首次发布，以下为截至 {tag} 的提交记录。")
    lines = [f"# 非空笔记 {tag[1:]}", "", "## 更新记录", "",
             "未提供 Release 草稿正文，以下内容由提交记录自动生成，未经人工整理。",
             scope, ""]
    lines.extend(f"- {markdown_text(commit)}" for commit in commits)
    if not commits:
        lines.append("- 与上一发布版本相比，没有新增提交。")
    return "\n".join(lines) + "\n"


def resolve(root, repository, tag, target="HEAD"):
    if not RELEASE_TAG.fullmatch(tag):
        raise ValueError("Release tag must use v-prefixed SemVer.")
    releases = github_releases(repository)
    matching = [release for release in releases if release["tag_name"] == tag]
    if len(matching) > 1:
        raise ValueError(f"Multiple GitHub releases match {tag}.")
    release = matching[0] if matching else None
    state = "missing" if release is None else "draft" if release["draft"] else "published"
    body = (release.get("body") or "").strip() if release else ""
    if body:
        return body + "\n", state
    if state == "published":
        raise ValueError("Published release body is empty; refusing to invent replacement notes.")
    return commit_notes(root, tag, target, releases), state


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", default=DEFAULT_REPOSITORY)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--target", default="HEAD")
    parser.add_argument("--source-dir", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--github-output", type=Path)
    args = parser.parse_args()
    notes, state = resolve(args.source_dir, args.repository, args.tag, args.target)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(notes, encoding="utf-8")
    if args.github_output:
        with args.github_output.open("a", encoding="utf-8") as output:
            output.write(f"state={state}\n")
    print(f"Release notes resolved ({state}): {args.output}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, OSError) as error:
        raise SystemExit(str(error)) from error
    except subprocess.CalledProcessError as error:
        raise SystemExit((error.stderr or str(error)).strip()) from error
