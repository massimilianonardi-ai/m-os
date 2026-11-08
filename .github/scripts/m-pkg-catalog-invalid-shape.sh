#!/bin/sh

[ -n "${m_ROOT:-}" ] || { printf '%s\n' 'm-pkg-catalog-invalid-shape: m environment not initialized' >&2; exit 1; }

pkg_catalog_shape_tmp="$(mktemp -d "$m_ROOT/.pkg-catalog-invalid-shape.XXXXXX")" || exit 1
pkg_catalog_shape_config="$(state-path system sys pkg conf)/catalog" || exit 1
pkg_catalog_shape_cache="$(state-path system sys pkg cache)/catalog" || exit 1
pkg_catalog_shape_old_config=0
pkg_catalog_shape_config_saved=0
pkg_catalog_shape_config_modified=0
pkg_catalog_shape_cache_created=0

pkg_catalog_shape_cleanup()
{
  python3 - "$m_ROOT" "$pkg_catalog_shape_tmp" "$pkg_catalog_shape_cache" \
    "$pkg_catalog_shape_config" "$pkg_catalog_shape_old_config" \
    "$pkg_catalog_shape_config_saved" "$pkg_catalog_shape_config_modified" \
    "$pkg_catalog_shape_cache_created" "$pkg_catalog_shape_tmp/original-config" <<'EOF_PKG_CATALOG_SHAPE_CLEANUP'
from pathlib import Path
import shutil
import sys

root = Path(sys.argv[1]).resolve()
scratch = Path(sys.argv[2]).resolve()
cache = Path(sys.argv[3]).resolve()
config = Path(sys.argv[4])
old_config_exists = sys.argv[5] == "1"
config_saved = sys.argv[6] == "1"
config_modified = sys.argv[7] == "1"
cache_created = sys.argv[8] == "1"
backup = Path(sys.argv[9])

for path in (scratch, cache, config):
    resolved = path.resolve(strict=False)
    if not resolved.is_relative_to(root):
        raise SystemExit(f"refusing cleanup outside m_ROOT: {resolved}")

if config_modified:
    if config_saved and old_config_exists:
        shutil.copy2(backup, config)
    elif config.exists() or config.is_symlink():
        config.unlink()

for path in (scratch, cache) if cache_created else (scratch,):
    if path.is_dir():
        shutil.rmtree(path)
    elif path.exists() or path.is_symlink():
        path.unlink()
EOF_PKG_CATALOG_SHAPE_CLEANUP
}
trap 'pkg_catalog_shape_cleanup' 0
trap 'exit 130' HUP INT TERM

if [ -e "$pkg_catalog_shape_config" ] || [ -L "$pkg_catalog_shape_config" ]
then
  [ -f "$pkg_catalog_shape_config" ] && [ ! -L "$pkg_catalog_shape_config" ] || exit 1
  cp -- "$pkg_catalog_shape_config" "$pkg_catalog_shape_tmp/original-config" || exit 1
  pkg_catalog_shape_old_config=1
  pkg_catalog_shape_config_saved=1
fi

[ ! -e "$pkg_catalog_shape_cache" ] && [ ! -L "$pkg_catalog_shape_cache" ] || {
  printf '%s\n' 'catalog cache must be empty in this isolated scenario' >&2
  exit 1
}

pkg_catalog_shape_repo="$pkg_catalog_shape_tmp/catalog"
mkdir -p -- "$pkg_catalog_shape_repo/v1/pkg" \
  "$pkg_catalog_shape_repo/pkg" "$pkg_catalog_shape_repo/facility" || exit 1
printf '%s\n' versioned > "$pkg_catalog_shape_repo/v1/marker" || exit 1
printf '%s\n' versioned-package > "$pkg_catalog_shape_repo/v1/pkg/marker" || exit 1
printf '%s\n' legacy > "$pkg_catalog_shape_repo/pkg/marker" || exit 1
printf '%s\n' legacy > "$pkg_catalog_shape_repo/facility/marker" || exit 1
git -C "$pkg_catalog_shape_repo" init -b main >/dev/null 2>&1 || exit 1
git -C "$pkg_catalog_shape_repo" add v1 pkg facility || exit 1
git -C "$pkg_catalog_shape_repo" \
  -c user.name=Validation \
  -c user.email=validation@example.invalid \
  commit -m 'test fixture: mixed catalog roots' >/dev/null 2>&1 || exit 1
mkdir -p -- "${pkg_catalog_shape_config%/*}" || exit 1
pkg_catalog_shape_config_modified=1
printf '%s\n' "$pkg_catalog_shape_repo" > "$pkg_catalog_shape_config" || exit 1
pkg_catalog_shape_cache_created=1

