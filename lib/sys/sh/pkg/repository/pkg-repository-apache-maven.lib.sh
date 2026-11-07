loadsyslib "pkg/repository/pkg-repository-artifact"

_pkg_repository_apache_maven_scalar()
{
  [ "$#" -eq 1 ] || return 2
  pkg_repository_apache_maven_scalar_file=$1

  [ -f "$pkg_repository_apache_maven_scalar_file" ] && \
  [ ! -L "$pkg_repository_apache_maven_scalar_file" ] && \
  [ -r "$pkg_repository_apache_maven_scalar_file" ] && \
  [ ! -x "$pkg_repository_apache_maven_scalar_file" ] || return 1

  pkg_repository_apache_maven_scalar_value=
  pkg_repository_apache_maven_scalar_extra=
  {
    IFS= read -r pkg_repository_apache_maven_scalar_value || return 1
    IFS= read -r pkg_repository_apache_maven_scalar_extra
    pkg_repository_apache_maven_scalar_second_status=$?
  } < "$pkg_repository_apache_maven_scalar_file"

  [ "$pkg_repository_apache_maven_scalar_second_status" -ne 0 ] || return 1
  [ -z "$pkg_repository_apache_maven_scalar_extra" ] || return 1
  [ -n "$pkg_repository_apache_maven_scalar_value" ] || return 1

  pkg_repository_apache_maven_scalar_cr="$(printf '\r')"
  case "$pkg_repository_apache_maven_scalar_value" in
    *"$pkg_repository_apache_maven_scalar_cr"*) return 1;;
  esac

  pkg_repository_apache_maven_scalar_actual="$(command -p -- wc -c < "$pkg_repository_apache_maven_scalar_file")" || return 1
  pkg_repository_apache_maven_scalar_expected="$(printf '%s\n' "$pkg_repository_apache_maven_scalar_value" | command -p -- wc -c)" || return 1
  [ "$pkg_repository_apache_maven_scalar_actual" = "$pkg_repository_apache_maven_scalar_expected" ] || return 1

  printf -- '%s\n' "$pkg_repository_apache_maven_scalar_value"
}

_pkg_repository_apache_maven_validate_repository()
{
  [ "$#" -eq 1 ] || return 2
  pkg_repository_apache_maven_repository_dir=$1

  [ -d "$pkg_repository_apache_maven_repository_dir" ] && [ ! -L "$pkg_repository_apache_maven_repository_dir" ] || return 1

  for pkg_repository_apache_maven_repository_item in \
    "$pkg_repository_apache_maven_repository_dir"/* \
    "$pkg_repository_apache_maven_repository_dir"/.[!.]* \
    "$pkg_repository_apache_maven_repository_dir"/..?*
  do
    [ -e "$pkg_repository_apache_maven_repository_item" ] || [ -L "$pkg_repository_apache_maven_repository_item" ] || continue
    pkg_repository_apache_maven_repository_name=${pkg_repository_apache_maven_repository_item##*/}
    [ "$pkg_repository_apache_maven_repository_name" = type ] || return 1
  done

  pkg_repository_apache_maven_type="$(_pkg_repository_apache_maven_scalar "$pkg_repository_apache_maven_repository_dir/type")" || return 1
  [ "$pkg_repository_apache_maven_type" = apache-maven ] || return 1
}

_pkg_repository_apache_maven_version_key()
{
  [ "$#" -eq 1 ] || return 2

  LC_ALL=C command -p -- awk -v version="$1" '
function decimal(value, positive)
{
  if (positive) return value ~ /^[1-9][0-9]*$/
  return value ~ /^(0|[1-9][0-9]*)$/
}
function parse(value, result, suffix, parts, qcount, pcount)
{
  qcount=split(value, suffix, /-rc-/)
  if (qcount != 1 && qcount != 2) return 0

  pcount=split(suffix[1], parts, /[.]/)
  if (pcount != 3) return 0
  if (!decimal(parts[1], 0) || !decimal(parts[2], 0) || !decimal(parts[3], 0)) return 0

  result[1]=parts[1]
  result[2]=parts[2]
  result[3]=parts[3]

  if (qcount == 2) {
    if (!decimal(suffix[2], 1)) return 0
    result[4]=0
    result[5]=suffix[2]
  } else {
    result[4]=1
    result[5]=""
  }
  return 1
}
BEGIN {
  if (!parse(version, parsed)) exit 1
  printf "%d\t%s\t%d\t%s\t%d\t%s\t%d\t%d\t%s\t%s\n", \
    length(parsed[1]), parsed[1], \
    length(parsed[2]), parsed[2], \
    length(parsed[3]), parsed[3], \
    parsed[4], length(parsed[5]), parsed[5], version
}
'
}

