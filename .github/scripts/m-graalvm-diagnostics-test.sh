#!/bin/sh

set -eu

[ -n "${m_ROOT:-}" ] || exit 2
[ -n "${GRAALVM_DIAGNOSTIC_TMP_BASE:-}" ] || exit 2

work="$GRAALVM_DIAGNOSTIC_TMP_BASE"
[ ! -e "$work" ] && [ ! -L "$work" ] || exit 2
mkdir -p "$work/bin"
cat > "$work/bin/http-fetch" <<'EOF_HTTP_FETCH'
#!/bin/sh
: > "$GRAALVM_HTTP_FETCH_MARKER"
exit 17
EOF_HTTP_FETCH
chmod +x "$work/bin/http-fetch"
PATH="$work/bin:$PATH"
GRAALVM_HTTP_FETCH_MARKER=$work/http-fetch-called
export PATH GRAALVM_HTTP_FETCH_MARKER

. "$m_LIB_DIR/sys/sh/core.lib.sh"
. "$m_LIB_DIR/sys/sh/pkg/repository/pkg-repository-graalvm.lib.sh"

check_failed_request()
(
  [ "$#" -eq 4 ] || exit 2
  pkg_repository_graalvm_expected_message=$1
  pkg_repository_graalvm_path=$2
  pkg_repository_graalvm_operation=$3
  pkg_repository_graalvm_case=$4
  pkg_repository_graalvm_stdout=$work/$pkg_repository_graalvm_case.out
  pkg_repository_graalvm_stderr=$work/$pkg_repository_graalvm_case.err

  if _pkg_repository_graalvm_get \
    "$pkg_repository_graalvm_path" \
    "$pkg_repository_graalvm_operation" \
    > "$pkg_repository_graalvm_stdout" \
    2> "$pkg_repository_graalvm_stderr"
  then
    echo "FAIL: request succeeded: $pkg_repository_graalvm_case" >&2
    exit 1
  else
    pkg_repository_graalvm_status=$?
  fi

  [ "$pkg_repository_graalvm_status" -eq 1 ] || {
    echo "FAIL: wrong adapter status for $pkg_repository_graalvm_case: $pkg_repository_graalvm_status" >&2
    exit 1
  }
  [ ! -s "$pkg_repository_graalvm_stdout" ] || {
    echo "FAIL: request emitted stdout: $pkg_repository_graalvm_case" >&2
    exit 1
  }
  grep -F \
    "[error] [pkg-repository-graalvm.$pkg_repository_graalvm_expected_message]" \
    "$pkg_repository_graalvm_stderr" >/dev/null || {
      cat "$pkg_repository_graalvm_stderr" >&2
      echo "FAIL: missing request diagnostic identity: $pkg_repository_graalvm_case" >&2
      exit 1
    }
  grep -F 'status="17"' "$pkg_repository_graalvm_stderr" >/dev/null || {
    echo "FAIL: child status field missing: $pkg_repository_graalvm_case" >&2
    exit 1
  }
)

check_failed_request \
  release-list-request-failed \
  '/releases?per_page=100&page=1' \
  pkg_repository_list_versions \
  list
check_failed_request \
  latest-release-request-failed \
  /releases/latest \
  pkg_repository_resolve_version \
  latest
check_failed_request \
  exact-release-request-failed \
  /releases/tags/jdk-25.3.4.1 \
  pkg_repository_resolve_version \
  exact
check_failed_request \
  artifact-metadata-request-failed \
  /releases/tags/jdk-25.3.4.1 \
  pkg_repository_resolve_artifact \
  artifact

