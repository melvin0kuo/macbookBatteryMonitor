// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "macbookBatteryMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "macbookBatteryMonitor",
            path: "Sources/macbookBatteryMonitor",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
            ]
        )
    ]
)
