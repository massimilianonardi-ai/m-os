loadsyslib "json"

_pkg_repository_temurin_scalar()
{
  [ "$#" -eq 1 ] || return 2
  pkg_repository_temurin_scalar_file="$1"

  [ -f "$pkg_repository_temurin_scalar_file" ] && \
  [ ! -L "$pkg_repository_temurin_scalar_file" ] && \
  [ ! -x "$pkg_repository_temurin_scalar_file" ] || return 1

  pkg_repository_temurin_scalar_value=
  pkg_repository_temurin_scalar_extra=
  {
    IFS= read -r pkg_repository_temurin_scalar_value || return 1
    IFS= read -r pkg_repository_temurin_scalar_extra
    pkg_repository_temurin_scalar_second_status=$?
  } < "$pkg_repository_temurin_scalar_file"

  [ "$pkg_repository_temurin_scalar_second_status" -ne 0 ] || return 1
  [ -z "$pkg_repository_temurin_scalar_extra" ] || return 1
  [ -n "$pkg_repository_temurin_scalar_value" ] || return 1

  pkg_repository_temurin_scalar_cr="$(printf '\r')"
  case "$pkg_repository_temurin_scalar_value" in
    *"$pkg_repository_temurin_scalar_cr"*) return 1;;
  esac

  pkg_repository_temurin_scalar_actual="$(command -p -- wc -c < "$pkg_repository_temurin_scalar_file")" || return 1
  pkg_repository_temurin_scalar_expected="$(printf '%s\n' "$pkg_repository_temurin_scalar_value" | command -p -- wc -c)" || return 1
  [ "$pkg_repository_temurin_scalar_actual" = "$pkg_repository_temurin_scalar_expected" ] || return 1

  printf -- '%s\n' "$pkg_repository_temurin_scalar_value"
}

_pkg_repository_temurin_validate_version()
{
  [ "$#" -eq 1 ] || return 2
  LC_ALL=C command -p -- awk -v value="$1" 'BEGIN {
    if (value ~ /^[1-9][0-9]*([.][0-9]+)*[+][0-9]+([.][0-9]+)*$/) exit 0
    exit 1
  }'
}

_pkg_repository_temurin_version_feature()
{
  [ "$#" -eq 1 ] || return 2
  _pkg_repository_temurin_validate_version "$1" || return 1
  printf -- '%s\n' "$1" | LC_ALL=C command -p -- awk -F '[.+]' '{ print $1 }'
}

_pkg_repository_temurin_features_read()
{
  [ "$#" -eq 1 ] || return 2
  pkg_repository_temurin_features_file="$1/feature_versions"
  [ -f "$pkg_repository_temurin_features_file" ] && \
  [ ! -L "$pkg_repository_temurin_features_file" ] && \
  [ -r "$pkg_repository_temurin_features_file" ] && \
  [ ! -x "$pkg_repository_temurin_features_file" ] || return 1

  pkg_repository_temurin_previous=
  pkg_repository_temurin_count=0
  while IFS= read -r pkg_repository_temurin_feature
  do
    case "$pkg_repository_temurin_feature" in
      ''|0|0*|*[!0-9]*) return 1;;
    esac
    if [ -n "$pkg_repository_temurin_previous" ]
    then
      [ "$pkg_repository_temurin_previous" -lt "$pkg_repository_temurin_feature" ] || return 1
    fi
    pkg_repository_temurin_previous=$pkg_repository_temurin_feature
    pkg_repository_temurin_count=$((pkg_repository_temurin_count + 1))
    printf -- '%s\n' "$pkg_repository_temurin_feature"
  done < "$pkg_repository_temurin_features_file"

  [ "$pkg_repository_temurin_count" -gt 0 ]
}

_pkg_repository_temurin_feature_supported()
{
  [ "$#" -eq 2 ] || return 2
  pkg_repository_temurin_wanted_feature=$2
  case "$pkg_repository_temurin_wanted_feature" in
    ''|0|0*|*[!0-9]*) return 1;;
  esac
  pkg_repository_temurin_features="$(_pkg_repository_temurin_features_read "$1")" || return 1
  while IFS= read -r pkg_repository_temurin_feature
  do
    [ "$pkg_repository_temurin_feature" = "$pkg_repository_temurin_wanted_feature" ] && return 0
  done <<EOF_FEATURES
$pkg_repository_temurin_features
EOF_FEATURES
  return 1
}

