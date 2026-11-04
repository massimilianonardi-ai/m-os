#!/bin/sh
# Exercise real generic and host-specific v2 concretes; verify global env.
set -eu
[ -n "${m_ROOT-}" ] && [ -n "${m_LIB_DIR-}" ] && [ -n "${CATALOG_V2-}" ] || exit 1
. "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 2
loadsyslib "osarch" || exit 3
loadsyslib "pkg/pkg-integration" || exit 4

work=$(mktemp -d) || exit 4
name=facility-ci-osarch-java-v2
generic="$m_PKG_DIR/$name@1"
specific="$m_PKG_DIR/$name@1!$m_OSARCH"
default_set=0
cleanup()
{
  if [ "$default_set" -eq 1 ]
  then
    "$m_ROOT/m" pkg provider default -u java >/dev/null 2>&1 || :
  fi
  command -p -- rm -rf -- "$generic" "$specific" "$work"
}
trap cleanup 0

[ ! -e "$generic" ] && [ ! -L "$generic" ] || exit 5
[ ! -e "$specific" ] && [ ! -L "$specific" ] || exit 6
if "$m_ROOT/m" pkg provider default java >/dev/null 2>&1
then
  printf '%s\n' 'INFRASTRUCTURE: existing java default would be replaced' >&2
  exit 7
fi
catalog="$work/catalog/v2"
range="$catalog/pkg/$name/all/n0001=1"
command -p -- mkdir -p -- "$catalog/facility" "$work/root-generic/bin" \
  "$work/root-specific/bin" "$range/facility-bin" \
  "$range/facility-env/java" || exit 8
command -p -- cp -R -- "$CATALOG_V2/facility/java" "$catalog/facility/java" || exit 9

# Extend only the copied central contract to probe shared/delta extraction.
: > "$catalog/facility/java/21/env/CI_SHARED"
: > "$catalog/facility/java/21/env/CI_CLASS"
printf 'tar.gz\n' > "$range/format"
printf 'java 21\n' > "$range/facility"
printf 'bin\n' > "$range/facility-bin/java"
printf 'root\n' > "$range/facility-env/java/JAVA_HOME"
printf 'root-path bin\n' > "$range/facility-env/java/PATH"
printf 'literal shared\n' > "$range/facility-env/java/CI_SHARED"
for member in "$catalog/facility/java/21/cmd/"*
do
  command_name=${member##*/}
  printf '#!/bin/sh\nprintf "generic\\n"\n' > "$work/root-generic/bin/$command_name"
  printf '#!/bin/sh\nprintf "specific\\n"\n' > "$work/root-specific/bin/$command_name"
  command -p -- chmod +x -- "$work/root-generic/bin/$command_name" \
    "$work/root-specific/bin/$command_name" || exit 10
done

printf 'literal generic\n' > "$range/facility-env/java/CI_CLASS"
# Emit a trace only on failing conformance to pinpoint a fixture mismatch.
if ! pkg_facility_provider_validate "$catalog" "$range" "$work/root-generic"
then
  ( set -x; pkg_facility_provider_validate "$catalog" "$range" "$work/root-generic" ) >&2 || :
  exit 11
fi
pkg_integrate "$name" 1 "$range" "$work/root-generic" "" v2 "$catalog" || exit 12
printf 'literal specific\n' > "$range/facility-env/java/CI_CLASS"
pkg_facility_provider_validate "$catalog" "$range" "$work/root-specific" || exit 13
pkg_integrate "$name" 1 "$range" "$work/root-specific" "$m_OSARCH" v2 "$catalog" || exit 14

cache="$m_STATE_SYS_DIR/sys/environment/cache"
"$m_ROOT/m" pkg provider default java "$name@1" || exit 15
default_set=1
[ "$("$m_ROOT/m" pkg provider default java)" = "$name@1" ] || exit 16
[ -f "$cache/env" ] && [ -f "$cache/env-$m_OSARCH" ] || exit 17
command -p -- grep -F 'CI_SHARED=' "$cache/env" >/dev/null || exit 18
if command -p -- grep -F 'CI_SHARED=' "$cache/env-$m_OSARCH" >/dev/null
then
  exit 19
fi

check_snapshot()
(
  selected_osarch=$1
  expected_class=$2
  expected_root=$3
  unset CI_SHARED CI_CLASS JAVA_HOME
  PATH=/usr/bin:/bin
  export PATH
  . "$cache/env" || exit 20
  . "$cache/env-$selected_osarch" || exit 21
  [ "$CI_SHARED" = shared ] || exit 22
  [ "$CI_CLASS" = "$expected_class" ] || exit 23
  [ "$JAVA_HOME" = "$expected_root" ] || exit 24
  case "$PATH" in
    "$expected_root/bin":*) : ;;
    *) exit 25 ;;
  esac
)

for candidate in linux-x86_64 linux-arm64 macos-x86_64 macos-arm64 windows-x86_64 windows-arm64
do
  case "$candidate" in
    "$m_OSARCH")
      check_snapshot "$candidate" specific "$specific/root" || exit 26
      ;;
    *)
      check_snapshot "$candidate" generic "$generic/root" || exit 27
      ;;
  esac
done

CI_EXPECTED_ROOT="$specific/root" "$m_ROOT/m" sh -ec '
  [ "$CI_SHARED" = shared ] || exit 1
  [ "$CI_CLASS" = specific ] || exit 2
  [ "$JAVA_HOME" = "$CI_EXPECTED_ROOT" ] || exit 3
  [ "$("$m_ROOT/m" javac)" = specific ] || exit 4
' || exit 28

# A class-qualified pin must prevent fallback on other platforms.
"$m_ROOT/m" pkg provider default java "$name@1!$m_OSARCH" || exit 29
for candidate in linux-x86_64 linux-arm64 macos-x86_64 macos-arm64 windows-x86_64 windows-arm64
do
  (
    unset CI_SHARED CI_CLASS JAVA_HOME
    PATH=/usr/bin:/bin
    export PATH
    . "$cache/env" || exit 30
    . "$cache/env-$candidate" || exit 31
    if [ "$candidate" = "$m_OSARCH" ]
    then
      [ "$CI_SHARED" = shared ] && [ "$CI_CLASS" = specific ] &&
        [ "$JAVA_HOME" = "$specific/root" ] || exit 32
    else
      [ -z "${CI_SHARED+x}" ] && [ -z "${CI_CLASS+x}" ] &&
        [ -z "${JAVA_HOME+x}" ] || exit 33
    fi
  ) || exit 34
done
[ "$("$m_ROOT/m" javac)" = specific ] || exit 35
"$m_ROOT/m" pkg provider default -u java || exit 36
default_set=0
"$m_ROOT/m" sh -ec '
  [ -z "${CI_SHARED+x}" ] && [ -z "${CI_CLASS+x}" ] || exit 1
' || exit 37

printf '%s\n' 'PASS: v2 generic/specific global env, six osarch snapshots, actual bootstrap, pinned selector and unset'
