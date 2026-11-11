#!/bin/bash
# Runs scripts/startup-check.txt the way the yolks steamcmd image's entrypoint runs an egg's startup command:
#   MODIFIED_STARTUP=$(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g'); eval ${MODIFIED_STARTUP}
# (https://github.com/pelican-eggs/yolks, steamcmd/entrypoint.sh).
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
check="$(cat "${repo_dir}/scripts/startup-check.txt")"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
failures=0

# The entrypoint's two lines, unchanged (unquoted on purpose).
cat > "${work}/entrypoint.sh" <<'EOF'
#!/bin/bash
cd "$1" || exit 2
# shellcheck disable=SC2086
MODIFIED_STARTUP=$(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')
# shellcheck disable=SC2086
eval ${MODIFIED_STARTUP}
EOF

# expect NAME DIR EXPECTED_EXIT EXPECTED_OUTPUT_PATTERN
expect() {
    local name=$1 dir=$2 want_exit=$3 pattern=$4 got_exit=0 out
    out=$(env -i PATH=/usr/bin:/bin GAME_BINARY=Game.x86_64 STARTUP="${check} echo GAME STARTED" \
        bash "${work}/entrypoint.sh" "${dir}" 2>&1) || got_exit=$?
    if [[ "${got_exit}" == "${want_exit}" ]] && grep -q -- "${pattern}" <<< "${out}"; then
        echo "ok   ${name}"
    else
        echo "FAIL ${name}: exit ${got_exit} (want ${want_exit}), output:"
        while IFS= read -r line; do printf '     | %s\n' "${line}"; done <<< "${out}"
        failures=$((failures + 1))
    fi
}

mkdir -p "${work}/empty" "${work}/installed"
touch "${work}/installed/Game.x86_64"

expect "game files missing: clear error, server stops" "${work}/empty" 1 "ERROR: The game files are missing"
expect "game files present: the game starts" "${work}/installed" 0 "GAME STARTED"

exit $(( failures > 0 ))
