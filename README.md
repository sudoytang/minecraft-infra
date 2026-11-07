# minecraft-infra

A Paper Minecraft server — Docker, scripts, and config.

## Architecture

```
Tencent CVM (host, Ubuntu)
└─ systemd minecraft.service  (host/minecraft.service: thin oneshot -> docker compose up -d --no-build)
   └─ docker container "minecraft" (image local/minecraft-aio:2, hostname mc-container,
      debian:trixie-slim, mem 3200m / swap 6g, 1.8 CPU, cap_drop ALL)
      └─ tini -> entrypoint.sh -> supervisord
         ├─ paper        run-paper   java -Xms1G -Xmx2560M -jar paper.jar (uid 999 minecraft)
         ├─ afk-azalea   run-afk-azalea -> minecraft-afk-azalea (ONE process, two bots:
         │               bot_7e3a9c overworld, bot_nether1 nether gold farm 183.5 256 55.5)
         ├─ afk          legacy Node/mineflayer bot (autostart=false, retired 2026-10-14)
         ├─ sshd         root, pubkey only (docker/sshd_config, docker/authorized_keys)
         ├─ cron         /etc/cron.d/minecraft (jobs wrapped by run-job: flock + log + notify)
         └─ notify       supervisor event listener -> webhook on unexpected exit/FATAL
```

Container shims: `/usr/bin/systemctl` and `/usr/bin/journalctl` (docker/rootfs/usr/bin) map the
old systemd-style calls used by `minecraft-admin` onto supervisorctl / log files.

### Backups / verification
| when (Asia/Shanghai) | what | script |
|---|---|---|
| daily 06:00 (+0-15 min jitter) | stop-mode local archive in `/srv/minecraft/backups` (Paper restarts) | `rootfs/usr/local/sbin/minecraft-backup` |
| daily 06:40 | newest archive -> Tencent COS Shanghai (internal endpoint) | `minecraft-backup-upload` |
| Sunday 03:17 | newest archive -> OneDrive `MCBackups/minecraft-weekly` (no deletes) | `minecraft-onedrive-weekly` |
| Sunday 04:56 | Grok Bot box: download weekly archive, integrity + NBT/seed check, boot same Paper, verify_bot logs in & visits bot/spawn coords | `restore-verify/run.sh` (scheduled as a Grok Bot automation, not cron) |

Failures of any cron job / supervised program POST to the Grok Bot webhook
(`minecraft-notify-failure`, env from `/etc/minecraft-secrets/minecraft-notify.env`).

## Layout
| dir | contents | source of truth |
|---|---|---|
| `docker/` | Dockerfile, compose.yaml, sshd_config, authorized_keys (public keys), `rootfs/` (copied to `/` in image), `host/` (admin tools + templates copied into image) | host `/opt/minecraft` (build context), cross-checked with the live container |
| `host/` | systemd unit on the CVM | `/etc/systemd/system/minecraft.service` |
| `server-config/` | `files/` = tracked Paper/plugin config, `PLUGINS.md` = jar names/versions/sha256 | live `/srv/minecraft` |
| `afk-bot-azalea/` | Rust/Azalea dual AFK bot + `verify_bot` (restore test client) | box `/workspace/mc-afk-azalea` |
| `restore-verify/` | weekly restore test harness | box `/workspace/mc-restore-verify` |
| `client-pack/` | HMCL/Modrinth client modpack builder + small `.mrpack` | host `~/minecraft-staging` |
| `legacy/` | retired: `node-afk-bot/` (mineflayer, replaced by Azalea 2026-10-14), `v1-host/` (pre-Docker systemd deployment, replaced by docker v2 2026-10-13) | reference only |
| `tools/` | `sync-from-live.sh`, `redact.sh`, `secret-scan.sh` | this repo |

