# Project Changelog

## 2025-05-24
- Evaluated `serjs/go-socks5-proxy` for qBittorrent traffic routing; identified compatibility limitations with current setup
- Planned migration to Dante SOCKS proxy for improved reliability
- Temporarily configured nat-server to route all outbound traffic through kostyan-server to keep torrent traffic off the Spanish IP
- Added and configured Bazarr
- Set up GDrive backup via rclone

## 2025-05-23
- Migrated LibreChat deployment to nat-server
- Replicated Jellyfin + arr stack across both nodes
- Reworked media architecture into dual independent instances (one per node), each serving content from its own local HDD
- Planned Syncthing integration for cross-node library synchronization
- Configured qBittorrent on kostyan-server to route torrent traffic through a SOCKS5 proxy

## 2025-05-19
- Assembled and brought online second homelab node (`nat-server`)

## 2025-04-25
- Finalized and integrated custom chat export/migration tool
- Completed full migration of conversation history from previous AI chat platform into LibreChat

## 2025-04-19
- Published custom LibreChat Docker image
- Migrated LibreChat and Kavita to brother's server

## 2025-04-18
- Built Jellyfin + arr stack + qBittorrent on brother's server via Docker Compose
- Initialized GitOps repository

## 2025-04-16
- Jellyfin bare metal install broke due to hardware/DB issues; decided to migrate to Docker

## 2025-04-10
- Built Kavita instance on local machine

## 2025-04-08
- Brother joined the project; added his server as a node on the Tailscale network

## 2025-04-06
- Installed Jellyfin (bare metal) on brother's server; validated hardware transcoding

## 2025-04-02
- Completed bookmarks AND-logic patch (`$in` → `$all`) on custom LibreChat image

## 2025-03-27
- Set up Tailscale network for homelab connectivity

## 2025-03-25
- Decided to build a dedicated home server node; began hardware planning

## 2025-03-24
- Migrated conversation history into LibreChat using scraper output

## 2025-03-23
- Wrote Python API scraper to extract conversation history from prior AI chat platform

## 2025-03-22
- Began building LibreChat; initial stack running on local machine via Docker Desktop