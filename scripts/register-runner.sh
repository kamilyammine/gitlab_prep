#!/usr/bin/env bash
# Registers the bundled gitlab-runner container against the local GitLab.
#   1. GitLab UI: Admin > CI/CD > Runners > New instance runner (set tags) > Create
#   2. Copy the token (starts with glrt-) and run:  bash scripts/register-runner.sh glrt-XXXX
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
set -a; . ./.env; set +a

TOKEN="${1:-}"
[ -n "$TOKEN" ] || { echo "usage: $0 <runner-token>"; exit 1; }

docker image inspect "${RUNNER_DEFAULT_IMAGE}" >/dev/null 2>&1 \
  || echo "WARNING: default job image ${RUNNER_DEFAULT_IMAGE} is not loaded on this host."

mkdir -p "$DATA_DIR/runner"
# Offline-specific settings merged into the generated config.toml:
#  - never pull from the internet unless asked (if-not-present)
#  - helper image pinned to the bundled tag (default would pull from registry.gitlab.com)
#  - jobs join gitlab-net and clone via http://gitlab, so no DNS for the external hostname is needed
cat > "$DATA_DIR/runner/template.toml" <<EOF
[[runners]]
  clone_url = "http://gitlab"
  [runners.docker]
    image = "${RUNNER_DEFAULT_IMAGE}"
    helper_image = "gitlab/gitlab-runner-helper:x86_64-${RUNNER_VERSION}"
    pull_policy = ["if-not-present"]
    allowed_pull_policies = ["if-not-present", "never", "always"]
    network_mode = "gitlab-net"
    privileged = ${RUNNER_PRIVILEGED:-false}
    volumes = ["/cache"]
EOF

docker compose run --rm --no-deps gitlab-runner register \
  --non-interactive \
  --url "http://gitlab" \
  --token "$TOKEN" \
  --executor docker \
  --docker-image "${RUNNER_DEFAULT_IMAGE}" \
  --template-config /etc/gitlab-runner/template.toml

rm -f "$DATA_DIR/runner/template.toml"
docker compose restart gitlab-runner
echo "Runner registered. It should show as online in Admin > CI/CD > Runners within a minute."
