#!/bin/sh
set -eu

assert_request_failure()
{
  expected_identity=$1
  request_path=$2
  request_operation=$3

  set +e
  request_output=$(
    env \
      HTTPS_PROXY=http://127.0.0.1:9 \
      https_proxy=http://127.0.0.1:9 \
      HTTP_PROXY=http://127.0.0.1:9 \
      http_proxy=http://127.0.0.1:9 \
      ALL_PROXY= \
      all_proxy= \
      NO_PROXY= \
      no_proxy= \
      m_LOG_LEVEL=error \
      SHELL=/bin/sh \
      ./m shell -c '
        . "$m_LIB_DIR/sys/sh/pkg/repository/pkg-repository-geoserver.lib.sh"
        _pkg_repository_geoserver_get "$1" "$2"
      ' geoserver-diagnostics "$request_path" "$request_operation" 2>&1
  )
  request_status=$?
  set -e

  [ "$request_status" -eq 1 ] || {
    printf 'FAIL: %s returned status %s, expected 1\n%s\n' \
      "$request_operation $request_path" "$request_status" "$request_output" >&2
    return 1
  }
  printf '%s\n' "$request_output" | grep -F \
    "[error] [pkg-repository-geoserver.$expected_identity]" >/dev/null || {
    printf 'FAIL: expected diagnostic %s for %s\n%s\n' \
      "$expected_identity" "$request_operation $request_path" "$request_output" >&2
    return 1
  }
}

assert_request_failure release-list-request-failed \
  '/releases?per_page=100&page=1' pkg_repository_list_versions
assert_request_failure latest-release-request-failed \
  /releases/latest pkg_repository_resolve_version
assert_request_failure exact-release-request-failed \
  /releases/tags/3.0.1 pkg_repository_resolve_version
assert_request_failure version-comparison-request-failed \
  /releases/tags/3.0.1 pkg_repository_compare_versions
assert_request_failure artifact-metadata-request-failed \
  /releases/tags/3.0.1 pkg_repository_resolve_artifact

set +e
unsupported_output=$(
  m_LOG_LEVEL=error SHELL=/bin/sh ./m shell -c '
    . "$m_LIB_DIR/sys/sh/pkg/repository/pkg-repository-geoserver.lib.sh"
    _pkg_repository_geoserver_get /unsupported pkg_repository_resolve_version
  ' geoserver-diagnostics 2>&1
)
unsupported_status=$?
set -e
[ "$unsupported_status" -eq 2 ] || {
  printf 'FAIL: unsupported internal request returned status %s, expected 2\n%s\n' \
    "$unsupported_status" "$unsupported_output" >&2
  exit 1
}
printf '%s\n' "$unsupported_output" | grep -F \
  '[error] [pkg-repository-geoserver.request-operation-unsupported]' >/dev/null || {
  printf 'FAIL: unsupported internal request was not rejected distinctly\n%s\n' \
    "$unsupported_output" >&2
  exit 1
}

printf 'PASS: GeoServer upstream request failures keep distinct identities and public status\n'
