// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChromaRSSCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ChromaRSSCore", targets: ["ChromaRSSCore"])
    ],
    targets: [
        .target(name: "ChromaRSSCore"),
        .testTarget(name: "ChromaRSSCoreTests", dependencies: ["ChromaRSSCore"])
    ]
)
