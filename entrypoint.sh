#!/bin/bash
# Custom entrypoint for dolt-remote
# Internal service behind firewall (only port 50051 exposed via Traefik)
set -e

DATA_DIR="/var/lib/dolt"
DOLT_SQL="dolt --host 127.0.0.1 --port 3306 --user root --password --no-tls sql"

# Ensure global dolt config exists
dolt config --global --add user.name "dolt-remote" 2>/dev/null || true
dolt config --global --add user.email "dolt@adrianphilipp.de" 2>/dev/null || true

# Start sql-server in background
echo "Starting sql-server..."
dolt sql-server \
    --host 0.0.0.0 \
    --port 3306 \
    --remotesapi-port 8080 \
    --data-dir "$DATA_DIR" &
SERVER_PID=$!

# Wait for server to accept connections
echo "Waiting for sql-server..."
for i in $(seq 1 30); do
    if $DOLT_SQL -q "SELECT 1" >/dev/null 2>&1; then
        echo "Server ready after ${i}s."

        # Ensure root@% exists with full privileges + CLONE_ADMIN
        $DOLT_SQL -q "CREATE USER IF NOT EXISTS 'root'@'%';" 2>/dev/null || true
        $DOLT_SQL -q "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;" 2>/dev/null || true
        $DOLT_SQL -q "GRANT CLONE_ADMIN ON *.* TO 'root'@'%';" 2>/dev/null && echo "root@%: CLONE_ADMIN OK" || true
        $DOLT_SQL -q "GRANT CLONE_ADMIN ON *.* TO 'root'@'localhost';" 2>/dev/null && echo "root@localhost: CLONE_ADMIN OK" || true

        break
    fi
    sleep 1
done

# Keep container alive
wait $SERVER_PID
