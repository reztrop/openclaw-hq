// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenClawDashboard",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "OpenClawDashboard",
            path: "Sources/OpenClawDashboard",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "OpenClawDashboardTests",
            dependencies: ["OpenClawDashboard"],
            path: "Tests/OpenClawDashboardTests"
        )
    ]
)
