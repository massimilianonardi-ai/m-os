#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
source="$root/native/sys/srv-supervisor.c"
if [ "$#" -gt 0 ]; then
  printf '%s\n' 'build-srv-supervisor.sh does not accept an external output path' >&2
  exit 2
fi
output="$root/libexec/sys/srv-supervisor"
compiler=${CC:-cc}

[ -f "$source" ] || { printf '%s\n' 'srv supervisor source is missing' >&2; exit 1; }
command -v "$compiler" >/dev/null 2>&1 || {
  printf 'srv supervisor build requires a C compiler: %s\n' "$compiler" >&2
  exit 1
}
mkdir -p -- "$(dirname -- "$output")"
tmp="$output.tmp.$$"
trap 'rm -f -- "$tmp"' 0 HUP INT TERM
"$compiler" -std=c99 -O2 -Wall -Wextra -Werror "$source" -o "$tmp"
chmod 755 "$tmp"
mv -f -- "$tmp" "$output"
trap - 0 HUP INT TERM
printf '%s\n' "$output"
