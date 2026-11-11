import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest
from unittest.mock import patch

import build_android_release
from prepare_github_release import prepare
from release_notes import github_releases, resolve


def release(tag, body=None, draft=False):
    return {"tag_name": tag, "body": body, "draft": draft}


class ReleaseNotesTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Release Test")
        self.git("config", "user.email", "release@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        self.commit("feat: 初始笔记")

    def git(self, *args):
        return subprocess.check_output(
            ["git", "-C", str(self.root), *args], text=True, stderr=subprocess.PIPE,
        ).strip()

    def commit(self, subject):
        self.git("commit", "--allow-empty", "-m", subject)
        return self.git("rev-parse", "HEAD")

    def resolve(self, releases, tag="v0.2.0", target="HEAD"):
        with patch("release_notes.github_releases", return_value=releases):
            return resolve(self.root, "owner/repo", tag, target)

    def test_draft_body_is_shared_with_manifest_notes_without_interpolation(self):
        body = "# 本次更新\n\n- 修复中文输入。\n- 保留 `$()` 与 Markdown。\n"
        with patch("release_notes.git", side_effect=AssertionError("No Git fallback")):
            notes, state = self.resolve([release("v0.2.0", body, True)])
        self.assertEqual((notes, state), (body, "draft"))
        notes_path = self.root / "source.md"
        notes_path.write_text(notes)
        for abi in ("universal", "arm64-v8a"):
            (self.root / f"fknotes-0.2.0+2-{abi}-release.apk").write_bytes(b"apk")
        prepare(self.root, "owner/repo", "0.2.0", 2, notes_path, "2026-11-10", False)
        self.assertEqual((self.root / "notes.md").read_text(), body)

    def test_published_body_is_reused_and_empty_published_body_fails(self):
        self.assertEqual(self.resolve([release("v0.2.0", "旧正文")]),
                         ("旧正文\n", "published"))
        with self.assertRaisesRegex(ValueError, "Published release body is empty"):
            self.resolve([release("v0.2.0", " ")])

    def test_first_release_falls_back_to_all_history(self):
        self.commit("fix: 修复保存")
        notes, state = self.resolve([])
        self.assertEqual(state, "missing")
        self.assertIn("首次发布", notes)
        self.assertIn("初始笔记", notes)
        self.assertIn("修复保存", notes)
        self.assertIn("未经人工整理", notes)

    def test_fallback_uses_previous_published_ancestor_and_exact_target(self):
        self.git("tag", "v0.1.0")
        self.git("checkout", "-b", "unrelated")
        self.commit("feat: 不属于当前版本")
        self.git("tag", "v9.0.0")
        self.git("checkout", "main")
        self.commit("feat: 较早的发布")
        self.git("-c", "tag.gpgsign=false", "tag", "-a", "v0.1.1", "-m", "release")
        self.commit("fix: 本次保存修复")
        self.git("tag", "v0.1.9")  # Unpublished tags must not truncate notes.
        target = self.commit("feat: 本次搜索优化")
        self.git("tag", "v0.2.0")
        self.commit("feat: 目标之后的变更")
        releases = [release("v0.1.0"), release("v9.0.0"),
                    release("v0.1.9", draft=True), release("v0.1.1")]
        notes, _ = self.resolve(releases, target=target)
        self.assertIn("从 v0.1.1 到 v0.2.0", notes)
        self.assertIn("本次保存修复", notes)
        self.assertIn("本次搜索优化", notes)
        for excluded in ("初始笔记", "不属于当前版本", "较早的发布", "目标之后的变更"):
            self.assertNotIn(excluded, notes)

    def test_blank_draft_falls_back_and_handles_no_new_commits(self):
        self.git("tag", "v0.1.0")
        notes, state = self.resolve([release("v0.1.0"), release("v0.2.0", " \n", True)])
        self.assertEqual(state, "draft")
        self.assertIn("没有新增提交", notes)

    def test_fallback_escapes_commit_subject_markdown_and_html(self):
        self.commit("fix: <script> [链接](https://example.invalid) `命令` *文本*")
        notes, _ = self.resolve([])
        self.assertNotIn("<script>", notes)
        self.assertIn("&lt;script&gt;", notes)
        self.assertIn(r"\[链接\]\(https://example\.invalid\)", notes)
        self.assertIn(r"\`命令\`", notes)

    def test_missing_published_tag_and_shallow_history_fail(self):
        with self.assertRaisesRegex(ValueError, "fetch all tags"):
            self.resolve([release("v0.1.0")])
        shallow = self.root / "shallow"
        subprocess.run(["git", "clone", "--depth=1", self.root.as_uri(), str(shallow)],
                       check=True, capture_output=True)
        with patch("release_notes.github_releases", return_value=[]):
            with self.assertRaisesRegex(ValueError, "full history"):
                resolve(shallow, "owner/repo", "v0.2.0")

    def test_api_errors_never_trigger_commit_fallback(self):
        for error in (subprocess.CalledProcessError(1, "gh"),
                      FileNotFoundError("gh"), ValueError("invalid JSON")):
            with self.subTest(error=type(error).__name__):
                with patch("release_notes.github_releases", side_effect=error), \
                        patch("release_notes.commit_notes") as fallback:
                    with self.assertRaises(type(error)):
                        resolve(self.root, "owner/repo", "v0.2.0")
                    fallback.assert_not_called()

    def test_api_paginates_drafts_and_validates_response(self):
        pages = [[release("v0.1.0")], [release("v0.2.0", "草稿", True)]]
        result = subprocess.CompletedProcess([], 0, json.dumps(pages))
        with patch("release_notes.subprocess.run", return_value=result) as run:
            self.assertEqual(github_releases("owner/repo"), pages[0] + pages[1])
            self.assertEqual(run.call_args.args[0], [
                "gh", "api", "--paginate", "--slurp", "repos/owner/repo/releases?per_page=100",
            ])
        for invalid in ({"message": "error"}, [[{"tag_name": "v0.2.0"}]]):
            result.stdout = json.dumps(invalid)
            with patch("release_notes.subprocess.run", return_value=result):
                with self.assertRaises(ValueError):
                    github_releases("owner/repo")

    def test_github_cli_failures_explain_the_problem(self):
        error = subprocess.CalledProcessError(1, "gh", stderr="HTTP 403: access denied")
        with patch("release_notes.subprocess.run", side_effect=error):
            with self.assertRaisesRegex(RuntimeError, "HTTP 403: access denied"):
                github_releases("owner/repo")
        with patch("release_notes.subprocess.run", side_effect=FileNotFoundError("gh")):
            with self.assertRaisesRegex(RuntimeError, "Install GitHub CLI"):
                github_releases("owner/repo")

    def test_invalid_tag_and_duplicate_release_fail(self):
        with self.assertRaises(ValueError):
            self.resolve([], tag="--all")
        with self.assertRaisesRegex(ValueError, "Multiple"):
            self.resolve([release("v0.2.0", "a"), release("v0.2.0", "b", True)])

    def test_cli_writes_notes_and_action_state_without_external_writes(self):
        binary = self.root / "bin"
        binary.mkdir()
        gh = binary / "gh"
        gh.write_text("#!/bin/sh\nprintf '%s' '[[{\"tag_name\":\"v0.2.0\","
                      "\"draft\":true,\"body\":\"测试正文\"}]]'\n")
        gh.chmod(0o755)
        output = self.root / "output/notes.md"
        action_output = self.root / "action-output"
        script = Path(__file__).with_name("release_notes.py")
        subprocess.run(["python3", str(script), "--repository", "owner/repo",
                        "--tag", "v0.2.0", "--output", str(output),
                        "--github-output", str(action_output)], check=True,
                       env={**os.environ, "PATH": f"{binary}:{os.environ['PATH']}"},
                       capture_output=True)
        self.assertEqual(output.read_text(), "测试正文\n")
        self.assertEqual(action_output.read_text(), "state=draft\n")

    def test_local_isolated_build_resolves_once_using_original_git_checkout(self):
        (self.root / "pubspec.yaml").write_text("version: 0.2.0+2\n")
        calls = []

        def run(command, *, cwd, env, check):
            calls.append(command)
            self.assertNotEqual(Path(cwd), self.root)
            self.assertFalse((Path(cwd) / ".git").exists())
            self.assertEqual(Path(env["FKNOTES_RELEASE_NOTES_PATH"]).read_text(), "共用正文\n")

        with patch.object(build_android_release, "ROOT", self.root), \
                patch.object(build_android_release, "copy_source"), \
                patch.object(build_android_release, "resolve", return_value=("共用正文\n", "draft")) as resolver, \
                patch.object(build_android_release.shutil, "which", return_value="/fake/flutter"), \
                patch.object(build_android_release.subprocess, "run", side_effect=run), \
                patch.dict(os.environ, {"FKNOTES_GITHUB_REPOSITORY": "owner/repo"}):
            build_android_release.main("flutter", "dart", [])
        resolver.assert_called_once_with(self.root, "owner/repo", "v0.2.0")
        self.assertEqual(calls[0], ["sh", "tool/export_android_release.sh", "--check-notes"])
        self.assertEqual(calls[-1], ["sh", "tool/export_android_release.sh"])

    def test_export_preflight_resolves_notes_without_versioned_markdown(self):
        tool_dir = self.root / "tool"
        tool_dir.mkdir()
        for name in ("export_android_release.sh", "release_notes.py", "prepare_github_release.py"):
            (tool_dir / name).write_bytes(Path(__file__).with_name(name).read_bytes())
        (self.root / "pubspec.yaml").write_text("version: 0.2.0+2\n")
        binary = self.root / "bin"
        binary.mkdir()
        gh = binary / "gh"
        gh.write_text("#!/bin/sh\nprintf '%s' '[[]]'\n")
        gh.chmod(0o755)
        env = {**os.environ, "PATH": f"{binary}:{os.environ['PATH']}",
               "FKNOTES_GITHUB_REPOSITORY": "owner/repo",
               "FKNOTES_RELEASE_ROOT": str(self.root / "release/android")}
        env.pop("FKNOTES_RELEASE_NOTES_PATH", None)
        subprocess.run(["sh", str(tool_dir / "export_android_release.sh"), "--check-notes"],
                       cwd=self.root, env=env, check=True, capture_output=True)
        notes = (self.root / "release/android/0.2.0/notes.md").read_text()
        self.assertIn("初始笔记", notes)
        self.assertFalse((self.root / "docs/releases").exists())

    def test_workflow_publication_branches_with_fake_github(self):
        # Execute the real workflow shell with a fake CLI. Nothing reaches GitHub.
        workflow = Path(__file__).resolve().parents[1] / ".github/workflows/release.yml"
        step = workflow.read_text().split("      - name: Publish GitHub Release\n", 1)[1]
        script = textwrap.dedent(step.split("        run: |\n", 1)[1]
                                 .split("\n      - name:", 1)[0])
        binary = self.root / "bin"
        binary.mkdir()
        gh = binary / "gh"
        gh.write_text(f"#!{sys.executable}\n" + textwrap.dedent('''\
            import json
            import os
            from pathlib import Path
            import sys
            args = sys.argv[1:]
            with Path("calls.jsonl").open("a") as log:
                log.write(json.dumps(args) + "\\n")
            action = args[1]
            if action == "view":
                if os.environ.get("VIEW_ERROR"):
                    sys.exit(1)
                print(os.environ.get("CURRENT_DRAFT", "true"))
            elif action in ("edit", "create"):
                notes = Path(args[args.index("--notes-file") + 1]).read_text()
                Path("published-body.md").write_text(notes)
            elif action == "download":
                Path("published/latest.json").write_text(json.dumps({
                    "app": "fknotes", "version": "0.2.0", "versionCode": 2,
                }))
            elif action != "upload":
                sys.exit(2)
        '''))
        gh.chmod(0o755)
        for state, current, error in (("draft", "true", ""), ("missing", "", ""),
                                      ("published", "", ""), ("draft", "false", ""),
                                      ("draft", "true", "yes")):
            with self.subTest(state=state, current=current, error=error):
                case = self.root / f"case-{state}-{current}-{error}"
                (case / "dist").mkdir(parents=True)
                body = "# 更新\n包含 `$()` 和中文。\n"
                (case / "dist/notes.md").write_text(body)
                (case / "dist/fknotes-0.2.0-ios-unsigned.ipa").write_bytes(b"synthetic IPA")
                (case / "dist/ios-installation.md").write_text("Experimental install guide")
                env = {**os.environ, "PATH": f"{binary}:{os.environ['PATH']}",
                       "RELEASE_STATE": state, "CURRENT_DRAFT": current, "VIEW_ERROR": error,
                       "GITHUB_REF_NAME": "main", "RELEASE_TAG": "v0.2.0", "GITHUB_REPOSITORY": "owner/repo",
                       "VERSION_NAME": "0.2.0", "BUILD_NUMBER": "2"}
                result = subprocess.run(["bash", "-c", script], cwd=case, env=env,
                                        capture_output=True, text=True)
                calls = [json.loads(line) for line in (case / "calls.jsonl").read_text().splitlines()]
                actions = [call[1] for call in calls]
                if state == "draft" and (current == "false" or error):
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(actions, ["view"])
                    continue
                self.assertEqual(result.returncode, 0, result.stderr)
                if state == "published":
                    self.assertEqual(actions, ["download"])
                    self.assertFalse((case / "published-body.md").exists())
                else:
                    self.assertEqual(actions, ["view", "upload", "edit", "download"]
                                     if state == "draft" else ["create", "download"])
                    self.assertEqual((case / "published-body.md").read_text(), body)
                    mutation = next(call for call in calls if call[1] in ("edit", "create"))
                    self.assertIn("--prerelease", mutation)
                    self.assertEqual(mutation[2], "v0.2.0")
                    upload = next(call for call in calls if call[1] in ("upload", "create"))
                    self.assertIn("dist/fknotes-0.2.0-ios-unsigned.ipa", upload)
                    self.assertIn("dist/ios-installation.md", upload)


if __name__ == "__main__":
    unittest.main()
