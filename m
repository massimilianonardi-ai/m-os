#!/bin/sh

#-------------------------------------------------------------------------------
# FUNCTIONS
#-------------------------------------------------------------------------------

readpathce()
{
  [ "$#" -eq 2 ] && [ -n "$1" ] && [ -n "$2" ] && [ "$1" != "PATH" ] || return 1

  case "$1" in "" | [0-9]* | *[!a-zA-Z0-9_]*) return 2 ;; esac

  eval $1=''

  set -- "$1" "$(
    set -eu
    shift
    if [ "${1#*/}" != "$1" ]
    then
      cmd="$1"
    else
      cmd="$(command -v -- "$1" 2>/dev/null; printf -- '%s' "x")"; cmd="${cmd%
x}"
    fi
    [ -e "$cmd" ] || exit 1
    cmd="$(command -p -- realpath -- "$cmd" 2>/dev/null; printf -- '%s' "x")"
    cmd="${cmd%
x}"
    [ -e "$cmd" ] || exit 1
    printf -- '%s' "${cmd}x"
  )"

  set -- "$1" "${2%x}"
  [ -n "$2" ] || return 3

  eval $1='$2'
}

export_readonly()
{
  while [ "$#" -gt "0" ]
  do
    export -- "$1" || return 1
    readonly -- "$1" || return 2
    shift
  done
}

#-------------------------------------------------------------------------------
# ROOT RESOLUTION
#-------------------------------------------------------------------------------

readpathce "m_BOOTSTRAP_BIN" "$0" && [ -f "$m_BOOTSTRAP_BIN" ] || { printf -- '%s\n' 'bootstrap bin resolution error' >&2; exit 1; }

m_ROOT=${m_BOOTSTRAP_BIN%/*}
[ -n "$m_ROOT" ] || m_ROOT=/

(cd -- "$m_ROOT" 2>/dev/null) || { printf -- '%s\n' 'bootstrap dir error' >&2; exit 1; }

export_readonly m_BOOTSTRAP_BIN m_ROOT

#-------------------------------------------------------------------------------
# SYSTEM VARIABLES
#-------------------------------------------------------------------------------

export_readonly m_BIN_DIR="$m_ROOT/bin"
export_readonly m_BIN_SYS_DIR="$m_BIN_DIR/sys"
export_readonly m_BIN_SYS_OSARCH_DIR="$m_BIN_DIR/sys-osarch"
export_readonly m_BIN_EXT_DIR="$m_BIN_DIR/ext"
export_readonly m_BIN_EXT_OSARCH_DIR="$m_BIN_DIR/ext-osarch"
export_readonly m_LIB_DIR="$m_ROOT/lib"
export_readonly m_PKG_DIR="$m_ROOT/pkg"
export_readonly m_RES_DIR="$m_ROOT/res"
export_readonly m_LANG_DIR="$m_RES_DIR/sys/lang"
export_readonly m_SRC_DIR="$m_ROOT/src"

export_readonly PAGER="pager"

export_readonly m_LANGUAGE_FALLBACK="en_US"
export_readonly m_TEXT_ENCODING="UTF-8"
export_readonly m_LANG_CURRENT_DIR="$m_LANG_DIR/current"
export_readonly m_LANG_FALLBACK_DIR="$m_LANG_DIR/$m_LANGUAGE_FALLBACK"

export_readonly m_STATE_DIR="$m_ROOT/state"
export_readonly m_STATE_SYS_DIR="$m_STATE_DIR/system/current"
export_readonly m_STATE_USER_DIR="$m_STATE_DIR/user/current"

export -- m_LOG_LEVEL

#-------------------------------------------------------------------------------
# LOAD CORE LIB
#-------------------------------------------------------------------------------

. "$m_LIB_DIR/sys/sh/core.lib.sh"

if _m_system_state_selector_validate
then
  :
else
  m_system_state_selector_status=$?
  case "$m_system_state_selector_status" in
    3) : ;; # No current profile is permitted during bootstrap.
    *) fatal execution system-state-selector-invalid selector "$m_STATE_SYS_DIR" ;;
  esac
fi

#-------------------------------------------------------------------------------
# GLOBAL EXECUTION ENVIRONMENT
#-------------------------------------------------------------------------------

if [ -f "$m_STATE_SYS_DIR/sys/environment/cache/env" ]
then
  . "$m_STATE_SYS_DIR/sys/environment/cache/env" || fatal execution execution-failed operation global-environment
fi

if [ -f "$m_STATE_SYS_DIR/sys/environment/cache/env-osarch" ]
then
  . "$m_STATE_SYS_DIR/sys/environment/cache/env-osarch" || fatal execution execution-failed operation global-environment
fi

PATH=$m_BIN_SYS_OSARCH_DIR:$m_BIN_SYS_DIR:$m_BIN_EXT_OSARCH_DIR:$m_BIN_EXT_DIR${PATH:+:$PATH}
export -- PATH

#-------------------------------------------------------------------------------
# EXECUTE
#-------------------------------------------------------------------------------

unset m_COMMAND_BIN

if [ "$#" -eq 0 ]
then
  shell
  exit "$?"
fi

if m_COMMAND_RESOLVED="$(command -v -- "$1" 2>/dev/null)" && [ "${m_COMMAND_RESOLVED#*/}" != "$m_COMMAND_RESOLVED" ] && readpathce "m_COMMAND_RESOLVED" "$m_COMMAND_RESOLVED"
then
  [ "$m_COMMAND_RESOLVED" != "$m_BOOTSTRAP_BIN" ] || fatal filesystem path-invalid command-original "$1" command-resolved "$m_COMMAND_RESOLVED"
fi
unset m_COMMAND_RESOLVED

exec "$@"
