loadsyslib "pkg/pkg-common"

_context_error()
{
  [ "$#" -eq 2 ] || return 2
  log error execution "$1" operation context value "$2"
}

# Read only the stable mode and numeric owner fields from POSIX ls output.
# Paths and all selections remain data; no preference file is sourced.
_context_fs_metadata()
(
  [ "$#" -eq 1 ] || return 2
  _context_metadata_path=$1
  [ ! -L "$_context_metadata_path" ] || return 1
  set -f
  set -- $(LC_ALL=C command -p ls -ldn "$_context_metadata_path" 2>/dev/null) || return 1
  [ "$#" -ge 4 ] || return 1
  case "$1" in
    ??????????) : ;;
    *) return 1 ;;
  esac
  [ "${#1}" -eq 10 ] || return 1
  printf '%s\n%s\n' "$1" "$3"
)

_context_uid()
{
  _context_effective_uid=$(command -p id -u 2>/dev/null) || return 1
  case "$_context_effective_uid" in
    '' | *[!0-9]*) return 1 ;;
  esac
}

_context_state_root_validate()
(
  [ "$#" -eq 1 ] || return 2
  _context_state_root=$1
  [ -d "$_context_state_root" ] && [ ! -L "$_context_state_root" ] || return 1
  _context_state_metadata=$(_context_fs_metadata "$_context_state_root") || return 1
  _context_state_mode=${_context_state_metadata%%
*}
  _context_state_uid=${_context_state_metadata#*
}
  case "$_context_state_mode" in
    d?????????) : ;;
    *) return 1 ;;
  esac
  _context_uid || return 1
  { [ "$_context_state_uid" = 0 ] || [ "$_context_state_uid" = "$_context_effective_uid" ]; } || return 1
  [ "$(printf '%s' "$_context_state_mode" | command -p cut -c6)" != w ] &&
  [ "$(printf '%s' "$_context_state_mode" | command -p cut -c9)" != w ]
)

_context_private_dir_validate()
(
  [ "$#" -eq 2 ] || return 2
  _context_private_dir=$1
  _context_expected_uid=$2
  [ -d "$_context_private_dir" ] && [ ! -L "$_context_private_dir" ] || return 1
  _context_private_metadata=$(_context_fs_metadata "$_context_private_dir") || return 1
  _context_private_mode=${_context_private_metadata%%
*}
  _context_private_uid=${_context_private_metadata#*
}
  [ "$_context_private_mode" = drwx------ ] &&
  [ "$_context_private_uid" = "$_context_expected_uid" ]
)

_context_private_file_validate()
(
  [ "$#" -eq 2 ] || return 2
  _context_private_file=$1
  _context_expected_uid=$2
  [ -f "$_context_private_file" ] && [ ! -L "$_context_private_file" ] || return 1
  _context_private_metadata=$(_context_fs_metadata "$_context_private_file") || return 1
  _context_private_mode=${_context_private_metadata%%
*}
  _context_private_uid=${_context_private_metadata#*
}
  [ "$_context_private_mode" = -rw------- ] &&
  [ "$_context_private_uid" = "$_context_expected_uid" ]
)

_context_presets_directory()
(
  [ "$#" -eq 1 ] || return 2
  _context_create=$1
  _context_uid || return 1
  _context_store_dir=$(_context_store_directory "$_context_create") || return 1
  [ -n "$_context_store_dir" ] || { printf '%s\n' ''; return 0; }
  _context_presets_dir="$_context_store_dir/presets"
  if [ ! -e "$_context_presets_dir" ] && [ ! -L "$_context_presets_dir" ]
  then
    [ "$_context_create" = yes ] || { printf '%s\n' ''; return 0; }
    (umask 077; command -p mkdir -m 700 "$_context_presets_dir") 2>/dev/null || return 1
  fi
  _context_private_dir_validate "$_context_presets_dir" "$_context_effective_uid" || return 1
  printf '%s\n' "$_context_presets_dir"
)

# Return the preference directory only after validating the global state root
# and every existing account-owned path component. Missing paths are reported
# to the caller without creating them on read-only initialization.
_context_store_directory()
(
  [ "$#" -eq 1 ] || return 2
  _context_create=$1
  _context_uid || return 1
  _context_store_state=$m_ROOT/state
  _context_state_root_validate "$_context_store_state" || return 1
  _context_store_account="$_context_store_state/$_context_effective_uid"
  _context_store_dir="$_context_store_account/context"

  if [ ! -e "$_context_store_account" ] && [ ! -L "$_context_store_account" ]
  then
    [ "$_context_create" = yes ] || { printf '%s\n' ''; return 0; }
    (umask 077; command -p mkdir -m 700 "$_context_store_account") 2>/dev/null || return 1
  fi
  _context_private_dir_validate "$_context_store_account" "$_context_effective_uid" || return 1

  if [ ! -e "$_context_store_dir" ] && [ ! -L "$_context_store_dir" ]
  then
    [ "$_context_create" = yes ] || { printf '%s\n' ''; return 0; }
    (umask 077; command -p mkdir -m 700 "$_context_store_dir") 2>/dev/null || return 1
  fi
  _context_private_dir_validate "$_context_store_dir" "$_context_effective_uid" || return 1
  printf '%s\n' "$_context_store_dir"
)

