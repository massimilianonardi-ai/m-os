loadsyslib "pkg/pkg-common"
loadsyslib "pkg/facility/pkg-dependency"
loadsyslib "context-store"
loadsyslib "context-profile-registry"

_context_error()
{
  [ "$#" -eq 2 ] || return 2
  log error execution "$1" operation context value "$2"
}

_context_host_osarch_ensure()
{
  [ "$#" -eq 0 ] || return 2
  if [ -z "${m_OSARCH-}" ]
  then
    loadsyslib osarch || return 1
  fi
  pkg_osarch_valid "$m_OSARCH"
}

# Resolve the selected concrete's schema once for command and library views.
_context_views_set()
{
  [ "$#" -eq 1 ] || return 2
  _pkg_schema_read "$m_PKG_DIR/$1" || return 1
  case "$pkg_schema" in
    v1)
      _context_bin_rel=cmd
      _context_lib_rel=lib
      ;;
    v2)
      _context_bin_rel=link/bin
      _context_lib_rel=link/lib
      ;;
    *) return 1 ;;
  esac
}

# Compute a most-recent-first concrete list from a data-only baseline followed
# by ordered pkg= operands. The caller applies it only after every check passes.
_context_resolve_list()
(
  [ "$#" -eq 2 ] || return 2
  _context_initial_operands=$1
  _context_ordered_operands=$2
  if [ -z "$_context_initial_operands" ] && [ -z "$_context_ordered_operands" ]
  then
    return 0
  fi

  # Detect the active host platform in this subshell: selecting an exact
  # concrete must work in a fresh m sh session without changing caller
  # variables other than the PATH/CLASSPATH owned by context.
  _context_host_osarch_ensure || return 1

  _context_resolved=
  _context_newline='
'
  _context_remaining_operands=$_context_initial_operands
  if [ -n "$_context_ordered_operands" ]
  then
    if [ -n "$_context_remaining_operands" ]
    then
      _context_remaining_operands="$_context_remaining_operands$_context_newline$_context_ordered_operands"
    else
      _context_remaining_operands=$_context_ordered_operands
    fi
  fi

  while [ -n "$_context_remaining_operands" ]
  do
    case "$_context_remaining_operands" in
      *"$_context_newline"*)
        _context_operand=${_context_remaining_operands%%"$_context_newline"*}
        _context_remaining_operands=${_context_remaining_operands#*"$_context_newline"}
        ;;
      *)
        _context_operand=$_context_remaining_operands
        _context_remaining_operands=
        ;;
    esac
    case "$_context_operand" in
      pkg=*) _context_requested=${_context_operand#pkg=} ;;
      *) _context_error context-operand-invalid "$_context_operand"; return 2 ;;
    esac

    if ! pkg_concrete_read _context_pkg _context_version _context_osarch "$_context_requested"
    then
      _context_error context-package-spec-invalid "$_context_requested"
      return 3
    fi

    if [ -n "$_context_osarch" ] && [ "$_context_osarch" != "${m_OSARCH-}" ]
    then
      _context_error context-platform-incompatible "$_context_requested"
      return 4
    fi

    _context_concrete="$m_PKG_DIR/$_context_requested"
    if [ ! -d "$_context_concrete" ] || [ -L "$_context_concrete" ]
    then
      _context_error context-concrete-unavailable "$_context_requested"
      return 5
    fi

    _context_previous=$_context_resolved
    _context_resolved=$_context_requested
    while [ -n "$_context_previous" ]
    do
      case "$_context_previous" in
        *"$_context_newline"*)
          _context_item=${_context_previous%%"$_context_newline"*}
          _context_previous=${_context_previous#*"$_context_newline"}
          ;;
        *)
          _context_item=$_context_previous
          _context_previous=
          ;;
      esac
      case "$_context_item" in
        "$_context_pkg@"*) continue ;;
      esac
      _context_resolved="$_context_resolved$_context_newline$_context_item"
    done
  done

  printf '%s' "$_context_resolved"
)

# Return the PATH with one previously published context-owned block removed.
# The wrapping colon preserves empty host PATH entries exactly.
_context_path_unapply()
{
  [ "$#" -eq 2 ] || [ "$#" -eq 3 ] || return 2
  _context_unapply_path=$1
  _context_unapply_prefix=$2
  if [ -z "$_context_unapply_prefix" ]
  then
    _context_path_base=$_context_unapply_path
    return 0
  fi

  _context_unapply_wrapped=":$_context_unapply_path:"
  _context_unapply_marker=":$_context_unapply_prefix:"
  case "$_context_unapply_wrapped" in
    *"$_context_unapply_marker"*) : ;;
    *)
      if [ "${3-}" = CLASSPATH ]
      then
        _context_error context-classpath-modified "$_context_unapply_prefix"
      else
        _context_error context-path-modified "$_context_unapply_prefix"
      fi
      return 6
      ;;
  esac

  _context_unapply_before=${_context_unapply_wrapped%%"$_context_unapply_marker"*}
  _context_unapply_after=${_context_unapply_wrapped#*"$_context_unapply_marker"}
  _context_unapply_wrapped="$_context_unapply_before:$_context_unapply_after"
  _context_unapply_wrapped=${_context_unapply_wrapped#:}
  _context_path_base=${_context_unapply_wrapped%:}
}

# The installed command directories are the real published surfaces. Reject
# command collisions rather than silently making one unrelated package win.
_context_commands_validate()
(
  [ "$#" -eq 1 ] || return 2
  _context_scan_remaining=$1
  _context_scan_names=
  _context_scan_newline='
'
  while [ -n "$_context_scan_remaining" ]
  do
    case "$_context_scan_remaining" in
      *"$_context_scan_newline"*)
        _context_scan_concrete=${_context_scan_remaining%%"$_context_scan_newline"*}
        _context_scan_remaining=${_context_scan_remaining#*"$_context_scan_newline"}
        ;;
      *)
        _context_scan_concrete=$_context_scan_remaining
        _context_scan_remaining=
        ;;
    esac

    _context_views_set "$_context_scan_concrete" || {
      _context_error context-package-schema-invalid "$_context_scan_concrete"
      return 9
    }
    for _context_scan_command in "$m_PKG_DIR/$_context_scan_concrete/$_context_bin_rel/"*
    do
      [ -e "$_context_scan_command" ] || [ -L "$_context_scan_command" ] || continue
      [ -f "$_context_scan_command" ] && [ -x "$_context_scan_command" ] || {
        _context_error context-command-invalid "$_context_scan_command"
        return 9
      }
      _context_scan_name=${_context_scan_command##*/}

      # Revalidate installed v2 symlinks before publishing their PATH view.
      # A direct executable bypasses the package launcher entirely.
      if [ "$_context_bin_rel" = link/bin ] &&
         ! _pkg_v2_installed_command_validate "$m_PKG_DIR/$_context_scan_concrete" "$_context_scan_name"
      then
        _context_error context-command-link-invalid "$_context_scan_command"
        return 18
      fi

      for _context_scan_core in "${m_BIN_SYS_DIR-}" "${m_BIN_SYS_OSARCH_DIR-}"
      do
        [ -n "$_context_scan_core" ] || continue
        if [ -e "$_context_scan_core/$_context_scan_name" ] ||
           [ -L "$_context_scan_core/$_context_scan_name" ]
        then
          _context_error context-command-protected "$_context_scan_name"
          return 10
        fi
      done

      case "$_context_scan_newline$_context_scan_names$_context_scan_newline" in
        *"$_context_scan_newline$_context_scan_name$_context_scan_newline"*)
          _context_error context-command-collision "$_context_scan_name"
          return 11
          ;;
      esac
      if [ -n "$_context_scan_names" ]
      then
        _context_scan_names="$_context_scan_names$_context_scan_newline$_context_scan_name"
      else
        _context_scan_names=$_context_scan_name
      fi
    done
  done
)

