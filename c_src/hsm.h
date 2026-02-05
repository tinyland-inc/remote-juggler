/*
 * hsm.h - Hardware Security Module abstraction for RemoteJuggler
 *
 * Provides a unified API for secure PIN storage across platforms:
 * - Linux: Uses TPM 2.0 (tpm2-tss ESAPI) with PCR binding
 * - macOS: Uses Secure Enclave (Security.framework) with ECIES
 * - Fallback: Uses Keychain storage (less secure, but available)
 *
 * The PIN is used for YubiKey OpenPGP operations and is identity-scoped,
 * meaning each identity (e.g., "personal", "work") has its own sealed PIN.
 *
 * SECURITY PROPERTIES:
 * - PIN is never stored in plaintext on disk
 * - TPM: PIN sealed to PCR 7 (Secure Boot state) - unsealing fails if boot chain changes
 * - Secure Enclave: PIN encrypted with SE-protected ECIES key - requires biometric/password
 * - Keychain: PIN stored in system keychain - protected by login password
 *
 * IMPORTANT: PIN values must never be logged, printed, or stored in memory longer than necessary.
 * Always use hsm_secure_free() to zero and free PIN buffers after use.
 */

#ifndef HSM_H
#define HSM_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * HSM operation status codes.
 * Negative values indicate errors, zero indicates success.
 */
typedef enum {
    HSM_SUCCESS           =  0,   /* Operation completed successfully */
    HSM_ERR_NOT_AVAILABLE = -1,   /* No HSM backend available on this platform */
    HSM_ERR_SEAL_FAILED   = -2,   /* Failed to seal/encrypt the PIN */
    HSM_ERR_UNSEAL_FAILED = -3,   /* Failed to unseal/decrypt the PIN (PCR mismatch, auth failure) */
    HSM_ERR_KEY_NOT_FOUND = -4,   /* HSM key for identity not found (never stored or deleted) */
    HSM_ERR_AUTH_FAILED   = -5,   /* Authentication/authorization failed (wrong password, biometric) */
    HSM_ERR_INVALID_PARAM = -6,   /* Invalid parameter (NULL pointer, empty string, etc.) */
    HSM_ERR_MEMORY        = -7,   /* Memory allocation failed */
    HSM_ERR_TPM_DEVICE    = -8,   /* TPM device not accessible (/dev/tpmrm0) */
    HSM_ERR_SE_NOT_READY  = -9,   /* Secure Enclave not ready or locked */
    HSM_ERR_PCR_MISMATCH  = -10,  /* TPM PCR values changed (boot chain modified) */
    HSM_ERR_IO            = -11,  /* I/O error during HSM operation */
    HSM_ERR_INTERNAL      = -12   /* Internal/unexpected error */
} HSMStatus;

/*
 * HSM backend types, in order of security preference.
 * Detection will prefer TPM on Linux and SecureEnclave on macOS.
 */
typedef enum {
    HSM_TYPE_NONE           = 0,  /* No HSM available */
    HSM_TYPE_TPM            = 1,  /* TPM 2.0 (Linux) - sealed to PCR 7 */
    HSM_TYPE_SECURE_ENCLAVE = 2,  /* Apple Secure Enclave (macOS) - ECIES encryption */
    HSM_TYPE_KEYCHAIN       = 3   /* Keychain/credential store (fallback) - less secure */
} HSMType;

/* ============================================================================
 * HSM Detection and Availability
 * ============================================================================ */

/*
 * Detect the best available HSM backend on this platform.
 *
 * Detection priority:
 * - Linux: TPM 2.0 (/dev/tpmrm0) > Keychain (libsecret/GNOME Keyring)
 * - macOS: Secure Enclave (T1/T2/M1+) > Keychain (Security.framework)
 *
 * @return  The HSM type that will be used for PIN operations.
 *          Returns HSM_TYPE_NONE if no backend is available.
 */
HSMType hsm_detect_available(void);

/*
 * Check if any HSM backend is available.
 *
 * @return  1 if an HSM is available, 0 otherwise.
 */
int hsm_is_available(void);

/*
 * Get a human-readable name for an HSM type.
 *
 * @param type  The HSM type to describe.
 * @return      Static string (do not free) describing the type.
 */
