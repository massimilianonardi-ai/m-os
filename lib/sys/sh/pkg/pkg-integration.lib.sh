loadsyslib "pkg/pkg-common"
loadsyslib "pkg/facility/pkg-facility"
loadsyslib "pkg/facility/pkg-dependency"
loadsyslib "pkg/pkg-state"
loadsyslib "pkg/pkg-setuid"

_pkg_integration_error()
{
  log error execution execution-failed operation "$1" reason "$2"
}

_pkg_integration_restore_input()
{
  [ "$#" -eq 2 ] || return 2
  pkg_integration_restore_concrete=$1
  pkg_integration_restore_input=$2

  for pkg_integration_restore_entry in \
    "$pkg_integration_restore_concrete"/* \
    "$pkg_integration_restore_concrete"/.[!.]* \
    "$pkg_integration_restore_concrete"/..?*
  do
    [ -e "$pkg_integration_restore_entry" ] || [ -L "$pkg_integration_restore_entry" ] || continue
    [ "${pkg_integration_restore_entry##*/}" = root ] && continue
    command -p -- rm -rf -- "$pkg_integration_restore_entry" 2>/dev/null || :
  done

  if command -p -- mv -- "$pkg_integration_restore_concrete/root" "$pkg_integration_restore_input" 2>/dev/null
  then
    command -p -- rmdir -- "$pkg_integration_restore_concrete" 2>/dev/null || :
    return 0
  fi

  return 1
}

_pkg_integration_set_class()
{
  [ "$#" -eq 2 ] || return 2
  pkg_integration_pkg=$1
  pkg_integration_osarch=$2

  if [ -n "$pkg_integration_osarch" ]
  then
    pkg_integration_selector_name="$pkg_integration_pkg!$pkg_integration_osarch"
    pkg_integration_public_dir="$m_BIN_DIR/ext-$pkg_integration_osarch"
  else
    pkg_integration_selector_name=$pkg_integration_pkg
    pkg_integration_public_dir=$m_BIN_EXT_DIR
  fi

  pkg_integration_selector="$m_PKG_DIR/$pkg_integration_selector_name"
}

_pkg_integration_set_concrete()
{
  [ "$#" -eq 3 ] || return 2
  _pkg_integration_set_class "$1" "$3" || return 1
  pkg_integration_version=$2

  if [ -n "$pkg_integration_osarch" ]
  then
    pkg_integration_concrete_name="$pkg_integration_pkg@$pkg_integration_version!$pkg_integration_osarch"
  else
    pkg_integration_concrete_name="$pkg_integration_pkg@$pkg_integration_version"
  fi

  pkg_integration_concrete="$m_PKG_DIR/$pkg_integration_concrete_name"
}

_pkg_integration_dir_entries_empty()
{
  [ "$#" -eq 1 ] || return 2
  for pkg_integration_entry in \
    "$1"/* \
    "$1"/.[!.]* \
    "$1"/..?*
  do
    [ -e "$pkg_integration_entry" ] || [ -L "$pkg_integration_entry" ] || continue
    return 1
  done
  return 0
}

_pkg_integration_link_target_read()
{
  [ "$#" -eq 1 ] || return 2
  [ -f "$1" ] && [ ! -L "$1" ] && [ -r "$1" ] && [ ! -x "$1" ] || return 1

  pkg_integration_link_target="$(command -p -- cat -- "$1")" || return 1
  case "$pkg_integration_link_target" in
    "" | /* | */ | *//*) return 1 ;;
  esac
  case "$pkg_integration_link_target" in
    *'
'*) return 1 ;;
  esac
  case "/$pkg_integration_link_target/" in
    */./* | */../*) return 1 ;;
  esac

  return 0
}

_pkg_integration_env_validate()
{
  [ "$#" -eq 1 ] || return 2
  [ -f "$1" ] && [ ! -L "$1" ] && [ -r "$1" ] && [ ! -x "$1" ] || return 1
  command -p -- sh -n "$1" >/dev/null 2>&1
}

_pkg_integration_facility_declared()
{
  [ "$#" -eq 2 ] || return 2
  pkg_integration_facility_file="$1/facility"
  pkg_integration_required_facility=$2

  _pkg_facility_file_validate "$pkg_integration_facility_file" || return 1
  while IFS= read -r pkg_integration_facility_line
  do
    _pkg_facility_line_parse "$pkg_integration_facility_line" || return 1
    [ "$pkg_facility_name" = "$pkg_integration_required_facility" ] && return 0
  done < "$pkg_integration_facility_file"
  return 1
}

_pkg_integration_facility_cmd_validate()
{
  [ "$#" -eq 2 ] || return 2
  pkg_integration_projection_range=$1
  pkg_integration_projection_root=$2
  pkg_integration_projection_dir="$pkg_integration_projection_range/facility-cmd"

  if [ ! -e "$pkg_integration_projection_dir" ] && [ ! -L "$pkg_integration_projection_dir" ]
  then
    return 0
  fi

  valid_dir "$pkg_integration_projection_dir" || return 1
  _pkg_integration_dir_entries_empty "$pkg_integration_projection_dir" && return 1

  for pkg_integration_facility_dir in "$pkg_integration_projection_dir"/*
  do
    [ -e "$pkg_integration_facility_dir" ] || [ -L "$pkg_integration_facility_dir" ] || continue
    pkg_integration_projection_facility=${pkg_integration_facility_dir##*/}
    _pkg_facility_name_valid "$pkg_integration_projection_facility" || return 1
    _pkg_integration_facility_declared "$pkg_integration_projection_range" "$pkg_integration_projection_facility" || return 1
    _pkg_facility_cmd_realization_validate \
      "$pkg_integration_facility_dir" \
      "$pkg_integration_projection_range" \
      "$pkg_integration_projection_root" || return 1
  done

  for pkg_integration_hidden in "$pkg_integration_projection_dir"/.[!.]* "$pkg_integration_projection_dir"/..?*
  do
    [ -e "$pkg_integration_hidden" ] || [ -L "$pkg_integration_hidden" ] || continue
    return 1
  done
}

