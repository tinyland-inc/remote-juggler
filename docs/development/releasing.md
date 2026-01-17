# Release Process

Guide for releasing new versions of RemoteJuggler.

## Version Numbering

RemoteJuggler follows semantic versioning (SemVer):

- **MAJOR**: Breaking changes
- **MINOR**: New features, backward compatible
- **PATCH**: Bug fixes, backward compatible

## Release Checklist

### 1. Update Version

Edit `src/remote_juggler/Core.chpl`:

```chapel
const VERSION = "2.1.0";
```

### 2. Update Documentation

- Update CHANGELOG.md
- Verify docs are current
- Check all code references

### 3. Build and Test

```bash
make clean
make release
make test
```

### 4. Create Tag

```bash
git add -A
git commit -m "Release v2.1.0"
git tag -s v2.1.0 -m "Release v2.1.0"
git push origin main --tags
```

### 5. CI/CD Pipeline

The GitLab CI pipeline automatically:

1. Builds for all platforms
2. Runs tests
3. Creates release artifacts
4. Publishes to GitLab Package Registry
5. Deploys documentation

## CI/CD Pipeline

### Build Stage

```yaml
build:linux-amd64:
  stage: build
  image: chapel/chapel:2.6
  script:
    - make release
    - mv target/release/remote-juggler remote-juggler-linux-amd64
  artifacts:
    paths:
      - remote-juggler-linux-amd64

build:darwin-arm64:
  stage: build
  tags: [macos, arm64]
  script:
    - make release
    - mv target/release/remote-juggler remote-juggler-darwin-arm64
  artifacts:
    paths:
      - remote-juggler-darwin-arm64
```

### Release Stage

```yaml
release:
  stage: release
  image: registry.gitlab.com/gitlab-org/release-cli:latest
  rules:
    - if: $CI_COMMIT_TAG
  script:
    - echo "Creating release $CI_COMMIT_TAG"
  release:
    tag_name: $CI_COMMIT_TAG
    description: "Release $CI_COMMIT_TAG"
    assets:
      links:
        - name: remote-juggler-linux-amd64
          url: "$CI_API_V4_URL/projects/$CI_PROJECT_ID/packages/generic/remote-juggler/$CI_COMMIT_TAG/remote-juggler-linux-amd64"
        - name: remote-juggler-darwin-arm64
          url: "$CI_API_V4_URL/projects/$CI_PROJECT_ID/packages/generic/remote-juggler/$CI_COMMIT_TAG/remote-juggler-darwin-arm64"
```

### Package Registry

```yaml
upload:
  stage: release
  rules:
    - if: $CI_COMMIT_TAG
  script:
    - |
      for binary in remote-juggler-*; do
        curl --header "JOB-TOKEN: $CI_JOB_TOKEN" \
             --upload-file "$binary" \
             "$CI_API_V4_URL/projects/$CI_PROJECT_ID/packages/generic/remote-juggler/$CI_COMMIT_TAG/$binary"
      done
```

## macOS Code Signing

RemoteJuggler uses a comprehensive code signing pipeline based on patterns from moonlight/sunshine projects.

### Signing Flow Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    macOS Code Signing Pipeline                   │
├─────────────────────────────────────────────────────────────────┤
│  1. Create temporary keychain with random password              │
│  2. Import Developer ID G2 CA certificate (trust chain)         │
│  3. Import Developer ID Application certificate                 │
│  4. Import Developer ID Installer certificate (for PKG)         │
│  5. Set partition list for headless codesign access             │
│  6. Sign binary with hardened runtime (required for notarize)   │
│  7. Create unsigned PKG with pkgbuild                           │
│  8. Sign PKG with productsign                                   │
│  9. Submit for notarization with xcrun notarytool               │
│  10. Staple notarization ticket with xcrun stapler              │
│  11. Cleanup: delete keychain and certificate files             │
└─────────────────────────────────────────────────────────────────┘
```

### Required CI Variables

Configure these in GitLab CI/CD Settings > Variables:

#### Code Signing Certificates

| Variable | Type | Protected | Masked | Description |
|----------|------|-----------|--------|-------------|
| `APPLE_CERTIFICATE_BASE64` | Variable | Yes | Yes | Base64-encoded Developer ID Application certificate (.p12) |
| `APPLE_CERTIFICATE_PASSWORD` | Variable | Yes | Yes | Password for the application certificate |
| `APPLE_INSTALLER_CERTIFICATE_BASE64` | Variable | Yes | Yes | Base64-encoded Developer ID Installer certificate (.p12) |
| `APPLE_INSTALLER_CERTIFICATE_PASSWORD` | Variable | Yes | Yes | Password for installer cert (optional, falls back to APPLE_CERTIFICATE_PASSWORD) |
| `APPLE_DEVELOPER_ID_CA_G2` | Variable | Yes | Yes | Base64-encoded Developer ID Certification Authority G2 intermediate cert |

#### Signing Identity Strings

| Variable | Type | Protected | Masked | Description |
|----------|------|-----------|--------|-------------|
| `APPLE_DEVELOPER_ID_APPLICATION` | Variable | No | No | e.g., "Developer ID Application: Your Name (TEAMID)" |
| `APPLE_DEVELOPER_ID_INSTALLER` | Variable | No | No | e.g., "Developer ID Installer: Your Name (TEAMID)" |

#### Notarization Credentials

| Variable | Type | Protected | Masked | Description |
|----------|------|-----------|--------|-------------|
| `APPLE_ID` | Variable | Yes | Yes | Apple ID email for notarization |
| `APPLE_NOTARIZE_PASSWORD` | Variable | Yes | Yes | App-specific password (NOT your Apple ID password) |
| `APPLE_TEAM_ID` | Variable | No | No | Apple Developer Team ID (10 characters) |

### Export Certificates

#### 1. List Available Certificates

```bash
# Find your Developer ID certificates
security find-identity -v -p codesigning

