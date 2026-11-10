# Private account-scoped storage primitives for context defaults and presets.

_context_store_uid()
{
  [ "$#" -eq 0 ] || return 2
  _context_store_uid=$(command -p id -u 2>/dev/null) || return 1
  case "$_context_store_uid" in
    ''|*[!0-9]*) return 1 ;;
  esac
  printf '%s\n' "$_context_store_uid"
}

_context_store_metadata()
{
  [ "$#" -eq 1 ] || return 2
  _context_store_ls=$(LC_ALL=C command -p ls -ldn "$1" 2>/dev/null) || return 1
  _context_store_meta=$(printf '%s\n' "$_context_store_ls" | LC_ALL=C command -p awk 'NR == 1 { printf "%s\t%s\n", $1, $3 }') || return 1
  _context_store_tab=$(printf '\t')
  _context_store_mode=${_context_store_meta%%"$_context_store_tab"*}
  _context_store_owner=${_context_store_meta#*"$_context_store_tab"}
  [ -n "$_context_store_mode" ] && [ -n "$_context_store_owner" ] || return 1
}

_context_store_state_validate()
{
  [ "$#" -eq 2 ] || return 2
  _context_store_root=$1
  _context_store_uid=$2
  [ -d "$_context_store_root" ] && [ ! -L "$_context_store_root" ] || return 1
  _context_store_state=$_context_store_root/state
  [ -d "$_context_store_state" ] && [ ! -L "$_context_store_state" ] || return 1
  _context_store_metadata "$_context_store_state" || return 1
  case "$_context_store_mode" in
    d????????? | d?????????@) : ;;
    *) return 1 ;;
  esac
  case "$_context_store_owner" in
    0 | "$_context_store_uid") : ;;
    *) return 1 ;;
  esac
  printf '%s\n' "$_context_store_mode" | LC_ALL=C command -p awk 'NR == 1 && length($0) >= 10 && substr($0, 1, 1) == "d" && substr($0, 6, 1) != "w" && substr($0, 9, 1) != "w" && substr($0, 11) !~ /[^@]/ { ok = 1 } END { if (!ok) exit 1 }'
}

_context_store_directory()
{
  [ "$#" -eq 3 ] || return 2
  _context_store_root=$1
  _context_store_uid=$2
  _context_store_create=$3
  _context_store_state_validate "$_context_store_root" "$_context_store_uid" || return 1

  _context_store_account="$_context_store_root/state/$_context_store_uid"
  if [ ! -e "$_context_store_account" ] && [ ! -L "$_context_store_account" ]
  then
    [ "$_context_store_create" = create ] || return 5
    (umask 077; command -p mkdir -m 700 "$_context_store_account") 2>/dev/null || return 1
  fi
  [ -d "$_context_store_account" ] && [ ! -L "$_context_store_account" ] || return 1
  _context_store_metadata "$_context_store_account" || return 1
  case "$_context_store_mode" in
    drwx------ | drwx------@) : ;;
    *) return 1 ;;
  esac
  [ "$_context_store_owner" = "$_context_store_uid" ] || return 1

  _context_store_context="$_context_store_account/context"
  if [ ! -e "$_context_store_context" ] && [ ! -L "$_context_store_context" ]
  then
    [ "$_context_store_create" = create ] || return 5
    (umask 077; command -p mkdir -m 700 "$_context_store_context") 2>/dev/null || return 1
  fi
  [ -d "$_context_store_context" ] && [ ! -L "$_context_store_context" ] || return 1
  _context_store_metadata "$_context_store_context" || return 1
  case "$_context_store_mode" in
    drwx------ | drwx------@) : ;;
    *) return 1 ;;
  esac
  [ "$_context_store_owner" = "$_context_store_uid" ] || return 1
  printf '%s\n' "$_context_store_context"
}

_context_store_name_valid()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in
    defaults) return 0 ;;
    preset.*)
      _context_store_name_check=${1#preset.}
      case "$_context_store_name_check" in
        '' | [!A-Za-z0-9]* | *[!A-Za-z0-9_.-]*) return 1 ;;
      esac
      return 0
      ;;
    *) return 1 ;;
  esac
}

_context_store_file_validate()
{
  [ "$#" -eq 2 ] || return 2
  _context_store_file=$1
  _context_store_uid=$2
  [ ! -L "$_context_store_file" ] || return 1
  [ -f "$_context_store_file" ] || return 1
  _context_store_metadata "$_context_store_file" || return 1
  case "$_context_store_mode" in
    -rw------- | -rw-------@) : ;;
    *) return 1 ;;
  esac
  [ "$_context_store_owner" = "$_context_store_uid" ] || return 1
  _context_store_size=$(LC_ALL=C command -p wc -c < "$_context_store_file" | LC_ALL=C command -p awk '{ print $1 }') || return 1
  case "$_context_store_size" in
    '' | *[!0-9]*) return 1 ;;
  esac
  [ "$_context_store_size" -le 16384 ]
}

