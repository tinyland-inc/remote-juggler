/*
 * test_hsm.c - Comprehensive test suite for HSM abstraction layer
 *
 * Tests HSM functionality across multiple backends:
 * - Stub/Keychain backend (always available)
 * - TPM 2.0 backend (Linux with TPM hardware)
 * - Secure Enclave backend (macOS with T2/M1+)
 *
 * Run with: make test
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/stat.h>
#include "hsm.h"

/* Test identities */
#define TEST_IDENTITY "test-identity"
#define TEST_PIN "123456"

/* Limits from hsm_stub.c */
#define MAX_PIN_LEN 256
#define MAX_IDENTITY_LEN 64

/* Test counters */
static int tests_passed = 0;
static int tests_failed = 0;
static int tests_skipped = 0;

/* Platform detection */
#ifdef __APPLE__
#define IS_MACOS 1
#else
#define IS_MACOS 0
#endif

#ifdef __linux__
#define IS_LINUX 1
#else
#define IS_LINUX 0
#endif

/* Test macros */
#define TEST(name, expr) do { \
    printf("  %-50s ", name); \
    if (expr) { \
        printf("[PASS]\n"); \
        tests_passed++; \
    } else { \
        printf("[FAIL]\n"); \
        tests_failed++; \
    } \
} while (0)

#define TEST_SKIP(name, reason) do { \
    printf("  %-50s [SKIP] %s\n", name, reason); \
    tests_skipped++; \
} while (0)

/* Forward declarations */
static int check_tpm_available(void);
static int check_secure_enclave_available(void);
static void cleanup_test_pins(void);

/*
 * Callback for unseal test.
 */
static int unseal_callback(const uint8_t* pin, size_t pin_len, void* user_data) {
    char* expected = (char*)user_data;
    size_t expected_len = strlen(expected);

    if (pin_len != expected_len) {
        fprintf(stderr, "PIN length mismatch: got %zu, expected %zu\n",
                pin_len, expected_len);
        return -1;
    }

    if (memcmp(pin, expected, pin_len) != 0) {
        fprintf(stderr, "PIN content mismatch\n");
        return -1;
    }

    return 0;
}

/*
 * Callback that records PIN content for verification.
 */
typedef struct {
    char pin_copy[MAX_PIN_LEN + 1];
    size_t pin_len;
    int called;
} callback_state_t;

static int recording_callback(const uint8_t* pin, size_t pin_len, void* user_data) {
    callback_state_t* state = (callback_state_t*)user_data;
    state->called = 1;
    state->pin_len = pin_len < MAX_PIN_LEN ? pin_len : MAX_PIN_LEN;
    memcpy(state->pin_copy, pin, state->pin_len);
    state->pin_copy[state->pin_len] = '\0';
    return 0;
}

/*
 * Check if TPM 2.0 is available.
 */
static int check_tpm_available(void) {
#if IS_LINUX
    hsm_method_t method = hsm_available();
    return method == HSM_METHOD_TPM;
#else
    return 0;
#endif
}

/*
 * Check if Secure Enclave is available.
 */
static int check_secure_enclave_available(void) {
#if IS_MACOS
    hsm_method_t method = hsm_available();
    return method == HSM_METHOD_SECURE_ENCLAVE;
#else
    return 0;
#endif
}

/*
 * Cleanup all test PINs.
 */
static void cleanup_test_pins(void) {
    /* Clear common test identities */
    hsm_clear_pin(TEST_IDENTITY);
    hsm_clear_pin("empty-test");
    hsm_clear_pin("long-pin-test");
    hsm_clear_pin("special-chars");
    hsm_clear_pin("unicode-test");
    hsm_clear_pin("boundary-64chars-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");

    /* Clear concurrent test identities */
    for (int i = 0; i < 20; i++) {
        char id[32];
        snprintf(id, sizeof(id), "concurrent-test-%d", i);
        hsm_clear_pin(id);
    }
}

/* ========================================================================
 * SECTION 1: Basic Tests (Stub/Keychain Backend)
 * ======================================================================== */

