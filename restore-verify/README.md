# Restore verification (weekly OneDrive backup)
Files: run.sh, check_structure.py, rcon.py, opt/{jdk-25.0.4.1+1, paper-26.2-123.jar (sha256 = live paper.jar), verify_bot, verify_bot.rs, cache/}
Results: last-result.txt (JSON), last-run.log, last-server.log, last-bot.log

## Weekly procedure (agent; Sunday after 03:17 Asia/Shanghai upload)
OneDrive is reachable only through the agent's user-Onedrive connector (DownloadFile caps at 100 MB, so it can't fetch the 0.85 GB archive).
1. list_drive_items folderId=<REDACTED_ONEDRIVE_FOLDER_ID> (MCBackups/minecraft-weekly); pick newest minecraft-*.tar.gz.
2. get_drive_item itemId=<id> -> take @microsoft.graph.downloadUrl (temporary, pre-authenticated).
3. ONEDRIVE_URL='<url>' ARCHIVE_NAME=<name> EXPECT_SIZE=<size> /workspace/mc-restore-verify/run.sh
   (or curl it into work/ yourself and run `run.sh work/<name>`). Exit 0 = PASS.
The script handles everything else (integrity, structure, boot, bot client, stop, cleanup). KEEP_ARCHIVE=1 keeps the archive.
Rebuild bot: cd /workspace/mc-afk-azalea && ~/.cargo/bin/cargo +nightly build --release --bin verify_bot && cp target/release/verify_bot ../mc-restore-verify/opt/
If the live Paper build changes, update PAPER_JAR/PAPER_SHA in run.sh.
