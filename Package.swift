// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Burrow",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Burrow",
            path: "Sources/Burrow",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "BurrowTests",
            dependencies: ["Burrow"],
            path: "Tests/BurrowTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
