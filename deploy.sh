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

# Step 2: Check .env — auto-generate if missing
if [ ! -f .env ]; then
    echo "Generating .env with BasicAuth credentials..."
    # Generate random password and htpasswd hash
    BEADS_PW=$(head -c 18 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
    # Use openssl for apr1 hash (available on most Linux)
    HASH=$(openssl passwd -apr1 "$BEADS_PW")
    # Docker compose needs $$ to escape $ signs
    ESCAPED_HASH=$(echo "$HASH" | sed 's/\$/\$\$/g')
    echo "BASIC_AUTH_USER=beads:${ESCAPED_HASH}" > .env
    echo ""
    echo "========================================="
    echo "GENERATED CREDENTIALS (save these!):"
    echo "  User: beads"
    echo "  Password: $BEADS_PW"
    echo "  URL: https://beads:${BEADS_PW}@dolt.adrianphilipp.de/<db>"
    echo "========================================="
    echo ""
fi

# Step 3: Rebuild container
echo "Rebuilding container..."
docker compose up -d --build

# Step 4: Wait for health (check SQL port inside container)
echo "Waiting for Dolt sql-server..."
for i in $(seq 1 20); do
    if docker exec dolt-remote dolt version > /dev/null 2>&1; then
        echo "Dolt: OK"
        echo ""
        echo "Deploy $PROJECT complete."
        exit 0
    fi
    # Alternative: check if port 3306 is listening
    if docker exec dolt-remote sh -c "ls /var/lib/dolt/ 2>/dev/null" > /dev/null 2>&1; then
        # Container is up, check if sql-server responds
        if docker exec dolt-remote sh -c "echo 'SELECT 1' | dolt sql 2>/dev/null" > /dev/null 2>&1; then
            echo "Dolt SQL: OK"
            DB_COUNT=$(docker exec dolt-remote sh -c "ls -d /var/lib/dolt/*/ 2>/dev/null | wc -l")
            echo "Databases: $DB_COUNT"
            echo ""
            echo "Deploy $PROJECT complete."
            exit 0
        fi
    fi
    sleep 3
done

echo "ERROR: Health check failed after 60s"
docker logs dolt-remote --tail 30
exit 1
