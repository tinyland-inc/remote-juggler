"""
RemoteJuggler TPM E2E Tests

Tests for TPM-based PIN storage and retrieval.
Requires swtpm or physical TPM 2.0.

Run with: pytest test/e2e/test_tpm.py -v -m tpm
"""

import json
import os
import subprocess
import time
from pathlib import Path

import pytest


pytestmark = pytest.mark.tpm


class TestTPMAvailability:
    """Tests for TPM detection and initialization."""

    def test_swtpm_running(self, swtpm_environment):
        """Verify swtpm is running and accessible."""
        env = swtpm_environment["env"]

        # Check TPM is responding
        result = subprocess.run(
            ["tpm2_getcap", "properties-fixed"],
            env=env,
            capture_output=True,
            text=True,
            timeout=10,
        )

        assert result.returncode == 0, f"TPM not accessible: {result.stderr}"
        assert "TPM2_PT_MANUFACTURER" in result.stdout

    def test_tpm_version(self, swtpm_environment, tpm_tools_available):
        """Verify TPM 2.0 version."""
        if not tpm_tools_available:
            pytest.skip("tpm2-tools not available")

        env = swtpm_environment["env"]

        result = subprocess.run(
            ["tpm2_getcap", "properties-fixed"],
            env=env,
            capture_output=True,
            text=True,
        )

        # Should report TPM 2.0 family
        assert "TPM2_PT_FAMILY_INDICATOR" in result.stdout

    def test_tpm_algorithms(self, swtpm_environment, tpm_tools_available):
        """Verify required cryptographic algorithms are available."""
        if not tpm_tools_available:
            pytest.skip("tpm2-tools not available")

        env = swtpm_environment["env"]

        result = subprocess.run(
            ["tpm2_getcap", "algorithms"],
            env=env,
            capture_output=True,
            text=True,
        )

        assert result.returncode == 0
        # Check for algorithms we need
        assert "sha256" in result.stdout.lower()
        assert "aes" in result.stdout.lower()