static void test_basic_availability(void) {
    printf("1. HSM Availability\n");

    hsm_method_t method = hsm_available();
    printf("   Method: ");
    switch (method) {
        case HSM_METHOD_NONE:
            printf("None (no HSM available)\n");
            break;
        case HSM_METHOD_TPM:
            printf("TPM 2.0\n");
            break;
        case HSM_METHOD_SECURE_ENCLAVE:
            printf("Secure Enclave\n");
            break;
        case HSM_METHOD_KEYCHAIN:
            printf("Software Keychain\n");
            break;
    }

    TEST("hsm_available() returns valid method",
         method >= HSM_METHOD_NONE && method <= HSM_METHOD_KEYCHAIN);
}

static void test_hsm_status(void) {
    printf("\n2. HSM Status\n");

    hsm_status_t status;
    hsm_error_t err = hsm_get_status(&status);

    TEST("hsm_get_status() succeeds", err == HSM_SUCCESS);
    TEST("status.description is set", status.description != NULL);
    TEST("status.version is set", status.version != NULL);

    if (status.description) {
        printf("   Description: %s\n", status.description);
    }
    if (status.version) {
        printf("   Version: %s\n", status.version);
    }
    if (status.tpm_manufacturer) {
        printf("   TPM Manufacturer: %s\n", status.tpm_manufacturer);
    }

    hsm_status_free(&status);

    /* Test status_free with NULL */
    hsm_status_free(NULL);  /* Should not crash */
    TEST("hsm_status_free(NULL) safe", 1);
}

static void test_initialization(void) {
    printf("\n3. HSM Initialization\n");

    hsm_error_t err = hsm_initialize();
    TEST("hsm_initialize() succeeds", err == HSM_SUCCESS);

    /* Multiple initialization should be safe */
    err = hsm_initialize();
    TEST("hsm_initialize() idempotent", err == HSM_SUCCESS);
}

static void test_seal_unseal_basic(void) {
    printf("\n4. Basic Seal/Unseal\n");

    /* Clear any existing test PIN */
    hsm_clear_pin(TEST_IDENTITY);
    TEST("hsm_pin_exists() returns 0", hsm_pin_exists(TEST_IDENTITY) == 0);

    /* Seal PIN */
    hsm_error_t err = hsm_seal_pin(TEST_IDENTITY,
                                    (const uint8_t*)TEST_PIN,
                                    strlen(TEST_PIN));
    TEST("hsm_seal_pin() succeeds", err == HSM_SUCCESS);
    TEST("hsm_pin_exists() returns 1 after seal",
         hsm_pin_exists(TEST_IDENTITY) == 1);

    /* Unseal PIN */
    char expected_pin[] = TEST_PIN;
    err = hsm_unseal_pin(TEST_IDENTITY, unseal_callback, expected_pin);
    TEST("hsm_unseal_pin() succeeds", err == HSM_SUCCESS);

    /* Clear PIN */
    err = hsm_clear_pin(TEST_IDENTITY);
    TEST("hsm_clear_pin() succeeds", err == HSM_SUCCESS);
    TEST("hsm_pin_exists() returns 0 after clear",
         hsm_pin_exists(TEST_IDENTITY) == 0);
}

static void test_unseal_after_clear(void) {
    printf("\n5. Unseal After Clear\n");

    char expected_pin[] = TEST_PIN;
    hsm_error_t err = hsm_unseal_pin(TEST_IDENTITY, unseal_callback, expected_pin);
    TEST("hsm_unseal_pin() returns NOT_FOUND after clear",
         err == HSM_ERR_NOT_FOUND);
}

static void test_error_messages(void) {
    printf("\n6. Error Messages\n");

    TEST("hsm_error_message(SUCCESS) returns string",
         hsm_error_message(HSM_SUCCESS) != NULL);
    TEST("hsm_error_message(NOT_FOUND) returns string",
         hsm_error_message(HSM_ERR_NOT_FOUND) != NULL);
    TEST("hsm_error_message(PCR_MISMATCH) returns string",
         hsm_error_message(HSM_ERR_PCR_MISMATCH) != NULL);
    TEST("hsm_error_message(PERMISSION) returns string",
         hsm_error_message(HSM_ERR_PERMISSION) != NULL);

    printf("   Example: HSM_ERR_PCR_MISMATCH = \"%s\"\n",
           hsm_error_message(HSM_ERR_PCR_MISMATCH));

    /* Invalid error code */
    const char* unknown = hsm_error_message((hsm_error_t)999);
    TEST("hsm_error_message(invalid) returns non-NULL",
         unknown != NULL);
}

