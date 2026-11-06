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

  pkg_facility_provider_validate "$pkg_install_catalog_work" "$pkg_install_range" "$pkg_install_extract_dir" || exit 17
  pkg_integrate "$pkg_install_pkg" "$pkg_install_version" "$pkg_install_range" "$pkg_install_extract_dir" "$pkg_install_osarch" || exit 18

  if [ -n "$pkg_install_osarch" ]
  then
    pkg_default_apply "$pkg_install_pkg" "$pkg_install_version" "$pkg_install_osarch" || exit 19
  else
    pkg_default_apply "$pkg_install_pkg" "$pkg_install_version" || exit 19
  fi
)

_pkg_install_resolve_one()
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

    if [ -e "$m_PKG_DIR/$pkg_install_concrete" ] || [ -L "$m_PKG_DIR/$pkg_install_concrete" ]
    then
      [ -d "$m_PKG_DIR/$pkg_install_concrete" ] && [ ! -L "$m_PKG_DIR/$pkg_install_concrete" ] || exit 6
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

_pkg_install_resolve()
(
  [ "$#" -ge 1 ] || exit 1

  _pkg_install_resolve_separator=""

  for pkg_install_request
  do
    pkg_install_concrete="$(_pkg_install_resolve_one "$pkg_install_request")" || exit 2
    pkg_request_read pkg_install_name pkg_install_requested_version pkg_install_requested_osarch "$pkg_install_request" || exit 4
    pkg_install_target=$m_OSARCH
    [ -z "$pkg_install_requested_osarch" ] || pkg_install_target=$pkg_install_requested_osarch
    pkg_osarch_valid "$pkg_install_target" || exit 5
    pkg_install_quoted="$(quote "$pkg_install_concrete|$pkg_install_target")" || exit 3

    printf -- '%s' "${_pkg_install_resolve_separator}${pkg_install_quoted}"
    _pkg_install_resolve_separator=" "
  done
)

_pkg_install_validate()
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

  mkdir -p -- "$m_PKG_DIR"

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

_pkg_install_one_checked()
(
  [ "$#" -eq 1 ] || return 2
  pkg_install_one "$1"
  _pkg_install_status=$?
  [ "$_pkg_install_status" -eq 0 ] && return 0

  case "$_pkg_install_status" in
    1) fatal 1 pkg-install invalid-internal-request package "$1" status "$_pkg_install_status" ;;
    2) fatal 1 pkg-install concrete-resolution-failed package "$1" status "$_pkg_install_status" ;;
    3) fatal 1 pkg-install invalid-installed-concrete package "$1" status "$_pkg_install_status" ;;
    7) fatal 1 pkg-install range-resolution-failed package "$1" status "$_pkg_install_status" ;;
    9) fatal 1 pkg-install repository-type-failed package "$1" status "$_pkg_install_status" ;;
    10) fatal 1 pkg-install staging-create-failed package "$1" status "$_pkg_install_status" ;;
    11) fatal 1 pkg-install staging-setup-failed package "$1" status "$_pkg_install_status" ;;
    12) fatal 1 pkg-install download-failed package "$1" status "$_pkg_install_status" ;;
    13) fatal 1 pkg-install extraction-failed package "$1" status "$_pkg_install_status" ;;
    17) fatal 1 pkg-install provider-validation-failed package "$1" status "$_pkg_install_status" ;;
    18) fatal 1 pkg-install integration-failed package "$1" status "$_pkg_install_status" ;;
    19) fatal 1 pkg-install default-selection-failed package "$1" status "$_pkg_install_status" ;;
    *) fatal 1 pkg-install unexpected-install-status package "$1" status "$_pkg_install_status" ;;
  esac
)

