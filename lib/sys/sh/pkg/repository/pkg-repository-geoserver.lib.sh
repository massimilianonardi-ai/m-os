loadsyslib "json"
loadsyslib "pkg/repository/pkg-repository-artifact"

_pkg_repository_geoserver_scalar()
{
  [ "$#" -eq 1 ] || return 2
  pkg_repository_geoserver_scalar_file=$1
  [ -f "$pkg_repository_geoserver_scalar_file" ] &&
  [ ! -L "$pkg_repository_geoserver_scalar_file" ] &&
  [ -r "$pkg_repository_geoserver_scalar_file" ] &&
  [ ! -x "$pkg_repository_geoserver_scalar_file" ] || return 1

  pkg_repository_geoserver_scalar_value=
  pkg_repository_geoserver_scalar_extra=
  {
    IFS= read -r pkg_repository_geoserver_scalar_value || return 1
    IFS= read -r pkg_repository_geoserver_scalar_extra
    pkg_repository_geoserver_scalar_second_status=$?
  } < "$pkg_repository_geoserver_scalar_file"
  [ "$pkg_repository_geoserver_scalar_second_status" -ne 0 ] || return 1
  [ -z "$pkg_repository_geoserver_scalar_extra" ] && [ -n "$pkg_repository_geoserver_scalar_value" ] || return 1
  pkg_repository_geoserver_scalar_actual="$(command -p -- wc -c < "$pkg_repository_geoserver_scalar_file")" || return 1
  pkg_repository_geoserver_scalar_expected="$(printf '%s\n' "$pkg_repository_geoserver_scalar_value" | command -p -- wc -c)" || return 1
  [ "$pkg_repository_geoserver_scalar_actual" = "$pkg_repository_geoserver_scalar_expected" ] || return 1
  pkg_repository_geoserver_scalar_cr="$(printf '\r')"
  case "$pkg_repository_geoserver_scalar_value" in *"$pkg_repository_geoserver_scalar_cr"*) return 1;; esac
  printf '%s\n' "$pkg_repository_geoserver_scalar_value"
}

_pkg_repository_geoserver_validate_version()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in ''|[!A-Za-z0-9]*|*[!A-Za-z0-9._+~-]*) return 1;; esac
}

_pkg_repository_geoserver_validate_repository()
{
  [ "$#" -eq 1 ] || return 2
  pkg_repository_geoserver_repository_dir=$1
  [ -d "$pkg_repository_geoserver_repository_dir" ] && [ ! -L "$pkg_repository_geoserver_repository_dir" ] || return 1

  for pkg_repository_geoserver_item in \
    "$pkg_repository_geoserver_repository_dir"/* \
    "$pkg_repository_geoserver_repository_dir"/.[!.]* \
    "$pkg_repository_geoserver_repository_dir"/..?*
  do
    [ -e "$pkg_repository_geoserver_item" ] || [ -L "$pkg_repository_geoserver_item" ] || continue
    pkg_repository_geoserver_name=${pkg_repository_geoserver_item##*/}
    case "$pkg_repository_geoserver_name" in
      type|versions)
        [ -f "$pkg_repository_geoserver_item" ] &&
        [ ! -L "$pkg_repository_geoserver_item" ] &&
        [ -r "$pkg_repository_geoserver_item" ] &&
        [ ! -x "$pkg_repository_geoserver_item" ] || return 1
        ;;
      download|metadata)
        [ -d "$pkg_repository_geoserver_item" ] && [ ! -L "$pkg_repository_geoserver_item" ] || return 1
        ;;
      *) return 1;;
    esac
  done

  [ "$(_pkg_repository_geoserver_scalar "$pkg_repository_geoserver_repository_dir/type")" = geoserver ] || return 1
  if [ -e "$pkg_repository_geoserver_repository_dir/versions" ] || [ -L "$pkg_repository_geoserver_repository_dir/versions" ]
  then
    LC_ALL=C command -p -- awk '
      $0 !~ /^[A-Za-z0-9][A-Za-z0-9._+~-]*$/ || seen[$0]++ { exit 1 }
      END { if (NR == 0) exit 1 }
    ' "$pkg_repository_geoserver_repository_dir/versions" || return 1
  fi
  pkg_repository_artifact_overrides_validate "$pkg_repository_geoserver_repository_dir"
}

