_pkg_state_area_root_set()
{
  [ "$#" -eq 2 ] || return 2
  pkg_state_pkg=$1
  pkg_state_area=$2

  case "$pkg_state_area" in
    conf | data | home | cache | log | run | tmp) : ;;
    *) return 1 ;;
  esac

  pkg_state_area_root="$(command -- state-path system pkg "$pkg_state_pkg" "$pkg_state_area")" || return 1
  [ -n "$pkg_state_area_root" ] || return 1
  case "$pkg_state_area_root" in
    /*) : ;;
    *) return 1 ;;
  esac
}

_pkg_state_path_valid()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in
    "" | /* | */ | *//*) return 1 ;;
  esac
  case "/$1/" in
    */./* | */../*) return 1 ;;
  esac
}

_pkg_state_file_validate()
{
  [ "$#" -eq 1 ] || return 2
  [ -f "$1" ] && [ ! -L "$1" ] && [ -r "$1" ] && [ ! -x "$1" ] || return 1

  pkg_state_file_data="$(
    command -p -- cat -- "$1" || exit 1
    printf -- '%s' x
  )" || return 1
  case "$pkg_state_file_data" in
    *'
'x) : ;;
    *) return 1 ;;
  esac

  pkg_state_file_count=0
  while IFS= read -r pkg_state_path
  do
    _pkg_state_path_valid "$pkg_state_path" || return 1
    pkg_state_file_count=$((pkg_state_file_count + 1))
  done < "$1"

  [ "$pkg_state_file_count" -gt 0 ]
}

_pkg_state_source_type_set()
{
  [ "$#" -eq 2 ] || return 2
  pkg_state_source_root=$1
  pkg_state_path=$2
  pkg_state_source_current=$pkg_state_source_root
  pkg_state_source_rest=$pkg_state_path
  pkg_state_source_factory=artifact

  while :
  do
    pkg_state_source_component=${pkg_state_source_rest%%/*}
    pkg_state_source_current="$pkg_state_source_current/$pkg_state_source_component"

    case "$pkg_state_source_rest" in
      */*)
        [ -d "$pkg_state_source_current" ] && [ ! -L "$pkg_state_source_current" ] || return 1
        pkg_state_source_rest=${pkg_state_source_rest#*/}
        ;;
      *)
        [ ! -L "$pkg_state_source_current" ] || return 1
        if [ -f "$pkg_state_source_current" ]
        then
          pkg_state_source_type=file
        elif [ -d "$pkg_state_source_current" ]
        then
          pkg_state_source_type=dir
        elif [ ! -e "$pkg_state_source_current" ]
        then
          pkg_state_source_type=dir
          pkg_state_source_factory=empty-dir
        else
          return 1
        fi
        return 0
        ;;
    esac
  done
}

_pkg_state_existing_validate()
{
  [ "$#" -eq 3 ] || return 2
  pkg_state_area_root=$1
  pkg_state_path=$2
  pkg_state_expected_type=$3

  if [ -e "$pkg_state_area_root" ] || [ -L "$pkg_state_area_root" ]
  then
    [ -d "$pkg_state_area_root" ] && [ ! -L "$pkg_state_area_root" ] || return 1
  else
    return 0
  fi

  pkg_state_existing_current=$pkg_state_area_root
  pkg_state_existing_rest=$pkg_state_path
  while :
  do
    pkg_state_existing_component=${pkg_state_existing_rest%%/*}
    pkg_state_existing_current="$pkg_state_existing_current/$pkg_state_existing_component"

    case "$pkg_state_existing_rest" in
      */*)
        if [ -e "$pkg_state_existing_current" ] || [ -L "$pkg_state_existing_current" ]
        then
          [ -d "$pkg_state_existing_current" ] && [ ! -L "$pkg_state_existing_current" ] || return 1
        else
          return 0
        fi
        pkg_state_existing_rest=${pkg_state_existing_rest#*/}
        ;;
      *)
        if [ ! -e "$pkg_state_existing_current" ] && [ ! -L "$pkg_state_existing_current" ]
        then
          return 0
        fi
        [ ! -L "$pkg_state_existing_current" ] || return 1
        case "$pkg_state_expected_type" in
          file) [ -f "$pkg_state_existing_current" ] ;;
          dir) [ -d "$pkg_state_existing_current" ] ;;
          *) return 2 ;;
        esac
        return $?
        ;;
    esac
  done
}

