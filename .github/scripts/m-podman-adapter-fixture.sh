#!/bin/sh

[ -n "${m_ROOT:-}" ] || { printf '%s\n' 'm-podman-adapter-fixture: m environment not initialized' >&2; exit 1; }

. "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 1
. "$m_LIB_DIR/sys/sh/pkg/repository/pkg-repository-podman.lib.sh" || exit 1

podman_fixture_tmp="$(mktemp -d "$m_ROOT/.podman-adapter-fixture.XXXXXX")" || exit 1
podman_fixture_cleanup()
{
  rm -rf -- "$podman_fixture_tmp"
}
trap podman_fixture_cleanup 0 HUP INT TERM

cat > "$podman_fixture_tmp/http-fetch" <<'EOF_PODMAN_HTTP_FETCH'
#!/bin/sh
for podman_fixture_argument
do
  podman_fixture_url=$podman_fixture_argument
done
if [ "${PODMAN_FIXTURE_HTTP_FAILURE:-0}" -eq 1 ]; then
  exit 18
fi
_podman_release_v613()
{
  cat <<'EOF_PODMAN_V613'
{"tag_name":"v6.1.3","draft":false,"prerelease":false,"created_at":"2026-09-29T13:00:27Z","published_at":"2026-09-29T15:34:46Z","assets":[{"name":"podman-installer-macos-arm64.pkg","state":"uploaded","size":76397043,"digest":"sha256:84400d0539b5df0b2f00e9165463d4c17de51933244d1ea4b9cc54d8f05e4de9","browser_download_url":"https://github.com/podman-container-tools/podman/releases/download/v6.1.3/podman-installer-macos-arm64.pkg"}]}
EOF_PODMAN_V613
}

_podman_release_v614()
{
  cat <<'EOF_PODMAN_V614'
{"tag_name":"v6.1.4","draft":false,"prerelease":false,"created_at":"2026-10-12T17:08:34Z","published_at":"2026-10-12T20:59:46Z","assets":[{"name":"podman-installer-macos-arm64.pkg","state":"uploaded","size":76099040,"digest":"sha256:48f675622f66233ca2116e67fdab41ed9dbcc25b48b78a8e6ef0be6549031d22","browser_download_url":"https://github.com/podman-container-tools/podman/releases/download/v6.1.4/podman-installer-macos-arm64.pkg"}]}
EOF_PODMAN_V614
}
case "$podman_fixture_url" in
  'https://api.github.com/repos/podman-container-tools/podman/releases?per_page=100&page=1')
    if [ "${PODMAN_FIXTURE_UNEXPECTED_TAG:-0}" -eq 1 ]
    then
      cat <<'EOF_PODMAN_RELEASES_BAD_TAG'
[{"tag_name":"v6.1.4","draft":false,"prerelease":false,"created_at":"2026-10-12T17:08:34Z","published_at":"2026-10-12T20:59:46Z"},{"tag_name":"v6.1.3-beta1","draft":false,"prerelease":false,"created_at":"2026-10-13T17:08:34Z","published_at":"2026-10-13T20:59:46Z"}]
EOF_PODMAN_RELEASES_BAD_TAG
    else
      cat <<'EOF_PODMAN_RELEASES'
[{"tag_name":"v6.1.4","draft":false,"prerelease":false,"created_at":"2026-10-12T17:08:34Z","published_at":"2026-10-12T20:59:46Z"},{"tag_name":"v6.1.3","draft":false,"prerelease":false,"created_at":"2026-09-29T13:00:27Z","published_at":"2026-09-29T15:34:46Z"},{"tag_name":"v1.7.0-rc1","draft":false,"prerelease":false,"created_at":"2019-12-11T17:49:25Z","published_at":"2019-12-11T19:05:58Z"}]
EOF_PODMAN_RELEASES
    fi
    ;;
  'https://api.github.com/repos/podman-container-tools/podman/releases/latest'|\
  'https://api.github.com/repos/podman-container-tools/podman/releases/tags/v6.1.4')
    _podman_release_v614
    ;;
  'https://api.github.com/repos/podman-container-tools/podman/releases/tags/v6.1.3')
    _podman_release_v613
    ;;
  *)
    printf 'Unexpected Podman fixture URL: %s\n' "$podman_fixture_url" >&2
    exit 1
    ;;
esac
EOF_PODMAN_HTTP_FETCH
chmod 700 "$podman_fixture_tmp/http-fetch" || exit 1
PATH="$podman_fixture_tmp:$PATH"
export PATH

podman_fixture_catalog=${PODMAN_FIXTURE_CATALOG:-catalog}
podman_fixture_repository=$podman_fixture_catalog/v1/pkg/podman/macos-arm64/repository
podman_fixture_range=$podman_fixture_catalog/v1/pkg/podman/macos-arm64/n0001=v6.1.2

podman_fixture_versions="$(pkg_repository_list_versions "$podman_fixture_repository")"
podman_fixture_expected_versions='v6.1.3
v6.1.4'
[ "$podman_fixture_versions" = "$podman_fixture_expected_versions" ] || {
  printf 'Unexpected stable release list:\n%s\n' "$podman_fixture_versions" >&2
  exit 1
}

