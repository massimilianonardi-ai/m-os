#!/bin/sh
set -u

script_dir=${0%/*}
repo_root=$script_dir/../..
repo_root=$(CDPATH= cd "$repo_root" 2>/dev/null && pwd -P) || {
  printf '%s\n' 'm-json-public: cannot resolve repository root' >&2
  exit 3
}
command_file=$repo_root/bin/sys/json
manual_file=$repo_root/res/sys/manual/json

fail()
{
  printf 'm-json-public: %s\n' "$*" >&2
  exit 1
}

error()
{
  printf 'm-json-public: %s\n' "$*" >&2
  exit 3
}

CDPATH= cd "$repo_root" || error 'cannot enter repository root'

[ -f "$command_file" ] && [ -x "$command_file" ] || fail 'json command is missing or not executable'
[ -f "$manual_file" ] && [ ! -L "$manual_file" ] || fail 'json manual is missing'
IFS= read -r first_line < "$command_file" || first_line=
[ "$first_line" = '#!/bin/sh' ] || fail 'json does not use the exact POSIX shell shebang'

tmp_base=${TMPDIR:-/tmp}
case "$tmp_base" in
  /*) : ;;
  *) tmp_base=./$tmp_base ;;
esac
attempt=0
tmp_dir=
while [ "$attempt" -lt 10 ]
do
  tmp_dir=$tmp_base/m-json-public-$$-$attempt
  if (umask 077; mkdir -m 700 "$tmp_dir") 2>/dev/null
  then
    break
  fi
  tmp_dir=
  attempt=$((attempt + 1))
done
[ -n "$tmp_dir" ] || error 'cannot create private temporary directory'
leading_tmp=
fake_bin=
cleanup()
{
  command -p rm -f "$tmp_dir/input" "$tmp_dir/input-a" "$tmp_dir/input-b" "$tmp_dir/filter" \
    "$tmp_dir/output" "$tmp_dir/expected" "$tmp_dir/error" "$tmp_dir/marker" \
    "$fake_bin"/*
  command -p rmdir "$fake_bin" 2>/dev/null || :
  command -p rmdir "$tmp_dir" 2>/dev/null || :
  if [ -n "$leading_tmp" ]
  then
    rmdir "$leading_tmp" 2>/dev/null || :
  fi
}
trap cleanup 0
trap 'exit 3' 1 2 3 15

unset m_ROOT

query()
{
  input=$1
  expected=$2
  shift 2
  printf '%s' "$input" | "$command_file" "$@" > "$tmp_dir/output" 2> "$tmp_dir/error" ||
    fail "public query failed: $*"
  printf '%b' "$expected" > "$tmp_dir/expected"
  cmp -s "$tmp_dir/expected" "$tmp_dir/output" || fail "public query output mismatch: $*"
}

query_failure()
{
  expected_status=$1
  input=$2
  shift 2
  printf '%s' "$input" | "$command_file" "$@" > "$tmp_dir/output" 2> "$tmp_dir/error"
  actual_status=$?
  [ "$actual_status" -eq "$expected_status" ] ||
    fail "query status $actual_status, expected $expected_status: $*"
  [ ! -s "$tmp_dir/output" ] || fail "failed query exposed partial output: $*"
  [ -s "$tmp_dir/error" ] || fail "failed query omitted its diagnostic: $*"
}

query '{"user":{"name":"Ada"}}' '"Ada"\n' -c '.user.name'
query '{"users":[{"name":"Ada"},{"name":"Lin"}]}' 'Ada\nLin\n' -r '.users[].name'
query '[10,20,30]' '30\n' -c '.[-1]'
query '{"\u0061":7}' '7\n' -c '.a'
query '{"a":1,"b":2,"a":3}' '{"a":3,"b":2}\n' -c
query '{"a":{"x":1},"b":{"x":2}}' '1\n2\n' -c '.a,.b | .x'
query '1 2' '1\n2\n' -c
query_failure 13 '1' -c '.x'
query_failure 3 '{}' -c '.foo + 1'
query_failure 10 '1 !' -c

printf '%s' '.user.name' > "$tmp_dir/filter"
printf '%s' '{"user":{"name":"Ada"}}' | "$command_file" -r -f "$tmp_dir/filter" > "$tmp_dir/output" 2> "$tmp_dir/error" ||
  fail 'json rejected a filter read from a file'
printf 'Ada\n' > "$tmp_dir/expected"
cmp -s "$tmp_dir/expected" "$tmp_dir/output" || fail 'filter-file query output mismatch'

printf '%s' '1' > "$tmp_dir/input-a"
printf '%s' '2' > "$tmp_dir/input-b"
"$command_file" -c '.' "$tmp_dir/input-a" "$tmp_dir/input-b" > "$tmp_dir/output" 2> "$tmp_dir/error" ||
  fail 'json rejected ordered input files'
printf '1\n2\n' > "$tmp_dir/expected"
cmp -s "$tmp_dir/expected" "$tmp_dir/output" || fail 'ordered input-file output mismatch'

printf '%s' 'false' | "$command_file" -e > "$tmp_dir/output" 2> "$tmp_dir/error"
actual_status=$?
[ "$actual_status" -eq 1 ] || fail "-e false returned $actual_status, expected 1"
[ "$(cat "$tmp_dir/output")" = false ] || fail '-e false output changed'

printf '%s' '[]' | "$command_file" -e '.[]' > "$tmp_dir/output" 2> "$tmp_dir/error"
actual_status=$?
[ "$actual_status" -eq 4 ] || fail "-e empty result returned $actual_status, expected 4"
[ ! -s "$tmp_dir/output" ] || fail '-e empty result produced output'

printf '%s' '1 2' | "$command_file" --check > "$tmp_dir/output" 2> "$tmp_dir/error"
actual_status=$?
[ "$actual_status" -eq 12 ] || fail "--check accepted multiple JSON values: status $actual_status"
[ ! -s "$tmp_dir/output" ] || fail '--check produced output'

printf '"\377"' | "$command_file" --check > "$tmp_dir/output" 2> "$tmp_dir/error"
actual_status=$?
[ "$actual_status" -eq 11 ] || fail "--check accepted invalid UTF-8: status $actual_status"
[ ! -s "$tmp_dir/output" ] || fail 'invalid UTF-8 check produced output'

printf '%s' '"\uD800"' | "$command_file" -r > "$tmp_dir/output" 2> "$tmp_dir/error" ||
  fail 'raw output rejected a grammar-valid unpaired surrogate'
printf '\357\277\275\n' > "$tmp_dir/expected"
cmp -s "$tmp_dir/expected" "$tmp_dir/output" || fail 'raw output emitted invalid UTF-8 for an unpaired surrogate'

leading_tmp=./-m-json-public-$$
command -p mkdir -m 700 "$leading_tmp" || error 'cannot create leading-dash TMPDIR fixture'
printf '%s' '{"leading":true}' | TMPDIR=${leading_tmp#./} "$command_file" -c > "$tmp_dir/output" 2> "$tmp_dir/error" ||
  fail 'json failed with a relative TMPDIR beginning with a dash'
printf '%s\n' '{"leading":true}' > "$tmp_dir/expected"
cmp -s "$tmp_dir/expected" "$tmp_dir/output" || fail 'leading-dash TMPDIR query output mismatch'
command -p rmdir "$leading_tmp" || fail 'json left temporary files in the leading-dash TMPDIR'
leading_tmp=

fake_bin=$tmp_dir/fake-bin
command -p mkdir -m 700 "$fake_bin" || error 'cannot create fake PATH fixture'
for utility in cat awk od mkdir rm rmdir
do
  {
    printf '%s\n' '#!/bin/sh'
    printf '%s\n' 'printf "%s\\n" "$0" >> "$JSON_PUBLIC_MARKER"'
    printf '%s\n' 'exit 99'
  } > "$fake_bin/$utility" || error "cannot create fake $utility"
  command -p chmod 700 "$fake_bin/$utility" || error "cannot make fake $utility executable"
done
printf '%s' '{"path":"isolated"}' | PATH=$fake_bin JSON_PUBLIC_MARKER=$tmp_dir/marker TMPDIR=$tmp_dir "$command_file" -c > "$tmp_dir/output" 2> "$tmp_dir/error" ||
  fail 'valid JSON failed with hostile PATH'
[ "$(command -p cat "$tmp_dir/output")" = '{"path":"isolated"}' ] || fail 'hostile PATH changed valid JSON output'
printf '%s' '{' | PATH=$fake_bin JSON_PUBLIC_MARKER=$tmp_dir/marker TMPDIR=$tmp_dir "$command_file" --check > "$tmp_dir/output" 2> "$tmp_dir/error"
actual_status=$?
[ "$actual_status" -eq 12 ] || fail "hostile PATH changed malformed JSON status to $actual_status"
[ ! -e "$tmp_dir/marker" ] || fail 'json executed a utility from caller-controlled PATH'

printf '%s\n' 'PASS: standalone POSIX json CLI, query, validation, atomic errors and caller-PATH isolation'
