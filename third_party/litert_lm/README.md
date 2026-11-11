# LiteRT-LM Swift wrapper

Source: Google AI Edge [LiteRT-LM v0.14.0](https://github.com/google-ai-edge/LiteRT-LM/tree/v0.14.0), commit `f73637c57f0940b53da184e0d5adfc52a4e55eef`, Apache-2.0 (`LICENSE`).

`swift/*.swift` are the unmodified production Swift sources from that commit. `upstream-sha256.json` records their hashes and the license hash. Tests/build files from upstream are not bundled. The local `Package.swift` keeps the upstream iOS binary URL/checksum and `-all_load` linker setting; macOS and upstream test targets are omitted because this integration targets iOS only.

The wrapper is local because Xcode rejects versioned remote products containing the upstream unsafe linker flags. This also avoids fetching the upstream repository's multi-gigabyte model history/LFS assets. Do not modify a global SwiftPM or Pub cache. The binary is downloaded and checksum-verified by SwiftPM, not committed.

To reproduce: fetch the pinned commit, copy non-`*Tests.swift` files from its `swift/` directory and `LICENSE`, then run `python3 tool/verify_litert_wrapper.py`. Updating the version requires reviewing the API and regenerating this manifest deliberately. Do not upgrade independently of the Android runtime.
