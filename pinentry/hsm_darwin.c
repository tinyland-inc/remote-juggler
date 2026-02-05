/*
 * hsm_darwin.c - Secure Enclave implementation for macOS
 *
 * Uses Security.framework to store PINs encrypted with Secure Enclave keys.
 * Requires macOS 10.12.1+ with T2 or Apple Silicon chip.
 *
 * Security Model:
 * - EC P-256 key generated and stored in Secure Enclave
 * - PIN encrypted using ECIES (EC Integrated Encryption Scheme)
 * - Encrypted blob stored in Keychain with SE protection class
 * - Decryption requires SE key (cannot be extracted)
 *
 * Build: clang -framework Security -framework CoreFoundation hsm_darwin.c
 */

#include "hsm.h"

#ifdef __APPLE__

#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

/* Keychain service prefix */
#define SERVICE_PREFIX "com.remotejuggler.pin."

/* SE key tag prefix */
#define KEY_TAG_PREFIX "com.remotejuggler.se-key."

/* Maximum PIN length */
#define MAX_PIN_LEN 256

/* Maximum CF objects tracked by guard */
#define CF_GUARD_MAX_REFS 16

/* Static state */
static int g_initialized = 0;
static int g_require_biometric = 0;

/* ============================================================================
 * Monadic Error Handling Infrastructure
 * ============================================================================
 *
 * These macros implement a Result<T,E>-like pattern for C, enabling:
 * - Early return on error with automatic cleanup
 * - OSStatus to hsm_error_t mapping
 * - CF object lifetime management via guards
 */

/*
 * CF cleanup guard - RAII-style resource management for CoreFoundation objects.
 * Tracks CFTypeRef objects and releases them all when cf_guard_release() is called.
 */
typedef struct {
    CFTypeRef refs[CF_GUARD_MAX_REFS];
    int count;
} cf_guard_t;

/* Initialize a CF guard */
#define CF_GUARD_INIT { .refs = {NULL}, .count = 0 }

/*
 * Add a CF object to the guard for automatic cleanup.
 * Returns the ref for use in assignment chains.
 */
static inline CFTypeRef cf_guard_add(cf_guard_t* guard, CFTypeRef ref) {
    if (guard && ref && guard->count < CF_GUARD_MAX_REFS) {
        guard->refs[guard->count++] = ref;
    }
    return ref;
}

/*
 * Release all tracked CF objects in reverse order.
 * Safe to call multiple times - clears refs after release.
 */
static void cf_guard_release(cf_guard_t* guard) {
    if (!guard) return;
    for (int i = guard->count - 1; i >= 0; i--) {
        if (guard->refs[i]) {
            CFRelease(guard->refs[i]);
            guard->refs[i] = NULL;
        }
    }
    guard->count = 0;
}

/*
 * Map OSStatus to hsm_error_t.
 * Centralizes error translation for Security.framework calls.
 */
static hsm_error_t osstatus_to_hsm_error(OSStatus status) {
    switch (status) {
        case errSecSuccess:
            return HSM_SUCCESS;
        case errSecItemNotFound:
            return HSM_ERR_NOT_FOUND;
        case errSecAuthFailed:
            return HSM_ERR_AUTH_FAILED;
        case errSecUserCanceled:
            return HSM_ERR_CANCELLED;
        case errSecInteractionNotAllowed:
            return HSM_ERR_PERMISSION;
        case errSecMissingEntitlement:
            return HSM_ERR_PERMISSION;
        case errSecAllocate:
            return HSM_ERR_MEMORY;
        case errSecIO:
            return HSM_ERR_IO;
        case errSecDuplicateItem:
            return HSM_SUCCESS; /* Treat as success for idempotent operations */
        default:
            return HSM_ERR_INTERNAL;
    }
}

/*
 * Extract error from CFErrorRef and map to hsm_error_t.
 */
