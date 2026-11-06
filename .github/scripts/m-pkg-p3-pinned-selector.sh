#!/bin/sh
# Isolated P3 selector-boundary regression: real public m commands and a
# controlled installed-provider metadata fixture, not a released artifact.
set -eu

./m osarch update
provider=ci-p3-pinned-provider
concrete="$provider@v1"
store="pkg/$concrete"
[ ! -e "$store" ] && [ ! -L "$store" ] || exit 1
if ./m pkg provider default web-control >/dev/null 2>&1; then exit 2; fi

cleanup()
{
  ./m pkg provider default -u -- web-control >/dev/null 2>&1 || :
  command -p rm -rf "$store"
}
trap cleanup 0
trap 'exit 3' HUP INT TERM

command -p mkdir -p "$store/root/bin" "$store/facility-cmd/web-control" \
  "$store/facility-cmd/java" "$store/facility-cmd/chromium" "$store/facility-env" || exit 4
printf 'chromium 1\njava 25\nweb-control 1\n' > "$store/facility"
printf 'JAVA_HOME\troot\n' > "$store/facility-env/java"
printf 'CHROME_DEVEL_SANDBOX\troot-path chrome_sandbox\n' > "$store/facility-env/chromium"
printf '#!/bin/sh\nprintf "fixture-pinned\\n"\n' > "$store/root/bin/web-control"
printf '#!/bin/sh\nprintf "java fixture\\n"\n' > "$store/root/bin/java"
printf '#!/bin/sh\nprintf "chromium fixture\\n"\n' > "$store/root/bin/chrome"
printf '%s\n' 'chromium sandbox fixture' > "$store/root/chrome_sandbox"
command -p chmod +x "$store/root/bin/web-control" || exit 14
command -p chmod +x "$store/root/bin/java" || exit 14
command -p chmod +x "$store/root/bin/chrome" || exit 14
command -p ln -s ../../root/bin/web-control "$store/facility-cmd/web-control/web-control" || exit 15
command -p ln -s ../../root/bin/java "$store/facility-cmd/java/java" || exit 15
command -p ln -s ../../root/bin/chrome "$store/facility-cmd/chromium/chromium" || exit 15

# Exercise the typed env handler through the public provider selector and
# documented global-environment API, with no mutable package-class default.
./m pkg provider default java "$concrete" || exit 18
[ "$(./m pkg requirement resolve java '=25')" = "$concrete" ] || exit 19
expected_java_home="$PWD/$store/root"
selected_java_home=$(./m sh -c '
  . "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 1
  loadsyslib "pkg/pkg-provider" || exit 2
  pkg_provider_global_environment_apply || exit 3
  printf "%s\n" "${JAVA_HOME-}"
') || exit 20
[ "$selected_java_home" = "$expected_java_home" ] || exit 21
./m pkg provider default -u -- java || exit 22

./m pkg provider default chromium "$concrete" || exit 23
[ "$(./m pkg requirement resolve chromium '=1')" = "$concrete" ] || exit 24
expected_sandbox="$PWD/$store/root/chrome_sandbox"
selected_sandbox=$(./m sh -c '
  . "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 1
  loadsyslib "pkg/pkg-provider" || exit 2
  pkg_provider_global_environment_apply || exit 3
  printf "%s\n" "${CHROME_DEVEL_SANDBOX-}"
') || exit 25
[ "$selected_sandbox" = "$expected_sandbox" ] || exit 26
[ "$(./m chromium --version)" = 'chromium fixture' ] || exit 27
./m pkg provider default -u -- chromium || exit 28

# A selected provider with an invalid typed root-path must fail atomically:
# no default or public command projection may survive the failed update.
printf 'CHROME_DEVEL_SANDBOX\troot-path missing_sandbox\n' > "$store/facility-env/chromium"
if ./m pkg provider default chromium "$concrete" >/dev/null 2>&1
then
  echo 'FAIL: provider selection accepted a missing typed root-path' >&2
  exit 29
fi
if ./m pkg provider default chromium >/dev/null 2>&1
then
  echo 'FAIL: failed provider update left a global default behind' >&2
  exit 30
fi
[ ! -e bin/ext/chromium ] && [ ! -L bin/ext/chromium ] || exit 31

./m pkg provider default web-control "$concrete" || exit 5
[ "$(./m pkg provider default web-control)" = "$concrete" ] || exit 6
[ "$(./m pkg requirement resolve web-control '=1')" = "$concrete" ] || exit 7
[ -L bin/ext/web-control ] || exit 16
[ "$(./m web-control)" = 'fixture-pinned' ] || exit 17

# Unversioned selection still requires the package-class default. The exact
# concrete above must NOT require that mutable default.
./m pkg provider default web-control "$provider" || exit 8
set +e
./m pkg requirement resolve web-control '=1' >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 1 ] || exit 9

./m pkg provider default web-control "$concrete" || exit 10
[ "$(./m pkg requirement resolve web-control '=1')" = "$concrete" ] || exit 11
./m pkg provider default -u -- web-control || exit 12
[ -d "$store" ] && [ ! -L "$store" ] || exit 13

echo 'PASS: P3 exact/unversioned selectors, typed root/root-path env, public command and failed-update atomicity'
