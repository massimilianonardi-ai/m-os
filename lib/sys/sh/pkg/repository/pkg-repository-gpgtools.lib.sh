_pkg_repository_gpgtools_scalar()
{
  [ "$#" -eq 1 ] || return 2
  pkg_repository_gpgtools_scalar_file=$1
  [ -f "$pkg_repository_gpgtools_scalar_file" ] &&
    [ ! -L "$pkg_repository_gpgtools_scalar_file" ] &&
    [ -r "$pkg_repository_gpgtools_scalar_file" ] &&
    [ ! -x "$pkg_repository_gpgtools_scalar_file" ] || return 1

  pkg_repository_gpgtools_scalar_value=
  pkg_repository_gpgtools_scalar_extra=
  {
    IFS= read -r pkg_repository_gpgtools_scalar_value || return 1
    IFS= read -r pkg_repository_gpgtools_scalar_extra
    pkg_repository_gpgtools_scalar_second_status=$?
  } < "$pkg_repository_gpgtools_scalar_file"
  [ "$pkg_repository_gpgtools_scalar_second_status" -ne 0 ] || return 1
  [ -z "$pkg_repository_gpgtools_scalar_extra" ] && [ -n "$pkg_repository_gpgtools_scalar_value" ] || return 1
  pkg_repository_gpgtools_scalar_cr="$(printf '\r')"
  case "$pkg_repository_gpgtools_scalar_value" in *"$pkg_repository_gpgtools_scalar_cr"*) return 1;; esac
  pkg_repository_gpgtools_scalar_actual="$(command -p -- wc -c < "$pkg_repository_gpgtools_scalar_file")" || return 1
  pkg_repository_gpgtools_scalar_expected="$(printf '%s\n' "$pkg_repository_gpgtools_scalar_value" | command -p -- wc -c)" || return 1
  [ "$pkg_repository_gpgtools_scalar_actual" = "$pkg_repository_gpgtools_scalar_expected" ] || return 1
  printf '%s\n' "$pkg_repository_gpgtools_scalar_value"
}

_pkg_repository_gpgtools_validate_version()
{
  [ "$#" -eq 1 ] || return 2
  LC_ALL=C command -p -- awk -v version="$1" '
BEGIN {
  exit(version ~ /^[0-9][0-9][0-9][0-9][.][0-9][0-9]*[+][0-9][0-9]*n$/ ? 0 : 1)
}
'
}

_pkg_repository_gpgtools_validate_digest()
{
  [ "$#" -eq 1 ] || return 2
  LC_ALL=C command -p -- awk -v digest="$1" '
BEGIN { exit(digest ~ /^[0-9A-Fa-f][0-9A-Fa-f]+$/ && length(digest) == 64 ? 0 : 1) }
'
}

_pkg_repository_gpgtools_validate_url()
{
  [ "$#" -eq 1 ] || return 2
  LC_ALL=C command -p -- awk -v url="$1" '
BEGIN {
  prefix="https://releases.gpgtools.com/nightlies/GPG_Suite-"
  if (index(url, prefix) != 1) exit 1
  suffix=substr(url, length(prefix)+1)
  exit(suffix ~ /^[0-9][0-9]*n[.]dmg$/ ? 0 : 1)
}
'
}

_pkg_repository_gpgtools_validate_repository()
{
  [ "$#" -eq 1 ] || return 2
  pkg_repository_gpgtools_repository_dir=$1
  [ -d "$pkg_repository_gpgtools_repository_dir" ] && [ ! -L "$pkg_repository_gpgtools_repository_dir" ] || return 1

  for pkg_repository_gpgtools_item in \
    "$pkg_repository_gpgtools_repository_dir"/* \
    "$pkg_repository_gpgtools_repository_dir"/.[!.]* \
    "$pkg_repository_gpgtools_repository_dir"/..?*
  do
    [ -e "$pkg_repository_gpgtools_item" ] || [ -L "$pkg_repository_gpgtools_item" ] || continue
    pkg_repository_gpgtools_name=${pkg_repository_gpgtools_item##*/}
    case "$pkg_repository_gpgtools_name" in
      type|version|url|digest)
        [ -f "$pkg_repository_gpgtools_item" ] && [ ! -L "$pkg_repository_gpgtools_item" ] &&
          [ -r "$pkg_repository_gpgtools_item" ] && [ ! -x "$pkg_repository_gpgtools_item" ] || return 1
        ;;
      *) return 1;;
    esac
  done

  pkg_repository_gpgtools_type="$(_pkg_repository_gpgtools_scalar "$pkg_repository_gpgtools_repository_dir/type")" || return 1
  pkg_repository_gpgtools_version="$(_pkg_repository_gpgtools_scalar "$pkg_repository_gpgtools_repository_dir/version")" || return 1
  pkg_repository_gpgtools_url="$(_pkg_repository_gpgtools_scalar "$pkg_repository_gpgtools_repository_dir/url")" || return 1
  pkg_repository_gpgtools_digest="$(_pkg_repository_gpgtools_scalar "$pkg_repository_gpgtools_repository_dir/digest")" || return 1
  [ "$pkg_repository_gpgtools_type" = gpgtools ] || return 1
  _pkg_repository_gpgtools_validate_version "$pkg_repository_gpgtools_version" || return 1
  _pkg_repository_gpgtools_validate_url "$pkg_repository_gpgtools_url" || return 1
  _pkg_repository_gpgtools_validate_digest "$pkg_repository_gpgtools_digest" || return 1
}

