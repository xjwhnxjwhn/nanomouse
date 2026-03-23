// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NanomouseReviewKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "NanomouseReviewKit",
            targets: ["NanomouseReviewKit"]
        ),
    ],
    targets: [
        .target(
            name: "NanomouseReviewKit",
            path: "Sources"
        ),
        .testTarget(
            name: "NanomouseReviewKitTests",
            dependencies: ["NanomouseReviewKit"],
            path: "Tests"
        ),
    ]
)
