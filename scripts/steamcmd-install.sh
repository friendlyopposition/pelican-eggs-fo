#!/bin/bash
# steamcmd Base Installation Script
#
# Server Files: /mnt/server
# Image to install with is 'ghcr.io/parkervcp/installers:debian'
#
# MASTER COPY: every SteamCMD egg in this repo carries this exact script (bin/check verifies it).
# Edit it here, then paste it into each egg's scripts.installation.script.
#
##
#
# Variables
# STEAM_USER, STEAM_PASS, STEAM_AUTH - Steam user setup. If a user has 2fa enabled it will most likely fail due to timeout. Leave blank for anon install.
# WINDOWS_INSTALL - if it's a windows server you want to install set to 1
# SRCDS_APPID - steam app id found here - https://developer.valvesoftware.com/wiki/Dedicated_Servers_List
# SRCDS_BETAID - beta branch of a steam app. Leave blank to install normal branch
# SRCDS_BETAPASS - password for a beta branch should one be required during private or closed testing phases.. Leave blank for no password.
# INSTALL_FLAGS - Any additional SteamCMD  flags to pass during install.. Keep in mind that steamcmd auto update process in the docker image might overwrite or ignore these when it performs update on server boot.
# AUTO_UPDATE - Adding this variable to the egg allows disabling or enabling automated updates on boot. Boolean value. 0 to disable and 1 to enable.
# GAME_BINARY - the file the server cannot run without, relative to /mnt/server (e.g. 7DaysToDieServer.x86_64).
#               A hidden egg variable; the startup command checks for the same file.
#
# Changed from upstream (pelican-eggs/games-steamcmd): SteamCMD is retried, and the install is checked
# before it is called complete. Steam's anonymous login and app info requests time out now and then
# ("Waiting for user info...ERROR! (Timed out)"), and SteamCMD then exits without installing anything
# and without an error code.
#
##

if [[ -z "${GAME_BINARY}" ]]; then
    echo "ERROR: the egg has no GAME_BINARY variable (the file the server runs, e.g. 7DaysToDieServer.x86_64)."
    exit 1
fi
# Download attempts, and seconds to wait before the 2nd, 3rd, ... attempt.
STEAMCMD_ATTEMPTS=4
STEAMCMD_RETRY_DELAYS=(30 60 120)

# Install packages. Default packages below are not required if using our existing install image thus speeding up the install process.
#apt -y update
#apt -y --no-install-recommends install curl lib32gcc-s1 ca-certificates

## just in case someone removed the defaults.
if [[ "${STEAM_USER}" == "" ]] || [[ "${STEAM_PASS}" == "" ]]; then
    echo -e "steam user is not set.\n"
    echo -e "Using anonymous user.\n"
    STEAM_USER=anonymous
    STEAM_PASS=""
    STEAM_AUTH=""
else
    echo -e "user set to ${STEAM_USER}"
fi

## download and install steamcmd
cd /tmp || exit 1
mkdir -p /mnt/server/steamcmd
if ! curl -fsSL --retry 3 --retry-delay 10 -o steamcmd.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz; then
    echo "ERROR: could not download SteamCMD."
    exit 1
fi
tar -xzvf steamcmd.tar.gz -C /mnt/server/steamcmd
mkdir -p /mnt/server/steamapps # Fix steamcmd disk write error when this folder is missing
cd /mnt/server/steamcmd || exit 1

# SteamCMD fails otherwise for some reason, even running as root.
# This is changed at the end of the install process anyways.
chown -R root:root /mnt
export HOME=/mnt/server

## install game using steamcmd, until Steam's manifest says the app is fully installed
APP_MANIFEST="/mnt/server/steamapps/appmanifest_${SRCDS_APPID}.acf"
app_installed() {
    # StateFlags 4 = fully installed; the game's binary must be there too.
    [[ -f "${APP_MANIFEST}" ]] && grep -Eq '"StateFlags"[[:space:]]+"4"' "${APP_MANIFEST}" && [[ -f "/mnt/server/${GAME_BINARY}" ]]
}

for (( attempt = 1; attempt <= STEAMCMD_ATTEMPTS; attempt++ )); do
    echo "-----------------------------------------"
    echo "SteamCMD: installing app ${SRCDS_APPID}, attempt ${attempt} of ${STEAMCMD_ATTEMPTS}"
    echo "-----------------------------------------"
    # shellcheck disable=SC2086,SC2046 # word splitting of the flags is intended (upstream's command line)
    ./steamcmd.sh +force_install_dir /mnt/server +login ${STEAM_USER} ${STEAM_PASS} ${STEAM_AUTH} $( [[ "${WINDOWS_INSTALL}" == "1" ]] && printf %s '+@sSteamCmdForcePlatformType windows' ) +app_update ${SRCDS_APPID} $( [[ -z ${SRCDS_BETAID} ]] || printf %s "-beta ${SRCDS_BETAID}" ) $( [[ -z ${SRCDS_BETAPASS} ]] || printf %s "-betapassword ${SRCDS_BETAPASS}" ) ${INSTALL_FLAGS} validate +quit ## other flags may be needed depending on install. looking at you cs 1.6

    if app_installed; then
        break
    fi
    if (( attempt < STEAMCMD_ATTEMPTS )); then
        delay=${STEAMCMD_RETRY_DELAYS[attempt - 1]:-120}
        echo "SteamCMD did not finish installing app ${SRCDS_APPID}; retrying in ${delay}s."
        sleep "${delay}"
    fi
done

if ! app_installed; then
    echo "-----------------------------------------"
    echo "ERROR: app ${SRCDS_APPID} is not installed after ${STEAMCMD_ATTEMPTS} attempts"
    echo "(no fully installed ${APP_MANIFEST}, or no /mnt/server/${GAME_BINARY})."
    echo "Steam may be having problems: reinstall the server later."
    echo "-----------------------------------------"
    exit 1
fi

## set up 32 bit libraries
mkdir -p /mnt/server/.steam/sdk32
cp -v linux32/steamclient.so ../.steam/sdk32/steamclient.so

## set up 64 bit libraries
mkdir -p /mnt/server/.steam/sdk64
cp -v linux64/steamclient.so ../.steam/sdk64/steamclient.so

## add below your custom commands if needed

## install end
echo "-----------------------------------------"
echo "Installation completed..."
echo "-----------------------------------------"
