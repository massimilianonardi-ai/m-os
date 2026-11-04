#!/bin/sh
# Exercise real v1/v2 consumers sharing a mutable provider binding/default.
# The external node binaries are disposable fixture payloads, not a download.
set -eu
[ -n "${m_ROOT-}" ] && [ -n "${m_LIB_DIR-}" ] && [ -n "${CATALOG_V2-}" ] || exit 1
. "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 2
loadsyslib "pkg/pkg-integration" || exit 3

consumer=ci-mixed-provider-consumer
provider=ci-mixed-node-provider
consumer_v1="$m_PKG_DIR/$consumer@1"
consumer_v2="$m_PKG_DIR/$consumer@2"
provider_v1="$m_PKG_DIR/$provider@1"
provider_v2="$m_PKG_DIR/$provider@2"
work=$(mktemp -d) || exit 4

# Refuse conflicts before installing a cleanup handler.
for path in "$consumer_v1" "$consumer_v2" "$provider_v1" "$provider_v2" \
  "$m_PKG_DIR/$consumer" "$m_PKG_DIR/$provider" \
  "$m_BIN_EXT_DIR/$consumer" "$m_BIN_EXT_DIR/node"
do
  if [ -e "$path" ] || [ -L "$path" ]
  then
    printf 'INFRASTRUCTURE: existing fixture path: %s\n' "$path" >&2
    command -p -- rm -rf -- "$work"
    exit 5
  fi
done
if "$m_ROOT/m" pkg provider default nodejs >/dev/null 2>&1 ||
   "$m_ROOT/m" pkg provider bind "$consumer" nodejs >/dev/null 2>&1
then
  command -p -- rm -rf -- "$work"
  printf '%s\n' 'INFRASTRUCTURE: existing provider selector would be replaced' >&2
  exit 6
fi

default_set=0
binding_set=0
package_default_set=0
cleanup()
{
  if [ "$binding_set" -eq 1 ]
  then
    "$m_ROOT/m" pkg provider bind -u "$consumer" nodejs >/dev/null 2>&1 || :
  fi
  if [ "$default_set" -eq 1 ]
  then
    "$m_ROOT/m" pkg provider default -u nodejs >/dev/null 2>&1 || :
  fi
  if [ "$package_default_set" -eq 1 ]
  then
    "$m_ROOT/m" pkg default -u "$consumer" >/dev/null 2>&1 || :
  fi
  command -p -- rm -rf -- "$consumer_v1" "$consumer_v2" \
    "$provider_v1" "$provider_v2" "$work"
}
trap cleanup 0

catalog="$work/catalog/v2"
command -p -- mkdir -p -- "$m_PKG_DIR" "$catalog/facility" || exit 7
command -p -- cp -R -- "$CATALOG_V2/facility/nodejs" "$catalog/facility/nodejs" || exit 8

# Two installed v2 providers implement the exact same central nodejs level.
for version in 1 2
do
  range="$catalog/pkg/$provider/all/n000$version=$version"
  root="$work/root-provider-$version"
  command -p -- mkdir -p -- "$range/facility-bin" "$root/bin" || exit 9
  printf 'tar.gz\n' > "$range/format"
  printf 'nodejs 26\n' > "$range/facility"
  printf 'bin\n' > "$range/facility-bin/nodejs"
  printf '#!/bin/sh\nprintf "provider-%s\\n"\n' "$version" > "$root/bin/node"
  command -p -- chmod +x "$root/bin/node" || exit 10
  pkg_facility_provider_validate "$catalog" "$range" "$root" || exit 11
  pkg_integrate "$provider" "$version" "$range" "$root" "" v2 "$catalog" || exit 12
done

# A v1 consumer and a v2 consumer have the same package identity,
# both declaring a facility dependency resolved at launch, not install.
range_v1="$work/consumer-v1"
root_v1="$work/root-consumer-v1"
range_v2="$work/consumer-v2"
root_v2="$work/root-consumer-v2"
command -p -- mkdir -p -- "$range_v1/cmd" "$range_v1/link" \
  "$root_v1/bin" "$range_v2/cmd" "$range_v2/link/bin" \
  "$range_v2/link/target" "$root_v2/bin" || exit 13
