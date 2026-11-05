loadsyslib "pkg/pkg-common"
loadsyslib "pkg/pkg-catalog"
loadsyslib "pkg/pkg-depend"
loadsyslib "pkg/pkg-download"
loadsyslib "pkg/pkg-extract"
loadsyslib "pkg/pkg-integration"

pkg_install_one()
(
  [ "$#" -eq 1 ] || exit 1

  pkg_install_request=$1

  if pkg_concrete_read pkg_install_pkg pkg_install_version pkg_install_osarch "$pkg_install_request"
  then
    if [ -e "$m_PKG_DIR/$pkg_install_request" ] || [ -L "$m_PKG_DIR/$pkg_install_request" ]
    then
      [ -d "$m_PKG_DIR/$pkg_install_request" ] && [ ! -L "$m_PKG_DIR/$pkg_install_request" ] || exit 3
      exit 0
    fi
  fi

  pkg_catalog_request_resolve pkg_install_concrete pkg_install_target "$pkg_install_catalog_work" "$pkg_install_request" "$m_OSARCH" || exit 2
  pkg_concrete_read pkg_install_pkg pkg_install_version pkg_install_osarch "$pkg_install_concrete" || exit 2

  if [ -e "$m_PKG_DIR/$pkg_install_concrete" ] || [ -L "$m_PKG_DIR/$pkg_install_concrete" ]
  then
    [ -d "$m_PKG_DIR/$pkg_install_concrete" ] && [ ! -L "$m_PKG_DIR/$pkg_install_concrete" ] || exit 3
    exit 0
  fi

  pkg_catalog_range_resolve pkg_install_range "$pkg_install_catalog_work" "$pkg_install_concrete" || exit 7

  pkg_install_repository="${pkg_install_range%/*}/repository"
  pkg_install_repository_type="$(cat "$pkg_install_repository/type")" || exit 9
  pkg_install_repository_adapter="$m_LIB_DIR/sys/sh/pkg/repository/pkg-repository-$pkg_install_repository_type.lib.sh"

  pkg_install_item="$pkg_install_work/$pkg_install_concrete"
  mkdir -- "$pkg_install_item" || exit 10

  pkg_install_download_dir="$pkg_install_item/download"
  pkg_install_extract_dir="$pkg_install_item/extract"
  mkdir -- "$pkg_install_download_dir" "$pkg_install_extract_dir" || exit 11

  pkg_install_artifact="$( ( . "$pkg_install_repository_adapter" || exit 1; pkg_repository_resolve_artifact "$pkg_install_repository" "$pkg_install_range" "$pkg_install_version" ) | pkg_download "$pkg_install_download_dir" )" || exit 12

  pkg_extract "$pkg_install_artifact" "$pkg_install_range" "$pkg_install_extract_dir" || exit 13

  pkg_install_schema=v1
  pkg_install_definition_root=$pkg_install_catalog_work
  case "$pkg_install_catalog_work" in
    */v1)
      case "$pkg_install_range" in
        "${pkg_install_catalog_work%/v1}/v2/"*)
          pkg_install_schema=v2
          pkg_install_definition_root="${pkg_install_catalog_work%/v1}/v2"
          ;;
      esac
      ;;
  esac

  pkg_facility_provider_validate "$pkg_install_definition_root" "$pkg_install_range" "$pkg_install_extract_dir" || exit 17
  pkg_integrate "$pkg_install_pkg" "$pkg_install_version" "$pkg_install_range" "$pkg_install_extract_dir" "$pkg_install_osarch" "$pkg_install_schema" "$pkg_install_definition_root" || exit 18

  if [ -n "$pkg_install_osarch" ]
  then
    pkg_default_apply "$pkg_install_pkg" "$pkg_install_version" "$pkg_install_osarch" || exit 19
  else
    pkg_default_apply "$pkg_install_pkg" "$pkg_install_version" || exit 19
  fi
)

