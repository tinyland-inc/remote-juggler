# Makefile for pinentry-remotejuggler
#
# Builds the C helper library for HSM operations.
# The Python pinentry is the primary implementation and doesn't need compilation.

UNAME := $(shell uname -s)

# Compiler settings
CC ?= cc
CFLAGS := -Wall -Wextra -O2 -fPIC
DEBUG_CFLAGS := -g -O0 -DDEBUG

# Platform-specific settings
ifeq ($(UNAME),Darwin)
    HSM_SRC := hsm_darwin.c
    HSM_LIBS := -framework Security -framework CoreFoundation
    LDFLAGS := -dynamiclib
    LIB_EXT := dylib
    INSTALL_DIR := /usr/local/lib
else ifeq ($(UNAME),Linux)
    HSM_SRC := hsm_linux.c
    HSM_LIBS := -ltss2-esys -ltss2-rc -ltss2-tctildr
    LDFLAGS := -shared
    LIB_EXT := so
    INSTALL_DIR := /usr/local/lib
    # Check if TPM libraries are available
    TPM_AVAILABLE := $(shell pkg-config --exists tss2-esys 2>/dev/null && echo yes || echo no)
    ifeq ($(TPM_AVAILABLE),no)
        HSM_SRC := hsm_stub.c
        HSM_LIBS :=
        $(warning TPM2-TSS not found, building stub implementation)
    endif
else
    HSM_SRC := hsm_stub.c
    HSM_LIBS :=
    LDFLAGS := -shared
    LIB_EXT := so
    INSTALL_DIR := /usr/local/lib
endif

# Output
LIB_NAME := libhsm_remotejuggler
LIB_FILE := $(LIB_NAME).$(LIB_EXT)

# Targets
.PHONY: all clean install uninstall test test-integration test-all debug help

all: $(LIB_FILE)

$(LIB_FILE): $(HSM_SRC) hsm.h
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $< $(HSM_LIBS)

debug: CFLAGS += $(DEBUG_CFLAGS)
debug: $(LIB_FILE)

# Simple test program
test_hsm: test_hsm.c $(LIB_FILE)
	$(CC) $(CFLAGS) -o $@ $< -L. -lhsm_remotejuggler $(HSM_LIBS)

test: test_hsm
	@echo "Running HSM unit tests..."
ifeq ($(UNAME),Darwin)
	DYLD_LIBRARY_PATH=. ./test_hsm
else
	LD_LIBRARY_PATH=. ./test_hsm
endif

# Integration tests (requires Python 3, optional gpg-agent)
test-integration: $(LIB_FILE)
	@echo "Running HSM integration tests..."
	@if [ -x "./test_hsm_integration.sh" ]; then \
		./test_hsm_integration.sh; \
	else \
		echo "Integration test script not found or not executable"; \
		exit 1; \
	fi

# Run all tests (unit + integration)
test-all: test test-integration
	@echo ""
	@echo "All HSM tests completed."

clean:
	rm -f $(LIB_FILE) test_hsm *.o

install: $(LIB_FILE)
	@echo "Installing library to $(INSTALL_DIR)..."
	install -d $(INSTALL_DIR)
	install -m 755 $(LIB_FILE) $(INSTALL_DIR)/
	@if [ "$(UNAME)" = "Darwin" ]; then \
		install_name_tool -id $(INSTALL_DIR)/$(LIB_FILE) $(INSTALL_DIR)/$(LIB_FILE); \
	else \
		ldconfig 2>/dev/null || true; \
	fi
	@echo "Installing pinentry-remotejuggler..."
	install -d /usr/local/bin
	install -m 755 pinentry-remotejuggler.py /usr/local/bin/pinentry-remotejuggler
	@echo ""
	@echo "Installation complete!"
	@echo ""
	@echo "To configure gpg-agent, add to ~/.gnupg/gpg-agent.conf:"
	@echo "    pinentry-program /usr/local/bin/pinentry-remotejuggler"
	@echo ""
	@echo "Then reload gpg-agent:"
	@echo "    gpgconf --kill gpg-agent"

uninstall:
	rm -f $(INSTALL_DIR)/$(LIB_FILE)
	rm -f /usr/local/bin/pinentry-remotejuggler
	@if [ "$(UNAME)" != "Darwin" ]; then \
		ldconfig 2>/dev/null || true; \
	fi
	@echo "Uninstalled"

help:
	@echo "pinentry-remotejuggler build system"
	@echo ""
	@echo "Targets:"
	@echo "  all              - Build the HSM library (default)"
	@echo "  debug            - Build with debug symbols"
	@echo "  test             - Build and run C unit tests"
	@echo "  test-integration - Run integration tests (requires Python 3)"
	@echo "  test-all         - Run both unit and integration tests"
	@echo "  install          - Install library and pinentry script"
	@echo "  uninstall        - Remove installed files"
	@echo "  clean            - Remove build artifacts"
	@echo ""
	@echo "Platform: $(UNAME)"
	@echo "HSM implementation: $(HSM_SRC)"
	@echo "Libraries: $(HSM_LIBS)"
