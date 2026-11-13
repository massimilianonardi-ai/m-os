#!/bin/sh
# Isolated facility-map derivation, ordering and offline-failure regression.
set -eu

repo_root=$(CDPATH= cd "$(dirname "$0")/../.." && pwd) || exit 1
CDPATH= cd "$repo_root" || exit 1
./m osarch update || exit 2

map_root="$repo_root/facility"
fixture_one=p4-facility-test@v1.0
fixture_two=p4-facility-test@v1.1
fixture_three=p4-facility-test@v1.2
unknown_one=p4-facility-noorder@v1.0
unknown_two=p4-facility-noorder@v1.1
graalvm_one=graalvm@25.3.4.1!linux-arm64
graalvm_two=graalvm@25.5.5.0.3!linux-arm64

if [ -e "$map_root" ] || [ -L "$map_root" ]
then
  echo 'FAIL: facility map already exists; refusing destructive fixture cleanup' >&2
  exit 1
fi
pkg_empty=1
for package_entry in pkg/* pkg/.[!.]* pkg/..?*
do
  [ -e "$package_entry" ] || [ -L "$package_entry" ] || continue
  pkg_empty=0
done
if [ "$pkg_empty" -ne 1 ]; then
  echo 'FAIL: package store is not empty; refusing synthetic map fixtures' >&2
  exit 1
fi
if ./m pkg provider default web-control >/dev/null 2>&1
then
  echo 'FAIL: web-control system default exists; refusing synthetic map fixture' >&2
  exit 1
fi

cleanup()
{
  command -p -- rm -rf -- \
    "pkg/$fixture_one" "pkg/$fixture_two" "pkg/$fixture_three" \
    "pkg/$unknown_one" "pkg/$unknown_two" \
    "pkg/$graalvm_one" "pkg/$graalvm_two" "$map_root"
}
trap cleanup 0
trap 'exit 130' HUP INT TERM

make_concrete()
{
  concrete=$1
  facility=$2
  versions=$3
  command -p -- mkdir -p "pkg/$concrete/repository" || return 1
  printf '%s\n' "$facility" > "pkg/$concrete/facility" || return 1
  printf '%s\n' github > "pkg/$concrete/repository/type" || return 1
  printf '%s\n' rumiai-test > "pkg/$concrete/repository/owner" || return 1
  printf '%s\n' facility-map-fixture > "pkg/$concrete/repository/repository" || return 1
  printf '%s\n' "$versions" > "pkg/$concrete/repository/versions" || return 1
}

make_concrete "$fixture_one" 'web-control 2' 'v1.0
v1.1
v1.2' || exit 2
make_concrete "$fixture_two" 'web-control 2' 'v1.0
v1.1
v1.2' || exit 2
make_concrete "$fixture_three" 'web-control 3' 'v1.0
v1.1
v1.2' || exit 2
make_concrete "$unknown_one" 'web-control 4' 'v1.0' || exit 2
make_concrete "$unknown_two" 'web-control 4' 'v1.1' || exit 2

# A GraalVM repository history copied from the immutable catalog snapshot is
# the local ordering witness used by reconciliation; it must not fetch release
# chronology from GitHub.
make_graalvm_concrete()
{
  concrete=$1
  facility=$2
  command -p -- mkdir -p "pkg/$concrete/repository" || return 1
  printf '%s\n' "$facility" > "pkg/$concrete/facility" || return 1
  printf '%s\n' graalvm > "pkg/$concrete/repository/type" || return 1
  printf '%s\n' graalvm > "pkg/$concrete/repository/owner" || return 1
  printf '%s\n' graalvm-ce-builds > "pkg/$concrete/repository/repository" || return 1
  printf '%s\n' '25.3.4.1
25.4.4.1.1
25.5.5.0.3' > "pkg/$concrete/repository/versions" || return 1
}
make_graalvm_concrete "$graalvm_one" 'java 25' || exit 2
make_graalvm_concrete "$graalvm_two" 'java 25' || exit 2

reconcile()
{
  ./m sh -c '
    . "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 1
    loadsyslib "pkg/facility/pkg-facility-map" || exit 2
    pkg_facility_map_reconcile
  '
}

reconcile || exit 3
map_v2="$map_root/web-control/2/all"
map_v3="$map_root/web-control/3/all"
map_v4="$map_root/web-control/4/all"
[ -L "$map_v2/$fixture_one" ] || exit 4
[ -L "$map_v2/$fixture_two" ] || exit 5
[ "$(command -p -- readlink "$map_v2/p4-facility-test@latest")" = "$fixture_two" ] || exit 6
[ "$(command -p -- readlink "$map_v2/$fixture_two")" = "../../../../pkg/$fixture_two" ] || exit 7
[ -L "$map_v3/$fixture_three" ] || exit 8
[ "$(command -p -- readlink "$map_v3/p4-facility-test@latest")" = "$fixture_three" ] || exit 9
[ -L "$map_v4/$unknown_one" ] && [ -L "$map_v4/$unknown_two" ] || exit 10
[ ! -e "$map_v4/p4-facility-noorder@latest" ] && [ ! -L "$map_v4/p4-facility-noorder@latest" ] || exit 11
[ "$(command -p -- readlink "$map_root/java/25/linux-arm64/graalvm@latest")" = "${graalvm_two%!linux-arm64}" ] || exit 16

# Corrupt ordering must close the alias without removing concrete membership.
printf '%s\n' '25.3.4.1
25.3.4.1
25.5.5.0.3' > "pkg/$graalvm_two/repository/versions"
printf '%s\n' '25.3.4.1
25.3.4.1
25.5.5.0.3' > "pkg/$graalvm_one/repository/versions"
reconcile || exit 17
[ -L "$map_root/java/25/linux-arm64/${graalvm_one%!linux-arm64}" ] && [ -L "$map_root/java/25/linux-arm64/${graalvm_two%!linux-arm64}" ] || exit 18
[ ! -e "$map_root/java/25/linux-arm64/graalvm@latest" ] && [ ! -L "$map_root/java/25/linux-arm64/graalvm@latest" ] || exit 19
printf '%s\n' '25.3.4.1
25.4.4.1.1
25.5.5.0.3' > "pkg/$graalvm_two/repository/versions"
printf '%s\n' '25.3.4.1
25.4.4.1.1
25.5.5.0.3' > "pkg/$graalvm_one/repository/versions"
reconcile || exit 20
[ "$(command -p -- readlink "$map_root/java/25/linux-arm64/graalvm@latest")" = "${graalvm_two%!linux-arm64}" ] || exit 21

# Missing history on either concrete must not make the remaining release look
# like a proven latest version.
command -p -- rm -- "pkg/$graalvm_two/repository/versions"
command -p -- rm -- "pkg/$graalvm_one/repository/versions"
reconcile || exit 22
[ -L "$map_root/java/25/linux-arm64/${graalvm_one%!linux-arm64}" ] && [ -L "$map_root/java/25/linux-arm64/${graalvm_two%!linux-arm64}" ] || exit 23
[ ! -e "$map_root/java/25/linux-arm64/graalvm@latest" ] && [ ! -L "$map_root/java/25/linux-arm64/graalvm@latest" ] || exit 24

command -p -- rm -rf -- "pkg/$fixture_two"
reconcile || exit 12
[ "$(command -p -- readlink "$map_v2/p4-facility-test@latest")" = "$fixture_one" ] || exit 13
command -p -- rm -rf -- "pkg/$fixture_three"
reconcile || exit 14
[ ! -e "$map_v3" ] && [ ! -L "$map_v3" ] || exit 15

echo 'PASS: facility membership, adapter-ordered compatible latest, GraalVM snapshot ordering, corrupt-index fail-closed behavior, compatibility changes, offline unknown ordering and removal reconciliation'