_pkg_state_path_add()
{
  [ "$#" -eq 2 ] || return 2
  pkg_state_area=$1
  pkg_state_path=$2

  if [ -n "$pkg_state_paths" ]
  then
    while IFS= read -r pkg_state_existing_path
    do
      [ "$pkg_state_path" != "$pkg_state_existing_path" ] || return 1
      case "$pkg_state_path" in
        "$pkg_state_existing_path"/*) return 1 ;;
      esac
      case "$pkg_state_existing_path" in
        "$pkg_state_path"/*) return 1 ;;
      esac
    done <<EOF_PATHS
$pkg_state_paths
EOF_PATHS
  fi

  if [ -n "$pkg_state_paths" ]
  then
    pkg_state_paths="$pkg_state_paths
$pkg_state_path"
    pkg_state_mappings="$pkg_state_mappings
$pkg_state_area/$pkg_state_path"
  else
    pkg_state_paths=$pkg_state_path
    pkg_state_mappings="$pkg_state_area/$pkg_state_path"
  fi
}

_pkg_state_direct_links_validate()
{
  [ "$#" -ge 2 ] && [ "$#" -le 3 ] || return 2
  pkg_state_range=$1
  pkg_state_root=$2
  pkg_state_schema=${3-v1}
  [ -d "$pkg_state_range/link" ] || return 0
  [ -n "$pkg_state_mappings" ] || return 0

  if [ "$pkg_state_schema" = v2 ]
  then
    set -- "$pkg_state_range/link/bin/"* "$pkg_state_range/link/target/"* \
      "$pkg_state_range/link/lib/sh/"* "$pkg_state_range/link/lib/java/"*
  else
    [ "$pkg_state_schema" = v1 ] || return 2
    set -- "$pkg_state_range/link/"*
  fi

  for pkg_state_link_file
  do
    [ -e "$pkg_state_link_file" ] || [ -L "$pkg_state_link_file" ] || continue
    if [ "$pkg_state_schema" = v2 ]
    then
      _pkg_integration_v2_descriptor_read "$pkg_state_link_file" || return 1
      case "$pkg_state_link_file" in
        "$pkg_state_range/link/lib/"*)
          pkg_state_link_prefix=../../../root/
          pkg_state_link_mode=readable
          ;;
        *)
          pkg_state_link_prefix=../../root/
          pkg_state_link_mode=executable
          ;;
      esac
      case "$pkg_v2_target" in
        ../../cmd/*)
          case "$pkg_state_link_file" in
            "$pkg_state_range/link/bin/"*) continue ;;
            *) return 1 ;;
          esac
          ;;
      esac
      _pkg_v2_root_target_validate \
        "$pkg_v2_target" "$pkg_state_root" "$pkg_state_link_prefix" "$pkg_state_link_mode" || return 1
      pkg_state_link_target=$pkg_v2_relative
    else
      _pkg_integration_link_target_read "$pkg_state_link_file" || return 1
      pkg_state_link_target=$pkg_integration_link_target
    fi
    readpathce pkg_state_link_resolved "$pkg_state_root/$pkg_state_link_target" || return 1

    while IFS= read -r pkg_state_mapping
    do
      pkg_state_area=${pkg_state_mapping%%/*}
      pkg_state_path=${pkg_state_mapping#*/}
      pkg_state_source="$pkg_state_root/$pkg_state_path"

      if [ "$pkg_state_link_target" = "$pkg_state_path" ]
      then
        return 1
      fi
      case "$pkg_state_link_target" in
        "$pkg_state_path"/*) return 1 ;;
      esac

      if [ "$pkg_state_link_resolved" = "$pkg_state_source" ]
      then
        return 1
      fi
      if [ -d "$pkg_state_source" ]
      then
        case "$pkg_state_link_resolved" in
          "$pkg_state_source"/*) return 1 ;;
        esac
      fi
    done <<EOF_MAPPINGS
$pkg_state_mappings
EOF_MAPPINGS
  done
}

_pkg_state_validate()
{
  [ "$#" -ge 3 ] && [ "$#" -le 4 ] || return 2
  pkg_state_range=$1
  pkg_state_root=$2
  pkg_state_pkg=$3
  pkg_state_schema=${4-v1}
  case "$pkg_state_schema" in
    v1) pkg_state_var="$pkg_state_range/var" ;;
    v2) pkg_state_var="$pkg_state_range/state-map" ;;
    *) return 2 ;;
  esac
  pkg_state_paths=
  pkg_state_mappings=

  if [ ! -e "$pkg_state_var" ] && [ ! -L "$pkg_state_var" ]
  then
    return 0
  fi
  [ -d "$pkg_state_var" ] && [ ! -L "$pkg_state_var" ] || return 1

  for pkg_state_area_file in \
    "$pkg_state_var"/* \
    "$pkg_state_var"/.[!.]* \
    "$pkg_state_var"/..?*
  do
    [ -e "$pkg_state_area_file" ] || [ -L "$pkg_state_area_file" ] || continue
    pkg_state_area=${pkg_state_area_file##*/}
    case "$pkg_state_area" in
      conf | data | home | cache | log | run | tmp) : ;;
      *) return 1 ;;
    esac
    _pkg_state_file_validate "$pkg_state_area_file" || return 1
    _pkg_state_area_root_set "$pkg_state_pkg" "$pkg_state_area" || return 1
    pkg_state_current_area_root=$pkg_state_area_root

    while IFS= read -r pkg_state_path
    do
      case "$pkg_state_area/$pkg_state_path" in
        conf/.m | conf/.m/*) return 1 ;;
      esac
      _pkg_state_source_type_set "$pkg_state_root" "$pkg_state_path" || return 1
      pkg_state_current_type=$pkg_state_source_type
      _pkg_state_existing_validate "$pkg_state_current_area_root" "$pkg_state_path" "$pkg_state_current_type" || return 1
      _pkg_state_path_add "$pkg_state_area" "$pkg_state_path" || return 1
    done < "$pkg_state_area_file"
  done

  [ -z "$pkg_state_mappings" ] || [ "$pkg_state_pkg" != sys ] || return 1
  _pkg_state_direct_links_validate "$pkg_state_range" "$pkg_state_root" "$pkg_state_schema"
}

_pkg_state_created_dir_add()
{
  [ "$#" -eq 1 ] || return 2
  if [ -n "$pkg_state_created_dirs" ]
  then
    pkg_state_created_dirs="$1
$pkg_state_created_dirs"
  else
    pkg_state_created_dirs=$1
  fi
}

_pkg_state_created_object_add()
{
  [ "$#" -eq 1 ] || return 2
  if [ -n "$pkg_state_created_objects" ]
  then
    pkg_state_created_objects="$1
$pkg_state_created_objects"
  else
    pkg_state_created_objects=$1
  fi
}

_pkg_state_materialized_add()
{
  [ "$#" -eq 1 ] || return 2
  if [ -n "$pkg_state_materialized" ]
  then
    pkg_state_materialized="$1
$pkg_state_materialized"
  else
    pkg_state_materialized=$1
  fi
}

_pkg_state_synthesized_add()
{
  [ "$#" -eq 1 ] || return 2
  if [ -n "$pkg_state_synthesized" ]
  then
    pkg_state_synthesized="$1
$pkg_state_synthesized"
  else
    pkg_state_synthesized=$1
  fi
}

_pkg_state_synthesized_has()
{
  [ "$#" -eq 1 ] || return 2
  [ -n "$pkg_state_synthesized" ] || return 1

  while IFS= read -r pkg_state_synthesized_mapping
  do
    [ "$pkg_state_synthesized_mapping" = "$1" ] && return 0
  done <<EOF_SYNTHESIZED
$pkg_state_synthesized
EOF_SYNTHESIZED

  return 1
}

_pkg_state_dir_ensure_owned()
{
  [ "$#" -eq 1 ] || return 2
  if [ -e "$1" ] || [ -L "$1" ]
  then
    [ -d "$1" ] && [ ! -L "$1" ]
    return $?
  fi
  command -p -- mkdir -- "$1" || return 1
  _pkg_state_created_dir_add "$1"
}

_pkg_state_area_root_ensure()
{
  [ "$#" -eq 1 ] || return 2
  if [ -e "$1" ] || [ -L "$1" ]
  then
    [ -d "$1" ] && [ ! -L "$1" ]
    return $?
  fi
  command -p -- mkdir -p -- "$1" || return 1
  [ -d "$1" ] && [ ! -L "$1" ] || return 1
  _pkg_state_created_dir_add "$1"
}

_pkg_state_parent_dirs_ensure()
{
  [ "$#" -eq 2 ] || return 2
  pkg_state_area_root=$1
  pkg_state_path=$2
  _pkg_state_area_root_ensure "$pkg_state_area_root" || return 1
  pkg_state_current=$pkg_state_area_root

  pkg_state_parent=${pkg_state_path%/*}
  [ "$pkg_state_parent" != "$pkg_state_path" ] || return 0
  pkg_state_rest=$pkg_state_parent
  while :
  do
    pkg_state_component=${pkg_state_rest%%/*}
    pkg_state_current="$pkg_state_current/$pkg_state_component"
    _pkg_state_dir_ensure_owned "$pkg_state_current" || return 1
    case "$pkg_state_rest" in
      */*) pkg_state_rest=${pkg_state_rest#*/} ;;
      *) break ;;
    esac
  done
}

