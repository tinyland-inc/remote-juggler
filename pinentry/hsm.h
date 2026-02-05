/*
 * hsm.h - Hardware Security Module abstraction for RemoteJuggler
 *
 * Provides a unified interface for secure PIN storage across platforms:
 * - macOS: Secure Enclave via Security.framework
 * - Linux: TPM 2.0 via tpm2-tss library
 * - Fallback: System keychain with software encryption
 *
 * Security Model:
 * - PIN is encrypted before storage (seal operation)
 * - PIN decryption happens within HSM, never in application memory
 * - Callback pattern ensures PIN is cleared after use
 *
 * Usage:
 *   // Store PIN
 *   int rc = hsm_seal_pin("personal", pin_data, pin_len);
 *
 *   // Retrieve and use PIN (callback pattern)
 *   rc = hsm_unseal_pin("personal", my_callback, user_data);
 *
 *   // Check capability
 *   int method = hsm_available();  // HSM_METHOD_TPM, HSM_METHOD_SE, etc.
 */

#ifndef HSM_H
#define HSM_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * HSM availability methods.
 * Used to determine what hardware security is available.
 */
typedef enum {
    HSM_METHOD_NONE = 0,        /* No HSM available */
    HSM_METHOD_TPM = 1,         /* TPM 2.0 (Linux) */
    HSM_METHOD_SECURE_ENCLAVE = 2, /* Secure Enclave (macOS T2/M1+) */
    HSM_METHOD_KEYCHAIN = 3,    /* Software keychain fallback */
} hsm_method_t;

/*
 * Error codes for HSM operations.
 */
typedef enum {
    HSM_SUCCESS = 0,
    HSM_ERR_NOT_AVAILABLE = 1,   /* HSM hardware not available */
    HSM_ERR_NOT_INITIALIZED = 2, /* HSM not initialized */
    HSM_ERR_INVALID_IDENTITY = 3, /* Invalid identity name */
    HSM_ERR_SEAL_FAILED = 4,     /* Failed to seal/encrypt PIN */
    HSM_ERR_UNSEAL_FAILED = 5,   /* Failed to unseal/decrypt PIN */
    HSM_ERR_NOT_FOUND = 6,       /* No PIN stored for identity */
    HSM_ERR_AUTH_FAILED = 7,     /* Authentication/authorization failed */
    HSM_ERR_PCR_MISMATCH = 8,    /* TPM PCR values changed (boot state) */
    HSM_ERR_MEMORY = 9,          /* Memory allocation failed */
    HSM_ERR_IO = 10,             /* I/O error */
    HSM_ERR_PERMISSION = 11,     /* Permission denied */
    HSM_ERR_TIMEOUT = 12,        /* Operation timed out */
    HSM_ERR_CANCELLED = 13,      /* Operation cancelled by user */
    HSM_ERR_INTERNAL = 99,       /* Internal error */
} hsm_error_t;

/*
 * Callback function type for PIN retrieval.
 *
 * The callback receives the decrypted PIN and must process it
 * immediately. The PIN buffer is cleared after the callback returns.
 *
 * @param pin       Pointer to decrypted PIN data
 * @param pin_len   Length of PIN data
 * @param user_data User-provided context pointer
 * @return          0 on success, non-zero to indicate callback failure
 */
typedef int (*hsm_pin_callback_t)(const uint8_t* pin, size_t pin_len, void* user_data);

/*
 * HSM status information.
 */
typedef struct {
    hsm_method_t method;         /* Available HSM method */
    int available;               /* 1 if HSM is available and ready */
    char* description;           /* Human-readable description (caller must free) */
    char* version;               /* HSM/driver version (caller must free) */

    /* TPM-specific fields */
    int tpm_has_persistent_key;  /* 1 if TPM primary key exists */
    char* tpm_manufacturer;      /* TPM manufacturer (caller must free) */

    /* Secure Enclave-specific fields */
    int se_biometric_available;  /* 1 if Touch ID available */
    int se_key_exists;           /* 1 if SE key exists for RemoteJuggler */
} hsm_status_t;

/*
 * Free memory allocated by HSM functions.
 *
 * @param ptr  Pointer to free (safe to call with NULL)
 */
