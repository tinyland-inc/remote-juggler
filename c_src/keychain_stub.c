/**
 * keychain_stub.c - Stub implementation for non-Darwin platforms
 *
 * This file provides stub implementations of the keychain functions for
 * platforms that don't have macOS Security.framework (e.g., Linux, Windows).
 * All functions return appropriate error codes indicating the feature is
 * not supported.
 *
 * This allows RemoteJuggler to compile on non-Darwin platforms while
 * gracefully falling back to other credential sources (environment variables,
 * CLI-stored auth, etc.).
 */

#include <stdlib.h>
#include <stdint.h>
#include <string.h>

/* Error codes matching macOS Security.framework for consistency */
#define KEYCHAIN_ERR_NOT_AVAILABLE  -25291  /* errSecNotAvailable equivalent */
#define KEYCHAIN_ERR_PARAM          -50     /* errSecParam equivalent */

/**
 * Store a token - STUB: Not supported on this platform.
 *
 * @param service       Service name (ignored)
 * @param account       Account name (ignored)
 * @param password      The token/password (ignored)
 * @param password_len  Length of the password (ignored)
 * @return              KEYCHAIN_ERR_NOT_AVAILABLE (-25291)
 */
int keychain_store(const char* service, const char* account,
                   const char* password, size_t password_len) {
    (void)service;
    (void)account;
    (void)password;
    (void)password_len;
    return KEYCHAIN_ERR_NOT_AVAILABLE;
}

/**
 * Retrieve a token - STUB: Not supported on this platform.
 *
 * @param service          Service name (ignored)
 * @param account          Account name (ignored)
 * @param password_out     Output pointer (set to NULL)
 * @param password_len_out Output length (set to 0)
 * @return                 KEYCHAIN_ERR_NOT_AVAILABLE (-25291)
 */
int keychain_retrieve(const char* service, const char* account,
                      char** password_out, size_t* password_len_out) {
    (void)service;
    (void)account;

    if (password_out != NULL) {
        *password_out = NULL;
    }
    if (password_len_out != NULL) {
        *password_len_out = 0;
    }

    return KEYCHAIN_ERR_NOT_AVAILABLE;
}

/**
 * Delete a token - STUB: Not supported on this platform.
 *
 * @param service  Service name (ignored)
 * @param account  Account name (ignored)
 * @return         KEYCHAIN_ERR_NOT_AVAILABLE (-25291)
 */
int keychain_delete(const char* service, const char* account) {
    (void)service;
    (void)account;
    return KEYCHAIN_ERR_NOT_AVAILABLE;
}

/**
 * Check if a token exists - STUB: Not supported on this platform.
 *
 * @param service  Service name (ignored)
 * @param account  Account name (ignored)
 * @return         KEYCHAIN_ERR_NOT_AVAILABLE (-25291)
 */
int keychain_exists(const char* service, const char* account) {
    (void)service;
    (void)account;
    return KEYCHAIN_ERR_NOT_AVAILABLE;
}

/**
 * Get error message - Returns platform-specific message for stub.
 *
 * The caller is responsible for freeing the returned string using free().
 *
 * @param status  OSStatus error code
 * @return        Allocated string with error description
 */
char* keychain_error_message(int status) {
    const char* message;

    switch (status) {
        case 0:
            message = "Success";
            break;
        case KEYCHAIN_ERR_NOT_AVAILABLE:
            message = "Keychain not available: Darwin Keychain is only supported on macOS";
            break;
        case KEYCHAIN_ERR_PARAM:
            message = "Invalid parameter";
            break;
        default:
            message = "Unknown error";
            break;
    }

    size_t len = strlen(message);
    char* buffer = (char*)malloc(len + 1);
    if (buffer != NULL) {
        memcpy(buffer, message, len + 1);
    }
    return buffer;
}

/**
 * Free a string allocated by keychain_error_message.
 *
 * @param str  String to free (safe to call with NULL)
 */
void keychain_free_string(char* str) {
    if (str != NULL) {
        free(str);
    }
}
