"""
RemoteJuggler E2E Test Fixtures

Provides pytest fixtures for end-to-end testing of RemoteJuggler
identity switching, MCP protocol compliance, GPG integration,
and HSM (TPM/Secure Enclave) operations.

Fixture Hierarchy:
- Session-scoped: isolated_gpg_environment (reused across all tests)
- Function-scoped: temp_git_repo, temp_config_dir (fresh per test)
- Conditional: swtpm_environment (only on Linux with swtpm available)
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Generator, Optional, Dict, Any

import pytest


# =============================================================================
# Configuration
# =============================================================================

# Path to the RemoteJuggler binary
REMOTE_JUGGLER_BIN = os.environ.get(
    "REMOTE_JUGGLER_BIN",
    str(Path(__file__).parent.parent.parent / "target" / "release" / "remote_juggler"),
)

# Path to pinentry-remotejuggler
PINENTRY_BIN = os.environ.get(
    "PINENTRY_BIN",
    str(Path(__file__).parent.parent.parent / "pinentry" / "pinentry-remotejuggler.py"),
)

# Test GPG key parameters
TEST_GPG_KEY = {
    "name": "RemoteJuggler Test",
    "email": "test@remotejuggler.local",
    "passphrase": "test-passphrase-12345",
    "key_type": "RSA",
    "key_length": 2048,
    "expire_date": 0,  # Never expire
}


# =============================================================================
# Utility Functions
# =============================================================================


def run_juggler(
    args: list[str],
    env: Optional[dict] = None,
    cwd: Optional[Path] = None,
    input_data: Optional[str] = None,
    timeout: int = 30,
) -> subprocess.CompletedProcess:
    """Run RemoteJuggler with given arguments."""
    cmd = [REMOTE_JUGGLER_BIN] + args

    return subprocess.run(
        cmd,
        env=env or os.environ,
        cwd=cwd,
        capture_output=True,
        text=True,
        input=input_data,
        timeout=timeout,
    )


def run_mcp_request(
    request: dict,
    env: Optional[dict] = None,
    timeout: int = 10,
) -> dict:
    """Send a JSON-RPC request to RemoteJuggler MCP server."""
    request_str = json.dumps(request) + "\n"

    result = run_juggler(
        ["--mode=mcp"],
        env=env,
        input_data=request_str,
        timeout=timeout,
    )

    # Parse the response (skip any debug output on stderr)
    if result.stdout:
        for line in result.stdout.strip().split("\n"):
            try:
                return json.loads(line)
            except json.JSONDecodeError:
                continue

    return {}


def wait_for_process(proc: subprocess.Popen, timeout: int = 5) -> bool:
    """Wait for a process to be ready (e.g., listening on socket)."""
    start = time.time()
    while time.time() - start < timeout:
        if proc.poll() is not None:
            return False  # Process exited
        time.sleep(0.1)
    return True


# =============================================================================
# Git Repository Fixtures
# =============================================================================


@pytest.fixture
def temp_git_repo() -> Generator[Path, None, None]:
    """Create a temporary git repository for testing."""
    with tempfile.TemporaryDirectory() as tmpdir:
        repo_path = Path(tmpdir) / "test-repo"
        repo_path.mkdir()

        # Initialize git repo
        subprocess.run(
            ["git", "init"],
            cwd=repo_path,
            check=True,
            capture_output=True,
        )

        # Configure minimal git settings
        subprocess.run(
            ["git", "config", "user.name", "Test User"],
            cwd=repo_path,
            check=True,
            capture_output=True,
        )
        subprocess.run(
            ["git", "config", "user.email", "test@example.com"],
            cwd=repo_path,
            check=True,
            capture_output=True,
        )

        # Add a remote (using a placeholder)
        subprocess.run(
            ["git", "remote", "add", "origin", "git@gitlab-personal:test/repo.git"],
            cwd=repo_path,
            check=True,
            capture_output=True,
        )

        yield repo_path


# =============================================================================
# Configuration Fixtures
# =============================================================================


@pytest.fixture
def temp_config_dir() -> Generator[Path, None, None]:
    """Create a temporary config directory with test identities."""
    with tempfile.TemporaryDirectory() as tmpdir:
        config_dir = Path(tmpdir) / ".config" / "remote-juggler"
        config_dir.mkdir(parents=True)

        # Create test config
        config = {
            "version": "2.0.0",
            "identities": {
                "personal": {
                    "provider": "gitlab",
                    "host": "gitlab-personal",
                    "hostname": "gitlab.com",
                    "user": "personaluser",
                    "email": "personal@example.com",
                    "identityFile": "~/.ssh/id_ed25519_personal",
                },
                "work": {
                    "provider": "gitlab",
                    "host": "gitlab-work",
                    "hostname": "gitlab.com",
                    "user": "workuser",
                    "email": "work@company.com",
                    "identityFile": "~/.ssh/id_ed25519_work",
                    "gpg": {
                        "keyId": "ABCD1234",
                        "signCommits": True,
                    },
                },
                "github": {
                    "provider": "github",
                    "host": "github.com",
                    "hostname": "github.com",
                    "user": "githubuser",
                    "email": "github@example.com",
                    "identityFile": "~/.ssh/id_ed25519_github",
                },
            },
            "settings": {
                "defaultProvider": "gitlab",
                "autoDetect": True,
                "useKeychain": False,
                "gpgSign": True,
            },
        }

        config_file = config_dir / "config.json"
        config_file.write_text(json.dumps(config, indent=2))

        yield config_dir


@pytest.fixture
def temp_dir(tmp_path: Path) -> Path:
    """Alias for tmp_path for backward compatibility."""
    return tmp_path


@pytest.fixture
def juggler_env(temp_config_dir: Path) -> dict:
    """Create environment with custom config path."""
    env = os.environ.copy()
    env["HOME"] = str(temp_config_dir.parent.parent)
    env["REMOTE_JUGGLER_CONFIG"] = str(temp_config_dir / "config.json")
    return env


@pytest.fixture
def mcp_env(temp_config_dir: Path) -> dict:
    """Environment for MCP server testing."""
    env = os.environ.copy()
    env["HOME"] = str(temp_config_dir.parent.parent)
    return env


# =============================================================================
# GPG Fixtures (Session-Scoped for Performance)
# =============================================================================


@pytest.fixture(scope="session")
def isolated_gpg_environment(tmp_path_factory) -> Generator[Dict[str, Any], None, None]:
    """
    Session-wide isolated GPG environment with test keys.

    Creates a fresh GNUPGHOME with a test keypair.
    This fixture is session-scoped for performance - GPG key generation is slow.

    Returns:
        Dict containing:
        - gnupghome: Path to GNUPGHOME
        - env: Environment dict with GNUPGHOME set
        - key_id: GPG key ID
        - fingerprint: Full key fingerprint
        - email: Key email address
        - passphrase: Key passphrase
    """
    # Create isolated GNUPGHOME
    gnupghome = tmp_path_factory.mktemp("gnupghome")
    gnupghome.chmod(0o700)

    env = os.environ.copy()
    env["GNUPGHOME"] = str(gnupghome)

    # Create gpg-agent.conf to avoid TTY issues
    agent_conf = gnupghome / "gpg-agent.conf"
    agent_conf.write_text(
        "allow-loopback-pinentry\n"
        "pinentry-mode loopback\n"
        "default-cache-ttl 0\n"
        "max-cache-ttl 0\n"
    )

    # Create gpg.conf for batch mode
    gpg_conf = gnupghome / "gpg.conf"
    gpg_conf.write_text("no-tty\n" "batch\n" "pinentry-mode loopback\n")

    # Generate test key using batch mode
    key_params = f"""
