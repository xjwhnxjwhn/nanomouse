// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "RimeKit",
  platforms: [
    .iOS(.v15),
  ],
  products: [
    .library(name: "RimeKit", targets: ["RimeKit"]),
  ],
  dependencies: [
    .package(path: "../HamsterKit"),
  ],
  targets: [
    .binaryTarget(
      name: "librimeRIME",
      path: "../../Frameworks/librime.xcframework"),
    .binaryTarget(
      name: "boost_filesystemRIME",
      path: "../../Frameworks/boost_filesystem.xcframework"),
    .binaryTarget(
      name: "boost_localeRIME",
      path: "../../Frameworks/boost_locale.xcframework"),
    .binaryTarget(
      name: "boost_regexRIME",
      path: "../../Frameworks/boost_regex.xcframework"),
    .binaryTarget(
      name: "boost_systemRIME",
      path: "../../Frameworks/boost_system.xcframework"),
    .binaryTarget(
      name: "libglogRIME",
      path: "../../Frameworks/libglog.xcframework"),
    .binaryTarget(
      name: "libleveldbRIME",
      path: "../../Frameworks/libleveldb.xcframework"),
    .binaryTarget(
      name: "libmarisaRIME",
      path: "../../Frameworks/libmarisa.xcframework"),
    .binaryTarget(
      name: "libopenccRIME",
      path: "../../Frameworks/libopencc.xcframework"),
    .binaryTarget(
      name: "libyaml-cppRIME",
      path: "../../Frameworks/libyaml-cpp.xcframework"),
    .binaryTarget(
      name: "icudataRIME",
      path: "../../Frameworks/icudata.xcframework"),
    .binaryTarget(
      name: "icui18nRIME",
      path: "../../Frameworks/icui18n.xcframework"),
    .binaryTarget(
      name: "icuioRIME",
      path: "../../Frameworks/icuio.xcframework"),
    .binaryTarget(
      name: "icuucRIME",
      path: "../../Frameworks/icuuc.xcframework"),
    .target(
      name: "RimeKitObjC",
      dependencies: [
        "librimeRIME",
        "boost_filesystemRIME",
        "boost_localeRIME",
        "boost_regexRIME",
        "boost_systemRIME",
        "libglogRIME",
        "libleveldbRIME",
        "libmarisaRIME",
        "libopenccRIME",
        "libyaml-cppRIME",
        "icudataRIME",
        "icui18nRIME",
        "icuioRIME",
        "icuucRIME",
      ],
      path: "Sources/ObjC",
      linkerSettings: [
        .linkedLibrary("c++"),
      ]),
    .target(
      name: "RimeKit",
      dependencies: [
        "RimeKitObjC",
        "HamsterKit",
      ],
      path: "Sources/Swift"),
    .testTarget(
      name: "RimeKitTests",
      dependencies: [
        "RimeKit",
        "librimeRIME",
        "boost_filesystemRIME",
        "boost_localeRIME",
        "boost_regexRIME",
        "boost_systemRIME",
        "libglogRIME",
        "libleveldbRIME",
        "libmarisaRIME",
        "libopenccRIME",
        "libyaml-cppRIME",
        "icudataRIME",
        "icui18nRIME",
        "icuioRIME",
        "icuucRIME",
      ]),
  ])
