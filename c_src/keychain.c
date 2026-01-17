/*
 * keychain.c - Platform-unified keychain wrapper
 *
 * This file includes the appropriate implementation based on the target platform:
 * - Darwin (macOS): Uses Security.framework Keychain Services
 * - Other platforms: Uses stub implementation that returns "not available"
 */

#include "keychain.h"

#ifdef __APPLE__
  #include "keychain_darwin.c"
#else
  #include "keychain_stub.c"
#endif

/* Platform detection function for Chapel */
int keychain_is_darwin(void) {
#ifdef __APPLE__
    return 1;
#else
    return 0;
#endif
}
