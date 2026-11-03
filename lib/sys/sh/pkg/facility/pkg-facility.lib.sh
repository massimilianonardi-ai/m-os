loadsyslib "pkg/pkg-common"
loadsyslib "pkg/facility/pkg-facility-cmd"
loadsyslib "pkg/facility/pkg-facility-env"
loadsyslib "pkg/facility/pkg-facility-service"

_pkg_facility_name_valid()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in
    "" | [!abcdefghijklmnopqrstuvwxyz]* | *[!abcdefghijklmnopqrstuvwxyz0123456789-]*) return 1 ;;
  esac
}

_pkg_facility_compatibility_valid()
{
  [ "$#" -eq 1 ] || return 2
  pkg_facility_compatibility=$1

  case "$pkg_facility_compatibility" in
    "" | *[!0123456789.]* | .* | *. | *..*) return 1 ;;
  esac

  if [ "${pkg_facility_compatibility#*.}" != "$pkg_facility_compatibility" ] && [ "${pkg_facility_compatibility##*.}" = 0 ]
  then
    return 1
  fi

  pkg_facility_compatibility_rest=$pkg_facility_compatibility
  while :
  do
    pkg_facility_compatibility_component=${pkg_facility_compatibility_rest%%.*}
    case "$pkg_facility_compatibility_component" in
      0) : ;;
      "" | 0* | *[!0123456789]*) return 1 ;;
    esac

    case "$pkg_facility_compatibility_rest" in
      *.*) pkg_facility_compatibility_rest=${pkg_facility_compatibility_rest#*.} ;;
      *) break ;;
    esac
  done
}

_pkg_facility_line_parse()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in
    *" "*)
      pkg_facility_name=${1%% *}
      pkg_facility_compatibility=${1#* }
      ;;
    *)
      return 1
      ;;
  esac

  [ -n "$pkg_facility_name" ] && [ -n "$pkg_facility_compatibility" ] || return 1
  case "$pkg_facility_compatibility" in *" "*) return 1 ;; esac
  _pkg_facility_name_valid "$pkg_facility_name" || return 1
  _pkg_facility_compatibility_valid "$pkg_facility_compatibility" || return 1
}

_pkg_facility_file_validate()
{
  [ "$#" -eq 1 ] || return 2
  [ -f "$1" ] && [ ! -L "$1" ] && [ -r "$1" ] && [ ! -x "$1" ] || return 1

  pkg_facility_original="$(
    command -p -- cat -- "$1" || exit 1
    printf -- '%s' x
  )" || return 1
  pkg_facility_sorted="$(
    LC_ALL=C command -p -- sort < "$1" || exit 1
    printf -- '%s' x
  )" || return 1
  [ "$pkg_facility_original" = "$pkg_facility_sorted" ] || return 1

  pkg_facility_count=0
  pkg_facility_previous=
  while IFS= read -r pkg_facility_line
  do
    _pkg_facility_line_parse "$pkg_facility_line" || return 1
    [ "$pkg_facility_name" != "$pkg_facility_previous" ] || return 1
    pkg_facility_previous=$pkg_facility_name
    pkg_facility_count=$((pkg_facility_count + 1))
  done < "$1"

  [ "$pkg_facility_count" -gt 0 ]
}

_pkg_facility_dir_ensure()
{
  [ "$#" -eq 1 ] || return 2
  if [ -e "$1" ] || [ -L "$1" ]
  then
    [ -d "$1" ] && [ ! -L "$1" ]
    return $?
  fi
  command -p -- mkdir -- "$1" || return 1
  [ -d "$1" ] && [ ! -L "$1" ]
}

