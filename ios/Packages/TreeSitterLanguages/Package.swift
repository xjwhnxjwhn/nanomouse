// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "TreeSitterLanguages",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "TreeSitterLua", targets: ["TreeSitterLua"]),
        .library(name: "TreeSitterLuaQueries", targets: ["TreeSitterLuaQueries"]),
        .library(name: "TreeSitterLuaRunestone", targets: ["TreeSitterLuaRunestone"]),
        .library(name: "TreeSitterYAML", targets: ["TreeSitterYAML"]),
        .library(name: "TreeSitterYAMLQueries", targets: ["TreeSitterYAMLQueries"]),
        .library(name: "TreeSitterYAMLRunestone", targets: ["TreeSitterYAMLRunestone"]),
    ],
    dependencies: [
        .package(path: "../Runestone")
    ],
    targets: [
        .target(name: "TreeSitterLua", cSettings: [.headerSearchPath("src")]),
        .target(name: "TreeSitterLuaQueries", resources: [.copy("highlights.scm"), .copy("injections.scm")]),
        .target(name: "TreeSitterLuaRunestone", dependencies: [.product(name: "Runestone", package: "Runestone"), "TreeSitterLua", "TreeSitterLuaQueries"]),
        .target(name: "TreeSitterYAML", exclude: ["src/schema.generated.cc"], cSettings: [.headerSearchPath("src")]),
        .target(name: "TreeSitterYAMLQueries", resources: [.copy("highlights.scm")]),
        .target(name: "TreeSitterYAMLRunestone", dependencies: [.product(name: "Runestone", package: "Runestone"), "TreeSitterYAML", "TreeSitterYAMLQueries"]),
    ]
)
