loadsyslib "pkg/pkg-common"
loadsyslib "pkg/pkg-catalog"
if ! command -v pkg_provider_default_resolve >/dev/null 2>&1
then
  loadsyslib "pkg/pkg-provider"
fi
loadsyslib "pkg/facility/pkg-facility"

_pkg_facility_map_warn()
{
  [ "$#" -ge 1 ] || return 2
  log warn execution facility-map-version-order-unavailable operation pkg-facility-map reason "$1" || :
}

_pkg_facility_map_group_finish()
{
  [ "$#" -eq 2 ] || return 2
  pkg_facility_map_stage=$1
  pkg_facility_map_group=$2
  [ -s "$pkg_facility_map_group" ] || return 0

  pkg_facility_map_first_line="$(command -p -- sed -n '1p' "$pkg_facility_map_group")" || return 1
  IFS="$(printf '\t')" read -r \
    pkg_facility_map_facility \
    pkg_facility_map_compatibility \
    pkg_facility_map_class \
    pkg_facility_map_package \
    pkg_facility_map_latest_version \
    pkg_facility_map_latest_concrete \
    pkg_facility_map_repository <<EOF_PKG_FACILITY_MAP_FIRST
$pkg_facility_map_first_line
EOF_PKG_FACILITY_MAP_FIRST

  pkg_facility_map_order_valid=1
  while IFS="$(printf '\t')" read -r \
    pkg_facility_map_row_facility \
    pkg_facility_map_row_compatibility \
    pkg_facility_map_row_class \
    pkg_facility_map_row_package \
    pkg_facility_map_row_version \
    pkg_facility_map_row_concrete \
    pkg_facility_map_row_repository
  do
    pkg_facility_map_candidate_version=$pkg_facility_map_row_version
    pkg_facility_map_candidate_concrete=$pkg_facility_map_row_concrete
    [ "$pkg_facility_map_candidate_version" = "$pkg_facility_map_latest_version" ] && continue
    pkg_facility_map_comparison="$(pkg_catalog_installed_versions_compare \
      "$pkg_facility_map_row_repository" \
      "$pkg_facility_map_latest_version" \
      "$pkg_facility_map_candidate_version")" || pkg_facility_map_comparison=
    if [ -z "$pkg_facility_map_comparison" ]
    then
      while IFS="$(printf '\t')" read -r \
        pkg_facility_map_probe_facility \
        pkg_facility_map_probe_compatibility \
        pkg_facility_map_probe_class \
        pkg_facility_map_probe_package \
        pkg_facility_map_probe_version \
        pkg_facility_map_probe_concrete \
        pkg_facility_map_probe_repository
      do
        pkg_facility_map_comparison="$(pkg_catalog_installed_versions_compare \
          "$pkg_facility_map_probe_repository" \
          "$pkg_facility_map_latest_version" \
          "$pkg_facility_map_candidate_version")" && break
        pkg_facility_map_comparison=
      done < "$pkg_facility_map_group"
    fi
    [ -n "$pkg_facility_map_comparison" ] || {
      pkg_facility_map_order_valid=0
      break
    }
    case "$pkg_facility_map_comparison" in
      -1) pkg_facility_map_latest_version=$pkg_facility_map_candidate_version; pkg_facility_map_latest_concrete=$pkg_facility_map_candidate_concrete ;;
      0) pkg_facility_map_order_valid=0; break ;;
      1) : ;;
      *) pkg_facility_map_order_valid=0; break ;;
    esac
  done < "$pkg_facility_map_group"

  pkg_facility_map_dir="$pkg_facility_map_stage/$pkg_facility_map_facility/$pkg_facility_map_compatibility/$pkg_facility_map_class"
  if [ "$pkg_facility_map_order_valid" -eq 1 ]
  then
    command -p -- ln -s \
      "$pkg_facility_map_package@$pkg_facility_map_latest_version" \
      "$pkg_facility_map_dir/$pkg_facility_map_package@latest" || return 1
  else
    _pkg_facility_map_warn version-order-unavailable
  fi

  # `default` mirrors the authoritative system selection when it resolves to
  # one member in this exact compatibility/class group.
  if pkg_provider_default_resolve "$pkg_facility_map_facility" > "$pkg_facility_map_stage/.default-resolution" 2>/dev/null
  then
    pkg_facility_map_default_concrete="$(command -p -- cat -- "$pkg_facility_map_stage/.default-resolution")" || return 1
    if command -p -- awk -F "$(printf '\t')" -v selected="$pkg_facility_map_default_concrete" '$6 == selected { found=1 } END { exit !found }' "$pkg_facility_map_group"
    then
      command -p -- ln -s \
        "../../../../pkg/$pkg_facility_map_default_concrete" \
        "$pkg_facility_map_dir/default" || return 1
    fi
  fi
  command -p -- rm -f -- "$pkg_facility_map_stage/.default-resolution"
}

