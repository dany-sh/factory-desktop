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
            dependencies: ["FactoryDesktopCore"]
        ),
        .testTarget(
            name: "FactoryDesktopCoreTests",
            dependencies: ["FactoryDesktopCore"]
        )
    ]
)
