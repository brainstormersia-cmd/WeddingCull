// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WeddingCull",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WeddingCull", targets: ["WeddingCullAppTarget"]),
        .library(name: "WeddingCullCore", targets: ["WeddingCullCore"]),
        .executable(name: "TestDatasetGenerator", targets: ["TestDatasetGenerator"]),
        .executable(name: "BenchmarkRunner", targets: ["BenchmarkRunner"]),
        .executable(name: "ValidationRunner", targets: ["ValidationRunner"])
    ],
    targets: [
        .target(
            name: "WeddingCullCore",
            path: "Sources",
            exclude: ["WeddingCullApp/WeddingCullApp.swift", "WeddingCullApp/Info.plist", "WeddingCullApp/WeddingCull.entitlements"]
        ),
        .executableTarget(
            name: "WeddingCullAppTarget",
            dependencies: ["WeddingCullCore"],
            path: "Sources/WeddingCullApp"
        ),
        .target(
            name: "TestDatasetGeneratorLibrary",
            path: "Tools/TestDatasetGenerator",
            exclude: ["main.swift"]
        ),
        .executableTarget(
            name: "TestDatasetGenerator",
            dependencies: ["TestDatasetGeneratorLibrary"],
            path: "Tools/TestDatasetGenerator",
            sources: ["main.swift"]
        ),
        .executableTarget(
            name: "BenchmarkRunner",
            dependencies: ["WeddingCullCore", "TestDatasetGeneratorLibrary"],
            path: "Tools/BenchmarkRunner"
        ),
        .executableTarget(
            name: "ValidationRunner",
            dependencies: ["WeddingCullCore", "TestDatasetGeneratorLibrary"],
            path: "Tools/ValidationRunner"
        ),
        .testTarget(
            name: "WeddingCullTests",
            dependencies: ["WeddingCullCore", "TestDatasetGeneratorLibrary"],
            path: "Tests/WeddingCullTests"
        ),
        .testTarget(
            name: "WeddingCullIntegrationTests",
            dependencies: ["WeddingCullCore", "TestDatasetGeneratorLibrary"],
            path: "Tests/WeddingCullIntegrationTests"
        )
    ]
)
