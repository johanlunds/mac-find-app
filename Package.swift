// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FindApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FindApp",
            path: "Sources/FindApp"
        )
    ]
)
