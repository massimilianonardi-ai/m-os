#!/bin/sh
set -eu
./m osarch update

command -v Xvfb >/dev/null 2>&1 || {
  echo 'INFRASTRUCTURE: Xvfb unavailable on runner' >&2
  exit 3
}
Xvfb :97 -screen 0 1280x900x24 > /tmp/m-srv-xvfb.log 2>&1 &
xvfb_pid=$!
cleanup() {
  ./m srv stop web-control >/dev/null 2>&1 || :
  ./m pkg provider default -u -- web-control >/dev/null 2>&1 || :
  kill "$xvfb_pid" 2>/dev/null || :
  wait "$xvfb_pid" 2>/dev/null || :
}
trap cleanup 0
trap 'exit 130' HUP INT TERM

export DISPLAY=:97
export WEB_CONTROL_HEADLESS=1
export ELECTRON_WEB_CONTROL_SOFTWARE_RENDERING=1
sleep 1
kill -0 "$xvfb_pid" || {
  cat /tmp/m-srv-xvfb.log >&2
  exit 3
}

# Real public negative paths before installing or selecting a provider.
./m srv stop web-control
if ./m srv start web-control >/tmp/m-srv-missing-default.log 2>&1
then
  echo 'FAIL: srv started without a configured service provider' >&2
  exit 1
fi
if ./m srv start invalid/name >/tmp/m-srv-invalid-name.log 2>&1
then
  echo 'FAIL: srv accepted an invalid service identity' >&2
  exit 1
fi
if [ "$(id -u)" -eq 0 ]
then
  echo 'INFRASTRUCTURE: non-admin host-system gate needs a non-root runner' >&2
  exit 3
fi
if ./m srv host system install web-control nobody >/tmp/m-srv-nonadmin.log 2>&1
then
  echo 'FAIL: non-admin host-system installation unexpectedly succeeded' >&2
  exit 1
fi

# Real catalog release and runtime dependency installation.
./m pkg install electron-web-control@v0.1.0
[ "$(./m pkg default electron-web-control)" = electron-web-control@v0.1.0 ]
./m pkg versions electron
./m pkg versions nodejs

# This published package supplies facility web-control 1 and
# the service part mapping to its real web-control-service command.
./m pkg provider default web-control electron-web-control
[ "$(./m pkg provider default web-control)" = electron-web-control ]
wait_web_control() {
  ready=0
  i=0
  while [ "$i" -lt 30 ]
  do
    if ./m web-control status > /tmp/m-srv-status.json 2>/tmp/m-srv-status.err
    then
      ready=1
      break
    fi
    sleep 1
    i=$((i + 1))
  done
  if [ "$ready" -ne 1 ]
  then
    echo 'FAIL: real srv process did not become responsive' >&2
    cat /tmp/m-srv-status.err >&2 || :
    ./m state-path user sys srv log || :
    exit 1
  fi
  [ -s /tmp/m-srv-status.json ]
}

./m srv start web-control
wait_web_control

# A second start must not replace an already running instance.
./m srv start web-control
wait_web_control

# A distinct caller cannot take over the process without explicit -f.
# Keep the nested shell alive after ./m, so its PID remains the caller.
/bin/sh -c './m srv stop web-control || exit; :'
wait_web_control
/bin/sh -c './m srv stop -f web-control || exit; :'

# Portable restart is a stop followed by a fresh start, not a new
# public srv restart command.
./m srv start web-control
wait_web_control

# Stop must use the recorded running instance, not re-resolve a
# now-unset provider default.
./m pkg provider default -u -- web-control
./m srv stop web-control
./m srv stop web-control
if ./m srv start web-control >/tmp/m-srv-unset-default.log 2>&1
then
  echo 'FAIL: srv started after the required provider default was removed' >&2
  exit 1
fi

# A restored genuine provider may launch again after the clean stop.
./m pkg provider default web-control electron-web-control
./m srv start web-control
wait_web_control
./m srv stop web-control
./m pkg provider default -u -- web-control
if ./m pkg provider default web-control >/dev/null 2>&1; then exit 1; fi
echo 'PASS: S1 real provider lifecycle, repeat start, caller ownership, force stop, restart and selector change'
echo 'PASS: S2 non-administrator host-system installation rejected; positive host supervision remains pending'
