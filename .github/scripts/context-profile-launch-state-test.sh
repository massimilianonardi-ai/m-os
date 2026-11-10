#!/bin/sh
# A context-selected profile must not reuse package var state bound to system/current.
set -eu
[ -n "${m_ROOT-}" ] && [ -n "${m_LIB_DIR-}" ] || exit 1
. "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 2
loadsyslib "pkg/pkg-integration" || exit 3

name=context-profile-state-probe
concrete="$m_PKG_DIR/$name@1"
profiles="$m_ROOT/state/system/profile"
inventory="$profiles/.inventory"
secondary="$profiles/secondary"
selector="$m_PKG_DIR/$name"
work_parent="$m_ROOT/.tmp"
command -p -- mkdir -p -- "$work_parent" || exit 4
work=$(command -p -- mktemp -d "$work_parent/context-profile-launch.XXXXXX") || exit 4

[ ! -e "$concrete" ] && [ ! -L "$concrete" ] || exit 5
[ ! -e "$selector" ] && [ ! -L "$selector" ] || exit 6
[ ! -e "$inventory" ] && [ ! -L "$inventory" ] || exit 7
[ ! -e "$secondary" ] && [ ! -L "$secondary" ] || exit 8

cleanup()
{
  context >/dev/null 2>&1 || :
  pkg_default_apply "$name" "" >/dev/null 2>&1 || :
  command -p -- rm -f -- "$selector"
  command -p -- rm -rf -- "$concrete" "$work"
  command -p -- rm -rf -- "$m_ROOT/state/system/current/pkg/$name"
  command -p -- rm -f -- "$inventory"
  command -p -- rmdir -- "$secondary" 2>/dev/null || :
}
trap cleanup 0
trap 'exit 130' HUP INT TERM

command -p -- mkdir -- "$secondary"
command -p -- chmod 755 -- "$secondary"
printf '%s\n' m-system-profile-inventory-v1 baseline=main profile=main profile=secondary > "$inventory"
command -p -- chmod 644 -- "$inventory"

range="$work/range"
root="$work/root"
command -p -- mkdir -p -- "$range/cmd" "$range/link" "$range/var" "$root/bin"
printf '%s\n' tar.gz > "$range/format"
printf '%s\n' config.txt > "$range/var/data"
printf '%s\n' factory > "$root/config.txt"
cat > "$range/cmd/runner" <<'WRAPPER'
#!/bin/sh
. "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 2
loadsyslib "pkg/pkg-launch" || exit 3
launcher context-profile-state-probe "$@"
WRAPPER
printf '%s\n' '#!/bin/sh' 'printf "launch-ok\n"' > "$root/bin/runner"
command -p -- chmod +x -- "$root/bin/runner"
printf '%s\n' bin/runner > "$range/link/runner"
pkg_integrate "$name" 1 "$range" "$root" || exit 9

current_target=$(command -p -- readlink -- "$m_ROOT/state/system/current") || exit 10
context system=main pkg="$name@1" || exit 11
[ "$(./m runner)" = launch-ok ] || exit 12

context system=secondary pkg="$name@1" || exit 13
if output=$(./m runner 2>"$work/launch.err")
then
  exit 14
fi
[ -z "$output" ] || exit 15
[ -s "$work/launch.err" ] || exit 16
[ "$(command -p -- readlink -- "$m_ROOT/state/system/current")" = "$current_target" ] || exit 17

printf '%s\n' 'PASS: package var launcher is rejected when context profile differs from system/current'
