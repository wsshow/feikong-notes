// swift-tools-version: 5.9
// Adapted from Google LLC LiteRT-LM v0.14.0, Apache-2.0. See README.md and LICENSE.
import PackageDescription

let package = Package(
  name: "LiteRTLM",
  platforms: [.iOS(.v15)],
  products: [.library(name: "LiteRTLM", targets: ["LiteRTLM"])],
  targets: [
    .binaryTarget(
      name: "CLiteRTLM",
      url: "https://github.com/google-ai-edge/LiteRT-LM/releases/download/v0.14.0/CLiteRTLM.xcframework.zip",
      checksum: "dddac2f6713ed65eaf01c18e115d9fec22184adf575cc7856a21387e8ba937e1"),
    .target(
      name: "LiteRTLM", dependencies: ["CLiteRTLM"], path: "swift",
      linkerSettings: [.unsafeFlags(["-Xlinker", "-all_load"])])
  ])
