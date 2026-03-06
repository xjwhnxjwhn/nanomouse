// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

var dependencies: [Package.Dependency] = [
  .package(url: "https://github.com/relatedcode/ProgressHUD.git", exact: "14.1.0"),
  .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
  .package(path: "../Runestone"),
  .package(url: "https://github.com/simonbs/TreeSitterLanguages.git", exact: "0.1.10"),
  .package(path: "../HamsterUIKit"),
  .package(path: "../HamsterKit"),
  .package(path: "../RimeKit"),
  .package(path: "../HamsterKeyboardKit"),
  .package(path: "../HamsterFileServer"),
  .package(path: "../../mac/Packages/EmbeddedModuleHostKit"),
]

var hamsterDependencies: [Target.Dependency] = [
  "Runestone",
  .product(name: "TreeSitterLua", package: "TreeSitterLanguages"),
  .product(name: "TreeSitterLuaQueries", package: "TreeSitterLanguages"),
  .product(name: "TreeSitterLuaRunestone", package: "TreeSitterLanguages"),
  .product(name: "TreeSitterYAML", package: "TreeSitterLanguages"),
  .product(name: "TreeSitterYAMLQueries", package: "TreeSitterLanguages"),
  .product(name: "TreeSitterYAMLRunestone", package: "TreeSitterLanguages"),
  "ProgressHUD",
  "HamsterUIKit",
  "HamsterKit",
  "HamsterKeyboardKit",
  .product(name: "RimeKit", package: "RimeKit"),
  "HamsterFileServer",
  "WhisperKit",
  .product(name: "EmbeddedMainModuleHost", package: "EmbeddedModuleHostKit"),
]

var hamsterSwiftSettings: [SwiftSetting] = [
  .interoperabilityMode(.Cxx),
]

let package = Package(
  name: "HamsteriOS",
  platforms: [
    .iOS(.v16),
  ],
  products: [
    .library(
      name: "HamsteriOS",
      targets: ["HamsteriOS"]),
  ],
  dependencies: dependencies,
  targets: [
    .target(
      name: "HamsteriOS",
      dependencies: hamsterDependencies,
      path: "Sources",
      resources: [.process("Resources")],
      swiftSettings: hamsterSwiftSettings
    ),
    .testTarget(
      name: "HamsteriOSTests",
      dependencies: ["HamsteriOS"],
      path: "Tests",
      swiftSettings: [.interoperabilityMode(.Cxx)]),
  ])
