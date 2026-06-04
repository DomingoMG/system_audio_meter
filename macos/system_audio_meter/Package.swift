// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "system_audio_meter",
    platforms: [
        .macOS("10.15")
    ],
    products: [
        .library(name: "system-audio-meter", targets: ["system_audio_meter"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "system_audio_meter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                // If your plugin requires a privacy manifest, for example if it collects user
                // data, update the PrivacyInfo.xcprivacy file to describe your plugin's
                // privacy impact, and then uncomment these lines. For more information, see
                // https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
                // .process("PrivacyInfo.xcprivacy"),

                // If you have other resources that need to be bundled with your plugin, refer to
                // the following instructions to add them:
                // https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package
            ]
        )
    ]
)
