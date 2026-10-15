// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Salat",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Salat", targets: ["Salat"]),
        .library(name: "PrayerKit", targets: ["PrayerKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/batoulapps/adhan-swift", exact: "1.5.0"),
    ],
    targets: [
        .target(
            name: "PrayerKit",
            dependencies: [.product(name: "Adhan", package: "adhan-swift")]
        ),
        .executableTarget(
            name: "Salat",
            dependencies: ["PrayerKit"]
        ),
        .executableTarget(
            name: "prayerkit-check",
            dependencies: ["PrayerKit"],
            path: "Tests/PrayerKitCheck"
        ),
        .testTarget(
            name: "PrayerKitTests",
            dependencies: ["PrayerKit"]
        ),
        .testTarget(
            name: "SalatTests",
            dependencies: ["Salat", "PrayerKit"]
        ),
    ]
)
