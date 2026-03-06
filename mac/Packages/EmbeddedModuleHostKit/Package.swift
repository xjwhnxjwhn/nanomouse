// swift-tools-version: 5.9
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

var dependencies: [Package.Dependency] = []
if hasPrivateEmbeddedPackage {
  dependencies.append(.package(path: resolvedPrivateEmbeddedPackagePath!))
}

var targetDependencies: [Target.Dependency] = []
var swiftSettings: [SwiftSetting] = []
if hasPrivateEmbeddedPackage {
  targetDependencies.append(
    .product(name: "EmbeddedMacModuleBridge", package: privateEmbeddedPackageIdentity!)
  )
  swiftSettings.append(.define("EMBEDDED_MODULE_BRIDGE_ENABLED"))
}

let package = Package(
  name: "EmbeddedModuleHostKit",
  platforms: [
    .macOS(.v13),
  ],
  products: [
    .library(
      name: "EmbeddedModuleHostKit",
      targets: ["EmbeddedModuleHostKit"]
    ),
  ],
  dependencies: dependencies,
  targets: [
    .target(
      name: "EmbeddedModuleHostKit",
      dependencies: targetDependencies,
      path: "Sources/EmbeddedModuleHostKit",
      swiftSettings: swiftSettings
    ),
  ]
)
