// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "reminders",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "reminders",
            path: "Sources"
        )
    ]
)
