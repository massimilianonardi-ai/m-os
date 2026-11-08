loadsyslib "json"

_pkg_repository_podman_scalar()
{
  [ "$#" -eq 1 ] || return 2
  pkg_repository_podman_scalar_file=$1
  [ -f "$pkg_repository_podman_scalar_file" ] &&
    [ ! -L "$pkg_repository_podman_scalar_file" ] &&
    [ -r "$pkg_repository_podman_scalar_file" ] &&
    [ ! -x "$pkg_repository_podman_scalar_file" ] || return 1

  pkg_repository_podman_scalar_value=
  pkg_repository_podman_scalar_extra=
  {
    IFS= read -r pkg_repository_podman_scalar_value || return 1
    IFS= read -r pkg_repository_podman_scalar_extra
    pkg_repository_podman_scalar_second_status=$?
  } < "$pkg_repository_podman_scalar_file"
  [ "$pkg_repository_podman_scalar_second_status" -ne 0 ] || return 1
  [ -z "$pkg_repository_podman_scalar_extra" ] &&
    [ -n "$pkg_repository_podman_scalar_value" ] || return 1
  pkg_repository_podman_scalar_actual="$(command -p -- wc -c < "$pkg_repository_podman_scalar_file")" || return 1
  pkg_repository_podman_scalar_expected="$(printf '%s\n' "$pkg_repository_podman_scalar_value" | command -p -- wc -c)" || return 1
  [ "$pkg_repository_podman_scalar_actual" = "$pkg_repository_podman_scalar_expected" ] || return 1
  pkg_repository_podman_scalar_cr="$(printf '\r')"
  case "$pkg_repository_podman_scalar_value" in *"$pkg_repository_podman_scalar_cr"*) return 1;; esac
  printf '%s\n' "$pkg_repository_podman_scalar_value"
}

_pkg_repository_podman_validate_version()
{
  [ "$#" -eq 1 ] || return 2
  LC_ALL=C command -p -- awk -v version="$1" '
BEGIN { exit(version ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/ ? 0 : 1) }
'
}

_pkg_repository_podman_validate_repository()
{
  [ "$#" -eq 1 ] || return 2
  pkg_repository_podman_repository_dir=$1
  [ -d "$pkg_repository_podman_repository_dir" ] &&
    [ ! -L "$pkg_repository_podman_repository_dir" ] || return 1
  for pkg_repository_podman_item in \
    "$pkg_repository_podman_repository_dir"/* \
    "$pkg_repository_podman_repository_dir"/.[!.]* \
    "$pkg_repository_podman_repository_dir"/..?*
  do
    [ -e "$pkg_repository_podman_item" ] || [ -L "$pkg_repository_podman_item" ] || continue
    case "${pkg_repository_podman_item##*/}" in
      type|url|version|digest)
        [ -f "$pkg_repository_podman_item" ] &&
          [ ! -L "$pkg_repository_podman_item" ] &&
          [ -r "$pkg_repository_podman_item" ] &&
          [ ! -x "$pkg_repository_podman_item" ] || return 1
        ;;
      *) return 1;;
    esac
  done
  pkg_repository_podman_type="$( _pkg_repository_podman_scalar "$pkg_repository_podman_repository_dir/type" )" || return 1
  pkg_repository_podman_url="$( _pkg_repository_podman_scalar "$pkg_repository_podman_repository_dir/url" )" || return 1
  pkg_repository_podman_anchor="$( _pkg_repository_podman_scalar "$pkg_repository_podman_repository_dir/version" )" || return 1
  pkg_repository_podman_digest="$( _pkg_repository_podman_scalar "$pkg_repository_podman_repository_dir/digest" )" || return 1
  [ "$pkg_repository_podman_type" = podman ] || return 1
  _pkg_repository_podman_validate_version "$pkg_repository_podman_anchor" || return 1
  [ "$pkg_repository_podman_url" = \
    "https://github.com/podman-container-tools/podman/releases/download/$pkg_repository_podman_anchor/podman-installer-macos-arm64.pkg" ] || return 1
  case "$pkg_repository_podman_digest" in *[!0-9a-fA-F]*|'') return 1;; esac
  [ "${#pkg_repository_podman_digest}" -eq 64 ]
}

