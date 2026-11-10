import argparse
from pathlib import Path
import re
import sys
from zipfile import BadZipFile, ZipFile


APP_LIBRARY = re.compile(r"(?:base/)?lib/[^/]+/libapp\.so")
PERSONAL_PATH = re.compile(
    rb"(?:/Users/|/home/(?!runner/work/)|[A-Z]:[\\/]Users[\\/])"
    rb"[^/\\\x00\r\n]{1,200}[/\\]",
    re.IGNORECASE,
)


def check_apk(path):
    with ZipFile(path) as archive:
        libraries = [name for name in archive.namelist() if APP_LIBRARY.fullmatch(name)]
        if not libraries:
            raise ValueError("no Flutter AOT libraries")
        for library in libraries:
            if PERSONAL_PATH.search(archive.read(library)):
                raise ValueError(f"{library} contains a developer home path")


def main():
    parser = argparse.ArgumentParser(description="Check APK/AAB Flutter libraries for home paths.")
    parser.add_argument("archives", nargs="+", type=Path)
    args = parser.parse_args()
    for path in args.archives:
        try:
            check_apk(path)
        except (BadZipFile, OSError, ValueError) as error:
            sys.exit(f"Release check failed for {path.name}: {error}")
        print(f"Release path check passed for {path.name}.")


if __name__ == "__main__":
    main()
