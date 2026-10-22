// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Yeoman",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Yeoman",
            targets: ["Yeoman"]
        ),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Yeoman",
            dependencies: [],
            path: "Sources/Yeoman"
        )
    ]
)