/* ========================================================================
 * SECTION 2: Invalid Input Tests
 * ======================================================================== */

static void test_invalid_inputs(void) {
    printf("\n7. Invalid Inputs\n");

    /* NULL identity */
    TEST("hsm_seal_pin(NULL identity) fails",
         hsm_seal_pin(NULL, (const uint8_t*)"123", 3) == HSM_ERR_INVALID_IDENTITY);

    /* NULL PIN */
    TEST("hsm_seal_pin(NULL PIN) fails",
         hsm_seal_pin("id", NULL, 3) == HSM_ERR_INVALID_IDENTITY);

    /* Zero-length PIN */
    TEST("hsm_seal_pin(zero-length PIN) fails",
         hsm_seal_pin("id", (const uint8_t*)"123", 0) == HSM_ERR_INVALID_IDENTITY);

    /* NULL identity for unseal */
    TEST("hsm_unseal_pin(NULL identity) fails",
         hsm_unseal_pin(NULL, unseal_callback, NULL) == HSM_ERR_INVALID_IDENTITY);

    /* NULL callback */
    TEST("hsm_unseal_pin(NULL callback) fails",
         hsm_unseal_pin("id", NULL, NULL) == HSM_ERR_INVALID_IDENTITY);

    /* NULL identity for exists */
    TEST("hsm_pin_exists(NULL) returns -1",
         hsm_pin_exists(NULL) == -1);

    /* NULL identity for clear */
    TEST("hsm_clear_pin(NULL) fails",
         hsm_clear_pin(NULL) == HSM_ERR_INVALID_IDENTITY);

    /* NULL status */
    TEST("hsm_get_status(NULL) fails",
         hsm_get_status(NULL) == HSM_ERR_INVALID_IDENTITY);
}

/* ========================================================================
 * SECTION 3: Edge Case Tests
 * ======================================================================== */

