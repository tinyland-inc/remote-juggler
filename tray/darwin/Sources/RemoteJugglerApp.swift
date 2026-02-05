// RemoteJuggler macOS Tray Application
// SwiftUI MenuBarExtra implementation for macOS 13+

import SwiftUI

@main
struct RemoteJugglerApp: App {
    @StateObject private var manager = IdentityManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(manager: manager)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: manager.forceMode ? "person.fill.badge.plus" : "person.fill")
                if let identity = manager.currentIdentity {
                    Text(identity.name)
                        .font(.system(size: 12))
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @ObservedObject var manager: IdentityManager
    @State private var showPINSheet = false
    @State private var pinInput = ""
    @State private var pinError: String? = nil
    @State private var isStoringPIN = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerSection

            Divider()
                .padding(.vertical, 4)

            // Identity List
            identityListSection

            Divider()
                .padding(.vertical, 4)

            // Security Mode
            securityModeSection

            Divider()
                .padding(.vertical, 4)

            // Settings
            settingsSection

            Divider()
                .padding(.vertical, 4)

            // Footer
            footerSection
        }
        .padding(12)
        .frame(width: 280)
        .sheet(isPresented: $showPINSheet) {
            PINEntrySheet(
                identityName: manager.currentIdentity?.name ?? "Unknown",
                pinInput: $pinInput,
                pinError: $pinError,
                isStoring: $isStoringPIN,
                onStore: storePIN,
                onCancel: {
                    showPINSheet = false
                    pinInput = ""
                    pinError = nil
                }
            )
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack {
            Image(systemName: "person.circle.fill")
                .font(.title2)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(manager.currentIdentity?.name ?? "No Identity")
                    .font(.headline)

                if let identity = manager.currentIdentity {
                    Text(identity.email)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if manager.forceMode {
                Text("FORCED")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange)
                    .cornerRadius(4)
            }
        }
    }

    private var identityListSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Identities")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

            ForEach(manager.identities) { identity in
                IdentityRow(
                    identity: identity,
                    isSelected: identity.id == manager.currentIdentity?.id,
                    action: { manager.switchTo(identity) }
                )
            }
        }
    }

    private var securityModeSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Security Mode")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

            ForEach(SecurityMode.allCases) { mode in
                SecurityModeRow(
                    mode: mode,
                    isSelected: manager.currentSecurityMode == mode,
                    action: { manager.setSecurityMode(mode) }
                )
            }

            // Store YubiKey PIN button (only enabled in Trusted Workstation mode)
            Button(action: {
                showPINSheet = true
            }) {
                HStack {
                    Image(systemName: "key.fill")
                        .frame(width: 20)
                        .foregroundColor(manager.currentSecurityMode == .trustedWorkstation ? .accentColor : .gray)
                    Text("Store YubiKey PIN...")
                    Spacer()
                    if manager.pinStored {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
            .disabled(manager.currentSecurityMode != .trustedWorkstation)
            .opacity(manager.currentSecurityMode == .trustedWorkstation ? 1.0 : 0.5)
            .padding(.top, 4)
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $manager.forceMode) {
                HStack {
                    Image(systemName: "lock.fill")
                    Text("Force Global Identity")
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Toggle(isOn: $manager.showNotifications) {
                HStack {
                    Image(systemName: "bell.fill")
                    Text("Show Notifications")
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    private func storePIN() {
        guard let identity = manager.currentIdentity else {
            pinError = "No identity selected"
            return
        }

        guard !pinInput.isEmpty else {
            pinError = "PIN cannot be empty"
            return
        }

        // YubiKey PINs are typically 6-8 digits
        guard pinInput.count >= 4 && pinInput.count <= 8 else {
            pinError = "PIN must be 4-8 characters"
            return
        }

        isStoringPIN = true
        pinError = nil

        Task {
            let success = await manager.storePIN(identity: identity.name, pin: pinInput)

            await MainActor.run {
                isStoringPIN = false
                if success {
                    showPINSheet = false
                    pinInput = ""
                    pinError = nil
                } else {
                    pinError = "Failed to store PIN. Check CLI output."
                }
            }
        }
    }

    private var footerSection: some View {
        HStack {
            Button("Refresh") {
                manager.reload()
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .font(.caption)
    }
}

// MARK: - Identity Row

struct IdentityRow: View {
    let identity: Identity
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: providerIcon)
                    .frame(width: 20)
                    .foregroundColor(providerColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text(identity.name)
                        .font(.system(size: 13))
                    Text(identity.provider)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private var providerIcon: String {
        switch identity.provider {
        case "gitlab": return "g.circle.fill"
        case "github": return "chevron.left.forwardslash.chevron.right"
        case "bitbucket": return "b.circle.fill"
        default: return "questionmark.circle"
        }
    }

    private var providerColor: Color {
        switch identity.provider {
        case "gitlab": return .orange
        case "github": return .primary
        case "bitbucket": return .blue
        default: return .gray
        }
    }
}

// MARK: - Security Mode Row

struct SecurityModeRow: View {
    let mode: SecurityMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .frame(width: 20)
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                Image(systemName: mode.icon)
                    .frame(width: 16)
                    .foregroundColor(modeColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text(mode.displayName)
                        .font(.system(size: 13))
                    Text(mode.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private var modeColor: Color {
        switch mode {
        case .maximumSecurity: return .red
        case .developerWorkflow: return .orange
        case .trustedWorkstation: return .green
        }
    }
}

// MARK: - PIN Entry Sheet

struct PINEntrySheet: View {
    let identityName: String
    @Binding var pinInput: String
    @Binding var pinError: String?
    @Binding var isStoring: Bool
    let onStore: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "key.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Store YubiKey PIN")
                    .font(.headline)
            }

            Text("Store your YubiKey PIN securely for identity:")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(identityName)
                .font(.body)
                .fontWeight(.medium)

            // PIN Input
            SecureField("Enter YubiKey PIN", text: $pinInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .disabled(isStoring)

            // Error message
            if let error = pinError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Security note
            Text("PIN will be stored in macOS Secure Enclave")
                .font(.caption2)
                .foregroundColor(.secondary)

            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .disabled(isStoring)

                Button(action: onStore) {
                    if isStoring {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Store PIN")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isStoring || pinInput.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 300)
    }
}

// MARK: - Preview (Xcode only)

#if DEBUG
struct MenuBarView_Previews: PreviewProvider {
    static var previews: some View {
        MenuBarView(manager: IdentityManager.preview)
            .frame(width: 280, height: 400)
    }
}
#endif
