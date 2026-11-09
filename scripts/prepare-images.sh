#!/usr/bin/env bash
# Run on a machine WITH internet and Docker (Linux/macOS).
# Pulls every image the offline stack needs and saves them into ./images.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
set -a; . ./.env; set +a

IMAGES=(
  "gitlab/gitlab-ce:${GITLAB_VERSION}"
  "gitlab/gitlab-runner:${RUNNER_VERSION}"
  "gitlab/gitlab-runner-helper:x86_64-${RUNNER_VERSION}"
)
for img in ${EXTRA_IMAGES:-}; do IMAGES+=("$img"); done

mkdir -p images
for img in "${IMAGES[@]}"; do
  file="images/$(echo "$img" | tr '/:' '__').tar"
  echo ">>> $img"
  docker pull --platform linux/amd64 "$img"
  docker save "$img" -o "$file"
done

( cd images && sha256sum *.tar > SHA256SUMS )
echo
echo "Done. Images saved in $ROOT/images:"
ls -lh images
