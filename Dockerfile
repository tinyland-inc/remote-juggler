# RemoteJuggler MCP Server Docker Image
#
# Multi-stage build for minimal container running remote-juggler as an MCP server.
#
# Build:
#   docker build -t remote-juggler .
#
# Run as MCP server (stdio):
#   docker run -i --rm remote-juggler --mode=mcp
#
# Run with config:
#   docker run -i --rm \
#     -v ~/.config/remote-juggler:/home/juggler/.config/remote-juggler:ro \
#     -v ~/.ssh:/home/juggler/.ssh:ro \
#     remote-juggler --mode=mcp

# --- Build stage ---
FROM ubuntu:24.04 AS builder

ARG CHAPEL_VERSION=2.7.0
ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget ca-certificates make gcc g++ pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Install Chapel (apt-get update needed since lists were cleaned above)
RUN ARCH=$(dpkg --print-architecture) && \
    wget -q "https://github.com/chapel-lang/chapel/releases/download/${CHAPEL_VERSION}/chapel-${CHAPEL_VERSION}-1.ubuntu24.${ARCH}.deb" && \
    apt-get update && \
    apt-get install -y "./chapel-${CHAPEL_VERSION}-1.ubuntu24.${ARCH}.deb" && \
    rm -f "chapel-${CHAPEL_VERSION}-1.ubuntu24.${ARCH}.deb" && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY src/ src/
COPY c_src/ c_src/
COPY Mason.toml Mason.lock ./

# Build directly with chpl (more reliable than mason in containers)
RUN chpl --fast -o /usr/local/bin/remote-juggler \
    src/remote_juggler.chpl \
    -M src/remote_juggler \
    -I c_src \
    --permit-unhandled-module-errors

# --- Runtime stage ---
FROM ubuntu:24.04 AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates openssh-client gnupg git libhwloc15 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -s /bin/bash juggler

COPY --from=builder /usr/local/bin/remote-juggler /usr/local/bin/remote-juggler

USER juggler
WORKDIR /home/juggler

ENTRYPOINT ["remote-juggler"]
CMD ["--mode=mcp"]
