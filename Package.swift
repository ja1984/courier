// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Courier",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Courier", targets: ["Courier"]),
    ],
    targets: [
        .target(name: "CourierCore"),
        .executableTarget(
            name: "Courier",
            dependencies: ["CourierCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "CourierCoreTests", dependencies: ["CourierCore"]),
    ]
)
