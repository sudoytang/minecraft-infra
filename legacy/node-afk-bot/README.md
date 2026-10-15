# Minecraft AFK bot

Runs an offline-mode Mineflayer client for the local Paper server. The AuthMe credential is stored separately in `authme-password` with mode `0600`; the bot process does not print it.

Run from this directory with `node bot.js`. The process reconnects after disconnects.
