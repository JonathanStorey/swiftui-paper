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
    ],
    targets: [
        .target(name: "PaperUI"),
        .testTarget(name: "PaperUITests", dependencies: ["PaperUI"]),
    ],
    swiftLanguageModes: [.v6]
)
