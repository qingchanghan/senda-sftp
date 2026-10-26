// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Senda",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Senda", targets: ["Senda"])],
    targets: [
        .target(name: "SFTPCore"),
        .executableTarget(name: "Senda", dependencies: ["SFTPCore"]),
        .executableTarget(name: "SendaChecks", dependencies: ["SFTPCore"], path: "Tests/SFTPCoreTests")
    ]
)
