/*
 * hsm_tpm.c - TPM 2.0 backend implementation (Linux)
 *
 * This file implements PIN sealing/unsealing using TPM 2.0 via tpm2-tss ESAPI.
 * PINs are sealed to PCR 7 (Secure Boot state).
 *
 * COMPILE:
 *   gcc -DHAS_TPM hsm_tpm.c -o hsm_tpm.o $(pkg-config --cflags --libs tss2-esys tss2-rc tss2-mu)
 *
 * DEPENDENCIES:
 *   - libtss2-esys: Enhanced System API
 *   - libtss2-rc: Return code translation
 *   - libtss2-mu: Marshalling/unmarshalling
 *
 * RUNTIME REQUIREMENTS:
 *   - /dev/tpmrm0 (TPM Resource Manager) or /dev/tpm0
 *   - User must have read/write access to TPM device
 *   - Typically requires membership in 'tss' or 'tpm' group
 */

#ifdef __linux__
#ifdef HAS_TPM

#include "hsm_tpm.h"
#include "hsm.h"

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/stat.h>
#include <errno.h>
#include <pwd.h>

/* TPM2-TSS includes */
#include <tss2/tss2_esys.h>
#include <tss2/tss2_rc.h>
#include <tss2/tss2_mu.h>

/* ============================================================================
 * Static State
 * ============================================================================ */

/* ESAPI context (initialized on first use) */
static ESYS_CONTEXT* s_esys_ctx = NULL;
static int s_tpm_initialized = 0;

/* Detected TPM device path */
static const char* s_tpm_device = NULL;

/* ============================================================================
 * TPM Device Detection
 * ============================================================================ */

int tpm_is_available(void) {
    /* Check for TPM resource manager first (preferred) */
    if (access(TPM_DEVICE_RM, R_OK | W_OK) == 0) {
        s_tpm_device = TPM_DEVICE_RM;
        return 1;
    }

    /* Fall back to direct device access */
    if (access(TPM_DEVICE_DIRECT, R_OK | W_OK) == 0) {
        s_tpm_device = TPM_DEVICE_DIRECT;
        return 1;
    }

    return 0;
}

const char* tpm_get_device_path(void) {
    if (s_tpm_device == NULL) {
        tpm_is_available();  /* Detect if not done */
    }
    return s_tpm_device;
}

/* ============================================================================
 * TPM Initialization
 * ============================================================================ */

HSMStatus tpm_init(void) {
    if (s_tpm_initialized) {
        return HSM_SUCCESS;
    }

    if (!tpm_is_available()) {
        return HSM_ERR_TPM_DEVICE;
    }

    /*
     * TODO: Initialize ESAPI context
     *
     * TSS2_RC rc = Esys_Initialize(&s_esys_ctx, NULL, NULL);
     * if (rc != TSS2_RC_SUCCESS) {
     *     return HSM_ERR_TPM_DEVICE;
     * }
     *
     * // Verify TPM communication with GetCapability
     * TPMS_CAPABILITY_DATA* cap_data = NULL;
     * rc = Esys_GetCapability(s_esys_ctx,
     *                         ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE,
     *                         TPM2_CAP_TPM_PROPERTIES,
     *                         TPM2_PT_MANUFACTURER,
     *                         1,
     *                         NULL,
     *                         &cap_data);
     * if (rc != TSS2_RC_SUCCESS) {
     *     Esys_Finalize(&s_esys_ctx);
     *     return HSM_ERR_TPM_DEVICE;
     * }
     * Esys_Free(cap_data);
     */

    s_tpm_initialized = 1;
    return HSM_SUCCESS;
}

void tpm_finalize(void) {
    if (s_esys_ctx != NULL) {
        /*
         * TODO: Finalize ESAPI context
         * Esys_Finalize(&s_esys_ctx);
         */
        s_esys_ctx = NULL;
    }
    s_tpm_initialized = 0;
}

/* ============================================================================
 * Storage Path Helpers
 * ============================================================================ */

char* tpm_get_sealed_path(const char* identity) {
    if (identity == NULL || identity[0] == '\0') {
        return NULL;
    }

    /* Get home directory */
    const char* home = getenv("HOME");
    if (home == NULL) {
        struct passwd* pw = getpwuid(getuid());
        if (pw == NULL) {
            return NULL;
        }
        home = pw->pw_dir;
    }

    /* Build path: $HOME/.config/remote-juggler/hsm/tpm/{identity}.sealed */
    size_t path_len = strlen(home) + 1 + strlen(TPM_SEALED_DIR) + 1 +
                      strlen(identity) + strlen(TPM_SEALED_EXT) + 1;

    char* path = (char*)malloc(path_len);
    if (path == NULL) {
        return NULL;
    }

    snprintf(path, path_len, "%s/%s/%s%s", home, TPM_SEALED_DIR, identity, TPM_SEALED_EXT);
    return path;
}

