// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SmartClip",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SmartClip", targets: ["SmartClip"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .executableTarget(
            name: "SmartClip",
            dependencies: ["CSQLite"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CryptoKit"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(name: "SmartClipTests", dependencies: ["SmartClip"])
    ]
)
