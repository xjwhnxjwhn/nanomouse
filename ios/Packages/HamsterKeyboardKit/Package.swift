// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let privateEmbeddedPackagePath = ProcessInfo.processInfo.environment["EMBEDDED_MODULE_PATH"]?
  .trimmingCharacters(in: .whitespacesAndNewlines)
let resolvedPrivateEmbeddedPackagePath: String? = {
  guard let privateEmbeddedPackagePath else { return nil }
  guard !privateEmbeddedPackagePath.isEmpty else { return nil }
  return URL(fileURLWithPath: privateEmbeddedPackagePath).standardizedFileURL.path
}()
let hasPrivateEmbeddedPackage = resolvedPrivateEmbeddedPackagePath
  .map { FileManager.default.fileExists(atPath: $0) } ?? false
let privateEmbeddedPackageIdentity = resolvedPrivateEmbeddedPackagePath.map {
  URL(fileURLWithPath: $0)
    .resolvingSymlinksInPath()
    .lastPathComponent
    .lowercased()
}

var dependencies: [Package.Dependency] = [
  .package(path: "../HamsterKit"),
  .package(path: "../HamsterUIKit"),
  .package(path: "../RimeKit"),
  // .package(url: "https://github.com/michaeleisel/ZippyJSON.git", exact: "1.2.10"),
  .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.16"),
  .package(url: "https://github.com/jpsim/Yams.git", exact: "5.0.6"),
  .package(path: "../AzooKeyKanaKanjiConverter"),
]

if hasPrivateEmbeddedPackage {
  dependencies.append(.package(path: resolvedPrivateEmbeddedPackagePath!))
}

var targetDependencies: [Target.Dependency] = [
  "HamsterKit",
  "HamsterUIKit",
  // "ZippyJSON",
  "RimeKit",
  .product(name: "KanaKanjiConverterModule", package: "AzooKeyKanaKanjiConverter"),
]

var keyboardSwiftSettings: [SwiftSetting] = [
  .interoperabilityMode(.Cxx),
]

if hasPrivateEmbeddedPackage {
  targetDependencies.append(
    .product(name: "EmbeddedKeyboardModuleBridge", package: privateEmbeddedPackageIdentity!)
  )
  keyboardSwiftSettings.append(.define("HAMSTER_EMBEDDED_MODULE_BRIDGE_ENABLED"))
}

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