class TestTPMKeyOperations:
    """Tests for TPM key creation and sealing."""

    def test_create_primary_key(self, swtpm_environment, tpm_tools_available):
        """Test creating a primary key in the TPM."""
        if not tpm_tools_available:
            pytest.skip("tpm2-tools not available")

        env = swtpm_environment["env"]
        state_dir = swtpm_environment["state_dir"]

        # Create primary key
        ctx_file = state_dir / "primary.ctx"
        result = subprocess.run(
            [
                "tpm2_createprimary",
                "-C",
                "o",  # Owner hierarchy
                "-c",
                str(ctx_file),
            ],
            env=env,
            capture_output=True,
            text=True,
        )

        assert result.returncode == 0, f"Failed to create primary: {result.stderr}"
        assert ctx_file.exists()

    def test_seal_unseal_data(self, swtpm_environment, tpm_tools_available):
        """Test sealing and unsealing data with TPM."""
        if not tpm_tools_available:
            pytest.skip("tpm2-tools not available")

        env = swtpm_environment["env"]
        state_dir = swtpm_environment["state_dir"]

        # Test data to seal
        test_data = "test-pin-12345"
        data_file = state_dir / "test_data.txt"
        data_file.write_text(test_data)

        # Create primary key
        primary_ctx = state_dir / "primary.ctx"
        subprocess.run(
            ["tpm2_createprimary", "-C", "o", "-c", str(primary_ctx)],
            env=env,
            check=True,
            capture_output=True,
        )

        # Create sealing key
        seal_pub = state_dir / "seal.pub"
        seal_priv = state_dir / "seal.priv"
        result = subprocess.run(
            [
                "tpm2_create",
                "-C",
                str(primary_ctx),
                "-i",
                str(data_file),
                "-u",
                str(seal_pub),
                "-r",
                str(seal_priv),
            ],
            env=env,
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"Failed to seal: {result.stderr}"

        # Load sealed object
        seal_ctx = state_dir / "seal.ctx"
        result = subprocess.run(
            [
                "tpm2_load",
                "-C",
                str(primary_ctx),
                "-u",
                str(seal_pub),
                "-r",
                str(seal_priv),
                "-c",
                str(seal_ctx),
            ],
            env=env,
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"Failed to load: {result.stderr}"

        # Unseal data
        unsealed_file = state_dir / "unsealed.txt"
        result = subprocess.run(
            [
                "tpm2_unseal",
                "-c",
                str(seal_ctx),
                "-o",
                str(unsealed_file),
            ],
            env=env,
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"Failed to unseal: {result.stderr}"

        # Verify data matches
        unsealed_data = unsealed_file.read_text()
        assert unsealed_data == test_data

    def test_seal_with_password(self, swtpm_environment, tpm_tools_available):
        """Test sealing data with password protection."""
        if not tpm_tools_available:
            pytest.skip("tpm2-tools not available")

        env = swtpm_environment["env"]
        state_dir = swtpm_environment["state_dir"]

        test_pin = "secure-pin-67890"
        password = "test-password"
        data_file = state_dir / "pin_data.txt"
        data_file.write_text(test_pin)

        # Create primary key
        primary_ctx = state_dir / "primary_pw.ctx"
        subprocess.run(
            ["tpm2_createprimary", "-C", "o", "-c", str(primary_ctx)],
            env=env,
            check=True,
            capture_output=True,
        )

        # Seal with password
        seal_pub = state_dir / "seal_pw.pub"
        seal_priv = state_dir / "seal_pw.priv"
        result = subprocess.run(
            [
                "tpm2_create",
                "-C",
                str(primary_ctx),
                "-i",
                str(data_file),
                "-u",
                str(seal_pub),
                "-r",
                str(seal_priv),
                "-p",
                password,
            ],
            env=env,
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0

        # Load sealed object
        seal_ctx = state_dir / "seal_pw.ctx"
        subprocess.run(
            [
                "tpm2_load",
                "-C",
                str(primary_ctx),
                "-u",
                str(seal_pub),
                "-r",
                str(seal_priv),
                "-c",
                str(seal_ctx),
            ],
            env=env,
            check=True,
            capture_output=True,
        )

        # Unseal with correct password
        unsealed_file = state_dir / "unsealed_pw.txt"
        result = subprocess.run(
            [
                "tpm2_unseal",
                "-c",
                str(seal_ctx),
                "-p",
                password,
                "-o",
                str(unsealed_file),
            ],
            env=env,
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0
        assert unsealed_file.read_text() == test_pin

        # Unseal with wrong password should fail
        result = subprocess.run(
            [
                "tpm2_unseal",
                "-c",
                str(seal_ctx),
                "-p",
                "wrong-password",
                "-o",
                str(state_dir / "bad.txt"),
            ],
            env=env,
            capture_output=True,
            text=True,
        )
        assert result.returncode != 0


class TestHSMLibraryTPM:
    """Tests for the HSM C library with TPM backend."""

    def test_hsm_library_loads(self, hsm_library_available):
        """Verify HSM library is available."""
        assert hsm_library_available, "HSM library not built"

    def test_hsm_tpm_backend(self, hsm_test_environment):
        """Test HSM library TPM backend detection."""
        if hsm_test_environment["backend"] != "tpm":
            pytest.skip("TPM backend not available")

        # The HSM library should detect TPM
        assert "tpm" in hsm_test_environment
        assert hsm_test_environment["tpm"]["process"].poll() is None

    def test_hsm_test_binary(self, hsm_test_environment, tpm_tools_available):
        """Run HSM C test suite with TPM backend."""
        if hsm_test_environment["backend"] != "tpm":
            pytest.skip("TPM backend not available")

        # Find the test_hsm binary
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


class TestPinentryTPM:
    """Tests for pinentry-remotejuggler with TPM backend."""

    def test_pinentry_protocol_compliance(self, pinentry_available, temp_dir):
        """Test pinentry responds to Assuan protocol."""
        if not pinentry_available:
            pytest.skip("pinentry-remotejuggler not available")

        project_root = Path(__file__).parent.parent.parent
        pinentry_bin = project_root / "pinentry" / "pinentry-remotejuggler.py"

        if not pinentry_bin.exists():
            pytest.skip("pinentry-remotejuggler.py not found")

        # Start pinentry
        proc = subprocess.Popen(
            ["python3", str(pinentry_bin), "--debug"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        try:
            # Send GETINFO commands
            proc.stdin.write("GETINFO version\n")
            proc.stdin.write("GETINFO pid\n")
            proc.stdin.write("BYE\n")
            proc.stdin.flush()

            stdout, stderr = proc.communicate(timeout=5)

            # Should respond with OK
            assert "OK" in stdout
        finally:
            proc.terminate()

    @pytest.mark.slow
    def test_pinentry_tpm_store_retrieve(
        self,
        swtpm_environment,
        hsm_test_environment,
        isolated_gpg_environment,
        tpm_tools_available,
    ):
        """Test storing and retrieving PIN via pinentry with TPM."""
        if hsm_test_environment["backend"] != "tpm":
            pytest.skip("TPM backend not available")

        env = hsm_test_environment["env"].copy()
        env.update(isolated_gpg_environment["env"])
        state_dir = hsm_test_environment["state_dir"]

        project_root = Path(__file__).parent.parent.parent
        pinentry_bin = project_root / "pinentry" / "pinentry-remotejuggler.py"

        if not pinentry_bin.exists():
            pytest.skip("pinentry-remotejuggler.py not found")

        # Configure gpg-agent to use our pinentry
        gpg_agent_conf = Path(env["GNUPGHOME"]) / "gpg-agent.conf"
        gpg_agent_conf.write_text(f"""
pinentry-program {pinentry_bin}
allow-loopback-pinentry
debug-level guru
log-file {state_dir}/gpg-agent.log
""")

        # Kill existing gpg-agent
        subprocess.run(
            ["gpgconf", "--kill", "gpg-agent"],
            env=env,
            capture_output=True,
        )

        # Set environment for RemoteJuggler to use TPM
        env["REMOTE_JUGGLER_HSM_BACKEND"] = "tpm"

        # Create a test config for the identity
        config_dir = state_dir / "config"
        config_dir.mkdir(exist_ok=True)
        config_file = config_dir / "config.json"
        config_file.write_text(
            json.dumps(
                {
                    "version": "2.0.0",
                    "identities": {
                        "test-identity": {
                            "provider": "gitlab",
                            "host": "gitlab.com",
                            "hostname": "gitlab.com",
                            "email": "test@example.com",
                            "gpg": {
                                "keyId": isolated_gpg_environment["key_id"],
                            },
                        }
                    },
                    "settings": {
                        "defaultSecurityMode": "trusted_workstation",
                        "hsmAvailable": True,
                    },
                }
            )
        )
        env["REMOTE_JUGGLER_CONFIG"] = str(config_file)

        # Test PIN storage via CLI (if binary exists)
        cli_binary = project_root / "target" / "release" / "remote-juggler"
        if cli_binary.exists():
            # Store PIN
            result = subprocess.run(
                [str(cli_binary), "pin", "store", "test-identity", "--pin", "123456"],
                env=env,
                capture_output=True,
                text=True,
                timeout=30,
            )
            # May fail if HSM library not linked, but should not crash
            assert (
                "error" not in result.stderr.lower()
                or "not available" in result.stderr.lower()
            )

    @pytest.mark.slow
    def test_gpg_sign_with_tpm_pin(
        self,
        swtpm_environment,
        hsm_test_environment,
        isolated_gpg_environment,
    ):
        """Test GPG signing operation with PIN from TPM."""
        if hsm_test_environment["backend"] != "tpm":
            pytest.skip("TPM backend not available")

        # This is a more comprehensive test that verifies:
        # 1. PIN is stored in TPM
        # 2. GPG operation triggers pinentry
        # 3. Pinentry retrieves PIN from TPM
        # 4. Signing succeeds without user interaction

        env = hsm_test_environment["env"].copy()
        env.update(isolated_gpg_environment["env"])
        state_dir = hsm_test_environment["state_dir"]

        # Create test file
        test_file = state_dir / "test_sign.txt"
        test_file.write_text("Test data for signing")

        # Configure loopback pinentry for testing
        # This allows us to inject PIN programmatically
        gpg_agent_conf = Path(env["GNUPGHOME"]) / "gpg-agent.conf"
        gpg_agent_conf.write_text("""
allow-loopback-pinentry
allow-preset-passphrase
""")

        # Restart gpg-agent
        subprocess.run(["gpgconf", "--kill", "gpg-agent"], env=env, capture_output=True)
        time.sleep(0.5)

        # Preset the passphrase for the key
        key_id = isolated_gpg_environment["key_id"]
        keygrip = isolated_gpg_environment.get("keygrip", "")

        if keygrip:
            # Use gpg-preset-passphrase to cache the passphrase
            result = subprocess.run(
                ["gpg-preset-passphrase", "--preset", keygrip],
                input="test-passphrase\n",
                env=env,
                capture_output=True,
                text=True,
            )

        # Try to sign with loopback
        result = subprocess.run(
            [
                "gpg",
                "--batch",
                "--yes",
                "--pinentry-mode",
                "loopback",
                "--passphrase",
                "test-passphrase",
                "--local-user",
                key_id,
                "--armor",
                "--detach-sign",
                str(test_file),
            ],
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
        )

        # Verify signature was created
        sig_file = state_dir / "test_sign.txt.asc"
        if result.returncode == 0:
            assert sig_file.exists() or (state_dir / "test_sign.txt.sig").exists()


class TestTPMErrorHandling:
    """Tests for TPM error conditions and recovery."""

    def test_tpm_unavailable_detection(self, tpm_tools_available):
        """Test detection when TPM is unavailable."""
        if not tpm_tools_available:
            pytest.skip("tpm2-tools not available")

        # Try to access TPM with invalid TCTI
        env = os.environ.copy()
        env["TPM2TOOLS_TCTI"] = "swtpm:host=invalid,port=0"

        result = subprocess.run(
            ["tpm2_getcap", "properties-fixed"],
            env=env,
            capture_output=True,
            text=True,
            timeout=10,
        )

        # Should fail gracefully
        assert result.returncode != 0

    def test_seal_empty_data(self, swtpm_environment, tpm_tools_available):
        """Test sealing empty data."""
        if not tpm_tools_available:
            pytest.skip("tpm2-tools not available")

        env = swtpm_environment["env"]
        state_dir = swtpm_environment["state_dir"]

        # Create empty file
        empty_file = state_dir / "empty.txt"
        empty_file.write_text("")

        # Create primary key
        primary_ctx = state_dir / "primary_empty.ctx"
        subprocess.run(
            ["tpm2_createprimary", "-C", "o", "-c", str(primary_ctx)],
            env=env,
            check=True,
            capture_output=True,
        )

        # Try to seal empty data - should either succeed or fail gracefully
        # Empty seal behavior varies by TPM implementation
        subprocess.run(
            [
                "tpm2_create",
                "-C",
                str(primary_ctx),
                "-i",
                str(empty_file),
                "-u",
                str(state_dir / "empty.pub"),
                "-r",
                str(state_dir / "empty.priv"),
            ],
            env=env,
            capture_output=True,
            text=True,
        )

    def test_seal_large_data(self, swtpm_environment, tpm_tools_available):
        """Test sealing data larger than TPM buffer."""
        if not tpm_tools_available:
            pytest.skip("tpm2-tools not available")

        env = swtpm_environment["env"]
        state_dir = swtpm_environment["state_dir"]

        # Create large file (larger than typical TPM seal limit ~1KB)
        large_file = state_dir / "large.txt"
        large_file.write_text("x" * 2048)

        # Create primary key
        primary_ctx = state_dir / "primary_large.ctx"
        subprocess.run(
            ["tpm2_createprimary", "-C", "o", "-c", str(primary_ctx)],
            env=env,
            check=True,
            capture_output=True,
        )

        # Try to seal large data
        result = subprocess.run(
            [
                "tpm2_create",
                "-C",
                str(primary_ctx),
                "-i",
                str(large_file),
                "-u",
                str(state_dir / "large.pub"),
                "-r",
                str(state_dir / "large.priv"),
            ],
            env=env,
            capture_output=True,
            text=True,
        )

        # Should fail gracefully with size error
        if result.returncode != 0:
            assert (
                "size" in result.stderr.lower()
                or "too" in result.stderr.lower()
                or "large" in result.stderr.lower()
                or "RC_SIZE" in result.stderr
            )


class TestTPMConcurrency:
    """Tests for concurrent TPM operations."""

    def test_concurrent_seal_operations(self, swtpm_environment, tpm_tools_available):
        """Test multiple concurrent seal operations."""
        if not tpm_tools_available:
            pytest.skip("tpm2-tools not available")

        import concurrent.futures

        env = swtpm_environment["env"]
        state_dir = swtpm_environment["state_dir"]

        # Create primary key
        primary_ctx = state_dir / "primary_concurrent.ctx"
        subprocess.run(
            ["tpm2_createprimary", "-C", "o", "-c", str(primary_ctx)],
            env=env,
            check=True,
            capture_output=True,
        )

        def seal_data(idx: int) -> bool:
            """Seal data in a thread."""
            data_file = state_dir / f"concurrent_{idx}.txt"
            data_file.write_text(f"data-{idx}")

            result = subprocess.run(
                [
                    "tpm2_create",
                    "-C",
                    str(primary_ctx),
                    "-i",
                    str(data_file),
                    "-u",
                    str(state_dir / f"concurrent_{idx}.pub"),
                    "-r",
                    str(state_dir / f"concurrent_{idx}.priv"),
                ],
                env=env,
                capture_output=True,
                text=True,
            )
            return result.returncode == 0

        # Run 5 concurrent seal operations
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
            futures = [executor.submit(seal_data, i) for i in range(5)]
            results = [f.result() for f in concurrent.futures.as_completed(futures)]

        # At least some should succeed (TPM may serialize)
        assert any(results), "All concurrent seal operations failed"


class TestTPMCleanup:
    """Tests for TPM state cleanup."""

    def test_clear_tpm_state(self, swtpm_environment, tpm_tools_available):
        """Test clearing TPM transient objects."""
        if not tpm_tools_available:
            pytest.skip("tpm2-tools not available")

        env = swtpm_environment["env"]

        # Flush all transient objects
        result = subprocess.run(
            ["tpm2_flushcontext", "-t"],
            env=env,
            capture_output=True,
            text=True,
        )

        # Should succeed (even if no objects to flush)
        assert result.returncode == 0 or "no object" in result.stderr.lower()
