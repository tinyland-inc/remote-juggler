---
title: "Apple Code Signing Setup"
description: "Setting up Apple Developer certificates for signing macOS binaries, PKG installers, and DMGs with notarization."
category: "reference"
llm_priority: 5
keywords:
  - apple
  - signing
  - notarization
  - certificate
  - macos
---

# Apple Code Signing Setup

This guide covers setting up Apple Developer certificates for signing RemoteJuggler macOS binaries and PKG installers.

## Prerequisites

- Apple Developer Program membership ($99/year)
- macOS with Keychain Access
- Xcode or Command Line Tools installed

## Required Certificates

You need two Developer ID certificates from Apple:

| Certificate Type | Usage |
|-----------------|-------|
| Developer ID Application | Signs binaries (.app, executable files) |
| Developer ID Installer | Signs installer packages (.pkg) |

## Creating Certificates

### 1. Request Certificates from Apple

1. Go to [Apple Developer Portal](https://developer.apple.com/account/resources/certificates/list)
2. Click the "+" button to create a new certificate
3. Select **Developer ID Application** (for binaries)
4. Follow the CSR creation process using Keychain Access
5. Download and install the certificate
6. Repeat for **Developer ID Installer** (for PKGs)

### 2. Verify Certificates in Keychain

```bash
# List all signing identities
security find-identity -v -p codesigning

# Expected output:
# 1) XXXXXXXX "Developer ID Application: Your Name (TEAMID)"
# 2) XXXXXXXX "Developer ID Installer: Your Name (TEAMID)"
```

## Exporting Certificates for CI

### Export Developer ID Application Certificate

```bash
# Find the certificate hash
security find-identity -v -p codesigning | grep "Developer ID Application"

# Export to .p12 file (will prompt for export password)
security export -k login.keychain-db -t identities \
  -f pkcs12 -P "YOUR_EXPORT_PASSWORD" \
  -o developer-id-application.p12

# Base64 encode for CI variable
base64 -i developer-id-application.p12 | tr -d '\n' > apple-cert-app-base64.txt

# The contents of apple-cert-app-base64.txt goes in APPLE_CERTIFICATE_BASE64
cat apple-cert-app-base64.txt | pbcopy
echo "Copied to clipboard"
```

### Export Developer ID Installer Certificate

```bash
# Export installer certificate
security export -k login.keychain-db -t identities \
  -f pkcs12 -P "YOUR_EXPORT_PASSWORD" \
  -o developer-id-installer.p12

# Base64 encode
base64 -i developer-id-installer.p12 | tr -d '\n' > apple-cert-installer-base64.txt
```

### Export Developer ID G2 CA Certificate

The G2 intermediate certificate is required for the trust chain:

```bash
# Download from Apple
curl -O https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer

# Base64 encode
base64 -i DeveloperIDG2CA.cer | tr -d '\n' > apple-g2-ca-base64.txt
```

## GitLab CI Variables

Configure these variables in your GitLab project or group settings:

| Variable | Type | Value | Masked | Protected |
|----------|------|-------|--------|-----------|
| `APPLE_CERTIFICATE_BASE64` | Variable | Contents of apple-cert-app-base64.txt | Yes | Yes |
| `APPLE_CERTIFICATE_PASSWORD` | Variable | Export password for app cert | Yes | Yes |
| `APPLE_INSTALLER_CERTIFICATE_BASE64` | Variable | Contents of apple-cert-installer-base64.txt | Yes | Yes |
| `APPLE_INSTALLER_CERTIFICATE_PASSWORD` | Variable | Export password for installer cert | Yes | Yes |
| `APPLE_DEVELOPER_ID_APPLICATION` | Variable | `Developer ID Application: Name (TEAMID)` | No | No |
| `APPLE_DEVELOPER_ID_INSTALLER` | Variable | `Developer ID Installer: Name (TEAMID)` | No | No |
| `APPLE_DEVELOPER_ID_CA_G2` | Variable | Contents of apple-g2-ca-base64.txt | No | No |
| `APPLE_ID` | Variable | Your Apple ID email | Yes | Yes |
| `APPLE_NOTARIZE_PASSWORD` | Variable | App-specific password for notarization | Yes | Yes |
| `APPLE_TEAM_ID` | Variable | Your Team ID (e.g., QP994XQKNH) | No | No |

### Creating App-Specific Password for Notarization

1. Go to [Apple ID Account](https://appleid.apple.com/account/manage)
2. Sign in with your Apple ID
3. In the Security section, click "Generate Password" under App-Specific Passwords
4. Name it "GitLab CI Notarization"
5. Copy the generated password to `APPLE_NOTARIZE_PASSWORD`

## Local Signing (Development)

For local development, signing uses your keychain automatically:

```bash
# Sign a binary
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  ./remote-juggler

# Verify signature
codesign --verify --verbose=4 ./remote-juggler
spctl --assess --type execute --verbose=4 ./remote-juggler
```

## Creating Signed App Bundle

```bash
# Build and sign the app bundle
./scripts/create-app-bundle.sh 2.0.0

# Create signed DMG
./scripts/create-dmg.sh 2.0.0
```

## Notarization

### Using Keychain Profile (Recommended)

Store notarization credentials in keychain for easier access:

```bash
# Store credentials (one-time setup)
xcrun notarytool store-credentials "RemoteJuggler-Notarize" \
  --apple-id "your@email.com" \
  --team-id "QP994XQKNH" \
  --password "app-specific-password"

# Use stored credentials
xcrun notarytool submit ./RemoteJuggler.dmg \
  --keychain-profile "RemoteJuggler-Notarize" \
  --wait

# Staple the ticket
xcrun stapler staple ./RemoteJuggler.dmg
```

### Using Direct Credentials

```bash
xcrun notarytool submit ./RemoteJuggler.dmg \
  --apple-id "your@email.com" \
  --password "app-specific-password" \
  --team-id "QP994XQKNH" \
  --wait

xcrun stapler staple ./RemoteJuggler.dmg
```

## Troubleshooting

### "errSecInternalComponent" Error

This usually means the keychain is locked or inaccessible:

```bash
# Unlock keychain
security unlock-keychain -p "YOUR_PASSWORD" login.keychain-db
```

### Notarization Fails

Get the detailed log:

```bash
xcrun notarytool log <submission-id> \
  --apple-id "your@email.com" \
  --password "app-specific-password" \
  --team-id "QP994XQKNH"
```

Common issues:
- Binary not signed with hardened runtime (`--options runtime`)
- Missing timestamp (`--timestamp`)
- Unsigned nested code (frameworks, helpers)

### "Developer ID Application" Not Found

Ensure the certificate is properly installed:

```bash
# List all certificates
security find-identity -v

# If missing, reinstall from Apple Developer Portal
```

## Security Best Practices

1. **Never commit certificates** - Always use CI variables
2. **Use masked variables** - Prevent exposure in logs
3. **Rotate passwords periodically** - Especially notarization passwords
4. **Use protected variables** - Only available on protected branches
5. **Clean up temp files** - Scripts should delete .p12 files after import

## Current RemoteJuggler Signing Identity

```
Developer ID Application: John Sullivan (QP994XQKNH)
Developer ID Installer: John Sullivan (QP994XQKNH)
Team ID: QP994XQKNH
```
