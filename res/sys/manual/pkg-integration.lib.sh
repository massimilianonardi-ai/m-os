NAME
    pkg-integration.lib.sh - integrate and deintegrate managed package concretes

DESCRIPTION
    pkg-integration.lib.sh implements package integration, deintegration and package
    default application inside the managed package store.

FUNCTIONS
    pkg_integrate <package> <version> <range-dir> <root-dir> [<osarch>]
        Validate a resolved package definition and extracted useful root, including
        flat-pkg primary component/payload-root metadata and dmg-pkg primary
        component/payload-root/overlay metadata, validate dependency declaration
        syntax, materialize the managed concrete and its command/environment/
        facility/state metadata and optional ordinary package library views
        lib/sh and lib/java. The package range descriptor lib/<runtime>/<name>
        contains one relative pathname beneath the useful root; integration
        validates it and creates the corresponding concrete-local symlink.
        Only non-executable POSIX *.lib.sh files and readable *.jar files
        are accepted in this first stage. Library publication is independent
        of facility declarations and does not copy payloads.

        Integration also validates/materializes declarative facility
        command/environment projections plus service realization metadata. A
        facility command may project either a useful-root executable or a validated
        ordinary package command of the same concrete provider. PATH is rejected as
        facility-env metadata because command-path exposure is owned by facility-cmd
        publication.

        pkg_integrate does not acquire or derive pkg-catalog context. The normal
        pkg-install path performs exact-snapshot provider conformance before calling
        integration. Integration validates the local realization structure it
        materializes through the same trusted cmd/env/service typed-part handlers,
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
        Select an installed concrete as the package/platform default and publish its
        package commands. An empty version clears that package default. A transition
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
