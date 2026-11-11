"""Download a pinned public smoke model and seed only the simulator validation app."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

from prepare_mnn_ios_simulator import digest

REPOSITORY = "taobao-mnn/SmolLM2-135M-Instruct-MNN"
REVISION = "b4fabed0f3925d4158fe470da88a179cfd31d8bc"
FILES = {
    "README.md": "cd0e1cf7c21ca6e30e0b1c8ccaacf92604664cd7244219e46de963ebe2016721",
    "config.json": "7636b063425bdbc0e2e429cb23af7f594b5ba145bab2045dfda852416d9285de",
    "embeddings_bf16.bin": "4af1341b29fe1dc67f81c951a4d4e84d99213e5fce7c853f18cd710f9bf95445",
    "llm.mnn": "cf53d62bf747a09e7c7364e26b2439c428f7a04813d8938ed9f2b94854e471db",
    "llm.mnn.weight": "81aa7c9477d62db641acb066dfd02d42d395914d2422e39c0aa8932c211fd105",
    "llm_config.json": "746353eceea26e6fd220958f201cc02880f9d39ee104a17e457a9a0525e3951e",
    "tokenizer.txt": "3a2d9a485e1f1369f88b5907ecbcb5f6036efc36863166a76fe034ce1a261470",
}
VALIDATION_ID = "com.fknotes.app.validation"


def prepare(cache, device):
    # Resolve before downloading. simctl cannot target a physical iPhone, and
    # this fixed ID never writes into the user's normal/preview app container.
    container = Path(subprocess.check_output(
        ["xcrun", "simctl", "get_app_container", device, VALIDATION_ID, "data"], text=True).strip())
    cache.mkdir(parents=True, exist_ok=True)
    for name, expected in FILES.items():
        path = cache / name
        if not path.exists() or digest(path) != expected:
            download = path.with_suffix(path.suffix + ".download")
            subprocess.run(["curl", "--fail", "--location", "--retry", "3", "--connect-timeout", "20",
                            f"https://huggingface.co/{REPOSITORY}/resolve/{REVISION}/{name}",
                            "--output", str(download)], check=True)
            if digest(download) != expected:
                download.unlink()
                raise ValueError(f"Smoke model checksum mismatch: {name}")
            download.replace(path)
    destination = container / "Library/Application Support/mnn-smoke"
    destination.mkdir(parents=True, exist_ok=True)
    for name in FILES:
        shutil.copyfile(cache / name, destination / name)
    # Preserve the verified download cache. Only this isolated test copy uses
    # greedy sampling so a lifecycle regression never depends on a random seed.
    config = destination / "config.json"
    settings = json.loads(config.read_text())
    settings["sampler_type"] = "greedy"
    config.write_text(json.dumps(settings, indent=2) + "\n")
    print(f"Seeded {VALIDATION_ID} with pinned SmolLM2-135M smoke model")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--cache", type=Path,
                        default=Path(__file__).resolve().parents[1] / "build/mnn-smoke-model")
    args = parser.parse_args()
    prepare(args.cache, args.device)