_pkg_facility_dir_entries_empty()
{
  [ "$#" -eq 1 ] || return 2
  for pkg_facility_entry in \
    "$1"/* \
    "$1"/.[!.]* \
    "$1"/..?*
  do
    [ -e "$pkg_facility_entry" ] || [ -L "$pkg_facility_entry" ] || continue
    return 1
  done
  return 0
}

_pkg_facility_materialize()
{
  [ "$#" -eq 2 ] || return 2
  pkg_facility_range=$1
  pkg_facility_concrete=$2
  pkg_facility_source="$pkg_facility_range/facility"

  if [ ! -e "$pkg_facility_source" ] && [ ! -L "$pkg_facility_source" ]
  then
    return 0
  fi

  _pkg_facility_file_validate "$pkg_facility_source" || return 1
  command -p -- cp -- "$pkg_facility_source" "$pkg_facility_concrete/facility" || return 1
  _pkg_facility_file_validate "$pkg_facility_concrete/facility"
}


_pkg_facility_contract_part_validate()
{
  [ "$#" -eq 2 ] || return 2
  pkg_facility_contract_part=$1
  pkg_facility_contract_part_dir=$2

  case "$pkg_facility_contract_part" in
    cmd) _pkg_facility_cmd_contract_validate "$pkg_facility_contract_part_dir" ;;
    env) _pkg_facility_env_contract_validate "$pkg_facility_contract_part_dir" ;;
    service) _pkg_facility_service_contract_validate "$pkg_facility_contract_part_dir" ;;
    *) return 1 ;;
  esac
}

pkg_facility_contract_validate()
{
  [ "$#" -eq 1 ] || return 2
  pkg_facility_contract_dir=$1

  [ -d "$pkg_facility_contract_dir" ] && [ ! -L "$pkg_facility_contract_dir" ] || return 1
  _pkg_facility_dir_entries_empty "$pkg_facility_contract_dir" && return 1

  pkg_facility_contract_count=0
  for pkg_facility_contract_part_dir in "$pkg_facility_contract_dir"/*
  do
    [ -e "$pkg_facility_contract_part_dir" ] || [ -L "$pkg_facility_contract_part_dir" ] || continue
    [ -d "$pkg_facility_contract_part_dir" ] && [ ! -L "$pkg_facility_contract_part_dir" ] || return 1
    pkg_facility_contract_part=${pkg_facility_contract_part_dir##*/}
    _pkg_facility_contract_part_validate "$pkg_facility_contract_part" "$pkg_facility_contract_part_dir" || return 1
    pkg_facility_contract_count=$((pkg_facility_contract_count + 1))
  done

  for pkg_facility_contract_hidden in "$pkg_facility_contract_dir"/.[!.]* "$pkg_facility_contract_dir"/..?*
  do
    [ -e "$pkg_facility_contract_hidden" ] || [ -L "$pkg_facility_contract_hidden" ] || continue
    return 1
  done

  [ "$pkg_facility_contract_count" -gt 0 ]
}

_pkg_facility_declared_compatibility()
{
  [ "$#" -eq 2 ] || return 2
  pkg_facility_declared_definition=$1
  pkg_facility_declared_name=$2
  pkg_facility_declared_file="$pkg_facility_declared_definition/facility"

  _pkg_facility_file_validate "$pkg_facility_declared_file" || return 1
  while IFS= read -r pkg_facility_declared_line
  do
    _pkg_facility_line_parse "$pkg_facility_declared_line" || return 1
    if [ "$pkg_facility_name" = "$pkg_facility_declared_name" ]
    then
      pkg_facility_declared_compatibility=$pkg_facility_compatibility
      return 0
    fi
  done < "$pkg_facility_declared_file"

  return 1
}

_pkg_facility_assign()
{
  [ "$#" -eq 2 ] || return 2
  valid_shell_identifier "$1" || return 2
  IFS= read -r "$1" <<EOF_PKG_FACILITY_ASSIGN
$2
EOF_PKG_FACILITY_ASSIGN
}

pkg_facility_compatibility_read()
{
  [ "$#" -eq 3 ] || return 2
  valid_shell_identifier "$1" || return 2
  _pkg_facility_name_valid "$3" || return 2

  pkg_facility_query_file="$2/facility"
  if [ ! -e "$pkg_facility_query_file" ] && [ ! -L "$pkg_facility_query_file" ]
  then
    return 3
  fi
  _pkg_facility_file_validate "$pkg_facility_query_file" || return 1

  while IFS= read -r pkg_facility_query_line
  do
    _pkg_facility_line_parse "$pkg_facility_query_line" || return 1
    if [ "$pkg_facility_name" = "$3" ]
    then
      _pkg_facility_assign "$1" "$pkg_facility_compatibility"
      return
    fi
  done < "$pkg_facility_query_file"

  return 3
}

