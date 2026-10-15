# Drift snapshot (2026-10-15, at repo creation)

Compared: host staging `~/minecraft-staging/docker-v2` vs host `/opt/minecraft` (real build context) vs live container.
This repo tracks **what is actually deployed** (`/opt/minecraft` == live container for every file below except where noted).

| item | staging | /opt/minecraft | live container | tracked |
|---|---|---|---|---|
| `host/minecraft-admin` | 16739 B, 09:44 | 13174 B, 09:44 | 13174 B, 09:38 (== /opt) | live |
| `compose.yaml` | 1160 B: old mem (2800m, no swap, Xmx2G) **+** `afk-azalea` named volume | 1065 B: mem 3200m / swap 6g / Xmx2560M, no afk-azalea volume | cgroup 3200 MiB / swap 6g, JAVA_OPTS Xmx2560M, no afk-azalea mount (== /opt) | /opt |
| `Dockerfile` (COPY host/minecraft-afk-azalea) | present | present (synced 2026-10-14) | binary present | identical, no drift |
| `minecraft-compose.service` | WorkingDirectory = staging dir | (file) same as staging | installed unit uses `/opt/minecraft` + `-f compose.yaml` | installed unit (`host/minecraft.service`) |
| rootfs/*, other host/* scripts, templates | | | all identical | — |
| `azalea-src/` | == box `/workspace/mc-afk-azalea` src (2026-10-15 relogin fix) | n/a | binary | box source |

## minecraft-admin: staging vs live
Live = v1 `minecraft-admin` (+ `rcon` passthrough action from `install-minecraft-admin-rcon.sh`, + 2026-10-15
`afk` -> `supervisorctl afk-azalea` patch). Staging contains **all of that plus** an un-deployed set of changes:
* `whitelist-add/remove`, `ops-add/remove` apply live via `minecraft-rcon` (`whitelist add`, `op`, ...) and update the
  JSON file, **no Paper restart** (live still wraps them in `restart_if_active` = stop/start Paper, kicking players).
* `auth-config-apply`, `auth-test-on`, `auth-test-off` now require an explicit `--restart` flag and warn before restarting.
* new helper `paper_is_active`, `require_restart_flag`.
So staging is the *newer* version (superset), not live. It is kept on branch `staging-minecraft-admin` in this repo
until it is deployed; after deploying (copy to `/opt/minecraft/host/` + container `/usr/local/sbin/`), merge that branch.

## Other observations
* `templates/server.properties(.auth-test)` contain `enable-rcon` but no `rcon.password`; `auth-test-on/off` installs
  them over the live server.properties, which would drop the rcon password/port until re-added.
* `/opt/minecraft` still holds one-time scripts (migrate/rollback/cleanup/move-to-opt/add-swap/apply-mem) – harmless, untracked.
