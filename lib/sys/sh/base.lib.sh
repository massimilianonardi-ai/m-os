
loadsyslib()
{
  [ "$#" -eq 1 ] || return 1

  loadlib "sys/sh/$1"
}

#-------------------------------------------------------------------------------

valid_integer()
{
  [ "$#" -eq 0 ] && return 1

  while [ "$#" -gt 0 ]
  do
    case "$1" in "" | *[!0123456789]*) return 2;; esac
    shift
  done
}

valid_shell_identifier()
{
  [ "$#" -eq 0 ] && return 1

  while [ "$#" -gt 0 ]
  do
    case "$1" in "" | [0123456789]* | *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*) return 2;; esac
    shift
  done
}

valid_cli_name()
{
  [ "$#" -eq 0 ] && return 1

  while [ "$#" -gt 0 ]
  do
    case "$1" in "" | [!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ]* | *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-]* | *[_-]) return 2 ;; esac
    shift
  done
}

valid_namespace_name()
{
  [ "$#" -eq 0 ] && return 1

  while [ "$#" -gt 0 ]
  do
    case "$1" in "" | [!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ]* | *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.]* | *[_-.]) return 2 ;; esac
    shift
  done
}

valid_dir()
{
  [ "$#" -eq 1 ] || return 1

  [ -d "$1" ] && [ ! -L "$1" ] || return 2
}

#-------------------------------------------------------------------------------

log_base_print()
{
  if [ "$#" -gt "0" ]
  then
    printf -- '%s' "$1" >&2
    shift
    if [ "$#" -gt "0" ]
    then
      printf -- ' %s' "$1" >&2
      shift
    fi
    if [ "$#" -gt "0" ]
    then
      printf -- '.%s' "$@" >&2
    fi
    printf -- '\n' >&2
  fi
}

log()
{
  log_base_print "$@"
}

fatal()
{
  EXIT_CODE="1"
  case "${1-}" in [1-9] | [1-9][0-9] | 1[0-9][0-9] | 2[0-4][0-9] | 25[0-5]) EXIT_CODE="$1"; shift;; *[!0-9]* | "") : ;; *) shift;; esac

  log fatal "$@" || log_base_print "$@"

  exit "$EXIT_CODE"
}

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

#-------------------------------------------------------------------------------

lang()
(
  [ "$#" -eq 2 ] || return 1
  case "$1" in "" | [!a-z0-9]* | *[!a-z0-9._-]* | *[._-]) return 1;; esac
  case "$2" in "" | [!a-z0-9]* | *[!a-z0-9._-]* | *[._-]) return 1;; esac

  lang_message="$(command -p -- cat "$m_LANG_CURRENT_DIR/$1/$2" 2>/dev/null)" || \
  lang_message="$(command -p -- cat "$m_LANG_FALLBACK_DIR/$1/$2" 2>/dev/null)" || \
  lang_message="${1}.${2}"

  printf -- '%s\n' "$lang_message"
)

#-------------------------------------------------------------------------------

: "${m_LOG_LEVEL:=info}"
export -- m_LOG_LEVEL

