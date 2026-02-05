// IdentityManager - Core state management for RemoteJuggler tray app

import Foundation
import SwiftUI

// MARK: - Models

/// Security mode for YubiKey PIN handling
///
/// Controls how YubiKey PINs are handled during signing operations:
/// - `maximumSecurity`: PIN required for every operation (default YubiKey behavior)
/// - `developerWorkflow`: PIN cached for session (default)
/// - `trustedWorkstation`: PIN stored in TPM/SecureEnclave for passwordless signing
enum SecurityMode: String, Codable, CaseIterable, Identifiable {
    case maximumSecurity = "maximum_security"
    case developerWorkflow = "developer_workflow"
    case trustedWorkstation = "trusted_workstation"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .maximumSecurity:
            return "Maximum Security"
        case .developerWorkflow:
            return "Developer Workflow"
        case .trustedWorkstation:
            return "Trusted Workstation"
        }
    }

    var description: String {
        switch self {
        case .maximumSecurity:
            return "PIN required for every operation"
        case .developerWorkflow:
            return "PIN cached for session"
        case .trustedWorkstation:
            return "PIN stored in secure hardware"
        }
    }

    var icon: String {
        switch self {
        case .maximumSecurity:
            return "lock.shield.fill"
        case .developerWorkflow:
            return "hammer.fill"
        case .trustedWorkstation:
            return "desktopcomputer"
        }
    }
}

/// GPG signing configuration
struct GpgConfig: Codable {
    var keyId: String = ""
    var signCommits: Bool = false
    var signTags: Bool = false
    var autoSignoff: Bool = false
    var securityMode: SecurityMode = .developerWorkflow
    var pinStorageMethod: String? = nil

    enum CodingKeys: String, CodingKey {
        case keyId
        case signCommits
        case signTags
        case autoSignoff
        case securityMode
        case pinStorageMethod
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyId = try container.decodeIfPresent(String.self, forKey: .keyId) ?? ""
        signCommits = try container.decodeIfPresent(Bool.self, forKey: .signCommits) ?? false
        signTags = try container.decodeIfPresent(Bool.self, forKey: .signTags) ?? false
        autoSignoff = try container.decodeIfPresent(Bool.self, forKey: .autoSignoff) ?? false
        securityMode = try container.decodeIfPresent(SecurityMode.self, forKey: .securityMode) ?? .developerWorkflow
        pinStorageMethod = try container.decodeIfPresent(String.self, forKey: .pinStorageMethod)
    }

    init() {}
}

struct Identity: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let provider: String
    let email: String
    let host: String
    var gpg: GpgConfig?

    init(id: String? = nil, name: String, provider: String, email: String, host: String, gpg: GpgConfig? = nil) {
        self.id = id ?? name
        self.name = name
        self.provider = provider
        self.email = email
        self.host = host
        self.gpg = gpg
    }

    static func == (lhs: Identity, rhs: Identity) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.provider == rhs.provider &&
        lhs.email == rhs.email && lhs.host == rhs.host
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
    var version: String?
    var identities: [String: IdentityConfig]
    var settings: ConfigSettings?

    struct IdentityConfig: Codable {
        var provider: String
        var host: String
        var user: String
        var email: String
        var sshKey: String?
        var gpgKey: String?
        var gpg: GpgConfig?
    }

    struct ConfigSettings: Codable {
        var defaultProvider: String?
        var autoDetect: Bool?
        var useKeychain: Bool?
        var gpgSign: Bool?
        /// Default security mode for new identities
        var defaultSecurityMode: SecurityMode?
        /// Whether hardware security module is available (runtime detection)
        var hsmAvailable: Bool?
        /// Require HSM for trusted_workstation mode
        var trustedWorkstationRequiresHSM: Bool?
    }
}

// MARK: - Identity Manager

@MainActor
class IdentityManager: ObservableObject {
    @Published var identities: [Identity] = []
    @Published var currentIdentity: Identity?
    @Published var currentSecurityMode: SecurityMode = .developerWorkflow
    @Published var forceMode: Bool = false {
        didSet { saveState() }
    }
    @Published var showNotifications: Bool = true {
        didSet { saveState() }
    }
    @Published var pinStored: Bool = false

