// RemoteJuggler Linux Tray Application
// System tray for global git identity management using fyne.io/systray

package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"fyne.io/systray"
	"github.com/godbus/dbus/v5"
)

// SecurityMode represents the security mode for YubiKey PIN handling
type SecurityMode string

const (
	// SecurityModeMaximum - PIN required for every operation (default YubiKey behavior)
	SecurityModeMaximum SecurityMode = "maximum_security"
	// SecurityModeDeveloper - PIN cached for session (default)
	SecurityModeDeveloper SecurityMode = "developer_workflow"
	// SecurityModeTrusted - PIN stored in TPM/SecureEnclave for passwordless signing
	SecurityModeTrusted SecurityMode = "trusted_workstation"
)

// GpgConfig represents GPG signing configuration
type GpgConfig struct {
	KeyId            string       `json:"keyId,omitempty"`
	SignCommits      bool         `json:"signCommits,omitempty"`
	SignTags         bool         `json:"signTags,omitempty"`
	AutoSignoff      bool         `json:"autoSignoff,omitempty"`
	HardwareKey      bool         `json:"hardwareKey,omitempty"`
	TouchPolicy      string       `json:"touchPolicy,omitempty"`
	SecurityMode     SecurityMode `json:"securityMode,omitempty"`
	PinStorageMethod string       `json:"pinStorageMethod,omitempty"`
}

// Identity represents a git identity configuration
type Identity struct {
	Name     string     `json:"name"`
	Provider string     `json:"provider"`
	Email    string     `json:"email"`
	Host     string     `json:"host"`
	Gpg      *GpgConfig `json:"gpg,omitempty"`
}

// Config represents the remote-juggler configuration file
type Config struct {
	Identities map[string]IdentityConfig `json:"identities"`
	Settings   *ConfigSettings           `json:"settings,omitempty"`
}

// IdentityConfig represents identity configuration from config.json
type IdentityConfig struct {
	Provider string     `json:"provider"`
	Host     string     `json:"host"`
	Hostname string     `json:"hostname"`
	User     string     `json:"user"`
	Email    string     `json:"email"`
	Gpg      *GpgConfig `json:"gpg,omitempty"`
}

// ConfigSettings represents application settings
type ConfigSettings struct {
	DefaultProvider               string       `json:"defaultProvider,omitempty"`
	AutoDetect                    bool         `json:"autoDetect,omitempty"`
	UseKeychain                   bool         `json:"useKeychain,omitempty"`
	GpgSign                       bool         `json:"gpgSign,omitempty"`
	DefaultSecurityMode           SecurityMode `json:"defaultSecurityMode,omitempty"`
	HsmAvailable                  bool         `json:"hsmAvailable,omitempty"`
	TrustedWorkstationRequiresHSM bool         `json:"trustedWorkstationRequiresHSM,omitempty"`
}

// GlobalState represents the singleton global state
type GlobalState struct {
	Version          string       `json:"version"`
	CurrentIdentity  string       `json:"currentIdentity"`
	ForceMode        bool         `json:"forceMode"`
	LastSwitch       *time.Time   `json:"lastSwitch,omitempty"`
	Tray             TraySettings `json:"tray"`
	RecentIdentities []string     `json:"recentIdentities"`
}

// TraySettings for the tray application
type TraySettings struct {
	ShowNotifications bool   `json:"showNotifications"`
	AutoStartEnabled  bool   `json:"autoStartEnabled"`
	IconStyle         string `json:"iconStyle"`
}

var (
	identities          []Identity
	globalState         GlobalState
	configDir           string
	cliPath                          = "/usr/local/bin/remote-juggler"
	currentSecurityMode SecurityMode = SecurityModeDeveloper
)

func main() {
	// Ensure single instance via D-Bus
	if !acquireDBusName() {
		fmt.Println("Another instance is already running")
		activateExistingInstance()
		os.Exit(0)
	}

	// Initialize paths
	configDir = getConfigDir()

	// Run the systray
	systray.Run(onReady, onExit)
}

