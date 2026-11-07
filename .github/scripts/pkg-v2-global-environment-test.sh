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
node_name=facility-ci-overlap-node-v2
node_concrete="$m_PKG_DIR/$node_name@1"
default_set=0
node_default_set=0
cleanup()
{
  if [ "$node_default_set" -eq 1 ]
  then
    "$m_ROOT/m" pkg provider default -u nodejs >/dev/null 2>&1 || :
  fi
  if [ "$default_set" -eq 1 ]
  then
    "$m_ROOT/m" pkg provider default -u java >/dev/null 2>&1 || :
  fi
  command -p -- rm -rf -- "$generic" "$specific" "$node_concrete" "$work"
}

# Do not establish the destructive cleanup trap until all pre-existing
# installations and configurations have been rejected.
if [ -e "$generic" ] || [ -L "$generic" ] ||
   [ -e "$specific" ] || [ -L "$specific" ] ||
   [ -e "$node_concrete" ] || [ -L "$node_concrete" ]
then
  command -p -- rm -rf -- "$work"
  printf '%s\n' 'INFRASTRUCTURE: fixture package concrete already exists' >&2
  exit 5
fi
if "$m_ROOT/m" pkg provider default java >/dev/null 2>&1 ||
   "$m_ROOT/m" pkg provider default nodejs >/dev/null 2>&1
then
  command -p -- rm -rf -- "$work"
  printf '%s\n' 'INFRASTRUCTURE: existing java/nodejs default would be replaced' >&2
  exit 6
fi
trap cleanup 0
# The integration entrypoint requires the managed package store to exist.
command -p -- mkdir -p -- "$m_PKG_DIR" || exit 8
catalog="$work/catalog/v2"
range="$catalog/pkg/$name/all/n0001=1"
command -p -- mkdir -p -- "$catalog/facility" "$work/root-generic/bin" \
  "$work/root-specific/bin" "$range/facility-bin" \
  "$range/facility-env/java" || exit 8
command -p -- cp -R -- "$CATALOG_V2/facility/java" "$catalog/facility/java" || exit 9

# Extend only the copied central contract to probe shared/delta extraction.
: > "$catalog/facility/java/21/env/CI_SHARED"
: > "$catalog/facility/java/21/env/CI_CLASS"
: > "$catalog/facility/java/21/env/PATH"
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
  command -p -- chmod +x "$work/root-generic/bin/$command_name" \
    "$work/root-specific/bin/$command_name" || exit 10
done

printf 'literal generic\n' > "$range/facility-env/java/CI_CLASS"
pkg_facility_provider_validate "$catalog" "$range" "$work/root-generic" || exit 11
if pkg_integrate "$name" 1 "$range" "$work/root-generic" "" v2 "$catalog"
then
  :
else
  status=$?
  printf 'FAIL: generic v2 integration status=%s\n' "$status" >&2
  exit 12
fi
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


# A second independent facility follows the same global pipeline.
# java precedes nodejs lexically: nodejs must win an ordinary variable
# collision and prepend its PATH segment, irrespective of mutation order.
node_range="$catalog/pkg/$node_name/all/n0001=1"
node_root="$work/root-nodejs"
command -p -- cp -R -- "$CATALOG_V2/facility/nodejs" \
  "$catalog/facility/nodejs" || exit 38
command -p -- mkdir -p -- "$node_range/facility-bin" \
  "$node_range/facility-env/nodejs" "$node_root/bin" \
  "$catalog/facility/nodejs/26/env" || exit 39
