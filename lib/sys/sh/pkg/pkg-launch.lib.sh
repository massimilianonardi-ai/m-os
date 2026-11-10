loadsyslib "pkg/pkg-common"
loadsyslib "pkg/facility/pkg-facility"
loadsyslib "pkg/facility/pkg-dependency"

_pkg_launch_error()
{
  log error execution execution-failed operation launcher reason "$1"
}

_pkg_launch_name_valid()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in
    "" | [!a-z0-9]* | *[!a-z0-9._-]* | *[._-]) return 1 ;;
  esac
}

_pkg_launch_override_name_valid()
{
  [ "$#" -eq 1 ] || return 2
  case "$1" in
    [a-zA-Z_]*)
      case "$1" in *[!a-zA-Z0-9_]*) return 1 ;; esac
      ;;
    *) return 1 ;;
  esac
}

_pkg_launch_override_error()
{
  [ "$#" -eq 2 ] || return 2
  log error execution "$1" operation launcher variable "$2"
}

_pkg_launch_state_context_set()
{
  [ "$#" -eq 0 ] || return 2

  pkg_launch_state_scope=user
  pkg_launch_state_instance=

  case "${m_PKG_LAUNCH_CONTEXT-}" in
    "")
      [ -z "${m_PKG_LAUNCH_STATE_INSTANCE-}" ] || return 1
      ;;
    system-service)
      _pkg_launch_name_valid "${m_PKG_LAUNCH_STATE_INSTANCE-}" || return 1
      pkg_launch_state_scope=system
      pkg_launch_state_instance=$m_PKG_LAUNCH_STATE_INSTANCE
      ;;
    *)
      return 1
      ;;
  esac
}

_pkg_launch_context_state_compatible()
{
  [ "$#" -eq 0 ] || return 2
  [ "${m_CONTEXT_ENVELOPE+x}" = x ] || return 0
  _context_envelope_validate || return 1
  _m_system_state_selector_validate || return 1
  if [ "$m_STATE_SYS_DIR" = "$m_ROOT/state/system/profile/$_m_system_state_identity" ]
  then
    return 0
  fi

  # Installed mutable var/ links are fixed to system/current. Until a concrete
  # has a verified process-local adapter, refuse its launch in another profile.
  loadsyslib "pkg/pkg-state" || return 1
  _pkg_state_validate "$pkg_launch_concrete" "$pkg_launch_root" "$pkg_launch_pkg" "$pkg_schema" || return 1
  [ -z "$pkg_state_paths" ]
}

_pkg_launch_env_apply()
{
  [ "$#" -eq 1 ] || return 2

  if [ ! -e "$1" ] && [ ! -L "$1" ]
  then
    return 0
  fi

  [ -f "$1" ] && [ ! -L "$1" ] && [ -r "$1" ] || return 1
  command -p -- sh -n "$1" >/dev/null 2>&1 || return 1
  . "$1" || return 1
}

_pkg_launch_provider_apply()
{
  [ "$#" -eq 2 ] || return 2
  pkg_launch_provider_facility=$1
  pkg_launch_provider_name=$2
  pkg_launch_provider_concrete="$m_PKG_DIR/$pkg_launch_provider_name"
  pkg_launch_provider_root="$pkg_launch_provider_concrete/root"

  [ -d "$pkg_launch_provider_concrete" ] && [ ! -L "$pkg_launch_provider_concrete" ] || return 1
  [ -d "$pkg_launch_provider_root" ] && [ ! -L "$pkg_launch_provider_root" ] || return 1

  pkg_launch_provider_cmd="$pkg_launch_provider_concrete/facility-cmd/$pkg_launch_provider_facility"
  if [ -e "$pkg_launch_provider_cmd" ] || [ -L "$pkg_launch_provider_cmd" ]
  then
    [ -d "$pkg_launch_provider_cmd" ] && [ ! -L "$pkg_launch_provider_cmd" ] || return 1
    PATH="$pkg_launch_provider_cmd:$PATH"
    export PATH
  fi

  pkg_provider_environment_apply "$pkg_launch_provider_facility" "$pkg_launch_provider_name"
}

