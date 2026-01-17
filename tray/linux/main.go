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

// Identity represents a git identity configuration
type Identity struct {
	Name     string `json:"name"`
	Provider string `json:"provider"`
	Email    string `json:"email"`
	Host     string `json:"host"`
}

// Config represents the remote-juggler configuration file
type Config struct {
	Identities map[string]IdentityConfig `json:"identities"`
}

// IdentityConfig represents identity configuration from config.json
type IdentityConfig struct {
	Provider string `json:"provider"`
	Host     string `json:"host"`
	Hostname string `json:"hostname"`
	User     string `json:"user"`
	Email    string `json:"email"`
}

// GlobalState represents the singleton global state
type GlobalState struct {
	Version         string       `json:"version"`
	CurrentIdentity string       `json:"currentIdentity"`
	ForceMode       bool         `json:"forceMode"`
	LastSwitch      *time.Time   `json:"lastSwitch,omitempty"`
	Tray            TraySettings `json:"tray"`
	RecentIdentities []string    `json:"recentIdentities"`
}

// TraySettings for the tray application
type TraySettings struct {
	ShowNotifications bool   `json:"showNotifications"`
	AutoStartEnabled  bool   `json:"autoStartEnabled"`
	IconStyle         string `json:"iconStyle"`
}

var (
	identities  []Identity
	globalState GlobalState
	configDir   string
	cliPath     = "/usr/local/bin/remote-juggler"
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

	// Refresh configuration
	mRefresh := systray.AddMenuItem("Refresh", "Reload configuration")
	go func() {
		for range mRefresh.ClickedCh {
			loadConfig()
			loadState()
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

// Embedded icon (placeholder - 16x16 PNG)
func getIcon() []byte {
	// This would normally contain embedded icon bytes
	// For now, return nil and systray will use a default
	return nil
}
