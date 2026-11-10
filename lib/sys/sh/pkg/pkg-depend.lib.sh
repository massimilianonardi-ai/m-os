loadsyslib "pkg/pkg-common"
loadsyslib "pkg/pkg-catalog"
loadsyslib "pkg/pkg-default"
loadsyslib "pkg/pkg-provider"
loadsyslib "pkg/facility/pkg-facility"
loadsyslib "pkg/facility/pkg-dependency"

_pkg_depend_concrete_make()
{
  [ "$#" -eq 3 ] || return 2
  pkg_depend_concrete="$1@$2"
  [ -z "$3" ] || pkg_depend_concrete="$pkg_depend_concrete!$3"
  pkg_concrete_read pkg_depend_check_pkg pkg_depend_check_version pkg_depend_check_osarch "$pkg_depend_concrete"
}

_pkg_depend_class_present()
{
  [ "$#" -eq 2 ] || return 2
  pkg_depend_class_pkg=$1
  pkg_depend_class_osarch=$2

  [ -d "$m_PKG_DIR" ] && [ ! -L "$m_PKG_DIR" ] || return 1

  for pkg_depend_class_path in "$m_PKG_DIR/$pkg_depend_class_pkg@"*
  do
    [ -e "$pkg_depend_class_path" ] || [ -L "$pkg_depend_class_path" ] || continue
    [ -d "$pkg_depend_class_path" ] && [ ! -L "$pkg_depend_class_path" ] || continue
    pkg_depend_class_name=${pkg_depend_class_path##*/}

    pkg_concrete_read pkg_depend_class_name_pkg pkg_depend_class_name_version pkg_depend_class_name_osarch "$pkg_depend_class_name" || continue
    [ "$pkg_depend_class_name_pkg" = "$pkg_depend_class_pkg" ] || continue
    [ "$pkg_depend_class_name_osarch" = "$pkg_depend_class_osarch" ] || continue
    return 0
  done

  return 1
}

_pkg_depend_request_resolve()
{
  [ "$#" -eq 4 ] || return 2
  pkg_depend_catalog=$1
  pkg_depend_request=$2
  pkg_depend_default_target=$3
  pkg_depend_request_mode=$4

  case "$pkg_depend_request_mode" in
    request)
      pkg_catalog_request_resolve pkg_depend_concrete pkg_depend_target "$pkg_depend_catalog" "$pkg_depend_request" "$pkg_depend_default_target"
      return
      ;;
    exact)
      pkg_concrete_read pkg_depend_pkg pkg_depend_version pkg_depend_requested_osarch "$pkg_depend_request" || return 3

      # The concrete identity may be osarch-independent (catalog "all").
      # Its dependency-consumer target then comes from the caller's exact
      # root context, not from the local host or an identity suffix.
      pkg_depend_target=$pkg_depend_default_target
      pkg_osarch_valid "$pkg_depend_target" || return 4

      pkg_catalog_stream_resolve pkg_depend_stream pkg_depend_identity_osarch "$pkg_depend_catalog" "$pkg_depend_pkg" "$pkg_depend_target" || return 5
      [ "$pkg_depend_requested_osarch" = "$pkg_depend_identity_osarch" ] || return 6

      pkg_depend_concrete=$pkg_depend_request
      if [ -e "$m_PKG_DIR/$pkg_depend_concrete" ] || [ -L "$m_PKG_DIR/$pkg_depend_concrete" ]
      then
        [ -d "$m_PKG_DIR/$pkg_depend_concrete" ] && [ ! -L "$m_PKG_DIR/$pkg_depend_concrete" ] || return 7
      else
        pkg_catalog_range_resolve pkg_depend_range "$pkg_depend_catalog" "$pkg_depend_concrete" || return 8
      fi
      return 0
      ;;
    selector)
      :
      ;;
    *)
      return 2
      ;;
  esac

  pkg_request_read pkg_depend_pkg pkg_depend_requested_version pkg_depend_requested_osarch "$pkg_depend_request" || return 2

  if [ -n "$pkg_depend_requested_osarch" ]
  then
    pkg_depend_target=$pkg_depend_requested_osarch
  else
    pkg_depend_target=$pkg_depend_default_target
  fi
  pkg_osarch_valid "$pkg_depend_target" || return 1

  pkg_catalog_stream_resolve pkg_depend_stream pkg_depend_identity_osarch "$pkg_depend_catalog" "$pkg_depend_pkg" "$pkg_depend_target" || return 1

  if [ -n "$pkg_depend_requested_version" ]
  then
    _pkg_depend_concrete_make "$pkg_depend_pkg" "$pkg_depend_requested_version" "$pkg_depend_identity_osarch" || return 1

    if [ -e "$m_PKG_DIR/$pkg_depend_concrete" ] || [ -L "$m_PKG_DIR/$pkg_depend_concrete" ]
    then
      [ -d "$m_PKG_DIR/$pkg_depend_concrete" ] && [ ! -L "$m_PKG_DIR/$pkg_depend_concrete" ] || return 1
      return
    fi

    pkg_catalog_version_resolve pkg_depend_version "$pkg_depend_stream" "$pkg_depend_requested_version" || return 1
  else
    if [ -n "$pkg_depend_identity_osarch" ]
    then
      pkg_depend_class="$pkg_depend_pkg!$pkg_depend_identity_osarch"
    else
      pkg_depend_class=$pkg_depend_pkg
    fi

    pkg_depend_current="$(pkg_default "$pkg_depend_class" 2>/dev/null)"
    if [ "$?" -eq 0 ]
    then
      if pkg_concrete_read pkg_depend_current_pkg pkg_depend_current_version pkg_depend_current_osarch "$pkg_depend_current" &&
         [ "$pkg_depend_current_pkg" = "$pkg_depend_pkg" ] &&
         [ "$pkg_depend_current_osarch" = "$pkg_depend_identity_osarch" ]
      then
        pkg_depend_concrete=$pkg_depend_current
        return
      fi
    elif _pkg_depend_class_present "$pkg_depend_pkg" "$pkg_depend_identity_osarch"
    then
      return 1
    fi

    pkg_catalog_version_resolve pkg_depend_version "$pkg_depend_stream" || return 1
  fi

  _pkg_depend_concrete_make "$pkg_depend_pkg" "$pkg_depend_version" "$pkg_depend_identity_osarch" || return 1
  pkg_catalog_range_resolve pkg_depend_range "$pkg_depend_catalog" "$pkg_depend_concrete" || return 1
}

