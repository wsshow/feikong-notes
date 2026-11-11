"""Inventory bundled privacy declarations for the archive review (no upload)."""
import argparse
import json
from pathlib import Path
import plistlib


def report(app):
    manifests = []
    for path in sorted(app.rglob("PrivacyInfo.xcprivacy")):
        data = plistlib.loads(path.read_bytes())
        manifests.append({"path": str(path.relative_to(app)), "declarations": data})
    frameworks = app / "Frameworks"
    missing = [str(p.relative_to(app)) for p in sorted(frameworks.glob("*.framework"))
               if not list(p.rglob("PrivacyInfo.xcprivacy"))]
    return {
        "scope": "Bundled declarations only; verify SDK behavior and App Store answers separately.",
        "manifests": manifests,
        "frameworksWithoutBundledManifest": missing,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report(args.app), ensure_ascii=False, indent=2) + "\n")
    print(f"Privacy inventory written: {args.output}")