_pkg_repository_podman_get()
{
  [ "$#" -eq 2 ] || return 2
  pkg_repository_podman_path=$1
  pkg_repository_podman_operation=$2
  pkg_repository_podman_url="https://api.github.com/repos/podman-container-tools/podman$pkg_repository_podman_path"
  http-fetch \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2026-03-10' \
    -- "$pkg_repository_podman_url"
  pkg_repository_podman_status=$?
  [ "$pkg_repository_podman_status" -eq 0 ] && return 0
  log error execution execution-failed \
    operation pkg-repository-podman \
    reason upstream-request-failed \
    function "$pkg_repository_podman_operation" \
    url "$pkg_repository_podman_url" \
    status "$pkg_repository_podman_status" || :
  return 1
}

_pkg_repository_podman_release_tokens()
{
  [ "$#" -eq 5 ] || return 2
  case "$1" in s:*) pkg_repository_podman_tag=${1#s:};; *) return 1;; esac
  [ "$2" = b:false ] && [ "$3" = b:false ] || return 1
  _pkg_repository_podman_validate_version "$pkg_repository_podman_tag" || return 1
  case "$4" in s:*) pkg_repository_podman_created=${4#s:};; *) return 1;; esac
  case "$5" in s:*) pkg_repository_podman_published=${5#s:};; *) return 1;; esac
  LC_ALL=C command -p -- awk \
    -v created="$pkg_repository_podman_created" \
    -v published="$pkg_repository_podman_published" '
BEGIN {
  timestamp="^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$"
  exit(created ~ timestamp && published ~ timestamp ? 0 : 1)
}
' || return 1
  printf '%s\t%s\t%s\n' \
    "$pkg_repository_podman_created" \
    "$pkg_repository_podman_published" \
    "$pkg_repository_podman_tag"
}

_pkg_repository_podman_release_body_validate()
{
  [ "$#" -eq 2 ] || return 2
  pkg_repository_podman_body=$1
  pkg_repository_podman_expected_version=$2
  json_object_read \
    tag_name pkg_repository_podman_tag_token \
    draft pkg_repository_podman_draft_token \
    prerelease pkg_repository_podman_prerelease_token \
    created_at pkg_repository_podman_created_token \
    published_at pkg_repository_podman_published_token <<EOF_PODMAN_RELEASE
$pkg_repository_podman_body
EOF_PODMAN_RELEASE
  [ "$?" -eq 0 ] || return 1
  pkg_repository_podman_record="$( _pkg_repository_podman_release_tokens \
    "$pkg_repository_podman_tag_token" \
    "$pkg_repository_podman_draft_token" \
    "$pkg_repository_podman_prerelease_token" \
    "$pkg_repository_podman_created_token" \
    "$pkg_repository_podman_published_token")" || return 1
  pkg_repository_podman_tab="$(printf '\t')"
  IFS="$pkg_repository_podman_tab" read -r \
    pkg_repository_podman_created \
    pkg_repository_podman_published \
    pkg_repository_podman_tag \
    pkg_repository_podman_extra <<EOF_PODMAN_RELEASE_RECORD
$pkg_repository_podman_record
EOF_PODMAN_RELEASE_RECORD
  [ -z "$pkg_repository_podman_extra" ] &&
    [ "$pkg_repository_podman_tag" = "$pkg_repository_podman_expected_version" ] || return 1
  printf '%s\t%s\t%s\n' \
    "$pkg_repository_podman_created" \
    "$pkg_repository_podman_published" \
    "$pkg_repository_podman_tag"
}

