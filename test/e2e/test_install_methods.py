"""
RemoteJuggler Installation Method Validation Tests

Tests that verify documented installation methods have valid URLs,
packages exist in registries, and install scripts function correctly.

These tests validate the *infrastructure* behind each install method,
not the binary itself (see test_installation.py for binary tests).

Run with:
    pytest test/e2e/test_install_methods.py -v
    pytest test/e2e/ -v -m install_methods
"""

import json
import os
import subprocess

import pytest


REPO = "tinyland-inc/remote-juggler"
GITHUB_API = f"https://api.github.com/repos/{REPO}"


def http_status(url: str) -> int:
    """Get HTTP status code for a URL (follows redirects)."""
    try:
        result = subprocess.run(
            ["curl", "-fsSL", "-o", "/dev/null", "-w", "%{http_code}", url],
            capture_output=True,
            text=True,
            timeout=15,
        )
        return int(result.stdout.strip())
    except (subprocess.TimeoutExpired, ValueError):
        return 0


def http_get(url: str) -> str:
    """Fetch URL content."""
    result = subprocess.run(
        ["curl", "-fsSL", url],
        capture_output=True,
        text=True,
        timeout=15,
    )
    return result.stdout if result.returncode == 0 else ""


# =============================================================================
# Install Script Tests
# =============================================================================


