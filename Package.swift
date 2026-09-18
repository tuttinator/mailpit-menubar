// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MailpitMenubar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MailpitMenubar",
            path: "Sources/MailpitMenubar"
        )
    ]
)