_pkg_repository_podman_release_records()
(
  [ "$#" -eq 1 ] || return 2
  _pkg_repository_podman_validate_repository "$1" || return 1
  pkg_repository_podman_page=1
  pkg_repository_podman_records=
  pkg_repository_podman_lf='
'
  pkg_repository_podman_tab="$(printf '\t')"
  while :
  do
    pkg_repository_podman_body="$( _pkg_repository_podman_get \
      "/releases?per_page=100&page=$pkg_repository_podman_page" \
      pkg_repository_list_versions )" || return 1
    pkg_repository_podman_tokens="$(printf '%s\n' "$pkg_repository_podman_body" | \
      json_array_object_fields tag_name draft prerelease created_at published_at)" || return 1
    pkg_repository_podman_count=0
    if [ -n "$pkg_repository_podman_tokens" ]
    then
      while IFS="$pkg_repository_podman_tab" read -r pkg_repository_podman_tag_token pkg_repository_podman_draft_token pkg_repository_podman_prerelease_token pkg_repository_podman_created_token pkg_repository_podman_published_token pkg_repository_podman_extra; do
        [ -z "$pkg_repository_podman_extra" ] || return 1
        pkg_repository_podman_count=$((pkg_repository_podman_count + 1))
        case "$pkg_repository_podman_draft_token" in
          b:true) continue;;
          b:false) :;;
          *) return 1;;
        esac
        case "$pkg_repository_podman_prerelease_token" in
          b:true) continue;;
          b:false) :;;
          *) return 1;;
        esac
        pkg_repository_podman_record="$( _pkg_repository_podman_release_tokens \
          "$pkg_repository_podman_tag_token" \
          "$pkg_repository_podman_draft_token" \
          "$pkg_repository_podman_prerelease_token" \
          "$pkg_repository_podman_created_token" \
          "$pkg_repository_podman_published_token")" || return 1
        if [ -n "$pkg_repository_podman_records" ]
        then pkg_repository_podman_records="$pkg_repository_podman_records$pkg_repository_podman_lf$pkg_repository_podman_record"
        else pkg_repository_podman_records=$pkg_repository_podman_record
        fi
      done <<EOF_PODMAN_RELEASES
$pkg_repository_podman_tokens
EOF_PODMAN_RELEASES
    fi
    [ "$pkg_repository_podman_count" -ge 100 ] || break
    pkg_repository_podman_page=$((pkg_repository_podman_page + 1))
  done
  [ -n "$pkg_repository_podman_records" ] || return 0
  printf '%s\n' "$pkg_repository_podman_records" | \
    LC_ALL=C command -p -- sort -t "$pkg_repository_podman_tab" -k1,1 -k2,2 -k3,3 | \
    LC_ALL=C command -p -- awk -F "$pkg_repository_podman_tab" '
NF != 3 { exit 1 }
{
  if (previous_created == $1 && previous_published == $2) exit 1
  if (seen[$3]++) exit 1
  previous_created=$1
  previous_published=$2
  print $1 "\t" $2 "\t" $3
}
'
)

pkg_repository_list_versions()
(
  [ "$#" -eq 1 ] || return 2
  pkg_repository_podman_records="$( _pkg_repository_podman_release_records "$1" )" || return 1
  [ -n "$pkg_repository_podman_records" ] || return 0
  pkg_repository_podman_tab="$(printf '\t')"
  printf '%s\n' "$pkg_repository_podman_records" | \
    LC_ALL=C command -p -- awk -F "$pkg_repository_podman_tab" '
NF != 3 { exit 1 }
{ print $3 }
'
)

pkg_repository_compare_versions()
(
  [ "$#" -eq 3 ] || return 2
  pkg_repository_podman_repository_dir=$1
  pkg_repository_podman_left=$2
  pkg_repository_podman_right=$3
  _pkg_repository_podman_validate_repository "$pkg_repository_podman_repository_dir" || return 1
  _pkg_repository_podman_validate_version "$pkg_repository_podman_left" || return 1
  _pkg_repository_podman_validate_version "$pkg_repository_podman_right" || return 1
  if [ "$pkg_repository_podman_left" = "$pkg_repository_podman_right" ]
  then printf '0\n'; return 0; fi
  pkg_repository_podman_records="$( _pkg_repository_podman_release_records "$pkg_repository_podman_repository_dir" )" || return 1
  [ -n "$pkg_repository_podman_records" ] || return 1
  pkg_repository_podman_tab="$(printf '\t')"
  printf '%s\n' "$pkg_repository_podman_records" | \
    LC_ALL=C command -p -- awk -F "$pkg_repository_podman_tab" \
      -v left="$pkg_repository_podman_left" \
      -v right="$pkg_repository_podman_right" '
NF != 3 { exit 1 }
$3 == left { left_position=NR }
$3 == right { right_position=NR }
END {
  if (!left_position || !right_position) exit 1
  if (left_position < right_position) print "-1"
  else if (left_position > right_position) print "1"
  else print "0"
}
'
)