mkdir -p "$work/repository"
printf '%s\n' graalvm > "$work/repository/type"
printf '%s\n' graalvm > "$work/repository/owner"
printf '%s\n' graalvm-ce-builds > "$work/repository/repository"
printf '%s\n' 25.3.4.1 25.5.5.0.3 > "$work/repository/versions"
rm -f "$GRAALVM_HTTP_FETCH_MARKER"
pkg_repository_graalvm_resolved="$(set +e; pkg_repository_resolve_version \
  "$work/repository" 25.3.4.1)" || {
  echo 'FAIL: indexed exact GraalVM version did not resolve offline' >&2
  exit 1
}
[ "$pkg_repository_graalvm_resolved" = 25.3.4.1 ] || {
  echo "FAIL: indexed exact GraalVM version resolved incorrectly: $pkg_repository_graalvm_resolved" >&2
  exit 1
}
[ ! -e "$GRAALVM_HTTP_FETCH_MARKER" ] || {
  echo 'FAIL: indexed exact GraalVM resolution used upstream transport' >&2
  exit 1
}

rm -f "$GRAALVM_HTTP_FETCH_MARKER"
if _pkg_repository_graalvm_get /releases/latest unknown_operation \
  > "$work/unknown-operation.out" \
  2> "$work/unknown-operation.err"
then
  echo 'FAIL: unknown request operation was accepted' >&2
  exit 1
else
  status=$?
fi
[ "$status" -eq 2 ] && [ ! -e "$GRAALVM_HTTP_FETCH_MARKER" ] || {
  echo 'FAIL: unknown request operation was not rejected before transport' >&2
  exit 1
}
grep -F '[error] [pkg-repository-graalvm.request-operation-unsupported]' \
  "$work/unknown-operation.err" >/dev/null || {
  cat "$work/unknown-operation.err" >&2
  echo 'FAIL: unknown operation diagnostic identity missing' >&2
  exit 1
}
grep -F 'operation="unknown_operation"' "$work/unknown-operation.err" >/dev/null || {
  echo 'FAIL: unknown operation diagnostic field missing' >&2
  exit 1
}
grep -F 'path="/releases/latest"' "$work/unknown-operation.err" >/dev/null || {
  echo 'FAIL: unknown operation path field missing' >&2
  exit 1
}

if _pkg_repository_graalvm_get /releases/unexpected pkg_repository_resolve_version \
  > "$work/unknown-path.out" \
  2> "$work/unknown-path.err"
then
  echo 'FAIL: unknown request path was accepted' >&2
  exit 1
else
  status=$?
fi
[ "$status" -eq 2 ] && [ ! -e "$GRAALVM_HTTP_FETCH_MARKER" ] || {
  echo 'FAIL: unknown request path was not rejected before transport' >&2
  exit 1
}
grep -F '[error] [pkg-repository-graalvm.request-operation-unsupported]' \
  "$work/unknown-path.err" >/dev/null || {
  cat "$work/unknown-path.err" >&2
  echo 'FAIL: unknown path diagnostic identity missing' >&2
  exit 1
}
grep -F 'operation="pkg_repository_resolve_version"' "$work/unknown-path.err" >/dev/null || {
  echo 'FAIL: unknown path operation field missing' >&2
  exit 1
}
grep -F 'path="/releases/unexpected"' "$work/unknown-path.err" >/dev/null || {
  echo 'FAIL: unknown path diagnostic field missing' >&2
  exit 1
}

rm -f \
  "$work/bin/http-fetch" \
  "$work/http-fetch-called" \
  "$work/repository/type" \
  "$work/repository/owner" \
  "$work/repository/repository" \
  "$work/repository/versions" \
  "$work/list.out" "$work/list.err" \
  "$work/latest.out" "$work/latest.err" \
  "$work/exact.out" "$work/exact.err" \
  "$work/artifact.out" "$work/artifact.err" \
  "$work/unknown-operation.out" "$work/unknown-operation.err" \
  "$work/unknown-path.out" "$work/unknown-path.err"
rmdir "$work/repository" "$work/bin" "$work"

echo 'PASS: GraalVM exact-index resolution is offline and upstream failures have stable operation-specific identities'