# Installed library projections are independently published by pkg, not by
# context, and do not depend on facility declarations. Reject ambiguous names.
_context_libraries_validate()
(
  [ "$#" -eq 1 ] || return 2
  _context_lib_items=$1
  _context_lib_newline='
'
  _context_lib_sh_names=
  _context_lib_java_names=

  while [ -n "$_context_lib_items" ]
  do
    case "$_context_lib_items" in
      *"$_context_lib_newline"*)
        _context_lib_concrete=${_context_lib_items%%"$_context_lib_newline"*}
        _context_lib_items=${_context_lib_items#*"$_context_lib_newline"}
        ;;
      *)
        _context_lib_concrete=$_context_lib_items
        _context_lib_items=
        ;;
    esac

    _context_views_set "$_context_lib_concrete" || {
      _context_error context-package-schema-invalid "$_context_lib_concrete"
      return 12
    }
    _context_concrete_lib_rel=$_context_lib_rel
    for _context_lib_kind in sh java
    do
      _context_lib_root="$m_PKG_DIR/$_context_lib_concrete/$_context_concrete_lib_rel"
      _context_lib_dir="$_context_lib_root/$_context_lib_kind"
      if [ ! -e "$_context_lib_dir" ] && [ ! -L "$_context_lib_dir" ]
      then
        continue
      fi
      [ -d "$_context_lib_root" ] && [ ! -L "$_context_lib_root" ] &&
      [ -d "$_context_lib_dir" ] && [ ! -L "$_context_lib_dir" ] || {
        _context_error context-library-view-invalid "$_context_lib_dir"
        return 12
      }

      for _context_lib_file in "$_context_lib_dir/"*
      do
        [ -e "$_context_lib_file" ] || [ -L "$_context_lib_file" ] || continue
        _context_lib_name=${_context_lib_file##*/}
        [ -L "$_context_lib_file" ] && [ -f "$_context_lib_file" ] && [ -r "$_context_lib_file" ] || {
          _context_error context-library-link-invalid "$_context_lib_file"
          return 13
        }
        case "$_context_lib_kind:$_context_lib_name" in
          sh:*.lib.sh)
            [ ! -x "$_context_lib_file" ] || {
              _context_error context-library-link-invalid "$_context_lib_file"
              return 13
            }

            # PATH serves both dot lookup and executable lookup: never let
            # a command script shadow a selected shell library name.
            for _context_lib_core_dir in "${m_BIN_SYS_DIR-}" "${m_BIN_SYS_OSARCH_DIR-}"
            do
              [ -n "$_context_lib_core_dir" ] || continue
              if [ -e "$_context_lib_core_dir/$_context_lib_name" ] ||
                 [ -L "$_context_lib_core_dir/$_context_lib_name" ]
              then
                _context_error context-library-name-collision "$_context_lib_name"
                return 14
              fi
            done
            _context_lib_other_items=$1
            while [ -n "$_context_lib_other_items" ]
            do
              case "$_context_lib_other_items" in
                *"$_context_lib_newline"*)
                  _context_lib_other=${_context_lib_other_items%%"$_context_lib_newline"*}
                  _context_lib_other_items=${_context_lib_other_items#*"$_context_lib_newline"}
                  ;;
                *)
                  _context_lib_other=$_context_lib_other_items
                  _context_lib_other_items=
                  ;;
              esac
              _context_views_set "$_context_lib_other" || return 12
              _context_lib_command="$m_PKG_DIR/$_context_lib_other/$_context_bin_rel/$_context_lib_name"
              if [ -e "$_context_lib_command" ] || [ -L "$_context_lib_command" ]
              then
                _context_error context-library-name-collision "$_context_lib_name"
                return 14
              fi
            done

            case "$_context_lib_newline$_context_lib_sh_names$_context_lib_newline" in
              *"$_context_lib_newline$_context_lib_name$_context_lib_newline"*)
                _context_error context-library-name-collision "$_context_lib_name"
                return 14
                ;;
            esac
            _context_lib_sh_names="$_context_lib_sh_names$_context_lib_newline$_context_lib_name"
            ;;
          java:*.jar)
            case "$_context_lib_newline$_context_lib_java_names$_context_lib_newline" in
              *"$_context_lib_newline$_context_lib_name$_context_lib_newline"*)
                _context_error context-library-name-collision "$_context_lib_name"
                return 14
                ;;
            esac
            _context_lib_java_names="$_context_lib_java_names$_context_lib_newline$_context_lib_name"
            ;;
          *)
            _context_error context-library-link-invalid "$_context_lib_file"
            return 13
            ;;
        esac
      done
    done
  done
)

_context_store_load_defaults()
{
  [ "$#" -eq 0 ] || return 2
  _context_store_read "$m_ROOT" defaults
  _context_store_status=$?
  case "$_context_store_status" in
    0) return 0 ;;
    5)
      CONTEXT_STORE_RECORD=
      CONTEXT_STORE_VERSION=
      CONTEXT_STORE_SYSTEM=
      CONTEXT_STORE_USER=
      CONTEXT_STORE_LOCALE=
      CONTEXT_STORE_OSARCH=
      CONTEXT_STORE_PACKAGES=
      CONTEXT_STORE_PROVIDERS=
      return 0
      ;;
    *)
      _context_error context-default-store-invalid "$m_ROOT/state"
      return 19
      ;;
  esac
}

_context_user_identity_resolve()
{
  [ "$#" -eq 1 ] || return 2
  _context_user_identity=$1
  _context_profile_registry_identity_valid "$_context_user_identity" || return 1
  if [ -e "$m_ROOT/state" ] || [ -L "$m_ROOT/state" ]
  then
    [ -d "$m_ROOT/state" ] && [ ! -L "$m_ROOT/state" ] || return 1
  fi
  if [ -e "$m_ROOT/state/user" ] || [ -L "$m_ROOT/state/user" ]
  then
    [ -d "$m_ROOT/state/user" ] && [ ! -L "$m_ROOT/state/user" ] || return 1
  fi
  _context_user_identity_path="$m_ROOT/state/user/$_context_user_identity"
  if [ -e "$_context_user_identity_path" ] || [ -L "$_context_user_identity_path" ]
  then
    [ -d "$_context_user_identity_path" ] && [ ! -L "$_context_user_identity_path" ] || return 1
  fi
  _context_user_identity_resolved=$_context_user_identity_path
}

_context_locale_resolve()
{
  [ "$#" -eq 1 ] || return 2
  _context_locale_requested=$1
  _context_store_locale_valid "$_context_locale_requested" || return 1
  [ -d "$m_LANG_DIR" ] && [ ! -L "$m_LANG_DIR" ] || return 1
  _context_locale_path="$m_LANG_DIR/$_context_locale_requested"
  [ -d "$_context_locale_path" ] && [ ! -L "$_context_locale_path" ] || return 1
  _context_locale_selected=$_context_locale_requested
}

_context_global_locale_resolve()
{
  [ "$#" -eq 0 ] || return 2
  _context_global_locale_selected=
  if [ -L "$m_LANG_CURRENT_DIR" ]
  then
    _context_global_locale_selected=$(command -p readlink "$m_LANG_CURRENT_DIR" 2>/dev/null) || return 1
  fi
  [ -n "$_context_global_locale_selected" ] || _context_global_locale_selected=${m_LANGUAGE_FALLBACK:-en_US}
  _context_locale_resolve "$_context_global_locale_selected"
}

_context_provider_pins_set()
{
  [ "$#" -eq 3 ] || return 2
  _context_provider_pins_current=$1
  _context_provider_pins_facility=$2
  _context_provider_pins_selector=$3
  _pkg_facility_name_valid "$_context_provider_pins_facility" || return 1
  pkg_request_read _context_provider_pkg _context_provider_version _context_provider_arch "$_context_provider_pins_selector" || return 1
  _context_provider_pins_newline='
'
  _context_provider_pins_next=
  _context_provider_pins_found=0
  _context_provider_pins_remaining=$_context_provider_pins_current
  while [ -n "$_context_provider_pins_remaining" ]
  do
    case "$_context_provider_pins_remaining" in
      *"$_context_provider_pins_newline"*)
        _context_provider_pins_line=${_context_provider_pins_remaining%%"$_context_provider_pins_newline"*}
        _context_provider_pins_remaining=${_context_provider_pins_remaining#*"$_context_provider_pins_newline"}
        ;;
      *) _context_provider_pins_line=$_context_provider_pins_remaining; _context_provider_pins_remaining= ;;
    esac
    _context_provider_pins_line_facility=${_context_provider_pins_line#provider.}
    _context_provider_pins_line_facility=${_context_provider_pins_line_facility%%=*}
    if [ "$_context_provider_pins_line_facility" = "$_context_provider_pins_facility" ]
    then
      _context_provider_pins_line="provider.$_context_provider_pins_facility=$_context_provider_pins_selector"
      _context_provider_pins_found=1
    fi
    if [ -n "$_context_provider_pins_next" ]; then
      _context_provider_pins_next="$_context_provider_pins_next$_context_provider_pins_newline$_context_provider_pins_line"
    else
      _context_provider_pins_next=$_context_provider_pins_line
    fi
  done
  if [ "$_context_provider_pins_found" -eq 0 ]
  then
    if [ -n "$_context_provider_pins_next" ]; then
      _context_provider_pins_next="$_context_provider_pins_next$_context_provider_pins_newline"
    fi
    _context_provider_pins_next="${_context_provider_pins_next}provider.$_context_provider_pins_facility=$_context_provider_pins_selector"
  fi
  _context_provider_pins_result=$_context_provider_pins_next
}

