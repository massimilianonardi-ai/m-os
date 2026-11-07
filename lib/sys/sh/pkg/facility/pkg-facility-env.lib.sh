_pkg_facility_env_name_valid()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in
    "" | [!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_]* | *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_]*) return 1 ;;
  esac
}

_pkg_facility_env_contract_validate()
{
  [ "$#" -eq 1 ] || return 2
  pkg_facility_env_contract=$1

  [ -d "$pkg_facility_env_contract" ] && [ ! -L "$pkg_facility_env_contract" ] || return 1
  _pkg_facility_dir_entries_empty "$pkg_facility_env_contract" && return 1

  for pkg_facility_env_marker in "$pkg_facility_env_contract"/*
  do
    [ -e "$pkg_facility_env_marker" ] || [ -L "$pkg_facility_env_marker" ] || continue
    pkg_facility_env_name=${pkg_facility_env_marker##*/}
    _pkg_facility_env_name_valid "$pkg_facility_env_name" || return 1
    [ -f "$pkg_facility_env_marker" ] && [ ! -L "$pkg_facility_env_marker" ] && [ -r "$pkg_facility_env_marker" ] && [ ! -x "$pkg_facility_env_marker" ] && [ ! -s "$pkg_facility_env_marker" ] || return 1
  done

  for pkg_facility_env_hidden in "$pkg_facility_env_contract"/.[!.]* "$pkg_facility_env_contract"/..?*
  do
    [ -e "$pkg_facility_env_hidden" ] || [ -L "$pkg_facility_env_hidden" ] || continue
    return 1
  done
}

_pkg_facility_env_relative_path_valid()
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