_pkg_repository_geoserver_get()
{
  [ "$#" -eq 2 ] || return 2
  pkg_repository_geoserver_path=$1
  pkg_repository_geoserver_operation=$2
  pkg_repository_geoserver_url="https://api.github.com/repos/geoserver/geoserver$pkg_repository_geoserver_path"
  http-fetch \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2026-03-10' \
    -- "$pkg_repository_geoserver_url"
  pkg_repository_geoserver_status=$?
  [ "$pkg_repository_geoserver_status" -eq 0 ] && return 0
  log error execution execution-failed \
    operation pkg-repository-geoserver \
    reason upstream-request-failed \
    function "$pkg_repository_geoserver_operation" \
    url "$pkg_repository_geoserver_url" \
    status "$pkg_repository_geoserver_status" || :
  return 1
}

_pkg_repository_geoserver_validate_release_tokens()
{
  [ "$#" -eq 6 ] || return 2
  pkg_repository_geoserver_tag_token=$1
  pkg_repository_geoserver_draft_token=$2
  pkg_repository_geoserver_prerelease_token=$3
  pkg_repository_geoserver_created_token=$4
  pkg_repository_geoserver_published_token=$5
  pkg_repository_geoserver_requested=$6
  case "$pkg_repository_geoserver_tag_token" in s:*) pkg_repository_geoserver_tag=${pkg_repository_geoserver_tag_token#s:};; *) return 1;; esac
  [ "$pkg_repository_geoserver_tag" = "$pkg_repository_geoserver_requested" ] || return 1
  [ "$pkg_repository_geoserver_draft_token" = b:false ] && [ "$pkg_repository_geoserver_prerelease_token" = b:false ] || return 1
  _pkg_repository_geoserver_validate_version "$pkg_repository_geoserver_tag" || return 1
  case "$pkg_repository_geoserver_created_token" in s:*) pkg_repository_geoserver_created=${pkg_repository_geoserver_created_token#s:};; *) return 1;; esac
  case "$pkg_repository_geoserver_published_token" in s:*) pkg_repository_geoserver_published=${pkg_repository_geoserver_published_token#s:};; *) return 1;; esac
  LC_ALL=C command -p -- awk -v created="$pkg_repository_geoserver_created" -v published="$pkg_repository_geoserver_published" '
    BEGIN {
      timestamp="^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$"
      exit(created ~ timestamp && published ~ timestamp ? 0 : 1)
    }
  ' || return 1
  printf '%s\t%s\n' "$pkg_repository_geoserver_created" "$pkg_repository_geoserver_published"
}

_pkg_repository_geoserver_validate_release()
{
  [ "$#" -eq 2 ] || return 2
  pkg_repository_geoserver_body=$1
  pkg_repository_geoserver_requested=$2
  json_object_read \
    tag_name pkg_repository_geoserver_tag_token \
    draft pkg_repository_geoserver_draft_token \
    prerelease pkg_repository_geoserver_prerelease_token \
    created_at pkg_repository_geoserver_created_token \
    published_at pkg_repository_geoserver_published_token <<EOF_RELEASE
$pkg_repository_geoserver_body
EOF_RELEASE
  [ "$?" -eq 0 ] || return 1
  _pkg_repository_geoserver_validate_release_tokens \
    "$pkg_repository_geoserver_tag_token" \
    "$pkg_repository_geoserver_draft_token" \
    "$pkg_repository_geoserver_prerelease_token" \
    "$pkg_repository_geoserver_created_token" \
    "$pkg_repository_geoserver_published_token" \
    "$pkg_repository_geoserver_requested"
}

_pkg_repository_geoserver_index_order()
(
  [ "$#" -eq 3 ] || return 2
  pkg_repository_geoserver_index="$1/versions"
  [ -e "$pkg_repository_geoserver_index" ] || [ -L "$pkg_repository_geoserver_index" ] || return 3
  [ -f "$pkg_repository_geoserver_index" ] && [ ! -L "$pkg_repository_geoserver_index" ] &&
    [ -r "$pkg_repository_geoserver_index" ] && [ ! -x "$pkg_repository_geoserver_index" ] || return 1
  LC_ALL=C command -p -- awk -v left="$2" -v right="$3" '
    {
      if ($0 !~ /^[A-Za-z0-9][A-Za-z0-9._+~-]*$/ || seen[$0]++) { invalid=1; exit 1 }
      if ($0 == left) left_position=NR
      if ($0 == right) right_position=NR
    }
    END {
      if (invalid || NR == 0) exit 1
      if (!left_position || !right_position) exit 3
      if (left_position < right_position) print "-1"
      else if (left_position > right_position) print "1"
      else print "0"
    }
  ' "$pkg_repository_geoserver_index"
)

