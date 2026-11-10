// swift-tools-version: 6.0
import PackageDescription

// Geocache data model, SQLite storage of cache lists and GPX import for the iCacheBox app.
// Written from scratch (Apache-2.0 like the app); Cachebox for Android only served as a functional reference.
let package = Package(
    name: "CacheboxCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CacheboxCore", targets: ["CacheboxCore"]),
    ],
    targets: [
        .target(name: "CacheboxCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "CacheboxCoreTests", dependencies: ["CacheboxCore"], resources: [.copy("Resources")]),
    ]
)