    private let configURL: URL
    private let stateURL: URL
    private var cliPath: String {
        // Check multiple possible installation locations
        let paths = [
            "/usr/local/bin/remote-juggler",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/remote-juggler").path,
            "/opt/homebrew/bin/remote-juggler"
        ]
        return paths.first { FileManager.default.fileExists(atPath: $0) } ?? paths[0]
    }

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

    /// Set the security mode for YubiKey PIN handling
    /// - Parameter mode: The security mode to set
    func setSecurityMode(_ mode: SecurityMode) {
        Task {
            await performSetSecurityMode(mode)
        }
    }

    /// Store YubiKey PIN in secure storage (Secure Enclave on macOS)
    /// - Parameters:
    ///   - identity: The identity name to store the PIN for
    ///   - pin: The YubiKey PIN to store
    /// - Returns: True if PIN was stored successfully
    func storePIN(identity: String, pin: String) async -> Bool {
        return await performStorePIN(identity: identity, pin: pin)
    }

    /// Check if a PIN is stored for the given identity
    /// - Parameter identity: The identity name to check
    /// - Returns: True if a PIN is stored for this identity
    func hasPINStored(identity: String) -> Bool {
        // Check using CLI or keychain query
        guard FileManager.default.fileExists(atPath: cliPath) else {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["gpg-status", "--identity", identity, "--check-pin"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
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
                host: cfg.host,
                gpg: cfg.gpg
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
        // Update state immediately (CLI integration WIP)
        await MainActor.run {
            self.currentIdentity = identity
            self.saveState()

            if self.showNotifications {
                self.sendNotification(identity: identity)
            }
        }

        // Try to call CLI if it exists (for future full integration)
        guard FileManager.default.fileExists(atPath: cliPath) else {
            print("CLI not found at \(cliPath)")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["switch", identity.name]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                print("CLI switch note: \(output)")
            }
        } catch {
            print("CLI execution note: \(error)")
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

    private func performSetSecurityMode(_ mode: SecurityMode) async {
        // Update local state immediately
        await MainActor.run {
            self.currentSecurityMode = mode
        }

        // Call CLI to persist the change
        guard FileManager.default.fileExists(atPath: cliPath) else {
            print("CLI not found at \(cliPath)")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["config", "set", "security-mode", mode.rawValue]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                await MainActor.run {
                    if self.showNotifications {
                        self.sendSecurityModeNotification(mode: mode)
                    }
                }
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                print("Failed to set security mode: \(output)")
            }
        } catch {
            print("CLI execution error: \(error)")
        }
    }

    private func performStorePIN(identity: String, pin: String) async -> Bool {
        guard FileManager.default.fileExists(atPath: cliPath) else {
            print("CLI not found at \(cliPath)")
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["store-pin", "--identity", identity]

        // Create pipes for stdin, stdout, stderr
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()

            // Write PIN to stdin
            let pinData = (pin + "\n").data(using: .utf8)!
            stdinPipe.fileHandleForWriting.write(pinData)
            stdinPipe.fileHandleForWriting.closeFile()

            process.waitUntilExit()

            let success = process.terminationStatus == 0

            await MainActor.run {
                self.pinStored = success
                if success && self.showNotifications {
                    self.sendPINStoredNotification(identity: identity)
                }
            }

            return success
        } catch {
            print("CLI execution error: \(error)")
            return false
        }
    }

    private func sendSecurityModeNotification(mode: SecurityMode) {
        let content = UNMutableNotificationContent()
        content.title = "Security Mode Changed"
        content.body = "\(mode.displayName): \(mode.description)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func sendPINStoredNotification(identity: String) {
        let content = UNMutableNotificationContent()
        content.title = "YubiKey PIN Stored"
        content.body = "PIN securely stored for \(identity)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func refreshPINStatus() {
        guard let identity = currentIdentity else {
            pinStored = false
            return
        }
        pinStored = hasPINStored(identity: identity.name)
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
