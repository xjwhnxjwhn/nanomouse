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
  .package(url: "https://github.com/relatedcode/ProgressHUD.git", exact: "14.1.0"),
  .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
  .package(path: "../Runestone"),
  .package(url: "https://github.com/simonbs/TreeSitterLanguages.git", exact: "0.1.10"),
  .package(path: "../HamsterUIKit"),
  .package(path: "../HamsterKit"),
  .package(path: "../RimeKit"),
  .package(path: "../HamsterKeyboardKit"),
  .package(path: "../HamsterFileServer"),
]

if hasPrivateEmbeddedPackage {
  dependencies.append(.package(path: resolvedPrivateEmbeddedPackagePath!))
}

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
]

var hamsterSwiftSettings: [SwiftSetting] = [
  .interoperabilityMode(.Cxx),
]

if hasPrivateEmbeddedPackage {
  hamsterDependencies.append(
    .product(name: "EmbeddedMainModuleBridge", package: privateEmbeddedPackageIdentity!)
  )
  hamsterSwiftSettings.append(.define("HAMSTER_EMBEDDED_MODULE_BRIDGE_ENABLED"))
}

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
