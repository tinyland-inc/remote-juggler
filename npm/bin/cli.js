#!/usr/bin/env node
/**
 * RemoteJuggler CLI wrapper
 *
 * Spawns the platform-native binary with all arguments and stdio inherited,
 * forwarding the exit code. This enables the `npx @tummycrypt/remote-juggler`
 * and `npx @tummycrypt/remote-juggler --mode=mcp` usage patterns.
 */

const { spawn } = require("child_process");
const { join } = require("path");
const { existsSync } = require("fs");

const BINARY_PATH = join(__dirname, "remote-juggler-binary");

if (!existsSync(BINARY_PATH)) {
  console.error("RemoteJuggler binary not found. Run: npm install @tummycrypt/remote-juggler");
  console.error("Or install directly: curl -fsSL https://raw.githubusercontent.com/Jesssullivan/RemoteJuggler/main/install.sh | bash");
  process.exit(1);
}

const child = spawn(BINARY_PATH, process.argv.slice(2), {
  stdio: "inherit",
  env: process.env,
});

child.on("error", (err) => {
  console.error(`Failed to start RemoteJuggler: ${err.message}`);
  process.exit(1);
});

child.on("exit", (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
  } else {
    process.exit(code || 0);
  }
});