_pkg_integration_facility_env_validate()
{
  [ "$#" -eq 2 ] || return 2
  pkg_integration_projection_range=$1
  pkg_integration_projection_root=$2
  pkg_integration_projection_dir="$pkg_integration_projection_range/facility-env"

  if [ ! -e "$pkg_integration_projection_dir" ] && [ ! -L "$pkg_integration_projection_dir" ]
  then
    return 0
  fi

  valid_dir "$pkg_integration_projection_dir" || return 1
  _pkg_integration_dir_entries_empty "$pkg_integration_projection_dir" && return 1

  for pkg_integration_env_file in "$pkg_integration_projection_dir"/*
  do
    [ -e "$pkg_integration_env_file" ] || [ -L "$pkg_integration_env_file" ] || continue
    pkg_integration_projection_facility=${pkg_integration_env_file##*/}
    _pkg_facility_name_valid "$pkg_integration_projection_facility" || return 1
    _pkg_integration_facility_declared "$pkg_integration_projection_range" "$pkg_integration_projection_facility" || return 1
    _pkg_facility_env_realization_validate "$pkg_integration_env_file" "$pkg_integration_projection_root" || return 1
  done

  for pkg_integration_hidden in "$pkg_integration_projection_dir"/.[!.]* "$pkg_integration_projection_dir"/..?*
  do
    [ -e "$pkg_integration_hidden" ] || [ -L "$pkg_integration_hidden" ] || continue
    return 1
  done
}
_pkg_integration_facility_service_validate()
{
  [ "$#" -eq 2 ] || return 2
  pkg_integration_service_range=$1
  pkg_integration_service_root=$2
  pkg_integration_service_dir="$pkg_integration_service_range/facility-service"

  if [ ! -e "$pkg_integration_service_dir" ] && [ ! -L "$pkg_integration_service_dir" ]
  then
    return 0
  fi

  valid_dir "$pkg_integration_service_dir" || return 1
  _pkg_integration_dir_entries_empty "$pkg_integration_service_dir" && return 1

  for pkg_integration_service_facility_dir in "$pkg_integration_service_dir"/*
  do
    [ -e "$pkg_integration_service_facility_dir" ] || [ -L "$pkg_integration_service_facility_dir" ] || continue
    pkg_integration_service_facility=${pkg_integration_service_facility_dir##*/}
    _pkg_facility_name_valid "$pkg_integration_service_facility" || return 1
    _pkg_integration_facility_declared "$pkg_integration_service_range" "$pkg_integration_service_facility" || return 1
    _pkg_facility_service_realization_validate \
      "$pkg_integration_service_facility_dir" \
      "$pkg_integration_service_range" \
      "$pkg_integration_service_root" || return 1
  done

  for pkg_integration_service_hidden in "$pkg_integration_service_dir"/.[!.]* "$pkg_integration_service_dir"/..?*
  do
    [ -e "$pkg_integration_service_hidden" ] || [ -L "$pkg_integration_service_hidden" ] || continue
    return 1
  done
}

_pkg_integration_facility_projection_validate()
{
  [ "$#" -eq 2 ] || return 2
  _pkg_integration_facility_cmd_validate "$1" "$2" || return 1
  _pkg_integration_facility_env_validate "$1" "$2" || return 1
  _pkg_integration_facility_service_validate "$1" "$2"
}

_pkg_integration_component_file_validate()
{
  [ "$#" -eq 1 ] || return 2
  [ -f "$1" ] && [ ! -L "$1" ] && [ -r "$1" ] && [ ! -x "$1" ] || return 1

  pkg_integration_component_value="$(command -p -- cat -- "$1")" || return 1
  case "$pkg_integration_component_value" in
    ""|.|..|*/*|*'
'*) return 1 ;;
    *.pkg) return 0 ;;
    *) return 1 ;;
  esac
}

_pkg_integration_dmg_overlay_validate()
{
  [ "$#" -eq 1 ] || return 2
  pkg_integration_overlay_dir=$1
  valid_dir "$pkg_integration_overlay_dir" || return 1
  _pkg_integration_dir_entries_empty "$pkg_integration_overlay_dir" && return 1

  for pkg_integration_overlay_entry in \
    "$pkg_integration_overlay_dir"/* \
    "$pkg_integration_overlay_dir"/.[!.]* \
    "$pkg_integration_overlay_dir"/..?*
  do
    [ -e "$pkg_integration_overlay_entry" ] || [ -L "$pkg_integration_overlay_entry" ] || continue
    pkg_integration_overlay_name=${pkg_integration_overlay_entry##*/}
    pkg_name_valid "$pkg_integration_overlay_name" || return 1
    valid_dir "$pkg_integration_overlay_entry" || return 1

    pkg_integration_overlay_component=
    pkg_integration_overlay_payload_root=
    pkg_integration_overlay_target_root=

    for pkg_integration_overlay_field in \
      "$pkg_integration_overlay_entry"/* \
      "$pkg_integration_overlay_entry"/.[!.]* \
      "$pkg_integration_overlay_entry"/..?*
    do
      [ -e "$pkg_integration_overlay_field" ] || [ -L "$pkg_integration_overlay_field" ] || continue
      case "${pkg_integration_overlay_field##*/}" in
        component)
          [ -z "$pkg_integration_overlay_component" ] || return 1
          _pkg_integration_component_file_validate "$pkg_integration_overlay_field" || return 1
          pkg_integration_overlay_component=$pkg_integration_overlay_field
          ;;
        payload-root)
          [ -z "$pkg_integration_overlay_payload_root" ] || return 1
          _pkg_integration_link_target_read "$pkg_integration_overlay_field" || return 1
          pkg_integration_overlay_payload_root=$pkg_integration_overlay_field
          ;;
        target-root)
          [ -z "$pkg_integration_overlay_target_root" ] || return 1
          _pkg_integration_link_target_read "$pkg_integration_overlay_field" || return 1
          pkg_integration_overlay_target_root=$pkg_integration_overlay_field
          ;;
        *)
          return 1
          ;;
      esac
    done

    [ -n "$pkg_integration_overlay_component" ] || return 1
  done

  return 0
}

# Library exports are ordinary package capabilities, independent of facilities.
# Descriptor leaf: <library>.lib.sh or <archive>.jar.
# Descriptor content: relative pathname inside the validated useful root.
# Library descriptors share one typed materializer. V1 descriptors name
# root-relative files; v2 descriptors are relative symlink destinations.
_pkg_integration_libraries_validate()
{
  [ "$#" -ge 2 ] && [ "$#" -le 3 ] || return 2
  pkg_integration_lib_range=$1
  pkg_integration_lib_root=$2
  pkg_integration_lib_schema=${3-v1}
  case "$pkg_integration_lib_schema" in
    v1) pkg_integration_lib_base="$pkg_integration_lib_range/lib" ;;
    v2) pkg_integration_lib_base="$pkg_integration_lib_range/link/lib" ;;
    *) return 2 ;;
  esac
  [ -e "$pkg_integration_lib_base" ] || [ -L "$pkg_integration_lib_base" ] || return 0
  valid_dir "$pkg_integration_lib_base" || return 1

  for pkg_integration_lib_runtime in "$pkg_integration_lib_base/"*
  do
    [ -e "$pkg_integration_lib_runtime" ] || [ -L "$pkg_integration_lib_runtime" ] || continue
    case "${pkg_integration_lib_runtime##*/}" in
      sh | java) : ;;
      *) return 1 ;;
    esac
    valid_dir "$pkg_integration_lib_runtime" || return 1
    _pkg_integration_dir_entries_empty "$pkg_integration_lib_runtime" && return 1

    for pkg_integration_lib_descriptor in "$pkg_integration_lib_runtime/"*
    do
      [ -e "$pkg_integration_lib_descriptor" ] || [ -L "$pkg_integration_lib_descriptor" ] || continue
      pkg_integration_lib_name=${pkg_integration_lib_descriptor##*/}
      pkg_name_valid "$pkg_integration_lib_name" || return 1
      case "${pkg_integration_lib_runtime##*/}:$pkg_integration_lib_name" in
        sh:*.lib.sh | java:*.jar) : ;;
        *) return 1 ;;
      esac
      if [ "$pkg_integration_lib_schema" = v2 ]
      then
        _pkg_integration_v2_descriptor_read "$pkg_integration_lib_descriptor" || return 1
        _pkg_integration_v2_root_target_validate "$pkg_v2_target" "$pkg_integration_lib_root" "../../../root/" || return 1
        pkg_integration_link_target=$pkg_v2_relative
      else
        _pkg_integration_link_target_read "$pkg_integration_lib_descriptor" || return 1
      fi

      [ -e "$pkg_integration_lib_root/$pkg_integration_link_target" ] || return 1
      readpathce pkg_integration_lib_resolved "$pkg_integration_lib_root/$pkg_integration_link_target" || return 1
      case "$pkg_integration_lib_resolved" in
        "$pkg_integration_lib_root"/*) : ;;
        *) return 1 ;;
      esac
      [ -f "$pkg_integration_lib_resolved" ] && [ -r "$pkg_integration_lib_resolved" ] || return 1
      if [ "${pkg_integration_lib_runtime##*/}" = sh ]
      then
        [ ! -x "$pkg_integration_lib_resolved" ] || return 1
        command -p -- sh -n "$pkg_integration_lib_resolved" >/dev/null 2>&1 || return 1
      fi
    done

    for pkg_integration_lib_hidden in "$pkg_integration_lib_runtime"/.[!.]* "$pkg_integration_lib_runtime"/..?*
    do
      [ -e "$pkg_integration_lib_hidden" ] || [ -L "$pkg_integration_lib_hidden" ] || continue
      return 1
    done
  done

  for pkg_integration_lib_hidden in "$pkg_integration_lib_base"/.[!.]* "$pkg_integration_lib_base"/..?*
  do
    [ -e "$pkg_integration_lib_hidden" ] || [ -L "$pkg_integration_lib_hidden" ] || continue
    return 1
  done
}

