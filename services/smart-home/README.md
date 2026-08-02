# Smart Home

ESPHome dashboard (Device Builder) for creating and managing custom firmware
for ESP8266/ESP32 boards. Runs on `kostyan-server` — single instance, not
duplicated.

## Stack

| Component | Purpose |
|---|---|
| ESPHome | Dashboard for building/flashing/managing ESP8266/ESP32 firmware |

Runs as a k8s Deployment in the `smart-home` namespace.

## Paths

| Path | Purpose |
|---|---|
| `/opt/appdata/esphome` | Mounted via `hostPath` to `/config`; holds device YAML configs, build cache, secrets |

Dashboard credentials (`USERNAME`/`PASSWORD`) are **not** an env file anymore
— they're a k8s `Secret`, injected via `envFrom`. Created imperatively, never
committed to git:

```bash
sudo k3s kubectl create secret generic esphome-credentials \
  --namespace smart-home \
  --from-literal=USERNAME='...' \
  --from-literal=PASSWORD='...'
```

`ESPHOME_LOG_LEVEL` (not sensitive) stays a plain env var in the manifest,
default `INFO`.

`privileged: true` from the old Compose config carries over as
`securityContext.privileged: true` on the container — same effective
permission level, k8s-native spelling.

## First-run commands

```bash
mkdir -p /opt/appdata/esphome
chown -R 1000:1000 /opt/appdata/esphome   # match homelab uid convention

sudo k3s kubectl create namespace smart-home
sudo k3s kubectl create secret generic esphome-credentials \
  --namespace smart-home \
  --from-literal=USERNAME='...' \
  --from-literal=PASSWORD='...'

sudo k3s kubectl apply -f services/smart-home/esphome/manifest.yaml
sudo k3s kubectl get pods -n smart-home -o wide
```

**Before creating the Secret, double-check it actually landed where
expected** — `kubectl create secret ... --namespace X` can silently land in
the wrong namespace with zero data if a shell-quoting issue swallows the
flag (this happened on first setup — see gotchas below). Verify with:

```bash
sudo k3s kubectl get secret esphome-credentials -n smart-home
```
Confirm `DATA` is non-zero before trusting it.

## Post-startup configuration

- Dashboard is reachable at `:6052` once the pod is `Running` — no separate
  setup wizard step needed for the dashboard itself.
- New device configs created via the dashboard wizard land under
  `/opt/appdata/esphome/<node_name>.yaml` and are not currently tracked in
  git — decide later whether to commit them to the homelab repo or keep
  them appdata-only (they may contain WiFi credentials in plaintext unless
  using `secrets.yaml`).

## First-flash-over-USB (improved over the old Compose pattern)

Previously, flashing a new device over USB required uncommenting a
`devices:` line in the compose file, restarting, flashing, then remembering
to comment it back out and restart again — the permanent service definition
had to be temporarily mutated for a one-time operation.

**Now: a separate, throwaway `Job`** (`services/smart-home/esphome/flash-job.yaml`,
committed but never applied by default) mounts `/dev/ttyUSB0` and runs once.
The main Deployment is never touched:

```bash
# 1. Confirm the device is physically plugged into kostyan-server and
#    shows up at /dev/ttyUSB0 — check the actual path before applying:
ls /dev/ttyUSB*

# 2. Apply the flash Job
sudo k3s kubectl apply -f services/smart-home/esphome/flash-job.yaml

# 3. Perform the flash via the ESPHome UI/CLI as normal

# 4. Clean up
sudo k3s kubectl delete job esphome-flash -n smart-home
```

If the device enumerates as a different path (`ttyUSB1`, etc.), update the
Job's `hostPath`/mount path to match before applying — don't assume
`ttyUSB0` blindly.

After the first flash, all subsequent updates are OTA — no USB, no Job
needed.

## Known gotchas

- **Secret landing in the wrong namespace, silently.** First setup attempt
  ran `kubectl create secret ... --namespace smart-home` but it actually
  landed in `default`, with zero data (`DATA 0`) — a shell-quoting issue
  likely caused both the namespace flag and the `--from-literal` values to
  not take effect as intended. Symptom: `CreateContainerConfigError` with
  `Error: secret "esphome-credentials" not found`, even though
  `kubectl get secrets -A` showed a same-named secret existing elsewhere.
  **When a "not found" error contradicts an "already exists" error for the
  same object name, check every namespace** (`kubectl get secrets -A`) —
  don't assume a namespace flag was actually honored. Once fixed, the
  already-scheduled pod self-healed within seconds with no manual restart —
  kubelet retries `CreateContainerConfigError` pods on its own.
- Hardware flashing is currently pending — dashboard-only setup so far, no
  devices flashed under k3s yet. The Job-based flash flow above is
  committed and ready but not yet exercised for real.
