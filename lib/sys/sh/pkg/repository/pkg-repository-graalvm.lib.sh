loadsyslib "json"

_pkg_repository_graalvm_scalar()
{
  [ "$#" -eq 1 ] || return 2
  pkg_repository_graalvm_scalar_file=$1
  [ -f "$pkg_repository_graalvm_scalar_file" ] &&
    [ ! -L "$pkg_repository_graalvm_scalar_file" ] &&
    [ -r "$pkg_repository_graalvm_scalar_file" ] &&
    [ ! -x "$pkg_repository_graalvm_scalar_file" ] || return 1

  pkg_repository_graalvm_scalar_value=
  pkg_repository_graalvm_scalar_extra=
  {
    IFS= read -r pkg_repository_graalvm_scalar_value || return 1
    IFS= read -r pkg_repository_graalvm_scalar_extra
    pkg_repository_graalvm_scalar_second_status=$?
  } < "$pkg_repository_graalvm_scalar_file"
  [ "$pkg_repository_graalvm_scalar_second_status" -ne 0 ] || return 1
  [ -z "$pkg_repository_graalvm_scalar_extra" ] && [ -n "$pkg_repository_graalvm_scalar_value" ] || return 1
  pkg_repository_graalvm_scalar_actual="$(command -p -- wc -c < "$pkg_repository_graalvm_scalar_file")" || return 1
  pkg_repository_graalvm_scalar_expected="$(printf '%s\n' "$pkg_repository_graalvm_scalar_value" | command -p -- wc -c)" || return 1
  [ "$pkg_repository_graalvm_scalar_actual" = "$pkg_repository_graalvm_scalar_expected" ] || return 1
  pkg_repository_graalvm_scalar_cr="$(printf '\r')"
  case "$pkg_repository_graalvm_scalar_value" in *"$pkg_repository_graalvm_scalar_cr"*) return 1;; esac
  printf '%s\n' "$pkg_repository_graalvm_scalar_value"
}

_pkg_repository_graalvm_validate_version()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in ''|[!A-Za-z0-9]*|*[!A-Za-z0-9._+~-]*) return 1;; esac
}

_pkg_repository_graalvm_tag_version()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in
    graal-*) pkg_repository_graalvm_mapped_version=${1#graal-};;
    jdk-*) pkg_repository_graalvm_mapped_version=${1#jdk-};;
    vm-*) pkg_repository_graalvm_mapped_version=${1#vm-};;
    *) return 1;;
  esac
  _pkg_repository_graalvm_validate_version "$pkg_repository_graalvm_mapped_version" || return 1
  printf '%s\n' "$pkg_repository_graalvm_mapped_version"
}

_pkg_repository_graalvm_version_tag()
(
  [ "$#" -eq 2 ] || return 2
  pkg_repository_graalvm_version=$2
  _pkg_repository_graalvm_validate_version "$pkg_repository_graalvm_version" || return 1
  pkg_repository_graalvm_records="$(_pkg_repository_graalvm_release_records "$1")" || return 1
  [ -n "$pkg_repository_graalvm_records" ] || return 1
  pkg_repository_graalvm_tab="$(printf '\t')"
  printf '%s\n' "$pkg_repository_graalvm_records" | LC_ALL=C command -p -- awk -F "$pkg_repository_graalvm_tab" -v version="$pkg_repository_graalvm_version" '
NF != 4 { exit 1 }
$3 == version { count++; tag=$4 }
END {
  if (count != 1) exit 1
  print tag
}
'
)