HSMStatus tpm_ensure_storage_dir(void) {
    const char* home = getenv("HOME");
    if (home == NULL) {
        struct passwd* pw = getpwuid(getuid());
        if (pw == NULL) {
            return HSM_ERR_IO;
        }
        home = pw->pw_dir;
    }

    /* Build directory path */
    size_t dir_len = strlen(home) + 1 + strlen(TPM_SEALED_DIR) + 1;
    char* dir_path = (char*)malloc(dir_len);
    if (dir_path == NULL) {
        return HSM_ERR_MEMORY;
    }
    snprintf(dir_path, dir_len, "%s/%s", home, TPM_SEALED_DIR);

    /* Create directory hierarchy with mode 0700 */
    char* p = dir_path + strlen(home) + 1;  /* Skip home directory */
    while (*p != '\0') {
        if (*p == '/') {
            *p = '\0';
            if (mkdir(dir_path, 0700) != 0 && errno != EEXIST) {
                free(dir_path);
                return HSM_ERR_IO;
            }
            *p = '/';
        }
        p++;
    }

    /* Create final directory */
    if (mkdir(dir_path, 0700) != 0 && errno != EEXIST) {
        free(dir_path);
        return HSM_ERR_IO;
    }

    free(dir_path);
    return HSM_SUCCESS;
}

/* ============================================================================
 * TPM Sealing Operations
 * ============================================================================ */

HSMStatus tpm_seal(const char* identity, const char* data, size_t data_len) {
    if (identity == NULL || identity[0] == '\0') {
        return HSM_ERR_INVALID_PARAM;
    }
    if (data == NULL || data_len == 0) {
        return HSM_ERR_INVALID_PARAM;
    }

    /* Ensure storage directory exists */
    HSMStatus status = tpm_ensure_storage_dir();
    if (status != HSM_SUCCESS) {
        return status;
    }

    /* Initialize TPM if needed */
    status = tpm_init();
    if (status != HSM_SUCCESS) {
        return status;
    }

    /*
     * TODO: Implement TPM sealing with PCR 7 policy
     *
     * The sealing process:
     * 1. Create a policy session with PCR 7 binding
     * 2. Create a sealing key under the Storage Root Key (SRK)
     * 3. Seal the data using TPM2_Create
     * 4. Write the sealed blob (public + private) to file
     *
     * TPM2_PolicyPCR(policySession, NULL, {PCR7});
     * TPM2_Create(srkHandle, sensitiveData, publicTemplate, policyDigest,
     *             &outPublic, &outPrivate);
     *
     * The sealed blob format:
     * - 4 bytes: public size (big-endian)
     * - N bytes: TPM2B_PUBLIC marshalled
     * - 4 bytes: private size (big-endian)
     * - M bytes: TPM2B_PRIVATE marshalled
     */

    /* Get storage path */
    char* sealed_path = tpm_get_sealed_path(identity);
    if (sealed_path == NULL) {
        return HSM_ERR_MEMORY;
    }

    /*
     * STUB: Write placeholder file for testing
     * TODO: Replace with actual TPM sealing
     */
    FILE* f = fopen(sealed_path, "wb");
    if (f == NULL) {
        free(sealed_path);
        return HSM_ERR_IO;
    }

    /* Write a marker indicating this is a stub */
    const char marker[] = "REMOTEJUGGLER_TPM_STUB_V1\n";
    fwrite(marker, 1, strlen(marker), f);
    /* NOTE: In stub mode, we're NOT writing the actual PIN - just a marker */
    /* Real implementation would write TPM-sealed blob */

    fclose(f);
    free(sealed_path);

    /* TODO: Remove stub and implement real TPM sealing */
    return HSM_ERR_NOT_AVAILABLE;  /* Return error until real implementation */
}

