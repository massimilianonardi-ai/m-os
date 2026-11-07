loadsyslib "pkg/pkg-common"

_pkg_provider_name_valid()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in
    "" | [!abcdefghijklmnopqrstuvwxyz0123456789]* | *[!abcdefghijklmnopqrstuvwxyz0123456789._-]* | *[._-]) return 1 ;;
  esac
}

_pkg_provider_facility_valid()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in
    "" | [!abcdefghijklmnopqrstuvwxyz]* | *[!abcdefghijklmnopqrstuvwxyz0123456789-]*) return 1 ;;
  esac
}

_pkg_provider_version_valid()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in
    "" | [!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789]* | *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._+~-]*) return 1 ;;
  esac
}

_pkg_provider_osarch_valid()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in
    linux-arm64 | linux-x86_64 | macos-arm64 | macos-x86_64 | windows-arm64 | windows-x86_64) return 0 ;;
    *) return 1 ;;
  esac
}

_pkg_provider_selector_validate()
{
  [ "$#" -eq 1 ] || return 2
  pkg_provider_selector=$1
  pkg_provider_selector_left=$pkg_provider_selector
  pkg_provider_selector_osarch=
  pkg_provider_selector_version=

  case "$pkg_provider_selector_left" in
    *!*)
      pkg_provider_selector_osarch=${pkg_provider_selector_left##*!}
      pkg_provider_selector_left=${pkg_provider_selector_left%!"$pkg_provider_selector_osarch"}
      case "$pkg_provider_selector_left" in *!*) return 1 ;; esac
      _pkg_provider_osarch_valid "$pkg_provider_selector_osarch" || return 1
      ;;
  esac

  case "$pkg_provider_selector_left" in
    *@*)
      pkg_provider_selector_version=${pkg_provider_selector_left##*@}
      pkg_provider_selector_pkg=${pkg_provider_selector_left%@"$pkg_provider_selector_version"}
      case "$pkg_provider_selector_pkg" in *@*) return 1 ;; esac
      _pkg_provider_version_valid "$pkg_provider_selector_version" || return 1
      ;;
    *)
      pkg_provider_selector_pkg=$pkg_provider_selector_left
      ;;
  esac

  _pkg_provider_name_valid "$pkg_provider_selector_pkg"
}

_pkg_provider_scalar_read()
{
  [ "$#" -eq 1 ] || return 2
  [ -f "$1" ] && [ ! -L "$1" ] && [ -r "$1" ] && [ ! -x "$1" ] || return 1

  pkg_provider_scalar=
  pkg_provider_scalar_extra=
  {
    IFS= read -r pkg_provider_scalar || return 1
    IFS= read -r pkg_provider_scalar_extra
    pkg_provider_scalar_second_status=$?
  } < "$1"

  [ "$pkg_provider_scalar_second_status" -ne 0 ] || return 1
  [ -z "$pkg_provider_scalar_extra" ] || return 1
  [ -n "$pkg_provider_scalar" ] || return 1

  pkg_provider_scalar_actual="$(command -p -- wc -c < "$1")" || return 1
  pkg_provider_scalar_expected="$(printf -- '%s\n' "$pkg_provider_scalar" | command -p -- wc -c)" || return 1
  [ "$pkg_provider_scalar_actual" = "$pkg_provider_scalar_expected" ] || return 1
}

_pkg_provider_facility_map_reconcile()
{
  [ "$#" -eq 0 ] || return 2
  loadsyslib "pkg/facility/pkg-facility-map" || return 1
  pkg_facility_map_reconcile
}

_pkg_provider_system_conf()
{
  [ "$#" -eq 0 ] || return 2
  pkg_provider_system_conf="$(command -- state-path system sys pkg conf)" || return 1
  [ -n "$pkg_provider_system_conf" ]
}

_pkg_provider_default_file()
{
  [ "$#" -eq 1 ] || return 2
  _pkg_provider_facility_valid "$1" || return 2
  _pkg_provider_system_conf || return 1
  pkg_provider_config_file="$pkg_provider_system_conf/provider/default/$1"
}

_pkg_provider_binding_file()
{
  [ "$#" -eq 2 ] || return 2
  _pkg_provider_name_valid "$1" || return 2
  _pkg_provider_facility_valid "$2" || return 2
  pkg_provider_consumer_conf="$(command -- state-path system pkg "$1" conf)" || return 1
  [ -n "$pkg_provider_consumer_conf" ] || return 1
  pkg_provider_config_file="$pkg_provider_consumer_conf/binding/$2"
}

_pkg_provider_config_query()
{
  [ "$#" -eq 1 ] || return 2
  _pkg_provider_scalar_read "$1" || return 1
  _pkg_provider_selector_validate "$pkg_provider_scalar" || return 1
  printf -- '%s\n' "$pkg_provider_scalar"
}

