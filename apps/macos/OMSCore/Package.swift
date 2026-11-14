// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OMSCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "OMSCore", targets: ["OMSCore"]),
    ],
    targets: [
        .target(name: "OMSCore"),
        .testTarget(name: "OMSCoreTests", dependencies: ["OMSCore"]),
    ]
)
