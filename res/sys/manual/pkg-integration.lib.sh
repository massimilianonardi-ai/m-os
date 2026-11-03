NAME
    pkg-integration.lib.sh - integrate and deintegrate managed package concretes

DESCRIPTION
    pkg-integration.lib.sh implements package integration, deintegration and package
    default application inside the managed package store.

FUNCTIONS
    pkg_integrate <package> <version> <range-dir> <root-dir> [<osarch> [<schema> [<catalog-root>]]]
        Validate a resolved package definition and extracted useful root, including
        flat-pkg primary component/payload-root metadata and dmg-pkg primary
        component/payload-root/overlay metadata, validate dependency declaration
        syntax, materialize the managed concrete and its command/environment/
        facility/state metadata and optional ordinary package library views.
        v1 materializes command wrappers in cmd/ and ordinary libraries in
        lib/sh and lib/java. The optional schema is v1 by default. v2 stores a
        schema marker and exposes commands through link/bin (either useful-root
        executables or validated cmd wrappers), with library links under
        link/lib/sh and link/lib/java. Both layouts bind to one exact installed
        concrete. Only non-executable POSIX *.lib.sh and readable *.jar
        library exports are supported; ordinary libraries do not create
        facility provider-selection state.

        Integration also validates/materializes declarative facility command,
        environment and service realizations. v1 retains facility-cmd mappings
        and flat facility-env records. In v2, command members derive from the
        central facility contract and the provider supplies facility-bin and/or
        exact link/bin entrypoints. The v2 provider supplies typed environment
        values keyed under facility-env/<facility>/<variable>; integration
        creates the established flat installed facility-env representation
        consumed by pkg-provider. PATH is permitted with root/root-path
        contributions only; it is not a literal variable replacement.

        pkg_integrate does not acquire or derive pkg-catalog context. The normal
        pkg-install path performs exact-snapshot provider conformance before calling
        integration. For v2 providers, catalog-root must be supplied so integration
        can validate contract-derived members against that same catalog snapshot.
        Integration validates local realization structure through trusted handlers
        while retaining package-definition envelope and declared-facility checks.

        osarch controls the concrete package identity/class. Dependency declarations
        are stored as immutable package metadata but mutable runtime provider
        availability/selection is deliberately not resolved during integration.
        No separate provider-index state is created; installed concrete facility
        declarations are the provider-discovery source of truth.

    pkg_deintegrate <package> <version> [<osarch>]
        Remove an installed concrete only when it is not the package default and is
        not referenced by explicit provider-selection configuration. No separate
        provider index must be maintained. Persistent package state is not removed.

    pkg_default_apply <package> <version> [<osarch>]
        Select an installed concrete as the package/platform default and publish
        its command view (v1 cmd, v2 link/bin). An empty version clears it. A transition
        also reconciles global facility commands whose configured provider selector
        depends on the presence or current concrete of this package/class.

RETURN STATUS
    pkg_integrate returns 0 on success.

    Its direct validation/materialization stages return:

        1   invalid invocation, definition-validation failure, or failure while
            moving the prepared root after concrete creation
        2   invalid package identity or unsupported package-definition feature
        3   package store is not a real directory
        4   range directory is not a real directory
        5   prepared root is not a real directory
        6   range directory cannot be canonicalized
        7   prepared root cannot be canonicalized
        8   concrete identity/class derivation failed
        9   concrete package already exists
        10  package state metadata validation failed
        11  setuid metadata validation failed
        12  concrete package directory creation failed
        13  command materialization failed
        14  environment materialization failed
        15  facility materialization failed
        16  facility projection materialization failed
        17  dependency materialization failed
        18  state materialization failed
        19  setuid/state rollback failed after setuid materialization failure
        20  setuid materialization failed and rollback succeeded
        21  ordinary library-view materialization failed
        22  v2 facility command materialization failed

    Definition validation may also propagate its existing status 1 or 2 as
    described above.

    pkg_deintegrate returns 0 on success, 1 for invalid invocation arity or
    when the requested installed concrete cannot be safely removed, and 2 when
    the supplied package identity is invalid.

    pkg_default_apply returns 0 on success, 1 when the requested default state
    cannot be validated or changed, and 2 for invalid invocation or invalid
    package/default identity operands.

DEPENDENCIES
    The library uses the shared package identity validators from pkg-common.lib.sh
    and composes package facility, dependency, state and setuid facilities.

SEE ALSO
    pkg
    pkg-dependency.lib.sh
    pkg-provider.lib.sh