log()
{
  (
    # Validate every operand before severity filtering so invalid calls never
    # become successful merely because their output would have been hidden.
    (
      [ "$#" -ge 3 ] || exit 1
      case "$1" in
        fatal|error|warn|info|debug|trace) :;;
        *) exit 2;;
      esac
      case "$m_LOG_LEVEL" in
        off|none|fatal|error|warn|info|debug|trace|all) :;;
        *) exit 3;;
      esac
      case "$2" in ""|[!a-z0-9]*|*[!a-z0-9._-]*|*[._-]) exit 4;; esac
      case "$3" in ""|[!a-z0-9]*|*[!a-z0-9._-]*|*[._-]) exit 5;; esac
      shift 3
      [ "$(( $# % 2 ))" -eq 0 ] || exit 6
      while [ "$#" -gt 0 ]
      do
        case "$1" in ""|[!a-z0-9]*|*[!a-z0-9._-]*|*[._-]) exit 7;; esac
        shift 2
      done
    )
    log_validation_status=$?
    [ "$log_validation_status" -eq 0 ] || exit "$log_validation_status"

    [ "$#" -ge 3 ] || exit 1

    log_severity="$1"
    shift

    case "$log_severity" in
      fatal) log_priority=1;;
      error) log_priority=2;;
      warn) log_priority=3;;
      info) log_priority=4;;
      debug) log_priority=5;;
      trace) log_priority=6;;
      *) exit 2;;
    esac

    case "$m_LOG_LEVEL" in
      off | none) log_threshold="0";;
      fatal) log_threshold="1";;
      error) log_threshold="2";;
      warn) log_threshold="3";;
      info) log_threshold="4";;
      debug) log_threshold="5";;
      trace | all) log_threshold="6";;
      *) exit 3;;
    esac

    [ "$log_priority" -le "$log_threshold" ] || exit 0

    case "$1" in "" | [!a-z0-9]* | *[!a-z0-9._-]* | *[._-]) exit 4 ;; esac
    case "$2" in "" | [!a-z0-9]* | *[!a-z0-9._-]* | *[._-]) exit 5 ;; esac

    log_domain=$1
    log_message_id=$2
    shift 2

    log_message=$(lang "$log_domain" "$log_message_id") || log_message=$log_domain.$log_message_id
    log_timestamp=$(command -p -- date '+%Y-%m-%d|%H:%M:%S' 2>/dev/null) || log_timestamp=-

    printf -- '[%s] [%s] [%s.%s] %s' \
      "$log_timestamp" \
      "$log_severity" \
      "$log_domain" \
      "$log_message_id" \
      "$log_message" >&2

    if [ ! "$(( $# % 2 ))" -eq 0 ]
    then
      printf -- '\n' >&2
      exit 6
    fi

    while [ "$#" -gt 0 ]
    do
      case "$1" in "" | [!a-z0-9]* | *[!a-z0-9._-]* | *[._-]) printf -- '\n' >&2; exit 7 ;; esac
      log_field_name=$1
      log_field_value=$2
      shift 2

      printf -- ' [%s="%s"]' \
        "$log_field_name" \
        "$log_field_value" >&2
    done

    printf -- '\n' >&2
  )

  (
    exit_code="$?"
    if [ "$exit_code" != "0" ]
    then
      printf -- '[%s] [%s] [%s] ' \
        "$(command -p -- date '+%Y-%m-%d|%H:%M:%S' 2>/dev/null)" \
        "error" \
        "log" >&2
      case "$exit_code" in
        "1") printf -- '%s ' "invalid number of arguments: $@" >&2;;
        "2") printf -- '%s ' "invalid log severity: $@" >&2;;
        "3") printf -- '%s ' "invalid m_LOG_LEVEL: $@" >&2;;
        "4") printf -- '%s ' "invalid log domain: $@" >&2;;
        "5") printf -- '%s ' "invalid message id: $@" >&2;;
        "6") printf -- '%s ' "invalid parity check of <field, value> pairs: $@" >&2;;
        "7") printf -- '%s ' "invalid field name: $@" >&2;;
        *) printf -- '%s ' "unknown error: $@" >&2;;
      esac
      printf -- '\n' >&2

      exit "$exit_code"
    fi
  )
}

#-------------------------------------------------------------------------------

shell()
{
  : "${SHELL:=sh}"

  m_SHELL_NAME="${SHELL##*/}"
  export -- m_SHELL_NAME
  printf -- '%s\n' "$(tput setaf 2)$(tput bold)${m_SHELL_NAME}$(tput sgr0)" >&2

  shell_conf_dir="$(command -- state-path system sys shell conf)" || return 1

  : "${m_SHELL_EXT:=}"
  export m_SHELL_EXT

  case "${SHELL##*/}" in
    bash)
      exec "$SHELL" --rcfile "$shell_conf_dir/bash/bashrc" "$@"
      ;;

    zsh)
      unset m_SHELL_ZDOTDIR

      if [ "${ZDOTDIR+x}" = "x" ]
      then
        m_SHELL_ZDOTDIR="$ZDOTDIR"
        export -- m_SHELL_ZDOTDIR
      fi

      shell_home_dir="$(command -- state-path user sys shell home)" || return 1
      shell_zdotdir_init="$shell_home_dir/zsh"
      command -p -- mkdir -p "$shell_zdotdir_init" || return 1

      for shell_zdotfile in .zshenv .zprofile .zshrc
      do
        shell_zdottmp="$shell_zdotdir_init/$shell_zdotfile.$$"

        if ! printf -- '. "$(state-path system sys shell conf)/zsh/%s"\n' "$shell_zdotfile" > "$shell_zdottmp"
        then
          command -p -- rm -f "$shell_zdottmp" 2>/dev/null
          return 1
        fi

        if ! command -p -- mv -f "$shell_zdottmp" "$shell_zdotdir_init/$shell_zdotfile"
        then
          command -p -- rm -f "$shell_zdottmp" 2>/dev/null
          return 1
        fi
      done

      m_SHELL_ZDOTDIR_INIT="$shell_zdotdir_init"
      export -- m_SHELL_ZDOTDIR_INIT

      ZDOTDIR="$m_SHELL_ZDOTDIR_INIT"
      export -- ZDOTDIR

      unset shell_conf_dir shell_home_dir shell_zdotdir_init shell_zdotfile shell_zdottmp

      exec "$SHELL" "$@"
      ;;

    sh | dash | ash)
      m_SHELL_ENV="${ENV-}"
      export -- m_SHELL_ENV

      ENV="$shell_conf_dir/sh/env"
      export -- ENV

      unset shell_conf_dir
      exec "$SHELL" "$@"
      ;;

    *)
      unset shell_conf_dir
      exec "$SHELL" "$@"
      ;;
  esac
}

