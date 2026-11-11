#!/usr/bin/env python3
"""Checks every egg under eggs/: it parses, is in Pelican's current format, points its update_url at its own
file in this repo, carries no secrets, and (for SteamCMD eggs) uses the master install script and startup check."""

import re
import subprocess
import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parent.parent
RAW_BASE = "https://raw.githubusercontent.com/friendlyopposition/pelican-eggs-fo/main/"
EXPORT_VERSION = "PLCN_v3"
SECRET_NAMES = re.compile(r"PASS|TOKEN|SECRET|KEY|AUTH", re.IGNORECASE)

master_script = (REPO / "scripts/steamcmd-install.sh").read_text()
startup_check = (REPO / "scripts/startup-check.txt").read_text().rstrip("\n") + " "
failures = []


def fail(egg: Path, message: str) -> None:
    failures.append(f"{egg.relative_to(REPO)}: {message}")


eggs = sorted(REPO.glob("eggs/*/egg-*.yaml"))
if not eggs:
    print("FAIL no eggs found under eggs/*/egg-*.yaml")
    sys.exit(1)

for path in eggs:
    try:
        egg = yaml.safe_load(path.read_text())
    except yaml.YAMLError as e:
        fail(path, f"not valid YAML: {e}")
        continue

    rel = path.relative_to(REPO).as_posix()
    if egg.get("meta", {}).get("version") != EXPORT_VERSION:
        fail(path, f"meta.version is {egg.get('meta', {}).get('version')!r}, want {EXPORT_VERSION} (run p:egg:normalize)")
    if egg.get("meta", {}).get("update_url") != RAW_BASE + rel:
        fail(path, f"meta.update_url must be {RAW_BASE + rel}")
    for key in ("uuid", "name", "startup_commands", "scripts", "variables"):
        if not egg.get(key):
            fail(path, f"missing {key}")

    variables = {v["env_variable"]: v for v in egg.get("variables") or []}
    for name, var in variables.items():
        if SECRET_NAMES.search(name) and str(var.get("default_value") or "") != "":
            fail(path, f"variable {name} has a default value: secrets do not belong in an egg")

    script = egg.get("scripts", {}).get("installation", {}).get("script", "")
    syntax = subprocess.run(["bash", "-n"], input=script, text=True, capture_output=True)
    if syntax.returncode != 0:
        fail(path, f"install script has bash syntax errors: {syntax.stderr.strip()}")

    if "steamcmd" in (egg.get("tags") or []):
        if script != master_script:
            fail(path, "install script differs from scripts/steamcmd-install.sh: copy the master script into the egg")
        binary = variables.get("GAME_BINARY")
        if not binary:
            fail(path, "no GAME_BINARY variable")
        else:
            if not str(binary.get("default_value") or ""):
                fail(path, "GAME_BINARY has no default value")
            if binary.get("user_viewable") or binary.get("user_editable"):
                fail(path, "GAME_BINARY must be hidden from clients and not editable")
        for name, command in (egg.get("startup_commands") or {}).items():
            if not command.startswith(startup_check):
                fail(path, f"startup command {name!r} does not start with scripts/startup-check.txt")

    if not any(f.startswith(f"{path.relative_to(REPO)}:") for f in failures):
        print(f"ok   {rel}")

for f in failures:
    print(f"FAIL {f}")
sys.exit(1 if failures else 0)
