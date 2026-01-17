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

            // Settings
            settingsSection

            Divider()
                .padding(.vertical, 4)

            // Footer
            footerSection
        }
        .padding(12)
        .frame(width: 280)
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

// MARK: - Preview (Xcode only)

#if DEBUG
struct MenuBarView_Previews: PreviewProvider {
    static var previews: some View {
        MenuBarView(manager: IdentityManager.preview)
            .frame(width: 280, height: 400)
    }
}
#endif
