// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TeleprompterCore",
    platforms: [.macOS("26.0")],
    products: [.library(name: "TeleprompterCore", targets: ["TeleprompterCore"])],
    dependencies: [
        .package(url: "https://github.com/moonshine-ai/moonshine-swift.git", exact: "0.1.5"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.4"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.0")
    ],
    targets: [
        .target(name: "TeleprompterCore", path: "Core", resources: [.copy("Licenses")]),
        .target(name: "TeleprompterSpeech", dependencies: [
            "TeleprompterCore",
            .product(name: "MoonshineVoice", package: "moonshine-swift"),
            .product(name: "FluidAudio", package: "FluidAudio"),
            .product(name: "WhisperKit", package: "argmax-oss-swift")
        ], path: "Speech"),
        .executableTarget(name: "VoiceEngineCheck", dependencies: ["TeleprompterSpeech", "TeleprompterCore"], path: "script/VoiceEngineCheck"),
        .testTarget(name: "TeleprompterCoreTests", dependencies: ["TeleprompterCore"], path: "Tests")
    ]
)
