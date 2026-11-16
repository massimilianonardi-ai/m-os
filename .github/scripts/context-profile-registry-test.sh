#!/bin/sh
set -eu

[ -n "${m_ROOT-}" ] || exit 1
. "$m_LIB_DIR/sys/sh/core.lib.sh"
loadsyslib "base"
loadsyslib "context-store"
loadsyslib "context-profile-registry"

work="$m_ROOT/.tmp/context-profile-registry-test.$$"
root="$work/install"
profiles="$root/state/system/profile"
registry="$profiles/.inventory"
cleanup() { command -p rm -rf "$work"; }
trap cleanup 0
trap 'exit 130' HUP INT TERM

command -p mkdir -p "$profiles/main" "$profiles/secondary"
command -p chmod 755 "$root" "$root/state" "$root/state/system" "$profiles" "$profiles/main" "$profiles/secondary"
write_valid()
{
  cat > "$registry" <<'RECORD'
m-system-profile-inventory-v1
baseline=main
profile=main
profile=secondary
RECORD
  command -p chmod 644 "$registry"
}
expect_invalid()
{
  if _context_profile_registry_read "$root"
  then
    echo "unexpectedly accepted invalid registry: $1" >&2
    exit 2
  fi
}

write_valid
_context_profile_registry_read "$root" || exit 3
[ "$CONTEXT_PROFILE_REGISTRY_BASELINE" = main ] || exit 4
[ "$CONTEXT_PROFILE_REGISTRY_IDENTITIES" = "$(printf 'main\nsecondary')" ] || exit 5

# The file is data, never shell input; unsupported records fail closed.
printf '%s\n' 'm-system-profile-inventory-v1' 'baseline=main' 'baseline=main' 'profile=main' > "$registry"
expect_invalid 'duplicate baseline'
write_valid
sed 's/profile=secondary/profile=main/' "$registry" > "$work/rewrite"
cat "$work/rewrite" > "$registry"
expect_invalid 'duplicate identity'
write_valid
sed 's/baseline=main/baseline=missing/' "$registry" > "$work/rewrite"
cat "$work/rewrite" > "$registry"
expect_invalid 'baseline absent from identities'
write_valid
printf '%s\n' 'm-system-profile-inventory-v1' 'baseline=main' 'profile=main' 'unknown=value' > "$registry"
expect_invalid 'unknown record'
write_valid
printf '%s\n' 'm-system-profile-inventory-v1' 'baseline=main' 'profile=main' '' > "$registry"
expect_invalid 'blank record'
write_valid
printf '%s\n' 'm-system-profile-inventory-v1' 'baseline=../outside' 'profile=main' > "$registry"
expect_invalid 'path traversal identity'
write_valid
printf '%s\r\n' 'm-system-profile-inventory-v1' 'baseline=main' 'profile=main' > "$registry"
expect_invalid 'CRLF records'
write_valid
printf '%s\n' 'm-system-profile-inventory-v1' 'baseline=main' 'profile=main' > "$registry"
command -p chmod 664 "$registry"
expect_invalid 'group-writable registry'
write_valid
LC_ALL=C awk 'BEGIN { for (i = 0; i < 17000; i++) printf "x" }' > "$registry"
expect_invalid 'oversized registry'
write_valid
command -p chmod 775 "$profiles"
expect_invalid 'group-writable profile parent'
command -p chmod 755 "$profiles"
command -p rm -rf "$profiles/secondary"
command -p ln -s "$profiles/main" "$profiles/secondary"
write_valid
expect_invalid 'symlinked profile directory'
command -p rm "$profiles/secondary"
command -p mkdir -m 755 "$profiles/secondary"
command -p rm "$registry"
command -p ln -s "$work/missing" "$registry"
expect_invalid 'symlinked registry'
command -p rm "$registry"
write_valid
command -p rm "$registry"
expect_invalid 'missing registry'

printf '%s\n' 'PASS: installation-managed profile registry baseline, identity, ownership, mode and hostile-input checks'