_pkg_repository_graalvm_validate_repository()
{
  [ "$#" -eq 1 ] || return 2
  pkg_repository_graalvm_repository_dir=$1
  [ -d "$pkg_repository_graalvm_repository_dir" ] && [ ! -L "$pkg_repository_graalvm_repository_dir" ] || return 1
  for pkg_repository_graalvm_item in \
    "$pkg_repository_graalvm_repository_dir"/* \
    "$pkg_repository_graalvm_repository_dir"/.[!.]* \
    "$pkg_repository_graalvm_repository_dir"/..?*
  do
    [ -e "$pkg_repository_graalvm_item" ] || [ -L "$pkg_repository_graalvm_item" ] || continue
    pkg_repository_graalvm_name=${pkg_repository_graalvm_item##*/}
    case "$pkg_repository_graalvm_name" in
      type|owner|repository|versions)
        [ -f "$pkg_repository_graalvm_item" ] && [ ! -L "$pkg_repository_graalvm_item" ] &&
          [ -r "$pkg_repository_graalvm_item" ] && [ ! -x "$pkg_repository_graalvm_item" ] || return 1
        ;;
      *) return 1;;
    esac
  done
  pkg_repository_graalvm_type="$(_pkg_repository_graalvm_scalar "$pkg_repository_graalvm_repository_dir/type")" || return 1
  pkg_repository_graalvm_owner="$(_pkg_repository_graalvm_scalar "$pkg_repository_graalvm_repository_dir/owner")" || return 1
  pkg_repository_graalvm_repository="$(_pkg_repository_graalvm_scalar "$pkg_repository_graalvm_repository_dir/repository")" || return 1
  [ "$pkg_repository_graalvm_type" = graalvm ] || return 1
  [ "$pkg_repository_graalvm_owner" = graalvm ] && [ "$pkg_repository_graalvm_repository" = graalvm-ce-builds ] || return 1
  if [ -e "$pkg_repository_graalvm_repository_dir/versions" ] || [ -L "$pkg_repository_graalvm_repository_dir/versions" ]
  then
    _pkg_repository_graalvm_validate_versions "$pkg_repository_graalvm_repository_dir/versions" || return 1
  fi
}

_pkg_repository_graalvm_validate_versions()
{
  [ "$#" -eq 1 ] || return 2
  pkg_repository_graalvm_versions_file=$1
  [ -f "$pkg_repository_graalvm_versions_file" ] &&
    [ ! -L "$pkg_repository_graalvm_versions_file" ] &&
    [ -r "$pkg_repository_graalvm_versions_file" ] &&
    [ ! -x "$pkg_repository_graalvm_versions_file" ] || return 1
  LC_ALL=C command -p -- awk '
    {
      if ($0 !~ /^[A-Za-z0-9][A-Za-z0-9._+~-]*$/ || seen[$0]++) exit 1
      count++
    }
    END { if (count == 0 || $0 == "") exit 1 }
  ' "$pkg_repository_graalvm_versions_file"
}

_pkg_repository_graalvm_compare_index()
{
  [ "$#" -eq 3 ] || return 2
  pkg_repository_graalvm_versions_file=$1
  pkg_repository_graalvm_left=$2
  pkg_repository_graalvm_right=$3
  _pkg_repository_graalvm_validate_versions "$pkg_repository_graalvm_versions_file" || return 1
  LC_ALL=C command -p -- awk -v left="$pkg_repository_graalvm_left" -v right="$pkg_repository_graalvm_right" '
    $0 == left { left_rank=NR }
    $0 == right { right_rank=NR }
    END {
      if (!left_rank || !right_rank) exit 1
      if (left_rank < right_rank) print "-1"
      else if (left_rank > right_rank) print "1"
      else print "0"
    }
  ' "$pkg_repository_graalvm_versions_file"
}