# Resolve every provider pin against the selected package target and require
# that the installed concrete actually publishes the named facility. This is
# run during preparation and inherited-envelope validation, before activation.
_context_provider_pins_validate()
(
  [ "$#" -eq 2 ] || return 2
  _context_provider_validate_remaining=$1
  _context_provider_validate_osarch=$2
  _context_provider_validate_newline='
'
  while [ -n "$_context_provider_validate_remaining" ]
  do
    case "$_context_provider_validate_remaining" in
      *"$_context_provider_validate_newline"*)
        _context_provider_validate_line=${_context_provider_validate_remaining%%"$_context_provider_validate_newline"*}
        _context_provider_validate_remaining=${_context_provider_validate_remaining#*"$_context_provider_validate_newline"}
        ;;
      *) _context_provider_validate_line=$_context_provider_validate_remaining; _context_provider_validate_remaining= ;;
    esac
    case "$_context_provider_validate_line" in provider.*=*) : ;; *) return 1 ;; esac
    _context_provider_validate_facility=${_context_provider_validate_line#provider.}
    _context_provider_validate_facility=${_context_provider_validate_facility%%=*}
    _pkg_facility_name_valid "$_context_provider_validate_facility" || return 1
    _context_provider_validate_selector=${_context_provider_validate_line#*=}
    _context_provider_validate_concrete=$(pkg_provider_selector_resolve \
      "$_context_provider_validate_selector" "$_context_provider_validate_osarch") || return 1
    _context_provider_validate_file="$m_PKG_DIR/$_context_provider_validate_concrete/facility"
    _pkg_facility_file_validate "$_context_provider_validate_file" || return 1
    _context_provider_validate_found=0
    while IFS= read -r _context_provider_validate_entry
    do
      _pkg_facility_line_parse "$_context_provider_validate_entry" || return 1
      if [ "$pkg_facility_name" = "$_context_provider_validate_facility" ]
      then
        _context_provider_validate_found=1
        break
      fi
    done < "$_context_provider_validate_file"
    [ "$_context_provider_validate_found" -eq 1 ] || return 1
  done
)

_context_profile_resolve()
{
  [ "$#" -eq 1 ] || return 2
  _context_profile_requested=$1
  _context_profile_registry_read "$m_ROOT" || {
    _context_error context-profile-inventory-invalid "$m_ROOT/state/system/profile/.inventory"
    return 24
  }
  _context_profile_selected=${_context_profile_requested:-$CONTEXT_PROFILE_REGISTRY_BASELINE}
  _context_profile_registry_identity_valid "$_context_profile_selected" || {
    _context_error context-profile-invalid "$_context_profile_selected"
    return 23
  }
  _context_profile_newline='
'
  case "$_context_profile_newline$_context_profile_registry_identities$_context_profile_newline" in
    *"$_context_profile_newline$_context_profile_selected$_context_profile_newline"*) : ;;
    *)
      _context_error context-profile-unmanaged "$_context_profile_selected"
      return 23
      ;;
  esac
  _context_profile_path="$m_ROOT/state/system/profile/$_context_profile_selected"
  [ -d "$_context_profile_path" ] && [ ! -L "$_context_profile_path" ] || {
    _context_error context-profile-unavailable "$_context_profile_selected"
    return 24
  }
}

_context_envelope_build()
{
  [ "$#" -eq 7 ] || return 2
  _context_envelope_system=$1
  _context_envelope_user=$2
  _context_envelope_locale=$3
  _context_envelope_osarch=$4
  _context_envelope_providers=$5
  _context_envelope_packages=$6
  _context_envelope_classpath_host_set=$7
  _context_envelope_uid=$(command -p id -u 2>/dev/null) || return 1
  case "$_context_envelope_uid" in '' | *[!0-9]*) return 1 ;; esac
  case "$m_ROOT" in *'
'*) return 1 ;; esac
  case "$_context_envelope_classpath_host_set" in 0 | 1) : ;; *) return 1 ;; esac
  _context_profile_registry_identity_valid "$_context_envelope_system" || return 1
  _context_user_identity_resolve "$_context_envelope_user" || return 1
  _context_locale_resolve "$_context_envelope_locale" || return 1
  pkg_osarch_valid "$_context_envelope_osarch" || return 1
  _context_envelope_newline='
'
  _context_envelope_value=$(printf '%s\n' \
    m-context-envelope-v2 \
    "root=$m_ROOT" \
    "uid=$_context_envelope_uid" \
    "system=$_context_envelope_system" \
    "user=$_context_envelope_user" \
    "locale=$_context_envelope_locale" \
    "osarch=$_context_envelope_osarch" \
    "classpath-host-set=$_context_envelope_classpath_host_set") || return 1
  _context_envelope_remaining=$_context_envelope_providers
  while [ -n "$_context_envelope_remaining" ]
  do
    case "$_context_envelope_remaining" in
      *"$_context_envelope_newline"*)
        _context_envelope_item=${_context_envelope_remaining%%"$_context_envelope_newline"*}
        _context_envelope_remaining=${_context_envelope_remaining#*"$_context_envelope_newline"}
        ;;
      *) _context_envelope_item=$_context_envelope_remaining; _context_envelope_remaining= ;;
    esac
    case "$_context_envelope_item" in
      provider.*=*)
        _context_envelope_facility=${_context_envelope_item#provider.}
        _context_envelope_facility=${_context_envelope_facility%%=*}
        _pkg_facility_name_valid "$_context_envelope_facility" || return 1
        _context_envelope_selector=${_context_envelope_item#*=}
        pkg_request_read _context_envelope_pkg _context_envelope_version _context_envelope_arch "$_context_envelope_selector" || return 1
        ;;
      *) return 1 ;;
    esac
    _context_envelope_value="$_context_envelope_value$_context_envelope_newline$_context_envelope_item"
  done
  _context_provider_pins_validate "$_context_envelope_providers" \
    "$_context_envelope_osarch" || return 1
  _context_envelope_remaining=$_context_envelope_packages
  while [ -n "$_context_envelope_remaining" ]
  do
    case "$_context_envelope_remaining" in
      *"$_context_envelope_newline"*)
        _context_envelope_item=${_context_envelope_remaining%%"$_context_envelope_newline"*}
        _context_envelope_remaining=${_context_envelope_remaining#*"$_context_envelope_newline"}
        ;;
      *)
        _context_envelope_item=$_context_envelope_remaining
        _context_envelope_remaining=
        ;;
    esac
    _context_envelope_value="${_context_envelope_value}${_context_envelope_newline}package=$_context_envelope_item"
  done
  [ "${#_context_envelope_value}" -le 16383 ] || return 1
  printf '%s\n' "$_context_envelope_value"
}

