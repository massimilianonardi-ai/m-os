#!/bin/sh
# Real pkg_integrate + core context + JVM/sh source lookup; isolated CI fixture.
set -e
[ -n "${m_ROOT-}" ] && [ -n "${m_LIB_DIR-}" ] || exit 1
. "$m_LIB_DIR/sys/sh/core.lib.sh"
loadsyslib "pkg/pkg-integration"

command -p -- mkdir -p "$m_ROOT/.tmp"
work=$(TMPDIR="$m_ROOT/.tmp" mktemp -d) || exit 2
profile_root="$m_ROOT/state/system/profile"
profile_inventory="$profile_root/.inventory"
created='context-ci-lib@1 context-ci-lib@2 context-ci-other@1'
context_ci_packages_created=0
context_ci_inventory_created=0
cleanup()
{
  if [ "$context_ci_packages_created" -eq 1 ]; then
    for concrete in $created
    do
      command -p -- rm -rf -- "$m_PKG_DIR/$concrete"
    done
  fi
  [ "$context_ci_inventory_created" -eq 0 ] || command -p -- rm -f -- "$profile_inventory"
  command -p -- rm -rf -- "$work"
}
trap cleanup 0
trap 'exit 130' HUP INT TERM
for concrete in $created
do
  [ ! -e "$m_PKG_DIR/$concrete" ] && [ ! -L "$m_PKG_DIR/$concrete" ] || exit 3
done
[ ! -e "$profile_inventory" ] && [ ! -L "$profile_inventory" ] || exit 3
command -p -- chmod 755 "$m_ROOT/state" "$m_ROOT/state/system" "$profile_root" "$profile_root/main"
printf '%s\n' m-system-profile-inventory-v1 baseline=main profile=main > "$profile_inventory"
context_ci_inventory_created=1
command -p -- chmod 644 "$profile_inventory"
context_ci_packages_created=1

for version in 1 2
do
  case "$version" in 1) value=A ;; 2) value=B ;; esac
  range="$work/range/$version"
  root="$work/root/$version"
  command -p -- mkdir -p "$range/lib/sh" "$range/lib/java" "$root/lib/sh" "$root/lib/java" \
    "$work/java-src/$version/demo" "$work/java-classes/$version"
  printf '%s\n' tar.gz > "$range/format"
  printf 'lib/sh/shared.lib.sh\n' > "$range/lib/sh/shared.lib.sh"
  printf 'lib/java/shared.jar\n' > "$range/lib/java/shared.jar"
  printf 'SHARED_VERSION=%s\n' "$value" > "$root/lib/sh/shared.lib.sh"
  printf 'package demo; public class Shared { public static String version() { return "%s"; } }\n' "$value" > "$work/java-src/$version/demo/Shared.java"
  javac -d "$work/java-classes/$version" "$work/java-src/$version/demo/Shared.java"
  jar cf "$root/lib/java/shared.jar" -C "$work/java-classes/$version" .
  pkg_integrate context-ci-lib "$version" "$range" "$root" || exit 4
  [ -L "$m_PKG_DIR/context-ci-lib@$version/lib/sh/shared.lib.sh" ] || exit 5
  [ -L "$m_PKG_DIR/context-ci-lib@$version/lib/java/shared.jar" ] || exit 6
done

# A second installed package with a conflicting shell-library leaf must
# integrate normally but be rejected when selected with context-ci-lib.
range="$work/range/other"
root="$work/root/other"
command -p -- mkdir -p "$range/lib/sh" "$root/lib/sh"
printf '%s\n' tar.gz > "$range/format"
printf '%s\n' lib/sh/shared.lib.sh > "$range/lib/sh/shared.lib.sh"
printf '%s\n' SHARED_VERSION=other > "$root/lib/sh/shared.lib.sh"
pkg_integrate context-ci-other 1 "$range" "$root" || exit 7

printf '%s\n' 'import demo.Shared; public class Consumer { public static void main(String[] args) { System.out.print(Shared.version()); } }' > "$work/Consumer.java"
command -p -- mkdir "$work/consumer"
javac -cp "$m_PKG_DIR/context-ci-lib@1/lib/java/shared.jar" -d "$work/consumer" "$work/Consumer.java"

# No inherited CLASSPATH: context must add one, then restore absence on reset.
unset CLASSPATH
context pkg=context-ci-lib@1 || exit 8
[ "${CLASSPATH-}" = "$m_PKG_DIR/context-ci-lib@1/lib/java/*" ] || exit 9
. shared.lib.sh
[ "$SHARED_VERSION" = A ] || exit 10
CLASSPATH="$CLASSPATH:$work/consumer" java Consumer > "$work/observed"
[ "$(command -p -- cat "$work/observed")" = A ] || exit 11

context pkg=context-ci-lib@2 || exit 12
. shared.lib.sh
[ "$SHARED_VERSION" = B ] || exit 13
CLASSPATH="$CLASSPATH:$work/consumer" java Consumer > "$work/observed"
[ "$(command -p -- cat "$work/observed")" = B ] || exit 14

before_path=$PATH
before_classpath=$CLASSPATH
if context pkg=context-ci-lib@2 pkg=context-ci-other@1
then
  echo 'FAIL: duplicate exported shell library accepted' >&2
  exit 15
fi
[ "$PATH" = "$before_path" ] && [ "$CLASSPATH" = "$before_classpath" ] || exit 16

context || exit 17
[ "${CLASSPATH+x}" != x ] || exit 18
case "$PATH" in *"/context-ci-lib@"*) exit 19 ;; esac

# Keep inherited empty CLASSPATH distinct from unset and restore it.
CLASSPATH=
export CLASSPATH
context pkg=context-ci-lib@1 || exit 20
case "$CLASSPATH" in *:) : ;; *) exit 21 ;; esac
context || exit 22
[ "${CLASSPATH+x}" = x ] && [ -z "$CLASSPATH" ] || exit 23

# A failed context preparation must not alter either search path.
before_path=$PATH
before_classpath=$CLASSPATH
if context pkg=context-ci-missing@1
then
  exit 24
fi
[ "$PATH" = "$before_path" ] && [ "$CLASSPATH" = "$before_classpath" ] || exit 25

# Failed readonly probes must leave an already active shell unchanged.
(
  readonly CLASSPATH
  previous=$PATH
  if context pkg=context-ci-lib@1
  then
    exit 26
  fi
  [ "$PATH" = "$previous" ] || exit 27
) || exit 28

# An unrelated PATH edit and an unrelated CLASSPATH edit must survive
# a subsequent context replacement.
unset CLASSPATH
context pkg=context-ci-lib@1 || exit 29
PATH="/tmp/context-host-extra:$PATH"
CLASSPATH="/tmp/context-classpath-extra:$CLASSPATH"
export PATH CLASSPATH
context pkg=context-ci-lib@2 || exit 30
case "$PATH" in *"/tmp/context-host-extra"*) : ;; *) exit 31 ;; esac
case "$CLASSPATH" in *"/tmp/context-classpath-extra"*) : ;; *) exit 32 ;; esac
context || exit 33
[ "$CLASSPATH" = "/tmp/context-classpath-extra" ] || exit 34

printf '%s\n' 'PASS: installed lib/sh and lib/java symlinks, POSIX dot, JVM CLASSPATH, replacement, rollback, collision'