_pkg_repository_temurin_validate_repository()
{
  [ "$#" -eq 1 ] || return 2
  pkg_repository_temurin_repository_dir="$1"

  [ -d "$pkg_repository_temurin_repository_dir" ] && [ ! -L "$pkg_repository_temurin_repository_dir" ] || return 1

  for pkg_repository_temurin_repository_item in \
    "$pkg_repository_temurin_repository_dir"/* \
    "$pkg_repository_temurin_repository_dir"/.[!.]* \
    "$pkg_repository_temurin_repository_dir"/..?*
  do
    [ -e "$pkg_repository_temurin_repository_item" ] || [ -L "$pkg_repository_temurin_repository_item" ] || continue
    pkg_repository_temurin_repository_name=${pkg_repository_temurin_repository_item##*/}
    case "$pkg_repository_temurin_repository_name" in
      type|os|architecture|feature_versions) :;;
      *) return 1;;
    esac
  done

  pkg_repository_temurin_type="$(_pkg_repository_temurin_scalar "$pkg_repository_temurin_repository_dir/type")" || return 1
  pkg_repository_temurin_os="$(_pkg_repository_temurin_scalar "$pkg_repository_temurin_repository_dir/os")" || return 1
  pkg_repository_temurin_architecture="$(_pkg_repository_temurin_scalar "$pkg_repository_temurin_repository_dir/architecture")" || return 1
  pkg_repository_temurin_features="$(_pkg_repository_temurin_features_read "$pkg_repository_temurin_repository_dir")" || return 1

  [ "$pkg_repository_temurin_type" = temurin ] || return 1

  case "$pkg_repository_temurin_os/$pkg_repository_temurin_architecture" in
    linux/x64|linux/aarch64|mac/x64|mac/aarch64|windows/x64) :;;
    *) return 1;;
  esac
}

_pkg_repository_temurin_encode_version()
{
  [ "$#" -eq 1 ] || return 2
  _pkg_repository_temurin_validate_version "$1" || return 1
  printf '%s\n' "$1" | command -p -- sed 's/+/%2B/g'
}

_pkg_repository_temurin_release_name_to_version()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in
    jdk-*) pkg_repository_temurin_mapped=${1#jdk-};;
    *) return 1;;
  esac
  _pkg_repository_temurin_validate_version "$pkg_repository_temurin_mapped" || return 1
  printf -- '%s\n' "$pkg_repository_temurin_mapped"
}

_pkg_repository_temurin_list_url()
{
  [ "$#" -eq 3 ] || return 2
  _pkg_repository_temurin_validate_repository "$1" || return 1
  _pkg_repository_temurin_feature_supported "$1" "$2" || return 1
  case "$3" in ''|*[!0-9]*) return 2;; esac
  printf -- 'https://api.adoptium.net/v3/assets/feature_releases/%s/ga?architecture=%s&heap_size=normal&image_type=jdk&jvm_impl=hotspot&os=%s&page=%s&page_size=20&project=jdk&sort_method=DATE&sort_order=ASC&vendor=eclipse\n' \
    "$2" \
    "$pkg_repository_temurin_architecture" \
    "$pkg_repository_temurin_os" \
    "$3"
}

pkg_repository_list_versions()
(
  [ "$#" -eq 1 ] || return 2
  _pkg_repository_temurin_validate_repository "$1" || return 1

  pkg_repository_temurin_versions=
  pkg_repository_temurin_lf='
'

  while IFS= read -r pkg_repository_temurin_feature
  do
    pkg_repository_temurin_page=0
    while :
    do
      pkg_repository_temurin_url="$(_pkg_repository_temurin_list_url "$1" "$pkg_repository_temurin_feature" "$pkg_repository_temurin_page")" || return 1
      pkg_repository_temurin_body="$(http-fetch -- "$pkg_repository_temurin_url")" || return 1
      pkg_repository_temurin_records="$(printf '%s\n' "$pkg_repository_temurin_body" | json_array_object_fields release_name)" || return 1

      pkg_repository_temurin_count=0
      if [ -n "$pkg_repository_temurin_records" ]
      then
        while IFS= read -r pkg_repository_temurin_release_token
        do
          pkg_repository_temurin_count=$((pkg_repository_temurin_count + 1))
          case "$pkg_repository_temurin_release_token" in
            s:*) pkg_repository_temurin_release_name=${pkg_repository_temurin_release_token#s:};;
            *) return 1;;
          esac
          pkg_repository_temurin_version="$(_pkg_repository_temurin_release_name_to_version "$pkg_repository_temurin_release_name")" || return 1
          pkg_repository_temurin_version_feature="$(_pkg_repository_temurin_version_feature "$pkg_repository_temurin_version")" || return 1
          [ "$pkg_repository_temurin_version_feature" = "$pkg_repository_temurin_feature" ] || return 1

          case "$pkg_repository_temurin_lf$pkg_repository_temurin_versions$pkg_repository_temurin_lf" in
            *"$pkg_repository_temurin_lf$pkg_repository_temurin_version$pkg_repository_temurin_lf"*) return 1;;
          esac
          if [ -n "$pkg_repository_temurin_versions" ]
          then
            pkg_repository_temurin_versions="$pkg_repository_temurin_versions$pkg_repository_temurin_lf$pkg_repository_temurin_version"
          else
            pkg_repository_temurin_versions=$pkg_repository_temurin_version
          fi
        done <<EOF_RECORDS