# Validate the inherited shell context as data before bootstrap uses it. A
# present invalid envelope is an error; it never falls back to global defaults.
_context_envelope_validate()
{
  [ "$#" -eq 0 ] || return 2
  [ "${m_CONTEXT_ENVELOPE+x}" = x ] || return 5
  _context_envelope_size=${#m_CONTEXT_ENVELOPE}
  [ "$_context_envelope_size" -le 16383 ] || return 1
  _context_envelope_root=
  _context_envelope_uid=
  _context_envelope_system=
  _context_envelope_user=
  _context_envelope_locale=
  _context_envelope_osarch=
  _context_envelope_providers=
  _context_envelope_classpath_host_set=
  _context_envelope_packages=
  _context_envelope_package_ids=
  _context_operand_newline='
'
  _context_envelope_line_count=0
  _context_envelope_header=1
  _context_envelope_format_version=
  _context_envelope_root_seen=0
  _context_envelope_uid_seen=0
  _context_envelope_system_seen=0
  _context_envelope_user_seen=0
  _context_envelope_locale_seen=0
  _context_envelope_osarch_seen=0
  _context_envelope_classpath_seen=0
  _context_envelope_provider_seen=
  _context_envelope_phase=0
  _context_envelope_newline='
'
  _context_envelope_cr=$(printf '\r')
  while IFS= read -r _context_envelope_line || [ -n "$_context_envelope_line" ]
  do
    _context_envelope_line_count=$((_context_envelope_line_count + 1))
    [ "$_context_envelope_line_count" -le 133 ] || return 1
    case "$_context_envelope_line" in *"$_context_envelope_cr"*) return 1 ;; esac
    if [ "$_context_envelope_header" -eq 1 ]
    then
      case "$_context_envelope_line" in
        m-context-envelope-v1) _context_envelope_format_version=1 ;;
        m-context-envelope-v2) _context_envelope_format_version=2 ;;
        *) return 1 ;;
      esac
      _context_envelope_header=0
      continue
    fi
    case "$_context_envelope_line" in
      root=*)
        [ "$_context_envelope_phase" -eq 0 ] && [ "$_context_envelope_root_seen" -eq 0 ] || return 1
        _context_envelope_root=${_context_envelope_line#root=}
        _context_envelope_root_seen=1
        _context_envelope_phase=1
        ;;
      uid=*)
        [ "$_context_envelope_phase" -eq 1 ] && [ "$_context_envelope_uid_seen" -eq 0 ] || return 1
        _context_envelope_uid=${_context_envelope_line#uid=}
        case "$_context_envelope_uid" in '' | *[!0-9]*) return 1 ;; esac
        _context_envelope_uid_seen=1
        _context_envelope_phase=2
        ;;
      system=*)
        [ "$_context_envelope_phase" -eq 2 ] && [ "$_context_envelope_system_seen" -eq 0 ] || return 1
        _context_envelope_system=${_context_envelope_line#system=}
        _context_profile_registry_identity_valid "$_context_envelope_system" || return 1
        _context_envelope_system_seen=1
        _context_envelope_phase=3
        ;;
      user=*)
        [ "$_context_envelope_format_version" -eq 2 ] && [ "$_context_envelope_phase" -eq 3 ] && [ "$_context_envelope_user_seen" -eq 0 ] || return 1
        _context_envelope_user=${_context_envelope_line#user=}
        _context_user_identity_resolve "$_context_envelope_user" || return 1
        _context_envelope_user_seen=1
        _context_envelope_phase=4
        ;;
      locale=*)
        [ "$_context_envelope_format_version" -eq 2 ] && [ "$_context_envelope_phase" -eq 4 ] && [ "$_context_envelope_locale_seen" -eq 0 ] || return 1
        _context_envelope_locale=${_context_envelope_line#locale=}
        _context_locale_resolve "$_context_envelope_locale" || return 1
        _context_envelope_locale_seen=1
        _context_envelope_phase=5
        ;;
      osarch=*)
        [ "$_context_envelope_format_version" -eq 2 ] && [ "$_context_envelope_phase" -eq 5 ] && [ "$_context_envelope_osarch_seen" -eq 0 ] || return 1
        _context_envelope_osarch=${_context_envelope_line#osarch=}
        pkg_osarch_valid "$_context_envelope_osarch" || return 1
        _context_envelope_osarch_seen=1
        _context_envelope_phase=6
        ;;
      classpath-host-set=*)
        [ "$_context_envelope_classpath_seen" -eq 0 ] || return 1
        if [ "$_context_envelope_format_version" -eq 2 ]
        then
          [ "$_context_envelope_phase" -eq 6 ] || return 1
        else
          [ "$_context_envelope_phase" -eq 3 ] || return 1
        fi
        _context_envelope_classpath_host_set=${_context_envelope_line#classpath-host-set=}
        case "$_context_envelope_classpath_host_set" in 0 | 1) : ;; *) return 1 ;; esac
        _context_envelope_classpath_seen=1
        _context_envelope_phase=7
        ;;
      provider.*=*)
        [ "$_context_envelope_format_version" -eq 2 ] && [ "$_context_envelope_phase" -eq 7 ] || return 1
        _context_envelope_facility=${_context_envelope_line#provider.}
        _context_envelope_facility=${_context_envelope_facility%%=*}
        _pkg_facility_name_valid "$_context_envelope_facility" || return 1
        case "$_context_envelope_provider_seen$_context_envelope_newline" in
          *"$_context_envelope_newline$_context_envelope_facility$_context_envelope_newline"*) return 1 ;;
        esac
        _context_envelope_selector=${_context_envelope_line#*=}
        pkg_request_read _context_envelope_provider _context_envelope_provider_version _context_envelope_provider_arch "$_context_envelope_selector" || return 1
        _context_operand_append "$_context_envelope_provider_seen" "$_context_envelope_facility"
        _context_envelope_provider_seen=$_context_operand_buffer
        _context_operand_append "$_context_envelope_providers" "$_context_envelope_line"
        _context_envelope_providers=$_context_operand_buffer
        ;;
      package=*)
        [ "$_context_envelope_classpath_seen" -eq 1 ] || return 1
        if [ "$_context_envelope_format_version" -eq 2 ]
        then
          [ "$_context_envelope_phase" -eq 7 ] || [ "$_context_envelope_phase" -eq 8 ] || return 1
        else
          [ "$_context_envelope_phase" -eq 7 ] || [ "$_context_envelope_phase" -eq 8 ] || return 1
        fi
        _context_envelope_package=${_context_envelope_line#package=}
        pkg_concrete_read _context_envelope_pkg _context_envelope_package_version _context_envelope_package_osarch "$_context_envelope_package" || return 1
        [ -d "$m_PKG_DIR/$_context_envelope_package" ] && [ ! -L "$m_PKG_DIR/$_context_envelope_package" ] || return 1
        case "$_context_envelope_package_ids$_context_envelope_newline" in
          *"$_context_envelope_newline$_context_envelope_package$_context_envelope_newline"*) return 1 ;;
        esac
        _context_operand_append "$_context_envelope_packages" "pkg=$_context_envelope_package"
        _context_envelope_packages=$_context_operand_buffer
        _context_operand_append "$_context_envelope_package_ids" "$_context_envelope_package"
        _context_envelope_package_ids=$_context_operand_buffer
        _context_envelope_phase=8
        ;;
      *) return 1 ;;
    esac
  done <<EOF_CONTEXT_ENVELOPE