HSMStatus tpm_unseal(const char* identity, char** data_out, size_t* data_len_out) {
    if (identity == NULL || identity[0] == '\0') {
        return HSM_ERR_INVALID_PARAM;
    }
    if (data_out == NULL || data_len_out == NULL) {
        return HSM_ERR_INVALID_PARAM;
    }

    *data_out = NULL;
    *data_len_out = 0;

    /* Check if sealed blob exists */
    if (!tpm_exists(identity)) {
        return HSM_ERR_KEY_NOT_FOUND;
    }

    /* Initialize TPM if needed */
    HSMStatus status = tpm_init();
    if (status != HSM_SUCCESS) {
        return status;
    }

    /*
     * TODO: Implement TPM unsealing with PCR 7 policy
     *
     * The unsealing process:
     * 1. Read sealed blob from file
     * 2. Unmarshal public and private parts
     * 3. Load the sealed object under SRK
     * 4. Create a policy session with current PCR 7 value
     * 5. Unseal using TPM2_Unseal
     *
     * If PCR 7 doesn't match the sealed policy, TPM2_Unseal will fail
     * with TPM2_RC_POLICY_FAIL.
     *
     * TPM2_Load(srkHandle, inPrivate, inPublic, &objectHandle);
     * TPM2_StartAuthSession(TPM2_SE_POLICY, &policySession);
     * TPM2_PolicyPCR(policySession, NULL, {PCR7});
     * TPM2_Unseal(objectHandle, policySession, &outData);
     */

    /* TODO: Remove stub and implement real TPM unsealing */
    return HSM_ERR_NOT_AVAILABLE;  /* Return error until real implementation */
}

HSMStatus tpm_delete(const char* identity) {
    if (identity == NULL || identity[0] == '\0') {
        return HSM_ERR_INVALID_PARAM;
    }

    char* sealed_path = tpm_get_sealed_path(identity);
    if (sealed_path == NULL) {
        return HSM_ERR_MEMORY;
    }

    if (access(sealed_path, F_OK) != 0) {
        free(sealed_path);
        return HSM_ERR_KEY_NOT_FOUND;
    }

    /* Securely delete the file by overwriting with zeros first */
    FILE* f = fopen(sealed_path, "r+b");
    if (f != NULL) {
        fseek(f, 0, SEEK_END);
        long size = ftell(f);
        fseek(f, 0, SEEK_SET);

        /* Overwrite with zeros */
        char zero = 0;
        for (long i = 0; i < size; i++) {
            fwrite(&zero, 1, 1, f);
        }
        fflush(f);
        fclose(f);
    }

    /* Remove the file */
    if (unlink(sealed_path) != 0) {
        free(sealed_path);
        return HSM_ERR_IO;
    }

    free(sealed_path);
    return HSM_SUCCESS;
}

int tpm_exists(const char* identity) {
    if (identity == NULL || identity[0] == '\0') {
        return 0;
    }

    char* sealed_path = tpm_get_sealed_path(identity);
    if (sealed_path == NULL) {
        return 0;
    }

    int exists = (access(sealed_path, F_OK) == 0) ? 1 : 0;
    free(sealed_path);
    return exists;
}

/* ============================================================================
 * TPM PCR Operations
 * ============================================================================ */

HSMStatus tpm_read_pcr7(uint8_t* pcr_value, size_t pcr_value_len) {
    if (pcr_value == NULL || pcr_value_len < 32) {
        return HSM_ERR_INVALID_PARAM;
    }

    HSMStatus status = tpm_init();
    if (status != HSM_SUCCESS) {
        return status;
    }

    /*
     * TODO: Read PCR 7 using TPM2_PCR_Read
     *
     * TPML_PCR_SELECTION pcrSelection = {
     *     .count = 1,
     *     .pcrSelections[0] = {
     *         .hash = TPM2_ALG_SHA256,
     *         .sizeofSelect = 3,
     *         .pcrSelect = {0x00, 0x00, 0x80}  // PCR 7
     *     }
     * };
     *
     * TPML_DIGEST* pcrValues = NULL;
     * TPM2_PCR_Read(s_esys_ctx, &pcrSelection, NULL, NULL, &pcrValues);
     * memcpy(pcr_value, pcrValues->digests[0].buffer, 32);
     */

    /* TODO: Remove stub */
    memset(pcr_value, 0, 32);
    return HSM_ERR_NOT_AVAILABLE;
}

char* tpm_get_pcr7_hex(void) {
    uint8_t pcr_value[32];
    HSMStatus status = tpm_read_pcr7(pcr_value, sizeof(pcr_value));
    if (status != HSM_SUCCESS) {
        return NULL;
    }

    /* Convert to hex string (64 chars + null) */
    char* hex = (char*)malloc(65);
    if (hex == NULL) {
        return NULL;
    }

    for (int i = 0; i < 32; i++) {
        sprintf(hex + (i * 2), "%02x", pcr_value[i]);
    }
    hex[64] = '\0';

    return hex;
}

#endif /* HAS_TPM */
#endif /* __linux__ */
