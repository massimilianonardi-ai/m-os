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

_pkg_v2_root_target_validate()
{
  [ "$#" -ge 2 ] && [ "$#" -le 4 ] || return 2
  pkg_v2_root_target=$1
  pkg_v2_useful_root=$2
  pkg_v2_root_prefix=${3-../../root/}
  pkg_v2_target_mode=${4-executable}
  case "$pkg_v2_root_prefix" in
    ../../root/ | ../../../root/) : ;;
    *) return 2 ;;
  esac

  case "$pkg_v2_root_target" in
    "$pkg_v2_root_prefix"*) pkg_v2_relative=${pkg_v2_root_target#"$pkg_v2_root_prefix"} ;;
    *) return 1 ;;
  esac
  case "$pkg_v2_relative" in
    "" | /* | */ | *//*) return 1 ;;
  esac
  case "/$pkg_v2_relative/" in
    */./* | */../*) return 1 ;;
  esac
  readpathce pkg_v2_resolved "$pkg_v2_useful_root/$pkg_v2_relative" || return 1
  case "$pkg_v2_resolved" in
    "$pkg_v2_useful_root"/*) : ;;
    *) return 1 ;;
  esac
  [ -f "$pkg_v2_resolved" ] || return 1
  case "$pkg_v2_target_mode" in
    executable) [ -x "$pkg_v2_resolved" ] ;;
    readable) [ -r "$pkg_v2_resolved" ] ;;
    *) return 2 ;;
  esac
}


# Validate the already-materialized v2 command view before a new selection.
# Direct entries must stay inside root/; wrappers must be executable in cmd/.
# This cannot guard a PATH symlink against later filesystem mutation.
_pkg_v2_installed_command_validate()
{
  [ "$#" -eq 2 ] || return 2
  pkg_v2_installed_concrete=$1
  pkg_v2_installed_name=$2
  pkg_name_valid "$pkg_v2_installed_name" || return 1
  [ -d "$pkg_v2_installed_concrete" ] && [ ! -L "$pkg_v2_installed_concrete" ] || return 1
  [ -d "$pkg_v2_installed_concrete/root" ] &&
    [ ! -L "$pkg_v2_installed_concrete/root" ] || return 1
  [ -d "$pkg_v2_installed_concrete/link/bin" ] &&
    [ ! -L "$pkg_v2_installed_concrete/link/bin" ] || return 1

  pkg_v2_installed_link="$pkg_v2_installed_concrete/link/bin/$pkg_v2_installed_name"
  [ -L "$pkg_v2_installed_link" ] || return 1
  pkg_v2_installed_target="$(command -p -- readlink "$pkg_v2_installed_link")" || return 1

  case "$pkg_v2_installed_target" in
    "../../cmd/$pkg_v2_installed_name")
      [ -d "$pkg_v2_installed_concrete/cmd" ] &&
        [ ! -L "$pkg_v2_installed_concrete/cmd" ] || return 1
      [ -f "$pkg_v2_installed_concrete/cmd/$pkg_v2_installed_name" ] &&
        [ ! -L "$pkg_v2_installed_concrete/cmd/$pkg_v2_installed_name" ] &&
        [ -x "$pkg_v2_installed_concrete/cmd/$pkg_v2_installed_name" ] || return 1
      ;;
    ../../root/*)
      _pkg_v2_root_target_validate "$pkg_v2_installed_target" "$pkg_v2_installed_concrete/root" || return 1
      ;;
    *)
      return 1
      ;;
  esac
}