## Rebuild / deploy
Binaries are not in git; put them into `docker/host/` (= `/opt/minecraft/host/`) before building:
* `host/rclone` – official static rclone linux-amd64 (`curl -O https://downloads.rclone.org/rclone-current-linux-amd64.zip`).
* `host/minecraft-afk-azalea` – `cd afk-bot-azalea && cargo +nightly build --release && cp target/release/minecraft-afk-azalea ../docker/host/` (Azalea needs nightly Rust).
* `paper.jar` / plugin jars live on the `/srv/minecraft` bind mount, not in the image. Paper 26.2 from https://papermc.io/downloads ; plugins from their Modrinth/Spigot pages. Check sha256 against `server-config/PLUGINS.md`.

Deploy (on the CVM, ~1–2 min downtime):
```bash
sudo cp -r docker/* /opt/minecraft/        # or edit /opt/minecraft directly
cd /opt/minecraft && sudo docker compose build && sudo docker compose up -d
```
Script-only changes can be hot-copied into the container (`docker cp` / `ssh mc-container`) but
**must also land in `/opt/minecraft`** or the next rebuild reverts them.
Restoring server config: copy from `server-config/files/` into `/srv/minecraft`, then set
local passwords and tokens as needed.

## Credentials on the host
| item | path |
|---|---|
| rclone.conf (COS + OneDrive) | docker volume `minecraft-secrets` -> `/etc/minecraft-secrets/rclone.conf` (symlinked to `/etc/rclone/rclone.conf`) |
| COS bucket env | `/etc/minecraft-secrets/cos.env` |
| failure webhook URL/key | `/etc/minecraft-secrets/minecraft-notify.env` (-> `/etc/minecraft-notify.env`) |
| AuthMe password for bot_nether1 | `/etc/minecraft-secrets/azalea-authme-password`, seeded by entrypoint to `/home/ytang/minecraft-afk-azalea/authme-password` |
| AuthMe password for bot_7e3a9c | docker volume `minecraft-afk` -> `/home/ytang/minecraft-afk-bot/authme-password` |
| container sshd host key | docker volume `minecraft-sshkeys` (`/etc/ssh/keys`, generated on first start) |
| `rcon.password`, `management-server-secret` | `/srv/minecraft/server.properties` |
| box -> host/container SSH keys | box `/home/box/.ssh/` |
| AuthMe DB, ops/whitelist/usercache | `/srv/minecraft` |

## Not in this repo (and why)
* World data, `backups/`, logs, `authme.db`, `ops.json`, `whitelist.json`, `usercache.json`, `banned-*.json` – player/runtime data.
* `*.jar`, rclone, compiled Azalea binary, `node_modules`, restore-verify JDK/cache – large, reproducible (see above).
* One-time migration/installer scripts (kept on the host in `~/minecraft-staging` and `/opt/minecraft`):
  `migrate-v2.sh`, `rollback-v2.sh`, `move-to-opt.sh`, `cleanup.sh`, `add-swap.sh`, `apply-mem.sh`, `compose.yaml.pre-mem`,
  `cos/install-in-container.sh` (+ superseded `cos/` copies), `docker/` (v1 docker attempt: migrate/rollback/patch),
  `install-split-backup.sh`, `install-axgraves.sh`, `notify/install-failure-notify.sh`, `enable-onedrive-backup.sh`,
  `finish-setup.sh`, `go-public.sh`, `set-backup-time.sh`, `disable-ssh-password.sh`, `restore-ssh-password.sh`,
  `reset-world*.sh`, `~/enable-minecraft-rcon.sh`, `~/install-minecraft-admin-rcon.sh`,
  box `mc-afk-azalea/{patch-admin.py,patch-supervisord.py,staging-patch/,deploy-out/}`.

## Keeping it in sync
On the Grok Bot box: `tools/sync-from-live.sh` (read-only on servers) pulls the build context
from `/opt/minecraft`, the systemd unit, live container scripts/config, and box sources;
anything where the live container differs from `/opt/minecraft` is reported as `DRIFT` and the
live copy is taken. Review `git diff --cached`, then `git commit && git push`
(or `tools/sync-from-live.sh --commit "msg"`).
Rule of thumb: change the repo -> copy to `/opt/minecraft` -> rebuild, or hot-fix live -> run sync the same day.
