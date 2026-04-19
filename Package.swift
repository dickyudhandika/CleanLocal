// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "MiniGuard",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MiniGuard", targets: ["MiniGuard"])
    ],
    targets: [
        .executableTarget(
            name: "MiniGuard",
            path: "Sources"
        )
    ]
)
