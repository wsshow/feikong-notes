import argparse
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
from zipfile import BadZipFile, ZipFile


APP_LIBRARY = re.compile(r"(?:base/)?lib/[^/]+/libapp\.so")
PERSONAL_PATH = re.compile(
    rb"(?:/Users/|/home/(?!runner/work/)|[A-Z]:[\\/]Users[\\/])"
    rb"[^/\\\x00\r\n]{1,200}[/\\]",
    re.IGNORECASE,
)

BUNDLETOOL_VERSION = "1.18.3"
BUNDLETOOL_SHA256 = "a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29"
ANDROID_NAMESPACE = "{http://schemas.android.com/apk/res/android}"


def aapt_path():
    executable = shutil.which("aapt")
    if executable:
        return executable
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if not sdk:
        properties = Path.cwd() / "android/local.properties"
        if properties.is_file():
            sdk = next((line.split("=", 1)[1] for line in properties.read_text().splitlines()
                        if line.startswith("sdk.dir=")), None)
    if sdk:
        candidates = [p for p in (Path(sdk) / "build-tools").glob("*/aapt")
                      if re.fullmatch(r"\d+\.\d+\.\d+", p.parent.name)]
        if candidates:
            return str(max(candidates, key=lambda p: tuple(map(int, p.parent.name.split(".")))))
    raise ValueError("Android SDK aapt is required to verify the actual APK manifest")


def bundletool_path():
    cache = Path.cwd() / "build/release-tools"
    output = cache / f"bundletool-all-{BUNDLETOOL_VERSION}.jar"
    if output.is_file() and hashlib.sha256(output.read_bytes()).hexdigest() == BUNDLETOOL_SHA256:
        return output
    cache.mkdir(parents=True, exist_ok=True)
    url = f"https://github.com/google/bundletool/releases/download/{BUNDLETOOL_VERSION}/{output.name}"
    with tempfile.TemporaryDirectory(prefix="bundletool-", dir=cache) as temp:
        downloaded = Path(temp) / output.name
        with urllib.request.urlopen(url, timeout=60) as source, downloaded.open("wb") as target:
            shutil.copyfileobj(source, target)
        if hashlib.sha256(downloaded.read_bytes()).hexdigest() != BUNDLETOOL_SHA256:
            raise ValueError("bundletool checksum mismatch")
        os.replace(downloaded, output)
    return output


def identity(path):
    if path.suffix == ".apk":
        output = subprocess.check_output([aapt_path(), "dump", "badging", str(path)], text=True)
        match = re.search(r"^package: name='([^']+)' versionCode='([0-9]+)' versionName='([^']+)'", output, re.MULTILINE)
        if not match:
            raise ValueError(f"Cannot read APK package/version: {path.name}")
        package_name, code, version = match.groups()
    elif path.suffix == ".aab":
        java = str(Path(os.environ["JAVA_HOME"]) / "bin/java") if os.environ.get("JAVA_HOME") else "java"
        output = subprocess.check_output([java, "-jar", str(bundletool_path()), "dump", "manifest", f"--bundle={path}"], text=True)
        root = ET.fromstring(output)
        package_name = root.get("package")
        code = root.get(ANDROID_NAMESPACE + "versionCode", "")
        version = root.get(ANDROID_NAMESPACE + "versionName")
        if root.tag != "manifest" or not re.fullmatch(r"[0-9]+", code):
            raise ValueError(f"Cannot read AAB package/version: {path.name}")
    else:
        raise ValueError("Expected an APK or AAB")
    return package_name, version, int(code)


def verify_identity(path, version, build_number):
    if not 1 <= build_number <= 2100000000:
        raise ValueError("Android build number must be between 1 and 2100000000")
    actual = identity(path)
    expected = ("com.fknotes.app", version, build_number)
    if actual != expected:
        raise ValueError(f"{path.name}: expected package/version/versionCode {expected}, got {actual}")
    return actual


def check_apk(path):
    with ZipFile(path) as archive:
        libraries = [name for name in archive.namelist() if APP_LIBRARY.fullmatch(name)]
        if not libraries:
            raise ValueError("no Flutter AOT libraries")
        for library in libraries:
            if PERSONAL_PATH.search(archive.read(library)):
                raise ValueError(f"{library} contains a developer home path")


def main():
    parser = argparse.ArgumentParser(description="Check APK/AAB paths and actual package/version metadata.")
    parser.add_argument("archives", nargs="+", type=Path)
    parser.add_argument("--version")
    parser.add_argument("--build-number", type=int)
    args = parser.parse_args()
    if (args.version is None) != (args.build_number is None):
        parser.error("--version and --build-number must be supplied together")
    for path in args.archives:
        try:
            check_apk(path)
            if args.version is not None:
                verify_identity(path, args.version, args.build_number)
        except (BadZipFile, OSError, ValueError, subprocess.CalledProcessError, ET.ParseError) as error:
            sys.exit(f"Release check failed for {path.name}: {error}")
        print(f"Release checks passed for {path.name}.")


if __name__ == "__main__":
    main()