_pkg_repository_apache_maven_validate_version()
{
  [ "$#" -eq 1 ] || return 2
  _pkg_repository_apache_maven_version_key "$1" >/dev/null
}

_pkg_repository_apache_maven_compare_values()
{
  [ "$#" -eq 2 ] || return 2

  LC_ALL=C command -p -- awk -v left="$1" -v right="$2" '
function decimal(value, positive)
{
  if (positive) return value ~ /^[1-9][0-9]*$/
  return value ~ /^(0|[1-9][0-9]*)$/
}
function parse(value, result, suffix, parts, qcount, pcount)
{
  qcount=split(value, suffix, /-rc-/)
  if (qcount != 1 && qcount != 2) return 0
  pcount=split(suffix[1], parts, /[.]/)
  if (pcount != 3) return 0
  if (!decimal(parts[1], 0) || !decimal(parts[2], 0) || !decimal(parts[3], 0)) return 0
  result[1]=parts[1]
  result[2]=parts[2]
  result[3]=parts[3]
  if (qcount == 2) {
    if (!decimal(suffix[2], 1)) return 0
    result[4]=0
    result[5]=suffix[2]
  } else {
    result[4]=1
    result[5]=""
  }
  return 1
}
function cmp_decimal(a, b)
{
  if (length(a) < length(b)) return -1
  if (length(a) > length(b)) return 1
  if (a == b) return 0
  return (("x" a) < ("x" b)) ? -1 : 1
}
BEGIN {
  if (!parse(left, l) || !parse(right, r)) exit 1
  for (i=1; i<=3; i++) {
    cmp=cmp_decimal(l[i], r[i])
    if (cmp != 0) { print cmp; exit 0 }
  }
  if (l[4] < r[4]) { print -1; exit 0 }
  if (l[4] > r[4]) { print 1; exit 0 }
  if (l[4] == 0) {
    cmp=cmp_decimal(l[5], r[5])
    print cmp
    exit 0
  }
  print 0
}
'
}

_pkg_repository_apache_maven_index_hrefs()
{
  [ "$#" -eq 1 ] || return 2
  _pkg_repository_apache_maven_validate_repository "$1" || return 1

  pkg_repository_apache_maven_index_body="$(http-fetch -- 'https://dlcdn.apache.org/maven/maven-4/')" || return 1
  printf '%s\n' "$pkg_repository_apache_maven_index_body" | LC_ALL=C command -p -- awk '
{
  remainder=$0
  while (match(remainder, /href="[^"]+"/)) {
    print substr(remainder, RSTART + 6, RLENGTH - 7)
    remainder=substr(remainder, RSTART + RLENGTH)
  }
}
'
}

_pkg_repository_apache_maven_index_contains()
{
  [ "$#" -eq 2 ] || return 2
  _pkg_repository_apache_maven_validate_version "$2" || return 1

  _pkg_repository_apache_maven_index_hrefs "$1" | LC_ALL=C command -p -- awk -v expected="$2/" '
$0 == expected { count++ }
END { exit(count == 1 ? 0 : 1) }
'
}

_pkg_repository_apache_maven_release_metadata()
{
  [ "$#" -eq 1 ] || return 2
  pkg_repository_apache_maven_version=$1
  _pkg_repository_apache_maven_validate_version "$pkg_repository_apache_maven_version" || return 1

  pkg_repository_apache_maven_download="$(pkg_repository_artifact_download_template_url \
    'apache-maven-{version}-bin.tar.gz' \
    'https://dlcdn.apache.org/maven/maven-4/{version}/binaries/{name}' \
    "$pkg_repository_apache_maven_version")" || return 1
  pkg_repository_apache_maven_tab="$(printf '\t')"
  IFS="$pkg_repository_apache_maven_tab" read -r \
    pkg_repository_apache_maven_name \
    pkg_repository_apache_maven_url \
    pkg_repository_apache_maven_extra <<EOF_DOWNLOAD
$pkg_repository_apache_maven_download
EOF_DOWNLOAD
  [ -z "$pkg_repository_apache_maven_extra" ] || return 1
  [ -n "$pkg_repository_apache_maven_name" ] && [ -n "$pkg_repository_apache_maven_url" ] || return 1

  pkg_repository_apache_maven_checksum_url="https://downloads.apache.org/maven/maven-4/$pkg_repository_apache_maven_version/binaries/$pkg_repository_apache_maven_name.sha512"

  pkg_repository_apache_maven_metadata="$(pkg_repository_artifact_metadata_checksum_sidecar \
    "$pkg_repository_apache_maven_checksum_url" \
    digest-only \
    sha512 \
    "$pkg_repository_apache_maven_name" \
    "$pkg_repository_apache_maven_url")" || return 1

  pkg_repository_apache_maven_tab="$(printf '\t')"
  IFS="$pkg_repository_apache_maven_tab" read -r \
    pkg_repository_apache_maven_size \
    pkg_repository_apache_maven_digest \
    pkg_repository_apache_maven_extra <<EOF_METADATA
$pkg_repository_apache_maven_metadata
EOF_METADATA
  [ -z "$pkg_repository_apache_maven_extra" ] || return 1
  case "$pkg_repository_apache_maven_digest" in
    sha512:*) pkg_repository_apache_maven_digest=${pkg_repository_apache_maven_digest#sha512:};;
    *) return 1;;
  esac

  printf -- '%s\t%s\n' "$pkg_repository_apache_maven_size" "$pkg_repository_apache_maven_digest"
}

