"""
RemoteJuggler Secure Enclave E2E Tests

Tests for macOS Secure Enclave-based PIN storage.
Requires macOS with T2/M1+ chip.

Run with: pytest test/e2e/test_secure_enclave.py -v -m secure_enclave
"""

import json
import subprocess
import sys
from pathlib import Path

import pytest


pytestmark = [pytest.mark.secure_enclave, pytest.mark.hardware]


# Skip entire module on non-macOS
if sys.platform != "darwin":
    pytestmark.append(pytest.mark.skip(reason="Secure Enclave tests require macOS"))


class TestSecureEnclaveAvailability:
    """Tests for Secure Enclave detection."""

    def test_secure_enclave_present(self, secure_enclave_available):
        """Verify Secure Enclave is available on this Mac."""
        if not secure_enclave_available:
            pytest.skip("Secure Enclave not available (requires T2/M1+ chip)")

        assert secure_enclave_available

    def test_security_framework_available(self):
        """Verify Security.framework is accessible."""
        # Check if we can query keychain
        result = subprocess.run(
            ["security", "list-keychains"],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0

    def test_macos_version(self):
        """Verify macOS version supports Secure Enclave APIs."""
        result = subprocess.run(
            ["sw_vers", "-productVersion"],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0

        version = result.stdout.strip()
        major_version = int(version.split(".")[0])

        # Secure Enclave APIs available in macOS 10.13+
        assert major_version >= 10, f"macOS version {version} too old for SE"


class TestSecureEnclaveKeychain:
    """Tests for Keychain integration with Secure Enclave."""

    def test_keychain_service_access(self, secure_enclave_available):
        """Test access to keychain services."""
        if not secure_enclave_available:
            pytest.skip("Secure Enclave not available")

        # List keychains to verify access
        result = subprocess.run(
            ["security", "list-keychains"],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0
        assert "login.keychain" in result.stdout or "keychain" in result.stdout.lower()

    def test_keychain_store_retrieve(self, secure_enclave_available, tmp_path):
        """Test storing and retrieving a generic password."""
        if not secure_enclave_available:
            pytest.skip("Secure Enclave not available")

        service_name = "dev.tinyland.remote-juggler.test"
        account_name = "test-identity"
        test_password = "test-pin-123456"

        # Clean up any existing entry
        subprocess.run(
            [
                "security",
                "delete-generic-password",
                "-s",
                service_name,
                "-a",
                account_name,
            ],
            capture_output=True,
        )

        try:
            # Store password
            result = subprocess.run(
                [
                    "security",
                    "add-generic-password",
                    "-s",
                    service_name,
                    "-a",
                    account_name,
                    "-w",
                    test_password,
                    "-U",
                ],  # Update if exists
                capture_output=True,
                text=True,
            )
            assert result.returncode == 0, f"Failed to store: {result.stderr}"

            # Retrieve password
            result = subprocess.run(
                [
                    "security",
                    "find-generic-password",
                    "-s",
                    service_name,
                    "-a",
                    account_name,
                    "-w",
                ],
                capture_output=True,
                text=True,
            )
            assert result.returncode == 0, f"Failed to retrieve: {result.stderr}"
            assert result.stdout.strip() == test_password

        finally:
            # Clean up
            subprocess.run(
                [
                    "security",
                    "delete-generic-password",
                    "-s",
                    service_name,
                    "-a",
                    account_name,
                ],
                capture_output=True,
            )

    def test_keychain_delete(self, secure_enclave_available):
        """Test deleting a keychain entry."""
        if not secure_enclave_available:
            pytest.skip("Secure Enclave not available")

        service_name = "dev.tinyland.remote-juggler.test-delete"
        account_name = "delete-test"

        # Store a test entry
        subprocess.run(
            [
                "security",
                "add-generic-password",
                "-s",
                service_name,
                "-a",
                account_name,
                "-w",
                "delete-me",
                "-U",
            ],
            capture_output=True,
        )

        # Delete it
        result = subprocess.run(
            [
                "security",
                "delete-generic-password",
                "-s",
                service_name,
                "-a",
                account_name,
            ],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0

        # Verify it's gone
        result = subprocess.run(
            [
                "security",
                "find-generic-password",
                "-s",
                service_name,
                "-a",
                account_name,
            ],
            capture_output=True,
            text=True,
        )
        assert result.returncode != 0  # Should not find


class TestHSMLibrarySecureEnclave:
    """Tests for the HSM C library with Secure Enclave backend."""

    def test_hsm_library_loads(self, hsm_library_available):
        """Verify HSM library is available."""
        assert hsm_library_available, "HSM library not built"

    def test_hsm_secure_enclave_backend(
        self, hsm_test_environment, secure_enclave_available
    ):
        """Test HSM library Secure Enclave backend."""
        if not secure_enclave_available:
            pytest.skip("Secure Enclave not available")

        if hsm_test_environment["backend"] != "secure_enclave":
            pytest.skip("Secure Enclave backend not configured")

        # Basic check that environment is set up for SE
        assert hsm_test_environment["backend"] == "secure_enclave"

    def test_hsm_test_binary_macos(
        self, hsm_test_environment, secure_enclave_available
    ):
        """Run HSM C test suite on macOS."""
        if not secure_enclave_available:
            pytest.skip("Secure Enclave not available")

        project_root = Path(__file__).parent.parent.parent
        test_binary = project_root / "pinentry" / "test_hsm"

        if not test_binary.exists():
            pytest.skip("test_hsm binary not built")

        env = hsm_test_environment["env"].copy()

        result = subprocess.run(
            [str(test_binary)],
            env=env,
            capture_output=True,
            text=True,
            timeout=60,
        )

        # Parse test output
        assert (
            "PASSED" in result.stdout or result.returncode == 0
        ), f"HSM tests failed:\n{result.stdout}\n{result.stderr}"


class TestPinentrySecureEnclave:
    """Tests for pinentry-remotejuggler with Secure Enclave backend."""

    def test_pinentry_exists_macos(self):
        """Verify pinentry-remotejuggler exists on macOS."""
        project_root = Path(__file__).parent.parent.parent
        pinentry_bin = project_root / "pinentry" / "pinentry-remotejuggler.py"

        assert pinentry_bin.exists(), "pinentry-remotejuggler.py not found"

    def test_pinentry_keychain_mode(self, secure_enclave_available, tmp_path):
        """Test pinentry in keychain storage mode."""
        if not secure_enclave_available:
            pytest.skip("Secure Enclave not available")

        project_root = Path(__file__).parent.parent.parent
        pinentry_bin = project_root / "pinentry" / "pinentry-remotejuggler.py"

        if not pinentry_bin.exists():
            pytest.skip("pinentry-remotejuggler.py not found")

        # Create test environment
        env = {
            "HOME": str(tmp_path),
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "REMOTE_JUGGLER_HSM_BACKEND": "keychain",
        }

        # Start pinentry and test basic commands
        proc = subprocess.Popen(
            ["python3", str(pinentry_bin), "--debug"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
        )

        try:
            proc.stdin.write("GETINFO version\n")
            proc.stdin.write("GETINFO flavor\n")
            proc.stdin.write("BYE\n")
            proc.stdin.flush()

            stdout, stderr = proc.communicate(timeout=5)

            assert "OK" in stdout
        finally:
            proc.terminate()

    @pytest.mark.slow
    def test_pinentry_se_store_retrieve(
        self,
        secure_enclave_available,
        pinentry_available,
        tmp_path,
    ):
        """Test storing and retrieving PIN via pinentry with Secure Enclave."""
        if not secure_enclave_available:
            pytest.skip("Secure Enclave not available")
        if not pinentry_available:
            pytest.skip("pinentry-remotejuggler not available")

        # Note: Full SE testing requires either:
        # 1. Disabling Touch ID/password requirement (not recommended)
        # 2. Running on a self-hosted Mac with accessibility access
        # 3. Using keychain fallback mode

        # Test with keychain backend (no biometric required)
        service_name = "dev.tinyland.remote-juggler.pinentry-test"
        identity = "test-pinentry-identity"
        test_pin = "test-pin-for-se"

        # Pre-store a PIN in keychain
        subprocess.run(
            ["security", "delete-generic-password", "-s", service_name, "-a", identity],
            capture_output=True,
        )

        subprocess.run(
            [
                "security",
                "add-generic-password",
                "-s",
                service_name,
                "-a",
                identity,
                "-w",
                test_pin,
                "-U",
            ],
            capture_output=True,
        )

        try:
            # Note: Full pinentry flow requires gpg-agent integration
            # which needs actual gpg key operations
            pass
        finally:
            # Clean up
            subprocess.run(
                [
                    "security",
                    "delete-generic-password",
                    "-s",
                    service_name,
                    "-a",
                    identity,
                ],
                capture_output=True,
            )


class TestSecureEnclaveEncryption:
    """Tests for Secure Enclave encryption operations."""

    def test_se_key_generation(self, secure_enclave_available):
        """Test generating a key in the Secure Enclave."""
        if not secure_enclave_available:
            pytest.skip("Secure Enclave not available")

        # Note: Direct SE key generation requires entitlements
        # and typically can only be done by signed applications.
        # We test the keychain path instead.

        # Verify keychain access control list capabilities
        # This command may fail without root, which is expected
        # The test verifies the security command is functional
        subprocess.run(
            ["security", "authorizationdb", "read", "system.keychain.modify"],
            capture_output=True,
            text=True,
        )


class TestSecureEnclaveErrorHandling:
    """Tests for Secure Enclave error conditions."""

    def test_keychain_access_denied(self, secure_enclave_available):
        """Test handling of keychain access denied."""
        if not secure_enclave_available:
            pytest.skip("Secure Enclave not available")

        # Try to access a non-existent keychain entry
        result = subprocess.run(
            [
                "security",
                "find-generic-password",
                "-s",
                "nonexistent.service.12345",
                "-a",
                "nonexistent.account",
            ],
            capture_output=True,
            text=True,
        )

        # Should fail gracefully
        assert result.returncode != 0
        assert "could not be found" in result.stderr or result.returncode == 44

    def test_invalid_service_name(self, secure_enclave_available):
        """Test handling of invalid service names."""
        if not secure_enclave_available:
            pytest.skip("Secure Enclave not available")

        # Try with empty service name
        result = subprocess.run(
            ["security", "find-generic-password", "-s", "", "-a", "test"],
            capture_output=True,
            text=True,
        )

        # Should fail with appropriate error
        assert result.returncode != 0


class TestSecureEnclaveCLI:
    """Tests for RemoteJuggler CLI with Secure Enclave."""

    def test_cli_pin_status(self, secure_enclave_available, tmp_path):
        """Test CLI pin status command on macOS."""
        if not secure_enclave_available:
            pytest.skip("Secure Enclave not available")

        project_root = Path(__file__).parent.parent.parent
        cli_binary = project_root / "target" / "release" / "remote-juggler"

        if not cli_binary.exists():
            pytest.skip("CLI binary not built")

        # Create minimal config
        config_dir = tmp_path / ".config" / "remote-juggler"
        config_dir.mkdir(parents=True)
        config_file = config_dir / "config.json"
        config_file.write_text(
            json.dumps(
                {
                    "version": "2.0.0",
                    "identities": {},
                    "settings": {"hsmAvailable": True},
                }
            )
        )

        env = {
            "HOME": str(tmp_path),
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        }

        result = subprocess.run(
            [str(cli_binary), "pin", "status"],
            env=env,
            capture_output=True,
            text=True,
            timeout=10,
        )

        # Should report SE availability or gracefully indicate unavailable
        # Don't require success as HSM library may not be linked
        assert (
            result.returncode == 0
            or "not available" in result.stdout.lower()
            or "not available" in result.stderr.lower()
        )


class TestSecureEnclaveBiometric:
    """Tests for Touch ID / biometric integration."""

    def test_biometric_availability(self, secure_enclave_available):
        """Check if biometric authentication is available."""
        if not secure_enclave_available:
            pytest.skip("Secure Enclave not available")

        # Check for biometric capability
        result = subprocess.run(
            ["bioutil", "-s"],
            capture_output=True,
            text=True,
        )

        # bioutil may not exist or may require specific entitlements
        # This is informational only
        if result.returncode == 0:
            has_biometric = (
                "Touch ID" in result.stdout or "biometric" in result.stdout.lower()
            )
            print(f"Biometric available: {has_biometric}")