_pkg_provider_config_set()
{
  [ "$#" -eq 2 ] || [ "$#" -eq 3 ] || return 2
  pkg_provider_config_path=$1
  pkg_provider_config_selector=$2
  pkg_provider_config_mode=${3-600}
  _pkg_provider_selector_validate "$pkg_provider_config_selector" || return 2
  case "$pkg_provider_config_mode" in
    600 | 644) : ;;
    *) return 2 ;;
  esac

  pkg_provider_config_dir=${pkg_provider_config_path%/*}
  [ "$pkg_provider_config_dir" != "$pkg_provider_config_path" ] || return 1

  umask 077
  command -p -- mkdir -p -- "$pkg_provider_config_dir" || return 1
  [ -d "$pkg_provider_config_dir" ] && [ ! -L "$pkg_provider_config_dir" ] || return 1

  if [ -e "$pkg_provider_config_path" ] || [ -L "$pkg_provider_config_path" ]
  then
    [ -f "$pkg_provider_config_path" ] && [ ! -L "$pkg_provider_config_path" ] || return 1
  fi

  pkg_provider_config_tmp="$pkg_provider_config_dir/.selector-$$"
  [ ! -e "$pkg_provider_config_tmp" ] && [ ! -L "$pkg_provider_config_tmp" ] || return 1
  if ! printf -- '%s\n' "$pkg_provider_config_selector" > "$pkg_provider_config_tmp"
  then
    command -p -- rm -f -- "$pkg_provider_config_tmp" 2>/dev/null
    return 1
  fi
  if ! command -p -- chmod "$pkg_provider_config_mode" "$pkg_provider_config_tmp"
  then
    command -p -- rm -f -- "$pkg_provider_config_tmp" 2>/dev/null
    return 1
  fi
  if ! command -p -- mv -f -- "$pkg_provider_config_tmp" "$pkg_provider_config_path"
  then
    command -p -- rm -f -- "$pkg_provider_config_tmp" 2>/dev/null
    return 1
  fi
  _pkg_provider_scalar_read "$pkg_provider_config_path" || return 1
  [ "$pkg_provider_scalar" = "$pkg_provider_config_selector" ]
}

_pkg_provider_default_parent_access_prepare()
{
  [ "$#" -eq 0 ] || return 2
  _pkg_provider_system_conf || return 1
  pkg_provider_default_access_provider="$pkg_provider_system_conf/provider"
  pkg_provider_default_access_root="$pkg_provider_default_access_provider/default"

  umask 077
  command -p -- mkdir -p -- "$pkg_provider_default_access_root" || return 1

  for pkg_provider_default_access_dir in \
    "$m_STATE_SYS_DIR/sys" \
    "$m_STATE_SYS_DIR/sys/pkg" \
    "$pkg_provider_system_conf" \
    "$pkg_provider_default_access_provider" \
    "$pkg_provider_default_access_root"
  do
    [ -d "$pkg_provider_default_access_dir" ] && [ ! -L "$pkg_provider_default_access_dir" ] || return 1
    command -p -- chmod 711 "$pkg_provider_default_access_dir" || return 1
  done
}

pkg_provider_default_runtime_access_prepare()
{
  [ "$#" -eq 1 ] || return 2
  _pkg_provider_default_file "$1" || return $?
  pkg_provider_default_runtime_file=$pkg_provider_config_file

  [ -f "$pkg_provider_default_runtime_file" ] && \
  [ ! -L "$pkg_provider_default_runtime_file" ] || return 1

  _pkg_provider_default_parent_access_prepare || return 1
  command -p -- chmod 644 "$pkg_provider_default_runtime_file"
}

pkg_provider_global_runtime_access_prepare()
{
  [ "$#" -eq 0 ] || return 2
  _pkg_provider_default_parent_access_prepare || return 1

  command -p -- chmod 755 "$pkg_provider_default_access_root" || return 1

  for pkg_provider_global_runtime_file in \
    "$pkg_provider_default_access_root"/* \
    "$pkg_provider_default_access_root"/.[!.]* \
    "$pkg_provider_default_access_root"/..?*
  do
    [ -e "$pkg_provider_global_runtime_file" ] || [ -L "$pkg_provider_global_runtime_file" ] || continue
    [ -f "$pkg_provider_global_runtime_file" ] && [ ! -L "$pkg_provider_global_runtime_file" ] || return 1
    _pkg_provider_config_query "$pkg_provider_global_runtime_file" >/dev/null || return 1
    command -p -- chmod 644 "$pkg_provider_global_runtime_file" || return 1
  done
}

_pkg_provider_binding_parent_access_prepare()
{
  [ "$#" -eq 1 ] || return 2
  _pkg_provider_name_valid "$1" || return 2

  pkg_provider_binding_access_conf="$(command -- state-path system pkg "$1" conf)" || return 1
  pkg_provider_binding_access_identity=${pkg_provider_binding_access_conf%/conf}
  pkg_provider_binding_access_pkg_root=${pkg_provider_binding_access_identity%/*}
  pkg_provider_binding_access_root="$pkg_provider_binding_access_conf/binding"

  umask 077
  command -p -- mkdir -p -- "$pkg_provider_binding_access_root" || return 1

  for pkg_provider_binding_access_dir in \
    "$pkg_provider_binding_access_pkg_root" \
    "$pkg_provider_binding_access_identity" \
    "$pkg_provider_binding_access_conf" \
    "$pkg_provider_binding_access_root"
  do
    [ -d "$pkg_provider_binding_access_dir" ] && [ ! -L "$pkg_provider_binding_access_dir" ] || return 1
    command -p -- chmod 711 "$pkg_provider_binding_access_dir" || return 1
  done
}

pkg_provider_effective_selector_runtime_access_prepare()
{
  [ "$#" -eq 2 ] || return 2
  _pkg_provider_binding_file "$1" "$2" || return $?
  pkg_provider_runtime_binding=$pkg_provider_config_file

  if [ -e "$pkg_provider_runtime_binding" ] || [ -L "$pkg_provider_runtime_binding" ]
  then
    [ -f "$pkg_provider_runtime_binding" ] && [ ! -L "$pkg_provider_runtime_binding" ] || return 1
    _pkg_provider_config_query "$pkg_provider_runtime_binding" >/dev/null || return 1
    _pkg_provider_binding_parent_access_prepare "$1" || return 1
    command -p -- chmod 644 "$pkg_provider_runtime_binding"
    return $?
  fi

  _pkg_provider_default_file "$2" || return $?
  if [ ! -e "$pkg_provider_config_file" ] && [ ! -L "$pkg_provider_config_file" ]
  then
    return 0
  fi

  pkg_provider_default_runtime_access_prepare "$2"
}

_pkg_provider_config_unset()
{
  [ "$#" -eq 1 ] || return 2

  if [ ! -e "$1" ] && [ ! -L "$1" ]
  then
    return 0
  fi

  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  command -p -- rm -f -- "$1"
}

_pkg_provider_default()
{
  pkg_provider_unset=0

  case "${1-}" in
    -u)
      pkg_provider_unset=1
      shift
      ;;
    --)
      shift
      ;;
    -*)
      return 2
      ;;
  esac

  if [ "$pkg_provider_unset" -eq 1 ] && [ "${1-}" = -- ]
  then
    shift
  fi

  if [ "$pkg_provider_unset" -eq 1 ]
  then
    [ "$#" -eq 1 ] || return 2
    _pkg_provider_default_file "$1" || return $?

    pkg_provider_old_selector=
    if [ -e "$pkg_provider_config_file" ] || [ -L "$pkg_provider_config_file" ]
    then
      _pkg_provider_scalar_read "$pkg_provider_config_file" || return 1
      _pkg_provider_selector_validate "$pkg_provider_scalar" || return 1
      pkg_provider_old_selector=$pkg_provider_scalar
    fi

    _pkg_provider_global_reconcile "$1" "$pkg_provider_old_selector" "" || return 1
    if ! _pkg_provider_config_unset "$pkg_provider_config_file"
    then
      _pkg_provider_global_reconcile "$1" "" "$pkg_provider_old_selector" >/dev/null 2>&1 || :
      return 1
    fi
    if ! pkg_provider_global_environment_materialize
    then
      if [ -n "$pkg_provider_old_selector" ]
      then
        _pkg_provider_config_set "$pkg_provider_config_file" "$pkg_provider_old_selector" >/dev/null 2>&1 || :
      fi
      _pkg_provider_global_reconcile "$1" "" "$pkg_provider_old_selector" >/dev/null 2>&1 || :
      return 1
    fi
    _pkg_provider_facility_map_reconcile || log warn execution facility-map-reconcile-failed operation pkg-provider-default || :
    return 0
  fi

  [ "$#" -eq 1 ] || [ "$#" -eq 2 ] || return 2
  _pkg_provider_default_file "$1" || return $?

  if [ "$#" -eq 1 ]
  then
    _pkg_provider_config_query "$pkg_provider_config_file"
    return $?
  fi

  _pkg_provider_selector_validate "$2" || return 2
  pkg_provider_new_selector=$2
  pkg_provider_old_selector=
  if [ -e "$pkg_provider_config_file" ] || [ -L "$pkg_provider_config_file" ]
  then
    _pkg_provider_scalar_read "$pkg_provider_config_file" || return 1
    _pkg_provider_selector_validate "$pkg_provider_scalar" || return 1
    pkg_provider_old_selector=$pkg_provider_scalar
  fi

  _pkg_provider_global_reconcile "$1" "$pkg_provider_old_selector" "$pkg_provider_new_selector" || return 1
  if ! _pkg_provider_config_set "$pkg_provider_config_file" "$pkg_provider_new_selector"
  then
    _pkg_provider_global_reconcile "$1" "$pkg_provider_new_selector" "$pkg_provider_old_selector" >/dev/null 2>&1 || :
    return 1
  fi
  if ! pkg_provider_global_environment_materialize
  then
    if [ -n "$pkg_provider_old_selector" ]
    then
      _pkg_provider_config_set "$pkg_provider_config_file" "$pkg_provider_old_selector" >/dev/null 2>&1 || :
    else
      _pkg_provider_config_unset "$pkg_provider_config_file" >/dev/null 2>&1 || :
    fi
    _pkg_provider_global_reconcile "$1" "$pkg_provider_new_selector" "$pkg_provider_old_selector" >/dev/null 2>&1 || :
    return 1
  fi
  _pkg_provider_facility_map_reconcile || log warn execution facility-map-reconcile-failed operation pkg-provider-default || :
  return 0
}

_pkg_provider_bind()
{
  pkg_provider_unset=0

  case "${1-}" in
    -u)
      pkg_provider_unset=1
      shift
      ;;
    --)
      shift
      ;;
    -*)
      return 2
      ;;
  esac

  if [ "$pkg_provider_unset" -eq 1 ] && [ "${1-}" = -- ]
  then
    shift
  fi

  if [ "$pkg_provider_unset" -eq 1 ]
  then
    [ "$#" -eq 2 ] || return 2
    _pkg_provider_binding_file "$1" "$2" || return $?
    _pkg_provider_config_unset "$pkg_provider_config_file"
    return $?
  fi

  [ "$#" -eq 2 ] || [ "$#" -eq 3 ] || return 2
  _pkg_provider_binding_file "$1" "$2" || return $?

  if [ "$#" -eq 2 ]
  then
    _pkg_provider_config_query "$pkg_provider_config_file"
  else
    _pkg_provider_selector_validate "$3" || return 2
    _pkg_provider_config_set "$pkg_provider_config_file" "$3"
  fi
}


_pkg_provider_concrete_parse()
{
  [ "$#" -eq 1 ] || return 2
  pkg_provider_concrete=$1
  pkg_concrete_read pkg_provider_concrete_pkg pkg_provider_concrete_version pkg_provider_concrete_osarch "$pkg_provider_concrete"
}

_pkg_provider_resolved_validate()
{
  [ "$#" -eq 4 ] || return 2
  pkg_provider_resolved_name=$1
  pkg_provider_expected_pkg=$2
  pkg_provider_expected_version=$3
  pkg_provider_consumer_osarch=$4

  _pkg_provider_concrete_parse "$pkg_provider_resolved_name" || return 1
  [ "$pkg_provider_concrete_pkg" = "$pkg_provider_expected_pkg" ] || return 1
  if [ -n "$pkg_provider_expected_version" ]
  then
    [ "$pkg_provider_concrete_version" = "$pkg_provider_expected_version" ] || return 1
  fi

  if [ -n "$pkg_provider_consumer_osarch" ]
  then
    [ -z "$pkg_provider_concrete_osarch" ] || [ "$pkg_provider_concrete_osarch" = "$pkg_provider_consumer_osarch" ] || return 1
  else
    [ -z "$pkg_provider_concrete_osarch" ] || return 1
  fi

  [ -d "$m_PKG_DIR/$pkg_provider_resolved_name" ] && [ ! -L "$m_PKG_DIR/$pkg_provider_resolved_name" ]
}

_pkg_provider_selector_current()
{
  [ "$#" -eq 3 ] || return 2
  pkg_provider_current_pkg=$1
  pkg_provider_current_osarch=$2
  pkg_provider_allow_generic=$3
  pkg_provider_current_name=

  if [ -n "$pkg_provider_current_osarch" ]
  then
    pkg_provider_current_path="$m_PKG_DIR/$pkg_provider_current_pkg!$pkg_provider_current_osarch"
    if [ -L "$pkg_provider_current_path" ]
    then
      pkg_provider_current_name="$(command -p -- readlink "$pkg_provider_current_path")" || return 1
    elif [ -e "$pkg_provider_current_path" ]
    then
      return 1
    elif [ "$pkg_provider_allow_generic" -eq 1 ]
    then
      pkg_provider_current_path="$m_PKG_DIR/$pkg_provider_current_pkg"
      [ -L "$pkg_provider_current_path" ] || {
        [ ! -e "$pkg_provider_current_path" ] || return 1
        return 1
      }
      pkg_provider_current_name="$(command -p -- readlink "$pkg_provider_current_path")" || return 1
    else
      return 1
    fi
  else
    pkg_provider_current_path="$m_PKG_DIR/$pkg_provider_current_pkg"
    [ -L "$pkg_provider_current_path" ] || {
      [ ! -e "$pkg_provider_current_path" ] || return 1
      return 1
    }
    pkg_provider_current_name="$(command -p -- readlink "$pkg_provider_current_path")" || return 1
  fi

  case "$pkg_provider_current_name" in "" | */*) return 1 ;; esac
}

pkg_provider_selector_resolve()
(
  [ "$#" -eq 1 ] || [ "$#" -eq 2 ] || return 2
  pkg_provider_resolve_selector=$1
  pkg_provider_resolve_consumer_osarch=${2-}

  if [ -n "$pkg_provider_resolve_consumer_osarch" ]
  then
    _pkg_provider_osarch_valid "$pkg_provider_resolve_consumer_osarch" || return 2
  fi

  _pkg_provider_selector_validate "$pkg_provider_resolve_selector" || return 2
  pkg_provider_resolve_pkg=$pkg_provider_selector_pkg
  pkg_provider_resolve_version=$pkg_provider_selector_version
  pkg_provider_resolve_selector_osarch=$pkg_provider_selector_osarch

  if [ -n "$pkg_provider_resolve_selector_osarch" ]
  then
    [ -n "$pkg_provider_resolve_consumer_osarch" ] || return 1
    [ "$pkg_provider_resolve_selector_osarch" = "$pkg_provider_resolve_consumer_osarch" ] || return 1
    pkg_provider_resolve_osarch=$pkg_provider_resolve_selector_osarch
    pkg_provider_resolve_allow_generic=0
  else
    pkg_provider_resolve_osarch=$pkg_provider_resolve_consumer_osarch
    pkg_provider_resolve_allow_generic=1
  fi

  if [ -n "$pkg_provider_resolve_version" ]
  then
    if [ -n "$pkg_provider_resolve_osarch" ]
    then
      pkg_provider_resolved="$pkg_provider_resolve_pkg@$pkg_provider_resolve_version!$pkg_provider_resolve_osarch"
      if [ ! -d "$m_PKG_DIR/$pkg_provider_resolved" ] || [ -L "$m_PKG_DIR/$pkg_provider_resolved" ]
      then
        [ "$pkg_provider_resolve_allow_generic" -eq 1 ] || return 1
        pkg_provider_resolved="$pkg_provider_resolve_pkg@$pkg_provider_resolve_version"
      fi
    else
      pkg_provider_resolved="$pkg_provider_resolve_pkg@$pkg_provider_resolve_version"
    fi
  else
    _pkg_provider_selector_current "$pkg_provider_resolve_pkg" "$pkg_provider_resolve_osarch" "$pkg_provider_resolve_allow_generic" || return 1
    pkg_provider_resolved=$pkg_provider_current_name
  fi

  _pkg_provider_resolved_validate "$pkg_provider_resolved" "$pkg_provider_resolve_pkg" "$pkg_provider_resolve_version" "$pkg_provider_resolve_consumer_osarch" || return 1
  printf -- '%s\n' "$pkg_provider_resolved"
)

