#!/bin/sh
# Real Chromium typed environment applied by an installed consumer launcher.
set -eu

repo_root=$(CDPATH= cd "$(dirname "$0")/../.." && pwd) || exit 1
CDPATH= cd "$repo_root" || exit 1
concrete=chromium@1697793
consumer=pwc-web-control@v0.1.0
root="$PWD/pkg/$concrete/root"
consumer_pid=
xvfb_pid=
work=

cleanup()
{
  if [ -n "$consumer_pid" ]
  then
    kill -TERM -- "-$consumer_pid" >/dev/null 2>&1 || kill -TERM "$consumer_pid" >/dev/null 2>&1 || :
    wait "$consumer_pid" 2>/dev/null || :
    consumer_pid=
  fi
  if [ -n "$xvfb_pid" ]; then kill "$xvfb_pid" >/dev/null 2>&1 || :; wait "$xvfb_pid" 2>/dev/null || :; fi
  ./m pkg uninstall "$consumer" "$concrete" >/dev/null 2>&1 || :
  if [ -n "$work" ]; then rm -rf "$work"; fi
}
trap cleanup 0
trap 'exit 130' HUP INT TERM

./m osarch update
./m pkg install "$concrete"
[ -d "$root" ] && [ ! -L "$root" ]
[ -f "$root/chrome_sandbox" ] && [ ! -L "$root/chrome_sandbox" ]
./m pkg install "$consumer"

command -v Xvfb >/dev/null 2>&1 || { echo 'FAIL: Xvfb is required' >&2; exit 1; }
command -v setsid >/dev/null 2>&1 || { echo 'FAIL: setsid is required for isolated consumer teardown' >&2; exit 1; }
work=$(mktemp -d)
Xvfb :97 -screen 0 1024x768x24 >"$work/xvfb.log" 2>&1 &
xvfb_pid=$!
i=0
while [ "$i" -lt 20 ] && ! kill -0 "$xvfb_pid" >/dev/null 2>&1; do sleep 1; i=$((i + 1)); done
DISPLAY=:97 WEB_CONTROL_HEADLESS=1 setsid ./m web-control-service >"$work/consumer.log" 2>&1 &
consumer_pid=$!

# Wait for the real service and its Chromium process, then inspect the child's
# environment to prove the binding-free package launcher supplied root-path.
ready=0
i=0
while [ "$i" -lt 45 ]
do
  if ./m pwc-web-control status >"$work/status" 2>"$work/status.err"; then ready=1; break; fi
  if ! kill -0 "$consumer_pid" >/dev/null 2>&1; then cat "$work/consumer.log" >&2; exit 1; fi
  sleep 1
  i=$((i + 1))
done
[ "$ready" -eq 1 ] || { cat "$work/status.err" >&2; exit 1; }
expected="$root/chrome_sandbox"
browser_pid=
for environ in /proc/[0-9]*/environ
do
  [ -r "$environ" ] || continue
  if tr '\000' '\n' <"$environ" 2>/dev/null | grep -F "CHROME_DEVEL_SANDBOX=$expected" >/dev/null
  then
    candidate=${environ#/proc/}
    candidate=${candidate%/environ}
    executable=$(command -p readlink "/proc/$candidate/exe" 2>/dev/null || :)
    case "$executable" in
      */chrome | */chromium | */chrome-headless-shell)
        browser_pid=$candidate
        break
        ;;
    esac
  fi
done
[ -n "$browser_pid" ] || { echo 'FAIL: Chromium child did not inherit selected root-path environment' >&2; exit 1; }
./m pwc-web-control status >"$work/status"
grep -F '"browserRunning":true' "$work/status" >/dev/null

# PWC handles SIGTERM by closing the Playwright context, which terminates the
# owned browser before test package cleanup. The isolated session bounds signals.
kill -TERM "$consumer_pid"
wait "$consumer_pid"
consumer_pid=
i=0
while [ "$i" -lt 15 ] && [ -e "/proc/$browser_pid" ]; do sleep 1; i=$((i + 1)); done
if [ -e "/proc/$browser_pid" ]
then
  echo 'FAIL: Chromium child survived orderly PWC shutdown' >&2
  exit 1
fi
kill "$xvfb_pid" >/dev/null 2>&1 || :
wait "$xvfb_pid" 2>/dev/null || :
xvfb_pid=
printf '%s\n' 'PASS: P3 genuine consumer provider resolution, Chromium root-path env, command and orderly shutdown'
