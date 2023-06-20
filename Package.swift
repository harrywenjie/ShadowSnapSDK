// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ShadowSnapSDK",
    platforms: [.iOS(.v14)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "ShadowSnapSDK",
            targets: ["ShadowSnapSDK"]),
    ],
    dependencies: [
                .package(url: "https://github.com/weichsel/ZIPFoundation.git", .upToNextMajor(from: "0.9.0"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "ShadowSnapSDK",
            dependencies: ["ZIPFoundation"],
            resources: [
                .process("Res/ARHead.obj"),
                .process("Res/camera_beep.mp3"),
                .process("Res/camera_fail.mp3"),
                .process("Res/camera_shutter.mp3"),
                .process("Res/headMask.png"),
                .process("Res/sampleMask.png")
            ]),
    ]
)