_pkg_repository_geoserver_release_key()
(
  [ "$#" -eq 2 ] || return 2
  _pkg_repository_geoserver_validate_repository "$1" || return 1
  _pkg_repository_geoserver_validate_version "$2" || return 1
  pkg_repository_geoserver_body="$(_pkg_repository_geoserver_get "/releases/tags/$2" pkg_repository_compare_versions)" || return 1
  _pkg_repository_geoserver_validate_release "$pkg_repository_geoserver_body" "$2"
)

pkg_repository_list_versions()
(
  [ "$#" -eq 1 ] || return 2
  _pkg_repository_geoserver_validate_repository "$1" || return 1
  pkg_repository_geoserver_page=1
  pkg_repository_geoserver_records=
  pkg_repository_geoserver_seen='|'
  pkg_repository_geoserver_lf='
'
  pkg_repository_geoserver_tab="$(printf '\t')"
  while :
  do
    pkg_repository_geoserver_body="$(_pkg_repository_geoserver_get "/releases?per_page=100&page=$pkg_repository_geoserver_page" pkg_repository_list_versions)" || return 1
    pkg_repository_geoserver_tokens="$(printf '%s\n' "$pkg_repository_geoserver_body" | json_array_object_fields tag_name draft prerelease created_at published_at)" || return 1
    pkg_repository_geoserver_count=0
    if [ -n "$pkg_repository_geoserver_tokens" ]
    then
      while IFS="$pkg_repository_geoserver_tab" read -r \
        pkg_repository_geoserver_tag_token \
        pkg_repository_geoserver_draft_token \
        pkg_repository_geoserver_prerelease_token \
        pkg_repository_geoserver_created_token \
        pkg_repository_geoserver_published_token \
        pkg_repository_geoserver_extra
      do
        [ -z "$pkg_repository_geoserver_extra" ] || return 1
        pkg_repository_geoserver_count=$((pkg_repository_geoserver_count + 1))
        case "$pkg_repository_geoserver_draft_token" in b:true) continue;; b:false) :;; *) return 1;; esac
        case "$pkg_repository_geoserver_prerelease_token" in b:true) continue;; b:false) :;; *) return 1;; esac
        case "$pkg_repository_geoserver_tag_token" in s:*) pkg_repository_geoserver_tag=${pkg_repository_geoserver_tag_token#s:};; *) return 1;; esac
        pkg_repository_geoserver_key="$(_pkg_repository_geoserver_validate_release_tokens \
          "$pkg_repository_geoserver_tag_token" \
          "$pkg_repository_geoserver_draft_token" \
          "$pkg_repository_geoserver_prerelease_token" \
          "$pkg_repository_geoserver_created_token" \
          "$pkg_repository_geoserver_published_token" \
          "$pkg_repository_geoserver_tag")" || return 1
        pkg_repository_geoserver_record="$pkg_repository_geoserver_key$pkg_repository_geoserver_tab$pkg_repository_geoserver_tag"
        case "$pkg_repository_geoserver_seen" in *"|$pkg_repository_geoserver_tag|"*) return 1;; esac
        pkg_repository_geoserver_seen="$pkg_repository_geoserver_seen$pkg_repository_geoserver_tag|"
        if [ -n "$pkg_repository_geoserver_records" ]
        then pkg_repository_geoserver_records="$pkg_repository_geoserver_records$pkg_repository_geoserver_lf$pkg_repository_geoserver_record"
        else pkg_repository_geoserver_records=$pkg_repository_geoserver_record
        fi
      done <<EOF_RELEASES
$pkg_repository_geoserver_tokens
EOF_RELEASES
    fi
    [ "$pkg_repository_geoserver_count" -ge 100 ] || break
    pkg_repository_geoserver_page=$((pkg_repository_geoserver_page + 1))
  done
  [ -n "$pkg_repository_geoserver_records" ] || return 0
  printf '%s\n' "$pkg_repository_geoserver_records" | LC_ALL=C command -p -- sort -t "$pkg_repository_geoserver_tab" -k1,1 -k2,2 -k3,3 | \
    LC_ALL=C command -p -- awk -F "$pkg_repository_geoserver_tab" '
      NF != 3 { exit 1 }
      { if (previous_created == $1 && previous_published == $2) exit 1; previous_created=$1; previous_published=$2; print $3 }
    '
)