_pkg_repository_graalvm_get()
{
  [ "$#" -eq 2 ] || return 2
  pkg_repository_graalvm_path=$1
  pkg_repository_graalvm_operation=$2
  case "$pkg_repository_graalvm_operation:$pkg_repository_graalvm_path" in
    pkg_repository_list_versions:/releases\?per_page=100\&page=*)
      pkg_repository_graalvm_message=release-list-request-failed
      ;;
    pkg_repository_resolve_version:/releases/latest)
      pkg_repository_graalvm_message=latest-release-request-failed
      ;;
    pkg_repository_resolve_version:/releases/tags/*)
      pkg_repository_graalvm_message=exact-release-request-failed
      ;;
    pkg_repository_resolve_artifact:/releases/tags/*)
      pkg_repository_graalvm_message=artifact-metadata-request-failed
      ;;
    *)
      log error pkg-repository-graalvm request-operation-unsupported \
        operation "$pkg_repository_graalvm_operation" \
        path "$pkg_repository_graalvm_path" || :
      return 2
      ;;
  esac
  pkg_repository_graalvm_url="https://api.github.com/repos/graalvm/graalvm-ce-builds$pkg_repository_graalvm_path"
  http-fetch \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2026-03-10' \
    -- "$pkg_repository_graalvm_url"
  pkg_repository_graalvm_status=$?
  [ "$pkg_repository_graalvm_status" -eq 0 ] && return 0
  log error pkg-repository-graalvm "$pkg_repository_graalvm_message" \
    operation upstream-request \
    function "$pkg_repository_graalvm_operation" \
    url "$pkg_repository_graalvm_url" \
    status "$pkg_repository_graalvm_status" || :
  return 1
}

_pkg_repository_graalvm_release_tokens()
{
  [ "$#" -eq 5 ] || return 2
  case "$1" in s:*) pkg_repository_graalvm_tag=${1#s:};; *) return 1;; esac
  [ "$2" = b:false ] && [ "$3" = b:false ] || return 1
  pkg_repository_graalvm_version="$(_pkg_repository_graalvm_tag_version "$pkg_repository_graalvm_tag")" || return 1
  case "$4" in s:*) pkg_repository_graalvm_created=${4#s:};; *) return 1;; esac
  case "$5" in s:*) pkg_repository_graalvm_published=${5#s:};; *) return 1;; esac
  LC_ALL=C command -p -- awk -v created="$pkg_repository_graalvm_created" -v published="$pkg_repository_graalvm_published" '
BEGIN {
  timestamp="^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$"
  exit(created ~ timestamp && published ~ timestamp ? 0 : 1)
  }
' || return 1
  printf '%s\t%s\t%s\t%s\n' \
    "$pkg_repository_graalvm_created" \
    "$pkg_repository_graalvm_published" \
    "$pkg_repository_graalvm_version" \
    "$pkg_repository_graalvm_tag"
}

_pkg_repository_graalvm_release_body_validate()
{
  [ "$#" -eq 2 ] || return 2
  pkg_repository_graalvm_body=$1
  pkg_repository_graalvm_expected_version=$2
  json_object_read \
    tag_name pkg_repository_graalvm_tag_token \
    draft pkg_repository_graalvm_draft_token \
    prerelease pkg_repository_graalvm_prerelease_token \
    created_at pkg_repository_graalvm_created_token \
    published_at pkg_repository_graalvm_published_token <<EOF_GRAALVM_RELEASE
$pkg_repository_graalvm_body
EOF_GRAALVM_RELEASE
  [ "$?" -eq 0 ] || return 1
  pkg_repository_graalvm_record="$(_pkg_repository_graalvm_release_tokens \
    "$pkg_repository_graalvm_tag_token" \
    "$pkg_repository_graalvm_draft_token" \
    "$pkg_repository_graalvm_prerelease_token" \
    "$pkg_repository_graalvm_created_token" \
    "$pkg_repository_graalvm_published_token")" || return 1
  pkg_repository_graalvm_tab="$(printf '\t')"
  IFS="$pkg_repository_graalvm_tab" read -r \
    pkg_repository_graalvm_created \
    pkg_repository_graalvm_published \
    pkg_repository_graalvm_version \
    pkg_repository_graalvm_tag \
    pkg_repository_graalvm_extra <<EOF_GRAALVM_RECORD
$pkg_repository_graalvm_record
EOF_GRAALVM_RECORD
  [ -z "$pkg_repository_graalvm_extra" ] && [ "$pkg_repository_graalvm_version" = "$pkg_repository_graalvm_expected_version" ] || return 1
  printf '%s\t%s\t%s\n' "$pkg_repository_graalvm_created" "$pkg_repository_graalvm_published" "$pkg_repository_graalvm_tag"
}

_pkg_repository_graalvm_release_records()
(
  [ "$#" -eq 1 ] || return 2
  _pkg_repository_graalvm_validate_repository "$1" || return 1
  pkg_repository_graalvm_page=1
  pkg_repository_graalvm_records=
  pkg_repository_graalvm_lf='
'
  pkg_repository_graalvm_tab="$(printf '\t')"
  while :
  do
    pkg_repository_graalvm_body="$(_pkg_repository_graalvm_get "/releases?per_page=100&page=$pkg_repository_graalvm_page" pkg_repository_list_versions)" || return 1
    pkg_repository_graalvm_tokens="$(printf '%s\n' "$pkg_repository_graalvm_body" | json_array_object_fields tag_name draft prerelease created_at published_at)" || return 1
    pkg_repository_graalvm_count=0
    if [ -n "$pkg_repository_graalvm_tokens" ]
    then
      while IFS="$pkg_repository_graalvm_tab" read -r \
        pkg_repository_graalvm_tag_token \
        pkg_repository_graalvm_draft_token \
        pkg_repository_graalvm_prerelease_token \
        pkg_repository_graalvm_created_token \
        pkg_repository_graalvm_published_token \
        pkg_repository_graalvm_extra
      do
        [ -z "$pkg_repository_graalvm_extra" ] || return 1
        pkg_repository_graalvm_count=$((pkg_repository_graalvm_count + 1))
        case "$pkg_repository_graalvm_draft_token" in b:true) continue;; b:false) :;; *) return 1;; esac
        case "$pkg_repository_graalvm_prerelease_token" in b:true) continue;; b:false) :;; *) return 1;; esac
        pkg_repository_graalvm_record="$(_pkg_repository_graalvm_release_tokens \
          "$pkg_repository_graalvm_tag_token" \
          "$pkg_repository_graalvm_draft_token" \
          "$pkg_repository_graalvm_prerelease_token" \
          "$pkg_repository_graalvm_created_token" \
          "$pkg_repository_graalvm_published_token")" || return 1
        if [ -n "$pkg_repository_graalvm_records" ]
        then pkg_repository_graalvm_records="$pkg_repository_graalvm_records$pkg_repository_graalvm_lf$pkg_repository_graalvm_record"
        else pkg_repository_graalvm_records=$pkg_repository_graalvm_record
        fi
      done <<EOF_GRAALVM_RELEASES
$pkg_repository_graalvm_tokens
EOF_GRAALVM_RELEASES
    fi
    [ "$pkg_repository_graalvm_count" -ge 100 ] || break
    pkg_repository_graalvm_page=$((pkg_repository_graalvm_page + 1))
  done
  [ -n "$pkg_repository_graalvm_records" ] || return 0
  printf '%s\n' "$pkg_repository_graalvm_records" | \
    LC_ALL=C command -p -- sort -t "$pkg_repository_graalvm_tab" -k3,3 -k1,1 -k2,2 -k4,4 | \
    LC_ALL=C command -p -- awk -F "$pkg_repository_graalvm_tab" '
NF != 4 { exit 1 }
{
  # Releases can be reissued under a newer tag family while retaining the
  # same package version. Keep the newest upstream chronology for that version.
  if ($3 != version) {
    if (version != "") print record
    version=$3
  }
  record=$1 "\t" $2 "\t" $3 "\t" $4
}
END { if (version != "") print record }
' | \
    LC_ALL=C command -p -- sort -t "$pkg_repository_graalvm_tab" -k1,1 -k2,2 -k3,3 -k4,4 | \
    LC_ALL=C command -p -- awk -F "$pkg_repository_graalvm_tab" '
NF != 4 { exit 1 }
{
  if (previous_created == $1 && previous_published == $2) exit 1
  previous_created=$1
  previous_published=$2
  print $1 "\t" $2 "\t" $3 "\t" $4
}
'
)

_pkg_repository_graalvm_find_release()
(
  [ "$#" -eq 2 ] || return 2
  pkg_repository_graalvm_version=$2
  _pkg_repository_graalvm_validate_version "$pkg_repository_graalvm_version" || return 1
  pkg_repository_graalvm_records="$(_pkg_repository_graalvm_release_records "$1")" || return 1
  [ -n "$pkg_repository_graalvm_records" ] || return 1
  pkg_repository_graalvm_tab="$(printf '\t')"
  printf '%s\n' "$pkg_repository_graalvm_records" | LC_ALL=C command -p -- awk -F "$pkg_repository_graalvm_tab" -v version="$pkg_repository_graalvm_version" '
NF != 4 { exit 1 }
$3 == version { count++; record=$1 "\t" $2 "\t" $4 }
END {
  if (count != 1) exit 1
  print record
}
'
)

pkg_repository_list_versions()
(
  [ "$#" -eq 1 ] || return 2
  pkg_repository_graalvm_records="$(_pkg_repository_graalvm_release_records "$1")" || return 1
  [ -n "$pkg_repository_graalvm_records" ] || return 0
  pkg_repository_graalvm_tab="$(printf '\t')"
  printf '%s\n' "$pkg_repository_graalvm_records" | LC_ALL=C command -p -- awk -F "$pkg_repository_graalvm_tab" '
NF != 4 { exit 1 }
{ print $3 }
'
)

pkg_repository_compare_versions()
(
  [ "$#" -eq 3 ] || return 2
  pkg_repository_graalvm_repository_dir=$1
  pkg_repository_graalvm_left=$2
  pkg_repository_graalvm_right=$3
  _pkg_repository_graalvm_validate_repository "$pkg_repository_graalvm_repository_dir" || return 1
  _pkg_repository_graalvm_validate_version "$pkg_repository_graalvm_left" || return 1
  _pkg_repository_graalvm_validate_version "$pkg_repository_graalvm_right" || return 1
  if [ "$pkg_repository_graalvm_left" = "$pkg_repository_graalvm_right" ]
  then printf '0\n'; return 0; fi
  if [ -f "$pkg_repository_graalvm_repository_dir/versions" ] && [ ! -L "$pkg_repository_graalvm_repository_dir/versions" ]
  then
    pkg_repository_graalvm_index_comparison="$(
      _pkg_repository_graalvm_compare_index \
        "$pkg_repository_graalvm_repository_dir/versions" \
        "$pkg_repository_graalvm_left" "$pkg_repository_graalvm_right"
    )" && {
      printf '%s\n' "$pkg_repository_graalvm_index_comparison"
      return 0
    }
  fi
  pkg_repository_graalvm_left_record="$(_pkg_repository_graalvm_find_release "$pkg_repository_graalvm_repository_dir" "$pkg_repository_graalvm_left")" || return 1
  pkg_repository_graalvm_right_record="$(_pkg_repository_graalvm_find_release "$pkg_repository_graalvm_repository_dir" "$pkg_repository_graalvm_right")" || return 1
  pkg_repository_graalvm_tab="$(printf '\t')"
  IFS="$pkg_repository_graalvm_tab" read -r pkg_repository_graalvm_left_created pkg_repository_graalvm_left_published pkg_repository_graalvm_left_tag pkg_repository_graalvm_extra <<EOF_GRAALVM_LEFT
$pkg_repository_graalvm_left_record
EOF_GRAALVM_LEFT
  [ -z "$pkg_repository_graalvm_extra" ] || return 1
  IFS="$pkg_repository_graalvm_tab" read -r pkg_repository_graalvm_right_created pkg_repository_graalvm_right_published pkg_repository_graalvm_right_tag pkg_repository_graalvm_extra <<EOF_GRAALVM_RIGHT
$pkg_repository_graalvm_right_record
EOF_GRAALVM_RIGHT
  [ -z "$pkg_repository_graalvm_extra" ] || return 1
  LC_ALL=C command -p -- awk \
    -v lc="$pkg_repository_graalvm_left_created" -v lp="$pkg_repository_graalvm_left_published" \
    -v rc="$pkg_repository_graalvm_right_created" -v rp="$pkg_repository_graalvm_right_published" '
BEGIN {
  if (lc < rc || (lc == rc && lp < rp)) print "-1"
  else if (lc > rc || (lc == rc && lp > rp)) print "1"
  else exit 1
}
'
)

pkg_repository_resolve_version()
(
  [ "$#" -ge 1 ] && [ "$#" -le 2 ] || return 2
  pkg_repository_graalvm_repository_dir=$1
  _pkg_repository_graalvm_validate_repository "$pkg_repository_graalvm_repository_dir" || return 1
  if [ "$#" -eq 2 ]
  then
    pkg_repository_graalvm_version=$2
    _pkg_repository_graalvm_validate_version "$pkg_repository_graalvm_version" || return 1
    if [ -e "$pkg_repository_graalvm_repository_dir/versions" ] ||
      [ -L "$pkg_repository_graalvm_repository_dir/versions" ]
    then
      _pkg_repository_graalvm_validate_versions \
        "$pkg_repository_graalvm_repository_dir/versions" || return 1
      if LC_ALL=C command -p -- awk -v version="$pkg_repository_graalvm_version" \
        '$0 == version { found=1 } END { exit !found }' \
        "$pkg_repository_graalvm_repository_dir/versions"
      then
        printf '%s\n' "$pkg_repository_graalvm_version"
        return 0
      fi
    fi
    _pkg_repository_graalvm_find_release "$pkg_repository_graalvm_repository_dir" "$pkg_repository_graalvm_version" >/dev/null || return 1
    printf '%s\n' "$pkg_repository_graalvm_version"
    return 0
  fi
  pkg_repository_graalvm_body="$(_pkg_repository_graalvm_get /releases/latest pkg_repository_resolve_version)" || return 1
  json_object_read \
    tag_name pkg_repository_graalvm_tag_token \
    draft pkg_repository_graalvm_draft_token \
    prerelease pkg_repository_graalvm_prerelease_token \
    created_at pkg_repository_graalvm_created_token \
    published_at pkg_repository_graalvm_published_token <<EOF_GRAALVM_LATEST
$pkg_repository_graalvm_body
EOF_GRAALVM_LATEST
  [ "$?" -eq 0 ] || return 1
  pkg_repository_graalvm_record="$(_pkg_repository_graalvm_release_tokens \
    "$pkg_repository_graalvm_tag_token" \
    "$pkg_repository_graalvm_draft_token" \
    "$pkg_repository_graalvm_prerelease_token" \
    "$pkg_repository_graalvm_created_token" \
    "$pkg_repository_graalvm_published_token")" || return 1
  pkg_repository_graalvm_tab="$(printf '\t')"
  IFS="$pkg_repository_graalvm_tab" read -r pkg_repository_graalvm_created pkg_repository_graalvm_published pkg_repository_graalvm_version pkg_repository_graalvm_tag pkg_repository_graalvm_extra <<EOF_GRAALVM_LATEST_RECORD
$pkg_repository_graalvm_record
EOF_GRAALVM_LATEST_RECORD
  [ -z "$pkg_repository_graalvm_extra" ] || return 1
  printf '%s\n' "$pkg_repository_graalvm_version"
)

pkg_repository_resolve_artifact()
(
  [ "$#" -eq 3 ] || return 2
  pkg_repository_graalvm_repository_dir=$1
  pkg_repository_graalvm_range_dir=$2
  pkg_repository_graalvm_version=$3
  _pkg_repository_graalvm_validate_repository "$pkg_repository_graalvm_repository_dir" || return 1
  _pkg_repository_graalvm_validate_version "$pkg_repository_graalvm_version" || return 1
  [ -d "$pkg_repository_graalvm_range_dir" ] && [ ! -L "$pkg_repository_graalvm_range_dir" ] || return 1
  pkg_repository_graalvm_archive_regex="$(_pkg_repository_graalvm_scalar "$pkg_repository_graalvm_range_dir/archive_regex")" || return 1
  pkg_repository_graalvm_digest_type="$(_pkg_repository_graalvm_scalar "$pkg_repository_graalvm_range_dir/digest_type")" || return 1
  [ "$pkg_repository_graalvm_digest_type" = sha256 ] || return 1
  if [ -e "$pkg_repository_graalvm_range_dir/digest_regex" ] || [ -L "$pkg_repository_graalvm_range_dir/digest_regex" ]; then return 1; fi
  pkg_repository_graalvm_release_record="$(_pkg_repository_graalvm_find_release "$pkg_repository_graalvm_repository_dir" "$pkg_repository_graalvm_version")" || return 1
  pkg_repository_graalvm_tab="$(printf '\t')"
  IFS="$pkg_repository_graalvm_tab" read -r pkg_repository_graalvm_created pkg_repository_graalvm_published pkg_repository_graalvm_tag pkg_repository_graalvm_extra <<EOF_GRAALVM_RELEASE_RECORD
$pkg_repository_graalvm_release_record
EOF_GRAALVM_RELEASE_RECORD
  [ -z "$pkg_repository_graalvm_extra" ] || return 1
  pkg_repository_graalvm_body="$(_pkg_repository_graalvm_get "/releases/tags/$pkg_repository_graalvm_tag" pkg_repository_resolve_artifact)" || return 1
  pkg_repository_graalvm_validated="$(_pkg_repository_graalvm_release_body_validate "$pkg_repository_graalvm_body" "$pkg_repository_graalvm_version")" || return 1
  IFS="$pkg_repository_graalvm_tab" read -r pkg_repository_graalvm_exact_created pkg_repository_graalvm_exact_published pkg_repository_graalvm_exact_tag pkg_repository_graalvm_extra <<EOF_GRAALVM_EXACT
$pkg_repository_graalvm_validated
EOF_GRAALVM_EXACT
  [ -z "$pkg_repository_graalvm_extra" ] && [ "$pkg_repository_graalvm_exact_tag" = "$pkg_repository_graalvm_tag" ] || return 1
  pkg_repository_graalvm_assets="$(printf '%s\n' "$pkg_repository_graalvm_body" | json_object_array_object_fields assets name state size digest browser_download_url)" || return 1
  [ -n "$pkg_repository_graalvm_assets" ] || return 1
  pkg_repository_graalvm_asset="$(printf '%s\n' "$pkg_repository_graalvm_assets" | LC_ALL=C command -p -- awk -F "$pkg_repository_graalvm_tab" -v expression="$pkg_repository_graalvm_archive_regex" '
function fail() { exit 1 }
{
  if (NF != 5 || $1 !~ /^s:/) fail()
  name=$1; sub(/^s:/,"",name)
  if (name ~ expression) { count++; selected=$0 }
}
END { if (count != 1) exit 1; print selected }
')" || return 1
  IFS="$pkg_repository_graalvm_tab" read -r \
    pkg_repository_graalvm_name_token \
    pkg_repository_graalvm_state_token \
    pkg_repository_graalvm_size_token \
    pkg_repository_graalvm_digest_token \
    pkg_repository_graalvm_url_token \
    pkg_repository_graalvm_extra <<EOF_GRAALVM_ASSET
$pkg_repository_graalvm_asset
EOF_GRAALVM_ASSET
  [ -z "$pkg_repository_graalvm_extra" ] || return 1
  case "$pkg_repository_graalvm_name_token" in s:*) pkg_repository_graalvm_name=${pkg_repository_graalvm_name_token#s:};; *) return 1;; esac
  [ "$pkg_repository_graalvm_state_token" = s:uploaded ] || return 1
  case "$pkg_repository_graalvm_size_token" in n:*) pkg_repository_graalvm_size=${pkg_repository_graalvm_size_token#n:};; *) return 1;; esac
  case "$pkg_repository_graalvm_size" in ''|*[!0-9]*) return 1;; esac
  [ "$pkg_repository_graalvm_size" -gt 0 ] || return 1
  case "$pkg_repository_graalvm_digest_token" in s:sha256:*) pkg_repository_graalvm_digest=${pkg_repository_graalvm_digest_token#s:sha256:};; *) return 1;; esac
  [ "${#pkg_repository_graalvm_digest}" -eq 64 ] || return 1
  case "$pkg_repository_graalvm_digest" in *[!0-9A-Fa-f]*) return 1;; esac
  pkg_repository_graalvm_digest="$(printf '%s\n' "$pkg_repository_graalvm_digest" | command -p -- tr 'A-F' 'a-f')" || return 1
  case "$pkg_repository_graalvm_url_token" in s:https://*) pkg_repository_graalvm_url=${pkg_repository_graalvm_url_token#s:};; *) return 1;; esac
  pkg_repository_graalvm_expected_url="https://github.com/graalvm/graalvm-ce-builds/releases/download/$pkg_repository_graalvm_tag/$pkg_repository_graalvm_name"
  [ "$pkg_repository_graalvm_url" = "$pkg_repository_graalvm_expected_url" ] || return 1
  LC_ALL=C command -p -- awk -v name="$pkg_repository_graalvm_name" -v expression="$pkg_repository_graalvm_archive_regex" 'BEGIN { exit(name ~ expression ? 0 : 1) }' || return 1
  printf 'name=%s\nurl=%s\nsize=%s\ndigest=sha256:%s\n' \
    "$pkg_repository_graalvm_name" "$pkg_repository_graalvm_url" "$pkg_repository_graalvm_size" "$pkg_repository_graalvm_digest"
)