void hsm_free(void* ptr);

/*
 * Free HSM status structure contents.
 *
 * @param status  Status structure to clean up
 */
void hsm_status_free(hsm_status_t* status);

/*
 * Check HSM availability and get status information.
 *
 * Detects available hardware security module and returns its status.
 * Call hsm_status_free() to release allocated memory.
 *
 * @param status  Output: status information
 * @return        HSM_SUCCESS or error code
 */
hsm_error_t hsm_get_status(hsm_status_t* status);

/*
 * Get the available HSM method.
 *
 * Quick check for HSM availability without full status.
 *
 * @return  HSM method (HSM_METHOD_NONE if none available)
 */
hsm_method_t hsm_available(void);

/*
 * Initialize the HSM subsystem.
 *
 * Must be called before seal/unseal operations.
 * Creates necessary keys and configures HSM.
 *
 * For TPM: Creates primary key in owner hierarchy
 * For Secure Enclave: Creates SE-protected key pair
 *
 * @return  HSM_SUCCESS or error code
 */
hsm_error_t hsm_initialize(void);

/*
 * Seal (encrypt) a PIN for an identity.
 *
 * The PIN is encrypted with the HSM key and stored securely.
 * For TPM: Sealed to current PCR state
 * For Secure Enclave: Encrypted with SE key
 *
 * @param identity   Identity name (e.g., "personal", "work")
 * @param pin        PIN data to seal
 * @param pin_len    Length of PIN data
 * @return           HSM_SUCCESS or error code
 */
hsm_error_t hsm_seal_pin(const char* identity,
                         const uint8_t* pin,
                         size_t pin_len);

/*
 * Unseal (decrypt) and use a PIN.
 *
 * The PIN is decrypted within the HSM and passed to the callback.
 * After the callback returns, the PIN is cleared from memory.
 *
 * @param identity   Identity name
 * @param callback   Function to receive decrypted PIN
 * @param user_data  User context passed to callback
 * @return           HSM_SUCCESS or error code
 */
hsm_error_t hsm_unseal_pin(const char* identity,
                           hsm_pin_callback_t callback,
                           void* user_data);

/*
 * Check if a PIN is stored for an identity.
 *
 * @param identity   Identity name
 * @return           1 if PIN exists, 0 if not, -1 on error
 */
int hsm_pin_exists(const char* identity);

/*
 * Clear a stored PIN.
 *
 * Removes the sealed PIN for an identity.
 *
 * @param identity   Identity name
 * @return           HSM_SUCCESS or error code
 */
hsm_error_t hsm_clear_pin(const char* identity);

/*
 * Clear all stored PINs.
 *
 * Emergency function to remove all sealed PINs.
 *
 * @return  HSM_SUCCESS or error code
 */
hsm_error_t hsm_clear_all(void);

/*
 * Get human-readable error message.
 *
 * @param error  Error code
 * @return       Static string describing the error
 */
const char* hsm_error_message(hsm_error_t error);

/*
 * List identities with stored PINs.
 *
 * Returns an array of identity names (NULL-terminated).
 * Caller must free each string and the array itself with hsm_free().
 *
 * @param count  Output: number of identities
 * @return       Array of identity names, or NULL on error
 */
char** hsm_list_identities(size_t* count);

/*
 * Configure TPM PCR binding.
 *
 * Linux-only. Specifies which PCR values to bind sealed data to.
 * Default is PCR 7 (Secure Boot state) only.
 *
 * @param pcr_mask   Bitmask of PCR indices (bit 0 = PCR 0, etc.)
 * @return           HSM_SUCCESS or error code
 */
hsm_error_t hsm_tpm_set_pcr_binding(uint32_t pcr_mask);

/*
 * Configure Secure Enclave biometric requirement.
 *
 * macOS-only. When enabled, PIN retrieval requires Touch ID.
 * Default is disabled (for agent/CLI compatibility).
 *
 * @param require_biometric  1 to require biometric, 0 to disable
 * @return                   HSM_SUCCESS or error code
 */
hsm_error_t hsm_se_set_biometric(int require_biometric);

#ifdef __cplusplus
}
#endif

#endif /* HSM_H */
