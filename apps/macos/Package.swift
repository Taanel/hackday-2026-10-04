// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Friday",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Friday", targets: ["FridayApp"]),
        .library(name: "FridayCore", targets: ["FridayCore"]),
        .library(name: "FridayAdapters", targets: ["FridayAdapters"])
    ],
    targets: [
        .target(name: "FridayCore"),
        .target(name: "FridayAdapters", dependencies: ["FridayCore"]),
        .executableTarget(
            name: "FridayApp",
            dependencies: ["FridayCore", "FridayAdapters"],
            resources: [.copy("Resources")]
        ),
        .testTarget(name: "FridayCoreTests", dependencies: ["FridayCore"])
    ]
)