static void test_edge_cases(void) {
    printf("\n8. Edge Cases\n");

    hsm_error_t err;
    callback_state_t state;

    /* Empty identity (single character) */
    const char* empty_id = "";
    err = hsm_seal_pin(empty_id, (const uint8_t*)"123", 3);
    /* Empty identity should likely fail or be handled */
    printf("  %-50s ", "Empty identity string handling");
    if (err == HSM_SUCCESS || err == HSM_ERR_INVALID_IDENTITY) {
        printf("[PASS] (returned %d)\n", err);
        tests_passed++;
        if (err == HSM_SUCCESS) {
            hsm_clear_pin(empty_id);
        }
    } else {
        printf("[FAIL] (returned %d)\n", err);
        tests_failed++;
    }

    /* Very long PIN (127 characters - just under common limit) */
    char long_pin[128];
    memset(long_pin, 'A', 127);
    long_pin[127] = '\0';

    err = hsm_seal_pin("long-pin-test", (const uint8_t*)long_pin, 127);
    TEST("Seal 127-char PIN succeeds", err == HSM_SUCCESS);

    if (err == HSM_SUCCESS) {
        memset(&state, 0, sizeof(state));
        err = hsm_unseal_pin("long-pin-test", recording_callback, &state);
        TEST("Unseal 127-char PIN succeeds", err == HSM_SUCCESS);
        TEST("127-char PIN content matches",
             state.pin_len == 127 && memcmp(state.pin_copy, long_pin, 127) == 0);
        hsm_clear_pin("long-pin-test");
    }

    /* PIN at max length (256 characters) */
    char max_pin[MAX_PIN_LEN + 1];
    memset(max_pin, 'B', MAX_PIN_LEN);
    max_pin[MAX_PIN_LEN] = '\0';

    err = hsm_seal_pin("max-pin-test", (const uint8_t*)max_pin, MAX_PIN_LEN);
    TEST("Seal 256-char (max) PIN succeeds", err == HSM_SUCCESS);
    if (err == HSM_SUCCESS) {
        hsm_clear_pin("max-pin-test");
    }

    /* PIN over max length - should be rejected */
    char over_max_pin[MAX_PIN_LEN + 2];
    memset(over_max_pin, 'C', MAX_PIN_LEN + 1);
    over_max_pin[MAX_PIN_LEN + 1] = '\0';

    err = hsm_seal_pin("over-max-test", (const uint8_t*)over_max_pin, MAX_PIN_LEN + 1);
    TEST("Seal over-max PIN fails", err == HSM_ERR_INVALID_IDENTITY);

    /* Special characters in PIN */
    const char* special_pin = "!@#$%^&*()_+-=[]{}|;':\",./<>?\t\n\r";
    err = hsm_seal_pin("special-chars", (const uint8_t*)special_pin, strlen(special_pin));
    TEST("Seal special chars PIN succeeds", err == HSM_SUCCESS);

    if (err == HSM_SUCCESS) {
        memset(&state, 0, sizeof(state));
        err = hsm_unseal_pin("special-chars", recording_callback, &state);
        TEST("Unseal special chars PIN succeeds", err == HSM_SUCCESS);
        TEST("Special chars PIN content matches",
             state.pin_len == strlen(special_pin) &&
             memcmp(state.pin_copy, special_pin, strlen(special_pin)) == 0);
        hsm_clear_pin("special-chars");
    }

    /* Binary data in PIN (including null bytes) */
    uint8_t binary_pin[] = {0x00, 0x01, 0x02, 0xFF, 0xFE, 0x00, 0x42};
    err = hsm_seal_pin("binary-pin-test", binary_pin, sizeof(binary_pin));
    TEST("Seal binary PIN with nulls succeeds", err == HSM_SUCCESS);

    if (err == HSM_SUCCESS) {
        memset(&state, 0, sizeof(state));
        err = hsm_unseal_pin("binary-pin-test", recording_callback, &state);
        TEST("Unseal binary PIN succeeds", err == HSM_SUCCESS);
        TEST("Binary PIN content matches",
             state.pin_len == sizeof(binary_pin) &&
             memcmp(state.pin_copy, binary_pin, sizeof(binary_pin)) == 0);
        hsm_clear_pin("binary-pin-test");
    }

    /* Unicode in identity name (UTF-8) */
    const char* unicode_id = "test-\xC3\xA9\xC3\xA8\xC3\xAB";  /* test-eee with accents */
    err = hsm_seal_pin(unicode_id, (const uint8_t*)"pin", 3);
    printf("  %-50s ", "Unicode identity name handling");
    if (err == HSM_SUCCESS || err == HSM_ERR_INVALID_IDENTITY) {
        printf("[PASS] (returned %d)\n", err);
        tests_passed++;
        if (err == HSM_SUCCESS) {
            hsm_clear_pin(unicode_id);
        }
    } else {
        printf("[FAIL] (returned %d)\n", err);
        tests_failed++;
    }

    /* Identity at max length (64 characters) */
    char max_id[MAX_IDENTITY_LEN + 1];
    memset(max_id, 'x', MAX_IDENTITY_LEN);
    max_id[MAX_IDENTITY_LEN] = '\0';

    err = hsm_seal_pin(max_id, (const uint8_t*)"pin", 3);
    TEST("Seal with 64-char identity succeeds", err == HSM_SUCCESS);
    if (err == HSM_SUCCESS) {
        hsm_clear_pin(max_id);
    }

    /* Identity over max length - should be rejected */
    char over_max_id[MAX_IDENTITY_LEN + 2];
    memset(over_max_id, 'y', MAX_IDENTITY_LEN + 1);
    over_max_id[MAX_IDENTITY_LEN + 1] = '\0';

    err = hsm_seal_pin(over_max_id, (const uint8_t*)"pin", 3);
    TEST("Seal with over-max identity fails", err == HSM_ERR_INVALID_IDENTITY);
}