_pkg_launch_dependencies_apply()
{
  [ "$#" -eq 3 ] || return 2
  pkg_launch_dependency_file=$1
  pkg_launch_dependency_consumer=$2
  pkg_launch_dependency_osarch=$3

  pkg_launch_dependency_set="$(pkg_dependency_resolve "$pkg_launch_dependency_file" "$pkg_launch_dependency_consumer" "$pkg_launch_dependency_osarch")" || return 1
  [ -n "$pkg_launch_dependency_set" ] || return 0

  pkg_launch_dependency_tab="$(printf '\t')"
  while IFS="$pkg_launch_dependency_tab" read -r pkg_launch_dependency_facility pkg_launch_dependency_provider pkg_launch_dependency_extra
  do
    [ -n "$pkg_launch_dependency_facility" ] && [ -n "$pkg_launch_dependency_provider" ] && [ -z "$pkg_launch_dependency_extra" ] || return 1
    _pkg_launch_provider_apply "$pkg_launch_dependency_facility" "$pkg_launch_dependency_provider" || return 1
  done <<EOF_DEPENDENCIES
$pkg_launch_dependency_set
EOF_DEPENDENCIES
}

# Called only by browser package entrypoints. The generic launcher keeps all
# normal state, dependency and environment semantics; this requests one trusted
# NSS projection at the final effective HOME immediately before exec.
launcher_nss()
{
  [ "$#" -ge 1 ] || return 2
  pkg_launch_nss_enabled=1
  launcher "$@"
}

