#!/usr/bin/env bash
# Creates a GitLab backup + copies the secrets/config that the backup does NOT include.
# Output: $DATA_DIR/data/backups/ (data) and ./backups/<timestamp>/ (config+secrets)
# Copy both off the VM. Without gitlab-secrets.json a restore loses CI variables, 2FA, etc.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
set -a; . ./.env; set +a

docker exec -t gitlab gitlab-backup create STRATEGY=copy

TS="$(date +%Y%m%d-%H%M%S)"
mkdir -p "backups/$TS"
docker cp gitlab:/etc/gitlab/gitlab-secrets.json "backups/$TS/"
docker cp gitlab:/etc/gitlab/gitlab.rb "backups/$TS/"
cp .env docker-compose.yml "backups/$TS/"

echo
echo "Data backup:     $DATA_DIR/data/backups/ (latest file below)"
docker exec gitlab sh -c 'ls -1t /var/opt/gitlab/backups | head -1'
echo "Config/secrets:  $ROOT/backups/$TS/"
