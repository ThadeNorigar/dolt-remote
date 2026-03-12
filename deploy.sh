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

# Step 2: Check .env
if [ ! -f .env ]; then
    echo "ERROR: .env missing. Create it with BASIC_AUTH_USER=beads:\$\$apr1\$\$..."
    exit 1
fi

# Step 3: Rebuild container
echo "Rebuilding container..."
docker compose up -d --build

# Step 4: Wait for health
echo "Waiting for Dolt remotesapi..."
for i in $(seq 1 15); do
    if docker exec dolt-remote dolt version > /dev/null 2>&1; then
        echo "Dolt: OK ($(docker exec dolt-remote dolt version))"
        echo ""

        # Count databases
        DB_COUNT=$(docker exec dolt-remote ls /var/lib/dolt/ 2>/dev/null | wc -l)
        echo "Databases: $DB_COUNT"
        echo ""
        echo "Deploy $PROJECT complete."
        exit 0
    fi
    sleep 2
done

echo "ERROR: Health check failed after 30s"
docker logs dolt-remote --tail 20
exit 1
