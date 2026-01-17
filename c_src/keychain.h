/*
 * keychain.h - Platform-unified keychain wrapper for RemoteJuggler
 *
 * Provides a consistent interface for secure credential storage across platforms:
 * - macOS: Uses Security.framework Keychain Services
 * - Other platforms: Stub implementation that returns "not available"
 */

#ifndef KEYCHAIN_H
#define KEYCHAIN_H

#include <stddef.h>

/*
 * Store a credential in the system keychain.
 *
 * @param service       Service name (e.g., "remote-juggler.gitlab.personal")
 * @param account       Account name (e.g., "xoxdjess")
 * @param password      The credential to store
 * @param password_len  Length of the credential in bytes
 * @return              0 on success, error code on failure
 */
int keychain_store(const char* service, const char* account,
                   const char* password, size_t password_len);

/*
 * Retrieve a credential from the system keychain.
 *
 * @param service          Service name
 * @param account          Account name
 * @param password_out     Output: allocated buffer with credential (caller must free)
 * @param password_len_out Output: length of credential
 * @return                 0 on success, error code on failure
 */
int keychain_retrieve(const char* service, const char* account,
                      char** password_out, size_t* password_len_out);

/*
 * Delete a credential from the system keychain.
 *
 * @param service  Service name
 * @param account  Account name
 * @return         0 on success, error code on failure
 */
int keychain_delete(const char* service, const char* account);

/*
 * Check if a credential exists in the system keychain.
 *
 * @param service  Service name
 * @param account  Account name
 * @return         0 if exists, error code otherwise
 */
int keychain_exists(const char* service, const char* account);

/*
 * Get a human-readable error message for an error code.
 *
 * @param status  Error code
 * @return        Allocated string (caller must free with keychain_free_string)
 */
char* keychain_error_message(int status);

/*
 * Free a string allocated by keychain_error_message.
 *
 * @param str  String to free (safe to call with NULL)
 */
void keychain_free_string(char* str);

/*
 * Check if running on Darwin/macOS.
 *
 * @return  1 if Darwin, 0 otherwise
 */
int keychain_is_darwin(void);

#endif /* KEYCHAIN_H */
