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
        .systemLibrary(name: "CArchive", path: "Sources/CArchive"),
        .target(
            name: "YeomanCore",
            dependencies: ["CArchive"],
            path: "Sources/Yeoman",
            exclude: ["App/YeomanApp.swift"]
        ),
        .executableTarget(
            name: "YeomanReleaseSign",
            dependencies: ["YeomanCore"],
            path: "Sources/YeomanReleaseSign"
        ),
        .executableTarget(
            name: "YeomanInstaller",
            dependencies: ["YeomanCore"],
            path: "Sources/YeomanInstaller"
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