printf 'tar.gz\n' > "$range_v1/format"
printf 'nodejs =26\n' > "$range_v1/dependency"
printf 'bin/%s\n' "$consumer" > "$range_v1/link/$consumer"
cat > "$range_v1/cmd/$consumer" <<'V1_WRAPPER'
#!/bin/sh
. "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 2
loadsyslib "pkg/pkg-launch" || exit 3
launcher ci-mixed-provider-consumer "$@"
V1_WRAPPER
cat > "$root_v1/bin/$consumer" <<'V1_TARGET'
#!/bin/sh
result=$(node) || exit 12
printf 'consumer-v1:%s\n' "$result"
V1_TARGET

printf 'tar.gz\n' > "$range_v2/format"
printf 'nodejs =26\n' > "$range_v2/dependency"
printf '../../cmd/%s\n' "$consumer" > "$range_v2/link/bin/$consumer"
printf '../../root/bin/%s\n' "$consumer" > "$range_v2/link/target/$consumer"
cat > "$range_v2/cmd/$consumer" <<'V2_WRAPPER'
#!/bin/sh
. "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 2
loadsyslib "pkg/pkg-launch" || exit 3
launcher ci-mixed-provider-consumer "$@"
V2_WRAPPER
cat > "$root_v2/bin/$consumer" <<'V2_TARGET'
#!/bin/sh
result=$(node) || exit 12
printf 'consumer-v2:%s\n' "$result"
V2_TARGET
command -p -- chmod +x "$root_v1/bin/$consumer" "$root_v2/bin/$consumer" || exit 14
pkg_integrate "$consumer" 1 "$range_v1" "$root_v1" || exit 15
pkg_integrate "$consumer" 2 "$range_v2" "$root_v2" "" v2 || exit 16

"$m_ROOT/m" pkg default "$consumer@1" || exit 17
package_default_set=1
"$m_ROOT/m" pkg provider default nodejs "$provider@1" || exit 18
default_set=1
[ "$("$m_ROOT/m" "$consumer")" = consumer-v1:provider-1 ] || exit 19

# The global facility default remains effective across consumer schema changes.
"$m_ROOT/m" pkg default "$consumer@2" || exit 20
[ "$("$m_ROOT/m" "$consumer")" = consumer-v2:provider-1 ] || exit 21
"$m_ROOT/m" pkg provider default nodejs "$provider@2" || exit 22
[ "$("$m_ROOT/m" "$consumer")" = consumer-v2:provider-2 ] || exit 23

# The consumer-scoped binding wins over the global default and survives
# a switch back to the legacy installed concrete.
"$m_ROOT/m" pkg provider bind "$consumer" nodejs "$provider@1" || exit 24
binding_set=1
[ "$("$m_ROOT/m" "$consumer")" = consumer-v2:provider-1 ] || exit 25
"$m_ROOT/m" pkg default "$consumer@1" || exit 26
[ "$("$m_ROOT/m" "$consumer")" = consumer-v1:provider-1 ] || exit 27
"$m_ROOT/m" pkg provider bind -u "$consumer" nodejs || exit 28
binding_set=0
[ "$("$m_ROOT/m" "$consumer")" = consumer-v1:provider-2 ] || exit 29

# Unset global selection leaves the multiple installed versions ambiguous.
"$m_ROOT/m" pkg provider default -u nodejs || exit 30
default_set=0
if "$m_ROOT/m" "$consumer" >/dev/null 2>&1
then
  exit 31
fi
"$m_ROOT/m" pkg provider bind "$consumer" nodejs "$provider@1" || exit 32
binding_set=1
[ "$("$m_ROOT/m" "$consumer")" = consumer-v1:provider-1 ] || exit 33
"$m_ROOT/m" pkg provider bind -u "$consumer" nodejs || exit 34
binding_set=0

printf '%s\n' 'PASS: v1/v2 consumer default, provider default, consumer binding, ambiguity and real target launch'
