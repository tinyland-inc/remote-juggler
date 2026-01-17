/**
 * Keychain.chpl - Chapel wrapper for Darwin Keychain integration
 *
 * This module provides secure credential storage for RemoteJuggler using
 * the macOS Security.framework Keychain Services on Darwin platforms.
 * On non-Darwin platforms, operations gracefully return failure.
 *
 * Service naming convention:
 *   Service: "remote-juggler.{provider}.{identity}"
 *   Account: "{username}"
 *
 * Example:
 *   Service: "remote-juggler.gitlab.personal"
 *   Account: "xoxdjess"
 *
 * Usage:
 *   use Keychain;
 *
 *   if Keychain.isDarwin() {
 *     if storeToken("gitlab", "personal", "xoxdjess", "glpat-xxx") {
 *       writeln("Token stored successfully");
 *     }
 *
 *     const (found, token) = retrieveToken("gitlab", "personal", "xoxdjess");
 *     if found {
 *       writeln("Token: ", token);
 *     }
 *   }
 */
prototype module Keychain {
  use CTypes;

  // ============================================================================
  // Platform-specific require statements
  // ============================================================================

  // On Darwin, use the Security.framework implementation
  // On other platforms, use the stub implementation
  //
  // Note: Chapel's `require` is evaluated at compile time. The compiler
  // selects which C source to use based on CHPL_TARGET_PLATFORM.
  //
  // For Darwin builds:
  //   chpl ... -s CHPL_TARGET_PLATFORM=darwin
  //   This requires -framework Security linker flag
  //
  // For non-Darwin builds:
  //   The stub implementation is used automatically

  // Require the appropriate C source based on platform
  // We require a unified keychain.c that uses preprocessor guards internally
  private module KeychainFFI {
    use CTypes;

    // Require the unified C source that handles platform detection internally
    // On Darwin, link against Security.framework (passed via Mason compopts)
    // The C code uses #ifdef __APPLE__ to select the right implementation
    require "../../c_src/keychain.h", "../../c_src/keychain.c";

    // External C function declarations
    extern proc keychain_store(
      service: c_ptrConst(c_char),
      account: c_ptrConst(c_char),
      password: c_ptrConst(c_char),
      password_len: c_size_t
    ): c_int;

    extern proc keychain_retrieve(
      service: c_ptrConst(c_char),
      account: c_ptrConst(c_char),
      password_out: c_ptr(c_ptr(c_char)),
      password_len_out: c_ptr(c_size_t)
    ): c_int;

    extern proc keychain_delete(
      service: c_ptrConst(c_char),
      account: c_ptrConst(c_char)
    ): c_int;

    extern proc keychain_exists(
      service: c_ptrConst(c_char),
      account: c_ptrConst(c_char)
    ): c_int;

    extern proc keychain_error_message(status: c_int): c_ptr(c_char);
    extern proc keychain_free_string(str: c_ptr(c_char)): void;
    extern proc keychain_is_darwin(): c_int;

    // Standard C library for memory management
    extern proc free(ptr: c_ptr(void)): void;
  }

  // ============================================================================
  // Error codes (matching macOS Security.framework values)
  // ============================================================================

  /** Success - no error */
  param ERR_SUCCESS: int(32) = 0;

  /** Invalid parameter provided */
  param ERR_PARAM: int(32) = -50;

  /** Memory allocation failed */
  param ERR_ALLOCATE: int(32) = -108;

  /** Keychain not available on this platform */
  param ERR_NOT_AVAILABLE: int(32) = -25291;

  /** Item already exists (used internally, handled by store) */
  param ERR_DUPLICATE_ITEM: int(32) = -25299;

  /** Item not found in keychain */
  param ERR_ITEM_NOT_FOUND: int(32) = -25300;

  /** User interaction required but not allowed */
  param ERR_INTERACTION_NOT_ALLOWED: int(32) = -25308;

  /** Authorization/authentication failed */
  param ERR_AUTH_FAILED: int(32) = -25293;

  // ============================================================================
  // Result types
  // ============================================================================

  /**
   * Result type for keychain operations that may fail.
   */
  record KeychainResult {
    /** Whether the operation succeeded */
    var success: bool;
    /** Error code (0 = success) */
    var errorCode: int(32);
    /** Human-readable error message (empty on success) */
    var errorMessage: string;
  }

  /**
   * Result type for token retrieval operations.
   */
  record TokenResult {
    /** Whether the token was found and retrieved */
    var found: bool;
    /** The retrieved token (empty if not found) */
    var token: string;
    /** Error code (0 = success, -25300 = not found) */
    var errorCode: int(32);
    /** Human-readable error message */
    var errorMessage: string;
  }

  // ============================================================================
  // Platform detection
  // ============================================================================

  /**
   * Check if running on Darwin (macOS).
   *
   * Keychain operations are only available on Darwin. On other platforms,
   * all keychain operations will return ERR_NOT_AVAILABLE.
   *
   * @return true if running on macOS, false otherwise
   */
  proc isDarwin(): bool {
    return KeychainFFI.keychain_is_darwin() != 0;
  }

  /**
   * Check if keychain functionality is available.
   *
   * This is equivalent to isDarwin() but provides a more descriptive name
   * for code that checks availability before attempting keychain operations.
   *
   * @return true if keychain is available, false otherwise
   */
  proc isAvailable(): bool {
    return isDarwin();
  }

  // ============================================================================
  // Service name helpers
  // ============================================================================

  /**
   * Build a keychain service name from provider and identity.
   *
   * The service name follows the convention: "remote-juggler.{provider}.{identity}"
   *
   * @param provider  Provider name (e.g., "gitlab", "github")
   * @param identity  Identity name (e.g., "personal", "work")
   * @return          Full service name (e.g., "remote-juggler.gitlab.personal")
   */
  proc buildServiceName(provider: string, identity: string): string {
    return "remote-juggler." + provider + "." + identity;
  }

  // ============================================================================
  // Low-level API (direct C function wrappers)
  // ============================================================================

  /**
   * Store a token in the keychain (low-level).
   *
   * @param service       Full service name
   * @param account       Account/username
   * @param token         Token value to store
   * @return              KeychainResult with success status and error info
   */
  proc storeTokenRaw(service: string, account: string, token: string): KeychainResult {
    if !isDarwin() {
      return new KeychainResult(
        success=false,
        errorCode=ERR_NOT_AVAILABLE,
        errorMessage="Keychain not available: only supported on macOS"
      );
    }

    const status = KeychainFFI.keychain_store(
      service.c_str(),
      account.c_str(),
      token.c_str(),
      token.numBytes: c_size_t
    );

    if status == 0 {
      return new KeychainResult(success=true, errorCode=0, errorMessage="");
    } else {
      return new KeychainResult(
        success=false,
        errorCode=status: int(32),
        errorMessage=getErrorMessage(status: int(32))
      );
    }
  }

  /**
   * Retrieve a token from the keychain (low-level).
   *
   * @param service  Full service name
   * @param account  Account/username
   * @return         TokenResult with found status, token value, and error info
   */
  proc retrieveTokenRaw(service: string, account: string): TokenResult {
    if !isDarwin() {
      return new TokenResult(
        found=false,
        token="",
        errorCode=ERR_NOT_AVAILABLE,
        errorMessage="Keychain not available: only supported on macOS"
      );
    }

    var passwordPtr: c_ptr(c_char);
    var passwordLen: c_size_t;

    const status = KeychainFFI.keychain_retrieve(
      service.c_str(),
      account.c_str(),
      c_ptrTo(passwordPtr),
      c_ptrTo(passwordLen)
    );

    if status == 0 && passwordPtr != nil {
      // Create Chapel string from C buffer
      const token = string.createCopyingBuffer(passwordPtr, passwordLen: int);

      // Free the C-allocated memory
      KeychainFFI.free(passwordPtr: c_ptr(void));

      return new TokenResult(found=true, token=token, errorCode=0, errorMessage="");
    } else {
      var errMsg = "";
      if status == ERR_ITEM_NOT_FOUND {
        errMsg = "Token not found in keychain";
      } else {
        errMsg = getErrorMessage(status: int(32));
      }

      return new TokenResult(
        found=false,
        token="",
        errorCode=status: int(32),
        errorMessage=errMsg
      );
    }
  }

  /**
   * Delete a token from the keychain (low-level).
   *
   * @param service  Full service name
   * @param account  Account/username
   * @return         KeychainResult with success status and error info
   */
  proc deleteTokenRaw(service: string, account: string): KeychainResult {
    if !isDarwin() {
      return new KeychainResult(
        success=false,
        errorCode=ERR_NOT_AVAILABLE,
        errorMessage="Keychain not available: only supported on macOS"
      );
    }

    const status = KeychainFFI.keychain_delete(
      service.c_str(),
      account.c_str()
    );

    if status == 0 {
      return new KeychainResult(success=true, errorCode=0, errorMessage="");
    } else {
      return new KeychainResult(
        success=false,
        errorCode=status: int(32),
        errorMessage=getErrorMessage(status: int(32))
      );
    }
  }

  /**
   * Check if a token exists in the keychain (low-level).
   *
   * @param service  Full service name
   * @param account  Account/username
   * @return         KeychainResult where success=true means item exists
   */
  proc tokenExistsRaw(service: string, account: string): KeychainResult {
    if !isDarwin() {
      return new KeychainResult(
        success=false,
        errorCode=ERR_NOT_AVAILABLE,
        errorMessage="Keychain not available: only supported on macOS"
      );
    }

    const status = KeychainFFI.keychain_exists(
      service.c_str(),
      account.c_str()
    );

    if status == 0 {
      return new KeychainResult(success=true, errorCode=0, errorMessage="");
    } else {
      return new KeychainResult(
        success=false,
        errorCode=status: int(32),
        errorMessage=if status == ERR_ITEM_NOT_FOUND
                     then "Token not found"
                     else getErrorMessage(status: int(32))
      );
    }
  }

  // ============================================================================
  // High-level API (convenience wrappers with service name construction)
  // ============================================================================

  /**
   * Store a token in the keychain for a provider/identity combination.
   *
   * This is the recommended high-level API for storing tokens.
   *
   * @param provider  Provider name (e.g., "gitlab", "github")
   * @param identity  Identity name (e.g., "personal", "work")
   * @param account   Account/username
   * @param token     Token value to store
   * @return          true if successful, false otherwise
   */
  proc storeToken(provider: string, identity: string,
                  account: string, token: string): bool {
    const service = buildServiceName(provider, identity);
    const result = storeTokenRaw(service, account, token);
    return result.success;
  }

  /**
   * Store a token with full result information.
   *
   * @param provider  Provider name
   * @param identity  Identity name
   * @param account   Account/username
   * @param token     Token value to store
   * @return          KeychainResult with detailed status
   */
  proc storeTokenWithResult(provider: string, identity: string,
                            account: string, token: string): KeychainResult {
    const service = buildServiceName(provider, identity);
    return storeTokenRaw(service, account, token);
  }

  /**
   * Retrieve a token from the keychain for a provider/identity combination.
   *
   * This is the recommended high-level API for retrieving tokens.
   *
   * @param provider  Provider name (e.g., "gitlab", "github")
   * @param identity  Identity name (e.g., "personal", "work")
   * @param account   Account/username
   * @return          Tuple of (found: bool, token: string)
   */
  proc retrieveToken(provider: string, identity: string,
                     account: string): (bool, string) {
    const service = buildServiceName(provider, identity);
    const result = retrieveTokenRaw(service, account);
    return (result.found, result.token);
  }

  /**
   * Retrieve a token with full result information.
   *
   * @param provider  Provider name
   * @param identity  Identity name
   * @param account   Account/username
   * @return          TokenResult with detailed status
   */
  proc retrieveTokenWithResult(provider: string, identity: string,
                               account: string): TokenResult {
    const service = buildServiceName(provider, identity);
    return retrieveTokenRaw(service, account);
  }

  /**
   * Delete a token from the keychain for a provider/identity combination.
   *
   * @param provider  Provider name (e.g., "gitlab", "github")
   * @param identity  Identity name (e.g., "personal", "work")
   * @param account   Account/username
   * @return          true if successful, false otherwise
   */
  proc deleteToken(provider: string, identity: string, account: string): bool {
    const service = buildServiceName(provider, identity);
    const result = deleteTokenRaw(service, account);
    return result.success;
  }

  /**
   * Delete a token with full result information.
   *
   * @param provider  Provider name
   * @param identity  Identity name
   * @param account   Account/username
   * @return          KeychainResult with detailed status
   */
  proc deleteTokenWithResult(provider: string, identity: string,
                             account: string): KeychainResult {
    const service = buildServiceName(provider, identity);
    return deleteTokenRaw(service, account);
  }

  /**
   * Check if a token exists in the keychain for a provider/identity combination.
   *
   * @param provider  Provider name (e.g., "gitlab", "github")
   * @param identity  Identity name (e.g., "personal", "work")
   * @param account   Account/username
   * @return          true if token exists, false otherwise
   */
  proc tokenExists(provider: string, identity: string, account: string): bool {
    const service = buildServiceName(provider, identity);
    const result = tokenExistsRaw(service, account);
    return result.success;
  }

  // ============================================================================
  // Error message handling
  // ============================================================================

  /**
   * Get a human-readable error message for an error code.
   *
   * @param errorCode  The error code to describe
   * @return           Human-readable error message
   */
  proc getErrorMessage(errorCode: int(32)): string {
    select errorCode {
      when ERR_SUCCESS do
        return "Success";
      when ERR_PARAM do
        return "Invalid parameter";
      when ERR_ALLOCATE do
        return "Memory allocation failed";
      when ERR_NOT_AVAILABLE do
        return "Keychain not available: only supported on macOS";
      when ERR_DUPLICATE_ITEM do
        return "Item already exists";
      when ERR_ITEM_NOT_FOUND do
        return "Item not found in keychain";
      when ERR_INTERACTION_NOT_ALLOWED do
        return "User interaction required but not allowed";
      when ERR_AUTH_FAILED do
        return "Authorization failed";
      otherwise {
        // Try to get message from C library
        if isDarwin() {
          const msgPtr = KeychainFFI.keychain_error_message(errorCode: c_int);
          if msgPtr != nil {
            const msg = string.createCopyingBuffer(msgPtr);
            KeychainFFI.keychain_free_string(msgPtr);
            return msg;
          }
        }
        return "Unknown error (code: " + errorCode: string + ")";
      }
    }
  }

  /**
   * Check if an error code indicates the item was not found.
   *
   * @param errorCode  The error code to check
   * @return           true if error indicates item not found
   */
  proc isNotFoundError(errorCode: int(32)): bool {
    return errorCode == ERR_ITEM_NOT_FOUND;
  }

  /**
   * Check if an error code indicates keychain is unavailable.
   *
   * @param errorCode  The error code to check
   * @return           true if error indicates keychain unavailable
   */
  proc isUnavailableError(errorCode: int(32)): bool {
    return errorCode == ERR_NOT_AVAILABLE;
  }
}
