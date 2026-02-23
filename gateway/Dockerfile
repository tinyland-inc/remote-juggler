FROM golang:1.23-bookworm AS builder

WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download

COPY *.go ./
RUN CGO_ENABLED=0 go build -o rj-gateway .

# Use Ubuntu 24.04 to match the Chapel CLI binary's glibc (2.38+).
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates libhwloc15 libunwind8 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/rj-gateway /usr/local/bin/rj-gateway

# The Chapel remote-juggler binary must be provided at runtime
# via --chapel-bin flag or RJ_GATEWAY_CHAPEL_BIN env var.

EXPOSE 443

ENTRYPOINT ["rj-gateway"]