static hsm_error_t cferror_to_hsm_error(CFErrorRef error) {
    if (!error) return HSM_ERR_INTERNAL;

    CFIndex code = CFErrorGetCode(error);
    CFStringRef domain = CFErrorGetDomain(error);

    /* Check for Security framework errors */
    if (CFEqual(domain, kCFErrorDomainOSStatus)) {
        return osstatus_to_hsm_error((OSStatus)code);
    }

    /* LAError codes (LocalAuthentication.framework) */
    if (domain && CFStringHasPrefix(domain, CFSTR("com.apple.LocalAuthentication"))) {
        switch (code) {
            case -1: /* LAErrorAuthenticationFailed */
                return HSM_ERR_AUTH_FAILED;
            case -2: /* LAErrorUserCancel */
                return HSM_ERR_CANCELLED;
            case -4: /* LAErrorSystemCancel */
                return HSM_ERR_CANCELLED;
            case -5: /* LAErrorPasscodeNotSet */
                return HSM_ERR_NOT_AVAILABLE;
            case -6: /* LAErrorBiometryNotAvailable (Touch ID not available) */
                return HSM_ERR_NOT_AVAILABLE;
            case -7: /* LAErrorBiometryNotEnrolled */
                return HSM_ERR_NOT_AVAILABLE;
            case -8: /* LAErrorBiometryLockout */
                return HSM_ERR_AUTH_FAILED;
            default:
                return HSM_ERR_INTERNAL;
        }
    }

    return HSM_ERR_INTERNAL;
}

/*
 * HSM_TRY_CF - Check CFTypeRef result, set error and cleanup on NULL.
 * Usage: HSM_TRY_CF(result, &guard, HSM_ERR_SEAL_FAILED);
 */
#define HSM_TRY_CF(expr, guard_ptr, err_code) \
    do { \
        if (!(expr)) { \
            cf_guard_release(guard_ptr); \
            return (err_code); \
        } \
    } while (0)

/*
 * HSM_TRY_CF_ERR - Check CFTypeRef, extract error from CFErrorRef on failure.
 * Usage: HSM_TRY_CF_ERR(SecKeyCreateRandomKey(attrs, &cf_err), &cf_err, &guard);
 */
#define HSM_TRY_CF_ERR(expr, cf_err_ptr, guard_ptr) \
    do { \
        if (!(expr)) { \
            hsm_error_t _err = cferror_to_hsm_error(*(cf_err_ptr)); \
            if (*(cf_err_ptr)) CFRelease(*(cf_err_ptr)); \
            cf_guard_release(guard_ptr); \
            return _err; \
        } \
    } while (0)

/*
 * HSM_TRY_OS - Check OSStatus, cleanup and return mapped error on failure.
 * Usage: HSM_TRY_OS(SecItemAdd(query, NULL), &guard);
 */
#define HSM_TRY_OS(status_expr, guard_ptr) \
    do { \
        OSStatus _status = (status_expr); \
        if (_status != errSecSuccess) { \
            cf_guard_release(guard_ptr); \
            return osstatus_to_hsm_error(_status); \
        } \
    } while (0)

/*
 * HSM_TRY_OS_ALLOW - Like HSM_TRY_OS but allows specific status codes.
 * Usage: HSM_TRY_OS_ALLOW(SecItemDelete(query), &guard, errSecItemNotFound);
 */
#define HSM_TRY_OS_ALLOW(status_expr, guard_ptr, allowed_status) \
    do { \
        OSStatus _status = (status_expr); \
        if (_status != errSecSuccess && _status != (allowed_status)) { \
            cf_guard_release(guard_ptr); \
            return osstatus_to_hsm_error(_status); \
        } \
    } while (0)

/*
 * HSM_GUARD_ADD - Add CF object to guard, return error if allocation failed.
 * Usage: HSM_GUARD_ADD(query, CFDictionaryCreateMutable(...), &guard, HSM_ERR_MEMORY);
 */
#define HSM_GUARD_ADD(var, expr, guard_ptr, err_code) \
    do { \
        (var) = (expr); \
        if (!(var)) { \
            cf_guard_release(guard_ptr); \
            return (err_code); \
        } \
        cf_guard_add((guard_ptr), (var)); \
    } while (0)

/* ============================================================================
 * Internal Helper Functions
 * ============================================================================ */

/*
 * Check if Secure Enclave is available.
 * Attempts to query SE key generation capabilities.
 */
static int se_available(void) {
    cf_guard_t guard = CF_GUARD_INIT;

    int key_size = 256;
    CFNumberRef key_size_ref = CFNumberCreate(kCFAllocatorDefault,
                                               kCFNumberIntType, &key_size);
    if (!key_size_ref) return 0;
    cf_guard_add(&guard, key_size_ref);

    CFMutableDictionaryRef attributes = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );
    if (!attributes) {
        cf_guard_release(&guard);
        return 0;
    }
    cf_guard_add(&guard, attributes);

    CFDictionarySetValue(attributes, kSecAttrKeyType, kSecAttrKeyTypeECSECPrimeRandom);
    CFDictionarySetValue(attributes, kSecAttrKeySizeInBits, key_size_ref);
    CFDictionarySetValue(attributes, kSecAttrTokenID, kSecAttrTokenIDSecureEnclave);

    /* Try to generate an ephemeral key - this will fail if no SE */
    CFErrorRef error = NULL;
    SecKeyRef key = SecKeyCreateRandomKey(attributes, &error);

    if (key) {
        /* SE available - delete the test key */
        CFRelease(key);
        cf_guard_release(&guard);
        return 1;
    }

    if (error) {
        CFRelease(error);
    }

    cf_guard_release(&guard);
    return 0;
}

