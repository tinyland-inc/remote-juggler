/*
 * hsm_secure_enclave.c - Secure Enclave backend implementation (macOS)
 *
 * This file implements PIN encryption/decryption using Apple Secure Enclave
 * via Security.framework. PINs are encrypted with ECIES using an SE-protected key.
 *
 * COMPILE:
 *   clang -DHAS_SECURE_ENCLAVE hsm_secure_enclave.c -o hsm_secure_enclave.o \
 *         -framework Security -framework LocalAuthentication
 *
 * HARDWARE REQUIREMENTS:
 *   - Mac with T1, T2, or Apple Silicon (M1/M2/M3+)
 *   - Or iOS device with A7+ chip
 *
 * SECURITY MODEL:
 *   - EC P-256 key pair generated in Secure Enclave
 *   - Private key never leaves the Secure Enclave
 *   - Decryption requires user authentication (Touch ID, Face ID, or password)
 *   - Encrypted blob stored in Keychain
 */

#ifdef __APPLE__
#ifdef HAS_SECURE_ENCLAVE

#include "hsm_secure_enclave.h"
#include "hsm.h"

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* Apple Security frameworks */
#include <Security/Security.h>
#include <LocalAuthentication/LocalAuthentication.h>

/* For CFBridgingRelease/Retain when using Objective-C runtime */
#ifdef __OBJC__
#import <Foundation/Foundation.h>
#else
/* Pure C - we'll use CF types directly */
#endif

/* ============================================================================
 * Static State
 * ============================================================================ */

/* Custom authentication reason string */
static const char* s_auth_reason = "authenticate to access YubiKey PIN";

/* ============================================================================
 * Secure Enclave Detection
 * ============================================================================ */

int se_is_available(void) {
    /*
     * Check if Secure Enclave is available by attempting to query
     * for SE key generation capability.
     *
     * On Macs without SE (pre-T1), this will return false.
     * On iOS devices without SE (pre-A7), this will return false.
     */

    /* Create access control for SE key */
    CFErrorRef error = NULL;
    SecAccessControlRef accessControl = SecAccessControlCreateWithFlags(
        kCFAllocatorDefault,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        kSecAccessControlPrivateKeyUsage,
        &error
    );

    if (accessControl == NULL) {
        if (error != NULL) {
            CFRelease(error);
        }
        return 0;
    }

    /* Check if we can create SE keys by querying capabilities */
    CFDictionaryRef attributes = CFDictionaryCreate(
        kCFAllocatorDefault,
        (const void*[]){
            kSecAttrKeyType,
            kSecAttrKeySizeInBits,
            kSecAttrTokenID
        },
        (const void*[]){
            kSecAttrKeyTypeECSECPrimeRandom,
            (__bridge CFNumberRef)@(256),
            kSecAttrTokenIDSecureEnclave
        },
        3,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );

    /*
     * TODO: Actually test SE key creation capability
     *
     * A robust check would:
     * 1. Try to generate a test key in SE
     * 2. Delete it immediately
     * 3. Return success if generation worked
     *
     * For now, we check based on known hardware support.
     */

    CFRelease(accessControl);
    if (attributes != NULL) {
        CFRelease(attributes);
    }

    /*
     * TODO: Implement proper SE detection
     * For now, assume SE is available on macOS 10.13+ with T1/T2/Apple Silicon
     */

    return 1;  /* Stub: assume available */
}

int se_has_biometry(void) {
    /*
     * TODO: Check LAContext canEvaluatePolicy for biometry
     *
     * LAContext* context = [[LAContext alloc] init];
     * NSError* error = nil;
     * BOOL canEvaluate = [context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
     *                                         error:&error];
     * return canEvaluate ? 1 : 0;
     */
    return 1;  /* Stub: assume available */
}

const char* se_biometry_type(void) {
    /*
     * TODO: Query LAContext biometryType
     *
     * LAContext* context = [[LAContext alloc] init];
     * [context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:nil];
     *
     * switch (context.biometryType) {
     *     case LABiometryTypeTouchID: return "Touch ID";
     *     case LABiometryTypeFaceID: return "Face ID";
     *     case LABiometryTypeOpticID: return "Optic ID";
     *     default: return "Passcode";
     * }
     */
    return "Touch ID";  /* Stub */
}

/* ============================================================================
 * Key Tag Helper
 * ============================================================================ */