func onReady() {
	// Set up the tray icon
	systray.SetIcon(getIcon())
	systray.SetTitle("RemoteJuggler")
	systray.SetTooltip("Git Identity Manager")

	// Load configuration and state
	loadConfig()
	loadState()
	loadSecurityMode()

	// Update tooltip with current identity
	updateTooltip()

	// Header showing current identity
	mCurrent := systray.AddMenuItem(
		fmt.Sprintf("Current: %s", globalState.CurrentIdentity),
		"Currently active identity",
	)
	mCurrent.Disable()

	systray.AddSeparator()

	// Create menu items for each identity
	for _, id := range identities {
		item := systray.AddMenuItem(
			id.Name,
			fmt.Sprintf("%s - %s", id.Provider, id.Email),
		)

		// Mark current identity with a checkmark prefix
		if id.Name == globalState.CurrentIdentity {
			item.Check()
		}

		// Handle click in goroutine
		go handleIdentityClick(id, item, mCurrent)
	}

	systray.AddSeparator()

	// Force mode toggle
	mForce := systray.AddMenuItemCheckbox(
		"Force Global Identity",
		"Override per-repository identity settings",
		globalState.ForceMode,
	)
	go handleForceToggle(mForce)

	// Notifications toggle
	mNotify := systray.AddMenuItemCheckbox(
		"Show Notifications",
		"Show desktop notifications on identity switch",
		globalState.Tray.ShowNotifications,
	)
	go handleNotifyToggle(mNotify)

	systray.AddSeparator()

	// Security Mode submenu
	mSecurityMode := systray.AddMenuItem("Security Mode", "YubiKey PIN handling mode")
	mMaxSecurity := mSecurityMode.AddSubMenuItem("Maximum Security", "PIN required for every operation")
	mDeveloper := mSecurityMode.AddSubMenuItem("Developer Workflow", "PIN cached for session")
	mTrusted := mSecurityMode.AddSubMenuItem("Trusted Workstation", "PIN stored in secure hardware")

	// Initialize security mode checkmarks
	updateSecurityModeChecks(mMaxSecurity, mDeveloper, mTrusted)

	// Handle security mode clicks
	go handleSecurityModeClick(mMaxSecurity, mDeveloper, mTrusted, SecurityModeMaximum)
	go handleSecurityModeClick(mDeveloper, mMaxSecurity, mTrusted, SecurityModeDeveloper)
	go handleSecurityModeClick(mTrusted, mMaxSecurity, mDeveloper, SecurityModeTrusted)

	// Store YubiKey PIN menu item
	mStorePIN := systray.AddMenuItem("Store YubiKey PIN...", "Store PIN in secure storage (requires Trusted Workstation mode)")
	go handleStorePINClick(mStorePIN)

	systray.AddSeparator()

	// Refresh configuration
	mRefresh := systray.AddMenuItem("Refresh", "Reload configuration")
	go func() {
		for range mRefresh.ClickedCh {
			loadConfig()
			loadState()
			loadSecurityMode()
			updateSecurityModeChecks(mMaxSecurity, mDeveloper, mTrusted)
			updateTooltip()
		}
	}()

	systray.AddSeparator()

	// Quit
	mQuit := systray.AddMenuItem("Quit", "Exit RemoteJuggler")
	go func() {
		<-mQuit.ClickedCh
		systray.Quit()
	}()
}

func handleIdentityClick(identity Identity, item *systray.MenuItem, header *systray.MenuItem) {
	for range item.ClickedCh {
		if switchIdentity(identity.Name) {
			// Update header
			header.SetTitle(fmt.Sprintf("Current: %s", identity.Name))

			// Update checkmarks (check this item)
			item.Check()

			// Send notification
			if globalState.Tray.ShowNotifications {
				sendNotification(
					"Identity Switched",
					fmt.Sprintf("Now using %s (%s)", identity.Name, identity.Provider),
				)
			}

			updateTooltip()
		}
	}
}

func handleForceToggle(item *systray.MenuItem) {
	for range item.ClickedCh {
		globalState.ForceMode = !globalState.ForceMode
		if globalState.ForceMode {
			item.Check()
		} else {
			item.Uncheck()
		}
		saveState()
		updateTooltip()
	}
}

func handleNotifyToggle(item *systray.MenuItem) {
	for range item.ClickedCh {
		globalState.Tray.ShowNotifications = !globalState.Tray.ShowNotifications
		if globalState.Tray.ShowNotifications {
			item.Check()
		} else {
			item.Uncheck()
		}
		saveState()
	}
}

func switchIdentity(name string) bool {
	cmd := exec.Command(cliPath, "switch", name)
	output, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Printf("Switch failed: %s\n%s\n", err, output)
		sendNotification("Switch Failed", fmt.Sprintf("Could not switch to %s", name))
		return false
	}

	globalState.CurrentIdentity = name
	now := time.Now()
	globalState.LastSwitch = &now
	saveState()
	return true
}

