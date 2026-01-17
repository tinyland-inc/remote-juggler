// swift-tools-version: 6.0
// RemoteJuggler macOS Tray Application

import PackageDescription

let package = Package(
    name: "RemoteJugglerTray",
    platforms: [
        .macOS(.v13)  // Requires macOS 13+ for MenuBarExtra
    ],
    products: [
        .executable(
            name: "RemoteJugglerTray",
            targets: ["RemoteJugglerTray"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "RemoteJugglerTray",
            dependencies: [],
            path: "Sources"
        )
    ]
)
