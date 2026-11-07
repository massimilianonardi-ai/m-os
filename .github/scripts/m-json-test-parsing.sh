#!/bin/sh
set -u

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
  printf '%s\n' 'usage: m-json-test-parsing.sh JSONTestSuite/test_parsing' >&2
  exit 2
fi
corpus=$1
script_dir=${0%/*}
repo_root=$(CDPATH= cd "$script_dir/../.." 2>/dev/null && pwd -P) || exit 3
json=$repo_root/bin/sys/json
[ -x "$json" ] || { printf '%s\n' 'json command is missing' >&2; exit 3; }

valid=0
invalid=0
implementation=0
for file in "$corpus"/y_*.json "$corpus"/n_*.json "$corpus"/i_*.json
do
  [ -f "$file" ] || continue
  name=${file##*/}
  "$json" --check "$file" >/dev/null 2>&1
  status=$?
  case "$name" in
    y_*)
      [ "$status" -eq 0 ] || { printf 'FAIL: valid case %s returned %s\n' "$name" "$status" >&2; exit 1; }
      valid=$((valid+1))
      ;;
    n_*)
      case "$status" in 10|11|12) :;; *) printf 'FAIL: invalid case %s returned %s\n' "$name" "$status" >&2; exit 1;; esac
      invalid=$((invalid+1))
      ;;
    i_*)
      case "$status" in 0|10|11|12) :;; *) printf 'FAIL: implementation-defined case %s returned %s\n' "$name" "$status" >&2; exit 1;; esac
      implementation=$((implementation+1))
      ;;
  esac
done
[ "$valid" -eq 95 ] && [ "$invalid" -eq 188 ] && [ "$implementation" -eq 35 ] || {
  printf 'FAIL: corpus counts y=%s n=%s i=%s, expected 95/188/35\n' "$valid" "$invalid" "$implementation" >&2
  exit 1
}
printf 'PASS: JSONTestSuite test_parsing (%s valid, %s invalid, %s implementation-defined)\n' "$valid" "$invalid" "$implementation"
