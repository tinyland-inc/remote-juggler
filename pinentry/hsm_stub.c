/*
 * hsm_stub.c - Stub implementation of HSM interface
 *
 * Used on platforms without TPM 2.0 or Secure Enclave.
 * Falls back to system keychain with software encryption.
 *
 * This implementation provides basic functionality for testing
 * and development, but should NOT be used in production for
 * security-sensitive PIN storage.
 */

#include "hsm.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* Storage path for stub implementation */
#ifndef HSM_STUB_PATH
#define HSM_STUB_PATH ".config/remote-juggler/pin-cache"
#endif

/* Maximum PIN length */
#define MAX_PIN_LEN 256

/* Maximum identity name length */
#define MAX_IDENTITY_LEN 64

/* Error messages */
static const char* error_messages[] = {
    [HSM_SUCCESS] = "Success",
    [HSM_ERR_NOT_AVAILABLE] = "HSM hardware not available",
    [HSM_ERR_NOT_INITIALIZED] = "HSM not initialized",
    [HSM_ERR_INVALID_IDENTITY] = "Invalid identity name",
    [HSM_ERR_SEAL_FAILED] = "Failed to seal PIN",
    [HSM_ERR_UNSEAL_FAILED] = "Failed to unseal PIN",
    [HSM_ERR_NOT_FOUND] = "No PIN stored for identity",
    [HSM_ERR_AUTH_FAILED] = "Authentication failed",
    [HSM_ERR_PCR_MISMATCH] = "Platform state changed",
    [HSM_ERR_MEMORY] = "Memory allocation failed",
    [HSM_ERR_IO] = "I/O error",
    [HSM_ERR_PERMISSION] = "Permission denied",
    [HSM_ERR_TIMEOUT] = "Operation timed out",
    [HSM_ERR_CANCELLED] = "Operation cancelled",
    [HSM_ERR_INTERNAL] = "Internal error",
};

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

    /* Stub implementation uses keychain fallback */
    status->method = HSM_METHOD_KEYCHAIN;
    status->available = 1;
    status->description = strdup("Software keychain fallback (stub implementation)");
    status->version = strdup("1.0.0-stub");

    if (!status->description || !status->version) {
        hsm_status_free(status);
        return HSM_ERR_MEMORY;
    }

    return HSM_SUCCESS;
}

hsm_method_t hsm_available(void) {
    /* Stub always returns keychain fallback */
    return HSM_METHOD_KEYCHAIN;
}

hsm_error_t hsm_initialize(void) {
    /* Stub: Nothing to initialize */
    return HSM_SUCCESS;
}

/*
 * WARNING: This is a STUB implementation!
 *
 * In this stub, PINs are stored with minimal obfuscation.
 * This is NOT secure and is only for testing/development.
 *
 * Production implementations must use:
 * - hsm_darwin.c (Secure Enclave)
 * - hsm_linux.c (TPM 2.0)
 */
hsm_error_t hsm_seal_pin(const char* identity,
                         const uint8_t* pin,
                         size_t pin_len) {
    if (!identity || !pin || pin_len == 0) {
        return HSM_ERR_INVALID_IDENTITY;
    }

    if (pin_len > MAX_PIN_LEN) {
        return HSM_ERR_INVALID_IDENTITY;
    }

    if (strlen(identity) > MAX_IDENTITY_LEN) {
        return HSM_ERR_INVALID_IDENTITY;
    }

    /* Get storage path */
    const char* home = getenv("HOME");
    if (!home) {
        home = "/tmp";
    }

    char path[1024];
    snprintf(path, sizeof(path), "%s/%s", home, HSM_STUB_PATH);

    /* Create directory */
    char mkdir_cmd[1100];
    snprintf(mkdir_cmd, sizeof(mkdir_cmd), "mkdir -p '%s'", path);
    int rc = system(mkdir_cmd);
    if (rc != 0) {
        return HSM_ERR_IO;
    }

    /* Write PIN file (XOR obfuscated - NOT secure!) */
    char filepath[1200];
    snprintf(filepath, sizeof(filepath), "%s/%s.pin", path, identity);

    FILE* f = fopen(filepath, "wb");
    if (!f) {
        return HSM_ERR_IO;
    }

    /* Simple XOR "obfuscation" - NOT real encryption! */
    const uint8_t xor_key = 0x5A;
    for (size_t i = 0; i < pin_len; i++) {
        uint8_t obfuscated = pin[i] ^ xor_key;
        fwrite(&obfuscated, 1, 1, f);
    }

    fclose(f);

    /* Restrict permissions */
    char chmod_cmd[1300];
    snprintf(chmod_cmd, sizeof(chmod_cmd), "chmod 600 '%s'", filepath);
    system(chmod_cmd);

    fprintf(stderr, "[hsm_stub] WARNING: PIN stored with minimal obfuscation. "
                    "NOT secure! Use TPM or Secure Enclave in production.\n");

    return HSM_SUCCESS;
}