launcher()
{
  [ "$#" -ge 1 ] || return 2
  pkg_launch_pkg=$1
  shift

  _pkg_launch_name_valid "$pkg_launch_pkg" || return 2

  [ -n "${m_PKG_DIR-}" ] || {
    _pkg_launch_error runtime-variable-missing
    return 1
  }

  # The native shell command owns its own identity, not an inherited
  # identity from the m bootstrap or a previously executed command.
  readpathce pkg_launch_command_bin "$0" || {
    _pkg_launch_error command-invalid
    return 1
  }
  [ -f "$pkg_launch_command_bin" ] && [ -r "$pkg_launch_command_bin" ] && [ -x "$pkg_launch_command_bin" ] || {
    _pkg_launch_error command-invalid
    return 1
  }

  pkg_launch_command=${pkg_launch_command_bin##*/}
  _pkg_launch_name_valid "$pkg_launch_command" || {
    _pkg_launch_error command-name-invalid
    return 1
  }

  pkg_launch_cmd_dir=${pkg_launch_command_bin%/*}
  [ "${pkg_launch_cmd_dir##*/}" = cmd ] || {
    _pkg_launch_error command-layout-invalid
    return 1
  }

  pkg_launch_concrete=${pkg_launch_cmd_dir%/*}
  [ -d "$pkg_launch_concrete" ] && [ ! -L "$pkg_launch_concrete" ] || {
    _pkg_launch_error concrete-invalid
    return 1
  }
  pkg_launch_concrete_name=${pkg_launch_concrete##*/}
  case "$pkg_launch_concrete_name" in
    *!*) pkg_launch_osarch=${pkg_launch_concrete_name##*!} ;;
    *) pkg_launch_osarch= ;;
  esac

  readpathce pkg_launch_pkg_dir "$m_PKG_DIR" || {
    _pkg_launch_error package-store-invalid
    return 1
  }
  [ -d "$pkg_launch_pkg_dir" ] && [ ! -L "$pkg_launch_pkg_dir" ] || {
    _pkg_launch_error package-store-invalid
    return 1
  }
  [ "${pkg_launch_concrete%/*}" = "$pkg_launch_pkg_dir" ] || {
    _pkg_launch_error command-outside-package-store
    return 1
  }

  pkg_launch_root="$pkg_launch_concrete/root"
  [ -d "$pkg_launch_root" ] && [ ! -L "$pkg_launch_root" ] || {
    _pkg_launch_error root-invalid
    return 1
  }
  readpathce pkg_launch_root "$pkg_launch_root" || {
    _pkg_launch_error root-invalid
    return 1
  }

  _pkg_schema_read "$pkg_launch_concrete" || {
    _pkg_launch_error package-schema-invalid
    return 1
  }

  _pkg_launch_context_state_compatible || {
    _pkg_launch_error context-state-incompatible
    return 1
  }

  if [ "$pkg_schema" = v2 ]
  then
    pkg_launch_link="$pkg_launch_concrete/link/target/$pkg_launch_command"
  else
    pkg_launch_link="$pkg_launch_concrete/link/$pkg_launch_command"
  fi
  [ -L "$pkg_launch_link" ] || {
    _pkg_launch_error link-missing
    return 1
  }
  pkg_launch_link_text="$(command -p -- readlink "$pkg_launch_link")" || {
    _pkg_launch_error link-invalid
    return 1
  }
  case "$pkg_launch_link_text" in
    "" | /* | *'
'*)
      _pkg_launch_error link-invalid
      return 1
      ;;
  esac

  readpathce pkg_launch_target "$pkg_launch_link" || {
    _pkg_launch_error target-invalid
    return 1
  }
  case "$pkg_launch_target" in
    "$pkg_launch_root"/*) : ;;
    *)
      _pkg_launch_error target-outside-root
      return 1
      ;;
  esac
  [ -f "$pkg_launch_target" ] && [ -x "$pkg_launch_target" ] || {
    _pkg_launch_error target-not-executable
    return 1
  }

  _pkg_launch_state_context_set || {
    _pkg_launch_error state-context-invalid
    return 1
  }

  if [ -n "$pkg_launch_state_instance" ]
  then
    pkg_launch_home="$(command -- state-path "$pkg_launch_state_scope" pkg "$pkg_launch_pkg" home "$pkg_launch_state_instance")" || {
      _pkg_launch_error home-state-invalid
      return 1
    }
    pkg_launch_conf="$(command -- state-path "$pkg_launch_state_scope" pkg "$pkg_launch_pkg" conf "$pkg_launch_state_instance")" || {
      _pkg_launch_error conf-state-invalid
      return 1
    }
  else
    pkg_launch_home="$(command -- state-path "$pkg_launch_state_scope" pkg "$pkg_launch_pkg" home)" || {
      _pkg_launch_error home-state-invalid
      return 1
    }
    pkg_launch_conf="$(command -- state-path "$pkg_launch_state_scope" pkg "$pkg_launch_pkg" conf)" || {
      _pkg_launch_error conf-state-invalid
      return 1
    }
  fi

  umask 077
  command -p -- mkdir -p -- "$pkg_launch_home" || {
    _pkg_launch_error home-state-create-failed
    return 1
  }
  [ -d "$pkg_launch_home" ] && [ ! -L "$pkg_launch_home" ] || {
    _pkg_launch_error home-state-invalid
    return 1
  }

  readonly -- \
    pkg_launch_pkg \
    pkg_launch_command_bin \
    pkg_launch_command \
    pkg_launch_cmd_dir \
    pkg_launch_concrete \
    pkg_launch_concrete_name \
    pkg_launch_osarch \
    pkg_launch_pkg_dir \
    pkg_launch_root \
    pkg_launch_link \
    pkg_launch_link_text \
    pkg_launch_target \
    pkg_launch_home \
    pkg_launch_conf \
    pkg_launch_state_scope \
    pkg_launch_state_instance

  # Snapshot caller values before package/provider environment is applied.
  # Keep assignments in argv: variable values are never evaluated as shell code.
  pkg_launch_override_active=0
  pkg_launch_nss_override_present=0
  if [ "${m_ENV_DO_NOT_OVERRIDE+x}" = x ]
  then
    pkg_launch_override_active=1
    pkg_launch_override_remaining=$m_ENV_DO_NOT_OVERRIDE
    pkg_launch_override_seen=' '
    [ -n "$pkg_launch_override_remaining" ] || {
      _pkg_launch_override_error environment-override-invalid m_ENV_DO_NOT_OVERRIDE
      return 3
    }

    set -- "$pkg_launch_target" "$@"
    while [ -n "$pkg_launch_override_remaining" ]
    do
      case "$pkg_launch_override_remaining" in
        *' '*)
          pkg_launch_override_name=${pkg_launch_override_remaining%% *}
          pkg_launch_override_remaining=${pkg_launch_override_remaining#* }
          [ -n "$pkg_launch_override_remaining" ] || {
            _pkg_launch_override_error environment-override-invalid m_ENV_DO_NOT_OVERRIDE
            return 3
          }
          ;;
        *)
          pkg_launch_override_name=$pkg_launch_override_remaining
          pkg_launch_override_remaining=
          ;;
      esac
      _pkg_launch_override_name_valid "$pkg_launch_override_name" || {
        _pkg_launch_override_error environment-override-invalid "$pkg_launch_override_name"
        return 3
      }
      case "$pkg_launch_override_name" in
        m_ENV_DO_NOT_OVERRIDE | m_PKG_LAUNCH_CONTEXT | m_PKG_LAUNCH_STATE_INSTANCE)
          _pkg_launch_override_error environment-override-control-variable "$pkg_launch_override_name"
          return 5
          ;;
      esac
      case "$pkg_launch_override_seen" in
        *" $pkg_launch_override_name "*)
          _pkg_launch_override_error environment-override-duplicate "$pkg_launch_override_name"
          return 7
          ;;
      esac
      pkg_launch_override_seen="$pkg_launch_override_seen$pkg_launch_override_name "
      # Only a validated identifier is interpolated into the expansion.
      eval "pkg_launch_override_present=\${$pkg_launch_override_name+x}"
      [ "$pkg_launch_override_present" = x ] || {
        _pkg_launch_override_error environment-override-variable-missing "$pkg_launch_override_name"
        return 4
      }
      eval "pkg_launch_override_value=\${$pkg_launch_override_name}"
      if [ "$pkg_launch_override_name" = HOME ] && [ "${pkg_launch_nss_enabled-0}" -eq 1 ]
      then
        pkg_launch_nss_override_present=1
        pkg_launch_nss_override_home=$pkg_launch_override_value
      fi
      set -- "$pkg_launch_override_name=$pkg_launch_override_value" "$@"
    done

    pkg_launch_override_env="$(command -p -v env)" || {
      _pkg_launch_override_error environment-override-executor-unavailable env
      return 6
    }
    case "$pkg_launch_override_env" in
      /*) : ;;
      *)
        _pkg_launch_override_error environment-override-executor-unavailable env
        return 6
        ;;
    esac
    unset m_ENV_DO_NOT_OVERRIDE
  fi

  HOME=$pkg_launch_home
  export -- HOME

  readonly -- m_ROOT m_STATE_DIR m_STATE_SYS_DIR m_STATE_USER_DIR
  if [ "${m_CONTEXT_ENVELOPE+x}" = x ]
  then
    readonly -- m_CONTEXT_ENVELOPE m_CONTEXT_SYSTEM_PROFILE m_CONTEXT_PACKAGES
  fi

  unset m_PKG_LAUNCH_CONTEXT m_PKG_LAUNCH_STATE_INSTANCE

  _pkg_launch_env_apply "$pkg_launch_concrete/env" || {
    _pkg_launch_error package-env-invalid
    return 1
  }
  _pkg_launch_dependencies_apply "$pkg_launch_concrete/dependency" "$pkg_launch_pkg" "$pkg_launch_osarch" || {
    _pkg_launch_error dependency-runtime-invalid
    return 1
  }
  _pkg_launch_env_apply "$pkg_launch_conf/.m/env" || {
    _pkg_launch_error user-env-invalid
    return 1
  }

  if [ "${pkg_launch_nss_enabled-0}" -eq 1 ]
  then
    pkg_launch_nss_home=$HOME
    if [ "$pkg_launch_nss_override_present" -eq 1 ]
    then
      pkg_launch_nss_home=$pkg_launch_nss_override_home
    fi
    # The integration point sees the effective HOME, including the one-shot
    # nested Electron override. Never mutate the application's browser profile.
    "$m_ROOT/m" "$m_BIN_DIR/sys/tls-nss-sync" "$pkg_launch_nss_home" || {
      printf 'pkg-launch.tls-nss-sync-failed: package=%s home=%s\n' "$pkg_launch_pkg" "$pkg_launch_nss_home" >&2
      return 8
    }
  fi

  if [ "$pkg_launch_override_active" -eq 1 ]
  then
    # env applies the saved values to the exec target without changing state-path.
    unset m_ENV_DO_NOT_OVERRIDE
    exec "$pkg_launch_override_env" "$@"
  fi
  exec "$pkg_launch_target" "$@"
}