_pkg_state_default_parent_ensure()
{
  [ "$#" -eq 3 ] || return 2
  pkg_state_concrete=$1
  pkg_state_area=$2
  pkg_state_path=$3
  pkg_state_default_area="$pkg_state_concrete/default/$pkg_state_area"
  command -p -- mkdir -p -- "$pkg_state_default_area" || return 1

  pkg_state_parent=${pkg_state_path%/*}
  [ "$pkg_state_parent" != "$pkg_state_path" ] || return 0
  command -p -- mkdir -p -- "$pkg_state_default_area/$pkg_state_parent"
}

_pkg_state_var_area_ensure()
{
  [ "$#" -eq 3 ] || return 2
  pkg_state_concrete=$1
  pkg_state_area=$2
  pkg_state_pkg=$3
  pkg_state_var_dir="$pkg_state_concrete/var"
  pkg_state_var_link="$pkg_state_var_dir/$pkg_state_area"
  pkg_state_var_target="../../../state/system/current/pkg/$pkg_state_pkg/$pkg_state_area"

  if [ ! -e "$pkg_state_var_dir" ] && [ ! -L "$pkg_state_var_dir" ]
  then
    command -p -- mkdir -- "$pkg_state_var_dir" || return 1
  fi
  [ -d "$pkg_state_var_dir" ] && [ ! -L "$pkg_state_var_dir" ] || return 1

  if [ -L "$pkg_state_var_link" ]
  then
    pkg_state_existing_target="$(command -p -- readlink "$pkg_state_var_link")" || return 1
    [ "$pkg_state_existing_target" = "$pkg_state_var_target" ]
    return $?
  fi
  [ ! -e "$pkg_state_var_link" ] || return 1
  command -p -- ln -s "$pkg_state_var_target" "$pkg_state_var_link"
}

_pkg_state_root_link_target_set()
{
  [ "$#" -eq 2 ] || return 2
  pkg_state_area=$1
  pkg_state_path=$2
  pkg_state_rest=$pkg_state_path
  pkg_state_up=

  while :
  do
    pkg_state_up="../$pkg_state_up"
    case "$pkg_state_rest" in
      */*) pkg_state_rest=${pkg_state_rest#*/} ;;
      *) break ;;
    esac
  done

  pkg_state_root_link_target="${pkg_state_up}var/$pkg_state_area/$pkg_state_path"
}

