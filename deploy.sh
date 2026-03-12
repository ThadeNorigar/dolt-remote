#!/bin/bash
set -euo pipefail

PROJECT="dolt-remote"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Deploy $PROJECT ==="
echo "Dir: $DIR"
echo ""

cd "$DIR"

# Step 1: Pull latest code
echo "Pulling latest code..."
git checkout -- .
git pull origin main

# Step 2: Rebuild container (force-recreate to ensure network attachment)
echo "Rebuilding container..."
docker compose down 2>/dev/null
docker compose up -d --build --force-recreate

# Step 3: Wait for sql-server to accept connections
echo "Waiting for Dolt sql-server..."
for i in $(seq 1 30); do
    if docker exec dolt-remote dolt sql-client \
        --host 127.0.0.1 --port 3306 --user root \
        -q "SELECT 1;" > /dev/null 2>&1; then
        echo "Dolt sql-server: OK"
        break
    fi
    sleep 2
done

if ! docker exec dolt-remote dolt sql-client \
    --host 127.0.0.1 --port 3306 --user root \
    -q "SELECT 1;" > /dev/null 2>&1; then
    echo "ERROR: sql-server not responding after 60s"
    docker logs dolt-remote --tail 30
    exit 1
fi

# Step 4: Init databases if needed
DB_COUNT=$(docker exec dolt-remote sh -c "ls -d /var/lib/dolt/*/ 2>/dev/null | wc -l" || echo "0")
echo "Databases: $DB_COUNT"
if [ "$DB_COUNT" -lt 5 ]; then
    echo "Initializing databases..."
    docker cp "$DIR/init-databases.sh" dolt-remote:/init-databases.sh
    docker exec dolt-remote bash /init-databases.sh
fi

# Step 5: Create beads user with full remotesapi privileges
# Dolt remotesapi requires:
#   - CLONE_ADMIN for clone/fetch/pull
#   - ALL PRIVILEGES for push (push can overwrite entire database)
# Auth via: DOLT_REMOTE_PASSWORD=<pw> dolt push --user beads origin main
echo "Setting up beads user..."
BEADS_PW="${BEADS_REMOTE_PW:-hi5vpTRWdH1Wjb2MnP4LlfAr}"
docker exec dolt-remote dolt sql-client \
    --host 127.0.0.1 --port 3306 --user root \
    -q "CREATE USER IF NOT EXISTS 'beads'@'%' IDENTIFIED BY '${BEADS_PW}';" 2>&1
docker exec dolt-remote dolt sql-client \
    --host 127.0.0.1 --port 3306 --user root \
    -q "GRANT ALL PRIVILEGES ON *.* TO 'beads'@'%' WITH GRANT OPTION;" 2>&1
echo "User beads: OK"

echo ""
echo "Deploy $PROJECT complete."
echo "Push: DOLT_REMOTE_PASSWORD=<pw> dolt push --user beads origin main"