pkg_provider_effective_selector()
(
  [ "$#" -eq 2 ] || return 2
  pkg_provider_effective_consumer=$1
  pkg_provider_effective_facility=$2

  _pkg_provider_binding_file "$pkg_provider_effective_consumer" "$pkg_provider_effective_facility" || return $?
  pkg_provider_effective_binding=$pkg_provider_config_file

  if [ -e "$pkg_provider_effective_binding" ] || [ -L "$pkg_provider_effective_binding" ]
  then
    [ -f "$pkg_provider_effective_binding" ] && [ ! -L "$pkg_provider_effective_binding" ] || return 3
    _pkg_provider_config_query "$pkg_provider_effective_binding" || return 3
    return 0
  fi

  _pkg_provider_default_file "$pkg_provider_effective_facility" || return $?
  if [ ! -e "$pkg_provider_config_file" ] && [ ! -L "$pkg_provider_config_file" ]
  then
    return 1
  fi
  [ -f "$pkg_provider_config_file" ] && [ ! -L "$pkg_provider_config_file" ] || return 3
  _pkg_provider_config_query "$pkg_provider_config_file" || return 3
)



_pkg_provider_environment_name_valid()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in
    "" | [!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_]* | *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_]*) return 1 ;;
    m_GLOBAL_ENV_GENERATION) return 1 ;;
  esac
}

_pkg_provider_environment_relative_path_valid()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in
    "" | /* | */ | *//* | *'
'*) return 1 ;;
  esac
  case "/$1/" in
    */./* | */../*) return 1 ;;
  esac
}

_pkg_provider_environment_plan()
(
  [ "$#" -eq 2 ] || return 2
  pkg_provider_environment_facility=$1
  pkg_provider_environment_name=$2

  _pkg_provider_facility_valid "$pkg_provider_environment_facility" || return 2
  _pkg_provider_concrete_parse "$pkg_provider_environment_name" || return 2

  pkg_provider_environment_concrete="$m_PKG_DIR/$pkg_provider_environment_name"
  pkg_provider_environment_root="$pkg_provider_environment_concrete/root"
  [ -d "$pkg_provider_environment_concrete" ] && [ ! -L "$pkg_provider_environment_concrete" ] || return 1
  [ -d "$pkg_provider_environment_root" ] && [ ! -L "$pkg_provider_environment_root" ] || return 1
  readpathce pkg_provider_environment_root "$pkg_provider_environment_root" || return 1

  pkg_provider_environment_file="$pkg_provider_environment_concrete/facility-env/$pkg_provider_environment_facility"
  if [ ! -e "$pkg_provider_environment_file" ] && [ ! -L "$pkg_provider_environment_file" ]
  then
    return 0
  fi

  [ -f "$pkg_provider_environment_file" ] && [ ! -L "$pkg_provider_environment_file" ] && [ -r "$pkg_provider_environment_file" ] && [ ! -x "$pkg_provider_environment_file" ] || return 1

  pkg_provider_environment_original="$(
    command -p -- cat -- "$pkg_provider_environment_file" || exit 1
    printf -- '%s' x
  )" || return 1
  pkg_provider_environment_sorted="$(
    LC_ALL=C command -p -- sort < "$pkg_provider_environment_file" || exit 1
    printf -- '%s' x
  )" || return 1
  [ "$pkg_provider_environment_original" = "$pkg_provider_environment_sorted" ] || return 1

  pkg_provider_environment_tab="$(printf '\t')"
  pkg_provider_environment_previous=
  pkg_provider_environment_count=0

  while IFS= read -r pkg_provider_environment_line
  do
    case "$pkg_provider_environment_line" in
      *"$pkg_provider_environment_tab"*) : ;;
      *) return 1 ;;
    esac

    pkg_provider_environment_variable=${pkg_provider_environment_line%%"$pkg_provider_environment_tab"*}
    pkg_provider_environment_descriptor=${pkg_provider_environment_line#*"$pkg_provider_environment_tab"}
    case "$pkg_provider_environment_descriptor" in *"$pkg_provider_environment_tab"*) return 1 ;; esac

    _pkg_provider_environment_name_valid "$pkg_provider_environment_variable" || return 1
    if [ "$pkg_provider_environment_variable" = "$pkg_provider_environment_previous" ] && [ "$pkg_provider_environment_variable" != PATH ]
    then
      return 1
    fi
    pkg_provider_environment_previous=$pkg_provider_environment_variable

    if [ "$pkg_provider_environment_variable" = PATH ]
    then
      case "$pkg_provider_environment_descriptor" in
        root | "root-path "*) : ;;
        *) return 1 ;;
      esac
    fi

    case "$pkg_provider_environment_descriptor" in
      root)
        pkg_provider_environment_value=$pkg_provider_environment_root
        ;;
      "root-path "*)
        pkg_provider_environment_relative=${pkg_provider_environment_descriptor#root-path }
        _pkg_provider_environment_relative_path_valid "$pkg_provider_environment_relative" || return 1
        [ -e "$pkg_provider_environment_root/$pkg_provider_environment_relative" ] || [ -L "$pkg_provider_environment_root/$pkg_provider_environment_relative" ] || return 1
        readpathce pkg_provider_environment_resolved "$pkg_provider_environment_root/$pkg_provider_environment_relative" || return 1
        case "$pkg_provider_environment_resolved" in
          "$pkg_provider_environment_root"/*) : ;;
          *) return 1 ;;
        esac
        if [ "$pkg_provider_environment_variable" = PATH ]
        then
          [ -d "$pkg_provider_environment_resolved" ] || return 1
        fi
        pkg_provider_environment_value="$pkg_provider_environment_root/$pkg_provider_environment_relative"
        ;;
      literal)
        pkg_provider_environment_value=
        ;;
      "literal "*)
        pkg_provider_environment_value=${pkg_provider_environment_descriptor#literal }
        ;;
      *)
        return 1
        ;;
    esac

    if [ "$pkg_provider_environment_variable" = PATH ]
    then
      case "$pkg_provider_environment_value" in
        "" | *:*) return 1 ;;
      esac
    fi

    printf -- '%s\t%s\n' "$pkg_provider_environment_variable" "$pkg_provider_environment_value" || return 1
    pkg_provider_environment_count=$((pkg_provider_environment_count + 1))
  done < "$pkg_provider_environment_file"

  [ "$pkg_provider_environment_count" -gt 0 ]
)

_pkg_provider_environment_plan_apply()
{
  [ "$#" -eq 1 ] || return 2
  [ -n "$1" ] || return 0

  pkg_provider_environment_apply_tab="$(printf '\t')"
  while IFS="$pkg_provider_environment_apply_tab" read -r pkg_provider_environment_apply_variable pkg_provider_environment_apply_value pkg_provider_environment_apply_extra
  do
    [ -n "$pkg_provider_environment_apply_variable" ] && [ -z "$pkg_provider_environment_apply_extra" ] || return 1
    _pkg_provider_environment_name_valid "$pkg_provider_environment_apply_variable" || return 1
    if [ "$pkg_provider_environment_apply_variable" = PATH ]
    then
      PATH="$pkg_provider_environment_apply_value${PATH:+:$PATH}"
      export PATH || return 1
    else
      export "$pkg_provider_environment_apply_variable=$pkg_provider_environment_apply_value" || return 1
    fi
  done <<EOF_PROVIDER_ENVIRONMENT
$1
EOF_PROVIDER_ENVIRONMENT
}

pkg_provider_environment_apply()
{
  [ "$#" -eq 2 ] || return 2

  pkg_provider_environment_apply_plan="$(_pkg_provider_environment_plan "$1" "$2")" || return $?
  ( _pkg_provider_environment_plan_apply "$pkg_provider_environment_apply_plan" ) || return 1
  _pkg_provider_environment_plan_apply "$pkg_provider_environment_apply_plan"
}

_pkg_provider_global_active_osarch()
(
  [ "$#" -eq 0 ] || return 2
  [ -L "$m_BIN_EXT_OSARCH_DIR" ] || return 1

  pkg_provider_global_osarch_target="$(command -p -- readlink "$m_BIN_EXT_OSARCH_DIR" 2>/dev/null)" || return 1
  case "$pkg_provider_global_osarch_target" in
    ext-*) pkg_provider_global_osarch=${pkg_provider_global_osarch_target#ext-} ;;
    *) return 1 ;;
  esac
  case "$pkg_provider_global_osarch_target" in */*) return 1 ;; esac

  _pkg_provider_osarch_valid "$pkg_provider_global_osarch" || return 1
  [ -d "$m_BIN_DIR/$pkg_provider_global_osarch_target" ] || return 1
  printf -- '%s\n' "$pkg_provider_global_osarch"
)