_pkg_depend_context_add()
{
  [ "$#" -eq 2 ] || return 2
  pkg_depend_context_record="$1|$2"

  if [ -n "$pkg_depend_contexts" ]
  then
    while IFS= read -r pkg_depend_context_existing
    do
      [ "$pkg_depend_context_existing" != "$pkg_depend_context_record" ] || return 0
    done <<EOF_PKG_DEPEND_CONTEXTS
$pkg_depend_contexts
EOF_PKG_DEPEND_CONTEXTS
    pkg_depend_contexts="$pkg_depend_contexts
$pkg_depend_context_record"
  else
    pkg_depend_contexts=$pkg_depend_context_record
  fi
}

_pkg_depend_candidate_add()
{
  [ "$#" -eq 1 ] || return 2

  if [ -n "$pkg_depend_candidates" ]
  then
    while IFS= read -r pkg_depend_candidate_existing
    do
      [ "$pkg_depend_candidate_existing" != "$1" ] || return 0
    done <<EOF_PKG_DEPEND_CANDIDATES
$pkg_depend_candidates
EOF_PKG_DEPEND_CANDIDATES
    pkg_depend_candidates="$pkg_depend_candidates
$1"
  else
    pkg_depend_candidates=$1
  fi
}

_pkg_depend_dependency_source()
{
  [ "$#" -eq 2 ] || return 2
  pkg_depend_catalog=$1
  pkg_depend_source_concrete=$2
  pkg_depend_dependency_source=

  if [ -e "$m_PKG_DIR/$pkg_depend_source_concrete" ] || [ -L "$m_PKG_DIR/$pkg_depend_source_concrete" ]
  then
    [ -d "$m_PKG_DIR/$pkg_depend_source_concrete" ] && [ ! -L "$m_PKG_DIR/$pkg_depend_source_concrete" ] || return 1
    if [ -e "$m_PKG_DIR/$pkg_depend_source_concrete/dependency" ] || [ -L "$m_PKG_DIR/$pkg_depend_source_concrete/dependency" ]
    then
      pkg_depend_dependency_source="$m_PKG_DIR/$pkg_depend_source_concrete/dependency"
    fi
  else
    pkg_catalog_range_resolve pkg_depend_source_range "$pkg_depend_catalog" "$pkg_depend_source_concrete" || return 1
    if [ -e "$pkg_depend_source_range/dependency" ] || [ -L "$pkg_depend_source_range/dependency" ]
    then
      pkg_depend_dependency_source="$pkg_depend_source_range/dependency"
    fi
  fi

  [ -z "$pkg_depend_dependency_source" ] || pkg_dependency_validate "$pkg_depend_dependency_source"
}

_pkg_depend_concrete_compatibility()
{
  [ "$#" -eq 3 ] || return 2
  pkg_depend_catalog=$1
  pkg_depend_provider_concrete=$2
  pkg_depend_required_facility=$3

  if [ -e "$m_PKG_DIR/$pkg_depend_provider_concrete" ] || [ -L "$m_PKG_DIR/$pkg_depend_provider_concrete" ]
  then
    [ -d "$m_PKG_DIR/$pkg_depend_provider_concrete" ] && [ ! -L "$m_PKG_DIR/$pkg_depend_provider_concrete" ] || return 1
    pkg_depend_provider_definition="$m_PKG_DIR/$pkg_depend_provider_concrete"
  else
    pkg_catalog_range_resolve pkg_depend_provider_definition "$pkg_depend_catalog" "$pkg_depend_provider_concrete" || return 1
  fi

  pkg_facility_compatibility_read pkg_depend_provider_compatibility "$pkg_depend_provider_definition" "$pkg_depend_required_facility"
}

