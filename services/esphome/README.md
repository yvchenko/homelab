# ESPHome

ESPHome dashboard (Device Builder) for creating and managing custom
firmware for ESP8266/ESP32 boards. Runs on `kostyan-server`.

## Access

| What | URL |
|---|---|
| Dashboard | `http://<kostyan-server-lan-ip>:6052` or `http://gwserver.salmon-halfmoon.ts.net:6052` |

## Stack

| Container | Image | Notes |
|---|---|---|
| `esphome` | `ghcr.io/esphome/esphome` | `network_mode: host` required for online/offline status pings in the dashboard |

## Paths

| Path | Purpose |
|---|---|
| `/opt/appdata/esphome` | Mounted to `/config`; holds device YAML configs, build cache, secrets |
| `.env` | Dashboard `USERNAME`/`PASSWORD`, not committed |

## First-run commands

```bash
mkdir -p /opt/appdata/esphome
chown -R 1000:1000 /opt/appdata/esphome   # match homelab uid convention; ESPHome's official image generally runs fine as root too, adjust if permission errors appear

cp .env.example .env
# edit .env with real dashboard credentials

docker compose up -d
```

## Post-startup configuration

- Dashboard is reachable at `:6052` once the container is up (no separate
  setup wizard step needed for the dashboard itself).
- **First flash of any new device requires USB.** The container is started
  in `network_mode: host` for status pings, but flashing over USB also
  needs the device passed through and `privileged: true` (already set).
  Uncomment the `devices:` block in `docker-compose.yml`, pointing at
  whatever the board enumerates as (commonly `/dev/ttyUSB0`), run
  `docker compose up -d` again, then flash from the dashboard UI.
- After the first flash, all subsequent updates are OTA — the USB device
  mapping can be commented back out and the container restarted clean
  (`compose down && compose up -d`).
- New device configs created via the dashboard wizard land under
  `/opt/appdata/esphome/<node_name>.yaml` and are not currently tracked in
  git — decide later whether to commit them to the homelab repo or keep
  them appdata-only (they may contain WiFi credentials in plaintext
  unless using `secrets.yaml`).

## Notes

- Logging level can be overridden via `ESPHOME_LOG_LEVEL` in `.env`
  (default `INFO`).
- If the dashboard's online/offline indicators don't behave correctly,
  check that nothing else on `kostyan-server` is bound to port 6052 in a
  way that conflicts with host networking.