$pkg_repository_temurin_records
EOF_RECORDS
      fi

      [ "$pkg_repository_temurin_count" -ge 20 ] || break
      pkg_repository_temurin_page=$((pkg_repository_temurin_page + 1))
    done
  done <<EOF_FEATURES
$pkg_repository_temurin_features
EOF_FEATURES

  [ -z "$pkg_repository_temurin_versions" ] || printf -- '%s\n' "$pkg_repository_temurin_versions"
)

pkg_repository_resolve_version()
(
  [ "$#" -ge 1 ] && [ "$#" -le 2 ] || return 2
  _pkg_repository_temurin_validate_repository "$1" || return 1

  pkg_repository_temurin_versions="$(pkg_repository_list_versions "$1")" || return 1
  [ -n "$pkg_repository_temurin_versions" ] || return 1

  if [ "$#" -eq 1 ]
  then
    printf '%s\n' "$pkg_repository_temurin_versions" | LC_ALL=C command -p -- awk 'NF { latest=$0 } END { if (latest == "") exit 1; print latest }'
    return "$?"
  fi

  pkg_repository_temurin_requested="$2"
  _pkg_repository_temurin_validate_version "$pkg_repository_temurin_requested" || return 1
  pkg_repository_temurin_found=0
  while IFS= read -r pkg_repository_temurin_version
  do
    if [ "$pkg_repository_temurin_version" = "$pkg_repository_temurin_requested" ]
    then
      pkg_repository_temurin_found=$((pkg_repository_temurin_found + 1))
    fi
  done <<EOF_VERSIONS
$pkg_repository_temurin_versions
EOF_VERSIONS
  [ "$pkg_repository_temurin_found" -eq 1 ] || return 1
  printf -- '%s\n' "$pkg_repository_temurin_requested"
)

pkg_repository_compare_versions()
(
  [ "$#" -eq 3 ] || return 2
  _pkg_repository_temurin_validate_repository "$1" || return 1
  _pkg_repository_temurin_validate_version "$2" || return 1
  _pkg_repository_temurin_validate_version "$3" || return 1

  pkg_repository_temurin_versions="$(pkg_repository_list_versions "$1")" || return 1
  pkg_repository_temurin_index=0
  pkg_repository_temurin_left_index=
  pkg_repository_temurin_right_index=
  while IFS= read -r pkg_repository_temurin_version
  do
    pkg_repository_temurin_index=$((pkg_repository_temurin_index + 1))
    [ "$pkg_repository_temurin_version" = "$2" ] && pkg_repository_temurin_left_index=$pkg_repository_temurin_index
    [ "$pkg_repository_temurin_version" = "$3" ] && pkg_repository_temurin_right_index=$pkg_repository_temurin_index
  done <<EOF_VERSIONS
$pkg_repository_temurin_versions
EOF_VERSIONS

  [ -n "$pkg_repository_temurin_left_index" ] && [ -n "$pkg_repository_temurin_right_index" ] || return 1
  if [ "$pkg_repository_temurin_left_index" -lt "$pkg_repository_temurin_right_index" ]
  then
    printf -- '%s\n' -1
  elif [ "$pkg_repository_temurin_left_index" -gt "$pkg_repository_temurin_right_index" ]
  then
    printf -- '%s\n' 1
  else
    printf -- '%s\n' 0
  fi
)

