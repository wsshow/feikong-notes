"""Build the pinned MNN LLM runtime for ARM64 iOS simulators (CPU only)."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile

VERSION = "3.6.0"
SOURCE_SHA256 = "4ddbe825a22ee06e8c237bf3382231d5b6130878c850291d015808946cb87690"
OPTIONS = [
    "-DCMAKE_BUILD_TYPE=Release", "-DENABLE_BITCODE=0", "-DMNN_AAPL_FMWK=1",
    "-DMNN_SEP_BUILD=OFF", "-DMNN_BUILD_SHARED_LIBS=OFF", "-DMNN_USE_THREAD_POOL=OFF",
    "-DPLATFORM=SIMULATOR64", "-DARCHS=arm64", "-DDEPLOYMENT_TARGET=15.0",
    "-DMNN_ARM82=ON", "-DMNN_LOW_MEMORY=ON", "-DMNN_SUPPORT_TRANSFORMER_FUSE=ON",
    "-DMNN_BUILD_LLM=ON", "-DMNN_METAL=OFF", "-DMNN_OPENCL=OFF",
    "-DMNN_BUILD_DIFFUSION=OFF", "-DMNN_BUILD_AUDIO=ON", "-DMNN_BUILD_OPENCV=ON",
    "-DMNN_IMGCODECS=ON", "-DLLM_SUPPORT_HTTP_RESOURCE=OFF", "-DMNN_BUILD_FOR_IOS=ON",
]


def digest(path):
    checksum = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            checksum.update(block)
    return checksum.hexdigest()


def extract_source(archive, destination, expected=SOURCE_SHA256):
    if digest(archive) != expected:
        raise ValueError("MNN source checksum mismatch")
    with tarfile.open(archive) as source:
        members = source.getmembers()
        for member in members:
            path = Path(member.name)
            if path.is_absolute() or ".." in path.parts or path.parts[0] != f"MNN-{VERSION}":
                raise ValueError("Unsafe MNN source archive member")
        # Upstream contains documentation/Android screenshot symlinks. They are
        # not build inputs; never materialize links or device nodes from a tar.
        source.extractall(destination, members=[m for m in members if m.isfile() or m.isdir()])


def prepare(cache, jobs):
    if not shutil.which("cmake"):
        raise RuntimeError("ARM64 simulator MNN builds require CMake (brew install cmake)")
    cache = cache.resolve()
    cache.mkdir(parents=True, exist_ok=True)
    framework = cache / "MNN.framework"
    binary = framework / "MNN"
    stamp = cache / "build-manifest.json"
    recipe = {
        "version": VERSION, "sourceSha256": SOURCE_SHA256, "options": OPTIONS,
        "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
        "recipeSha256": digest(Path(__file__)),
        "developerDirectory": subprocess.check_output(["xcode-select", "-p"], text=True).strip(),
    }
    if stamp.exists() and binary.exists():
        previous = json.loads(stamp.read_text())
        if previous.get("recipe") == recipe and previous.get("binarySha256") == digest(binary):
            return framework
    archive = cache / f"MNN-{VERSION}.tar.gz"
    if not archive.exists() or digest(archive) != SOURCE_SHA256:
        download = archive.with_suffix(".download")
        subprocess.run(["curl", "--fail", "--location", "--retry", "3", "--connect-timeout", "20",
                        f"https://codeload.github.com/alibaba/MNN/tar.gz/refs/tags/{VERSION}",
                        "--output", str(download)], check=True)
        if digest(download) != SOURCE_SHA256:
            download.unlink()
            raise ValueError("MNN source checksum mismatch")
        download.replace(archive)
    source = cache / f"MNN-{VERSION}"
    # Re-extract verified sources on a recipe change; incremental object builds
    # still use CMake's dependency checks. Nothing outside this cache is removed.
    with tempfile.TemporaryDirectory(dir=cache) as temporary:
        extract_source(archive, Path(temporary))
        if source.exists():
            shutil.rmtree(source)
        shutil.move(str(Path(temporary) / source.name), source)
    build = cache / "cmake-build"
    subprocess.run(["cmake", "-S", str(source), "-B", str(build),
                    f"-DCMAKE_TOOLCHAIN_FILE={source}/cmake/ios.toolchain.cmake", *OPTIONS], check=True)
    subprocess.run(["cmake", "--build", str(build), "--target", "MNN", "--parallel", str(jobs)], check=True)
    built = build / "MNN.framework"
    architectures = subprocess.check_output(["xcrun", "lipo", "-archs", str(built / "MNN")], text=True)
    if architectures.strip() != "arm64" or not (built / "Headers/llm/llm.hpp").is_file():
        raise ValueError("MNN ARM64 framework or LLM headers missing")
    # Validate the platform of a real inference object, not only its ARM64 CPU.
    llm_object = build / "CMakeFiles/llm.dir/transformers/llm/engine/src/llm.cpp.o"
    platform = subprocess.check_output(["xcrun", "vtool", "-show-build", str(llm_object)], text=True)
    if "platform IOSSIMULATOR" not in platform:
        raise ValueError("MNN LLM object is not built for the iOS simulator")
    if framework.exists():
        shutil.rmtree(framework)
    shutil.copytree(built, framework, symlinks=True)
    pending = stamp.with_suffix(".tmp")
    pending.write_text(json.dumps({"recipe": recipe, "binarySha256": digest(binary)}, indent=2) + "\n")
    pending.replace(stamp)
    return framework


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cache", type=Path)
    parser.add_argument("--jobs", type=int, default=int(os.environ.get("FKNOTES_MNN_BUILD_JOBS", "3")))
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    args.cache.mkdir(parents=True, exist_ok=True)
    with (args.cache / ".build.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        print(prepare(args.cache, args.jobs))
