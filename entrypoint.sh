#!/bin/bash
# Custom entrypoint for dolt-remote
# Internal service behind firewall (only port 50051 exposed via Traefik)
set -e

DATA_DIR="/var/lib/dolt"

# Ensure global dolt config exists
dolt config --global --add user.name "dolt-remote" 2>/dev/null || true
dolt config --global --add user.email "dolt@adrianphilipp.de" 2>/dev/null || true

# Auto-create missing databases BEFORE server start (filesystem only, no SQL needed)
if [ -f /init-databases.sh ]; then
    echo "Checking databases..."
    CREATED=0
    # Parse DATABASES array from init-databases.sh
    while IFS= read -r db; do
        db=$(echo "$db" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        if [ -n "$db" ] && [ ! -d "$DATA_DIR/$db/.dolt" ]; then
            echo -n "CREATE: $db ... "
            mkdir -p "$DATA_DIR/$db"
            cd "$DATA_DIR/$db"
            dolt init --name "beads" --email "beads@adrianphilipp.de" >/dev/null 2>&1
            cd "$DATA_DIR"
            echo "OK"
            CREATED=$((CREATED + 1))
        fi
    done < <(sed -n '/^DATABASES=(/,/)/{ /^DATABASES=(/d; /)/d; s/^[[:space:]]*//; s/[[:space:]]*$//; /^$/d; /^#/d; p }' /init-databases.sh)
    [ "$CREATED" -gt 0 ] && echo "Created $CREATED new database(s)." || echo "All databases exist."
fi

# List all databases
echo "Databases on disk:"
ls -1 "$DATA_DIR" | sort

# Pull from external remotes BEFORE starting server (CLI mode, env vars work)
if [ -d "$DATA_DIR/beads_mira/.dolt" ]; then
    echo "Pulling beads_mira from cognovis..."
    cd "$DATA_DIR/beads_mira"
    dolt config --local --add user.name "dolt-remote" 2>/dev/null || true
    dolt config --local --add user.email "dolt@adrianphilipp.de" 2>/dev/null || true
    # Add remote if missing
    dolt remote add cognovis "https://dolt.cognovis.de/beads_mira" 2>/dev/null || true
    dolt pull cognovis main 2>&1 && echo "beads_mira: pull OK" || echo "beads_mira: pull failed (continuing)"
    cd "$DATA_DIR"
fi

# Start sql-server in background
echo "Starting sql-server..."
dolt sql-server \
    --host 0.0.0.0 \
    --port 3306 \
    --remotesapi-port 8080 \
    --data-dir "$DATA_DIR" &
SERVER_PID=$!

# Wait for server to accept connections and grant permissions
echo "Waiting for sql-server..."
for i in $(seq 1 30); do
    if dolt --host 127.0.0.1 --port 3306 --user root --password "" --no-tls sql -q "SELECT 1" >/dev/null 2>&1; then
        echo "Server ready after ${i}s."

        # Ensure root@% exists with full privileges + CLONE_ADMIN
        DOLT_SQL="dolt --host 127.0.0.1 --port 3306 --user root --password '' --no-tls sql"
        $DOLT_SQL -q "CREATE USER IF NOT EXISTS 'root'@'%';" 2>/dev/null || true
        $DOLT_SQL -q "ALTER USER 'root'@'%' IDENTIFIED BY '';" 2>/dev/null || true
        $DOLT_SQL -q "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;" 2>/dev/null || true
        $DOLT_SQL -q "GRANT CLONE_ADMIN ON *.* TO 'root'@'%';" 2>/dev/null && echo "root@%: CLONE_ADMIN OK" || true
        $DOLT_SQL -q "GRANT CLONE_ADMIN ON *.* TO 'root'@'localhost';" 2>/dev/null && echo "root@localhost: CLONE_ADMIN OK" || true

        # Configure cognovis remote for beads_mira (external Dolt server)
        $DOLT_SQL -q "USE beads_mira; CALL DOLT_REMOTE('add', 'cognovis', 'https://dolt.cognovis.de/beads_mira');" 2>/dev/null && echo "beads_mira: cognovis remote OK" || echo "beads_mira: cognovis remote already exists or failed"

        break
    fi
    sleep 1
done

# Keep container alive
wait $SERVER_PID
