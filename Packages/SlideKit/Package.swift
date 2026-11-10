// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SlideKit",
    platforms: [.iOS(.v18), .tvOS(.v18), .macOS(.v15)],
    products: [.library(name: "SlideKit", targets: ["SlideKit"])],
    targets: [
        .target(name: "SlideKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "SlideKitTests", dependencies: ["SlideKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
