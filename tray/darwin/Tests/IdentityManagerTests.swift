// RemoteJuggler macOS Tray Tests
//
// XCTest suite for identity management, configuration loading, and state handling.
//
// Run with: swift test

import XCTest
import Foundation

// =============================================================================
// Test Configuration Types (mirrors main app types)
// =============================================================================

/// Security mode for YubiKey PIN handling
enum TestSecurityMode: String, Codable {
    case maximumSecurity = "maximum_security"
    case developerWorkflow = "developer_workflow"
    case trustedWorkstation = "trusted_workstation"
}

/// GPG configuration
struct TestGpgConfig: Codable {
    var keyId: String?
    var signCommits: Bool?
    var signTags: Bool?
    var securityMode: TestSecurityMode?
    var pinStorageMethod: String?
}

/// Identity configuration from config.json
struct TestIdentityConfig: Codable {
    var provider: String
    var host: String
    var hostname: String?
    var user: String
    var email: String?
    var gpg: TestGpgConfig?
}

/// Application settings
struct TestSettings: Codable {
    var defaultProvider: String?
    var autoDetect: Bool?
    var useKeychain: Bool?
    var gpgSign: Bool?
    var defaultSecurityMode: TestSecurityMode?
    var hsmAvailable: Bool?
}

/// Main configuration structure
struct TestConfig: Codable {
    var version: String?
    var identities: [String: TestIdentityConfig]
    var settings: TestSettings?
}

/// Global state
struct TestGlobalState: Codable {
    var version: String?
    var currentIdentity: String?
    var forceMode: Bool?
    var lastSwitch: Date?
    var recentIdentities: [String]?

    struct TraySettings: Codable {
        var showNotifications: Bool?
        var autoStartEnabled: Bool?
        var iconStyle: String?
    }
    var tray: TraySettings?
}

// =============================================================================
// Configuration Tests
// =============================================================================

final class ConfigurationTests: XCTestCase {

    func testParseMinimalConfig() throws {
        let json = """
        {
            "identities": {}
        }
        """

        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(TestConfig.self, from: data)

        XCTAssertTrue(config.identities.isEmpty)
    }

    func testParseFullConfig() throws {
        let json = """
        {
            "version": "2.0.0",
            "identities": {
                "personal": {
                    "provider": "gitlab",
                    "host": "gitlab-personal",
                    "hostname": "gitlab.com",
                    "user": "personaluser",
                    "email": "personal@example.com"
                },
                "work": {
                    "provider": "github",
                    "host": "github.com",
                    "hostname": "github.com",
                    "user": "workuser",
                    "email": "work@company.com",
                    "gpg": {
                        "keyId": "ABCD1234",
                        "signCommits": true,
                        "securityMode": "trusted_workstation",
                        "pinStorageMethod": "secure_enclave"
                    }
                }
            },
            "settings": {
                "defaultProvider": "gitlab",
                "autoDetect": true,
                "gpgSign": true
            }
        }
        """

        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(TestConfig.self, from: data)

        XCTAssertEqual(config.version, "2.0.0")
        XCTAssertEqual(config.identities.count, 2)

        // Check personal identity
        let personal = try XCTUnwrap(config.identities["personal"])
        XCTAssertEqual(personal.provider, "gitlab")
        XCTAssertEqual(personal.email, "personal@example.com")
        XCTAssertNil(personal.gpg)

        // Check work identity with GPG
        let work = try XCTUnwrap(config.identities["work"])
        XCTAssertEqual(work.provider, "github")

        let gpg = try XCTUnwrap(work.gpg)
        XCTAssertEqual(gpg.keyId, "ABCD1234")
        XCTAssertEqual(gpg.signCommits, true)
        XCTAssertEqual(gpg.securityMode, .trustedWorkstation)
        XCTAssertEqual(gpg.pinStorageMethod, "secure_enclave")

        // Check settings
        let settings = try XCTUnwrap(config.settings)
        XCTAssertEqual(settings.defaultProvider, "gitlab")
        XCTAssertEqual(settings.autoDetect, true)
        XCTAssertEqual(settings.gpgSign, true)
    }

