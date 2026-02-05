//! Main application window
//!
//! Implements the Libadwaita-styled main window with identity management UI.
//!
//! The UI groups identities into profiles, with SSH key variants shown as a
//! secondary selection within each profile.

use gtk4::prelude::*;
use gtk4::{gio, glib};
use libadwaita as adw;
use libadwaita::prelude::*;

use crate::config::{Config, SecurityMode, SshKeyType};

glib::wrapper! {
    pub struct RemoteJugglerWindow(ObjectSubclass<imp::RemoteJugglerWindow>)
        @extends adw::ApplicationWindow, gtk4::ApplicationWindow, gtk4::Window, gtk4::Widget,
        @implements gio::ActionGroup, gio::ActionMap;
}

impl RemoteJugglerWindow {
    pub fn new(app: &adw::Application) -> Self {
        glib::Object::builder().property("application", app).build()
    }
}

mod imp {
    use super::*;
    use gtk4::subclass::prelude::*;
    use libadwaita::subclass::prelude::*;
    use std::cell::RefCell;
    use std::process::Command;

    #[derive(Default)]
    pub struct RemoteJugglerWindow {
        config: RefCell<Option<Config>>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for RemoteJugglerWindow {
        const NAME: &'static str = "RemoteJugglerWindow";
        type Type = super::RemoteJugglerWindow;
        type ParentType = adw::ApplicationWindow;
    }

    impl ObjectImpl for RemoteJugglerWindow {
        fn constructed(&self) {
            self.parent_constructed();

            let window = self.obj();
            window.set_title(Some("RemoteJuggler"));
            window.set_default_size(400, 500);

            // Load config
            self.load_config();

            // Build UI
            self.build_ui();
        }
    }

    impl WidgetImpl for RemoteJugglerWindow {}
    impl WindowImpl for RemoteJugglerWindow {}
    impl ApplicationWindowImpl for RemoteJugglerWindow {}
    impl AdwApplicationWindowImpl for RemoteJugglerWindow {}

    impl RemoteJugglerWindow {
        fn load_config(&self) {
            match Config::load() {
                Ok(config) => {
                    *self.config.borrow_mut() = Some(config);
                }
                Err(e) => {
                    tracing::error!("Failed to load config: {}", e);
                }
            }
        }