_pkg_facility_provider_part_validate()
{
  [ "$#" -ge 5 ] && [ "$#" -le 6 ] || return 2
  pkg_facility_provider_schema=${6-v1}
  pkg_facility_provider_part=$1
  pkg_facility_provider_contract_part=$2
  pkg_facility_provider_definition=$3
  pkg_facility_provider_root=$4
  pkg_facility_provider_name=$5

  case "$pkg_facility_provider_part" in
    cmd)
      if [ "$pkg_facility_provider_schema" = v2 ]
      then
        _pkg_facility_cmd_v2_provider_validate \
          "$pkg_facility_provider_contract_part" \
          "$pkg_facility_provider_definition" \
          "$pkg_facility_provider_root" \
          "$pkg_facility_provider_name"
      else
        _pkg_facility_cmd_provider_validate \
          "$pkg_facility_provider_contract_part" \
          "$pkg_facility_provider_definition/facility-cmd/$pkg_facility_provider_name" \
          "$pkg_facility_provider_definition" \
          "$pkg_facility_provider_root"
      fi
      ;;
    env)
      if [ "$pkg_facility_provider_schema" = v2 ]
      then
        _pkg_facility_env_v2_provider_validate \
          "$pkg_facility_provider_contract_part" \
          "$pkg_facility_provider_definition/facility-env/$pkg_facility_provider_name" \
          "$pkg_facility_provider_root"
      else
        _pkg_facility_env_provider_validate \
          "$pkg_facility_provider_contract_part" \
          "$pkg_facility_provider_definition/facility-env/$pkg_facility_provider_name" \
          "$pkg_facility_provider_root"
      fi
      ;;
    service)
      _pkg_facility_service_provider_validate \
        "$pkg_facility_provider_contract_part" \
        "$pkg_facility_provider_definition/facility-service/$pkg_facility_provider_name" \
        "$pkg_facility_provider_definition" \
        "$pkg_facility_provider_root"
      ;;
    *)
      return 1
      ;;
  esac
}

_pkg_facility_provider_declared_validate()
{
  [ "$#" -ge 5 ] && [ "$#" -le 6 ] || return 2
  pkg_facility_provider_schema=${6-v1}
  pkg_facility_provider_catalog=$1
  pkg_facility_provider_definition=$2
  pkg_facility_provider_root=$3
  pkg_facility_provider_name=$4
  pkg_facility_provider_compatibility=$5
  pkg_facility_provider_contract="$pkg_facility_provider_catalog/$pkg_facility_provider_name/$pkg_facility_provider_compatibility"

  pkg_facility_contract_validate "$pkg_facility_provider_contract" || return 1

  for pkg_facility_provider_contract_part in "$pkg_facility_provider_contract"/*
  do
    [ -e "$pkg_facility_provider_contract_part" ] || [ -L "$pkg_facility_provider_contract_part" ] || continue
    pkg_facility_provider_part=${pkg_facility_provider_contract_part##*/}
    _pkg_facility_provider_part_validate \
      "$pkg_facility_provider_part" \
      "$pkg_facility_provider_contract_part" \
      "$pkg_facility_provider_definition" \
      "$pkg_facility_provider_root" \
      "$pkg_facility_provider_name" \
      "$pkg_facility_provider_schema" || return 1
  done
}

_pkg_facility_provider_surface_validate()
{
  [ "$#" -eq 3 ] || return 2
  pkg_facility_surface_catalog=$1
  pkg_facility_surface_definition=$2
  pkg_facility_surface_type=$3
  pkg_facility_surface_root="$pkg_facility_surface_definition/facility-$pkg_facility_surface_type"

  if [ ! -e "$pkg_facility_surface_root" ] && [ ! -L "$pkg_facility_surface_root" ]
  then
    return 0
  fi

  [ -d "$pkg_facility_surface_root" ] && [ ! -L "$pkg_facility_surface_root" ] || return 1
  _pkg_facility_dir_entries_empty "$pkg_facility_surface_root" && return 1

  for pkg_facility_surface_entry in "$pkg_facility_surface_root"/*
  do
    [ -e "$pkg_facility_surface_entry" ] || [ -L "$pkg_facility_surface_entry" ] || continue
    pkg_facility_surface_name=${pkg_facility_surface_entry##*/}
    _pkg_facility_name_valid "$pkg_facility_surface_name" || return 1
    _pkg_facility_declared_compatibility "$pkg_facility_surface_definition" "$pkg_facility_surface_name" || return 1
    pkg_facility_surface_contract_type=$pkg_facility_surface_type
    [ "$pkg_facility_surface_type" != bin ] || pkg_facility_surface_contract_type=cmd
    pkg_facility_surface_contract="$pkg_facility_surface_catalog/$pkg_facility_surface_name/$pkg_facility_declared_compatibility/$pkg_facility_surface_contract_type"
    [ -d "$pkg_facility_surface_contract" ] && [ ! -L "$pkg_facility_surface_contract" ] || return 1
  done

  for pkg_facility_surface_hidden in "$pkg_facility_surface_root"/.[!.]* "$pkg_facility_surface_root"/..?*
  do
    [ -e "$pkg_facility_surface_hidden" ] || [ -L "$pkg_facility_surface_hidden" ] || continue
    return 1
  done
}

