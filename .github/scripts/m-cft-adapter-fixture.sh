#!/bin/sh
# Exercise the CfT adapter contract through its real shell library with an
# isolated fake http-fetch executable and exact catalog-shaped descriptors.
set -eu

work=$(mktemp -d "${TMPDIR:-/tmp}/m-cft-adapter.XXXXXXXX") || exit 1
trap 'command -p -- rm -rf -- "$work"' 0
trap 'exit 3' HUP INT TERM

mkdir -p "$work/bin" "$work/repository" "$work/range" || exit 4
printf '%s\n' chrome-for-testing > "$work/repository/type"
printf '%s\n' Stable > "$work/repository/channel"
printf '%s\n' linux-arm64 > "$work/repository/platform"
printf '%s\n' '^chrome-linux-arm64[.]zip$' > "$work/range/archive_regex"
printf '%s\n' md5 > "$work/range/digest_type"

cat > "$work/bin/http-fetch" <<'EOF_HTTP'
#!/bin/sh
case "$*" in
  *LATEST_RELEASE_STABLE*) printf '%s\n' '157.0.8103.38'; exit 0;;
esac
case "${CFT_FIXTURE_MODE:-valid}" in
  wrong-name) name=incorrect/object.zip;;
  *)
    case "$*" in
      *157.0.8103.38*) name=157.0.8103.38/linux-arm64/chrome-linux-arm64.zip;;
      *) name=153.0.8010.12/linux-arm64/chrome-linux-arm64.zip;;
    esac;;
esac
size=195926016
md5=cvNEHdP94czbLvLdzI1d4A==
case "${CFT_FIXTURE_MODE:-valid}" in
  bad-size) size=0;;
  bad-md5) md5=not-base64;;
esac
printf '{"name":"%s","size":"%s","md5Hash":"%s"}\n' "$name" "$size" "$md5"
EOF_HTTP
chmod 700 "$work/bin/http-fetch" || exit 5

./m sh -c '
  . "$m_LIB_DIR/sys/sh/core.lib.sh" || exit 1
  loadsyslib "pkg/repository/pkg-repository-chrome-for-testing" || exit 2
  PATH="$1:$PATH"; export PATH
  repo=$2; range=$3
  [ "$(pkg_repository_compare_versions "$repo" 153.0.9.12 153.0.10.1)" = -1 ] || exit 10
  [ "$(pkg_repository_resolve_version "$repo" 153.0.8010.12)" = 153.0.8010.12 ] || exit 11
  [ "$(pkg_repository_resolve_version "$repo")" = 157.0.8103.38 ] || exit 12
  artifact=$(pkg_repository_resolve_artifact "$repo" "$range" 153.0.8010.12) || exit 13
  printf "%s\n" "$artifact" | grep -F "name=chrome-linux-arm64.zip" >/dev/null || exit 14
  printf "%s\n" "$artifact" | grep -F "size=195926016" >/dev/null || exit 15
  printf "%s\n" "$artifact" | grep -F "digest=md5:72f3441dd3fde1ccdb2ef2ddcc8d5de0" >/dev/null || exit 16

  for mode in wrong-name bad-size bad-md5; do
    CFT_FIXTURE_MODE=$mode; export CFT_FIXTURE_MODE
    if pkg_repository_resolve_version "$repo" 153.0.8010.12 >/dev/null 2>&1; then exit 17; fi
  done
  CFT_FIXTURE_MODE=valid; export CFT_FIXTURE_MODE

  printf "%s\n" "wrong-archive" > "$range/archive_regex"
  if pkg_repository_resolve_artifact "$repo" "$range" 153.0.8010.12 >/dev/null 2>&1; then exit 18; fi
  printf "%s\n" "^chrome-linux-arm64[.]zip$" > "$range/archive_regex"
  printf "%s\n" sha256 > "$range/digest_type"
  if pkg_repository_resolve_artifact "$repo" "$range" 153.0.8010.12 >/dev/null 2>&1; then exit 19; fi
  printf "%s\n" md5 > "$range/digest_type"
  printf "%s\n" fixture-pass
' sh "$work/bin" "$work/repository" "$work/range"