_pkg_depend_candidate_compatible()
{
  [ "$#" -eq 5 ] || return 2
  pkg_depend_catalog=$1
  pkg_depend_candidate=$2
  pkg_depend_candidate_target=$3
  pkg_depend_candidate_facility=$4
  pkg_depend_candidate_constraints=$5

  pkg_concrete_read pkg_depend_candidate_pkg pkg_depend_candidate_version pkg_depend_candidate_osarch "$pkg_depend_candidate" || return 1
  if [ -n "$pkg_depend_candidate_osarch" ] && [ "$pkg_depend_candidate_osarch" != "$pkg_depend_candidate_target" ]
  then
    return 3
  fi

  _pkg_depend_concrete_compatibility "$pkg_depend_catalog" "$pkg_depend_candidate" "$pkg_depend_candidate_facility"
  pkg_depend_candidate_status=$?
  case "$pkg_depend_candidate_status" in
    0) : ;;
    3) return 3 ;;
    *) return 1 ;;
  esac

  pkg_dependency_satisfied "$pkg_depend_provider_compatibility" "$pkg_depend_candidate_constraints" && return 0
  return 4
}

_pkg_depend_candidate_choose()
{
  [ "$#" -eq 1 ] || return 2
  pkg_depend_candidate_target=$1
  [ -n "$pkg_depend_candidates" ] || return 1

  pkg_depend_candidate_count=0
  pkg_depend_candidate_package=
  pkg_depend_candidate_one_package=1
  pkg_depend_selected=

  while IFS= read -r pkg_depend_candidate
  do
    [ -n "$pkg_depend_candidate" ] || continue
    pkg_concrete_read pkg_depend_candidate_pkg pkg_depend_candidate_version pkg_depend_candidate_osarch "$pkg_depend_candidate" || return 1
    pkg_depend_candidate_count=$((pkg_depend_candidate_count + 1))
    pkg_depend_selected=$pkg_depend_candidate

    if [ -z "$pkg_depend_candidate_package" ]
    then
      pkg_depend_candidate_package=$pkg_depend_candidate_pkg
    elif [ "$pkg_depend_candidate_package" != "$pkg_depend_candidate_pkg" ]
    then
      pkg_depend_candidate_one_package=0
    fi
  done <<EOF_PKG_DEPEND_CHOOSE
$pkg_depend_candidates
EOF_PKG_DEPEND_CHOOSE

  [ "$pkg_depend_candidate_count" -gt 0 ] || return 1
  [ "$pkg_depend_candidate_count" -gt 1 ] || return 0
  [ "$pkg_depend_candidate_one_package" -eq 1 ] || return 4

  pkg_depend_candidate_default="$(pkg_provider_selector_resolve "$pkg_depend_candidate_package" "$pkg_depend_candidate_target" 2>/dev/null)" || return 4

  while IFS= read -r pkg_depend_candidate
  do
    if [ "$pkg_depend_candidate" = "$pkg_depend_candidate_default" ]
    then
      pkg_depend_selected=$pkg_depend_candidate_default
      return 0
    fi
  done <<EOF_PKG_DEPEND_DEFAULT
$pkg_depend_candidates
EOF_PKG_DEPEND_DEFAULT

  return 4
}

_pkg_depend_planned_candidates()
{
  [ "$#" -eq 4 ] || return 2
  pkg_depend_catalog=$1
  pkg_depend_target=$2
  pkg_depend_facility=$3
  pkg_depend_constraints=$4
  pkg_depend_candidates=

  [ -z "$pkg_depend_contexts" ] && return 0

  while IFS='|' read -r pkg_depend_context_concrete pkg_depend_context_target pkg_depend_context_extra
  do
    [ -z "$pkg_depend_context_extra" ] || return 1
    [ "$pkg_depend_context_target" = "$pkg_depend_target" ] || continue
    _pkg_depend_candidate_compatible "$pkg_depend_catalog" "$pkg_depend_context_concrete" "$pkg_depend_target" "$pkg_depend_facility" "$pkg_depend_constraints"
    pkg_depend_candidate_status=$?
    case "$pkg_depend_candidate_status" in
      0) _pkg_depend_candidate_add "$pkg_depend_context_concrete" || return 1 ;;
      3|4) : ;;
      *) return 1 ;;
    esac
  done <<EOF_PKG_DEPEND_PLANNED
$pkg_depend_contexts
EOF_PKG_DEPEND_PLANNED
}

