// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Planner",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "calmenu", targets: ["CalMenu"])
    ],
    targets: [
        .executableTarget(
            name: "CalMenu",
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("EventKit"),
                .linkedFramework("Combine")
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
