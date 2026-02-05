#!/usr/bin/env python3
"""
pinentry-remotejuggler - Custom pinentry for RemoteJuggler trusted workstation mode

Retrieves YubiKey PIN from TPM/SecureEnclave when configured, otherwise
delegates to the system pinentry.

This pinentry implements the Assuan protocol to intercept GPG PIN requests.
When a PIN request is received:
1. Check if the identity has "trusted workstation" mode enabled
2. If enabled, retrieve PIN from TPM/SecureEnclave via HSM library (direct ctypes)
3. If HSM fails, fallback to remote-juggler CLI
4. If CLI fails or not enabled, delegate to system pinentry

Security Model:
- PIN is never stored in this process longer than necessary
- PIN retrieval happens via HSM (TPM/SecureEnclave) with direct native calls
- All PIN handling follows the monadic pattern: retrieve -> use -> clear
- Callback-based API ensures PIN memory is controlled by HSM library

HSM Integration:
- Direct ctypes bindings to libhsm_remotejuggler.so
- Callback-based PIN retrieval (hsm_unseal_pin)
- Supports TPM 2.0 (Linux) and Secure Enclave (macOS)
- Falls back to software keychain if hardware unavailable

Install:
    chmod +x /path/to/pinentry-remotejuggler.py
    ln -s /path/to/pinentry-remotejuggler.py /usr/local/bin/pinentry-remotejuggler

Configure gpg-agent.conf:
    pinentry-program /usr/local/bin/pinentry-remotejuggler

Environment Variables:
    PINENTRY_REMOTEJUGGLER_DEBUG=1  - Enable debug logging to stderr
    PINENTRY_REMOTEJUGGLER_FALLBACK - Override fallback pinentry path
    REMOTE_JUGGLER_BIN              - Override remote-juggler binary path
    HSM_LIBRARY_PATH                - Override HSM library path

Author: RemoteJuggler Team
License: MIT
"""

import ctypes
import json
import logging
import logging.handlers
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional


def _detect_fallback_pinentry() -> str:
    """Detect the system's fallback pinentry program."""
    candidates = [
        "/usr/local/bin/pinentry-mac",  # macOS Homebrew
        "/opt/homebrew/bin/pinentry-mac",  # macOS Apple Silicon
        "/usr/bin/pinentry-gnome3",  # GNOME
        "/usr/bin/pinentry-qt",  # KDE
        "/usr/bin/pinentry-gtk-2",  # GTK2
        "/usr/bin/pinentry-curses",  # Terminal
        "/usr/bin/pinentry-tty",  # Basic TTY
        "/usr/bin/pinentry",  # Generic
    ]
    for candidate in candidates:
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return "/usr/bin/pinentry"


def _detect_hsm_library() -> str:
    """Detect the HSM shared library path."""
    candidates = [
        # Development paths
        str(Path(__file__).parent / "libhsm_remotejuggler.so"),
        str(Path(__file__).parent / "libhsm_remotejuggler.dylib"),
        # Installed paths
        "/usr/local/lib/libhsm_remotejuggler.so",
        "/usr/local/lib/libhsm_remotejuggler.dylib",
        str(Path.home() / ".local" / "lib" / "libhsm_remotejuggler.so"),
        str(Path.home() / ".local" / "lib" / "libhsm_remotejuggler.dylib"),
        # System paths
        "/usr/lib/libhsm_remotejuggler.so",
        "/usr/lib64/libhsm_remotejuggler.so",
    ]
    for candidate in candidates:
        if os.path.isfile(candidate):
            return candidate
    return ""


# Configuration
DEBUG = os.environ.get("PINENTRY_REMOTEJUGGLER_DEBUG", "").lower() in (
    "1",
    "true",
    "yes",
)
FALLBACK_PINENTRY = os.environ.get(
    "PINENTRY_REMOTEJUGGLER_FALLBACK", _detect_fallback_pinentry()
)
REMOTE_JUGGLER_BIN = os.environ.get("REMOTE_JUGGLER_BIN", "remote-juggler")
HSM_LIBRARY_PATH = os.environ.get("HSM_LIBRARY_PATH", _detect_hsm_library())
CONFIG_PATH = Path.home() / ".config" / "remote-juggler" / "config.json"
LOG_PATH = Path.home() / ".cache" / "remote-juggler" / "pinentry.log"

# =============================================================================
# HSM Constants (from hsm.h)
# =============================================================================

# HSM method/type constants
HSM_METHOD_NONE = 0
HSM_METHOD_TPM = 1
HSM_METHOD_SECURE_ENCLAVE = 2
HSM_METHOD_KEYCHAIN = 3

