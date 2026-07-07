// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FOGNote",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(path: "Vendor/SwiftLAME")
    ],
    targets: [
        .executableTarget(
            name: "FOGNote",
            dependencies: [.product(name: "SwiftLAME", package: "SwiftLAME")],
            path: "Sources/FOGNote",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "FOGNoteTests",
            dependencies: ["FOGNote"],
            path: "Tests/FOGNoteTests"
        )
    ]
)
