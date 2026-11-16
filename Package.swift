// swift-tools-version:5.9
// Only used to unit-test the planning logic (`swift test`). The iPhone app is built from project.yml.
import PackageDescription

let package = Package(
    name: "LockinCore",
    targets: [
        .target(name: "LockinCore", path: "Lockin/Core"),
        .testTarget(name: "LockinCoreTests", dependencies: ["LockinCore"], path: "Tests/LockinCoreTests"),
    ]
)
