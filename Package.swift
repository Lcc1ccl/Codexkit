// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Codexkit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Codexkit", targets: ["CodexkitApp"])
    ],
    targets: [
        .executableTarget(
            name: "CodexkitApp",
            path: "Sources/CodexkitApp",
            exclude: ["Info.plist"],
            resources: [
                .copy("Bundled/CLIProxyAPIServiceBundle")
            ],
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-strict-concurrency=minimal"])
            ]
        ),
        .testTarget(
            name: "CodexkitAppTests",
            dependencies: ["CodexkitApp"],
            path: "Tests/CodexkitAppTests",
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-strict-concurrency=minimal"])
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