func updateTooltip() {
	tooltip := fmt.Sprintf("RemoteJuggler: %s", globalState.CurrentIdentity)
	if globalState.ForceMode {
		tooltip += " (FORCED)"
	}
	systray.SetTooltip(tooltip)
}

func onExit() {
	// Cleanup
}

// Configuration and state management

func getConfigDir() string {
	if xdgConfig := os.Getenv("XDG_CONFIG_HOME"); xdgConfig != "" {
		return filepath.Join(xdgConfig, "remote-juggler")
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "remote-juggler")
}

func loadConfig() {
	configPath := filepath.Join(configDir, "config.json")
	data, err := os.ReadFile(configPath)
	if err != nil {
		fmt.Printf("Failed to read config: %v\n", err)
		return
	}

	var config Config
	if err := json.Unmarshal(data, &config); err != nil {
		fmt.Printf("Failed to parse config: %v\n", err)
		return
	}

	identities = make([]Identity, 0, len(config.Identities))
	for name, cfg := range config.Identities {
		identities = append(identities, Identity{
			Name:     name,
			Provider: cfg.Provider,
			Email:    cfg.Email,
			Host:     cfg.Host,
			Gpg:      cfg.Gpg,
		})
	}
}

func loadState() {
	statePath := filepath.Join(configDir, "global.json")
	data, err := os.ReadFile(statePath)
	if err != nil {
		// Initialize default state
		globalState = GlobalState{
			Version:   "1.0.0",
			ForceMode: false,
			Tray: TraySettings{
				ShowNotifications: true,
				AutoStartEnabled:  false,
				IconStyle:         "default",
			},
		}
		if len(identities) > 0 {
			globalState.CurrentIdentity = identities[0].Name
		}
		return
	}

	if err := json.Unmarshal(data, &globalState); err != nil {
		fmt.Printf("Failed to parse state: %v\n", err)
	}
}

func saveState() {
	statePath := filepath.Join(configDir, "global.json")

	data, err := json.MarshalIndent(globalState, "", "  ")
	if err != nil {
		fmt.Printf("Failed to marshal state: %v\n", err)
		return
	}

	if err := os.WriteFile(statePath, data, 0644); err != nil {
		fmt.Printf("Failed to write state: %v\n", err)
	}
}

// D-Bus singleton management

func acquireDBusName() bool {
	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		fmt.Printf("Failed to connect to session bus: %v\n", err)
		// Fall back to allowing this instance if D-Bus is unavailable
		return true
	}

	reply, err := conn.RequestName(
		"dev.tinyland.RemoteJuggler",
		dbus.NameFlagDoNotQueue,
	)
	if err != nil {
		fmt.Printf("Failed to request D-Bus name: %v\n", err)
		return true // Allow if we can't determine
	}

	return reply == dbus.RequestNameReplyPrimaryOwner
}

func activateExistingInstance() {
	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		return
	}
	defer conn.Close()

	// Send activation signal to existing instance
	obj := conn.Object("dev.tinyland.RemoteJuggler", "/dev/tinyland/RemoteJuggler")
	obj.Call("dev.tinyland.RemoteJuggler.Activate", 0)
}

// Desktop notifications via D-Bus

func sendNotification(title, body string) {
	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		return
	}
	defer conn.Close()

	obj := conn.Object(
		"org.freedesktop.Notifications",
		"/org/freedesktop/Notifications",
	)

	call := obj.Call(
		"org.freedesktop.Notifications.Notify",
		0,
		"RemoteJuggler",           // app_name
		uint32(0),                 // replaces_id
		"remote-juggler",          // app_icon
		title,                     // summary
		body,                      // body
		[]string{},                // actions
		map[string]dbus.Variant{}, // hints
		int32(5000),               // expire_timeout (ms)
	)

	if call.Err != nil {
		fmt.Printf("Notification failed: %v\n", call.Err)
	}
}

// Security Mode management

// loadSecurityMode fetches current security mode from CLI
func loadSecurityMode() {
	cmd := exec.Command(cliPath, "security-mode")
	output, err := cmd.Output()
	if err != nil {
		fmt.Printf("Failed to get security mode: %v\n", err)
		currentSecurityMode = SecurityModeDeveloper
		return
	}

	// Parse the output - look for the mode in the response
	outputStr := string(output)
	if contains(outputStr, "maximum_security") {
		currentSecurityMode = SecurityModeMaximum
	} else if contains(outputStr, "trusted_workstation") {
		currentSecurityMode = SecurityModeTrusted
	} else {
		currentSecurityMode = SecurityModeDeveloper
	}
}