_pkg_repository_apache_maven_validate_exact_release()
{
  [ "$#" -eq 2 ] || return 2
  _pkg_repository_apache_maven_validate_repository "$1" || return 1
  _pkg_repository_apache_maven_validate_version "$2" || return 1
  _pkg_repository_apache_maven_index_contains "$1" "$2" || return 1
  _pkg_repository_apache_maven_release_metadata "$2" >/dev/null || return 1
}

pkg_repository_list_versions()
(
  [ "$#" -eq 1 ] || return 2
  _pkg_repository_apache_maven_validate_repository "$1" || return 1

  pkg_repository_apache_maven_hrefs="$(_pkg_repository_apache_maven_index_hrefs "$1")" || return 1
  pkg_repository_apache_maven_records=
  pkg_repository_apache_maven_seen='
'
  pkg_repository_apache_maven_lf='
'

  while IFS= read -r pkg_repository_apache_maven_href
  do
    case "$pkg_repository_apache_maven_href" in
      */) pkg_repository_apache_maven_candidate=${pkg_repository_apache_maven_href%/};;
      *) continue;;
    esac

    _pkg_repository_apache_maven_validate_version "$pkg_repository_apache_maven_candidate" || continue

    case "$pkg_repository_apache_maven_seen" in
      *"$pkg_repository_apache_maven_lf$pkg_repository_apache_maven_candidate$pkg_repository_apache_maven_lf"*) return 1;;
    esac
    pkg_repository_apache_maven_seen="$pkg_repository_apache_maven_seen$pkg_repository_apache_maven_candidate$pkg_repository_apache_maven_lf"

    _pkg_repository_apache_maven_release_metadata "$pkg_repository_apache_maven_candidate" >/dev/null || continue
    pkg_repository_apache_maven_key="$(_pkg_repository_apache_maven_version_key "$pkg_repository_apache_maven_candidate")" || return 1

    if [ -n "$pkg_repository_apache_maven_records" ]
    then
      pkg_repository_apache_maven_records="$pkg_repository_apache_maven_records$pkg_repository_apache_maven_lf$pkg_repository_apache_maven_key"
    else
      pkg_repository_apache_maven_records=$pkg_repository_apache_maven_key
    fi
  done <<EOF_HREFS
$pkg_repository_apache_maven_hrefs
EOF_HREFS

  [ -n "$pkg_repository_apache_maven_records" ] || return 0

  pkg_repository_apache_maven_tab="$(printf '\t')"
  printf '%s\n' "$pkg_repository_apache_maven_records" | \
    LC_ALL=C command -p -- sort -t "$pkg_repository_apache_maven_tab" \
      -k1,1n -k2,2 -k3,3n -k4,4 -k5,5n -k6,6 -k7,7n -k8,8n -k9,9 -k10,10 | \
    LC_ALL=C command -p -- awk -F "$pkg_repository_apache_maven_tab" '
NF != 10 { exit 1 }
{ print $10 }
'
)