_pkg_integration_libraries_materialize()
{
  [ "$#" -ge 2 ] && [ "$#" -le 3 ] || return 2
  pkg_integration_lib_range=$1
  pkg_integration_lib_concrete=$2
  pkg_integration_lib_schema=${3-v1}
  case "$pkg_integration_lib_schema" in
    v1)
      pkg_integration_lib_base="$pkg_integration_lib_range/lib"
      pkg_integration_lib_dest="$pkg_integration_lib_concrete/lib"
      ;;
    v2)
      pkg_integration_lib_base="$pkg_integration_lib_range/link/lib"
      pkg_integration_lib_dest="$pkg_integration_lib_concrete/link/lib"
      ;;
    *) return 2 ;;
  esac
  [ -d "$pkg_integration_lib_base" ] || return 0
  command -p -- mkdir "$pkg_integration_lib_dest" || return 1

  for pkg_integration_lib_runtime in "$pkg_integration_lib_base/"*
  do
    [ -d "$pkg_integration_lib_runtime" ] || continue
    pkg_integration_lib_runtime_name=${pkg_integration_lib_runtime##*/}
    command -p -- mkdir "$pkg_integration_lib_dest/$pkg_integration_lib_runtime_name" || return 1
    for pkg_integration_lib_descriptor in "$pkg_integration_lib_runtime/"*
    do
      [ -f "$pkg_integration_lib_descriptor" ] || continue
      if [ "$pkg_integration_lib_schema" = v2 ]
      then
        _pkg_integration_v2_descriptor_read "$pkg_integration_lib_descriptor" || return 1
        pkg_integration_lib_target=$pkg_v2_target
      else
        _pkg_integration_link_target_read "$pkg_integration_lib_descriptor" || return 1
        pkg_integration_lib_target="../../root/$pkg_integration_link_target"
      fi
      pkg_integration_lib_name=${pkg_integration_lib_descriptor##*/}
      command -p -- ln -s "$pkg_integration_lib_target" \
        "$pkg_integration_lib_dest/$pkg_integration_lib_runtime_name/$pkg_integration_lib_name" || return 1
    done
  done
}

# v2 commands are concrete-local executable symlinks. A link targets either
# the useful root or an optional package-specific cmd wrapper; it never names
# another package, selector, or globally published command.
_pkg_integration_v2_descriptor_read()
{
  [ "$#" -eq 1 ] || return 2
  [ -f "$1" ] && [ ! -L "$1" ] && [ -r "$1" ] && [ ! -x "$1" ] || return 1
  pkg_v2_target="$(command -p -- cat -- "$1")" || return 1
  pkg_v2_newline='
'
  case "$pkg_v2_target" in
    "" | /* | *"$pkg_v2_newline"* | *"$(printf '\r')"*) return 1 ;;
  esac
}

_pkg_integration_v2_root_target_validate()
{
  [ "$#" -ge 2 ] && [ "$#" -le 3 ] || return 2
  pkg_v2_root_target=$1
  pkg_v2_useful_root=$2
  pkg_v2_root_prefix=${3-../../root/}
  case "$pkg_v2_root_prefix" in
    ../../root/ | ../../../root/) : ;;
    *) return 2 ;;
  esac

  case "$pkg_v2_root_target" in
    "$pkg_v2_root_prefix"*) pkg_v2_relative=${pkg_v2_root_target#"$pkg_v2_root_prefix"} ;;
    *) return 1 ;;
  esac
  case "$pkg_v2_relative" in
    "" | /* | */ | *//*) return 1 ;;
  esac
  case "/$pkg_v2_relative/" in
    */./* | */../*) return 1 ;;
  esac
  readpathce pkg_v2_resolved "$pkg_v2_useful_root/$pkg_v2_relative" || return 1
  case "$pkg_v2_resolved" in
    "$pkg_v2_useful_root"/*) : ;;
    *) return 1 ;;
  esac
  [ -f "$pkg_v2_resolved" ] && [ -x "$pkg_v2_resolved" ]
}

_pkg_integration_v2_validate_definition()
{
  [ "$#" -eq 2 ] || return 2
  pkg_v2_range=$1
  pkg_v2_root=$2

  for pkg_v2_entry in "$pkg_v2_range"/* "$pkg_v2_range"/.[!.]* "$pkg_v2_range"/..?*
  do
    [ -e "$pkg_v2_entry" ] || [ -L "$pkg_v2_entry" ] || continue
    case "${pkg_v2_entry##*/}" in
      archive_regex | digest_type | format)
        [ -f "$pkg_v2_entry" ] && [ ! -L "$pkg_v2_entry" ] || return 1
        ;;
      cmd | link)
        valid_dir "$pkg_v2_entry" || return 1
        ;;
      *)
        # No v2 facility/state/library descriptor may be silently ignored
        # before its responsible handler is implemented and validated.
        return 2
        ;;
    esac
  done

  [ -f "$pkg_v2_range/format" ] && [ ! -L "$pkg_v2_range/format" ] || return 1
  valid_dir "$pkg_v2_range/link" || return 1
  if [ -e "$pkg_v2_range/link/bin" ] || [ -L "$pkg_v2_range/link/bin" ]
  then
    valid_dir "$pkg_v2_range/link/bin" || return 1
    _pkg_integration_dir_entries_empty "$pkg_v2_range/link/bin" && return 1
  else
    valid_dir "$pkg_v2_range/link/lib" || return 1
  fi
  _pkg_integration_libraries_validate "$pkg_v2_range" "$pkg_v2_root" v2 || return 1

  for pkg_v2_entry in "$pkg_v2_range/link"/*
  do
    [ -e "$pkg_v2_entry" ] || [ -L "$pkg_v2_entry" ] || continue
    case "${pkg_v2_entry##*/}" in
      bin | target | lib) valid_dir "$pkg_v2_entry" || return 1 ;;
      *) return 1 ;;
    esac
  done

  for pkg_v2_descriptor in "$pkg_v2_range/link/bin"/*
  do
    [ -e "$pkg_v2_descriptor" ] || [ -L "$pkg_v2_descriptor" ] || continue
    pkg_v2_command=${pkg_v2_descriptor##*/}
    pkg_name_valid "$pkg_v2_command" || return 1
    _pkg_integration_v2_descriptor_read "$pkg_v2_descriptor" || return 1
    case "$pkg_v2_target" in
      ../../root/*)
        _pkg_integration_v2_root_target_validate "$pkg_v2_target" "$pkg_v2_root" || return 1
        ;;
      "../../cmd/$pkg_v2_command")
        pkg_v2_cmd="$pkg_v2_range/cmd/$pkg_v2_command"
        [ -f "$pkg_v2_cmd" ] && [ ! -L "$pkg_v2_cmd" ] &&
          [ -r "$pkg_v2_cmd" ] && [ ! -x "$pkg_v2_cmd" ] || return 1
        _pkg_integration_v2_descriptor_read "$pkg_v2_range/link/target/$pkg_v2_command" || return 1
        _pkg_integration_v2_root_target_validate "$pkg_v2_target" "$pkg_v2_root" || return 1
        ;;
      *) return 1 ;;
    esac
  done

  if [ -d "$pkg_v2_range/cmd" ]
  then
    valid_dir "$pkg_v2_range/cmd" || return 1
    for pkg_v2_cmd in "$pkg_v2_range/cmd"/*
    do
      [ -e "$pkg_v2_cmd" ] || [ -L "$pkg_v2_cmd" ] || continue
      pkg_v2_command=${pkg_v2_cmd##*/}
      pkg_name_valid "$pkg_v2_command" || return 1
      [ -f "$pkg_v2_cmd" ] && [ ! -L "$pkg_v2_cmd" ] &&
        [ -r "$pkg_v2_cmd" ] && [ ! -x "$pkg_v2_cmd" ] || return 1
      _pkg_integration_v2_descriptor_read "$pkg_v2_range/link/bin/$pkg_v2_command" || return 1
      [ "$pkg_v2_target" = "../../cmd/$pkg_v2_command" ] || return 1
      _pkg_integration_v2_descriptor_read "$pkg_v2_range/link/target/$pkg_v2_command" || return 1
      _pkg_integration_v2_root_target_validate "$pkg_v2_target" "$pkg_v2_root" || return 1
    done
  fi

  if [ -d "$pkg_v2_range/link/target" ]
  then
    valid_dir "$pkg_v2_range/link/target" || return 1
    for pkg_v2_descriptor in "$pkg_v2_range/link/target"/*
    do
      [ -e "$pkg_v2_descriptor" ] || [ -L "$pkg_v2_descriptor" ] || continue
      pkg_v2_command=${pkg_v2_descriptor##*/}
      [ -f "$pkg_v2_range/cmd/$pkg_v2_command" ] || return 1
    done
  fi

  return 0
}