pkg_repository_resolve_artifact()
(
  [ "$#" -eq 3 ] || return 2
  _pkg_repository_temurin_validate_repository "$1" || return 1
  pkg_repository_temurin_range_dir="$2"
  pkg_repository_temurin_requested="$3"

  _pkg_repository_temurin_validate_version "$pkg_repository_temurin_requested" || return 1
  [ -d "$pkg_repository_temurin_range_dir" ] && [ ! -L "$pkg_repository_temurin_range_dir" ] || return 1
  [ "$(pkg_repository_resolve_version "$1" "$pkg_repository_temurin_requested")" = "$pkg_repository_temurin_requested" ] || return 1

  pkg_repository_temurin_archive_regex="$(_pkg_repository_temurin_scalar "$pkg_repository_temurin_range_dir/archive_regex")" || return 1
  LC_ALL=C command -p -- awk -v expression="$pkg_repository_temurin_archive_regex" 'BEGIN { value=""; value ~ expression; exit 0 }' || return 1

  if [ -e "$pkg_repository_temurin_range_dir/digest_regex" ] || [ -L "$pkg_repository_temurin_range_dir/digest_regex" ]
  then
    return 1
  fi

  pkg_repository_temurin_digest_type="$(_pkg_repository_temurin_scalar "$pkg_repository_temurin_range_dir/digest_type")" || return 1
  [ "$pkg_repository_temurin_digest_type" = sha256 ] || return 1

  pkg_repository_temurin_feature="$(_pkg_repository_temurin_version_feature "$pkg_repository_temurin_requested")" || return 1
  _pkg_repository_temurin_feature_supported "$1" "$pkg_repository_temurin_feature" || return 1
  pkg_repository_temurin_encoded="$(_pkg_repository_temurin_encode_version "$pkg_repository_temurin_requested")" || return 1
  pkg_repository_temurin_upstream="jdk-$pkg_repository_temurin_encoded"
  pkg_repository_temurin_base="https://api.adoptium.net/v3"
  pkg_repository_temurin_path="$pkg_repository_temurin_os/$pkg_repository_temurin_architecture/jdk/hotspot/normal/eclipse?project=jdk"
  pkg_repository_temurin_checksum_url="$pkg_repository_temurin_base/checksum/version/$pkg_repository_temurin_upstream/$pkg_repository_temurin_path"
  pkg_repository_temurin_binary_url="$pkg_repository_temurin_base/binary/version/$pkg_repository_temurin_upstream/$pkg_repository_temurin_path"

  pkg_repository_temurin_checksums="$(http-fetch -- "$pkg_repository_temurin_checksum_url")" || return 1
  pkg_repository_temurin_selected="$(printf '%s\n' "$pkg_repository_temurin_checksums" | \
    LC_ALL=C command -p -- awk -v expression="$pkg_repository_temurin_archive_regex" '
function fail() { exit 1 }
{
  if (NF != 2) fail()
  digest=$1
  name=$2
  sub(/^\*/, "", name)
  if (name ~ expression) {
    count++
    selected_digest=digest
    selected_name=name
  }
}
END {
  if (count != 1) exit 1
  print selected_digest "\t" selected_name
}
')" || return 1

  pkg_repository_temurin_tab="$(printf '\t')"
  IFS="$pkg_repository_temurin_tab" read -r \
    pkg_repository_temurin_digest \
    pkg_repository_temurin_name \
    pkg_repository_temurin_extra <<EOF_SELECTED
$pkg_repository_temurin_selected
EOF_SELECTED
  [ -z "$pkg_repository_temurin_extra" ] || return 1
  [ -n "$pkg_repository_temurin_name" ] || return 1
  case "$pkg_repository_temurin_name" in */*|.|..) return 1;; esac
  [ "${#pkg_repository_temurin_digest}" -eq 64 ] || return 1
  case "$pkg_repository_temurin_digest" in *[!0-9A-Fa-f]*) return 1;; esac
  pkg_repository_temurin_digest="$(printf '%s\n' "$pkg_repository_temurin_digest" | command -p -- tr 'A-F' 'a-f')" || return 1

  pkg_repository_temurin_size="$(http-fetch -l -- "$pkg_repository_temurin_binary_url")" || return 1
  case "$pkg_repository_temurin_size" in ''|*[!0-9]*|0[0-9]*) return 1;; esac

  printf -- 'name=%s\n' "$pkg_repository_temurin_name"
  printf -- 'url=%s\n' "$pkg_repository_temurin_binary_url"
  printf -- 'size=%s\n' "$pkg_repository_temurin_size"
  printf -- 'digest=sha256:%s\n' "$pkg_repository_temurin_digest"
)
