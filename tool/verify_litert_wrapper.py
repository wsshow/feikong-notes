"""Check the pinned, unmodified LiteRT-LM production Swift sources."""
import hashlib
import json
from pathlib import Path


def verify():
    root = Path(__file__).resolve().parents[1] / "third_party/litert_lm"
    manifest = json.loads((root / "upstream-sha256.json").read_text())
    actual = {str(p.relative_to(root)) for p in (root / "swift").glob("*.swift")}
    if actual != {p for p in manifest if p.endswith(".swift")}:
        raise ValueError("LiteRT-LM source file set changed")
    for name, digest in manifest.items():
        if hashlib.sha256((root / name).read_bytes()).hexdigest() != digest:
            raise ValueError(f"LiteRT-LM upstream source changed: {name}")


if __name__ == "__main__":
    verify()
    print("LiteRT-LM v0.14.0 wrapper checksums verified")