_pkg_facility_provider_unknown_surfaces_reject()
{
  [ "$#" -ge 1 ] && [ "$#" -le 2 ] || return 2
  pkg_facility_surface_definition=$1
  pkg_facility_surface_schema=${2-v1}

  for pkg_facility_surface_entry in "$pkg_facility_surface_definition"/facility-*
  do
    [ -e "$pkg_facility_surface_entry" ] || [ -L "$pkg_facility_surface_entry" ] || continue
    case "${pkg_facility_surface_entry##*/}" in
      facility-env | facility-service) : ;;
      facility-cmd) [ "$pkg_facility_surface_schema" = v1 ] || return 1 ;;
      facility-bin) [ "$pkg_facility_surface_schema" = v2 ] || return 1 ;;
      *) return 1 ;;
    esac
  done
}

pkg_facility_provider_validate()
{
  [ "$#" -eq 3 ] || return 2
  pkg_facility_provider_catalog_root=$1
  pkg_facility_provider_definition=$2
  pkg_facility_provider_root=$3
  pkg_facility_provider_file="$pkg_facility_provider_definition/facility"
  pkg_facility_provider_schema=v1
  case "$pkg_facility_provider_catalog_root" in
    */v2) pkg_facility_provider_schema=v2 ;;
  esac

  [ -d "$pkg_facility_provider_catalog_root" ] && [ ! -L "$pkg_facility_provider_catalog_root" ] || return 1
  [ -d "$pkg_facility_provider_catalog_root/pkg" ] && [ ! -L "$pkg_facility_provider_catalog_root/pkg" ] || return 1
  [ -d "$pkg_facility_provider_definition" ] && [ ! -L "$pkg_facility_provider_definition" ] || return 1
  [ -d "$pkg_facility_provider_root" ] && [ ! -L "$pkg_facility_provider_root" ] || return 1

  readpathce pkg_facility_provider_catalog_root_resolved "$pkg_facility_provider_catalog_root" || return 1
  readpathce pkg_facility_provider_pkg_root_resolved "$pkg_facility_provider_catalog_root/pkg" || return 1
  readpathce pkg_facility_provider_definition_resolved "$pkg_facility_provider_definition" || return 1
  case "$pkg_facility_provider_definition_resolved" in
    "$pkg_facility_provider_pkg_root_resolved"/*) : ;;
    *) return 1 ;;
  esac

  _pkg_facility_provider_unknown_surfaces_reject "$pkg_facility_provider_definition" "$pkg_facility_provider_schema" || return 1

  if [ ! -e "$pkg_facility_provider_file" ] && [ ! -L "$pkg_facility_provider_file" ]
  then
    [ ! -e "$pkg_facility_provider_definition/facility-cmd" ] && \
    [ ! -L "$pkg_facility_provider_definition/facility-cmd" ] && \
    [ ! -e "$pkg_facility_provider_definition/facility-env" ] && \
    [ ! -L "$pkg_facility_provider_definition/facility-env" ] && \
    [ ! -e "$pkg_facility_provider_definition/facility-service" ] && \
    [ ! -L "$pkg_facility_provider_definition/facility-service" ] && \
    [ ! -e "$pkg_facility_provider_definition/facility-bin" ] && \
    [ ! -L "$pkg_facility_provider_definition/facility-bin" ]
    return $?
  fi

  pkg_facility_provider_catalog="$pkg_facility_provider_catalog_root/facility"
  [ -d "$pkg_facility_provider_catalog" ] && [ ! -L "$pkg_facility_provider_catalog" ] || return 1
  _pkg_facility_file_validate "$pkg_facility_provider_file" || return 1

  while IFS= read -r pkg_facility_provider_line
  do
    _pkg_facility_line_parse "$pkg_facility_provider_line" || return 1
    _pkg_facility_provider_declared_validate \
      "$pkg_facility_provider_catalog" \
      "$pkg_facility_provider_definition" \
      "$pkg_facility_provider_root" \
      "$pkg_facility_name" \
      "$pkg_facility_compatibility" \
      "$pkg_facility_provider_schema" || return 1
  done < "$pkg_facility_provider_file"

  if [ "$pkg_facility_provider_schema" = v2 ]
  then
    _pkg_facility_provider_surface_validate "$pkg_facility_provider_catalog" "$pkg_facility_provider_definition" bin || return 1
  else
    _pkg_facility_provider_surface_validate "$pkg_facility_provider_catalog" "$pkg_facility_provider_definition" cmd || return 1
  fi
  _pkg_facility_provider_surface_validate "$pkg_facility_provider_catalog" "$pkg_facility_provider_definition" env || return 1
  _pkg_facility_provider_surface_validate "$pkg_facility_provider_catalog" "$pkg_facility_provider_definition" service
}

pkg_facility_service_start_resolve()
(
  [ "$#" -eq 2 ] || return 2
  pkg_facility_service_runtime_facility=$1
  pkg_facility_service_runtime_concrete_name=$2

  _pkg_facility_name_valid "$pkg_facility_service_runtime_facility" || return 2
  case "$pkg_facility_service_runtime_concrete_name" in
    "" | */* | *'
