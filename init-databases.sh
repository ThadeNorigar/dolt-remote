#!/bin/bash
# Creates empty Dolt databases for all Beads projects.
# Run on server: docker exec -it dolt-remote bash /init-databases.sh
# Or copy into container first: docker cp init-databases.sh dolt-remote:/init-databases.sh

set -e

DATABASES=(
  K2SO
  app
  k2board
  k2vault
  telegram
  workshops
  alphina
  apccoachingsuite
  apcinsights
  claude-updater
  confluenceimporter
  disg-app
  fhir-pvs-dummy
  insights-database
  kalo
  mcnzulassungscockpit
  beads_mira
  shadowrungamemaster
  shadowrunbattlemap
  templatedjangowebapp
  tetrisandroid
  transcriptioneer
  vibedtoolingplatform
  zaehler-ki
)

DATA_DIR="/var/lib/dolt"
CREATED=0
EXISTED=0

for db in "${DATABASES[@]}"; do
  if [ -d "$DATA_DIR/$db/.dolt" ]; then
    echo "EXISTS: $db"
    EXISTED=$((EXISTED + 1))
  else
    echo -n "CREATE: $db ... "
    mkdir -p "$DATA_DIR/$db"
    cd "$DATA_DIR/$db"
    dolt init --name "beads" --email "beads@adrianphilipp.de"
    cd "$DATA_DIR"
    echo "OK"
    CREATED=$((CREATED + 1))
  fi
done

echo ""
echo "Done. Created: $CREATED, Existed: $EXISTED, Total: $((CREATED + EXISTED))"