pkg_repository_compare_versions()
(
  [ "$#" -eq 3 ] || return 2
  pkg_repository_geoserver_repository_dir=$1
  pkg_repository_geoserver_left=$2
  pkg_repository_geoserver_right=$3
  _pkg_repository_geoserver_validate_repository "$pkg_repository_geoserver_repository_dir" || return 1
  _pkg_repository_geoserver_validate_version "$pkg_repository_geoserver_left" || return 1
  _pkg_repository_geoserver_validate_version "$pkg_repository_geoserver_right" || return 1
  [ "$pkg_repository_geoserver_left" != "$pkg_repository_geoserver_right" ] || { printf '0\n'; return 0; }
  _pkg_repository_geoserver_index_order "$pkg_repository_geoserver_repository_dir" "$pkg_repository_geoserver_left" "$pkg_repository_geoserver_right"
  pkg_repository_geoserver_index_status=$?
  case "$pkg_repository_geoserver_index_status" in 0) return 0;; 3) :;; *) return 1;; esac
  pkg_repository_geoserver_left_key="$(_pkg_repository_geoserver_release_key "$pkg_repository_geoserver_repository_dir" "$pkg_repository_geoserver_left")" || return 1
  pkg_repository_geoserver_right_key="$(_pkg_repository_geoserver_release_key "$pkg_repository_geoserver_repository_dir" "$pkg_repository_geoserver_right")" || return 1
  LC_ALL=C command -p -- awk -F '\t' -v left="$pkg_repository_geoserver_left_key" -v right="$pkg_repository_geoserver_right_key" '
    BEGIN {
      split(left, l, "\t"); split(right, r, "\t")
      if (l[1] < r[1]) print "-1"
      else if (l[1] > r[1]) print "1"
      else if (l[2] < r[2]) print "-1"
      else if (l[2] > r[2]) print "1"
      else exit 1
    }
  '
)

pkg_repository_resolve_version()
(
  [ "$#" -ge 1 ] && [ "$#" -le 2 ] || return 2
  pkg_repository_geoserver_repository_dir=$1
  _pkg_repository_geoserver_validate_repository "$pkg_repository_geoserver_repository_dir" || return 1
  if [ "$#" -eq 1 ]
  then
    pkg_repository_geoserver_body="$(_pkg_repository_geoserver_get /releases/latest pkg_repository_resolve_version)" || return 1
    pkg_repository_geoserver_tag_token=
    json_object_read tag_name pkg_repository_geoserver_tag_token <<EOF_LATEST
$pkg_repository_geoserver_body
EOF_LATEST
    [ "$?" -eq 0 ] || return 1
    case "$pkg_repository_geoserver_tag_token" in s:*) pkg_repository_geoserver_version=${pkg_repository_geoserver_tag_token#s:};; *) return 1;; esac
    _pkg_repository_geoserver_validate_release "$pkg_repository_geoserver_body" "$pkg_repository_geoserver_version" >/dev/null || return 1
  else
    pkg_repository_geoserver_version=$2
  fi
  _pkg_repository_geoserver_validate_version "$pkg_repository_geoserver_version" || return 1
  if [ "$#" -eq 2 ]
  then
    _pkg_repository_geoserver_index_order "$pkg_repository_geoserver_repository_dir" "$pkg_repository_geoserver_version" "$pkg_repository_geoserver_version" >/dev/null
    pkg_repository_geoserver_index_status=$?
    case "$pkg_repository_geoserver_index_status" in
      0) printf '%s\n' "$pkg_repository_geoserver_version"; return 0;;
      3) :;;
      *) return 1;;
    esac
    pkg_repository_geoserver_body="$(_pkg_repository_geoserver_get "/releases/tags/$pkg_repository_geoserver_version" pkg_repository_resolve_version)" || return 1
    _pkg_repository_geoserver_validate_release "$pkg_repository_geoserver_body" "$pkg_repository_geoserver_version" >/dev/null || return 1
  fi
  printf '%s\n' "$pkg_repository_geoserver_version"
)

