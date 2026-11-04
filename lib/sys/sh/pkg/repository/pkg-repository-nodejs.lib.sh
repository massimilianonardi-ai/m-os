loadsyslib "json"
loadsyslib "pkg/repository/pkg-repository-artifact"

_pkg_repository_nodejs_scalar()
{
  [ "$#" -eq 1 ] || return 2
  nodejs_scalar_file=$1
  [ -f "$nodejs_scalar_file" ] && [ ! -L "$nodejs_scalar_file" ] && [ ! -x "$nodejs_scalar_file" ] || return 1

  nodejs_scalar_value=
  nodejs_scalar_extra=
  {
    IFS= read -r nodejs_scalar_value || return 1
    IFS= read -r nodejs_scalar_extra
    nodejs_scalar_second_status=$?
  } < "$nodejs_scalar_file"

  [ "$nodejs_scalar_second_status" -ne 0 ] || return 1
  [ -z "$nodejs_scalar_extra" ] || return 1
  [ -n "$nodejs_scalar_value" ] || return 1

  nodejs_scalar_actual="$(command -p -- wc -c < "$nodejs_scalar_file")" || return 1
  nodejs_scalar_expected="$(printf -- '%s\n' "$nodejs_scalar_value" | command -p -- wc -c)" || return 1
  [ "$nodejs_scalar_actual" = "$nodejs_scalar_expected" ] || return 1
  printf -- '%s\n' "$nodejs_scalar_value"
}

_pkg_repository_nodejs_validate_version()
{
  [ "$#" -eq 1 ] || return 2
  LC_ALL=C command -p -- awk -v value="$1" '
BEGIN {
  if (substr(value,1,1) != "v") exit 1
  value=substr(value,2)
  count=split(value,part,/[.]/)
  if (count != 3) exit 1
  for (i=1; i<=3; i++) {
    if (part[i] !~ /^(0|[1-9][0-9]*)$/) exit 1
  }
}
' >/dev/null
}

_pkg_repository_nodejs_version_major()
{
  [ "$#" -eq 1 ] || return 2
  _pkg_repository_nodejs_validate_version "$1" || return 1
  nodejs_version_major="${1#v}"
  nodejs_version_major="${nodejs_version_major%%.*}"
  printf -- '%s\n' "$nodejs_version_major"
}

_pkg_repository_nodejs_validate_repository()
{
  [ "$#" -eq 1 ] || return 2
  nodejs_repository_dir=$1
  [ -d "$nodejs_repository_dir" ] && [ ! -L "$nodejs_repository_dir" ] || return 1

  for nodejs_repository_item in "$nodejs_repository_dir"/* "$nodejs_repository_dir"/.[!.]* "$nodejs_repository_dir"/..?*
  do
    [ -e "$nodejs_repository_item" ] || [ -L "$nodejs_repository_item" ] || continue
    nodejs_repository_name=${nodejs_repository_item##*/}
    case "$nodejs_repository_name" in
      type|major|download|metadata) :;;
      *) return 1;;
    esac
  done

  nodejs_type="$(_pkg_repository_nodejs_scalar "$nodejs_repository_dir/type")" || return 1
  nodejs_major="$(_pkg_repository_nodejs_scalar "$nodejs_repository_dir/major")" || return 1
  [ "$nodejs_type" = nodejs ] || return 1
  case "$nodejs_major" in ''|*[!0-9]*|0|0[0-9]*) return 1;; esac

  pkg_repository_artifact_overrides_validate "$nodejs_repository_dir" || return 1
  [ -d "$nodejs_repository_dir/download" ] && [ ! -L "$nodejs_repository_dir/download" ] || return 1
  [ -d "$nodejs_repository_dir/metadata" ] && [ ! -L "$nodejs_repository_dir/metadata" ] || return 1
}

