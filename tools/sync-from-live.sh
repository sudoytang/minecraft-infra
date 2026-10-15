#!/usr/bin/env bash
# Pull the tracked (non-secret) infra files from the live host/container and the box
# into this repo, redact secrets, then show what changed. Read-only on the servers.
# Usage: tools/sync-from-live.sh [--commit "message"]
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
HOST_SSH=(ssh -o BatchMode=yes -i $SSH_KEY -o IdentitiesOnly=yes user@HOST)
CTR_SSH=(ssh -o BatchMode=yes mc-container)
AZALEA_SRC=${AZALEA_SRC:-/workspace/mc-afk-azalea}
VERIFY_SRC=${VERIFY_SRC:-/workspace/mc-restore-verify}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/opt" "$T/ctr"

echo ">> host: /opt/minecraft (build context, minus binaries) + systemd unit"
"${HOST_SSH[@]}" 'tar -C /opt/minecraft -czf - --exclude=host/rclone --exclude=host/minecraft-afk-azalea \
   Dockerfile compose.yaml sshd_config authorized_keys rootfs host' | tar -C "$T/opt" -xzf -
"${HOST_SSH[@]}" 'cat /etc/systemd/system/minecraft.service' > "$T/minecraft.service"

echo ">> container: live scripts + server config"
"${CTR_SSH[@]}" 'cd / && tar -czf - \
  usr/local/sbin/minecraft-admin usr/local/sbin/minecraft-rcon usr/local/sbin/minecraft-backup \
  usr/local/sbin/minecraft-backup-upload usr/local/sbin/minecraft-onedrive-weekly usr/local/sbin/minecraft-notify-failure \
  usr/local/bin/entrypoint.sh usr/local/bin/notify-failure usr/local/bin/run-afk usr/local/bin/run-afk-azalea \
  usr/local/bin/run-job usr/local/bin/run-paper usr/local/bin/supervisor-notify usr/bin/systemctl usr/bin/journalctl \
  etc/cron.d/minecraft etc/supervisor/supervisord.conf usr/local/share/minecraft-admin \
  srv/minecraft/server.properties srv/minecraft/bukkit.yml srv/minecraft/spigot.yml srv/minecraft/commands.yml \
  srv/minecraft/eula.txt srv/minecraft/config/paper-global.yml srv/minecraft/config/paper-world-defaults.yml \
  srv/minecraft/plugins/AuthMe/config.yml srv/minecraft/plugins/AuthMe/commands.yml srv/minecraft/plugins/AuthMe/spawn.yml \
  srv/minecraft/plugins/AuthMe/welcome.txt srv/minecraft/plugins/AuthMe/messages \
  srv/minecraft/plugins/AxGraves/config.yml srv/minecraft/plugins/AxGraves/messages.yml \
  srv/minecraft/plugins/spark/config.json' | tar -C "$T/ctr" -xzf -
# plugin inventory (name/version/sha256), computed in the container with python3
"${CTR_SSH[@]}" 'python3 - <<"PY"
import glob, hashlib, json, zipfile, re
rows = []
for j in sorted(glob.glob("/srv/minecraft/plugins/*.jar")) + ["/srv/minecraft/paper.jar"]:
    z = zipfile.ZipFile(j); name = ver = "?"
    for meta in ("paper-plugin.yml", "plugin.yml"):
        if meta in z.namelist():
            t = z.read(meta).decode("utf-8", "replace")
            name = re.search(r"^name:\s*(.+)$", t, re.M).group(1).strip().strip("\x27\"")
            ver = re.search(r"^version:\s*(.+)$", t, re.M).group(1).strip().strip("\x27\""); break
    if j.endswith("paper.jar"):
        name = "Paper"; ver = json.loads(z.read("version.json"))["id"] + " (version.json)"
    h = hashlib.sha256(open(j, "rb").read()).hexdigest()
    rows.append("| %s | %s | %s | `%s` |" % (j.split("/")[-1], name, ver, h))
