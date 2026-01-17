/**
 * keychain_darwin.c - macOS Security.framework bindings for RemoteJuggler
 *
 * This file provides C bindings to the macOS Keychain Services API for
 * secure credential storage. Used by the Chapel Keychain module via C FFI.
 *
 * Compile with: -framework Security
 *
 * Service naming convention:
 *   Service: "remote-juggler.{provider}.{identity}" (e.g., "remote-juggler.gitlab.personal")
 *   Account: "{username}" (e.g., "xoxdjess")
 */

#include <Security/Security.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>

/**
 * Store a token in the macOS Keychain.
 *
 * If an item with the same service/account already exists, it will be updated.
 *
 * @param service       Service name (e.g., "remote-juggler.gitlab.personal")
 * @param account       Account name (e.g., "xoxdjess")
 * @param password      The token/password to store
 * @param password_len  Length of the password in bytes
 * @return              0 (errSecSuccess) on success, OSStatus error code on failure
 */
int keychain_store(const char* service, const char* account,
                   const char* password, size_t password_len) {
    if (service == NULL || account == NULL || password == NULL) {
        return errSecParam;
    }

    OSStatus status = SecKeychainAddGenericPassword(
        NULL,                              /* default keychain */
        (UInt32)strlen(service), service,  /* service name */
        (UInt32)strlen(account), account,  /* account name */
        (UInt32)password_len, password,    /* password data */
        NULL                               /* item ref (not needed) */
    );

    if (status == errSecDuplicateItem) {
        /* Item already exists - find and update it */
        SecKeychainItemRef item = NULL;
        status = SecKeychainFindGenericPassword(
            NULL,
            (UInt32)strlen(service), service,
            (UInt32)strlen(account), account,
            NULL, NULL,  /* don't need password data */
            &item
        );

        if (status == errSecSuccess && item != NULL) {
            status = SecKeychainItemModifyAttributesAndData(
                item,
                NULL,                          /* no attribute changes */
                (UInt32)password_len, password /* new password data */
            );
            CFRelease(item);
        }
    }

    return (int)status;
}

/**
 * Retrieve a token from the macOS Keychain.
 *
 * The caller is responsible for freeing the returned password buffer using free().
 *
 * @param service          Service name (e.g., "remote-juggler.gitlab.personal")
 * @param account          Account name (e.g., "xoxdjess")
 * @param password_out     Output pointer to receive allocated password buffer
 * @param password_len_out Output pointer to receive password length
 * @return                 0 (errSecSuccess) on success, OSStatus error code on failure
 */
int keychain_retrieve(const char* service, const char* account,
                      char** password_out, size_t* password_len_out) {
    if (service == NULL || account == NULL ||
        password_out == NULL || password_len_out == NULL) {
        return errSecParam;
    }

    /* Initialize outputs */
    *password_out = NULL;
    *password_len_out = 0;

    void* password_data = NULL;
    UInt32 password_len = 0;

    OSStatus status = SecKeychainFindGenericPassword(
        NULL,
        (UInt32)strlen(service), service,
        (UInt32)strlen(account), account,
        &password_len, &password_data,
        NULL  /* item ref not needed */
    );

    if (status == errSecSuccess && password_data != NULL) {
        /* Allocate buffer and copy password (add null terminator for safety) */
        *password_out = (char*)malloc(password_len + 1);
        if (*password_out == NULL) {
            SecKeychainItemFreeContent(NULL, password_data);
            return errSecAllocate;
        }

        memcpy(*password_out, password_data, password_len);
        (*password_out)[password_len] = '\0';
        *password_len_out = (size_t)password_len;

        /* Free the keychain-allocated buffer */
        SecKeychainItemFreeContent(NULL, password_data);
    }

    return (int)status;
}

/**
 * Delete a token from the macOS Keychain.
 *
 * @param service  Service name (e.g., "remote-juggler.gitlab.personal")
 * @param account  Account name (e.g., "xoxdjess")
 * @return         0 (errSecSuccess) on success, OSStatus error code on failure
 *                 errSecItemNotFound (-25300) if item doesn't exist
 */
int keychain_delete(const char* service, const char* account) {
    if (service == NULL || account == NULL) {
        return errSecParam;
    }

    SecKeychainItemRef item = NULL;
    OSStatus status = SecKeychainFindGenericPassword(
        NULL,
        (UInt32)strlen(service), service,
        (UInt32)strlen(account), account,
        NULL, NULL,  /* don't need password data */
        &item
    );

    if (status == errSecSuccess && item != NULL) {
        status = SecKeychainItemDelete(item);
        CFRelease(item);
    }

    return (int)status;
}

/**
 * Check if a token exists in the macOS Keychain.
 *
 * @param service  Service name (e.g., "remote-juggler.gitlab.personal")
 * @param account  Account name (e.g., "xoxdjess")
 * @return         0 (errSecSuccess) if exists, errSecItemNotFound (-25300) if not,
 *                 other OSStatus on error
 */
int keychain_exists(const char* service, const char* account) {
    if (service == NULL || account == NULL) {
        return errSecParam;
    }

    SecKeychainItemRef item = NULL;
    OSStatus status = SecKeychainFindGenericPassword(
        NULL,
        (UInt32)strlen(service), service,
        (UInt32)strlen(account), account,
        NULL, NULL,  /* don't need password data */
        &item
    );

    if (item != NULL) {
        CFRelease(item);
    }

    return (int)status;
}

/**
 * Get a human-readable error message for an OSStatus code.
 *
 * The caller is responsible for freeing the returned string using free().
 *
 * @param status  OSStatus error code
 * @return        Allocated string with error description, or NULL on failure
 */
char* keychain_error_message(int status) {
    CFStringRef message = SecCopyErrorMessageString((OSStatus)status, NULL);
    if (message == NULL) {
        return NULL;
    }

    CFIndex length = CFStringGetLength(message);
    CFIndex max_size = CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8) + 1;
    char* buffer = (char*)malloc(max_size);

    if (buffer != NULL) {
        if (!CFStringGetCString(message, buffer, max_size, kCFStringEncodingUTF8)) {
            free(buffer);
            buffer = NULL;
        }
    }

    CFRelease(message);
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

/* Common OSStatus values for reference:
 * errSecSuccess          =     0  - No error
 * errSecParam            = -50    - Invalid parameter
 * errSecAllocate         = -108   - Memory allocation failed
 * errSecNotAvailable     = -25291 - Keychain not available
 * errSecDuplicateItem    = -25299 - Item already exists
 * errSecItemNotFound     = -25300 - Item not found
 * errSecInteractionNotAllowed = -25308 - User interaction not allowed
 * errSecDecode           = -26275 - Unable to decode data
 * errSecAuthFailed       = -25293 - Authorization failed
 */
