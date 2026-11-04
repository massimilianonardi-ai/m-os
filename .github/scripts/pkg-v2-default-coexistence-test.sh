#!/bin/sh
# Verify schema-specific installed package defaults and exact real launch.
# No upstream download or GitHub Releases API is used.
set -eu
[ -n "${m_ROOT-}" ] && [ -n "${m_LIB_DIR-}" ] && [ -n "${m_PKG_DIR-}" ] || exit 1
. "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 2
loadsyslib "pkg/pkg-integration" || exit 3

name=ci-mixed-lifecycle
legacy="$m_PKG_DIR/$name@1"
modern="$m_PKG_DIR/$name@2"
selector="$m_PKG_DIR/$name"
public="$m_BIN_EXT_DIR/$name"
public_direct="$m_BIN_EXT_DIR/$name-direct"
work=$(mktemp -d) || exit 4

# Reject pre-existing paths before owning the selector or cleanup.
for path in "$legacy" "$modern" "$selector" "$public" "$public_direct"
do
  if [ -e "$path" ] || [ -L "$path" ]
  then
    printf 'INFRASTRUCTURE: fixture path exists: %s\n' "$path" >&2
    command -p -- rm -rf -- "$work"
    exit 5
  fi
done

cleanup()
{
  "$m_ROOT/m" pkg default -u "$name" >/dev/null 2>&1 || :
  command -p -- rm -rf -- "$legacy" "$modern" "$work"
}
trap cleanup 0

command -p -- mkdir -p -- "$m_PKG_DIR" "$work/v1/cmd" "$work/v1/link" \
  "$work/root-v1/bin" "$work/v2/cmd" "$work/v2/link/bin" \
  "$work/v2/link/target" "$work/root-v2/bin" || exit 6

printf 'tar.gz\n' > "$work/v1/format"
printf 'bin/%s\n' "$name" > "$work/v1/link/$name"
cat > "$work/v1/cmd/$name" <<'V1_WRAPPER'
#!/bin/sh
. "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 2
loadsyslib "pkg/pkg-launch" || exit 3
launcher ci-mixed-lifecycle "$@"
V1_WRAPPER
cat > "$work/v1/env" <<'V1_ENV'
CI_MIXED_STAGE=legacy
export CI_MIXED_STAGE
V1_ENV
cat > "$work/root-v1/bin/$name" <<'V1_EXEC'
#!/bin/sh
printf 'legacy:%s:%s\n' "${CI_MIXED_STAGE-unset}" "${1-}"
V1_EXEC

printf 'tar.gz\n' > "$work/v2/format"
printf '../../cmd/%s\n' "$name" > "$work/v2/link/bin/$name"
printf '../../root/bin/%s\n' "$name" > "$work/v2/link/target/$name"
printf '../../root/bin/%s-direct\n' "$name" > "$work/v2/link/bin/$name-direct"
cat > "$work/v2/cmd/$name" <<'V2_WRAPPER'
#!/bin/sh
. "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 2
loadsyslib "pkg/pkg-launch" || exit 3
launcher ci-mixed-lifecycle fixed "$@"
V2_WRAPPER
cat > "$work/v2/env" <<'V2_ENV'
CI_MIXED_STAGE=modern
export CI_MIXED_STAGE
V2_ENV
cat > "$work/root-v2/bin/$name" <<'V2_EXEC'
#!/bin/sh
printf 'modern:%s:%s:%s\n' "${CI_MIXED_STAGE-unset}" "${1-}" "${2-}"
V2_EXEC
cat > "$work/root-v2/bin/$name-direct" <<'DIRECT_EXEC'
#!/bin/sh
printf 'direct:%s:%s\n' "${CI_MIXED_STAGE-unset}" "${1-}"
DIRECT_EXEC
command -p -- chmod +x "$work/root-v1/bin/$name" \
  "$work/root-v2/bin/$name" "$work/root-v2/bin/$name-direct" || exit 7

