_pkg_facility_cmd_name_valid()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in
    "" | [!abcdefghijklmnopqrstuvwxyz0123456789]* | *[!abcdefghijklmnopqrstuvwxyz0123456789._-]* | *[._-]) return 1 ;;
  esac
}

_pkg_facility_cmd_contract_validate()
{
  [ "$#" -eq 1 ] || return 2
  pkg_facility_cmd_contract=$1

  [ -d "$pkg_facility_cmd_contract" ] && [ ! -L "$pkg_facility_cmd_contract" ] || return 1
  _pkg_facility_dir_entries_empty "$pkg_facility_cmd_contract" && return 1

  for pkg_facility_cmd_marker in "$pkg_facility_cmd_contract"/*
  do
    [ -e "$pkg_facility_cmd_marker" ] || [ -L "$pkg_facility_cmd_marker" ] || continue
    pkg_facility_cmd_name=${pkg_facility_cmd_marker##*/}
    _pkg_facility_cmd_name_valid "$pkg_facility_cmd_name" || return 1
    [ -f "$pkg_facility_cmd_marker" ] && [ ! -L "$pkg_facility_cmd_marker" ] && [ -r "$pkg_facility_cmd_marker" ] && [ ! -x "$pkg_facility_cmd_marker" ] && [ ! -s "$pkg_facility_cmd_marker" ] || return 1
  done

  for pkg_facility_cmd_hidden in "$pkg_facility_cmd_contract"/.[!.]* "$pkg_facility_cmd_contract"/..?*
  do
    [ -e "$pkg_facility_cmd_hidden" ] || [ -L "$pkg_facility_cmd_hidden" ] || continue
    return 1
  done
}