_pkg_repository_gpgtools_latest_release()
(
  [ "$#" -eq 0 ] || return 2
  pkg_repository_gpgtools_url='https://releases.gpgtools.com/nightlies/'
  pkg_repository_gpgtools_body="$(http-fetch -- "$pkg_repository_gpgtools_url")"
  pkg_repository_gpgtools_fetch_status=$?
  if [ "$pkg_repository_gpgtools_fetch_status" -ne 0 ]
  then
    log error pkg-repository-gpgtools latest-index-fetch-failed \
      url "$pkg_repository_gpgtools_url" status "$pkg_repository_gpgtools_fetch_status" || :
    return 1
  fi

  pkg_repository_gpgtools_lf='
'
  printf '%s\n' "$pkg_repository_gpgtools_body" | LC_ALL=C command -p -- awk '
function fail() { invalid=1; exit 1 }
function field(row, marker, closing,    start, rest, finish, after) {
  start=index(row, marker)
  if (!start) fail()
  rest=substr(row, start+length(marker))
  finish=index(rest, closing)
  if (!finish) fail()
  after=substr(rest, finish+length(closing))
  if (index(after, marker)) fail()
  return substr(rest, 1, finish-1)
}
{
  if (!in_latest && index($0, "<div class=\"latest\">")) {
    in_latest=1
    latest_section_count++
    next
  }
  if (!in_latest) next
  if (index($0, "</table>")) {
    latest_table_count++
    in_latest=0
    next
  }
  if (index($0, "<tr>")) {
    if (in_row) fail()
    in_row=1
    row=$0 "\n"
    next
  }
  if (in_row) {
    row=row $0 "\n"
    if (index(row, "</tr>")) {
      rows++
      if (rows != 1) fail()
      record=row
      in_row=0
      row=""
    }
  }
}
END {
  if (invalid || in_row || latest_section_count != 1 || latest_table_count != 1 || rows != 1) exit 1
  date=field(record, "<td class=\"date\">", "</td>")
  if (date !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) exit 1
  url=field(record, "<td class=\047filename\047><a href=\047", "\047>")
  title=field(record, "<td class=\047filename\047><a href=\047" url "\047>", "</a>")
  if (title !~ /^GPGSuite [0-9][0-9][0-9][0-9][.][0-9][0-9]* \([0-9][0-9]*n\)$/) exit 1
  version=title
  sub(/^GPGSuite /, "", version)
  build=version
  sub(/^.* \(/, "", build)
  sub(/\)$/, "", build)
  sub(/ \(.*/, "", version)
  version=version "+" build
  digest=field(record, "<span class=\047tooltiptext\047>", "</span>")
  if (digest !~ /^[0-9A-Fa-f][0-9A-Fa-f]+$/ || length(digest) != 64) exit 1
  if (!index(record, "<span class=\"sha\">SHA256 </span>")) exit 1
  prefix="https://releases.gpgtools.com/nightlies/GPG_Suite-"
  if (index(url, prefix) != 1 || substr(url, length(prefix)+1) !~ /^[0-9][0-9]*n[.]dmg$/) exit 1
  print date "\t" version "\t" url "\t" tolower(digest)
}
'
)

pkg_repository_list_versions()
(
  [ "$#" -eq 1 ] || return 2
  _pkg_repository_gpgtools_validate_repository "$1" || return 1
  pkg_repository_gpgtools_pinned="$(_pkg_repository_gpgtools_scalar "$1/version")" || return 1
  pkg_repository_gpgtools_latest="$(_pkg_repository_gpgtools_latest_release)" || return 1
  pkg_repository_gpgtools_tab="$(printf '\t')"
  IFS="$pkg_repository_gpgtools_tab" read -r \
    pkg_repository_gpgtools_date pkg_repository_gpgtools_version \
    pkg_repository_gpgtools_url pkg_repository_gpgtools_digest \
    pkg_repository_gpgtools_extra <<EOF_GPGTOOLS_LATEST
$pkg_repository_gpgtools_latest
EOF_GPGTOOLS_LATEST
  [ -z "$pkg_repository_gpgtools_extra" ] || return 1
  if [ "$pkg_repository_gpgtools_pinned" = "$pkg_repository_gpgtools_version" ]
  then printf '%s\n' "$pkg_repository_gpgtools_pinned"
  else printf '%s\n%s\n' "$pkg_repository_gpgtools_pinned" "$pkg_repository_gpgtools_version"
  fi
)

pkg_repository_compare_versions()
(
  [ "$#" -eq 3 ] || return 2
  pkg_repository_gpgtools_repository_dir=$1
  pkg_repository_gpgtools_left=$2
  pkg_repository_gpgtools_right=$3
  _pkg_repository_gpgtools_validate_repository "$pkg_repository_gpgtools_repository_dir" || return 1
  _pkg_repository_gpgtools_validate_version "$pkg_repository_gpgtools_left" || return 1
  _pkg_repository_gpgtools_validate_version "$pkg_repository_gpgtools_right" || return 1
  if [ "$pkg_repository_gpgtools_left" = "$pkg_repository_gpgtools_right" ]
  then printf '0\n'; return 0; fi

  pkg_repository_gpgtools_pinned="$(_pkg_repository_gpgtools_scalar "$pkg_repository_gpgtools_repository_dir/version")" || return 1
  case "$pkg_repository_gpgtools_left:$pkg_repository_gpgtools_right" in
    "$pkg_repository_gpgtools_pinned":*|*:"$pkg_repository_gpgtools_pinned") :;;
    *) return 1;;
  esac
  pkg_repository_gpgtools_latest="$(_pkg_repository_gpgtools_latest_release)" || return 1
  pkg_repository_gpgtools_tab="$(printf '\t')"
  IFS="$pkg_repository_gpgtools_tab" read -r \
    pkg_repository_gpgtools_date pkg_repository_gpgtools_latest_version \
    pkg_repository_gpgtools_url pkg_repository_gpgtools_digest \
    pkg_repository_gpgtools_extra <<EOF_GPGTOOLS_COMPARE
