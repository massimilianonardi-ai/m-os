_pkg_facility_service_scalar_read()
{
  [ "$#" -eq 1 ] || return 2
  [ -f "$1" ] && [ ! -L "$1" ] && [ -r "$1" ] && [ ! -x "$1" ] || return 1

  pkg_facility_service_scalar=
  pkg_facility_service_extra=
  {
    IFS= read -r pkg_facility_service_scalar || return 1
    IFS= read -r pkg_facility_service_extra
    pkg_facility_service_second_status=$?
  } < "$1"

  [ "$pkg_facility_service_second_status" -ne 0 ] || return 1
  [ -z "$pkg_facility_service_extra" ] || return 1
  [ -n "$pkg_facility_service_scalar" ] || return 1

  pkg_facility_service_actual="$(command -p -- wc -c < "$1")" || return 1
  pkg_facility_service_expected="$(printf -- '%s\n' "$pkg_facility_service_scalar" | command -p -- wc -c)" || return 1
  [ "$pkg_facility_service_actual" = "$pkg_facility_service_expected" ]
}

_pkg_facility_service_realization_start_read()
{
  [ "$#" -eq 1 ] || return 2
  pkg_facility_service_realization=$1

  [ -d "$pkg_facility_service_realization" ] && [ ! -L "$pkg_facility_service_realization" ] || return 1

  pkg_facility_service_count=0
  for pkg_facility_service_entry in \
    "$pkg_facility_service_realization"/* \
    "$pkg_facility_service_realization"/.[!.]* \
    "$pkg_facility_service_realization"/..?*
  do
    [ -e "$pkg_facility_service_entry" ] || [ -L "$pkg_facility_service_entry" ] || continue
    [ -f "$pkg_facility_service_entry" ] && [ ! -L "$pkg_facility_service_entry" ] || return 1
    [ "${pkg_facility_service_entry##*/}" = start ] || return 1
    pkg_facility_service_count=$((pkg_facility_service_count + 1))
  done
  [ "$pkg_facility_service_count" -eq 1 ] || return 1

  _pkg_facility_service_scalar_read "$pkg_facility_service_realization/start"
}

_pkg_facility_service_contract_validate()
{
  [ "$#" -eq 1 ] || return 2
  pkg_facility_service_contract=$1

  [ -d "$pkg_facility_service_contract" ] && [ ! -L "$pkg_facility_service_contract" ] || return 1

  pkg_facility_service_count=0
  for pkg_facility_service_entry in \
    "$pkg_facility_service_contract"/* \
    "$pkg_facility_service_contract"/.[!.]* \
    "$pkg_facility_service_contract"/..?*
  do
    [ -e "$pkg_facility_service_entry" ] || [ -L "$pkg_facility_service_entry" ] || continue
    [ -f "$pkg_facility_service_entry" ] && [ ! -L "$pkg_facility_service_entry" ] || return 1

    case "${pkg_facility_service_entry##*/}" in
      start | process | stop) : ;;
      *) return 1 ;;
    esac
    pkg_facility_service_count=$((pkg_facility_service_count + 1))
  done
  [ "$pkg_facility_service_count" -eq 3 ] || return 1

  _pkg_facility_service_scalar_read "$pkg_facility_service_contract/start" || return 1
  pkg_facility_service_start_type=package-command
  case "$pkg_facility_service_contract" in
    */v2/facility/*/service) pkg_facility_service_start_type=package-bin ;;
  esac
  [ "$pkg_facility_service_scalar" = "$pkg_facility_service_start_type" ] || return 1

  _pkg_facility_service_scalar_read "$pkg_facility_service_contract/process" || return 1
  [ "$pkg_facility_service_scalar" = foreground ] || return 1

  _pkg_facility_service_scalar_read "$pkg_facility_service_contract/stop" || return 1
  [ "$pkg_facility_service_scalar" = sigterm ]
}

_pkg_facility_service_realization_validate()
{
  [ "$#" -ge 3 ] && [ "$#" -le 4 ] || return 2
  pkg_facility_service_schema=${4-v1}
  pkg_facility_service_realization=$1
  pkg_facility_service_definition=$2
  pkg_facility_service_root=$3

  [ -d "$pkg_facility_service_definition" ] && [ ! -L "$pkg_facility_service_definition" ] || return 1
  [ -d "$pkg_facility_service_root" ] && [ ! -L "$pkg_facility_service_root" ] || return 1
  _pkg_facility_service_realization_start_read "$pkg_facility_service_realization" || return 1

  pkg_facility_service_command=$pkg_facility_service_scalar
  if [ "$pkg_facility_service_schema" = v2 ]
  then
    _pkg_facility_cmd_v2_entry_validate \
      "$pkg_facility_service_definition" \
      "$pkg_facility_service_root" \
      "$pkg_facility_service_command"
  else
    _pkg_facility_cmd_package_command_validate \
      "$pkg_facility_service_definition" \
      "$pkg_facility_service_command" \
      "$pkg_facility_service_root"
  fi
}

_pkg_facility_service_provider_validate()
{
  [ "$#" -eq 4 ] || return 2
  _pkg_facility_service_contract_validate "$1" || return 1
  pkg_facility_service_schema=v1
  case "$1" in */v2/facility/*/service) pkg_facility_service_schema=v2 ;; esac
  _pkg_facility_service_realization_validate "$2" "$3" "$4" "$pkg_facility_service_schema"
}