/*
 * Create LAContext usage dictionary for biometric prompt.
 * Sets localized reason for Touch ID dialog.
 */
static CFDictionaryRef create_la_context_attrs(const char* identity) {
    CFMutableDictionaryRef la_attrs = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );
    if (!la_attrs) return NULL;

    /* Build user-facing message */
    char reason[512];
    snprintf(reason, sizeof(reason),
             "RemoteJuggler needs to access the PIN for identity '%s'", identity);

    CFStringRef reason_str = CFStringCreateWithCString(kCFAllocatorDefault,
                                                        reason,
                                                        kCFStringEncodingUTF8);
    if (reason_str) {
        CFDictionarySetValue(la_attrs, kSecUseOperationPrompt, reason_str);
        CFRelease(reason_str);
    }

    return la_attrs;
}

/*
 * Get or create the SE key for an identity.
 * Implements monadic composition: lookup -> create on miss.
 */
static SecKeyRef get_or_create_se_key(const char* identity, hsm_error_t* out_error) {
    cf_guard_t guard = CF_GUARD_INIT;
    CFErrorRef cf_error = NULL;

    /* Build key tag */
    char tag[256];
    snprintf(tag, sizeof(tag), "%s%s", KEY_TAG_PREFIX, identity);

    CFDataRef tag_data = CFDataCreate(kCFAllocatorDefault, (const UInt8*)tag, strlen(tag));
    if (!tag_data) {
        if (out_error) *out_error = HSM_ERR_MEMORY;
        return NULL;
    }
    cf_guard_add(&guard, tag_data);

    /* === Phase 1: Try to find existing key === */
    CFMutableDictionaryRef query = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                            &kCFTypeDictionaryKeyCallBacks,
                                            &kCFTypeDictionaryValueCallBacks);
    if (!query) {
        cf_guard_release(&guard);
        if (out_error) *out_error = HSM_ERR_MEMORY;
        return NULL;
    }
    cf_guard_add(&guard, query);

    CFDictionarySetValue(query, kSecClass, kSecClassKey);
    CFDictionarySetValue(query, kSecAttrApplicationTag, tag_data);
    CFDictionarySetValue(query, kSecAttrKeyType, kSecAttrKeyTypeECSECPrimeRandom);
    CFDictionarySetValue(query, kSecReturnRef, kCFBooleanTrue);

    SecKeyRef key = NULL;
    OSStatus status = SecItemCopyMatching(query, (CFTypeRef*)&key);

    if (status == errSecSuccess && key) {
        /* Key found - return it (caller owns reference) */
        cf_guard_release(&guard);
        if (out_error) *out_error = HSM_SUCCESS;
        return key;
    }

    /* === Phase 2: Create new SE key === */

    /* Configure access control based on biometric requirement */
    SecAccessControlCreateFlags ac_flags = kSecAccessControlPrivateKeyUsage;
    if (g_require_biometric) {
        ac_flags |= kSecAccessControlBiometryCurrentSet;
    }

    SecAccessControlRef access_control = SecAccessControlCreateWithFlags(
        kCFAllocatorDefault,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ac_flags,
        &cf_error
    );

    if (!access_control) {
        hsm_error_t err = cferror_to_hsm_error(cf_error);
        if (cf_error) CFRelease(cf_error);
        cf_guard_release(&guard);
        if (out_error) *out_error = err;
        return NULL;
    }
    cf_guard_add(&guard, access_control);

    /* Key size */
    int key_size = 256;
    CFNumberRef key_size_ref = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &key_size);
    if (!key_size_ref) {
        cf_guard_release(&guard);
        if (out_error) *out_error = HSM_ERR_MEMORY;
        return NULL;
    }
    cf_guard_add(&guard, key_size_ref);

    /* Private key attributes */
    CFMutableDictionaryRef private_attrs = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                            &kCFTypeDictionaryKeyCallBacks,
                                            &kCFTypeDictionaryValueCallBacks);
    if (!private_attrs) {
        cf_guard_release(&guard);
        if (out_error) *out_error = HSM_ERR_MEMORY;
        return NULL;
    }
    cf_guard_add(&guard, private_attrs);

    CFDictionarySetValue(private_attrs, kSecAttrIsPermanent, kCFBooleanTrue);
    CFDictionarySetValue(private_attrs, kSecAttrApplicationTag, tag_data);
    CFDictionarySetValue(private_attrs, kSecAttrAccessControl, access_control);

    /* Main key attributes */
    CFMutableDictionaryRef attributes = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                            &kCFTypeDictionaryKeyCallBacks,
                                            &kCFTypeDictionaryValueCallBacks);
    if (!attributes) {
        cf_guard_release(&guard);
        if (out_error) *out_error = HSM_ERR_MEMORY;
        return NULL;
    }
    cf_guard_add(&guard, attributes);

    CFDictionarySetValue(attributes, kSecAttrKeyType, kSecAttrKeyTypeECSECPrimeRandom);
    CFDictionarySetValue(attributes, kSecAttrKeySizeInBits, key_size_ref);
    CFDictionarySetValue(attributes, kSecAttrTokenID, kSecAttrTokenIDSecureEnclave);
    CFDictionarySetValue(attributes, kSecPrivateKeyAttrs, private_attrs);

    key = SecKeyCreateRandomKey(attributes, &cf_error);

    if (!key) {
        hsm_error_t err = cferror_to_hsm_error(cf_error);
        if (cf_error) CFRelease(cf_error);
        cf_guard_release(&guard);
        if (out_error) *out_error = err;
        return NULL;
    }

    cf_guard_release(&guard);
    if (out_error) *out_error = HSM_SUCCESS;
    return key;
}