_pkg_state_initialize_object()
{
  [ "$#" -eq 3 ] || return 2
  pkg_state_factory=$1
  pkg_state_destination=$2
  pkg_state_type=$3

  case "$pkg_state_type" in
    file) command -p -- cp -- "$pkg_state_factory" "$pkg_state_destination" ;;
    dir) command -p -- cp -R -- "$pkg_state_factory" "$pkg_state_destination" ;;
    *) return 2 ;;
  esac
}

_pkg_state_rollback()
{
  [ "$#" -eq 1 ] || return 2
  pkg_state_concrete=$1
  pkg_state_rollback_status=0

  if [ -n "${pkg_state_materialized-}" ]
  then
    while IFS= read -r pkg_state_mapping
    do
      pkg_state_area=${pkg_state_mapping%%/*}
      pkg_state_path=${pkg_state_mapping#*/}
      pkg_state_root_path="$pkg_state_concrete/root/$pkg_state_path"
      pkg_state_default_path="$pkg_state_concrete/default/$pkg_state_area/$pkg_state_path"

      if [ -L "$pkg_state_root_path" ]
      then
        command -p -- rm -f -- "$pkg_state_root_path" || pkg_state_rollback_status=1
      elif [ -e "$pkg_state_root_path" ]
      then
        pkg_state_rollback_status=1
        continue
      fi

      if [ -e "$pkg_state_default_path" ] || [ -L "$pkg_state_default_path" ]
      then
        if _pkg_state_synthesized_has "$pkg_state_mapping"
        then
          command -p -- rm -rf -- "$pkg_state_default_path" || pkg_state_rollback_status=1
        else
          command -p -- mv -- "$pkg_state_default_path" "$pkg_state_root_path" || pkg_state_rollback_status=1
        fi
      else
        pkg_state_rollback_status=1
      fi
    done <<EOF_MATERIALIZED
$pkg_state_materialized
EOF_MATERIALIZED
  fi

  command -p -- rm -rf -- "$pkg_state_concrete/default" "$pkg_state_concrete/var" 2>/dev/null || pkg_state_rollback_status=1

  if [ -n "${pkg_state_created_objects-}" ]
  then
    while IFS= read -r pkg_state_created_object
    do
      command -p -- rm -rf -- "$pkg_state_created_object" 2>/dev/null || pkg_state_rollback_status=1
    done <<EOF_OBJECTS
$pkg_state_created_objects
EOF_OBJECTS
  fi

  if [ -n "${pkg_state_created_dirs-}" ]
  then
    while IFS= read -r pkg_state_created_dir
    do
      if [ -d "$pkg_state_created_dir" ] && [ ! -L "$pkg_state_created_dir" ]
      then
        command -p -- rmdir -- "$pkg_state_created_dir" 2>/dev/null || :
      fi
    done <<EOF_DIRS
$pkg_state_created_dirs
EOF_DIRS
  fi

  return "$pkg_state_rollback_status"
}

