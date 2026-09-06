// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "sfmap",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "SFMap",
            path: "Sources/SFMap",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SFMapTests",
            dependencies: ["SFMap"],
            path: "Tests/SFMapTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
