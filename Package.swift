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
        ),
        .library(
            name: "PasteOverlay",
            targets: ["PasteOverlay"]
        )
    ],
    targets: [
        .target(
            name: "PasteCore",
            path: "Sources/PasteCore"
        ),
        .target(
            name: "PasteOverlay",
            dependencies: ["PasteCore"],
            path: "Sources/PasteOverlay"
        ),
        .testTarget(
            name: "PasteCoreTests",
            dependencies: ["PasteCore"],
            path: "Tests/PasteCoreTests"
        ),
        .testTarget(
            name: "PasteOverlayTests",
            dependencies: ["PasteCore", "PasteOverlay"],
            path: "Tests/PasteOverlayTests"
        )
    ]
)
