#!/bin/sh
# Isolated P3 selector-boundary regression: real public m commands and a
# controlled installed-provider metadata fixture, not a released artifact.
set -eu

./m osarch update
provider=ci-p3-pinned-provider
concrete="$provider@v1"
store="pkg/$concrete"
[ ! -e "$store" ] && [ ! -L "$store" ] || exit 1
if ./m pkg provider default web-control >/dev/null 2>&1; then exit 2; fi

cleanup()
{
  ./m pkg provider default -u -- web-control >/dev/null 2>&1 || :
  command -p -- rm -f -- bin/ext/web-control >/dev/null 2>&1 || :
  command -p -- rm -rf -- "$store"
}
trap cleanup 0
trap 'exit 3' HUP INT TERM

command -p -- mkdir -p -- "$store/root/bin" "$store/facility-cmd/web-control" || exit 4
printf 'web-control 1\n' > "$store/facility"
printf '#!/bin/sh\nprintf "fixture-pinned\\n"\n' > "$store/root/bin/web-control"
command -p -- chmod +x "$store/root/bin/web-control" || exit 14
command -p -- ln -s ../../root/bin/web-control "$store/facility-cmd/web-control/web-control" || exit 15

./m pkg provider default web-control "$concrete" || exit 5
[ "$(./m pkg provider default web-control)" = "$concrete" ] || exit 6
[ "$(./m pkg requirement resolve web-control '=1')" = "$concrete" ] || exit 7
[ -L bin/ext/web-control ] || exit 16
[ "$(command -p -- readlink bin/ext/web-control)" = "../../pkg/$concrete/facility-cmd/web-control/web-control" ] || exit 17

# Unversioned selection still requires the package-class default. The exact
# concrete above must NOT require that mutable default.
./m pkg provider default web-control "$provider" || exit 8
set +e
./m pkg requirement resolve web-control '=1' >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 1 ] || exit 9

./m pkg provider default web-control "$concrete" || exit 10
[ "$(./m pkg requirement resolve web-control '=1')" = "$concrete" ] || exit 11
./m pkg provider default -u -- web-control || exit 12
[ -d "$store" ] && [ ! -L "$store" ] || exit 13

echo 'PASS: P3 exact all-stream facility selector bypasses package default; unversioned selector still follows it'