pkg_catalog_shape_before=
if [ -d "$m_ROOT/pkg" ]
then
  pkg_catalog_shape_before="$(find "$m_ROOT/pkg" -mindepth 1 -maxdepth 1 -print | LC_ALL=C sort)" || exit 1
fi

if ./m pkg requirement list jsc@v0.1.0 \
  >"$pkg_catalog_shape_tmp/requirement.out" \
  2>"$pkg_catalog_shape_tmp/requirement.err"
then
  printf '%s\n' 'pkg requirement list accepted a mixed-schema catalog' >&2
  exit 1
else
  pkg_catalog_shape_requirement_status=$?
fi
[ "$pkg_catalog_shape_requirement_status" -eq 1 ] || exit 1
[ ! -s "$pkg_catalog_shape_tmp/requirement.out" ] || exit 1
grep -F 'pkg-catalog.schema-roots-conflict' \
  "$pkg_catalog_shape_tmp/requirement.err" >/dev/null || exit 1

if ./m pkg install jsc@v0.1.0 \
  >"$pkg_catalog_shape_tmp/install.out" \
  2>"$pkg_catalog_shape_tmp/install.err"
then
  printf '%s\n' 'pkg install accepted a mixed-schema catalog' >&2
  exit 1
else
  pkg_catalog_shape_install_status=$?
fi
[ "$pkg_catalog_shape_install_status" -eq 1 ] || exit 1
[ ! -s "$pkg_catalog_shape_tmp/install.out" ] || exit 1
[ "$(grep -Fc 'pkg-catalog.schema-roots-conflict' \
  "$pkg_catalog_shape_tmp/install.err")" -eq 1 ] || exit 1
if grep -F 'pkg-install.initialization-failed' \
  "$pkg_catalog_shape_tmp/install.err" >/dev/null
then
  printf '%s\n' 'pkg install duplicated the schema diagnostic with a generic fatal' >&2
  exit 1
fi

pkg_catalog_shape_after=
if [ -d "$m_ROOT/pkg" ]
then
  pkg_catalog_shape_after="$(find "$m_ROOT/pkg" -mindepth 1 -maxdepth 1 -print | LC_ALL=C sort)" || exit 1
fi
[ "$pkg_catalog_shape_before" = "$pkg_catalog_shape_after" ] || exit 1

printf '%s\n' 'PASS: public requirement and install reject mixed catalog roots with one specific diagnostic and no package concrete installed'

# A versioned v1 snapshot must contain both required roots. Exercise the public
# query and install commands with an isolated catalog that omits facility/.
rm -rf -- "$pkg_catalog_shape_repo/pkg" "$pkg_catalog_shape_repo/facility"
git -C "$pkg_catalog_shape_repo" add -A || exit 1
git -C "$pkg_catalog_shape_repo" \
  -c user.name=Validation \
  -c user.email=validation@example.invalid \
  commit -m 'test fixture: incomplete versioned catalog roots' >/dev/null 2>&1 || exit 1

if ./m pkg requirement list jsc@v0.1.0 \
  >"$pkg_catalog_shape_tmp/incomplete-requirement.out" \
  2>"$pkg_catalog_shape_tmp/incomplete-requirement.err"
then
  printf '%s\n' 'pkg requirement list accepted an incomplete v1 catalog' >&2
  exit 1
else
  pkg_catalog_shape_requirement_status=$?
fi
[ "$pkg_catalog_shape_requirement_status" -eq 1 ] || exit 1
[ ! -s "$pkg_catalog_shape_tmp/incomplete-requirement.out" ] || exit 1
grep -F 'pkg-catalog.schema-root-incomplete' \
  "$pkg_catalog_shape_tmp/incomplete-requirement.err" >/dev/null || exit 1
grep -F '/v1/facility"' \
  "$pkg_catalog_shape_tmp/incomplete-requirement.err" >/dev/null || {
    cat "$pkg_catalog_shape_tmp/incomplete-requirement.err" >&2
    exit 1
  }

if ./m pkg install jsc@v0.1.0 \
  >"$pkg_catalog_shape_tmp/incomplete-install.out" \
  2>"$pkg_catalog_shape_tmp/incomplete-install.err"
then
  printf '%s\n' 'pkg install accepted an incomplete v1 catalog' >&2
  exit 1
else
  pkg_catalog_shape_install_status=$?
