# pelican-eggs-fo

The Pelican eggs we run, changed from [pelican-eggs](https://github.com/pelican-eggs) where upstream did not
work well enough for us. Only changed eggs live here; every other egg is used as published upstream.

| Egg | Upstream | What changed |
|---|---|---|
| [7 Days To Die](eggs/7_days_to_die/) | `games-steamcmd/7_days_to_die` | SteamCMD retries, install and startup checks |

## Layout

```
eggs/<game>/egg-<game>.yaml   the egg, in Pelican's YAML format (PLCN_v3), update_url pointing at itself
eggs/<game>/README.md         what changed from upstream, and why
scripts/steamcmd-install.sh   master install script for every SteamCMD egg
scripts/startup-check.txt     master check that starts every SteamCMD egg's startup command
tests/                        the checks bin/check runs
UPSTREAM.md                   the upstream file and commit each egg is based on
```

Run `bin/check` before every commit (needs bash and python3 with PyYAML; shellcheck when installed). GitHub
Actions runs the same on every push.

## How the panel picks up changes

Each egg's `meta.update_url` is the raw URL of its own file on this repo's `main` branch, e.g.
`https://raw.githubusercontent.com/friendlyopposition/pelican-eggs-fo/main/eggs/7_days_to_die/egg-7-days-to-die.yaml`.
The panel checks it once a day (`p:egg:check-updates`) and marks the egg as having an update in
Admin → Eggs; the egg's **Update** action (or the bulk action) then applies it.

- The panel downloads the file without credentials: **this repo must stay public**. Eggs hold no secrets
  (`bin/check` fails on a default value for a variable named like a password, token or key).
- An egg is matched by its `uuid`. The eggs here keep upstream's uuid, so importing one updates the panel's
  existing egg in place instead of adding a second egg.
- **Existing servers keep their own startup command.** Updating an egg changes the egg's startup command,
  not the servers': change those on each server's Startup tab (or in the admin server edit page).
- New egg variables reach existing servers with their default value.

## SteamCMD eggs

Every egg tagged `steamcmd` must use the master install script and startup check unchanged (`bin/check`
compares them byte for byte), and define a hidden, non-editable `GAME_BINARY` variable: the file the server
runs, relative to the server folder (e.g. `7DaysToDieServer.x86_64`). That one variable is all that differs
per game.

- **Install script** (`scripts/steamcmd-install.sh`): upstream's SteamCMD script, plus up to 4 SteamCMD
  attempts (30 s, 60 s, 120 s apart). An attempt only counts when Steam's app manifest says the app is fully
  installed (`StateFlags 4`) and `GAME_BINARY` exists; otherwise the script exits 1. Upstream exits 0 after a
  Steam timeout with nothing installed, and the server is then marked installed.
- **Startup check** (`scripts/startup-check.txt`), put in front of the game's startup command: if
  `GAME_BINARY` is missing, the server stops with "The game files are missing..." instead of looping.

Wings (v1.0.0-rc.1) does not look at the install script's exit code, so a failed install still shows as
installed on the panel: the startup check is what tells the client.

### Changing the master script

1. Edit `scripts/steamcmd-install.sh` (or `startup-check.txt`).
2. Paste it into every SteamCMD egg's `scripts.installation.script` (or each `startup_commands` entry).
   `bin/check` lists every egg that still differs.
3. `bin/check`, commit, push. The panel offers the update the next day, or import the file at once.

## Adding an egg

1. Take the upstream file (note its repo, path and commit in `UPSTREAM.md`), or export the egg from the
   panel.
2. Set `meta.update_url` to the egg's raw URL (see above); the next command needs it to be a string.
3. Convert it to YAML with the panel's own command, which only reads and writes the file:
   `php artisan p:egg:normalize egg-<game>.json` (in the panel container; writes `egg-<game>.yaml`).
4. Make the changes; for a SteamCMD egg: the master script, `GAME_BINARY`, and the startup check in front of
   each startup command.
5. Write `eggs/<game>/README.md` and add the egg to the table above.
6. `bin/check`, commit, push, then import it in the panel (Admin → Eggs → Import, from the URL or the file).

## Taking upstream changes

Upstream changes are not applied automatically: compare upstream's file at its latest commit with the commit
in `UPSTREAM.md`, carry over what you want, and update `UPSTREAM.md`. Upstream JSON can be converted with
`p:egg:normalize` to compare it with the YAML here.
