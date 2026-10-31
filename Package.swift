// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Burrow",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Burrow",
            dependencies: ["Sparkle"],
            path: "Sources/Burrow",
            swiftSettings: [.swiftLanguageMode(.v5)],
            // Sparkle.framework sits next to the binary in .build and in Contents/Frameworks in the app.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                                           "-Xlinker", "-rpath", "-Xlinker", "@loader_path"])]
        ),
        // Sparkle 2.10.0: in-app updates from the GitHub releases (EdDSA-signed appcast), the
        // standard for Mac apps outside the App Store. Its release zip, not the package: the
        // package clones Sparkle's whole git history.
        .binaryTarget(
            name: "Sparkle",
            url: "https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-for-Swift-Package-Manager.zip",
            checksum: "17e28312b8e18ab7cdbbe09a6fb28cc55a5479ec6c371dbc07cdecd2a14fd959"
        ),
        .testTarget(
            name: "BurrowTests",
            dependencies: ["Burrow"],
            path: "Tests/BurrowTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