// contains is a simple string contains check
func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > 0 && containsHelper(s, substr))
}

func containsHelper(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}

// setSecurityMode calls the CLI to change the security mode
func setSecurityMode(mode SecurityMode) bool {
	cmd := exec.Command(cliPath, "security-mode", string(mode))
	output, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Printf("Failed to set security mode: %s\n%s\n", err, output)
		sendNotification("Security Mode Error", fmt.Sprintf("Could not set mode to %s", mode))
		return false
	}

	currentSecurityMode = mode
	return true
}

// updateSecurityModeChecks updates checkmarks on security mode menu items
func updateSecurityModeChecks(mMax, mDev, mTrusted *systray.MenuItem) {
	// Uncheck all first
	mMax.Uncheck()
	mDev.Uncheck()
	mTrusted.Uncheck()

	// Check the current mode
	switch currentSecurityMode {
	case SecurityModeMaximum:
		mMax.Check()
	case SecurityModeDeveloper:
		mDev.Check()
	case SecurityModeTrusted:
		mTrusted.Check()
	}
}

// handleSecurityModeClick handles clicks on security mode submenu items
func handleSecurityModeClick(thisItem, other1, other2 *systray.MenuItem, mode SecurityMode) {
	for range thisItem.ClickedCh {
		if currentSecurityMode == mode {
			// Already in this mode, do nothing
			continue
		}

		if setSecurityMode(mode) {
			// Update checkmarks
			thisItem.Check()
			other1.Uncheck()
			other2.Uncheck()

			if globalState.Tray.ShowNotifications {
				var modeName string
				switch mode {
				case SecurityModeMaximum:
					modeName = "Maximum Security"
				case SecurityModeDeveloper:
					modeName = "Developer Workflow"
				case SecurityModeTrusted:
					modeName = "Trusted Workstation"
				}
				sendNotification("Security Mode Changed", fmt.Sprintf("Now using %s", modeName))
			}
		}
	}
}

// handleStorePINClick handles clicks on the Store YubiKey PIN menu item
func handleStorePINClick(item *systray.MenuItem) {
	for range item.ClickedCh {
		// Check if we're in Trusted Workstation mode
		if currentSecurityMode != SecurityModeTrusted {
			sendNotification(
				"PIN Storage Not Available",
				"Switch to Trusted Workstation mode to store YubiKey PIN",
			)
			continue
		}

		// Check if we have a current identity with GPG
		if globalState.CurrentIdentity == "" {
			sendNotification("No Identity Selected", "Select an identity first")
			continue
		}

		// For now, show a notification that PIN storage requires the GUI or CLI
		// A full implementation would show a secure PIN entry dialog
		sendNotification(
			"Store YubiKey PIN",
			fmt.Sprintf("Use CLI: remote-juggler pin store %s", globalState.CurrentIdentity),
		)
	}
}

// storePIN stores a PIN for an identity using the CLI
func storePIN(identity, pin string) bool {
	cmd := exec.Command(cliPath, "pin", "store", identity)
	stdin, err := cmd.StdinPipe()
	if err != nil {
		fmt.Printf("Failed to create stdin pipe: %v\n", err)
		return false
	}

	if err := cmd.Start(); err != nil {
		fmt.Printf("Failed to start pin store: %v\n", err)
		return false
	}

	// Write PIN to stdin
	_, err = stdin.Write([]byte(pin + "\n"))
	if err != nil {
		fmt.Printf("Failed to write PIN: %v\n", err)
		return false
	}
	stdin.Close()

	if err := cmd.Wait(); err != nil {
		fmt.Printf("Pin store failed: %v\n", err)
		return false
	}

	return true
}

// hasPINStored checks if a PIN is stored for an identity
func hasPINStored(identity string) bool {
	cmd := exec.Command(cliPath, "pin", "status", identity)
	output, err := cmd.Output()
	if err != nil {
		return false
	}

	// Check if the output indicates a PIN is stored
	outputStr := string(output)
	return contains(outputStr, "stored") || contains(outputStr, "available")
}

// Embedded icon (placeholder - 16x16 PNG)
func getIcon() []byte {
	// This would normally contain embedded icon bytes
	// For now, return nil and systray will use a default
	return nil
}
