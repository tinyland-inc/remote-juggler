mod config;
mod window;

#[cfg(test)]
mod config_properties;

use gtk4::prelude::*;
use gtk4::glib;
use libadwaita as adw;

const APP_ID: &str = "dev.tinyland.RemoteJuggler";

fn main() -> glib::ExitCode {
    // Initialize logging
    tracing_subscriber::fmt::init();

    // Create the application
    let app = adw::Application::builder()
        .application_id(APP_ID)
        .build();

    app.connect_activate(build_ui);

    app.run()
}

fn build_ui(app: &adw::Application) {
    let window = window::RemoteJugglerWindow::new(app);
    window.present();
}
