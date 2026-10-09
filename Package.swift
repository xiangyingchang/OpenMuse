// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenMuseCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "OpenMuseCore", targets: ["OpenMuseCore"])],
    targets: [
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        .target(name: "OpenMuseCore", dependencies: ["CSQLite"], path: "Sources/OpenMuseCore"),
        .testTarget(name: "OpenMuseCoreTests", dependencies: ["OpenMuseCore", "CSQLite"], path: "Tests/OpenMuseCoreTests")
    ]
)
