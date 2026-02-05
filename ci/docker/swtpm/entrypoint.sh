#!/bin/bash
# swtpm entrypoint script
#
# Starts the software TPM 2.0 emulator in socket mode.
# Control port: 2322 (for swtpm_ioctl commands)
# Server port: 2321 (for TPM commands via TCTI)

set -e

# State directory for TPM persistence
STATE_DIR="${SWTPM_STATE_DIR:-/var/lib/swtpm}"

# Ports (can be overridden via environment)
CTRL_PORT="${SWTPM_CTRL_PORT:-2322}"
SERVER_PORT="${SWTPM_SERVER_PORT:-2321}"

# Ensure state directory exists
mkdir -p "$STATE_DIR"

echo "Starting swtpm..."
echo "  State directory: $STATE_DIR"
echo "  Control port: $CTRL_PORT"
echo "  Server port: $SERVER_PORT"

# Start swtpm in foreground mode
exec swtpm socket \
    --tpmstate "dir=$STATE_DIR" \
    --tpm2 \
    --ctrl "type=tcp,port=$CTRL_PORT,bindaddr=0.0.0.0" \
    --server "type=tcp,port=$SERVER_PORT,bindaddr=0.0.0.0" \
    --flags not-need-init,startup-clear \
    --log level=5