print("\n".join(rows))
PY' > "$T/plugins.md"

R="$REPO"; C="$T/ctr"; O="$T/opt"
echo ">> docker/ (build context: from /opt/minecraft; scripts verified against live container)"
mkdir -p "$R/docker"
cp "$O/Dockerfile" "$O/compose.yaml" "$O/sshd_config" "$O/authorized_keys" "$R/docker/"
rm -rf "$R/docker/rootfs" "$R/docker/host"; cp -a "$O/rootfs" "$O/host" "$R/docker/"
# live container is authoritative for anything also present in the image context
for p in usr/local/sbin/minecraft-backup usr/local/sbin/minecraft-backup-upload usr/local/sbin/minecraft-onedrive-weekly \
         usr/local/bin/entrypoint.sh usr/local/bin/notify-failure usr/local/bin/run-afk usr/local/bin/run-afk-azalea \
         usr/local/bin/run-job usr/local/bin/run-paper usr/local/bin/supervisor-notify usr/bin/systemctl usr/bin/journalctl \
         etc/cron.d/minecraft etc/supervisor/supervisord.conf; do
  cmp -s "$C/$p" "$R/docker/rootfs/$p" || { echo "   DRIFT live!=image: $p (taking live)"; cp "$C/$p" "$R/docker/rootfs/$p"; }
done
for f in minecraft-admin minecraft-rcon minecraft-backup-upload minecraft-notify-failure; do
  cmp -s "$C/usr/local/sbin/$f" "$R/docker/host/$f" || { echo "   DRIFT live!=image: host/$f (taking live)"; cp "$C/usr/local/sbin/$f" "$R/docker/host/$f"; }
done
for f in $(ls "$C/usr/local/share/minecraft-admin"); do
  cmp -s "$C/usr/local/share/minecraft-admin/$f" "$R/docker/host/templates/$f" || { echo "   DRIFT live!=image: templates/$f (taking live)"; cp "$C/usr/local/share/minecraft-admin/$f" "$R/docker/host/templates/$f"; }
done

echo ">> host/ (systemd)"
mkdir -p "$R/host"; cp "$T/minecraft.service" "$R/host/minecraft.service"

echo ">> server-config/"
rm -rf "$R/server-config/files"; mkdir -p "$R/server-config/files"
cp -a "$C/srv/minecraft/." "$R/server-config/files/"
{ echo "| jar | name | version | sha256 |"; echo "|---|---|---|---|"; cat "$T/plugins.md"; } > "$R/server-config/PLUGINS.md"

echo ">> afk-bot-azalea/ (box: $AZALEA_SRC)"
mkdir -p "$R/afk-bot-azalea/src/bin" "$R/afk-bot-azalea/.cargo"
cp "$AZALEA_SRC/Cargo.toml" "$AZALEA_SRC/Cargo.lock" "$R/afk-bot-azalea/"
cp "$AZALEA_SRC/src/main.rs" "$R/afk-bot-azalea/src/"; cp "$AZALEA_SRC/src/bin/"*.rs "$R/afk-bot-azalea/src/bin/"
cp "$AZALEA_SRC/.cargo/config.toml" "$R/afk-bot-azalea/.cargo/"

echo ">> restore-verify/ (box: $VERIFY_SRC)"
mkdir -p "$R/restore-verify"
cp "$VERIFY_SRC/run.sh" "$VERIFY_SRC/check_structure.py" "$VERIFY_SRC/rcon.py" "$VERIFY_SRC/README.md" "$R/restore-verify/"

"$R/tools/redact.sh" "$R"
"$R/tools/secret-scan.sh" "$R"
cd "$R"; git add -A; git status --short
if [[ "${1:-}" == "--commit" ]]; then
  git diff --cached --quiet && echo "no changes" || git commit -q -m "${2:-sync from live $(date +%F)}" && git log --oneline -1
fi
