#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function dkstart () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local SELFPATH="$(readlink -m -- "$BASH_SOURCE"/..)"
  cd -- "$SELFPATH" || return $?
  local DK_CTNR='skimask'
  if docker container port "$DK_CTNR" >/dev/null; then
    echo D: 'Container exists. Start!'
    docker container start "$DK_CTNR" || return $?
    dklogs || return $?
    return 0
  fi

  echo D: 'Container missing. Create!'
  local LIST=()
  local VAL=
  local DK_RUN=(
    run
    --name="$DK_CTNR"
    --hostname="$DK_CTNR"
    --restart=no
    # --interactive --tty
    --detach
    --workdir='/app'
    # --add-host=host.docker.internal:host-gateway
    --env="TZ=$(cat -- /etc/timezone)"
    --volume="$PWD":/app:ro
    )

  local TOR_HOME_HOST='tor-home.@local'
  mkdir --parents -- "$TOR_HOME_HOST" || return $?
  local TOR_HOME_INSIDE='/home/tor'
  DK_RUN+=(
    --env="TOR_HOME=$TOR_HOME_INSIDE"
    --volume="$PWD/$TOR_HOME_HOST:$TOR_HOME_INSIDE:rw"
    )

  local RW_DIRS=(
    tmp.cache.apk
    )
  mkdir --parents -- "${RW_DIRS[@]}" || return $?
  for VAL in "${RW_DIRS[@]}"; do
    DK_RUN+=( --volume="$PWD/$VAL:/app/$VAL:rw" )
  done

  # TCP port forwarding
  VAL='9050-9051'
  DK_RUN+=( --publish "127.0.0.1:$VAL:$VAL/tcp" )

  DK_RUN+=(
    alpine:latest
    /app/src/inside.sh
    )
  docker "${DK_RUN[@]}" || return $?
  dklogs || return $?
}


function dklogs () {
  docker logs --follow "$DK_CTNR" | sed -re '/ Bootstrapped 100%/a'$(
    )'\# ^-- Looking good. You may press Ctrl-c to stop watching the logs.'
}


dkstart "$@"; exit $?