_pkg_provider_global_environment_class_resolve()
(
  [ "$#" -eq 4 ] || return 2
  pkg_provider_global_environment_class_pkg=$1
  pkg_provider_global_environment_class_version=$2
  pkg_provider_global_environment_class_osarch=$3
  pkg_provider_global_environment_class_require_default=$4

  _pkg_provider_name_valid "$pkg_provider_global_environment_class_pkg" || return 2
  if [ -n "$pkg_provider_global_environment_class_version" ]
  then
    _pkg_provider_version_valid "$pkg_provider_global_environment_class_version" || return 2
  fi
  if [ -n "$pkg_provider_global_environment_class_osarch" ]
  then
    _pkg_provider_osarch_valid "$pkg_provider_global_environment_class_osarch" || return 2
    pkg_provider_global_environment_class_name="$pkg_provider_global_environment_class_pkg!$pkg_provider_global_environment_class_osarch"
  else
    pkg_provider_global_environment_class_name=$pkg_provider_global_environment_class_pkg
  fi

  pkg_provider_global_environment_class_selector="$m_PKG_DIR/$pkg_provider_global_environment_class_name"
  pkg_provider_global_environment_class_current=

  if [ -z "$pkg_provider_global_environment_class_version" ] || [ "$pkg_provider_global_environment_class_require_default" -eq 1 ]
  then
    if [ ! -e "$pkg_provider_global_environment_class_selector" ] && [ ! -L "$pkg_provider_global_environment_class_selector" ]
    then
      return 1
    fi
    [ -L "$pkg_provider_global_environment_class_selector" ] || return 2
    pkg_provider_global_environment_class_current="$(command -p -- readlink "$pkg_provider_global_environment_class_selector")" || return 2
    [ -n "$pkg_provider_global_environment_class_current" ] || return 2
    case "$pkg_provider_global_environment_class_current" in */*) return 2 ;; esac
    _pkg_provider_resolved_validate       "$pkg_provider_global_environment_class_current"       "$pkg_provider_global_environment_class_pkg"       ""       "$pkg_provider_global_environment_class_osarch" || return 2
  fi

  if [ -z "$pkg_provider_global_environment_class_version" ]
  then
    pkg_provider_global_environment_class_concrete=$pkg_provider_global_environment_class_current
  elif [ -n "$pkg_provider_global_environment_class_osarch" ]
  then
    pkg_provider_global_environment_class_concrete="$pkg_provider_global_environment_class_pkg@$pkg_provider_global_environment_class_version!$pkg_provider_global_environment_class_osarch"
  else
    pkg_provider_global_environment_class_concrete="$pkg_provider_global_environment_class_pkg@$pkg_provider_global_environment_class_version"
  fi

  [ -d "$m_PKG_DIR/$pkg_provider_global_environment_class_concrete" ] && [ ! -L "$m_PKG_DIR/$pkg_provider_global_environment_class_concrete" ] || return 1
  _pkg_provider_resolved_validate     "$pkg_provider_global_environment_class_concrete"     "$pkg_provider_global_environment_class_pkg"     "$pkg_provider_global_environment_class_version"     "$pkg_provider_global_environment_class_osarch" || return 2

  printf -- '%s\n' "$pkg_provider_global_environment_class_concrete"
)

_pkg_provider_global_selector_resolve()
(
  [ "$#" -eq 1 ] || [ "$#" -eq 2 ] || return 2
  pkg_provider_global_environment_selector=$1
  pkg_provider_global_environment_active_osarch=${2-}

  if [ -n "$pkg_provider_global_environment_active_osarch" ]
  then
    _pkg_provider_osarch_valid "$pkg_provider_global_environment_active_osarch" || return 2
  fi

  _pkg_provider_selector_validate "$pkg_provider_global_environment_selector" || return 2
  pkg_provider_global_environment_selector_pkg=$pkg_provider_selector_pkg
  pkg_provider_global_environment_selector_version=$pkg_provider_selector_version
  pkg_provider_global_environment_selector_osarch=$pkg_provider_selector_osarch

  # An exact provider version identifies an installed concrete without a
  # package-class default. Only versionless selectors follow that default.
  pkg_provider_global_environment_require_default=1
  if [ -n "$pkg_provider_global_environment_selector_version" ]
  then
    pkg_provider_global_environment_require_default=0
  fi

  if [ -n "$pkg_provider_global_environment_selector_osarch" ]
  then
    [ -n "$pkg_provider_global_environment_active_osarch" ] || return 1
    [ "$pkg_provider_global_environment_selector_osarch" = "$pkg_provider_global_environment_active_osarch" ] || return 1

    if [ -n "$pkg_provider_global_environment_selector_version" ]
    then
      _pkg_provider_global_environment_class_resolve         "$pkg_provider_global_environment_selector_pkg"         "$pkg_provider_global_environment_selector_version"         "$pkg_provider_global_environment_selector_osarch"         0
    else
      _pkg_provider_global_environment_class_resolve         "$pkg_provider_global_environment_selector_pkg"         ""         "$pkg_provider_global_environment_selector_osarch"         1
    fi
    return $?
  fi

  if [ -n "$pkg_provider_global_environment_active_osarch" ]
  then
    pkg_provider_global_environment_candidate="$(
      _pkg_provider_global_environment_class_resolve         "$pkg_provider_global_environment_selector_pkg"         "$pkg_provider_global_environment_selector_version"         "$pkg_provider_global_environment_active_osarch"         "$pkg_provider_global_environment_require_default"
    )"
    pkg_provider_global_environment_candidate_status=$?
    case "$pkg_provider_global_environment_candidate_status" in
      0)
        printf -- '%s\n' "$pkg_provider_global_environment_candidate"
        return 0
        ;;
      1) : ;;
      *) return 2 ;;
    esac
  fi

  _pkg_provider_global_environment_class_resolve     "$pkg_provider_global_environment_selector_pkg"     "$pkg_provider_global_environment_selector_version"     ""     "$pkg_provider_global_environment_require_default"
)

pkg_provider_default_resolve()
(
  [ "$#" -eq 1 ] || return 2
  _pkg_provider_facility_valid "$1" || return 2

  _pkg_provider_default_file "$1" || return 3
  pkg_provider_default_resolve_file=$pkg_provider_config_file

  if [ ! -e "$pkg_provider_default_resolve_file" ] && [ ! -L "$pkg_provider_default_resolve_file" ]
  then
    return 1
  fi

  pkg_provider_default_resolve_selector="$(_pkg_provider_config_query "$pkg_provider_default_resolve_file")" || return 3
  pkg_provider_default_resolve_osarch="$(_pkg_provider_global_active_osarch 2>/dev/null)" || pkg_provider_default_resolve_osarch=

  if [ -n "$pkg_provider_default_resolve_osarch" ]
  then
    pkg_provider_default_resolve_concrete="$(
      _pkg_provider_global_selector_resolve "$pkg_provider_default_resolve_selector" "$pkg_provider_default_resolve_osarch"
    )"
  else
    pkg_provider_default_resolve_concrete="$(
      _pkg_provider_global_selector_resolve "$pkg_provider_default_resolve_selector"
    )"
  fi
  [ "$?" -eq 0 ] || return 3

  printf -- '%s\n' "$pkg_provider_default_resolve_concrete"
)

_pkg_provider_environment_plan_normalize()
{
  [ "$#" -eq 1 ] || return 2
  [ -n "$1" ] || return 0

  pkg_provider_environment_normalize_tab="$(printf '\t')"
  pkg_provider_environment_normalized="$(
    printf -- '%s\n' "$1" | LC_ALL=C command -p -- awk -F "$pkg_provider_environment_normalize_tab" '
      NF != 2 { invalid = 1; next }
      $1 == "PATH" {
        if (!path_seen[$2]++) {
          if (path == "")
            path = $2
          else
            path = $2 ":" path
        }
        next
      }
      { value[$1] = $2 }
      END {
        if (invalid)
          exit 1
        for (name in value)
          print name "\t" value[name]
        if (path != "")
          print "PATH\t" path
      }
    ' || exit 1
    printf -- '%s' x
  )" || return 1
  pkg_provider_environment_normalized=${pkg_provider_environment_normalized%x}
  [ -n "$pkg_provider_environment_normalized" ] || return 0

  printf -- '%s' "$pkg_provider_environment_normalized" | LC_ALL=C command -p -- sort
}

_pkg_provider_global_environment_plan()
(
  [ "$#" -eq 0 ] || [ "$#" -eq 1 ] || return 2
  pkg_provider_global_environment_osarch=${1-}

  if [ -n "$pkg_provider_global_environment_osarch" ]
  then
    _pkg_provider_osarch_valid "$pkg_provider_global_environment_osarch" || return 2
  fi

  _pkg_provider_system_conf || return 1
  pkg_provider_global_environment_root="$pkg_provider_system_conf/provider/default"

  if [ ! -e "$pkg_provider_global_environment_root" ] && [ ! -L "$pkg_provider_global_environment_root" ]
  then
    return 0
  fi
  valid_dir "$pkg_provider_global_environment_root" || return 1

  pkg_provider_global_environment_files="$(
    for pkg_provider_global_environment_file in "$pkg_provider_global_environment_root"/*
    do
      [ -e "$pkg_provider_global_environment_file" ] || [ -L "$pkg_provider_global_environment_file" ] || continue
      printf -- '%s\n' "$pkg_provider_global_environment_file" || exit 1
    done | LC_ALL=C command -p -- sort
  )" || return 1
  [ -n "$pkg_provider_global_environment_files" ] || return 0

  pkg_provider_global_environment_raw=

  while IFS= read -r pkg_provider_global_environment_file
  do
    [ -n "$pkg_provider_global_environment_file" ] || continue
    pkg_provider_global_environment_facility=${pkg_provider_global_environment_file##*/}
    _pkg_provider_facility_valid "$pkg_provider_global_environment_facility" || return 1

    pkg_provider_global_environment_selector="$(_pkg_provider_config_query "$pkg_provider_global_environment_file")" || return 1

    if [ -n "$pkg_provider_global_environment_osarch" ]
    then
      pkg_provider_global_environment_concrete="$(_pkg_provider_global_selector_resolve "$pkg_provider_global_environment_selector" "$pkg_provider_global_environment_osarch")"
    else
      pkg_provider_global_environment_concrete="$(_pkg_provider_global_selector_resolve "$pkg_provider_global_environment_selector")"
    fi
    pkg_provider_global_environment_status=$?

    case "$pkg_provider_global_environment_status" in
      0) : ;;
      1) continue ;;
      *) return 1 ;;
    esac

    pkg_provider_global_environment_fragment="$(_pkg_provider_environment_plan "$pkg_provider_global_environment_facility" "$pkg_provider_global_environment_concrete")" || return 1
    [ -n "$pkg_provider_global_environment_fragment" ] || continue

    if [ -n "$pkg_provider_global_environment_raw" ]
    then
      pkg_provider_global_environment_raw="$pkg_provider_global_environment_raw
$pkg_provider_global_environment_fragment"
    else
      pkg_provider_global_environment_raw=$pkg_provider_global_environment_fragment
    fi
  done <<EOF_PROVIDER_DEFAULTS
$pkg_provider_global_environment_files
EOF_PROVIDER_DEFAULTS

  _pkg_provider_environment_plan_normalize "$pkg_provider_global_environment_raw"
)

