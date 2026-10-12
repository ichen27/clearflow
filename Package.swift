// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ClearFlow",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ClearFlow", targets: ["ClearFlow"])],
    targets: [
        .target(name: "ClearFlowCore"),
        .executableTarget(name: "ClearFlow", dependencies: ["ClearFlowCore"]),
        .executableTarget(name: "ClearFlowCoreChecks", dependencies: ["ClearFlowCore"], path: "Tests/ClearFlowCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