${m_CONTEXT_ENVELOPE}
EOF_CONTEXT_ENVELOPE
  [ "$_context_envelope_header" -eq 0 ] &&
  [ "$_context_envelope_root_seen" -eq 1 ] &&
  [ "$_context_envelope_uid_seen" -eq 1 ] &&
  [ "$_context_envelope_system_seen" -eq 1 ] &&
  [ "$_context_envelope_classpath_seen" -eq 1 ] || return 1
  [ "$_context_envelope_root" = "$m_ROOT" ] || return 1
  if [ "$_context_envelope_format_version" -eq 2 ]
  then
    [ "$_context_envelope_user_seen" -eq 1 ] &&
    [ "$_context_envelope_locale_seen" -eq 1 ] &&
    [ "$_context_envelope_osarch_seen" -eq 1 ] || return 1
  else
    _context_envelope_user=default
    _context_global_locale_resolve || return 1
    _context_envelope_locale=$_context_locale_selected
    _context_host_osarch_ensure || return 1
    _context_envelope_osarch=$m_OSARCH
  fi
  _context_envelope_current_uid=$(command -p id -u 2>/dev/null) || return 1
  [ "$_context_envelope_uid" = "$_context_envelope_current_uid" ] || return 1
  _context_profile_resolve "$_context_envelope_system" || return 1
  _context_user_identity_resolve "$_context_envelope_user" || return 1
  _context_locale_resolve "$_context_envelope_locale" || return 1
  _context_provider_pins_validate "$_context_envelope_providers" \
    "$_context_envelope_osarch" || return 1
  _context_envelope_resolved=$(_context_resolve_list '' "$_context_envelope_packages") || return 1
  [ "$_context_envelope_resolved" = "$_context_envelope_package_ids" ] || return 1
  _context_envelope_packages=$_context_envelope_resolved
  _context_commands_validate "$_context_envelope_packages" || return 1
  _context_libraries_validate "$_context_envelope_packages" || return 1

  _context_envelope_path_prefix=
  _context_envelope_classpath_prefix=
  _context_envelope_remaining=$_context_envelope_packages
  while [ -n "$_context_envelope_remaining" ]
  do
    case "$_context_envelope_remaining" in
      *"$_context_envelope_newline"*)
        _context_envelope_item=${_context_envelope_remaining%%"$_context_envelope_newline"*}
        _context_envelope_remaining=${_context_envelope_remaining#*"$_context_envelope_newline"}
        ;;
      *)
        _context_envelope_item=$_context_envelope_remaining
        _context_envelope_remaining=
        ;;
    esac
    _context_views_set "$_context_envelope_item" || return 1
    for _context_envelope_rel in "$_context_bin_rel" "$_context_lib_rel/sh"
    do
      _context_envelope_dir="$m_PKG_DIR/$_context_envelope_item/$_context_envelope_rel"
      if [ -e "$_context_envelope_dir" ] || [ -L "$_context_envelope_dir" ]
      then
        [ -d "$_context_envelope_dir" ] && [ ! -L "$_context_envelope_dir" ] || return 1
        if [ -n "$_context_envelope_path_prefix" ]; then
          _context_envelope_path_prefix="$_context_envelope_path_prefix:$_context_envelope_dir"
        else
          _context_envelope_path_prefix=$_context_envelope_dir
        fi
      fi
    done
    _context_envelope_dir="$m_PKG_DIR/$_context_envelope_item/$_context_lib_rel/java"
    if [ -e "$_context_envelope_dir" ] || [ -L "$_context_envelope_dir" ]
    then
      [ -d "$_context_envelope_dir" ] && [ ! -L "$_context_envelope_dir" ] || return 1
      if [ -n "$_context_envelope_classpath_prefix" ]; then
        _context_envelope_classpath_prefix="$_context_envelope_classpath_prefix:$_context_envelope_dir/*"
      else
        _context_envelope_classpath_prefix="$_context_envelope_dir/*"
      fi
    fi
  done
  m_STATE_SYS_DIR=$_context_profile_path
  m_STATE_USER_DIR=$_context_user_identity_resolved
  m_CONTEXT_SYSTEM_PROFILE=$_context_envelope_system
  m_CONTEXT_USER_IDENTITY=$_context_envelope_user
  m_CONTEXT_LOCALE=$_context_envelope_locale
  m_CONTEXT_OSARCH=$_context_envelope_osarch
  m_CONTEXT_PROVIDER_PINS=$_context_envelope_providers
  m_CONTEXT_PACKAGES=$_context_envelope_packages
  m_CONTEXT_PATH_PREFIX=$_context_envelope_path_prefix
  m_CONTEXT_CLASSPATH_PREFIX=$_context_envelope_classpath_prefix
  m_CONTEXT_CLASSPATH_HOST_SET=$_context_envelope_classpath_host_set
  export m_CONTEXT_SYSTEM_PROFILE m_CONTEXT_USER_IDENTITY m_CONTEXT_LOCALE
  export m_CONTEXT_OSARCH m_CONTEXT_PROVIDER_PINS m_CONTEXT_PACKAGES
  export m_CONTEXT_PATH_PREFIX m_CONTEXT_CLASSPATH_PREFIX m_CONTEXT_CLASSPATH_HOST_SET
}

_context_record_from_concretes()
{
  [ "$#" -eq 6 ] || return 2
  _context_record_system=$1
  _context_record_user=$2
  _context_record_locale=$3
  _context_record_osarch=$4
  _context_record_packages=$5
  _context_record_providers=$6
  _context_record_newline='
'
  _context_record_prefixed_packages=
  while [ -n "$_context_record_packages" ]
  do
    case "$_context_record_packages" in
      *"$_context_record_newline"*)
        _context_record_package=${_context_record_packages%%"$_context_record_newline"*}
        _context_record_packages=${_context_record_packages#*"$_context_record_newline"}
        ;;
      *) _context_record_package=$_context_record_packages; _context_record_packages= ;;
    esac
    [ -n "$_context_record_prefixed_packages" ] &&
      _context_record_prefixed_packages="$_context_record_prefixed_packages$_context_record_newline"
    _context_record_prefixed_packages="${_context_record_prefixed_packages}pkg=$_context_record_package"
  done
  _context_store_record_build "$_context_record_system" "$_context_record_user" \
    "$_context_record_locale" "$_context_record_osarch" \
    "$_context_record_prefixed_packages" "$_context_record_providers"
  _context_store_record=$CONTEXT_STORE_RECORD
}

_context_defaults_lock_cleanup()
{
  [ "${_context_store_lock_token_owned-0}" -eq 1 ] || return 0
  if [ -n "${_context_store_lock_dir-}" ] &&
     [ -f "$_context_store_lock_dir/owner" ] &&
     [ ! -L "$_context_store_lock_dir/owner" ]
  then
    IFS= read -r _context_cleanup_owner < "$_context_store_lock_dir/owner" || _context_cleanup_owner=
    if [ "$_context_cleanup_owner" = "$_context_store_lock_token_path" ]; then
      _context_store_unlock "$_context_store_lock_dir" >/dev/null 2>&1 || :
      return 0
    fi
  fi
  command -p rm -f "$_context_store_lock_token_path" 2>/dev/null || :
  _context_store_lock_token_owned=0
}

_context_operand_append()
{
  [ "$#" -eq 2 ] || return 2
  _context_operand_buffer=$1
  _context_operand_value=$2
  _context_operand_newline=$(printf '\nX')
  _context_operand_newline=${_context_operand_newline%X}
  if [ -n "$_context_operand_buffer" ]
  then
    _context_operand_buffer="$_context_operand_buffer$_context_operand_newline$_context_operand_value"
  else
    _context_operand_buffer=$_context_operand_value
  fi
}

_context_build_activation_operands()
{
  _context_requested_operands=
  _context_operand_newline=$(printf '\nX')
  _context_operand_newline=${_context_operand_newline%X}
  _context_operand_cr=$(printf '\r')
  for _context_operand
  do
    case "$_context_operand" in
      *"$_context_operand_newline"* | *"$_context_operand_cr"*)
        _context_error context-operand-invalid "$_context_operand"
        return 2
        ;;
      pkg=*)
        _context_operand_append "$_context_requested_operands" "$_context_operand"
        _context_requested_operands=$_context_operand_buffer
        ;;
      system=*)
        _context_requested_system=${_context_operand#system=}
        _context_profile_registry_identity_valid "$_context_requested_system" || {
          _context_error context-profile-invalid "$_context_requested_system"
          return 23
        }
        ;;
      user=*)
        _context_requested_user=${_context_operand#user=}
        _context_user_identity_resolve "$_context_requested_user" || {
          _context_error context-user-identity-invalid "$_context_requested_user"
          return 26
        }
        ;;
      locale=*)
        _context_requested_locale=${_context_operand#locale=}
        _context_locale_resolve "$_context_requested_locale" || {
          _context_error context-locale-invalid "$_context_requested_locale"
          return 27
        }
        ;;
      osarch=*)
        _context_requested_osarch=${_context_operand#osarch=}
        pkg_osarch_valid "$_context_requested_osarch" || {
          _context_error context-osarch-invalid "$_context_requested_osarch"
          return 28
        }
        ;;
      provider.*=*)
        _context_requested_provider_facility=${_context_operand#provider.}
        _context_requested_provider_facility=${_context_requested_provider_facility%%=*}
        _context_requested_provider_selector=${_context_operand#*=}
        _context_provider_pins_set "$_context_requested_providers" "$_context_requested_provider_facility" "$_context_requested_provider_selector" || {
          _context_error context-provider-invalid "$_context_operand"
          return 29
        }
        _context_requested_providers=$_context_provider_pins_result
        ;;
      full-context=*)
        _context_preset_name=${_context_operand#full-context=}
        _context_store_name="preset.$_context_preset_name"
        _context_store_name_valid "$_context_store_name" || {
          _context_error context-preset-name-invalid "$_context_preset_name"
          return 20
        }
        _context_store_read "$m_ROOT" "$_context_store_name"
        _context_store_status=$?
        case "$_context_store_status" in
          0) : ;;
          5)
            _context_error context-preset-unavailable "$_context_preset_name"
            return 20
            ;;
          *)
            _context_error context-preset-store-invalid "$_context_preset_name"
            return 19
            ;;
        esac
        [ -z "${CONTEXT_STORE_SYSTEM-}" ] || _context_requested_system=$CONTEXT_STORE_SYSTEM
        [ -z "${CONTEXT_STORE_USER-}" ] || _context_requested_user=$CONTEXT_STORE_USER
        [ -z "${CONTEXT_STORE_LOCALE-}" ] || _context_requested_locale=$CONTEXT_STORE_LOCALE
        [ -z "${CONTEXT_STORE_OSARCH-}" ] || _context_requested_osarch=$CONTEXT_STORE_OSARCH
        _context_preset_provider_remaining=${CONTEXT_STORE_PROVIDERS-}
        while [ -n "$_context_preset_provider_remaining" ]
        do
          case "$_context_preset_provider_remaining" in
            *"$_context_operand_newline"*)
              _context_preset_provider=${_context_preset_provider_remaining%%"$_context_operand_newline"*}
              _context_preset_provider_remaining=${_context_preset_provider_remaining#*"$_context_operand_newline"}
              ;;
            *) _context_preset_provider=$_context_preset_provider_remaining; _context_preset_provider_remaining= ;;
          esac
          _context_preset_provider_facility=${_context_preset_provider#provider.}
          _context_preset_provider_facility=${_context_preset_provider_facility%%=*}
          _context_preset_provider_selector=${_context_preset_provider#*=}
          _context_provider_pins_set "$_context_requested_providers" "$_context_preset_provider_facility" "$_context_preset_provider_selector" || return 29
          _context_requested_providers=$_context_provider_pins_result
        done
        _context_preset_operands=${CONTEXT_STORE_PACKAGES-}
        while [ -n "$_context_preset_operands" ]
        do
          case "$_context_preset_operands" in
            *"$_context_operand_newline"*)
              _context_preset_operand=${_context_preset_operands%%"$_context_operand_newline"*}
              _context_preset_operands=${_context_preset_operands#*"$_context_operand_newline"}
              ;;
            *)
              _context_preset_operand=$_context_preset_operands
              _context_preset_operands=
              ;;
          esac
          _context_operand_append "$_context_requested_operands" "$_context_preset_operand"
          _context_requested_operands=$_context_operand_buffer
        done
        ;;
      *) _context_error context-operand-invalid "$_context_operand"; return 2 ;;
    esac
  done
}

