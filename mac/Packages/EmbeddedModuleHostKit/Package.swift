// swift-tools-version: 5.9
import PackageDescription
import Foundation

private let packageDirectoryURL = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
private let repositoryRootURL = packageDirectoryURL
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .deletingLastPathComponent()
private let defaultEmbeddedPackagePath = repositoryRootURL
  .appendingPathComponent(".private/embedded-module")
  .standardizedFileURL
  .path
private let privateEmbeddedPackagePath = ProcessInfo.processInfo.environment["EMBEDDED_MODULE_PATH"]?
  .trimmingCharacters(in: .whitespacesAndNewlines)
private let resolvedPrivateEmbeddedPackagePath: String? = {
  let fileManager = FileManager.default
  let candidates = [privateEmbeddedPackagePath, defaultEmbeddedPackagePath]

  for candidate in candidates {
    guard let candidate else { continue }
    guard !candidate.isEmpty else { continue }

    let normalizedPath = URL(fileURLWithPath: candidate).standardizedFileURL.path
    if fileManager.fileExists(atPath: normalizedPath) {
      return normalizedPath
    }
  }

  return nil
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
    .iOS(.v16),
    .macOS(.v13),
  ],
  products: [
    .library(
      name: "EmbeddedMainModuleHost",
      targets: ["EmbeddedMainModuleHost"]
    ),
    .library(
      name: "EmbeddedKeyboardModuleHost",
      targets: ["EmbeddedKeyboardModuleHost"]
    ),
    .library(
      name: "EmbeddedModuleHostKit",
      targets: ["EmbeddedModuleHostKit"]
    ),
  ],
  dependencies: dependencies,
  targets: [
    .target(
      name: "EmbeddedMainModuleHost",
      dependencies: hasPrivateEmbeddedPackage ? [
        .product(name: "EmbeddedMainModuleBridge", package: privateEmbeddedPackageIdentity!),
      ] : [],
      path: "Sources/EmbeddedMainModuleHost",
      swiftSettings: hasPrivateEmbeddedPackage ? [.define("EMBEDDED_MODULE_BRIDGE_ENABLED")] : []
    ),
    .target(
      name: "EmbeddedKeyboardModuleHost",
      dependencies: hasPrivateEmbeddedPackage ? [
        .product(name: "EmbeddedKeyboardModuleBridge", package: privateEmbeddedPackageIdentity!),
      ] : [],
      path: "Sources/EmbeddedKeyboardModuleHost",
      swiftSettings: hasPrivateEmbeddedPackage ? [.define("EMBEDDED_MODULE_BRIDGE_ENABLED")] : []
    ),
    .target(
      name: "EmbeddedModuleHostKit",
      dependencies: targetDependencies,
      path: "Sources/EmbeddedModuleHostKit",
      swiftSettings: swiftSettings
    ),
  ]
)
