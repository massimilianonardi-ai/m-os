#!/bin/sh
set -eu

[ -n "${m_ROOT-}" ] && [ -n "${m_LIB_DIR-}" ] || exit 1
. "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 2
loadsyslib "context-profile-registry" || exit 3

selector="$m_ROOT/state/system/current"
profiles="$m_ROOT/state/system/profile"
inventory="$profiles/.inventory"
[ -L "$selector" ] || exit 4
saved_target=$(command -p -- readlink -- "$selector") || exit 5
[ -f "$inventory" ] && [ ! -L "$inventory" ] || exit 6

work="$m_ROOT/.tmp/state-selector-security.$$"
outside="$work/outside"
marker="$work/external-env-was-sourced"
profile_id="state-selector-test.$$"
profile="$profiles/$profile_id"
profile_link_id="state-selector-link.$$"
profile_link="$profiles/$profile_link_id"
inventory_backup="$work/profile-inventory.saved"

[ ! -e "$work" ] && [ ! -L "$work" ] || exit 7
command -p -- mkdir -p -- "$outside/sys/environment/cache" "$work" || exit 8
[ ! -e "$profile" ] && [ ! -L "$profile" ] || {
  command -p -- rm -rf -- "$work" 2>/dev/null || :
  exit 10
}
[ ! -e "$profile_link" ] && [ ! -L "$profile_link" ] || {
  command -p -- rm -rf -- "$work" 2>/dev/null || :
  exit 11
}
if ! command -p -- cp -p -- "$inventory" "$inventory_backup"
then
  command -p -- rm -rf -- "$work" 2>/dev/null || :
  exit 12
fi

cleanup()
{
  if [ -e "$selector" ] || [ -L "$selector" ]
  then
    command -p -- rm -f -- "$selector" || :
  fi
  command -p -- ln -s -- "$saved_target" "$selector" 2>/dev/null || :
  command -p -- cp -p -- "$inventory_backup" "$inventory" 2>/dev/null || :
  command -p -- rm -f -- "$profile_link" 2>/dev/null || :
  command -p -- rm -rf -- "$profile" "$work" 2>/dev/null || :
}
trap cleanup 0
trap 'exit 130' HUP INT TERM

printf '%s\n' ': > "$M_TEST_MARKER"' > "$outside/sys/environment/cache/env"
M_TEST_MARKER=$marker
export M_TEST_MARKER

# A real but unregistered profile and a profile symlink cannot be selected by
# context. A registry entry that names the symlink invalidates the registry.
command -p -- mkdir -- "$profile" || exit 13
command -p -- ln -s -- "$outside" "$profile_link" || exit 14
context_profile_before=$m_STATE_SYS_DIR
context_envelope_before=$m_CONTEXT_ENVELOPE
if context "system=$profile_id"
then
  exit 15
else
  status=$?
fi
[ "$status" -eq 23 ] || exit 16
[ "$m_STATE_SYS_DIR" = "$context_profile_before" ] && \
  [ "$m_CONTEXT_ENVELOPE" = "$context_envelope_before" ] || exit 17

if context "system=$profile_link_id"
then
  exit 18
else
  status=$?
fi
[ "$status" -eq 23 ] || exit 19
[ "$m_STATE_SYS_DIR" = "$context_profile_before" ] && \
  [ "$m_CONTEXT_ENVELOPE" = "$context_envelope_before" ] || exit 20

printf 'profile=%s\n' "$profile_link_id" >> "$inventory"
if context "system=$profile_link_id"
then
  exit 21
else
  status=$?
fi
[ "$status" -eq 24 ] || exit 22
[ "$m_STATE_SYS_DIR" = "$context_profile_before" ] && \
  [ "$m_CONTEXT_ENVELOPE" = "$context_envelope_before" ] || exit 23
command -p -- cp -p -- "$inventory_backup" "$inventory" || exit 24

# Corrupting the legacy global selector must not redirect the process context,
# the public state-path resolver, or fresh bootstrap environment sourcing.
command -p -- rm -f -- "$selector" || exit 25
command -p -- ln -s -- "$outside" "$selector" || exit 26
context
selected_profile=$m_STATE_SYS_DIR
selected_identity=$m_CONTEXT_SYSTEM_PROFILE
expected_state_path="$selected_profile/sys/probe/data"
[ "$("$m_ROOT/bin/sys/state-path" system sys probe data)" = "$expected_state_path" ] || exit 27

expected_fresh_path="$selected_profile/sys/probe/data"
fresh_path=$(command -p env -i PATH="$PATH" M_TEST_MARKER="$marker" \
  "$m_ROOT/m" state-path system sys probe data) || exit 28
[ "$fresh_path" = "$expected_fresh_path" ] || exit 29
command -p env -i PATH="$PATH" M_TEST_MARKER="$marker" "$m_ROOT/m" true || exit 30
[ ! -e "$marker" ] || exit 31
[ "$(command -p -- readlink -- "$selector")" = "$outside" ] || exit 32
[ "$m_STATE_SYS_DIR" = "$selected_profile" ] && \
  [ "$m_CONTEXT_SYSTEM_PROFILE" = "$selected_identity" ] || exit 33

printf '%s\n' 'PASS: current is legacy; context and state-path ignore it and reject unregistered/symlinked profiles'