_pkg_depend_installed_candidates()
{
  [ "$#" -eq 4 ] || return 2
  pkg_depend_catalog=$1
  pkg_depend_target=$2
  pkg_depend_facility=$3
  pkg_depend_constraints=$4
  pkg_depend_candidates=

  if [ ! -e "$m_PKG_DIR" ] && [ ! -L "$m_PKG_DIR" ]
  then
    return 0
  fi
  [ -d "$m_PKG_DIR" ] && [ ! -L "$m_PKG_DIR" ] || return 1

  for pkg_depend_installed_path in "$m_PKG_DIR"/*
  do
    [ -e "$pkg_depend_installed_path" ] || [ -L "$pkg_depend_installed_path" ] || continue
    [ -d "$pkg_depend_installed_path" ] && [ ! -L "$pkg_depend_installed_path" ] || continue
    pkg_depend_installed=${pkg_depend_installed_path##*/}

    _pkg_depend_candidate_compatible "$pkg_depend_catalog" "$pkg_depend_installed" "$pkg_depend_target" "$pkg_depend_facility" "$pkg_depend_constraints"
    pkg_depend_candidate_status=$?
    case "$pkg_depend_candidate_status" in
      0) _pkg_depend_candidate_add "$pkg_depend_installed" || return 1 ;;
      3|4) : ;;
      *) return 1 ;;
    esac
  done
}

_pkg_depend_catalog_package_candidate()
(
  [ "$#" -eq 5 ] || return 2
  pkg_depend_catalog=$1
  pkg_depend_package=$2
  pkg_depend_target=$3
  pkg_depend_facility=$4
  pkg_depend_constraints=$5

  pkg_catalog_stream_resolve pkg_depend_stream pkg_depend_identity_osarch "$pkg_depend_catalog" "$pkg_depend_package" "$pkg_depend_target" || return 3

  pkg_depend_fallback_version=
  for pkg_depend_range in "$pkg_depend_stream"/n[0-9][0-9][0-9][0-9]=*
  do
    [ -e "$pkg_depend_range" ] || [ -L "$pkg_depend_range" ] || continue
    [ -d "$pkg_depend_range" ] && [ ! -L "$pkg_depend_range" ] || return 1

    pkg_facility_compatibility_read pkg_depend_compatibility "$pkg_depend_range" "$pkg_depend_facility"
    pkg_depend_compatibility_status=$?
    case "$pkg_depend_compatibility_status" in
      0)
        if pkg_dependency_satisfied "$pkg_depend_compatibility" "$pkg_depend_constraints"
        then
          pkg_depend_range_name=${pkg_depend_range##*/}
          pkg_depend_fallback_version=${pkg_depend_range_name#*=}
        fi
        ;;
      3) : ;;
      *) return 1 ;;
    esac
  done

  [ -n "$pkg_depend_fallback_version" ] || return 3

  if pkg_catalog_version_resolve pkg_depend_version "$pkg_depend_stream"
  then
    _pkg_depend_concrete_make "$pkg_depend_package" "$pkg_depend_version" "$pkg_depend_identity_osarch" || return 1
    pkg_catalog_range_resolve pkg_depend_latest_range "$pkg_depend_catalog" "$pkg_depend_concrete" || return 1
    pkg_facility_compatibility_read pkg_depend_compatibility "$pkg_depend_latest_range" "$pkg_depend_facility"
    pkg_depend_compatibility_status=$?
    case "$pkg_depend_compatibility_status" in
      0)
        if pkg_dependency_satisfied "$pkg_depend_compatibility" "$pkg_depend_constraints"
        then
          printf -- '%s\n' "$pkg_depend_concrete"
          return 0
        fi
        ;;
      3) : ;;
      *) return 1 ;;
    esac
  fi

  pkg_catalog_version_resolve pkg_depend_version "$pkg_depend_stream" "$pkg_depend_fallback_version" || return 1
  _pkg_depend_concrete_make "$pkg_depend_package" "$pkg_depend_version" "$pkg_depend_identity_osarch" || return 1
  printf -- '%s\n' "$pkg_depend_concrete"
)

_pkg_depend_catalog_candidates()
{
  [ "$#" -eq 4 ] || return 2
  pkg_depend_catalog=$1
  pkg_depend_target=$2
  pkg_depend_facility=$3
  pkg_depend_constraints=$4
  pkg_depend_candidates=

  [ -d "$pkg_depend_catalog/pkg" ] && [ ! -L "$pkg_depend_catalog/pkg" ] || return 1

  for pkg_depend_package_path in "$pkg_depend_catalog/pkg"/*
  do
    [ -e "$pkg_depend_package_path" ] || [ -L "$pkg_depend_package_path" ] || continue
    [ -d "$pkg_depend_package_path" ] && [ ! -L "$pkg_depend_package_path" ] || return 1
    pkg_depend_package=${pkg_depend_package_path##*/}
    pkg_name_valid "$pkg_depend_package" || return 1

    pkg_depend_candidate="$(_pkg_depend_catalog_package_candidate "$pkg_depend_catalog" "$pkg_depend_package" "$pkg_depend_target" "$pkg_depend_facility" "$pkg_depend_constraints")"
    pkg_depend_candidate_status=$?
    case "$pkg_depend_candidate_status" in
      0) _pkg_depend_candidate_add "$pkg_depend_candidate" || return 1 ;;
      3) : ;;
      *) return 1 ;;
    esac
  done
}

