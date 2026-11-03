loadsyslib "pkg/pkg-common"

_pkg_catalog_assign()
{
  [ "$#" -eq 2 ] || return 2
  valid_shell_identifier "$1" || return 2
  IFS= read -r "$1" <<EOF_PKG_CATALOG_ASSIGN
$2
EOF_PKG_CATALOG_ASSIGN
}

_pkg_catalog_scalar_read()
{
  [ "$#" -eq 1 ] || return 2
  [ -f "$1" ] && [ ! -L "$1" ] && [ -r "$1" ] && [ ! -x "$1" ] || return 1

  pkg_catalog_scalar=
  pkg_catalog_scalar_extra=
  {
    IFS= read -r pkg_catalog_scalar || return 1
    IFS= read -r pkg_catalog_scalar_extra
    pkg_catalog_scalar_second_status=$?
  } < "$1"

  [ "$pkg_catalog_scalar_second_status" -ne 0 ] || return 1
  [ -z "$pkg_catalog_scalar_extra" ] || return 1
  [ -n "$pkg_catalog_scalar" ] || return 1

  pkg_catalog_scalar_cr="$(printf '\r')"
  case "$pkg_catalog_scalar" in
    *"$pkg_catalog_scalar_cr"*) return 1 ;;
  esac

  pkg_catalog_scalar_actual="$(command -p -- wc -c < "$1")" || return 1
  pkg_catalog_scalar_expected="$(printf '%s\n' "$pkg_catalog_scalar" | command -p -- wc -c)" || return 1
  [ "$pkg_catalog_scalar_actual" = "$pkg_catalog_scalar_expected" ] || return 1

  printf -- '%s\n' "$pkg_catalog_scalar"
}

_pkg_catalog_repository_adapter()
{
  [ "$#" -eq 1 ] || return 2

  pkg_catalog_repository=$1
  pkg_catalog_repository_type="$(_pkg_catalog_scalar_read "$pkg_catalog_repository/type")" || return 1

  case "$pkg_catalog_repository_type" in
    "" | [!abcdefghijklmnopqrstuvwxyz0123456789]* | *[!abcdefghijklmnopqrstuvwxyz0123456789-]* | *-) return 1 ;;
  esac

  pkg_catalog_repository_adapter="$m_LIB_DIR/sys/sh/pkg/repository/pkg-repository-$pkg_catalog_repository_type.lib.sh"
  [ -f "$pkg_catalog_repository_adapter" ] && [ ! -L "$pkg_catalog_repository_adapter" ] && [ -r "$pkg_catalog_repository_adapter" ] && [ ! -x "$pkg_catalog_repository_adapter" ]
}

_pkg_catalog_compare_versions()
{
  [ "$#" -eq 4 ] || return 2

  pkg_catalog_compare="$(
    . "$1" || exit 1
    pkg_repository_compare_versions "$2" "$3" "$4"
  )" || return 1

  case "$pkg_catalog_compare" in
    -1|0|1) printf -- '%s\n' "$pkg_catalog_compare" ;;
    *) return 1 ;;
  esac
}

pkg_catalog_init()
{
  [ "$#" -eq 4 ] || return 2
  valid_shell_identifier "$1" "$2" || return 2
  [ "$1" != "$2" ] || return 2

  pkg_catalog_output_work=$1
  pkg_catalog_output_head=$2
  pkg_catalog_work_root=$3
  pkg_catalog_cache_root=$4

  [ -d "$pkg_catalog_work_root" ] && [ ! -L "$pkg_catalog_work_root" ] || return 1
  [ -d "$pkg_catalog_cache_root" ] && [ ! -L "$pkg_catalog_cache_root" ] || return 1

  pkg_catalog_conf="$(state-path system sys pkg conf)/catalog" || return 1
  pkg_catalog_url="$(_pkg_catalog_scalar_read "$pkg_catalog_conf")" || return 1

  pkg_catalog_work="$pkg_catalog_work_root/catalog"
  [ ! -e "$pkg_catalog_work" ] && [ ! -L "$pkg_catalog_work" ] || return 1
  command -p -- mkdir "$pkg_catalog_work" || return 1

  pkg_catalog_cache="$pkg_catalog_cache_root/catalog"

  if [ ! -d "$pkg_catalog_cache/.git" ]
  then
    git clone -- "$pkg_catalog_url" "$pkg_catalog_cache" >&2 || return 1
  else
    git -C "$pkg_catalog_cache" remote set-url origin "$pkg_catalog_url" || return 1
    git -C "$pkg_catalog_cache" pull --ff-only >&2 || return 1
  fi

  pkg_catalog_head="$(git -C "$pkg_catalog_cache" rev-parse HEAD)" || return 1
  git -C "$pkg_catalog_cache" archive "$pkg_catalog_head" | tar -x -C "$pkg_catalog_work" || return 1

  # v1 preserves the original pkg/facility definition schema unchanged.
  # Accept an unversioned catalog only as the explicit legacy snapshot shape.
  pkg_catalog_definition_root=$pkg_catalog_work
  if [ -e "$pkg_catalog_work/v1" ] || [ -L "$pkg_catalog_work/v1" ]
  then
    valid_dir "$pkg_catalog_work/v1" || return 1
    [ ! -e "$pkg_catalog_work/pkg" ] && [ ! -L "$pkg_catalog_work/pkg" ] || return 1
    [ ! -e "$pkg_catalog_work/facility" ] && [ ! -L "$pkg_catalog_work/facility" ] || return 1
    pkg_catalog_definition_root="$pkg_catalog_work/v1"
  fi
  valid_dir "$pkg_catalog_definition_root/pkg" || return 1
  valid_dir "$pkg_catalog_definition_root/facility" || return 1

  _pkg_catalog_assign "$pkg_catalog_output_work" "$pkg_catalog_definition_root" || return 1
  _pkg_catalog_assign "$pkg_catalog_output_head" "$pkg_catalog_head"
}

