# Active Directory Elastic deployment

Follow the [GitHub-to-Linux deployment tutorial](docs/TUTORIAL.md) for publishing,
VM setup, dashboard access, collector configuration, and troubleshooting.

Rebuild project based on configuration captured from the existing Ubuntu VM on
October 26, 2026. No changes have been made to that VM.

## Current status

- Captured: Compose source, Kibana settings, Docker inventory, and Winlogbeat package.
- Rebuilt: Elasticsearch/Kibana pinned to **8.19.14**, persistent data volume,
  authenticated health checks, Kibana initialization, private environment generation.
- Included: 11 real dashboards, 105 visualizations, eight saved searches, two data
  views, two tags, six Winlogbeat 8.19.14 pipelines, the Winlogbeat index template,
  and the source's 60-day lifecycle policy. All saved-object references resolve.
- Pending: Windows collector configuration and a fresh-VM startup test.
- Nothing has been published or pushed. Raw captures remain in ignored `private/`.

Source versions: Docker Engine 27.2.1, Compose 2.29.2. Source Elasticsearch heap
ranged from 2g to 8g; this rebuild defaults both bounds to 2g for predictable memory
use. Tune `ES_HEAP` for your target. Ports default to loopback; the source published
both ports on all interfaces. Its external HTTPS Kibana URL implies additional
infrastructure, but no proxy configuration was captured. Provision TLS termination,
DNS, and the proxy separately for equivalent external access.

## Refresh the source capture when needed

Run from **Mac Terminal**, which has working SSH access:

```bash
cd ~/elastic-ad-rebuild
bash scripts/capture-live.sh
```

Requires the Mac's bundled Bash/Ruby/SSH and Ubuntu Python 3. It prompts for sudo
privately, reads the existing Elasticsearch password on the VM, and exports every
space's dashboards with references, Elasticsearch templates, ILM policies, ingest
pipelines, index names/counts, and node settings. No event documents are exported
and no services changed. Output: `private/live.*/source/`. Report that path to
review changes before updating the bundled dashboards and policies. The current
bundle already includes the reviewed October 26 live export.

The exporter expects HTTP listeners on VM loopback and standard `.env` key/value
syntax. API failures stop export. Unrelated saved objects, connector secrets,
Fleet configuration, and Windows collector configuration are not included.

## Deploy on a separate Linux VM

On the Mac, build and transfer the portable archive:

```bash
cd ~/elastic-ad-rebuild
bash scripts/package-linux.sh
scp ~/elastic-ad-linux.tar.gz USER@NEW_VM_IP:~/
```

On a fresh Ubuntu VM (22.04/24.04 LTS recommended):

```bash
tar -xzf ~/elastic-ad-linux.tar.gz
cd ~/elastic-ad-rebuild
sudo bash scripts/prepare-ubuntu.sh
sudo bash scripts/deploy-linux.sh
```

Host preparation uses Docker's official apt repository, installs Docker and Compose
if absent, and persists the Elasticsearch kernel setting. It preserves existing
Docker installations and requires their Compose v2 plugin to be present. Docker
packages use the current repository version; Elastic images are pinned to 8.19.14.
Deployment creates private credentials, waits up to five minutes for health checks,
then restores the Winlogbeat policy, pipelines, template, and all 128 saved objects.
It records successful restore in `.restore-complete` and skips it on later restarts.
Remove this marker if intentionally rebuilding after deleting the data volume.
On other Linux distributions, install Docker/Compose and set the kernel limit yourself,
then run `sudo bash scripts/deploy-linux.sh`.

Do not deploy into the source VM's existing Compose project: project and volume
names match the captured deployment and could affect its existing services.
Use a separate test VM.

Install Docker Engine and Compose v2 using your normal provisioning. Allocate
memory for Elasticsearch heap, native memory, Kibana, and the OS; 8 GB RAM is a
starting test allocation. Provide adequate disk for event retention. Configure:

```bash
echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-elastic-ad.conf
sudo sysctl --system
```

Transfer reviewed source, excluding `private/` and real credentials, then:

```bash
cd elastic-ad-rebuild
bash scripts/init-env.sh
# Edit .env for your target host and available memory.
docker compose config --quiet
docker compose up -d
docker compose ps
docker compose logs --tail=100 elasticsearch kibana-setup kibana
```

Environment generation creates unique passwords and three persistent Kibana keys,
refusing to overwrite an existing `.env`. Back up that file privately. Generated
Kibana system passwords are 64 hexadecimal characters. Setup fails on HTTP errors.
Changing `ELASTIC_PASSWORD` does not reset an existing volume's password. Changing
Kibana keys may prevent access to existing encrypted saved objects.

Access from Mac Terminal:

```bash
ssh -N -o ExitOnForwardFailure=yes -L 15601:127.0.0.1:5601 admiral@NEW_VM_IP
```

Open `http://localhost:15601`; log in as `elastic` with the target `.env` password.
For permanent access configure an HTTPS proxy and `KIBANA_PUBLIC_BASE_URL`.
Remote collectors need a reachable Elasticsearch endpoint: provide a TLS proxy
and access controls, or an appropriate private `ES_BIND_IP` on your trusted network.
The captured stack uses HTTP internally.

## Windows Active Directory ingestion workflow

Use this order on a fresh deployment. Complete the Docker stack first, then install
Winlogbeat on each approved Active Directory domain controller, and only then enable
the Windows integrations and validate events.

### 1. Start the Docker stack

