pkg_name_valid()
{
  [ "$#" -eq 1 ] || return 1
  case "$1" in
    "" | [!abcdefghijklmnopqrstuvwxyz0123456789]* | *[!abcdefghijklmnopqrstuvwxyz0123456789._-]* | *[._-]) return 2 ;;
  esac
}

pkg_version_valid()
{
  [ "$#" -eq 1 ] || return 1
  case "$1" in
    "" | [!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789]* | *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._+~-]*) return 2 ;;
  esac
}

pkg_osarch_valid()
{
  [ "$#" -eq 1 ] || return 1
  case "$1" in
    linux-arm64 | linux-x86_64 | macos-arm64 | macos-x86_64 | windows-arm64 | windows-x86_64) return 0 ;;
    *) return 2 ;;
  esac
}

pkg_name_version_osarch_valid()
{
  [ "$#" -ge 2 ] || return 1

  pkg_name_valid "$1" || return 2
  pkg_version_valid "$2" || return 3
  if [ -n "$3" ]
  then
    pkg_osarch_valid "$3" || return 4
  fi
}

_pkg_spec_read()
{
  [ "$#" -eq 5 ] || return 2

  pkg_spec_kind=$1
  shift

  valid_shell_identifier "$1" "$2" "$3" || return 2
  [ "$1" != "$2" ] && [ "$1" != "$3" ] && [ "$2" != "$3" ] || return 2

  pkg_spec=$4
  pkg_spec_left=$pkg_spec
  pkg_spec_osarch=
  pkg_spec_version=

  case "$pkg_spec_left" in
    *!*)
      pkg_spec_osarch=${pkg_spec_left##*!}
      pkg_spec_left=${pkg_spec_left%!"$pkg_spec_osarch"}
      case "$pkg_spec_left" in *!*) return 1 ;; esac
      pkg_osarch_valid "$pkg_spec_osarch" || return 1
      ;;
  esac

  case "$pkg_spec_left" in
    *@*)
      pkg_spec_version=${pkg_spec_left##*@}
      pkg_spec_name=${pkg_spec_left%@"$pkg_spec_version"}
      case "$pkg_spec_name" in *@*) return 1 ;; esac
      pkg_version_valid "$pkg_spec_version" || return 1
      ;;
    *)
      [ "$pkg_spec_kind" = request ] || return 1
      pkg_spec_name=$pkg_spec_left
      ;;
  esac

  pkg_name_valid "$pkg_spec_name" || return 1

  IFS='|' read -r "$1" "$2" "$3" <<EOF_PKG_SPEC
$pkg_spec_name|$pkg_spec_version|$pkg_spec_osarch
EOF_PKG_SPEC
}

pkg_request_read()
{
  [ "$#" -eq 4 ] || return 1
  _pkg_spec_read request "$@"
}

pkg_concrete_read()
{
  [ "$#" -eq 4 ] || return 1
  _pkg_spec_read concrete "$@"
}

# An absent marker is the existing v1 installed-concrete layout.
# A v2 marker is data created and owned by the package integrator.
_pkg_schema_read()
{
  [ "$#" -eq 1 ] || return 2
  pkg_schema=v1
  pkg_schema_marker="$1/schema"

  if [ -e "$pkg_schema_marker" ] || [ -L "$pkg_schema_marker" ]
  then
    [ -f "$pkg_schema_marker" ] && [ ! -L "$pkg_schema_marker" ] &&
      [ -r "$pkg_schema_marker" ] && [ ! -x "$pkg_schema_marker" ] || return 1
    [ "$(command -p -- cat -- "$pkg_schema_marker")" = v2 ] || return 1
    pkg_schema_size="$(command -p -- wc -c < "$pkg_schema_marker")" || return 1
    [ "$pkg_schema_size" -eq 3 ] || return 1
    pkg_schema=v2
  fi
}
