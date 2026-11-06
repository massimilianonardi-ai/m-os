#!/bin/sh
# Real Chromium typed environment applied by an installed consumer launcher.
set -eu

repo_root=$(CDPATH= cd "$(dirname "$0")/../.." && pwd) || exit 1
CDPATH= cd "$repo_root" || exit 1
concrete=chromium@1697793
consumer=pwc-web-control@v0.1.0
root="$PWD/pkg/$concrete/root"
consumer_pid=
controller_pid=
work=

cleanup()
{
  if [ -n "$controller_pid" ]; then kill -TERM "$controller_pid" >/dev/null 2>&1 || :; fi
  if [ -n "$consumer_pid" ]; then wait "$consumer_pid" 2>/dev/null || :; consumer_pid=; fi
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

command -v setsid >/dev/null 2>&1 || { echo 'FAIL: setsid is required for isolated consumer teardown' >&2; exit 1; }
command -v strace >/dev/null 2>&1 || { echo 'FAIL: strace is required to inspect the real child exec environment' >&2; exit 1; }
work=$(mktemp -d)
WEB_CONTROL_HEADLESS=1 WEB_CONTROL_BROWSER_ARGS='["--no-sandbox"]' \
  setsid strace -f -v -s 8192 -e trace=execve -o "$work/execve.log" \
  ./m web-control-service >"$work/consumer.log" 2>&1 &
consumer_pid=$!
controller_path="$PWD/pkg/$consumer/root/src/controller.mjs"
i=0
while [ "$i" -lt 20 ] && [ -z "$controller_pid" ]
do
  controller_pid=$(ps -eo pid=,args= | awk -v needle="$controller_path" '$2 == "node" && index($0, needle) > 0 { print $1; exit }')
  [ -n "$controller_pid" ] || sleep 1
  i=$((i + 1))
done
[ -n "$controller_pid" ] || { cat "$work/consumer.log" >&2; echo 'FAIL: PWC controller did not start' >&2; exit 1; }

ready=0
i=0
while [ "$i" -lt 45 ]
do
  if ./m pwc-web-control status >"$work/status" 2>"$work/status.err"; then ready=1; break; fi
  if ! kill -0 "$controller_pid" >/dev/null 2>&1; then cat "$work/consumer.log" >&2; exit 1; fi
  sleep 1
  i=$((i + 1))
done
[ "$ready" -eq 1 ] || { cat "$work/status.err" >&2; exit 1; }
grep -F '"browserRunning":true' "$work/status" >/dev/null

expected="$root/chrome_sandbox"
awk -v expected="CHROME_DEVEL_SANDBOX=$expected" '
  /execve\(/ && (index($0, "/chrome\"") || index($0, "/chromium\"") || index($0, "/chrome-headless-shell\"")) && index($0, expected) { found=1 }
  END { exit !found }
' "$work/execve.log" || {
  echo 'FAIL: real Chromium exec did not receive selected root-path environment' >&2
  cat "$work/execve.log" >&2
  exit 1
}

# PWC handles SIGTERM by closing its Playwright context, which terminates the
# owned browser. Signal the controller only; strace observes and waits for it.
kill -TERM "$controller_pid"
wait "$consumer_pid"
consumer_pid=
controller_pid=
if ./m pwc-web-control status >"$work/status-after-stop" 2>&1
then
  echo 'FAIL: PWC remained available after its controller received SIGTERM' >&2
  exit 1
fi
printf '%s\n' 'PASS: P3 genuine consumer provider resolution, Chromium root-path env, command and orderly shutdown'
