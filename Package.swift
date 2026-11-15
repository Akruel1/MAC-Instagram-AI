// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InstagramAIStudio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "InstagramAIStudioCore", targets: ["Core"]),
        .library(name: "InstagramAIStudioBackend", targets: ["BackendInterface"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "AppUI", targets: ["AppUI"]),
        .executable(name: "instagram-ai-studio", targets: ["CLI"]),
        .executable(name: "InstagramAIStudio", targets: ["InstagramAIStudio"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "Core",
            dependencies: [],
            path: "Sources/Core"
        ),
        .target(
            name: "Persistence",
            dependencies: [
                "Core",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/Persistence"
        ),
        .target(
            name: "Jobs",
            dependencies: ["Core", "Persistence"],
            path: "Sources/Jobs"
        ),
        .target(
            name: "MCP",
            dependencies: ["Core", "Persistence"],
            path: "Sources/MCP"
        ),
        .target(
            name: "Instagram",
            dependencies: ["Core", "Persistence"],
            path: "Sources/Instagram"
        ),
        .target(
            name: "Video",
            dependencies: ["Core", "Persistence", "Jobs"],
            path: "Sources/Video"
        ),
        .target(
            name: "Dependencies",
            dependencies: ["Core", "Persistence"],
            path: "Sources/Dependencies"
        ),
        .target(
            name: "Hermes",
            dependencies: ["Core", "Dependencies"],
            path: "Sources/Hermes"
        ),
        .target(
            name: "AI",
            dependencies: ["Core", "Persistence", "MCP", "Instagram", "Video"],
            path: "Sources/AI"
        ),
        .target(
            name: "BackendInterface",
            dependencies: [
                "Core",
                "Persistence",
                "AI",
                "MCP",
                "Instagram",
                "Video",
                "Dependencies",
                "Hermes",
                "Jobs"
            ],
            path: "Sources/BackendInterface"
        ),
        .target(
            name: "DesignSystem",
            dependencies: [],
            path: "Sources/DesignSystem"
        ),
        .target(
            name: "AppUI",
            dependencies: ["DesignSystem", "BackendInterface", "Core", "Persistence", "Jobs", "Dependencies", "Hermes"],
            path: "Sources/AppUI"
        ),
        .executableTarget(
            name: "InstagramAIStudio",
            dependencies: ["AppUI", "DesignSystem", "BackendInterface", "Core"],
            path: "Sources/InstagramAIStudio"
        ),
        .executableTarget(
            name: "CLI",
            dependencies: ["BackendInterface", "Core"],
            path: "Sources/CLI"
        ),
        .executableTarget(
            name: "TestHarness",
            dependencies: [
                "BackendInterface",
                "Core",
                "Persistence",
                "AI",
                "MCP",
                "Instagram",
                "Video",
                "Dependencies",
                "Hermes",
                "Jobs"
            ],
            path: "Sources/TestHarness"
        ),
        .testTarget(name: "CoreTests", dependencies: ["Core"], path: "Tests/CoreTests"),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence", "Core"], path: "Tests/PersistenceTests"),
        .testTarget(name: "AITests", dependencies: ["AI", "Core", "Persistence"], path: "Tests/AITests"),
        .testTarget(name: "MCPTests", dependencies: ["MCP", "Core"], path: "Tests/MCPTests"),
        .testTarget(name: "InstagramTests", dependencies: ["Instagram", "Core"], path: "Tests/InstagramTests"),
        .testTarget(name: "VideoTests", dependencies: ["Video", "Core", "Jobs", "Persistence"], path: "Tests/VideoTests"),
        .testTarget(name: "DependenciesTests", dependencies: ["Dependencies", "Core"], path: "Tests/DependenciesTests"),
        .testTarget(name: "HermesTests", dependencies: ["Hermes", "Core"], path: "Tests/HermesTests"),
        .testTarget(name: "JobsTests", dependencies: ["Jobs", "Core", "Persistence"], path: "Tests/JobsTests"),
        .testTarget(
            name: "SecurityTests",
            dependencies: ["Core", "MCP", "AI", "Instagram", "Video", "Dependencies"],
            path: "Tests/SecurityTests"
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: [
                "BackendInterface",
                "Persistence",
                "MCP",
                "Video",
                "Core",
                "AI"
            ],
            path: "Tests/IntegrationTests"
        ),
        .testTarget(
            name: "AppUITests",
            dependencies: ["AppUI", "DesignSystem", "BackendInterface", "Core", "Persistence"],
            path: "Tests/AppUITests"
        )
    ]
)