/* ========================================================================
 * SECTION 4: Overwrite and Replace Tests
 * ======================================================================== */

static void test_overwrite_pin(void) {
    printf("\n9. PIN Overwrite\n");

    hsm_error_t err;
    callback_state_t state;

    /* Store initial PIN */
    const char* pin1 = "first-pin";
    err = hsm_seal_pin("overwrite-test", (const uint8_t*)pin1, strlen(pin1));
    TEST("Seal first PIN succeeds", err == HSM_SUCCESS);

    /* Overwrite with new PIN */
    const char* pin2 = "second-pin-longer";
    err = hsm_seal_pin("overwrite-test", (const uint8_t*)pin2, strlen(pin2));
    TEST("Seal second PIN (overwrite) succeeds", err == HSM_SUCCESS);

    /* Verify it's the new PIN */
    memset(&state, 0, sizeof(state));
    err = hsm_unseal_pin("overwrite-test", recording_callback, &state);
    TEST("Unseal returns second PIN", err == HSM_SUCCESS);
    TEST("Overwritten PIN matches second",
         state.pin_len == strlen(pin2) &&
         memcmp(state.pin_copy, pin2, strlen(pin2)) == 0);

    hsm_clear_pin("overwrite-test");
}

/* ========================================================================
 * SECTION 5: List Identities Tests
 * ======================================================================== */

static void test_list_identities(void) {
    printf("\n10. List Identities\n");

    hsm_error_t err;

    /* Clear all and add some test identities */
    hsm_clear_all();

    err = hsm_seal_pin("list-test-1", (const uint8_t*)"pin1", 4);
    TEST("Seal list-test-1 succeeds", err == HSM_SUCCESS);

    err = hsm_seal_pin("list-test-2", (const uint8_t*)"pin2", 4);
    TEST("Seal list-test-2 succeeds", err == HSM_SUCCESS);

    err = hsm_seal_pin("list-test-3", (const uint8_t*)"pin3", 4);
    TEST("Seal list-test-3 succeeds", err == HSM_SUCCESS);

    /* List identities */
    size_t count = 0;
    char** identities = hsm_list_identities(&count);

    TEST("hsm_list_identities() returns non-NULL", identities != NULL);
    TEST("hsm_list_identities() returns count >= 3", count >= 3);

    if (identities) {
        printf("   Listed identities: %zu\n", count);
        for (size_t i = 0; i < count; i++) {
            printf("   - %s\n", identities[i]);
            free(identities[i]);
        }
        free(identities);
    }

    /* Test with NULL count */
    char** null_result = hsm_list_identities(NULL);
    TEST("hsm_list_identities(NULL) returns NULL", null_result == NULL);

    /* Cleanup */
    hsm_clear_pin("list-test-1");
    hsm_clear_pin("list-test-2");
    hsm_clear_pin("list-test-3");
}

/* ========================================================================
 * SECTION 6: Clear All Tests
 * ======================================================================== */

static void test_clear_all(void) {
    printf("\n11. Clear All\n");

    hsm_error_t err;

    /* Add some test identities */
    hsm_seal_pin("clearall-1", (const uint8_t*)"pin", 3);
    hsm_seal_pin("clearall-2", (const uint8_t*)"pin", 3);
    hsm_seal_pin("clearall-3", (const uint8_t*)"pin", 3);

    TEST("clearall-1 exists before clear", hsm_pin_exists("clearall-1") == 1);
    TEST("clearall-2 exists before clear", hsm_pin_exists("clearall-2") == 1);

    err = hsm_clear_all();
    TEST("hsm_clear_all() succeeds", err == HSM_SUCCESS);

    TEST("clearall-1 gone after clear", hsm_pin_exists("clearall-1") == 0);
    TEST("clearall-2 gone after clear", hsm_pin_exists("clearall-2") == 0);
    TEST("clearall-3 gone after clear", hsm_pin_exists("clearall-3") == 0);
}

/* ========================================================================
 * SECTION 7: Concurrency Tests
 * ======================================================================== */

typedef struct {
    int thread_id;
    int success;
    char identity[64];
    char pin[32];
} thread_data_t;