pkg_catalog_stream_resolve()
{
  [ "$#" -eq 5 ] || return 2
  valid_shell_identifier "$1" "$2" || return 2
  [ "$1" != "$2" ] || return 2

  pkg_catalog_output_stream=$1
  pkg_catalog_output_identity_osarch=$2
  pkg_catalog_root=$3
  pkg_catalog_package=$4
  pkg_catalog_target=$5

  pkg_name_valid "$pkg_catalog_package" || return 1
  pkg_osarch_valid "$pkg_catalog_target" || return 1
  [ -d "$pkg_catalog_root" ] && [ ! -L "$pkg_catalog_root" ] || return 1

  pkg_catalog_package_dir="$pkg_catalog_root/pkg/$pkg_catalog_package"
  pkg_catalog_target_stream="$pkg_catalog_package_dir/$pkg_catalog_target"
  pkg_catalog_generic_stream="$pkg_catalog_package_dir/all"

  [ -d "$pkg_catalog_package_dir" ] && [ ! -L "$pkg_catalog_package_dir" ] || return 1

  if [ -e "$pkg_catalog_target_stream" ] || [ -L "$pkg_catalog_target_stream" ]
  then
    [ -d "$pkg_catalog_target_stream" ] && [ ! -L "$pkg_catalog_target_stream" ] || return 1
    pkg_catalog_stream=$pkg_catalog_target_stream
    pkg_catalog_identity_osarch=$pkg_catalog_target
  elif [ -e "$pkg_catalog_generic_stream" ] || [ -L "$pkg_catalog_generic_stream" ]
  then
    [ -d "$pkg_catalog_generic_stream" ] && [ ! -L "$pkg_catalog_generic_stream" ] || return 1
    pkg_catalog_stream=$pkg_catalog_generic_stream
    pkg_catalog_identity_osarch=
  else
    return 1
  fi

  _pkg_catalog_assign "$pkg_catalog_output_stream" "$pkg_catalog_stream" || return 1
  _pkg_catalog_assign "$pkg_catalog_output_identity_osarch" "$pkg_catalog_identity_osarch"
}

pkg_catalog_request_resolve()
{
  [ "$#" -eq 5 ] || return 2
  valid_shell_identifier "$1" "$2" || return 2
  [ "$1" != "$2" ] || return 2

  pkg_catalog_output_concrete=$1
  pkg_catalog_output_target=$2
  pkg_catalog_root=$3
  pkg_catalog_request=$4
  pkg_catalog_default_target=$5

  [ -d "$pkg_catalog_root" ] && [ ! -L "$pkg_catalog_root" ] || return 1
  pkg_request_read pkg_catalog_package pkg_catalog_requested_version pkg_catalog_requested_osarch "$pkg_catalog_request" || return 2

  if [ -n "$pkg_catalog_requested_osarch" ]
  then
    pkg_catalog_target=$pkg_catalog_requested_osarch
  else
    pkg_catalog_target=$pkg_catalog_default_target
  fi
  pkg_osarch_valid "$pkg_catalog_target" || return 1

  pkg_catalog_stream_resolve pkg_catalog_request_stream pkg_catalog_identity_osarch "$pkg_catalog_root" "$pkg_catalog_package" "$pkg_catalog_target" || return 1

  if [ -n "$pkg_catalog_requested_version" ]
  then
    pkg_catalog_version_resolve pkg_catalog_request_version "$pkg_catalog_request_stream" "$pkg_catalog_requested_version" || return 1
  else
    pkg_catalog_version_resolve pkg_catalog_request_version "$pkg_catalog_request_stream" || return 1
  fi

  pkg_catalog_concrete="$pkg_catalog_package@$pkg_catalog_request_version"
  [ -z "$pkg_catalog_identity_osarch" ] || pkg_catalog_concrete="$pkg_catalog_concrete!$pkg_catalog_identity_osarch"
  pkg_concrete_read pkg_catalog_check_package pkg_catalog_check_version pkg_catalog_check_osarch "$pkg_catalog_concrete" || return 1

  _pkg_catalog_assign "$pkg_catalog_output_concrete" "$pkg_catalog_concrete" || return 1
  _pkg_catalog_assign "$pkg_catalog_output_target" "$pkg_catalog_target"
}

