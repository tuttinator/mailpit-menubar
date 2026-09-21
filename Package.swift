// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MailpitMenubar",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Sparkle 2: auto-updates from the SUFeedURL appcast (see Resources/Info.plist).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "MailpitMenubar",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/MailpitMenubar",
            linkerSettings: [
                // Sparkle.framework is copied into Contents/Frameworks by `make bundle`.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        )
    ]
)