'*) return 2 ;;
  esac
  [ -n "${m_PKG_DIR-}" ] || return 1

  pkg_facility_service_runtime_concrete="$m_PKG_DIR/$pkg_facility_service_runtime_concrete_name"
  [ -d "$pkg_facility_service_runtime_concrete" ] && [ ! -L "$pkg_facility_service_runtime_concrete" ] || return 1
  readpathce pkg_facility_service_runtime_concrete_resolved "$pkg_facility_service_runtime_concrete" || return 1

  _pkg_facility_file_validate "$pkg_facility_service_runtime_concrete/facility" || return 1
  pkg_facility_service_runtime_declared=0
  while IFS= read -r pkg_facility_service_runtime_line
  do
    _pkg_facility_line_parse "$pkg_facility_service_runtime_line" || return 1
    if [ "$pkg_facility_name" = "$pkg_facility_service_runtime_facility" ]
    then
      pkg_facility_service_runtime_declared=1
      break
    fi
  done < "$pkg_facility_service_runtime_concrete/facility"
  [ "$pkg_facility_service_runtime_declared" -eq 1 ] || return 1

  _pkg_facility_service_realization_start_read \
    "$pkg_facility_service_runtime_concrete/facility-service/$pkg_facility_service_runtime_facility" || return 1
  pkg_facility_service_runtime_command=$pkg_facility_service_scalar
  _pkg_facility_cmd_name_valid "$pkg_facility_service_runtime_command" || return 1

  _pkg_schema_read "$pkg_facility_service_runtime_concrete" || return 1
  if [ "$pkg_schema" = v2 ]
  then
    pkg_facility_service_runtime_command_path="$pkg_facility_service_runtime_concrete/link/bin/$pkg_facility_service_runtime_command"
    [ -L "$pkg_facility_service_runtime_command_path" ] || return 1
    readpathce pkg_facility_service_runtime_command_resolved "$pkg_facility_service_runtime_command_path" || return 1
    case "$pkg_facility_service_runtime_command_resolved" in
      "$pkg_facility_service_runtime_concrete_resolved/root/"* | "$pkg_facility_service_runtime_concrete_resolved/cmd/"*) : ;;
      *) return 1 ;;
    esac
    [ -f "$pkg_facility_service_runtime_command_resolved" ] &&
      [ -x "$pkg_facility_service_runtime_command_resolved" ] || return 1
    printf -- '%s\n' "$pkg_facility_service_runtime_command_path"
    return 0
  fi

  pkg_facility_service_runtime_command_path="$pkg_facility_service_runtime_concrete/cmd/$pkg_facility_service_runtime_command"
  [ -f "$pkg_facility_service_runtime_command_path" ] && \
  [ ! -L "$pkg_facility_service_runtime_command_path" ] && \
  [ -x "$pkg_facility_service_runtime_command_path" ] || return 1
  readpathce pkg_facility_service_runtime_command_resolved "$pkg_facility_service_runtime_command_path" || return 1
  [ "$pkg_facility_service_runtime_command_resolved" = "$pkg_facility_service_runtime_concrete_resolved/cmd/$pkg_facility_service_runtime_command" ] || return 1

  printf -- '%s\n' "$pkg_facility_service_runtime_command_resolved"
)
