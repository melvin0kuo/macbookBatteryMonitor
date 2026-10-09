// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "BatteryMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "BatteryMonitor",
            path: "Sources/BatteryMonitor",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
            ]
        )
    ]
)
