NAME
    pkg-provider.lib.sh - manage package facility provider configuration

DESCRIPTION
    pkg-provider.lib.sh implements the provider-selection configuration surface used
    by the public pkg provider command.

    Facility defaults are system-scoped package-subsystem configuration. A facility
    default owns global command publication for that facility through bin/ext and
    bin/ext-<osarch> and contributes the selected provider's facility environment
    to each new m bootstrap. Facility-default selectors are non-secret runtime
    selection metadata: their storage is read-only/traversable for runtime accounts
    that must resolve global/system-host intent, while mutation remains protected by
    normal filesystem ownership. Consumer bindings are system-scoped package
    configuration stored as binding/<facility> beneath the consumer package conf
    area. A binding file contains exactly one provider selector followed by newline.
    Provider selectors are non-secret runtime-selection metadata; both defaults and
    bindings may be made read-only/traversable for a service account while their
    enclosing state remains non-writable to that account.

    Global environment is materialized as derived system environment cache when
    facility-default or provider-package-default state changes. The materializer
    resolves every supported osarch, extracts assignments common to all platform
    contexts into the generic env snapshot and writes remaining assignments into
    env-<osarch> snapshots. Facility defaults are processed in LC_ALL=C facility
    order and later assignments win duplicate ordinary variables.

    PATH is a special facility-env projection. It accepts root/root-path descriptors
    only, may repeat, and contributes managed provider directories rather than
    replacing the whole PATH. A PATH root-path descriptor must resolve to a directory
    contained by the provider useful root. Later contributions have higher precedence.

FUNCTIONS
    pkg_provider_default_resolve <facility>
        Resolve the configured system facility default to one installed concrete
        provider using the same active global package-class semantics as global
        facility publication/environment. Consumer bindings are not consulted.

        Returns 0 and prints the concrete identity on success, 1 when no system
        facility default is configured, 2 for invalid invocation/facility syntax,
        and 3 when configured/default state exists but cannot be validated or
        resolved.

    pkg_provider_default_runtime_access_prepare <facility>
        Prepare the configured facility-default selector for read-only resolution
        by a non-owner runtime account. The function changes only traversal/read
        permissions on the facility-default configuration path; it does not change
        selector intent, provider installation or consumer bindings.

    pkg_provider_global_runtime_access_prepare
        Prepare every configured system facility-default selector for read-only
        enumeration/resolution by a non-owner runtime account that explicitly uses
        live provider-selection APIs. The m bootstrap does not require this access
        for global environment loading because it consumes materialized environment
        cache instead. Selector intent is not changed.

    pkg_provider_effective_selector_runtime_access_prepare <consumer> <facility>
        Prepare explicit selector metadata used by one consumer/facility pair for
        read-only resolution by a non-owner runtime account. An explicit binding is
        prepared when present; otherwise a configured system facility default is
        prepared. If neither exists, no selector-state preparation is required
        because package-consumer resolution may be implicit. Selector intent is not
        changed.

    pkg_provider_effective_selector <consumer> <facility>
        Print the effective explicitly configured selector for the consumer/facility
        pair: the explicit consumer binding when present, otherwise the configured
        system facility default. Returns 1 when neither selector is configured,
        2 for invalid invocation/syntax and 3 when selector configuration exists but
        is invalid. Installed-provider fallback belongs to pkg-dependency.lib.sh,
        not to this configuration API.

    pkg_provider_selector_resolve <provider-selector> [<consumer-osarch>]
        Resolve selector intent to one installed concrete package identity. A
        selector without version follows the provider package default. A selector
        with version is pinned. When consumer-osarch is supplied, a matching
        platform-specific provider is preferred and a generic provider may satisfy
        a selector that did not explicitly pin another osarch.

    pkg_provider_concrete_referenced <concrete-provider>
        Return 0 when the concrete provider is currently selected by a system
        facility default or a system consumer binding, 1 when it is not referenced,
        and 2 when the request or authoritative configuration cannot be validated.

    pkg_provider_environment_apply <facility> <concrete-provider>
        Validate and apply one installed concrete provider's facility-env projection
        to the current process. The projection is interpreted without shell
        evaluation and is validated as a whole before export.

    pkg_provider_global_environment_apply
        Recompute and apply the environment of all currently resolvable system
        facility defaults to the current process. This API remains available for
        direct runtime use; the m bootstrap does not call it.

    pkg_provider_global_environment_materialize
        Recompute all supported-osarch global facility environments and atomically
        publish the derived env and env-<osarch> snapshots under the system
        sys/environment cache. Ordinary assignments common to every platform are
        placed in env. PATH is common only when its complete resolved contribution
        sequence is identical for every platform.

    pkg_provider_package_default_reconcile <package> <osarch> <old-concrete> <new-concrete>
        Reconcile global commands affected by one package-default transition. For
        unversioned facility selectors this updates the selected command set while
        preserving selector-based targets. A pinned selector without osarch remains
        pinned but is published or removed as the corresponding package class
        appears or disappears. osarch is empty for the generic package class.
        Unrelated external-command collisions are rejected. The derived installed
        facility map is refreshed after the selection transition; map failure is
        logged without changing the authoritative package/provider selection.

    pkg_provider default <facility>
        Print the configured system default provider selector for the facility.

    pkg_provider default <facility> <provider-selector>
        Set the configured system default provider selector and reconcile the
        facility's owned global command projection and derived installed facility
        map default projection. Map reconciliation failure is logged and does not
        invalidate the configured selection.

    pkg_provider default -u [--] <facility>
        Remove the configured system default provider selector and its owned global
        command projection, then reconcile the derived installed facility map.

    pkg_provider bind <consumer> <facility>
        Print the configured provider selector for that consumer/facility pair.

    pkg_provider bind <consumer> <facility> <provider-selector>
        Set the consumer/facility provider selector.

    pkg_provider bind -u [--] <consumer> <facility>
        Remove the consumer binding. Package-consumer dependency resolution then
        uses the facility default when configured and otherwise may use deterministic
        implicit installed-provider resolution.

PROVIDER SELECTORS
    Provider selectors use package-spec syntax:

        <package>
        <package>@<version>
        <package>!<osarch>
        <package>@<version>!<osarch>

    This library stores selector intent; it does not install providers or choose a
    missing provider automatically. Unversioned global command links target provider
    package-default selectors; pinned selectors target pinned provider concretes.
    Facility-default and provider-package-default mutations reconcile generated
    environment snapshots before returning. New m executions source those already
    resolved snapshots and perform no provider resolution.

RETURN STATUS
    Unless a function documents a more specific status contract:
    0   Requested query or mutation succeeded.
    1   Required configured state is absent or configuration storage could not be
        read or changed safely.
    2   Invocation, consumer/facility name or provider-selector syntax is invalid.

    pkg_provider_default_resolve additionally uses status 3 for an existing
    configured/default state that is invalid or cannot resolve to an installed
    concrete.

DEPENDENCIES
    The library runs inside the m bootstrap environment. Authoritative selector
    configuration remains under package subsystem state; generated global
    environment is written under the system sys/environment cache.

SEE ALSO
    pkg
    state-path
