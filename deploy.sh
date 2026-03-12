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

# Step 3: Rebuild container (force-recreate to ensure network attachment)
echo "Rebuilding container..."
docker compose down 2>/dev/null
docker compose up -d --build --force-recreate

# Step 4: Wait for health
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

# Step 5: Init databases if needed
DB_COUNT=$(docker exec dolt-remote sh -c "ls -d /var/lib/dolt/*/ 2>/dev/null | wc -l" || echo "0")
echo "Databases: $DB_COUNT"
if [ "$DB_COUNT" -lt 5 ]; then
    echo "Initializing databases..."
    docker cp "$DIR/init-databases.sh" dolt-remote:/init-databases.sh
    docker exec dolt-remote bash /init-databases.sh
fi

echo ""
echo "Deploy $PROJECT complete."