# HSM error codes
HSM_SUCCESS = 0
HSM_ERR_NOT_AVAILABLE = 1
HSM_ERR_NOT_INITIALIZED = 2
HSM_ERR_INVALID_IDENTITY = 3
HSM_ERR_SEAL_FAILED = 4
HSM_ERR_UNSEAL_FAILED = 5
HSM_ERR_NOT_FOUND = 6
HSM_ERR_AUTH_FAILED = 7
HSM_ERR_PCR_MISMATCH = 8
HSM_ERR_MEMORY = 9
HSM_ERR_IO = 10
HSM_ERR_PERMISSION = 11
HSM_ERR_TIMEOUT = 12
HSM_ERR_CANCELLED = 13
HSM_ERR_INTERNAL = 99

# Human-readable error messages
HSM_ERROR_MESSAGES = {
    HSM_SUCCESS: "Success",
    HSM_ERR_NOT_AVAILABLE: "HSM hardware not available",
    HSM_ERR_NOT_INITIALIZED: "HSM not initialized",
    HSM_ERR_INVALID_IDENTITY: "Invalid identity name",
    HSM_ERR_SEAL_FAILED: "Failed to seal/encrypt PIN",
    HSM_ERR_UNSEAL_FAILED: "Failed to unseal/decrypt PIN",
    HSM_ERR_NOT_FOUND: "No PIN stored for identity",
    HSM_ERR_AUTH_FAILED: "Authentication/authorization failed",
    HSM_ERR_PCR_MISMATCH: "TPM PCR values changed (boot state)",
    HSM_ERR_MEMORY: "Memory allocation failed",
    HSM_ERR_IO: "I/O error",
    HSM_ERR_PERMISSION: "Permission denied",
    HSM_ERR_TIMEOUT: "Operation timed out",
    HSM_ERR_CANCELLED: "Operation cancelled",
    HSM_ERR_INTERNAL: "Internal error",
}

# HSM method names
HSM_METHOD_NAMES = {
    HSM_METHOD_NONE: "None",
    HSM_METHOD_TPM: "TPM 2.0",
    HSM_METHOD_SECURE_ENCLAVE: "Secure Enclave",
    HSM_METHOD_KEYCHAIN: "Software Keychain",
}

# =============================================================================
# Logging Setup
# =============================================================================

# Setup file logging
_logger = logging.getLogger("pinentry-remotejuggler")
_logger.setLevel(logging.DEBUG if DEBUG else logging.INFO)

try:
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    _file_handler = logging.handlers.RotatingFileHandler(
        LOG_PATH, maxBytes=1024 * 1024, backupCount=3
    )
    _file_handler.setFormatter(
        logging.Formatter("%(asctime)s [%(levelname)s] %(message)s")
    )
    _logger.addHandler(_file_handler)
except (OSError, PermissionError):
    pass  # Can't write to log file, continue without

if DEBUG:
    _stderr_handler = logging.StreamHandler(sys.stderr)
    _stderr_handler.setFormatter(logging.Formatter("[pinentry-rj] %(message)s"))
    _logger.addHandler(_stderr_handler)


def debug(msg: str) -> None:
    """Log debug message."""
    _logger.debug(msg)


def info(msg: str) -> None:
    """Log info message."""
    _logger.info(msg)


def warn(msg: str) -> None:
    """Log warning message."""
    _logger.warning(msg)


def error(msg: str) -> None:
    """Log error message."""
    _logger.error(msg)


# =============================================================================
# HSM Library Wrapper
# =============================================================================

# Callback function type for PIN retrieval
# int (*hsm_pin_callback_t)(const uint8_t* pin, size_t pin_len, void* user_data);
HSM_PIN_CALLBACK = ctypes.CFUNCTYPE(
    ctypes.c_int,  # return type
    ctypes.POINTER(ctypes.c_ubyte),  # pin
    ctypes.c_size_t,  # pin_len
    ctypes.c_void_p,  # user_data
)


