// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SZUPower",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SZUPower",
            path: "Sources/SZUPower"
        )
    ]
)
