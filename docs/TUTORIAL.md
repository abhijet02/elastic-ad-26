# Tutorial: GitHub to a Linux VM

This project recreates the captured Elasticsearch/Kibana **8.19.14** configuration
and imports 11 dashboards with their dependencies. Use a fresh VM; the original
VM's services and historical event data are not part of this deployment.

## 1. Publish from the Mac to GitHub

If an agent has already pushed this repository, skip this section.
Git and GitHub CLI (`gh`) must be installed. If macOS Git asks for Command Line
Tools, run `xcode-select --install`, finish the installer, then open a new Terminal.
Install GitHub CLI using its [official installation guide](https://github.com/cli/cli#installation).

Authenticate using your browser, without pasting credentials into project files:

```bash
gh auth login --hostname github.com --git-protocol https --web
gh auth setup-git
```

The commands below use your GitHub username, `abhijet02`. If Git requests your identity, configure your
own name and email with `git config --global user.name` and `git config --global user.email`.
You may use your GitHub-provided no-reply email.

```bash
cd ~/elastic-ad-rebuild
git init -b main
git add .gitignore .env.example README.md docker-compose.yml scripts config dashboards docs winlogbeat_2026-10-28_0539.zip
git diff --cached --stat
git diff --cached --name-only
# Check the staged source. private/, .env, and real collector credentials must be absent.
git commit -m "Add Linux Elastic AD deployment with dashboards and tutorial"
gh repo create abhijet02/elastic-ad-rebuild --private --source=. --remote=origin --push
```

For an existing empty GitHub repository, use these two commands instead of
`gh repo create` (do not recreate an existing `origin`):

```bash
git remote add origin https://github.com/abhijet02/elastic-ad-rebuild.git
git push -u origin main
```

The repository starts private. Reviewed dashboards and mappings are included;
raw captures, event documents, original passwords, and original encryption keys
are excluded. No license is assigned by this tutorial; review third-party asset
licensing before distributing beyond your organization.

## 2. Prepare a Linux VM

Use a separate 64-bit Ubuntu 22.04 or 24.04 VM with internet access, at least 8 GB RAM
as a starting allocation, and enough disk for your event volume and retention.
Automatic Docker installation currently uses the official Docker apt repository.
The Elastic application versions are pinned; Docker packages use the current repository version.

From the Mac, package and transfer the checked-out project:

```bash
cd ~/elastic-ad-rebuild
bash scripts/package-linux.sh
scp ~/elastic-ad-linux.tar.gz VM_USER@VM_IP:~/
ssh VM_USER@VM_IP
```

On the Ubuntu VM:

```bash
tar -xzf ~/elastic-ad-linux.tar.gz
cd ~/elastic-ad-rebuild
sudo bash scripts/prepare-ubuntu.sh
```

Alternatively clone GitHub directly on the VM after configuring a GitHub-authorized
SSH key there. A private repository requires GitHub authentication:

```bash
sudo apt-get update
sudo apt-get install -y git
git clone git@github.com:abhijet02/elastic-ad-rebuild.git
cd elastic-ad-rebuild
sudo bash scripts/prepare-ubuntu.sh
```

Do not copy your Mac's private SSH key to the VM. For distributions other than
Ubuntu, install Docker Engine, Compose v2, and OpenSSL using that distribution's
instructions, and persist `vm.max_map_count=262144` before deployment.

## 3. Configure and deploy

To review settings before startup, generate the private environment first:

```bash
sudo bash scripts/init-env.sh
sudo nano .env
```

The generated Elasticsearch heap is 2 GB. Keep enough RAM for native memory,
Kibana, and the OS. Ports default to loopback, accessible by SSH tunnel. For an
HTTPS reverse proxy, set `KIBANA_PUBLIC_BASE_URL` to the actual external URL and
configure that proxy separately. Configure a reachable, protected Elasticsearch
endpoint before redirecting remote Windows collectors.

Start the deployment:

```bash
sudo bash scripts/deploy-linux.sh
```

It validates Compose, starts Elasticsearch and Kibana, waits for readiness, and
restores the 60-day Winlogbeat lifecycle policy, six pipelines, the index template,
and 128 saved objects including all 11 dashboards. It writes `.restore-complete`
only after successful restore. Subsequent runs skip the completed restore.

Credentials are in the target VM's private `.env` file. Changing the file's
Elasticsearch password does not reset a password already stored in the data volume.
Keep the three generated Kibana encryption keys stable across restarts.

## 4. Open Kibana from the Mac

In another Mac Terminal, keep this tunnel running:

```bash
ssh -N -o ExitOnForwardFailure=yes -L 15601:127.0.0.1:5601 VM_USER@VM_IP
```

Open `http://localhost:15601`. Log in with username `elastic` and the
`ELASTIC_PASSWORD` value from the target VM's `.env`. Open Analytics → Dashboard.
The default space should contain 11 dashboards. The Elastic Security monitoring
dashboard will populate only if its underlying monitoring activity exists.

## 5. Connect Active Directory event collectors

The Linux stack is ready to receive configured events, but the source capture did
not include Windows Winlogbeat/Elastic Agent configuration or domain audit policies.
Copy those from the existing collectors, review their settings, and change their
Elasticsearch output to the new protected endpoint. Match the captured Winlogbeat
8.19.14 routing pipeline and `winlogbeat-*` data-stream template. Verify the actual
collector version rather than assuming the source `.env` reflects it.

Use an appropriate collector account/API key for ingestion. Keep `elastic` for
administration. Provision TLS and network access controls for remote ingestion.

Check Discover for recent `winlogbeat-*` events, then inspect dashboard panels and
the selected time range. Historical events do not move with configuration; restore
an Elasticsearch snapshot separately if history is needed.

## 6. Check operation and diagnose failures

On the Linux VM:

```bash
cd ~/elastic-ad-rebuild
sudo docker compose ps
sudo docker compose logs --tail=100 elasticsearch kibana-setup kibana
```

If readiness times out, inspect logs and check RAM, disk, kernel settings, and
container image access before rerunning `deploy-linux.sh`.

If import reports existing-object conflicts after a partial run, inspect the errors.
When replacing matching saved objects is intended, retry explicitly:

```bash
sudo env RESTORE_OVERWRITE=1 bash scripts/deploy-linux.sh
```

The overwrite retry can replace dashboards with the same IDs in the default space.
If intentionally rebuilding after removing the Elasticsearch data volume, remove
`.restore-complete` so the next deployment restores configuration again.

To stop containers while retaining data:

```bash
sudo docker compose down
```

To start them again, run `sudo bash scripts/deploy-linux.sh`. Back up the private
`.env` and use Elasticsearch snapshots for event data. A project archive is not a
database backup.

## Validation status

Checked locally: shell syntax, YAML/JSON parsing, all saved-object references,
captured-secret exclusion, bundle contents, mocked restore API ordering/conflicts,
and mocked deployment completion/restart behavior. Actual Linux container startup
and Windows-to-Linux ingestion still require testing on your target VM.

References:
- [Publish local code to GitHub](https://docs.github.com/en/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github)
- [GitHub CLI authentication](https://cli.github.com/manual/gh_auth_login)
- [Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
