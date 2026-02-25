/*
 * hsm_linux.c - TPM 2.0 implementation for Linux
 *
 * Uses tpm2-tss ESAPI to seal PINs to TPM with PCR binding.
 * Requires TPM 2.0 hardware and tpm2-tss library.
 *
 * Security Model:
 * - PIN is sealed to TPM with PCR binding (default: PCR 7 for Secure Boot)
 * - Sealed blob stored in XDG data directory
 * - Unsealing requires same PCR values (boot state unchanged)
 * - PIN never leaves TPM in cleartext except during callback
 *
 * Error Handling:
 * - Uses functional, monadic patterns with HSM_TRY/HSM_TRY_OR macros
 * - TSS2_RC errors are mapped to hsm_error_t via HSM_MAP_TSS_ERROR
 * - RAII-style cleanup with hsm_guard structures
 *
 * Build: cc -ltss2-esys -ltss2-rc -ltss2-tctildr hsm_linux.c
 *
 * Dependencies:
 * - tpm2-tss (libtss2-esys, libtss2-rc, libtss2-tctildr)
 * - TPM 2.0 resource manager (tpm2-abrmd or kernel module)
 */

#include "hsm.h"

#ifdef __linux__

#include <tss2/tss2_esys.h>
#include <tss2/tss2_rc.h>
#include <tss2/tss2_tctildr.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/stat.h>
#include <errno.h>
#include <stdarg.h>

/* Storage directory under XDG_DATA_HOME */
#define DATA_DIR "remote-juggler/tpm-sealed"

/* Default PCR binding: PCR 7 (Secure Boot state) */
#define DEFAULT_PCR_MASK (1 << 7)

/* Maximum PIN length for TPM seal */
#define MAX_PIN_LEN 128

/* Sealed blob file extension */
#define SEALED_EXT ".tpm2"

/* ==========================================================================
 * Monadic Error Handling Macros
 * ==========================================================================
 * These macros implement a Result<T,E> pattern for C, enabling:
 * - Early return on error with proper error propagation
 * - Chainable operations with automatic cleanup
 * - Clear error flow visualization
 * ========================================================================== */

/* Debug logging control - set HSM_DEBUG_ENABLED=1 to enable */
static int g_debug_enabled = -1;  /* -1 = uninitialized */

static void hsm_debug_init(void) {
    if (g_debug_enabled < 0) {
        const char* env = getenv("HSM_DEBUG");
        g_debug_enabled = (env && (strcmp(env, "1") == 0 || strcmp(env, "true") == 0)) ? 1 : 0;
    }
}

/* Debug logging macro - only logs when HSM_DEBUG=1 */
#define HSM_DEBUG(fmt, ...) do { \
    hsm_debug_init(); \
    if (g_debug_enabled) { \
        fprintf(stderr, "[HSM DEBUG] %s:%d: " fmt "\n", __func__, __LINE__, ##__VA_ARGS__); \
    } \
} while(0)

/*
 * HSM_TRY - Early return on error, propagating error code
 * Usage: HSM_TRY(operation_that_returns_hsm_error_t());
 */
#define HSM_TRY(expr) do { \
    hsm_error_t _hsm_try_rc = (expr); \
    if (_hsm_try_rc != HSM_SUCCESS) { \
        HSM_DEBUG("HSM_TRY failed: %s -> %d (%s)", #expr, _hsm_try_rc, hsm_error_message(_hsm_try_rc)); \
        return _hsm_try_rc; \
    } \
} while(0)

/*
 * HSM_TRY_OR - Try with cleanup on failure
 * Usage: HSM_TRY_OR(operation(), { cleanup_code(); });
 */
#define HSM_TRY_OR(expr, cleanup) do { \
    hsm_error_t _hsm_try_rc = (expr); \
    if (_hsm_try_rc != HSM_SUCCESS) { \
        HSM_DEBUG("HSM_TRY_OR failed: %s -> %d (%s)", #expr, _hsm_try_rc, hsm_error_message(_hsm_try_rc)); \
        do { cleanup } while(0); \
        return _hsm_try_rc; \
    } \
} while(0)

/*
 * HSM_MAP_TSS_ERROR - Map TSS2_RC to hsm_error_t
 * Provides semantic error mapping from TPM-specific errors to our API
 */
static hsm_error_t hsm_map_tss_error(TSS2_RC tss_rc) {
    if (tss_rc == TSS2_RC_SUCCESS) {
        return HSM_SUCCESS;
    }

    /* Extract base error code (mask off layer information) */
    TSS2_RC base = tss_rc & 0xFFFF;

    HSM_DEBUG("Mapping TSS2_RC: 0x%08x (base: 0x%04x)", tss_rc, base);

    /* Map specific TPM error codes */
    switch (base) {
        /* Policy/PCR errors */
        case TPM2_RC_POLICY_FAIL:
        case TPM2_RC_PCR_CHANGED:
        case TPM2_RC_PCR:
            HSM_DEBUG("Mapped to HSM_ERR_PCR_MISMATCH");
            return HSM_ERR_PCR_MISMATCH;

        /* Authentication errors */
        case TPM2_RC_AUTH_FAIL:
        case TPM2_RC_BAD_AUTH:
        case TPM2_RC_AUTH_MISSING:
        case TPM2_RC_AUTH_TYPE:
        case TPM2_RC_AUTH_CONTEXT:
        case TPM2_RC_AUTH_UNAVAILABLE:
            HSM_DEBUG("Mapped to HSM_ERR_AUTH_FAILED");
            return HSM_ERR_AUTH_FAILED;

        /* Permission/locality errors */
        case TPM2_RC_LOCALITY:
        case TPM2_RC_HIERARCHY:
        case TPM2_RC_NV_AUTHORIZATION:
        case TPM2_RC_COMMAND_CODE:
        case TPM2_RC_DISABLED:
            HSM_DEBUG("Mapped to HSM_ERR_PERMISSION");
            return HSM_ERR_PERMISSION;

        /* Resource errors */
        case TPM2_RC_MEMORY:
        case TPM2_RC_OBJECT_MEMORY:
        case TPM2_RC_SESSION_MEMORY:
        case TPM2_RC_OBJECT_HANDLES:
        case TPM2_RC_SESSION_HANDLES:
            HSM_DEBUG("Mapped to HSM_ERR_MEMORY");
            return HSM_ERR_MEMORY;

        /* Timeout/retry errors */
        case TPM2_RC_RETRY:
        case TPM2_RC_YIELDED:
        case TPM2_RC_CANCELED:
            HSM_DEBUG("Mapped to HSM_ERR_TIMEOUT");
            return HSM_ERR_TIMEOUT;

        /* Not found / handle errors */
        case TPM2_RC_HANDLE:
        case TPM2_RC_REFERENCE_H0:
        case TPM2_RC_REFERENCE_H1:
        case TPM2_RC_REFERENCE_H2:
            HSM_DEBUG("Mapped to HSM_ERR_NOT_FOUND");
            return HSM_ERR_NOT_FOUND;

        /* Initialize/available errors */
        case TPM2_RC_INITIALIZE:
        case TPM2_RC_NOT_USED:
        case TPM2_RC_UPGRADE:
            HSM_DEBUG("Mapped to HSM_ERR_NOT_AVAILABLE");
            return HSM_ERR_NOT_AVAILABLE;

        default:
            HSM_DEBUG("Mapped to HSM_ERR_INTERNAL (unknown TSS error)");
            return HSM_ERR_INTERNAL;
    }
}

