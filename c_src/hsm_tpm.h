/*
 * hsm_tpm.h - TPM 2.0 backend for HSM abstraction (Linux)
 *
 * This file provides TPM 2.0 support using the tpm2-tss ESAPI library.
 * PINs are sealed to PCR 7 (Secure Boot state), meaning:
 * - The PIN can only be unsealed on the same device
 * - If the boot chain is modified (different bootloader, kernel, etc.), unsealing fails
 * - This provides protection against offline attacks and boot tampering
 *
 * DEPENDENCIES:
 * - libtss2-esys (Enhanced System API)
 * - libtss2-rc (Return code helpers)
 * - libtss2-mu (Marshalling/unmarshalling)
 *
 * COMPILE WITH:
 *   pkg-config --cflags --libs tss2-esys tss2-rc tss2-mu
 *
 * TPM DEVICE:
 * - Uses /dev/tpmrm0 (Resource Manager) by default
 * - Falls back to /dev/tpm0 if resource manager unavailable
 *
 * PCR BINDING:
 * - PCR 7: Secure Boot state (EFI variables, boot configuration)
 * - Changing boot settings, updating UEFI, or disabling Secure Boot will
 *   invalidate sealed data
 *
 * STORAGE:
 * - Sealed blobs are stored in ~/.config/remote-juggler/hsm/tpm/{identity}.sealed
 * - Directory should have mode 0700
 */

#ifndef HSM_TPM_H
#define HSM_TPM_H

#include "hsm.h"

#ifdef __linux__

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * TPM Device Constants
 * ============================================================================ */

/* TPM device paths in order of preference */
#define TPM_DEVICE_RM       "/dev/tpmrm0"   /* Resource Manager (preferred) */
#define TPM_DEVICE_DIRECT   "/dev/tpm0"     /* Direct access (requires exclusive) */

/* PCR index for sealing */
#define TPM_PCR_SECURE_BOOT 7               /* Secure Boot state */

/* Storage paths */
#define TPM_SEALED_DIR      ".config/remote-juggler/hsm/tpm"
#define TPM_SEALED_EXT      ".sealed"

/* ============================================================================
 * TPM Detection and Initialization
 * ============================================================================ */

/*
 * Check if a TPM 2.0 device is available and accessible.
 *
 * Checks for:
 * 1. /dev/tpmrm0 or /dev/tpm0 exists
 * 2. Device is readable/writable by current user
 * 3. Basic TPM communication succeeds
 *
 * @return  1 if TPM is available, 0 otherwise.
 */
int tpm_is_available(void);

/*
 * Get the TPM device path that will be used.
 *
 * @return  Static string with device path, or NULL if no TPM available.
 */
const char* tpm_get_device_path(void);

/*
 * Initialize the TPM ESAPI context.
 *
 * Must be called before any seal/unseal operations.
 * Initializes connection to the TPM via resource manager.
 *
 * @return  HSM_SUCCESS on success, error code on failure.
 */
HSMStatus tpm_init(void);

/*
 * Finalize and clean up TPM ESAPI context.
 *
 * Should be called when TPM operations are complete.
 */
void tpm_finalize(void);

/* ============================================================================
 * TPM Sealing Operations
 * ============================================================================ */

/*
 * Seal data to the TPM, bound to PCR 7.
 *
 * The sealed blob can only be unsealed when:
 * 1. Running on the same TPM
 * 2. PCR 7 has the same value as when sealing occurred
 *
 * @param identity      Identity name for storage path.
 * @param data          Data to seal (the PIN).
 * @param data_len      Length of data in bytes.
 * @return              HSM_SUCCESS on success, error code on failure.
 *
 * IMPLEMENTATION NOTES:
 * - Creates a sealing key under the Storage Root Key (SRK)
 * - Uses TPM2_Create with a seal policy bound to PCR 7
 * - Writes sealed blob to ~/.config/remote-juggler/hsm/tpm/{identity}.sealed
 */
HSMStatus tpm_seal(const char* identity, const char* data, size_t data_len);

/*
 * Unseal data from the TPM.
 *
 * Retrieves previously sealed data. Will fail if:
 * - Sealed blob file doesn't exist
 * - PCR 7 values don't match (boot chain changed)
 * - TPM reports any other error
 *
 * @param identity      Identity name for storage path.
 * @param data_out      Output: Allocated buffer with unsealed data.
 *                      Caller must free with hsm_secure_free().
 * @param data_len_out  Output: Length of unsealed data.
 * @return              HSM_SUCCESS on success, error code on failure.
 *
 * IMPLEMENTATION NOTES:
 * - Reads sealed blob from ~/.config/remote-juggler/hsm/tpm/{identity}.sealed
 * - Uses TPM2_Load to load the sealed object
 * - Uses TPM2_Unseal with PCR policy session
 * - Zeros and frees internal buffers after copying to output
 */
HSMStatus tpm_unseal(const char* identity, char** data_out, size_t* data_len_out);

/*
 * Delete a sealed blob.
 *
 * Removes the sealed blob file. The TPM key is transient and doesn't need cleanup.
 *
 * @param identity  Identity name for storage path.
 * @return          HSM_SUCCESS on success, HSM_ERR_KEY_NOT_FOUND if not found.
 */
HSMStatus tpm_delete(const char* identity);

/*
 * Check if a sealed blob exists for an identity.
 *
 * @param identity  Identity name for storage path.
 * @return          1 if sealed blob exists, 0 otherwise.
 */
int tpm_exists(const char* identity);

/* ============================================================================
 * TPM PCR Operations (for diagnostics)
 * ============================================================================ */

/*
 * Read the current value of PCR 7.
 *
 * Useful for diagnostics when unsealing fails.
 *
 * @param pcr_value     Output: 32-byte buffer for SHA-256 PCR value.
 * @param pcr_value_len Size of buffer (should be >= 32).
 * @return              HSM_SUCCESS on success, error code on failure.
 */
HSMStatus tpm_read_pcr7(uint8_t* pcr_value, size_t pcr_value_len);

/*
 * Get a hex string representation of PCR 7.
 *
 * @return  Allocated string (caller must free) with hex PCR value,
 *          or NULL on error.
 */
char* tpm_get_pcr7_hex(void);

/* ============================================================================
 * Internal Storage Helpers
 * ============================================================================ */

/*
 * Get the storage path for a sealed blob.
 *
 * @param identity  Identity name.
 * @return          Allocated path string (caller must free), or NULL on error.
 *                  Path: $HOME/.config/remote-juggler/hsm/tpm/{identity}.sealed
 */
char* tpm_get_sealed_path(const char* identity);

/*
 * Ensure the TPM storage directory exists with proper permissions.
 *
 * Creates $HOME/.config/remote-juggler/hsm/tpm with mode 0700.
 *
 * @return  HSM_SUCCESS on success, error code on failure.
 */
HSMStatus tpm_ensure_storage_dir(void);

#ifdef __cplusplus
}
#endif

#endif /* __linux__ */

#endif /* HSM_TPM_H */
