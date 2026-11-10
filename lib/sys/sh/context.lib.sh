loadsyslib "pkg/pkg-common"
loadsyslib "context-store"
loadsyslib "context-profile-registry"

_context_error()
{
  [ "$#" -eq 2 ] || return 2
  log error execution "$1" operation context value "$2"
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
  loadsyslib "osarch" || return 1

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
      CONTEXT_STORE_PACKAGES=
      return 0
      ;;
    *)
      _context_error context-default-store-invalid "$m_ROOT/state"
      return 19
      ;;
  esac
}

_context_record_from_concretes()
{
  [ "$#" -eq 1 ] || return 2
  _context_record_items=$1
  _context_record_newline=$(printf '\nX')
  _context_record_newline=${_context_record_newline%X}
  _context_store_record=m-context-record-v1
  while [ -n "$_context_record_items" ]
  do
    case "$_context_record_items" in
      *"$_context_record_newline"*)
        _context_record_item=${_context_record_items%%"$_context_record_newline"*}
        _context_record_items=${_context_record_items#*"$_context_record_newline"}
        ;;
      *)
        _context_record_item=$_context_record_items
        _context_record_items=
        ;;
    esac
    _context_store_record="$_context_store_record$_context_record_newline"pkg=$_context_record_item
  done
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

_context_build_pkg_operands()
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
      pkg=*) _context_operand_append "$_context_requested_operands" "$_context_operand"; _context_requested_operands=$_context_operand_buffer ;;
      *) _context_error context-operand-invalid "$_context_operand"; return 2 ;;
    esac
  done
  [ -n "$_context_requested_operands" ] || {
    _context_error context-operand-invalid "missing package selector"
    return 2
  }
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
        _context_preset_operands=$CONTEXT_STORE_PACKAGES
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
  _context_build_pkg_operands "$@" || return $?
  _context_next=$(_context_prepare_packages "$_context_default_operands" "$_context_requested_operands") || return $?
  _context_record_from_concretes "$_context_next"
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
  _context_build_pkg_operands "$@" || return $?
  _context_next=$(_context_prepare_packages '' "$_context_requested_operands") || return $?
  _context_record_from_concretes "$_context_next"
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
  _context_default_operands=$CONTEXT_STORE_PACKAGES
  if [ "$#" -gt 0 ]
  then
    _context_build_activation_operands "$@" || return $?
  else
    _context_requested_operands=
  fi

  # Resolve the persisted baseline and ordered overrides before touching shell state.
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
  m_CONTEXT_PATH_PREFIX=$_context_next_path_prefix
  m_CONTEXT_CLASSPATH_PREFIX=$_context_next_classpath_prefix
  m_CONTEXT_CLASSPATH_HOST_SET=$_context_classpath_host_set

  unset _context_next _context_remaining _context_newline _context_item
  unset _context_kind _context_dir _context_next_path_prefix
  unset _context_next_classpath_prefix _context_host_path _context_host_classpath
  unset _context_classpath_host_set _context_path_base
  unset _context_unapply_path _context_unapply_prefix _context_unapply_wrapped
  unset _context_unapply_marker _context_unapply_before _context_unapply_after
  return 0
}
