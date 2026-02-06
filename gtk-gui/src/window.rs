//! Main application window
//!
//! Implements the Libadwaita-styled main window with identity management UI.
//!
//! The UI groups identities into profiles, with SSH key variants shown as a
//! secondary selection within each profile.

use gtk4::prelude::*;
use gtk4::{gdk, gio, glib};
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
        content_box: RefCell<Option<gtk4::Box>>,
        scrolled: RefCell<Option<gtk4::ScrolledWindow>>,
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

            // Reload config when window gains focus
            let imp = self.downgrade();
            window.connect_is_active_notify(move |_win| {
                if let Some(imp) = imp.upgrade() {
                    imp.reload_config_and_ui();
                }
            });
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

        fn reload_config_and_ui(&self) {
            self.load_config();
            // Rebuild the content inside the scrolled window
            if let Some(ref scrolled) = *self.scrolled.borrow() {
                let main_box = self.build_main_content();
                scrolled.set_child(Some(&main_box));
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

            // Build main content
            let main_box = self.build_main_content();
            scrolled.set_child(Some(&main_box));

            *self.scrolled.borrow_mut() = Some(scrolled.clone());

            vbox.append(&scrolled);
            window.set_content(Some(&vbox));
        }

        fn build_main_content(&self) -> gtk4::Box {
            // Create main content box
            let main_box = gtk4::Box::new(gtk4::Orientation::Vertical, 12);
            main_box.set_margin_top(24);
            main_box.set_margin_bottom(24);
            main_box.set_margin_start(24);
            main_box.set_margin_end(24);

            let config = self.config.borrow();
            if let Some(config) = config.as_ref() {
                let profiles = config.profiles();

                // Status label for feedback
                let status_label = gtk4::Label::new(None);
                status_label.set_wrap(true);
                status_label.set_xalign(0.0);
                status_label.add_css_class("dim-label");
                status_label.set_visible(false);

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

                // Wire profile ComboRow handler (2a)
                {
                    let profiles_for_handler = profiles.clone();
                    let status_clone = status_label.clone();
                    let imp_weak = self.downgrade();
                    profile_row.connect_selected_notify(move |row| {
                        let selected = row.selected() as usize;
                        if selected >= profiles_for_handler.len() {
                            return;
                        }
                        let profile = &profiles_for_handler[selected];
                        // Use default variant (prefer FIDO2)
                        let identity_name = profile
                            .default_variant()
                            .map(|v| v.identity_name.clone())
                            .unwrap_or_else(|| profile.name.clone());

                        let status = status_clone.clone();
                        let name = identity_name.clone();
                        let imp = imp_weak.clone();
                        status.set_text(&format!("Switching to {}...", &name));
                        status.set_visible(true);
                        status.remove_css_class("error");
                        status.remove_css_class("success");

                        glib::spawn_future_local(async move {
                            let result = run_cli_async("switch", &name).await;
                            match result {
                                Ok(msg) => {
                                    status.set_text(&format!("Switched to {}", &name));
                                    status.add_css_class("success");
                                    tracing::info!("Switched identity: {} - {}", &name, msg);
                                }
                                Err(e) => {
                                    status.set_text(&format!("Failed: {}", e));
                                    status.add_css_class("error");
                                    tracing::error!("Switch failed: {}", e);
                                }
                            }
                            // Reload config after switch
                            if let Some(imp) = imp.upgrade() {
                                imp.load_config();
                            }
                        });
                    });
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

                        // Wire variant ComboRow handler (2b)
                        {
                            let variants_for_handler: Vec<String> = profile
                                .variants
                                .iter()
                                .map(|v| v.identity_name.clone())
                                .collect();
                            let status_clone = status_label.clone();
                            let imp_weak = self.downgrade();
                            variant_row.connect_selected_notify(move |row| {
                                let selected = row.selected() as usize;
                                if selected >= variants_for_handler.len() {
                                    return;
                                }
                                let identity_name = &variants_for_handler[selected];
                                let status = status_clone.clone();
                                let name = identity_name.clone();
                                let imp = imp_weak.clone();
                                status.set_text(&format!("Switching to variant {}...", &name));
                                status.set_visible(true);
                                status.remove_css_class("error");
                                status.remove_css_class("success");

                                glib::spawn_future_local(async move {
                                    let result = run_cli_async("switch", &name).await;
                                    match result {
                                        Ok(_) => {
                                            status.set_text(&format!(
                                                "Switched to variant {}",
                                                &name
                                            ));
                                            status.add_css_class("success");
                                        }
                                        Err(e) => {
                                            status.set_text(&format!("Failed: {}", e));
                                            status.add_css_class("error");
                                        }
                                    }
                                    if let Some(imp) = imp.upgrade() {
                                        imp.load_config();
                                    }
                                });
                            });
                        }

                        profile_group.add(&variant_row);
                    }
                }

                main_box.append(&profile_group);

                // Status feedback label
                main_box.append(&status_label);

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

                // Wire security mode change handler (2c)
                {
                    let pin_group_clone = pin_group.clone();
                    let status_clone = status_label.clone();
                    security_mode_row.connect_selected_notify(move |row| {
                        let selected = row.selected();
                        let mode = SecurityMode::from_index(selected);
                        let show = mode == SecurityMode::TrustedWorkstation;
                        pin_group_clone.set_visible(show);

                        // Call CLI to persist the security mode change
                        let mode_str = match mode {
                            SecurityMode::MaximumSecurity => "maximum_security",
                            SecurityMode::DeveloperWorkflow => "developer_workflow",
                            SecurityMode::TrustedWorkstation => "trusted_workstation",
                        };
                        let status = status_clone.clone();
                        let mode_display = mode.display_name().to_string();
                        let mode_arg = mode_str.to_string();
                        status.set_visible(true);
                        status.remove_css_class("error");
                        status.remove_css_class("success");
                        status.set_text(&format!("Setting security mode to {}...", &mode_display));

                        glib::spawn_future_local(async move {
                            let result =
                                run_cli_async("security-mode", &mode_arg).await;
                            match result {
                                Ok(_) => {
                                    status.set_text(&format!(
                                        "Security mode: {}",
                                        &mode_display
                                    ));
                                    status.add_css_class("success");
                                    tracing::info!("Security mode changed to: {}", &mode_display);
                                }
                                Err(e) => {
                                    status.set_text(&format!("Failed: {}", e));
                                    status.add_css_class("error");
                                    tracing::error!("Security mode change failed: {}", e);
                                }
                            }
                        });
                    });
                }

                // ============================================================
                // KeePassXC Key Store Group
                // ============================================================
                let keys_group = adw::PreferencesGroup::new();
                keys_group.set_title("Key Store (KeePassXC)");
                keys_group.set_description(Some("Credential authority for secrets management"));

                // Key store status row
                let keys_status_row = adw::ActionRow::new();
                keys_status_row.set_title("Key Store");
                let keys_status_label = gtk4::Label::new(Some("Checking..."));
                keys_status_label.add_css_class("dim-label");
                keys_status_row.add_suffix(&keys_status_label);
                keys_group.add(&keys_status_row);

                // Check key store status async
                {
                    let label = keys_status_label.clone();
                    glib::spawn_future_local(async move {
                        let result = run_cli_async("keys", "status").await;
                        match result {
                            Ok(output) => {
                                if output.contains("Auto-Unlock:   ready") || output.contains("Auto-Unlock: ready") {
                                    label.set_text("Unlocked");
                                    label.remove_css_class("dim-label");
                                    label.add_css_class("success");
                                } else if output.contains("Exists:      yes") || output.contains("Exists: yes") {
                                    label.set_text("Locked");
                                    label.remove_css_class("dim-label");
                                    label.add_css_class("warning");
                                } else {
                                    label.set_text("Not initialized");
                                }
                            }
                            Err(_) => {
                                label.set_text("Unavailable");
                            }
                        }
                    });
                }

                // Initialize key store button row
                let init_row = adw::ActionRow::new();
                init_row.set_title("Initialize Key Store");
                init_row.set_subtitle("Create a new kdbx credential database");
                let init_button = gtk4::Button::with_label("Initialize");
                init_button.set_valign(gtk4::Align::Center);
                init_button.add_css_class("suggested-action");
                init_row.add_suffix(&init_button);
                init_row.set_activatable_widget(Some(&init_button));
                keys_group.add(&init_row);

                // Wire init button
                {
                    let status_clone = status_label.clone();
                    let keys_label = keys_status_label.clone();
                    init_button.connect_clicked(move |button| {
                        button.set_sensitive(false);
                        let status = status_clone.clone();
                        let klabel = keys_label.clone();
                        let btn = button.clone();
                        status.set_text("Initializing key store...");
                        status.set_visible(true);
                        status.remove_css_class("error");
                        status.remove_css_class("success");

                        glib::spawn_future_local(async move {
                            let result = run_cli_async("keys", "init").await;
                            match result {
                                Ok(_) => {
                                    status.set_text("Key store initialized");
                                    status.add_css_class("success");
                                    klabel.set_text("Ready");
                                    klabel.remove_css_class("dim-label");
                                    klabel.add_css_class("success");
                                }
                                Err(e) => {
                                    status.set_text(&format!("Init failed: {}", e));
                                    status.add_css_class("error");
                                }
                            }
                            btn.set_sensitive(true);
                        });
                    });
                }

                // Search entry row
                let search_row = adw::ActionRow::new();
                search_row.set_title("Search Keys");
                search_row.set_subtitle("Fuzzy search across all stored credentials");
                let search_entry = gtk4::Entry::new();
                search_entry.set_placeholder_text(Some("Search..."));
                search_entry.set_hexpand(true);
                search_entry.set_valign(gtk4::Align::Center);
                search_row.add_suffix(&search_entry);
                search_row.set_activatable_widget(Some(&search_entry));
                keys_group.add(&search_row);

                // Search results label (hidden initially)
                let search_results_label = gtk4::Label::new(None);
                search_results_label.set_wrap(true);
                search_results_label.set_xalign(0.0);
                search_results_label.add_css_class("dim-label");
                search_results_label.add_css_class("monospace");
                search_results_label.set_visible(false);

                // Wire search entry activate
                {
                    let results_label = search_results_label.clone();
                    search_entry.connect_activate(move |entry| {
                        let query = entry.text().to_string();
                        if query.is_empty() {
                            return;
                        }
                        let label = results_label.clone();
                        label.set_text("Searching...");
                        label.set_visible(true);

                        glib::spawn_future_local(async move {
                            let result = run_cli_args_async(vec!["keys".into(), "search".into(), query]).await;
                            match result {
                                Ok(output) => {
                                    label.set_text(&output);
                                }
                                Err(e) => {
                                    label.set_text(&format!("Search error: {}", e));
                                }
                            }
                        });
                    });
                }

                // Ingest .env row
                let ingest_row = adw::ActionRow::new();
                ingest_row.set_title("Ingest .env File");
                ingest_row.set_subtitle("Import environment variables into key store");
                let ingest_button = gtk4::Button::with_label("Choose File");
                ingest_button.set_valign(gtk4::Align::Center);
                ingest_row.add_suffix(&ingest_button);
                ingest_row.set_activatable_widget(Some(&ingest_button));
                keys_group.add(&ingest_row);

                // Wire ingest button to open file chooser
                {
                    let status_clone = status_label.clone();
                    let window_ref = self.obj().clone();
                    ingest_button.connect_clicked(move |_button| {
                        let dialog = gtk4::FileDialog::new();
                        dialog.set_title("Select .env file");
                        let filter = gtk4::FileFilter::new();
                        filter.add_pattern("*.env");
                        filter.add_pattern(".env*");
                        filter.set_name(Some("Environment files"));
                        let filters = gio::ListStore::new::<gtk4::FileFilter>();
                        filters.append(&filter);
                        dialog.set_filters(Some(&filters));

                        let status = status_clone.clone();
                        dialog.open(Some(&window_ref), gio::Cancellable::NONE, move |result| {
                            if let Ok(file) = result {
                                if let Some(path) = file.path() {
                                    let path_str = path.to_string_lossy().to_string();
                                    let st = status.clone();
                                    st.set_text(&format!("Ingesting {}...", &path_str));
                                    st.set_visible(true);
                                    st.remove_css_class("error");
                                    st.remove_css_class("success");

                                    glib::spawn_future_local(async move {
                                        let result = run_cli_args_async(vec!["keys".into(), "ingest".into(), path_str.clone()]).await;
                                        match result {
                                            Ok(output) => {
                                                st.set_text(&format!("Ingested: {}", output.lines().last().unwrap_or("done")));
                                                st.add_css_class("success");
                                            }
                                            Err(e) => {
                                                st.set_text(&format!("Ingest failed: {}", e));
                                                st.add_css_class("error");
                                            }
                                        }
                                    });
                                }
                            }
                        });
                    });
                }

                // Get/Copy credential row
                let get_row = adw::ActionRow::new();
                get_row.set_title("Get Credential");
                get_row.set_subtitle("Retrieve and copy a secret to clipboard");
                let get_entry = gtk4::Entry::new();
                get_entry.set_placeholder_text(Some("Entry path..."));
                get_entry.set_hexpand(true);
                get_entry.set_valign(gtk4::Align::Center);
                let copy_button = gtk4::Button::with_label("Copy");
                copy_button.set_valign(gtk4::Align::Center);
                get_row.add_suffix(&get_entry);
                get_row.add_suffix(&copy_button);
                keys_group.add(&get_row);

                // Wire copy button
                {
                    let entry_clone = get_entry.clone();
                    let status_clone = status_label.clone();
                    copy_button.connect_clicked(move |_| {
                        let path = entry_clone.text().to_string();
                        if path.is_empty() {
                            return;
                        }
                        let status = status_clone.clone();
                        glib::spawn_future_local(async move {
                            let result = run_cli_args_async(vec!["keys".into(), "get".into(), path]).await;
                            match result {
                                Ok(value) => {
                                    let display = gdk::Display::default().unwrap();
                                    let clipboard = display.clipboard();
                                    clipboard.set_text(&value.trim());
                                    status.set_text("Copied to clipboard");
                                    status.set_visible(true);
                                    status.remove_css_class("error");
                                    status.add_css_class("success");
                                }
                                Err(e) => {
                                    status.set_text(&format!("Get failed: {}", e));
                                    status.set_visible(true);
                                    status.remove_css_class("success");
                                    status.add_css_class("error");
                                }
                            }
                        });
                    });
                }

                // Store credential row
                let store_row = adw::ActionRow::new();
                store_row.set_title("Store Credential");
                store_row.set_subtitle("Store a new secret in the key store");
                let store_path_entry = gtk4::Entry::new();
                store_path_entry.set_placeholder_text(Some("Path (e.g. RemoteJuggler/API/KEY)"));
                store_path_entry.set_hexpand(true);
                store_path_entry.set_valign(gtk4::Align::Center);
                let store_value_entry = gtk4::PasswordEntry::new();
                store_value_entry.set_placeholder_text(Some("Secret value"));
                store_value_entry.set_hexpand(true);
                store_value_entry.set_valign(gtk4::Align::Center);
                store_value_entry.set_show_peek_icon(true);
                let store_cred_button = gtk4::Button::with_label("Store");
                store_cred_button.set_valign(gtk4::Align::Center);
                store_cred_button.add_css_class("suggested-action");
                store_row.add_suffix(&store_path_entry);
                store_row.add_suffix(&store_value_entry);
                store_row.add_suffix(&store_cred_button);
                keys_group.add(&store_row);

                // Wire store credential button
                {
                    let path_clone = store_path_entry.clone();
                    let value_clone = store_value_entry.clone();
                    let status_clone = status_label.clone();
                    store_cred_button.connect_clicked(move |button| {
                        let path = path_clone.text().to_string();
                        let value = value_clone.text().to_string();
                        if path.is_empty() || value.is_empty() {
                            return;
                        }
                        button.set_sensitive(false);
                        let btn = button.clone();
                        let status = status_clone.clone();
                        let pc = path_clone.clone();
                        let vc = value_clone.clone();
                        glib::spawn_future_local(async move {
                            let result = run_cli_args_async(vec![
                                "keys".into(), "store".into(), path.clone(),
                                "--value".into(), value,
                            ]).await;
                            match result {
                                Ok(_) => {
                                    status.set_text(&format!("Stored: {}", path));
                                    status.set_visible(true);
                                    status.remove_css_class("error");
                                    status.add_css_class("success");
                                    pc.set_text("");
                                    vc.set_text("");
                                }
                                Err(e) => {
                                    status.set_text(&format!("Store failed: {}", e));
                                    status.set_visible(true);
                                    status.remove_css_class("success");
                                    status.add_css_class("error");
                                }
                            }
                            btn.set_sensitive(true);
                        });
                    });
                }

                // Delete credential row
                let delete_row = adw::ActionRow::new();
                delete_row.set_title("Delete Credential");
                delete_row.set_subtitle("Remove an entry from the key store");
                let delete_entry = gtk4::Entry::new();
                delete_entry.set_placeholder_text(Some("Entry path..."));
                delete_entry.set_hexpand(true);
                delete_entry.set_valign(gtk4::Align::Center);
                let delete_button = gtk4::Button::with_label("Delete");
                delete_button.set_valign(gtk4::Align::Center);
                delete_button.add_css_class("destructive-action");
                delete_row.add_suffix(&delete_entry);
                delete_row.add_suffix(&delete_button);
                keys_group.add(&delete_row);

                // Wire delete button
                {
                    let entry_clone = delete_entry.clone();
                    let status_clone = status_label.clone();
                    delete_button.connect_clicked(move |_| {
                        let path = entry_clone.text().to_string();
                        if path.is_empty() {
                            return;
                        }
                        let status = status_clone.clone();
                        let ec = entry_clone.clone();
                        glib::spawn_future_local(async move {
                            let result = run_cli_args_async(vec![
                                "keys".into(), "delete".into(), path.clone(),
                            ]).await;
                            match result {
                                Ok(_) => {
                                    status.set_text(&format!("Deleted: {}", path));
                                    status.set_visible(true);
                                    status.remove_css_class("error");
                                    status.add_css_class("success");
                                    ec.set_text("");
                                }
                                Err(e) => {
                                    status.set_text(&format!("Delete failed: {}", e));
                                    status.set_visible(true);
                                    status.remove_css_class("success");
                                    status.add_css_class("error");
                                }
                            }
                        });
                    });
                }

                // Discover credentials button row
                let discover_row = adw::ActionRow::new();
                discover_row.set_title("Discover Credentials");
                discover_row.set_subtitle("Auto-discover env vars and SSH keys");
                let discover_button = gtk4::Button::with_label("Discover");
                discover_button.set_valign(gtk4::Align::Center);
                discover_row.add_suffix(&discover_button);
                discover_row.set_activatable_widget(Some(&discover_button));
                keys_group.add(&discover_row);

                // Wire discover button
                {
                    let status_clone = status_label.clone();
                    discover_button.connect_clicked(move |button| {
                        button.set_sensitive(false);
                        let btn = button.clone();
                        let status = status_clone.clone();
                        status.set_text("Discovering credentials...");
                        status.set_visible(true);
                        status.remove_css_class("error");
                        status.remove_css_class("success");

                        glib::spawn_future_local(async move {
                            let result = run_cli_args_async(vec![
                                "keys".into(), "discover".into(), "--types".into(), "all".into(),
                            ]).await;
                            match result {
                                Ok(output) => {
                                    status.set_text(&output.lines().last().unwrap_or("Done"));
                                    status.add_css_class("success");
                                }
                                Err(e) => {
                                    status.set_text(&format!("Discovery failed: {}", e));
                                    status.add_css_class("error");
                                }
                            }
                            btn.set_sensitive(true);
                        });
                    });
                }

                main_box.append(&keys_group);
                main_box.append(&search_results_label);

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

            main_box
        }
    }

    /// Run a remote-juggler CLI command asynchronously with two args
    async fn run_cli_async(command: &str, arg: &str) -> Result<String, String> {
        run_cli_args_async(vec![command.to_string(), arg.to_string()]).await
    }

    /// Run a remote-juggler CLI command asynchronously with arbitrary args
    async fn run_cli_args_async(args: Vec<String>) -> Result<String, String> {
        let result = gio::spawn_blocking(move || {
            let output = Command::new("remote-juggler")
                .args(&args)
                .output();

            match output {
                Ok(output) => {
                    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
                    if output.status.success() {
                        Ok(stdout)
                    } else {
                        let stderr = String::from_utf8_lossy(&output.stderr);
                        Err(format!("{}", stderr))
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
