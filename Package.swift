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
        )
    ],
    targets: [
        .executableTarget(
            name: "FlybookEurope",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "FlybookEuropeTests",
            dependencies: ["FlybookEurope"]
        )
    ]
)