_pkg_integration_v2_materialize_commands()
{
  [ "$#" -eq 2 ] || return 2
  pkg_v2_range=$1
  pkg_v2_concrete=$2

  command -p -- mkdir "$pkg_v2_concrete/link" || return 1
  if [ -d "$pkg_v2_range/link/bin" ]
  then
    command -p -- mkdir "$pkg_v2_concrete/link/bin" || return 1
  fi
  if [ -d "$pkg_v2_range/cmd" ]
  then
    command -p -- mkdir "$pkg_v2_concrete/cmd" || return 1
    for pkg_v2_cmd in "$pkg_v2_range/cmd"/*
    do
      [ -f "$pkg_v2_cmd" ] || continue
      command -p -- cp -- "$pkg_v2_cmd" "$pkg_v2_concrete/cmd/${pkg_v2_cmd##*/}" || return 1
      command -p -- chmod +x "$pkg_v2_concrete/cmd/${pkg_v2_cmd##*/}" || return 1
    done
  fi
  if [ -d "$pkg_v2_range/link/target" ]
  then
    command -p -- mkdir "$pkg_v2_concrete/link/target" || return 1
    for pkg_v2_descriptor in "$pkg_v2_range/link/target"/*
    do
      [ -f "$pkg_v2_descriptor" ] || continue
      _pkg_integration_v2_descriptor_read "$pkg_v2_descriptor" || return 1
      command -p -- ln -s "$pkg_v2_target" "$pkg_v2_concrete/link/target/${pkg_v2_descriptor##*/}" || return 1
    done
  fi
  for pkg_v2_descriptor in "$pkg_v2_range/link/bin"/*
  do
    [ -f "$pkg_v2_descriptor" ] || continue
    _pkg_integration_v2_descriptor_read "$pkg_v2_descriptor" || return 1
    command -p -- ln -s "$pkg_v2_target" "$pkg_v2_concrete/link/bin/${pkg_v2_descriptor##*/}" || return 1
  done
  printf 'v2\n' > "$pkg_v2_concrete/schema" || return 1
}

_pkg_integration_validate_definition()
{
  [ "$#" -eq 2 ] || return 2
  pkg_integration_range=$1
  pkg_integration_root=$2
  pkg_integration_have_cmd=0
  pkg_integration_have_link=0
  pkg_integration_format_file=
  pkg_integration_component_file=
  pkg_integration_payload_root_file=
  pkg_integration_overlay_dir=

  for pkg_integration_entry in \
    "$pkg_integration_range"/* \
    "$pkg_integration_range"/.[!.]* \
    "$pkg_integration_range"/..?*
  do
    [ -e "$pkg_integration_entry" ] || [ -L "$pkg_integration_entry" ] || continue
    pkg_integration_entry_name=${pkg_integration_entry##*/}
    case "$pkg_integration_entry_name" in
      archive_regex | digest_regex | digest_type)
        [ -f "$pkg_integration_entry" ] && [ ! -L "$pkg_integration_entry" ] || return 1
        ;;
      format)
        [ -f "$pkg_integration_entry" ] && [ ! -L "$pkg_integration_entry" ] || return 1
        pkg_integration_format_file=$pkg_integration_entry
        ;;
      component)
        [ -f "$pkg_integration_entry" ] && [ ! -L "$pkg_integration_entry" ] || return 1
        pkg_integration_component_file=$pkg_integration_entry
        ;;
      payload-root)
        [ -f "$pkg_integration_entry" ] && [ ! -L "$pkg_integration_entry" ] || return 1
        pkg_integration_payload_root_file=$pkg_integration_entry
        ;;
      overlay)
        valid_dir "$pkg_integration_entry" || return 1
        pkg_integration_overlay_dir=$pkg_integration_entry
        ;;
      facility)
        _pkg_facility_file_validate "$pkg_integration_entry" || return 1
        ;;
      dependency)
        _pkg_dependency_file_validate "$pkg_integration_entry" || return 1
        ;;
      env)
        _pkg_integration_env_validate "$pkg_integration_entry" || return 1
        ;;
      facility-cmd | facility-env | facility-service)
        valid_dir "$pkg_integration_entry" || return 1
        ;;
      setuid_root)
        [ -f "$pkg_integration_entry" ] && [ ! -L "$pkg_integration_entry" ] || return 1
        ;;
      var)
        valid_dir "$pkg_integration_entry" || return 1
        ;;
      lib)
        valid_dir "$pkg_integration_entry" || return 1
        ;;
      cmd)
        valid_dir "$pkg_integration_entry" || return 1
        pkg_integration_have_cmd=1
        ;;
      link)
        valid_dir "$pkg_integration_entry" || return 1
        pkg_integration_have_link=1
        ;;
      *)
        return 2
        ;;
    esac
  done

  [ -n "$pkg_integration_format_file" ] || return 1
  pkg_integration_format_value="$(command -p -- cat -- "$pkg_integration_format_file")" || return 1
  case "$pkg_integration_format_value" in
    *'
