#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function stage2_cli_init () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  set -o pipefail -o errexit
  cd /app || return $?
  source -- cfg.@local.rc

  local APK_CACHE='/app/tmp.cache.apk'
  local TOR_USER='tor'
  local TOR_GROUP="$TOR_USER"

  [ -n "$USER" ] || local USER="$(whoami)"
  echo D: "Stage 2 running as user '$USER'."
  case "$USER" in
    root )
      create_proxy_user_group_home
      install_approved_torrc
      echo D: "Dropping privileges: Re-run as user '$TOR_USER'."
      exec su -s /bin/bash -l "$TOR_USER" -c 'exec /app/src/stage2.sh' ||
        return 4$(echo E: "The user stage failed, rv=$?" >&2)
      ;;
    "$TOR_USER" )
      cd || return 4$(echo E: "Cannot chdir to home directory, rv=$?" >&2)
      # exec bash -i
      verify_tor_config
      echo D: "We're ready to start the TOR daemon!"
      exec tor || return $?$(echo E: "Cannot start 'tor', rv=$?" >&2)
      ;;
    * ) exec bash -i;;
  esac
}


function fix_ownership () {
  chown $(stat -c %u:%g -- /app) -R -- "$APK_CACHE" || return $?$(
    echo E: $FUNCNAME: "Failed, rv=$?" >&2)
}


function fix_dir_ownership () {
  chown $(stat -c %u:%g -- "$APK_CACHE") -R -- "$APK_CACHE" || return $?$(
    echo E: $FUNCNAME: "Failed, rv=$?" >&2)
}


function create_proxy_user_group_home () {
  echo D: 'Create proxy user/group/home:'
  [ -d "$TOR_HOME" ] || return 4$(
    echo E: "TOR home dir should have been docker-mounted: $TOR_HOME" >&2)
  getent group "$TOR_GROUP" >/dev/null || addgroup -S "$TOR_GROUP" -g "$(
    stat -c %g -- "$TOR_HOME")" ||
    return 4$(echo E: "Failed to create group: $TOR_GROUP" >&2)
  getent passwd "$TOR_USER" >/dev/null ||
    adduser -S -h "$TOR_HOME" -G "$TOR_GROUP" -s /sbin/nologin -u "$(
    stat -c %u -- "$TOR_HOME")" "$TOR_USER" ||
    return 4$(echo E: "Failed to create user: $TOR_USER" >&2)
  ln -sfT .tor "$TOR_HOME"/dot-tor
  chown "$TOR_USER:$TOR_GROUP" -R -- "$TOR_HOME"
  chmod a=,ug+rx,u+w -- "$TOR_HOME"
}


function install_approved_torrc () {
  echo D: 'Detect available tor version(s)'
  local APK_BFN="$(apk list tor | sed -nre 's!^(tor-[0-9]\S+)\s.*$!\1!p')"
  APK_BFN="${APK_BFN//$'\n'/, }"
  local VAL="${APK_BFN//[a-z0-9.-]/}"
  [ -z "$VAL" ] || return 4$(
    echo E: "Unexpected characters '$VAL' in TOR version '$APK_BFN'" >&2)

  local TOR_VER="${APK_BFN#[a-z]*-}"
  VAL='s![0-9]+!<00000&> !g'
  VAL+=';s!<0*([0-9]{3})>!\1!g'
  VAL+=';s!<0*([1-9][0-9]*)>!\1!g'
  local PADDED="$(echo "$TOR_VER" | sed -re "$VAL")"
  PADDED="${PADDED/ /}"
  local VER_DIR="ver/${PADDED%% *}"
  PADDED="${PADDED// /}"
  VER_DIR+="/$PADDED"
  echo D: "Found '$TOR_VER', version subdirectory: '$VER_DIR'"
  # mkdir -p -- "$VER_DIR"

  local APK_FILE="$APK_CACHE/$APK_BFN.apk"
  local APK_DIR="${APK_FILE%/*}"
  echo D: 'Fetch the tor package:'
  mkdir -p -- "$APK_DIR" || true
  [ -s "$APK_FILE" ] || apk fetch --output "$APK_DIR" -- tor || return $?$(
    echo E: "Failed to download tor into '$APK'" >&2)
  echo -n D: 'Verify integrity: '
  apk verify -- "$APK_FILE" || return $(echo E: 'Failed to verify download.' >&2)

  echo D: 'Check config file compatibility:'
  local MANIF="$(apk manifest -- "$APK_FILE")"$'\n'
  local ALGO= HASH= FILE= SAMP=
  local RGX='^(sha1):([0-9a-f]+) +(\S+)$'
  while [ -n "$MANIF" ]; do
    VAL="${MANIF%%$'\n'*}"; MANIF="${MANIF:${#VAL}+1}"
    [ -n "$VAL" ] || continue
    [[ "$VAL" =~ $RGX ]] || return 4$(
      echo E: "Unsupported manifest line: '$VAL'" >&2)
    ALGO="${BASH_REMATCH[1]}"
    HASH="${BASH_REMATCH[2]}"
    FILE="${BASH_REMATCH[3]}"
    case "$FILE" in
      etc/tor/torrc.sample ) SAMP+=" ${FILE#etc/tor/}@$ALGO:$HASH";;
      usr/bin/tor* ) ;;
      usr/share/tor/geoip* ) ;;
      * ) echo E: "Unexpected file: $FILE" >&2; return 4;;
    esac
  done

  VAL="#%base%$SAMP"
  FILE="$(grep -lxFe "$VAL" -- ver/*/*/torrc.approved.txt || true)"
  echo D: "Matching config templates: ${FILE:-none}"
  if [ ! -f "$FILE" ]; then
    echo W: "Cannot find config version info for:$SAMP" >&2
    VAL="$APK_CACHE/$APK_BFN"
    echo -n D: "Extract into $APK_CACHE/ so you can debug it: "
    mkdir -p -- "$VAL" || true
    apk extract --destination "$VAL" -- "$APK_FILE" || return 4$(
      echo E: 'Failed to extract APK.' >&2)
    fix_cachedir_ownership
    echo E: 'Flinching: Cannot decide expected config file syntax.' >&2
  fi

  echo D: "Install the config file:"
  mkdir -p /etc/tor
  SED='' # By default, copy template verbatim

  # Maybe add proxy?
  local PRX="$https_proxy"
  PRX="${PRX%/}"
  PRX="${PRX#http://}"
  [ -z "$PRX" ] || PRX='s|^# *(HTTPS?Proxy\s+)\S+|\1'"$PRX|i"

  sed -re "$SED" -- "$FILE" | sed -re "$PRX" >/etc/tor/torrc
  echo D: 'Config file was installed. Now we install tor.'
  apk add tor
}


function verify_tor_config () {
  echo D: 'Verify our config file is valid:'
  tor --verify-config

  echo D: 'Verify our config file is parsed as we expect it to be:'
  local VAL='s!\s+! !g'
  VAL+='; s!^ExitRelay !&!ip'
  VAL+='; s!^ORPort !&!ip'
  VAL="$(tor --dump-config full | sed -nre "$VAL")"
  [ "$VAL" == "ExitRelay 0" ] || return 4$(
    echo E: "Unexpected config summary: ${VAL//$'\n'/¶ }" >&2)
}












stage2_cli_init "$@"; exit $?
