// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UnagiReader",
    defaultLocalization: "en",
    // Build floor, not the support floor (macOS 27.0; see docs/decisions/0065). CI has no macOS 27 runner,
    // so raising this would stop `swift test` there.
    platforms: [.macOS("26.6")],
    products: [.executable(name: "UnagiReader", targets: ["UnagiReader"])],
    dependencies: [.package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.13.9")],
    targets: [
        .target(name: "ReaderCore", dependencies: ["SwiftSoup"],
                resources: [.copy("Resources/Localizable.xcstrings")], plugins: ["CompileCatalog"]),
        .executableTarget(name: "UnagiReader", dependencies: ["ReaderCore"]),
        .testTarget(name: "ReaderCoreTests", dependencies: ["ReaderCore"]),
        .testTarget(name: "ReaderUITests", dependencies: ["UnagiReader"]),
        .plugin(name: "CompileCatalog", capability: .buildTool())
    ]
)
