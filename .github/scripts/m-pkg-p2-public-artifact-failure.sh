#!/bin/sh
# Exercise a complete public pkg install until a controlled corrupt HTTPS
# artifact is rejected. The catalog is an ordinary local Git snapshot with
# one test-owned package; product commands, repository adapter, HTTP fetch,
# digest check, installer and cleanup are all the unmodified real targets.
set -eu

work=$(mktemp -d "${TMPDIR:-/tmp}/m-p2-install.XXXXXXXX") || exit 1
trap 'command -p -- rm -rf -- "$work"' 0
trap 'exit 3' HUP INT TERM

source_revision=$(git rev-parse HEAD) || exit 2
catalog_revision=4083aa19c4362f00ec62428a631edfa493faf7f0
fixture_revision=e99801c35e8a5144e75283d934187363cdf72275
target="$work/m-os"
catalog="$work/catalog"

command -p -- mkdir -- "$target" || exit 4
git archive "$source_revision" | command -p -- tar -xf - -C "$target" || exit 5
git clone --quiet -- https://github.com/massimilianonardi-ai/pkg-catalog.git "$catalog" || exit 6
git -C "$catalog" checkout --quiet "$catalog_revision" || exit 7
git -C "$catalog" checkout --quiet -b p2-ci-fixture || exit 22

package="$catalog/v1/pkg/p2bad/all"
range="$package/n0001=v0.1.0"
repository="$package/repository"
command -p -- mkdir -p -- "$range" "$repository/download" "$repository/metadata" || exit 8

printf 'zip\n' > "$range/format"
printf '^p2bad-v0[.]1[.]0[.]bin$\n' > "$range/archive_regex"
printf 'sha256\n' > "$range/digest_type"

printf 'github\n' > "$repository/type"
printf 'massimilianonardi-ai\n' > "$repository/owner"
printf 'm-mk\n' > "$repository/repository"
printf 'template-url\n' > "$repository/download/type"
printf 'p2bad-{version}.bin\n' > "$repository/download/name-template"
printf 'https://raw.githubusercontent.com/massimilianonardi-ai/m-os/%s/.github/scripts/m-pkg-p2-negatives.sh\n' "$fixture_revision" > "$repository/download/url-template"
printf 'checksum-sidecar\n' > "$repository/metadata/type"
printf 'https://raw.githubusercontent.com/massimilianonardi-ai/m-os/%s/.github/fixtures/m-pkg-p2-bad.sha256\n' "$fixture_revision" > "$repository/metadata/url-template"
printf 'digest-only\n' > "$repository/metadata/record-format"

git -C "$catalog" add -- v1/pkg/p2bad || exit 9
git -C "$catalog" -c user.name='RumiAI P2 CI' -c user.email='p2-ci@localhost' commit --quiet -m 'test fixture: bad checksum for public install' || exit 10

cd "$target" || exit 11
./m osarch update || exit 12
conf=$(./m state-path system sys pkg conf) || exit 13
command -p -- mkdir -p -- "$conf" || exit 14
printf '%s\n' "$catalog" > "$conf/catalog"

set +e
./m pkg install p2bad@v0.1.0 > "$work/install.out" 2>&1
status=$?
set -e
[ "$status" -eq 1 ] || { command -p -- cat "$work/install.out"; exit 15; }
command -p -- grep 'digest-mismatch' "$work/install.out" || exit 16
command -p -- grep 'pkg-install.download-failed' "$work/install.out" || exit 17

[ ! -e pkg/p2bad@v0.1.0 ] && [ ! -L pkg/p2bad@v0.1.0 ] || exit 18
[ ! -e pkg/p2bad ] && [ ! -L pkg/p2bad ] || exit 19
temp=$(./m state-path system sys pkg tmp) || exit 20
for entry in "$temp"/install2-*
do
  [ ! -e "$entry" ] && [ ! -L "$entry" ] || exit 21
done

echo 'PASS: P2 public pkg install rejected corrupt HTTPS artifact without publishing a partial concrete'
