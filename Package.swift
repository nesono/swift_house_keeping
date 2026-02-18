// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "house-keeping",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.3.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.4.0"),
    ],
    targets: [
        .target(
            name: "HouseKeeping",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
        ),
        .executableTarget(
            name: "house-keeping",
            dependencies: [
                "HouseKeeping",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
        ),
        .testTarget(
            name: "HouseKeepingTests",
            dependencies: ["HouseKeeping"],
        ),
    ],
)