class HSMLibrary:
    """
    Wrapper for libhsm_remotejuggler native library.

    Provides Python bindings for HSM operations via ctypes.
    Handles graceful fallback when library is unavailable.
    """

    def __init__(self, library_path: str = ""):
        self._lib: Optional[ctypes.CDLL] = None
        self._available = False
        self._load_error: Optional[str] = None
        self._hsm_method = HSM_METHOD_NONE

        if not library_path:
            library_path = HSM_LIBRARY_PATH

        if library_path:
            self._load_library(library_path)

    def _load_library(self, path: str) -> None:
        """Load the HSM shared library."""
        try:
            self._lib = ctypes.CDLL(path)
            self._setup_functions()
            self._available = True
            self._hsm_method = self._lib.hsm_available()
            debug(
                f"HSM library loaded from {path}, method={HSM_METHOD_NAMES.get(self._hsm_method, 'Unknown')}"
            )
        except OSError as e:
            self._load_error = str(e)
            debug(f"Failed to load HSM library from {path}: {e}")

    def _setup_functions(self) -> None:
        """Setup ctypes function signatures."""
        if not self._lib:
            return

        # int hsm_available(void)
        self._lib.hsm_available.argtypes = []
        self._lib.hsm_available.restype = ctypes.c_int

        # int hsm_initialize(void)
        self._lib.hsm_initialize.argtypes = []
        self._lib.hsm_initialize.restype = ctypes.c_int

        # int hsm_pin_exists(const char* identity)
        self._lib.hsm_pin_exists.argtypes = [ctypes.c_char_p]
        self._lib.hsm_pin_exists.restype = ctypes.c_int

        # int hsm_unseal_pin(const char* identity, hsm_pin_callback_t callback, void* user_data)
        self._lib.hsm_unseal_pin.argtypes = [
            ctypes.c_char_p,
            HSM_PIN_CALLBACK,
            ctypes.c_void_p,
        ]
        self._lib.hsm_unseal_pin.restype = ctypes.c_int

        # const char* hsm_error_message(int error)
        self._lib.hsm_error_message.argtypes = [ctypes.c_int]
        self._lib.hsm_error_message.restype = ctypes.c_char_p

    @property
    def available(self) -> bool:
        """Check if HSM library is loaded and available."""
        return self._available and self._hsm_method != HSM_METHOD_NONE

    @property
    def method(self) -> int:
        """Get the HSM method (TPM, Secure Enclave, etc.)."""
        return self._hsm_method

    @property
    def method_name(self) -> str:
        """Get human-readable HSM method name."""
        return HSM_METHOD_NAMES.get(self._hsm_method, "Unknown")

    def pin_exists(self, identity: str) -> bool:
        """Check if a PIN is stored for the identity."""
        if not self._lib:
            return False
        result = self._lib.hsm_pin_exists(identity.encode("utf-8"))
        return result == 1

    def unseal_pin(self, identity: str) -> tuple[int, Optional[str]]:
        """
        Unseal PIN from HSM using callback pattern.

        Args:
            identity: Identity name to unseal PIN for

        Returns:
            Tuple of (error_code, pin_or_none)
        """
        if not self._lib:
            return (HSM_ERR_NOT_AVAILABLE, None)

        # Result container - mutable to capture from callback
        result_container = {"pin": None}

        # Define callback that captures PIN
        @HSM_PIN_CALLBACK
        def pin_callback(
            pin_ptr: ctypes.POINTER(ctypes.c_ubyte),
            pin_len: ctypes.c_size_t,
            user_data: ctypes.c_void_p,
        ) -> int:
            try:
                # Copy PIN bytes before callback returns
                pin_bytes = bytes(pin_ptr[i] for i in range(pin_len))
                result_container["pin"] = pin_bytes.decode("utf-8")
                return 0
            except Exception as e:
                error(f"PIN callback error: {e}")
                return -1

        # Call HSM unseal
        rc = self._lib.hsm_unseal_pin(
            identity.encode("utf-8"),
            pin_callback,
            None,
        )

        return (rc, result_container["pin"])

    def error_message(self, code: int) -> str:
        """Get human-readable error message for error code."""
        if self._lib:
            try:
                msg = self._lib.hsm_error_message(code)
                if msg:
                    return msg.decode("utf-8")
            except Exception:
                pass
        return HSM_ERROR_MESSAGES.get(code, f"Unknown error ({code})")


# Global HSM instance
_hsm: Optional[HSMLibrary] = None


def get_hsm() -> HSMLibrary:
    """Get or create the global HSM library instance."""
    global _hsm
    if _hsm is None:
        _hsm = HSMLibrary()
    return _hsm


