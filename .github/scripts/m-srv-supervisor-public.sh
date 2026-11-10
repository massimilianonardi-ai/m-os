#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
helper="$repo/libexec/sys/srv-supervisor"
work="$repo/.s v;$$/long-checkout-root-component-012345678901234567890123456789/another-long-checkout-component-012345678901234567890123456789/third-long-checkout-component-012345678901234567890123456789"
root="$work/installation"
run_root="$root/state/user/default/sys/srv/run"
log_root="$root/state/user/default/sys/srv/log"
bootstrap="$work/bootstrap"
service_pid=
unrelated_pid=
manager_pid=
churn_pid=

cleanup() {
  if [ -n "$service_pid" ] && kill -0 "$service_pid" 2>/dev/null; then
    kill -KILL "$service_pid" 2>/dev/null || :
  fi
  if [ -n "$unrelated_pid" ] && kill -0 "$unrelated_pid" 2>/dev/null; then
    kill "$unrelated_pid" 2>/dev/null || :
    wait "$unrelated_pid" 2>/dev/null || :
  fi
  if [ -n "$manager_pid" ] && kill -0 "$manager_pid" 2>/dev/null; then
    kill -TERM "$manager_pid" 2>/dev/null || :
  fi
  if [ -n "$churn_pid" ] && kill -0 "$churn_pid" 2>/dev/null; then
    kill "$churn_pid" 2>/dev/null || :
    wait "$churn_pid" 2>/dev/null || :
  fi
  rm -rf -- "$work"
}
trap cleanup 0
trap 'exit 130' HUP INT TERM

[ -x "$helper" ] || { echo 'FAIL: native supervisor helper is not built' >&2; exit 1; }
mkdir -p -- "$run_root" "$log_root"
chmod 700 "$root/state" "$root/state/user" "$root/state/user/default" \
  "$root/state/user/default/sys" "$root/state/user/default/sys/srv" \
  "$run_root" "$log_root"
cat > "$bootstrap" <<'EOF_BOOTSTRAP'
#!/bin/sh
case "$1" in
  long) exec /bin/sleep 90 ;;
  ignore-term) trap '' TERM; while :; do /bin/sleep 1; done ;;
  race) exec /bin/sleep 1 ;;
  environment)
    printf '%s\n' "${SUPERVISOR_TEST_TOKEN-unset}" > "$SUPERVISOR_TEST_OUTPUT"
    exec /bin/sleep 90 ;;
  immediate) exit 37 ;;
  *) exit 38 ;;
esac
EOF_BOOTSTRAP
chmod 700 "$bootstrap"

request() {
  request_output=$("$helper" --request "$root" "$run_root" "$log_root/test.log" \
    "$1" "$2" "$3" "$4" "$bootstrap" "$5" "$6") || {
    echo "FAIL: supervisor request transport failed ($4 $1)" >&2
    exit 1
  }
  set -- $request_output
  [ "$#" -eq 2 ] || { echo 'FAIL: malformed helper response' >&2; exit 1; }
  request_result=$1
  request_pid=$2
}

request managed 1001 0 START long provider-a@1
[ "$request_result" -eq 0 ] || { echo "FAIL: start result $request_result" >&2; exit 1; }
service_pid=$request_pid
kill -0 "$service_pid"

# Repeated start is idempotent and does not resolve/reselect the provider.
request managed 1001 0 START immediate provider-b@1
[ "$request_result" -eq 1 ] && [ "$request_pid" = "$service_pid" ] || {
  echo 'FAIL: repeated start did not retain the owned instance' >&2; exit 1;
}

# Caller ownership is enforced by the manager; -f is the explicit override.
request managed 1002 0 STOP '' ''
[ "$request_result" -eq 4 ] && kill -0 "$service_pid" || {
  echo 'FAIL: non-owner stop affected the service' >&2; exit 1;
}
request managed 1002 1 STOP '' ''
[ "$request_result" -eq 2 ] || { echo "FAIL: force stop result $request_result" >&2; exit 1; }
service_pid=
request managed 1001 0 STOP '' ''
[ "$request_result" -eq 3 ] || { echo 'FAIL: stop was not idempotent' >&2; exit 1; }

# A long-lived manager must pass each caller's current environment to its child.
SUPERVISOR_TEST_OUTPUT="$work/environment-result"
SUPERVISOR_TEST_TOKEN=context-one
export SUPERVISOR_TEST_OUTPUT SUPERVISOR_TEST_TOKEN
request context-env 1001 0 START environment provider-a@1
[ "$request_result" -eq 0 ] || { echo 'FAIL: environment fixture did not start' >&2; exit 1; }
service_pid=$request_pid
i=0
while [ ! -s "$SUPERVISOR_TEST_OUTPUT" ] && [ "$i" -lt 10 ]; do i=$((i + 1)); /bin/sleep 1; done
[ "$(cat "$SUPERVISOR_TEST_OUTPUT")" = context-one ] || {
  echo 'FAIL: supervisor did not preserve request environment' >&2; exit 1;
}
request context-env 1001 1 STOP '' ''
[ "$request_result" -eq 2 ] || { echo 'FAIL: environment fixture did not stop' >&2; exit 1; }
service_pid=
SUPERVISOR_TEST_TOKEN=context-two
export SUPERVISOR_TEST_TOKEN
request context-env 1001 0 START environment provider-a@1
[ "$request_result" -eq 0 ] || { echo 'FAIL: second environment fixture did not start' >&2; exit 1; }
service_pid=$request_pid
i=0
while [ "$(cat "$SUPERVISOR_TEST_OUTPUT")" = context-one ] && [ "$i" -lt 10 ]; do i=$((i + 1)); /bin/sleep 1; done
[ "$(cat "$SUPERVISOR_TEST_OUTPUT")" = context-two ] || {
  echo 'FAIL: supervisor reused its startup environment for a later context' >&2; exit 1;
}
request context-env 1001 1 STOP '' ''
[ "$request_result" -eq 2 ] || { echo 'FAIL: second environment fixture did not stop' >&2; exit 1; }
service_pid=
unset SUPERVISOR_TEST_TOKEN SUPERVISOR_TEST_OUTPUT

