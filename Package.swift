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
        .testTarget(
            name: "PasteCoreTests",
            dependencies: ["PasteCore"],
            path: "Tests/PasteCoreTests"
        ),
        .testTarget(
            name: "PasteMacSystemTests",
            dependencies: ["PasteCore", "PasteMacSystem"],
            path: "Tests/PasteMacSystemTests"
        )
    ]
)