    func testParseConfigWithMissingFields() throws {
        let json = """
        {
            "identities": {
                "test": {
                    "provider": "github",
                    "host": "github.com",
                    "user": "testuser"
                }
            }
        }
        """

        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(TestConfig.self, from: data)

        let identity = try XCTUnwrap(config.identities["test"])
        XCTAssertNil(identity.email)
        XCTAssertNil(identity.hostname)
    }
}

// =============================================================================
// Security Mode Tests
// =============================================================================

final class SecurityModeTests: XCTestCase {

    func testSecurityModeRawValues() {
        XCTAssertEqual(TestSecurityMode.maximumSecurity.rawValue, "maximum_security")
        XCTAssertEqual(TestSecurityMode.developerWorkflow.rawValue, "developer_workflow")
        XCTAssertEqual(TestSecurityMode.trustedWorkstation.rawValue, "trusted_workstation")
    }

    func testSecurityModeSerialization() throws {
        let gpg = TestGpgConfig(
            keyId: "TEST123",
            signCommits: true,
            securityMode: .trustedWorkstation
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(gpg)

        let decoder = JSONDecoder()
        let parsed = try decoder.decode(TestGpgConfig.self, from: data)

        XCTAssertEqual(parsed.securityMode, .trustedWorkstation)
    }

    func testAllSecurityModes() throws {
        let modes: [TestSecurityMode] = [.maximumSecurity, .developerWorkflow, .trustedWorkstation]

        for mode in modes {
            let gpg = TestGpgConfig(securityMode: mode)
            let data = try JSONEncoder().encode(gpg)
            let parsed = try JSONDecoder().decode(TestGpgConfig.self, from: data)
            XCTAssertEqual(parsed.securityMode, mode)
        }
    }
}

// =============================================================================
// Global State Tests
// =============================================================================

final class GlobalStateTests: XCTestCase {

    func testParseBasicState() throws {
        let json = """
        {
            "version": "2.0.0",
            "currentIdentity": "personal"
        }
        """

        let data = json.data(using: .utf8)!
        let state = try JSONDecoder().decode(TestGlobalState.self, from: data)

        XCTAssertEqual(state.version, "2.0.0")
        XCTAssertEqual(state.currentIdentity, "personal")
    }

    func testParseFullState() throws {
        let json = """
        {
            "version": "2.0.0",
            "currentIdentity": "work",
            "forceMode": true,
            "tray": {
                "showNotifications": true,
                "autoStartEnabled": false,
                "iconStyle": "monochrome"
            },
            "recentIdentities": ["work", "personal"]
        }
        """

        let data = json.data(using: .utf8)!
        let state = try JSONDecoder().decode(TestGlobalState.self, from: data)

        XCTAssertEqual(state.forceMode, true)

        let tray = try XCTUnwrap(state.tray)
        XCTAssertEqual(tray.showNotifications, true)
        XCTAssertEqual(tray.autoStartEnabled, false)
        XCTAssertEqual(tray.iconStyle, "monochrome")

        let recent = try XCTUnwrap(state.recentIdentities)
        XCTAssertEqual(recent.count, 2)
        XCTAssertEqual(recent[0], "work")
    }

    func testStateRoundtrip() throws {
        var state = TestGlobalState()
        state.version = "2.0.0"
        state.currentIdentity = "test"
        state.forceMode = false
        state.recentIdentities = ["test", "other"]

        let encoder = JSONEncoder()
        let data = try encoder.encode(state)

        let decoder = JSONDecoder()
        let parsed = try decoder.decode(TestGlobalState.self, from: data)

        XCTAssertEqual(parsed.version, state.version)
        XCTAssertEqual(parsed.currentIdentity, state.currentIdentity)
        XCTAssertEqual(parsed.forceMode, state.forceMode)
        XCTAssertEqual(parsed.recentIdentities, state.recentIdentities)
    }
}

// =============================================================================
// GPG Config Tests
// =============================================================================

final class GpgConfigTests: XCTestCase {