#-------------------------------------------------------------------------------

# quote [arg] ...
# returns a perfectly safe quoted string.
# typical use is to store/restore command arguments:
# current_args="$(quote "$@")"
# set -- foo bar baz boo
# eval "set -- $current_args"
quote()
(
  while [ "$#" -gt 0 ]
  do
    _quote_arg="$1"

    printf "'" || exit 1

    while [ "$_quote_arg" != "${_quote_arg#*"'"}" ]
    do
      _quote_part="${_quote_arg%%"'"*}"

      printf "%s'\\\\''" "$_quote_part" || exit 2

      _quote_arg="${_quote_arg#*"'"}"
    done

    printf "%s'" "$_quote_arg" || exit 3

    shift

    if [ "$#" -gt 0 ]
    then
      printf " " || exit 4
    fi
  done
)

#-------------------------------------------------------------------------------

pathsearch()
{
  [ "$#" -eq 2 ] && [ -n "$1" ] && [ -n "$2" ] && [ "$1" != "PATH" ] || return 1

  case "$1" in "" | [0-9]* | *[!a-zA-Z0-9_]*) return 2 ;; esac

  eval $1=''

  if [ "${2#*/}" != "$2" ]
  then
    [ -f "$2" ] || return 3
  else
    [ -n "${PATH-}" ] || return 4

    set -- "$1" "$(
      set -eu
      shift

      pathsearch_path="$PATH:"

      while [ -n "$pathsearch_path" ]
      do
        pathsearch_dir=${pathsearch_path%%:*}
        pathsearch_path=${pathsearch_path#*:}

        [ -n "$pathsearch_dir" ] || pathsearch_dir=.

        pathsearch_candidate="$pathsearch_dir/$1"

        if [ -f "$pathsearch_candidate" ]
        then
          printf -- '%s' "${pathsearch_candidate}x"
          exit 0
        fi
      done

      exit 1
    )"

    set -- "$1" "${2%x}"
    [ -n "$2" ] || return 5
  fi

  readpathce "$1" "$2" || return 6
}

#-------------------------------------------------------------------------------

exist_function()
(
  [ "$#" -eq "1" ] || return 1
  case "$1" in "" | [0-9]* | *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*) return 2;; esac

  unalias "$1" 2>/dev/null || :

  _exist_function_command="$(command -v "$1" 2>/dev/null)" || return 6
  case "$_exist_function_command" in */*) return 7 ;; esac

  unset -f "$1" 2>/dev/null || return 8
  _exist_function_reserved_word="$(command -v "$1" 2>/dev/null)" && return 9
  [ "$_exist_function_command" = "$_exist_function_reserved_word" ] && return 10

  return 0
)

#-------------------------------------------------------------------------------

exec_if_exist_function()
{
  exist_function "$1" && "$@"
}

#-------------------------------------------------------------------------------

waituser()
{
  # detect if launched from gui or active terminal
  PARENT_PROCESS="$(ps -o 'cmd=' -p $(ps -o 'ppid=' -p $$))"
  #if [ "$PARENT_PROCESS" != "bash" ]
  if [ "${PARENT_PROCESS%sh}" = "$PARENT_PROCESS" ]
  then
    echo ""
    echo "--------------------------------------------------------------------------------"
    echo "press ENTER to exit"
    read -r EXIT_VAR
  fi
}