: > "$catalog/facility/nodejs/26/env/CI_SHARED"
: > "$catalog/facility/nodejs/26/env/PATH"
printf 'tar.gz\n' > "$node_range/format"
printf 'nodejs 26\n' > "$node_range/facility"
printf 'bin\n' > "$node_range/facility-bin/nodejs"
printf 'literal nodejs\n' > "$node_range/facility-env/nodejs/CI_SHARED"
printf 'root-path bin\n' > "$node_range/facility-env/nodejs/PATH"
for member in "$catalog/facility/nodejs/26/cmd/"*
do
  command_name=${member##*/}
  printf '#!/bin/sh\nprintf "nodejs\\n"\n' > "$node_root/bin/$command_name"
  command -p -- chmod +x "$node_root/bin/$command_name" || exit 40
done
pkg_facility_provider_validate "$catalog" "$node_range" "$node_root" || exit 41
pkg_integrate "$node_name" 1 "$node_range" "$node_root" "" v2 "$catalog" || exit 42
"$m_ROOT/m" pkg provider default nodejs "$node_name@1" || exit 43
node_default_set=1

for candidate in linux-x86_64 linux-arm64 macos-x86_64 macos-arm64 windows-x86_64 windows-arm64
do
  (
    unset CI_SHARED CI_CLASS JAVA_HOME
    PATH=/usr/bin:/bin
    export PATH
    . "$cache/env" || exit 1
    . "$cache/env-$candidate" || exit 2
    java_root="$generic/root"
    expected_class=generic
    if [ "$candidate" = "$m_OSARCH" ]
    then
      java_root="$specific/root"
      expected_class=specific
    fi
    [ "$CI_SHARED" = nodejs ] || exit 3
    [ "$CI_CLASS" = "$expected_class" ] || exit 4
    [ "$JAVA_HOME" = "$java_root" ] || exit 5
    case "$PATH" in
      "$node_concrete/root/bin:$java_root/bin":*) : ;;
      *) exit 6 ;;
    esac
  ) || exit 44
done
CI_EXPECTED_JAVA="$specific/root" CI_EXPECTED_NODE="$node_concrete/root" \
  "$m_ROOT/m" sh -ec '
    [ "$CI_SHARED" = nodejs ] || exit 1
    [ "$CI_CLASS" = specific ] || exit 2
    [ "$JAVA_HOME" = "$CI_EXPECTED_JAVA" ] || exit 3
    [ "$("$m_ROOT/m" node)" = nodejs ] || exit 4
    case "$PATH" in
      *"$CI_EXPECTED_NODE/bin:$CI_EXPECTED_JAVA/bin":*) : ;;
      *) exit 5 ;;
    esac
  ' || exit 45

# Changing the earlier facility must not reverse the later facility's
# precedence or resurrect the generic provider on other osarch classes.
"$m_ROOT/m" pkg provider default java "$name@1!$m_OSARCH" || exit 46
for candidate in linux-x86_64 linux-arm64 macos-x86_64 macos-arm64 windows-x86_64 windows-arm64
do
  (
    unset CI_SHARED CI_CLASS JAVA_HOME
    PATH=/usr/bin:/bin
    export PATH
    . "$cache/env" || exit 1
    . "$cache/env-$candidate" || exit 2
    [ "$CI_SHARED" = nodejs ] || exit 3
    if [ "$candidate" = "$m_OSARCH" ]
    then
      [ "$CI_CLASS" = specific ] &&
        [ "$JAVA_HOME" = "$specific/root" ] || exit 4
      case "$PATH" in
        "$node_concrete/root/bin:$specific/root/bin":*) : ;;
        *) exit 5 ;;
      esac
    else
      [ -z "${CI_CLASS+x}" ] && [ -z "${JAVA_HOME+x}" ] || exit 6
      case "$PATH" in
        "$node_concrete/root/bin":*) : ;;
        *) exit 7 ;;
      esac
    fi
  ) || exit 47
done
"$m_ROOT/m" pkg provider default -u nodejs || exit 48
node_default_set=0

# A class-qualified pin must prevent fallback on other platforms.
[ "$("$m_ROOT/m" pkg provider default java)" = "$name@1!$m_OSARCH" ] || exit 29
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

printf '%s\n' 'PASS: v2 global env for generic/specific providers and two facilities, six osarch snapshots, actual bootstrap, ordering and unset'
