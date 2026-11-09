#!/bin/sh
set -eu

[ -n "${m_ROOT-}" ] && [ -n "${m_LIB_DIR-}" ] || exit 1
. "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 2
loadsyslib "pkg/pkg-integration" || exit 3
valid_dir "$m_PKG_DIR" || exit 24

selector=$m_STATE_SYS_DIR
[ -L "$selector" ] || exit 4
saved_target=$(command -p -- readlink -- "$selector") || exit 5
_m_system_state_selector_validate || exit 6

work="$m_ROOT/.tmp/state-selector-security.$$"
outside="$work/outside"
range="$work/range"
concrete="$work/state-selector-probe@1"
rejected_root="$work/rejected-root"
marker="$work/external-env-was-sourced"
profiles="$m_ROOT/state/system/profile"
profile_id="state-selector-test.$$"
profile="$profiles/$profile_id"
profile_link="$profiles/state-selector-link.$$"

cleanup()
{
  if [ -e "$selector" ] || [ -L "$selector" ]
  then
    command -p -- rm -f -- "$selector" || :
  fi
  command -p -- ln -s -- "$saved_target" "$selector" 2>/dev/null || :
  command -p -- rm -f -- "$profile_link" 2>/dev/null || :
  command -p -- rm -rf -- "$profile" 2>/dev/null || :
  command -p -- rm -rf -- "$work" 2>/dev/null || :
}
trap cleanup 0
trap 'exit 130' HUP INT TERM

command -p -- mkdir -p -- "$outside/sys/environment/cache" "$range/var" "$concrete/root" "$rejected_root"
printf '%s\n' tar.gz > "$range/format"
printf '%s\n' config.txt > "$range/var/data"
printf '%s\n' fixture > "$concrete/root/config.txt"
printf '%s\n' fixture > "$rejected_root/config.txt"
printf '%s\n' ': > "$M_TEST_MARKER"' > "$outside/sys/environment/cache/env"
M_TEST_MARKER=$marker
export M_TEST_MARKER

# A direct relative selector to a real profile remains valid and package state
# materializes inside that selected profile.
command -p -- mkdir -- "$profile"
command -p -- rm -f -- "$selector"
command -p -- ln -s -- "profile/$profile_id" "$selector"
_m_system_state_selector_validate || exit 16
_pkg_state_materialize "$range" "$concrete" state-selector-probe || exit 17
[ -f "$profile/pkg/state-selector-probe/data/config.txt" ] || exit 18

# A package state declaration must be rejected before it creates anything
# through an absolute system/current link.
command -p -- rm -f -- "$selector"
command -p -- ln -s -- "$outside" "$selector"
if pkg_integrate state-selector-probe 1 "$range" "$rejected_root"
then
  exit 7
else
  status=$?
fi
[ "$status" -eq 10 ] || exit 25
[ ! -e "$outside/pkg/state-selector-probe/data/config.txt" ] || exit 8
[ ! -e "$m_PKG_DIR/state-selector-probe@1" ] && [ -f "$rejected_root/config.txt" ] || exit 26

# The public resolver preserves its side-effect-free contract while rejecting
# a malformed existing system selector with status 3 and no pathname output.
if "$m_ROOT/bin/sys/state-path" system pkg state-selector-probe data > "$work/state-path.out" 2> "$work/state-path.err"
then
  exit 9
else
  status=$?
fi
[ "$status" -eq 3 ] || exit 10
[ ! -s "$work/state-path.out" ] && [ -s "$work/state-path.err" ] || exit 11

# Other direct consumers of the system selector must reject it as well, even
# when invoked from a shell that bootstrapped before the selector was changed.
if "$m_ROOT/bin/sys/osarch" update > "$work/osarch.out" 2> "$work/osarch.err"
then
  exit 20
else
  status=$?
fi
[ "$status" -ne 0 ] && [ -s "$work/osarch.err" ] || exit 21
pkg_provider_global_environment_materialize && exit 22
[ ! -e "$outside/sys/environment/cache/.env-stage-$$" ] || exit 23

# Bootstrap must fail before sourcing an env file reachable only through the
# malformed selector.
if "$m_ROOT/m" true > "$work/bootstrap.out" 2> "$work/bootstrap.err"
then
  exit 12
else
  status=$?
fi
[ "$status" -ne 0 ] || exit 13
[ ! -e "$marker" ] || exit 14
[ ! -s "$work/bootstrap.out" ] && [ -s "$work/bootstrap.err" ] || exit 15

# A canonical-looking link is still rejected when its profile entry is itself
# a symlink; the inventory target must be a real directory.
command -p -- ln -s -- "$outside" "$profile_link"
command -p -- rm -f -- "$selector"
command -p -- ln -s -- "profile/${profile_link##*/}" "$selector"
if _m_system_state_selector_validate
then
  exit 19
fi

printf '%s\n' 'PASS: malformed system selector rejected before state writes or bootstrap environment sourcing'
