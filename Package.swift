// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlybookEurope",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Flybook Europe",
            targets: ["FlybookEurope"]
        ),
        .executable(
            name: "Flybook Image Studio",
            targets: ["FlybookImageStudio"]
        )
    ],
    targets: [
        .executableTarget(
            name: "FlybookEurope",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "FlybookImageStudio",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Security")
            ]
        )
    ]
)
