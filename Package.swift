// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Yeoman",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Yeoman", targets: ["Yeoman"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "YeomanCore",
            dependencies: [],
            path: "Sources/Yeoman",
            exclude: ["App/YeomanApp.swift"]
        ),
        .executableTarget(
            name: "Yeoman",
            dependencies: ["YeomanCore"],
            path: "Sources/Yeoman/App"
        ),
        .executableTarget(
            name: "YeomanTests",
            dependencies: ["YeomanCore"],
            path: "Tests"
        )
    ]
)
