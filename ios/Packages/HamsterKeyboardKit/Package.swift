// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

var dependencies: [Package.Dependency] = [
  .package(path: "../HamsterKit"),
  .package(path: "../HamsterUIKit"),
  .package(path: "../RimeKit"),
  // .package(url: "https://github.com/michaeleisel/ZippyJSON.git", exact: "1.2.10"),
  .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.16"),
  .package(url: "https://github.com/jpsim/Yams.git", exact: "5.0.6"),
  .package(path: "../AzooKeyKanaKanjiConverter"),
  .package(path: "../../../mac/Packages/EmbeddedModuleHostKit"),
]

var targetDependencies: [Target.Dependency] = [
  "HamsterKit",
  "HamsterUIKit",
  // "ZippyJSON",
  "RimeKit",
  .product(name: "KanaKanjiConverterModule", package: "AzooKeyKanaKanjiConverter"),
  .product(name: "EmbeddedKeyboardModuleHost", package: "EmbeddedModuleHostKit"),
]

var keyboardSwiftSettings: [SwiftSetting] = [
  .interoperabilityMode(.Cxx),
]

let package = Package(
  name: "HamsterKeyboardKit",
  defaultLocalization: "zh-Hans",
  platforms: [
    .iOS(.v16),
  ],
  products: [
    .library(name: "HamsterKeyboardKit", targets: ["HamsterKeyboardKit"]),
  ],
  dependencies: dependencies,
  targets: [
    .target(
      name: "HamsterKeyboardKit",
      dependencies: targetDependencies,
      path: "Sources",
      resources: [.process("Resources")],
      swiftSettings: keyboardSwiftSettings),
    .testTarget(
      name: "HamsterKeyboardKitTests",
      dependencies: [
        "HamsterKeyboardKit",
        "Yams",
        "HamsterKit",
        "HamsterUIKit",
        "ZIPFoundation",
        // "ZippyJSON",
        "RimeKit",
      ],
      path: "Tests",
      swiftSettings: [.interoperabilityMode(.Cxx)]),
  ])
