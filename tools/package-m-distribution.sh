#!/bin/sh
set -eu
umask 022

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
git -C "$root" rev-parse --show-toplevel >/dev/null 2>&1 || {
  printf '%s\n' 'm distribution build requires a Git checkout' >&2
  exit 1
}
git_root=$(git -C "$root" rev-parse --show-toplevel) || exit 1
[ "$git_root" = "$root" ] || {
  printf '%s\n' 'm distribution build must run from the repository root' >&2
  exit 1
}
source_status=$(git -C "$root" status --porcelain --untracked-files=all) || exit 1
[ -z "$source_status" ] || {
  printf '%s\n' 'm distribution build requires a clean Git checkout' >&2
  exit 1
}
commit=$(git -C "$root" rev-parse --verify HEAD) || exit 1

dist="$root/dist"
if [ -L "$dist" ] || { [ -e "$dist" ] && [ ! -d "$dist" ]; }
then
  printf 'm distribution output path is not a directory: %s\n' "$dist" >&2
  exit 1
fi
mkdir -p "$dist"
[ -d "$dist" ] && [ ! -L "$dist" ] || {
  printf 'm distribution output path is unsafe: %s\n' "$dist" >&2
  exit 1
}

work=
stage=
verify=
archive_tmp=
cleanup()
{
  [ -z "$work" ] || rm -rf "$work"
}
trap cleanup 0
trap 'exit 130' HUP INT TERM

counter=0
while [ "$counter" -lt 100 ]
do
  candidate="$dist/.m-os-build.$$.$counter"
  if (umask 077; mkdir "$candidate") 2>/dev/null
  then
    work=$candidate
    break
  fi
  counter=$((counter + 1))
done
[ -n "$work" ] || {
  printf '%s\n' 'm distribution could not allocate a private staging directory' >&2
  exit 1
}
stage="$work/source"
verify="$work/verify"
mkdir "$stage"

git -C "$root" archive --format=tar "$commit" > "$stage/source.tar"
(cd "$stage" && tar -xf source.tar)
rm -f "$stage/source.tar"

(cd "$stage" && ./m osarch update)
host_osarch=$(cd "$stage" && ./m osarch)
case "$host_osarch" in
  linux-arm64 | linux-x86_64 | macos-arm64 | macos-x86_64) : ;;
  *)
    printf 'm distribution has no native service supervisor for %s\n' "$host_osarch" >&2
    exit 2
    ;;
esac

(cd "$stage" && CC="${CC:-cc}" ./tools/build-srv-supervisor.sh >/dev/null)
helper="$stage/libexec/sys/srv-supervisor"
[ -f "$helper" ] && [ ! -L "$helper" ] && [ -x "$helper" ] || {
  printf '%s\n' 'm distribution did not produce an executable supervisor' >&2
  exit 1
}

{
  printf '%s\n' 'm-os-distribution-v1'
  printf 'commit=%s\n' "$commit"
  printf 'osarch=%s\n' "$host_osarch"
} > "$stage/M-DISTRIBUTION"
chmod 644 "$stage/M-DISTRIBUTION"

if "$helper" --invalid >/dev/null 2>&1
then
  printf '%s\n' 'm distribution supervisor accepted an invalid internal invocation' >&2
  exit 1
else
  helper_status=$?
fi
[ "$helper_status" -eq 2 ] || {
  printf 'm distribution supervisor could not execute (status %s)\n' "$helper_status" >&2
  exit 1
}

archive="$dist/m-os-$host_osarch.tar.gz"
if [ -L "$archive" ] || { [ -e "$archive" ] && [ ! -f "$archive" ]; }
then
  printf 'm distribution archive path is not a regular file: %s\n' "$archive" >&2
  exit 1
fi
archive_tmp="$work/m-os-$host_osarch.tar.gz"
(cd "$stage" && tar -czf "$archive_tmp" .)

list="$stage/archive.list"
tar -tzf "$archive_tmp" > "$list"
grep -Fx './m' "$list" >/dev/null
grep -Fx './bin/sys/srv' "$list" >/dev/null
grep -Fx './libexec/sys/srv-supervisor' "$list" >/dev/null
grep -Fx './M-DISTRIBUTION' "$list" >/dev/null

mkdir "$verify"
tar -xzf "$archive_tmp" -C "$verify"
[ -x "$verify/m" ] && [ -x "$verify/libexec/sys/srv-supervisor" ] || {
  printf '%s\n' 'm distribution archive lost executable permissions' >&2
  exit 1
}
verified_osarch=$(cd "$verify" && ./m osarch)
[ "$verified_osarch" = "$host_osarch" ] || {
  printf 'm distribution archive osarch mismatch: built %s, extracted %s\n' \
    "$host_osarch" "$verified_osarch" >&2
  exit 1
}
grep -Fx "commit=$commit" "$verify/M-DISTRIBUTION" >/dev/null
grep -Fx "osarch=$host_osarch" "$verify/M-DISTRIBUTION" >/dev/null
if "$verify/libexec/sys/srv-supervisor" --invalid >/dev/null 2>&1
then
  printf '%s\n' 'm distribution archive supervisor accepted an invalid invocation' >&2
  exit 1
else
  helper_status=$?
fi
[ "$helper_status" -eq 2 ] || {
  printf 'm distribution archive supervisor failed to execute (status %s)\n' \
    "$helper_status" >&2
  exit 1
}
(cd "$verify" && ./.github/scripts/m-srv-supervisor-public.sh)

mv -f "$archive_tmp" "$archive"
archive_tmp=
printf 'PASS: %s at m-os@%s\n' "$archive" "$commit"
