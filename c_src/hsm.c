/*
 * hsm.c - Hardware Security Module abstraction implementation
 *
 * This file provides the unified HSM API that dispatches to platform-specific
 * backends:
 * - Linux: TPM 2.0 via tpm2-tss ESAPI
 * - macOS: Secure Enclave via Security.framework
 * - Fallback: Keychain storage (less secure)
 *
 * The dispatcher detects the best available backend at runtime and caches the
 * result. All PIN operations are routed through the appropriate backend.
 *
 * COMPILE:
 * - Linux with TPM:     gcc -DHAS_TPM hsm.c -o hsm.o $(pkg-config --cflags --libs tss2-esys)
 * - macOS with SE:      clang -DHAS_SECURE_ENCLAVE hsm.c -o hsm.o -framework Security
 * - Cross-platform:     Use build system to detect and enable appropriate backend
 */

#include "hsm.h"
#include "keychain.h"

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* Platform-specific includes */
#ifdef __linux__
  #ifdef HAS_TPM
    #include "hsm_tpm.h"
  #endif
#endif

#ifdef __APPLE__
  #ifdef HAS_SECURE_ENCLAVE
    #include "hsm_secure_enclave.h"
  #endif
#endif

/* ============================================================================
 * Static State
 * ============================================================================ */

/* Cached HSM type after detection */
static HSMType s_detected_type = HSM_TYPE_NONE;
static int s_detection_done = 0;

/* Keychain service prefix for fallback storage */
static const char* KEYCHAIN_SERVICE_PREFIX = "remote-juggler.hsm.pin";

/* ============================================================================
 * Error Messages (static strings for hsm_error_message)
 * ============================================================================ */

static const char* ERROR_MESSAGES[] = {
    "Success",                                          /* HSM_SUCCESS = 0 */
    "HSM not available on this platform",              /* HSM_ERR_NOT_AVAILABLE = -1 */
    "Failed to seal/encrypt PIN",                       /* HSM_ERR_SEAL_FAILED = -2 */
    "Failed to unseal/decrypt PIN (security state may have changed)",  /* HSM_ERR_UNSEAL_FAILED = -3 */
    "No PIN stored for this identity",                 /* HSM_ERR_KEY_NOT_FOUND = -4 */
    "Authentication failed (wrong password or biometric)", /* HSM_ERR_AUTH_FAILED = -5 */
    "Invalid parameter",                                /* HSM_ERR_INVALID_PARAM = -6 */
    "Memory allocation failed",                         /* HSM_ERR_MEMORY = -7 */
    "TPM device not accessible",                        /* HSM_ERR_TPM_DEVICE = -8 */
    "Secure Enclave not ready or locked",              /* HSM_ERR_SE_NOT_READY = -9 */
    "TPM PCR mismatch (boot configuration changed)",   /* HSM_ERR_PCR_MISMATCH = -10 */
    "I/O error during HSM operation",                  /* HSM_ERR_IO = -11 */
    "Internal error"                                    /* HSM_ERR_INTERNAL = -12 */
};

#define ERROR_MESSAGE_COUNT (sizeof(ERROR_MESSAGES) / sizeof(ERROR_MESSAGES[0]))

/* ============================================================================
 * HSM Type Names
 * ============================================================================ */

static const char* TYPE_NAMES[] = {
    "None",             /* HSM_TYPE_NONE = 0 */
    "TPM 2.0",          /* HSM_TYPE_TPM = 1 */
    "Secure Enclave",   /* HSM_TYPE_SECURE_ENCLAVE = 2 */
    "Keychain"          /* HSM_TYPE_KEYCHAIN = 3 */
};

#define TYPE_NAME_COUNT (sizeof(TYPE_NAMES) / sizeof(TYPE_NAMES[0]))

/* ============================================================================
 * Internal Helpers
 * ============================================================================ */

/*
 * Build a keychain service name for an identity (fallback storage).
 * Returns allocated string that caller must free.
 */
static char* build_keychain_service(const char* identity) {
    size_t prefix_len = strlen(KEYCHAIN_SERVICE_PREFIX);
    size_t identity_len = strlen(identity);
    size_t total_len = prefix_len + 1 + identity_len + 1;  /* prefix.identity\0 */

    char* service = (char*)malloc(total_len);
    if (service == NULL) {
        return NULL;
    }

    snprintf(service, total_len, "%s.%s", KEYCHAIN_SERVICE_PREFIX, identity);
    return service;
}

/*
 * Validate identity parameter.
 */
