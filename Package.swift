// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PasteClipboardAssistantContracts",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "PasteCore",
            targets: ["PasteCore"]
        )
    ],
    targets: [
        .target(
            name: "PasteCore",
            path: "Sources/PasteCore"
        ),
        .testTarget(
            name: "PasteCoreTests",
            dependencies: ["PasteCore"],
            path: "Tests/PasteCoreTests"
        )
    ]
)