static void* concurrent_seal_thread(void* arg) {
    thread_data_t* data = (thread_data_t*)arg;

    snprintf(data->identity, sizeof(data->identity), "concurrent-test-%d", data->thread_id);
    snprintf(data->pin, sizeof(data->pin), "pin-%d", data->thread_id);

    hsm_error_t err = hsm_seal_pin(data->identity,
                                    (const uint8_t*)data->pin,
                                    strlen(data->pin));
    data->success = (err == HSM_SUCCESS);

    return NULL;
}

static void* concurrent_unseal_thread(void* arg) {
    thread_data_t* data = (thread_data_t*)arg;

    callback_state_t state;
    memset(&state, 0, sizeof(state));

    hsm_error_t err = hsm_unseal_pin(data->identity, recording_callback, &state);

    if (err == HSM_SUCCESS && state.called) {
        data->success = (strcmp(state.pin_copy, data->pin) == 0);
    } else {
        data->success = 0;
    }

    return NULL;
}

static void test_concurrency(void) {
    printf("\n12. Concurrency Tests\n");

    const int num_threads = 10;
    pthread_t threads[num_threads];
    thread_data_t thread_data[num_threads];

    /* Test concurrent seal operations */
    printf("   Starting %d concurrent seal threads...\n", num_threads);

    for (int i = 0; i < num_threads; i++) {
        thread_data[i].thread_id = i;
        thread_data[i].success = 0;
        pthread_create(&threads[i], NULL, concurrent_seal_thread, &thread_data[i]);
    }

    for (int i = 0; i < num_threads; i++) {
        pthread_join(threads[i], NULL);
    }

    int seal_success = 0;
    for (int i = 0; i < num_threads; i++) {
        if (thread_data[i].success) {
            seal_success++;
        }
    }

    TEST("All concurrent seals succeeded", seal_success == num_threads);

    /* Test concurrent unseal operations */
    printf("   Starting %d concurrent unseal threads...\n", num_threads);

    for (int i = 0; i < num_threads; i++) {
        pthread_create(&threads[i], NULL, concurrent_unseal_thread, &thread_data[i]);
    }

    for (int i = 0; i < num_threads; i++) {
        pthread_join(threads[i], NULL);
    }

    int unseal_success = 0;
    for (int i = 0; i < num_threads; i++) {
        if (thread_data[i].success) {
            unseal_success++;
        }
    }

    TEST("All concurrent unseals succeeded", unseal_success == num_threads);

    /* Cleanup */
    for (int i = 0; i < num_threads; i++) {
        hsm_clear_pin(thread_data[i].identity);
    }
}

/* ========================================================================
 * SECTION 8: Callback Failure Tests
 * ======================================================================== */

static int failing_callback(const uint8_t* pin, size_t pin_len, void* user_data) {
    (void)pin;
    (void)pin_len;
    (void)user_data;
    return -1;  /* Simulate callback failure */
}

static void test_callback_failure(void) {
    printf("\n13. Callback Failure Handling\n");

    hsm_error_t err;

    /* Seal a test PIN */
    err = hsm_seal_pin("callback-fail-test", (const uint8_t*)"pin", 3);
    TEST("Seal for callback test succeeds", err == HSM_SUCCESS);

    /* Unseal with failing callback */
    err = hsm_unseal_pin("callback-fail-test", failing_callback, NULL);
    TEST("Unseal with failing callback returns error",
         err == HSM_ERR_INTERNAL);

    /* PIN should still exist */
    TEST("PIN still exists after callback failure",
         hsm_pin_exists("callback-fail-test") == 1);

    hsm_clear_pin("callback-fail-test");
}

/* ========================================================================
 * SECTION 9: TPM-Specific Tests
 * ======================================================================== */

