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
    echo "User ${BEADS_USR}: configured"
fi

# Start sql-server (exec replaces this process)
echo "Starting sql-server..."
exec dolt sql-server \
    --host 0.0.0.0 \
    --port 3306 \
    --remotesapi-port 8080 \
    --data-dir "$DATA_DIR"
