// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .interoperabilityMode(.Cxx),
    .define("ZenzaiCPU", .when(platforms: [.iOS, .macOS])),
]

var dependencies: [Package.Dependency] = [
    // Dependencies declare other packages that this package depends on.
    // .package(url: /* package url */, from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-algorithms", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-collections", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMajor(from: "1.0.0")),
    .package(url: "https://github.com/ensan-hcl/swift-tokenizers", from: "0.0.1")
]

var efficientNGramDependencies: [Target.Dependency] = [
    .product(name: "Transformers", package: "swift-tokenizers")
]

#if (!os(Linux) || !canImport(Android)) && !os(Windows)
// Android環境・Windows環境ではSwiftyMarisaが利用できないため、EfficientNGramは除外する。
// (Nanomouse 目前不启用 Zenzai，因此不引入 SwiftyMarisa 以避免 C++ 构建问题)
#endif


var targets: [Target] = [
    // Targets are the basic building blocks of a package. A target can define a module or a test suite.
    // Targets can depend on other targets in this package, and on products in packages this package depends on.
    .target(
        name: "SwiftUtils",
        dependencies: [
            .product(name: "Algorithms", package: "swift-algorithms")
        ],
        resources: [],
        swiftSettings: swiftSettings
    ),
    .target(
        name: "EfficientNGram",
        dependencies: efficientNGramDependencies,
        resources: [.copy("tokenizer")],
        swiftSettings: swiftSettings
    ),
    .testTarget(
        name: "SwiftUtilsTests",
        dependencies: ["SwiftUtils"],
        resources: [],
        swiftSettings: swiftSettings
    ),
    .testTarget(
        name: "EfficientNGramTests",
        dependencies: ["EfficientNGram"],
        resources: [],
        swiftSettings: swiftSettings
    ),
    .testTarget(
        name: "KanaKanjiConverterModuleTests",
        dependencies: ["KanaKanjiConverterModule"],
        resources: [
            .copy("DictionaryMock")
        ],
        swiftSettings: swiftSettings
    )
]

#if os(Linux) && !canImport(Android)
func checkObjcAvailability() -> Bool {
    do {
        let linkCheck = Process()
        linkCheck.executableURL = URL(fileURLWithPath: "/bin/sh")
        linkCheck.arguments = ["-c", "echo 'int main() { return 0; }' | clang -x c - -lobjc -o /dev/null"]
        
        try linkCheck.run()
        linkCheck.waitUntilExit()
        
        if linkCheck.terminationStatus != 0 {
            print("Cannot link with -lobjc")
            return false
        }
        return true
    } catch {
        print("Error checking Objective-C availability: \(error)")
        return false
    }
}

if checkObjcAvailability() {
    print("Objective-C runtime is available")
    targets = targets.map { target in
        if target.name == "CliTool" || target.name == "KanaKanjiConverterModuleWithDefaultDictionaryTests" {
        let modifiedTarget = target
        modifiedTarget.linkerSettings = [.linkedLibrary("objc")]
        return modifiedTarget
        }
        return target
    }
}
#endif

targets.append(
    .binaryTarget(
        name: "llama.cpp",
        url: "https://github.com/azooKey/llama.cpp/releases/download/b4846/signed-llama.xcframework.zip",
        checksum: "db3b13169df8870375f212e6ac21194225f1c85f7911d595ab64c8c790068e0a"
    )
)
targets.append(
    .target(
        name: "KanaKanjiConverterModule",
        dependencies: [
            "SwiftUtils",
            .target(name: "EfficientNGram"),
            .target(name: "llama.cpp"),
            .product(name: "Collections", package: "swift-collections"),
        ],
        swiftSettings: swiftSettings
    )
)

let package = Package(
    name: "AzooKeyKanaKanjiConverter",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "SwiftUtils",
            targets: ["SwiftUtils"]
        ),
        /// 辞書データを含まないバージョンの辞書モジュール
        .library(
            name: "KanaKanjiConverterModule",
            targets: ["KanaKanjiConverterModule"]
        ),
    ],
    dependencies: dependencies,
    targets: targets
)
