#!/bin/sh
# Genuine released providers and a real catalog consumer expose ambiguity.
set -eu

repo_root=$(CDPATH= cd "$(dirname "$0")/../.." && pwd) || exit 1
CDPATH= cd "$repo_root" || exit 1
provider_a=electron-web-control@v0.1.6
provider_b=pwc-web-control@v0.1.6
consumer=amazon-wishlist-extract@v0.1.0

work=$(mktemp -d)
cleanup_packages=0
cleanup()
{
  if [ "$cleanup_packages" -eq 1 ]
  then
    ./m pkg provider default -u -- web-control >/dev/null 2>&1 || :
    ./m pkg default -u -- electron-web-control >/dev/null 2>&1 || :
    ./m pkg default -u -- pwc-web-control >/dev/null 2>&1 || :
    for package in "$provider_b" "$provider_a" electron chromium nodejs
    do
      ./m pkg uninstall "$package" >/dev/null 2>&1 || :
    done
  fi
  rm -rf "$work"
}
trap cleanup 0
trap 'exit 130' HUP INT TERM

./m osarch update
if [ -e pkg ] || [ -L pkg ]
then
  echo 'FAIL: real ambiguity test requires an absent package store' >&2
  exit 1
fi
for package in electron-web-control pwc-web-control electron chromium nodejs
 do
  if ./m pkg default "$package" >/dev/null 2>&1
  then
    echo "FAIL: pre-existing package default for $package" >&2
    exit 1
  fi
done
for facility in web-control electron chromium nodejs
do
  if ./m pkg provider default "$facility" >/dev/null 2>&1
  then
    echo "FAIL: pre-existing $facility facility default" >&2
    exit 1
  fi
done
for facility in web-control nodejs
do
  if ./m pkg provider bind "$consumer" "$facility" >/dev/null 2>&1
  then
    echo "FAIL: pre-existing consumer $facility binding" >&2
    exit 1
  fi
done
[ "$(./m pkg requirement list "$consumer")" = 'nodejs =26
web-control >2' ]

cleanup_packages=1

# Install two separately published provider packages whose genuine v0.1.6
# releases both declare web-control 3. Keep only PWC's ordinary package default;
# neither a consumer binding nor a system facility default selects web-control.
./m pkg install "$provider_a"
./m pkg default -u -- electron-web-control
./m pkg install "$provider_b"
[ "$(./m pkg default pwc-web-control)" = "$provider_b" ]
if ./m pkg provider default web-control >/dev/null 2>&1
then
  echo 'FAIL: fresh store unexpectedly has a web-control system default' >&2
  exit 2
fi

set +e
./m pkg depend "$consumer" >"$work/depend" 2>&1
status=$?
set -e
[ "$status" -eq 1 ] || {
  echo "FAIL: expected public dependency planning to reject ambiguity, got status $status" >&2
  cat "$work/depend" >&2
  exit 3
}
grep -F 'provider-ambiguous' "$work/depend" >/dev/null
grep -F 'facility="web-control"' "$work/depend" >/dev/null
grep -F 'electron-web-control@v0.1.6' "$work/depend" >/dev/null
grep -F 'pwc-web-control@v0.1.6' "$work/depend" >/dev/null
[ ! -e "pkg/$consumer" ] && [ ! -L "pkg/$consumer" ]
echo 'PASS: public pkg depend reports ambiguity between two genuine compatible providers for a real consumer'