_pkg_facility_cmd_target_read()
{
  [ "$#" -eq 1 ] || return 2
  [ -f "$1" ] && [ ! -L "$1" ] && [ -r "$1" ] && [ ! -x "$1" ] || return 1

  pkg_facility_cmd_target="$(command -p -- cat -- "$1")" || return 1
  case "$pkg_facility_cmd_target" in
    "" | /* | */ | *//* | *'
'*) return 1 ;;
  esac
  case "/$pkg_facility_cmd_target/" in
    */./* | */../*) return 1 ;;
  esac
}

_pkg_facility_cmd_realization_read()
{
  [ "$#" -eq 1 ] || return 2
  [ -f "$1" ] && [ ! -L "$1" ] && [ -r "$1" ] && [ ! -x "$1" ] || return 1

  pkg_facility_cmd_realization_value="$(command -p -- cat -- "$1")" || return 1
  case "$pkg_facility_cmd_realization_value" in
    *'
'*) return 1 ;;
  esac

  pkg_facility_cmd_tab="$(printf '\t')"
  case "$pkg_facility_cmd_realization_value" in
    "package-command$pkg_facility_cmd_tab"*)
      pkg_facility_cmd_realization_type=package-command
      pkg_facility_cmd_realization_value=${pkg_facility_cmd_realization_value#*"package-command$pkg_facility_cmd_tab"}
      _pkg_facility_cmd_name_valid "$pkg_facility_cmd_realization_value" || return 1
      ;;
    *)
      _pkg_facility_cmd_target_read "$1" || return 1
      pkg_facility_cmd_realization_type=root
      pkg_facility_cmd_realization_value=$pkg_facility_cmd_target
      ;;
  esac
}

_pkg_facility_cmd_package_command_validate()
{
  [ "$#" -eq 3 ] || return 2
  pkg_facility_cmd_definition=$1
  pkg_facility_cmd_package_command=$2
  pkg_facility_cmd_root=$3

  [ -d "$pkg_facility_cmd_definition" ] && [ ! -L "$pkg_facility_cmd_definition" ] || return 1
  [ -d "$pkg_facility_cmd_root" ] && [ ! -L "$pkg_facility_cmd_root" ] || return 1
  _pkg_facility_cmd_name_valid "$pkg_facility_cmd_package_command" || return 1

  pkg_facility_cmd_package_command_file="$pkg_facility_cmd_definition/cmd/$pkg_facility_cmd_package_command"
  [ -f "$pkg_facility_cmd_package_command_file" ] && \
  [ ! -L "$pkg_facility_cmd_package_command_file" ] && \
  [ -r "$pkg_facility_cmd_package_command_file" ] && \
  [ ! -x "$pkg_facility_cmd_package_command_file" ] || return 1

  pkg_facility_cmd_package_command_link="$pkg_facility_cmd_definition/link/$pkg_facility_cmd_package_command"
  _pkg_facility_cmd_target_read "$pkg_facility_cmd_package_command_link" || return 1

  readpathce pkg_facility_cmd_root_resolved "$pkg_facility_cmd_root" || return 1
  [ -e "$pkg_facility_cmd_root/$pkg_facility_cmd_target" ] || \
  [ -L "$pkg_facility_cmd_root/$pkg_facility_cmd_target" ] || return 1
  readpathce pkg_facility_cmd_package_command_target_resolved \
    "$pkg_facility_cmd_root/$pkg_facility_cmd_target" || return 1
  case "$pkg_facility_cmd_package_command_target_resolved" in
    "$pkg_facility_cmd_root_resolved"/*) : ;;
    *) return 1 ;;
  esac

  [ -f "$pkg_facility_cmd_package_command_target_resolved" ] && \
  [ -x "$pkg_facility_cmd_package_command_target_resolved" ]
}

_pkg_facility_cmd_realization_validate()
{
  [ "$#" -eq 3 ] || return 2
  pkg_facility_cmd_realization=$1
  pkg_facility_cmd_definition=$2
  pkg_facility_cmd_root=$3

  [ -d "$pkg_facility_cmd_realization" ] && [ ! -L "$pkg_facility_cmd_realization" ] || return 1
  [ -d "$pkg_facility_cmd_definition" ] && [ ! -L "$pkg_facility_cmd_definition" ] || return 1
  [ -d "$pkg_facility_cmd_root" ] && [ ! -L "$pkg_facility_cmd_root" ] || return 1
  readpathce pkg_facility_cmd_root_resolved "$pkg_facility_cmd_root" || return 1
  _pkg_facility_dir_entries_empty "$pkg_facility_cmd_realization" && return 1

  for pkg_facility_cmd_descriptor in "$pkg_facility_cmd_realization"/*
  do
    [ -e "$pkg_facility_cmd_descriptor" ] || [ -L "$pkg_facility_cmd_descriptor" ] || continue
    pkg_facility_cmd_name=${pkg_facility_cmd_descriptor##*/}
    _pkg_facility_cmd_name_valid "$pkg_facility_cmd_name" || return 1
    _pkg_facility_cmd_realization_read "$pkg_facility_cmd_descriptor" || return 1

    case "$pkg_facility_cmd_realization_type" in
      root)
        pkg_facility_cmd_target=$pkg_facility_cmd_realization_value
        [ -e "$pkg_facility_cmd_root/$pkg_facility_cmd_target" ] || [ -L "$pkg_facility_cmd_root/$pkg_facility_cmd_target" ] || return 1
        readpathce pkg_facility_cmd_target_resolved "$pkg_facility_cmd_root/$pkg_facility_cmd_target" || return 1
        case "$pkg_facility_cmd_target_resolved" in
          "$pkg_facility_cmd_root_resolved"/*) : ;;
          *) return 1 ;;
        esac
        [ -f "$pkg_facility_cmd_target_resolved" ] && [ -x "$pkg_facility_cmd_target_resolved" ] || return 1
        ;;
      package-command)
        _pkg_facility_cmd_package_command_validate \
          "$pkg_facility_cmd_definition" \
          "$pkg_facility_cmd_realization_value" \
          "$pkg_facility_cmd_root" || return 1
        ;;
      *)
        return 1
        ;;
    esac
  done

  for pkg_facility_cmd_hidden in "$pkg_facility_cmd_realization"/.[!.]* "$pkg_facility_cmd_realization"/..?*
  do
    [ -e "$pkg_facility_cmd_hidden" ] || [ -L "$pkg_facility_cmd_hidden" ] || continue
    return 1
  done
}

_pkg_facility_cmd_provider_validate()
{
  [ "$#" -eq 4 ] || return 2
  pkg_facility_cmd_contract=$1
  pkg_facility_cmd_realization=$2
  pkg_facility_cmd_definition=$3
  pkg_facility_cmd_root=$4

  _pkg_facility_cmd_contract_validate "$pkg_facility_cmd_contract" || return 1
  _pkg_facility_cmd_realization_validate \
    "$pkg_facility_cmd_realization" \
    "$pkg_facility_cmd_definition" \
    "$pkg_facility_cmd_root" || return 1

  pkg_facility_cmd_contract_count=0
  for pkg_facility_cmd_marker in "$pkg_facility_cmd_contract"/*
  do
    [ -e "$pkg_facility_cmd_marker" ] || [ -L "$pkg_facility_cmd_marker" ] || continue
    pkg_facility_cmd_name=${pkg_facility_cmd_marker##*/}
    [ -f "$pkg_facility_cmd_realization/$pkg_facility_cmd_name" ] && [ ! -L "$pkg_facility_cmd_realization/$pkg_facility_cmd_name" ] || return 1
    pkg_facility_cmd_contract_count=$((pkg_facility_cmd_contract_count + 1))
  done

  pkg_facility_cmd_realization_count=0
  for pkg_facility_cmd_descriptor in "$pkg_facility_cmd_realization"/*
  do
    [ -e "$pkg_facility_cmd_descriptor" ] || [ -L "$pkg_facility_cmd_descriptor" ] || continue
    pkg_facility_cmd_name=${pkg_facility_cmd_descriptor##*/}
    [ -f "$pkg_facility_cmd_contract/$pkg_facility_cmd_name" ] && [ ! -L "$pkg_facility_cmd_contract/$pkg_facility_cmd_name" ] || return 1
    pkg_facility_cmd_realization_count=$((pkg_facility_cmd_realization_count + 1))
  done

  [ "$pkg_facility_cmd_realization_count" -eq "$pkg_facility_cmd_contract_count" ]
}


