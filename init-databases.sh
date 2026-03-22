#!/bin/bash
# Creates empty Dolt databases for all Beads projects.
# Names MUST match dolt_database in each project's .beads/metadata.json.
# Auto-executed on container start via entrypoint.sh.

set -e

DATABASES=(
  K2SO
  alphina
  app
  apccoachingsuite
  apcinsights
  beads_mira
  beads_pvs
  claude_updater
  confluenceimporter
  disg_app
  fhir_pvs_dummy
  insights_database
  k2beads
  k2board
  k2vault
  kalo
  mcnzulassungscockpit
  mentor
  shadowrunbattlemap
  shadowrungamemaster
  telegram
  templatedjangowebapp
  tetrisandroid
  transcriptioneer
  vtp
  workshops
  zaehler_ki
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
