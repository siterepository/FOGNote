// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FOGNote",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "FOGNote",
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
