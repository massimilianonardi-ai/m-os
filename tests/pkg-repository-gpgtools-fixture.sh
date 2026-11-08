#!/bin/sh
set -eu

# Run through `./m shell -c '. ./tests/pkg-repository-gpgtools-fixture.sh'`.
# The fake transport keeps this check deterministic and prevents downloads.
_gpgtools_fixture_dir=$(pwd -P)
_gpgtools_fixture_catalog=${GPGTOOLS_FIXTURE_CATALOG:-${GITHUB_WORKSPACE:-$(pwd -P)}/catalog}
. "$_gpgtools_fixture_dir/lib/sys/sh/core.lib.sh"
loadsyslib pkg/repository/pkg-repository-gpgtools

_gpgtools_fixture_repo=$_gpgtools_fixture_catalog/v1/pkg/macgpg/macos-arm64/repository
_gpgtools_fixture_range=$_gpgtools_fixture_catalog/v1/pkg/macgpg/macos-arm64/n0001=2026.1+3633n
_gpgtools_fixture_tmp=$(mktemp -d "${GPGTOOLS_FIXTURE_TMP_BASE:-$(pwd -P)/.tmp-gpgtools-fixture}.XXXXXX")
trap 'rm -rf -- "$_gpgtools_fixture_tmp"' 0 HUP INT TERM
mkdir -p "$_gpgtools_fixture_tmp/bin"
export GPGTOOLS_FIXTURE_STATE="$_gpgtools_fixture_tmp/state"
printf '%s\n' valid > "$GPGTOOLS_FIXTURE_STATE"
GPGTOOLS_FIXTURE_TMP_CALLS="$_gpgtools_fixture_tmp/calls"
export GPGTOOLS_FIXTURE_TMP_CALLS
printf '%s\n' 0 > "$GPGTOOLS_FIXTURE_TMP_CALLS"
cat > "$_gpgtools_fixture_tmp/bin/http-fetch" <<'EOF_GPGTOOLS_COMMAND'
#!/bin/sh
calls=$(cat "$GPGTOOLS_FIXTURE_TMP_CALLS")
printf '%s\n' "$((calls + 1))" > "$GPGTOOLS_FIXTURE_TMP_CALLS"
case "$*" in
  *'https://releases.gpgtools.com/nightlies/')
    if [ "$(cat "$GPGTOOLS_FIXTURE_STATE")" = malformed ]; then
      printf '%s\n' '<div class="latest"><table><tr><td>broken</td></tr></table></div>'
    else
      cat <<'EOF_GPGTOOLS_PAGE'
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
EOF_GPGTOOLS_PAGE
    fi
    ;;
  *'-l -- https://releases.gpgtools.com/nightlies/GPG_Suite-3633n.dmg') printf '%s\n' 67104027;;
  *) exit 1;;
esac
EOF_GPGTOOLS_COMMAND
chmod +x "$_gpgtools_fixture_tmp/bin/http-fetch"
PATH="$_gpgtools_fixture_tmp/bin:$PATH"
export PATH

_gpgtools_anchor_url=$(cat "$_gpgtools_fixture_repo/url")
[ "$_gpgtools_anchor_url" = 'https://releases.gpgtools.com/nightlies/GPG_Suite-3633n.dmg' ]
_gpgtools_before=$(cat "$GPGTOOLS_FIXTURE_TMP_CALLS")
[ "$(pkg_repository_resolve_version "$_gpgtools_fixture_repo" '2026.1+3633n')" = '2026.1+3633n' ]
[ "$(cat "$GPGTOOLS_FIXTURE_TMP_CALLS")" -eq "$_gpgtools_before" ] # pinned exact is local
[ "$(pkg_repository_resolve_version "$_gpgtools_fixture_repo")" = '2026.1+3633n' ] # live latest
[ "${_gpgtools_fixture_range##*/}" = 'n0001=2026.1+3633n' ] # catalog range entry covers live latest
[ "$(pkg_repository_list_versions "$_gpgtools_fixture_repo")" = '2026.1+3633n' ]
[ "$(pkg_repository_compare_versions "$_gpgtools_fixture_repo" '2026.1+3633n' '2026.1+3633n')" = 0 ]
_gpgtools_artifact=$(pkg_repository_resolve_artifact "$_gpgtools_fixture_repo" "$_gpgtools_fixture_range" '2026.1+3633n')
case "$_gpgtools_artifact" in
  *'name=GPG_Suite-3633n.dmg'*'size=67104027'*'digest=sha256:16fa6c1dfa6b440e900632618a6ebaac7d974c3faed3a0e14ce3d1ee6826c9c5'*) :;;
  *) printf '%s\n' "unexpected descriptor: $_gpgtools_artifact" >&2; exit 1;;
esac

printf '%s\n' malformed > "$GPGTOOLS_FIXTURE_STATE"
if _pkg_repository_gpgtools_latest_release >/dev/null 2>&1; then
  echo 'malformed latest index unexpectedly accepted' >&2
  exit 1
fi
echo 'PASS: GPGTools fixture parsing, exact anchor, live latest, artifact metadata and malformed-index rejection'
