# minecraft-afk-azalea

Rust ([Azalea](https://github.com/azalea-rs/azalea), git master) offline-mode AFK bots for the local
Paper 26.2 server. **One process, two accounts (swarm)** – cheaper than two processes.

| bot | world | position after login |
|---|---|---|
| `bot_7e3a9c` | overworld | keeps chunks loaded / counts for sleep % |
| `bot_nether1` | nether gold farm | `/execute in minecraft:the_nether run tp @s 183.5 256 55.5` (needs op) |

* Connects to `127.0.0.1:25565`; AuthMe `/register` then `/login` on **every** (re)connect or login
  prompt, then re-teleports (fix of 2026-10-15 for the AuthMe login-timeout kick loop).
* Passwords: `AUTHME_PASSWORD_FILE` (nether) and `AUTHME_PASSWORD_FILE_MAIN` (overworld); never logged.
* Runs under supervisord program `afk-azalea` (`docker/rootfs/usr/local/bin/run-afk-azalea`);
  control with `minecraft-admin afk status|start|stop|restart`.
* `src/bin/verify_bot.rs`: test client used by `restore-verify/` (env VERIFY_SERVER/USER/PASSWORD/SECONDS;
  password is random per run, `verifyPw123` is only a throwaway default for the temp server).

Build: `cargo +nightly build --release` -> `target/release/minecraft-afk-azalea` (~28 MB, stripped);
copy to `/opt/minecraft/host/` and rebuild the image (or hot-copy to `/usr/local/bin/` + `supervisorctl restart afk-azalea`).