$pkg_repository_gpgtools_latest
EOF_GPGTOOLS_COMPARE
  [ -z "$pkg_repository_gpgtools_extra" ] || return 1
  if [ "$pkg_repository_gpgtools_left" = "$pkg_repository_gpgtools_pinned" ] &&
     [ "$pkg_repository_gpgtools_right" = "$pkg_repository_gpgtools_latest_version" ]
  then printf '%s\n' -1; return 0; fi
  if [ "$pkg_repository_gpgtools_left" = "$pkg_repository_gpgtools_latest_version" ] &&
     [ "$pkg_repository_gpgtools_right" = "$pkg_repository_gpgtools_pinned" ]
  then printf '%s\n' 1; return 0; fi
  return 1
)

pkg_repository_resolve_version()
(
  [ "$#" -ge 1 ] && [ "$#" -le 2 ] || return 2
  pkg_repository_gpgtools_repository_dir=$1
  _pkg_repository_gpgtools_validate_repository "$pkg_repository_gpgtools_repository_dir" || return 1
  pkg_repository_gpgtools_pinned="$(_pkg_repository_gpgtools_scalar "$pkg_repository_gpgtools_repository_dir/version")" || return 1
  if [ "$#" -eq 2 ]
  then
    pkg_repository_gpgtools_requested=$2
    _pkg_repository_gpgtools_validate_version "$pkg_repository_gpgtools_requested" || return 1
    if [ "$pkg_repository_gpgtools_requested" = "$pkg_repository_gpgtools_pinned" ]
    then printf '%s\n' "$pkg_repository_gpgtools_requested"; return 0; fi
    pkg_repository_gpgtools_latest="$(_pkg_repository_gpgtools_latest_release)" || return 1
    case "$pkg_repository_gpgtools_latest" in
      *"$(printf '\t')$pkg_repository_gpgtools_requested$(printf '\t')"*) :;;
      *) return 1;;
    esac
    printf '%s\n' "$pkg_repository_gpgtools_requested"
    return 0
  fi

  pkg_repository_gpgtools_latest="$(_pkg_repository_gpgtools_latest_release)" || return 1
  pkg_repository_gpgtools_tab="$(printf '\t')"
  IFS="$pkg_repository_gpgtools_tab" read -r \
    pkg_repository_gpgtools_date pkg_repository_gpgtools_version \
    pkg_repository_gpgtools_url pkg_repository_gpgtools_digest \
    pkg_repository_gpgtools_extra <<EOF_GPGTOOLS_RESOLVE