#define HSM_MAP_TSS_ERROR(tss_rc) hsm_map_tss_error(tss_rc)

/*
 * HSM_TRY_TSS - Try a TSS2 operation, mapping errors
 * Usage: HSM_TRY_TSS(Esys_SomeOperation(...));
 */
#define HSM_TRY_TSS(expr) do { \
    TSS2_RC _tss_rc = (expr); \
    if (_tss_rc != TSS2_RC_SUCCESS) { \
        hsm_error_t _mapped = HSM_MAP_TSS_ERROR(_tss_rc); \
        HSM_DEBUG("HSM_TRY_TSS failed: %s -> TSS2_RC 0x%08x -> hsm_error_t %d", #expr, _tss_rc, _mapped); \
        return _mapped; \
    } \
} while(0)

/*
 * HSM_TRY_TSS_OR - Try TSS operation with cleanup on failure
 * Usage: HSM_TRY_TSS_OR(Esys_Op(...), { cleanup; });
 */
#define HSM_TRY_TSS_OR(expr, cleanup) do { \
    TSS2_RC _tss_rc = (expr); \
    if (_tss_rc != TSS2_RC_SUCCESS) { \
        hsm_error_t _mapped = HSM_MAP_TSS_ERROR(_tss_rc); \
        HSM_DEBUG("HSM_TRY_TSS_OR failed: %s -> TSS2_RC 0x%08x -> hsm_error_t %d", #expr, _tss_rc, _mapped); \
        do { cleanup } while(0); \
        return _mapped; \
    } \
} while(0)

/* ==========================================================================
 * RAII-Style Cleanup Guards
 * ==========================================================================
 * Provides automatic resource cleanup for ESYS handles
 * ========================================================================== */

/*
 * Guard structure for ESYS handles - enables RAII-style cleanup
 */
typedef struct hsm_guard {
    ESYS_TR handle;
    ESYS_CONTEXT* ctx;
} hsm_guard_t;

/* Initialize a guard with no handle */
#define HSM_GUARD_INIT { .handle = ESYS_TR_NONE, .ctx = NULL }

/*
 * Release (flush) the handle held by a guard
 * Safe to call multiple times - handle is set to ESYS_TR_NONE after release
 */
static void hsm_guard_release(hsm_guard_t* guard) {
    if (guard && guard->ctx && guard->handle != ESYS_TR_NONE) {
        HSM_DEBUG("Releasing guard handle: 0x%x", guard->handle);
        Esys_FlushContext(guard->ctx, guard->handle);
        guard->handle = ESYS_TR_NONE;
    }
}

/*
 * Result type for create_primary - monadic Result<ESYS_TR, hsm_error_t>
 */
typedef struct {
    hsm_error_t error;
    ESYS_TR handle;
} primary_result_t;

#define PRIMARY_RESULT_OK(h) ((primary_result_t){ .error = HSM_SUCCESS, .handle = (h) })
#define PRIMARY_RESULT_ERR(e) ((primary_result_t){ .error = (e), .handle = ESYS_TR_NONE })

/* Static state */
static int g_initialized = 0;
static uint32_t g_pcr_mask = DEFAULT_PCR_MASK;
static ESYS_CONTEXT* g_esys_ctx = NULL;

/*
 * Get storage directory path.
 */
static char* get_storage_path(void) {
    const char* xdg_data = getenv("XDG_DATA_HOME");
    char* path = malloc(512);
    if (!path) return NULL;

    if (xdg_data && xdg_data[0]) {
        snprintf(path, 512, "%s/%s", xdg_data, DATA_DIR);
    } else {
        const char* home = getenv("HOME");
        if (!home) home = "/tmp";
        snprintf(path, 512, "%s/.local/share/%s", home, DATA_DIR);
    }

    return path;
}

/*
 * Recursively create directory (equivalent to mkdir -p).
 */
static int mkdir_p(const char* path, mode_t mode) {
    char tmp[512];
    char* p = NULL;
    size_t len;

    snprintf(tmp, sizeof(tmp), "%s", path);
    len = strlen(tmp);
    if (len > 0 && tmp[len - 1] == '/')
        tmp[len - 1] = '\0';

    for (p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            if (mkdir(tmp, mode) != 0 && errno != EEXIST)
                return -1;
            *p = '/';
        }
    }
    if (mkdir(tmp, mode) != 0 && errno != EEXIST)
        return -1;
    /* Ensure final directory has correct permissions. */
    return chmod(tmp, mode);
}

/*
 * Ensure storage directory exists.
 */
static int ensure_storage_dir(void) {
    char* path = get_storage_path();
    if (!path) return -1;

    int rc = mkdir_p(path, 0700);

    free(path);
    return rc;
}

/*
 * Get sealed blob file path for an identity.
 */
static char* get_sealed_path(const char* identity) {
    char* dir = get_storage_path();
    if (!dir) return NULL;

    char* path = malloc(600);
    if (!path) {
        free(dir);
        return NULL;
    }

    snprintf(path, 600, "%s/%s%s", dir, identity, SEALED_EXT);
    free(dir);

    return path;
}