PODMAN_FIXTURE_UNEXPECTED_TAG=1
export PODMAN_FIXTURE_UNEXPECTED_TAG
if pkg_repository_list_versions "$podman_fixture_repository" >/dev/null 2>&1
then
  printf '%s\n' 'unexpected stable tag did not fail closed' >&2
  exit 1
fi
unset PODMAN_FIXTURE_UNEXPECTED_TAG

[ "$(pkg_repository_resolve_version "$podman_fixture_repository" v6.1.3)" = v6.1.3 ]
[ "$(pkg_repository_resolve_version "$podman_fixture_repository")" = v6.1.4 ]
[ "$(pkg_repository_compare_versions "$podman_fixture_repository" v6.1.3 v6.1.4)" = -1 ]
[ "$(pkg_repository_compare_versions "$podman_fixture_repository" v6.1.4 v6.1.3)" = 1 ]
podman_fixture_artifact="$(pkg_repository_resolve_artifact \
  "$podman_fixture_repository" "$podman_fixture_range" v6.1.4)"
case "$podman_fixture_artifact" in
  *'url=https://github.com/podman-container-tools/podman/releases/download/v6.1.4/podman-installer-macos-arm64.pkg'*'size=76099040'*'digest=sha256:48f675622f66233ca2116e67fdab41ed9dbcc25b48b78a8e6ef0be6549031d22'*) :;;
  *) printf 'Unexpected exact anchor artifact metadata:\n%s\n' "$podman_fixture_artifact" >&2; exit 1;;
esac

podman_fixture_assert_request_failure()
{
  podman_fixture_expected_identity=$1
  podman_fixture_path=$2
  podman_fixture_operation=$3
  if m_LOG_LEVEL=error PODMAN_FIXTURE_HTTP_FAILURE=1 \
    _pkg_repository_podman_get \
      "$podman_fixture_path" "$podman_fixture_operation" \
      >"$podman_fixture_tmp/out" 2>"$podman_fixture_tmp/err"
  then
    printf 'HTTP failure unexpectedly succeeded for %s\n' \
      "$podman_fixture_operation" >&2
    exit 1
  else
    podman_fixture_status=$?
  fi
  [ "$podman_fixture_status" -eq 1 ] || {
    printf 'Unexpected adapter status %s for %s\n' \
      "$podman_fixture_status" "$podman_fixture_operation" >&2
    exit 1
  }
  [ ! -s "$podman_fixture_tmp/out" ] || exit 1
  grep -F "[error] [pkg-repository-podman.$podman_fixture_expected_identity]" \
    "$podman_fixture_tmp/err" >/dev/null || {
      cat "$podman_fixture_tmp/err" >&2
      printf 'Missing request-failure identity %s\n' \
        "$podman_fixture_expected_identity" >&2
      exit 1
    }
  grep -F '[status="18"]' "$podman_fixture_tmp/err" >/dev/null || exit 1
}

podman_fixture_assert_request_failure \
  release-list-request-failed \
  '/releases?per_page=100&page=1' \
  pkg_repository_list_versions
podman_fixture_assert_request_failure \
  latest-release-request-failed \
  /releases/latest \
  pkg_repository_resolve_version
podman_fixture_assert_request_failure \
  exact-release-request-failed \
  /releases/tags/v6.1.3 \
  pkg_repository_resolve_version
podman_fixture_assert_request_failure \
  version-comparison-request-failed \
  /releases/tags/v6.1.3 \
  pkg_repository_compare_versions
podman_fixture_assert_request_failure \
  artifact-metadata-request-failed \
  /releases/tags/v6.1.3 \
  pkg_repository_resolve_artifact

podman_fixture_assert_unsupported_request()
{
  podman_fixture_path=$1
  podman_fixture_operation=$2
  if m_LOG_LEVEL=error _pkg_repository_podman_get \
    "$podman_fixture_path" "$podman_fixture_operation" \
    >"$podman_fixture_tmp/out" 2>"$podman_fixture_tmp/err"
  then
    printf '%s\n' 'Unsupported internal request unexpectedly succeeded' >&2
    exit 1
  else
    podman_fixture_status=$?
  fi
  [ "$podman_fixture_status" -eq 2 ] || exit 1
  [ ! -s "$podman_fixture_tmp/out" ] || exit 1
  grep -F '[error] [pkg-repository-podman.request-operation-unsupported]' \
    "$podman_fixture_tmp/err" >/dev/null || {
    cat "$podman_fixture_tmp/err" >&2
    printf '%s\n' 'Unsupported internal request diagnostic missing' >&2
    exit 1
  }
}
podman_fixture_assert_unsupported_request /releases/latest unsupported-operation
podman_fixture_assert_unsupported_request /unsupported pkg_repository_resolve_version

printf '%s\n' 'PASS: Podman release fixtures, stable tag filtering, exact/latest chronology and anchor asset metadata'
