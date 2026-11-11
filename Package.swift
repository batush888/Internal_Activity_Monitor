// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PulseMatrixPro",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "PulseMatrixPro",
            targets: ["PulseMatrixPro"]
        ),
        .library(
            name: "PulseMatrixCore",
            targets: ["PulseMatrixCore"]
        )
    ],
    targets: [
        .target(
            name: "CIOKitBridge",
            path: "Sources/CIOKitBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation")
            ]
        ),
        .target(
            name: "PulseMatrixCore",
            dependencies: ["CIOKitBridge"],
            path: "Sources/PulseMatrixCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Metal"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreFoundation")
            ]
        ),
        .executableTarget(
            name: "PulseMatrixPro",
            dependencies: ["PulseMatrixCore", "CIOKitBridge"],
            path: "Sources/PulseMatrixPro",
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("Charts"),
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "PulseMatrixProTests",
            dependencies: ["PulseMatrixCore"],
            path: "Tests/PulseMatrixProTests"
        )
    ]
)