/*
 * Check if TPM 2.0 is available.
 */
static int tpm_available(void) {
    /* Try to initialize ESAPI context */
    TSS2_TCTI_CONTEXT* tcti_ctx = NULL;
    TSS2_RC rc;

    /* Try default TCTI (usually device or tabrmd) */
    rc = Tss2_TctiLdr_Initialize(NULL, &tcti_ctx);
    if (rc != TSS2_RC_SUCCESS) {
        return 0;
    }

    ESYS_CONTEXT* esys_ctx = NULL;
    rc = Esys_Initialize(&esys_ctx, tcti_ctx, NULL);

    if (rc == TSS2_RC_SUCCESS && esys_ctx) {
        /* TPM available - try a simple operation */
        TPMS_CAPABILITY_DATA* cap_data = NULL;
        rc = Esys_GetCapability(
            esys_ctx,
            ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE,
            TPM2_CAP_TPM_PROPERTIES,
            TPM2_PT_MANUFACTURER,
            1,
            NULL,
            &cap_data
        );

        if (cap_data) {
            Esys_Free(cap_data);
        }

        Esys_Finalize(&esys_ctx);
        Tss2_TctiLdr_Finalize(&tcti_ctx);

        return (rc == TSS2_RC_SUCCESS) ? 1 : 0;
    }

    if (tcti_ctx) {
        Tss2_TctiLdr_Finalize(&tcti_ctx);
    }

    return 0;
}

/*
 * Log TPM manufacturer and capabilities on init (debug mode only)
 */
static void log_tpm_info(ESYS_CONTEXT* ctx) {
    if (!ctx) return;

    hsm_debug_init();
    if (!g_debug_enabled) return;

    TPMS_CAPABILITY_DATA* cap_data = NULL;

    /* Get manufacturer */
    TSS2_RC rc = Esys_GetCapability(
        ctx,
        ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE,
        TPM2_CAP_TPM_PROPERTIES,
        TPM2_PT_MANUFACTURER,
        1,
        NULL,
        &cap_data
    );

    if (rc == TSS2_RC_SUCCESS && cap_data && cap_data->data.tpmProperties.count > 0) {
        uint32_t mfr = cap_data->data.tpmProperties.tpmProperty[0].value;
        char mfr_str[5] = {
            (mfr >> 24) & 0xFF,
            (mfr >> 16) & 0xFF,
            (mfr >> 8) & 0xFF,
            mfr & 0xFF,
            '\0'
        };
        HSM_DEBUG("TPM Manufacturer: %s (0x%08x)", mfr_str, mfr);
        Esys_Free(cap_data);
        cap_data = NULL;
    }

    /* Get firmware version */
    rc = Esys_GetCapability(
        ctx,
        ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE,
        TPM2_CAP_TPM_PROPERTIES,
        TPM2_PT_FIRMWARE_VERSION_1,
        1,
        NULL,
        &cap_data
    );

    if (rc == TSS2_RC_SUCCESS && cap_data && cap_data->data.tpmProperties.count > 0) {
        uint32_t fw = cap_data->data.tpmProperties.tpmProperty[0].value;
        HSM_DEBUG("TPM Firmware Version: %d.%d", (fw >> 16) & 0xFFFF, fw & 0xFFFF);
        Esys_Free(cap_data);
        cap_data = NULL;
    }

    /* Log current PCR binding configuration */
    HSM_DEBUG("PCR binding mask: 0x%08x", g_pcr_mask);
    for (int i = 0; i < 24; i++) {
        if (g_pcr_mask & (1 << i)) {
            HSM_DEBUG("  PCR %d: bound", i);
        }
    }
}

/*
 * Initialize ESAPI context using monadic error handling.
 * Uses HSM_TRY_TSS_OR for proper cleanup on TCTI/ESAPI failures.
 */
static hsm_error_t init_esys(void) {
    if (g_esys_ctx) {
        HSM_DEBUG("ESYS context already initialized");
        return HSM_SUCCESS;
    }

    HSM_DEBUG("Initializing ESYS context...");

    TSS2_TCTI_CONTEXT* tcti_ctx = NULL;
    TSS2_RC rc;

    /* Initialize TCTI (Transport Connection) */
    rc = Tss2_TctiLdr_Initialize(NULL, &tcti_ctx);
    if (rc != TSS2_RC_SUCCESS) {
        HSM_DEBUG("TCTI initialization failed: 0x%08x", rc);
        return HSM_ERR_NOT_AVAILABLE;
    }
    HSM_DEBUG("TCTI initialized successfully");

    /* Initialize ESAPI context - cleanup TCTI on failure */
    rc = Esys_Initialize(&g_esys_ctx, tcti_ctx, NULL);
    if (rc != TSS2_RC_SUCCESS) {
        HSM_DEBUG("ESAPI initialization failed: 0x%08x", rc);
        Tss2_TctiLdr_Finalize(&tcti_ctx);
        return HSM_MAP_TSS_ERROR(rc);
    }
    HSM_DEBUG("ESAPI initialized successfully");

    /* Log TPM info in debug mode */
    log_tpm_info(g_esys_ctx);

    return HSM_SUCCESS;
}

/*
 * Create primary key in owner hierarchy.
 * Returns Result<ESYS_TR, hsm_error_t> via primary_result_t struct.
 * Uses monadic pattern - caller must check .error before using .handle.
 */