'*) return 1 ;;
  esac
  case "$pkg_integration_format_value" in
    flat-pkg)
      [ -n "$pkg_integration_component_file" ] || return 1
      _pkg_integration_component_file_validate "$pkg_integration_component_file" || return 1
      if [ -n "$pkg_integration_payload_root_file" ]
      then
        _pkg_integration_link_target_read "$pkg_integration_payload_root_file" || return 1
      fi
      [ -z "$pkg_integration_overlay_dir" ] || return 1
      ;;
    dmg-pkg)
      [ -n "$pkg_integration_component_file" ] || return 1
      _pkg_integration_component_file_validate "$pkg_integration_component_file" || return 1
      if [ -n "$pkg_integration_payload_root_file" ]
      then
        _pkg_integration_link_target_read "$pkg_integration_payload_root_file" || return 1
      fi
      if [ -n "$pkg_integration_overlay_dir" ]
      then
        _pkg_integration_dmg_overlay_validate "$pkg_integration_overlay_dir" || return 1
      fi
      ;;
    *)
      [ -z "$pkg_integration_component_file" ] || return 1
      [ -z "$pkg_integration_payload_root_file" ] || return 1
      [ -z "$pkg_integration_overlay_dir" ] || return 1
      ;;
  esac

  _pkg_integration_libraries_validate "$pkg_integration_range" "$pkg_integration_root" || return 1
  _pkg_integration_facility_projection_validate "$pkg_integration_range" "$pkg_integration_root" || return 1

  [ "$pkg_integration_have_cmd" -eq "$pkg_integration_have_link" ] || return 1
  [ "$pkg_integration_have_cmd" -eq 1 ] || return 0
  _pkg_integration_dir_entries_empty "$pkg_integration_range/cmd" && return 1
  _pkg_integration_dir_entries_empty "$pkg_integration_range/link" && return 1

  for pkg_integration_cmd_source in "$pkg_integration_range/cmd"/*
  do
    [ -e "$pkg_integration_cmd_source" ] || [ -L "$pkg_integration_cmd_source" ] || continue
    pkg_integration_command=${pkg_integration_cmd_source##*/}
    pkg_name_valid "$pkg_integration_command" || return 1
    [ -f "$pkg_integration_cmd_source" ] && [ ! -L "$pkg_integration_cmd_source" ] && [ -r "$pkg_integration_cmd_source" ] && [ ! -x "$pkg_integration_cmd_source" ] || return 1
    [ -f "$pkg_integration_range/link/$pkg_integration_command" ] && [ ! -L "$pkg_integration_range/link/$pkg_integration_command" ] || return 1

    _pkg_integration_link_target_read "$pkg_integration_range/link/$pkg_integration_command" || return 1
    [ -e "$pkg_integration_root/$pkg_integration_link_target" ] || [ -L "$pkg_integration_root/$pkg_integration_link_target" ] || return 1
    readpathce pkg_integration_link_resolved "$pkg_integration_root/$pkg_integration_link_target" || return 1
    case "$pkg_integration_link_resolved" in
      "$pkg_integration_root"/*) : ;;
      *) return 1 ;;
    esac
    [ -f "$pkg_integration_link_resolved" ] || return 1
  done

  for pkg_integration_link_source in "$pkg_integration_range/link"/*
  do
    [ -e "$pkg_integration_link_source" ] || [ -L "$pkg_integration_link_source" ] || continue
    pkg_integration_command=${pkg_integration_link_source##*/}
    pkg_name_valid "$pkg_integration_command" || return 1
    [ -f "$pkg_integration_range/cmd/$pkg_integration_command" ] && [ ! -L "$pkg_integration_range/cmd/$pkg_integration_command" ] || return 1
  done

  for pkg_integration_entry in \
    "$pkg_integration_range/cmd"/.[!.]* \
    "$pkg_integration_range/cmd"/..?* \
    "$pkg_integration_range/link"/.[!.]* \
    "$pkg_integration_range/link"/..?*
  do
    [ -e "$pkg_integration_entry" ] || [ -L "$pkg_integration_entry" ] || continue
    return 1
  done

  return 0
}

_pkg_integration_materialize_commands()
{
  [ "$#" -eq 2 ] || return 2
  pkg_integration_range=$1
  pkg_integration_concrete=$2
  [ -d "$pkg_integration_range/cmd" ] || return 0

  command -p -- mkdir "$pkg_integration_concrete/cmd" "$pkg_integration_concrete/link" || return 1

  for pkg_integration_cmd_source in "$pkg_integration_range/cmd"/*
  do
    [ -e "$pkg_integration_cmd_source" ] || continue
    pkg_integration_command=${pkg_integration_cmd_source##*/}
    command -p -- cp -- "$pkg_integration_cmd_source" "$pkg_integration_concrete/cmd/$pkg_integration_command" || return 1
    command -p -- chmod +x "$pkg_integration_concrete/cmd/$pkg_integration_command" || return 1

    _pkg_integration_link_target_read "$pkg_integration_range/link/$pkg_integration_command" || return 1
    command -p -- ln -s "../root/$pkg_integration_link_target" "$pkg_integration_concrete/link/$pkg_integration_command" || return 1
  done
}

