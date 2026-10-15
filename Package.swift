// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cork",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "CorkKit", targets: ["CorkKit"]),
        .executable(name: "cork", targets: ["cork"]),
        .executable(name: "cork-tests", targets: ["cork-tests"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "CorkKit",
            resources: [
                .copy("Resources/RuntimeManifest.json")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "cork",
            dependencies: [
                "CorkKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "cork-tests",
            dependencies: ["CorkKit"],
            path: "Tests/CorkTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
