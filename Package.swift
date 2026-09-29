// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TeleprompterCore",
    platforms: [.macOS("26.0")],
    products: [.library(name: "TeleprompterCore", targets: ["TeleprompterCore"])],
    targets: [
        .target(name: "TeleprompterCore", path: "Core"),
        .testTarget(name: "TeleprompterCoreTests", dependencies: ["TeleprompterCore"], path: "Tests")
    ]
)