_pkg_depend_ambiguity_log()
{
  [ "$#" -eq 3 ] || return 2
  pkg_depend_ambiguity_facility=$1
  pkg_depend_ambiguity_constraints=$2
  pkg_depend_ambiguity_target=$3
  pkg_depend_ambiguity_providers=

  while IFS= read -r pkg_depend_ambiguity_candidate
  do
    [ -n "$pkg_depend_ambiguity_candidate" ] || continue
    if [ -n "$pkg_depend_ambiguity_providers" ]
    then
      pkg_depend_ambiguity_providers="$pkg_depend_ambiguity_providers $pkg_depend_ambiguity_candidate"
    else
      pkg_depend_ambiguity_providers=$pkg_depend_ambiguity_candidate
    fi
  done <<EOF_PKG_DEPEND_AMBIGUITY
$pkg_depend_candidates
EOF_PKG_DEPEND_AMBIGUITY

  log error execution execution-failed operation pkg-depend \
    reason provider-ambiguous \
    facility "$pkg_depend_ambiguity_facility" \
    constraints "$pkg_depend_ambiguity_constraints" \
    target "$pkg_depend_ambiguity_target" \
    providers "$pkg_depend_ambiguity_providers"
}

_pkg_depend_candidate_choose_report()
{
  [ "$#" -eq 3 ] || return 2
  pkg_depend_choose_target=$1
  pkg_depend_choose_facility=$2
  pkg_depend_choose_constraints=$3

  _pkg_depend_candidate_choose "$pkg_depend_choose_target"
  pkg_depend_choose_status=$?
  case "$pkg_depend_choose_status" in
    0) return 0 ;;
    4)
      _pkg_depend_ambiguity_log \
        "$pkg_depend_choose_facility" \
        "$pkg_depend_choose_constraints" \
        "$pkg_depend_choose_target" || :
      return 4
      ;;
    *) return "$pkg_depend_choose_status" ;;
  esac
}

_pkg_depend_provider_resolve()
{
  [ "$#" -eq 5 ] || return 2
  pkg_depend_catalog=$1
  pkg_depend_selector=$2
  pkg_depend_facility=$3
  pkg_depend_constraints=$4
  pkg_depend_target=$5
  pkg_depend_selected=

  if [ -n "$pkg_depend_selector" ]
  then
    _pkg_depend_request_resolve "$pkg_depend_catalog" "$pkg_depend_selector" "$pkg_depend_target" selector || return 1
    pkg_depend_selected=$pkg_depend_concrete
    _pkg_depend_candidate_compatible "$pkg_depend_catalog" "$pkg_depend_selected" "$pkg_depend_target" "$pkg_depend_facility" "$pkg_depend_constraints" || return 1
    return 0
  fi

  _pkg_depend_planned_candidates "$pkg_depend_catalog" "$pkg_depend_target" "$pkg_depend_facility" "$pkg_depend_constraints" || return 1
  if [ -n "$pkg_depend_candidates" ]
  then
    _pkg_depend_candidate_choose_report "$pkg_depend_target" "$pkg_depend_facility" "$pkg_depend_constraints" || return $?
    return 0
  fi

  _pkg_depend_installed_candidates "$pkg_depend_catalog" "$pkg_depend_target" "$pkg_depend_facility" "$pkg_depend_constraints" || return 1
  if [ -n "$pkg_depend_candidates" ]
  then
    _pkg_depend_candidate_choose_report "$pkg_depend_target" "$pkg_depend_facility" "$pkg_depend_constraints" || return $?
    return 0
  fi

  _pkg_depend_catalog_candidates "$pkg_depend_catalog" "$pkg_depend_target" "$pkg_depend_facility" "$pkg_depend_constraints" || return 1
  _pkg_depend_candidate_choose_report "$pkg_depend_target" "$pkg_depend_facility" "$pkg_depend_constraints"
}

_pkg_depend_contexts_rebuild()
{
  pkg_depend_contexts=$pkg_depend_roots

  if [ -n "$pkg_depend_selections" ]
  then
    while IFS='|' read -r pkg_depend_selection_key pkg_depend_selection_concrete pkg_depend_selection_target pkg_depend_selection_extra
    do
      [ -z "$pkg_depend_selection_extra" ] || return 1
      _pkg_depend_context_add "$pkg_depend_selection_concrete" "$pkg_depend_selection_target" || return 1
    done <<EOF_PKG_DEPEND_SELECTION_CONTEXTS
$pkg_depend_selections
EOF_PKG_DEPEND_SELECTION_CONTEXTS
  fi
}

