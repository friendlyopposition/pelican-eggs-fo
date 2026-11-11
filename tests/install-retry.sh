#!/bin/bash
# Runs scripts/steamcmd-install.sh against a fake SteamCMD that times out a given number of times, the way
# Steam's anonymous login does ("Waiting for user info...ERROR! (Timed out)", exit code 0).
# The script's /mnt and /tmp paths are pointed at a temporary folder; curl, tar, chown and sleep are fakes.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${repo_dir}/scripts/steamcmd-install.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
failures=0

mkdir -p "${work}/bin"
cat > "${work}/bin/curl" <<'EOF'
#!/bin/bash
for a; do [[ "${prev:-}" == -o ]] && : > "$a"; prev=$a; done
EOF
cat > "${work}/bin/sleep" <<'EOF'
#!/bin/bash
echo "[sleep $1]"
EOF
printf '#!/bin/bash\n:\n' > "${work}/bin/chown"
# "Extracting" SteamCMD writes a fake steamcmd.sh. It fails FAIL_RUNS times, then installs the app,
# writing the manifest unless NO_MANIFEST and the binary unless NO_BINARY.
cat > "${work}/bin/tar" <<'EOF'
#!/bin/bash
d=${*: -1}
cat > "$d/steamcmd.sh" <<'S'
#!/bin/bash
n=$(cat "$ROOT/runs" 2>/dev/null || echo 0); echo $((n + 1)) > "$ROOT/runs"
if (( n < FAIL_RUNS )); then echo "Waiting for user info...ERROR! (Timed out)"; exit 0; fi
[[ -n "${NO_MANIFEST:-}" ]] || printf '"AppState"\n{\n\t"StateFlags"\t\t"4"\n}\n' > "$ROOT/mnt/server/steamapps/appmanifest_${SRCDS_APPID}.acf"
[[ -n "${NO_BINARY:-}" ]] || touch "$ROOT/mnt/server/${GAME_BINARY}"
echo "Success! App '${SRCDS_APPID}' fully installed."
S
chmod +x "$d/steamcmd.sh"
mkdir -p "$d/linux32" "$d/linux64"
touch "$d/linux32/steamclient.so" "$d/linux64/steamclient.so"
EOF
chmod +x "${work}"/bin/*

# scenario NAME EXPECTED_EXIT EXPECTED_RUNS [VAR=value ...]
scenario() {
    local name=$1 want_exit=$2 want_runs=$3
    shift 3
    local root="${work}/${name// /_}"
    mkdir -p "${root}/tmp"
    sed -e "s#/mnt#${root}/mnt#g" -e "s#^cd /tmp #cd ${root}/tmp #" "${script}" > "${root}/install.sh"

    local got_exit=0
    env -i PATH="${work}/bin:/usr/bin:/bin" ROOT="${root}" SRCDS_APPID=294420 GAME_BINARY=Game.x86_64 FAIL_RUNS=0 "$@" \
        bash "${root}/install.sh" > "${root}/out.txt" 2>&1 || got_exit=$?
    local got_runs
    got_runs=$(cat "${root}/runs" 2>/dev/null || echo 0)

    if [[ "${got_exit}" == "${want_exit}" && "${got_runs}" == "${want_runs}" ]]; then
        echo "ok   ${name} (exit ${got_exit}, ${got_runs} SteamCMD runs)"
    else
        echo "FAIL ${name}: exit ${got_exit} (want ${want_exit}), ${got_runs} SteamCMD runs (want ${want_runs})"
        sed 's/^/     | /' "${root}/out.txt"
        failures=$((failures + 1))
    fi
}

scenario "installs first time" 0 1
scenario "retries after two timeouts" 0 3 FAIL_RUNS=2
scenario "gives up after four attempts" 1 4 FAIL_RUNS=9
scenario "manifest but no binary is not installed" 1 4 NO_BINARY=1
scenario "binary but no manifest is not installed" 1 4 NO_MANIFEST=1
scenario "egg without GAME_BINARY stops at once" 1 0 GAME_BINARY=

if grep -q 'Installation completed' "${work}/gives_up_after_four_attempts/out.txt"; then
    echo "FAIL a failed install still prints 'Installation completed'"
    failures=$((failures + 1))
fi
if ! grep -q 'retrying in 30s' "${work}/retries_after_two_timeouts/out.txt" \
    || ! grep -q 'retrying in 60s' "${work}/retries_after_two_timeouts/out.txt"; then
    echo "FAIL the retry delays are not 30s then 60s"
    failures=$((failures + 1))
fi

exit $(( failures > 0 ))