/*
 * Delete SE key for an identity.
 */
static hsm_error_t delete_se_key(const char* identity) {
    cf_guard_t guard = CF_GUARD_INIT;

    char tag[256];
    snprintf(tag, sizeof(tag), "%s%s", KEY_TAG_PREFIX, identity);

    CFDataRef tag_data;
    HSM_GUARD_ADD(tag_data,
                  CFDataCreate(kCFAllocatorDefault, (const UInt8*)tag, strlen(tag)),
                  &guard, HSM_ERR_MEMORY);

    CFMutableDictionaryRef query;
    HSM_GUARD_ADD(query,
                  CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                            &kCFTypeDictionaryKeyCallBacks,
                                            &kCFTypeDictionaryValueCallBacks),
                  &guard, HSM_ERR_MEMORY);

    CFDictionarySetValue(query, kSecClass, kSecClassKey);
    CFDictionarySetValue(query, kSecAttrApplicationTag, tag_data);

    OSStatus status = SecItemDelete(query);
    cf_guard_release(&guard);

    /* Not found is OK for delete operations */
    if (status == errSecSuccess || status == errSecItemNotFound) {
        return HSM_SUCCESS;
    }
    return osstatus_to_hsm_error(status);
}

/*
 * Store encrypted blob in Keychain.
 * Implements delete-then-add pattern for idempotent storage.
 */
static hsm_error_t store_encrypted_pin(const char* identity, CFDataRef encrypted) {
    cf_guard_t guard = CF_GUARD_INIT;

    char service[256];
    snprintf(service, sizeof(service), "%s%s", SERVICE_PREFIX, identity);

    CFStringRef service_ref;
    HSM_GUARD_ADD(service_ref,
                  CFStringCreateWithCString(kCFAllocatorDefault, service, kCFStringEncodingUTF8),
                  &guard, HSM_ERR_MEMORY);

    /* Delete existing item first (ignore not-found) */
    CFMutableDictionaryRef delete_query;
    HSM_GUARD_ADD(delete_query,
                  CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                            &kCFTypeDictionaryKeyCallBacks,
                                            &kCFTypeDictionaryValueCallBacks),
                  &guard, HSM_ERR_MEMORY);

    CFDictionarySetValue(delete_query, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(delete_query, kSecAttrService, service_ref);
    SecItemDelete(delete_query); /* Ignore result */

    /* Add new item */
    CFMutableDictionaryRef add_query;
    HSM_GUARD_ADD(add_query,
                  CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                            &kCFTypeDictionaryKeyCallBacks,
                                            &kCFTypeDictionaryValueCallBacks),
                  &guard, HSM_ERR_MEMORY);

    CFDictionarySetValue(add_query, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(add_query, kSecAttrService, service_ref);
    CFDictionarySetValue(add_query, kSecValueData, encrypted);
    CFDictionarySetValue(add_query, kSecAttrAccessible,
                         kSecAttrAccessibleWhenUnlockedThisDeviceOnly);

    OSStatus status = SecItemAdd(add_query, NULL);
    cf_guard_release(&guard);

    return osstatus_to_hsm_error(status);
}