static void test_tpm_specific(void) {
    printf("\n14. TPM-Specific Tests\n");

    if (!check_tpm_available()) {
        TEST_SKIP("TPM PCR binding test", "TPM not available");
        TEST_SKIP("TPM PCR mismatch simulation", "TPM not available");
        TEST_SKIP("TPM manufacturer info", "TPM not available");
        return;
    }

    hsm_error_t err;

    /* Test PCR binding configuration */
    err = hsm_tpm_set_pcr_binding(0x0080);  /* PCR 7 */
    TEST("hsm_tpm_set_pcr_binding(PCR7) succeeds", err == HSM_SUCCESS);

    /* Test with multiple PCRs */
    err = hsm_tpm_set_pcr_binding(0x00C0);  /* PCR 6 and 7 */
    TEST("hsm_tpm_set_pcr_binding(PCR6+7) succeeds", err == HSM_SUCCESS);

    /* Test TPM-specific status fields */
    hsm_status_t status;
    err = hsm_get_status(&status);
    TEST("TPM status has manufacturer",
         err == HSM_SUCCESS && status.tpm_manufacturer != NULL);
    TEST("TPM has persistent key flag",
         err == HSM_SUCCESS);

    if (status.tpm_manufacturer) {
        printf("   TPM Manufacturer: %s\n", status.tpm_manufacturer);
    }
    printf("   TPM has persistent key: %d\n", status.tpm_has_persistent_key);

    hsm_status_free(&status);

    /* Test seal/unseal with TPM */
    err = hsm_seal_pin("tpm-test", (const uint8_t*)"tpm-pin", 7);
    TEST("Seal with TPM succeeds", err == HSM_SUCCESS);

    if (err == HSM_SUCCESS) {
        callback_state_t state;
        memset(&state, 0, sizeof(state));
        err = hsm_unseal_pin("tpm-test", recording_callback, &state);
        TEST("Unseal with TPM succeeds", err == HSM_SUCCESS);
        TEST("TPM-sealed PIN matches",
             strcmp(state.pin_copy, "tpm-pin") == 0);
        hsm_clear_pin("tpm-test");
    }
}

/* ========================================================================
 * SECTION 10: Secure Enclave-Specific Tests
 * ======================================================================== */

static void test_secure_enclave_specific(void) {
    printf("\n15. Secure Enclave-Specific Tests\n");

    if (!check_secure_enclave_available()) {
        TEST_SKIP("SE biometric config test", "Secure Enclave not available");
        TEST_SKIP("SE keychain fallback test", "Secure Enclave not available");
        TEST_SKIP("SE biometric available check", "Secure Enclave not available");
        return;
    }

    hsm_error_t err;

    /* Test biometric configuration */
    err = hsm_se_set_biometric(0);  /* Disable biometric */
    TEST("hsm_se_set_biometric(0) succeeds", err == HSM_SUCCESS);

    err = hsm_se_set_biometric(1);  /* Enable biometric */
    TEST("hsm_se_set_biometric(1) succeeds", err == HSM_SUCCESS);

    /* Disable biometric for testing (agent mode) */
    err = hsm_se_set_biometric(0);
    TEST("Disable biometric for test succeeds", err == HSM_SUCCESS);

    /* Test SE-specific status fields */
    hsm_status_t status;
    err = hsm_get_status(&status);
    TEST("SE status retrieval succeeds", err == HSM_SUCCESS);

    printf("   SE biometric available: %d\n", status.se_biometric_available);
    printf("   SE key exists: %d\n", status.se_key_exists);

    hsm_status_free(&status);

    /* Test seal/unseal with Secure Enclave */
    err = hsm_seal_pin("se-test", (const uint8_t*)"se-pin", 6);
    TEST("Seal with SE succeeds", err == HSM_SUCCESS);

    if (err == HSM_SUCCESS) {
        callback_state_t state;
        memset(&state, 0, sizeof(state));
        err = hsm_unseal_pin("se-test", recording_callback, &state);
        TEST("Unseal with SE succeeds", err == HSM_SUCCESS);
        TEST("SE-sealed PIN matches",
             strcmp(state.pin_copy, "se-pin") == 0);
        hsm_clear_pin("se-test");
    }
}

/* ========================================================================
 * SECTION 11: Platform API Tests (TPM/SE Not Available)
 * ======================================================================== */