        fn build_ui(&self) {
            let window = self.obj();

            // Create header bar
            let header = adw::HeaderBar::new();

            // Create main vertical box
            let vbox = gtk4::Box::new(gtk4::Orientation::Vertical, 0);
            vbox.append(&header);

            // Create scrolled window for content
            let scrolled = gtk4::ScrolledWindow::new();
            scrolled.set_vexpand(true);

            // Create main content box
            let main_box = gtk4::Box::new(gtk4::Orientation::Vertical, 12);
            main_box.set_margin_top(24);
            main_box.set_margin_bottom(24);
            main_box.set_margin_start(24);
            main_box.set_margin_end(24);

            // Add status page when no identity is selected
            let config = self.config.borrow();
            if let Some(config) = config.as_ref() {
                let profiles = config.profiles();

                // Create profile selector group
                let profile_group = adw::PreferencesGroup::new();
                profile_group.set_title("Git Identity");
                profile_group.set_description(Some("Select your active git identity profile"));

                // Create combo row for profile selection
                let profile_row = adw::ComboRow::new();
                profile_row.set_title("Active Profile");

                let profile_names: Vec<String> =
                    profiles.iter().map(|p| p.display_name()).collect();
                let profile_names_strs: Vec<&str> =
                    profile_names.iter().map(|s| s.as_str()).collect();
                let profile_list = gtk4::StringList::new(&profile_names_strs);
                profile_row.set_model(Some(&profile_list));

                // Set current selection based on current identity's profile
                if let Some(current_profile) = config.current_profile() {
                    if let Some(pos) = profiles.iter().position(|p| p.name == current_profile.name)
                    {
                        profile_row.set_selected(pos as u32);
                    }
                }

                profile_group.add(&profile_row);

                // Add SSH key variant selector if current profile has multiple variants
                let current_profile = config.current_profile();
                let current_variant = config.current_variant();

                if let Some(ref profile) = current_profile {
                    if profile.has_multiple_variants() {
                        let variant_row = adw::ComboRow::new();
                        variant_row.set_title("SSH Key Type");
                        variant_row
                            .set_subtitle("Choose between regular SSH or hardware security key");

                        let variant_names: Vec<&str> = profile
                            .variants
                            .iter()
                            .map(|v| v.key_type.display_name())
                            .collect();
                        let variant_list = gtk4::StringList::new(&variant_names);
                        variant_row.set_model(Some(&variant_list));

                        // Set current variant selection
                        if let Some(ref current_var) = current_variant {
                            if let Some(pos) = profile
                                .variants
                                .iter()
                                .position(|v| v.identity_name == current_var.identity_name)
                            {
                                variant_row.set_selected(pos as u32);
                            }
                        }

                        profile_group.add(&variant_row);
                    }
                }

                main_box.append(&profile_group);

                // Add current profile details if available
                if let Some(ref profile) = current_profile {
                    let details_group = adw::PreferencesGroup::new();
                    details_group.set_title("Current Profile Details");

                    // Provider row
                    let provider_row = adw::ActionRow::new();
                    provider_row.set_title("Provider");
                    provider_row.set_subtitle(&profile.provider);
                    details_group.add(&provider_row);

                    // User row
                    let user_row = adw::ActionRow::new();
                    user_row.set_title("Username");
                    user_row.set_subtitle(&profile.user);
                    details_group.add(&user_row);

                    // Email row
                    let email_row = adw::ActionRow::new();
                    email_row.set_title("Email");
                    email_row.set_subtitle(&profile.email);
                    details_group.add(&email_row);

                    // SSH Key variant info
                    if let Some(ref variant) = current_variant {
                        let ssh_row = adw::ActionRow::new();
                        ssh_row.set_title("SSH Key");
                        let ssh_info = if variant.identity.ssh_key_path.is_empty() {
                            format!("{} (default)", variant.key_type.display_name())
                        } else {
                            format!(
                                "{} ({})",
                                variant.key_type.display_name(),
                                variant
                                    .identity
                                    .ssh_key_path
                                    .rsplit('/')
                                    .next()
                                    .unwrap_or(&variant.identity.ssh_key_path)
                            )
                        };
                        ssh_row.set_subtitle(&ssh_info);

                        // Add badge for security key
                        if variant.key_type == SshKeyType::Fido2 {
                            let badge = gtk4::Label::new(Some("HW"));
                            badge.add_css_class("heading");
                            badge.add_css_class("accent");
                            ssh_row.add_suffix(&badge);
                        }

                        details_group.add(&ssh_row);
                    }

                    // GPG row
                    let gpg_row = adw::ActionRow::new();
                    gpg_row.set_title("GPG Signing");
                    if profile.has_gpg_signing() {
                        gpg_row.set_subtitle(&format!("Enabled ({})", &profile.gpg.key_id));
                    } else {
                        gpg_row.set_subtitle("Disabled");
                    }
                    details_group.add(&gpg_row);

                    // Available variants summary
                    let variants_row = adw::ActionRow::new();
                    variants_row.set_title("Available Key Types");
                    let variant_summary: Vec<&str> = profile
                        .variants
                        .iter()
                        .map(|v| v.key_type.short_name())
                        .collect();
                    variants_row.set_subtitle(&variant_summary.join(", "));
                    details_group.add(&variants_row);

                    main_box.append(&details_group);
                }

                // Add GPG status group
                let gpg_group = adw::PreferencesGroup::new();
                gpg_group.set_title("GPG Status");

                let gpg_status_row = adw::ActionRow::new();
                gpg_status_row.set_title("Signing Ready");
                gpg_status_row.set_subtitle("Checking...");

                // Add a switch for GPG signing toggle
                let gpg_switch = gtk4::Switch::new();
                gpg_switch.set_valign(gtk4::Align::Center);
                gpg_switch.set_active(config.settings.gpg_sign);
                gpg_status_row.add_suffix(&gpg_switch);

                gpg_group.add(&gpg_status_row);
                main_box.append(&gpg_group);

                // Add Security Mode group
                let security_group = adw::PreferencesGroup::new();
                security_group.set_title("Security");
                security_group.set_description(Some("YubiKey PIN handling mode"));

                // Security Mode combo row
                let security_mode_row = adw::ComboRow::new();
                security_mode_row.set_title("Security Mode");
                security_mode_row.set_subtitle("How YubiKey PIN is handled during signing");

                // Create string list for security modes
                let mode_names: Vec<&str> = SecurityMode::all()
                    .iter()
                    .map(|m| m.display_name())
                    .collect();
                let mode_list = gtk4::StringList::new(&mode_names);
                security_mode_row.set_model(Some(&mode_list));

                // Get current security mode from the current profile's GPG config
                let current_security_mode = current_profile
                    .as_ref()
                    .map(|p| p.gpg.security_mode.clone())
                    .unwrap_or_default();
                security_mode_row.set_selected(current_security_mode.index());

                security_group.add(&security_mode_row);

                // YubiKey PIN Storage group (only visible in TrustedWorkstation mode)
                let pin_group = adw::PreferencesGroup::new();
                pin_group.set_title("YubiKey PIN Storage");
                pin_group.set_description(Some("Store PIN in hardware security module"));

                // PIN entry row using gtk4::PasswordEntry inside an ActionRow
                let pin_entry = gtk4::PasswordEntry::new();
                pin_entry.set_show_peek_icon(true);
                pin_entry.set_hexpand(true);
                pin_entry.set_valign(gtk4::Align::Center);

                let pin_entry_row = adw::ActionRow::new();
                pin_entry_row.set_title("Enter PIN");
                pin_entry_row.add_suffix(&pin_entry);
                pin_entry_row.set_activatable_widget(Some(&pin_entry));
                pin_group.add(&pin_entry_row);

                // Store PIN button and status row
                let store_pin_row = adw::ActionRow::new();
                store_pin_row.set_title("Store PIN in HSM");

                // Status indicator
                let pin_status_label = gtk4::Label::new(Some("Not stored"));
                pin_status_label.add_css_class("dim-label");
                store_pin_row.add_suffix(&pin_status_label);

                // Store button
                let store_button = gtk4::Button::with_label("Store PIN");
                store_button.set_valign(gtk4::Align::Center);
                store_button.add_css_class("suggested-action");
                store_pin_row.add_suffix(&store_button);
                store_pin_row.set_activatable_widget(Some(&store_button));

                pin_group.add(&store_pin_row);

                // Set initial visibility based on security mode
                let show_pin_storage = current_security_mode == SecurityMode::TrustedWorkstation;
                pin_group.set_visible(show_pin_storage);

                main_box.append(&security_group);
                main_box.append(&pin_group);

                // Connect security mode change handler
                let pin_group_clone = pin_group.clone();
                security_mode_row.connect_selected_notify(move |row| {
                    let selected = row.selected();
                    let mode = SecurityMode::from_index(selected);
                    let show = mode == SecurityMode::TrustedWorkstation;
                    pin_group_clone.set_visible(show);

                    // Log the change (actual config save would be implemented here)
                    tracing::info!("Security mode changed to: {}", mode.display_name());
                });

                // Connect store PIN button handler
                let pin_entry_clone = pin_entry.clone();
                let pin_status_clone = pin_status_label.clone();
                let current_identity = config.state.current_identity.clone();
                store_button.connect_clicked(move |button| {
                    let pin = pin_entry_clone.text();
                    if pin.is_empty() {
                        tracing::warn!("Cannot store empty PIN");
                        return;
                    }

                    let identity = current_identity.clone();
                    if identity.is_empty() {
                        tracing::warn!("No identity selected");
                        return;
                    }

                    // Disable button during operation
                    button.set_sensitive(false);
                    pin_status_clone.set_text("Storing...");

                    // Spawn async task to call CLI
                    let button_clone = button.clone();
                    let status_clone = pin_status_clone.clone();
                    let entry_clone = pin_entry_clone.clone();
                    let pin = pin.to_string();
                    glib::spawn_future_local(async move {
                        let result = store_pin_async(&identity, &pin).await;

                        // Update UI based on result
                        match result {
                            Ok(()) => {
                                status_clone.set_text("Stored");
                                status_clone.remove_css_class("dim-label");
                                status_clone.add_css_class("success");
                                entry_clone.set_text("");
                                tracing::info!("PIN stored successfully for {}", identity);
                            }
                            Err(e) => {
                                status_clone.set_text("Failed");
                                status_clone.remove_css_class("dim-label");
                                status_clone.add_css_class("error");
                                tracing::error!("Failed to store PIN: {}", e);
                            }
                        }
                        button_clone.set_sensitive(true);
                    });
                });
            } else {
                // Show error status page
                let status_page = adw::StatusPage::new();
                status_page.set_icon_name(Some("dialog-error-symbolic"));
                status_page.set_title("Configuration Not Found");
                status_page.set_description(Some(
                    "Could not load RemoteJuggler configuration.\n\
                     Please ensure ~/.config/remote-juggler/config.json exists.",
                ));
                main_box.append(&status_page);
            }

            scrolled.set_child(Some(&main_box));
            vbox.append(&scrolled);
            window.set_content(Some(&vbox));
        }
    }

    /// Store a PIN for an identity using the remote-juggler CLI
    async fn store_pin_async(identity: &str, pin: &str) -> Result<(), String> {
        // Run the command in a blocking thread to avoid blocking the UI
        let identity = identity.to_string();
        let pin = pin.to_string();

        let result = gio::spawn_blocking(move || {
            let output = Command::new("remote-juggler")
                .args(["pin", "store", &identity])
                .env("REMOTE_JUGGLER_PIN", &pin)
                .output();

            match output {
                Ok(output) => {
                    if output.status.success() {
                        Ok(())
                    } else {
                        let stderr = String::from_utf8_lossy(&output.stderr);
                        Err(format!("Command failed: {}", stderr))
                    }
                }
                Err(e) => Err(format!("Failed to execute command: {}", e)),
            }
        })
        .await;

        match result {
            Ok(inner_result) => inner_result,
            Err(e) => Err(format!("Task join error: {:?}", e)),
        }
    }
}