static int validate_identity(const char* identity) {
    if (identity == NULL || identity[0] == '\0') {
        return 0;
    }
    /* Basic validation: no path separators or special chars */
    for (const char* p = identity; *p != '\0'; p++) {
        char c = *p;
        if (c == '/' || c == '\\' || c == '.' || c == '\0' ||
            c < 32 || c > 126) {
            return 0;
        }
    }
    return 1;
}

/* ============================================================================
 * HSM Detection and Availability
 * ============================================================================ */

HSMType hsm_detect_available(void) {
    if (s_detection_done) {
        return s_detected_type;
    }

    s_detected_type = HSM_TYPE_NONE;

#ifdef __linux__
  #ifdef HAS_TPM
    /* Check for TPM 2.0 availability */
    if (tpm_is_available()) {
        s_detected_type = HSM_TYPE_TPM;
        s_detection_done = 1;
        return s_detected_type;
    }
  #endif
#endif

#ifdef __APPLE__
  #ifdef HAS_SECURE_ENCLAVE
    /* Check for Secure Enclave availability */
    if (se_is_available()) {
        s_detected_type = HSM_TYPE_SECURE_ENCLAVE;
        s_detection_done = 1;
        return s_detected_type;
    }
  #endif

    /* Check for Keychain availability (macOS always has this) */
    if (keychain_is_darwin()) {
        s_detected_type = HSM_TYPE_KEYCHAIN;
        s_detection_done = 1;
        return s_detected_type;
    }
#endif

    /* No HSM available */
    s_detection_done = 1;
    return s_detected_type;
}

int hsm_is_available(void) {
    return hsm_detect_available() != HSM_TYPE_NONE;
}

const char* hsm_type_name(HSMType type) {
    if (type >= 0 && (size_t)type < TYPE_NAME_COUNT) {
        return TYPE_NAMES[type];
    }
    return "Unknown";
}

HSMType hsm_get_type(void) {
    return hsm_detect_available();
}

/* ============================================================================
 * PIN Storage Operations - Dispatcher
 * ============================================================================ */

HSMStatus hsm_store_pin(const char* identity, const char* pin, size_t pin_len) {
    /* Validate parameters */
    if (!validate_identity(identity)) {
        return HSM_ERR_INVALID_PARAM;
    }
    if (pin == NULL || pin_len == 0) {
        return HSM_ERR_INVALID_PARAM;
    }

    HSMType type = hsm_detect_available();

    switch (type) {
#ifdef __linux__
  #ifdef HAS_TPM
        case HSM_TYPE_TPM:
            return tpm_seal(identity, pin, pin_len);
  #endif
#endif

#ifdef __APPLE__
  #ifdef HAS_SECURE_ENCLAVE
        case HSM_TYPE_SECURE_ENCLAVE:
            return se_encrypt_pin(identity, pin, pin_len);
  #endif
#endif

        case HSM_TYPE_KEYCHAIN: {
            /* Fallback to keychain storage */
            char* service = build_keychain_service(identity);
            if (service == NULL) {
                return HSM_ERR_MEMORY;
            }

            int result = keychain_store(service, identity, pin, pin_len);
            free(service);

            if (result == 0) {
                return HSM_SUCCESS;
            }
            return HSM_ERR_SEAL_FAILED;
        }

        case HSM_TYPE_NONE:
        default:
            return HSM_ERR_NOT_AVAILABLE;
    }
}

HSMStatus hsm_retrieve_pin(const char* identity, char** pin_out, size_t* pin_len_out) {
    /* Validate parameters */
    if (!validate_identity(identity)) {
        return HSM_ERR_INVALID_PARAM;
    }
    if (pin_out == NULL || pin_len_out == NULL) {
        return HSM_ERR_INVALID_PARAM;
    }

    /* Initialize outputs */
    *pin_out = NULL;
    *pin_len_out = 0;

    HSMType type = hsm_detect_available();

    switch (type) {
#ifdef __linux__
  #ifdef HAS_TPM
        case HSM_TYPE_TPM:
            return tpm_unseal(identity, pin_out, pin_len_out);
  #endif
#endif

#ifdef __APPLE__
  #ifdef HAS_SECURE_ENCLAVE
        case HSM_TYPE_SECURE_ENCLAVE:
            return se_decrypt_pin(identity, pin_out, pin_len_out);
  #endif
#endif

        case HSM_TYPE_KEYCHAIN: {
            /* Fallback to keychain retrieval */
            char* service = build_keychain_service(identity);
            if (service == NULL) {
                return HSM_ERR_MEMORY;
            }

            int result = keychain_retrieve(service, identity, pin_out, pin_len_out);
            free(service);

            if (result == 0) {
                return HSM_SUCCESS;
            }
            /* Map keychain errors */
            if (result == -25300) {  /* errSecItemNotFound */
                return HSM_ERR_KEY_NOT_FOUND;
            }
            if (result == -25293) {  /* errSecAuthFailed */
                return HSM_ERR_AUTH_FAILED;
            }
            return HSM_ERR_UNSEAL_FAILED;
        }

        case HSM_TYPE_NONE:
        default:
            return HSM_ERR_NOT_AVAILABLE;
    }
}

