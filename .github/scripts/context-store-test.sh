#!/bin/sh
set -eu

[ -n "${m_ROOT-}" ] || exit 1
. "$m_LIB_DIR/sys/sh/core.lib.sh"
loadsyslib "base"

work="$m_ROOT/.tmp/context-store-test.$$"
normal="$work/normal"
unsafe="$work/unsafe"
linked="$work/linked"
race="$work/race"
fakebin="$work/fakebin"
marker="$work/fake-ran"
test_uid=$(command -p id -u)
signal_marker="$work/lock-ready"
signal_writer=
old_path=$PATH

cleanup()
{
  PATH=$old_path
  export PATH
  if [ -n "$signal_writer" ]; then
    command -p kill -TERM "$signal_writer" 2>/dev/null || :
    wait "$signal_writer" 2>/dev/null || :
  fi
  command -p chmod 755 "$work/readonly/state" 2>/dev/null || :
  command -p rm -rf "$work"
}
trap cleanup 0
trap 'exit 130' HUP INT TERM

command -p mkdir -p "$work" "$normal/state" "$unsafe/state" "$linked/state" "$race/state" "$fakebin"
command -p chmod 755 "$normal/state" "$linked/state" "$race/state"
command -p chmod 777 "$unsafe/state"

# Empty reads are non-mutating, and account data is strict and bounded.
if _context_store_read "$normal" defaults; then status=0; else status=$?; fi
[ "$status" -eq 5 ] || exit 10
[ ! -e "$normal/state/$test_uid" ] || exit 11

record_a='m-context-record-v1
pkg=context-a@1'
record_b='m-context-record-v1
pkg=context-b@1'
_context_store_write "$normal" defaults "$record_a" || exit 12
account="$normal/state/$test_uid"
context_dir="$account/context"
_context_store_metadata "$account" || exit 13
case "$_context_store_mode" in drwx------ | drwx------@) : ;; *) exit 14 ;; esac
[ "$_context_store_owner" = "$test_uid" ] || exit 15
_context_store_file_validate "$context_dir/defaults" "$test_uid" || exit 16
_context_store_read "$normal" defaults || exit 17
[ "$CONTEXT_STORE_PACKAGES" = 'pkg=context-a@1' ] || exit 18
command -p chmod 755 "$context_dir"
if _context_store_read "$normal" defaults; then exit 41; fi
command -p chmod 700 "$context_dir"
command -p chmod 644 "$context_dir/defaults"
if _context_store_read "$normal" defaults; then exit 42; fi
command -p chmod 600 "$context_dir/defaults"

# The store root and its direct state child must also be real directories.
command -p ln -s "$normal" "$work/root-link"
if _context_store_read "$work/root-link" defaults; then exit 43; fi
command -p mkdir -p "$work/state-target"
command -p chmod 755 "$work/state-target"
command -p ln -s "$work/state-target" "$work/state-link-state"
command -p mkdir "$work/state-link-root"
command -p ln -s "$work/state-link-state" "$work/state-link-root/state"
if _context_store_write "$work/state-link-root" defaults "$record_a"; then exit 44; fi

# Same-account concurrent updates must leave one whole parseable record.
_context_store_directory "$race" "$test_uid" create >/dev/null || exit 19
(_context_store_write "$race" defaults "$record_a") &
writer_a=$!
(_context_store_write "$race" defaults "$record_b") &
writer_b=$!
wait "$writer_a" || exit 20
wait "$writer_b" || exit 21
_context_store_read "$race" defaults || exit 22
case "$CONTEXT_STORE_PACKAGES" in
  pkg=context-a@1 | pkg=context-b@1) : ;;
  *) exit 23 ;;
esac

# Unsafe shared parents fail without having their permissions changed.
if _context_store_write "$unsafe" defaults "$record_a"; then exit 24; fi
_context_store_metadata "$unsafe/state" || exit 25
[ "$_context_store_mode" = drwxrwxrwx ] || exit 26

# A read-only parent works only after the account/context leaves are provisioned.
readonly_root="$work/readonly"
command -p mkdir -p "$readonly_root/state/$test_uid/context"
command -p chmod 700 "$readonly_root/state/$test_uid" "$readonly_root/state/$test_uid/context"
command -p chmod 555 "$readonly_root/state"
_context_store_write "$readonly_root" defaults "$record_a" || exit 27
_context_store_read "$readonly_root" defaults || exit 28
[ "$CONTEXT_STORE_PACKAGES" = 'pkg=context-a@1' ] || exit 29