___pkg_install_resolve_one()
(
  [ "$#" -eq 1 ] || exit 1

  pkg_install_request=$1
  pkg_request_read pkg_install_pkg pkg_install_requested_version pkg_install_requested_osarch "$pkg_install_request" || exit 2

  if [ -n "$pkg_install_requested_osarch" ]
  then
    pkg_install_target=$pkg_install_requested_osarch
  else
    pkg_install_target=$m_OSARCH
  fi

  pkg_install_package="$pkg_install_catalog_work/pkg/$pkg_install_pkg"

  if [ -d "$pkg_install_package/$pkg_install_target" ]
  then
    pkg_install_stream="$pkg_install_package/$pkg_install_target"
    pkg_install_identity_osarch=$pkg_install_target
  elif [ -d "$pkg_install_package/all" ]
  then
    pkg_install_stream="$pkg_install_package/all"
    pkg_install_identity_osarch=
  else
    exit 2
  fi

  if [ -n "$pkg_install_requested_version" ]
  then
    _pkg_integration_set_concrete "$pkg_install_pkg" "$pkg_install_requested_version" "$pkg_install_identity_osarch" || exit 3

    if [ -e "$pkg_integration_concrete" ] || [ -L "$pkg_integration_concrete" ]
    then
      [ -d "$pkg_integration_concrete" ] && [ ! -L "$pkg_integration_concrete" ] || exit 4

      printf -- '%s\n' "$pkg_integration_concrete_name"
      exit 0
    fi

  else
    _pkg_local_class_scan "$pkg_install_pkg" "$pkg_install_identity_osarch" || exit 5

    if [ -n "$pkg_local_class_current_name" ]
    then
      printf -- '%s\n' "$pkg_local_class_current_name"
      exit 0
    fi
  fi

  pkg_install_repository="$pkg_install_stream/repository"

  pkg_install_repository_type="$(cat "$pkg_install_repository/type")" || exit 6

  case "$pkg_install_repository_type" in
    "" | [!a-z0-9]* | *[!a-z0-9-]* | *-)
      exit 7
    ;;
  esac

  pkg_install_repository_adapter="$m_LIB_DIR/sys/sh/pkg/repository/pkg-repository-$pkg_install_repository_type.lib.sh"

  if [ -n "$pkg_install_requested_version" ]
  then
    pkg_install_version="$(
      . "$pkg_install_repository_adapter" || exit 1
      pkg_repository_resolve_version "$pkg_install_repository" "$pkg_install_requested_version"
    )" || exit 8

    [ "$pkg_install_version" = "$pkg_install_requested_version" ] || exit 9
  else
    pkg_install_version="$(
      . "$pkg_install_repository_adapter" || exit 1
      pkg_repository_resolve_version "$pkg_install_repository"
    )" || exit 8
  fi

  pkg_version_valid "$pkg_install_version" || exit 10

  _pkg_integration_set_concrete "$pkg_install_pkg" "$pkg_install_version" "$pkg_install_identity_osarch" || exit 11

  printf -- '%s\n' "$pkg_integration_concrete_name"
)

pkg_install_resolve_one()
(
  [ "$#" -eq 1 ] || exit 1

  pkg_install_request=$1
  pkg_request_read pkg_install_pkg pkg_install_requested_version pkg_install_requested_osarch "$pkg_install_request" || exit 2

  if [ -n "$pkg_install_requested_osarch" ]
  then
    pkg_install_target=$pkg_install_requested_osarch
  else
    pkg_install_target=$m_OSARCH
  fi

  pkg_catalog_stream_resolve pkg_install_stream pkg_install_identity_osarch "$pkg_install_catalog_work" "$pkg_install_pkg" "$pkg_install_target" || exit 3

  if [ -n "$pkg_install_requested_version" ]
  then
    pkg_install_concrete="$pkg_install_pkg@$pkg_install_requested_version"
    [ -z "$pkg_install_identity_osarch" ] || pkg_install_concrete="$pkg_install_concrete!$pkg_install_identity_osarch"

    if [ -d "$m_PKG_DIR/$pkg_install_concrete" ]
    then
      printf -- '%s\n' "$pkg_install_concrete"
      exit 0
    fi
  else
    _pkg_local_class_scan "$pkg_install_pkg" "$pkg_install_identity_osarch" || exit 5

    if [ -n "$pkg_local_class_current_name" ]
    then
      printf -- '%s\n' "$pkg_local_class_current_name"
      exit 0
    fi
  fi

  if [ -n "$pkg_install_requested_version" ]
  then
    pkg_catalog_version_resolve pkg_install_version "$pkg_install_stream" "$pkg_install_requested_version" || exit 4
  else
    pkg_catalog_version_resolve pkg_install_version "$pkg_install_stream" || exit 4
  fi

  pkg_install_concrete="$pkg_install_pkg@$pkg_install_version"
  [ -z "$pkg_install_identity_osarch" ] || pkg_install_concrete="$pkg_install_concrete!$pkg_install_identity_osarch"

  printf -- '%s\n' "$pkg_install_concrete"
)

