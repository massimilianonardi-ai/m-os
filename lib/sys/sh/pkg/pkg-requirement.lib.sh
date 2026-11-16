loadsyslib "pkg/pkg-catalog"
loadsyslib "pkg/facility/pkg-facility"
loadsyslib "pkg/facility/pkg-dependency"

_pkg_requirement_cleanup()
{
  [ -z "${pkg_requirement_work-}" ] || command -p -- rm -rf -- "$pkg_requirement_work" 2>/dev/null || :
}

_pkg_requirement_list()
(
  [ "$#" -eq 1 ] || return 2

  pkg_request_read pkg_requirement_pkg pkg_requirement_version pkg_requirement_osarch "$1" || return 2

  umask 077
  pkg_requirement_work=
  trap '_pkg_requirement_cleanup' 0
  trap 'exit 130' HUP INT TERM

  pkg_requirement_tmp_root="$(state-path system sys pkg tmp)" || return 1
  command -p -- mkdir -p -- "$pkg_requirement_tmp_root" || return 1
  [ -d "$pkg_requirement_tmp_root" ] && [ ! -L "$pkg_requirement_tmp_root" ] || return 1

  pkg_requirement_cache_root="$(state-path system sys pkg cache)" || return 1
  command -p -- mkdir -p -- "$pkg_requirement_cache_root" || return 1
  [ -d "$pkg_requirement_cache_root" ] && [ ! -L "$pkg_requirement_cache_root" ] || return 1

  pkg_requirement_work="$pkg_requirement_tmp_root/requirement-$$"
  [ ! -e "$pkg_requirement_work" ] && [ ! -L "$pkg_requirement_work" ] || return 1
  command -p -- mkdir -- "$pkg_requirement_work" || return 1

  pkg_catalog_init pkg_requirement_catalog pkg_requirement_catalog_head "$pkg_requirement_work" "$pkg_requirement_cache_root" || return 1
  pkg_catalog_request_resolve pkg_requirement_concrete pkg_requirement_target "$pkg_requirement_catalog" "$1" "${m_CONTEXT_OSARCH:-$m_OSARCH}" || return 1
  pkg_catalog_range_resolve pkg_requirement_range "$pkg_requirement_catalog" "$pkg_requirement_concrete" || return 1

  pkg_requirement_dependency="$pkg_requirement_range/dependency"
  if [ ! -e "$pkg_requirement_dependency" ] && [ ! -L "$pkg_requirement_dependency" ]
  then
    return 0
  fi

  pkg_dependency_validate "$pkg_requirement_dependency" || return 1
  command -p -- cat -- "$pkg_requirement_dependency"
)

pkg_requirement()
(
  [ "$#" -ge 1 ] || return 2
  pkg_requirement_action=$1
  shift

  case "$pkg_requirement_action" in
    list)
      [ "$#" -eq 1 ] || return 2
      _pkg_requirement_list "$1"
      ;;
    resolve)
      [ "$#" -ge 2 ] || return 2
      pkg_dependency_default_resolve "$@"
      ;;
    *)
      return 2
      ;;
  esac
)
