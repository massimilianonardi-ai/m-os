#!/bin/sh
# Exact installed v2 concrete replacement using immutable published releases.
set -eu

fail()
{
  printf '%s\n' "FAIL: $1" >&2
  exit 1
}

[ -n "${m_ROOT-}" ] && [ -n "${m_LIB_DIR-}" ] && [ -n "${m_PKG_DIR-}" ] ||
  fail 'm environment missing'
. "$m_LIB_DIR/sys/sh/core.lib.sh" || fail 'm runtime loading failed'

for concrete in m-core@v0.1.0 m-core@v0.1.1 m-term@v0.1.0 m-term@v0.1.1
do
  [ -d "$m_PKG_DIR/$concrete" ] || fail "published package concrete $concrete not installed"
done

context || fail 'initial context reset'
host_path=$PATH
unset CLASSPATH
context 'pkg=m-core@v0.1.0' 'pkg=m-term@v0.1.0' ||
  fail 'cannot select original published versions'
[ "$(command -v menu)" = "$m_PKG_DIR/m-term@v0.1.0/link/bin/menu" ] ||
  fail 'old m-term command version not selected'
[ -L "$m_PKG_DIR/m-core@v0.1.0/link/lib/sh/array.lib.sh" ] ||
  fail 'original published core library link missing'
case ":$PATH:" in
  *":$m_PKG_DIR/m-core@v0.1.0/link/lib/sh:"*) : ;;
  *) fail 'old m-core shell-library PATH view not selected' ;;
esac

# Replace same package identities independently; unrelated package is retained.
context 'pkg=m-term@v0.1.1' 'pkg=m-core@v0.1.1' ||
  fail 'cannot switch to actual newer installed versions'
[ "$(command -v menu)" = "$m_PKG_DIR/m-term@v0.1.1/link/bin/menu" ] ||
  fail 'new m-term command version not selected'
[ -L "$m_PKG_DIR/m-core@v0.1.1/link/lib/sh/array.lib.sh" ] ||
  fail 'new published core library link missing'
case ":$PATH:" in
  *":$m_PKG_DIR/m-core@v0.1.1/link/lib/sh:"*) : ;;
  *) fail 'new m-core shell-library PATH view not selected' ;;
esac
case "$PATH" in
  *"$m_PKG_DIR/m-term@v0.1.0/"* | *"$m_PKG_DIR/m-core@v0.1.0/"*)
    fail 'stale older package PATH contribution survived replacement' ;;
esac

. array.lib.sh || fail 'genuine newer core shell library cannot be sourced'
array context_ci_versions || fail 'real newer array creation failed'
array context_ci_versions set new version || fail 'real newer array set failed'
array context_ci_versions size context_ci_count || fail 'real newer array query failed'
[ "$context_ci_count" -eq 2 ] || fail 'real newer source returned unexpected result'

selected_path=$PATH
selected_concretes=${m_CONTEXT_PACKAGES-}
if context 'pkg=m-core@never-published'; then
  fail 'missing replacement concrete unexpectedly accepted'
fi
[ "$PATH" = "$selected_path" ] &&
[ "${m_CONTEXT_PACKAGES-}" = "$selected_concretes" ] ||
  fail 'failed replacement altered active real context'

# Replace just core back with the older release without disturbing term.
context 'pkg=m-core@v0.1.0' || fail 'cannot select original core version again'
case ":$PATH:" in
  *":$m_PKG_DIR/m-core@v0.1.0/link/lib/sh:"*) : ;;
  *) fail 'core reverse library view replacement failed' ;;
esac
[ "$(command -v menu)" = "$m_PKG_DIR/m-term@v0.1.1/link/bin/menu" ] ||
  fail 'unrelated term version was not retained'

context || fail 'real installed-version context reset failed'
[ "$PATH" = "$host_path" ] || fail 'reset retained an installed-version PATH segment'
[ "${CLASSPATH+x}" != x ] || fail 'reset introduced a classpath value'
printf '%s\n' 'PASS: real v2 installed 0.1.0 to 0.1.1 concrete replacement, exact commands, shell libraries and reset'
