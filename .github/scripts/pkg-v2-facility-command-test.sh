#!/bin/sh
# Validate one real v2 contract against a fixture provider binary directory.
set -eu
[ -n "${m_ROOT-}" ] && [ -n "${m_LIB_DIR-}" ] && [ -n "${CATALOG_V2-}" ] || exit 1
. "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 2
loadsyslib "pkg/pkg-integration" || exit 3

work=$(mktemp -d) || exit 4
name=facility-ci-node-v2
concrete="$m_PKG_DIR/$name@1"
cleanup()
{
  command -p -- rm -rf -- "$concrete" "$work"
}
[ ! -e "$concrete" ] && [ ! -L "$concrete" ] || exit 5
trap cleanup 0
command -p -- mkdir -p -- "$m_PKG_DIR" "$work/catalog/v2/pkg/$name/all" \
  "$work/catalog/v2/facility" "$work/root/bin" || exit 6
command -p -- cp -R -- "$CATALOG_V2/facility/nodejs" "$work/catalog/v2/facility/nodejs" || exit 7
range="$work/catalog/v2/pkg/$name/all/n0001=1"
command -p -- mkdir -p -- "$range/facility-bin" || exit 8
printf 'tar.gz\n' > "$range/format"
printf 'nodejs 26\n' > "$range/facility"
printf 'bin\n' > "$range/facility-bin/nodejs"
cat > "$work/root/bin/node" <<'EXE'
#!/bin/sh
printf 'fixture-node-v2\n'
EXE
command -p -- chmod +x "$work/root/bin/node" || exit 9

pkg_facility_provider_validate "$work/catalog/v2" "$range" "$work/root" || exit 10
pkg_integrate "$name" 1 "$range" "$work/root" "" v2 "$work/catalog/v2" || exit 11
[ "$(command -p -- cat -- "$concrete/schema")" = v2 ] || exit 12
[ "$(command -p -- readlink "$concrete/link/bin/node")" = "../../root/bin/node" ] || exit 13
[ "$(command -p -- readlink "$concrete/facility-cmd/nodejs/node")" = "../../link/bin/node" ] || exit 14
[ "$("$concrete/link/bin/node")" = fixture-node-v2 ] || exit 15
[ "$("$concrete/facility-cmd/nodejs/node")" = fixture-node-v2 ] || exit 16

command -p -- rm -f -- "$concrete/root/bin/node" || exit 17
if pkg_facility_provider_validate "$work/catalog/v2" "$range" "$concrete/root"
then
  exit 18
fi

printf '%s\n' 'PASS: v2 central facility command contract and provider bin parameter'