_context_store_parse_file()
{
  [ "$#" -eq 2 ] || return 2
  _context_store_file=$1
  _context_store_uid=$2
  _context_store_lines=0
  _context_store_first=1
  _context_store_format_version=
  _context_store_record=
  _context_store_system=
  _context_store_packages=
  _context_store_seen=
  _context_store_system_seen=0
  _context_store_newline='
'
  _context_store_cr=$(printf '\r')
  while IFS= read -r _context_store_line || [ -n "$_context_store_line" ]
  do
    _context_store_lines=$((_context_store_lines + 1))
    [ "$_context_store_lines" -le 130 ] || return 1
    [ "${#_context_store_line}" -le 512 ] || return 1
    case "$_context_store_line" in
      *"$_context_store_cr"*) return 1 ;;
    esac
    if [ "$_context_store_first" -eq 1 ]
    then
      case "$_context_store_line" in
        m-context-record-v1) _context_store_format_version=1 ;;
        m-context-record-v2) _context_store_format_version=2 ;;
        *) return 1 ;;
      esac
      _context_store_first=0
      _context_store_record=$_context_store_line
      continue
    fi
    case "$_context_store_line" in
      system=*)
        [ "$_context_store_format_version" -eq 2 ] && [ "$_context_store_system_seen" -eq 0 ] || return 1
        _context_store_system=${_context_store_line#system=}
        _context_profile_registry_identity_valid "$_context_store_system" || return 1
        _context_store_system_seen=1
        ;;
      pkg=*)
        _context_store_value=${_context_store_line#pkg=}
        pkg_concrete_read _context_store_package _context_store_version _context_store_osarch "$_context_store_value" || return 1
        case "$_context_store_seen$_context_store_newline" in
          *"$_context_store_newline$_context_store_package$_context_store_newline"*) return 1 ;;
        esac
        _context_store_seen="$_context_store_seen$_context_store_newline$_context_store_package"
        _context_store_packages="$_context_store_packages$_context_store_newline$_context_store_line"
        ;;
      *) return 1 ;;
    esac
    _context_store_record="$_context_store_record$_context_store_newline$_context_store_line"
  done < "$_context_store_file"
  [ "$_context_store_first" -eq 0 ] || return 1
  CONTEXT_STORE_RECORD=$_context_store_record
  CONTEXT_STORE_VERSION=$_context_store_format_version
  CONTEXT_STORE_SYSTEM=$_context_store_system
  CONTEXT_STORE_PACKAGES=${_context_store_packages#"$_context_store_newline"}
}

# Read a strict data record. Status 5 means that the record is absent.
_context_store_read()
{
  [ "$#" -eq 2 ] || return 2
  CONTEXT_STORE_RECORD=
  CONTEXT_STORE_PACKAGES=
  _context_store_root=$1
  _context_store_name=$2
  _context_store_name_valid "$_context_store_name" || return 1
  _context_store_uid=$(_context_store_uid) || return 1
  _context_store_context=$(_context_store_directory "$_context_store_root" "$_context_store_uid" existing) || return $?
  _context_store_file="$_context_store_context/$_context_store_name"
  [ ! -L "$_context_store_file" ] || return 1
  [ -e "$_context_store_file" ] || return 5
  _context_store_file_validate "$_context_store_file" "$_context_store_uid" || return 1
  _context_store_parse_file "$_context_store_file" "$_context_store_uid"
}

# Write a strict record by same-directory atomic rename.
_context_store_write()
{
  [ "$#" -eq 3 ] || return 2
  _context_store_root=$1
  _context_store_name=$2
  _context_store_record=$3
  _context_store_name_valid "$_context_store_name" || return 1
  _context_store_uid=$(_context_store_uid) || return 1
  _context_store_context=$(_context_store_directory "$_context_store_root" "$_context_store_uid" create) || return 1
  _context_store_target="$_context_store_context/$_context_store_name"
  if [ -e "$_context_store_target" ] || [ -L "$_context_store_target" ]; then
    _context_store_file_validate "$_context_store_target" "$_context_store_uid" || return 1
  fi

  _context_store_counter=0
  _context_store_temp=
  while [ "$_context_store_counter" -lt 100 ]
  do
    _context_store_candidate="$_context_store_context/.$_context_store_name.$_context_store_uid.$$.$_context_store_counter"
    if (umask 077; set -C; printf '%s\n' "$_context_store_record" > "$_context_store_candidate") 2>/dev/null
    then
      _context_store_temp=$_context_store_candidate
      break
    fi
    _context_store_counter=$((_context_store_counter + 1))
  done
  [ -n "$_context_store_temp" ] || return 1
  command -p chmod 600 "$_context_store_temp" 2>/dev/null || {
    command -p rm -f "$_context_store_temp" 2>/dev/null || :
    return 1
  }
  _context_store_file_validate "$_context_store_temp" "$_context_store_uid" &&
  _context_store_parse_file "$_context_store_temp" "$_context_store_uid" || {
    command -p rm -f "$_context_store_temp" 2>/dev/null || :
    return 1
  }
  command -p mv -f "$_context_store_temp" "$_context_store_target" 2>/dev/null || {
    command -p rm -f "$_context_store_temp" 2>/dev/null || :
    return 1
  }
  _context_store_file_validate "$_context_store_target" "$_context_store_uid"
}