_pkg_provider_global_environment_snapshot_write()
{
  [ "$#" -eq 4 ] || return 2
  pkg_provider_snapshot_plan=$1
  pkg_provider_snapshot_file=$2
  pkg_provider_snapshot_generation=$3
  pkg_provider_snapshot_kind=$4

  case "$pkg_provider_snapshot_kind" in
    generic | osarch) : ;;
    *) return 2 ;;
  esac

  : > "$pkg_provider_snapshot_file" || return 1

  pkg_provider_snapshot_quoted="$(quote "$pkg_provider_snapshot_generation")" || return 1
  if [ "$pkg_provider_snapshot_kind" = generic ]
  then
    printf -- 'm_GLOBAL_ENV_GENERATION=%s\n' "$pkg_provider_snapshot_quoted" >> "$pkg_provider_snapshot_file" || return 1
  else
    printf -- '[ "${m_GLOBAL_ENV_GENERATION-}" = %s ] || return 1\n' "$pkg_provider_snapshot_quoted" >> "$pkg_provider_snapshot_file" || return 1
  fi

  [ -s "$pkg_provider_snapshot_plan" ] || return 0

  pkg_provider_snapshot_tab="$(printf '\t')"
  while IFS="$pkg_provider_snapshot_tab" read -r pkg_provider_snapshot_name pkg_provider_snapshot_value pkg_provider_snapshot_extra
  do
    [ -n "$pkg_provider_snapshot_name" ] && [ -z "$pkg_provider_snapshot_extra" ] || return 1
    _pkg_provider_environment_name_valid "$pkg_provider_snapshot_name" || return 1
    pkg_provider_snapshot_quoted="$(quote "$pkg_provider_snapshot_value")" || return 1

    if [ "$pkg_provider_snapshot_name" = PATH ]
    then
      printf -- 'PATH=%s${PATH:+":$PATH"}\nexport PATH\n' "$pkg_provider_snapshot_quoted" >> "$pkg_provider_snapshot_file" || return 1
    else
      printf -- '%s=%s\nexport %s\n' "$pkg_provider_snapshot_name" "$pkg_provider_snapshot_quoted" "$pkg_provider_snapshot_name" >> "$pkg_provider_snapshot_file" || return 1
    fi
  done < "$pkg_provider_snapshot_plan"
}

_pkg_provider_global_environment_restore()
{
  [ "$#" -eq 2 ] || return 2
  pkg_provider_restore_cache=$1
  pkg_provider_restore_backup=$2
  pkg_provider_restore_status=0

  for pkg_provider_restore_name in \
    env \
    env-linux-x86_64 env-linux-arm64 \
    env-macos-x86_64 env-macos-arm64 \
    env-windows-x86_64 env-windows-arm64
  do
    command -p -- rm -f -- "$pkg_provider_restore_cache/$pkg_provider_restore_name" 2>/dev/null || pkg_provider_restore_status=1
    if [ -f "$pkg_provider_restore_backup/$pkg_provider_restore_name" ] && [ ! -L "$pkg_provider_restore_backup/$pkg_provider_restore_name" ]
    then
      command -p -- cp -p -- "$pkg_provider_restore_backup/$pkg_provider_restore_name" "$pkg_provider_restore_cache/$pkg_provider_restore_name" 2>/dev/null || pkg_provider_restore_status=1
    fi
  done

  [ "$pkg_provider_restore_status" -eq 0 ]
}

pkg_provider_global_environment_materialize()
(
  [ "$#" -eq 0 ] || return 2

  pkg_provider_materialize_cache="$m_STATE_SYS_DIR/sys/environment/cache"
  umask 022
  command -p -- mkdir -p -- "$pkg_provider_materialize_cache" || return 1
  valid_dir "$pkg_provider_materialize_cache" || return 1
  command -p -- chmod 755 "$pkg_provider_materialize_cache" || return 1

  pkg_provider_materialize_stage="$pkg_provider_materialize_cache/.env-stage-$$"
  pkg_provider_materialize_backup="$pkg_provider_materialize_cache/.env-backup-$$"
  [ ! -e "$pkg_provider_materialize_stage" ] && [ ! -L "$pkg_provider_materialize_stage" ] || return 1
  [ ! -e "$pkg_provider_materialize_backup" ] && [ ! -L "$pkg_provider_materialize_backup" ] || return 1
  command -p -- mkdir -- "$pkg_provider_materialize_stage" "$pkg_provider_materialize_backup" || return 1

  _pkg_provider_materialize_cleanup()
  {
    command -p -- rm -rf -- "$pkg_provider_materialize_stage" "$pkg_provider_materialize_backup" 2>/dev/null || :
  }

  for pkg_provider_materialize_osarch in \
    linux-x86_64 linux-arm64 \
    macos-x86_64 macos-arm64 \
    windows-x86_64 windows-arm64
  do
    if ! _pkg_provider_global_environment_plan "$pkg_provider_materialize_osarch" > "$pkg_provider_materialize_stage/plan-$pkg_provider_materialize_osarch"
    then
      _pkg_provider_materialize_cleanup
      return 1
    fi
  done

  command -p -- cp -- "$pkg_provider_materialize_stage/plan-linux-x86_64" "$pkg_provider_materialize_stage/common" || {
    _pkg_provider_materialize_cleanup
    return 1
  }

  for pkg_provider_materialize_osarch in \
    linux-arm64 macos-x86_64 macos-arm64 windows-x86_64 windows-arm64
  do
    if ! command -p -- comm -12 "$pkg_provider_materialize_stage/common" "$pkg_provider_materialize_stage/plan-$pkg_provider_materialize_osarch" > "$pkg_provider_materialize_stage/common-next"
    then
      _pkg_provider_materialize_cleanup
      return 1
    fi
    command -p -- mv -f -- "$pkg_provider_materialize_stage/common-next" "$pkg_provider_materialize_stage/common" || {
      _pkg_provider_materialize_cleanup
      return 1
    }
  done

  for pkg_provider_materialize_osarch in \
    linux-x86_64 linux-arm64 \
    macos-x86_64 macos-arm64 \
    windows-x86_64 windows-arm64
  do
    if ! command -p -- comm -23 "$pkg_provider_materialize_stage/plan-$pkg_provider_materialize_osarch" "$pkg_provider_materialize_stage/common" > "$pkg_provider_materialize_stage/delta-$pkg_provider_materialize_osarch"
    then
      _pkg_provider_materialize_cleanup
      return 1
    fi
  done

  pkg_provider_materialize_generation="$(
    {
      printf -- 'generic\n'
      command -p -- cat -- "$pkg_provider_materialize_stage/common"
      for pkg_provider_materialize_osarch in \
        linux-x86_64 linux-arm64 \
        macos-x86_64 macos-arm64 \
        windows-x86_64 windows-arm64
      do
        printf -- '%s\n' "$pkg_provider_materialize_osarch"
        command -p -- cat -- "$pkg_provider_materialize_stage/delta-$pkg_provider_materialize_osarch"
      done
    } | command -p -- cksum
  )" || {
    _pkg_provider_materialize_cleanup
    return 1
  }
  set -- $pkg_provider_materialize_generation
  [ "$#" -ge 2 ] || {
    _pkg_provider_materialize_cleanup
    return 1
  }
  pkg_provider_materialize_generation="$1-$2"

  _pkg_provider_global_environment_snapshot_write \
    "$pkg_provider_materialize_stage/common" \
    "$pkg_provider_materialize_stage/env" \
    "$pkg_provider_materialize_generation" \
    generic || {
      _pkg_provider_materialize_cleanup
      return 1
    }

  for pkg_provider_materialize_osarch in \
    linux-x86_64 linux-arm64 \
    macos-x86_64 macos-arm64 \
    windows-x86_64 windows-arm64
  do
    _pkg_provider_global_environment_snapshot_write \
      "$pkg_provider_materialize_stage/delta-$pkg_provider_materialize_osarch" \
      "$pkg_provider_materialize_stage/env-$pkg_provider_materialize_osarch" \
      "$pkg_provider_materialize_generation" \
      osarch || {
        _pkg_provider_materialize_cleanup
        return 1
      }
  done

  for pkg_provider_materialize_name in \
    env \
    env-linux-x86_64 env-linux-arm64 \
    env-macos-x86_64 env-macos-arm64 \
    env-windows-x86_64 env-windows-arm64
  do
    command -p -- chmod 644 "$pkg_provider_materialize_stage/$pkg_provider_materialize_name" || {
      _pkg_provider_materialize_cleanup
      return 1
    }

    if [ -e "$pkg_provider_materialize_cache/$pkg_provider_materialize_name" ] || [ -L "$pkg_provider_materialize_cache/$pkg_provider_materialize_name" ]
    then
      [ -f "$pkg_provider_materialize_cache/$pkg_provider_materialize_name" ] && [ ! -L "$pkg_provider_materialize_cache/$pkg_provider_materialize_name" ] || {
        _pkg_provider_materialize_cleanup
        return 1
      }
      command -p -- cp -p -- "$pkg_provider_materialize_cache/$pkg_provider_materialize_name" "$pkg_provider_materialize_backup/$pkg_provider_materialize_name" || {
        _pkg_provider_materialize_cleanup
        return 1
      }
    fi
  done

  pkg_provider_materialize_publish_status=0
  for pkg_provider_materialize_name in \
    env-linux-x86_64 env-linux-arm64 \
    env-macos-x86_64 env-macos-arm64 \
    env-windows-x86_64 env-windows-arm64 \
    env
  do
    command -p -- mv -f -- "$pkg_provider_materialize_stage/$pkg_provider_materialize_name" "$pkg_provider_materialize_cache/$pkg_provider_materialize_name" || {
      pkg_provider_materialize_publish_status=1
      break
    }
  done

  if [ "$pkg_provider_materialize_publish_status" -ne 0 ]
  then
    _pkg_provider_global_environment_restore "$pkg_provider_materialize_cache" "$pkg_provider_materialize_backup" >/dev/null 2>&1 || :
    _pkg_provider_materialize_cleanup
    return 1
  fi

  _pkg_provider_materialize_cleanup
  return 0
)

pkg_provider_global_environment_apply()
{
  [ "$#" -eq 0 ] || return 2

  pkg_provider_global_environment_osarch="$(_pkg_provider_global_active_osarch 2>/dev/null)" || pkg_provider_global_environment_osarch=
  if [ -n "$pkg_provider_global_environment_osarch" ]
  then
    pkg_provider_global_environment_plan="$(_pkg_provider_global_environment_plan "$pkg_provider_global_environment_osarch")" || return 1
  else
    pkg_provider_global_environment_plan="$(_pkg_provider_global_environment_plan)" || return 1
  fi

  [ -n "$pkg_provider_global_environment_plan" ] || return 0
  ( _pkg_provider_environment_plan_apply "$pkg_provider_global_environment_plan" ) || return 1
  _pkg_provider_environment_plan_apply "$pkg_provider_global_environment_plan"
}

