// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SmartClip",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SmartClip", targets: ["SmartClip"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .executableTarget(
            name: "SmartClip",
            dependencies: [
                "CSQLite",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CryptoKit"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
                .unsafeFlags([
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"
                ])
            ]
        ),
        .testTarget(name: "SmartClipTests", dependencies: ["SmartClip"])
    ]
)
