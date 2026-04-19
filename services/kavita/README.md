# Kavita

Self-hosted manga and ebook library.

## Access

| Interface | URL |
|-----------|-----|
| Web UI | http://kostyan-server.salmon-halfmoon.ts.net:5000 |

Accessible over Tailscale only — not exposed to the public internet.

## Stack

| Component | Image |
|-----------|-------|
| Kavita | `jvmilazz0/kavita:latest` |

## Paths

| Purpose | Host path | Container path |
|---------|-----------|----------------|
| Config & database | `/opt/appdata/kavita` | `/kavita/config` |
| Books | `/mnt/media/books` | `/media/books` |

## First run

```bash
# Create config directory
sudo mkdir -p /opt/appdata/kavita

# Start
docker compose up -d

# Logs
docker compose logs -f kavita
```

The first user to register becomes the admin. Add `/media/books` as a library
in the UI after logging in.

## Migrating from another instance

To carry over user data, reading progress, and bookmarks, copy the config
directory from the source machine before starting the container.

```powershell
# On the source machine (Windows)
Compress-Archive -Path C:\homelab\kavita -DestinationPath C:\homelab\kavita-backup.zip
scp C:\homelab\kavita-backup.zip nat@kostyan-server.salmon-halfmoon.ts.net:/home/nat/kavita-backup.zip
```

```bash
# On target server
unzip ~/kavita-backup.zip -d ~/kavita-extract
sudo cp -r ~/kavita-extract/kavita/* /opt/appdata/kavita/

# Then start the container
docker compose up -d
```