# v2 command contracts own the names. A provider supplies either an explicit
# link/bin mapping or a useful-root binary directory in facility-bin/<facility>.
_pkg_facility_cmd_v2_provider_validate()
{
  [ "$#" -eq 4 ] || return 2
  pkg_facility_v2_contract=$1
  pkg_facility_v2_definition=$2
  pkg_facility_v2_root=$3
  pkg_facility_v2_name=$4

  _pkg_facility_cmd_contract_validate "$pkg_facility_v2_contract" || return 1
  readpathce pkg_facility_v2_root_resolved "$pkg_facility_v2_root" || return 1

  pkg_facility_v2_bin=
  pkg_facility_v2_parameter="$pkg_facility_v2_definition/facility-bin/$pkg_facility_v2_name"
  if [ -e "$pkg_facility_v2_parameter" ] || [ -L "$pkg_facility_v2_parameter" ]
  then
    _pkg_facility_cmd_target_read "$pkg_facility_v2_parameter" || return 1
    pkg_facility_v2_bin=$pkg_facility_cmd_target
    readpathce pkg_facility_v2_directory "$pkg_facility_v2_root/$pkg_facility_v2_bin" || return 1
    case "$pkg_facility_v2_directory" in
      "$pkg_facility_v2_root_resolved"/*) : ;;
      *) return 1 ;;
    esac
    [ -d "$pkg_facility_v2_directory" ] || return 1
  fi

  for pkg_facility_v2_marker in "$pkg_facility_v2_contract"/*
  do
    [ -f "$pkg_facility_v2_marker" ] || return 1
    pkg_facility_v2_command=${pkg_facility_v2_marker##*/}
    pkg_facility_v2_link="$pkg_facility_v2_definition/link/bin/$pkg_facility_v2_command"

    if [ -e "$pkg_facility_v2_link" ] || [ -L "$pkg_facility_v2_link" ]
    then
      [ -f "$pkg_facility_v2_link" ] && [ ! -L "$pkg_facility_v2_link" ] &&
        [ -r "$pkg_facility_v2_link" ] && [ ! -x "$pkg_facility_v2_link" ] || return 1
      pkg_facility_v2_link_target="$(command -p -- cat -- "$pkg_facility_v2_link")" || return 1
      case "$pkg_facility_v2_link_target" in
        "../../cmd/$pkg_facility_v2_command")
          pkg_facility_v2_wrapper="$pkg_facility_v2_definition/cmd/$pkg_facility_v2_command"
          [ -f "$pkg_facility_v2_wrapper" ] && [ ! -L "$pkg_facility_v2_wrapper" ] &&
            [ -r "$pkg_facility_v2_wrapper" ] && [ ! -x "$pkg_facility_v2_wrapper" ] || return 1
          pkg_facility_v2_upstream="$pkg_facility_v2_definition/link/target/$pkg_facility_v2_command"
          [ -f "$pkg_facility_v2_upstream" ] && [ ! -L "$pkg_facility_v2_upstream" ] || return 1
          pkg_facility_v2_link_target="$(command -p -- cat -- "$pkg_facility_v2_upstream")" || return 1
          ;;
      esac
      case "$pkg_facility_v2_link_target" in
        ../../root/*) pkg_facility_v2_relative=${pkg_facility_v2_link_target#../../root/} ;;
        *) return 1 ;;
      esac
      _pkg_facility_cmd_target_path_valid "$pkg_facility_v2_relative" || return 1
      pkg_facility_v2_target="$pkg_facility_v2_root/$pkg_facility_v2_relative"
    else
      [ -n "$pkg_facility_v2_bin" ] || return 1
      pkg_facility_v2_target="$pkg_facility_v2_root/$pkg_facility_v2_bin/$pkg_facility_v2_command"
    fi

    readpathce pkg_facility_v2_resolved "$pkg_facility_v2_target" || return 1
    case "$pkg_facility_v2_resolved" in
      "$pkg_facility_v2_root_resolved"/*) : ;;
      *) return 1 ;;
    esac
    [ -f "$pkg_facility_v2_resolved" ] && [ -x "$pkg_facility_v2_resolved" ] || return 1
  done
}

_pkg_facility_cmd_target_path_valid()
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

_pkg_facility_cmd_v2_entry_validate()
{
  [ "$#" -eq 3 ] || return 2
  pkg_facility_entry_definition=$1
  pkg_facility_entry_root=$2
  pkg_facility_entry_name=$3
  pkg_facility_entry_descriptor="$pkg_facility_entry_definition/link/bin/$pkg_facility_entry_name"
  [ -f "$pkg_facility_entry_descriptor" ] && [ ! -L "$pkg_facility_entry_descriptor" ] || return 1
  pkg_facility_entry_value="$(command -p -- cat -- "$pkg_facility_entry_descriptor")" || return 1
  case "$pkg_facility_entry_value" in
    "../../cmd/$pkg_facility_entry_name")
      [ -f "$pkg_facility_entry_definition/cmd/$pkg_facility_entry_name" ] || return 1
      [ ! -L "$pkg_facility_entry_definition/cmd/$pkg_facility_entry_name" ] || return 1
      pkg_facility_entry_value="$(command -p -- cat -- "$pkg_facility_entry_definition/link/target/$pkg_facility_entry_name")" || return 1
      ;;
  esac
  case "$pkg_facility_entry_value" in
    ../../root/*) pkg_facility_entry_relative=${pkg_facility_entry_value#../../root/} ;;
    *) return 1 ;;
  esac
  _pkg_facility_cmd_target_path_valid "$pkg_facility_entry_relative" || return 1
  readpathce pkg_facility_entry_root_canonical "$pkg_facility_entry_root" || return 1
  readpathce pkg_facility_entry_canonical "$pkg_facility_entry_root/$pkg_facility_entry_relative" || return 1
  case "$pkg_facility_entry_canonical" in
    "$pkg_facility_entry_root_canonical"/*) : ;;
    *) return 1 ;;
  esac
  [ -f "$pkg_facility_entry_canonical" ] && [ -x "$pkg_facility_entry_canonical" ]
}
