// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacCustomizer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "MacCustomizer",
            targets: ["MacCustomizer"]
        ),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MacCustomizer",
            dependencies: [],
            path: "Sources/MacCustomizer"
        )
    ]
)
