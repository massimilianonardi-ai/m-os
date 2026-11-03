#!/bin/sh
# Verify that a v1 installed concrete and a real v2 concrete can be used
# together in the same shell-local context; leave installed defaults intact.
set -eu
[ -n "${m_ROOT-}" ] && [ -n "${m_LIB_DIR-}" ] && [ -n "${CONCRETE-}" ] || exit 1
. "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 2
loadsyslib "pkg/pkg-integration" || exit 3

case "$CONCRETE" in jq@jq-1.8.2!*) : ;; *) exit 4 ;; esac
[ -d "$m_PKG_DIR/$CONCRETE" ] && [ -f "$m_PKG_DIR/$CONCRETE/schema" ] || exit 5
[ "$(command -p -- cat -- "$m_PKG_DIR/$CONCRETE/schema")" = v2 ] || exit 6

work=$(mktemp -d) || exit 7
legacy="$m_PKG_DIR/context-ci-v1@1"
cleanup()
{
  command -p -- rm -rf -- "$legacy" "$work"
}
[ ! -e "$legacy" ] && [ ! -L "$legacy" ] || exit 8
trap cleanup 0

range="$work/range"
root="$work/root"
command -p -- mkdir -p "$range/cmd" "$range/link" "$root/bin" || exit 9
printf 'tar.gz\n' > "$range/format"
printf 'bin/ci-v1\n' > "$range/link/ci-v1"
cat > "$range/cmd/ci-v1" <<'WRAPPER'
#!/bin/sh
. "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 2
loadsyslib "pkg/pkg-launch" || exit 3
launcher context-ci-v1 "$@"
WRAPPER
printf '#!/bin/sh\nprintf "v1\n"\n' > "$root/bin/ci-v1"
command -p -- chmod +x "$root/bin/ci-v1" || exit 10
pkg_integrate context-ci-v1 1 "$range" "$root" || exit 11

[ -f "$legacy/cmd/ci-v1" ] && [ ! -e "$legacy/schema" ] || exit 12
[ -L "$legacy/link/ci-v1" ] || exit 13

baseline=$PATH
context "pkg=$CONCRETE" "pkg=context-ci-v1@1" || exit 14
[ "$(command -v jq)" = "$m_PKG_DIR/$CONCRETE/link/bin/jq" ] || exit 15
[ "$(command -v jq-wrapped)" = "$m_PKG_DIR/$CONCRETE/link/bin/jq-wrapped" ] || exit 16
[ "$(command -v ci-v1)" = "$legacy/cmd/ci-v1" ] || exit 17
[ "$(jq -n '6*7')" = 42 ] || exit 18
[ "$(jq-wrapped '6*7')" = 42 ] || exit 19
[ "$(ci-v1)" = v1 ] || exit 20

# Most-recent-first precedence spans both v1 cmd and v2 link/bin views.
# Re-selecting the earlier concrete moves it to the front without
# discarding the other selection or duplicating PATH contributions.
[ "${PATH%%:*}" = "$legacy/cmd" ] || exit 23
context "pkg=$CONCRETE" || exit 24
[ "${PATH%%:*}" = "$m_PKG_DIR/$CONCRETE/link/bin" ] || exit 25
[ "$(command -v ci-v1)" = "$legacy/cmd/ci-v1" ] || exit 26
[ "$(jq -n '6*7')" = 42 ] || exit 27
before_reapply=$PATH
context "pkg=$CONCRETE" || exit 28
[ "$PATH" = "$before_reapply" ] || exit 29

context || exit 21
[ "$PATH" = "$baseline" ] || exit 22
printf '%s\n' 'PASS: v1 + v2 installed views, context selection and reset'
