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
            exclude: [
                "Info.plist"
            ],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/FlybookEurope/Info.plist"
                ], .when(platforms: [.macOS]))
            ]
        ),
        .testTarget(
            name: "FlybookEuropeTests",
            dependencies: ["FlybookEurope"]
        )
    ]
)