static primary_result_t create_primary(void) {
    HSM_DEBUG("Creating primary key in owner hierarchy...");

    if (!g_esys_ctx) {
        HSM_DEBUG("ESYS context not initialized");
        return PRIMARY_RESULT_ERR(HSM_ERR_NOT_INITIALIZED);
    }

    TPM2B_SENSITIVE_CREATE in_sensitive = {
        .size = 0,
    };

    TPM2B_PUBLIC in_public = {
        .size = 0,
        .publicArea = {
            .type = TPM2_ALG_RSA,
            .nameAlg = TPM2_ALG_SHA256,
            .objectAttributes = (
                TPMA_OBJECT_RESTRICTED |
                TPMA_OBJECT_DECRYPT |
                TPMA_OBJECT_FIXEDTPM |
                TPMA_OBJECT_FIXEDPARENT |
                TPMA_OBJECT_SENSITIVEDATAORIGIN |
                TPMA_OBJECT_USERWITHAUTH
            ),
            .authPolicy = { .size = 0 },
            .parameters.rsaDetail = {
                .symmetric = {
                    .algorithm = TPM2_ALG_AES,
                    .keyBits.aes = 128,
                    .mode.aes = TPM2_ALG_CFB,
                },
                .scheme = { .scheme = TPM2_ALG_NULL },
                .keyBits = 2048,
                .exponent = 0,
            },
            .unique.rsa = { .size = 0 },
        },
    };

    TPM2B_DATA outside_info = { .size = 0 };
    TPML_PCR_SELECTION creation_pcr = { .count = 0 };

    ESYS_TR primary_handle = ESYS_TR_NONE;
    TPM2B_PUBLIC* out_public = NULL;
    TPM2B_CREATION_DATA* creation_data = NULL;
    TPM2B_DIGEST* creation_hash = NULL;
    TPMT_TK_CREATION* creation_ticket = NULL;

    TSS2_RC rc = Esys_CreatePrimary(
        g_esys_ctx,
        ESYS_TR_RH_OWNER,
        ESYS_TR_PASSWORD, ESYS_TR_NONE, ESYS_TR_NONE,
        &in_sensitive,
        &in_public,
        &outside_info,
        &creation_pcr,
        &primary_handle,
        &out_public,
        &creation_data,
        &creation_hash,
        &creation_ticket
    );

    /* Free optional output blobs */
    Esys_Free(out_public);
    Esys_Free(creation_data);
    Esys_Free(creation_hash);
    Esys_Free(creation_ticket);

    if (rc != TSS2_RC_SUCCESS) {
        hsm_error_t mapped = HSM_MAP_TSS_ERROR(rc);
        HSM_DEBUG("CreatePrimary failed: TSS2_RC 0x%08x -> hsm_error_t %d", rc, mapped);
        return PRIMARY_RESULT_ERR(mapped);
    }

    HSM_DEBUG("Primary key created: handle=0x%x", primary_handle);
    return PRIMARY_RESULT_OK(primary_handle);
}

/*
 * Build PCR selection structure from mask.
 * Helper for create_pcr_policy and unseal operations.
 */
static TPML_PCR_SELECTION build_pcr_selection(uint32_t pcr_mask) {
    TPML_PCR_SELECTION pcr_selection = {
        .count = 1,
        .pcrSelections[0] = {
            .hash = TPM2_ALG_SHA256,
            .sizeofSelect = 3,
            .pcrSelect = { 0, 0, 0 },
        },
    };

    for (int i = 0; i < 24; i++) {
        if (pcr_mask & (1 << i)) {
            pcr_selection.pcrSelections[0].pcrSelect[i / 8] |= (1 << (i % 8));
        }
    }

    return pcr_selection;
}

/*
 * Log PCR values for debugging (when HSM_DEBUG=1)
 */
static void log_pcr_values(ESYS_CONTEXT* ctx, uint32_t pcr_mask) {
    hsm_debug_init();
    if (!g_debug_enabled || !ctx) return;

    TPML_PCR_SELECTION pcr_selection = build_pcr_selection(pcr_mask);
    TPML_DIGEST* pcr_values = NULL;
    TPML_PCR_SELECTION* pcr_selection_out = NULL;
    uint32_t pcr_update_counter = 0;

    TSS2_RC rc = Esys_PCR_Read(
        ctx,
        ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE,
        &pcr_selection,
        &pcr_update_counter,
        &pcr_selection_out,
        &pcr_values
    );

    if (rc == TSS2_RC_SUCCESS && pcr_values) {
        HSM_DEBUG("PCR values (update counter: %u):", pcr_update_counter);
        for (size_t i = 0; i < (size_t)pcr_values->count; i++) {
            char hex[65] = {0};
            for (size_t j = 0; j < (size_t)pcr_values->digests[i].size && j < 32; j++) {
                snprintf(hex + j*2, 3, "%02x", pcr_values->digests[i].buffer[j]);
            }
            HSM_DEBUG("  PCR[%zu]: %s", i, hex);
        }
    }

    if (pcr_values) Esys_Free(pcr_values);
    if (pcr_selection_out) Esys_Free(pcr_selection_out);
}

/*
 * Create PCR policy for sealing.
 * Uses monadic chaining - PolicyPCR >> PolicyGetDigest
 * Returns: HSM_SUCCESS with policy_digest populated, or error
 */
static hsm_error_t create_pcr_policy(ESYS_TR session, TPM2B_DIGEST** policy_digest) {
    HSM_DEBUG("Creating PCR policy for sealing...");

    /* Precondition validation */
    if (!g_esys_ctx) {
        HSM_DEBUG("ESYS context not initialized");
        return HSM_ERR_NOT_INITIALIZED;
    }
    if (session == ESYS_TR_NONE) {
        HSM_DEBUG("Invalid session handle");
        return HSM_ERR_NOT_INITIALIZED;
    }
    if (!policy_digest) {
        HSM_DEBUG("Invalid output pointer");
        return HSM_ERR_INTERNAL;
    }

    /* Log current PCR values for debugging */
    log_pcr_values(g_esys_ctx, g_pcr_mask);

    /* Build PCR selection from global mask */
    TPML_PCR_SELECTION pcr_selection = build_pcr_selection(g_pcr_mask);

    /* Chain: PolicyPCR >> PolicyGetDigest */
    TSS2_RC rc = Esys_PolicyPCR(
        g_esys_ctx,
        session,
        ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE,
        NULL,  /* Use current PCR values */
        &pcr_selection
    );

    if (rc != TSS2_RC_SUCCESS) {
        hsm_error_t mapped = HSM_MAP_TSS_ERROR(rc);
        HSM_DEBUG("PolicyPCR failed: TSS2_RC 0x%08x -> %d", rc, mapped);
        /* Map policy-specific errors */
        if (mapped == HSM_ERR_INTERNAL) {
            return HSM_ERR_SEAL_FAILED;
        }
        return mapped;
    }
    HSM_DEBUG("PolicyPCR succeeded");

    rc = Esys_PolicyGetDigest(
        g_esys_ctx,
        session,
        ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE,
        policy_digest
    );

    if (rc != TSS2_RC_SUCCESS) {
        hsm_error_t mapped = HSM_MAP_TSS_ERROR(rc);
        HSM_DEBUG("PolicyGetDigest failed: TSS2_RC 0x%08x -> %d", rc, mapped);
        return (mapped == HSM_ERR_INTERNAL) ? HSM_ERR_SEAL_FAILED : mapped;
    }

    HSM_DEBUG("PCR policy created successfully, digest size: %u", (*policy_digest)->size);
    return HSM_SUCCESS;
}