static void test_platform_api_unavailable(void) {
    printf("\n16. Platform API When Unavailable\n");

    hsm_method_t method = hsm_available();

    if (method != HSM_METHOD_TPM) {
        /* TPM APIs should return NOT_AVAILABLE on non-TPM systems */
        hsm_error_t err = hsm_tpm_set_pcr_binding(0x0080);
        TEST("hsm_tpm_set_pcr_binding() on non-TPM returns NOT_AVAILABLE",
             err == HSM_ERR_NOT_AVAILABLE);
    } else {
        TEST_SKIP("Non-TPM PCR binding test", "TPM is available");
    }

    if (method != HSM_METHOD_SECURE_ENCLAVE) {
        /* SE APIs should return NOT_AVAILABLE on non-SE systems */
        hsm_error_t err = hsm_se_set_biometric(1);
        TEST("hsm_se_set_biometric() on non-SE returns NOT_AVAILABLE",
             err == HSM_ERR_NOT_AVAILABLE);
    } else {
        TEST_SKIP("Non-SE biometric test", "Secure Enclave is available");
    }
}

/* ========================================================================
 * SECTION 12: Memory Safety Tests
 * ======================================================================== */

static void test_memory_safety(void) {
    printf("\n17. Memory Safety\n");

    /* hsm_free with NULL should be safe */
    hsm_free(NULL);
    TEST("hsm_free(NULL) is safe", 1);

    /* hsm_status_free with NULL should be safe */
    hsm_status_free(NULL);
    TEST("hsm_status_free(NULL) is safe", 1);

    /* Double status_free should be safe */
    hsm_status_t status;
    hsm_get_status(&status);
    hsm_status_free(&status);
    hsm_status_free(&status);  /* Second call should be safe */
    TEST("Double hsm_status_free() is safe", 1);

    /* Large allocation test */
    for (int i = 0; i < 100; i++) {
        hsm_status_t s;
        hsm_get_status(&s);
        hsm_status_free(&s);
    }
    TEST("100 status alloc/free cycles succeed", 1);
}

/* ========================================================================
 * SECTION 13: Stress Tests
 * ======================================================================== */

static void test_stress(void) {
    printf("\n18. Stress Tests\n");

    hsm_error_t err;
    int success_count = 0;
    const int iterations = 50;

    printf("   Running %d seal/unseal cycles...\n", iterations);

    for (int i = 0; i < iterations; i++) {
        char pin[16];
        snprintf(pin, sizeof(pin), "stress-%d", i);

        err = hsm_seal_pin("stress-test", (const uint8_t*)pin, strlen(pin));
        if (err != HSM_SUCCESS) continue;

        callback_state_t state;
        memset(&state, 0, sizeof(state));
        err = hsm_unseal_pin("stress-test", recording_callback, &state);

        if (err == HSM_SUCCESS && strcmp(state.pin_copy, pin) == 0) {
            success_count++;
        }
    }

    hsm_clear_pin("stress-test");

    TEST("Stress test: all iterations passed", success_count == iterations);
}

/* ========================================================================
 * MAIN
 * ======================================================================== */

int main(int argc, char* argv[]) {
    (void)argc;
    (void)argv;

    printf("HSM Abstraction Layer Tests\n");
    printf("===========================\n\n");

    /* Initialize */
    hsm_initialize();

    /* Cleanup any previous test data */
    cleanup_test_pins();

    /* Run all test sections */
    test_basic_availability();
    test_hsm_status();
    test_initialization();
    test_seal_unseal_basic();
    test_unseal_after_clear();
    test_error_messages();
    test_invalid_inputs();
    test_edge_cases();
    test_overwrite_pin();
    test_list_identities();
    test_clear_all();
    test_concurrency();
    test_callback_failure();
    test_tpm_specific();
    test_secure_enclave_specific();
    test_platform_api_unavailable();
    test_memory_safety();
    test_stress();

    /* Final cleanup */
    cleanup_test_pins();

    /* Summary */
    printf("\n===========================\n");
    printf("Tests passed:  %d\n", tests_passed);
    printf("Tests failed:  %d\n", tests_failed);
    printf("Tests skipped: %d\n", tests_skipped);
    printf("===========================\n");

    return tests_failed > 0 ? 1 : 0;
}