_pkg_state_materialize()
{
  [ "$#" -ge 3 ] && [ "$#" -le 4 ] || return 2
  pkg_state_range=$1
  pkg_state_concrete=$2
  pkg_state_pkg=$3
  pkg_state_schema=${4-v1}
  pkg_state_created_dirs=
  pkg_state_created_objects=
  pkg_state_materialized=
  pkg_state_synthesized=

  _pkg_state_validate "$pkg_state_range" "$pkg_state_concrete/root" "$pkg_state_pkg" "$pkg_state_schema" || return 1
  [ -n "$pkg_state_mappings" ] || return 0

  while IFS= read -r pkg_state_mapping
  do
    pkg_state_area=${pkg_state_mapping%%/*}
    pkg_state_path=${pkg_state_mapping#*/}
    _pkg_state_area_root_set "$pkg_state_pkg" "$pkg_state_area" || {
      _pkg_state_rollback "$pkg_state_concrete" >/dev/null 2>&1 || :
      return 1
    }
    pkg_state_current_area_root=$pkg_state_area_root
    _pkg_state_source_type_set "$pkg_state_concrete/root" "$pkg_state_path" || {
      _pkg_state_rollback "$pkg_state_concrete" >/dev/null 2>&1 || :
      return 1
    }
    pkg_state_current_type=$pkg_state_source_type
    pkg_state_current_factory=$pkg_state_source_factory
    pkg_state_source="$pkg_state_concrete/root/$pkg_state_path"
    pkg_state_default="$pkg_state_concrete/default/$pkg_state_area/$pkg_state_path"
    pkg_state_destination="$pkg_state_current_area_root/$pkg_state_path"

    _pkg_state_default_parent_ensure "$pkg_state_concrete" "$pkg_state_area" "$pkg_state_path" || {
      _pkg_state_rollback "$pkg_state_concrete" >/dev/null 2>&1 || :
      return 1
    }
    case "$pkg_state_current_factory" in
      artifact)
        command -p -- mv -- "$pkg_state_source" "$pkg_state_default" || {
          _pkg_state_rollback "$pkg_state_concrete" >/dev/null 2>&1 || :
          return 1
        }
        ;;
      empty-dir)
        command -p -- mkdir -- "$pkg_state_default" || {
          _pkg_state_rollback "$pkg_state_concrete" >/dev/null 2>&1 || :
          return 1
        }
        _pkg_state_synthesized_add "$pkg_state_mapping" || {
          _pkg_state_rollback "$pkg_state_concrete" >/dev/null 2>&1 || :
          return 1
        }
        ;;
      *)
        _pkg_state_rollback "$pkg_state_concrete" >/dev/null 2>&1 || :
        return 1
        ;;
    esac
    _pkg_state_materialized_add "$pkg_state_mapping" || {
      _pkg_state_rollback "$pkg_state_concrete" >/dev/null 2>&1 || :
      return 1
    }

    if [ ! -e "$pkg_state_destination" ] && [ ! -L "$pkg_state_destination" ]
    then
      _pkg_state_parent_dirs_ensure "$pkg_state_current_area_root" "$pkg_state_path" || {
        _pkg_state_rollback "$pkg_state_concrete" >/dev/null 2>&1 || :
        return 1
      }
      if ! _pkg_state_initialize_object "$pkg_state_default" "$pkg_state_destination" "$pkg_state_current_type"
      then
        command -p -- rm -rf -- "$pkg_state_destination" 2>/dev/null || :
        _pkg_state_rollback "$pkg_state_concrete" >/dev/null 2>&1 || :
        return 1
      fi
      _pkg_state_created_object_add "$pkg_state_destination" || {
        _pkg_state_rollback "$pkg_state_concrete" >/dev/null 2>&1 || :
        return 1
      }
    fi

    _pkg_state_var_area_ensure "$pkg_state_concrete" "$pkg_state_area" "$pkg_state_pkg" || {
      _pkg_state_rollback "$pkg_state_concrete" >/dev/null 2>&1 || :
      return 1
    }
    _pkg_state_root_link_target_set "$pkg_state_area" "$pkg_state_path" || {
      _pkg_state_rollback "$pkg_state_concrete" >/dev/null 2>&1 || :
      return 1
    }
    command -p -- ln -s "$pkg_state_root_link_target" "$pkg_state_source" || {
      _pkg_state_rollback "$pkg_state_concrete" >/dev/null 2>&1 || :
      return 1
    }
  done <<EOF_MAPPINGS
$pkg_state_mappings
EOF_MAPPINGS

  return 0
}
