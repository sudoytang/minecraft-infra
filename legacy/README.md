# legacy (retired, reference only)
* `node-afk-bot/` – mineflayer AFK bot for `bot_7e3a9c` (needs `npm install`; mineflayer fork for 26.2). Replaced by
  `afk-bot-azalea/` on 2026-10-14 (supervisord program `afk` kept with `autostart=false`). Its docker volume
  `minecraft-afk` still holds the overworld bot's `authme-password`.
* `v1-host/` – pre-Docker deployment: Paper as a host systemd service, backup/upload timers, systemd OnFailure
  webhook notify, `minecraft-admin` v1 + sudoers rule. Replaced by the all-in-one container (docker v2) on 2026-10-13.