void hsm_free(void* ptr) {
    if (ptr) {
        free(ptr);
    }
}

void hsm_status_free(hsm_status_t* status) {
    if (status) {
        hsm_free(status->description);
        hsm_free(status->version);
        hsm_free(status->tpm_manufacturer);
        status->description = NULL;
        status->version = NULL;
        status->tpm_manufacturer = NULL;
    }
}

hsm_error_t hsm_get_status(hsm_status_t* status) {
    if (!status) {
        return HSM_ERR_INVALID_IDENTITY;
    }

    memset(status, 0, sizeof(*status));

    if (tpm_available()) {
        status->method = HSM_METHOD_TPM;
        status->available = 1;
        status->description = strdup("TPM 2.0");
        status->version = strdup("1.0.0");

        /* Get TPM manufacturer info */
        if (init_esys() == HSM_SUCCESS && g_esys_ctx) {
            TPMS_CAPABILITY_DATA* cap_data = NULL;
            TSS2_RC rc = Esys_GetCapability(
                g_esys_ctx,
                ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE,
                TPM2_CAP_TPM_PROPERTIES,
                TPM2_PT_MANUFACTURER,
                1,
                NULL,
                &cap_data
            );

            if (rc == TSS2_RC_SUCCESS && cap_data &&
                cap_data->data.tpmProperties.count > 0) {
                uint32_t mfr = cap_data->data.tpmProperties.tpmProperty[0].value;
                char mfr_str[32];
                /* Convert manufacturer ID to string */
                mfr_str[0] = (mfr >> 24) & 0xFF;
                mfr_str[1] = (mfr >> 16) & 0xFF;
                mfr_str[2] = (mfr >> 8) & 0xFF;
                mfr_str[3] = mfr & 0xFF;
                mfr_str[4] = '\0';
                status->tpm_manufacturer = strdup(mfr_str);
            }

            if (cap_data) Esys_Free(cap_data);
        }
    } else {
        status->method = HSM_METHOD_NONE;
        status->available = 0;
        status->description = strdup("TPM 2.0 not available");
        status->version = strdup("N/A");
    }

    if (!status->description || !status->version) {
        hsm_status_free(status);
        return HSM_ERR_MEMORY;
    }

    return HSM_SUCCESS;
}

hsm_method_t hsm_available(void) {
    return tpm_available() ? HSM_METHOD_TPM : HSM_METHOD_NONE;
}

hsm_error_t hsm_initialize(void) {
    if (g_initialized) {
        return HSM_SUCCESS;
    }

    hsm_error_t rc = init_esys();
    if (rc != HSM_SUCCESS) {
        return rc;
    }

    if (ensure_storage_dir() != 0) {
        return HSM_ERR_IO;
    }

    g_initialized = 1;
    return HSM_SUCCESS;
}

/*
 * Seal cleanup context - holds all resources that need cleanup
 */
typedef struct {
    hsm_guard_t primary;
    hsm_guard_t session;
    TPM2B_DIGEST* policy_digest;
    TPM2B_PRIVATE* out_private;
    TPM2B_PUBLIC* out_public;
    TPM2B_CREATION_DATA* creation_data;
    TPM2B_DIGEST* creation_hash;
    TPMT_TK_CREATION* creation_ticket;
    char* path;
    FILE* file;
} seal_cleanup_ctx_t;

/*
 * Cleanup function for seal operation
 */
static void seal_cleanup(seal_cleanup_ctx_t* ctx) {
    if (!ctx) return;

    HSM_DEBUG("Seal cleanup: releasing resources");

    hsm_guard_release(&ctx->primary);
    hsm_guard_release(&ctx->session);

    if (ctx->policy_digest) Esys_Free(ctx->policy_digest);
    if (ctx->out_private) Esys_Free(ctx->out_private);
    if (ctx->out_public) Esys_Free(ctx->out_public);
    if (ctx->creation_data) Esys_Free(ctx->creation_data);
    if (ctx->creation_hash) Esys_Free(ctx->creation_hash);
    if (ctx->creation_ticket) Esys_Free(ctx->creation_ticket);
    if (ctx->path) free(ctx->path);
    if (ctx->file) fclose(ctx->file);
}

