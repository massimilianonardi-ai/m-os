loadsyslib "json"

_pkg_repository_chrome_for_testing_scalar()
{
  [ "$#" -eq 1 ] || return 2
  pkg_repository_cft_scalar_file=$1
  [ -f "$pkg_repository_cft_scalar_file" ] && [ ! -L "$pkg_repository_cft_scalar_file" ] && [ ! -x "$pkg_repository_cft_scalar_file" ] || return 1
  pkg_repository_cft_scalar_extra=
  {
    IFS= read -r pkg_repository_cft_scalar_value || return 1
    IFS= read -r pkg_repository_cft_scalar_extra
    pkg_repository_cft_scalar_second_status=$?
  } < "$pkg_repository_cft_scalar_file"
  [ "$pkg_repository_cft_scalar_second_status" -ne 0 ] && [ -z "$pkg_repository_cft_scalar_extra" ] && [ -n "$pkg_repository_cft_scalar_value" ] || return 1
  pkg_repository_cft_scalar_cr="$(printf '\r')"
  case "$pkg_repository_cft_scalar_value" in *"$pkg_repository_cft_scalar_cr"*) return 1;; esac
  pkg_repository_cft_scalar_actual="$(command -p -- wc -c < "$pkg_repository_cft_scalar_file")" || return 1
  pkg_repository_cft_scalar_expected="$(printf '%s\n' "$pkg_repository_cft_scalar_value" | command -p -- wc -c)" || return 1
  [ "$pkg_repository_cft_scalar_actual" = "$pkg_repository_cft_scalar_expected" ] || return 1
  printf '%s\n' "$pkg_repository_cft_scalar_value"
}

_pkg_repository_chrome_for_testing_validate_repository()
{
  [ "$#" -eq 1 ] || return 2
  pkg_repository_cft_repository_dir=$1
  [ -d "$pkg_repository_cft_repository_dir" ] && [ ! -L "$pkg_repository_cft_repository_dir" ] || return 1
  for pkg_repository_cft_item in "$pkg_repository_cft_repository_dir"/* "$pkg_repository_cft_repository_dir"/.[!.]* "$pkg_repository_cft_repository_dir"/..?*
  do
    [ -e "$pkg_repository_cft_item" ] || [ -L "$pkg_repository_cft_item" ] || continue
    case "${pkg_repository_cft_item##*/}" in type|channel|platform) :;; *) return 1;; esac
  done
  [ "$(_pkg_repository_chrome_for_testing_scalar "$pkg_repository_cft_repository_dir/type")" = chrome-for-testing ] || return 1
  [ "$(_pkg_repository_chrome_for_testing_scalar "$pkg_repository_cft_repository_dir/channel")" = Stable ] || return 1
  [ "$(_pkg_repository_chrome_for_testing_scalar "$pkg_repository_cft_repository_dir/platform")" = linux-arm64 ] || return 1
}

_pkg_repository_chrome_for_testing_version()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in ''|*[!0-9.]*) return 1;; esac
  LC_ALL=C command -p -- awk -F. 'NF == 4 { for (i=1;i<=4;i++) if ($i !~ /^[0-9]+$/ || (length($i)>1 && substr($i,1,1)=="0")) exit 1; exit 0 } { exit 1 }' <<EOF_VERSION
$1
EOF_VERSION
}

_pkg_repository_chrome_for_testing_md5_hex()
{
  [ "$#" -eq 1 ] || return 2
  LC_ALL=C command -p -- awk -v value="$1" '
function b64(c, p) { p=index(alphabet,c); if (!p) exit 1; return p-1 }
BEGIN {
  alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  if (length(value)!=24 || substr(value,23,2)!="==") exit 1
  for (i=1;i<=22;i++) if (index(alphabet,substr(value,i,1))==0) exit 1
  out=""
  for (i=1;i<=20;i+=4) {
    a=b64(substr(value,i,1)); b=b64(substr(value,i+1,1)); c=b64(substr(value,i+2,1)); d=b64(substr(value,i+3,1))
    out=out sprintf("%02x%02x%02x",a*4+int(b/16),(b%16)*16+int(c/4),(c%4)*64+d)
  }
  a=b64(substr(value,21,1)); b=b64(substr(value,22,1)); if (b%16) exit 1
  out=out sprintf("%02x",a*4+int(b/16)); if(length(out)!=32) exit 1; print out
}'
}