%echo Generating test key
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: {TEST_GPG_KEY['name']}
Name-Email: {TEST_GPG_KEY['email']}
Expire-Date: 0
Passphrase: {TEST_GPG_KEY['passphrase']}
%commit
%echo Key generation complete
"""

    # Generate the key
    gen_result = subprocess.run(
        ["gpg", "--batch", "--gen-key"],
        input=key_params,
        env=env,
        capture_output=True,
        text=True,
        timeout=120,
    )

    if gen_result.returncode != 0:
        pytest.skip(f"Failed to generate GPG key: {gen_result.stderr}")

    # Get the key ID
    list_result = subprocess.run(
        ["gpg", "--list-keys", "--keyid-format=long", TEST_GPG_KEY["email"]],
        env=env,
        capture_output=True,
        text=True,
    )

    key_id = None
    fingerprint = None
    for line in list_result.stdout.split("\n"):
        if line.strip().startswith("pub"):
            # Extract key ID from line like "pub   rsa2048/KEYID 2024-01-01"
            parts = line.split("/")
            if len(parts) >= 2:
                key_id = parts[1].split()[0]
        elif len(line.strip()) == 40 and all(
            c in "0123456789ABCDEF" for c in line.strip()
        ):
            fingerprint = line.strip()

    if not key_id:
        pytest.skip("Could not extract GPG key ID")

    yield {
        "gnupghome": gnupghome,
        "env": env,
        "key_id": key_id,
        "fingerprint": fingerprint or key_id,
        "email": TEST_GPG_KEY["email"],
        "passphrase": TEST_GPG_KEY["passphrase"],
    }

    # Cleanup: kill gpg-agent
    subprocess.run(
        ["gpgconf", "--kill", "gpg-agent"],
        env=env,
        capture_output=True,
    )


@pytest.fixture
def gpg_env(isolated_gpg_environment: Dict[str, Any]) -> Dict[str, Any]:
    """Function-scoped access to session GPG environment."""
    return isolated_gpg_environment


# =============================================================================
# TPM Fixtures (swtpm)
# =============================================================================


@pytest.fixture
def swtpm_available() -> bool:
    """Check if swtpm is available on the system."""
    return shutil.which("swtpm") is not None


@pytest.fixture
def swtpm_environment(
    tmp_path, swtpm_available
) -> Generator[Dict[str, Any], None, None]:
    """
    Start a software TPM emulator for testing.

    Requires swtpm to be installed. On Linux:
        apt install swtpm swtpm-tools
        # or on Fedora/Rocky:
        dnf install swtpm swtpm-tools

    Returns:
        Dict containing:
        - state_dir: Path to TPM state directory
        - tcti: TPM2 TCTI connection string
        - ctrl_port: Control port number
        - server_port: Server port number
        - env: Environment with TPM2TOOLS_TCTI set
        - process: swtpm Popen object
    """
    if not swtpm_available:
        pytest.skip("swtpm not available")

    if sys.platform != "linux":
        pytest.skip("swtpm only supported on Linux")

    state_dir = tmp_path / "swtpm"
    state_dir.mkdir()

    # Find available ports
    import socket

    def find_free_port() -> int:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.bind(("", 0))
            return s.getsockname()[1]

    ctrl_port = find_free_port()
    server_port = find_free_port()

    # Start swtpm in socket mode
    proc = subprocess.Popen(
        [
            "swtpm",
            "socket",
            "--tpmstate",
            f"dir={state_dir}",
            "--tpm2",
            "--ctrl",
            f"type=tcp,port={ctrl_port}",
            "--server",
            f"type=tcp,port={server_port}",
            "--flags",
            "not-need-init",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    # Wait for swtpm to start
    time.sleep(1)

    if proc.poll() is not None:
        stderr = proc.stderr.read().decode() if proc.stderr else ""
        pytest.skip(f"swtpm failed to start: {stderr}")

    tcti = f"swtpm:host=127.0.0.1,port={server_port}"

    env = os.environ.copy()
    env["TPM2TOOLS_TCTI"] = tcti

    yield {
        "state_dir": state_dir,
        "tcti": tcti,
        "ctrl_port": ctrl_port,
        "server_port": server_port,
        "env": env,
        "process": proc,
    }

    # Cleanup
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()


@pytest.fixture
def tpm_tools_available() -> bool:
    """Check if tpm2-tools are available."""
    return shutil.which("tpm2_getcap") is not None


# =============================================================================
# Secure Enclave Fixtures (macOS only)
# =============================================================================


@pytest.fixture
def secure_enclave_available() -> bool:
    """Check if Secure Enclave is available (macOS with T2/M1+ chip)."""
    if sys.platform != "darwin":
        return False

    # Check for Secure Enclave by looking for SEP in system info
    try:
        result = subprocess.run(
            ["system_profiler", "SPiBridgeDataType"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        return "T2" in result.stdout or "Apple M" in result.stdout
    except (subprocess.SubprocessError, FileNotFoundError):
        return False


# =============================================================================
# Pinentry Fixtures
# =============================================================================


@pytest.fixture
def pinentry_available() -> bool:
    """Check if pinentry-remotejuggler is available."""
    return Path(PINENTRY_BIN).exists()


@pytest.fixture
def pinentry_test_env(
    tmp_path,
    isolated_gpg_environment: Dict[str, Any],
) -> Generator[Dict[str, Any], None, None]:
    """
    Environment for testing pinentry-remotejuggler integration.

    Sets up GPG agent with our custom pinentry.
    """
    if not Path(PINENTRY_BIN).exists():
        pytest.skip("pinentry-remotejuggler not found")

    gnupghome = tmp_path / "gnupghome-pinentry"
    gnupghome.mkdir()
    gnupghome.chmod(0o700)

    # Copy keys from session GPG environment
    shutil.copytree(
        isolated_gpg_environment["gnupghome"],
        gnupghome,
        dirs_exist_ok=True,
    )

    env = os.environ.copy()
    env["GNUPGHOME"] = str(gnupghome)

    # Configure gpg-agent to use our pinentry
    agent_conf = gnupghome / "gpg-agent.conf"
    agent_conf.write_text(
        f"pinentry-program {PINENTRY_BIN}\n"
        "allow-preset-passphrase\n"
        "default-cache-ttl 300\n"
        "max-cache-ttl 600\n"
    )

    # Restart gpg-agent with new config
    subprocess.run(
        ["gpgconf", "--kill", "gpg-agent"],
        env=env,
        capture_output=True,
    )

    yield {
        "gnupghome": gnupghome,
        "env": env,
        "pinentry": PINENTRY_BIN,
        "key_id": isolated_gpg_environment["key_id"],
        "passphrase": isolated_gpg_environment["passphrase"],
    }

    # Cleanup
    subprocess.run(
        ["gpgconf", "--kill", "gpg-agent"],
        env=env,
        capture_output=True,
    )


# =============================================================================
# HSM Test Fixtures
# =============================================================================


@pytest.fixture
def hsm_library_available() -> bool:
    """Check if the HSM C library is available."""
    lib_path = Path(__file__).parent.parent.parent / "pinentry"

    if sys.platform == "darwin":
        return (lib_path / "libhsm_remotejuggler.dylib").exists()
    else:
        return (lib_path / "libhsm_remotejuggler.so").exists()


@pytest.fixture
def hsm_test_environment(
    tmp_path,
    swtpm_environment: Optional[Dict[str, Any]],
    hsm_library_available: bool,
) -> Generator[Dict[str, Any], None, None]:
    """
    Combined HSM test environment with TPM (on Linux) or stub mode.

    Provides a unified interface for HSM testing regardless of backend.
    """
    if not hsm_library_available:
        pytest.skip("HSM library not built")

    env = os.environ.copy()
    hsm_state_dir = tmp_path / "hsm-state"
    hsm_state_dir.mkdir()

    result = {
        "state_dir": hsm_state_dir,
        "env": env,
        "backend": "stub",
    }

    if sys.platform == "linux" and swtpm_environment:
        # Use swtpm on Linux
        env["TPM2TOOLS_TCTI"] = swtpm_environment["tcti"]
        result["backend"] = "tpm"
        result["tpm"] = swtpm_environment
    elif sys.platform == "darwin":
        result["backend"] = "secure_enclave"

    yield result


# =============================================================================
# Marker Helpers
# =============================================================================


def pytest_configure(config):
    """Register custom markers."""
    config.addinivalue_line("markers", "gpg: tests requiring GPG")
    config.addinivalue_line("markers", "tpm: tests requiring TPM/swtpm")
    config.addinivalue_line("markers", "secure_enclave: tests requiring macOS SE")
    config.addinivalue_line("markers", "yubikey: tests requiring physical YubiKey")
    config.addinivalue_line("markers", "hardware: tests requiring physical hardware")
    config.addinivalue_line("markers", "e2e: end-to-end integration tests")
    config.addinivalue_line("markers", "slow: tests that take more than 10 seconds")
    config.addinivalue_line("markers", "mcp: Model Context Protocol tests")
    config.addinivalue_line("markers", "acp: Agent Context Protocol tests")
    config.addinivalue_line(
        "markers", "multi_identity: tests for concurrent identity switches"
    )
    config.addinivalue_line("markers", "installation: tests for installed binary")


# =============================================================================
# Multi-Identity Test Fixtures
# =============================================================================


@pytest.fixture
def multi_identity_repos(tmp_path) -> Generator[Dict[str, Path], None, None]:
    """
    Create 3 git repos with different identity requirements for testing
    concurrent identity switches.

    Scenario: User with 3 projects, potentially shared GPG key, different SSH keys
      - personal (GitHub personal account)
      - work (GitLab work account)
      - freelance (Bitbucket freelance client)

    Returns:
        Dict mapping identity name to repo path
    """
    repos = {}
    identities = [
        ("personal", "github.com:user/personal.git", "personal@example.com"),
        ("work", "gitlab.com:company/work.git", "work@company.com"),
        ("freelance", "bitbucket.org:client/project.git", "freelance@example.com"),
    ]

    for name, remote, email in identities:
        repo_path = tmp_path / name
        repo_path.mkdir()

        # Initialize git repo
        subprocess.run(
            ["git", "init"],
            cwd=repo_path,
            check=True,
            capture_output=True,
        )

        # Set initial config
        subprocess.run(
            ["git", "config", "user.name", f"Test {name.title()}"],
            cwd=repo_path,
            check=True,
            capture_output=True,
        )
        subprocess.run(
            ["git", "config", "user.email", email],
            cwd=repo_path,
            check=True,
            capture_output=True,
        )

        # Disable GPG signing in test repos
        subprocess.run(
            ["git", "config", "commit.gpgsign", "false"],
            cwd=repo_path,
            check=True,
            capture_output=True,
        )

        # Add remote
        subprocess.run(
            ["git", "remote", "add", "origin", f"git@{remote}"],
            cwd=repo_path,
            check=True,
            capture_output=True,
        )

        # Create initial commit
        readme = repo_path / "README.md"
        readme.write_text(f"# {name.title()} Project\n")
        subprocess.run(
            ["git", "add", "README.md"],
            cwd=repo_path,
            check=True,
            capture_output=True,
        )
        subprocess.run(
            ["git", "commit", "--no-gpg-sign", "-m", "Initial commit"],
            cwd=repo_path,
            check=True,
            capture_output=True,
        )

        repos[name] = repo_path

    yield repos


@pytest.fixture
def multi_identity_config(
    tmp_path, multi_identity_repos
) -> Generator[Dict[str, Any], None, None]:
    """
    Create config file with multiple identities matching the multi_identity_repos.
    """
    config_dir = tmp_path / ".config" / "remote-juggler"
    config_dir.mkdir(parents=True)

    config = {
        "version": "2.0.0",
        "identities": {
            "personal": {
                "provider": "github",
                "host": "github.com",
                "hostname": "github.com",
                "user": "personaluser",
                "email": "personal@example.com",
                "identityFile": "~/.ssh/id_ed25519_personal",
            },
            "work": {
                "provider": "gitlab",
                "host": "gitlab.com",
                "hostname": "gitlab.com",
                "user": "workuser",
                "email": "work@company.com",
                "identityFile": "~/.ssh/id_ed25519_work",
                "gpg": {
                    "keyId": "WORK1234",
                    "signCommits": True,
                },
            },
            "freelance": {
                "provider": "bitbucket",
                "host": "bitbucket.org",
                "hostname": "bitbucket.org",
                "user": "freelanceuser",
                "email": "freelance@example.com",
                "identityFile": "~/.ssh/id_ed25519_freelance",
            },
        },
        "settings": {
            "defaultProvider": "gitlab",
            "autoDetect": True,
            "useKeychain": False,
            "gpgSign": True,
        },
    }

    config_file = config_dir / "config.json"
    config_file.write_text(json.dumps(config, indent=2))

    env = os.environ.copy()
    env["HOME"] = str(tmp_path)
    env["REMOTE_JUGGLER_CONFIG"] = str(config_file)

    yield {
        "config_dir": config_dir,
        "config_file": config_file,
        "config": config,
        "env": env,
        "repos": multi_identity_repos,
    }


# =============================================================================
# YubiKey Mock Fixtures
# =============================================================================


@pytest.fixture
def mock_ykman(tmp_path, monkeypatch) -> Generator[Path, None, None]:
    """
    Create mock ykman that simulates YubiKey responses for CI testing.

    This allows testing YubiKey detection and configuration without
    requiring a physical YubiKey.
    """
    mock_script = tmp_path / "ykman"
    mock_script.write_text("""#!/bin/bash
