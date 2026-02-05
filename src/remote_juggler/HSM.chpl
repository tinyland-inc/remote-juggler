/*
  HSM Module - Hardware Security Module Abstraction
  ==================================================

  Provides Chapel bindings for TPM 2.0 (Linux) and SecureEnclave (macOS)
  PIN storage operations.

  When the native HSM library is linked (via HSM_NATIVE_AVAILABLE=true),
  this module calls the real C functions. Otherwise, it falls back to
  stub implementations that provide safe error handling.

  Build Configuration:
  - With HSM: chpl -sHSM_NATIVE_AVAILABLE=true --ccflags="-Ipinentry" --ldflags="-Lpinentry -lhsm_remotejuggler"
  - Without HSM: chpl -sHSM_NATIVE_AVAILABLE=false

  :author: RemoteJuggler Team
  :version: 2.0.0
*/
prototype module HSM {
  use CTypes;

  // =========================================================================
  // Compile-time Configuration
  // =========================================================================

  /*
    Compile-time flag indicating if native HSM library is linked.
    Set via -sHSM_NATIVE_AVAILABLE=true/false at compile time.
  */
  config param HSM_NATIVE_AVAILABLE: bool = false;

  // =========================================================================
  // HSM Method Constants (matching hsm_method_t in pinentry/hsm.h)
  // =========================================================================

  /* No HSM available */
  const HSM_METHOD_NONE: c_int = 0;
  /* TPM 2.0 (Linux) - sealed to PCR state */
  const HSM_METHOD_TPM: c_int = 1;
  /* Apple Secure Enclave (macOS) - ECIES encryption */
  const HSM_METHOD_SECURE_ENCLAVE: c_int = 2;
  /* Keychain/credential store (fallback) */
  const HSM_METHOD_KEYCHAIN: c_int = 3;

  // Legacy aliases for compatibility
  const HSM_TYPE_NONE = HSM_METHOD_NONE;
  const HSM_TYPE_TPM = HSM_METHOD_TPM;
  const HSM_TYPE_SECURE_ENCLAVE = HSM_METHOD_SECURE_ENCLAVE;
  const HSM_TYPE_KEYCHAIN = HSM_METHOD_KEYCHAIN;

  // =========================================================================
  // HSM Error Constants (matching hsm_error_t in pinentry/hsm.h)
  // =========================================================================

  /* Operation completed successfully */
  const HSM_SUCCESS: c_int = 0;
  /* HSM hardware not available */
  const HSM_ERR_NOT_AVAILABLE: c_int = 1;
  /* HSM not initialized */
  const HSM_ERR_NOT_INITIALIZED: c_int = 2;
  /* Invalid identity name */
  const HSM_ERR_INVALID_IDENTITY: c_int = 3;
  /* Failed to seal/encrypt PIN */
  const HSM_ERR_SEAL_FAILED: c_int = 4;
  /* Failed to unseal/decrypt PIN */
  const HSM_ERR_UNSEAL_FAILED: c_int = 5;
  /* No PIN stored for identity */
  const HSM_ERR_NOT_FOUND: c_int = 6;
  /* Authentication/authorization failed */
  const HSM_ERR_AUTH_FAILED: c_int = 7;
  /* TPM PCR values changed (boot state) */
  const HSM_ERR_PCR_MISMATCH: c_int = 8;
  /* Memory allocation failed */
  const HSM_ERR_MEMORY: c_int = 9;
  /* I/O error */
  const HSM_ERR_IO: c_int = 10;
  /* Permission denied */
  const HSM_ERR_PERMISSION: c_int = 11;
  /* Operation timed out */
  const HSM_ERR_TIMEOUT: c_int = 12;
  /* Operation cancelled by user */
  const HSM_ERR_CANCELLED: c_int = 13;
  /* Internal error */
  const HSM_ERR_INTERNAL: c_int = 99;

  // =========================================================================
  // Native C Bindings - Conditional Submodule Pattern
  // =========================================================================
  //
  // Chapel extern declarations must be at module scope to be visible.
  // We use a private submodule that's conditionally compiled based on
  // HSM_NATIVE_AVAILABLE. The wrapper functions use param-conditional
  // dispatch to call the appropriate implementation.
  //
  // When HSM_NATIVE_AVAILABLE=false, the NativeBindings module is not
  // compiled (the 'use' statement inside param-if is eliminated).
  // =========================================================================

  /*
    Private submodule containing native C bindings.
    Only compiled and linked when HSM_NATIVE_AVAILABLE=true.
  */
  private module NativeBindings {
    use CTypes;
    require "hsm.h";

    // HSM detection and availability
    extern "hsm_available" proc c_hsm_available(): c_int;
    extern "hsm_initialize" proc c_hsm_initialize(): c_int;

    // PIN storage operations
    extern "hsm_seal_pin" proc c_hsm_seal_pin(identity: c_ptrConst(c_char),
                                               pin: c_ptrConst(c_uchar),
                                               pin_len: c_size_t): c_int;

    extern "hsm_pin_exists" proc c_hsm_pin_exists(identity: c_ptrConst(c_char)): c_int;
    extern "hsm_clear_pin" proc c_hsm_clear_pin(identity: c_ptrConst(c_char)): c_int;
    extern "hsm_clear_all" proc c_hsm_clear_all(): c_int;

    // Memory management
    extern "hsm_free" proc c_hsm_free(ptr: c_ptr(void)): void;

    // Error handling
    extern "hsm_error_message" proc c_hsm_error_message(error: c_int): c_ptrConst(c_char);

    // Configuration
    extern "hsm_tpm_set_pcr_binding" proc c_hsm_tpm_set_pcr_binding(pcr_mask: c_uint): c_int;
    extern "hsm_se_set_biometric" proc c_hsm_se_set_biometric(require_biometric: c_int): c_int;

    // Callback type for PIN retrieval
    extern "hsm_unseal_pin" proc c_hsm_unseal_pin(identity: c_ptrConst(c_char),
                                                   callback: c_fn_ptr,
                                                   user_data: c_ptr(void)): c_int;
  }

  // =========================================================================
  // HSM Public API
  // =========================================================================

  /*
    Check if native HSM support is compiled in.

    :returns: true if native HSM library is linked
  */
  proc hsmIsNativeAvailable(): bool {
    return HSM_NATIVE_AVAILABLE;
  }

  /*
    Detect the best available HSM backend.

    :returns: HSM method constant
  */
  proc hsm_detect_available(): c_int {
    param useNative = HSM_NATIVE_AVAILABLE;
    if useNative {
      use NativeBindings;
      return c_hsm_available();
    } else {
      // Stub: Return keychain fallback (software)
      return HSM_METHOD_KEYCHAIN;
    }
  }

  /*
    Check if any HSM backend is available.

    :returns: 1 if available, 0 otherwise
  */
  proc hsm_is_available(): c_int {
    return if hsm_detect_available() != HSM_METHOD_NONE then 1:c_int else 0:c_int;
  }

  /*
    Initialize the HSM subsystem.

    Must be called before seal/unseal operations.

    :returns: HSM_SUCCESS or error code
  */
  proc hsmInitialize(): c_int {
    param useNative = HSM_NATIVE_AVAILABLE;
    if useNative {
      use NativeBindings;
      return c_hsm_initialize();
    } else {
      // Stub: Always succeeds
      return HSM_SUCCESS;
    }
  }

  /*
    Get human-readable name for HSM method.

    :arg hsmMethod: HSM method constant
    :returns: Description string
  */
  proc hsm_type_name(hsmMethod: c_int): string {
    select hsmMethod {
      when HSM_METHOD_NONE do return "None";
      when HSM_METHOD_TPM do return "TPM 2.0";
      when HSM_METHOD_SECURE_ENCLAVE do return "Secure Enclave";
      when HSM_METHOD_KEYCHAIN do return "Keychain";
      otherwise do return "Unknown";
    }
  }

  /*
    Store a PIN securely using the HSM.

    :arg identity: Identity name (e.g., "personal", "work")
    :arg pin: PIN string to store
    :arg pin_len: Length of PIN
    :returns: Status code
  */
  proc hsm_store_pin(identity: string, pin: string, pin_len: int): c_int {
    param useNative = HSM_NATIVE_AVAILABLE;
    if useNative {
      use NativeBindings;
      return c_hsm_seal_pin(identity.c_str(),
                            pin.c_str(): c_ptrConst(c_uchar),
                            pin_len: c_size_t);
    } else {
      // Stub: HSM not available, return error
      // In production, this would fall back to keychain storage
      return HSM_ERR_NOT_AVAILABLE;
    }
  }

  /*
    Check if a PIN is stored for an identity.

    :arg identity: Identity name
    :returns: 1 if stored, 0 otherwise, -1 on error
  */
  proc hsm_has_pin(identity: string): c_int {
    param useNative = HSM_NATIVE_AVAILABLE;
    if useNative {
      use NativeBindings;
      return c_hsm_pin_exists(identity.c_str());
    } else {
      // Stub: No PINs stored
      return 0:c_int;
    }
  }

  /*
    Clear a stored PIN.

    :arg identity: Identity name
    :returns: Status code
  */
  proc hsm_clear_pin(identity: string): c_int {
    param useNative = HSM_NATIVE_AVAILABLE;
    if useNative {
      use NativeBindings;
      return c_hsm_clear_pin(identity.c_str());
    } else {
      // Stub: Nothing to clear
      return HSM_SUCCESS;
    }
  }

  /*
    Clear all stored PINs.

    :returns: Status code
  */
  proc hsmClearAll(): c_int {
    param useNative = HSM_NATIVE_AVAILABLE;
    if useNative {
      use NativeBindings;
      return c_hsm_clear_all();
    } else {
      // Stub: Nothing to clear
      return HSM_SUCCESS;
    }
  }

  /*
    Get error message for status code.

    :arg status: Status code
    :returns: Error message
  */
  proc hsm_error_message(status: c_int): string {
    param useNative = HSM_NATIVE_AVAILABLE;
    if useNative {
      use NativeBindings;
      var cMsg = c_hsm_error_message(status);
      if cMsg != nil then
        return string.createCopyingBuffer(cMsg);
    }

    // Fallback error messages (or when native not available)
    select status {
      when HSM_SUCCESS do return "Success";
      when HSM_ERR_NOT_AVAILABLE do return "HSM hardware not available";
      when HSM_ERR_NOT_INITIALIZED do return "HSM not initialized";
      when HSM_ERR_INVALID_IDENTITY do return "Invalid identity name";
      when HSM_ERR_SEAL_FAILED do return "Failed to seal PIN";
      when HSM_ERR_UNSEAL_FAILED do return "Failed to unseal PIN";
      when HSM_ERR_NOT_FOUND do return "No PIN stored for identity";
      when HSM_ERR_AUTH_FAILED do return "Authentication failed";
      when HSM_ERR_PCR_MISMATCH do return "Platform state changed";
      when HSM_ERR_MEMORY do return "Memory allocation failed";
      when HSM_ERR_IO do return "I/O error";
      when HSM_ERR_PERMISSION do return "Permission denied";
      when HSM_ERR_TIMEOUT do return "Operation timed out";
      when HSM_ERR_CANCELLED do return "Operation cancelled";
      when HSM_ERR_INTERNAL do return "Internal error";
      otherwise do return "Unknown error";
    }
  }

  /*
    Configure TPM PCR binding (Linux only).

    :arg pcrMask: Bitmask of PCR indices to bind to
    :returns: Status code
  */
  proc hsmSetPcrBinding(pcrMask: uint(32)): c_int {
    param useNative = HSM_NATIVE_AVAILABLE;
    if useNative {
      use NativeBindings;
      return c_hsm_tpm_set_pcr_binding(pcrMask: c_uint);
    } else {
      return HSM_ERR_NOT_AVAILABLE;
    }
  }

  /*
    Configure Secure Enclave biometric requirement (macOS only).

    :arg requireBiometric: true to require Touch ID
    :returns: Status code
  */
  proc hsmSetBiometric(requireBiometric: bool): c_int {
    param useNative = HSM_NATIVE_AVAILABLE;
    if useNative {
      use NativeBindings;
      return c_hsm_se_set_biometric(if requireBiometric then 1:c_int else 0:c_int);
    } else {
      return HSM_ERR_NOT_AVAILABLE;
    }
  }

  // =========================================================================
  // PIN Retrieval with Callback (Advanced API)
  // =========================================================================

  /*
    PIN retrieval requires a callback pattern in the native library
    to ensure the PIN is cleared from memory after use.

    For Chapel usage, we provide a simpler interface that retrieves
    the PIN into a Chapel string. The caller is responsible for
    not persisting the PIN longer than necessary.
  */

  // Internal state for PIN retrieval callback
  private var _retrievedPin: string;
  private var _retrievedPinLen: int;
  private var _retrieveSuccess: bool;

  /*
    Internal callback function for PIN retrieval.
    This is called by the C library with the decrypted PIN.
  */
  export proc _hsmPinRetrieveCallback(pin: c_ptrConst(c_uchar),
                                       pin_len: c_size_t,
                                       user_data: c_ptr(void)): c_int {
    if pin != nil && pin_len > 0 {
      // Copy PIN to Chapel string
      _retrievedPin = string.createCopyingBuffer(pin: c_ptrConst(c_char),
                                                  pin_len: int);
      _retrievedPinLen = pin_len: int;
      _retrieveSuccess = true;
      return 0;
    }
    _retrieveSuccess = false;
    return 1;
  }

  /*
    Retrieve a stored PIN.

    Note: This uses an internal callback to get the PIN from the native
    library. The PIN should be used immediately and not stored.

    :arg identity: Identity name
    :returns: (status, pin) tuple
  */
  proc hsm_retrieve_pin(identity: string): (c_int, string) {
    param useNative = HSM_NATIVE_AVAILABLE;
    if useNative {
      use NativeBindings;
      // Reset state
      _retrievedPin = "";
      _retrievedPinLen = 0;
      _retrieveSuccess = false;

      // Call native unseal with our callback
      // Note: This is a simplified approach. For production, you might
      // want a more sophisticated callback mechanism.
      var status = c_hsm_unseal_pin(identity.c_str(),
                                     c_ptrTo(_hsmPinRetrieveCallback): c_fn_ptr,
                                     nil);

      if status == HSM_SUCCESS && _retrieveSuccess {
        var pin = _retrievedPin;
        // Clear internal state
        _retrievedPin = "";
        return (HSM_SUCCESS, pin);
      } else {
        return (status, "");
      }
    } else {
      // Stub: No PIN available
      return (HSM_ERR_NOT_AVAILABLE, "");
    }
  }

  /*
    Securely free memory containing sensitive data.
    In Chapel, this is primarily a no-op as we use managed memory,
    but it calls the native secure_free when available.
  */
  proc hsm_secure_free(ptr: c_ptr(void), len: c_size_t): void {
    param useNative = HSM_NATIVE_AVAILABLE;
    if useNative {
      use NativeBindings;
      // The native library doesn't have a secure_free with length,
      // but we can use hsm_free
      c_hsm_free(ptr);
    }
    // In Chapel, memory is managed - no explicit action needed
  }

  // =========================================================================
  // Convenience Functions
  // =========================================================================

  /*
    Get a human-readable status string for the HSM subsystem.

    :returns: Status description
  */
  proc hsmStatusString(): string {
    var method = hsm_detect_available();
    var methodName = hsm_type_name(method);

    if HSM_NATIVE_AVAILABLE {
      return "HSM: " + methodName + " (native library linked)";
    } else {
      return "HSM: " + methodName + " (stub mode - native library not linked)";
    }
  }

  /*
    Check if HSM is in stub mode (no real hardware protection).

    :returns: true if using stub/software-only implementation
  */
  proc hsmIsStubMode(): bool {
    if !HSM_NATIVE_AVAILABLE {
      return true;
    }
    // Even with native library, keychain is considered "stub" level security
    return hsm_detect_available() == HSM_METHOD_KEYCHAIN;
  }
}
