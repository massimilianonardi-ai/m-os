loadsyslib "pkg/pkg-common"

_context_error()
{
  [ "$#" -eq 2 ] || return 2
  log error execution "$1" operation context value "$2"
}

# Compute the active, most-recent-first concrete list without modifying the
# calling shell. The caller applies it only after all checks succeed.
_context_resolve()
(
  if [ "$#" -eq 0 ]
  then
    return 0
  fi

  _context_resolved=${m_CONTEXT_PACKAGES-}
  _context_newline='
'

  for _context_operand
  do
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
    if [ ! -d "$_context_concrete" ] || [ -L "$_context_concrete" ] ||
       [ ! -d "$_context_concrete/cmd" ] || [ -L "$_context_concrete/cmd" ]
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
  [ "$#" -eq 2 ] || return 2
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
    *) _context_error context-path-modified "$_context_unapply_prefix"; return 6 ;;
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

    for _context_scan_command in "$m_PKG_DIR/$_context_scan_concrete/cmd/"*
    do
      [ -e "$_context_scan_command" ] || [ -L "$_context_scan_command" ] || continue
      [ -f "$_context_scan_command" ] && [ -x "$_context_scan_command" ] || {
        _context_error context-command-invalid "$_context_scan_command"
        return 9
      }
      _context_scan_name=${_context_scan_command##*/}

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

  _context_next="$( _context_resolve "$@" )" || return $?
  _context_path_unapply "${PATH-}" "${m_CONTEXT_PATH_PREFIX-}" || return $?
  _context_commands_validate "$_context_next" || return $?

  _context_next_prefix=
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

    _context_dir="$m_PKG_DIR/$_context_item/cmd"
    if [ ! -d "$_context_dir" ] || [ -L "$_context_dir" ]
    then
      _context_error context-concrete-disappeared "$_context_item"
      return 8
    fi
    if [ -n "$_context_next_prefix" ]
    then
      _context_next_prefix="$_context_next_prefix:$_context_dir"
    else
      _context_next_prefix=$_context_dir
    fi
  done

  if [ -n "$_context_next_prefix" ]
  then
    PATH="$_context_next_prefix${_context_path_base:+:$_context_path_base}"
  else
    PATH=$_context_path_base
  fi
  export PATH
  m_CONTEXT_PACKAGES=$_context_next
  m_CONTEXT_PATH_PREFIX=$_context_next_prefix

  unset _context_next _context_next_prefix _context_remaining _context_newline
  unset _context_item _context_dir _context_path_base
  unset _context_unapply_path _context_unapply_prefix _context_unapply_wrapped
  unset _context_unapply_marker _context_unapply_before _context_unapply_after
  return 0
}