_pkg_integration_materialize_facility_projection()
{
  [ "$#" -eq 2 ] || return 2
  pkg_integration_range=$1
  pkg_integration_concrete=$2

  if [ -d "$pkg_integration_range/facility-cmd" ]
  then
    command -p -- mkdir "$pkg_integration_concrete/facility-cmd" || return 1
    for pkg_integration_facility_dir in "$pkg_integration_range/facility-cmd"/*
    do
      [ -d "$pkg_integration_facility_dir" ] || continue
      pkg_integration_projection_facility=${pkg_integration_facility_dir##*/}
      command -p -- mkdir "$pkg_integration_concrete/facility-cmd/$pkg_integration_projection_facility" || return 1
      for pkg_integration_descriptor in "$pkg_integration_facility_dir"/*
      do
        [ -f "$pkg_integration_descriptor" ] || continue
        pkg_integration_projection_command=${pkg_integration_descriptor##*/}
        _pkg_facility_cmd_realization_read "$pkg_integration_descriptor" || return 1
        case "$pkg_facility_cmd_realization_type" in
          root)
            pkg_integration_projection_target="../../root/$pkg_facility_cmd_realization_value"
            ;;
          package-command)
            pkg_integration_projection_target="../../cmd/$pkg_facility_cmd_realization_value"
            ;;
          *)
            return 1
            ;;
        esac
        command -p -- ln -s \
          "$pkg_integration_projection_target" \
          "$pkg_integration_concrete/facility-cmd/$pkg_integration_projection_facility/$pkg_integration_projection_command" || return 1
      done
    done
  fi

  if [ -d "$pkg_integration_range/facility-env" ]
  then
    command -p -- mkdir "$pkg_integration_concrete/facility-env" || return 1
    for pkg_integration_env_file in "$pkg_integration_range/facility-env"/*
    do
      [ -f "$pkg_integration_env_file" ] || continue
      command -p -- cp -- "$pkg_integration_env_file" "$pkg_integration_concrete/facility-env/${pkg_integration_env_file##*/}" || return 1
    done
  fi

  if [ -d "$pkg_integration_range/facility-service" ]
  then
    command -p -- mkdir "$pkg_integration_concrete/facility-service" || return 1
    for pkg_integration_service_facility_dir in "$pkg_integration_range/facility-service"/*
    do
      [ -d "$pkg_integration_service_facility_dir" ] || continue
      pkg_integration_service_facility=${pkg_integration_service_facility_dir##*/}
      command -p -- mkdir "$pkg_integration_concrete/facility-service/$pkg_integration_service_facility" || return 1
      command -p -- cp -- \
        "$pkg_integration_service_facility_dir/start" \
        "$pkg_integration_concrete/facility-service/$pkg_integration_service_facility/start" || return 1
    done
  fi
}

_pkg_integration_materialize_env()
{
  [ "$#" -eq 2 ] || return 2
  pkg_integration_range=$1
  pkg_integration_concrete=$2
  [ -e "$pkg_integration_range/env" ] || [ -L "$pkg_integration_range/env" ] || return 0

  command -p -- cp -- "$pkg_integration_range/env" "$pkg_integration_concrete/env" || return 1
  [ -f "$pkg_integration_concrete/env" ] && \
  [ ! -L "$pkg_integration_concrete/env" ] && \
  [ -r "$pkg_integration_concrete/env" ] && \
  [ ! -x "$pkg_integration_concrete/env" ]
}

_pkg_default_read_current()
{
  [ "$#" -eq 1 ] || return 2
  pkg_default_current=

  if [ -L "$1" ]
  then
    pkg_default_current="$(command -p -- readlink "$1")" || return 1
    [ -n "$pkg_default_current" ] || return 1
    case "$pkg_default_current" in
      */*) return 1 ;;
    esac
    return 0
  fi

  [ ! -e "$1" ] || return 1
  return 0
}

_pkg_default_current_valid()
{
  [ "$#" -eq 1 ] || return 2
  [ -n "$1" ] || return 0

  pkg_default_prefix="$pkg_integration_pkg@"
  if [ -n "$pkg_integration_osarch" ]
  then
    pkg_default_suffix="!$pkg_integration_osarch"
    case "$1" in
      "$pkg_default_prefix"*"$pkg_default_suffix") : ;;
      *) return 1 ;;
    esac
    pkg_default_current_version=${1#"$pkg_default_prefix"}
    pkg_default_current_version=${pkg_default_current_version%"$pkg_default_suffix"}
  else
    case "$1" in
      "$pkg_default_prefix"*) : ;;
      *) return 1 ;;
    esac
    pkg_default_current_version=${1#"$pkg_default_prefix"}
  fi

  pkg_version_valid "$pkg_default_current_version"
}

# Public package defaults publish the exact concrete's command view.
# v1 remains its historical cmd directory; v2 exposes link/bin instead.
_pkg_default_view_set()
{
  [ "$#" -eq 1 ] || return 2
  valid_dir "$m_PKG_DIR/$1" || return 1
  _pkg_schema_read "$m_PKG_DIR/$1" || return 1
  case "$pkg_schema" in
    v1) pkg_default_view_rel=cmd ;;
    v2) pkg_default_view_rel=link/bin ;;
    *) return 1 ;;
  esac
  pkg_default_view_dir="$m_PKG_DIR/$1/$pkg_default_view_rel"
  if [ -e "$pkg_default_view_dir" ] || [ -L "$pkg_default_view_dir" ]
  then
    valid_dir "$pkg_default_view_dir" || return 1
  fi
}

_pkg_default_public_target()
{
  [ "$#" -eq 2 ] || return 2
  _pkg_default_view_set "$2" || return 1
  pkg_default_public_target="../../pkg/$pkg_integration_selector_name/$pkg_default_view_rel/$1"
}

_pkg_default_validate_current_bindings()
{
  [ "$#" -eq 1 ] || return 2
  pkg_default_old_concrete=$1
  _pkg_default_view_set "$pkg_default_old_concrete" || return 1
  pkg_default_old_cmd_dir=$pkg_default_view_dir

  [ -d "$pkg_default_old_cmd_dir" ] || return 0
  valid_dir "$pkg_integration_public_dir" || return 1

  for pkg_default_cmd_path in "$pkg_default_old_cmd_dir"/*
  do
    [ -e "$pkg_default_cmd_path" ] || [ -L "$pkg_default_cmd_path" ] || continue
    pkg_default_command=${pkg_default_cmd_path##*/}
    [ -f "$pkg_default_cmd_path" ] && [ -x "$pkg_default_cmd_path" ] || return 1
    _pkg_default_public_target "$pkg_default_command" "$pkg_default_old_concrete" || return 1
    pkg_default_expected=$pkg_default_public_target
    pkg_default_public="$pkg_integration_public_dir/$pkg_default_command"
    [ -L "$pkg_default_public" ] || return 1
    pkg_default_actual="$(command -p -- readlink "$pkg_default_public")" || return 1
    [ "$pkg_default_actual" = "$pkg_default_expected" ] || return 1
  done
}

_pkg_default_validate_new_collisions()
{
  [ "$#" -eq 2 ] || return 2
  pkg_default_new_concrete=$1
  pkg_default_old_concrete=$2
  _pkg_default_view_set "$pkg_default_new_concrete" || return 1
  pkg_default_new_cmd_dir=$pkg_default_view_dir

  [ -d "$pkg_default_new_cmd_dir" ] || return 0

  for pkg_default_cmd_path in "$pkg_default_new_cmd_dir"/*
  do
    [ -e "$pkg_default_cmd_path" ] || [ -L "$pkg_default_cmd_path" ] || continue
    pkg_default_command=${pkg_default_cmd_path##*/}
    [ -f "$pkg_default_cmd_path" ] && [ -x "$pkg_default_cmd_path" ] || return 1
    pkg_default_public="$pkg_integration_public_dir/$pkg_default_command"
    [ ! -e "$pkg_default_public" ] && [ ! -L "$pkg_default_public" ] && continue

    [ -n "$pkg_default_old_concrete" ] || return 1
    _pkg_default_public_target "$pkg_default_command" "$pkg_default_old_concrete" || return 1
    pkg_default_expected=$pkg_default_public_target
    pkg_default_old_command=$pkg_default_view_dir/$pkg_default_command
    [ -f "$pkg_default_old_command" ] && [ -x "$pkg_default_old_command" ] || return 1
    [ -L "$pkg_default_public" ] || return 1
    pkg_default_actual="$(command -p -- readlink "$pkg_default_public")" || return 1
    [ "$pkg_default_actual" = "$pkg_default_expected" ] || return 1
  done
}

