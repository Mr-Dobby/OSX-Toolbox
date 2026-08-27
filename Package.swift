// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RALBEOSXToolbox",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "RALBEOSXToolbox",
            path: "Sources/RALBEOSXToolbox"
        )
    ]
)