    func testParseGpgConfigDefaults() throws {
        let json = "{}"

        let data = json.data(using: .utf8)!
        let gpg = try JSONDecoder().decode(TestGpgConfig.self, from: data)

        XCTAssertNil(gpg.keyId)
        XCTAssertNil(gpg.signCommits)
        XCTAssertNil(gpg.signTags)
        XCTAssertNil(gpg.securityMode)
    }

    func testParseGpgConfigFull() throws {
        let json = """
        {
            "keyId": "ABC123",
            "signCommits": true,
            "signTags": true,
            "securityMode": "maximum_security",
            "pinStorageMethod": "secure_enclave"
        }
        """

        let data = json.data(using: .utf8)!
        let gpg = try JSONDecoder().decode(TestGpgConfig.self, from: data)

        XCTAssertEqual(gpg.keyId, "ABC123")
        XCTAssertEqual(gpg.signCommits, true)
        XCTAssertEqual(gpg.signTags, true)
        XCTAssertEqual(gpg.securityMode, .maximumSecurity)
        XCTAssertEqual(gpg.pinStorageMethod, "secure_enclave")
    }
}

// =============================================================================
// Provider Tests
// =============================================================================

final class ProviderTests: XCTestCase {

    func testAllProviderTypes() throws {
        let providers = ["gitlab", "github", "bitbucket"]

        for provider in providers {
            let json = """
            {
                "identities": {
                    "test": {
                        "provider": "\(provider)",
                        "host": "test.com",
                        "user": "testuser"
                    }
                }
            }
            """

            let data = json.data(using: .utf8)!
            let config = try JSONDecoder().decode(TestConfig.self, from: data)

            let identity = try XCTUnwrap(config.identities["test"])
            XCTAssertEqual(identity.provider, provider)
        }
    }
}

// =============================================================================
// File System Tests
// =============================================================================

final class FileSystemTests: XCTestCase {

    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testLoadConfigFromFile() throws {
        let configPath = tempDir.appendingPathComponent("config.json")

        let json = """
        {
            "version": "2.0.0",
            "identities": {
                "file-test": {
                    "provider": "gitlab",
                    "host": "gitlab.com",
                    "user": "fileuser",
                    "email": "file@test.com"
                }
            }
        }
        """

        try json.write(to: configPath, atomically: true, encoding: .utf8)

        let data = try Data(contentsOf: configPath)
        let config = try JSONDecoder().decode(TestConfig.self, from: data)

        XCTAssertNotNil(config.identities["file-test"])
    }

    func testSaveStateToFile() throws {
        let statePath = tempDir.appendingPathComponent("state.json")

        var state = TestGlobalState()
        state.version = "2.0.0"
        state.currentIdentity = "saved-test"

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(state)
        try data.write(to: statePath)

        // Read back
        let loadedData = try Data(contentsOf: statePath)
        let loadedState = try JSONDecoder().decode(TestGlobalState.self, from: loadedData)

        XCTAssertEqual(loadedState.currentIdentity, "saved-test")
    }
}

// =============================================================================
// Performance Tests
// =============================================================================

final class PerformanceTests: XCTestCase {

    func testConfigParsingPerformance() throws {
        let json = """
        {
            "identities": {
                "id1": {"provider": "gitlab", "host": "h1", "user": "u1", "email": "e1@test.com"},
                "id2": {"provider": "github", "host": "h2", "user": "u2", "email": "e2@test.com"},
                "id3": {"provider": "bitbucket", "host": "h3", "user": "u3", "email": "e3@test.com"}
            },
            "settings": {
                "defaultProvider": "gitlab",
                "autoDetect": true
            }
        }
        """
        let data = json.data(using: .utf8)!

        measure {
            for _ in 0..<100 {
                _ = try? JSONDecoder().decode(TestConfig.self, from: data)
            }
        }
    }
}
