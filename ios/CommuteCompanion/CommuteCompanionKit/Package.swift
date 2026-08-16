// swift-tools-version: 6.3
import PackageDescription

let baseSettings: [SwiftSetting] = [
    .defaultIsolation(nil),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault")
]

let package = Package(
    name: "CommuteCompanionKit",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "Root",
            targets: ["Root"]
        ),
    ],
    targets: [
        .target(
            name: "Root",
            dependencies: [
                "StationsFeature",
                "DeparturesFeature",
                "APIClient",
            ],
            swiftSettings: baseSettings
        ),
        .target(
            name: "APIClient",
            swiftSettings: baseSettings
        ),
        .target(
            name: "StationsFeature",
            dependencies: ["APIClient"],
            swiftSettings: baseSettings
        ),
        .target(
            name: "DeparturesFeature",
            dependencies: ["APIClient"],
            swiftSettings: baseSettings
        ),
        .testTarget(
            name: "RootTests",
            dependencies: ["Root"],
            swiftSettings: baseSettings
        ),
        .testTarget(
            name: "APIClientTests",
            dependencies: ["APIClient"],
            swiftSettings: baseSettings
        ),
        .testTarget(
            name: "StationsFeatureTests",
            dependencies: [
                "StationsFeature",
                "APIClient",
            ],
            swiftSettings: baseSettings
        ),
        .testTarget(
            name: "DeparturesFeatureTests",
            dependencies: [
                "DeparturesFeature",
                "APIClient",
            ],
            swiftSettings: baseSettings
        )
    ],
    swiftLanguageModes: [.v6]
)