$pkg_repository_gpgtools_latest
EOF_GPGTOOLS_RESOLVE
  [ -z "$pkg_repository_gpgtools_extra" ] || return 1
  printf '%s\n' "$pkg_repository_gpgtools_version"
)

pkg_repository_resolve_artifact()
(
  [ "$#" -eq 3 ] || return 2
  pkg_repository_gpgtools_repository_dir=$1
  pkg_repository_gpgtools_range_dir=$2
  pkg_repository_gpgtools_requested=$3
  _pkg_repository_gpgtools_validate_repository "$pkg_repository_gpgtools_repository_dir" || return 1
  _pkg_repository_gpgtools_validate_version "$pkg_repository_gpgtools_requested" || return 1
  [ -d "$pkg_repository_gpgtools_range_dir" ] && [ ! -L "$pkg_repository_gpgtools_range_dir" ] || return 1

  pkg_repository_gpgtools_archive_regex="$(_pkg_repository_gpgtools_scalar "$pkg_repository_gpgtools_range_dir/archive_regex")" || return 1
  pkg_repository_gpgtools_digest_type="$(_pkg_repository_gpgtools_scalar "$pkg_repository_gpgtools_range_dir/digest_type")" || return 1
  [ "$pkg_repository_gpgtools_digest_type" = sha256 ] || return 1
  if [ -e "$pkg_repository_gpgtools_range_dir/digest_regex" ] || [ -L "$pkg_repository_gpgtools_range_dir/digest_regex" ]
  then return 1; fi

  pkg_repository_gpgtools_pinned="$(_pkg_repository_gpgtools_scalar "$pkg_repository_gpgtools_repository_dir/version")" || return 1
  if [ "$pkg_repository_gpgtools_requested" = "$pkg_repository_gpgtools_pinned" ]
  then
    pkg_repository_gpgtools_url="$(_pkg_repository_gpgtools_scalar "$pkg_repository_gpgtools_repository_dir/url")" || return 1
    pkg_repository_gpgtools_digest="$(_pkg_repository_gpgtools_scalar "$pkg_repository_gpgtools_repository_dir/digest")" || return 1
  else
    pkg_repository_gpgtools_latest="$(_pkg_repository_gpgtools_latest_release)" || return 1
    pkg_repository_gpgtools_tab="$(printf '\t')"
    IFS="$pkg_repository_gpgtools_tab" read -r \
      pkg_repository_gpgtools_date pkg_repository_gpgtools_latest_version \
      pkg_repository_gpgtools_url pkg_repository_gpgtools_digest \
      pkg_repository_gpgtools_extra <<EOF_GPGTOOLS_ARTIFACT
$pkg_repository_gpgtools_latest
EOF_GPGTOOLS_ARTIFACT
    [ -z "$pkg_repository_gpgtools_extra" ] &&
      [ "$pkg_repository_gpgtools_latest_version" = "$pkg_repository_gpgtools_requested" ] || return 1
  fi
  _pkg_repository_gpgtools_validate_url "$pkg_repository_gpgtools_url" || return 1
  _pkg_repository_gpgtools_validate_digest "$pkg_repository_gpgtools_digest" || return 1

  pkg_repository_gpgtools_name=${pkg_repository_gpgtools_url##*/}
  LC_ALL=C command -p -- awk \
    -v name="$pkg_repository_gpgtools_name" \
    -v expression="$pkg_repository_gpgtools_archive_regex" \
    'BEGIN { exit(name ~ expression ? 0 : 1) }' || return 1
  pkg_repository_gpgtools_size="$(http-fetch -l -- "$pkg_repository_gpgtools_url")" || return 1
  case "$pkg_repository_gpgtools_size" in ''|*[!0-9]*|0[0-9]*) return 1;; esac
  [ "$pkg_repository_gpgtools_size" -gt 0 ] || return 1
  pkg_repository_gpgtools_digest="$(printf '%s\n' "$pkg_repository_gpgtools_digest" | command -p -- tr 'A-F' 'a-f')" || return 1
  printf 'name=%s\nurl=%s\nsize=%s\ndigest=sha256:%s\n' \
    "$pkg_repository_gpgtools_name" \
    "$pkg_repository_gpgtools_url" \
    "$pkg_repository_gpgtools_size" \
    "$pkg_repository_gpgtools_digest"
)
