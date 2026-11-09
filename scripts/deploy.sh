#!/usr/bin/env bash
# Run on the OFFLINE Ubuntu VM from inside this folder:   bash scripts/deploy.sh
# Loads the bundled images, starts GitLab + runner, waits until healthy.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

die() { echo "ERROR: $*" >&2; exit 1; }

# --- Pre-flight -------------------------------------------------------------
command -v docker >/dev/null || die "docker is not installed"
docker info >/dev/null 2>&1 || die "cannot talk to docker (run with sudo or add your user to the 'docker' group)"
docker compose version >/dev/null 2>&1 || die "docker compose plugin is missing (docker-compose-plugin .deb)"
[ -f .env ] || die ".env not found in $ROOT"
if grep -q $'\r' .env docker-compose.yml scripts/*.sh; then
  die "Windows line endings detected. Fix with:  sed -i 's/\r\$//' .env docker-compose.yml scripts/*.sh"
fi

set -a; . ./.env; set +a

if [ "$GITLAB_HOSTNAME" = "gitlab.client.internal" ]; then
  echo "WARNING: .env still uses the example hostname 'gitlab.client.internal'."
  read -r -p "Continue anyway? [y/N] " ans; [[ "$ans" =~ ^[Yy]$ ]] || exit 1
fi

REQUIRED=(
  "gitlab/gitlab-ce:${GITLAB_VERSION}"
  "gitlab/gitlab-runner:${RUNNER_VERSION}"
  "gitlab/gitlab-runner-helper:x86_64-${RUNNER_VERSION}"
)

missing() { for i in "${REQUIRED[@]}"; do docker image inspect "$i" >/dev/null 2>&1 || return 0; done; return 1; }

# --- Load images ------------------------------------------------------------
if missing; then
  ls images/*.tar >/dev/null 2>&1 || die "no image tarballs in ./images (run scripts/prepare-images on an online machine first)"
  if [ -f images/SHA256SUMS ]; then
    echo ">>> Verifying image checksums..."
    ( cd images && sha256sum -c SHA256SUMS ) || die "checksum mismatch - re-copy the images folder"
  fi
  for t in images/*.tar; do echo ">>> Loading $t"; docker load -i "$t"; done
else
  echo ">>> Required images already present, skipping docker load"
fi
for i in "${REQUIRED[@]}"; do
  docker image inspect "$i" >/dev/null 2>&1 || die "image $i missing after load (version in .env doesn't match bundled images?)"
done

# --- Start ------------------------------------------------------------------
mkdir -p "$DATA_DIR"/{config,logs,data,runner}
docker compose up -d

echo ">>> Waiting for GitLab to become healthy (first boot takes 3-10 min)..."
for _ in $(seq 1 120); do
  status="$(docker inspect -f '{{.State.Health.Status}}' gitlab 2>/dev/null || echo starting)"
  [ "$status" = "healthy" ] && break
  sleep 10; printf '.'
done
echo
[ "$status" = "healthy" ] || die "GitLab not healthy after 20 min. Check: docker compose logs -f gitlab"

echo
echo "================================================================"
echo " GitLab is up:  $GITLAB_EXTERNAL_URL"
echo " Login user:    root"
if docker exec gitlab test -f /etc/gitlab/initial_root_password; then
  echo " Password:      $(docker exec gitlab awk '/^Password:/ {print $2}' /etc/gitlab/initial_root_password)"
  echo "                (file is auto-deleted after 24h - change the password now)"
fi
echo " Git SSH:       ssh://git@${GITLAB_HOSTNAME}:${GITLAB_SSH_PORT}/<group>/<project>.git"
echo
echo " Next: create an instance runner in Admin > CI/CD > Runners, then:"
echo "       bash scripts/register-runner.sh <glrt-token>"
echo "================================================================"