_pkg_provider_selector_matches_concrete()
{
  [ "$#" -eq 2 ] || return 2
  pkg_provider_match_selector=$1
  pkg_provider_match_concrete=$2

  _pkg_provider_concrete_parse "$pkg_provider_match_concrete" || return 2
  pkg_provider_match_osarch=$pkg_provider_concrete_osarch

  pkg_provider_match_resolved="$(pkg_provider_selector_resolve "$pkg_provider_match_selector" "$pkg_provider_match_osarch")"
  pkg_provider_match_status=$?
  case "$pkg_provider_match_status" in
    0) [ "$pkg_provider_match_resolved" = "$pkg_provider_match_concrete" ] ;;
    1) return 1 ;;
    *) return 2 ;;
  esac
}

pkg_provider_concrete_referenced()
{
  [ "$#" -eq 1 ] || return 2
  pkg_provider_reference_target=$1
  _pkg_provider_concrete_parse "$pkg_provider_reference_target" || return 2

  _pkg_provider_system_conf || return 2
  pkg_provider_reference_default_root="$pkg_provider_system_conf/provider/default"

  if [ -e "$pkg_provider_reference_default_root" ] || [ -L "$pkg_provider_reference_default_root" ]
  then
    [ -d "$pkg_provider_reference_default_root" ] && [ ! -L "$pkg_provider_reference_default_root" ] || return 2
    for pkg_provider_reference_file in       "$pkg_provider_reference_default_root"/*       "$pkg_provider_reference_default_root"/.[!.]*       "$pkg_provider_reference_default_root"/..?*
    do
      [ -e "$pkg_provider_reference_file" ] || [ -L "$pkg_provider_reference_file" ] || continue
      _pkg_provider_scalar_read "$pkg_provider_reference_file" || return 2
      _pkg_provider_selector_validate "$pkg_provider_scalar" || return 2
      if _pkg_provider_selector_matches_concrete "$pkg_provider_scalar" "$pkg_provider_reference_target"
      then
        return 0
      else
        pkg_provider_reference_status=$?
        [ "$pkg_provider_reference_status" -eq 1 ] || return 2
      fi
    done
  fi

  pkg_provider_reference_pkg_root="$m_STATE_SYS_DIR/pkg"
  if [ ! -e "$pkg_provider_reference_pkg_root" ] && [ ! -L "$pkg_provider_reference_pkg_root" ]
  then
    return 1
  fi
  [ -d "$pkg_provider_reference_pkg_root" ] && [ ! -L "$pkg_provider_reference_pkg_root" ] || return 2

  for pkg_provider_reference_consumer in     "$pkg_provider_reference_pkg_root"/*     "$pkg_provider_reference_pkg_root"/.[!.]*     "$pkg_provider_reference_pkg_root"/..?*
  do
    [ -e "$pkg_provider_reference_consumer" ] || [ -L "$pkg_provider_reference_consumer" ] || continue
    [ -d "$pkg_provider_reference_consumer" ] && [ ! -L "$pkg_provider_reference_consumer" ] || continue
    pkg_provider_reference_binding_root="$pkg_provider_reference_consumer/conf/binding"

    if [ ! -e "$pkg_provider_reference_binding_root" ] && [ ! -L "$pkg_provider_reference_binding_root" ]
    then
      continue
    fi
    [ -d "$pkg_provider_reference_binding_root" ] && [ ! -L "$pkg_provider_reference_binding_root" ] || return 2

    for pkg_provider_reference_file in       "$pkg_provider_reference_binding_root"/*       "$pkg_provider_reference_binding_root"/.[!.]*       "$pkg_provider_reference_binding_root"/..?*
    do
      [ -e "$pkg_provider_reference_file" ] || [ -L "$pkg_provider_reference_file" ] || continue
      _pkg_provider_scalar_read "$pkg_provider_reference_file" || return 2
      _pkg_provider_selector_validate "$pkg_provider_scalar" || return 2
      if _pkg_provider_selector_matches_concrete "$pkg_provider_scalar" "$pkg_provider_reference_target"
      then
        return 0
      else
        pkg_provider_reference_status=$?
        [ "$pkg_provider_reference_status" -eq 1 ] || return 2
      fi
    done
  done

  return 1
}

_pkg_provider_global_class_set()
{
  [ "$#" -eq 2 ] || return 2
  pkg_provider_global_pkg=$1
  pkg_provider_global_osarch=$2

  if [ -n "$pkg_provider_global_osarch" ]
  then
    _pkg_provider_osarch_valid "$pkg_provider_global_osarch" || return 2
    pkg_provider_global_class="$pkg_provider_global_pkg!$pkg_provider_global_osarch"
    pkg_provider_global_public_dir="$m_BIN_DIR/ext-$pkg_provider_global_osarch"
  else
    pkg_provider_global_class=$pkg_provider_global_pkg
    pkg_provider_global_public_dir=$m_BIN_EXT_DIR
  fi
  pkg_provider_global_selector_path="$m_PKG_DIR/$pkg_provider_global_class"
}

_pkg_provider_global_plan_concrete()
{
  [ "$#" -eq 5 ] || return 2
  pkg_provider_global_facility=$1
  pkg_provider_global_pkg=$2
  pkg_provider_global_osarch=$3
  pkg_provider_global_concrete=$4
  pkg_provider_global_target_name=$5

  [ -n "$pkg_provider_global_concrete" ] || return 0
  _pkg_provider_resolved_validate "$pkg_provider_global_concrete" "$pkg_provider_global_pkg" "" "$pkg_provider_global_osarch" || return 1
  _pkg_provider_global_class_set "$pkg_provider_global_pkg" "$pkg_provider_global_osarch" || return 1

  pkg_provider_global_cmd_dir="$m_PKG_DIR/$pkg_provider_global_concrete/facility-cmd/$pkg_provider_global_facility"
  if [ ! -e "$pkg_provider_global_cmd_dir" ] && [ ! -L "$pkg_provider_global_cmd_dir" ]
  then
    return 0
  fi
  [ -d "$pkg_provider_global_cmd_dir" ] && [ ! -L "$pkg_provider_global_cmd_dir" ] || return 1

  for pkg_provider_global_cmd_path in "$pkg_provider_global_cmd_dir"/*
  do
    [ -e "$pkg_provider_global_cmd_path" ] || [ -L "$pkg_provider_global_cmd_path" ] || continue
    [ -L "$pkg_provider_global_cmd_path" ] || return 1
    pkg_provider_global_command=${pkg_provider_global_cmd_path##*/}
    _pkg_provider_name_valid "$pkg_provider_global_command" || return 1
    readpathce pkg_provider_global_resolved "$pkg_provider_global_cmd_path" || return 1
    [ -f "$pkg_provider_global_resolved" ] && [ -x "$pkg_provider_global_resolved" ] || return 1
    printf -- '%s\t%s\n' \
      "$pkg_provider_global_public_dir/$pkg_provider_global_command" \
      "../../pkg/$pkg_provider_global_target_name/facility-cmd/$pkg_provider_global_facility/$pkg_provider_global_command"
  done
}

