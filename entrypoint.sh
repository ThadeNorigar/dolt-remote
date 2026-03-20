#!/bin/bash
# Custom entrypoint for dolt-remote
# No auth enforcement — internal service behind firewall (only port 50051 exposed)
set -e

DATA_DIR="/var/lib/dolt"

# Ensure global dolt config exists
dolt config --global --add user.name "dolt-remote" 2>/dev/null || true
dolt config --global --add user.email "dolt@adrianphilipp.de" 2>/dev/null || true

# Start sql-server without custom privileges (let dolt create default root superuser)
# Then grant CLONE_ADMIN to root via the running server
echo "Starting sql-server..."
rm -rf "$DATA_DIR/.doltcfg" 2>/dev/null || true

dolt sql-server \
    --host 0.0.0.0 \
    --port 3306 \
    --remotesapi-port 8080 \
    --data-dir "$DATA_DIR" &
SERVER_PID=$!

# Wait for server, then grant CLONE_ADMIN
echo "Waiting for sql-server to accept connections..."
for i in $(seq 1 30); do
    if dolt --host 127.0.0.1 --port 3306 --user root --password "" sql -q "SELECT 1" >/dev/null 2>&1; then
        echo "Server ready."
        dolt --host 127.0.0.1 --port 3306 --user root --password "" sql -q "GRANT CLONE_ADMIN ON *.* TO 'root'@'localhost';" 2>/dev/null && echo "root@localhost: CLONE_ADMIN granted" || echo "root@localhost: grant skipped"
        dolt --host 127.0.0.1 --port 3306 --user root --password "" sql -q "GRANT CLONE_ADMIN ON *.* TO 'root'@'%';" 2>/dev/null && echo "root@%: CLONE_ADMIN granted" || echo "root@%: grant skipped"
        break
    fi
    sleep 1
done

wait $SERVER_PID
