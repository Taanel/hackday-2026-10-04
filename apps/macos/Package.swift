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
    dependencies: [.package(path: "Vendor/ThinkingOrbsKit")],
    targets: [
        .target(name: "FridayMotion", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "FridayCore"),
        .target(name: "FridayAdapters", dependencies: ["FridayCore", "FridayMotion"]),
        .executableTarget(
            name: "FridayApp",
            dependencies: [
                "FridayCore", "FridayAdapters",
                .product(name: "ThinkingOrbsKit", package: "ThinkingOrbsKit")
            ],
            resources: [.copy("Resources")]
        ),
        .testTarget(name: "FridayCoreTests", dependencies: ["FridayCore"]),
        .testTarget(name: "FridayAdaptersTests", dependencies: ["FridayAdapters", "FridayCore"]),
        .testTarget(name: "FridayAppTests", dependencies: ["FridayApp", "FridayCore"])
    ]
)