char* se_get_key_tag(const char* identity) {
    if (identity == NULL || identity[0] == '\0') {
        return NULL;
    }

    size_t prefix_len = strlen(SE_KEY_TAG_PREFIX);
    size_t identity_len = strlen(identity);
    size_t total_len = prefix_len + identity_len + 1;

    char* tag = (char*)malloc(total_len);
    if (tag == NULL) {
        return NULL;
    }

    snprintf(tag, total_len, "%s%s", SE_KEY_TAG_PREFIX, identity);
    return tag;
}

/* ============================================================================
 * Secure Enclave Key Management
 * ============================================================================ */

HSMStatus se_create_key(const char* identity, int require_bio) {
    if (identity == NULL || identity[0] == '\0') {
        return HSM_ERR_INVALID_PARAM;
    }

    /* Check if key already exists */
    if (se_has_key(identity)) {
        return HSM_SUCCESS;  /* Key exists, don't regenerate */
    }

    char* key_tag = se_get_key_tag(identity);
    if (key_tag == NULL) {
        return HSM_ERR_MEMORY;
    }

    /*
     * TODO: Generate EC P-256 key pair in Secure Enclave
     *
     * CFErrorRef error = NULL;
     *
     * // Create access control
     * SecAccessControlCreateFlags flags = kSecAccessControlPrivateKeyUsage;
     * if (require_bio) {
     *     flags |= kSecAccessControlBiometryCurrentSet;
     * } else {
     *     flags |= kSecAccessControlDevicePasscode;
     * }
     *
     * SecAccessControlRef accessControl = SecAccessControlCreateWithFlags(
     *     kCFAllocatorDefault,
     *     kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
     *     flags,
     *     &error
     * );
     *
     * // Key attributes
     * CFDataRef tagData = CFDataCreate(NULL, (UInt8*)key_tag, strlen(key_tag));
     *
     * CFDictionaryRef attributes = @{
     *     (id)kSecAttrKeyType: (id)kSecAttrKeyTypeECSECPrimeRandom,
     *     (id)kSecAttrKeySizeInBits: @256,
     *     (id)kSecAttrTokenID: (id)kSecAttrTokenIDSecureEnclave,
     *     (id)kSecPrivateKeyAttrs: @{
     *         (id)kSecAttrIsPermanent: @YES,
     *         (id)kSecAttrApplicationTag: (__bridge id)tagData,
     *         (id)kSecAttrAccessControl: (__bridge id)accessControl,
     *     },
     * };
     *
     * SecKeyRef privateKey = SecKeyCreateRandomKey(
     *     (__bridge CFDictionaryRef)attributes,
     *     &error
     * );
     *
     * if (privateKey == NULL) {
     *     // Handle error
     *     return HSM_ERR_SE_NOT_READY;
     * }
     *
     * CFRelease(privateKey);
     * CFRelease(tagData);
     * CFRelease(accessControl);
     */

    free(key_tag);

    /* TODO: Remove stub */
    return HSM_ERR_NOT_AVAILABLE;
}

HSMStatus se_delete_key(const char* identity) {
    if (identity == NULL || identity[0] == '\0') {
        return HSM_ERR_INVALID_PARAM;
    }

    char* key_tag = se_get_key_tag(identity);
    if (key_tag == NULL) {
        return HSM_ERR_MEMORY;
    }

    /*
     * TODO: Delete SE key from Keychain
     *
     * CFDataRef tagData = CFDataCreate(NULL, (UInt8*)key_tag, strlen(key_tag));
     *
     * CFDictionaryRef query = @{
     *     (id)kSecClass: (id)kSecClassKey,
     *     (id)kSecAttrApplicationTag: (__bridge id)tagData,
     *     (id)kSecAttrKeyType: (id)kSecAttrKeyTypeECSECPrimeRandom,
     * };
     *
     * OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
     * CFRelease(tagData);
     *
     * if (status == errSecItemNotFound) {
     *     return HSM_ERR_KEY_NOT_FOUND;
     * }
     * if (status != errSecSuccess) {
     *     return HSM_ERR_IO;
     * }
     */

    free(key_tag);

    /* Also delete encrypted PIN blob */
    se_delete_encrypted_pin(identity);

    /* TODO: Remove stub */
    return HSM_ERR_NOT_AVAILABLE;
}

