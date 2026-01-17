// IdentityManager - Core state management for RemoteJuggler tray app

import Foundation
import SwiftUI

// MARK: - Models

struct Identity: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let provider: String
    let email: String
    let host: String

    init(id: String? = nil, name: String, provider: String, email: String, host: String) {
        self.id = id ?? name
        self.name = name
        self.provider = provider
        self.email = email
        self.host = host
    }
}

struct GlobalState: Codable {
    var version: String = "1.0.0"
    var currentIdentity: String
    var forceMode: Bool = false
    var lastSwitch: Date?
    var tray: TraySettings = TraySettings()
    var recentIdentities: [String] = []
}

struct TraySettings: Codable {
    var showNotifications: Bool = true
    var autoStartEnabled: Bool = false
    var iconStyle: String = "default"
}

struct Config: Codable {
    var identities: [String: IdentityConfig]

    struct IdentityConfig: Codable {
        var provider: String
        var host: String
        var hostname: String
        var user: String
        var email: String
    }
}

// MARK: - Identity Manager

@MainActor
class IdentityManager: ObservableObject {
    @Published var identities: [Identity] = []
    @Published var currentIdentity: Identity?
    @Published var forceMode: Bool = false {
        didSet { saveState() }
    }
    @Published var showNotifications: Bool = true {
        didSet { saveState() }
    }

    private let configURL: URL
    private let stateURL: URL
    private let cliPath = "/usr/local/bin/remote-juggler"

    init() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/remote-juggler")

        self.configURL = configDir.appendingPathComponent("config.json")
        self.stateURL = configDir.appendingPathComponent("global.json")

        reload()
    }

    // MARK: - Public Methods

    func reload() {
        loadConfig()
        loadState()
    }

    func switchTo(_ identity: Identity) {
        Task {
            await performSwitch(identity)
        }
    }

    // MARK: - Private Methods

    private func loadConfig() {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            print("Failed to load config from \(configURL.path)")
            return
        }

        identities = config.identities.map { (name, cfg) in
            Identity(
                name: name,
                provider: cfg.provider,
                email: cfg.email,
                host: cfg.host
            )
        }.sorted { $0.name < $1.name }
    }

    private func loadState() {
        if let data = try? Data(contentsOf: stateURL),
           let state = try? JSONDecoder().decode(GlobalState.self, from: data) {
            forceMode = state.forceMode
            showNotifications = state.tray.showNotifications
            currentIdentity = identities.first { $0.name == state.currentIdentity }
        } else {
            // Default to first identity if no state
            currentIdentity = identities.first
        }
    }

    private func saveState() {
        let state = GlobalState(
            currentIdentity: currentIdentity?.name ?? "",
            forceMode: forceMode,
            lastSwitch: Date(),
            tray: TraySettings(
                showNotifications: showNotifications,
                autoStartEnabled: false,
                iconStyle: "default"
            ),
            recentIdentities: []
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        if let data = try? encoder.encode(state) {
            try? data.write(to: stateURL)
        }
    }

    private func performSwitch(_ identity: Identity) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["switch", identity.name]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                await MainActor.run {
                    self.currentIdentity = identity
                    self.saveState()

                    if self.showNotifications {
                        self.sendNotification(identity: identity)
                    }
                }
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                print("Switch failed: \(output)")
            }
        } catch {
            print("Failed to run CLI: \(error)")
        }
    }

    private func sendNotification(identity: Identity) {
        let content = UNMutableNotificationContent()
        content.title = "Identity Switched"
        content.body = "Now using \(identity.name) (\(identity.provider))"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Preview Support

    static var preview: IdentityManager {
        let manager = IdentityManager()
        manager.identities = [
            Identity(name: "gitlab-work", provider: "gitlab", email: "work@company.com", host: "gitlab-work"),
            Identity(name: "gitlab-personal", provider: "gitlab", email: "personal@email.com", host: "gitlab-personal"),
            Identity(name: "github-oss", provider: "github", email: "oss@email.com", host: "github.com")
        ]
        manager.currentIdentity = manager.identities.first
        manager.forceMode = false
        return manager
    }
}

// Required for notifications
import UserNotifications
