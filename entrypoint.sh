#!/bin/bash
# Custom entrypoint for dolt-remote
# No auth enforcement — internal service behind firewall (only port 50051 exposed)
set -e

DATA_DIR="/var/lib/dolt"

# Ensure global dolt config exists
dolt config --global --add user.name "dolt-remote" 2>/dev/null || true
dolt config --global --add user.email "dolt@adrianphilipp.de" 2>/dev/null || true

# Remove any privilege files to disable auth entirely
rm -rf "$DATA_DIR/.doltcfg" 2>/dev/null || true

# Start sql-server (exec replaces this process)
echo "Starting sql-server (no auth)..."
exec dolt sql-server \
    --host 0.0.0.0 \
    --port 3306 \
    --remotesapi-port 8080 \
    --privilege-file=/dev/null \
    --data-dir "$DATA_DIR"