fi
[ "$pkg_catalog_shape_install_status" -eq 1 ] || exit 1
[ ! -s "$pkg_catalog_shape_tmp/incomplete-install.out" ] || exit 1
[ "$(grep -Fc 'pkg-catalog.schema-root-incomplete' \
  "$pkg_catalog_shape_tmp/incomplete-install.err")" -eq 1 ] || exit 1
grep -F '/v1/facility"' \
  "$pkg_catalog_shape_tmp/incomplete-install.err" >/dev/null || exit 1
if grep -F 'pkg-install.initialization-failed' \
  "$pkg_catalog_shape_tmp/incomplete-install.err" >/dev/null
then
  printf '%s\n' 'pkg install duplicated the incomplete-schema diagnostic' >&2
  exit 1
fi

pkg_catalog_shape_after=
if [ -d "$m_ROOT/pkg" ]
then
  pkg_catalog_shape_after="$(find "$m_ROOT/pkg" -mindepth 1 -maxdepth 1 -print | LC_ALL=C sort)" || exit 1
fi
[ "$pkg_catalog_shape_before" = "$pkg_catalog_shape_after" ] || exit 1

printf '%s\n' 'PASS: public requirement and install reject an incomplete v1 catalog with one specific diagnostic and no package concrete installed'

# Exercise the other mandatory v1 root independently. Keep the fixture history
# linear so the product's normal cached-checkout refresh path remains genuine.
rm -rf -- "$pkg_catalog_shape_repo/v1/pkg"
mkdir -p -- "$pkg_catalog_shape_repo/v1/facility" || exit 1
printf '%s\n' facility > "$pkg_catalog_shape_repo/v1/facility/marker" || exit 1
git -C "$pkg_catalog_shape_repo" add -A || exit 1
git -C "$pkg_catalog_shape_repo" \
  -c user.name=Validation \
  -c user.email=validation@example.invalid \
  commit -m 'test fixture: missing versioned package root' >/dev/null 2>&1 || exit 1

if ./m pkg requirement list jsc@v0.1.0 \
  >"$pkg_catalog_shape_tmp/missing-pkg-requirement.out" \
  2>"$pkg_catalog_shape_tmp/missing-pkg-requirement.err"
then
  printf '%s\n' 'pkg requirement list accepted a v1 catalog missing pkg/' >&2
  exit 1
else
  pkg_catalog_shape_requirement_status=$?
fi
[ "$pkg_catalog_shape_requirement_status" -eq 1 ] || exit 1
[ ! -s "$pkg_catalog_shape_tmp/missing-pkg-requirement.out" ] || exit 1
grep -F 'pkg-catalog.schema-root-incomplete' \
  "$pkg_catalog_shape_tmp/missing-pkg-requirement.err" >/dev/null || exit 1
grep -F '/v1/pkg"' \
  "$pkg_catalog_shape_tmp/missing-pkg-requirement.err" >/dev/null || exit 1

if ./m pkg install jsc@v0.1.0 \
  >"$pkg_catalog_shape_tmp/missing-pkg-install.out" \
  2>"$pkg_catalog_shape_tmp/missing-pkg-install.err"
then
  printf '%s\n' 'pkg install accepted a v1 catalog missing pkg/' >&2
  exit 1
else
  pkg_catalog_shape_install_status=$?
fi
[ "$pkg_catalog_shape_install_status" -eq 1 ] || exit 1
[ ! -s "$pkg_catalog_shape_tmp/missing-pkg-install.out" ] || exit 1
[ "$(grep -Fc 'pkg-catalog.schema-root-incomplete' \
  "$pkg_catalog_shape_tmp/missing-pkg-install.err")" -eq 1 ] || exit 1
grep -F '/v1/pkg"' \
  "$pkg_catalog_shape_tmp/missing-pkg-install.err" >/dev/null || exit 1
if grep -F 'pkg-install.initialization-failed' \
  "$pkg_catalog_shape_tmp/missing-pkg-install.err" >/dev/null
then
  printf '%s\n' 'pkg install duplicated the missing-pkg schema diagnostic' >&2
  exit 1
fi

pkg_catalog_shape_after=
if [ -d "$m_ROOT/pkg" ]
then
  pkg_catalog_shape_after="$(find "$m_ROOT/pkg" -mindepth 1 -maxdepth 1 -print | LC_ALL=C sort)" || exit 1
fi
[ "$pkg_catalog_shape_before" = "$pkg_catalog_shape_after" ] || exit 1

printf '%s\n' 'PASS: public requirement and install reject a v1 catalog missing pkg/ with one specific diagnostic and no package concrete installed'
