#!/bin/sh
# v2 service entrypoint contract test; not a full srv process-lifecycle test.
set -eu
[ -n "${m_ROOT-}" ] && [ -n "${CATALOG_V2-}" ] || exit 1
. "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 2
loadsyslib "pkg/pkg-integration" || exit 3

work=$(mktemp -d) || exit 4
name=facility-ci-ollama-v2
concrete="$m_PKG_DIR/$name@1"
[ ! -e "$concrete" ] && [ ! -L "$concrete" ] || exit 5
trap 'command -p -- rm -rf -- "$concrete" "$work"' 0
command -p -- mkdir -p "$m_PKG_DIR" "$work/catalog/v2/pkg/$name/all" \
  "$work/catalog/v2/facility" "$work/root/bin" || exit 6
command -p -- cp -R "$CATALOG_V2/facility/ollama" "$work/catalog/v2/facility/ollama" || exit 7
range="$work/catalog/v2/pkg/$name/all/n0001=1"
command -p -- mkdir -p "$range/cmd" "$range/link/bin" \
  "$range/link/target" "$range/facility-service/ollama" || exit 8
printf 'tar.gz\n' > "$range/format"
printf 'ollama 1\n' > "$range/facility"
printf 'ollama-serve\n' > "$range/facility-service/ollama/start"
printf '../../cmd/ollama-serve\n' > "$range/link/bin/ollama-serve"
printf '../../root/bin/ollama\n' > "$range/link/target/ollama-serve"

cat > "$range/cmd/ollama-serve" <<'WRAPPER'
#!/bin/sh
. "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 2
loadsyslib "pkg/pkg-launch" || exit 3
launcher facility-ci-ollama-v2 serve "$@"
WRAPPER

cat > "$work/root/bin/ollama" <<'EXECUTABLE'
#!/bin/sh
printf '%s\n' "$1"
EXECUTABLE
command -p -- chmod +x "$work/root/bin/ollama" || exit 9

pkg_facility_provider_validate "$work/catalog/v2" "$range" "$work/root" || exit 10
pkg_integrate "$name" 1 "$range" "$work/root" "" v2 "$work/catalog/v2" || exit 11
service_path="$(pkg_facility_service_start_resolve ollama "$name@1")" || exit 12
[ "$service_path" = "$concrete/link/bin/ollama-serve" ] || exit 13
[ "$(command -p -- readlink "$service_path")" = ../../cmd/ollama-serve ] || exit 14
[ "$("$m_ROOT/m" "$service_path")" = serve ] || exit 15

command -p -- rm -f "$range/link/bin/ollama-serve" || exit 16
if pkg_facility_provider_validate "$work/catalog/v2" "$range" "$concrete/root"
then
  exit 17
fi
printf '%s\n' 'PASS: v2 service contract, provider binding and exact link/bin start'