HSMStatus hsm_clear_pin(const char* identity) {
    /* Validate parameters */
    if (!validate_identity(identity)) {
        return HSM_ERR_INVALID_PARAM;
    }

    HSMType type = hsm_detect_available();

    switch (type) {
#ifdef __linux__
  #ifdef HAS_TPM
        case HSM_TYPE_TPM:
            return tpm_delete(identity);
  #endif
#endif

#ifdef __APPLE__
  #ifdef HAS_SECURE_ENCLAVE
        case HSM_TYPE_SECURE_ENCLAVE:
            return se_delete_encrypted_pin(identity);
  #endif
#endif

        case HSM_TYPE_KEYCHAIN: {
            /* Fallback to keychain deletion */
            char* service = build_keychain_service(identity);
            if (service == NULL) {
                return HSM_ERR_MEMORY;
            }

            int result = keychain_delete(service, identity);
            free(service);

            if (result == 0) {
                return HSM_SUCCESS;
            }
            if (result == -25300) {  /* errSecItemNotFound */
                return HSM_ERR_KEY_NOT_FOUND;
            }
            return HSM_ERR_IO;
        }

        case HSM_TYPE_NONE:
        default:
            return HSM_ERR_NOT_AVAILABLE;
    }
}

int hsm_has_pin(const char* identity) {
    /* Validate parameters */
    if (!validate_identity(identity)) {
        return 0;
    }

    HSMType type = hsm_detect_available();

    switch (type) {
#ifdef __linux__
  #ifdef HAS_TPM
        case HSM_TYPE_TPM:
            return tpm_exists(identity);
  #endif
#endif

#ifdef __APPLE__
  #ifdef HAS_SECURE_ENCLAVE
        case HSM_TYPE_SECURE_ENCLAVE:
            return se_has_encrypted_pin(identity);
  #endif
#endif

        case HSM_TYPE_KEYCHAIN: {
            /* Fallback to keychain existence check */
            char* service = build_keychain_service(identity);
            if (service == NULL) {
                return 0;
            }

            int result = keychain_exists(service, identity);
            free(service);

            return (result == 0) ? 1 : 0;
        }

        case HSM_TYPE_NONE:
        default:
            return 0;
    }
}

/* ============================================================================
 * Memory Management
 * ============================================================================ */

void hsm_secure_free(void* ptr, size_t len) {
    if (ptr == NULL) {
        return;
    }

    /*
     * Secure memory erasure:
     * 1. Use volatile to prevent compiler optimization
     * 2. Write zeros to the entire region
     * 3. Memory barrier to ensure writes complete
     * 4. Free the memory
     */
    volatile unsigned char* vptr = (volatile unsigned char*)ptr;
    for (size_t i = 0; i < len; i++) {
        vptr[i] = 0;
    }

    /*
     * Compiler barrier to prevent reordering.
     * Most compilers will not optimize away volatile writes, but this
     * provides additional assurance.
     */
#if defined(__GNUC__) || defined(__clang__)
    __asm__ __volatile__("" ::: "memory");
#elif defined(_MSC_VER)
    _ReadWriteBarrier();
#endif

    free(ptr);
}

/* ============================================================================
 * Error Handling
 * ============================================================================ */

const char* hsm_error_message(HSMStatus status) {
    /* Convert negative status to positive index */
    int index = (status <= 0) ? -status : 0;

    if ((size_t)index < ERROR_MESSAGE_COUNT) {
        return ERROR_MESSAGES[index];
    }
    return "Unknown error";
}

/* ============================================================================
 * Platform Detection
 * ============================================================================ */

int hsm_has_tpm_support(void) {
#if defined(__linux__) && defined(HAS_TPM)
    return 1;
#else
    return 0;
#endif
}

int hsm_has_secure_enclave_support(void) {
#if defined(__APPLE__) && defined(HAS_SECURE_ENCLAVE)
    return 1;
#else
    return 0;
#endif
}
