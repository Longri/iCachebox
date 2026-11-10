// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mapsforge",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "MapsforgeCore", targets: ["MapsforgeCore"]),
        .library(name: "MapsforgeRender", targets: ["MapsforgeRender"]),
        .executable(name: "mfdump", targets: ["mfdump"]),
    ],
    targets: [
        // Platform-independent port of mapsforge-core + mapsforge-map-reader.
        .target(name: "MapsforgeCore"),

        // Rendertheme parser and CoreGraphics tile renderer.
        .target(
            name: "MapsforgeRender",
            dependencies: ["MapsforgeCore"],
            resources: [.copy("Resources/themes")]
        ),

        // Developer CLI: dump tiles as JSON, render tiles as PNG, benchmark.
        .executableTarget(
            name: "mfdump",
            dependencies: ["MapsforgeCore", "MapsforgeRender"]
        ),

        .testTarget(name: "MapsforgeCoreTests", dependencies: ["MapsforgeCore"]),
        .testTarget(name: "MapsforgeRenderTests", dependencies: ["MapsforgeCore", "MapsforgeRender"]),
    ]
)