hsm_error_t hsm_unseal_pin(const char* identity,
                           hsm_pin_callback_t callback,
                           void* user_data) {
    if (!identity || !callback) {
        return HSM_ERR_INVALID_IDENTITY;
    }

    /* Get storage path */
    const char* home = getenv("HOME");
    if (!home) {
        home = "/tmp";
    }

    char filepath[1200];
    snprintf(filepath, sizeof(filepath), "%s/%s/%s.pin",
             home, HSM_STUB_PATH, identity);

    FILE* f = fopen(filepath, "rb");
    if (!f) {
        return HSM_ERR_NOT_FOUND;
    }

    /* Read and "decrypt" PIN */
    uint8_t pin[MAX_PIN_LEN + 1];
    size_t pin_len = 0;

    const uint8_t xor_key = 0x5A;
    int c;
    while ((c = fgetc(f)) != EOF && pin_len < MAX_PIN_LEN) {
        pin[pin_len++] = (uint8_t)c ^ xor_key;
    }

    fclose(f);

    if (pin_len == 0) {
        return HSM_ERR_NOT_FOUND;
    }

    /* Call callback with PIN */
    int cb_result = callback(pin, pin_len, user_data);

    /* Clear PIN from memory */
    memset(pin, 0, sizeof(pin));

    if (cb_result != 0) {
        return HSM_ERR_INTERNAL;
    }

    return HSM_SUCCESS;
}

int hsm_pin_exists(const char* identity) {
    if (!identity) {
        return -1;
    }

    const char* home = getenv("HOME");
    if (!home) {
        home = "/tmp";
    }

    char filepath[1200];
    snprintf(filepath, sizeof(filepath), "%s/%s/%s.pin",
             home, HSM_STUB_PATH, identity);

    FILE* f = fopen(filepath, "r");
    if (f) {
        fclose(f);
        return 1;
    }
    return 0;
}

hsm_error_t hsm_clear_pin(const char* identity) {
    if (!identity) {
        return HSM_ERR_INVALID_IDENTITY;
    }

    const char* home = getenv("HOME");
    if (!home) {
        home = "/tmp";
    }

    char filepath[1200];
    snprintf(filepath, sizeof(filepath), "%s/%s/%s.pin",
             home, HSM_STUB_PATH, identity);

    /* Overwrite with zeros before deletion */
    FILE* f = fopen(filepath, "r+b");
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

    if (remove(filepath) != 0) {
        return HSM_ERR_IO;
    }

    return HSM_SUCCESS;
}

hsm_error_t hsm_clear_all(void) {
    const char* home = getenv("HOME");
    if (!home) {
        home = "/tmp";
    }

    char cmd[1100];
    snprintf(cmd, sizeof(cmd), "rm -f '%s/%s'/*.pin 2>/dev/null",
             home, HSM_STUB_PATH);

    system(cmd);

    return HSM_SUCCESS;
}

const char* hsm_error_message(hsm_error_t error) {
    if (error >= 0 && error < sizeof(error_messages) / sizeof(error_messages[0])) {
        return error_messages[error];
    }
    return "Unknown error";
}

char** hsm_list_identities(size_t* count) {
    if (!count) {
        return NULL;
    }

    *count = 0;

    const char* home = getenv("HOME");
    if (!home) {
        home = "/tmp";
    }

    char path[1024];
    snprintf(path, sizeof(path), "%s/%s", home, HSM_STUB_PATH);

    /* Use ls to list .pin files */
    char cmd[1100];
    snprintf(cmd, sizeof(cmd), "ls -1 '%s'/*.pin 2>/dev/null | "
             "xargs -I{} basename {} .pin", path);

    FILE* p = popen(cmd, "r");
    if (!p) {
        return NULL;
    }

    /* Read identities */
    char** identities = NULL;
    size_t capacity = 0;
    char line[MAX_IDENTITY_LEN + 1];

    while (fgets(line, sizeof(line), p)) {
        /* Remove newline */
        size_t len = strlen(line);
        if (len > 0 && line[len-1] == '\n') {
            line[len-1] = '\0';
        }

        /* Expand array */
        if (*count >= capacity) {
            capacity = capacity ? capacity * 2 : 4;
            char** new_ids = realloc(identities, (capacity + 1) * sizeof(char*));
            if (!new_ids) {
                /* Cleanup on failure */
                for (size_t i = 0; i < *count; i++) {
                    free(identities[i]);
                }
                free(identities);
                pclose(p);
                *count = 0;
                return NULL;
            }
            identities = new_ids;
        }

        identities[*count] = strdup(line);
        if (!identities[*count]) {
            for (size_t i = 0; i < *count; i++) {
                free(identities[i]);
            }
            free(identities);
            pclose(p);
            *count = 0;
            return NULL;
        }
        (*count)++;
    }

    pclose(p);

    /* NULL-terminate array */
    if (identities) {
        identities[*count] = NULL;
    }

    return identities;
}

hsm_error_t hsm_tpm_set_pcr_binding(uint32_t pcr_mask) {
    (void)pcr_mask;
    /* Stub: No TPM support */
    return HSM_ERR_NOT_AVAILABLE;
}

hsm_error_t hsm_se_set_biometric(int require_biometric) {
    (void)require_biometric;
    /* Stub: No Secure Enclave support */
    return HSM_ERR_NOT_AVAILABLE;
}