/*
 * Retrieve encrypted blob from Keychain.
 */
static CFDataRef retrieve_encrypted_pin(const char* identity, hsm_error_t* out_error) {
    cf_guard_t guard = CF_GUARD_INIT;

    char service[256];
    snprintf(service, sizeof(service), "%s%s", SERVICE_PREFIX, identity);

    CFStringRef service_ref = CFStringCreateWithCString(kCFAllocatorDefault, service, kCFStringEncodingUTF8);
    if (!service_ref) {
        if (out_error) *out_error = HSM_ERR_MEMORY;
        return NULL;
    }
    cf_guard_add(&guard, service_ref);

    CFMutableDictionaryRef query = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                            &kCFTypeDictionaryKeyCallBacks,
                                            &kCFTypeDictionaryValueCallBacks);
    if (!query) {
        cf_guard_release(&guard);
        if (out_error) *out_error = HSM_ERR_MEMORY;
        return NULL;
    }
    cf_guard_add(&guard, query);

    CFDictionarySetValue(query, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(query, kSecAttrService, service_ref);
    CFDictionarySetValue(query, kSecReturnData, kCFBooleanTrue);

    /* Add LAContext attributes for biometric prompt */
    if (g_require_biometric) {
        CFDictionaryRef la_attrs = create_la_context_attrs(identity);
        if (la_attrs) {
            CFDictionarySetValue(query, kSecUseAuthenticationContext, la_attrs);
            cf_guard_add(&guard, la_attrs);
        }
    }

    CFDataRef data = NULL;
    OSStatus status = SecItemCopyMatching(query, (CFTypeRef*)&data);
    cf_guard_release(&guard);

    if (status != errSecSuccess || !data) {
        if (out_error) *out_error = osstatus_to_hsm_error(status);
        return NULL;
    }

    if (out_error) *out_error = HSM_SUCCESS;
    return data; /* Caller owns reference */
}

/* ============================================================================
 * Public API Implementation
 * ============================================================================ */

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

    if (se_available()) {
        status->method = HSM_METHOD_SECURE_ENCLAVE;
        status->available = 1;
        status->description = strdup("macOS Secure Enclave");
        status->version = strdup("1.0.0");
        status->se_biometric_available = 1; /* Assume available on SE-capable Macs */
        status->se_key_exists = 0; /* Would need to check per-identity */
    } else {
        status->method = HSM_METHOD_KEYCHAIN;
        status->available = 1;
        status->description = strdup("macOS Keychain (software fallback)");
        status->version = strdup("1.0.0");
    }

    if (!status->description || !status->version) {
        hsm_status_free(status);
        return HSM_ERR_MEMORY;
    }

    return HSM_SUCCESS;
}

hsm_method_t hsm_available(void) {
    if (se_available()) {
        return HSM_METHOD_SECURE_ENCLAVE;
    }
    return HSM_METHOD_KEYCHAIN;
}

hsm_error_t hsm_initialize(void) {
    g_initialized = 1;
    return HSM_SUCCESS;
}

hsm_error_t hsm_seal_pin(const char* identity,
                         const uint8_t* pin,
                         size_t pin_len) {
    if (!identity || !pin || pin_len == 0 || pin_len > MAX_PIN_LEN) {
        return HSM_ERR_INVALID_IDENTITY;
    }

    cf_guard_t guard = CF_GUARD_INIT;

    if (se_available()) {
        /* === Secure Enclave path === */

        /* Step 1: Get or create SE key */
        hsm_error_t key_err;
        SecKeyRef private_key = get_or_create_se_key(identity, &key_err);
        if (!private_key) {
            return (key_err != HSM_SUCCESS) ? key_err : HSM_ERR_SEAL_FAILED;
        }
        cf_guard_add(&guard, private_key);

        /* Step 2: Get public key for encryption */
        SecKeyRef public_key = SecKeyCopyPublicKey(private_key);
        HSM_TRY_CF(public_key, &guard, HSM_ERR_SEAL_FAILED);
        cf_guard_add(&guard, public_key);

        /* Step 3: Encrypt PIN with ECIES */
        CFDataRef pin_data;
        HSM_GUARD_ADD(pin_data,
                      CFDataCreate(kCFAllocatorDefault, pin, pin_len),
                      &guard, HSM_ERR_MEMORY);

        CFErrorRef cf_error = NULL;
        CFDataRef encrypted = SecKeyCreateEncryptedData(
            public_key,
            kSecKeyAlgorithmECIESEncryptionCofactorVariableIVX963SHA256AESGCM,
            pin_data,
            &cf_error
        );

        if (!encrypted) {
            hsm_error_t err = cferror_to_hsm_error(cf_error);
            if (cf_error) CFRelease(cf_error);
            cf_guard_release(&guard);
            return (err != HSM_SUCCESS) ? err : HSM_ERR_SEAL_FAILED;
        }
        cf_guard_add(&guard, encrypted);

        /* Step 4: Store encrypted blob in Keychain */
        hsm_error_t store_err = store_encrypted_pin(identity, encrypted);
        cf_guard_release(&guard);
        return store_err;
    }

    /* === Keychain fallback path (no SE encryption) === */
    CFDataRef pin_data;
    HSM_GUARD_ADD(pin_data,
                  CFDataCreate(kCFAllocatorDefault, pin, pin_len),
                  &guard, HSM_ERR_MEMORY);

    hsm_error_t store_err = store_encrypted_pin(identity, pin_data);
    cf_guard_release(&guard);
    return store_err;
}