_context_prepare_packages()
(
  [ "$#" -eq 2 ] || return 2
  _context_prepared=$(_context_resolve_list "$1" "$2") || return $?
  _context_commands_validate "$_context_prepared" || return $?
  _context_libraries_validate "$_context_prepared" || return $?
  printf '%s' "$_context_prepared"
)

_context_store_set_defaults()
(
  [ "$#" -gt 0 ] || {
    _context_error context-operand-invalid "missing default selector"
    return 2
  }
  _context_store_lock_dir=
  _context_store_lock_token_path=
  _context_store_lock_token_owned=0
  trap '_context_defaults_lock_cleanup' 0
  trap 'exit 1' HUP INT TERM
  if _context_store_lock "$m_ROOT"
  then
    _context_store_lock_status=0
  else
    _context_store_lock_status=$?
  fi
  case "$_context_store_lock_status" in
    0) : ;;
    3)
      _context_error context-default-store-busy "$m_ROOT/state"
      return 22
      ;;
    *)
      _context_error context-default-store-invalid "$m_ROOT/state"
      return 19
      ;;
  esac
  _context_store_load_defaults || return $?
  _context_default_operands=$CONTEXT_STORE_PACKAGES
  _context_requested_system=${CONTEXT_STORE_SYSTEM-}
  _context_requested_user=${CONTEXT_STORE_USER-}
  _context_requested_locale=${CONTEXT_STORE_LOCALE-}
  _context_requested_osarch=${CONTEXT_STORE_OSARCH-}
  _context_requested_providers=${CONTEXT_STORE_PROVIDERS-}
  _context_requested_operands=
  _context_build_activation_operands "$@" || return $?
  if [ -n "$_context_requested_system" ]
  then
    _context_profile_resolve "$_context_requested_system" || return $?
  fi
  if [ -n "$_context_requested_user" ]
  then
    _context_user_identity_resolve "$_context_requested_user" || return 26
  fi
  if [ -n "$_context_requested_locale" ]
  then
    _context_locale_resolve "$_context_requested_locale" || return 27
  fi
  if [ -n "$_context_requested_osarch" ]
  then
    pkg_osarch_valid "$_context_requested_osarch" || return 28
  fi
  _context_host_osarch_ensure || return 28
  _context_selected_osarch=${_context_requested_osarch:-$m_OSARCH}
  _context_provider_pins_validate "$_context_requested_providers" \
    "$_context_selected_osarch" || {
      _context_error context-provider-invalid "$_context_requested_providers"
      return 29
    }
  _context_next=$(_context_prepare_packages "$_context_default_operands" "$_context_requested_operands") || return $?
  _context_record_from_concretes "$_context_requested_system" "$_context_requested_user" \
    "$_context_requested_locale" "$_context_requested_osarch" "$_context_next" \
    "$_context_requested_providers"
  _context_store_write "$m_ROOT" defaults "$_context_store_record" || {
    _context_error context-default-store-write-failed "$m_ROOT/state"
    return 21
  }
)

_context_store_define_preset()
(
  [ "$#" -ge 2 ] || return 2
  _context_store_lock_dir=
  _context_store_lock_token_path=
  _context_store_lock_token_owned=0
  trap '_context_defaults_lock_cleanup' 0
  trap 'exit 1' HUP INT TERM
  if _context_store_lock "$m_ROOT"
  then
    _context_store_lock_status=0
  else
    _context_store_lock_status=$?
  fi
  case "$_context_store_lock_status" in
    0) : ;;
    3)
      _context_error context-default-store-busy "$m_ROOT/state"
      return 22
      ;;
    *)
      _context_error context-default-store-invalid "$m_ROOT/state"
      return 19
      ;;
  esac
  _context_preset_name=$1
  _context_store_name="preset.$_context_preset_name"
  _context_store_name_valid "$_context_store_name" || {
    _context_error context-preset-name-invalid "$_context_preset_name"
    return 20
  }
  shift
  _context_requested_system=
  _context_requested_user=
  _context_requested_locale=
  _context_requested_osarch=
  _context_requested_providers=
  _context_requested_operands=
  _context_build_activation_operands "$@" || return $?
  if [ -n "$_context_requested_system" ]
  then
    _context_profile_resolve "$_context_requested_system" || return $?
  fi
  if [ -n "$_context_requested_user" ]
  then
    _context_user_identity_resolve "$_context_requested_user" || return 26
  fi
  if [ -n "$_context_requested_locale" ]
  then
    _context_locale_resolve "$_context_requested_locale" || return 27
  fi
  if [ -n "$_context_requested_osarch" ]
  then
    pkg_osarch_valid "$_context_requested_osarch" || return 28
  fi
  _context_host_osarch_ensure || return 28
  _context_selected_osarch=${_context_requested_osarch:-$m_OSARCH}
  _context_provider_pins_validate "$_context_requested_providers" \
    "$_context_selected_osarch" || {
      _context_error context-provider-invalid "$_context_requested_providers"
      return 29
    }
  _context_next=$(_context_prepare_packages '' "$_context_requested_operands") || return $?
  _context_record_from_concretes "$_context_requested_system" "$_context_requested_user" \
    "$_context_requested_locale" "$_context_requested_osarch" "$_context_next" \
    "$_context_requested_providers"
  _context_store_write "$m_ROOT" "$_context_store_name" "$_context_store_record" || {
    _context_error context-preset-store-write-failed "$_context_preset_name"
    return 21
  }
)

_context_store_delete_defaults()
(
  _context_store_lock_dir=
  _context_store_lock_token_path=
  _context_store_lock_token_owned=0
  trap '_context_defaults_lock_cleanup' 0
  trap 'exit 1' HUP INT TERM
  if _context_store_lock "$m_ROOT" existing
  then
    _context_store_lock_status=0
  else
    _context_store_lock_status=$?
  fi
  case "$_context_store_lock_status" in
    0) : ;;
    5) return 0 ;;
    3)
      _context_error context-default-store-busy "$m_ROOT/state"
      return 22
      ;;
    *)
      _context_error context-default-store-invalid "$m_ROOT/state"
      return 19
      ;;
  esac
  _context_store_delete "$m_ROOT" defaults || {
    _context_error context-default-store-invalid "$m_ROOT/state"
    return 19
  }
)

