#!/bin/sh
# Real pkg_integrate + core context + JVM/sh source lookup; isolated CI fixture.
set -e
[ -n "${m_ROOT-}" ] && [ -n "${m_LIB_DIR-}" ] || exit 1
. "$m_LIB_DIR/sys/sh/core.lib.sh"
loadsyslib "pkg/pkg-integration"

work=$(mktemp -d) || exit 2
created='context-ci-lib@1 context-ci-lib@2 context-ci-other@1 context-ci-aux@1'
cleanup()
{
  for concrete in $created
  do
    command -p -- rm -rf -- "$m_PKG_DIR/$concrete"
  done
  command -p -- rm -rf -- "$work"
}
for concrete in $created
do
  [ ! -e "$m_PKG_DIR/$concrete" ] && [ ! -L "$m_PKG_DIR/$concrete" ] || exit 3
done
trap cleanup 0

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

range="$work/range/aux"
root="$work/root/aux"
command -p -- mkdir -p "$range/lib/sh" "$root/lib/sh"
printf '%s\n' tar.gz > "$range/format"
printf '%s\n' lib/sh/aux.lib.sh > "$range/lib/sh/aux.lib.sh"
printf '%s\n' AUX_VERSION=1 > "$root/lib/sh/aux.lib.sh"
pkg_integrate context-ci-aux 1 "$range" "$root" || exit 34

# Persisted account defaults and presets are separate from active shell state.
context defaults clear || exit 35
context reset || exit 36
_context_defaults_base_path=$PATH
context defaults set pkg=context-ci-lib@1 || exit 37
[ "$PATH" = "$_context_defaults_base_path" ] || exit 38
context || exit 39
[ "${PATH%%:*}" = "$m_PKG_DIR/context-ci-lib@1/lib/sh" ] || exit 40
[ "${CLASSPATH-}" = "$m_PKG_DIR/context-ci-lib@1/lib/java/*" ] || exit 41
context defaults set pkg=context-ci-lib@2 || exit 42
[ "${PATH%%:*}" = "$m_PKG_DIR/context-ci-lib@1/lib/sh" ] || exit 43
context defaults set pkg=context-ci-aux@1 || exit 67
[ "${PATH%%:*}" = "$m_PKG_DIR/context-ci-lib@1/lib/sh" ] || exit 68
_context_pref_dir="$m_ROOT/state/$(id -u)/context"
command -p -- grep -Fx 'pkg=context-ci-aux@1' "$_context_pref_dir/defaults" >/dev/null || exit 75
context || exit 44
[ "${PATH%%:*}" = "$m_PKG_DIR/context-ci-aux@1/lib/sh" ] || exit 45
case ":$PATH:" in *":$m_PKG_DIR/context-ci-lib@2/lib/sh:"*) : ;; *) exit 69 ;; esac
context defaults set pkg=context-ci-lib@1 || exit 70
context || exit 71
[ "${PATH%%:*}" = "$m_PKG_DIR/context-ci-lib@1/lib/sh" ] || exit 72
case ":$PATH:" in *":$m_PKG_DIR/context-ci-aux@1/lib/sh:"*) : ;; *) exit 73 ;; esac
context preset set saved pkg=context-ci-lib@1 || exit 46
context reset || exit 47
context preset=saved || exit 48
[ "${PATH%%:*}" = "$m_PKG_DIR/context-ci-lib@1/lib/sh" ] || exit 49
context preset clear saved || exit 50
before_path=$PATH
_context_pref_dir="$m_ROOT/state/$(id -u)/context"
command -p -- rmdir "$_context_pref_dir/presets" || exit 76
command -p -- ln -s "$work" "$_context_pref_dir/presets" || exit 77
if context preset=saved
then
  exit 78
fi
[ "$PATH" = "$before_path" ] || exit 79
command -p -- rm -f "$_context_pref_dir/presets" || exit 80
if context preset=saved
then
  exit 51
fi
[ "$PATH" = "$before_path" ] || exit 52
context defaults clear || exit 53
[ "${PATH%%:*}" = "$m_PKG_DIR/context-ci-lib@1/lib/sh" ] || exit 54
context || exit 55
case "$PATH" in *"$m_PKG_DIR/context-ci-lib@"*) exit 56 ;; esac
context defaults set pkg=context-ci-lib@1 || exit 57
_context_pref_dir="$m_ROOT/state/$(id -u)/context"
[ "$(command -p -- head -n 1 "$_context_pref_dir/defaults")" = m-context-v1 ] || exit 58
command -p -- grep -Fx 'pkg=context-ci-lib@1' "$_context_pref_dir/defaults" >/dev/null || exit 74
printf 'm-context-v1\n$(touch %s)\n' "$work/untrusted-evaluated" > "$work/unsafe-record"
context defaults clear || exit 60
command -p -- ln -s "$work/unsafe-record" "$_context_pref_dir/defaults" || exit 60
before_path=$PATH
if context
then
  exit 61
fi
[ "$PATH" = "$before_path" ] && [ ! -e "$work/untrusted-evaluated" ] || exit 62
command -p -- rm -f "$_context_pref_dir/defaults" || exit 63
command -p -- chmod 775 "$m_STATE_DIR" || exit 64
if context
then
  command -p -- chmod 755 "$m_STATE_DIR" || exit 66
  exit 65
fi
command -p -- chmod 755 "$m_STATE_DIR" || exit 66
context defaults clear || exit 59

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
if context pkg=context-ci-other@1
then
  echo 'FAIL: duplicate exported shell library accepted' >&2
  exit 15
fi
[ "$PATH" = "$before_path" ] && [ "$CLASSPATH" = "$before_classpath" ] || exit 16

context reset || exit 17
[ "${CLASSPATH+x}" != x ] || exit 18
case "$PATH" in *"/context-ci-lib@"*) exit 19 ;; esac

# Keep inherited empty CLASSPATH distinct from unset and restore it.
CLASSPATH=
export CLASSPATH
context pkg=context-ci-lib@1 || exit 20
case "$CLASSPATH" in *:) : ;; *) exit 21 ;; esac
context reset || exit 22
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
context reset || exit 33
[ "$CLASSPATH" = "/tmp/context-classpath-extra" ] || exit 34

printf '%s\n' 'PASS: installed lib/sh and lib/java symlinks, POSIX dot, JVM CLASSPATH, replacement, rollback, collision'
