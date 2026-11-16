# Read-only validator for the installation-managed system-profile inventory.

_context_profile_registry_directory_validate()
{
  [ "$#" -eq 2 ] || return 2
  _context_profile_dir=$1
  _context_profile_root_owner=$2
  [ -d "$_context_profile_dir" ] && [ ! -L "$_context_profile_dir" ] || return 1
  _context_store_metadata "$_context_profile_dir" || return 1
  case "$_context_store_mode" in d????????? | d?????????@) : ;; *) return 1 ;; esac
  case "$_context_store_owner" in 0 | "$_context_profile_root_owner") : ;; *) return 1 ;; esac
  printf '%s\n' "$_context_store_mode" | LC_ALL=C command -p awk 'NR == 1 && length($0) >= 10 && substr($0, 1, 1) == "d" && substr($0, 6, 1) != "w" && substr($0, 9, 1) != "w" && substr($0, 11) !~ /[^@]/ { ok = 1 } END { if (!ok) exit 1 }'
}

_context_profile_registry_identity_valid()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in
    '' | [!abcdefghijklmnopqrstuvwxyz0123456789]* | *[!abcdefghijklmnopqrstuvwxyz0123456789._-]* | *[._-]) return 1 ;;
  esac
}

# Set CONTEXT_PROFILE_REGISTRY_BASELINE and
# CONTEXT_PROFILE_REGISTRY_IDENTITIES only after the entire inventory validates.
_context_profile_registry_read()
{
  [ "$#" -eq 1 ] || return 2
  _context_profile_registry_root=$1
  CONTEXT_PROFILE_REGISTRY_BASELINE=
  CONTEXT_PROFILE_REGISTRY_IDENTITIES=

  [ -d "$_context_profile_registry_root" ] && [ ! -L "$_context_profile_registry_root" ] || return 1
  _context_store_metadata "$_context_profile_registry_root" || return 1
  _context_profile_root_owner=$_context_store_owner
  _context_profile_registry_state="$_context_profile_registry_root/state"
  _context_profile_registry_system="$_context_profile_registry_state/system"
  _context_profile_registry_profiles="$_context_profile_registry_system/profile"
  _context_profile_registry_file="$_context_profile_registry_profiles/.inventory"

  _context_profile_registry_directory_validate "$_context_profile_registry_state" "$_context_profile_root_owner" || return 1
  _context_profile_registry_directory_validate "$_context_profile_registry_system" "$_context_profile_root_owner" || return 1
  _context_profile_registry_directory_validate "$_context_profile_registry_profiles" "$_context_profile_root_owner" || return 1

  [ ! -L "$_context_profile_registry_file" ] && [ -f "$_context_profile_registry_file" ] || return 1
  _context_store_metadata "$_context_profile_registry_file" || return 1
  case "$_context_store_mode" in -????????? | -?????????@) : ;; *) return 1 ;; esac
  case "$_context_store_owner" in 0 | "$_context_profile_root_owner") : ;; *) return 1 ;; esac
  printf '%s\n' "$_context_store_mode" | LC_ALL=C command -p awk 'NR == 1 && length($0) >= 10 && substr($0, 1, 1) == "-" && substr($0, 6, 1) != "w" && substr($0, 9, 1) != "w" && substr($0, 11) !~ /[^@]/ { ok = 1 } END { if (!ok) exit 1 }' || return 1

  _context_profile_registry_size=$(LC_ALL=C command -p wc -c < "$_context_profile_registry_file" | LC_ALL=C command -p awk '{ print $1 }') || return 1
  case "$_context_profile_registry_size" in '' | *[!0-9]*) return 1 ;; esac
  [ "$_context_profile_registry_size" -le 16384 ] || return 1

  _context_profile_registry_header=1
  _context_profile_registry_baseline_seen=0
  _context_profile_registry_baseline=
  _context_profile_registry_identities=
  _context_profile_registry_count=0
  _context_profile_registry_lines=0
  _context_profile_registry_newline='
'
  _context_profile_registry_cr=$(printf '\r')
  while IFS= read -r _context_profile_registry_line || [ -n "$_context_profile_registry_line" ]
  do
    _context_profile_registry_lines=$((_context_profile_registry_lines + 1))
    [ "$_context_profile_registry_lines" -le 258 ] || return 1
    [ "${#_context_profile_registry_line}" -le 512 ] || return 1
    case "$_context_profile_registry_line" in '' | *"$_context_profile_registry_cr"*) return 1 ;; esac

    if [ "$_context_profile_registry_header" -eq 1 ]
    then
      [ "$_context_profile_registry_line" = m-system-profile-inventory-v1 ] || return 1
      _context_profile_registry_header=0
      continue
    fi

    case "$_context_profile_registry_line" in
      baseline=*)
        [ "$_context_profile_registry_baseline_seen" -eq 0 ] || return 1
        [ "$_context_profile_registry_count" -eq 0 ] || return 1
        _context_profile_registry_baseline=${_context_profile_registry_line#baseline=}
        _context_profile_registry_identity_valid "$_context_profile_registry_baseline" || return 1
        _context_profile_registry_baseline_seen=1
        ;;
      profile=*)
        [ "$_context_profile_registry_baseline_seen" -eq 1 ] || return 1
        _context_profile_registry_identity=${_context_profile_registry_line#profile=}
        _context_profile_registry_identity_valid "$_context_profile_registry_identity" || return 1
        case "$_context_profile_registry_newline$_context_profile_registry_identities$_context_profile_registry_newline" in
          *"$_context_profile_registry_newline$_context_profile_registry_identity$_context_profile_registry_newline"*) return 1 ;;
        esac
        _context_profile_registry_count=$((_context_profile_registry_count + 1))
        [ "$_context_profile_registry_count" -le 256 ] || return 1
        _context_profile_registry_identity_dir="$_context_profile_registry_profiles/$_context_profile_registry_identity"
        _context_profile_registry_directory_validate "$_context_profile_registry_identity_dir" "$_context_profile_root_owner" || return 1
        if [ -n "$_context_profile_registry_identities" ]
        then
          _context_profile_registry_identities="$_context_profile_registry_identities$_context_profile_registry_newline$_context_profile_registry_identity"
        else
          _context_profile_registry_identities=$_context_profile_registry_identity
        fi
        ;;
      *) return 1 ;;
    esac
  done < "$_context_profile_registry_file"
  _context_profile_registry_newlines=$(LC_ALL=C command -p wc -l < "$_context_profile_registry_file" | LC_ALL=C command -p awk '{ print $1 }') || return 1
  [ "$_context_profile_registry_newlines" = "$_context_profile_registry_lines" ] || return 1

  [ "$_context_profile_registry_header" -eq 0 ] || return 1
  [ "$_context_profile_registry_baseline_seen" -eq 1 ] || return 1
  [ "$_context_profile_registry_count" -ge 1 ] || return 1
  case "$_context_profile_registry_newline$_context_profile_registry_identities$_context_profile_registry_newline" in
    *"$_context_profile_registry_newline$_context_profile_registry_baseline$_context_profile_registry_newline"*) : ;;
    *) return 1 ;;
  esac
  CONTEXT_PROFILE_REGISTRY_BASELINE=$_context_profile_registry_baseline
  CONTEXT_PROFILE_REGISTRY_IDENTITIES=$_context_profile_registry_identities
}
