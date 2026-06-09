// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "factory-desktop",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FactoryDesktop", targets: ["FactoryDesktop"])
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1")
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            providers: [
                .brew(["sqlite"])
            ]
        ),
        .target(
            name: "FactoryDesktopCore",
            dependencies: ["CSQLite"]
        ),
        .executableTarget(
            name: "FactoryDesktop",
            dependencies: [
                "FactoryDesktopCore",
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ],
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "FactoryDesktopCoreTests",
            dependencies: ["FactoryDesktopCore"]
        )
    ]
)