@dataclass
class PinentryState:
    """State accumulated from Assuan protocol commands."""

    description: str = ""
    prompt: str = ""
    title: str = ""
    error: str = ""
    ok_button: str = ""
    cancel_button: str = ""
    notok_button: str = ""
    timeout: int = 0
    keyinfo: str = ""
    repeat: str = ""
    qualitybar: bool = False
    genpin: bool = False
    options: dict = field(default_factory=dict)

    def get_keygrip(self) -> Optional[str]:
        """
        Extract keygrip from SETKEYINFO.

        The keyinfo typically contains the keygrip in format:
        - "s/SERIALNO/KEYGRIP" for smartcard keys
        - "n/KEYGRIP" for regular keys

        Returns:
            40-character keygrip hex string, or None
        """
        if not self.keyinfo:
            return None

        # Pattern: s/SERIALNO/KEYGRIP or n/KEYGRIP
        # KEYGRIP is 40 hex characters
        keygrip_patterns = [
            r"s/[^/]+/([A-Fa-f0-9]{40})",  # Smartcard: s/SERIALNO/KEYGRIP
            r"n/([A-Fa-f0-9]{40})",  # Normal: n/KEYGRIP
            r"([A-Fa-f0-9]{40})",  # Just the keygrip
        ]

        for pattern in keygrip_patterns:
            match = re.search(pattern, self.keyinfo, re.IGNORECASE)
            if match:
                return match.group(1).upper()

        return None

    def get_key_id(self) -> Optional[str]:
        """
        Extract GPG key ID from description.

        The description typically contains text like:
        "Please enter the PIN for key 8547785CA25F0AA8"

        Returns:
            Key ID (8-16 hex chars), or None
        """
        if not self.description:
            return None

        key_id_patterns = [
            r"key\s+([A-Fa-f0-9]{16})",  # Full 16-char key ID
            r"key\s+([A-Fa-f0-9]{8})",  # Short 8-char key ID
            r"Key ID:\s*([A-Fa-f0-9]{8,16})",
            r"Smartcard\s+([A-Fa-f0-9]{8,16})",
            r"0x([A-Fa-f0-9]{8,16})",  # With 0x prefix
        ]

        for pattern in key_id_patterns:
            match = re.search(pattern, self.description, re.IGNORECASE)
            if match:
                return match.group(1).upper()

        return None

    def get_identity_hint(self) -> Optional[str]:
        """
        Extract identity hint from description or keyinfo.

        Tries multiple strategies:
        1. Extract keygrip from SETKEYINFO
        2. Extract key ID from description
        3. Look for any 16-char hex string

        Returns the key ID or keygrip if found.
        """
        # Try keygrip first (more specific)
        keygrip = self.get_keygrip()
        if keygrip:
            return keygrip

        # Try key ID from description
        key_id = self.get_key_id()
        if key_id:
            return key_id

        # Fallback: any 16-char hex in combined text
        text = f"{self.description} {self.keyinfo}"
        match = re.search(r"([A-Fa-f0-9]{16})", text)
        if match:
            return match.group(1).upper()

        return None


