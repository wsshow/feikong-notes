import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1]


def release_url(env, name):
    value = env.get(name, "")
    uri = urlsplit(value)
    if (
        uri.scheme != "https"
        or not uri.hostname
        or uri.username is not None
        or uri.query
        or uri.fragment
        or any(char.isspace() or char in '"\\' for char in value)
    ):
        raise SystemExit(
            f"{name} must be a public HTTPS URL without credentials, query, or fragment."
        )
    return value


def copy_source(build_root):
    paths = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=ROOT,
    )
    for name in sorted(set(paths.split(b"\0")) - {b""}):
        relative = Path(os.fsdecode(name))
        source = ROOT / relative
        if source.is_file() or source.is_symlink():
            dest = build_root / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, dest, follow_symlinks=False)

    # Reuse cached native dependencies without copying generated app files.
    for pattern in (
        "build/app/mnn-runtime/downloads/mnn-*.zip",
        ".dart_tool/hooks_runner/shared/sqlite3/build/download-*/libsqlite3.*",
        ".dart_tool/hooks_runner/shared/pdfium_dart/build/chromium_*/*/libpdfium.*",
    ):
        for download in ROOT.glob(pattern):
            dest = build_root / download.relative_to(ROOT)
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(download, dest)

    local_properties = Path("android/local.properties")
    if (ROOT / local_properties).is_file():
        shutil.copy2(ROOT / local_properties, build_root / local_properties)


def main(flutter_command, dart_command, build_args):
    flutter = shutil.which(flutter_command)
    dart = shutil.which(dart_command)
    if flutter is None or dart is None:
        raise SystemExit("Flutter and Dart executables are required.")
    flutter = str(Path(flutter).absolute())
    dart = str(Path(dart).absolute())

    env = os.environ.copy()
    env["FKNOTES_RELEASE_BASE_URL"] = release_url(
        env, "FKNOTES_RELEASE_BASE_URL"
    ).rstrip("/")
    manifest_url = release_url(env, "FKNOTES_UPDATE_MANIFEST_URL")
    env["FKNOTES_RELEASE_ROOT"] = str(ROOT / "release/android")
    env["FKNOTES_ANDROID_SIGNING_PROJECT_DIR"] = str(ROOT / "android")
    env.pop("FKNOTES_ANDROID_ARM64_ONLY", None)
    build = [
        flutter,
        "build",
        "apk",
        "--release",
        *build_args,
        f"--dart-define=FKNOTES_UPDATE_MANIFEST_URL={manifest_url}",
    ]
    export = ["sh", "tool/export_android_release.sh"]
    # Flutter can embed the build directory in its generated plugin registrant.
    with tempfile.TemporaryDirectory(prefix="fknotes-release-", dir="/tmp") as temporary:
        build_root = Path(temporary)
        copy_source(build_root)
        subprocess.run([*export, "--check-notes"], cwd=build_root, env=env, check=True)
        subprocess.run(
            [dart, "pub", "get", "--enforce-lockfile"],
            cwd=build_root / "packages/fknotes_harness",
            env=env,
            check=True,
        )
        commands = [
            [flutter, "pub", "get", "--enforce-lockfile"],
            [flutter, "analyze", "--no-pub"],
            [flutter, "test", "--no-pub"],
            build,
            [*export, "--stage-universal"],
        ]
        for command in commands:
            subprocess.run(command, cwd=build_root, env=env, check=True)

        subprocess.run(
            [*build, "--target-platform", "android-arm64"],
            cwd=build_root,
            env={**env, "FKNOTES_ANDROID_ARM64_ONLY": "1"},
            check=True,
        )
        subprocess.run(export, cwd=build_root, env=env, check=True)


if __name__ == "__main__":
    try:
        main(sys.argv[1], sys.argv[2], sys.argv[3:])
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)
