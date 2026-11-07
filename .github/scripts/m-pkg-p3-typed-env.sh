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
chromium_installed=0
consumer_installed=0
provider_default_owned=0

cleanup()
{
  if [ -n "$controller_pid" ]
  then
    kill -TERM "$controller_pid" >/dev/null 2>&1 || :
  elif [ -n "$consumer_pid" ]
  then
    kill -TERM -- "-$consumer_pid" >/dev/null 2>&1 || kill -TERM "$consumer_pid" >/dev/null 2>&1 || :
  fi
  if [ -n "$consumer_pid" ]; then wait "$consumer_pid" 2>/dev/null || :; consumer_pid=; fi
  if [ "$provider_default_owned" -eq 1 ]; then
    cleanup_provider_default=$(./m pkg provider default web-control 2>/dev/null) || cleanup_provider_default=
    case "$cleanup_provider_default" in
      pwc-web-control@v0.1.0)
        ./m pkg provider default -u -- web-control >/dev/null 2>&1 || :
        ;;
    esac
  fi
  if [ "$consumer_installed" -eq 1 ]; then
    ./m pkg uninstall "$consumer" >/dev/null 2>&1 || :
  fi
  if [ "$chromium_installed" -eq 1 ]; then
    ./m pkg uninstall "$concrete" >/dev/null 2>&1 || :
  fi
  if [ -n "$work" ]; then rm -rf "$work"; fi
}
trap cleanup 0
trap 'exit 130' HUP INT TERM

./m osarch update
[ ! -e "pkg/$concrete" ] && [ ! -L "pkg/$concrete" ] || { echo 'FAIL: Chromium concrete already exists; refusing destructive test cleanup' >&2; exit 1; }
[ ! -e "pkg/chromium" ] && [ ! -L "pkg/chromium" ] || { echo 'FAIL: Chromium package default already exists; refusing destructive test cleanup' >&2; exit 1; }
[ ! -e "pkg/$consumer" ] && [ ! -L "pkg/$consumer" ] || { echo 'FAIL: consumer concrete already exists; refusing destructive test cleanup' >&2; exit 1; }
[ ! -e bin/ext/chromium ] && [ ! -L bin/ext/chromium ] || { echo 'FAIL: Chromium command projection already exists; refusing destructive test cleanup' >&2; exit 1; }
if ./m pkg provider default web-control >/dev/null 2>&1
then
  echo 'FAIL: web-control already has a provider default; refusing destructive test cleanup' >&2
  exit 1
fi
[ ! -e bin/ext/web-control ] && [ ! -L bin/ext/web-control ] || { echo 'FAIL: web-control command projection already exists; refusing destructive test cleanup' >&2; exit 1; }
consumer_conf=$(./m state-path system pkg pwc-web-control conf) || exit 1
[ ! -e "$consumer_conf/binding/browser" ] && [ ! -L "$consumer_conf/binding/browser" ] || { echo 'FAIL: consumer browser binding already exists; refusing a non-isolated provider test' >&2; exit 1; }
command -v setsid >/dev/null 2>&1 || { echo 'FAIL: setsid is required for isolated consumer teardown' >&2; exit 1; }
command -v strace >/dev/null 2>&1 || { echo 'FAIL: strace is required to inspect the real child exec environment' >&2; exit 1; }
./m pkg install "$concrete"
chromium_installed=1
[ -d "$root" ] && [ ! -L "$root" ]
[ -f "$root/chrome_sandbox" ] && [ ! -L "$root/chrome_sandbox" ]
./m pkg install "$consumer"
consumer_installed=1
provider_default_owned=1
./m pkg provider default web-control pwc-web-control@v0.1.0

work=$(mktemp -d)
WEB_CONTROL_HEADLESS=1 WEB_CONTROL_BROWSER_ARGS='["--no-sandbox"]' \
  setsid strace -f -v -s 8192 -e trace=execve -o "$work/execve.log" \
  ./m web-control-service >"$work/consumer.log" 2>&1 &
consumer_pid=$!
controller_path="$PWD/pkg/$consumer/root/src/controller.mjs"
i=0
while [ "$i" -lt 20 ] && [ -z "$controller_pid" ]
do
  controller_pid=$(ps -eo pid=,args= | awk -v needle="$controller_path" '
    {
      executable = $2
      sub(/^.*\//, "", executable)
      if (executable == "node" && index($0, needle) > 0) {
        print $1
        exit
      }
    }
  ')
  [ -n "$controller_pid" ] || sleep 1
  i=$((i + 1))
done
[ -n "$controller_pid" ] || {
  cat "$work/consumer.log" >&2
  ps -eo pid=,args= | awk -v needle="$controller_path" 'index($0, needle) > 0 || /web-control-service/ { print }' >&2
  echo 'FAIL: PWC controller process was not identified' >&2
  exit 1
}

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

# Status must not create an absent browser. A page-required operation does.
./m web-control page new >"$work/page-new"
browser_ready=0
i=0
while [ "$i" -lt 15 ]
do
  if ./m web-control status >"$work/status" 2>"$work/status.err" && \
     grep -F '"browserRunning":true' "$work/status" >/dev/null
  then
    browser_ready=1
    break
  fi
  sleep 1
  i=$((i + 1))
done
[ "$browser_ready" -eq 1 ] || {
  cat "$work/status" "$work/status.err" "$work/page-new" "$work/consumer.log" >&2
  echo 'FAIL: page creation did not start the Chromium browser runtime' >&2
  exit 1
}

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