# A child that exits during startup is never published as a running service.
request immediate-exit 1001 0 START immediate provider-a@1
[ "$request_result" -eq 6 ] && [ ! -e "$run_root/immediate-exit" ] || {
  echo 'FAIL: exited child left a managed runtime record' >&2; exit 1;
}

# A finite timeout leaves the still-owned child tracked for a later stop.
request timeout 1001 0 START ignore-term provider-a@1
[ "$request_result" -eq 0 ] || { echo 'FAIL: timeout fixture did not start' >&2; exit 1; }
service_pid=$request_pid
request timeout 1001 1 STOP '' ''
[ "$request_result" -eq 7 ] && kill -0 "$service_pid" || {
  echo 'FAIL: stop timeout did not preserve the running child' >&2; exit 1;
}
kill -KILL "$service_pid"
service_pid=
i=0
while [ "$i" -lt 20 ]
do
  request timeout 1001 1 STOP '' ''
  [ "$request_result" -eq 3 ] && break
  i=$((i + 1))
  /bin/sleep 1
done
[ "$request_result" -eq 3 ] || { echo 'FAIL: manager did not reap the test child' >&2; exit 1; }

# A PID in external metadata is never signal authority.
/bin/sleep 90 &
unrelated_pid=$!
mkdir -m 700 -- "$run_root/unrelated"
printf '%s\n' "$unrelated_pid" > "$run_root/unrelated/pid"
chmod 600 "$run_root/unrelated/pid"
request unrelated 1001 0 START long provider-a@1
[ "$request_result" -eq 5 ] && kill -0 "$unrelated_pid" || {
  echo 'FAIL: start adopted an unrelated live PID' >&2; exit 1;
}
request unrelated 1001 1 STOP '' ''
[ "$request_result" -eq 5 ] && kill -0 "$unrelated_pid" || {
  echo 'FAIL: stop signaled an unrelated live PID' >&2; exit 1;
}
kill "$unrelated_pid"
wait "$unrelated_pid" 2>/dev/null || :
unrelated_pid=
request unrelated 1001 1 STOP '' ''
[ "$request_result" -eq 3 ] || { echo 'FAIL: dead stale metadata was not cleaned' >&2; exit 1; }

# Killing the supervisor leaves the service unmanaged; restart must fail closed.
request crash 1001 0 START long provider-a@1
[ "$request_result" -eq 0 ] || { echo 'FAIL: crash fixture did not start' >&2; exit 1; }
service_pid=$request_pid
manager_pid=$("$helper" --server-pid "$root")
kill -KILL "$manager_pid"
/bin/sleep 1
kill -0 "$service_pid"
request crash 1001 0 STOP '' ''
[ "$request_result" -eq 5 ] && kill -0 "$service_pid" || {
  echo 'FAIL: stop treated persisted PID as authority after manager crash' >&2; exit 1;
}
manager_pid=$("$helper" --server-pid "$root")
kill -KILL "$service_pid"
service_pid=
/bin/sleep 1
request crash 1001 0 STOP '' ''
[ "$request_result" -eq 3 ] || { echo 'FAIL: exited orphan record did not clean safely' >&2; exit 1; }

# Race child exit against stop while unrelated live sentinels remain untouched.
/bin/sleep 90 &
unrelated_pid=$!
iteration=0
while [ "$iteration" -lt 8 ]
do
  request "race-$iteration" 1001 0 START race provider-a@1
  if [ "$request_result" -eq 0 ]; then
    service_pid=$request_pid
    /bin/sh -c 'i=0; while [ "$i" -lt 50 ]; do /bin/true; i=$((i + 1)); done' &
    churn_pid=$!
    request "race-$iteration" 1001 1 STOP '' ''
    wait "$churn_pid"
    churn_pid=
    case "$request_result" in 2 | 3) : ;; *) echo 'FAIL: exit/stop race result invalid' >&2; exit 1 ;; esac
    service_pid=
  else
    [ "$request_result" -eq 6 ] || { echo 'FAIL: race fixture start result invalid' >&2; exit 1; }
  fi
  kill -0 "$unrelated_pid"
  iteration=$((iteration + 1))
done
kill "$unrelated_pid"
wait "$unrelated_pid" 2>/dev/null || :
unrelated_pid=

manager_pid=$("$helper" --server-pid "$root")
kill -TERM "$manager_pid"
i=0
while [ "$i" -lt 20 ] && kill -0 "$manager_pid" 2>/dev/null
do
  i=$((i + 1)); /bin/sleep 1
done
manager_pid=
echo 'PASS: supervisor ownership, stop semantics, orphan fail-closed, PID safety and exit/stop races'
