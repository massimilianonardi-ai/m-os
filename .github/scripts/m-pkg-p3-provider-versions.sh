#!/bin/sh
# Genuine public provider-version selection and compatibility regression.
set -eu

repo_root=$(CDPATH= cd "$(dirname "$0")/../.." && pwd) || exit 1
CDPATH= cd "$repo_root" || exit 1

umask 077
tmp_base=${TMPDIR:-/tmp}
case "$tmp_base" in
  /*) : ;;
  *) tmp_base=./$tmp_base ;;
esac
attempt=0
work=
while [ "$attempt" -lt 10 ]
do
  work=$tmp_base/m-pkg-p3-provider-versions-$$-$attempt
  if (umask 077; mkdir -m 700 "$work") 2>/dev/null
  then
    break
  fi
  work=
  attempt=$((attempt + 1))
done
[ -n "$work" ] || exit 2

cleanup()
{
  ./m pkg provider default -u -- web-control >/dev/null 2>&1 || :
  ./m pkg default -u -- electron-web-control >/dev/null 2>&1 || :
  ./m pkg uninstall electron-web-control@v0.1.0 electron-web-control@v0.1.4 >/dev/null 2>&1 || :
  rm -rf "$work/catalog"
  rm -f "$work/catalog-path" "$work/versions" "$work/incompatible" || :
  rmdir "$work" 2>/dev/null || :
}
trap cleanup 0
trap 'exit 130' HUP INT TERM

./m osarch update || exit 3
catalog="$work/catalog"
git clone --quiet -- https://github.com/massimilianonardi-ai/pkg-catalog.git "$catalog" || exit 4
git -C "$catalog" checkout --quiet 4083aa19c4362f00ec62428a631edfa493faf7f0 || exit 5
conf=$(./m state-path system sys pkg conf) || exit 6
command -p mkdir -p "$conf" || exit 7
printf '%s\n' "$catalog" > "$conf/catalog" || exit 8

# These are genuine published releases of one provider package. Their
# metadata deliberately declares different exact compatibility levels.
./m pkg install electron-web-control@v0.1.0 || exit 9
./m pkg install electron-web-control@v0.1.4 || exit 10
[ "$(./m pkg default electron-web-control)" = electron-web-control@v0.1.4 ] || {
  echo 'FAIL: latest installed concrete was not selected as the package default' >&2
  exit 12
}
[ -d pkg/electron-web-control@v0.1.0 ] && [ ! -L pkg/electron-web-control@v0.1.0 ] || exit 13
[ -d pkg/electron-web-control@v0.1.4 ] && [ ! -L pkg/electron-web-control@v0.1.4 ] || exit 14
[ "$(command -p cat pkg/electron-web-control@v0.1.0/facility)" = 'web-control 1' ] || exit 15
[ "$(command -p cat pkg/electron-web-control@v0.1.4/facility)" = 'web-control 2' ] || exit 16

./m pkg versions electron-web-control > "$work/versions" || exit 17
grep -F 'electron-web-control@v0.1.0' "$work/versions" >/dev/null || exit 18
grep -F 'electron-web-control@v0.1.4' "$work/versions" >/dev/null || exit 19

./m pkg provider default web-control electron-web-control@v0.1.0 || exit 20
[ "$(./m pkg requirement resolve web-control '=1')" = electron-web-control@v0.1.0 ] || exit 21
if ./m pkg requirement resolve web-control '=2' > "$work/incompatible" 2>&1
then
  echo 'FAIL: compatibility 1 provider satisfied compatibility 2' >&2
  exit 22
fi
[ -L bin/ext/web-control ] || exit 23
[ "$(command -p readlink bin/ext/web-control)" = '../../pkg/electron-web-control@v0.1.0/facility-cmd/web-control/web-control' ] || exit 24

if ./m pkg uninstall electron-web-control@v0.1.0 > "$work/incompatible" 2>&1
then
  echo 'FAIL: selected concrete provider was uninstalled' >&2
  exit 25
fi
[ -d pkg/electron-web-control@v0.1.0 ] && [ ! -L pkg/electron-web-control@v0.1.0 ] || exit 26
[ "$(./m pkg provider default web-control)" = electron-web-control@v0.1.0 ] || exit 38
[ -L bin/ext/web-control ] || exit 39
[ "$(command -p readlink bin/ext/web-control)" = '../../pkg/electron-web-control@v0.1.0/facility-cmd/web-control/web-control' ] || exit 40

./m pkg provider default web-control electron-web-control@v0.1.4 || exit 27
[ "$(./m pkg requirement resolve web-control '=2')" = electron-web-control@v0.1.4 ] || exit 28
if ./m pkg requirement resolve web-control '=1' > "$work/incompatible" 2>&1
then
  echo 'FAIL: compatibility 2 provider satisfied compatibility 1' >&2
  exit 29
fi
[ "$(command -p readlink bin/ext/web-control)" = '../../pkg/electron-web-control@v0.1.4/facility-cmd/web-control/web-control' ] || exit 30

# An unversioned selector follows the package-class default as it moves
# between two installed concrete releases, while exact selectors remain pinned.
./m pkg provider default -u -- web-control || exit 41
./m pkg default electron-web-control@v0.1.0 || exit 42
./m pkg provider default web-control electron-web-control || exit 43
[ "$(./m pkg requirement resolve web-control '=1')" = electron-web-control@v0.1.0 ] || exit 44
./m pkg default -u -- electron-web-control || exit 45
./m pkg default electron-web-control@v0.1.4 || exit 46
[ "$(./m pkg requirement resolve web-control '=2')" = electron-web-control@v0.1.4 ] || exit 47
if ./m pkg requirement resolve web-control '=1' > "$work/incompatible" 2>&1
then
  echo 'FAIL: unversioned selector ignored changed package default compatibility' >&2
  exit 48
fi
[ "$(command -p readlink bin/ext/web-control)" = '../../pkg/electron-web-control@v0.1.4/facility-cmd/web-control/web-control' ] || exit 49
./m pkg provider default web-control electron-web-control@v0.1.4 || exit 50

./m pkg uninstall electron-web-control@v0.1.0 || exit 31
[ ! -e pkg/electron-web-control@v0.1.0 ] && [ ! -L pkg/electron-web-control@v0.1.0 ] || exit 32
[ -d pkg/electron-web-control@v0.1.4 ] && [ ! -L pkg/electron-web-control@v0.1.4 ] || exit 33
./m pkg provider default -u -- web-control || exit 34
[ ! -e bin/ext/web-control ] && [ ! -L bin/ext/web-control ] || exit 35
./m pkg uninstall electron-web-control@v0.1.4 || exit 36
[ ! -e pkg/electron-web-control@v0.1.4 ] && [ ! -L pkg/electron-web-control@v0.1.4 ] || exit 37
if ./m pkg default electron-web-control >/dev/null 2>&1; then exit 51; fi
if ./m pkg versions electron-web-control >/dev/null 2>&1; then exit 52; fi

echo 'PASS: P3 genuine provider multiple-version selection, tracking, exact compatibility, projection and protected removal'
