# GitLab CE – offline Docker deployment

Self-contained bundle for installing GitLab CE and a GitLab Runner on an air-gapped Ubuntu VM using Docker Compose.

| Component | Image | Version |
|---|---|---|
| GitLab CE | `gitlab/gitlab-ce` | `19.5.3-ce.0` |
| Runner | `gitlab/gitlab-runner` | `v19.5.3` |
| Runner helper | `gitlab/gitlab-runner-helper` | `x86_64-v19.5.3` |

## Layout

```
.env                      <- all settings (edit this)
docker-compose.yml        <- gitlab + gitlab-runner
images/                   <- docker image tarballs + SHA256SUMS (created by prepare-images, git-ignored)
scripts/prepare-images.*  <- run ONLINE: pull & save images
scripts/deploy.sh         <- run on VM: load images, start, wait, print root password
scripts/register-runner.sh<- run on VM: register the runner with a glrt- token
scripts/backup.sh         <- run on VM: backup data + secrets
nginx/gitlab.conf.example <- optional TLS reverse proxy
data/                     <- created on deploy: config, data, logs, runner config
```

## VM requirements

- Ubuntu 22.04/24.04, x86_64, Docker Engine **with the compose plugin** (`docker compose version`)
- Minimum 4 vCPU / 8 GB RAM; disk 50 GB+ (repos, CI artifacts and backups grow)
- Ports open: `GITLAB_HTTP_PORT` (default 80) and `GITLAB_SSH_PORT` (default 2222)

## Step 1 – Prepare the bundle (machine with internet)

Edit `.env` (at least the versions and `EXTRA_IMAGES` with every CI image the client's pipelines will use), then:

```bash
bash scripts/prepare-images.sh                                   # Linux/macOS
powershell -ExecutionPolicy Bypass -File scripts\prepare-images.ps1   # Windows
```

This fills `images/` (about 4.5 GB). The tarballs are **not in git** (`.gitignore`), so after a fresh `git clone` you must run this step before copying the folder. Copy the **whole folder**, including the hidden `.env`, to the VM, for example to `/opt/hosting/gitlab`:

```bash
scp -r gitlab_prep/ user@vm:/opt/hosting/gitlab      # or USB/rsync
```

## Step 2 – Deploy (offline VM)

```bash
cd /opt/hosting/gitlab
nano .env                     # set GITLAB_HOSTNAME, GITLAB_EXTERNAL_URL, ports
bash scripts/deploy.sh
```

The script checks image checksums, loads the images, starts the stack and waits for GitLab to become healthy. It then prints the URL and the initial `root` password. **Change the password right away**, because the file holding it is deleted after 24 h.
To read it again later: `docker exec gitlab grep Password: /etc/gitlab/initial_root_password`

> Clients must resolve `GITLAB_HOSTNAME` to the VM's IP through internal DNS or `/etc/hosts`. Or use the IP directly in `GITLAB_EXTERNAL_URL`.

## Step 3 – Register the runner

1. GitLab UI → **Admin** → **CI/CD → Runners** → **New instance runner**. Set the tags and click **Create**.
2. Copy the token (`glrt-…`) and run:

```bash
bash scripts/register-runner.sh glrt-XXXXXXXXXXXX
```

Offline-specific runner config (from the old doc, now automated):
- `pull_policy = if-not-present`, so jobs use locally loaded images and never try the internet.
- The helper image is pinned to the bundled tag. By default it would be pulled from registry.gitlab.com, which fails offline.
- Jobs join the `gitlab-net` network and clone from `http://gitlab`, so no DNS or `extra_hosts` is needed.

**CI images:** every image used in `.gitlab-ci.yml` must be loaded on the VM. Add images later on an online machine, then load them on the VM:

```bash
docker pull --platform linux/amd64 node:22 && docker save node:22 -o node_22.tar   # online
docker load -i node_22.tar                                                         # VM
```

If you have several runners/servers, push the images to an internal registry such as Harbor and reference them from there.

## Optional – HTTPS through a reverse proxy

GitLab inside the container always serves plain HTTP, because Let's Encrypt can't work offline. For HTTPS, put nginx in front: see `nginx/gitlab.conf.example`. Then set `GITLAB_EXTERNAL_URL=https://...` and run `docker compose up -d`.

## Operations

```bash
docker compose ps                               # status
docker compose logs -f gitlab                   # logs
docker compose restart gitlab
docker exec -it gitlab gitlab-ctl reconfigure   # after changing GITLAB_OMNIBUS_CONFIG: use `docker compose up -d` instead
bash scripts/backup.sh                          # backup (copy results off the VM!)
```

Backups: `scripts/backup.sh` writes the data archive to `data/data/backups/` and `gitlab-secrets.json` + config to `backups/<timestamp>/`. **Without `gitlab-secrets.json` a restore is incomplete.**

### Upgrading (offline)

GitLab must be upgraded along its official **upgrade path**, so you can't jump arbitrary versions. Check the GitLab Upgrade Path tool on an online machine. For each required stop:

1. Set `GITLAB_VERSION` and `RUNNER_VERSION` in `.env` and run `prepare-images` online.
2. Copy the new `images/` to the VM, run `bash scripts/backup.sh`, then `bash scripts/deploy.sh`.
3. Wait for background migrations to finish (Admin → Monitoring → Background migrations) before the next stop.

## Troubleshooting

- **`$'\r': command not found`**: the files got Windows line endings during the copy. Fix with: `sed -i 's/\r$//' .env docker-compose.yml scripts/*.sh`
- **Unhealthy after deploy**: run `docker compose logs gitlab | tail -100`. The usual causes are too little RAM or a port already in use (`ss -tlnp`).
- **Job stuck with "pull access denied" / "no such host"**: the image isn't loaded on the VM. Run `docker images` to check.
- **Changing the URL or ports**: edit `.env`, then run `docker compose up -d`. This recreates the container and reapplies the config, and data is kept.
- The old `/etc/hosts` entries for gitlab.com/docs.gitlab.com were needed only for the `.deb` install. The Docker image doesn't need them.
