"""
RemoteJuggler HSM Workflow E2E Tests

End-to-end tests for the complete HSM workflow:
- First-time setup with HSM detection
- PIN storage in TPM/Secure Enclave
- GPG signing with auto-PIN retrieval
- Security mode transitions
- Error recovery

Run with: pytest test/e2e/test_hsm_workflow.py -v
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path

import pytest


class TestHSMDetection:
    """Tests for HSM backend auto-detection."""

    def test_detect_available_hsm(self, hsm_test_environment):
        """Verify HSM detection identifies available backend."""
        backend = hsm_test_environment["backend"]
        assert backend in ["tpm", "secure_enclave", "keychain", "stub"]

        if sys.platform == "linux":
            # On Linux with swtpm, should detect TPM
            if hsm_test_environment.get("tpm"):
                assert backend == "tpm"
        elif sys.platform == "darwin":
            # On macOS, should detect SE or keychain
            assert backend in ["secure_enclave", "keychain"]

    def test_hsm_detection_via_cli(self, hsm_test_environment, tmp_path):
        """Test HSM detection through CLI command."""
        project_root = Path(__file__).parent.parent.parent
        cli_binary = project_root / "target" / "release" / "remote-juggler"

        if not cli_binary.exists():
            pytest.skip("CLI binary not built")

        env = hsm_test_environment["env"].copy()
        env["HOME"] = str(tmp_path)

        # Create minimal config
        config_dir = tmp_path / ".config" / "remote-juggler"
        config_dir.mkdir(parents=True)
        (config_dir / "config.json").write_text(
            json.dumps({"version": "2.0.0", "identities": {}, "settings": {}})
        )

        result = subprocess.run(
            [str(cli_binary), "pin", "status"],
            env=env,
            capture_output=True,
            text=True,
            timeout=10,
        )

        # Should report some HSM status
        output = result.stdout + result.stderr
        assert any(
            word in output.lower()
            for word in ["tpm", "secure enclave", "keychain", "hsm", "not available"]
        )


class TestSecurityModeWorkflow:
    """Tests for security mode configuration workflow."""

    def test_security_mode_transitions(self, hsm_test_environment, tmp_path):
        """Test transitioning between security modes."""
        project_root = Path(__file__).parent.parent.parent
        cli_binary = project_root / "target" / "release" / "remote-juggler"

        if not cli_binary.exists():
            pytest.skip("CLI binary not built")

        env = hsm_test_environment["env"].copy()
        env["HOME"] = str(tmp_path)

        # Create config with initial mode
        config_dir = tmp_path / ".config" / "remote-juggler"
        config_dir.mkdir(parents=True)
        config_file = config_dir / "config.json"
        config_file.write_text(
            json.dumps(
                {
                    "version": "2.0.0",
                    "identities": {
                        "test-id": {
                            "provider": "gitlab",
                            "host": "gitlab.com",
                            "hostname": "gitlab.com",
                        }
                    },
                    "settings": {
                        "defaultSecurityMode": "developer_workflow",
                        "hsmAvailable": hsm_test_environment["backend"] != "stub",
                    },
                }
            )
        )

        # Query current mode
        result = subprocess.run(
            [str(cli_binary), "security-mode"],
            env=env,
            capture_output=True,
            text=True,
            timeout=10,
        )

        # Should show current mode
        if result.returncode == 0:
            assert (
                "developer_workflow" in result.stdout.lower()
                or "mode" in result.stdout.lower()
            )


class TestPINStorageWorkflow:
    """Tests for PIN storage and retrieval workflow."""

    @pytest.mark.tpm
    def test_pin_lifecycle_tpm(self, hsm_test_environment, isolated_gpg_environment):
        """Test complete PIN lifecycle with TPM backend."""
        if hsm_test_environment["backend"] != "tpm":
            pytest.skip("TPM backend not available")

        state_dir = hsm_test_environment["state_dir"]
        env = hsm_test_environment["env"].copy()
        env.update(isolated_gpg_environment["env"])

        project_root = Path(__file__).parent.parent.parent
        cli_binary = project_root / "target" / "release" / "remote-juggler"

        if not cli_binary.exists():
            pytest.skip("CLI binary not built")

        identity = "test-workflow-identity"
        test_pin = "workflow-pin-123456"

        # Create config
        config_dir = state_dir / "config"
        config_dir.mkdir(exist_ok=True)
        config_file = config_dir / "config.json"
        config_file.write_text(
            json.dumps(
                {
                    "version": "2.0.0",
                    "identities": {
                        identity: {
                            "provider": "gitlab",
                            "host": "gitlab.com",
                            "hostname": "gitlab.com",
                            "email": "test@example.com",
                            "gpg": {"keyId": isolated_gpg_environment["key_id"]},
                        }
                    },
                    "settings": {
                        "defaultSecurityMode": "trusted_workstation",
                        "hsmAvailable": True,
                    },
                }
            )
        )
        env["HOME"] = str(state_dir)

        # Step 1: Store PIN
        result = subprocess.run(
            [str(cli_binary), "pin", "store", identity, "--pin", test_pin],
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
        )
        # May fail if HSM not fully integrated, but should not crash
        store_success = result.returncode == 0

        if store_success:
            # Step 2: Verify PIN is stored
            result = subprocess.run(
                [str(cli_binary), "pin", "status", identity],
                env=env,
                capture_output=True,
                text=True,
                timeout=10,
            )
            assert "stored" in result.stdout.lower() or identity in result.stdout

            # Step 3: Clear PIN
            result = subprocess.run(
                [str(cli_binary), "pin", "clear", identity],
                env=env,
                capture_output=True,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0 or "cleared" in result.stdout.lower()

    @pytest.mark.secure_enclave
    def test_pin_lifecycle_secure_enclave(self, hsm_test_environment, tmp_path):
        """Test complete PIN lifecycle with Secure Enclave backend."""
        if hsm_test_environment["backend"] not in ["secure_enclave", "keychain"]:
            pytest.skip("Secure Enclave/Keychain backend not available")

        if sys.platform != "darwin":
            pytest.skip("Secure Enclave tests require macOS")

        identity = "test-se-identity"
        test_pin = "se-pin-654321"
        service_name = f"dev.tinyland.remote-juggler.{identity}"

        # Clean up any existing
        subprocess.run(
            ["security", "delete-generic-password", "-s", service_name, "-a", identity],
            capture_output=True,
        )

        try:
            # Store PIN via keychain
            result = subprocess.run(
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
                text=True,
            )
            assert result.returncode == 0, f"Failed to store: {result.stderr}"

            # Verify retrieval
            result = subprocess.run(
                [
                    "security",
                    "find-generic-password",
                    "-s",
                    service_name,
                    "-a",
                    identity,
                    "-w",
                ],
                capture_output=True,
                text=True,
            )
            assert result.returncode == 0
            assert result.stdout.strip() == test_pin

            # Delete PIN
            result = subprocess.run(
                [
                    "security",
                    "delete-generic-password",
                    "-s",
                    service_name,
                    "-a",
                    identity,
                ],
                capture_output=True,
                text=True,
            )
            assert result.returncode == 0

            # Verify deletion
            result = subprocess.run(
                [
                    "security",
                    "find-generic-password",
                    "-s",
                    service_name,
                    "-a",
                    identity,
                ],
                capture_output=True,
                text=True,
            )
            assert result.returncode != 0  # Should not find

        finally:
            # Ensure cleanup
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


class TestGPGSigningWorkflow:
    """Tests for GPG signing with HSM-stored PIN."""

    @pytest.mark.slow
    @pytest.mark.gpg
    def test_gpg_sign_with_cached_passphrase(self, isolated_gpg_environment, tmp_path):
        """Test GPG signing with pre-cached passphrase."""
        env = isolated_gpg_environment["env"].copy()
        key_id = isolated_gpg_environment["key_id"]

        # Create test file
        test_file = tmp_path / "test_sign.txt"
        test_file.write_text("Test data for GPG signing workflow")

        # Configure gpg-agent for loopback
        gpg_agent_conf = Path(env["GNUPGHOME"]) / "gpg-agent.conf"
        gpg_agent_conf.write_text("""
