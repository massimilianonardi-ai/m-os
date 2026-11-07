loadsyslib "pkg/pkg-local"
loadsyslib "pkg/pkg-integration"

_pkg_uninstall_error()
{
  log error execution execution-failed operation pkg-uninstall reason "$1"
}

_pkg_uninstall_resolve()
{
  [ "$#" -eq 1 ] || return 2
  _pkg_local_operand_parse "$1" || return 2
  _pkg_local_class_select "$pkg_local_pkg" "$pkg_local_requested_osarch" || return 1
  [ "$pkg_local_class_present" -eq 1 ] || return 1

  pkg_uninstall_pkg=$pkg_local_pkg
  pkg_uninstall_identity_osarch=$pkg_local_identity_osarch

  if [ -n "$pkg_local_requested_version" ]
  then
    pkg_uninstall_version=$pkg_local_requested_version
    pkg_integration_set_concrete "$pkg_uninstall_pkg" "$pkg_uninstall_version" "$pkg_uninstall_identity_osarch" || return 1
    [ -d "$pkg_integration_concrete" ] && [ ! -L "$pkg_integration_concrete" ] || return 1
  elif [ -n "$pkg_local_class_current_version" ]
  then
    pkg_uninstall_version=$pkg_local_class_current_version
  elif [ "$pkg_local_class_count" -eq 1 ]
  then
    pkg_uninstall_version=$pkg_local_class_single_version
  else
    return 1
  fi

  pkg_uninstall_is_current=0
  if [ -n "$pkg_local_class_current_version" ] && [ "$pkg_uninstall_version" = "$pkg_local_class_current_version" ]
  then
    pkg_uninstall_is_current=1
  fi
}

_pkg_uninstall_one()
(
  [ "$#" -eq 1 ] || return 2
  _pkg_uninstall_resolve "$1" || return 1

  pkg_integration_set_concrete "$pkg_uninstall_pkg" "$pkg_uninstall_version" "$pkg_uninstall_identity_osarch" || return 1
  _pkg_dependency_provider_unreferenced "$pkg_integration_concrete_name" || return 1

  if [ "$pkg_uninstall_is_current" -eq 1 ]
  then
    if [ -n "$pkg_uninstall_identity_osarch" ]
    then
      pkg_default_apply "$pkg_uninstall_pkg" "" "$pkg_uninstall_identity_osarch" || return 1
    else
      pkg_default_apply "$pkg_uninstall_pkg" "" || return 1
    fi
  fi

  if [ -n "$pkg_uninstall_identity_osarch" ]
  then
    pkg_deintegrate "$pkg_uninstall_pkg" "$pkg_uninstall_version" "$pkg_uninstall_identity_osarch" || return 1
  else
    pkg_deintegrate "$pkg_uninstall_pkg" "$pkg_uninstall_version" || return 1
  fi
)

pkg_uninstall()
(
  [ "$#" -ge 1 ] || return 2

  for pkg_uninstall_operand
  do
    _pkg_local_operand_parse "$pkg_uninstall_operand" || return 2
  done

  for pkg_uninstall_operand
  do
    if ! _pkg_uninstall_one "$pkg_uninstall_operand"
    then
      _pkg_uninstall_error package-failed
      return 1
    fi
  done

  return 0
)