pkg_repository_resolve_version()
(
  [ "$#" -ge 1 ] && [ "$#" -le 2 ] || return 2
  pkg_repository_podman_repository_dir=$1
  _pkg_repository_podman_validate_repository "$pkg_repository_podman_repository_dir" || return 1
  if [ "$#" -eq 2 ]
  then
    pkg_repository_podman_version=$2
    _pkg_repository_podman_validate_version "$pkg_repository_podman_version" || return 1
    pkg_repository_podman_records="$( _pkg_repository_podman_release_records "$pkg_repository_podman_repository_dir" )" || return 1
    pkg_repository_podman_tab="$(printf '\t')"
    printf '%s\n' "$pkg_repository_podman_records" | \
      LC_ALL=C command -p -- awk -F "$pkg_repository_podman_tab" -v version="$pkg_repository_podman_version" '
NF != 3 { exit 1 }
$3 == version { count++ }
END { if (count != 1) exit 1; print version }
'
    return
  fi
  pkg_repository_podman_body="$( _pkg_repository_podman_get /releases/latest pkg_repository_resolve_version )" || return 1
  json_object_read \
    tag_name pkg_repository_podman_tag_token \
    draft pkg_repository_podman_draft_token \
    prerelease pkg_repository_podman_prerelease_token \
    created_at pkg_repository_podman_created_token \
    published_at pkg_repository_podman_published_token <<EOF_PODMAN_LATEST
$pkg_repository_podman_body
EOF_PODMAN_LATEST
  [ "$?" -eq 0 ] || return 1
  pkg_repository_podman_record="$( _pkg_repository_podman_release_tokens \
    "$pkg_repository_podman_tag_token" \
    "$pkg_repository_podman_draft_token" \
    "$pkg_repository_podman_prerelease_token" \
    "$pkg_repository_podman_created_token" \
    "$pkg_repository_podman_published_token")" || return 1
  pkg_repository_podman_tab="$(printf '\t')"
  IFS="$pkg_repository_podman_tab" read -r \
    pkg_repository_podman_created \
    pkg_repository_podman_published \
    pkg_repository_podman_version \
    pkg_repository_podman_extra <<EOF_PODMAN_LATEST_RECORD
$pkg_repository_podman_record
EOF_PODMAN_LATEST_RECORD
  [ -z "$pkg_repository_podman_extra" ] || return 1
  printf '%s\n' "$pkg_repository_podman_version"
)

