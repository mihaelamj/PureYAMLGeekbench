// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PureYAMLGeekbench",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "pureyaml-geekbench", targets: ["PureYAMLGeekbench"]),
    ],
    dependencies: [
        .package(url: "https://github.com/mihaelamj/PureYAML.git", branch: "main"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/1amageek/swift-yaml.git", from: "0.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "PureYAMLGeekbench",
            dependencies: [
                "PureYAML",
                .product(name: "Yams", package: "Yams"),
                .product(name: "YAML", package: "swift-yaml"),
            ],
        ),
        .testTarget(
            name: "PureYAMLGeekbenchTests",
            dependencies: [],
        ),
    ],
)
