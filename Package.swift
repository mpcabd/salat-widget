// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Salat",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Salat", targets: ["Salat"]),
        .library(name: "PrayerKit", targets: ["PrayerKit"]),
    ],
    targets: [
        .target(name: "PrayerKit"),
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
    ]
)