int se_has_key(const char* identity) {
    if (identity == NULL || identity[0] == '\0') {
        return 0;
    }

    char* key_tag = se_get_key_tag(identity);
    if (key_tag == NULL) {
        return 0;
    }

    /*
     * TODO: Query for SE key existence
     *
     * CFDataRef tagData = CFDataCreate(NULL, (UInt8*)key_tag, strlen(key_tag));
     *
     * CFDictionaryRef query = @{
     *     (id)kSecClass: (id)kSecClassKey,
     *     (id)kSecAttrApplicationTag: (__bridge id)tagData,
     *     (id)kSecAttrKeyType: (id)kSecAttrKeyTypeECSECPrimeRandom,
     *     (id)kSecReturnRef: @NO,
     * };
     *
     * OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, NULL);
     * CFRelease(tagData);
     *
     * return (status == errSecSuccess) ? 1 : 0;
     */

    free(key_tag);
    return 0;  /* Stub */
}

/* ============================================================================
 * Secure Enclave Encryption Operations
 * ============================================================================ */

HSMStatus se_encrypt_pin(const char* identity, const char* pin, size_t pin_len) {
    if (identity == NULL || identity[0] == '\0') {
        return HSM_ERR_INVALID_PARAM;
    }
    if (pin == NULL || pin_len == 0) {
        return HSM_ERR_INVALID_PARAM;
    }

    /* Ensure key exists */
    HSMStatus status = se_create_key(identity, 0);
    if (status != HSM_SUCCESS) {
        return status;
    }

    char* key_tag = se_get_key_tag(identity);
    if (key_tag == NULL) {
        return HSM_ERR_MEMORY;
    }

    /*
     * TODO: Encrypt PIN using SE public key and store in Keychain
     *
     * // 1. Get public key from SE
     * CFDataRef tagData = CFDataCreate(NULL, (UInt8*)key_tag, strlen(key_tag));
     *
     * CFDictionaryRef query = @{
     *     (id)kSecClass: (id)kSecClassKey,
     *     (id)kSecAttrApplicationTag: (__bridge id)tagData,
     *     (id)kSecAttrKeyType: (id)kSecAttrKeyTypeECSECPrimeRandom,
     *     (id)kSecReturnRef: @YES,
     * };
     *
     * SecKeyRef privateKey = NULL;
     * OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef*)&privateKey);
     *
     * SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
     *
     * // 2. Encrypt using ECIES
     * CFDataRef pinData = CFDataCreate(NULL, (UInt8*)pin, pin_len);
     * CFErrorRef error = NULL;
     *
     * CFDataRef encryptedData = SecKeyCreateEncryptedData(
     *     publicKey,
     *     kSecKeyAlgorithmECIESEncryptionCofactorVariableIVX963SHA256AESGCM,
     *     pinData,
     *     &error
     * );
     *
     * // 3. Store encrypted blob in Keychain
     * CFDictionaryRef addQuery = @{
     *     (id)kSecClass: (id)kSecClassGenericPassword,
     *     (id)kSecAttrService: @SE_KEYCHAIN_SERVICE,
     *     (id)kSecAttrAccount: [NSString stringWithUTF8String:identity],
     *     (id)kSecValueData: (__bridge id)encryptedData,
     * };
     *
     * SecItemDelete((__bridge CFDictionaryRef)addQuery);  // Remove existing
     * SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
     *
     * CFRelease(pinData);
     * CFRelease(encryptedData);
     * CFRelease(publicKey);
     * CFRelease(privateKey);
     * CFRelease(tagData);
     */

    free(key_tag);

    /* TODO: Remove stub */
    return HSM_ERR_NOT_AVAILABLE;
}