# Import only direct, validated legacy selectors. Existing account choices win,
# so repeated migration is idempotent and never overwrites a user's decision.
_context_store_migrate_legacy()
(
  [ "$#" -eq 0 ] || return 2
  _context_store_lock_dir=
  _context_store_lock_token_path=
  _context_store_lock_token_owned=0
  trap '_context_defaults_lock_cleanup' 0
  trap 'exit 1' HUP INT TERM
  if _context_store_lock "$m_ROOT"; then
    _context_migrate_lock_status=0
  else
    _context_migrate_lock_status=$?
  fi
  case "$_context_migrate_lock_status" in
    0) : ;;
    3)
      _context_error context-default-store-busy "$m_ROOT/state"
      return 22
      ;;
    *)
      _context_error context-default-store-invalid "$m_ROOT/state"
      return 19
      ;;
  esac
  _context_store_load_defaults || return $?
  _context_migrate_system=${CONTEXT_STORE_SYSTEM-}
  _context_migrate_user=${CONTEXT_STORE_USER-}
  _context_migrate_locale=${CONTEXT_STORE_LOCALE-}
  _context_migrate_osarch=${CONTEXT_STORE_OSARCH-}
  _context_migrate_packages=${CONTEXT_STORE_PACKAGES-}
  _context_migrate_providers=${CONTEXT_STORE_PROVIDERS-}
  _context_migrate_changed=0

  _context_migrate_system_link="$m_ROOT/state/system/current"
  if [ -z "$_context_migrate_system" ] && [ -L "$_context_migrate_system_link" ]
  then
    _context_migrate_system_target=$(command -p readlink "$_context_migrate_system_link" 2>/dev/null) || return 24
    case "$_context_migrate_system_target" in
      profile/*) _context_migrate_identity=${_context_migrate_system_target#profile/} ;;
      *) return 24 ;;
    esac
    case "$_context_migrate_identity" in '' | */*) return 24 ;; esac
    _context_profile_resolve "$_context_migrate_identity" || return $?
    _context_migrate_system=$_context_migrate_identity
    _context_migrate_changed=1
  fi

  _context_migrate_user_link="$m_ROOT/state/user/current"
  if [ -z "$_context_migrate_user" ] && [ -L "$_context_migrate_user_link" ]
  then
    _context_migrate_user_target=$(command -p readlink "$_context_migrate_user_link" 2>/dev/null) || return 26
    case "$_context_migrate_user_target" in '' | */* | . | ..) return 26 ;; esac
    _context_user_identity_resolve "$_context_migrate_user_target" || return 26
    [ -d "$_context_user_identity_resolved" ] && [ ! -L "$_context_user_identity_resolved" ] || return 26
    _context_migrate_user=$_context_migrate_user_target
    _context_migrate_changed=1
  fi

  _context_migrate_locale_link="$m_LANG_DIR/current"
  if [ -z "$_context_migrate_locale" ] && [ -L "$_context_migrate_locale_link" ]
  then
    _context_migrate_locale_target=$(command -p readlink "$_context_migrate_locale_link" 2>/dev/null) || return 27
    case "$_context_migrate_locale_target" in '' | */* | . | ..) return 27 ;; esac
    _context_locale_resolve "$_context_migrate_locale_target" || return 27
    _context_migrate_locale=$_context_migrate_locale_target
    _context_migrate_changed=1
  fi

  if [ -z "$_context_migrate_osarch" ]
  then
    _context_profile_resolve "$_context_migrate_system" || return $?
    _context_migrate_env_dir="$_context_profile_path/sys/environment/cache"
    _context_migrate_env_link="$_context_migrate_env_dir/env-osarch"
    if [ -L "$_context_migrate_env_link" ]
    then
      _context_migrate_env_target=$(command -p readlink "$_context_migrate_env_link" 2>/dev/null) || return 28
      case "$_context_migrate_env_target" in
        env-*) _context_migrate_osarch=${_context_migrate_env_target#env-} ;;
        *) return 28 ;;
      esac
      pkg_osarch_valid "$_context_migrate_osarch" || return 28
      [ -f "$_context_migrate_env_dir/$_context_migrate_env_target" ] &&
      [ ! -L "$_context_migrate_env_dir/$_context_migrate_env_target" ] || return 28
      _context_migrate_changed=1
    fi
  fi

  [ "$_context_migrate_changed" -eq 1 ] || return 0
  _context_record_from_concretes "$_context_migrate_system" "$_context_migrate_user" \
    "$_context_migrate_locale" "$_context_migrate_osarch" \
    "$_context_migrate_packages" "$_context_migrate_providers" || return 1
  _context_store_write "$m_ROOT" defaults "$CONTEXT_STORE_RECORD" || {
    _context_error context-default-store-write-failed "$m_ROOT/state"
    return 21
  }
)

_context_store_delete_preset()
(
  [ "$#" -eq 1 ] || return 2
  _context_store_lock_dir=
  _context_store_lock_token_path=
  _context_store_lock_token_owned=0
  trap '_context_defaults_lock_cleanup' 0
  trap 'exit 1' HUP INT TERM
  if _context_store_lock "$m_ROOT" existing
  then
    _context_store_lock_status=0
  else
    _context_store_lock_status=$?
  fi
  case "$_context_store_lock_status" in
    0) : ;;
    5) return 0 ;;
    3)
      _context_error context-default-store-busy "$m_ROOT/state"
      return 22
      ;;
    *)
      _context_error context-default-store-invalid "$m_ROOT/state"
      return 19
      ;;
  esac
  _context_store_name="preset.$1"
  _context_store_name_valid "$_context_store_name" || {
    _context_error context-preset-name-invalid "$1"
    return 20
  }
  _context_store_delete "$m_ROOT" "$_context_store_name" || {
    _context_error context-preset-store-invalid "$1"
    return 19
  }
)

# Apply only after resolution; caller PATH and active selection remain unchanged
# on invalid operands, missing concretes, or a lost PATH ownership marker.
context()
{
  [ -n "${m_ROOT-}" ] && [ -n "${m_PKG_DIR-}" ] || {
    _context_error context-runtime-unavailable m_ROOT
    return 1
  }
  case "$m_PKG_DIR" in
    *:*) _context_error context-path-unsupported "$m_PKG_DIR"; return 7 ;;
  esac

  case "${1-}" in
    --clear-defaults)
      [ "$#" -eq 1 ] || { _context_error context-operand-invalid --clear-defaults; return 2; }
      _context_store_delete_defaults
      return $?
      ;;
    --migrate-legacy)
      [ "$#" -eq 1 ] || { _context_error context-operand-invalid --migrate-legacy; return 2; }
      _context_store_migrate_legacy
      return $?
      ;;
    --set-defaults)
      shift
      _context_store_set_defaults "$@"
      return $?
      ;;
    --define-preset)
      [ "$#" -ge 3 ] || { _context_error context-operand-invalid --define-preset; return 2; }
      _context_preset_name=$2
      shift 2
      _context_store_define_preset "$_context_preset_name" "$@"
      return $?
      ;;
    --delete-preset)
      [ "$#" -eq 2 ] || { _context_error context-operand-invalid --delete-preset; return 2; }
      _context_store_delete_preset "$2"
      return $?
      ;;
  esac

  _context_store_load_defaults || return $?
  _context_host_osarch_ensure || {
    _context_error context-osarch-unavailable m_OSARCH
    return 28
  }
  _context_default_operands=$CONTEXT_STORE_PACKAGES
  _context_requested_system=$CONTEXT_STORE_SYSTEM
  _context_requested_user=${CONTEXT_STORE_USER:-default}
  _context_requested_locale=${CONTEXT_STORE_LOCALE-}
  if [ -z "$_context_requested_locale" ]
  then
    _context_global_locale_resolve || {
      _context_error context-locale-invalid "$m_LANG_CURRENT_DIR"
      return 27
    }
    _context_requested_locale=$_context_locale_selected
  fi
  _context_requested_osarch=${CONTEXT_STORE_OSARCH:-$m_OSARCH}
  _context_requested_providers=${CONTEXT_STORE_PROVIDERS-}
  _context_requested_operands=
  if [ "$#" -gt 0 ]
  then
    _context_build_activation_operands "$@" || return $?
  fi

  # Resolve the persisted baseline and ordered overrides before touching shell state.
  _context_profile_resolve "$_context_requested_system" || return $?
  _context_selected_system=$_context_profile_selected
  _context_user_identity_resolve "$_context_requested_user" || {
    _context_error context-user-identity-invalid "$_context_requested_user"
    return 26
  }
  _context_selected_user=$_context_requested_user
  _context_locale_resolve "$_context_requested_locale" || {
    _context_error context-locale-invalid "$_context_requested_locale"
    return 27
  }
  _context_selected_locale=$_context_locale_selected
  pkg_osarch_valid "$_context_requested_osarch" || {
    _context_error context-osarch-invalid "$_context_requested_osarch"
    return 28
  }
  _context_selected_osarch=$_context_requested_osarch
  _context_provider_pins_validate "$_context_requested_providers" \
    "$_context_selected_osarch" || {
      _context_error context-provider-invalid "$_context_requested_providers"
      return 29
    }
  _context_next="$(_context_prepare_packages "$_context_default_operands" "$_context_requested_operands")" || return $?
  _context_path_unapply "${PATH-}" "${m_CONTEXT_PATH_PREFIX-}" || return $?
  _context_host_path=$_context_path_base

  _context_classpath_host_set=${CLASSPATH+x}
  if [ -n "${m_CONTEXT_CLASSPATH_PREFIX-}" ]
  then
    [ "${CLASSPATH+x}" = x ] || {
      _context_error context-classpath-modified unset
      return 15
    }
    _context_classpath_host_set=${m_CONTEXT_CLASSPATH_HOST_SET-}
  fi
  _context_path_unapply "${CLASSPATH-}" "${m_CONTEXT_CLASSPATH_PREFIX-}" CLASSPATH || return 15
  _context_host_classpath=$_context_path_base
  # Retain non-context classpath edits made after an initially unset value.
  [ -z "$_context_host_classpath" ] || _context_classpath_host_set=x
  _context_envelope_host_set=0
  [ -n "$_context_classpath_host_set" ] && _context_envelope_host_set=1

  _context_commands_validate "$_context_next" || return $?
  _context_libraries_validate "$_context_next" || return $?

  _context_next_path_prefix=
  _context_next_classpath_prefix=
  _context_remaining=$_context_next
  _context_newline='