_pkg_facility_env_descriptor_validate()
{
  [ "$#" -eq 2 ] || return 2
  pkg_facility_env_descriptor=$1
  pkg_facility_env_root=$2

  case "$pkg_facility_env_descriptor" in
    root | literal)
      return 0
      ;;
    "root-path "*)
      pkg_facility_env_relative=${pkg_facility_env_descriptor#root-path }
      _pkg_facility_env_relative_path_valid "$pkg_facility_env_relative" || return 1
      [ -e "$pkg_facility_env_root/$pkg_facility_env_relative" ] || [ -L "$pkg_facility_env_root/$pkg_facility_env_relative" ] || return 1
      readpathce pkg_facility_env_resolved "$pkg_facility_env_root/$pkg_facility_env_relative" || return 1
      case "$pkg_facility_env_resolved" in
        "$pkg_facility_env_root_resolved"/*) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    "literal "*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

_pkg_facility_env_realization_validate()
{
  [ "$#" -eq 2 ] || return 2
  pkg_facility_env_realization=$1
  pkg_facility_env_root=$2

  [ -f "$pkg_facility_env_realization" ] && [ ! -L "$pkg_facility_env_realization" ] && [ -r "$pkg_facility_env_realization" ] && [ ! -x "$pkg_facility_env_realization" ] || return 1
  [ -d "$pkg_facility_env_root" ] && [ ! -L "$pkg_facility_env_root" ] || return 1
  readpathce pkg_facility_env_root_resolved "$pkg_facility_env_root" || return 1

  pkg_facility_env_original="$(
    command -p -- cat -- "$pkg_facility_env_realization" || exit 1
    printf -- '%s' x
  )" || return 1
  pkg_facility_env_sorted="$(
    LC_ALL=C command -p -- sort < "$pkg_facility_env_realization" || exit 1
    printf -- '%s' x
  )" || return 1
  [ "$pkg_facility_env_original" = "$pkg_facility_env_sorted" ] || return 1

  pkg_facility_env_tab="$(printf '\t')"
  pkg_facility_env_previous=
  pkg_facility_env_realization_count=0
  while IFS= read -r pkg_facility_env_line
  do
    case "$pkg_facility_env_line" in
      *"$pkg_facility_env_tab"*) : ;;
      *) return 1 ;;
    esac
    pkg_facility_env_name=${pkg_facility_env_line%%"$pkg_facility_env_tab"*}
    pkg_facility_env_descriptor=${pkg_facility_env_line#*"$pkg_facility_env_tab"}
    case "$pkg_facility_env_descriptor" in *"$pkg_facility_env_tab"*) return 1 ;; esac

    _pkg_facility_env_name_valid "$pkg_facility_env_name" || return 1
    if [ "$pkg_facility_env_name" = "$pkg_facility_env_previous" ] && [ "$pkg_facility_env_name" != PATH ]
    then
      return 1
    fi
    pkg_facility_env_previous=$pkg_facility_env_name

    if [ "$pkg_facility_env_name" = PATH ]
    then
      case "$pkg_facility_env_descriptor" in
        root | "root-path "*) : ;;
        *) return 1 ;;
      esac
    fi

    _pkg_facility_env_descriptor_validate "$pkg_facility_env_descriptor" "$pkg_facility_env_root" || return 1
    if [ "$pkg_facility_env_name" = PATH ]
    then
      case "$pkg_facility_env_descriptor" in
        "root-path "*)
          [ -d "$pkg_facility_env_resolved" ] || return 1
          ;;
      esac
    fi
    pkg_facility_env_realization_count=$((pkg_facility_env_realization_count + 1))
  done < "$pkg_facility_env_realization"

  [ "$pkg_facility_env_realization_count" -gt 0 ]
}

_pkg_facility_env_provider_validate()
{
  [ "$#" -eq 3 ] || return 2
  pkg_facility_env_contract=$1
  pkg_facility_env_realization=$2
  pkg_facility_env_root=$3

  _pkg_facility_env_contract_validate "$pkg_facility_env_contract" || return 1
  _pkg_facility_env_realization_validate "$pkg_facility_env_realization" "$pkg_facility_env_root" || return 1

  pkg_facility_env_tab="$(printf '\t')"
  pkg_facility_env_realization_count=0
  pkg_facility_env_previous=
  while IFS= read -r pkg_facility_env_line
  do
    pkg_facility_env_name=${pkg_facility_env_line%%"$pkg_facility_env_tab"*}
    [ -f "$pkg_facility_env_contract/$pkg_facility_env_name" ] && [ ! -L "$pkg_facility_env_contract/$pkg_facility_env_name" ] || return 1
    if [ "$pkg_facility_env_name" != "$pkg_facility_env_previous" ]
    then
      pkg_facility_env_realization_count=$((pkg_facility_env_realization_count + 1))
      pkg_facility_env_previous=$pkg_facility_env_name
    fi
  done < "$pkg_facility_env_realization"

  pkg_facility_env_contract_count=0
  for pkg_facility_env_marker in "$pkg_facility_env_contract"/*
  do
    [ -e "$pkg_facility_env_marker" ] || [ -L "$pkg_facility_env_marker" ] || continue
    pkg_facility_env_contract_count=$((pkg_facility_env_contract_count + 1))
  done

  [ "$pkg_facility_env_realization_count" -eq "$pkg_facility_env_contract_count" ]
}

# In v2 the facility contract owns the variable names; the provider supplies
# only typed values for those required names. PATH may have multiple ordered
# contributions, while ordinary variables have exactly one value.
_pkg_facility_env_v2_provider_validate()
{
  [ "$#" -eq 3 ] || return 2
  pkg_facility_v2_env_contract=$1
  pkg_facility_v2_env_realization=$2
  pkg_facility_v2_env_root=$3

  _pkg_facility_env_contract_validate "$pkg_facility_v2_env_contract" || return 1
  [ -d "$pkg_facility_v2_env_realization" ] &&
    [ ! -L "$pkg_facility_v2_env_realization" ] || return 1
  [ -d "$pkg_facility_v2_env_root" ] &&
    [ ! -L "$pkg_facility_v2_env_root" ] || return 1
  readpathce pkg_facility_env_root_resolved "$pkg_facility_v2_env_root" || return 1

  for pkg_facility_v2_env_entry in \
    "$pkg_facility_v2_env_realization"/* \
    "$pkg_facility_v2_env_realization"/.[!.]* \
    "$pkg_facility_v2_env_realization"/..?*
  do
    [ -e "$pkg_facility_v2_env_entry" ] ||
      [ -L "$pkg_facility_v2_env_entry" ] || continue
    pkg_facility_v2_env_name=${pkg_facility_v2_env_entry##*/}
    [ -f "$pkg_facility_v2_env_contract/$pkg_facility_v2_env_name" ] &&
      [ ! -L "$pkg_facility_v2_env_contract/$pkg_facility_v2_env_name" ] || return 1
    [ -f "$pkg_facility_v2_env_entry" ] &&
      [ ! -L "$pkg_facility_v2_env_entry" ] &&
      [ -r "$pkg_facility_v2_env_entry" ] &&
      [ ! -x "$pkg_facility_v2_env_entry" ] || return 1
  done

  for pkg_facility_v2_env_marker in "$pkg_facility_v2_env_contract"/*
  do
    pkg_facility_v2_env_name=${pkg_facility_v2_env_marker##*/}
    pkg_facility_v2_env_value_file="$pkg_facility_v2_env_realization/$pkg_facility_v2_env_name"
    [ -f "$pkg_facility_v2_env_value_file" ] &&
      [ ! -L "$pkg_facility_v2_env_value_file" ] &&
      [ -r "$pkg_facility_v2_env_value_file" ] &&
      [ ! -x "$pkg_facility_v2_env_value_file" ] || return 1

    pkg_facility_v2_env_count=0
    while IFS= read -r pkg_facility_v2_env_descriptor
    do
      _pkg_facility_env_descriptor_validate \
        "$pkg_facility_v2_env_descriptor" "$pkg_facility_v2_env_root" || return 1
      if [ "$pkg_facility_v2_env_name" = PATH ]
      then
        case "$pkg_facility_v2_env_descriptor" in
          root | "root-path "*) : ;;
          *) return 1 ;;
        esac
        case "$pkg_facility_v2_env_descriptor" in
          "root-path "*) [ -d "$pkg_facility_env_resolved" ] || return 1 ;;
        esac
      fi
      pkg_facility_v2_env_count=$((pkg_facility_v2_env_count + 1))
      [ "$pkg_facility_v2_env_name" = PATH ] ||
        [ "$pkg_facility_v2_env_count" -eq 1 ] || return 1
    done < "$pkg_facility_v2_env_value_file"
    [ "$pkg_facility_v2_env_count" -gt 0 ] || return 1
  done
}
