// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "YTSubs", platforms: [.macOS(.v13)], products: [.executable(name: "YTSubs", targets: ["YTSubs"])], targets: [.target(name: "YTSubsCore"), .executableTarget(name: "YTSubs", dependencies: ["YTSubsCore"]), .executableTarget(name: "YTSubsBridge", dependencies: ["YTSubsCore"]), .testTarget(name: "YTSubsCoreTests", dependencies: ["YTSubsCore"])])
