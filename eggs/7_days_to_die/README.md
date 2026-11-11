# 7 Days To Die

Based on upstream `pelican-eggs/games-steamcmd` `7_days_to_die/egg-7-days-to-die.json` (see `UPSTREAM.md`),
converted to Pelican's YAML format. Same uuid, so importing it updates the existing egg.

## Changes

- **Install script:** the master SteamCMD script (`scripts/steamcmd-install.sh`): retries SteamCMD and fails
  the install when the game is not fully installed.
- **New variable `GAME_BINARY`** = `7DaysToDieServer.x86_64`, hidden from clients and not editable.
- **Startup command:** starts with the master startup check (`scripts/startup-check.txt`); the rest is
  upstream's command unchanged.
- **`update_url`** points at this file in this repo (upstream has none).

## Why

On pp-wings-1 (2026-11), a new server was marked installed within minutes with 175 MB on disk: SteamCMD's
anonymous login had timed out ("Waiting for user info...ERROR! (Timed out)"), it exited 0, and upstream's
script then reported "Installation completed". The server's boot update timed out too, and the startup
command waited forever for the telnet port of a game that was not there.

## After importing

The panel's two existing 7 Days To Die servers keep their own startup command. To give them the startup
check, copy the egg's startup command onto each server's Startup tab.
