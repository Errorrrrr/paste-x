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
            name: "PasteMacSystem",
            targets: ["PasteMacSystem"]
        ),
        .library(
            name: "PasteIntegration",
            targets: ["PasteIntegration"]
        ),
        .library(
            name: "PasteOverlay",
            targets: ["PasteOverlay"]
        ),
        .executable(
            name: "Paste",
            targets: ["PasteApp"]
        )
    ],
    targets: [
        .target(
            name: "PasteCore",
            path: "Sources/PasteCore"
        ),
        .target(
            name: "PasteMacSystem",
            dependencies: ["PasteCore"],
            path: "Sources/PasteMacSystem"
        ),
        .target(
            name: "PasteOverlay",
            dependencies: ["PasteCore"],
            path: "Sources/PasteOverlay"
        ),
        .target(
            name: "PasteIntegration",
            dependencies: ["PasteCore", "PasteMacSystem", "PasteOverlay"],
            path: "Sources/PasteIntegration"
        ),
        .executableTarget(
            name: "PasteApp",
            dependencies: ["PasteIntegration"],
            path: "Sources/PasteApp"
        ),
        .testTarget(
            name: "PasteCoreTests",
            dependencies: ["PasteCore"],
            path: "Tests/PasteCoreTests"
        ),
        .testTarget(
            name: "PasteMacSystemTests",
            dependencies: ["PasteCore", "PasteMacSystem"],
            path: "Tests/PasteMacSystemTests"
        ),
        .testTarget(
            name: "PasteOverlayTests",
            dependencies: ["PasteCore", "PasteOverlay"],
            path: "Tests/PasteOverlayTests"
        ),
        .testTarget(
            name: "PasteIntegrationTests",
            dependencies: ["PasteCore", "PasteIntegration", "PasteOverlay"],
            path: "Tests/PasteIntegrationTests"
        )
    ]
)