hsm_error_t hsm_unseal_pin(const char* identity,
                           hsm_pin_callback_t callback,
                           void* user_data) {
    if (!identity || !callback) {
        return HSM_ERR_INVALID_IDENTITY;
    }

    /* Step 1: Retrieve encrypted blob from Keychain */
    hsm_error_t retrieve_err;
    CFDataRef encrypted = retrieve_encrypted_pin(identity, &retrieve_err);
    if (!encrypted) {
        return (retrieve_err != HSM_SUCCESS) ? retrieve_err : HSM_ERR_NOT_FOUND;
    }

    cf_guard_t guard = CF_GUARD_INIT;
    cf_guard_add(&guard, encrypted);

    if (se_available()) {
        /* === Secure Enclave decryption path === */

        /* Step 2: Get SE key for decryption */
        hsm_error_t key_err;
        SecKeyRef private_key = get_or_create_se_key(identity, &key_err);
        if (!private_key) {
            cf_guard_release(&guard);
            return (key_err != HSM_SUCCESS) ? key_err : HSM_ERR_UNSEAL_FAILED;
        }
        cf_guard_add(&guard, private_key);

        /* Step 3: Decrypt with SE (may trigger Touch ID) */
        CFErrorRef cf_error = NULL;
        CFDataRef decrypted = SecKeyCreateDecryptedData(
            private_key,
            kSecKeyAlgorithmECIESEncryptionCofactorVariableIVX963SHA256AESGCM,
            encrypted,
            &cf_error
        );

        if (!decrypted) {
            hsm_error_t err = cferror_to_hsm_error(cf_error);
            if (cf_error) CFRelease(cf_error);
            cf_guard_release(&guard);
            return (err != HSM_SUCCESS) ? err : HSM_ERR_UNSEAL_FAILED;
        }
        cf_guard_add(&guard, decrypted);

        /* Step 4: Invoke callback with decrypted PIN */
        const UInt8* pin_bytes = CFDataGetBytePtr(decrypted);
        CFIndex pin_len = CFDataGetLength(decrypted);

        int cb_result = callback(pin_bytes, (size_t)pin_len, user_data);
        cf_guard_release(&guard);

        return (cb_result == 0) ? HSM_SUCCESS : HSM_ERR_INTERNAL;
    }

    /* === Fallback: Data is not encrypted === */
    const UInt8* pin_bytes = CFDataGetBytePtr(encrypted);
    CFIndex pin_len = CFDataGetLength(encrypted);

    int cb_result = callback(pin_bytes, (size_t)pin_len, user_data);
    cf_guard_release(&guard);

    return (cb_result == 0) ? HSM_SUCCESS : HSM_ERR_INTERNAL;
}

int hsm_pin_exists(const char* identity) {
    if (!identity) {
        return -1;
    }

    cf_guard_t guard = CF_GUARD_INIT;

    char service[256];
    snprintf(service, sizeof(service), "%s%s", SERVICE_PREFIX, identity);

    CFStringRef service_ref = CFStringCreateWithCString(kCFAllocatorDefault,
                                                        service,
                                                        kCFStringEncodingUTF8);
    if (!service_ref) return -1;
    cf_guard_add(&guard, service_ref);

    CFMutableDictionaryRef query = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );
    if (!query) {
        cf_guard_release(&guard);
        return -1;
    }
    cf_guard_add(&guard, query);

    CFDictionarySetValue(query, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(query, kSecAttrService, service_ref);

    OSStatus status = SecItemCopyMatching(query, NULL);
    cf_guard_release(&guard);

    return (status == errSecSuccess) ? 1 : 0;
}

