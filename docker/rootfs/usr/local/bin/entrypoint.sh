#!/bin/bash
set -euo pipefail
mkdir -p /etc/ssh/keys /run/sshd /var/log/minecraft /var/run/minecraft
[[ -f /etc/ssh/keys/ssh_host_ed25519_key ]] || ssh-keygen -q -t ed25519 -N '' -f /etc/ssh/keys/ssh_host_ed25519_key
chmod 700 /etc/minecraft-secrets 2>/dev/null || true
# Seed Azalea AuthMe password into ytang home (secrets volume is root-only 0700)
if [[ -f /etc/minecraft-secrets/azalea-authme-password ]]; then
  mkdir -p /home/ytang/minecraft-afk-azalea
  if [[ ! -f /home/ytang/minecraft-afk-azalea/authme-password ]]; then
    cp /etc/minecraft-secrets/azalea-authme-password /home/ytang/minecraft-afk-azalea/authme-password
  fi
  chown -R ytang:ytang /home/ytang/minecraft-afk-azalea
  chmod 700 /home/ytang/minecraft-afk-azalea
  chmod 600 /home/ytang/minecraft-afk-azalea/authme-password
fi
# cron jobs need env (TZ, PATH) — cron strips it
printenv | grep -E '^(TZ|LANG|JAVA_OPTS)=' > /etc/environment || true
exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