_pkg_default_remove_bindings()
{
  [ "$#" -eq 1 ] || return 2
  _pkg_default_view_set "$1" || return 1
  pkg_default_cmd_dir=$pkg_default_view_dir
  [ -d "$pkg_default_cmd_dir" ] || return 0

  for pkg_default_cmd_path in "$pkg_default_cmd_dir"/*
  do
    [ -e "$pkg_default_cmd_path" ] || [ -L "$pkg_default_cmd_path" ] || continue
    pkg_default_command=${pkg_default_cmd_path##*/}
    command -p -- rm -f -- "$pkg_integration_public_dir/$pkg_default_command" || return 1
  done
}

_pkg_default_create_bindings()
{
  [ "$#" -eq 1 ] || return 2
  pkg_default_selected_concrete=$1
  _pkg_default_view_set "$pkg_default_selected_concrete" || return 1
  pkg_default_cmd_dir=$pkg_default_view_dir
  [ -d "$pkg_default_cmd_dir" ] || return 0

  for pkg_default_cmd_path in "$pkg_default_cmd_dir"/*
  do
    [ -e "$pkg_default_cmd_path" ] || [ -L "$pkg_default_cmd_path" ] || continue
    pkg_default_command=${pkg_default_cmd_path##*/}
    [ -f "$pkg_default_cmd_path" ] && [ -x "$pkg_default_cmd_path" ] || return 1
    _pkg_default_public_target "$pkg_default_command" "$pkg_default_selected_concrete" || return 1
    pkg_default_target=$pkg_default_public_target
    command -p -- ln -s "$pkg_default_target" "$pkg_integration_public_dir/$pkg_default_command" || return 1
  done
}

pkg_integrate()
(
  # Phase 1: validate invocation and package identity.
  [ "$#" -ge 4 ] && [ "$#" -le 6 ] || return 1
  pkg_integrate_pkg=$1
  pkg_integrate_version=$2
  pkg_integrate_range_input=$3
  pkg_integrate_root_input=$4
  pkg_integrate_osarch=${5-}
  pkg_integrate_schema=${6-v1}
  case "$pkg_integrate_schema" in
    v1 | v2) : ;;
    *) return 2 ;;
  esac

  pkg_name_version_osarch_valid "$pkg_integrate_pkg" "$pkg_integrate_version" "$pkg_integrate_osarch" || return 2

  # Phase 2: validate and canonicalize integration inputs, then derive
  # the concrete package identity that will be created.
  valid_dir "$m_PKG_DIR" || return 3
  valid_dir "$pkg_integrate_range_input" || return 4
  valid_dir "$pkg_integrate_root_input" || return 5
  readpathce pkg_integrate_range "$pkg_integrate_range_input" || return 6
  readpathce pkg_integrate_root "$pkg_integrate_root_input" || return 7

  _pkg_integration_set_concrete "$pkg_integrate_pkg" "$pkg_integrate_version" "$pkg_integrate_osarch" || return 8
  [ ! -e "$pkg_integration_concrete" ] && [ ! -L "$pkg_integration_concrete" ] || return 9

  # Phase 3: validate the complete integration plan before consuming the
  # caller-owned staging root.
  if [ "$pkg_integrate_schema" = v2 ]
  then
    _pkg_integration_v2_validate_definition "$pkg_integrate_range" "$pkg_integrate_root"
  else
    _pkg_integration_validate_definition "$pkg_integrate_range" "$pkg_integrate_root"
  fi
  pkg_integrate_status=$?
  [ "$pkg_integrate_status" -eq 0 ] || return "$pkg_integrate_status"

  _pkg_state_validate "$pkg_integrate_range" "$pkg_integrate_root" "$pkg_integrate_pkg" || return 10
  _pkg_setuid_validate "$pkg_integrate_range" "$pkg_integrate_root" "$pkg_integrate_osarch" "$pkg_state_paths" || return 11

  # Phase 4: create the concrete package and move the prepared useful root
  # into managed package storage.
  mkdir "$pkg_integration_concrete" || return 12
  if ! mv -- "$pkg_integrate_root" "$pkg_integration_concrete/root"
  then
    rmdir "$pkg_integration_concrete" 2>/dev/null
    return 1
  fi

  # Phase 5: materialize package-local runtime metadata and projections.
  # Any failure restores the caller-owned staging root.
  if [ "$pkg_integrate_schema" = v2 ]
  then
    _pkg_integration_v2_materialize_commands "$pkg_integrate_range" "$pkg_integration_concrete"
  else
    _pkg_integration_materialize_commands "$pkg_integrate_range" "$pkg_integration_concrete"
  fi
  if [ "$?" -ne 0 ]
  then
    _pkg_integration_restore_input "$pkg_integration_concrete" "$pkg_integrate_root_input" || :
    _pkg_integration_error pkg-integrate materialization-failed
    return 13
  fi

  if ! _pkg_integration_libraries_materialize "$pkg_integrate_range" "$pkg_integration_concrete" "$pkg_integrate_schema"
  then
    _pkg_integration_restore_input "$pkg_integration_concrete" "$pkg_integrate_root_input" || :
    log error execution library-materialization-failed operation pkg-integrate
    return 21
  fi

  if ! _pkg_integration_materialize_env "$pkg_integrate_range" "$pkg_integration_concrete"
  then
    _pkg_integration_restore_input "$pkg_integration_concrete" "$pkg_integrate_root_input" || :
    _pkg_integration_error pkg-integrate env-materialization-failed
    return 14
  fi

  if ! _pkg_facility_materialize "$pkg_integrate_range" "$pkg_integration_concrete"
  then
    _pkg_integration_restore_input "$pkg_integration_concrete" "$pkg_integrate_root_input" || :
    _pkg_integration_error pkg-integrate facility-materialization-failed
    return 15
  fi

  if ! _pkg_integration_materialize_facility_projection "$pkg_integrate_range" "$pkg_integration_concrete"
  then
    _pkg_integration_restore_input "$pkg_integration_concrete" "$pkg_integrate_root_input" || :
    _pkg_integration_error pkg-integrate facility-projection-materialization-failed
    return 16
  fi

  if ! _pkg_dependency_materialize "$pkg_integrate_range/dependency" "$pkg_integration_concrete"
  then
    _pkg_integration_restore_input "$pkg_integration_concrete" "$pkg_integrate_root_input" || :
    _pkg_integration_error pkg-integrate dependency-materialization-failed
    return 17
  fi

  # Phase 6: materialize state and privileged setuid effects.
  if ! _pkg_state_materialize "$pkg_integrate_range" "$pkg_integration_concrete" "$pkg_integrate_pkg"
  then
    _pkg_integration_restore_input "$pkg_integration_concrete" "$pkg_integrate_root_input" || :
    _pkg_integration_error pkg-integrate state-materialization-failed
    return 18
  fi

  if ! _pkg_setuid_materialize "$pkg_integrate_range" "$pkg_integration_concrete"
  then
    # Setuid failure requires specialized rollback before restoring the
    # package-local staging root.
    pkg_integrate_rollback_status=0
    if ! _pkg_setuid_rollback "$pkg_integrate_range" "$pkg_integration_concrete"
    then
      _pkg_integration_error pkg-integrate setuid-rollback-failed
      pkg_integrate_rollback_status=1
    fi
    if ! _pkg_state_rollback "$pkg_integration_concrete"
    then
      _pkg_integration_error pkg-integrate state-rollback-failed
      pkg_integrate_rollback_status=1
    fi
    [ "$pkg_integrate_rollback_status" -eq 0 ] || return 19

    _pkg_integration_restore_input "$pkg_integration_concrete" "$pkg_integrate_root_input" || :
    _pkg_integration_error pkg-integrate setuid-materialization-failed
    return 20
  fi

  # Phase 7: finalize the setuid transaction and complete integration.
  _pkg_setuid_commit "$pkg_integrate_range" "$pkg_integration_concrete" || :

  return 0
)