_pkg_repository_nodejs_get()
{
  [ "$#" -eq 2 ] || return 2
  nodejs_url=$1
  nodejs_function=$2

  http-fetch -- "$nodejs_url"
  nodejs_status=$?
  [ "$nodejs_status" -eq 0 ] && return 0

  log error execution execution-failed \
    operation pkg-repository-nodejs \
    reason upstream-request-failed \
    function "$nodejs_function" \
    url "$nodejs_url" \
    status "$nodejs_status" || :
  return 1
}

_pkg_repository_nodejs_index_versions()
(
  [ "$#" -eq 2 ] || return 2
  _pkg_repository_nodejs_validate_repository "$1" || return 1
  nodejs_function=$2
  nodejs_index_url=https://nodejs.org/dist/index.json

  nodejs_body="$(_pkg_repository_nodejs_get "$nodejs_index_url" "$nodejs_function")" || return 1
  nodejs_records="$(printf '%s\n' "$nodejs_body" | json_array_object_fields version)" || return 1
  [ -n "$nodejs_records" ] || return 1

  nodejs_tab="$(printf '\t')"
  nodejs_seen=
  while IFS="$nodejs_tab" read -r nodejs_token nodejs_extra
  do
    [ -z "$nodejs_extra" ] || return 1
    case "$nodejs_token" in s:*) nodejs_version=${nodejs_token#s:};; *) return 1;; esac
    # The upstream index can start with prereleases of a newer major.
    # Only the configured major is subject to stable-version validation.
    case "$nodejs_version" in
      "v$nodejs_major".*) : ;;
      *) continue ;;
    esac
    _pkg_repository_nodejs_validate_version "$nodejs_version" || return 1
    nodejs_record_major="$(_pkg_repository_nodejs_version_major "$nodejs_version")" || return 1
    [ "$nodejs_record_major" = "$nodejs_major" ] || continue

    case "
$nodejs_seen
" in *"
$nodejs_version
"*) return 1;; esac

    if [ -n "$nodejs_seen" ]; then
      nodejs_seen="$nodejs_seen
$nodejs_version"
    else
      nodejs_seen=$nodejs_version
    fi
    printf -- '%s\n' "$nodejs_version"
  done <<EOF_NODEJS_INDEX
$nodejs_records
EOF_NODEJS_INDEX
)

pkg_repository_list_versions()
(
  [ "$#" -eq 1 ] || return 2
  _pkg_repository_nodejs_index_versions "$1" pkg_repository_list_versions
)

pkg_repository_compare_versions()
(
  [ "$#" -eq 3 ] || return 2
  _pkg_repository_nodejs_validate_repository "$1" || return 1
  _pkg_repository_nodejs_validate_version "$2" || return 1
  _pkg_repository_nodejs_validate_version "$3" || return 1

  nodejs_left_major="$(_pkg_repository_nodejs_version_major "$2")" || return 1
  nodejs_right_major="$(_pkg_repository_nodejs_version_major "$3")" || return 1
  [ "$nodejs_left_major" = "$nodejs_major" ] || return 1
  [ "$nodejs_right_major" = "$nodejs_major" ] || return 1

  [ "$2" = "$3" ] && { printf -- '0\n'; return 0; }

  LC_ALL=C command -p -- awk -v left="$2" -v right="$3" '
function cmp(a,b) {
  if (length(a) < length(b)) return -1
  if (length(a) > length(b)) return 1
  if ("x" a < "x" b) return -1
  if ("x" a > "x" b) return 1
  return 0
}
BEGIN {
  sub(/^v/,"",left); sub(/^v/,"",right)
  split(left,l,/[.]/); split(right,r,/[.]/)
  for (i=1; i<=3; i++) {
    c=cmp(l[i],r[i])
    if (c != 0) { print c; exit 0 }
  }
  exit 1
}
' || return 1
)

