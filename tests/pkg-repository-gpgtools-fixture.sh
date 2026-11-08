#!/bin/bash
set -eu

# Run through `./m shell -c '. ./tests/pkg-repository-gpgtools-fixture.sh'`.
# The fake transport keeps this check deterministic and prevents downloads.
_gpgtools_fixture_dir=$(pwd -P)
_gpgtools_fixture_catalog=${GPGTOOLS_FIXTURE_CATALOG:-${GITHUB_WORKSPACE:-$(pwd -P)}/catalog}
source "$_gpgtools_fixture_dir/lib/sys/sh/core.lib.sh"
loadsyslib pkg/repository/pkg-repository-gpgtools

_gpgtools_fixture_repo=$_gpgtools_fixture_catalog/v1/pkg/macgpg/macos-arm64/repository
_gpgtools_fixture_range=$_gpgtools_fixture_catalog/v1/pkg/macgpg/macos-arm64/n0001=2026.1+3633n
_gpgtools_fixture_calls=0
_gpgtools_fixture_index=valid
http-fetch()
{
  _gpgtools_fixture_calls=$((_gpgtools_fixture_calls + 1))
  case "$*" in
    *'https://releases.gpgtools.com/nightlies/')
      if [ "$_gpgtools_fixture_index" = malformed ]; then
        printf '%s\n' '<div class="latest"><table><tr><td>broken</td></tr></table></div>'
      else
        cat <<'EOF_GPGTOOLS_FIXTURE'
<div class="latest">
<table>
<tr>
<td class="date">2026-08-21</td>
<td class='filename'><a href='https://releases.gpgtools.com/nightlies/GPG_Suite-3633n.dmg'>GPGSuite 2026.1 (3633n)</a></td>
<td class='size'>64 MB</td>
<td class='hash'><div class='tooltip' tabindex="1"><span class="sha">SHA256 </span><span class='tooltiptext'>16fa6c1dfa6b440e900632618a6ebaac7d974c3faed3a0e14ce3d1ee6826c9c5</span></div></td>
</tr>
</table>
</div>
EOF_GPGTOOLS_FIXTURE
      fi
      ;;
    *'-l -- https://releases.gpgtools.com/nightlies/GPG_Suite-3633n.dmg')
      printf '%s\n' 67104027
      ;;
    *) return 1;;
  esac
}

_gpgtools_anchor_url=$(cat "$_gpgtools_fixture_repo/url")
[ "$_gpgtools_anchor_url" = 'https://releases.gpgtools.com/nightlies/GPG_Suite-3633n.dmg' ]
_gpgtools_before=$_gpgtools_fixture_calls
[ "$(pkg_repository_resolve_version "$_gpgtools_fixture_repo" '2026.1+3633n')" = '2026.1+3633n' ]
[ "$_gpgtools_fixture_calls" -eq "$_gpgtools_before" ] # pinned exact is local
[ "$(pkg_repository_resolve_version "$_gpgtools_fixture_repo")" = '2026.1+3633n' ] # live latest
[ "${_gpgtools_fixture_range##*/}" = 'n0001=2026.1+3633n' ] # catalog range entry covers live latest
[ "$(pkg_repository_list_versions "$_gpgtools_fixture_repo")" = '2026.1+3633n' ]
[ "$(pkg_repository_compare_versions "$_gpgtools_fixture_repo" '2026.1+3633n' '2026.1+3633n')" = 0 ]
_gpgtools_artifact=$(pkg_repository_resolve_artifact "$_gpgtools_fixture_repo" "$_gpgtools_fixture_range" '2026.1+3633n')
case "$_gpgtools_artifact" in
  *'name=GPG_Suite-3633n.dmg'*'size=67104027'*'digest=sha256:16fa6c1dfa6b440e900632618a6ebaac7d974c3faed3a0e14ce3d1ee6826c9c5'*) :;;
  *) printf '%s\n' "unexpected descriptor: $_gpgtools_artifact" >&2; exit 1;;
esac

_gpgtools_fixture_index=malformed
if _pkg_repository_gpgtools_latest_release >/dev/null 2>&1; then
  echo 'malformed latest index unexpectedly accepted' >&2
  exit 1
fi
echo 'PASS: GPGTools fixture parsing, exact anchor, live latest, artifact metadata and malformed-index rejection'