pkg_deintegrate()
(
  [ "$#" -eq 2 ] || [ "$#" -eq 3 ] || return 1
  pkg_deintegrate_pkg=$1
  pkg_deintegrate_version=$2
  pkg_deintegrate_osarch=${3-}

  pkg_name_version_osarch_valid "$pkg_deintegrate_pkg" "$pkg_deintegrate_version" "$pkg_deintegrate_osarch" || return 2

  _pkg_integration_set_concrete "$pkg_deintegrate_pkg" "$pkg_deintegrate_version" "$pkg_deintegrate_osarch" || return 1
  valid_dir "$pkg_integration_concrete" || return 1

  _pkg_default_read_current "$pkg_integration_selector" || return 1
  _pkg_default_current_valid "$pkg_default_current" || return 1
  [ "$pkg_default_current" != "$pkg_integration_concrete_name" ] || return 1
  _pkg_dependency_provider_unreferenced "$pkg_integration_concrete_name" || return 1

  command -p -- rm -rf -- "$pkg_integration_concrete" || return 1
  return 0
)

_pkg_default_restore_previous()
{
  [ "$#" -eq 2 ] || return 2
  pkg_default_restore_old=$1
  pkg_default_restore_new=$2
  pkg_default_restore_status=0

  if [ -n "$pkg_default_restore_new" ]
  then
    _pkg_default_remove_bindings "$pkg_default_restore_new" 2>/dev/null || pkg_default_restore_status=1
  fi
  command -p -- rm -f -- "$pkg_integration_selector" 2>/dev/null || pkg_default_restore_status=1

  if [ -n "$pkg_default_restore_old" ]
  then
    command -p -- ln -s "$pkg_default_restore_old" "$pkg_integration_selector" 2>/dev/null || pkg_default_restore_status=1
    _pkg_default_create_bindings "$pkg_default_restore_old" 2>/dev/null || pkg_default_restore_status=1
  fi

  [ "$pkg_default_restore_status" -eq 0 ]
}

pkg_default_apply()
(
  [ "$#" -eq 2 ] || [ "$#" -eq 3 ] || return 2
  pkg_default_pkg=$1
  pkg_default_version=$2
  pkg_default_osarch=${3-}

  pkg_name_valid "$pkg_default_pkg" || return 2
  if [ -n "$pkg_default_version" ]
  then
    pkg_version_valid "$pkg_default_version" || return 2
  fi
  if [ -n "$pkg_default_osarch" ]
  then
    pkg_osarch_valid "$pkg_default_osarch" || return 2
  fi

  valid_dir "$m_PKG_DIR" || return 1
  valid_dir "$m_BIN_DIR" || return 1
  _pkg_integration_set_class "$pkg_default_pkg" "$pkg_default_osarch" || return 1
  _pkg_default_read_current "$pkg_integration_selector" || return 1
  _pkg_default_current_valid "$pkg_default_current" || return 1
  pkg_default_old_concrete=$pkg_default_current

  if [ -n "$pkg_default_old_concrete" ]
  then
    _pkg_default_validate_current_bindings "$pkg_default_old_concrete" || return 1
  fi

  if [ -z "$pkg_default_version" ]
  then
    [ -n "$pkg_default_old_concrete" ] || return 0
    _pkg_default_remove_bindings "$pkg_default_old_concrete" || return 1
    if ! command -p -- rm -f -- "$pkg_integration_selector"
    then
      _pkg_default_create_bindings "$pkg_default_old_concrete" >/dev/null 2>&1 || :
      return 1
    fi
    if ! pkg_provider_package_default_reconcile "$pkg_default_pkg" "$pkg_default_osarch" "$pkg_default_old_concrete" ""
    then
      _pkg_default_restore_previous "$pkg_default_old_concrete" "" >/dev/null 2>&1 || :
      return 1
    fi
    return 0
  fi

  _pkg_integration_set_concrete "$pkg_default_pkg" "$pkg_default_version" "$pkg_default_osarch" || return 1
  pkg_default_new_concrete=$pkg_integration_concrete_name
  valid_dir "$pkg_integration_concrete" || return 1

  if [ "$pkg_default_old_concrete" = "$pkg_default_new_concrete" ]
  then
    return 0
  fi

  if [ ! -e "$pkg_integration_public_dir" ] && [ ! -L "$pkg_integration_public_dir" ]
  then
    command -p -- mkdir "$pkg_integration_public_dir" || return 1
  fi
  valid_dir "$pkg_integration_public_dir" || return 1

  _pkg_default_validate_new_collisions "$pkg_default_new_concrete" "$pkg_default_old_concrete" || return 1

  if [ -n "$pkg_default_old_concrete" ]
  then
    _pkg_default_remove_bindings "$pkg_default_old_concrete" || return 1
    if ! command -p -- rm -f -- "$pkg_integration_selector"
    then
      _pkg_default_create_bindings "$pkg_default_old_concrete" >/dev/null 2>&1 || :
      return 1
    fi
  fi

  if ! command -p -- ln -s "$pkg_default_new_concrete" "$pkg_integration_selector"
  then
    _pkg_default_restore_previous "$pkg_default_old_concrete" "" >/dev/null 2>&1 || :
    return 1
  fi

  if ! _pkg_default_create_bindings "$pkg_default_new_concrete"
  then
    _pkg_default_restore_previous "$pkg_default_old_concrete" "$pkg_default_new_concrete" >/dev/null 2>&1 || :
    return 1
  fi

  if ! pkg_provider_package_default_reconcile "$pkg_default_pkg" "$pkg_default_osarch" "$pkg_default_old_concrete" "$pkg_default_new_concrete"
  then
    _pkg_default_restore_previous "$pkg_default_old_concrete" "$pkg_default_new_concrete" >/dev/null 2>&1 || :
    return 1
  fi

  return 0
)