hsm_error_t hsm_seal_pin(const char* identity,
                         const uint8_t* pin,
                         size_t pin_len) {
    HSM_DEBUG("Sealing PIN for identity: %s (len=%zu)", identity ? identity : "(null)", pin_len);

    /* Validate inputs */
    if (!identity || !pin || pin_len == 0 || pin_len > MAX_PIN_LEN) {
        HSM_DEBUG("Invalid input parameters");
        return HSM_ERR_INVALID_IDENTITY;
    }

    /* Initialize cleanup context - RAII-style */
    seal_cleanup_ctx_t cleanup = {
        .primary = HSM_GUARD_INIT,
        .session = HSM_GUARD_INIT,
        .policy_digest = NULL,
        .out_private = NULL,
        .out_public = NULL,
        .creation_data = NULL,
        .creation_hash = NULL,
        .creation_ticket = NULL,
        .path = NULL,
        .file = NULL,
    };

    /* Ensure initialized - monadic composition */
    if (!g_initialized) {
        HSM_TRY(hsm_initialize());
    }

    /* Create primary key - Result pattern */
    primary_result_t primary_result = create_primary();
    if (primary_result.error != HSM_SUCCESS) {
        HSM_DEBUG("Failed to create primary key: %d", primary_result.error);
        return primary_result.error;
    }
    cleanup.primary.handle = primary_result.handle;
    cleanup.primary.ctx = g_esys_ctx;

    /* Start policy session for PCR binding */
    TPMT_SYM_DEF sym = {
        .algorithm = TPM2_ALG_AES,
        .keyBits.aes = 128,
        .mode.aes = TPM2_ALG_CFB,
    };

    TSS2_RC tss_rc = Esys_StartAuthSession(
        g_esys_ctx,
        ESYS_TR_NONE, ESYS_TR_NONE,
        ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE,
        NULL,
        TPM2_SE_TRIAL,  /* Trial session for policy creation */
        &sym,
        TPM2_ALG_SHA256,
        &cleanup.session.handle
    );

    if (tss_rc != TSS2_RC_SUCCESS) {
        hsm_error_t err = HSM_MAP_TSS_ERROR(tss_rc);
        HSM_DEBUG("StartAuthSession failed: 0x%08x -> %d", tss_rc, err);
        seal_cleanup(&cleanup);
        return (err == HSM_ERR_INTERNAL) ? HSM_ERR_SEAL_FAILED : err;
    }
    cleanup.session.ctx = g_esys_ctx;
    HSM_DEBUG("Trial session started: handle=0x%x", cleanup.session.handle);

    /* Create PCR policy - monadic chain */
    hsm_error_t rc = create_pcr_policy(cleanup.session.handle, &cleanup.policy_digest);
    if (rc != HSM_SUCCESS) {
        HSM_DEBUG("create_pcr_policy failed: %d", rc);
        seal_cleanup(&cleanup);
        return rc;
    }

    /* Flush session after getting policy (we only needed the digest) */
    hsm_guard_release(&cleanup.session);

    /* Create sealed object */
    TPM2B_SENSITIVE_CREATE in_sensitive = {
        .size = 0,
        .sensitive = {
            .userAuth = { .size = 0 },
            .data = { .size = pin_len },
        },
    };
    memcpy(in_sensitive.sensitive.data.buffer, pin, pin_len);

    TPM2B_PUBLIC in_public = {
        .size = 0,
        .publicArea = {
            .type = TPM2_ALG_KEYEDHASH,
            .nameAlg = TPM2_ALG_SHA256,
            .objectAttributes = (
                TPMA_OBJECT_FIXEDTPM |
                TPMA_OBJECT_FIXEDPARENT
            ),
            .authPolicy = *cleanup.policy_digest,
            .parameters.keyedHashDetail = {
                .scheme = { .scheme = TPM2_ALG_NULL },
            },
            .unique.keyedHash = { .size = 0 },
        },
    };

    TPM2B_DATA outside_info = { .size = 0 };
    TPML_PCR_SELECTION creation_pcr = { .count = 0 };

    HSM_DEBUG("Creating sealed object...");
    tss_rc = Esys_Create(
        g_esys_ctx,
        cleanup.primary.handle,
        ESYS_TR_PASSWORD, ESYS_TR_NONE, ESYS_TR_NONE,
        &in_sensitive,
        &in_public,
        &outside_info,
        &creation_pcr,
        &cleanup.out_private,
        &cleanup.out_public,
        &cleanup.creation_data,
        &cleanup.creation_hash,
        &cleanup.creation_ticket
    );

    /* Clear sensitive data immediately */
    memset(&in_sensitive, 0, sizeof(in_sensitive));

    if (tss_rc != TSS2_RC_SUCCESS) {
        hsm_error_t err = HSM_MAP_TSS_ERROR(tss_rc);
        HSM_DEBUG("Esys_Create failed: 0x%08x -> %d", tss_rc, err);
        seal_cleanup(&cleanup);
        return (err == HSM_ERR_INTERNAL) ? HSM_ERR_SEAL_FAILED : err;
    }
    HSM_DEBUG("Sealed object created successfully");

    /* Primary key no longer needed */
    hsm_guard_release(&cleanup.primary);

    /* Save sealed blob to file */
    cleanup.path = get_sealed_path(identity);
    if (!cleanup.path) {
        HSM_DEBUG("Failed to get sealed path");
        seal_cleanup(&cleanup);
        return HSM_ERR_MEMORY;
    }

    cleanup.file = fopen(cleanup.path, "wb");
    if (!cleanup.file) {
        HSM_DEBUG("Failed to open file for writing: %s", cleanup.path);
        seal_cleanup(&cleanup);
        return HSM_ERR_IO;
    }

    /* Write public + private blobs */
    size_t written = 0;
    written += fwrite(&cleanup.out_public->size, sizeof(uint16_t), 1, cleanup.file);
    written += fwrite(cleanup.out_public, cleanup.out_public->size + sizeof(uint16_t), 1, cleanup.file);
    written += fwrite(&cleanup.out_private->size, sizeof(uint16_t), 1, cleanup.file);
    written += fwrite(cleanup.out_private, cleanup.out_private->size + sizeof(uint16_t), 1, cleanup.file);

    if (written != 4) {
        HSM_DEBUG("Failed to write sealed blob (wrote %zu/4 items)", written);
        seal_cleanup(&cleanup);
        return HSM_ERR_IO;
    }

    fclose(cleanup.file);
    cleanup.file = NULL;  /* Prevent double-close in cleanup */

    /* Set permissions */
    chmod(cleanup.path, 0600);
    HSM_DEBUG("Sealed blob written to: %s", cleanup.path);

    /* Success - cleanup remaining resources */
    seal_cleanup(&cleanup);

    return HSM_SUCCESS;
}

/*
 * Unseal cleanup context - holds all resources that need cleanup
 */
typedef struct {
    char* path;
    FILE* file;
    hsm_guard_t primary;
    hsm_guard_t loaded_key;
    hsm_guard_t session;
    TPM2B_SENSITIVE_DATA* unsealed;
} unseal_cleanup_ctx_t;

/*
 * Cleanup function for unseal operation
 */
static void unseal_cleanup(unseal_cleanup_ctx_t* ctx) {
    if (!ctx) return;

    HSM_DEBUG("Unseal cleanup: releasing resources");

    /* Clear sensitive data before freeing */
    if (ctx->unsealed) {
        memset(ctx->unsealed->buffer, 0, ctx->unsealed->size);
        Esys_Free(ctx->unsealed);
    }

    hsm_guard_release(&ctx->session);
    hsm_guard_release(&ctx->loaded_key);
    hsm_guard_release(&ctx->primary);

    if (ctx->file) fclose(ctx->file);
    if (ctx->path) free(ctx->path);
}

/*
 * Map unseal-specific TSS errors to appropriate hsm_error_t
 */
