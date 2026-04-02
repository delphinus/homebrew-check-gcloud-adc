// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "check-gcloud-adc",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CheckGcloudADCLib",
            path: "Sources/CheckGcloudADCLib",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "check-gcloud-adc",
            dependencies: ["CheckGcloudADCLib"],
            path: "Sources/check-gcloud-adc"
        ),
        .executableTarget(
            name: "check-gcloud-adc-tests",
            dependencies: ["CheckGcloudADCLib"],
            path: "Sources/check-gcloud-adc-tests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