_pkg_provider_global_plan_class()
{
  [ "$#" -eq 5 ] || return 2
  pkg_provider_global_facility=$1
  pkg_provider_global_pkg=$2
  pkg_provider_global_version=$3
  pkg_provider_global_osarch=$4
  pkg_provider_global_require_default=$5

  _pkg_provider_global_class_set "$pkg_provider_global_pkg" "$pkg_provider_global_osarch" || return 1
  pkg_provider_global_current=

  if [ -z "$pkg_provider_global_version" ] || [ "$pkg_provider_global_require_default" -eq 1 ]
  then
    if [ ! -e "$pkg_provider_global_selector_path" ] && [ ! -L "$pkg_provider_global_selector_path" ]
    then
      return 0
    fi
    [ -L "$pkg_provider_global_selector_path" ] || return 1
    pkg_provider_global_current="$(command -p -- readlink "$pkg_provider_global_selector_path")" || return 1
    [ -n "$pkg_provider_global_current" ] || return 1
    case "$pkg_provider_global_current" in */*) return 1 ;; esac
    _pkg_provider_resolved_validate "$pkg_provider_global_current" "$pkg_provider_global_pkg" "" "$pkg_provider_global_osarch" || return 1
  fi

  if [ -z "$pkg_provider_global_version" ]
  then
    pkg_provider_global_concrete=$pkg_provider_global_current
    pkg_provider_global_target_name=$pkg_provider_global_class
  else
    if [ -n "$pkg_provider_global_osarch" ]
    then
      pkg_provider_global_concrete="$pkg_provider_global_pkg@$pkg_provider_global_version!$pkg_provider_global_osarch"
    else
      pkg_provider_global_concrete="$pkg_provider_global_pkg@$pkg_provider_global_version"
    fi
    if [ ! -d "$m_PKG_DIR/$pkg_provider_global_concrete" ] || [ -L "$m_PKG_DIR/$pkg_provider_global_concrete" ]
    then
      return 0
    fi
    pkg_provider_global_target_name=$pkg_provider_global_concrete
  fi

  _pkg_provider_global_plan_concrete \
    "$pkg_provider_global_facility" \
    "$pkg_provider_global_pkg" \
    "$pkg_provider_global_osarch" \
    "$pkg_provider_global_concrete" \
    "$pkg_provider_global_target_name"
}

_pkg_provider_global_plan_selector()
{
  [ "$#" -eq 2 ] || return 2
  pkg_provider_global_facility=$1
  pkg_provider_global_selector=$2

  [ -n "$pkg_provider_global_selector" ] || return 0
  _pkg_provider_selector_validate "$pkg_provider_global_selector" || return 2
  pkg_provider_global_plan_pkg=$pkg_provider_selector_pkg
  pkg_provider_global_plan_version=$pkg_provider_selector_version
  pkg_provider_global_plan_osarch=$pkg_provider_selector_osarch

  # An exact provider must publish its own facility commands even when
  # its package class has no mutable default selection.
  pkg_provider_global_plan_require_default=1
  if [ -n "$pkg_provider_global_plan_version" ]
  then
    pkg_provider_global_plan_require_default=0
  fi

  if [ -n "$pkg_provider_global_plan_osarch" ]
  then
    if [ -n "$pkg_provider_global_plan_version" ]
    then
      _pkg_provider_global_plan_class "$pkg_provider_global_facility" "$pkg_provider_global_plan_pkg" "$pkg_provider_global_plan_version" "$pkg_provider_global_plan_osarch" 0
    else
      _pkg_provider_global_plan_class "$pkg_provider_global_facility" "$pkg_provider_global_plan_pkg" "" "$pkg_provider_global_plan_osarch" 1
    fi
    return $?
  fi

  _pkg_provider_global_plan_class "$pkg_provider_global_facility" "$pkg_provider_global_plan_pkg" "$pkg_provider_global_plan_version" "" "$pkg_provider_global_plan_require_default" || return 1
  for pkg_provider_global_each_osarch in \
    linux-arm64 linux-x86_64 macos-arm64 macos-x86_64 windows-arm64 windows-x86_64
  do
    _pkg_provider_global_plan_class "$pkg_provider_global_facility" "$pkg_provider_global_plan_pkg" "$pkg_provider_global_plan_version" "$pkg_provider_global_each_osarch" "$pkg_provider_global_plan_require_default" || return 1
  done
}

_pkg_provider_global_plan_find()
{
  [ "$#" -eq 2 ] || return 2
  pkg_provider_global_find_plan=$1
  pkg_provider_global_find_public=$2
  pkg_provider_global_found_target=
  pkg_provider_global_found=0
  [ -n "$pkg_provider_global_find_plan" ] || return 1

  pkg_provider_global_tab="$(printf '\t')"
  while IFS="$pkg_provider_global_tab" read -r pkg_provider_global_find_path pkg_provider_global_find_target pkg_provider_global_find_extra
  do
    [ -n "$pkg_provider_global_find_path" ] && [ -n "$pkg_provider_global_find_target" ] && [ -z "$pkg_provider_global_find_extra" ] || return 2
    if [ "$pkg_provider_global_find_path" = "$pkg_provider_global_find_public" ]
    then
      [ "$pkg_provider_global_found" -eq 0 ] || return 2
      pkg_provider_global_found=1
      pkg_provider_global_found_target=$pkg_provider_global_find_target
    fi
  done <<EOF_PROVIDER_GLOBAL_FIND
$pkg_provider_global_find_plan
EOF_PROVIDER_GLOBAL_FIND

  [ "$pkg_provider_global_found" -eq 1 ]
}

_pkg_provider_global_plan_validate()
{
  [ "$#" -eq 1 ] || return 2
  pkg_provider_global_validate_plan=$1
  [ -n "$pkg_provider_global_validate_plan" ] || return 0

  pkg_provider_global_seen=
  pkg_provider_global_tab="$(printf '\t')"
  while IFS="$pkg_provider_global_tab" read -r pkg_provider_global_validate_public pkg_provider_global_validate_target pkg_provider_global_validate_extra
  do
    [ -n "$pkg_provider_global_validate_public" ] && [ -n "$pkg_provider_global_validate_target" ] && [ -z "$pkg_provider_global_validate_extra" ] || return 1
    case "$pkg_provider_global_validate_public" in "$m_BIN_EXT_DIR"/* | "$m_BIN_DIR"/ext-*/*) : ;; *) return 1 ;; esac
    case "$pkg_provider_global_validate_target" in ../../pkg/*/facility-cmd/*/*) : ;; *) return 1 ;; esac

    if [ -n "$pkg_provider_global_seen" ]
    then
      while IFS= read -r pkg_provider_global_seen_public
      do
        [ "$pkg_provider_global_seen_public" != "$pkg_provider_global_validate_public" ] || return 1
      done <<EOF_PROVIDER_GLOBAL_SEEN
$pkg_provider_global_seen
EOF_PROVIDER_GLOBAL_SEEN
      pkg_provider_global_seen="$pkg_provider_global_seen
$pkg_provider_global_validate_public"
    else
      pkg_provider_global_seen=$pkg_provider_global_validate_public
    fi
  done <<EOF_PROVIDER_GLOBAL_VALIDATE
$pkg_provider_global_validate_plan
EOF_PROVIDER_GLOBAL_VALIDATE
}

_pkg_provider_global_existing_validate()
{
  [ "$#" -eq 2 ] || return 2
  pkg_provider_global_old_plan=$1
  pkg_provider_global_new_plan=$2
  _pkg_provider_global_plan_validate "$pkg_provider_global_old_plan" || return 1
  _pkg_provider_global_plan_validate "$pkg_provider_global_new_plan" || return 1

  pkg_provider_global_tab="$(printf '\t')"
  if [ -n "$pkg_provider_global_old_plan" ]
  then
    while IFS="$pkg_provider_global_tab" read -r pkg_provider_global_public pkg_provider_global_target pkg_provider_global_extra
    do
      [ -z "$pkg_provider_global_extra" ] || return 1
      if [ -e "$pkg_provider_global_public" ] || [ -L "$pkg_provider_global_public" ]
      then
        [ -L "$pkg_provider_global_public" ] || return 1
        pkg_provider_global_actual="$(command -p -- readlink "$pkg_provider_global_public")" || return 1
        [ "$pkg_provider_global_actual" = "$pkg_provider_global_target" ] || return 1
      fi
    done <<EOF_PROVIDER_GLOBAL_OLD
$pkg_provider_global_old_plan
EOF_PROVIDER_GLOBAL_OLD
  fi

  if [ -n "$pkg_provider_global_new_plan" ]
  then
    while IFS="$pkg_provider_global_tab" read -r pkg_provider_global_public pkg_provider_global_target pkg_provider_global_extra
    do
      [ -z "$pkg_provider_global_extra" ] || return 1
      if [ -e "$pkg_provider_global_public" ] || [ -L "$pkg_provider_global_public" ]
      then
        _pkg_provider_global_plan_find "$pkg_provider_global_old_plan" "$pkg_provider_global_public" || return 1
        [ -L "$pkg_provider_global_public" ] || return 1
        pkg_provider_global_actual="$(command -p -- readlink "$pkg_provider_global_public")" || return 1
        [ "$pkg_provider_global_actual" = "$pkg_provider_global_found_target" ] || return 1
      fi
    done <<EOF_PROVIDER_GLOBAL_NEW
$pkg_provider_global_new_plan
EOF_PROVIDER_GLOBAL_NEW
  fi
}