_context_store_file_validate()
{
  [ "$#" -eq 1 ] || return 2
  _context_store_file=$1
  _context_uid || return 1
  [ ! -e "$_context_store_file" ] && [ ! -L "$_context_store_file" ] && return 0
  _context_private_file_validate "$_context_store_file" "$_context_effective_uid"
}

_context_store_write()
(
  [ "$#" -ge 2 ] || return 2
  _context_store_target=$1
  _context_store_append=${2-}
  [ "$#" -ge 3 ] || return 2
  shift
  shift
  _context_store_directory=$(_context_store_directory yes) || return 1
  [ -n "$_context_store_directory" ] || return 1
  _context_uid || return 1
  _context_private_dir_validate "${_context_store_target%/*}" "$_context_effective_uid" || return 1
  _context_store_file_validate "$_context_store_target" || return 1
  _context_store_tmp="$_context_store_target.tmp.$$"
  (umask 077; set -C; : > "$_context_store_tmp") 2>/dev/null || return 1
  command -p chmod 600 "$_context_store_tmp" || {
    command -p rm -f "$_context_store_tmp"
    return 1
  }
  if [ "$_context_store_append" = append ] && [ -f "$_context_store_target" ]
  then
    command -p cat "$_context_store_target" > "$_context_store_tmp" || {
      command -p rm -f "$_context_store_tmp"
      return 1
    }
  else
    printf '%s\n' m-context-v1 > "$_context_store_tmp" || {
      command -p rm -f "$_context_store_tmp"
      return 1
    }
  fi
  {
    for _context_store_line
    do
      [ -n "$_context_store_line" ] || exit 1
      printf '%s\n' "$_context_store_line" || exit 1
    done
  } >> "$_context_store_tmp" || {
    command -p rm -f "$_context_store_tmp"
    return 1
  }
  _context_store_uid=$(_context_uid && printf '%s' "$_context_effective_uid") || {
    command -p rm -f "$_context_store_tmp"
    return 1
  }
  _context_private_file_validate "$_context_store_tmp" "$_context_store_uid" || {
    command -p rm -f "$_context_store_tmp"
    return 1
  }
  command -p mv -f "$_context_store_tmp" "$_context_store_target" || {
    command -p rm -f "$_context_store_tmp"
    return 1
  }
)

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

# Fold one already-tokenized selection into the candidate concrete list.
_context_resolve_one()
{
  [ "$#" -eq 1 ] || return 2
  _context_operand=$1
  case "$_context_operand" in
    pkg=*) _context_requested=${_context_operand#pkg=} ;;
    preset=*)
      [ "${_context_from_preset-}" != yes ] || {
        _context_error context-preset-recursive "${_context_operand#preset=}"
        return 2
      }
      _context_preset_name=${_context_operand#preset=}
      case "$_context_preset_name" in
        '' | [!a-zA-Z0-9]* | *[!a-zA-Z0-9._-]*)
          _context_error context-preset-name-invalid "$_context_preset_name"
          return 2
          ;;
      esac
      _context_presets_dir=$(_context_presets_directory no) || {
        _context_error context-preset-activation-storage-unavailable "$m_ROOT/state"
        return 29
      }
      [ -n "$_context_presets_dir" ] || {
        _context_error context-preset-unavailable "$_context_preset_name"
        return 20
      }
      _context_preset_file="$_context_presets_dir/$_context_preset_name"
      _context_store_file_validate "$_context_preset_file" || {
        _context_error context-preset-record-invalid "$_context_preset_name"
        return 36
      }
      [ -f "$_context_preset_file" ] || {
        _context_error context-preset-unavailable "$_context_preset_name"
        return 20
      }
      _context_resolve_record "$_context_preset_file" preset || return $?
      return 0
      ;;
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
}

# Read and validate a versioned data-only preference or preset record.
_context_resolve_record()
{
  [ "$#" -eq 2 ] || return 2
  _context_record_file=$1
  _context_record_kind=$2
  _context_store_file_validate "$_context_record_file" || {
    _context_error context-record-invalid "$_context_record_file"
    return 21
  }
  [ -f "$_context_record_file" ] || {
    _context_error context-record-invalid "$_context_record_file"
    return 21
  }
  _context_record_header=
  while IFS= read -r _context_record_line || [ -n "$_context_record_line" ]
  do
    if [ -z "$_context_record_header" ]
    then
      [ "$_context_record_line" = m-context-v1 ] || {
        _context_error context-record-version-invalid "$_context_record_file"
        return 22
      }
      _context_record_header=yes
      continue
    fi
    [ -n "$_context_record_line" ] || {
      _context_error context-record-line-invalid "$_context_record_file"
      return 23
    }
    case "$_context_record_line" in
      pkg=*) : ;;
      *)
        _context_error context-record-line-invalid "$_context_record_file"
        return 23
        ;;
    esac
    _context_from_preset=yes
    _context_resolve_one "$_context_record_line" || return $?
    _context_from_preset=
  done < "$_context_record_file"
  [ -n "$_context_record_header" ] || {
    _context_error context-record-empty "$_context_record_file"
    return 24
  }
}