# Example output:
# 1) ABC123... "Developer ID Application: Your Name (TEAMID)"
# 2) DEF456... "Developer ID Installer: Your Name (TEAMID)"
```

#### 2. Export Developer ID Application Certificate

```bash
# Export to .p12 file (you'll be prompted for a password)
security export -k ~/Library/Keychains/login.keychain-db \
  -t identities -f pkcs12 \
  -o developer-id-application.p12

# Base64 encode for CI variable
base64 -i developer-id-application.p12 | tr -d '\n' > cert-application.b64
cat cert-application.b64  # Copy this to APPLE_CERTIFICATE_BASE64
```

#### 3. Export Developer ID Installer Certificate

```bash
# Export installer certificate (used for PKG signing)
security export -k ~/Library/Keychains/login.keychain-db \
  -t identities -f pkcs12 \
  -o developer-id-installer.p12

# Base64 encode
base64 -i developer-id-installer.p12 | tr -d '\n' > cert-installer.b64
cat cert-installer.b64  # Copy to APPLE_INSTALLER_CERTIFICATE_BASE64
```

#### 4. Export Developer ID G2 CA Certificate

```bash
# Download from Apple or export from Keychain Access
# The Developer ID G2 CA is available at:
# https://www.apple.com/certificateauthority/

# If you have it in your keychain:
security find-certificate -c "Developer ID Certification Authority" \
  -p ~/Library/Keychains/login.keychain-db > DeveloperIDG2CA.cer

# Base64 encode
base64 -i DeveloperIDG2CA.cer | tr -d '\n' > cert-ca.b64
cat cert-ca.b64  # Copy to APPLE_DEVELOPER_ID_CA_G2
```

#### 5. Create App-Specific Password

1. Go to [appleid.apple.com](https://appleid.apple.com)
2. Sign in with your Apple ID
3. Navigate to Security > App-Specific Passwords
4. Generate a new password for "RemoteJuggler CI"
5. Store this as `APPLE_NOTARIZE_PASSWORD`

### CI Signing Jobs

The CI pipeline includes two signing jobs:

#### `sign:darwin-binary`

- Signs the standalone binary with Developer ID Application certificate
- Uses hardened runtime (required for notarization)
- Generates SHA256 checksum

#### `sign:darwin-pkg`

- Creates PKG installer with signed binary
- Signs PKG with Developer ID Installer certificate
- Submits for Apple notarization
- Staples notarization ticket to PKG
- Generates SHA256 checksum

### Graceful Fallback

Both signing jobs have graceful fallback behavior:

- If `APPLE_CERTIFICATE_BASE64` is not set, creates unsigned artifacts
- If notarization fails, PKG is still available (unsigned)
- `allow_failure: true` prevents pipeline failure from signing issues

### Verification Commands

```bash
# Verify binary signature
codesign --verify --verbose=4 remote-juggler-darwin-arm64

# Check Gatekeeper assessment
spctl --assess --type execute --verbose=4 remote-juggler-darwin-arm64

# Verify PKG signature
pkgutil --check-signature remote-juggler-*.pkg

# Verify stapled PKG
xcrun stapler validate remote-juggler-*.pkg
```

### Troubleshooting

#### "CSSMERR_TP_NOT_TRUSTED" Error

The Developer ID G2 CA certificate is missing. Ensure `APPLE_DEVELOPER_ID_CA_G2` is set.

#### "code has no resources but signature indicates they must be present"

The binary was not signed with hardened runtime. Ensure `--options runtime` flag is used.

#### Notarization Fails with "Invalid"

Check the notarization log artifact (`notarization-log.json`) for details. Common causes:
- Binary not signed with hardened runtime
- Missing timestamp (`--timestamp` flag)
- Using wrong certificate chain (WWDR instead of Developer ID)

## Homebrew Formula Update

After release, update Homebrew formula:

```ruby
class RemoteJuggler < Formula
  desc "Backend-agnostic git identity management"
  homepage "https://gitlab.com/tinyland/projects/remote-juggler"
  url "https://gitlab.com/tinyland/projects/remote-juggler/-/archive/v2.1.0/remote-juggler-v2.1.0.tar.gz"
  sha256 "NEW_SHA256_HERE"
  license "MIT"
end
```

## Post-Release

### 1. Verify Downloads

```bash
curl -LO https://gitlab.com/.../remote-juggler-darwin-arm64
chmod +x remote-juggler-darwin-arm64
./remote-juggler-darwin-arm64 --version
```

### 2. Update Documentation

Update version references in docs.

### 3. Announce

- GitLab release notes
- Changelog update
- Social media (if applicable)

## Hotfix Process

For urgent fixes:

1. Create branch from tag:
   ```bash
   git checkout -b hotfix/2.1.1 v2.1.0
   ```

2. Apply fix and test

3. Update version to patch increment

4. Tag and release:
   ```bash
   git tag -s v2.1.1 -m "Hotfix release"
   git push origin hotfix/2.1.1 --tags
   ```

5. Merge back to main:
   ```bash
   git checkout main
   git merge hotfix/2.1.1
   ```