pkg_facility_map_reconcile()
(
  [ "$#" -eq 0 ] || return 2
  [ -n "${m_ROOT-}" ] && [ -n "${m_PKG_DIR-}" ] || return 1
  valid_dir "$m_ROOT" && valid_dir "$m_PKG_DIR" || return 1

  pkg_facility_map_root="$m_ROOT/facility"
  pkg_facility_map_lock="$m_ROOT/.facility-map.lock"
  pkg_facility_map_stage="$m_ROOT/.facility-map-stage-$$"
  pkg_facility_map_backup="$m_ROOT/.facility-map-backup-$$"
  pkg_facility_map_candidates="$m_ROOT/.facility-map-candidates-$$"
  pkg_facility_map_sorted="$m_ROOT/.facility-map-sorted-$$"
  pkg_facility_map_group="$m_ROOT/.facility-map-group-$$"

  command -p -- mkdir "$pkg_facility_map_lock" || return 1
  trap 'command -p -- rm -f -- "$pkg_facility_map_candidates" "$pkg_facility_map_sorted" "$pkg_facility_map_group"; command -p -- rm -rf -- "$pkg_facility_map_stage"; if [ -e "$pkg_facility_map_backup" ] || [ -L "$pkg_facility_map_backup" ]; then if [ ! -e "$pkg_facility_map_root" ] && [ ! -L "$pkg_facility_map_root" ]; then command -p -- mv -- "$pkg_facility_map_backup" "$pkg_facility_map_root" || :; else command -p -- rm -rf -- "$pkg_facility_map_backup" || :; fi; fi; rmdir "$pkg_facility_map_lock" 2>/dev/null || :' 0

  [ ! -e "$pkg_facility_map_stage" ] && [ ! -L "$pkg_facility_map_stage" ] || return 1
  [ ! -e "$pkg_facility_map_backup" ] && [ ! -L "$pkg_facility_map_backup" ] || return 1
  [ ! -e "$pkg_facility_map_candidates" ] && [ ! -L "$pkg_facility_map_candidates" ] || return 1
  [ ! -e "$pkg_facility_map_sorted" ] && [ ! -L "$pkg_facility_map_sorted" ] || return 1
  [ ! -e "$pkg_facility_map_group" ] && [ ! -L "$pkg_facility_map_group" ] || return 1
  if [ -e "$pkg_facility_map_root" ] || [ -L "$pkg_facility_map_root" ]
  then
    [ -d "$pkg_facility_map_root" ] && [ ! -L "$pkg_facility_map_root" ] || return 1
  fi

  command -p -- mkdir "$pkg_facility_map_stage" || return 1
  : > "$pkg_facility_map_candidates" || return 1
  pkg_facility_map_tab="$(printf '\t')"

  for pkg_facility_map_concrete_dir in "$m_PKG_DIR"/*
  do
    [ -d "$pkg_facility_map_concrete_dir" ] && [ ! -L "$pkg_facility_map_concrete_dir" ] || continue
    pkg_facility_map_concrete=${pkg_facility_map_concrete_dir##*/}
    pkg_concrete_read \
      pkg_facility_map_package \
      pkg_facility_map_version \
      pkg_facility_map_osarch \
      "$pkg_facility_map_concrete" || continue
    pkg_facility_map_facility_file="$pkg_facility_map_concrete_dir/facility"
    [ -f "$pkg_facility_map_facility_file" ] && [ ! -L "$pkg_facility_map_facility_file" ] || continue
    _pkg_facility_file_validate "$pkg_facility_map_facility_file" || return 1
    pkg_facility_map_class=${pkg_facility_map_osarch:-all}

    while IFS= read -r pkg_facility_map_line
    do
      _pkg_facility_line_parse "$pkg_facility_map_line" || return 1
      pkg_facility_map_facility_dir="$pkg_facility_map_stage/$pkg_facility_name/$pkg_facility_compatibility/$pkg_facility_map_class"
      command -p -- mkdir -p -- "$pkg_facility_map_facility_dir" || return 1
      pkg_facility_map_link_name="$pkg_facility_map_package@$pkg_facility_map_version"
      pkg_facility_map_target="../../../../pkg/$pkg_facility_map_concrete"
      [ ! -e "$pkg_facility_map_facility_dir/$pkg_facility_map_link_name" ] &&
        [ ! -L "$pkg_facility_map_facility_dir/$pkg_facility_map_link_name" ] || return 1
      command -p -- ln -s "$pkg_facility_map_target" "$pkg_facility_map_facility_dir/$pkg_facility_map_link_name" || return 1
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$pkg_facility_name" \
        "$pkg_facility_compatibility" \
        "$pkg_facility_map_class" \
        "$pkg_facility_map_package" \
        "$pkg_facility_map_version" \
        "$pkg_facility_map_concrete" \
        "$pkg_facility_map_concrete_dir/repository" >> "$pkg_facility_map_candidates" || return 1
    done < "$pkg_facility_map_facility_file"
  done

  LC_ALL=C command -p -- sort -t "$pkg_facility_map_tab" \
    -k1,1 -k2,2 -k3,3 -k4,4 -k5,5 \
    "$pkg_facility_map_candidates" > "$pkg_facility_map_sorted" || return 1

  pkg_facility_map_previous_key=
  : > "$pkg_facility_map_group" || return 1
  while IFS="$pkg_facility_map_tab" read -r \
    pkg_facility_map_facility \
    pkg_facility_map_compatibility \
    pkg_facility_map_class \
    pkg_facility_map_package \
    pkg_facility_map_version \
    pkg_facility_map_concrete \
    pkg_facility_map_repository
  do
    pkg_facility_map_key="$pkg_facility_map_facility$pkg_facility_map_tab$pkg_facility_map_compatibility$pkg_facility_map_tab$pkg_facility_map_class$pkg_facility_map_tab$pkg_facility_map_package"
    if [ -n "$pkg_facility_map_previous_key" ] && [ "$pkg_facility_map_key" != "$pkg_facility_map_previous_key" ]
    then
      pkg_facility_map_pending_facility=$pkg_facility_map_facility
      pkg_facility_map_pending_compatibility=$pkg_facility_map_compatibility
      pkg_facility_map_pending_class=$pkg_facility_map_class
      pkg_facility_map_pending_package=$pkg_facility_map_package
      pkg_facility_map_pending_version=$pkg_facility_map_version
      pkg_facility_map_pending_concrete=$pkg_facility_map_concrete
      pkg_facility_map_pending_repository=$pkg_facility_map_repository
      _pkg_facility_map_group_finish "$pkg_facility_map_stage" "$pkg_facility_map_group" || return 1
      : > "$pkg_facility_map_group" || return 1
      pkg_facility_map_facility=$pkg_facility_map_pending_facility
      pkg_facility_map_compatibility=$pkg_facility_map_pending_compatibility
      pkg_facility_map_class=$pkg_facility_map_pending_class
      pkg_facility_map_package=$pkg_facility_map_pending_package
      pkg_facility_map_version=$pkg_facility_map_pending_version
      pkg_facility_map_concrete=$pkg_facility_map_pending_concrete
      pkg_facility_map_repository=$pkg_facility_map_pending_repository
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$pkg_facility_map_facility" \
      "$pkg_facility_map_compatibility" \
      "$pkg_facility_map_class" \
      "$pkg_facility_map_package" \
      "$pkg_facility_map_version" \
      "$pkg_facility_map_concrete" \
      "$pkg_facility_map_repository" >> "$pkg_facility_map_group" || return 1
    pkg_facility_map_previous_key=$pkg_facility_map_key
  done < "$pkg_facility_map_sorted"
  _pkg_facility_map_group_finish "$pkg_facility_map_stage" "$pkg_facility_map_group" || return 1

  command -p -- rm -f -- "$pkg_facility_map_candidates" "$pkg_facility_map_sorted" "$pkg_facility_map_group" || return 1
  if [ -e "$pkg_facility_map_root" ] || [ -L "$pkg_facility_map_root" ]
  then
    command -p -- mv -- "$pkg_facility_map_root" "$pkg_facility_map_backup" || return 1
  fi
  if ! command -p -- mv -- "$pkg_facility_map_stage" "$pkg_facility_map_root"
  then
    if [ -e "$pkg_facility_map_backup" ] || [ -L "$pkg_facility_map_backup" ]
    then
      command -p -- mv -- "$pkg_facility_map_backup" "$pkg_facility_map_root" || :
    fi
    return 1
  fi
  if [ -e "$pkg_facility_map_backup" ] || [ -L "$pkg_facility_map_backup" ]
  then
    command -p -- rm -rf -- "$pkg_facility_map_backup" || return 1
  fi
  return 0
)
