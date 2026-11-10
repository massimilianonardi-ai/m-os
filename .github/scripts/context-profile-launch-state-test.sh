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
[ -f "$inventory" ] && [ ! -L "$inventory" ] || exit 7
inventory_backup="$work/profile-inventory"
command -p -- cp -- "$inventory" "$inventory_backup" || exit 4

[ ! -e "$concrete" ] && [ ! -L "$concrete" ] || exit 5
[ ! -e "$selector" ] && [ ! -L "$selector" ] || exit 6
[ ! -e "$secondary" ] && [ ! -L "$secondary" ] || exit 8

cleanup()
{
  context >/dev/null 2>&1 || :
  pkg_default_apply "$name" "" >/dev/null 2>&1 || :
  command -p -- rm -f -- "$selector"
  command -p -- rm -rf -- "$concrete"
  command -p -- rm -rf -- "$m_ROOT/state/system/current/pkg/$name"
  command -p -- cp -- "$inventory_backup" "$inventory"
  command -p -- rm -rf -- "$work"
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
cat > "$range/env" <<'PACKAGE_ENV'
if [ "${CONTEXT_TEST_ATTACK-}" = 1 ]
then
  m_CONTEXT_PATH_PREFIX=/tmp/context-profile-attack
elif [ "${CONTEXT_TEST_ATTACK-}" = 2 ]
then
  m_CONTEXT_ENVELOPE=forged
fi
PACKAGE_ENV
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

_expect_invalid_envelope()
{
  [ "$#" -eq 1 ] || return 2
  m_CONTEXT_ENVELOPE=$1
  export m_CONTEXT_ENVELOPE
  if ./m osarch show >"$work/envelope.out" 2>"$work/envelope.err"
  then
    return 1
  fi
  [ ! -s "$work/envelope.out" ] && [ -s "$work/envelope.err" ]
}

current_target=$(command -p -- readlink -- "$m_ROOT/state/system/current") || exit 10
if output=$(CONTEXT_TEST_ATTACK=2 ./m "$concrete/cmd/runner" 2>"$work/no-context-attack.err")
then
  exit 21
fi
[ -z "$output" ] || exit 22
[ -s "$work/no-context-attack.err" ] || exit 23

context system=main pkg="$name@1" || exit 11
[ "$(./m runner)" = launch-ok ] || exit 12

before_path=$PATH
before_state_root=$m_STATE_SYS_DIR
before_context_envelope=$m_CONTEXT_ENVELOPE
command -p cp -- "$inventory" "$work/inventory.saved"
printf '%s\n' invalid-inventory > "$inventory"
if context >"$work/inventory.out" 2>"$work/inventory.err"
then
  exit 34
else
  inventory_status=$?
fi
[ "$inventory_status" -eq 24 ] || exit 35
[ "$PATH" = "$before_path" ] || exit 36
[ "$m_STATE_SYS_DIR" = "$before_state_root" ] || exit 37
[ "$m_CONTEXT_ENVELOPE" = "$before_context_envelope" ] || exit 38
[ -s "$work/inventory.err" ] || exit 39
command -p cp -- "$work/inventory.saved" "$inventory"

if output=$(CONTEXT_TEST_ATTACK=1 ./m runner 2>"$work/attack.err")
then
  exit 18
fi
[ -z "$output" ] || exit 19
[ -s "$work/attack.err" ] || exit 20

saved_envelope=$m_CONTEXT_ENVELOPE
test_uid=$(command -p id -u)
valid_envelope=$(printf '%s\n' m-context-envelope-v1 "root=$m_ROOT" "uid=$test_uid" system=main classpath-host-set=0 "package=$name@1")
if ! _expect_invalid_envelope "$(printf '%s\n' m-context-envelope-v99 "root=$m_ROOT" "uid=$test_uid" system=main classpath-host-set=0 "package=$name@1")"
then
  exit 25
fi
if ! _expect_invalid_envelope "$(printf '%s\n' "$valid_envelope" "root=$m_ROOT")"
then
  exit 26
fi
case "$test_uid" in 0) invalid_uid=1 ;; *) invalid_uid=0 ;; esac
if ! _expect_invalid_envelope "$(printf '%s\n' m-context-envelope-v1 "root=$m_ROOT" "uid=$invalid_uid" system=main classpath-host-set=0 "package=$name@1")"
then
  exit 27
fi
if ! _expect_invalid_envelope "$(printf '%s\n' m-context-envelope-v1 "root=$m_ROOT" "uid=$test_uid" system=unmanaged classpath-host-set=0 "package=$name@1")"
then
  exit 28
fi
if ! _expect_invalid_envelope "$(printf '%s\n' m-context-envelope-v1 "root=$m_ROOT" "uid=$test_uid" system=main classpath-host-set=0 package=not-installed@1)"
then
  exit 29
fi
if ! _expect_invalid_envelope "$(printf '%s\n\n' "$valid_envelope" extra=value)"
then
  exit 30
fi
if ! _expect_invalid_envelope "$(printf '%s\r' "$valid_envelope")"
then
  exit 31
fi
oversized_envelope=$(command -p awk 'BEGIN { for (i = 0; i < 17000; i++) printf "x" }') || exit 32
if ! _expect_invalid_envelope "$oversized_envelope"
then
  exit 33
fi
m_CONTEXT_ENVELOPE=$saved_envelope
export m_CONTEXT_ENVELOPE

context system=secondary pkg="$name@1" || exit 13
expected_context_state="$m_ROOT/state/system/profile/secondary/sys/environment/cache"
[ "$(./m state-path system sys environment cache)" = "$expected_context_state" ] || exit 24
if output=$(./m runner 2>"$work/launch.err")
then
  exit 14
fi
[ -z "$output" ] || exit 15
[ -s "$work/launch.err" ] || exit 16
[ "$(command -p -- readlink -- "$m_ROOT/state/system/current")" = "$current_target" ] || exit 17

printf '%s\n' 'PASS: package var launcher is rejected when context profile differs from system/current'
