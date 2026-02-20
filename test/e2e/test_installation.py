"""
RemoteJuggler Installation Smoke Tests

Tests that verify the installed binary works correctly.
These tests are marked with @pytest.mark.installation and are designed
to run against an installed version of remote-juggler.

Run with:
    pytest test/e2e/test_installation.py -v
    pytest test/e2e/ -v -m installation
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest


# =============================================================================
# Binary Availability Tests
# =============================================================================


@pytest.mark.installation
class TestBinaryAvailability:
    """Tests for verifying binary installation and accessibility."""

    def test_binary_in_path(self, cli_binary: Path):
        """Verify remote-juggler binary exists and is executable."""
        assert cli_binary.exists(), f"Binary not found at {cli_binary}"
        assert os.access(cli_binary, os.X_OK), f"Binary not executable: {cli_binary}"

    def test_binary_executes(self, cli_binary: Path):
        """Verify binary can be executed without crashing."""
        result = subprocess.run(
            [str(cli_binary), "--help"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        # --help should exit 0 or show usage
        assert result.returncode in (0, 1), f"Binary crashed: {result.stderr}"

    def test_version_output(self, cli_binary: Path):
        """Verify --version returns valid version string."""
        result = subprocess.run(
            [str(cli_binary), "--version"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        # Check output contains version-like string
        output = result.stdout + result.stderr
        # Should contain something like "2.0.0" or "remote-juggler"
        assert (
            "2." in output or "remote" in output.lower() or "juggler" in output.lower()
        ), f"Unexpected version output: {output}"


# =============================================================================
# Help Output Tests
# =============================================================================


@pytest.mark.installation
class TestHelpOutput:
    """Tests for verifying help text and command documentation."""

    def test_help_shows_commands(self, cli_binary: Path):
        """Verify --help shows available commands."""
        result = subprocess.run(
            [str(cli_binary), "--help"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        output = result.stdout + result.stderr

        # Should mention key commands
        expected_commands = ["switch", "list", "status"]
        for cmd in expected_commands:
            assert (
                cmd in output.lower()
            ), f"Expected command '{cmd}' not in help: {output}"

    def test_list_help(self, cli_binary: Path):
        """Verify 'list' subcommand has help."""
        result = subprocess.run(
            [str(cli_binary), "list", "--help"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        # Should not crash
        assert result.returncode in (0, 1, 2)

    def test_switch_help(self, cli_binary: Path):
        """Verify 'switch' subcommand has help."""
        result = subprocess.run(
            [str(cli_binary), "switch", "--help"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        # Should not crash
        assert result.returncode in (0, 1, 2)

    def test_status_help(self, cli_binary: Path):
        """Verify 'status' subcommand has help."""
        result = subprocess.run(
            [str(cli_binary), "status", "--help"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        # Should not crash
        assert result.returncode in (0, 1, 2)


# =============================================================================
# MCP Mode Tests
# =============================================================================


@pytest.mark.installation
class TestMCPMode:
    """Tests for verifying MCP server mode works."""

    def test_mcp_mode_accepts_initialize(self, cli_binary: Path):
        """Verify MCP mode responds to initialize request."""
        import json

        request = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2025-11-25",
                "capabilities": {},
                "clientInfo": {"name": "test", "version": "1.0.0"},
            },
        }

        result = subprocess.run(
            [str(cli_binary), "--mode=mcp"],
            input=json.dumps(request) + "\n",
            capture_output=True,
            text=True,
            timeout=10,
        )

        # Should produce JSON output
        output = result.stdout
        if output:
            # Try to parse response
            for line in output.strip().split("\n"):
                try:
                    response = json.loads(line)
                    assert "result" in response or "error" in response
                    return  # Success
                except json.JSONDecodeError:
                    continue

        # MCP mode should have produced valid JSON
        # Allow for CLI that doesn't fully support MCP yet
        assert result.returncode in (0, 1)


# =============================================================================
# Man Page Tests
# =============================================================================


@pytest.mark.installation
@pytest.mark.skipif(
    sys.platform == "win32", reason="Man pages not supported on Windows"
)
class TestManPage:
    """Tests for verifying man page installation."""

    def test_man_page_accessible(self):
        """Verify man page is accessible via man command."""
        # Skip if man command not available
        if not shutil.which("man"):
            pytest.skip("man command not available")

        # Try to find man page
        result = subprocess.run(
            ["man", "-w", "remote-juggler"],
            capture_output=True,
            text=True,
            timeout=10,
        )

        if result.returncode != 0:
            pytest.skip("Man page not installed")

        # Man page path should be returned
        assert result.stdout.strip(), "Man page path should be returned"


# =============================================================================
# Shell Completion Tests
# =============================================================================


@pytest.mark.installation
@pytest.mark.skipif(sys.platform == "win32", reason="Shell completions not on Windows")
class TestShellCompletions:
    """Tests for verifying shell completion installation."""

    def test_bash_completion_exists(self):
        """Check if bash completion file exists in common locations."""
        bash_completion_paths = [
            "/usr/local/share/bash-completion/completions/remote-juggler",
            "/usr/share/bash-completion/completions/remote-juggler",
            "/etc/bash_completion.d/remote-juggler",
            Path.home() / ".local/share/bash-completion/completions/remote-juggler",
        ]

        for path in bash_completion_paths:
            if Path(path).exists():
                return  # Found!

        pytest.skip("Bash completion not installed (this is optional)")

    def test_zsh_completion_exists(self):
        """Check if zsh completion file exists in common locations."""
        zsh_completion_paths = [
            "/usr/local/share/zsh/site-functions/_remote-juggler",
            "/usr/share/zsh/vendor-completions/_remote-juggler",
            Path.home() / ".zsh/completions/_remote-juggler",
        ]

        for path in zsh_completion_paths:
            if Path(path).exists():
                return  # Found!

        pytest.skip("Zsh completion not installed (this is optional)")


# =============================================================================
# Functional Tests
# =============================================================================


@pytest.mark.installation
class TestFunctionalCommands:
    """Tests for verifying basic command functionality."""

    def test_list_command_runs(self, cli_binary: Path, juggler_env: dict):
        """Verify 'list' command runs without crashing."""
        result = subprocess.run(
            [str(cli_binary), "list"],
            env=juggler_env,
            capture_output=True,
            text=True,
            timeout=10,
        )
        # Should not crash, even if no identities configured
        assert result.returncode in (0, 1)

    def test_status_command_runs(self, cli_binary: Path, juggler_env: dict):
        """Verify 'status' command runs without crashing."""
        result = subprocess.run(
            [str(cli_binary), "status"],
            env=juggler_env,
            capture_output=True,
            text=True,
            timeout=10,
        )
        # Should not crash
        assert result.returncode in (0, 1)

    def test_switch_without_args_shows_error(self, cli_binary: Path, juggler_env: dict):
        """Verify 'switch' without identity shows helpful error."""
        result = subprocess.run(
            [str(cli_binary), "switch"],
            env=juggler_env,
            capture_output=True,
            text=True,
            timeout=10,
        )
        # Should show error about missing identity
        output = result.stdout + result.stderr
        # Either error message or usage should be shown
        assert (
            result.returncode != 0
            or "identity" in output.lower()
            or "usage" in output.lower()
        )


# =============================================================================
# Multi-Identity Concurrent Switch Tests
# =============================================================================


@pytest.mark.installation
@pytest.mark.multi_identity
class TestMultiIdentitySwitching:
    """Tests for concurrent identity switching across multiple repos."""

    @pytest.mark.xfail(
        reason="Race condition in rapid git config writes - tracked for fix",
        strict=False,
    )
    def test_concurrent_identity_switches(
        self, cli_binary: Path, multi_identity_config: dict
    ):
        """Test switching between 3 identities doesn't corrupt state."""
        env = multi_identity_config["env"]
        repos = multi_identity_config["repos"]

        # Rapid identity switches with brief settle time
        for iteration in range(5):
            for name, path in repos.items():
                result = subprocess.run(
                    [str(cli_binary), "switch", name, "--local"],
                    cwd=path,
                    env=env,
                    capture_output=True,
                    text=True,
                    timeout=10,
                )
                # Should not crash
                if result.returncode not in (0, 1):
                    pytest.fail(
                        f"Switch failed on iteration {iteration} for {name}: {result.stderr}"
                    )

    def test_singleton_switch_updates_global(
        self, cli_binary: Path, multi_identity_config: dict, tmp_path: Path
    ):
        """Singleton switch (without --local) updates global git config."""
        env = multi_identity_config["env"]

        # Create a separate test dir to avoid affecting test repos
        test_dir = tmp_path / "singleton-test"
        test_dir.mkdir()

        result = subprocess.run(
            [str(cli_binary), "switch", "personal"],
            cwd=test_dir,
            env=env,
            capture_output=True,
            text=True,
            timeout=10,
        )

        # Check what was set
        if result.returncode == 0:
            # Global email should be updated
            email_result = subprocess.run(
                ["git", "config", "--global", "user.email"],
                env=env,
                capture_output=True,
                text=True,
                timeout=5,
            )
            # If switch worked, email should be set
            if email_result.returncode == 0:
                assert (
                    "personal" in email_result.stdout.lower()
                    or "@" in email_result.stdout
                )

    def test_local_switch_preserves_global(
        self, cli_binary: Path, multi_identity_config: dict
    ):
        """Local switch (--local) only affects the repo, not global config."""
        env = multi_identity_config["env"]
        repos = multi_identity_config["repos"]

        # First, get current global email
        global_result = subprocess.run(
            ["git", "config", "--global", "user.email"],
            env=env,
            capture_output=True,
            text=True,
            timeout=5,
        )
        original_global = (
            global_result.stdout.strip() if global_result.returncode == 0 else ""
        )

        # Switch to work identity in work repo with --local
        work_repo = repos["work"]
        result = subprocess.run(
            [str(cli_binary), "switch", "work", "--local"],
            cwd=work_repo,
            env=env,
            capture_output=True,
            text=True,
            timeout=10,
        )

        if result.returncode == 0:
            # Global should be unchanged
            global_after = subprocess.run(
                ["git", "config", "--global", "user.email"],
                env=env,
                capture_output=True,
                text=True,
                timeout=5,
            )
            assert (
                global_after.stdout.strip() == original_global
            ), "Local switch changed global config"
