// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SavedPlacesCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "SavedPlacesCore", targets: ["SavedPlacesCore"])
    ],
    targets: [
        .target(
            name: "SavedPlacesCore",
            path: "Sources/SavedPlacesCore"
        ),
        .testTarget(
            name: "SavedPlacesCoreTests",
            dependencies: ["SavedPlacesCore"],
            path: "Tests/SavedPlacesCoreTests"
        )
    ]
)
