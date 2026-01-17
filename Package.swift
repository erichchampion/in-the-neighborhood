// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LlamaFramework",
    platforms: [
        .iOS("18.0"),
        .macOS("14.0")
    ],
    products: [
        .library(
            name: "LlamaFramework",
            targets: ["LlamaFramework"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "LlamaFramework",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b7658/llama-b7658-xcframework.zip",
            checksum: "9a148c92efdc0ce73ec702b44d58c3040fdb70426a81da83b15a7b97c48ac9b3"
        )
    ]
)
