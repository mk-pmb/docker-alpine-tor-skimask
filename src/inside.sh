#!/bin/sh
# -*- coding: utf-8, tab-width: 2 -*-


function inside_cli_init () {
  set -o pipefail -o errexit
  cd /app || return $?
  [ "$(whoami)" == root ] || return 4$(echo E: Not root >&2)
  [ -L /etc/localtime ] || install_basics
  exec ./src/stage2.sh
}


function install_basics () {
  source -- cfg.@local.rc
  echo D: 'Update package lists:'
  apk update
  local PKG='
    bash
    ca-certificates
    netcat-openbsd
    tzdata
    '
  echo D: 'Install basic packages:' $PKG
  apk add $PKG
  echo D: 'Set timezone:'
  export TZ=UTC
  echo $TZ > /etc/timezone
  ln -fsT /usr/share/zoneinfo/"$TZ" /etc/localtime
}










inside_cli_init "$@"; exit $?