_pkg_depend_requirements_build()
{
  [ "$#" -eq 1 ] || return 2
  pkg_depend_catalog=$1
  pkg_depend_requirements=
  pkg_depend_keys=

  [ -z "$pkg_depend_contexts" ] && return 0

  while IFS='|' read -r pkg_depend_consumer_concrete pkg_depend_consumer_target pkg_depend_context_extra
  do
    [ -z "$pkg_depend_context_extra" ] || return 1
    pkg_concrete_read pkg_depend_consumer_pkg pkg_depend_consumer_version pkg_depend_consumer_osarch "$pkg_depend_consumer_concrete" || return 1
    _pkg_depend_dependency_source "$pkg_depend_catalog" "$pkg_depend_consumer_concrete" || return 1
    [ -n "$pkg_depend_dependency_source" ] || continue

    while IFS= read -r pkg_depend_dependency_line
    do
      pkg_dependency_read pkg_depend_facility pkg_depend_constraints "$pkg_depend_dependency_line" || return 1

      pkg_depend_selector="$(pkg_provider_effective_selector "$pkg_depend_consumer_pkg" "$pkg_depend_facility" 2>/dev/null)"
      pkg_depend_selector_status=$?
      case "$pkg_depend_selector_status" in
        0) pkg_depend_key="S^$pkg_depend_selector^$pkg_depend_facility^$pkg_depend_consumer_target" ;;
        1) pkg_depend_selector=; pkg_depend_key="I^^$pkg_depend_facility^$pkg_depend_consumer_target" ;;
        *) return 1 ;;
      esac

      pkg_depend_requirement="$pkg_depend_consumer_concrete|$pkg_depend_consumer_target|$pkg_depend_consumer_pkg|$pkg_depend_facility|$pkg_depend_constraints|$pkg_depend_selector|$pkg_depend_key"
      if [ -n "$pkg_depend_requirements" ]
      then
        pkg_depend_requirements="$pkg_depend_requirements
$pkg_depend_requirement"
      else
        pkg_depend_requirements=$pkg_depend_requirement
      fi

      if [ -n "$pkg_depend_keys" ]
      then
        pkg_depend_keys="$pkg_depend_keys
$pkg_depend_key"
      else
        pkg_depend_keys=$pkg_depend_key
      fi
    done < "$pkg_depend_dependency_source"
  done <<EOF_PKG_DEPEND_CONTEXT_SCAN
$pkg_depend_contexts
EOF_PKG_DEPEND_CONTEXT_SCAN

  [ -z "$pkg_depend_keys" ] || pkg_depend_keys="$(printf '%s\n' "$pkg_depend_keys" | LC_ALL=C command -p -- sort -u)" || return 1
}

_pkg_depend_selections_resolve()
{
  [ "$#" -eq 1 ] || return 2
  pkg_depend_catalog=$1
  pkg_depend_new_selections=

  [ -z "$pkg_depend_keys" ] && return 0

  while IFS= read -r pkg_depend_key
  do
    pkg_depend_key_selector=
    pkg_depend_key_facility=
    pkg_depend_key_target=
    pkg_depend_key_constraints=

    while IFS='|' read -r pkg_depend_consumer_concrete pkg_depend_consumer_target pkg_depend_consumer_pkg pkg_depend_facility pkg_depend_constraints pkg_depend_selector pkg_depend_requirement_key pkg_depend_requirement_extra
    do
      [ -z "$pkg_depend_requirement_extra" ] || return 1
      [ "$pkg_depend_requirement_key" = "$pkg_depend_key" ] || continue

      pkg_depend_key_selector=$pkg_depend_selector
      pkg_depend_key_facility=$pkg_depend_facility
      pkg_depend_key_target=$pkg_depend_consumer_target
      if [ -n "$pkg_depend_key_constraints" ]
      then
        pkg_depend_key_constraints="$pkg_depend_key_constraints $pkg_depend_constraints"
      else
        pkg_depend_key_constraints=$pkg_depend_constraints
      fi
    done <<EOF_PKG_DEPEND_REQUIREMENTS_FOR_KEY
$pkg_depend_requirements
EOF_PKG_DEPEND_REQUIREMENTS_FOR_KEY

    [ -n "$pkg_depend_key_facility" ] && [ -n "$pkg_depend_key_target" ] && [ -n "$pkg_depend_key_constraints" ] || return 1

    _pkg_depend_provider_resolve "$pkg_depend_catalog" "$pkg_depend_key_selector" "$pkg_depend_key_facility" "$pkg_depend_key_constraints" "$pkg_depend_key_target"
    pkg_depend_provider_status=$?
    case "$pkg_depend_provider_status" in
      0) : ;;
      4) return 1 ;;
      *)
        log error execution execution-failed operation pkg-depend \
          reason provider-unresolvable \
          facility "$pkg_depend_key_facility" \
          constraints "$pkg_depend_key_constraints" \
          target "$pkg_depend_key_target" \
          selector "$pkg_depend_key_selector" \
          status "$pkg_depend_provider_status" || :
        return 1
        ;;
    esac
    pkg_depend_selection="$pkg_depend_key|$pkg_depend_selected|$pkg_depend_key_target"

    if [ -n "$pkg_depend_new_selections" ]
    then
      pkg_depend_new_selections="$pkg_depend_new_selections
