#!/bin/bash
# Custom entrypoint: create beads user before starting sql-server
# dolt sql (non-server mode) modifies privilege files directly
set -e

DATA_DIR="/var/lib/dolt"
BEADS_PW="${BEADS_REMOTE_PW}"
BEADS_USR="${BEADS_REMOTE_USR:-adrian}"

# Ensure global dolt config exists
dolt config --global --add user.name "dolt-remote" 2>/dev/null || true
dolt config --global --add user.email "dolt@adrianphilipp.de" 2>/dev/null || true

# Create beads user with full privileges (runs against privilege files, not running server)
echo "Setting up beads user..."
cd "$DATA_DIR"

# Pick any database dir to run SQL against (privileges are global)
FIRST_DB=$(ls -d */ 2>/dev/null | head -1)
if [ -n "$FIRST_DB" ]; then
    cd "$DATA_DIR/$FIRST_DB"
    dolt sql -q "CREATE USER IF NOT EXISTS '${BEADS_USR}'@'%' IDENTIFIED BY '${BEADS_PW}';" 2>/dev/null || true
    dolt sql -q "ALTER USER '${BEADS_USR}'@'%' IDENTIFIED BY '${BEADS_PW}';" 2>/dev/null || true
    dolt sql -q "GRANT ALL PRIVILEGES ON *.* TO '${BEADS_USR}'@'%' WITH GRANT OPTION;" 2>/dev/null || true
    dolt sql -q "GRANT CLONE_ADMIN ON *.* TO '${BEADS_USR}'@'%';" 2>/dev/null || true
    dolt sql -q "GRANT CLONE_ADMIN ON *.* TO 'root'@'%';" 2>/dev/null || true
    echo "User ${BEADS_USR} + root: configured"
fi

# Start sql-server in background, then apply runtime GRANTs
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
    if dolt sql -q "SELECT 1;" --host 127.0.0.1 --port 3306 --user root 2>/dev/null; then
        echo "Server ready after ${i}s"
        break
    fi
    sleep 1
done

# Apply runtime GRANTs (these require a running server for root)
echo "Applying runtime GRANTs..."
dolt sql --host 127.0.0.1 --port 3306 --user root \
    -q "GRANT CLONE_ADMIN ON *.* TO 'root'@'%';" 2>/dev/null && echo "root: CLONE_ADMIN granted" || echo "root: CLONE_ADMIN grant failed (may already exist)"
dolt sql --host 127.0.0.1 --port 3306 --user root \
    -q "GRANT CLONE_ADMIN ON *.* TO '${BEADS_USR}'@'%';" 2>/dev/null && echo "${BEADS_USR}: CLONE_ADMIN granted" || echo "${BEADS_USR}: CLONE_ADMIN grant failed (may already exist)"

# Wait for server process (keeps container alive)
wait $SERVER_PID