_pkg_provider_global_link_replace()
{
  [ "$#" -eq 2 ] || return 2
  pkg_provider_global_public=$1
  pkg_provider_global_target=$2
  pkg_provider_global_parent=${pkg_provider_global_public%/*}
  [ "$pkg_provider_global_parent" != "$pkg_provider_global_public" ] || return 1

  if [ ! -e "$pkg_provider_global_parent" ] && [ ! -L "$pkg_provider_global_parent" ]
  then
    command -p -- mkdir -p -- "$pkg_provider_global_parent" || return 1
  fi
  [ -d "$pkg_provider_global_parent" ] && [ ! -L "$pkg_provider_global_parent" ] || return 1

  pkg_provider_global_index=$((pkg_provider_global_index + 1))
  pkg_provider_global_tmp="$pkg_provider_global_parent/.pkg-provider-$$-$pkg_provider_global_index"
  [ ! -e "$pkg_provider_global_tmp" ] && [ ! -L "$pkg_provider_global_tmp" ] || return 1
  command -p -- ln -s "$pkg_provider_global_target" "$pkg_provider_global_tmp" || return 1
  if ! command -p -- mv -f -- "$pkg_provider_global_tmp" "$pkg_provider_global_public"
  then
    command -p -- rm -f -- "$pkg_provider_global_tmp" 2>/dev/null || :
    return 1
  fi
}

_pkg_provider_global_restore()
{
  [ "$#" -eq 2 ] || return 2
  pkg_provider_global_restore_old=$1
  pkg_provider_global_restore_new=$2
  pkg_provider_global_index=0
  pkg_provider_global_tab="$(printf '\t')"

  if [ -n "$pkg_provider_global_restore_old" ]
  then
    while IFS="$pkg_provider_global_tab" read -r pkg_provider_global_public pkg_provider_global_target pkg_provider_global_extra
    do
      [ -z "$pkg_provider_global_extra" ] || return 1
      if [ -e "$pkg_provider_global_public" ] || [ -L "$pkg_provider_global_public" ]
      then
        [ -L "$pkg_provider_global_public" ] || return 1
        pkg_provider_global_actual="$(command -p -- readlink "$pkg_provider_global_public")" || return 1
        if [ "$pkg_provider_global_actual" != "$pkg_provider_global_target" ]
        then
          _pkg_provider_global_plan_find "$pkg_provider_global_restore_new" "$pkg_provider_global_public" || return 1
          [ "$pkg_provider_global_actual" = "$pkg_provider_global_found_target" ] || return 1
        fi
      fi
      _pkg_provider_global_link_replace "$pkg_provider_global_public" "$pkg_provider_global_target" || return 1
    done <<EOF_PROVIDER_GLOBAL_RESTORE_OLD
$pkg_provider_global_restore_old
EOF_PROVIDER_GLOBAL_RESTORE_OLD
  fi

  if [ -n "$pkg_provider_global_restore_new" ]
  then
    while IFS="$pkg_provider_global_tab" read -r pkg_provider_global_public pkg_provider_global_target pkg_provider_global_extra
    do
      [ -z "$pkg_provider_global_extra" ] || return 1
      if _pkg_provider_global_plan_find "$pkg_provider_global_restore_old" "$pkg_provider_global_public"
      then
        continue
      fi
      if [ -e "$pkg_provider_global_public" ] || [ -L "$pkg_provider_global_public" ]
      then
        [ -L "$pkg_provider_global_public" ] || return 1
        pkg_provider_global_actual="$(command -p -- readlink "$pkg_provider_global_public")" || return 1
        [ "$pkg_provider_global_actual" = "$pkg_provider_global_target" ] || return 1
        command -p -- rm -f -- "$pkg_provider_global_public" || return 1
      fi
    done <<EOF_PROVIDER_GLOBAL_RESTORE_NEW
$pkg_provider_global_restore_new
EOF_PROVIDER_GLOBAL_RESTORE_NEW
  fi
}

_pkg_provider_global_reconcile_plans()
{
  [ "$#" -eq 2 ] || return 2
  pkg_provider_global_old_plan=$1
  pkg_provider_global_new_plan=$2
  _pkg_provider_global_existing_validate "$pkg_provider_global_old_plan" "$pkg_provider_global_new_plan" || return 1

  pkg_provider_global_index=0
  pkg_provider_global_tab="$(printf '\t')"

  if [ -n "$pkg_provider_global_new_plan" ]
  then
    while IFS="$pkg_provider_global_tab" read -r pkg_provider_global_public pkg_provider_global_target pkg_provider_global_extra
    do
      [ -z "$pkg_provider_global_extra" ] || {
        _pkg_provider_global_restore "$pkg_provider_global_old_plan" "$pkg_provider_global_new_plan" >/dev/null 2>&1 || :
        return 1
      }

      if [ -L "$pkg_provider_global_public" ]
      then
        pkg_provider_global_actual="$(command -p -- readlink "$pkg_provider_global_public")" || {
          _pkg_provider_global_restore "$pkg_provider_global_old_plan" "$pkg_provider_global_new_plan" >/dev/null 2>&1 || :
          return 1
        }
        [ "$pkg_provider_global_actual" != "$pkg_provider_global_target" ] || continue
      fi

      if ! _pkg_provider_global_link_replace "$pkg_provider_global_public" "$pkg_provider_global_target"
      then
        _pkg_provider_global_restore "$pkg_provider_global_old_plan" "$pkg_provider_global_new_plan" >/dev/null 2>&1 || :
        return 1
      fi
    done <<EOF_PROVIDER_GLOBAL_APPLY_NEW
$pkg_provider_global_new_plan
EOF_PROVIDER_GLOBAL_APPLY_NEW
  fi

  if [ -n "$pkg_provider_global_old_plan" ]
  then
    while IFS="$pkg_provider_global_tab" read -r pkg_provider_global_public pkg_provider_global_target pkg_provider_global_extra
    do
      [ -z "$pkg_provider_global_extra" ] || {
        _pkg_provider_global_restore "$pkg_provider_global_old_plan" "$pkg_provider_global_new_plan" >/dev/null 2>&1 || :
        return 1
      }
      if _pkg_provider_global_plan_find "$pkg_provider_global_new_plan" "$pkg_provider_global_public"
      then
        continue
      fi
      if [ -e "$pkg_provider_global_public" ] || [ -L "$pkg_provider_global_public" ]
      then
        [ -L "$pkg_provider_global_public" ] || {
          _pkg_provider_global_restore "$pkg_provider_global_old_plan" "$pkg_provider_global_new_plan" >/dev/null 2>&1 || :
          return 1
        }
        pkg_provider_global_actual="$(command -p -- readlink "$pkg_provider_global_public")" || {
          _pkg_provider_global_restore "$pkg_provider_global_old_plan" "$pkg_provider_global_new_plan" >/dev/null 2>&1 || :
          return 1
        }
        [ "$pkg_provider_global_actual" = "$pkg_provider_global_target" ] || {
          _pkg_provider_global_restore "$pkg_provider_global_old_plan" "$pkg_provider_global_new_plan" >/dev/null 2>&1 || :
          return 1
        }
        if ! command -p -- rm -f -- "$pkg_provider_global_public"
        then
          _pkg_provider_global_restore "$pkg_provider_global_old_plan" "$pkg_provider_global_new_plan" >/dev/null 2>&1 || :
          return 1
        fi
      fi
    done <<EOF_PROVIDER_GLOBAL_APPLY_OLD
$pkg_provider_global_old_plan
EOF_PROVIDER_GLOBAL_APPLY_OLD
  fi
}

_pkg_provider_global_reconcile()
{
  [ "$#" -eq 3 ] || return 2
  pkg_provider_global_facility=$1
  pkg_provider_global_old_selector=$2
  pkg_provider_global_new_selector=$3
  _pkg_provider_facility_valid "$pkg_provider_global_facility" || return 2

  pkg_provider_global_old_plan="$(_pkg_provider_global_plan_selector "$pkg_provider_global_facility" "$pkg_provider_global_old_selector")" || return 1
  pkg_provider_global_new_plan="$(_pkg_provider_global_plan_selector "$pkg_provider_global_facility" "$pkg_provider_global_new_selector")" || return 1
  _pkg_provider_global_reconcile_plans "$pkg_provider_global_old_plan" "$pkg_provider_global_new_plan"
}

pkg_provider_package_default_reconcile()
(
  [ "$#" -eq 4 ] || return 2
  pkg_provider_transition_pkg=$1
  pkg_provider_transition_osarch=$2
  pkg_provider_transition_old=$3
  pkg_provider_transition_new=$4

  _pkg_provider_name_valid "$pkg_provider_transition_pkg" || return 2
  if [ -n "$pkg_provider_transition_osarch" ]
  then
    _pkg_provider_osarch_valid "$pkg_provider_transition_osarch" || return 2
    pkg_provider_transition_class="$pkg_provider_transition_pkg!$pkg_provider_transition_osarch"
  else
    pkg_provider_transition_class=$pkg_provider_transition_pkg
  fi

  if [ -n "$pkg_provider_transition_old" ]
  then
    _pkg_provider_resolved_validate "$pkg_provider_transition_old" "$pkg_provider_transition_pkg" "" "$pkg_provider_transition_osarch" || return 1
  fi
  if [ -n "$pkg_provider_transition_new" ]
  then
    _pkg_provider_resolved_validate "$pkg_provider_transition_new" "$pkg_provider_transition_pkg" "" "$pkg_provider_transition_osarch" || return 1
  fi

  _pkg_provider_system_conf || return 1
  pkg_provider_transition_root="$pkg_provider_system_conf/provider/default"
  if [ ! -e "$pkg_provider_transition_root" ] && [ ! -L "$pkg_provider_transition_root" ]
  then
    return 0
  fi
  [ -d "$pkg_provider_transition_root" ] && [ ! -L "$pkg_provider_transition_root" ] || return 1

  pkg_provider_transition_old_plan=
  pkg_provider_transition_new_plan=
  for pkg_provider_transition_file in \
    "$pkg_provider_transition_root"/* \
    "$pkg_provider_transition_root"/.[!.]* \
    "$pkg_provider_transition_root"/..?*
  do
    [ -e "$pkg_provider_transition_file" ] || [ -L "$pkg_provider_transition_file" ] || continue
    [ -f "$pkg_provider_transition_file" ] && [ ! -L "$pkg_provider_transition_file" ] || return 1
    pkg_provider_transition_facility=${pkg_provider_transition_file##*/}
    _pkg_provider_facility_valid "$pkg_provider_transition_facility" || return 1
    _pkg_provider_scalar_read "$pkg_provider_transition_file" || return 1
    _pkg_provider_selector_validate "$pkg_provider_scalar" || return 1

    pkg_provider_transition_selector_pkg=$pkg_provider_selector_pkg
    pkg_provider_transition_selector_version=$pkg_provider_selector_version
    pkg_provider_transition_selector_osarch=$pkg_provider_selector_osarch

    [ "$pkg_provider_transition_selector_pkg" = "$pkg_provider_transition_pkg" ] || continue

    if [ -n "$pkg_provider_transition_selector_osarch" ]
    then
      [ "$pkg_provider_transition_selector_osarch" = "$pkg_provider_transition_osarch" ] || continue
      [ -z "$pkg_provider_transition_selector_version" ] || continue
    fi

    if [ -n "$pkg_provider_transition_selector_version" ]
    then
      if [ -n "$pkg_provider_transition_osarch" ]
      then
        pkg_provider_transition_selected_concrete="$pkg_provider_transition_pkg@$pkg_provider_transition_selector_version!$pkg_provider_transition_osarch"
      else
        pkg_provider_transition_selected_concrete="$pkg_provider_transition_pkg@$pkg_provider_transition_selector_version"
      fi
      pkg_provider_transition_target=$pkg_provider_transition_selected_concrete
      if [ -n "$pkg_provider_transition_old" ]
      then
        pkg_provider_transition_old_source=$pkg_provider_transition_selected_concrete
      else
        pkg_provider_transition_old_source=
      fi
      if [ -n "$pkg_provider_transition_new" ]
      then
        pkg_provider_transition_new_source=$pkg_provider_transition_selected_concrete
      else
        pkg_provider_transition_new_source=
      fi
    else
      pkg_provider_transition_target=$pkg_provider_transition_class
      pkg_provider_transition_old_source=$pkg_provider_transition_old
      pkg_provider_transition_new_source=$pkg_provider_transition_new
    fi

    pkg_provider_transition_piece="$(_pkg_provider_global_plan_concrete \
      "$pkg_provider_transition_facility" \
      "$pkg_provider_transition_pkg" \
      "$pkg_provider_transition_osarch" \
      "$pkg_provider_transition_old_source" \
      "$pkg_provider_transition_target")" || return 1
    if [ -n "$pkg_provider_transition_piece" ]
    then
      if [ -n "$pkg_provider_transition_old_plan" ]
      then
        pkg_provider_transition_old_plan="$pkg_provider_transition_old_plan
$pkg_provider_transition_piece"
      else
        pkg_provider_transition_old_plan=$pkg_provider_transition_piece
      fi
    fi

    pkg_provider_transition_piece="$(_pkg_provider_global_plan_concrete \
      "$pkg_provider_transition_facility" \
      "$pkg_provider_transition_pkg" \
      "$pkg_provider_transition_osarch" \
      "$pkg_provider_transition_new_source" \
      "$pkg_provider_transition_target")" || return 1
    if [ -n "$pkg_provider_transition_piece" ]
    then
      if [ -n "$pkg_provider_transition_new_plan" ]
      then
        pkg_provider_transition_new_plan="$pkg_provider_transition_new_plan
$pkg_provider_transition_piece"
      else
        pkg_provider_transition_new_plan=$pkg_provider_transition_piece
      fi
    fi
  done

  _pkg_provider_global_reconcile_plans "$pkg_provider_transition_old_plan" "$pkg_provider_transition_new_plan" || return 1
  if ! pkg_provider_global_environment_materialize
  then
    _pkg_provider_global_reconcile_plans "$pkg_provider_transition_new_plan" "$pkg_provider_transition_old_plan" >/dev/null 2>&1 || :
    return 1
  fi
  _pkg_provider_facility_map_reconcile || log warn execution facility-map-reconcile-failed operation pkg-provider-package-default || :
  return 0
)

pkg_provider()
(
  [ "$#" -ge 1 ] || return 2
  pkg_provider_action=$1
  shift

  case "$pkg_provider_action" in
    default) _pkg_provider_default "$@" ;;
    bind) _pkg_provider_bind "$@" ;;
    *) return 2 ;;
  esac
)