# Mock ykman for CI testing
case "$1" in
    list)
        echo "YubiKey 5 NFC (12345678) [OTP+FIDO+CCID]"
        ;;
    openpgp)
        case "$2" in
            info)
                echo "OpenPGP version:            3.4"
                echo "Application version:        5.4.3"
                echo ""
                echo "PIN tries remaining:        3"
                echo "Reset code tries remaining: 0"
                echo "Admin PIN tries remaining:  3"
                echo ""
                echo "Touch policies:"
                echo "  Signature key:            Cached"
                echo "  Encryption key:           Off"
                echo "  Authentication key:       On"
                echo ""
                echo "PIN policies:"
                echo "  Signature key:            Once"
                echo "  Encryption key:           Once"
                echo "  Authentication key:       Once"
                ;;
            keys)
                case "$3" in
                    info|"")
                        echo "Signature key [SIGN]:"
                        echo "  Algorithm:      RSA4096"
                        echo "  Created:        2024-01-15 10:30:00"
                        echo "  Touch policy:   Cached"
                        echo ""
                        echo "Encryption key [ENCR]:"
                        echo "  Algorithm:      RSA4096"
                        echo "  Created:        2024-01-15 10:30:00"
                        echo "  Touch policy:   Off"
                        echo ""
                        echo "Authentication key [AUTH]:"
                        echo "  Algorithm:      RSA4096"
                        echo "  Created:        2024-01-15 10:30:00"
                        echo "  Touch policy:   On"
                        ;;
                    set-touch)
                        # Simulate touch policy change
                        echo "Touch policy updated."
                        ;;
                esac
                ;;
            access)
                case "$3" in
                    change-pin)
                        echo "PIN changed."
                        ;;
                    set-retries)
                        echo "Retry counters set."
                        ;;
                esac
                ;;
        esac
        ;;
    *)
        echo "Unknown command: $1" >&2
        exit 1
        ;;