const char* hsm_type_name(HSMType type);

/*
 * Get the currently active HSM type.
 * This is cached after first detection.
 *
 * @return  The HSM type in use.
 */
HSMType hsm_get_type(void);

/* ============================================================================
 * PIN Storage Operations (Identity-Scoped)
 * ============================================================================ */

/*
 * Store a PIN securely using the available HSM.
 *
 * The PIN is sealed/encrypted using the HSM and can only be retrieved on the
 * same device under the same security conditions:
 * - TPM: Same boot chain (PCR 7 values)
 * - Secure Enclave: Same user authentication
 * - Keychain: Same login session
 *
 * If a PIN already exists for this identity, it will be replaced.
 *
 * @param identity  The identity name (e.g., "personal", "work"). Must not be NULL or empty.
 * @param pin       The PIN to store. Must not be NULL.
 * @param pin_len   Length of the PIN in bytes. Must be > 0.
 * @return          HSM_SUCCESS on success, error code on failure.
 *
 * SECURITY: The PIN is copied internally; the caller can securely erase their copy
 * after this function returns.
 */
HSMStatus hsm_store_pin(const char* identity, const char* pin, size_t pin_len);

/*
 * Retrieve a previously stored PIN.
 *
 * The PIN is unsealed/decrypted using the HSM. This may require user interaction:
 * - TPM: None (automatic if PCRs match)
 * - Secure Enclave: Touch ID, Face ID, or password prompt
 * - Keychain: May prompt for keychain password
 *
 * @param identity     The identity name. Must not be NULL or empty.
 * @param pin_out      Output: Allocated buffer containing the PIN. Caller must free
 *                     using hsm_secure_free() to ensure secure memory erasure.
 * @param pin_len_out  Output: Length of the PIN in bytes.
 * @return             HSM_SUCCESS on success, error code on failure.
 *
 * SECURITY: Always use hsm_secure_free(pin_out, *pin_len_out) when done with the PIN.
 */
HSMStatus hsm_retrieve_pin(const char* identity, char** pin_out, size_t* pin_len_out);

/*
 * Clear/delete a stored PIN for an identity.
 *
 * This removes both the sealed PIN blob and any associated HSM key material.
 *
 * @param identity  The identity name. Must not be NULL or empty.
 * @return          HSM_SUCCESS on success, HSM_ERR_KEY_NOT_FOUND if not stored,
 *                  other error code on failure.
 */
HSMStatus hsm_clear_pin(const char* identity);

/*
 * Check if a PIN is stored for an identity.
 *
 * This only checks for existence; it does not attempt to unseal the PIN.
 *
 * @param identity  The identity name. Must not be NULL or empty.
 * @return          1 if a PIN is stored, 0 otherwise.
 */
int hsm_has_pin(const char* identity);

/* ============================================================================
 * Memory Management
 * ============================================================================ */

/*
 * Securely free memory containing sensitive data.
 *
 * This function zeros the memory before freeing it, preventing sensitive data
 * from lingering in freed memory. Use this for all PIN buffers.
 *
 * @param ptr  Pointer to memory to free. Safe to call with NULL.
 * @param len  Length of the memory region in bytes.
 *
 * IMPORTANT: Always use this instead of free() for PIN data!
 */
void hsm_secure_free(void* ptr, size_t len);

/* ============================================================================
 * Error Handling
 * ============================================================================ */

/*
 * Get a human-readable error message for an HSM status code.
 *
 * @param status  The HSM status code.
 * @return        Static string (do not free) describing the error.
 */
const char* hsm_error_message(HSMStatus status);

/* ============================================================================
 * Platform Detection (for conditional compilation in callers)
 * ============================================================================ */

/*
 * Check if running on Linux with TPM 2.0 support compiled in.
 *
 * @return  1 if TPM support is compiled in, 0 otherwise.
 */
int hsm_has_tpm_support(void);

/*
 * Check if running on macOS with Secure Enclave support compiled in.
 *
 * @return  1 if Secure Enclave support is compiled in, 0 otherwise.
 */
int hsm_has_secure_enclave_support(void);

#ifdef __cplusplus
}
#endif

#endif /* HSM_H */