_pkg_catalog_latest_known()
(
  [ "$#" -eq 1 ] || return 2
  pkg_catalog_versions_file="$1/repository/versions"
  [ -f "$pkg_catalog_versions_file" ] && [ ! -L "$pkg_catalog_versions_file" ] && \
    [ -r "$pkg_catalog_versions_file" ] && [ ! -x "$pkg_catalog_versions_file" ] || return 1
  LC_ALL=C command -p -- awk '
    {
      if ($0 !~ /^[A-Za-z0-9][A-Za-z0-9._+~-]*$/ || seen[$0]++) {
        invalid=1
        exit 1
      }
      last=$0
    }
    END {
      if (invalid || NR == 0) exit 1
      print last
    }
  ' "$pkg_catalog_versions_file"
)

pkg_catalog_version_resolve()
{
  [ "$#" -eq 2 ] || [ "$#" -eq 3 ] || return 2
  valid_shell_identifier "$1" || return 2

  pkg_catalog_output_version=$1
  pkg_catalog_stream=$2
  pkg_catalog_requested_version=${3-}

  [ -d "$pkg_catalog_stream" ] && [ ! -L "$pkg_catalog_stream" ] || return 1
  pkg_catalog_repository="$pkg_catalog_stream/repository"
  [ -d "$pkg_catalog_repository" ] && [ ! -L "$pkg_catalog_repository" ] || return 1
  _pkg_catalog_repository_adapter "$pkg_catalog_repository" || return 1
  pkg_catalog_adapter=$pkg_catalog_repository_adapter

  if [ -n "$pkg_catalog_requested_version" ]
  then
    pkg_version_valid "$pkg_catalog_requested_version" || return 2
    pkg_catalog_version="$(
      . "$pkg_catalog_adapter" || exit 1
      pkg_repository_resolve_version "$pkg_catalog_repository" "$pkg_catalog_requested_version"
    )" || return 1
    [ "$pkg_catalog_version" = "$pkg_catalog_requested_version" ] || return 1
  else
    pkg_catalog_version="$(
      . "$pkg_catalog_adapter" || exit 1
      pkg_repository_resolve_version "$pkg_catalog_repository"
    )"
    pkg_catalog_resolve_status=$?
    if [ "$pkg_catalog_resolve_status" -ne 0 ]
    then
      pkg_catalog_known="$(_pkg_catalog_latest_known "$pkg_catalog_stream")" || pkg_catalog_known=
      if [ -n "$pkg_catalog_known" ]
      then
        pkg_catalog_name=${pkg_catalog_stream%/*}
        pkg_catalog_name=${pkg_catalog_name##*/}
        log warn pkg-catalog latest-discovery-unavailable \
          package "$pkg_catalog_name" \
          last_known_version "$pkg_catalog_known" \
          suggestion "pkg install $pkg_catalog_name@$pkg_catalog_known" \
          caveat "artifact availability not verified" || :
      fi
      return 1
    fi
  fi

  pkg_version_valid "$pkg_catalog_version" || return 1
  _pkg_catalog_assign "$pkg_catalog_output_version" "$pkg_catalog_version"
}