# Compute the active, most-recent-first concrete list without modifying the
# calling shell. A bare invocation starts from the account defaults; explicit
# operands replace the current selection incrementally.
_context_resolve()
(
  loadsyslib "osarch" || return 1
  _context_newline='
'
  if [ "$#" -eq 0 ]
  then
    _context_resolved=
    _context_store_dir=$(_context_store_directory no) || {
      _context_error context-preferences-unavailable "$m_ROOT/state"
      return 19
    }
    if [ -n "$_context_store_dir" ] &&
       { [ -e "$_context_store_dir/defaults" ] || [ -L "$_context_store_dir/defaults" ]; }
    then
      _context_resolve_record "$_context_store_dir/defaults" defaults || return $?
    fi
  else
    _context_resolved=${m_CONTEXT_PACKAGES-}
    for _context_operand
    do
      _context_resolve_one "$_context_operand" || return $?
    done
  fi

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

  case "$#:${1-}:${2-}" in
    2:defaults:clear)
      _context_store_dir=$(_context_store_directory no) || {
        _context_error context-defaults-clear-storage-unavailable "$m_ROOT/state"
        return 30
      }
      [ -n "$_context_store_dir" ] || return 0
      _context_store_file="$_context_store_dir/defaults"
      _context_store_file_validate "$_context_store_file" || {
        _context_error context-defaults-record-invalid "$_context_store_file"
        return 31
      }
      if [ -e "$_context_store_file" ] || [ -L "$_context_store_file" ]
      then
        command -p rm -f "$_context_store_file" || {
          _context_error context-defaults-clear-failed "$_context_store_file"
          return 25
        }
      fi
      return 0
      ;;
    3:preset:clear)
      _context_preset_name=$3
      case "$_context_preset_name" in
        '' | [!a-zA-Z0-9]* | *[!a-zA-Z0-9._-]*)
          _context_error context-preset-name-invalid "$_context_preset_name"
          return 2
          ;;
      esac
      _context_presets_dir=$(_context_presets_directory no) || {
        _context_error context-preset-clear-storage-unavailable "$m_ROOT/state"
        return 32
      }
      [ -n "$_context_presets_dir" ] || return 0
      _context_store_file="$_context_presets_dir/$_context_preset_name"
      _context_store_file_validate "$_context_store_file" || {
        _context_error context-preset-clear-record-invalid "$_context_preset_name"
        return 33
      }
      if [ -e "$_context_store_file" ] || [ -L "$_context_store_file" ]
      then
        command -p rm -f "$_context_store_file" || {
          _context_error context-preset-clear-failed "$_context_preset_name"
          return 26
        }
      fi
      return 0
      ;;
    1:reset:)
      _context_next=
      ;;
    *)
      case "${1-}:${2-}" in
        defaults:set)
          [ "$#" -ge 3 ] || {
            _context_error context-operand-invalid defaults-set
            return 2
          }
          shift 2
          _context_candidate="$(m_CONTEXT_PACKAGES= _context_resolve "$@")" || return $?
          _context_store_dir=$(_context_store_directory yes) || {
            _context_error context-defaults-set-storage-unavailable "$m_ROOT/state"
            return 34
          }
          [ -n "$_context_store_dir" ] || {
            _context_error context-defaults-set-storage-unavailable "$m_ROOT/state"
            return 34
          }
          if [ -e "$_context_store_dir/defaults" ] || [ -L "$_context_store_dir/defaults" ]
          then
            _context_existing="$(_context_resolve)" || return $?
          fi
          _context_store_write "$_context_store_dir/defaults" append "$@" || {
            _context_error context-preferences-write-failed "$_context_store_dir/defaults"
            return 27
          }
          return 0
          ;;
        preset:set)
          [ "$#" -ge 4 ] || {
            _context_error context-operand-invalid preset-set
            return 2
          }
          _context_preset_name=$3
          case "$_context_preset_name" in
            '' | [!a-zA-Z0-9]* | *[!a-zA-Z0-9._-]*)
              _context_error context-preset-name-invalid "$_context_preset_name"
              return 2
              ;;
          esac
          shift 3
          _context_candidate="$(m_CONTEXT_PACKAGES= _context_resolve "$@")" || return $?
          _context_presets_dir=$(_context_presets_directory yes) || {
            _context_error context-preset-set-storage-unavailable "$m_ROOT/state"
            return 35
          }
          [ -n "$_context_presets_dir" ] || {
            _context_error context-preset-set-storage-unavailable "$m_ROOT/state"
            return 35
          }
          _context_store_write "$_context_presets_dir/$_context_preset_name" replace "$@" || {
            _context_error context-preset-write-failed "$_context_preset_name"
            return 28
          }
          return 0
          ;;
        *) _context_next="$(_context_resolve "$@")" || return $? ;;
      esac
      ;;
  esac

  # Resolve and validate both lookup surfaces before touching the shell.
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
