// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "SwiftUIPaper",
    platforms: [
        .iOS(.v27),
        .macOS(.v27),
        .visionOS(.v27),
    ],
    products: [
        .library(name: "PaperUI", targets: ["PaperUI"]),
        .library(name: "PaperTesting", targets: ["PaperTesting"]),
    ],
    targets: [
        // Foundation + CoreGraphics only.
        .target(name: "PaperModel"),
        // PaperKit + PencilKit + PDFKit + Vision.
        .target(name: "PaperCore", dependencies: ["PaperModel"]),
        // SwiftUI views and modifiers.
        .target(name: "PaperUI", dependencies: ["PaperModel", "PaperCore"]),
        // Fixtures for tests and previews.
        .target(name: "PaperTesting", dependencies: ["PaperModel", "PaperCore"]),

        .testTarget(name: "PaperModelTests", dependencies: ["PaperModel"]),
        .testTarget(name: "PaperCoreTests", dependencies: ["PaperCore", "PaperTesting"]),
        .testTarget(name: "PaperUITests", dependencies: ["PaperUI"]),
    ],
    swiftLanguageModes: [.v6]
)