hsm_error_t hsm_clear_pin(const char* identity) {
    if (!identity) {
        return HSM_ERR_INVALID_IDENTITY;
    }

    cf_guard_t guard = CF_GUARD_INIT;

    /* Delete from Keychain */
    char service[256];
    snprintf(service, sizeof(service), "%s%s", SERVICE_PREFIX, identity);

    CFStringRef service_ref;
    HSM_GUARD_ADD(service_ref,
                  CFStringCreateWithCString(kCFAllocatorDefault, service, kCFStringEncodingUTF8),
                  &guard, HSM_ERR_MEMORY);

    CFMutableDictionaryRef query;
    HSM_GUARD_ADD(query,
                  CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                            &kCFTypeDictionaryKeyCallBacks,
                                            &kCFTypeDictionaryValueCallBacks),
                  &guard, HSM_ERR_MEMORY);

    CFDictionarySetValue(query, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(query, kSecAttrService, service_ref);

    OSStatus status = SecItemDelete(query);
    cf_guard_release(&guard);

    /* Also delete SE key */
    delete_se_key(identity);

    return (status == errSecSuccess || status == errSecItemNotFound)
           ? HSM_SUCCESS : osstatus_to_hsm_error(status);
}

hsm_error_t hsm_clear_all(void) {
    cf_guard_t guard = CF_GUARD_INIT;

    /* Query for all items with our service prefix */
    CFStringRef service_prefix;
    HSM_GUARD_ADD(service_prefix,
                  CFStringCreateWithCString(kCFAllocatorDefault, SERVICE_PREFIX, kCFStringEncodingUTF8),
                  &guard, HSM_ERR_MEMORY);

    CFMutableDictionaryRef query;
    HSM_GUARD_ADD(query,
                  CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                            &kCFTypeDictionaryKeyCallBacks,
                                            &kCFTypeDictionaryValueCallBacks),
                  &guard, HSM_ERR_MEMORY);

    CFDictionarySetValue(query, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(query, kSecMatchLimit, kSecMatchLimitAll);
    CFDictionarySetValue(query, kSecReturnAttributes, kCFBooleanTrue);

    CFArrayRef items = NULL;
    OSStatus status = SecItemCopyMatching(query, (CFTypeRef*)&items);

    if (status == errSecSuccess && items) {
        cf_guard_add(&guard, items);

        CFIndex count = CFArrayGetCount(items);
        for (CFIndex i = 0; i < count; i++) {
            CFDictionaryRef item = CFArrayGetValueAtIndex(items, i);
            CFStringRef item_service = CFDictionaryGetValue(item, kSecAttrService);

            if (item_service && CFStringHasPrefix(item_service, service_prefix)) {
                /* Delete this item */
                CFMutableDictionaryRef delete_query = CFDictionaryCreateMutable(
                    kCFAllocatorDefault, 0,
                    &kCFTypeDictionaryKeyCallBacks,
                    &kCFTypeDictionaryValueCallBacks
                );
                if (delete_query) {
                    CFDictionarySetValue(delete_query, kSecClass, kSecClassGenericPassword);
                    CFDictionarySetValue(delete_query, kSecAttrService, item_service);
                    SecItemDelete(delete_query);
                    CFRelease(delete_query);

                    /* Extract identity name and delete SE key */
                    char service_buf[256];
                    if (CFStringGetCString(item_service, service_buf, sizeof(service_buf),
                                           kCFStringEncodingUTF8)) {
                        size_t prefix_len = strlen(SERVICE_PREFIX);
                        if (strlen(service_buf) > prefix_len) {
                            delete_se_key(service_buf + prefix_len);
                        }
                    }
                }
            }
        }
    }

    cf_guard_release(&guard);
    return HSM_SUCCESS;
}