pkg_catalog_range_resolve()
{
  [ "$#" -eq 3 ] || return 2
  valid_shell_identifier "$1" || return 2

  pkg_catalog_output_range=$1
  pkg_catalog_root=$2
  pkg_catalog_concrete=$3

  [ -d "$pkg_catalog_root" ] && [ ! -L "$pkg_catalog_root" ] || return 1
  pkg_concrete_read pkg_catalog_package pkg_catalog_version pkg_catalog_osarch "$pkg_catalog_concrete" || return 1

  if [ -n "$pkg_catalog_osarch" ]
  then
    pkg_catalog_stream="$pkg_catalog_root/pkg/$pkg_catalog_package/$pkg_catalog_osarch"
  else
    pkg_catalog_stream="$pkg_catalog_root/pkg/$pkg_catalog_package/all"
  fi

  [ -d "$pkg_catalog_stream" ] && [ ! -L "$pkg_catalog_stream" ] || return 1

  pkg_catalog_repository="$pkg_catalog_stream/repository"
  [ -d "$pkg_catalog_repository" ] && [ ! -L "$pkg_catalog_repository" ] || return 1
  _pkg_catalog_repository_adapter "$pkg_catalog_repository" || return 1
  pkg_catalog_adapter=$pkg_catalog_repository_adapter

  pkg_catalog_lf='
'
  pkg_catalog_ranges=

  for pkg_catalog_entry in "$pkg_catalog_stream"/* "$pkg_catalog_stream"/.[!.]* "$pkg_catalog_stream"/..?*
  do
    [ -e "$pkg_catalog_entry" ] || [ -L "$pkg_catalog_entry" ] || continue
    pkg_catalog_name=${pkg_catalog_entry##*/}

    case "$pkg_catalog_name" in
      repository)
        [ -d "$pkg_catalog_entry" ] && [ ! -L "$pkg_catalog_entry" ] || return 1
        ;;
      n[0-9][0-9][0-9][0-9]=*)
        [ -d "$pkg_catalog_entry" ] && [ ! -L "$pkg_catalog_entry" ] || return 1
        pkg_catalog_anchor=${pkg_catalog_name#*=}
        pkg_version_valid "$pkg_catalog_anchor" || return 1
        if [ -n "$pkg_catalog_ranges" ]
        then
          pkg_catalog_ranges="$pkg_catalog_ranges$pkg_catalog_lf$pkg_catalog_name"
        else
          pkg_catalog_ranges=$pkg_catalog_name
        fi
        ;;
      *)
        return 1
        ;;
    esac
  done

  [ -n "$pkg_catalog_ranges" ] || return 1
  pkg_catalog_ranges="$(printf '%s\n' "$pkg_catalog_ranges" | LC_ALL=C command -p -- sort)" || return 1

  pkg_catalog_expected=1
  pkg_catalog_previous_anchor=
  pkg_catalog_reverse_ranges=

  while IFS= read -r pkg_catalog_name
  do
    pkg_catalog_prefix=${pkg_catalog_name%%=*}
    pkg_catalog_anchor=${pkg_catalog_name#*=}
    pkg_catalog_expected_prefix="$(printf 'n%04d' "$pkg_catalog_expected")" || return 1
    [ "$pkg_catalog_prefix" = "$pkg_catalog_expected_prefix" ] || return 1

    if [ -n "$pkg_catalog_previous_anchor" ]
    then
      pkg_catalog_order="$(_pkg_catalog_compare_versions "$pkg_catalog_adapter" "$pkg_catalog_repository" "$pkg_catalog_previous_anchor" "$pkg_catalog_anchor")" || return 1
      [ "$pkg_catalog_order" = -1 ] || return 1
    fi

    if [ -n "$pkg_catalog_reverse_ranges" ]
    then
      pkg_catalog_reverse_ranges="$pkg_catalog_name$pkg_catalog_lf$pkg_catalog_reverse_ranges"
    else
      pkg_catalog_reverse_ranges=$pkg_catalog_name
    fi

    pkg_catalog_previous_anchor=$pkg_catalog_anchor
    pkg_catalog_expected=$((pkg_catalog_expected + 1))
  done <<EOF_PKG_CATALOG_RANGES
$pkg_catalog_ranges
EOF_PKG_CATALOG_RANGES

  pkg_catalog_selected=
  while IFS= read -r pkg_catalog_name
  do
    pkg_catalog_anchor=${pkg_catalog_name#*=}
    pkg_catalog_order="$(_pkg_catalog_compare_versions "$pkg_catalog_adapter" "$pkg_catalog_repository" "$pkg_catalog_anchor" "$pkg_catalog_version")" || return 1
    case "$pkg_catalog_order" in
      -1|0)
        pkg_catalog_selected="$pkg_catalog_stream/$pkg_catalog_name"
        break
        ;;
      1) : ;;
      *) return 1 ;;
    esac
  done <<EOF_PKG_CATALOG_REVERSE_RANGES
$pkg_catalog_reverse_ranges
EOF_PKG_CATALOG_REVERSE_RANGES

  [ -n "$pkg_catalog_selected" ] || return 1
  _pkg_catalog_assign "$pkg_catalog_output_range" "$pkg_catalog_selected"
}