pkg_integrate "$name" 1 "$work/v1" "$work/root-v1" || exit 8
pkg_integrate "$name" 2 "$work/v2" "$work/root-v2" "" v2 || exit 9
[ ! -e "$legacy/schema" ] && [ ! -L "$legacy/schema" ] || exit 10
[ "$(command -p -- cat -- "$modern/schema")" = v2 ] || exit 11
[ "$(command -p -- readlink "$modern/link/bin/$name")" = "../../cmd/$name" ] || exit 12
[ "$(command -p -- readlink "$modern/link/target/$name")" = "../../root/bin/$name" ] || exit 13

# Installing both concretes does not select either one.
if "$m_ROOT/m" pkg default "$name" >/dev/null 2>&1
then
  exit 14
fi
[ ! -e "$public" ] && [ ! -L "$public" ] || exit 15

"$m_ROOT/m" pkg default "$name@1" || exit 16
[ "$("$m_ROOT/m" pkg default "$name")" = "$name@1" ] || exit 17
[ "$(command -p -- readlink "$public")" = "../../pkg/$name/cmd/$name" ] || exit 18
[ "$("$m_ROOT/m" "$name" first)" = legacy:legacy:first ] || exit 19
[ ! -e "$public_direct" ] && [ ! -L "$public_direct" ] || exit 20

"$m_ROOT/m" pkg default "$name@2" || exit 21
[ "$("$m_ROOT/m" pkg default "$name")" = "$name@2" ] || exit 22
[ "$(command -p -- readlink "$public")" = "../../pkg/$name/link/bin/$name" ] || exit 23
[ "$(command -p -- readlink "$public_direct")" = "../../pkg/$name/link/bin/$name-direct" ] || exit 24
[ "$("$m_ROOT/m" "$name" second)" = modern:modern:fixed:second ] || exit 25
[ "$(CI_MIXED_STAGE=caller "$m_ROOT/m" "$name-direct" third)" = direct:caller:third ] || exit 26

# Failed selection preserves the currently published v2 command view.
if "$m_ROOT/m" pkg default "$name@999" >/dev/null 2>&1
then
  exit 27
fi
[ "$("$m_ROOT/m" pkg default "$name")" = "$name@2" ] || exit 28
[ "$("$m_ROOT/m" "$name" stable)" = modern:modern:fixed:stable ] || exit 29

# Context changes shell-local selection without rewriting global defaults.
baseline=$PATH
context "pkg=$name@1" || exit 30
[ "$(command -v "$name")" = "$legacy/cmd/$name" ] || exit 31
context "pkg=$name@2" || exit 32
[ "$(command -v "$name")" = "$modern/link/bin/$name" ] || exit 33
[ "$(command -v "$name-direct")" = "$modern/link/bin/$name-direct" ] || exit 34
context || exit 35
[ "$PATH" = "$baseline" ] || exit 36
[ "$("$m_ROOT/m" pkg default "$name")" = "$name@2" ] || exit 37

"$m_ROOT/m" pkg default "$name@1" || exit 38
[ "$("$m_ROOT/m" "$name" back)" = legacy:legacy:back ] || exit 39
[ ! -e "$public_direct" ] && [ ! -L "$public_direct" ] || exit 40
"$m_ROOT/m" pkg default -u "$name" || exit 41
[ ! -e "$selector" ] && [ ! -L "$selector" ] || exit 42
[ ! -e "$public" ] && [ ! -L "$public" ] || exit 43
[ ! -e "$public_direct" ] && [ ! -L "$public_direct" ] || exit 44
if "$m_ROOT/m" pkg default "$name" >/dev/null 2>&1
then
  exit 45
fi
[ -d "$legacy" ] && [ -d "$modern" ] || exit 46

printf '%s\n' 'PASS: v1/v2 exact defaults, public links, wrapped/direct execution, context and unset'