pkg_repository_resolve_version()
(
  [ "$#" -ge 1 ] && [ "$#" -le 2 ] || return 2
  _pkg_repository_nodejs_validate_repository "$1" || return 1
  nodejs_versions="$(_pkg_repository_nodejs_index_versions "$1" pkg_repository_resolve_version)" || return 1
  [ -n "$nodejs_versions" ] || return 1

  if [ "$#" -eq 2 ]
  then
    _pkg_repository_nodejs_validate_version "$2" || return 1
    nodejs_requested_major="$(_pkg_repository_nodejs_version_major "$2")" || return 1
    [ "$nodejs_requested_major" = "$nodejs_major" ] || return 1
    while IFS= read -r nodejs_version
    do
      [ "$nodejs_version" = "$2" ] || continue
      printf -- '%s\n' "$2"
      return 0
    done <<EOF_NODEJS_EXACT
$nodejs_versions
EOF_NODEJS_EXACT
    return 1
  fi

  nodejs_latest=
  while IFS= read -r nodejs_version
  do
    [ -n "$nodejs_version" ] || continue
    if [ -z "$nodejs_latest" ]
    then
      nodejs_latest=$nodejs_version
      continue
    fi
    nodejs_cmp="$(pkg_repository_compare_versions "$1" "$nodejs_version" "$nodejs_latest")" || return 1
    [ "$nodejs_cmp" -le 0 ] || nodejs_latest=$nodejs_version
  done <<EOF_NODEJS_LATEST
$nodejs_versions
EOF_NODEJS_LATEST

  [ -n "$nodejs_latest" ] || return 1
  printf -- '%s\n' "$nodejs_latest"
)

pkg_repository_resolve_artifact()
(
  [ "$#" -eq 3 ] || return 2
  nodejs_repository_dir=$1
  nodejs_range_dir=$2
  nodejs_requested=$3

  _pkg_repository_nodejs_validate_repository "$nodejs_repository_dir" || return 1
  [ "$(pkg_repository_resolve_version "$nodejs_repository_dir" "$nodejs_requested")" = "$nodejs_requested" ] || return 1
  [ -d "$nodejs_range_dir" ] && [ ! -L "$nodejs_range_dir" ] || return 1

  nodejs_archive_regex="$(_pkg_repository_nodejs_scalar "$nodejs_range_dir/archive_regex")" || return 1
  [ ! -e "$nodejs_range_dir/digest_regex" ] && [ ! -L "$nodejs_range_dir/digest_regex" ] || return 1
  nodejs_digest_type="$(_pkg_repository_nodejs_scalar "$nodejs_range_dir/digest_type")" || return 1

  nodejs_download="$(pkg_repository_artifact_download_resolve "$nodejs_repository_dir/download" "$nodejs_requested")" || return 1
  nodejs_tab="$(printf '\t')"
  IFS="$nodejs_tab" read -r nodejs_name nodejs_url nodejs_extra <<EOF_NODEJS_DOWNLOAD
$nodejs_download
EOF_NODEJS_DOWNLOAD
  [ -z "$nodejs_extra" ] || return 1
  [ -n "$nodejs_name" ] && [ -n "$nodejs_url" ] || return 1

  LC_ALL=C command -p -- awk -v value="$nodejs_name" -v expression="$nodejs_archive_regex" 'BEGIN { exit(value ~ expression ? 0 : 1) }' || return 1

  nodejs_metadata="$(pkg_repository_artifact_metadata_resolve "$nodejs_repository_dir/metadata" "$nodejs_digest_type" "$nodejs_requested" "$nodejs_name" "$nodejs_url")" || return 1
  IFS="$nodejs_tab" read -r nodejs_size nodejs_digest nodejs_extra <<EOF_NODEJS_METADATA
$nodejs_metadata
EOF_NODEJS_METADATA
  [ -z "$nodejs_extra" ] || return 1
  [ -n "$nodejs_size" ] && [ -n "$nodejs_digest" ] || return 1

  printf -- 'name=%s\n' "$nodejs_name"
  printf -- 'url=%s\n' "$nodejs_url"
  printf -- 'size=%s\n' "$nodejs_size"
  printf -- 'digest=%s\n' "$nodejs_digest"
)