esac
""")
    mock_script.chmod(0o755)

    # Prepend tmp_path to PATH so mock takes precedence
    old_path = os.environ.get("PATH", "")
    monkeypatch.setenv("PATH", f"{tmp_path}:{old_path}")

    yield mock_script


@pytest.fixture
def mock_ykman_no_key(tmp_path, monkeypatch) -> Generator[Path, None, None]:
    """
    Create mock ykman that simulates no YubiKey connected.
    """
    mock_script = tmp_path / "ykman"
    mock_script.write_text("""#!/bin/bash
# Mock ykman - no YubiKey connected
case "$1" in
    list)
        # Empty output - no YubiKey
        exit 0
        ;;
    *)
        echo "Error: No YubiKey detected." >&2
        exit 1
        ;;
esac
""")
    mock_script.chmod(0o755)

    old_path = os.environ.get("PATH", "")
    monkeypatch.setenv("PATH", f"{tmp_path}:{old_path}")

    yield mock_script


# =============================================================================
# Installation Test Fixtures
# =============================================================================


@pytest.fixture
def installed_binary_available() -> bool:
    """Check if remote-juggler is installed in PATH."""
    return shutil.which("remote-juggler") is not None


@pytest.fixture
def cli_binary() -> Path:
    """
    Get the path to the CLI binary, preferring installed version
    then falling back to build artifacts.
    """
    # Check if installed in PATH
    installed = shutil.which("remote-juggler")
    if installed:
        return Path(installed)

    # Fall back to build artifact
    build_path = Path(REMOTE_JUGGLER_BIN)
    if build_path.exists():
        return build_path

    pytest.skip("No remote-juggler binary found (neither installed nor in build)")