pkg_repository_resolve_artifact()
(
  [ "$#" -eq 3 ] || return 2
  pkg_repository_podman_repository_dir=$1
  pkg_repository_podman_range_dir=$2
  pkg_repository_podman_version=$3
  _pkg_repository_podman_validate_repository "$pkg_repository_podman_repository_dir" || return 1
  _pkg_repository_podman_validate_version "$pkg_repository_podman_version" || return 1
  [ -d "$pkg_repository_podman_range_dir" ] && [ ! -L "$pkg_repository_podman_range_dir" ] || return 1
  pkg_repository_podman_archive_regex="$( _pkg_repository_podman_scalar "$pkg_repository_podman_range_dir/archive_regex" )" || return 1
  pkg_repository_podman_digest_type="$( _pkg_repository_podman_scalar "$pkg_repository_podman_range_dir/digest_type" )" || return 1
  [ "$pkg_repository_podman_digest_type" = sha256 ] || return 1
  pkg_repository_podman_body="$( _pkg_repository_podman_get "/releases/tags/$pkg_repository_podman_version" pkg_repository_resolve_artifact )" || return 1
  pkg_repository_podman_release="$( _pkg_repository_podman_release_body_validate "$pkg_repository_podman_body" "$pkg_repository_podman_version" )" || return 1
  pkg_repository_podman_assets="$(printf '%s\n' "$pkg_repository_podman_body" | \
    json_object_array_object_fields assets name state size digest browser_download_url)" || return 1
  [ -n "$pkg_repository_podman_assets" ] || return 1
  pkg_repository_podman_tab="$(printf '\t')"
  pkg_repository_podman_asset="$(printf '%s\n' "$pkg_repository_podman_assets" | \
    LC_ALL=C command -p -- awk -F "$pkg_repository_podman_tab" -v expression="$pkg_repository_podman_archive_regex" '
function fail() { exit 1 }
{
  if (NF != 5 || $1 !~ /^s:/) fail()
  name=$1; sub(/^s:/,"",name)
  if (name ~ expression) { count++; selected=$0 }
}
END { if (count != 1) exit 1; print selected }
' )" || return 1
  IFS="$pkg_repository_podman_tab" read -r \
    pkg_repository_podman_name_token \
    pkg_repository_podman_state_token \
    pkg_repository_podman_size_token \
    pkg_repository_podman_digest_token \
    pkg_repository_podman_url_token \
    pkg_repository_podman_extra <<EOF_PODMAN_ASSET
$pkg_repository_podman_asset
EOF_PODMAN_ASSET
  [ -z "$pkg_repository_podman_extra" ] || return 1
  case "$pkg_repository_podman_name_token" in s:*) pkg_repository_podman_name=${pkg_repository_podman_name_token#s:};; *) return 1;; esac
  [ "$pkg_repository_podman_state_token" = s:uploaded ] || return 1
  case "$pkg_repository_podman_size_token" in n:*) pkg_repository_podman_size=${pkg_repository_podman_size_token#n:};; *) return 1;; esac
  case "$pkg_repository_podman_size" in ''|*[!0-9]*) return 1;; esac
  [ "$pkg_repository_podman_size" -gt 0 ] || return 1
  case "$pkg_repository_podman_digest_token" in s:sha256:*) pkg_repository_podman_digest=${pkg_repository_podman_digest_token#s:sha256:};; *) return 1;; esac
  [ "${#pkg_repository_podman_digest}" -eq 64 ] || return 1
  case "$pkg_repository_podman_digest" in *[!0-9A-Fa-f]*) return 1;; esac
  pkg_repository_podman_digest="$(printf '%s\n' "$pkg_repository_podman_digest" | command -p -- tr 'A-F' 'a-f')" || return 1
  case "$pkg_repository_podman_url_token" in s:https://*) pkg_repository_podman_url=${pkg_repository_podman_url_token#s:};; *) return 1;; esac
  pkg_repository_podman_expected_url="https://github.com/podman-container-tools/podman/releases/download/$pkg_repository_podman_version/$pkg_repository_podman_name"
  [ "$pkg_repository_podman_url" = "$pkg_repository_podman_expected_url" ] || return 1
  [ "$pkg_repository_podman_name" = podman-installer-macos-arm64.pkg ] || return 1
  LC_ALL=C command -p -- awk -v name="$pkg_repository_podman_name" -v expression="$pkg_repository_podman_archive_regex" 'BEGIN { exit(name ~ expression ? 0 : 1) }' || return 1
  pkg_repository_podman_anchor="$( _pkg_repository_podman_scalar "$pkg_repository_podman_repository_dir/version" )" || return 1
  if [ "$pkg_repository_podman_version" = "$pkg_repository_podman_anchor" ]
  then
    pkg_repository_podman_expected_digest="$( _pkg_repository_podman_scalar "$pkg_repository_podman_repository_dir/digest" )" || return 1
    [ "$pkg_repository_podman_digest" = "$pkg_repository_podman_expected_digest" ] || return 1
    pkg_repository_podman_expected_static_url="$( _pkg_repository_podman_scalar "$pkg_repository_podman_repository_dir/url" )" || return 1
    [ "$pkg_repository_podman_url" = "$pkg_repository_podman_expected_static_url" ] || return 1
  fi
  printf 'name=%s\nurl=%s\nsize=%s\ndigest=sha256:%s\n' \
    "$pkg_repository_podman_name" \
    "$pkg_repository_podman_url" \
    "$pkg_repository_podman_size" \
    "$pkg_repository_podman_digest"
)
