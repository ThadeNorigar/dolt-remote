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

# Step 2: Rebuild container
echo "Rebuilding container..."
docker compose down 2>/dev/null
docker compose up -d --build --force-recreate

# Step 3: Wait for health
echo "Waiting for Dolt sql-server..."
for i in $(seq 1 20); do
    if docker exec dolt-remote dolt version > /dev/null 2>&1; then
        echo "Dolt: OK"
        break
    fi
    sleep 3
done

if ! docker exec dolt-remote dolt version > /dev/null 2>&1; then
    echo "ERROR: Health check failed after 60s"
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

echo ""
echo "Deploy $PROJECT complete."
echo "Push: DOLT_REMOTE_PASSWORD=<pw> dolt push --user beads origin main"