'
  while [ -n "$_context_remaining" ]
  do
    case "$_context_remaining" in
      *"$_context_newline"*)
        _context_item=${_context_remaining%%"$_context_newline"*}
        _context_remaining=${_context_remaining#*"$_context_newline"}
        ;;
      *)
        _context_item=$_context_remaining
        _context_remaining=
        ;;
    esac

    # Preserve one selected concrete across executable and library views.
    _context_views_set "$_context_item" || {
      _context_error context-package-schema-invalid "$_context_item"
      return 8
    }
    _context_selected_bin=$_context_bin_rel
    _context_selected_lib=$_context_lib_rel
    for _context_kind in "$_context_selected_bin" "$_context_selected_lib/sh"
    do
      _context_dir="$m_PKG_DIR/$_context_item/$_context_kind"
      if [ ! -e "$_context_dir" ] && [ ! -L "$_context_dir" ]
      then
        continue
      fi
      [ -d "$_context_dir" ] && [ ! -L "$_context_dir" ] || {
        _context_error context-view-disappeared "$_context_dir"
        return 8
      }
      if [ -n "$_context_next_path_prefix" ]
      then
        _context_next_path_prefix="$_context_next_path_prefix:$_context_dir"
      else
        _context_next_path_prefix=$_context_dir
      fi
    done

    _context_dir="$m_PKG_DIR/$_context_item/$_context_selected_lib/java"
    if [ -e "$_context_dir" ] || [ -L "$_context_dir" ]
    then
      [ -d "$_context_dir" ] && [ ! -L "$_context_dir" ] || {
        _context_error context-view-disappeared "$_context_dir"
        return 8
      }
      if [ -n "$_context_next_classpath_prefix" ]
      then
        _context_next_classpath_prefix="$_context_next_classpath_prefix:$_context_dir/*"
      else
        _context_next_classpath_prefix="$_context_dir/*"
      fi
    fi
  done

  _context_envelope_next=$(_context_envelope_build "$_context_selected_system" "$_context_selected_user" \
    "$_context_selected_locale" "$_context_selected_osarch" "$_context_requested_providers" \
    "$_context_next" "$_context_envelope_host_set") || {
    _context_error context-envelope-build-failed "$_context_selected_system"
    return 25
  }

  # Readonly shell variables can abort a POSIX shell on assignment. Probe
  # writability in subshells so an abort cannot partially update the caller.
  ( PATH="${PATH-}" ) 2>/dev/null || {
    _context_error context-path-readonly PATH
    return 16
  }
  ( CLASSPATH="${CLASSPATH-}" ) 2>/dev/null || {
    _context_error context-classpath-readonly CLASSPATH
    return 17
  }
  ( m_STATE_SYS_DIR="${m_STATE_SYS_DIR-}" ) 2>/dev/null || {
    _context_error context-state-readonly m_STATE_SYS_DIR
    return 16
  }
  ( m_STATE_USER_DIR="${m_STATE_USER_DIR-}" ) 2>/dev/null || {
    _context_error context-state-readonly m_STATE_USER_DIR
    return 16
  }
  ( m_CONTEXT_ENVELOPE="${m_CONTEXT_ENVELOPE-}" ) 2>/dev/null || {
    _context_error context-envelope-readonly m_CONTEXT_ENVELOPE
    return 16
  }
  ( m_CONTEXT_SYSTEM_PROFILE="${m_CONTEXT_SYSTEM_PROFILE-}" ) 2>/dev/null || {
    _context_error context-state-readonly m_CONTEXT_SYSTEM_PROFILE
    return 16
  }
  ( m_CONTEXT_USER_IDENTITY="${m_CONTEXT_USER_IDENTITY-}" ) 2>/dev/null || {
    _context_error context-state-readonly m_CONTEXT_USER_IDENTITY
    return 16
  }
  ( m_CONTEXT_LOCALE="${m_CONTEXT_LOCALE-}" ) 2>/dev/null || {
    _context_error context-state-readonly m_CONTEXT_LOCALE
    return 16
  }
  ( m_CONTEXT_OSARCH="${m_CONTEXT_OSARCH-}" ) 2>/dev/null || {
    _context_error context-state-readonly m_CONTEXT_OSARCH
    return 16
  }
  ( m_CONTEXT_PROVIDER_PINS="${m_CONTEXT_PROVIDER_PINS-}" ) 2>/dev/null || {
    _context_error context-state-readonly m_CONTEXT_PROVIDER_PINS
    return 16
  }

  # Shell state changes are confined to this final application stage.
  if [ -n "$_context_next_path_prefix" ]
  then
    PATH="$_context_next_path_prefix${_context_host_path:+:$_context_host_path}"
  else
    PATH=$_context_host_path
  fi
  export PATH

  if [ -n "$_context_next_classpath_prefix" ]
  then
    if [ -n "$_context_classpath_host_set" ]
    then
      CLASSPATH="$_context_next_classpath_prefix:$_context_host_classpath"
    else
      CLASSPATH=$_context_next_classpath_prefix
    fi
    export CLASSPATH
  elif [ -n "$_context_classpath_host_set" ]
  then
    CLASSPATH=$_context_host_classpath
    export CLASSPATH
  else
    unset CLASSPATH
  fi

  m_CONTEXT_PACKAGES=$_context_next
  m_CONTEXT_SYSTEM_PROFILE=$_context_selected_system
  m_CONTEXT_USER_IDENTITY=$_context_selected_user
  m_CONTEXT_LOCALE=$_context_selected_locale
  m_CONTEXT_OSARCH=$_context_selected_osarch
  m_CONTEXT_PROVIDER_PINS=$_context_requested_providers
  m_STATE_SYS_DIR="$_context_profile_path"
  m_STATE_USER_DIR="$_context_user_identity_resolved"
  m_CONTEXT_ENVELOPE=$_context_envelope_next
  m_CONTEXT_ENVELOPE_VALIDATED=1
  export m_CONTEXT_ENVELOPE
  export m_CONTEXT_ENVELOPE_VALIDATED
  export m_CONTEXT_SYSTEM_PROFILE m_CONTEXT_USER_IDENTITY m_CONTEXT_LOCALE
  export m_CONTEXT_OSARCH m_CONTEXT_PROVIDER_PINS
  m_CONTEXT_PATH_PREFIX=$_context_next_path_prefix
  m_CONTEXT_CLASSPATH_PREFIX=$_context_next_classpath_prefix
  m_CONTEXT_CLASSPATH_HOST_SET=$_context_classpath_host_set
  export m_CONTEXT_PACKAGES m_CONTEXT_PATH_PREFIX m_CONTEXT_CLASSPATH_PREFIX m_CONTEXT_CLASSPATH_HOST_SET

  unset _context_next _context_remaining _context_newline _context_item
  unset _context_kind _context_dir _context_next_path_prefix
  unset _context_next_classpath_prefix _context_host_path _context_host_classpath
  unset _context_classpath_host_set _context_path_base
  unset _context_unapply_path _context_unapply_prefix _context_unapply_wrapped
  unset _context_unapply_marker _context_unapply_before _context_unapply_after
  return 0
}
