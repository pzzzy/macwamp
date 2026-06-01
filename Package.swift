// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacWamp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacWamp", targets: ["MacWamp"])
    ],
    targets: [
        .executableTarget(
            name: "MacWamp",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        )
    ]
)