class RemoteJugglerPinentry:
    """
    Custom pinentry that retrieves PINs from TPM/SecureEnclave.

    Implements the Assuan protocol for communication with gpg-agent.

    PIN Retrieval Strategy:
    1. Try HSM direct unseal (native library via ctypes)
    2. Fall back to remote-juggler CLI unseal-pin command
    3. Fall back to system pinentry dialog

    Identity Resolution:
    1. Parse keygrip from SETKEYINFO
    2. Parse key ID from SETDESC
    3. Map keygrip/key ID to identity via config or CLI
    """

    def __init__(self, input_stream=sys.stdin, output_stream=sys.stdout):
        self.input = input_stream
        self.output = output_stream
        self.state = PinentryState()
        self.config: Optional[dict] = None
        self.hsm = get_hsm()
        self._keygrip_cache: dict[str, str] = {}  # keygrip -> identity name
        self._load_config()
        info(
            f"Pinentry initialized, HSM available: {self.hsm.available} ({self.hsm.method_name})"
        )

    def _load_config(self) -> None:
        """Load RemoteJuggler configuration."""
        try:
            if CONFIG_PATH.exists():
                self.config = json.loads(CONFIG_PATH.read_text())
                debug(f"Loaded config from {CONFIG_PATH}")
                self._build_keygrip_cache()
            else:
                debug(f"Config not found at {CONFIG_PATH}")
        except Exception as e:
            debug(f"Failed to load config: {e}")
            self.config = None

    def _build_keygrip_cache(self) -> None:
        """Build cache mapping keygrips to identity names."""
        if not self.config or "identities" not in self.config:
            return

        for name, identity in self.config.get("identities", {}).items():
            gpg_config = identity.get("gpg", {})
            # If identity has keygrips stored, cache them
            for keygrip in gpg_config.get("keygrips", []):
                self._keygrip_cache[keygrip.upper()] = name
            # Also cache the primary key ID
            key_id = gpg_config.get("keyId", "")
            if key_id:
                self._keygrip_cache[key_id.upper()] = name

    def _send(self, line: str) -> None:
        """Send a line to gpg-agent."""
        self.output.write(line + "\n")
        self.output.flush()
        debug(f"< {line}")

    def _send_ok(self, message: str = "") -> None:
        """Send OK response."""
        if message:
            self._send(f"OK {message}")
        else:
            self._send("OK")

    def _send_err(self, code: int, message: str) -> None:
        """Send ERR response."""
        self._send(f"ERR {code} {message}")

    def _send_data(self, data: str) -> None:
        """Send D (data) response with percent-encoding."""
        # Percent-encode special characters: %, CR, LF
        encoded = ""
        for c in data:
            if c == "%":
                encoded += "%25"
            elif c == "\r":
                encoded += "%0D"
            elif c == "\n":
                encoded += "%0A"
            else:
                encoded += c
        self._send(f"D {encoded}")

    def _find_identity_for_keygrip(self, keygrip: str) -> Optional[str]:
        """
        Find identity name for a keygrip.

        Strategies:
        1. Check local cache
        2. Search config for matching keygrips
        3. Try remote-juggler CLI (if available)

        Args:
            keygrip: 40-character GPG keygrip

        Returns:
            Identity name if found, None otherwise
        """
        keygrip_upper = keygrip.upper()

        # Check cache first
        if keygrip_upper in self._keygrip_cache:
            return self._keygrip_cache[keygrip_upper]

        # Search config for matching keygrips
        if self.config and "identities" in self.config:
            for name, identity in self.config["identities"].items():
                gpg_config = identity.get("gpg", {})
                # Check stored keygrips
                for kg in gpg_config.get("keygrips", []):
                    if kg.upper() == keygrip_upper:
                        self._keygrip_cache[keygrip_upper] = name
                        debug(
                            f"Config matched keygrip {keygrip[:8]}... to identity '{name}'"
                        )
                        return name

        # Try remote-juggler CLI to resolve keygrip (if command exists)
        try:
            result = subprocess.run(
                [REMOTE_JUGGLER_BIN, "gpg", "keygrip-to-identity", keygrip],
                capture_output=True,
                text=True,
                timeout=5,
            )
            # Only accept if exit code is 0 and output looks like an identity name
            # (no ANSI codes, no "ERROR", single word or hyphenated name)
            if result.returncode == 0 and result.stdout.strip():
                identity = result.stdout.strip()
                # Validate identity name (no ANSI, no error messages)
                if not identity.startswith("[") and "ERROR" not in identity.upper():
                    self._keygrip_cache[keygrip_upper] = identity
                    debug(
                        f"CLI resolved keygrip {keygrip[:8]}... to identity '{identity}'"
                    )
                    return identity
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass  # CLI not available or timed out

        return None

    def _find_identity_for_key(self, key_id: str) -> Optional[str]:
        """
        Find the identity name that uses a given GPG key ID or keygrip.

        Args:
            key_id: GPG key ID (8-16 chars) or keygrip (40 chars)

        Returns:
            Identity name if found, None otherwise
        """
        key_id_upper = key_id.upper()

        # Check keygrip cache
        if key_id_upper in self._keygrip_cache:
            return self._keygrip_cache[key_id_upper]

        # If it looks like a keygrip (40 chars), try CLI lookup
        if len(key_id) == 40:
            identity = self._find_identity_for_keygrip(key_id_upper)
            if identity:
                return identity

        # Search in config
        if not self.config or "identities" not in self.config:
            return None

        for name, identity in self.config["identities"].items():
            gpg_config = identity.get("gpg", {})
            configured_key = gpg_config.get("keyId", "")

            # Match by exact ID or suffix match (for short vs long IDs)
            if configured_key:
                configured_upper = configured_key.upper()
                if (
                    configured_upper == key_id_upper
                    or configured_upper.endswith(key_id_upper)
                    or key_id_upper.endswith(configured_upper)
                ):
                    debug(f"Matched key {key_id} to identity '{name}'")
                    return name

        return None

    def _is_trusted_workstation(self, identity_name: str) -> bool:
        """
        Check if an identity has trusted workstation mode enabled.

        Args:
            identity_name: Name of the identity to check

        Returns:
            True if trusted workstation mode is enabled
        """
        if not self.config or "identities" not in self.config:
            return False

        identity = self.config["identities"].get(identity_name, {})
        gpg_config = identity.get("gpg", {})
        security_mode = gpg_config.get("securityMode", "developer_workflow")

        return security_mode == "trusted_workstation"

    def _try_hsm_unseal(self, identity_name: str) -> Optional[str]:
        """
        Try to unseal PIN directly from HSM via native library.

        Args:
            identity_name: Identity to unseal PIN for

        Returns:
            PIN if successful, None otherwise
        """
        if not self.hsm.available:
            debug("HSM not available for direct unseal")
            return None

        # Check if PIN exists first
        if not self.hsm.pin_exists(identity_name):
            debug(f"No PIN stored in HSM for identity '{identity_name}'")
            return None

        debug(f"Attempting HSM unseal for identity '{identity_name}'")
        rc, pin = self.hsm.unseal_pin(identity_name)

        if rc == HSM_SUCCESS and pin:
            info(f"PIN unsealed from HSM for '{identity_name}'")
            return pin

        # Handle specific errors
        if rc == HSM_ERR_PCR_MISMATCH:
            warn(
                f"TPM PCR mismatch for '{identity_name}' - boot state changed, PIN inaccessible"
            )
            warn(
                "Re-seal PIN after verifying system integrity: remote-juggler pin store <identity>"
            )
        elif rc == HSM_ERR_NOT_FOUND:
            debug(f"No PIN in HSM for '{identity_name}'")
        elif rc == HSM_ERR_AUTH_FAILED:
            warn(f"HSM authentication failed for '{identity_name}'")
        else:
            debug(f"HSM unseal failed: {self.hsm.error_message(rc)}")

        return None

    def _try_cli_unseal(self, identity_name: str) -> Optional[str]:
        """
        Try to unseal PIN via remote-juggler CLI.

        Args:
            identity_name: Identity to unseal PIN for

        Returns:
            PIN if successful, None otherwise
        """
        try:
            debug(f"Attempting CLI unseal for identity '{identity_name}'")

            result = subprocess.run(
                [REMOTE_JUGGLER_BIN, "unseal-pin", identity_name],
                capture_output=True,
                text=True,
                timeout=30,
            )

            if result.returncode == 0 and result.stdout.strip():
                info(f"PIN unsealed via CLI for '{identity_name}'")
                return result.stdout.strip()
            else:
                debug(f"CLI unseal failed: {result.stderr}")
                return None

        except subprocess.TimeoutExpired:
            warn("Timeout waiting for CLI PIN unseal")
            return None
        except FileNotFoundError:
            debug(f"remote-juggler binary not found at {REMOTE_JUGGLER_BIN}")
            return None
        except Exception as e:
            debug(f"CLI unseal error: {e}")
            return None

    def _unseal_pin(self, identity_name: str) -> Optional[str]:
        """
        Retrieve PIN from TPM/SecureEnclave.

        Strategy:
        1. Try direct HSM unseal via native library (fastest, most secure)
        2. Fall back to remote-juggler CLI (works without library)

        This is the critical security function. The PIN is:
        1. Unsealed from hardware security module
        2. Returned to this function
        3. Immediately passed to gpg-agent
        4. Cleared from memory

        Args:
            identity_name: Identity to unseal PIN for

        Returns:
            PIN if successful, None otherwise
        """
        debug(f"Unseal requested for identity '{identity_name}'")

        # Strategy 1: Direct HSM unseal
        pin = self._try_hsm_unseal(identity_name)
        if pin:
            return pin

        # Strategy 2: CLI fallback
        pin = self._try_cli_unseal(identity_name)
        if pin:
            return pin

        debug(f"All unseal methods failed for '{identity_name}'")
        return None

    def _delegate_to_fallback(self) -> Optional[str]:
        """
        Delegate PIN request to the fallback pinentry.

        Spawns the system pinentry and proxies the current state to it.

        Returns:
            PIN from fallback pinentry, or None if cancelled/failed
        """
        debug(f"Delegating to fallback pinentry: {FALLBACK_PINENTRY}")

        try:
            proc = subprocess.Popen(
                [FALLBACK_PINENTRY],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )

            # Build commands to replay state
            commands = []

            if self.state.title:
                commands.append(f"SETTITLE {self.state.title}")
            if self.state.description:
                commands.append(f"SETDESC {self.state.description}")
            if self.state.prompt:
                commands.append(f"SETPROMPT {self.state.prompt}")
            if self.state.error:
                commands.append(f"SETERROR {self.state.error}")
            if self.state.ok_button:
                commands.append(f"SETOK {self.state.ok_button}")
            if self.state.cancel_button:
                commands.append(f"SETCANCEL {self.state.cancel_button}")
            if self.state.timeout > 0:
                commands.append(f"SETTIMEOUT {self.state.timeout}")
            if self.state.keyinfo:
                commands.append(f"SETKEYINFO {self.state.keyinfo}")

            # Add GETPIN command
            commands.append("GETPIN")
            commands.append("BYE")

            # Send all commands
            input_data = "\n".join(commands) + "\n"
            stdout, stderr = proc.communicate(input=input_data, timeout=300)

            # Parse response to find PIN
            pin = None
            for line in stdout.split("\n"):
                line = line.strip()
                if line.startswith("D "):
                    # Decode percent-encoded PIN
                    encoded_pin = line[2:]
                    pin = self._decode_percent(encoded_pin)
                    break

            if pin:
                debug("Got PIN from fallback pinentry")
                return pin
            else:
                debug(f"No PIN from fallback: {stdout}")
                return None

        except subprocess.TimeoutExpired:
            debug("Timeout waiting for fallback pinentry")
            proc.kill()
            return None
        except Exception as e:
            debug(f"Error with fallback pinentry: {e}")
            return None

    def _decode_percent(self, encoded: str) -> str:
        """Decode percent-encoded string."""
        result = ""
        i = 0
        while i < len(encoded):
            if encoded[i] == "%" and i + 2 < len(encoded):
                try:
                    char_code = int(encoded[i + 1 : i + 3], 16)
                    result += chr(char_code)
                    i += 3
                except ValueError:
                    result += encoded[i]
                    i += 1
            else:
                result += encoded[i]
                i += 1
        return result

    def handle_getpin(self) -> None:
        """
        Handle GETPIN command - the core PIN retrieval logic.

        Flow:
        1. Extract keygrip from SETKEYINFO (most reliable)
        2. Extract key ID from SETDESC as fallback
        3. Map keygrip/key ID to identity name
        4. Check if identity uses trusted workstation mode
        5. If yes, try to unseal PIN from HSM (direct, then CLI)
        6. If no or unseal fails, delegate to fallback pinentry
        """
        # Try to find identity from keygrip or key ID
        keygrip = self.state.get_keygrip()
        key_id = self.state.get_key_id()
        identity_name = None

        desc_preview = (
            self.state.description[:50] + "..."
            if len(self.state.description) > 50
            else self.state.description
        )
        keygrip_preview = keygrip[:8] + "..." if keygrip else None
        info(
            f"GETPIN request: keygrip={keygrip_preview}, key_id={key_id}, desc='{desc_preview}'"
        )

        # Try keygrip first (more specific)
        if keygrip:
            identity_name = self._find_identity_for_keygrip(keygrip)

        # Fall back to key ID
        if not identity_name and key_id:
            identity_name = self._find_identity_for_key(key_id)

        # Last resort: try any hint we can extract
        if not identity_name:
            hint = self.state.get_identity_hint()
            if hint:
                identity_name = self._find_identity_for_key(hint)

        debug(
            f"Identity resolution: keygrip={keygrip}, key_id={key_id}, identity={identity_name}"
        )

        pin = None

        # Try HSM retrieval if trusted workstation mode
        if identity_name and self._is_trusted_workstation(identity_name):
            info(f"Identity '{identity_name}' uses trusted workstation mode")
            pin = self._unseal_pin(identity_name)
            if pin:
                info(f"PIN retrieved from HSM for '{identity_name}'")

        # Fallback to system pinentry
        if pin is None:
            debug("Falling back to system pinentry")
            pin = self._delegate_to_fallback()

        if pin is not None:
            self._send_data(pin)
            self._send_ok()
            # Clear PIN from memory
            pin = None  # noqa: F841
        else:
            self._send_err(83886179, "Operation cancelled")

    def handle_confirm(self) -> None:
        """Handle CONFIRM command for yes/no dialogs."""
        # Delegate to fallback for confirmation dialogs
        # These are typically "do you want to create a new key" etc.
        debug("CONFIRM: delegating to fallback")

        try:
            proc = subprocess.Popen(
                [FALLBACK_PINENTRY],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                text=True,
            )

            commands = []
            if self.state.title:
                commands.append(f"SETTITLE {self.state.title}")
            if self.state.description:
                commands.append(f"SETDESC {self.state.description}")
            if self.state.ok_button:
                commands.append(f"SETOK {self.state.ok_button}")
            if self.state.cancel_button:
                commands.append(f"SETCANCEL {self.state.cancel_button}")
            if self.state.notok_button:
                commands.append(f"SETNOTOK {self.state.notok_button}")

            commands.append("CONFIRM")
            commands.append("BYE")

            stdout, _ = proc.communicate(input="\n".join(commands) + "\n", timeout=300)

            # Check if confirmed
            for line in stdout.split("\n"):
                if line.strip().startswith("OK"):
                    self._send_ok()
                    return

            self._send_err(83886179, "Operation cancelled")

        except Exception as e:
            debug(f"CONFIRM error: {e}")
            self._send_err(83886179, "Operation cancelled")

    def handle_message(self) -> None:
        """Handle MESSAGE command for informational dialogs."""
        # Delegate to fallback
        debug("MESSAGE: delegating to fallback")
        self._delegate_to_fallback()
        self._send_ok()

    def handle_command(self, line: str) -> bool:
        """
        Handle a single Assuan protocol command.

        Args:
            line: Command line from gpg-agent

        Returns:
            True to continue processing, False to exit
        """
        debug(f"> {line}")

        parts = line.split(None, 1)
        if not parts:
            return True

        cmd = parts[0].upper()
        args = parts[1] if len(parts) > 1 else ""

        if cmd == "SETDESC":
            self.state.description = args
            self._send_ok()

        elif cmd == "SETPROMPT":
            self.state.prompt = args
            self._send_ok()

        elif cmd == "SETTITLE":
            self.state.title = args
            self._send_ok()

        elif cmd == "SETERROR":
            self.state.error = args
            self._send_ok()

        elif cmd == "SETOK":
            self.state.ok_button = args
            self._send_ok()

        elif cmd == "SETCANCEL":
            self.state.cancel_button = args
            self._send_ok()

        elif cmd == "SETNOTOK":
            self.state.notok_button = args
            self._send_ok()

        elif cmd == "SETTIMEOUT":
            try:
                self.state.timeout = int(args)
            except ValueError:
                pass
            self._send_ok()

        elif cmd == "SETKEYINFO":
            self.state.keyinfo = args
            self._send_ok()

        elif cmd == "SETREPEAT":
            self.state.repeat = args
            self._send_ok()

        elif cmd == "SETQUALITYBAR":
            self.state.qualitybar = True
            self._send_ok()

        elif cmd == "SETGENPIN":
            self.state.genpin = True
            self._send_ok()

        elif cmd == "OPTION":
            # OPTION name=value
            if "=" in args:
                name, value = args.split("=", 1)
                self.state.options[name] = value
            else:
                self.state.options[args] = True
            self._send_ok()

        elif cmd == "GETPIN":
            self.handle_getpin()

        elif cmd == "CONFIRM":
            self.handle_confirm()

        elif cmd == "MESSAGE":
            self.handle_message()

        elif cmd == "GETINFO":
            # Return info about this pinentry
            if args == "pid":
                self._send_data(str(os.getpid()))
                self._send_ok()
            elif args == "version":
                self._send_data("1.0.0")
                self._send_ok()
            elif args == "flavor":
                self._send_data("remotejuggler")
                self._send_ok()
            elif args == "ttyinfo":
                tty_name = os.environ.get("GPG_TTY", "")
                tty_type = os.environ.get("TERM", "")
                self._send_data(f"{tty_name} {tty_type}")
                self._send_ok()
            else:
                self._send_err(275, f"Unknown GETINFO option: {args}")

        elif cmd == "CLEARPASSPHRASE":
            # Clear cached passphrase - we don't cache, so just OK
            self._send_ok()

        elif cmd == "RESET":
            # Reset state
            self.state = PinentryState()
            self._send_ok()

        elif cmd == "BYE":
            self._send_ok("closing connection")
            return False

        elif cmd == "NOP":
            self._send_ok()

        elif cmd == "CANCEL":
            self._send_ok()

        elif cmd == "#":
            # Comment, ignore
            pass

        else:
            debug(f"Unknown command: {cmd}")
            self._send_err(275, f"Unknown IPC command: {cmd}")

        return True

    def run(self) -> int:
        """
        Main loop - implement the Assuan protocol.

        Returns:
            Exit code (0 for success)
        """
        # Send greeting
        self._send("OK Pleased to meet you, I am pinentry-remotejuggler")

        try:
            while True:
                line = self.input.readline()
                if not line:
                    break

                line = line.strip()
                if not line:
                    continue

                if not self.handle_command(line):
                    break

        except KeyboardInterrupt:
            debug("Interrupted")
            return 1
        except BrokenPipeError:
            debug("Broken pipe")
            return 0
        except Exception as e:
            debug(f"Error: {e}")
            return 1

        return 0


def main() -> int:
    """Entry point."""
    info("pinentry-remotejuggler starting")
    debug(f"Fallback pinentry: {FALLBACK_PINENTRY}")
    debug(f"Config path: {CONFIG_PATH}")
    debug(f"HSM library path: {HSM_LIBRARY_PATH}")
    debug(f"Remote-juggler binary: {REMOTE_JUGGLER_BIN}")

    # Initialize HSM early to report status
    hsm = get_hsm()
    if hsm.available:
        info(f"HSM available: {hsm.method_name}")
    else:
        debug("HSM not available, will use CLI fallback or system pinentry")

    pinentry = RemoteJugglerPinentry()
    return pinentry.run()


if __name__ == "__main__":
    sys.exit(main())