@pytest.mark.install_methods
class TestInstallScript:
    """Validate the curl | bash install script."""

    SCRIPT_URL = f"https://raw.githubusercontent.com/{REPO}/main/install.sh"

    def test_install_script_url_reachable(self):
        """Install script URL returns HTTP 200."""
        # raw.githubusercontent.com returns 200 for valid files
        content = http_get(self.SCRIPT_URL)
        assert len(content) > 100, "Install script content too small or empty"
        assert "#!/" in content, "Install script missing shebang"

    def test_install_script_help(self):
        """Install script --help exits cleanly."""
        result = subprocess.run(
            ["bash", "scripts/install.sh", "--help"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0
        assert "RemoteJuggler" in result.stdout

    def test_install_script_downloads_bare_binary(self):
        """Install script constructs URLs for bare binaries, not tar.gz."""
        with open("scripts/install.sh") as f:
            content = f.read()
        # The download section should not construct tar.gz URLs
        assert (
            "tar.gz"
            not in content.split("# Download binary")[1].split("# Download and verify")[
                0
            ]
            if "# Download binary" in content
            else True
        ), "Install script still references tar.gz archives in download section"
        # Should reference bare binary naming pattern
        assert "${PROGRAM_NAME}-${platform}" in content

    def test_install_script_uses_github_api(self):
        """Install script fetches versions from GitHub, not GitLab."""
        with open("scripts/install.sh") as f:
            content = f.read()
        assert "https://api.github.com/" in content
        assert "gitlab.com" not in content


# =============================================================================
# GitHub Release Asset Tests
# =============================================================================


@pytest.mark.install_methods
class TestGitHubReleases:
    """Validate release assets exist on GitHub."""

    def _get_latest_prerelease(self):
        """Get the latest pre-release tag."""
        result = subprocess.run(
            [
                "gh",
                "release",
                "list",
                "--repo",
                REPO,
                "--limit",
                "1",
                "--json",
                "tagName,isPrerelease",
            ],
            capture_output=True,
            text=True,
            timeout=15,
            env={**os.environ, "GITHUB_TOKEN": ""},
        )
        if result.returncode != 0:
            pytest.skip("gh CLI not available or not authenticated")
        releases = json.loads(result.stdout)
        if not releases:
            pytest.skip("No releases found")
        return releases[0]["tagName"]

    def _get_release_assets(self, tag: str):
        """Get asset names for a release."""
        result = subprocess.run(
            [
                "gh",
                "release",
                "view",
                tag,
                "--repo",
                REPO,
                "--json",
                "assets",
                "--jq",
                ".assets[].name",
            ],
            capture_output=True,
            text=True,
            timeout=15,
            env={**os.environ, "GITHUB_TOKEN": ""},
        )
        if result.returncode != 0:
            return []
        return result.stdout.strip().split("\n")

    def test_latest_release_has_assets(self):
        """Latest pre-release has downloadable assets."""
        tag = self._get_latest_prerelease()
        assets = self._get_release_assets(tag)
        assert len(assets) > 0, f"Release {tag} has no assets"

    def test_linux_amd64_binary_exists(self):
        """Linux amd64 bare binary exists in latest release."""
        tag = self._get_latest_prerelease()
        assets = self._get_release_assets(tag)
        assert (
            "remote-juggler-linux-amd64" in assets
        ), f"Missing remote-juggler-linux-amd64 in {tag} assets: {assets}"

    def test_linux_arm64_binary_exists(self):
        """Linux arm64 bare binary exists in latest release."""
        tag = self._get_latest_prerelease()
        assets = self._get_release_assets(tag)
        assert (
            "remote-juggler-linux-arm64" in assets
        ), f"Missing remote-juggler-linux-arm64 in {tag} assets: {assets}"

    def test_sha256_checksums_exist(self):
        """SHA256SUMS.txt exists in latest release."""
        tag = self._get_latest_prerelease()
        assets = self._get_release_assets(tag)
        assert (
            "SHA256SUMS.txt" in assets
        ), f"Missing SHA256SUMS.txt in {tag} assets: {assets}"

    def test_deb_package_exists(self):
        """Debian package exists in latest release."""
        tag = self._get_latest_prerelease()
        assets = self._get_release_assets(tag)
        deb_assets = [a for a in assets if a.endswith(".deb")]
        assert len(deb_assets) > 0, f"No .deb package in {tag} assets: {assets}"

    def test_rpm_package_exists(self):
        """RPM package exists in latest release."""
        tag = self._get_latest_prerelease()
        assets = self._get_release_assets(tag)
        rpm_assets = [a for a in assets if a.endswith(".rpm")]
        assert len(rpm_assets) > 0, f"No .rpm package in {tag} assets: {assets}"

    def test_per_file_checksums_exist(self):
        """Per-file .sha256 checksums exist for binaries."""
        tag = self._get_latest_prerelease()
        assets = self._get_release_assets(tag)
        assert "remote-juggler-linux-amd64.sha256" in assets


# =============================================================================
# npm Package Tests
# =============================================================================


@pytest.mark.install_methods
class TestNpmPackage:
    """Validate npm package availability."""

    PACKAGE = "@tummycrypt/remote-juggler"

    def test_npm_package_exists(self):
        """Package exists on npm registry."""
        result = subprocess.run(
            ["npm", "view", self.PACKAGE, "version"],
            capture_output=True,
            text=True,
            timeout=15,
        )
        if result.returncode != 0:
            pytest.skip("npm not available")
        assert result.stdout.strip(), f"npm package {self.PACKAGE} not found"

    def test_npm_beta_tag_exists(self):
        """Beta dist-tag exists on npm."""
        result = subprocess.run(
            ["npm", "view", self.PACKAGE, "dist-tags", "--json"],
            capture_output=True,
            text=True,
            timeout=15,
        )
        if result.returncode != 0:
            pytest.skip("npm not available")
        tags = json.loads(result.stdout)
        assert "beta" in tags, f"No 'beta' dist-tag: {tags}"

    def test_npm_package_has_bin(self):
        """Package defines a bin entry."""
        result = subprocess.run(
            ["npm", "view", self.PACKAGE, "bin", "--json"],
            capture_output=True,
            text=True,
            timeout=15,
        )
        if result.returncode != 0:
            pytest.skip("npm not available")
        bins = json.loads(result.stdout)
        assert "remote-juggler" in bins, f"No 'remote-juggler' bin entry: {bins}"


# =============================================================================
# Nix Flake Tests
# =============================================================================


@pytest.mark.install_methods
class TestNixFlake:
    """Validate Nix flake configuration."""

    def test_flake_exists(self):
        """flake.nix exists in repository root."""
        assert os.path.exists("flake.nix"), "flake.nix not found"

    def test_flake_has_default_package(self):
        """Flake defines a default package."""
        with open("flake.nix") as f:
            content = f.read()
        # Nix flakes use `default = <pkg>` inside the packages attrset
        assert "default =" in content, "flake.nix missing default package output"

    def test_flake_has_home_manager_module(self):
        """Flake exports Home Manager module."""
        with open("flake.nix") as f:
            content = f.read()
        assert (
            "homeManagerModules" in content
        ), "flake.nix missing homeManagerModules output"

    def test_home_manager_module_exists(self):
        """Home Manager module file exists."""
        assert os.path.exists(
            "nix/homeManagerModule.nix"
        ), "nix/homeManagerModule.nix not found"


# =============================================================================
# Documentation Consistency Tests
# =============================================================================


@pytest.mark.install_methods
class TestDocsConsistency:
    """Validate install docs match actual release assets."""

    def test_install_md_no_stale_gitlab_urls(self):
        """install.md contains no GitLab URLs."""
        with open("docs/install.md") as f:
            content = f.read()
        assert (
            "gitlab.com" not in content
        ), "docs/install.md still references gitlab.com"

    def test_installation_md_no_stale_gitlab_urls(self):
        """installation.md contains no GitLab URLs."""
        with open("docs/getting-started/installation.md") as f:
            content = f.read()
        assert (
            "gitlab.com" not in content
        ), "installation.md still references gitlab.com"

    def test_install_md_no_tar_gz_references(self):
        """install.md does not reference tar.gz for CLI download."""
        with open("docs/install.md") as f:
            content = f.read()
        # AppImage tar.gz is fine, but CLI tar.gz is wrong
        lines = [
            line
            for line in content.split("\n")
            if ".tar.gz" in line and "AppImage" not in line and "Source" not in line
        ]
        assert len(lines) == 0, f"install.md references tar.gz: {lines}"

    def test_install_md_uses_beta_tag_for_npm(self):
        """install.md uses @beta tag for npm commands."""
        with open("docs/install.md") as f:
            content = f.read()
        # Find lines with npm install or npx that reference our package
        for line in content.split("\n"):
            stripped = line.strip()
            if "@tummycrypt/remote-juggler" in stripped and (
                "npm install" in stripped or "npx " in stripped
            ):
                assert (
                    "@beta" in stripped
                ), f"npm command should use @beta tag: {stripped}"

    def test_no_homebrew_tap_in_install_md(self):
        """install.md does not document non-existent Homebrew tap."""
        with open("docs/install.md") as f:
            content = f.read()
        assert (
            "brew tap" not in content
        ), "install.md references Homebrew tap that doesn't exist"

    def test_no_aur_in_install_md(self):
        """install.md does not document non-existent AUR package."""
        with open("docs/install.md") as f:
            content = f.read()
        assert (
            "yay -S remote-juggler" not in content
        ), "install.md references AUR package that doesn't exist"

    def test_no_flatpak_in_install_md(self):
        """install.md does not document non-existent Flatpak."""
        with open("docs/install.md") as f:
            content = f.read()
        assert (
            "flatpak install" not in content
        ), "install.md references Flatpak that isn't on Flathub"