pkg_install_resolve()
(
  [ "$#" -ge 1 ] || exit 1

  _pkg_install_resolve_separator=""

  for pkg_install_request
  do
    pkg_install_concrete="$(pkg_install_resolve_one "$pkg_install_request")" || exit 2
    pkg_install_quoted="$(quote "$pkg_install_concrete")" || exit 3

    printf -- '%s' "${_pkg_install_resolve_separator}${pkg_install_quoted}"
    _pkg_install_resolve_separator=" "
  done
)

pkg_install_validate()
(
  [ "$#" -ge 1 ] || exit 1

  for pkg_install_operand
  do
    pkg_request_read pkg_install_pkg pkg_install_version pkg_install_osarch "$pkg_install_operand" || exit 2
  done
)

_pkg_install_init()
{
  [ "$#" -eq 0 ] || return 1

  mkdir -p $m_PKG_DIR

  trap '_pkg_install_end' 0
  trap 'exit 130' HUP INT TERM

  umask 077

  pkg_install_tmp_root="$(state-path system sys pkg tmp)" || return 2
  mkdir -p -- "$pkg_install_tmp_root" || return 3

  pkg_install_cache_root="$(state-path system sys pkg cache)" || return 4
  mkdir -p -- "$pkg_install_cache_root" || return 5

  pkg_install_work="$pkg_install_tmp_root/install2-$$"
  mkdir -p -- "$pkg_install_work" || return 6

  pkg_catalog_init pkg_install_catalog_work pkg_install_catalog_head "$pkg_install_work" "$pkg_install_cache_root" || return 7
}

_pkg_install_end()
{
  rm -rf -- "$pkg_install_work"
}

pkg_install()
(
  [ "$#" -ge 1 ] || exit 1

  pkg_install_validate "$@" || fatal 2 execution invalid-arguments operation pkg-install

  _pkg_install_init || fatal 3 execution execution-failed operation pkg-install reason pkg-init-failed

  _pkg_install_list_requested=
  for _pkg_install_request
  do
    _pkg_install_request_quoted="$(quote "$_pkg_install_request")" ||
      fatal 3 execution execution-failed operation pkg-install reason pkg-init-failed

    if [ -n "$_pkg_install_list_requested" ]
    then
      _pkg_install_list_requested="$_pkg_install_list_requested $_pkg_install_request_quoted"
    else
      _pkg_install_list_requested=$_pkg_install_request_quoted
    fi
  done

  _pkg_install_dependency_output=$(pkg depend "$@") || fatal 5 execution execution-failed operation pkg-install reason dependency-unresolvable
  _pkg_install_list_dependency_resolved=

  if [ -n "$_pkg_install_dependency_output" ]
  then
    while IFS= read -r _pkg_install_dependency
    do
      [ -n "$_pkg_install_dependency" ] || fatal 5 execution execution-failed operation pkg-install reason dependency-unresolvable
      _pkg_install_dependency_quoted="$(quote "$_pkg_install_dependency")" ||
        fatal 5 execution execution-failed operation pkg-install reason dependency-unresolvable

      if [ -n "$_pkg_install_list_dependency_resolved" ]
      then
        _pkg_install_list_dependency_resolved="$_pkg_install_list_dependency_resolved $_pkg_install_dependency_quoted"
      else
        _pkg_install_list_dependency_resolved=$_pkg_install_dependency_quoted
      fi
    done <<EOF_PKG_INSTALL_DEPENDENCIES
$_pkg_install_dependency_output
EOF_PKG_INSTALL_DEPENDENCIES
  fi

  eval "set -- $_pkg_install_list_dependency_resolved $_pkg_install_list_requested"

  for _pkg_install_pkg
  do
    pkg_install_one "$_pkg_install_pkg"
    _pkg_install_status=$?
    [ "$_pkg_install_status" -eq 0 ] && continue

    case "$_pkg_install_status" in
      12) _pkg_install_stage=download ;;
      13) _pkg_install_stage=extract ;;
      17) _pkg_install_stage=provider-validation ;;
      18) _pkg_install_stage=integration ;;
      19) _pkg_install_stage=default-selection ;;
      *) _pkg_install_stage=install ;;
    esac

    fatal 6 execution execution-failed       operation pkg-install       reason install-failed       package "$_pkg_install_pkg"       stage "$_pkg_install_stage"       status "$_pkg_install_status"
  done
)
