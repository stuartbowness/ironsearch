// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IronSearch",
    platforms: [.macOS("27.0")],
    products: [.executable(name: "IronSearch", targets: ["IronSearch"])],
    targets: [
        .target(name: "SearchCore"),
        .executableTarget(name: "IronSearch", dependencies: ["SearchCore"]),
        .executableTarget(name: "SearchChecks", dependencies: ["SearchCore"], path: "Tests/SearchCoreTests")
    ]
)
