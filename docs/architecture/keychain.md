# Keychain Integration

RemoteJuggler integrates with macOS Keychain via the Security.framework.

## Overview

On macOS, tokens are stored securely in the system Keychain rather than in plaintext configuration files. This provides:

- Encrypted storage at rest
- Access control via system prompts
- Integration with macOS security features
- Automatic lock/unlock with system login

## C FFI Implementation

Chapel interfaces with Security.framework through C foreign function interface.

### Header File

**Location:** `c_src/keychain.h`

```c
#ifndef KEYCHAIN_H
#define KEYCHAIN_H

#include <stddef.h>

int keychain_store(const char* service, const char* account,
                   const char* password, size_t password_len);
int keychain_retrieve(const char* service, const char* account,
                      char** password_out, size_t* password_len_out);
int keychain_delete(const char* service, const char* account);
int keychain_exists(const char* service, const char* account);
char* keychain_error_message(int status);
void keychain_free_string(char* str);
int keychain_is_darwin(void);

#endif
```

### Implementation

**Location:** `c_src/keychain.c`

The implementation uses Security.framework functions:

- `SecItemAdd` - Store new keychain item
- `SecItemCopyMatching` - Retrieve existing item
- `SecItemDelete` - Remove item
- `SecItemUpdate` - Update existing item

```c
#if defined(__APPLE__)
#include <Security/Security.h>
#include <CoreFoundation/CoreFoundation.h>

int keychain_store(const char* service, const char* account,
                   const char* password, size_t password_len) {
    CFStringRef serviceRef = CFStringCreateWithCString(NULL, service, kCFStringEncodingUTF8);
    CFStringRef accountRef = CFStringCreateWithCString(NULL, account, kCFStringEncodingUTF8);
    CFDataRef passwordRef = CFDataCreate(NULL, (UInt8*)password, password_len);

    CFMutableDictionaryRef query = CFDictionaryCreateMutable(
        NULL, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    CFDictionarySetValue(query, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(query, kSecAttrService, serviceRef);
    CFDictionarySetValue(query, kSecAttrAccount, accountRef);
    CFDictionarySetValue(query, kSecValueData, passwordRef);

    OSStatus status = SecItemAdd(query, NULL);

    // Handle duplicate by updating
    if (status == errSecDuplicateItem) {
        CFMutableDictionaryRef update = CFDictionaryCreateMutable(
            NULL, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFDictionarySetValue(update, kSecValueData, passwordRef);
        status = SecItemUpdate(query, update);
        CFRelease(update);
    }

    CFRelease(query);
    CFRelease(serviceRef);
    CFRelease(accountRef);
    CFRelease(passwordRef);

    return (int)status;
}
#endif
```

### Chapel Binding

**Location:** `src/remote_juggler/Keychain.chpl`

```chapel
prototype module Keychain {
  use CTypes;

  require "../../c_src/keychain.h", "../../c_src/keychain.c";

  extern proc keychain_store(service: c_ptrConst(c_char),
                             account: c_ptrConst(c_char),
                             password: c_ptrConst(c_char),
                             password_len: c_size_t): c_int;

  extern proc keychain_retrieve(service: c_ptrConst(c_char),
                                account: c_ptrConst(c_char),
                                password_out: c_ptr(c_ptr(c_char)),
                                password_len_out: c_ptr(c_size_t)): c_int;

  extern proc keychain_delete(service: c_ptrConst(c_char),
                              account: c_ptrConst(c_char)): c_int;

  extern proc keychain_is_darwin(): c_int;
  extern proc keychain_free_string(str: c_ptr(c_char)): void;
}
```

## Service Name Convention

Keychain items are stored with a consistent service name format:

```
remote-juggler.<provider>.<identity>
```

Examples:
- `remote-juggler.gitlab.personal`
- `remote-juggler.gitlab.work`
- `remote-juggler.github.oss`

## API Reference

### isDarwin

Check if running on macOS.

```chapel
proc isDarwin(): bool
```

Returns `true` on macOS, `false` on Linux/other platforms.

### storeToken

Store a token in Keychain.

```chapel
proc storeToken(provider: string, identity: string,
                account: string, token: string): bool
```

**Parameters:**
- `provider`: Provider name (gitlab, github, bitbucket)
- `identity`: Identity name
- `account`: User account name
- `token`: Access token to store

**Returns:** `true` on success, `false` on failure.

### retrieveToken

Retrieve a token from Keychain.

```chapel
proc retrieveToken(provider: string, identity: string,
                   account: string): (bool, string)
```

**Returns:** Tuple of (found, token). Token is empty string if not found.

### deleteToken

Remove a token from Keychain.

```chapel
proc deleteToken(provider: string, identity: string,
                 account: string): bool
```

**Returns:** `true` if deleted, `false` if not found or error.

## Build Requirements

### macOS

The Makefile includes framework linking for macOS builds:

```makefile
ifeq ($(UNAME_S),Darwin)
  CHPL_LDFLAGS = --ldflags="-framework Security -framework CoreFoundation"
endif
```

### Linux

On Linux, Keychain functions return failure codes. The application falls back to environment variable token storage.

## Security Considerations

### Access Control

The first time a token is accessed, macOS prompts for Keychain access permission. Users can choose:

- **Always Allow**: Grant permanent access
- **Allow Once**: Grant single-use access
- **Deny**: Refuse access

### Token Visibility

When retrieving tokens via CLI, only masked output is shown:

```
Token: glpat-****...xyz8 (40 chars)
```

The full token is never displayed to prevent shoulder-surfing.

### Debugging

To inspect Keychain items directly:

```bash
# List RemoteJuggler items
security find-generic-password -s "remote-juggler.gitlab.personal"

# Show token (requires authentication)
security find-generic-password -s "remote-juggler.gitlab.personal" -w
```

## Error Handling

Keychain errors are mapped to status codes:

| Code | Meaning |
|------|---------|
| 0 | Success |
| -25291 | Duplicate item (handled internally) |
| -25293 | Item not found |
| -25308 | User canceled |
| -25315 | Keychain locked |
