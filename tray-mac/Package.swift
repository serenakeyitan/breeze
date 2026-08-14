// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BreezeTray",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "BreezeTrayCore", targets: ["BreezeTrayCore"]),
        .executable(name: "BreezeTray", targets: ["BreezeTray"]),
        .executable(name: "breeze-tray-probe", targets: ["BreezeTrayProbe"]),
    ],
    targets: [
        .target(name: "BreezeTrayCore", path: "Sources/BreezeTrayCore"),
        .executableTarget(
            name: "BreezeTray",
            dependencies: ["BreezeTrayCore"],
            path: "Sources/BreezeTray"
        ),
        .executableTarget(
            name: "BreezeTrayProbe",
            dependencies: ["BreezeTrayCore"],
            path: "Sources/BreezeTrayProbe"
        ),
        .executableTarget(
            name: "BreezeTraySelfTest",
            dependencies: ["BreezeTrayCore"],
            path: "Sources/BreezeTraySelfTest"
        ),
    ]
)
