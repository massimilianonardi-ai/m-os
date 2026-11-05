#!/bin/sh
# CI-only C1 validation using genuine published m packages.
set -eu

fail()
{
  printf '%s\n' "FAIL: $1" >&2
  exit 1
}

[ -n "${m_ROOT-}" ] && [ -n "${m_LIB_DIR-}" ] && [ -n "${m_PKG_DIR-}" ] || fail 'm environment unavailable'
. "$m_LIB_DIR/sys/sh/core.lib.sh" || fail 'm core not available'

for name in m-core m-term m-rsudo
do
  [ -d "$m_PKG_DIR/$name@v0.1.0" ] || fail "real installed $name concrete missing"
done

# The currently specified no-argument call is a reset, not a default context.
context || fail 'initial context reset'
initial_path=$PATH
unset CLASSPATH
context 'pkg=m-core@v0.1.0' 'pkg=m-term@v0.1.0' 'pkg=m-rsudo@v0.1.0' ||
  fail 'cannot select three real packages'

[ "$(command -v menu)" = "$m_PKG_DIR/m-term@v0.1.0/link/bin/menu" ] ||
  fail 'menu did not resolve from installed v2 command view'
[ "$(command -v rsudo)" = "$m_PKG_DIR/m-rsudo@v0.1.0/link/bin/rsudo" ] ||
  fail 'rsudo did not resolve from installed v2 command view'
[ -L "$m_PKG_DIR/m-core@v0.1.0/link/lib/sh/array.lib.sh" ] ||
  fail 'real package shell library projection missing'
. array.lib.sh || fail 'cannot source genuine selected array library'
array context_ci_items || fail 'genuine array library consumer failed'
array context_ci_items set one two || fail 'genuine array set failed'
array context_ci_items size context_ci_size || fail 'genuine array size failed'
[ "$context_ci_size" -eq 2 ] || fail 'genuine array result incorrect'

# Repeating selection cannot accumulate context PATH entries.
selected_path=$PATH
selected_concretes=${m_CONTEXT_PACKAGES-}
context 'pkg=m-core@v0.1.0' 'pkg=m-term@v0.1.0' 'pkg=m-rsudo@v0.1.0' ||
  fail 'idempotent selection failed'
[ "$PATH" = "$selected_path" ] && [ "${m_CONTEXT_PACKAGES-}" = "$selected_concretes" ] ||
  fail 'repeated selection changed current context'

# Invalid mixed and missing selections must not mutate a working context.
if context 'pkg=m-core@v0.1.0' 'not-a-context-operand'; then
  fail 'invalid mixed selection was accepted'
fi
[ "$PATH" = "$selected_path" ] && [ "${m_CONTEXT_PACKAGES-}" = "$selected_concretes" ] ||
  fail 'invalid mixed selection changed current context'
if context 'pkg=m-core@never-published'; then
  fail 'missing concrete was accepted'
fi
[ "$PATH" = "$selected_path" ] && [ "${m_CONTEXT_PACKAGES-}" = "$selected_concretes" ] ||
  fail 'missing concrete changed current context'

# A child m shell must load and apply its own shell-local context function.
"$m_ROOT/m" sh -ec '
  . "$m_LIB_DIR/sys/sh/core.lib.sh"
  command -v context >/dev/null
  context "pkg=m-term@v0.1.0"
  [ "$(command -v menu)" = "$m_PKG_DIR/m-term@v0.1.0/link/bin/menu" ]
' || fail 'nested m shell cannot reinitialize/use context'

context || fail 'no-argument reset failed'
[ "$PATH" = "$initial_path" ] || fail 'reset did not restore host PATH'
[ "${CLASSPATH+x}" != x ] || fail 'reset did not preserve unset CLASSPATH'
[ -z "${m_CONTEXT_PACKAGES-}" ] || fail 'reset retained package selection'
printf '%s\n' 'PASS: genuine v2 package context, POSIX consumer, idempotence, failure atomicity, nested shell and reset'