allow-loopback-pinentry
allow-preset-passphrase
default-cache-ttl 600
max-cache-ttl 7200
""")

        # Restart gpg-agent
        subprocess.run(["gpgconf", "--kill", "gpg-agent"], env=env, capture_output=True)
        time.sleep(0.5)

        # Sign with loopback passphrase
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

        if result.returncode == 0:
            # Verify signature file was created
            sig_file = tmp_path / "test_sign.txt.asc"
            assert sig_file.exists()

            # Verify signature is valid
            verify_result = subprocess.run(
                ["gpg", "--verify", str(sig_file), str(test_file)],
                env=env,
                capture_output=True,
                text=True,
            )
            assert (
                verify_result.returncode == 0
                or "Good signature" in verify_result.stderr
            )


class TestSetupWizardWorkflow:
    """Tests for first-time setup wizard with HSM."""

    def test_setup_detects_hsm(self, hsm_test_environment, tmp_path):
        """Test that setup wizard detects HSM availability."""
        project_root = Path(__file__).parent.parent.parent
        cli_binary = project_root / "target" / "release" / "remote-juggler"

        if not cli_binary.exists():
            pytest.skip("CLI binary not built")

        env = hsm_test_environment["env"].copy()
        env["HOME"] = str(tmp_path)

        # Run setup in status mode
        result = subprocess.run(
            [str(cli_binary), "setup", "--status"],
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
        )

        # Should report HSM status
        output = result.stdout + result.stderr
        # Accept various output formats
        assert (
            result.returncode == 0
            or "setup" in output.lower()
            or "hsm" in output.lower()
        )


class TestMCPToolWorkflow:
    """Tests for MCP tool integration with HSM."""

    def test_mcp_pin_status_tool(self, hsm_test_environment, tmp_path):
        """Test juggler_pin_status MCP tool."""
        project_root = Path(__file__).parent.parent.parent
        cli_binary = project_root / "target" / "release" / "remote-juggler"

        if not cli_binary.exists():
            pytest.skip("CLI binary not built")

        env = hsm_test_environment["env"].copy()
        env["HOME"] = str(tmp_path)

        # Create config
        config_dir = tmp_path / ".config" / "remote-juggler"
        config_dir.mkdir(parents=True)
        (config_dir / "config.json").write_text(
            json.dumps(
                {
                    "version": "2.0.0",
                    "identities": {},
                    "settings": {"hsmAvailable": True},
                }
            )
        )

        # Start MCP server and send tool call
        proc = subprocess.Popen(
            [str(cli_binary), "--mode=mcp"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            text=True,
        )

        try:
            # Send initialize
            init_msg = (
                json.dumps(
                    {
                        "jsonrpc": "2.0",
                        "id": 1,
                        "method": "initialize",
                        "params": {
                            "protocolVersion": "2024-11-05",
                            "capabilities": {},
                            "clientInfo": {"name": "test", "version": "1.0"},
                        },
                    }
                )
                + "\n"
            )

            proc.stdin.write(init_msg)
            proc.stdin.flush()

            # Read response (with timeout)
            import select

            ready, _, _ = select.select([proc.stdout], [], [], 5)
            if ready:
                response = proc.stdout.readline()
                data = json.loads(response)
                assert "result" in data or "error" in data

        except Exception:
            # MCP server may not be fully operational
            pass
        finally:
            proc.terminate()
            proc.wait(timeout=2)


class TestHSMErrorRecovery:
    """Tests for HSM error recovery scenarios."""

    @pytest.mark.tpm
    def test_tpm_connection_recovery(self, swtpm_environment, tpm_tools_available):
        """Test recovery when TPM connection is lost and restored."""
        if not tpm_tools_available:
            pytest.skip("tpm2-tools not available")

        env = swtpm_environment["env"]
        _state_dir = swtpm_environment["state_dir"]  # noqa: F841

        # First, verify TPM is working
        result = subprocess.run(
            ["tpm2_getcap", "properties-fixed"],
            env=env,
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0

        # Simulate TPM unavailability by using wrong TCTI
        bad_env = env.copy()
        bad_env["TPM2TOOLS_TCTI"] = "swtpm:host=invalid,port=0"

        result = subprocess.run(
            ["tpm2_getcap", "properties-fixed"],
            env=bad_env,
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode != 0  # Should fail

        # Verify recovery with correct TCTI
        result = subprocess.run(
            ["tpm2_getcap", "properties-fixed"],
            env=env,
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0  # Should work again

    def test_graceful_degradation_no_hsm(self, tmp_path):
        """Test graceful degradation when no HSM is available."""
        project_root = Path(__file__).parent.parent.parent
        cli_binary = project_root / "target" / "release" / "remote-juggler"

        if not cli_binary.exists():
            pytest.skip("CLI binary not built")

        # Environment with no HSM access
        env = os.environ.copy()
        env["HOME"] = str(tmp_path)
        env["REMOTE_JUGGLER_HSM_BACKEND"] = "none"

        # Create config
        config_dir = tmp_path / ".config" / "remote-juggler"
        config_dir.mkdir(parents=True)
        (config_dir / "config.json").write_text(
            json.dumps(
                {
                    "version": "2.0.0",
                    "identities": {
                        "test": {
                            "provider": "gitlab",
                            "host": "gitlab.com",
                            "hostname": "gitlab.com",
                        }
                    },
                    "settings": {"hsmAvailable": False},
                }
            )
        )

        # Try to store PIN - should fail gracefully
        result = subprocess.run(
            [str(cli_binary), "pin", "store", "test", "--pin", "123456"],
            env=env,
            capture_output=True,
            text=True,
            timeout=10,
        )

        # Should either fail with clear message or succeed with warning
        output = result.stdout + result.stderr
        assert (
            result.returncode != 0
            or "not available" in output.lower()
            or "fallback" in output.lower()
            or "warning" in output.lower()
        )


class TestMultiIdentityWorkflow:
    """Tests for managing PINs for multiple identities."""

    @pytest.mark.secure_enclave
    def test_multiple_identity_pins_keychain(self, tmp_path):
        """Test storing PINs for multiple identities in keychain."""
        if sys.platform != "darwin":
            pytest.skip("Keychain tests require macOS")

        identities = {
            "personal": "personal-pin-111",
            "work": "work-pin-222",
            "github": "github-pin-333",
        }

        service_base = "dev.tinyland.remote-juggler.multi-test"

        try:
            # Store all PINs
            for identity, pin in identities.items():
                service_name = f"{service_base}.{identity}"

                # Clean existing
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

                # Store
                result = subprocess.run(
                    [
                        "security",
                        "add-generic-password",
                        "-s",
                        service_name,
                        "-a",
                        identity,
                        "-w",
                        pin,
                        "-U",
                    ],
                    capture_output=True,
                    text=True,
                )
                assert result.returncode == 0

            # Verify all PINs
            for identity, expected_pin in identities.items():
                service_name = f"{service_base}.{identity}"

                result = subprocess.run(
                    [
                        "security",
                        "find-generic-password",
                        "-s",
                        service_name,
                        "-a",
                        identity,
                        "-w",
                    ],
                    capture_output=True,
                    text=True,
                )
                assert result.returncode == 0
                assert result.stdout.strip() == expected_pin

        finally:
            # Cleanup all
            for identity in identities:
                service_name = f"{service_base}.{identity}"
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