# Serialize read/merge/write of account defaults. POSIX has no portable
# advisory-lock utility, so an atomic private directory is used. A stale lock
# after an uncatchable process termination fails closed and can be removed by
# the account owner after confirming no context update is running.
_context_store_lock()
{
  [ "$#" -eq 1 ] || [ "$#" -eq 2 ] || return 2
  _context_store_root=$1
  _context_store_create=${2-create}
  _context_store_uid=$(_context_store_uid) || return 1
  _context_store_context=$(_context_store_directory "$_context_store_root" "$_context_store_uid" "$_context_store_create") || return $?
  _context_store_lock_dir="$_context_store_context/.defaults.lock"
  _context_store_token_counter=0
  _context_store_lock_token_path=
  _context_store_lock_token_owned=0
  while [ "$_context_store_token_counter" -lt 100 ]
  do
    _context_store_lock_token_path="$_context_store_context/._defaults-owner.$$.$_context_store_token_counter"
    if (umask 077; set -C; : > "$_context_store_lock_token_path") 2>/dev/null
    then
      _context_store_lock_token_owned=1
      break
    fi
    _context_store_token_counter=$((_context_store_token_counter + 1))
  done
  [ "$_context_store_token_counter" -lt 100 ] || return 1
  _context_store_attempt=0
  while [ "$_context_store_attempt" -lt 10 ]
  do
    if (umask 077; command -p mkdir -m 700 "$_context_store_lock_dir") 2>/dev/null
    then
      (umask 077; printf '%s\n' "$_context_store_lock_token_path" > "$_context_store_lock_dir/owner") || {
        command -p rmdir "$_context_store_lock_dir" 2>/dev/null || :
        return 1
      }
      return 0
    fi
    [ -d "$_context_store_lock_dir" ] && [ ! -L "$_context_store_lock_dir" ] || return 1
    _context_store_metadata "$_context_store_lock_dir" || return 1
    case "$_context_store_mode" in
      drwx------ | drwx------@) : ;;
      *) return 1 ;;
    esac
    [ "$_context_store_owner" = "$_context_store_uid" ] || return 1
    _context_store_attempt=$((_context_store_attempt + 1))
    command -p sleep 1 || return 1
  done
  return 3
}

_context_store_unlock()
{
  [ "$#" -eq 1 ] || return 2
  _context_store_lock_dir=$1
  _context_store_lock_owner=
  if [ -f "$_context_store_lock_dir/owner" ] && [ ! -L "$_context_store_lock_dir/owner" ]
  then
    IFS= read -r _context_store_lock_owner < "$_context_store_lock_dir/owner" || return 1
  fi
  [ -n "${_context_store_lock_token_path-}" ] &&
  [ "$_context_store_lock_owner" = "$_context_store_lock_token_path" ] || return 1
  command -p rm -f "$_context_store_lock_dir/owner" || return 1
  command -p rmdir "$_context_store_lock_dir" || return 1
  command -p rm -f "$_context_store_lock_token_path"
  _context_store_lock_token_owned=0
}

# Deletion is idempotent and does not need to parse the record contents.
_context_store_delete()
{
  [ "$#" -eq 2 ] || return 2
  _context_store_root=$1
  _context_store_name=$2
  _context_store_name_valid "$_context_store_name" || return 1
  _context_store_uid=$(_context_store_uid) || return 1
  _context_store_context=$(_context_store_directory "$_context_store_root" "$_context_store_uid" existing) || {
    _context_store_status=$?
    [ "$_context_store_status" -eq 5 ] && return 0
    return "$_context_store_status"
  }
  _context_store_file="$_context_store_context/$_context_store_name"
  [ ! -L "$_context_store_file" ] || return 1
  [ -e "$_context_store_file" ] || return 0
  _context_store_file_validate "$_context_store_file" "$_context_store_uid" || return 1
  command -p rm -f "$_context_store_file"
}
