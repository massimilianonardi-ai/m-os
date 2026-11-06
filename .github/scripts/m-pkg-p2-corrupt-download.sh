#!/bin/sh
# P2 regression: the real pkg-download boundary must remove a corrupt transfer.
# A local HTTP fixture controls input bytes; target http-fetch, digest and
# download validation remain the actual m implementation.
set -eu

work=$(mktemp -d "${TMPDIR:-/tmp}/m-p2-download.XXXXXXXX") || exit 1
server_pid=
cleanup()
{
  if [ -n "$server_pid" ]
  then
    kill "$server_pid" >/dev/null 2>&1 || :
    wait "$server_pid" >/dev/null 2>&1 || :
  fi
  command -p -- rm -rf -- "$work"
}
trap cleanup 0
trap 'exit 3' HUP INT TERM

cat > "$work/server.js" <<'EOF_NODE'
const http = require("node:http");
const bytes = Buffer.from("tampered-bytes", "utf8");
const server = http.createServer
(
  (request, response) =>
  {
    response.writeHead(200, { "Content-Length": bytes.length });
    response.end(bytes);
  }
);
server.listen
(
  0,
  "127.0.0.1",
  () =>
  {
    process.stdout.write(String(server.address().port) + "\n");
  }
);
EOF_NODE

./m node "$work/server.js" > "$work/port" 2> "$work/server.err" &
server_pid=$!
port=
for attempt in 1 2 3 4 5 6 7 8 9 10
do
  if [ -s "$work/port" ]
  then
    port=$(command -p -- sed -n '1p' "$work/port") || exit 2
    break
  fi
  kill -0 "$server_pid" >/dev/null 2>&1 || exit 4
  sleep 1
done
case "$port" in
  ""|*[!0-9]*) exit 5 ;;
esac

command -p -- mkdir -- "$work/staging" || exit 6
size=$(printf '%s' 'tampered-bytes' | LC_ALL=C command -p -- wc -c | command -p -- awk '{ print $1 }') || exit 7
expected=$(printf '%064d' 0) || exit 8

# Expected bytes and measured size agree. Only the deliberately wrong
# digest causes rejection after a successful real HTTP transfer.
set +e
{
  printf 'name=corrupt-archive.tgz\n'
  printf 'url=http://127.0.0.1:%s/payload\n' "$port"
  printf 'size=%s\n' "$size"
  printf 'digest=sha256:%s\n' "$expected"
} | NO_PROXY=127.0.0.1 no_proxy=127.0.0.1 ./m sh -c '
  . "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 1
  loadsyslib "pkg/pkg-download" || exit 2
  pkg_download "$1"
' _ "$work/staging" > "$work/output" 2> "$work/errors"
status=$?
set -e

[ "$status" -eq 1 ] || exit 9
command -p -- grep 'reason="digest-mismatch"' "$work/errors" || exit 10
[ ! -e "$work/staging/corrupt-archive.tgz" ] && [ ! -L "$work/staging/corrupt-archive.tgz" ] || exit 11
[ ! -s "$work/output" ] || exit 12
echo 'PASS: P2 real HTTP transfer rejected wrong digest and cleaned corrupt staged bytes'
