mod config;
mod window;

#[cfg(test)]
mod config_properties;

use gtk4::glib;
use gtk4::prelude::*;
use libadwaita as adw;

const APP_ID: &str = "dev.tinyland.RemoteJuggler";

fn main() -> glib::ExitCode {
    // Initialize logging
    tracing_subscriber::fmt::init();

    // Parse CLI flags before GTK takes over
    let args: Vec<String> = std::env::args().collect();
    let mut initial_view = InitialView::Default;
    let mut switch_identity: Option<String> = None;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--status" => {
                initial_view = InitialView::Status;
            }
            "--switch" => {
                if i + 1 < args.len() {
                    i += 1;
                    switch_identity = Some(args[i].clone());
                    initial_view = InitialView::Switch;
                } else {
                    eprintln!("--switch requires an identity name argument");
                    return glib::ExitCode::from(1);
                }
            }
            arg if arg.starts_with("--switch=") => {
                let name = arg.strip_prefix("--switch=").unwrap_or("");
                if name.is_empty() {
                    eprintln!("--switch requires an identity name");
                    return glib::ExitCode::from(1);
                }
                switch_identity = Some(name.to_string());
                initial_view = InitialView::Switch;
            }
            "--help" | "-h" => {
                println!("Usage: remote-juggler-gui [OPTIONS]");
                println!();
                println!("Options:");
                println!("  --status           Open to status view");
                println!("  --switch <NAME>    Switch identity and open GUI");
                println!("  --help, -h         Show this help");
                return glib::ExitCode::SUCCESS;
            }
            // Ignore GTK/GLib args (they start with --)
            _ => {}
        }
        i += 1;
    }

    // If --switch was given, perform the switch before launching the GUI
    if let Some(ref identity) = switch_identity {
        tracing::info!("Pre-launch switch to identity: {}", identity);
        let output = std::process::Command::new("remote-juggler")
            .args(["switch", identity])
            .output();
        match output {
            Ok(o) if o.status.success() => {
                tracing::info!("Switched to {}", identity);
            }
            Ok(o) => {
                let stderr = String::from_utf8_lossy(&o.stderr);
                tracing::error!("Switch failed: {}", stderr);
            }
            Err(e) => {
                tracing::error!("Failed to run remote-juggler: {}", e);
            }
        }
    }

    // Create the application
    let app = adw::Application::builder().application_id(APP_ID).build();

    let view = initial_view;
    app.connect_activate(move |app| {
        build_ui(app, &view);
    });

    // Pass only non-RemoteJuggler args to GTK
    let gtk_args: Vec<String> = args
        .iter()
        .filter(|a| {
            !a.starts_with("--status")
                && !a.starts_with("--switch")
                && *a != "--help"
                && *a != "-h"
        })
        .cloned()
        .collect();

    app.run_with_args(&gtk_args)
}

#[derive(Debug, Clone, Copy)]
enum InitialView {
    Default,
    Status,
    Switch,
}

fn build_ui(app: &adw::Application, _view: &InitialView) {
    let window = window::RemoteJugglerWindow::new(app);
    window.present();
}