HSMStatus se_decrypt_pin(const char* identity, char** pin_out, size_t* pin_len_out) {
    if (identity == NULL || identity[0] == '\0') {
        return HSM_ERR_INVALID_PARAM;
    }
    if (pin_out == NULL || pin_len_out == NULL) {
        return HSM_ERR_INVALID_PARAM;
    }

    *pin_out = NULL;
    *pin_len_out = 0;

    if (!se_has_encrypted_pin(identity)) {
        return HSM_ERR_KEY_NOT_FOUND;
    }

    char* key_tag = se_get_key_tag(identity);
    if (key_tag == NULL) {
        return HSM_ERR_MEMORY;
    }

    /*
     * TODO: Decrypt PIN using SE private key (triggers auth prompt)
     *
     * // 1. Get encrypted blob from Keychain
     * CFDictionaryRef query = @{
     *     (id)kSecClass: (id)kSecClassGenericPassword,
     *     (id)kSecAttrService: @SE_KEYCHAIN_SERVICE,
     *     (id)kSecAttrAccount: [NSString stringWithUTF8String:identity],
     *     (id)kSecReturnData: @YES,
     * };
     *
     * CFDataRef encryptedData = NULL;
     * OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef*)&encryptedData);
     *
     * // 2. Get SE private key
     * CFDataRef tagData = CFDataCreate(NULL, (UInt8*)key_tag, strlen(key_tag));
     *
     * CFDictionaryRef keyQuery = @{
     *     (id)kSecClass: (id)kSecClassKey,
     *     (id)kSecAttrApplicationTag: (__bridge id)tagData,
     *     (id)kSecAttrKeyType: (id)kSecAttrKeyTypeECSECPrimeRandom,
     *     (id)kSecReturnRef: @YES,
     *     (id)kSecUseOperationPrompt: [NSString stringWithUTF8String:s_auth_reason],
     * };
     *
     * SecKeyRef privateKey = NULL;
     * status = SecItemCopyMatching((__bridge CFDictionaryRef)keyQuery, (CFTypeRef*)&privateKey);
     *
     * // 3. Decrypt (this triggers the authentication prompt)
     * CFErrorRef error = NULL;
     * CFDataRef decryptedData = SecKeyCreateDecryptedData(
     *     privateKey,
     *     kSecKeyAlgorithmECIESEncryptionCofactorVariableIVX963SHA256AESGCM,
     *     encryptedData,
     *     &error
     * );
     *
     * if (decryptedData == NULL) {
     *     // Authentication failed or cancelled
     *     return HSM_ERR_AUTH_FAILED;
     * }
     *
     * // 4. Copy to output
     * CFIndex len = CFDataGetLength(decryptedData);
     * *pin_out = (char*)malloc(len + 1);
     * memcpy(*pin_out, CFDataGetBytePtr(decryptedData), len);
     * (*pin_out)[len] = '\0';
     * *pin_len_out = len;
     *
     * CFRelease(decryptedData);
     * CFRelease(privateKey);
     * CFRelease(encryptedData);
     * CFRelease(tagData);
     */

    free(key_tag);

    /* TODO: Remove stub */
    return HSM_ERR_NOT_AVAILABLE;
}

int se_has_encrypted_pin(const char* identity) {
    if (identity == NULL || identity[0] == '\0') {
        return 0;
    }

    /*
     * TODO: Check if encrypted blob exists in Keychain
     *
     * CFDictionaryRef query = @{
     *     (id)kSecClass: (id)kSecClassGenericPassword,
     *     (id)kSecAttrService: @SE_KEYCHAIN_SERVICE,
     *     (id)kSecAttrAccount: [NSString stringWithUTF8String:identity],
     *     (id)kSecReturnData: @NO,
     * };
     *
     * OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, NULL);
     * return (status == errSecSuccess) ? 1 : 0;
     */

    return 0;  /* Stub */
}

HSMStatus se_delete_encrypted_pin(const char* identity) {
    if (identity == NULL || identity[0] == '\0') {
        return HSM_ERR_INVALID_PARAM;
    }

    /*
     * TODO: Delete encrypted blob from Keychain
     *
     * CFDictionaryRef query = @{
     *     (id)kSecClass: (id)kSecClassGenericPassword,
     *     (id)kSecAttrService: @SE_KEYCHAIN_SERVICE,
     *     (id)kSecAttrAccount: [NSString stringWithUTF8String:identity],
     * };
     *
     * OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
     *
     * if (status == errSecItemNotFound) {
     *     return HSM_ERR_KEY_NOT_FOUND;
     * }
     * if (status != errSecSuccess) {
     *     return HSM_ERR_IO;
     * }
     */

    /* TODO: Remove stub */
    return HSM_ERR_NOT_AVAILABLE;
}

/* ============================================================================
 * Authentication Context
 * ============================================================================ */

void se_set_auth_reason(const char* reason) {
    if (reason != NULL && reason[0] != '\0') {
        s_auth_reason = reason;
    }
}

int se_auth_required(const char* identity) {
    /*
     * TODO: Check if LAContext has cached authentication
     *
     * This is tricky because LAContext caching depends on:
     * - Time since last authentication
     * - System settings
     * - Whether the device was locked
     *
     * For simplicity, always return 1 (auth required).
     * The actual authentication caching is handled by the system.
     */
    (void)identity;
    return 1;
}

#endif /* HAS_SECURE_ENCLAVE */
#endif /* __APPLE__ */