_pkg_repository_chrome_for_testing_metadata()
(
  [ "$#" -eq 2 ] || return 2
  _pkg_repository_chrome_for_testing_validate_repository "$1" || return 1
  pkg_repository_cft_version=$2
  _pkg_repository_chrome_for_testing_version "$pkg_repository_cft_version" || return 1
  pkg_repository_cft_object="$pkg_repository_cft_version/linux-arm64/chrome-linux-arm64.zip"
  pkg_repository_cft_encoded="${pkg_repository_cft_version}%2Flinux-arm64%2Fchrome-linux-arm64.zip"
  pkg_repository_cft_url="https://storage.googleapis.com/storage/v1/b/chrome-for-testing-public/o/$pkg_repository_cft_encoded?fields=name%2Csize%2Cmd5Hash"
  pkg_repository_cft_body="$(http-fetch -- "$pkg_repository_cft_url")" || return 1
  json_object_read name pkg_repository_cft_name size pkg_repository_cft_size md5Hash pkg_repository_cft_md5 <<EOF_JSON
$pkg_repository_cft_body
EOF_JSON
  [ "$?" -eq 0 ] || return 1
  case "$pkg_repository_cft_name" in s:*) pkg_repository_cft_name=${pkg_repository_cft_name#s:};; *) return 1;; esac
  [ "$pkg_repository_cft_name" = "$pkg_repository_cft_object" ] || return 1
  case "$pkg_repository_cft_size" in s:*) pkg_repository_cft_size=${pkg_repository_cft_size#s:};; *) return 1;; esac
  case "$pkg_repository_cft_size" in ''|0|0[0-9]*|*[!0-9]*) return 1;; esac
  case "$pkg_repository_cft_md5" in s:*) pkg_repository_cft_md5=${pkg_repository_cft_md5#s:};; *) return 1;; esac
  pkg_repository_cft_md5_hex="$(_pkg_repository_chrome_for_testing_md5_hex "$pkg_repository_cft_md5")" || return 1
  printf '%s\t%s\t%s\n' chrome-linux-arm64.zip "$pkg_repository_cft_size" "$pkg_repository_cft_md5_hex"
)

_pkg_repository_chrome_for_testing_latest()
(
  [ "$#" -eq 1 ] || return 2
  _pkg_repository_chrome_for_testing_validate_repository "$1" || return 1
  pkg_repository_cft_latest="$(http-fetch -- 'https://googlechromelabs.github.io/chrome-for-testing/LATEST_RELEASE_STABLE')" || return 1
  _pkg_repository_chrome_for_testing_version "$pkg_repository_cft_latest" || return 1
  _pkg_repository_chrome_for_testing_metadata "$1" "$pkg_repository_cft_latest" >/dev/null || return 1
  printf '%s\n' "$pkg_repository_cft_latest"
)

pkg_repository_compare_versions()
(
  [ "$#" -eq 3 ] || return 2
  _pkg_repository_chrome_for_testing_validate_repository "$1" || return 1
  _pkg_repository_chrome_for_testing_version "$2" && _pkg_repository_chrome_for_testing_version "$3" || return 1
  LC_ALL=C command -p -- awk -F. -v left="$2" -v right="$3" 'BEGIN {
    split(left,a); split(right,b)
    for(i=1;i<=4;i++) {
      sub(/^0+/,"",a[i]); sub(/^0+/,"",b[i]); if(a[i]=="")a[i]="0"; if(b[i]=="")b[i]="0"
      if(length(a[i])<length(b[i])) {print "-1"; exit}
      if(length(a[i])>length(b[i])) {print "1"; exit}
      if(("x" a[i])<("x" b[i])) {print "-1"; exit}
      if(("x" a[i])>("x" b[i])) {print "1"; exit}
    }
    print "0"
  }'
)

pkg_repository_resolve_version()
(
  [ "$#" -ge 1 ] && [ "$#" -le 2 ] || return 2
  _pkg_repository_chrome_for_testing_validate_repository "$1" || return 1
  if [ "$#" -eq 1 ]; then _pkg_repository_chrome_for_testing_latest "$1"; return $?; fi
  _pkg_repository_chrome_for_testing_metadata "$1" "$2" >/dev/null || return 1
  printf '%s\n' "$2"
)

pkg_repository_resolve_artifact()
(
  [ "$#" -eq 3 ] || return 2
  _pkg_repository_chrome_for_testing_validate_repository "$1" || return 1
  pkg_repository_cft_range=$2
  [ -d "$pkg_repository_cft_range" ] && [ ! -L "$pkg_repository_cft_range" ] || return 1
  [ "$(_pkg_repository_chrome_for_testing_scalar "$pkg_repository_cft_range/digest_type")" = md5 ] || return 1
  [ ! -e "$pkg_repository_cft_range/digest_regex" ] && [ ! -L "$pkg_repository_cft_range/digest_regex" ] || return 1
  pkg_repository_cft_regex="$(_pkg_repository_chrome_for_testing_scalar "$pkg_repository_cft_range/archive_regex")" || return 1
  LC_ALL=C command -p -- awk -v v=chrome-linux-arm64.zip -v r="$pkg_repository_cft_regex" 'BEGIN {exit !(v ~ r)}' || return 1
  pkg_repository_cft_record="$(_pkg_repository_chrome_for_testing_metadata "$1" "$3")" || return 1
  IFS="$(printf '\t')" read -r pkg_repository_cft_name pkg_repository_cft_size pkg_repository_cft_md5 <<EOF_RECORD
$pkg_repository_cft_record
EOF_RECORD
  printf 'name=%s\nurl=https://storage.googleapis.com/chrome-for-testing-public/%s/linux-arm64/%s\nsize=%s\ndigest=md5:%s\n' \
    "$pkg_repository_cft_name" "$3" "$pkg_repository_cft_name" "$pkg_repository_cft_size" "$pkg_repository_cft_md5"
)