pkg_install()
(
  [ "$#" -ge 1 ] || return 2

  _pkg_install_validate "$@" ||
    fatal 2 pkg-install invalid-request-list operation pkg-install

  _pkg_install_init ||
    fatal 1 pkg-install initialization-failed operation pkg-install

  _pkg_install_list_contexts="$(_pkg_install_resolve "$@")" ||
    fatal 1 pkg-install root-resolution-failed operation pkg-install

  # Keep the requested target with each exact root. In particular, an
  # osarch-independent "all" concrete has no !osarch identity suffix, while
  # its provider dependencies still use the originally requested target.
  eval "set -- $_pkg_install_list_contexts"
  _pkg_install_list_requested=
  _pkg_install_separator=
  for _pkg_install_context
  do
    _pkg_install_root=${_pkg_install_context%%|*}
    _pkg_install_target=${_pkg_install_context#*|}
    [ "$_pkg_install_root" != "$_pkg_install_context" ] ||
      fatal 1 pkg-install invalid-root-context context "$_pkg_install_context"
    pkg_concrete_read _pkg_install_name _pkg_install_version _pkg_install_osarch "$_pkg_install_root" ||
      fatal 1 pkg-install invalid-root-concrete package "$_pkg_install_root"
    pkg_osarch_valid "$_pkg_install_target" ||
      fatal 1 pkg-install invalid-root-target target "$_pkg_install_target"
    _pkg_install_quoted="$(quote "$_pkg_install_root")" ||
      fatal 1 pkg-install root-quoting-failed package "$_pkg_install_root"
    _pkg_install_list_requested="$_pkg_install_list_requested$_pkg_install_separator$_pkg_install_quoted"
    _pkg_install_separator=" "
  done

  # Distinguish roots that existed before this invocation from roots
  # materialized during its dependency-first installation.
  eval "set -- $_pkg_install_list_requested"
  _pkg_install_preexisting_roots=
  for _pkg_install_root
  do
    if [ -e "$m_PKG_DIR/$_pkg_install_root" ] || [ -L "$m_PKG_DIR/$_pkg_install_root" ]
    then
      [ -d "$m_PKG_DIR/$_pkg_install_root" ] && [ ! -L "$m_PKG_DIR/$_pkg_install_root" ] ||
        fatal 1 pkg-install invalid-installed-concrete package "$_pkg_install_root"
      _pkg_install_preexisting_roots="$_pkg_install_preexisting_roots $_pkg_install_root"
    fi
  done

  eval "set -- $_pkg_install_list_contexts"
  _pkg_install_list_dependencies="$(pkg_depend_plan "$pkg_install_catalog_work" "$@")" ||
    fatal 1 pkg-install dependency-planning-failed operation pkg-install

  # Dependency concretes and requested roots use the same catalog snapshot.
  eval "set -- $_pkg_install_list_dependencies"
  _pkg_install_completed_dependencies=
  for _pkg_install_dependency
  do
    _pkg_install_one_checked "$_pkg_install_dependency" || return 1
    _pkg_install_completed_dependencies="$_pkg_install_completed_dependencies $_pkg_install_dependency"
  done

  eval "set -- $_pkg_install_list_requested"
  _pkg_install_existing_failed=0
  for _pkg_install_root
  do
    if [ -e "$m_PKG_DIR/$_pkg_install_root" ] || [ -L "$m_PKG_DIR/$_pkg_install_root" ]
    then
      if [ ! -d "$m_PKG_DIR/$_pkg_install_root" ] || [ -L "$m_PKG_DIR/$_pkg_install_root" ]
      then
        fatal 1 pkg-install invalid-installed-concrete package "$_pkg_install_root"
      fi

      # A root newly installed as another root's dependency is fulfilled,
      # not a pre-existing explicit-root request or duplicate root error.
      case " $_pkg_install_preexisting_roots " in
        *" $_pkg_install_root "*) : ;;
        *)
          case " $_pkg_install_completed_dependencies " in
            *" $_pkg_install_root "*) continue ;;
          esac
          ;;
      esac

      pkg_concrete_read _pkg_install_name _pkg_install_version _pkg_install_osarch "$_pkg_install_root" ||
        fatal 1 pkg-install invalid-root-identity package "$_pkg_install_root"

      _pkg_install_class=$_pkg_install_name
      [ -z "$_pkg_install_osarch" ] ||
        _pkg_install_class="$_pkg_install_name!$_pkg_install_osarch"
      _pkg_install_current="$(pkg_default "$_pkg_install_class" 2>/dev/null)" || _pkg_install_current=

      log error pkg-install already-installed \
        package "$_pkg_install_root" \
        current "$_pkg_install_current" || :
      _pkg_install_existing_failed=1
      continue
    fi

    _pkg_install_one_checked "$_pkg_install_root" || return 1
  done

  [ "$_pkg_install_existing_failed" -eq 0 ]
)
