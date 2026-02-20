#!/usr/bin/env node
/**
 * RemoteJuggler npm postinstall script
 *
 * Downloads the correct platform-specific binary from GitHub Releases
 * and places it alongside this script for the CLI wrapper to invoke.
 */

const { createWriteStream, chmodSync, existsSync } = require("fs");
const { join } = require("path");
const https = require("https");
const { execSync } = require("child_process");

const pkg = require("../package.json");
const VERSION = pkg.version;
const BINARY_PATH = join(__dirname, "remote-juggler-binary");

// Map Node.js platform/arch to GitHub Release asset names
const PLATFORM_MAP = {
  "linux-x64": "remote-juggler-linux-amd64",
  "linux-arm64": "remote-juggler-linux-arm64",
  "darwin-x64": "remote-juggler-darwin-amd64",
  "darwin-arm64": "remote-juggler-darwin-arm64",
};

function getPlatformKey() {
  return `${process.platform}-${process.arch}`;
}

function getDownloadUrl() {
  const key = getPlatformKey();
  const asset = PLATFORM_MAP[key];
  if (!asset) {
    if (process.platform === "win32") {
      console.error("RemoteJuggler does not have a native Windows build.");
      console.error("Use WSL (Windows Subsystem for Linux) instead:");
      console.error("  wsl --install && wsl npm install -g @tummycrypt/remote-juggler");
      console.error("");
      console.error("Or install in WSL directly:");
      console.error("  wsl curl -fsSL https://raw.githubusercontent.com/Jesssullivan/RemoteJuggler/main/install.sh | bash");
    } else {
      console.error(
        `Unsupported platform: ${key}. Supported: ${Object.keys(PLATFORM_MAP).join(", ")}`
      );
    }
    process.exit(1);
  }
  return `https://github.com/Jesssullivan/RemoteJuggler/releases/download/v${VERSION}/${asset}`;
}

function download(url) {
  return new Promise((resolve, reject) => {
    const request = https.get(url, (response) => {
      // Handle redirects (GitHub sends 302 to S3)
      if (response.statusCode >= 300 && response.statusCode < 400 && response.headers.location) {
        return download(response.headers.location).then(resolve).catch(reject);
      }

      if (response.statusCode !== 200) {
        reject(new Error(`Download failed: HTTP ${response.statusCode} from ${url}`));
        return;
      }

      const file = createWriteStream(BINARY_PATH);
      response.pipe(file);
      file.on("finish", () => {
        file.close();
        chmodSync(BINARY_PATH, 0o755);
        resolve();
      });
      file.on("error", (err) => {
        reject(err);
      });
    });

    request.on("error", reject);
    request.setTimeout(60000, () => {
      request.destroy();
      reject(new Error("Download timeout (60s)"));
    });
  });
}

async function main() {
  // Skip download if binary already exists (e.g., local development)
  if (existsSync(BINARY_PATH)) {
    console.log("RemoteJuggler binary already exists, skipping download.");
    return;
  }

  const url = getDownloadUrl();
  const key = getPlatformKey();
  console.log(`Downloading RemoteJuggler v${VERSION} for ${key}...`);
  console.log(`  URL: ${url}`);

  try {
    await download(url);
    console.log(`RemoteJuggler v${VERSION} installed successfully.`);

    // Quick sanity check
    try {
      const output = execSync(`"${BINARY_PATH}" --help`, {
        timeout: 5000,
        encoding: "utf-8",
      });
      if (output.includes("remote-juggler") || output.includes("RemoteJuggler")) {
        console.log("  Binary verified OK.");
      }
    } catch {
      // Binary may not be fully compatible (e.g., missing libs) but install succeeded
      console.log("  Binary downloaded (verification skipped).");
    }
  } catch (err) {
    console.error(`Failed to download RemoteJuggler: ${err.message}`);
    console.error("");
    console.error("You can install manually:");
    console.error("  curl -fsSL https://raw.githubusercontent.com/Jesssullivan/RemoteJuggler/main/install.sh | bash");
    process.exit(1);
  }
}

main();