On the Linux Elastic VM:

```bash
cd ~/elastic-ad-rebuild
bash scripts/init-env.sh
# Review .env and set ES_HEAP, bind addresses, and the Kibana public URL.
docker compose config --quiet
docker compose up -d

docker compose ps
docker compose logs --tail=100 elasticsearch kibana-setup kibana
```

Wait until Elasticsearch and Kibana are healthy. Confirm the Kibana URL is reachable
from the administrator network, and keep Elasticsearch protected behind the approved
network controls. Do not put `.env` or generated credentials in GitHub.

### 2. Install Winlogbeat on the Active Directory instance

The repository includes `winlogbeat_2026-10-28_0539.zip`. Transfer it to the approved
Windows domain controller using your organization's secure file-transfer method.
Run PowerShell as Administrator:

```powershell
Expand-Archive .\\winlogbeat_2026-10-28_0539.zip -DestinationPath 'C:\\Program Files'
cd 'C:\\Program Files\\winlogbeat'
# Edit winlogbeat.yml with the approved Elastic endpoint and credentials.
# Validate before installing:
.\\winlogbeat.exe test config -c .\\winlogbeat.yml
.\\winlogbeat.exe test output -c .\\winlogbeat.yml
.\\install-service-winlogbeat.ps1
Start-Service winlogbeat
Get-Service winlogbeat
```

Use a dedicated least-privilege ingestion credential or API key. Use TLS for any
endpoint reachable outside the private Docker network; do not paste credentials into
this repository. Start with one domain controller and confirm ingestion before adding
more collectors.

### 3. Enable Windows integrations and validate

In Kibana, open **Integrations**, install or configure the approved **Windows**
integration for the target data stream, and assign it only to the intended Windows
host policy. Enable the event channels required by the security team, typically
Security, System, Application, and PowerShell; add Sysmon only after Sysmon is deployed
and approved on the host.

Validate in this order:

```powershell
.\\winlogbeat.exe test output -c .\\winlogbeat.yml
Get-Service winlogbeat
Get-WinEvent -LogName Security -MaxEvents 1
```

Then in Kibana check **Discover** for recent `winlogbeat-*` or Windows integration
data, confirm the host name and event timestamps, and open the restored AD dashboards.
Investigate rejected events, mapping errors, or missing channels before enabling more
hosts. Keep the original configuration and service stop command available for rollback:

```powershell
Stop-Service winlogbeat
```


## Dashboard restore and AD ingestion

`deploy-linux.sh` automatically restores the reviewed files in `dashboards/` and
`config/elasticsearch/`. Pipelines are restored in dependency order. Only the
captured Winlogbeat template/policy/pipelines are restored; unrelated Fleet/APM
resources and historical index metadata remain private. Obsolete source-host
`parsedUrl` metadata was removed from visualization state for portability.

Import conflicts stop the restore. If a partial run already imported some objects,
inspect the errors and deliberately retry with overwrite only when appropriate:

```bash
sudo env RESTORE_OVERWRITE=1 bash scripts/deploy-linux.sh
```

This may replace existing saved objects with matching IDs in the default space.
For an explicit manual restore without the deployment wrapper:

```bash
sudo docker compose --profile restore run --rm --no-deps restore
```

In Kibana, use Stack Management → Saved Objects → Import. Select the correct space
(create it first) and corresponding NDJSON file. Optional Python 3 tooling:

```bash
python3 scripts/kibana.py import dashboards/default.ndjson
# For another space:
python3 scripts/kibana.py import dashboards/SPACE.ndjson --url http://localhost:15601/s/SPACE
```

No Windows Winlogbeat/Elastic Agent configuration was captured. The source `.env`
lists Winlogbeat 8.19.14, which does not prove its running version. Capture Windows
collector configuration and domain-controller audit policies to reproduce ingestion.
Do not assume a generic Winlogbeat example matches these dashboards. Source `.env`
also lists 60-day retention, confirmed by the captured `winlogbeat-policy` delete
phase. It rolls over at one day or 5 GB and enters warm/read-only after seven days.
The restored index template declares a data stream for `winlogbeat-*`; configure
collectors consistently with this captured template and routing pipeline.

On the separate VM verify Elasticsearch health, recent AD events, collector
connections, expected fields, data views, and all dashboard panels. Docker is absent
on this Mac, so no Compose startup test has run here. Local checks covered shell
syntax, YAML/JSON parsing, all saved-object references, credential exclusion, and
the restore code's request order, dependency resolution, and conflict handling with
mock APIs. These checks do not replace a live Linux deployment test.

## Backups and sharing

Configuration and dashboard exports do not preserve historical AD events. Use
Elasticsearch snapshots and test restore separately. Never use a copy of a live
data directory as a database backup. Preserve original private Kibana encryption
keys when restoring encrypted objects from the existing deployment.

Review files before sharing. Never commit `private/`, `.env`, collector `config.yml`,
service-account JSON, or event documents. Commit reviewed source and `.env.example`
only. GitHub publication remains pending.

References:
- [Docker installation on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [Elasticsearch Docker, version 8.19](https://www.elastic.co/guide/en/elasticsearch/reference/8.19/docker.html)
- [Kibana saved-object export](https://www.elastic.co/docs/api/doc/kibana/v8/operation/operation-exportsavedobjectsdefault)
- [Elasticsearch snapshots](https://www.elastic.co/docs/deploy-manage/tools/snapshot-and-restore)
