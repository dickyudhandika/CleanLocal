// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "CleanLocal",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CleanLocal", targets: ["CleanLocal"])
    ],
    targets: [
        .executableTarget(
            name: "CleanLocal",
            path: "Sources"
        ),
        .testTarget(
            name: "CleanLocalTests",
            dependencies: ["CleanLocal"],
            path: "Tests/CleanLocalTests"
        )
    ]
)
