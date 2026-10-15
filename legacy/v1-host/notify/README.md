# Minecraft systemd OnFailure → webhook notify

Staging only until you run the installer. Does **not** touch `/etc` by itself.

## What it does

When `minecraft.service`, `minecraft-backup.service`, or `minecraft-backup-upload.service` enters **failed**, systemd starts `minecraft-failure@<unit>.service`, which POSTs a small JSON payload (hostname, unit, time, last ~30 journal lines) to `WEBHOOK_URL`.

The notifier always exits 0 after at most one curl retry so a bad webhook cannot cascade more failures.

## Install (once, needs your sudo)

```bash
sudo bash /home/ytang/minecraft-staging/notify/install-failure-notify.sh
sudoedit /etc/minecraft-notify.env   # or: sudo nano /etc/minecraft-notify.env
```

Set:

- `WEBHOOK_URL=` — HTTPS URL from the Grok Bot **webhook / failure-alert routine** panel
- `WEBHOOK_KEY=` — optional shared secret from the same panel (sent as `Authorization: Bearer …` and `X-Webhook-Key`)

File mode stays `600` (root-only).

Verify:

```bash
systemctl show minecraft.service -p OnFailure --value
systemctl show minecraft-backup.service -p OnFailure --value
systemctl show minecraft-backup-upload.service -p OnFailure --value
```

Expect values like `minecraft-failure@minecraft.service`.

Optional test (does not fail the game server):

```bash
sudo MONITOR_UNIT=minecraft.service EnvironmentFile=/etc/minecraft-notify.env \
  bash -c 'set -a; . /etc/minecraft-notify.env; set +a; /usr/local/sbin/minecraft-notify-failure'
```

Or:

```bash
sudo systemctl start minecraft-failure@minecraft.service
journalctl -u minecraft-failure@minecraft.service -n 20 --no-pager
```

## Files

| Staging path | Installed path |
|---|---|
| `minecraft-notify-failure.sh` | `/usr/local/sbin/minecraft-notify-failure` |
| `minecraft-failure@.service` | `/etc/systemd/system/minecraft-failure@.service` |
| `*.service.d-onfailure.conf` | `/etc/systemd/system/<unit>.d/onfailure.conf` |
| (created by installer) | `/etc/minecraft-notify.env` |

## Notes

- Fill the webhook URL/key **before** relying on alerts; empty `WEBHOOK_URL` makes the script no-op (exit 0) and log to stderr.
- Daily “all quiet / backup OK” checks are separate (Grok Bot routine), not this OnFailure hook.