$pkg_depend_selection"
    else
      pkg_depend_new_selections=$pkg_depend_selection
    fi
  done <<EOF_PKG_DEPEND_KEYS
$pkg_depend_keys
EOF_PKG_DEPEND_KEYS
}

_pkg_depend_selected_concrete()
{
  [ "$#" -eq 1 ] || return 2
  [ -n "$pkg_depend_selections" ] || return 1

  while IFS='|' read -r pkg_depend_selection_key pkg_depend_selection_concrete pkg_depend_selection_target pkg_depend_selection_extra
  do
    [ -z "$pkg_depend_selection_extra" ] || return 1
    [ "$pkg_depend_selection_concrete" = "$1" ] && return 0
  done <<EOF_PKG_DEPEND_SELECTED_CONCRETE
$pkg_depend_selections
EOF_PKG_DEPEND_SELECTED_CONCRETE

  return 1
}

_pkg_depend_selection_find()
{
  [ "$#" -eq 1 ] || return 2

  while IFS='|' read -r pkg_depend_selection_key pkg_depend_selection_concrete pkg_depend_selection_target pkg_depend_selection_extra
  do
    [ -z "$pkg_depend_selection_extra" ] || return 1
    [ "$pkg_depend_selection_key" = "$1" ] || continue
    pkg_depend_selected=$pkg_depend_selection_concrete
    return 0
  done <<EOF_PKG_DEPEND_SELECTION_FIND
$pkg_depend_selections
EOF_PKG_DEPEND_SELECTION_FIND

  return 1
}

_pkg_depend_edges_build()
{
  pkg_depend_edges=
  [ -z "$pkg_depend_requirements" ] && return 0

  while IFS='|' read -r pkg_depend_consumer_concrete pkg_depend_consumer_target pkg_depend_consumer_pkg pkg_depend_facility pkg_depend_constraints pkg_depend_selector pkg_depend_requirement_key pkg_depend_requirement_extra
  do
    [ -z "$pkg_depend_requirement_extra" ] || return 1
    _pkg_depend_selection_find "$pkg_depend_requirement_key" || return 1
    pkg_depend_edge="$pkg_depend_consumer_concrete|$pkg_depend_selected"

    pkg_depend_edge_seen=0
    if [ -n "$pkg_depend_edges" ]
    then
      while IFS= read -r pkg_depend_existing_edge
      do
        if [ "$pkg_depend_existing_edge" = "$pkg_depend_edge" ]
        then
          pkg_depend_edge_seen=1
          break
        fi
      done <<EOF_PKG_DEPEND_EXISTING_EDGES
$pkg_depend_edges
EOF_PKG_DEPEND_EXISTING_EDGES
    fi

    [ "$pkg_depend_edge_seen" -eq 0 ] || continue
    if [ -n "$pkg_depend_edges" ]
    then
      pkg_depend_edges="$pkg_depend_edges
$pkg_depend_edge"
    else
      pkg_depend_edges=$pkg_depend_edge
    fi
  done <<EOF_PKG_DEPEND_EDGE_REQUIREMENTS
$pkg_depend_requirements
EOF_PKG_DEPEND_EDGE_REQUIREMENTS
}

_pkg_depend_visit()
{
  [ "$#" -eq 1 ] || return 2

  case " $pkg_depend_done " in *" $1 "*) return 0 ;; esac
  case " $pkg_depend_stack " in *" $1 "*) return 1 ;; esac

  pkg_depend_stack_saved=$pkg_depend_stack
  pkg_depend_stack="$pkg_depend_stack $1"

  if [ -n "$pkg_depend_edges" ]
  then
    while IFS='|' read -r pkg_depend_edge_consumer pkg_depend_edge_provider pkg_depend_edge_extra
    do
      [ -z "$pkg_depend_edge_extra" ] || return 1
      [ "$pkg_depend_edge_consumer" = "$1" ] || continue
      _pkg_depend_visit "$pkg_depend_edge_provider" || return 1
    done <<EOF_PKG_DEPEND_VISIT_EDGES
$pkg_depend_edges
EOF_PKG_DEPEND_VISIT_EDGES
  fi

  pkg_depend_stack=$pkg_depend_stack_saved
  pkg_depend_done="$pkg_depend_done $1"
  pkg_depend_order="$pkg_depend_order $1"
}

