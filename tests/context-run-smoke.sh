#!/bin/sh
set -eu

[ "$#" -eq 1 ] || { printf '%s\n' 'usage: sh tests/context-run-smoke.sh <context-run-command>' >&2; exit 2; }
command_path=$1
[ -f "$command_path" ] || exit 2

work=$(mktemp -d "${TMPDIR:-/tmp}/m-context-run.XXXXXXXX") || exit 3
trap 'command -p -- rm -rf -- "$work"' 0
trap 'exit 130' HUP INT TERM
command -p -- mkdir -p -- "$work/lib/sys/sh"
cat > "$work/lib/sys/sh/core.lib.sh" <<'EOF_CORE'
context() {
  printf '%s\n' "$@" > "$CONTEXT_RUN_TEST_SELECTORS"
  CONTEXT_RUN_TEST_ACTIVE=yes
  export CONTEXT_RUN_TEST_ACTIVE
}
loadsyslib() { :; }
_pkg_facility_name_valid() { [ "$1" = node ]; }
_pkg_dependency_constraint_parse() { [ "$1" = '>=26' ]; }
pkg_provider_selector_resolve() { printf '%s\n' "$1"; }
_pkg_dependency_provider_satisfies() { [ "$1" = node@v26 ] && [ "$2" = node ] && [ "$3" = '>=26' ]; }
pkg_dependency_default_resolve() { printf '%s\n' default-node; }
EOF_CORE
cat > "$work/m" <<'EOF_M'
#!/bin/sh
exec "$@"
EOF_M
chmod 700 "$work/m"
m_ROOT=$work
m_LIB_DIR=$work/lib
CONTEXT_RUN_TEST_SELECTORS=$work/selectors
export m_ROOT m_LIB_DIR CONTEXT_RUN_TEST_SELECTORS

sh "$command_path" full-context=development pkg=nodejs@v26 -- \
  sh -c '[ "$CONTEXT_RUN_TEST_ACTIVE" = yes ] && [ "$1" = "argument with spaces" ]' \
  sh 'argument with spaces'
[ "$(command -p -- cat "$work/selectors")" = "$(printf 'full-context=development\npkg=nodejs@v26')" ] || exit 4
[ "${CONTEXT_RUN_TEST_ACTIVE-}" != yes ] || exit 5
[ "$(sh "$command_path" --resolve node '>=26')" = default-node ] || exit 6
m_CONTEXT_PROVIDER_PINS='provider.node=node@v26'
export m_CONTEXT_PROVIDER_PINS
[ "$(sh "$command_path" --resolve node '>=26')" = node@v26 ] || exit 7
if sh "$command_path" invalid-selector -- true >/dev/null 2>&1; then exit 8; fi
if sh "$command_path" pkg=nodejs@v26 true >/dev/null 2>&1; then exit 9; fi
if sh "$command_path" --resolve node invalid >/dev/null 2>&1; then exit 10; fi
printf '%s\n' 'PASS: context-run isolated activation, arguments, pinned/default resolution, errors'
