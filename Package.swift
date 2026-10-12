// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenMuseCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "OpenMuseCore", targets: ["OpenMuseCore"])],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")
    ],
    targets: [
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        .target(
            name: "OpenMuseCore",
            dependencies: ["CSQLite", .product(name: "ZIPFoundation", package: "ZIPFoundation")],
            path: "Sources/OpenMuseCore",
            resources: [.copy("Resources/memory-transfer.v1.md"), .copy("Resources/openmuse-pi-read.mjs")],
            linkerSettings: [.linkedFramework("Vision", .when(platforms: [.iOS, .macOS]))]
        ),
        .testTarget(name: "OpenMuseCoreTests", dependencies: ["OpenMuseCore", "CSQLite", .product(name: "ZIPFoundation", package: "ZIPFoundation")], path: "Tests/OpenMuseCoreTests", exclude: ["OpenMusePiReadTools.test.mjs", "OpenMusePiReadRuntime.test.mjs"])
    ]
)