_pkg_depend_plan()
(
  [ "$#" -ge 3 ] || return 2
  pkg_depend_catalog=$1
  pkg_depend_root_mode=$2
  shift 2

  case "$pkg_depend_root_mode" in request|exact) : ;; *) return 2 ;; esac

  [ -d "$pkg_depend_catalog" ] && [ ! -L "$pkg_depend_catalog" ] || return 1
  pkg_depend_default_target=${m_CONTEXT_OSARCH:-$m_OSARCH}
  pkg_osarch_valid "$pkg_depend_default_target" || return 1

  pkg_depend_roots=
  pkg_depend_contexts=

  for pkg_depend_request
  do
    pkg_depend_root_request=$pkg_depend_request
    pkg_depend_root_target=$pkg_depend_default_target
    if [ "$pkg_depend_root_mode" = exact ]
    then
      case "$pkg_depend_request" in
        *'|'*) : ;;
        *) return 2 ;;
      esac
      pkg_depend_root_request=${pkg_depend_request%%|*}
      pkg_depend_root_target=${pkg_depend_request#*|}
      case "$pkg_depend_root_target" in
        *'|'*) return 2 ;;
      esac
      pkg_osarch_valid "$pkg_depend_root_target" || return 2
    fi

    _pkg_depend_request_resolve "$pkg_depend_catalog" "$pkg_depend_root_request" "$pkg_depend_root_target" "$pkg_depend_root_mode"
    pkg_depend_request_status=$?
    if [ "$pkg_depend_request_status" -ne 0 ]
    then
      log error execution execution-failed operation pkg-depend \
        reason request-unresolvable \
        request "$pkg_depend_request" \
        default-target "$pkg_depend_default_target" \
        status "$pkg_depend_request_status" || :
      return "$pkg_depend_request_status"
    fi
    _pkg_depend_context_add "$pkg_depend_concrete" "$pkg_depend_target" || return 1
  done
  pkg_depend_roots=$pkg_depend_contexts

  pkg_depend_selections=
  pkg_depend_previous_selections=

  while :
  do
    _pkg_depend_contexts_rebuild || return 1
    _pkg_depend_requirements_build "$pkg_depend_catalog" || return 1
    _pkg_depend_selections_resolve "$pkg_depend_catalog" || return 1

    if [ "$pkg_depend_new_selections" = "$pkg_depend_selections" ]
    then
      break
    fi

    if [ -n "$pkg_depend_previous_selections" ] && [ "$pkg_depend_new_selections" = "$pkg_depend_previous_selections" ]
    then
      return 1
    fi

    pkg_depend_previous_selections=$pkg_depend_selections
    pkg_depend_selections=$pkg_depend_new_selections
  done

  _pkg_depend_edges_build || return 1

  pkg_depend_done=
  pkg_depend_stack=
  pkg_depend_order=

  while IFS='|' read -r pkg_depend_root_concrete pkg_depend_root_target pkg_depend_root_extra
  do
    [ -z "$pkg_depend_root_extra" ] || return 1
    _pkg_depend_visit "$pkg_depend_root_concrete" || return 1
  done <<EOF_PKG_DEPEND_ROOT_VISIT
$pkg_depend_roots
EOF_PKG_DEPEND_ROOT_VISIT

  pkg_depend_separator=
  for pkg_depend_concrete in $pkg_depend_order
  do
    _pkg_depend_selected_concrete "$pkg_depend_concrete" || continue
    pkg_depend_quoted="$(quote "$pkg_depend_concrete")" || return 1
    printf -- '%s' "$pkg_depend_separator$pkg_depend_quoted"
    pkg_depend_separator=" "
  done
)

pkg_depend_plan()
(
  [ "$#" -ge 2 ] || return 2
  pkg_depend_plan_catalog=$1
  shift
  _pkg_depend_plan "$pkg_depend_plan_catalog" exact "$@"
)

_pkg_depend_cleanup()
{
  [ -z "${pkg_depend_work-}" ] || command -p -- rm -rf -- "$pkg_depend_work" 2>/dev/null || :
}

pkg_depend()
(
  [ "$#" -ge 1 ] || return 2

  for pkg_depend_request
  do
    pkg_request_read pkg_depend_validate_pkg pkg_depend_validate_version pkg_depend_validate_osarch "$pkg_depend_request" || return 2
  done

  umask 077
  pkg_depend_work=
  trap '_pkg_depend_cleanup' 0
  trap 'exit 130' HUP INT TERM

  pkg_depend_tmp_root="$(command -- state-path system sys pkg tmp)" || return 1
  command -p -- mkdir -p -- "$pkg_depend_tmp_root" || return 1
  [ -d "$pkg_depend_tmp_root" ] && [ ! -L "$pkg_depend_tmp_root" ] || return 1

  pkg_depend_cache_root="$(command -- state-path system sys pkg cache)" || return 1
  command -p -- mkdir -p -- "$pkg_depend_cache_root" || return 1
  [ -d "$pkg_depend_cache_root" ] && [ ! -L "$pkg_depend_cache_root" ] || return 1

  pkg_depend_work="$pkg_depend_tmp_root/depend-$$"
  [ ! -e "$pkg_depend_work" ] && [ ! -L "$pkg_depend_work" ] || return 1
  command -p -- mkdir -- "$pkg_depend_work" || return 1

  pkg_catalog_init pkg_depend_catalog_work pkg_depend_catalog_head "$pkg_depend_work" "$pkg_depend_cache_root" || return 1

  pkg_depend_result="$(_pkg_depend_plan "$pkg_depend_catalog_work" request "$@")" || return $?
  eval "set -- $pkg_depend_result"

  for pkg_depend_concrete
  do
    printf -- '%s\n' "$pkg_depend_concrete" || return 1
  done
)
