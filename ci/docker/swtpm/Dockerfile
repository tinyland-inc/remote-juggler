# RemoteJuggler swtpm Container
#
# Software TPM 2.0 emulator for CI testing.
# Used for testing TPM-based PIN storage without hardware TPM.
#
# Build:
#   docker build -t remote-juggler-swtpm ci/docker/swtpm/
#
# Run:
#   docker run -d --name swtpm -p 2321:2321 -p 2322:2322 remote-juggler-swtpm
#
# Connect:
#   export TPM2TOOLS_TCTI="swtpm:host=localhost,port=2321"
#   tpm2_getcap properties-fixed

FROM debian:bookworm-slim

LABEL maintainer="jess@tinyland.dev"
LABEL description="Software TPM 2.0 for RemoteJuggler CI testing"

# Install swtpm and tpm2 tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        swtpm \
        swtpm-tools \
        tpm2-tools \
        libtss2-tcti-swtpm0 \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create state directory
RUN mkdir -p /var/lib/swtpm-localca /var/lib/swtpm

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose TPM server and control ports
EXPOSE 2321 2322

# Health check
HEALTHCHECK --interval=5s --timeout=3s --start-period=2s --retries=3 \
    CMD TPM2TOOLS_TCTI="swtpm:host=localhost,port=2321" tpm2_getcap properties-fixed > /dev/null 2>&1 || exit 1

VOLUME ["/var/lib/swtpm"]

ENTRYPOINT ["/entrypoint.sh"]