static hsm_error_t map_unseal_error(TSS2_RC tss_rc) {
    hsm_error_t mapped = HSM_MAP_TSS_ERROR(tss_rc);

    /* Remap certain errors to unseal-specific codes */
    switch (mapped) {
        case HSM_ERR_AUTH_FAILED:
        case HSM_ERR_PCR_MISMATCH:
            /* These are the expected failure modes during unseal */
            return mapped;
        case HSM_ERR_INTERNAL:
            /* Unknown error during unseal -> unseal failed */
            return HSM_ERR_UNSEAL_FAILED;
        default:
            return mapped;
    }
}

hsm_error_t hsm_unseal_pin(const char* identity,
                           hsm_pin_callback_t callback,
                           void* user_data) {
    HSM_DEBUG("Unsealing PIN for identity: %s", identity ? identity : "(null)");

    /* Validate inputs */
    if (!identity || !callback) {
        HSM_DEBUG("Invalid input parameters");
        return HSM_ERR_INVALID_IDENTITY;
    }

    /* Initialize cleanup context - RAII-style */
    unseal_cleanup_ctx_t cleanup = {
        .path = NULL,
        .file = NULL,
        .primary = HSM_GUARD_INIT,
        .loaded_key = HSM_GUARD_INIT,
        .session = HSM_GUARD_INIT,
        .unsealed = NULL,
    };

    /* Ensure initialized - monadic composition */
    if (!g_initialized) {
        HSM_TRY(hsm_initialize());
    }

    /* Load sealed blob from file */
    cleanup.path = get_sealed_path(identity);
    if (!cleanup.path) {
        HSM_DEBUG("Failed to get sealed path");
        return HSM_ERR_MEMORY;
    }

    cleanup.file = fopen(cleanup.path, "rb");
    if (!cleanup.file) {
        HSM_DEBUG("Failed to open sealed file: %s", cleanup.path);
        unseal_cleanup(&cleanup);
        return HSM_ERR_NOT_FOUND;
    }

    /* Read public blob */
    TPM2B_PUBLIC in_public;
    uint16_t pub_size;
    if (fread(&pub_size, sizeof(uint16_t), 1, cleanup.file) != 1 ||
        fread(&in_public, pub_size + sizeof(uint16_t), 1, cleanup.file) != 1) {
        HSM_DEBUG("Failed to read public blob");
        unseal_cleanup(&cleanup);
        return HSM_ERR_IO;
    }

    /* Read private blob */
    TPM2B_PRIVATE in_private;
    uint16_t priv_size;
    if (fread(&priv_size, sizeof(uint16_t), 1, cleanup.file) != 1 ||
        fread(&in_private, priv_size + sizeof(uint16_t), 1, cleanup.file) != 1) {
        HSM_DEBUG("Failed to read private blob");
        unseal_cleanup(&cleanup);
        return HSM_ERR_IO;
    }

    /* File no longer needed */
    fclose(cleanup.file);
    cleanup.file = NULL;
    HSM_DEBUG("Sealed blob loaded from: %s", cleanup.path);

    /* Create primary key (same as sealing) - Result pattern */
    primary_result_t primary_result = create_primary();
    if (primary_result.error != HSM_SUCCESS) {
        HSM_DEBUG("Failed to create primary key: %d", primary_result.error);
        unseal_cleanup(&cleanup);
        return primary_result.error;
    }
    cleanup.primary.handle = primary_result.handle;
    cleanup.primary.ctx = g_esys_ctx;

    /* Load sealed object into TPM */
    HSM_DEBUG("Loading sealed object into TPM...");
    TSS2_RC tss_rc = Esys_Load(
        g_esys_ctx,
        cleanup.primary.handle,
        ESYS_TR_PASSWORD, ESYS_TR_NONE, ESYS_TR_NONE,
        &in_private,
        &in_public,
        &cleanup.loaded_key.handle
    );

    /* Primary no longer needed after load */
    hsm_guard_release(&cleanup.primary);

    if (tss_rc != TSS2_RC_SUCCESS) {
        hsm_error_t err = map_unseal_error(tss_rc);
        HSM_DEBUG("Esys_Load failed: 0x%08x -> %d", tss_rc, err);
        unseal_cleanup(&cleanup);
        return err;
    }
    cleanup.loaded_key.ctx = g_esys_ctx;
    HSM_DEBUG("Sealed object loaded: handle=0x%x", cleanup.loaded_key.handle);

    /* Start policy session with current PCR values */
    TPMT_SYM_DEF sym = {
        .algorithm = TPM2_ALG_AES,
        .keyBits.aes = 128,
        .mode.aes = TPM2_ALG_CFB,
    };

    tss_rc = Esys_StartAuthSession(
        g_esys_ctx,
        ESYS_TR_NONE, ESYS_TR_NONE,
        ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE,
        NULL,
        TPM2_SE_POLICY,
        &sym,
        TPM2_ALG_SHA256,
        &cleanup.session.handle
    );

    if (tss_rc != TSS2_RC_SUCCESS) {
        hsm_error_t err = map_unseal_error(tss_rc);
        HSM_DEBUG("StartAuthSession failed: 0x%08x -> %d", tss_rc, err);
        unseal_cleanup(&cleanup);
        return err;
    }
    cleanup.session.ctx = g_esys_ctx;
    HSM_DEBUG("Policy session started: handle=0x%x", cleanup.session.handle);

    /* Log current PCR values for debugging */
    log_pcr_values(g_esys_ctx, g_pcr_mask);

    /* Apply PCR policy using helper function */
    TPML_PCR_SELECTION pcr_selection = build_pcr_selection(g_pcr_mask);

    HSM_DEBUG("Applying PCR policy...");
    tss_rc = Esys_PolicyPCR(
        g_esys_ctx,
        cleanup.session.handle,
        ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE,
        NULL,
        &pcr_selection
    );

    if (tss_rc != TSS2_RC_SUCCESS) {
        hsm_error_t err = HSM_MAP_TSS_ERROR(tss_rc);
        HSM_DEBUG("PolicyPCR failed: 0x%08x -> %d (PCR mismatch?)", tss_rc, err);
        unseal_cleanup(&cleanup);
        /* PolicyPCR failure almost always means PCR mismatch */
        return (err == HSM_ERR_INTERNAL) ? HSM_ERR_PCR_MISMATCH : err;
    }
    HSM_DEBUG("PCR policy applied successfully");

    /* Unseal the data */
    HSM_DEBUG("Unsealing data...");
    tss_rc = Esys_Unseal(
        g_esys_ctx,
        cleanup.loaded_key.handle,
        cleanup.session.handle, ESYS_TR_NONE, ESYS_TR_NONE,
        &cleanup.unsealed
    );

    /* Release session and loaded key immediately after unseal */
    hsm_guard_release(&cleanup.session);
    hsm_guard_release(&cleanup.loaded_key);

    if (tss_rc != TSS2_RC_SUCCESS || !cleanup.unsealed) {
        hsm_error_t err = HSM_MAP_TSS_ERROR(tss_rc);
        HSM_DEBUG("Esys_Unseal failed: 0x%08x -> %d", tss_rc, err);
        unseal_cleanup(&cleanup);
        /* Unseal failure is likely due to PCR/policy mismatch */
        return (err == HSM_ERR_INTERNAL) ? HSM_ERR_PCR_MISMATCH : err;
    }
    HSM_DEBUG("Data unsealed successfully: %u bytes", cleanup.unsealed->size);

    /* Call callback with unsealed PIN */
    HSM_DEBUG("Invoking callback...");
    int cb_result = callback(cleanup.unsealed->buffer, cleanup.unsealed->size, user_data);
    HSM_DEBUG("Callback returned: %d", cb_result);

    /* Cleanup clears unsealed data */
    unseal_cleanup(&cleanup);

    return (cb_result == 0) ? HSM_SUCCESS : HSM_ERR_INTERNAL;
}

