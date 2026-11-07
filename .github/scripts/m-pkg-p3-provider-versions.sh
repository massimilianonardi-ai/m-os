#!/bin/sh
# Genuine public provider-version selection and compatibility regression.
set -eu

repo_root=$(CDPATH= cd "$(dirname "$0")/../.." && pwd) || exit 1
CDPATH= cd "$repo_root" || exit 1

umask 077
tmp_base=${TMPDIR:-/tmp}
case "$tmp_base" in
  /*) : ;;
  *) tmp_base=./$tmp_base ;;
esac
attempt=0
work=
installed_v010=0
installed_v014=0
installed_v015=0
installed_v016=0
package_default_owned=0
provider_default_owned=0
catalog_config=
catalog_config_saved=0
catalog_config_mutated=0
while [ "$attempt" -lt 10 ]
do
  work=$tmp_base/m-pkg-p3-provider-versions-$$-$attempt
  if (umask 077; mkdir -m 700 "$work") 2>/dev/null
  then
    break
  fi
  work=
  attempt=$((attempt + 1))
done
[ -n "$work" ] || exit 2

cleanup()
{
  if [ "$provider_default_owned" -eq 1 ]; then
    cleanup_provider_default=$(./m pkg provider default web-control 2>/dev/null) || cleanup_provider_default=
    case "$cleanup_provider_default" in
      pwc-web-control@v0.1.0|pwc-web-control@v0.1.4|pwc-web-control@v0.1.5|pwc-web-control@v0.1.6)
        ./m pkg provider default -u -- web-control >/dev/null 2>&1 || :
        ;;
    esac
  fi
  if [ "$package_default_owned" -eq 1 ]; then
    cleanup_package_default=$(./m pkg default pwc-web-control 2>/dev/null) || cleanup_package_default=
    case "$cleanup_package_default" in
      pwc-web-control@v0.1.0|pwc-web-control@v0.1.4|pwc-web-control@v0.1.5|pwc-web-control@v0.1.6)
        ./m pkg default -u -- pwc-web-control >/dev/null 2>&1 || :
        ;;
    esac
  fi
  if [ "$installed_v010" -eq 1 ]; then
    ./m pkg uninstall pwc-web-control@v0.1.0 >/dev/null 2>&1 || :
  fi
  if [ "$installed_v015" -eq 1 ]; then
    ./m pkg uninstall pwc-web-control@v0.1.5 >/dev/null 2>&1 || :
  fi
  if [ "$installed_v016" -eq 1 ]; then
    ./m pkg uninstall pwc-web-control@v0.1.6 >/dev/null 2>&1 || :
  fi
  if [ "$installed_v014" -eq 1 ]; then
    ./m pkg uninstall pwc-web-control@v0.1.4 >/dev/null 2>&1 || :
  fi
  if [ "$catalog_config_mutated" -eq 1 ]; then
    [ -f "$catalog_config" ] && [ ! -L "$catalog_config" ] || {
      echo 'ERROR: pkg-catalog setting changed type during P3 test; preserving it and temporary checkout for recovery' >&2
      return 1
    }
    cleanup_catalog_path=$(command -p cat -- "$catalog_config") || return 1
    [ "$cleanup_catalog_path" = "$catalog" ] || {
      echo 'ERROR: pkg-catalog setting changed during P3 test; preserving it and temporary checkout for recovery' >&2
      return 1
    }
    if [ "$catalog_config_saved" -eq 1 ]; then
      command -p cp -p -- "$work/catalog-config" "$catalog_config" || return 1
    else
      command -p rm -f -- "$catalog_config" || return 1
    fi
  fi
  if [ -d "$work/catalog" ]; then command -p rm -rf -- "$work/catalog" || return 1; fi
  command -p rm -f -- "$work/catalog-config" "$work/versions" "$work/incompatible" || :
  rmdir "$work" 2>/dev/null || :
}
trap cleanup 0
trap 'exit 130' HUP INT TERM

./m osarch update || exit 3

# This destructive lifecycle test requires a clean, test-owned package view.
[ ! -e "pkg/pwc-web-control@v0.1.0" ] && [ ! -L "pkg/pwc-web-control@v0.1.0" ] || exit 9
[ ! -e "pkg/pwc-web-control@v0.1.4" ] && [ ! -L "pkg/pwc-web-control@v0.1.4" ] || exit 9
[ ! -e "pkg/pwc-web-control@v0.1.5" ] && [ ! -L "pkg/pwc-web-control@v0.1.5" ] || exit 9
[ ! -e "pkg/pwc-web-control@v0.1.6" ] && [ ! -L "pkg/pwc-web-control@v0.1.6" ] || exit 9
[ ! -e "pkg/pwc-web-control" ] && [ ! -L "pkg/pwc-web-control" ] || exit 9
[ ! -e "bin/ext/web-control" ] && [ ! -L "bin/ext/web-control" ] || exit 9
catalog="$work/catalog"
git clone --quiet -- https://github.com/massimilianonardi-ai/pkg-catalog.git "$catalog" || exit 4
git -C "$catalog" checkout --quiet 4083aa19c4362f00ec62428a631edfa493faf7f0 || exit 5
conf=$(./m state-path system sys pkg conf) || exit 6
catalog_config="$conf/catalog"
provider_config="$conf/provider/default/web-control"
[ ! -e "$provider_config" ] && [ ! -L "$provider_config" ] || exit 9
if [ -e "$catalog_config" ] || [ -L "$catalog_config" ]; then
  [ -f "$catalog_config" ] && [ ! -L "$catalog_config" ] || exit 9
  command -p cp -p -- "$catalog_config" "$work/catalog-config" || exit 9
  catalog_config_saved=1
fi
command -p mkdir -p "$conf" || exit 7
catalog_config_mutated=1
printf '%s\n' "$catalog" > "$conf/catalog" || exit 8

# These are genuine published releases of one provider package. Their
# metadata deliberately declares different exact compatibility levels.
./m pkg install pwc-web-control@v0.1.0 || exit 10
installed_v010=1
package_default_owned=1
./m pkg install pwc-web-control@v0.1.4 || exit 11
installed_v014=1
[ "$(./m pkg default pwc-web-control)" = pwc-web-control@v0.1.4 ] || {
  echo 'FAIL: latest installed concrete was not selected as the package default' >&2
  exit 12
}
concrete_v014=$(./m pkg default pwc-web-control) || exit 72
case "$concrete_v014" in *!*) class_v014=${concrete_v014##*!} ;; *) class_v014=all ;; esac
[ -d pkg/pwc-web-control@v0.1.0 ] && [ ! -L pkg/pwc-web-control@v0.1.0 ] || exit 13
[ -d pkg/pwc-web-control@v0.1.4 ] && [ ! -L pkg/pwc-web-control@v0.1.4 ] || exit 14
[ "$(command -p cat pkg/pwc-web-control@v0.1.0/facility)" = 'web-control 1' ] || exit 15
[ "$(command -p cat pkg/pwc-web-control@v0.1.4/facility)" = 'web-control 2' ] || exit 16

# Two compatible versions of one provider receive provider-local latest links;
# a later release that dropped compatibility 2 belongs only to compatibility 3.
./m pkg install pwc-web-control@v0.1.5 || exit 53
installed_v015=1
concrete_v015=$(./m pkg default pwc-web-control) || exit 54
case "$concrete_v015" in *!*) class_v015=${concrete_v015##*!} ;; *) class_v015=all ;; esac
map_v2="$repo_root/facility/web-control/2/$class_v015"
[ -L "$map_v2/pwc-web-control@v0.1.4" ] || exit 55
[ -L "$map_v2/pwc-web-control@v0.1.5" ] || exit 56
[ "$(command -p readlink "$map_v2/pwc-web-control@latest")" = 'pwc-web-control@v0.1.5' ] || exit 57
[ "$(command -p readlink "$map_v2/pwc-web-control@v0.1.5")" = "../../../../pkg/$concrete_v015" ] || exit 58

./m pkg install pwc-web-control@v0.1.6 || exit 59
installed_v016=1
concrete_v016=$(./m pkg default pwc-web-control) || exit 60
case "$concrete_v016" in *!*) class_v016=${concrete_v016##*!} ;; *) class_v016=all ;; esac
map_v3="$repo_root/facility/web-control/3/$class_v016"
[ "$(command -p readlink "$map_v2/pwc-web-control@latest")" = 'pwc-web-control@v0.1.5' ] || exit 61
[ -L "$map_v3/pwc-web-control@v0.1.6" ] || exit 62
[ "$(command -p readlink "$map_v3/pwc-web-control@latest")" = 'pwc-web-control@v0.1.6' ] || exit 63
[ "$(command -p readlink "$map_v3/pwc-web-control@v0.1.6")" = "../../../../pkg/$concrete_v016" ] || exit 64

# Removing the compatibility-3 release leaves compatibility-2 ranking intact;
# removing its newest member restores the preceding compatible concrete.
./m pkg uninstall pwc-web-control@v0.1.6 || exit 65
installed_v016=0
[ ! -e "$repo_root/facility/web-control/3" ] || exit 66
./m pkg uninstall pwc-web-control@v0.1.5 || exit 67
installed_v015=0
[ "$(command -p readlink "$map_v2/pwc-web-control@latest")" = 'pwc-web-control@v0.1.4' ] || exit 68
./m pkg default pwc-web-control@v0.1.4 || exit 69

./m pkg versions pwc-web-control > "$work/versions" || exit 17
grep -F 'pwc-web-control@v0.1.0' "$work/versions" >/dev/null || exit 18
grep -F 'pwc-web-control@v0.1.4' "$work/versions" >/dev/null || exit 19

./m pkg provider default web-control pwc-web-control@v0.1.0 || exit 20
provider_default_owned=1
[ "$(./m pkg requirement resolve web-control '=1')" = pwc-web-control@v0.1.0 ] || exit 21
if ./m pkg requirement resolve web-control '=2' > "$work/incompatible" 2>&1
then
  echo 'FAIL: compatibility 1 provider satisfied compatibility 2' >&2
  exit 22
fi
[ -L bin/ext/web-control ] || exit 23
[ "$(command -p readlink bin/ext/web-control)" = '../../pkg/pwc-web-control@v0.1.0/facility-cmd/web-control/web-control' ] || exit 24

if ./m pkg uninstall pwc-web-control@v0.1.0 > "$work/incompatible" 2>&1
then
  echo 'FAIL: selected concrete provider was uninstalled' >&2
  exit 25
fi
[ -d pkg/pwc-web-control@v0.1.0 ] && [ ! -L pkg/pwc-web-control@v0.1.0 ] || exit 26
[ "$(./m pkg provider default web-control)" = pwc-web-control@v0.1.0 ] || exit 38
concrete_v010=$(./m pkg default pwc-web-control) || exit 73
case "$concrete_v010" in *!*) class_v010=${concrete_v010##*!} ;; *) class_v010=all ;; esac
[ "$(command -p readlink "$repo_root/facility/web-control/1/$class_v010/default")" = "../../../../pkg/$concrete_v010" ] || exit 70
[ -L bin/ext/web-control ] || exit 39
[ "$(command -p readlink bin/ext/web-control)" = '../../pkg/pwc-web-control@v0.1.0/facility-cmd/web-control/web-control' ] || exit 40

./m pkg provider default web-control pwc-web-control@v0.1.4 || exit 27
[ "$(./m pkg requirement resolve web-control '=2')" = pwc-web-control@v0.1.4 ] || exit 28
if ./m pkg requirement resolve web-control '=1' > "$work/incompatible" 2>&1
then
  echo 'FAIL: compatibility 2 provider satisfied compatibility 1' >&2
  exit 29
fi
[ "$(command -p readlink bin/ext/web-control)" = '../../pkg/pwc-web-control@v0.1.4/facility-cmd/web-control/web-control' ] || exit 30

# An unversioned selector follows the package-class default as it moves
# between two installed concrete releases, while exact selectors remain pinned.
./m pkg provider default -u -- web-control || exit 41
./m pkg default pwc-web-control@v0.1.0 || exit 42
./m pkg provider default web-control pwc-web-control || exit 43
[ "$(./m pkg requirement resolve web-control '=1')" = pwc-web-control@v0.1.0 ] || exit 44
[ "$(command -p readlink "$repo_root/facility/web-control/1/$class_v010/default")" = "../../../../pkg/$concrete_v010" ] || exit 74
./m pkg default -u -- pwc-web-control || exit 45
[ ! -e "$repo_root/facility/web-control/1/$class_v010/default" ] && [ ! -L "$repo_root/facility/web-control/1/$class_v010/default" ] || exit 75
./m pkg default pwc-web-control@v0.1.4 || exit 46
[ "$(./m pkg requirement resolve web-control '=2')" = pwc-web-control@v0.1.4 ] || exit 47
[ "$(command -p readlink "$repo_root/facility/web-control/2/$class_v014/default")" = "../../../../pkg/$concrete_v014" ] || exit 76
if ./m pkg requirement resolve web-control '=1' > "$work/incompatible" 2>&1
then
  echo 'FAIL: unversioned selector ignored changed package default compatibility' >&2
  exit 48
fi
[ "$(./m pkg requirement resolve web-control '=2')" = pwc-web-control@v0.1.4 ] || exit 49
./m pkg provider default web-control pwc-web-control@v0.1.4 || exit 50
[ "$(command -p readlink "$repo_root/facility/web-control/2/$class_v014/default")" = "../../../../pkg/$concrete_v014" ] || exit 71

./m pkg uninstall pwc-web-control@v0.1.0 || exit 31
[ ! -e pkg/pwc-web-control@v0.1.0 ] && [ ! -L pkg/pwc-web-control@v0.1.0 ] || exit 32
[ -d pkg/pwc-web-control@v0.1.4 ] && [ ! -L pkg/pwc-web-control@v0.1.4 ] || exit 33
./m pkg provider default -u -- web-control || exit 34
[ ! -e bin/ext/web-control ] && [ ! -L bin/ext/web-control ] || exit 35
./m pkg uninstall pwc-web-control@v0.1.4 || exit 36
[ ! -e pkg/pwc-web-control@v0.1.4 ] && [ ! -L pkg/pwc-web-control@v0.1.4 ] || exit 37
if ./m pkg default pwc-web-control >/dev/null 2>&1; then exit 51; fi
if ./m pkg versions pwc-web-control >/dev/null 2>&1; then exit 52; fi

echo 'PASS: P3 provider selection/protection and P4 facility membership, compatible-latest ordering, dropped-compatibility removal and default projection'