pkg_repository_compare_versions()
(
  [ "$#" -eq 3 ] || return 2
  pkg_repository_apache_maven_repository_dir=$1
  pkg_repository_apache_maven_left=$2
  pkg_repository_apache_maven_right=$3

  _pkg_repository_apache_maven_validate_repository "$pkg_repository_apache_maven_repository_dir" || return 1
  _pkg_repository_apache_maven_validate_exact_release "$pkg_repository_apache_maven_repository_dir" "$pkg_repository_apache_maven_left" || return 1

  if [ "$pkg_repository_apache_maven_left" = "$pkg_repository_apache_maven_right" ]
  then
    printf -- '0\n'
    return 0
  fi

  _pkg_repository_apache_maven_validate_exact_release "$pkg_repository_apache_maven_repository_dir" "$pkg_repository_apache_maven_right" || return 1
  _pkg_repository_apache_maven_compare_values "$pkg_repository_apache_maven_left" "$pkg_repository_apache_maven_right"
)

pkg_repository_resolve_version()
(
  [ "$#" -ge 1 ] && [ "$#" -le 2 ] || return 2
  _pkg_repository_apache_maven_validate_repository "$1" || return 1

  if [ "$#" -eq 2 ]
  then
    _pkg_repository_apache_maven_validate_exact_release "$1" "$2" || return 1
    printf -- '%s\n' "$2"
    return 0
  fi

  pkg_repository_apache_maven_versions="$(pkg_repository_list_versions "$1")" || return 1
  [ -n "$pkg_repository_apache_maven_versions" ] || return 1
  printf '%s\n' "$pkg_repository_apache_maven_versions" | LC_ALL=C command -p -- awk '
NF { latest=$0 }
END {
  if (latest == "") exit 1
  print latest
}
'
)

pkg_repository_resolve_artifact()
(
  [ "$#" -eq 3 ] || return 2
  pkg_repository_apache_maven_repository_dir=$1
  pkg_repository_apache_maven_range_dir=$2
  pkg_repository_apache_maven_version=$3

  _pkg_repository_apache_maven_validate_repository "$pkg_repository_apache_maven_repository_dir" || return 1
  _pkg_repository_apache_maven_validate_version "$pkg_repository_apache_maven_version" || return 1
  _pkg_repository_apache_maven_index_contains "$pkg_repository_apache_maven_repository_dir" "$pkg_repository_apache_maven_version" || return 1
  [ -d "$pkg_repository_apache_maven_range_dir" ] && [ ! -L "$pkg_repository_apache_maven_range_dir" ] || return 1

  pkg_repository_apache_maven_archive_regex="$(_pkg_repository_apache_maven_scalar "$pkg_repository_apache_maven_range_dir/archive_regex")" || return 1
  LC_ALL=C command -p -- awk -v expression="$pkg_repository_apache_maven_archive_regex" 'BEGIN { value=""; value ~ expression; exit 0 }' || return 1

  if [ -e "$pkg_repository_apache_maven_range_dir/digest_regex" ] || [ -L "$pkg_repository_apache_maven_range_dir/digest_regex" ]
  then
    return 1
  fi

  pkg_repository_apache_maven_digest_type="$(_pkg_repository_apache_maven_scalar "$pkg_repository_apache_maven_range_dir/digest_type")" || return 1
  [ "$pkg_repository_apache_maven_digest_type" = sha512 ] || return 1

  pkg_repository_apache_maven_name="apache-maven-$pkg_repository_apache_maven_version-bin.tar.gz"
  LC_ALL=C command -p -- awk \
    -v value="$pkg_repository_apache_maven_name" \
    -v expression="$pkg_repository_apache_maven_archive_regex" \
    'BEGIN { exit(value ~ expression ? 0 : 1) }' || return 1

  pkg_repository_apache_maven_metadata="$(_pkg_repository_apache_maven_release_metadata "$pkg_repository_apache_maven_version")" || return 1
  pkg_repository_apache_maven_tab="$(printf '\t')"
  IFS="$pkg_repository_apache_maven_tab" read -r \
    pkg_repository_apache_maven_size \
    pkg_repository_apache_maven_digest \
    pkg_repository_apache_maven_extra <<EOF_METADATA
$pkg_repository_apache_maven_metadata
EOF_METADATA
  [ -z "$pkg_repository_apache_maven_extra" ] || return 1
  [ -n "$pkg_repository_apache_maven_size" ] && [ -n "$pkg_repository_apache_maven_digest" ] || return 1

  pkg_repository_apache_maven_url="https://dlcdn.apache.org/maven/maven-4/$pkg_repository_apache_maven_version/binaries/$pkg_repository_apache_maven_name"
  printf -- 'name=%s\n' "$pkg_repository_apache_maven_name"
  printf -- 'url=%s\n' "$pkg_repository_apache_maven_url"
  printf -- 'size=%s\n' "$pkg_repository_apache_maven_size"
  printf -- 'digest=sha512:%s\n' "$pkg_repository_apache_maven_digest"
)
