// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Vault",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "VaultCore", targets: ["VaultCore"]),
        .executable(name: "vault-cli", targets: ["VaultCLI"]),
    ],
    targets: [
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        .target(name: "VaultCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "VaultCLI", dependencies: ["VaultCore"]),
        .testTarget(name: "VaultCoreTests", dependencies: ["VaultCore"]),
    ]
)
