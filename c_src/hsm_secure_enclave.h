/*
 * hsm_secure_enclave.h - Secure Enclave backend for HSM abstraction (macOS)
 *
 * This file provides Apple Secure Enclave support using Security.framework.
 * PINs are encrypted using ECIES with a Secure Enclave-protected key, meaning:
 * - The private key never leaves the Secure Enclave
 * - Decryption requires user authentication (Touch ID, Face ID, or password)
 * - The encrypted PIN blob is stored in the Keychain
 *
 * HARDWARE REQUIREMENTS:
 * - Mac with T1, T2, or Apple Silicon (M1+) chip
 * - iPhone/iPad with Secure Enclave (A7+)
 *
 * DEPENDENCIES:
 * - Security.framework
 * - LocalAuthentication.framework (for biometric prompts)
 *
 * COMPILE WITH:
 *   -framework Security -framework LocalAuthentication
 *
 * SECURITY MODEL:
 * 1. Generate an EC P-256 key pair in the Secure Enclave (first store)
 * 2. Public key is used for ECIES encryption
 * 3. Private key operations require user authentication
 * 4. Encrypted blob stored in Keychain with SE key reference
 *
 * KEY NAMING:
 * - Key tag: "com.remotejuggler.hsm.{identity}"
 * - Keychain service: "remote-juggler.hsm.pin"
 * - Keychain account: "{identity}"
 *
 * ACCESS CONTROL:
 * - biometryCurrentSet: Requires current biometric enrollment
 * - devicePasscode: Falls back to device passcode
 * - privateKeyUsage: Only for decryption, not export
 */

#ifndef HSM_SECURE_ENCLAVE_H
#define HSM_SECURE_ENCLAVE_H

#include "hsm.h"

#ifdef __APPLE__

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * Secure Enclave Constants
 * ============================================================================ */

/* Key tag prefix for SE keys */
#define SE_KEY_TAG_PREFIX   "com.remotejuggler.hsm."

/* Keychain service name for encrypted PIN blobs */
#define SE_KEYCHAIN_SERVICE "remote-juggler.hsm.pin"

/* Algorithm: ECIES with P-256 curve */
#define SE_KEY_TYPE         kSecAttrKeyTypeECSECPrimeRandom
#define SE_KEY_SIZE         256  /* P-256 */

/* ============================================================================
 * Secure Enclave Detection
 * ============================================================================ */

/*
 * Check if Secure Enclave is available on this device.
 *
 * Checks for:
 * 1. Hardware support (T1/T2/Apple Silicon or A7+)
 * 2. Keychain access
 * 3. Ability to create SE-protected keys
 *
 * @return  1 if Secure Enclave is available, 0 otherwise.
 */
int se_is_available(void);

/*
 * Check if biometric authentication is available.
 *
 * @return  1 if Touch ID/Face ID available, 0 otherwise (falls back to passcode).
 */
int se_has_biometry(void);

/*
 * Get the type of biometric authentication available.
 *
 * @return  "Touch ID", "Face ID", "Optic ID", "Passcode", or "None".
 */
const char* se_biometry_type(void);

/* ============================================================================
 * Secure Enclave Key Management
 * ============================================================================ */

/*
 * Generate an EC key pair in the Secure Enclave for an identity.
 *
 * Creates a P-256 key pair with:
 * - Private key stored in Secure Enclave (never extractable)
 * - Access control requiring user authentication
 * - Usable only for encryption/decryption
 *
 * If a key already exists for this identity, returns success without
 * regenerating (to avoid invalidating existing sealed data).
 *
 * @param identity      Identity name for key tag.
 * @param require_bio   If 1, require biometry (not just passcode).
 * @return              HSM_SUCCESS on success, error code on failure.
 */
HSMStatus se_create_key(const char* identity, int require_bio);

/*
 * Delete the SE key for an identity.
 *
 * Also removes any encrypted PIN blob from the Keychain.
 *
 * @param identity  Identity name for key tag.
 * @return          HSM_SUCCESS on success, HSM_ERR_KEY_NOT_FOUND if not found.
 */
HSMStatus se_delete_key(const char* identity);

/*
 * Check if an SE key exists for an identity.
 *
 * @param identity  Identity name for key tag.
 * @return          1 if key exists, 0 otherwise.
 */
int se_has_key(const char* identity);

/* ============================================================================
 * Secure Enclave Encryption Operations
 * ============================================================================ */

/*
 * Encrypt and store a PIN using Secure Enclave.
 *
 * Process:
 * 1. Create SE key if it doesn't exist
 * 2. Encrypt PIN using ECIES with SE public key
 * 3. Store encrypted blob in Keychain
 *
 * @param identity  Identity name.
 * @param pin       PIN to encrypt and store.
 * @param pin_len   Length of PIN in bytes.
 * @return          HSM_SUCCESS on success, error code on failure.
 */
HSMStatus se_encrypt_pin(const char* identity, const char* pin, size_t pin_len);

/*
 * Decrypt and retrieve a PIN from Secure Enclave.
 *
 * Process:
 * 1. Retrieve encrypted blob from Keychain
 * 2. Prompt user for authentication (Touch ID/Face ID/passcode)
 * 3. Decrypt using SE private key
 *
 * @param identity      Identity name.
 * @param pin_out       Output: Allocated buffer with decrypted PIN.
 *                      Caller must free with hsm_secure_free().
 * @param pin_len_out   Output: Length of PIN in bytes.
 * @return              HSM_SUCCESS on success, error code on failure.
 *
 * NOTE: This may display a system authentication prompt.
 */
HSMStatus se_decrypt_pin(const char* identity, char** pin_out, size_t* pin_len_out);

/*
 * Check if an encrypted PIN blob exists for an identity.
 *
 * Does not check if the SE key still exists or if decryption would succeed.
 *
 * @param identity  Identity name.
 * @return          1 if encrypted blob exists, 0 otherwise.
 */
int se_has_encrypted_pin(const char* identity);

/*
 * Delete the encrypted PIN blob for an identity.
 *
 * Does not delete the SE key (which can be reused).
 *
 * @param identity  Identity name.
 * @return          HSM_SUCCESS on success, HSM_ERR_KEY_NOT_FOUND if not found.
 */
HSMStatus se_delete_encrypted_pin(const char* identity);

/* ============================================================================
 * Authentication Context
 * ============================================================================ */

/*
 * Set a custom reason string for the authentication prompt.
 *
 * Default: "authenticate to access YubiKey PIN"
 *
 * @param reason  The reason string to display.
 */
void se_set_auth_reason(const char* reason);

/*
 * Check if authentication is required for the next decrypt operation.
 *
 * Some systems cache authentication for a short period.
 *
 * @param identity  Identity name.
 * @return          1 if auth required, 0 if cached.
 */
int se_auth_required(const char* identity);

/* ============================================================================
 * Key Tag Helpers
 * ============================================================================ */

/*
 * Get the full key tag for an identity.
 *
 * @param identity  Identity name.
 * @return          Allocated tag string (caller must free), or NULL on error.
 *                  Format: "com.remotejuggler.hsm.{identity}"
 */
char* se_get_key_tag(const char* identity);

#ifdef __cplusplus
}
#endif

#endif /* __APPLE__ */

#endif /* HSM_SECURE_ENCLAVE_H */
