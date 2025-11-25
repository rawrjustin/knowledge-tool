// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KnowledgeTool",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "KnowledgeTool",
            targets: ["KnowledgeTool"]
        )
    ],
    targets: [
        .executableTarget(
            name: "KnowledgeTool",
            path: "KnowledgeTool",
            resources: [
                .copy("Resources/KnowledgeTool.entitlements")
            ],
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals"),
                .enableUpcomingFeature("ConciseMagicFile"),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("ForwardTrailingClosures"),
                .enableUpcomingFeature("ImplicitOpenExistentials"),
                .enableUpcomingFeature("StrictConcurrency"),
                .unsafeFlags(["-enable-bare-slash-regex"])
            ]
        )
    ]
)