# Refuse symlinked account leaves, context directories and record files.
command -p mkdir -p "$linked/state/$test_uid/context"
command -p chmod 700 "$linked/state/$test_uid" "$linked/state/$test_uid/context"
command -p rm -rf "$linked/state/$test_uid/context"
command -p ln -s "$normal/state/$test_uid/context" "$linked/state/$test_uid/context"
if _context_store_read "$linked" defaults; then exit 30; fi
command -p rm "$linked/state/$test_uid/context"
command -p rmdir "$linked/state/$test_uid"
command -p ln -s "$normal/state/$test_uid" "$linked/state/$test_uid"
if _context_store_read "$linked" defaults; then exit 31; fi
command -p rm "$linked/state/$test_uid"
command -p mkdir -m 700 "$linked/state/$test_uid"
command -p ln -s "$normal/state/$test_uid/context/defaults" "$linked/state/$test_uid/context-defaults-link"
command -p mkdir -m 700 "$linked/state/$test_uid/context"
command -p ln -s "$normal/state/$test_uid/context/defaults" "$linked/state/$test_uid/context/defaults"
if _context_store_read "$linked" defaults; then exit 32; fi

# Unknown versions, duplicate package dimensions and oversized records fail closed.
command -p rm "$linked/state/$test_uid/context/defaults"
printf '%s\n' unknown-version > "$linked/state/$test_uid/context/defaults"
command -p chmod 600 "$linked/state/$test_uid/context/defaults"
if _context_store_read "$linked" defaults; then exit 33; fi
printf '%s\n' m-context-record-v1 pkg=context-a@1 pkg=context-a@2 > "$linked/state/$test_uid/context/defaults"
if _context_store_read "$linked" defaults; then exit 34; fi
LC_ALL=C command -p awk 'BEGIN { printf "m-context-record-v1\\n"; for (i = 0; i < 17000; i++) printf "x" }' > "$linked/state/$test_uid/context/defaults"
if _context_store_read "$linked" defaults; then exit 35; fi

# A front-of-PATH fake utility set must not participate in storage operations.
for utility in id ls awk wc mkdir chmod mv rm sleep
do
  printf '#!/bin/sh\n: > "%s"\nexit 99\n' "$marker" > "$fakebin/$utility"
  command -p chmod 700 "$fakebin/$utility"
done
PATH="$fakebin:$old_path"
export PATH
_context_store_write "$normal" preset.fakecheck "$record_b" || exit 36
_context_store_read "$normal" preset.fakecheck || exit 37
[ "$CONTEXT_STORE_PACKAGES" = 'pkg=context-b@1' ] || exit 38
_context_store_delete "$normal" preset.fakecheck || exit 39
[ ! -e "$marker" ] || exit 40
PATH=$old_path
export PATH

# Named preset records use the same validated atomic store primitives.
_context_store_write "$normal" preset.race "$record_a" || exit 55
_context_store_read "$normal" preset.race || exit 56
[ "$CONTEXT_STORE_PACKAGES" = 'pkg=context-a@1' ] || exit 57
_context_store_write "$normal" preset.race "$record_b" || exit 58
_context_store_read "$normal" preset.race || exit 59
[ "$CONTEXT_STORE_PACKAGES" = 'pkg=context-b@1' ] || exit 60
_context_store_delete "$normal" preset.race || exit 61
[ ! -e "$normal/state/$test_uid/context/preset.race" ] || exit 62

# A handled termination after lock acquisition releases its own lock and token.
(
  _context_store_lock_dir=
  _context_store_lock_token_path=
  _context_store_lock_token_owned=0
  trap '_context_defaults_lock_cleanup' 0
  trap 'exit 143' HUP INT TERM
  _context_store_lock "$race" || exit 46
  command -p sleep 30 &
  lock_sleep=$!
  printf '%s\n' "$lock_sleep" > "$signal_marker"
  wait "$lock_sleep"
  :
) &
signal_writer=$!
signal_attempt=0
while [ ! -f "$signal_marker" ] && [ "$signal_attempt" -lt 10 ]
do
  command -p sleep 1
  signal_attempt=$((signal_attempt + 1))
done
[ -f "$signal_marker" ] || exit 47
IFS= read -r signal_sleep < "$signal_marker" || exit 48
command -p kill -TERM "$signal_writer" "$signal_sleep" || exit 49
if wait "$signal_writer"; then exit 50; else signal_status=$?; fi
signal_writer=
[ "$signal_status" -eq 143 ] || exit 51
[ ! -e "$race/state/$test_uid/context/.defaults.lock" ] && [ ! -L "$race/state/$test_uid/context/.defaults.lock" ] || exit 52
for token in "$race/state/$test_uid/context"/._defaults-owner.*
do
  [ -e "$token" ] || [ -L "$token" ] || continue
  exit 53
done
printf '%s\n' 'PASS: account context store ownership, atomic records, isolation and hostile-input checks'
