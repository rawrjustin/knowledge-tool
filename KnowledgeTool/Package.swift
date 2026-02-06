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
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "KnowledgeTool",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift")
            ],
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
