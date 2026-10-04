// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PulsoKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WhoopProtocol", targets: ["WhoopProtocol"]),
        .library(name: "PulsoStore", targets: ["PulsoStore"]),
        .library(name: "PulsoAnalytics", targets: ["PulsoAnalytics"]),
    ],
    targets: [
        // On Apple platforms SQLite3 ships with the SDK; on Linux (CI / tests) we link the system lib.
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        .target(name: "WhoopProtocol"),
        .target(
            name: "PulsoStore",
            dependencies: [
                "WhoopProtocol",
                .target(name: "CSQLite", condition: .when(platforms: [.linux])),
            ]
        ),
        .target(name: "PulsoAnalytics", dependencies: ["PulsoStore", "WhoopProtocol"]),
        .testTarget(name: "WhoopProtocolTests", dependencies: ["WhoopProtocol"]),
        .testTarget(name: "PulsoStoreTests", dependencies: ["PulsoStore"]),
        .testTarget(name: "PulsoAnalyticsTests", dependencies: ["PulsoAnalytics", "PulsoStore"]),
    ]
)