pkg_repository_resolve_artifact()
(
  [ "$#" -eq 3 ] || return 2
  pkg_repository_geoserver_repository_dir=$1
  pkg_repository_geoserver_range_dir=$2
  pkg_repository_geoserver_version=$3
  _pkg_repository_geoserver_validate_repository "$pkg_repository_geoserver_repository_dir" || return 1
  _pkg_repository_geoserver_validate_version "$pkg_repository_geoserver_version" || return 1
  _pkg_repository_geoserver_validate_release "$(_pkg_repository_geoserver_get "/releases/tags/$pkg_repository_geoserver_version" pkg_repository_resolve_artifact)" "$pkg_repository_geoserver_version" >/dev/null || return 1
  [ -d "$pkg_repository_geoserver_range_dir" ] && [ ! -L "$pkg_repository_geoserver_range_dir" ] || return 1
  pkg_repository_geoserver_archive_regex="$(_pkg_repository_geoserver_scalar "$pkg_repository_geoserver_range_dir/archive_regex")" || return 1
  if [ -e "$pkg_repository_geoserver_range_dir/digest_regex" ] || [ -L "$pkg_repository_geoserver_range_dir/digest_regex" ]; then return 1; fi
  pkg_repository_geoserver_digest_type="$(_pkg_repository_geoserver_scalar "$pkg_repository_geoserver_range_dir/digest_type")" || return 1
  [ "$pkg_repository_geoserver_digest_type" = md5 ] || return 1
  pkg_repository_geoserver_download_override=0
  pkg_repository_geoserver_metadata_override=0
  if [ -e "$pkg_repository_geoserver_repository_dir/download" ] || [ -L "$pkg_repository_geoserver_repository_dir/download" ]; then pkg_repository_geoserver_download_override=1; fi
  if [ -e "$pkg_repository_geoserver_repository_dir/metadata" ] || [ -L "$pkg_repository_geoserver_repository_dir/metadata" ]; then pkg_repository_geoserver_metadata_override=1; fi
  if [ "$pkg_repository_geoserver_download_override" -eq 1 ]
  then
    pkg_repository_geoserver_download="$(pkg_repository_artifact_download_resolve "$pkg_repository_geoserver_repository_dir/download" "$pkg_repository_geoserver_version")" || return 1
    pkg_repository_geoserver_tab="$(printf '\t')"
    IFS="$pkg_repository_geoserver_tab" read -r pkg_repository_geoserver_name pkg_repository_geoserver_url pkg_repository_geoserver_extra <<EOF_DOWNLOAD
$pkg_repository_geoserver_download
EOF_DOWNLOAD
    [ -z "$pkg_repository_geoserver_extra" ] && [ -n "$pkg_repository_geoserver_name" ] && [ -n "$pkg_repository_geoserver_url" ] || return 1
  else
    pkg_repository_geoserver_name="geoserver-$pkg_repository_geoserver_version-bin.zip"
    pkg_repository_geoserver_url="https://sourceforge.net/projects/geoserver/files/GeoServer/$pkg_repository_geoserver_version/$pkg_repository_geoserver_name/download"
  fi
  LC_ALL=C command -p -- awk -v value="$pkg_repository_geoserver_name" -v expression="$pkg_repository_geoserver_archive_regex" 'BEGIN { exit(value ~ expression ? 0 : 1) }' || return 1
  if [ "$pkg_repository_geoserver_metadata_override" -eq 1 ]
  then
    pkg_repository_geoserver_metadata="$(pkg_repository_artifact_metadata_resolve "$pkg_repository_geoserver_repository_dir/metadata" md5 "$pkg_repository_geoserver_version" "$pkg_repository_geoserver_name" "$pkg_repository_geoserver_url")" || return 1
  else
    pkg_repository_geoserver_metadata="$(pkg_repository_artifact_metadata_sourceforge_rss geoserver '/GeoServer/{version}' md5 "$pkg_repository_geoserver_version" "$pkg_repository_geoserver_name" "$pkg_repository_geoserver_url")" || return 1
  fi
  pkg_repository_geoserver_tab="$(printf '\t')"
  IFS="$pkg_repository_geoserver_tab" read -r pkg_repository_geoserver_size pkg_repository_geoserver_digest pkg_repository_geoserver_extra <<EOF_METADATA
$pkg_repository_geoserver_metadata
EOF_METADATA
  [ -z "$pkg_repository_geoserver_extra" ] && [ -n "$pkg_repository_geoserver_size" ] || return 1
  case "$pkg_repository_geoserver_digest" in md5:*) :;; *) return 1;; esac
  printf 'name=%s\nurl=%s\nsize=%s\ndigest=%s\n' "$pkg_repository_geoserver_name" "$pkg_repository_geoserver_url" "$pkg_repository_geoserver_size" "$pkg_repository_geoserver_digest"
)