int hsm_pin_exists(const char* identity) {
    if (!identity) return -1;

    char* path = get_sealed_path(identity);
    if (!path) return -1;

    int exists = (access(path, F_OK) == 0) ? 1 : 0;
    free(path);

    return exists;
}

hsm_error_t hsm_clear_pin(const char* identity) {
    if (!identity) {
        return HSM_ERR_INVALID_IDENTITY;
    }

    char* path = get_sealed_path(identity);
    if (!path) {
        return HSM_ERR_MEMORY;
    }

    /* Overwrite with zeros before deletion */
    FILE* f = fopen(path, "r+b");
    if (f) {
        fseek(f, 0, SEEK_END);
        long size = ftell(f);
        fseek(f, 0, SEEK_SET);

        uint8_t zero = 0;
        for (long i = 0; i < size; i++) {
            fwrite(&zero, 1, 1, f);
        }
        fclose(f);
    }

    int rc = unlink(path);
    free(path);

    return (rc == 0 || errno == ENOENT) ? HSM_SUCCESS : HSM_ERR_IO;
}

hsm_error_t hsm_clear_all(void) {
    char* dir = get_storage_path();
    if (!dir) return HSM_ERR_MEMORY;

    char cmd[600];
    snprintf(cmd, sizeof(cmd), "rm -f '%s'/*%s 2>/dev/null", dir, SEALED_EXT);
    system(cmd);

    free(dir);
    return HSM_SUCCESS;
}

const char* hsm_error_message(hsm_error_t error) {
    static const char* messages[] = {
        [HSM_SUCCESS] = "Success",
        [HSM_ERR_NOT_AVAILABLE] = "TPM 2.0 hardware not available",
        [HSM_ERR_NOT_INITIALIZED] = "TPM not initialized",
        [HSM_ERR_INVALID_IDENTITY] = "Invalid identity name",
        [HSM_ERR_SEAL_FAILED] = "Failed to seal PIN with TPM",
        [HSM_ERR_UNSEAL_FAILED] = "Failed to unseal PIN from TPM",
        [HSM_ERR_NOT_FOUND] = "No PIN stored for identity",
        [HSM_ERR_AUTH_FAILED] = "TPM authentication failed",
        [HSM_ERR_PCR_MISMATCH] = "Platform boot state changed since PIN was sealed",
        [HSM_ERR_MEMORY] = "Memory allocation failed",
        [HSM_ERR_IO] = "I/O error",
        [HSM_ERR_PERMISSION] = "Permission denied (check TPM access)",
        [HSM_ERR_TIMEOUT] = "TPM operation timed out",
        [HSM_ERR_CANCELLED] = "Operation cancelled",
        [HSM_ERR_INTERNAL] = "Internal error",
    };

    if (error >= 0 && error < sizeof(messages) / sizeof(messages[0])) {
        return messages[error];
    }
    return "Unknown error";
}

char** hsm_list_identities(size_t* count) {
    if (!count) return NULL;
    *count = 0;

    char* dir = get_storage_path();
    if (!dir) return NULL;

    /* List .tpm2 files */
    char cmd[600];
    snprintf(cmd, sizeof(cmd),
             "ls -1 '%s'/*%s 2>/dev/null | xargs -I{} basename {} %s",
             dir, SEALED_EXT, SEALED_EXT);

    free(dir);

    FILE* p = popen(cmd, "r");
    if (!p) return NULL;

    char** identities = NULL;
    size_t capacity = 0;
    char line[128];

    while (fgets(line, sizeof(line), p)) {
        size_t len = strlen(line);
        if (len > 0 && line[len-1] == '\n') {
            line[len-1] = '\0';
        }

        if (*count >= capacity) {
            capacity = capacity ? capacity * 2 : 4;
            char** new_ids = realloc(identities, (capacity + 1) * sizeof(char*));
            if (!new_ids) {
                for (size_t i = 0; i < *count; i++) free(identities[i]);
                free(identities);
                pclose(p);
                *count = 0;
                return NULL;
            }
            identities = new_ids;
        }

        identities[*count] = strdup(line);
        if (!identities[*count]) {
            for (size_t i = 0; i < *count; i++) free(identities[i]);
            free(identities);
            pclose(p);
            *count = 0;
            return NULL;
        }
        (*count)++;
    }

    pclose(p);

    if (identities) {
        identities[*count] = NULL;
    }

    return identities;
}

hsm_error_t hsm_tpm_set_pcr_binding(uint32_t pcr_mask) {
    g_pcr_mask = pcr_mask;
    return HSM_SUCCESS;
}

hsm_error_t hsm_se_set_biometric(int require_biometric) {
    (void)require_biometric;
    return HSM_ERR_NOT_AVAILABLE;
}

#else /* !__linux__ */

/* Stub for non-Linux platforms */
#include "hsm_stub.c"

#endif /* __linux__ */
