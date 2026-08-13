// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BlueSwiftCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14) // macOS target kept only so `swift test` runs fast in CI/locally
    ],
    products: [
        .library(name: "BlueSwiftCore", targets: ["BlueSwiftCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "509.0.0")
    ],
    targets: [
        .target(
            name: "BlueSwiftCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ]
        ),
        .testTarget(
            name: "BlueSwiftCoreTests",
            dependencies: ["BlueSwiftCore"]
        )
    ]
)
