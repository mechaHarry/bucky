// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Bucky",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "Bucky", targets: ["Bucky"])
    ],
    targets: [
        .executableTarget(
            name: "Bucky",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreServices"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI")
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
