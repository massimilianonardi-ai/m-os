#!/bin/sh
# Real v2 library-only package integration, shell sourcing and JVM classpath.
set -eu
[ -n "${m_ROOT-}" ] && [ -n "${m_LIB_DIR-}" ] || exit 1
. "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 2
loadsyslib "pkg/pkg-integration" || exit 3

name=context-ci-v2-libs
concrete="$m_PKG_DIR/$name@1"
selector="$m_PKG_DIR/$name"
work=$(mktemp -d) || exit 4

cleanup()
{
  context >/dev/null 2>&1 || :
  command -p -- rm -f -- "$selector"
  command -p -- rm -rf -- "$concrete" "$work"
}
[ ! -e "$concrete" ] && [ ! -L "$concrete" ] || exit 5
[ ! -e "$selector" ] && [ ! -L "$selector" ] || exit 6
trap cleanup 0

range="$work/range"
root="$work/root"
command -p -- mkdir -p "$range/link/lib/sh" "$range/link/lib/java" \
  "$root/lib/sh" "$root/lib/java" "$work/java-src/demo" "$work/java-classes" "$work/consumer" || exit 7
printf 'tar.gz\n' > "$range/format"
printf '../../../root/lib/sh/sample.lib.sh\n' > "$range/link/lib/sh/sample.lib.sh"
printf '../../../root/lib/java/sample.jar\n' > "$range/link/lib/java/sample.jar"
printf 'SAMPLE_VERSION=v2\n' > "$root/lib/sh/sample.lib.sh"

printf '%s\n' 'package demo; public class Shared { public static String version() { return "v2"; } }' > "$work/java-src/demo/Shared.java"
javac -d "$work/java-classes" "$work/java-src/demo/Shared.java"
jar cf "$root/lib/java/sample.jar" -C "$work/java-classes" .

set -x
if pkg_integrate "$name" 1 "$range" "$root" "" v2
then
  :
else
  status=$?
  printf 'v2 library-only integration failed: status=%s\n' "$status" >&2
  exit 8
fi
set +x
[ "$(command -p -- cat -- "$concrete/schema")" = v2 ] || exit 9
[ ! -e "$concrete/link/bin" ] && [ ! -L "$concrete/link/bin" ] || exit 10
[ -L "$concrete/link/lib/sh/sample.lib.sh" ] && [ -L "$concrete/link/lib/java/sample.jar" ] || exit 11
[ "$(command -p -- readlink "$concrete/link/lib/sh/sample.lib.sh")" = "../../../root/lib/sh/sample.lib.sh" ] || exit 12
pkg_default_apply "$name" 1 || exit 13
[ -L "$selector" ] || exit 14

printf '%s\n' 'import demo.Shared; public class Consumer { public static void main(String[] args) { System.out.print(Shared.version()); } }' > "$work/Consumer.java"
javac -cp "$concrete/link/lib/java/sample.jar" -d "$work/consumer" "$work/Consumer.java"

unset CLASSPATH
baseline=$PATH
context "pkg=$name@1" || exit 15
[ "${CLASSPATH-}" = "$concrete/link/lib/java/*" ] || exit 16
. sample.lib.sh
[ "$SAMPLE_VERSION" = v2 ] || exit 17
[ "$(CLASSPATH="$CLASSPATH:$work/consumer" java Consumer)" = v2 ] || exit 18
context || exit 19
[ "$PATH" = "$baseline" ] || exit 20
[ "${CLASSPATH+x}" != x ] || exit 21
pkg_default_apply "$name" "" || exit 22

printf '%s\n' 'PASS: library-only v2 link/lib/sh + Java JAR, context and default lifecycle'