const char* hsm_error_message(hsm_error_t error) {
    static const char* messages[] = {
        [HSM_SUCCESS] = "Success",
        [HSM_ERR_NOT_AVAILABLE] = "HSM hardware not available",
        [HSM_ERR_NOT_INITIALIZED] = "HSM not initialized",
        [HSM_ERR_INVALID_IDENTITY] = "Invalid identity name",
        [HSM_ERR_SEAL_FAILED] = "Failed to seal PIN with Secure Enclave",
        [HSM_ERR_UNSEAL_FAILED] = "Failed to unseal PIN with Secure Enclave",
        [HSM_ERR_NOT_FOUND] = "No PIN stored for identity",
        [HSM_ERR_AUTH_FAILED] = "Authentication failed (Touch ID required?)",
        [HSM_ERR_PCR_MISMATCH] = "N/A for Secure Enclave",
        [HSM_ERR_MEMORY] = "Memory allocation failed",
        [HSM_ERR_IO] = "Keychain I/O error",
        [HSM_ERR_PERMISSION] = "Permission denied",
        [HSM_ERR_TIMEOUT] = "Operation timed out",
        [HSM_ERR_CANCELLED] = "Operation cancelled by user",
        [HSM_ERR_INTERNAL] = "Internal error",
    };

    if (error >= 0 && error < sizeof(messages) / sizeof(messages[0])) {
        return messages[error];
    }
    return "Unknown error";
}

char** hsm_list_identities(size_t* count) {
    if (count) *count = 0;

    cf_guard_t guard = CF_GUARD_INIT;

    /* Query all generic password items */
    CFMutableDictionaryRef query = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                            &kCFTypeDictionaryKeyCallBacks,
                                            &kCFTypeDictionaryValueCallBacks);
    if (!query) {
        return NULL;
    }
    cf_guard_add(&guard, query);

    CFDictionarySetValue(query, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(query, kSecMatchLimit, kSecMatchLimitAll);
    CFDictionarySetValue(query, kSecReturnAttributes, kCFBooleanTrue);

    CFArrayRef items = NULL;
    OSStatus status = SecItemCopyMatching(query, (CFTypeRef*)&items);

    if (status != errSecSuccess || !items) {
        cf_guard_release(&guard);
        return NULL;
    }
    cf_guard_add(&guard, items);

    /* First pass: count matching items */
    size_t prefix_len = strlen(SERVICE_PREFIX);
    CFIndex total_items = CFArrayGetCount(items);
    size_t matching_count = 0;

    for (CFIndex i = 0; i < total_items; i++) {
        CFDictionaryRef item = CFArrayGetValueAtIndex(items, i);
        CFStringRef item_service = CFDictionaryGetValue(item, kSecAttrService);

        if (item_service) {
            char service_buf[256];
            if (CFStringGetCString(item_service, service_buf, sizeof(service_buf),
                                   kCFStringEncodingUTF8)) {
                if (strncmp(service_buf, SERVICE_PREFIX, prefix_len) == 0) {
                    matching_count++;
                }
            }
        }
    }

    if (matching_count == 0) {
        cf_guard_release(&guard);
        return NULL;
    }

    /* Allocate result array (NULL-terminated) */
    char** identities = calloc(matching_count + 1, sizeof(char*));
    if (!identities) {
        cf_guard_release(&guard);
        return NULL;
    }

    /* Second pass: extract identity names */
    size_t result_idx = 0;
    for (CFIndex i = 0; i < total_items && result_idx < matching_count; i++) {
        CFDictionaryRef item = CFArrayGetValueAtIndex(items, i);
        CFStringRef item_service = CFDictionaryGetValue(item, kSecAttrService);

        if (item_service) {
            char service_buf[256];
            if (CFStringGetCString(item_service, service_buf, sizeof(service_buf),
                                   kCFStringEncodingUTF8)) {
                if (strncmp(service_buf, SERVICE_PREFIX, prefix_len) == 0) {
                    /* Extract identity name after prefix */
                    const char* identity_name = service_buf + prefix_len;
                    identities[result_idx] = strdup(identity_name);
                    if (!identities[result_idx]) {
                        /* Cleanup on allocation failure */
                        for (size_t j = 0; j < result_idx; j++) {
                            free(identities[j]);
                        }
                        free(identities);
                        cf_guard_release(&guard);
                        return NULL;
                    }
                    result_idx++;
                }
            }
        }
    }

    identities[result_idx] = NULL; /* NULL-terminate */
    if (count) *count = result_idx;

    cf_guard_release(&guard);
    return identities;
}

hsm_error_t hsm_tpm_set_pcr_binding(uint32_t pcr_mask) {
    (void)pcr_mask;
    return HSM_ERR_NOT_AVAILABLE;
}

hsm_error_t hsm_se_set_biometric(int require_biometric) {
    g_require_biometric = require_biometric;
    return HSM_SUCCESS;
}

#else /* !__APPLE__ */

/* Stub for non-Apple platforms */
#include "hsm_stub.c"

#endif /* __APPLE__ */
