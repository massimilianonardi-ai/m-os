#!/bin/sh
# Two real v2 pkg integrations: consumer executable uses another package's
# context-selected POSIX library and m's own loadsyslib in the same process.
set -eu
[ -n "${m_ROOT-}" ] && [ -n "${m_LIB_DIR-}" ] && [ -n "${m_PKG_DIR-}" ] || exit 1
. "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 2
loadsyslib "pkg/pkg-integration" || exit 3

provider=context-sh-ci-provider
consumer=context-sh-ci-consumer
work=$(mktemp -d) || exit 4
for concrete in "$provider@1" "$provider@2" "$consumer@1"
do
  if [ -e "$m_PKG_DIR/$concrete" ] || [ -L "$m_PKG_DIR/$concrete" ]
  then
    printf 'ERROR: fixture already installed: %s\n' "$concrete" >&2
    command -p -- rm -rf -- "$work"
    exit 5
  fi
done
cleanup()
{
  context >/dev/null 2>&1 || :
  for concrete in "$provider@1" "$provider@2" "$consumer@1"
  do
    command -p -- rm -rf -- "$m_PKG_DIR/$concrete"
  done
  command -p -- rm -rf -- "$work"
}
trap cleanup 0
trap 'exit 130' HUP INT TERM
command -p -- mkdir -p -- "$m_PKG_DIR"

for version in 1 2
do
  range="$work/range/provider-$version"
  root="$work/root/provider-$version"
  command -p -- mkdir -p -- "$range/link/lib/sh" "$root/lib/sh"
  printf '%s\n' tar.gz > "$range/format"
  printf '%s\n' '../../../root/lib/sh/context-sh-ci-value.lib.sh' > "$range/link/lib/sh/context-sh-ci-value.lib.sh"
  cat > "$root/lib/sh/context-sh-ci-value.lib.sh" <<EOF_PROVIDER
context_sh_ci_value()
{
  printf '%s\\n' '$version'
}
EOF_PROVIDER
  pkg_integrate "$provider" "$version" "$range" "$root" "" v2 || exit 6
  [ -L "$m_PKG_DIR/$provider@$version/link/lib/sh/context-sh-ci-value.lib.sh" ] || exit 7
done

range="$work/range/consumer"
root="$work/root/consumer"
command -p -- mkdir -p -- "$range/link/bin" "$root/bin"
printf '%s\n' tar.gz > "$range/format"
printf '%s\n' '../../root/bin/context-sh-ci-probe' > "$range/link/bin/context-sh-ci-probe"
cat > "$root/bin/context-sh-ci-probe" <<'EOF_CONSUMER'
#!/bin/sh
set -eu
[ "$#" -eq 1 ] || exit 70
[ -n "${m_LIB_DIR-}" ] || exit 71
. "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 72
loadsyslib "pkg/pkg-common" || exit 73
pkg_concrete_read ci_pkg ci_version ci_osarch 'context-sh-ci-provider@1' || exit 74
[ "$ci_pkg" = context-sh-ci-provider ] && [ "$ci_version" = 1 ] || exit 75
. context-sh-ci-value.lib.sh || exit 76
[ "$(context_sh_ci_value)" = "$1" ] || exit 77
printf 'PASS: consumer read provider %s and system pkg-common\n' "$1"
EOF_CONSUMER
command -p -- chmod +x "$root/bin/context-sh-ci-probe"
pkg_integrate "$consumer" 1 "$range" "$root" "" v2 || exit 8
[ -L "$m_PKG_DIR/$consumer@1/link/bin/context-sh-ci-probe" ] || exit 9

baseline_path=$PATH
baseline_cp_set=${CLASSPATH+x}
baseline_cp=${CLASSPATH-}
context "pkg=$provider@1" "pkg=$consumer@1" || exit 10
[ "$(command -v context-sh-ci-probe)" = "$m_PKG_DIR/$consumer@1/link/bin/context-sh-ci-probe" ] || exit 11
context-sh-ci-probe 1 || exit 12
# A later version of provider replaces only that package's library view.
context "pkg=$provider@2" || exit 13
context-sh-ci-probe 2 || exit 14
selected_path=$PATH
context "pkg=$provider@2" || exit 15
[ "$PATH" = "$selected_path" ] || exit 16
# Failed resolution retains the effective selection and search paths.
if context pkg=context-sh-ci-absent@1; then exit 17; fi
[ "$PATH" = "$selected_path" ] || exit 18
context-sh-ci-probe 2 || exit 19
context || exit 20
[ "$PATH" = "$baseline_path" ] || exit 21
[ "${CLASSPATH+x}" = "$baseline_cp_set" ] && [ "${CLASSPATH-}" = "$baseline_cp" ] || exit 22
printf '%s\n' 'PASS: v2 context producer/consumer, core library, version switch, idempotence, failure preservation, reset'
