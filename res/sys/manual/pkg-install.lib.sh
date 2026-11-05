NAME
    pkg-install.lib.sh - orchestrate recursive package installation

DESCRIPTION
    pkg-install.lib.sh implements the public pkg install command. It validates the
    complete original request list before catalog initialization, dependency
    planning or package installation. Only after every request is syntactically
    valid does it initialize one installation catalog snapshot and call pkg depend
    with the untouched original request list.

    Dependency concrete identities returned by pkg depend are prepended to the
    original request list. The dependency entries are already concrete; original
    roots deliberately retain their requested form and are resolved by
    pkg_install_one against the same installation catalog snapshot when their turn
    in the install sequence is reached. This preserves one dependency-planning
    authority while still installing dependencies before requested roots.

    pkg install owns request installation, not dependency discovery. Each package
    selected for installation is resolved to its package range, its artifact is
    downloaded and extracted, provider conformance is validated, and the package
    is integrated. An already installed concrete dependency is reused directly
    without redundant catalog resolution.

FUNCTIONS
    pkg_install <package-spec>...
        Validate every original package specification first. If any request is
        syntactically invalid, fail before dependency planning and install nothing.
        Otherwise initialize the catalog snapshot, invoke pkg depend exactly once
        with the untouched original requests, prepend the returned dependency
        concretes to those original requests, and install the resulting sequence.

        A dependency-planning failure after valid request syntax is an execution
        failure, not an invalid-arguments condition. Diagnostics emitted by
        pkg depend remain visible before the top-level pkg-install
        dependency-unresolvable failure.

    pkg_install_validate <package-spec>...
        Check the syntax of a nonempty list of package requests without
        consulting a catalog or changing package state. Return success only
        when every operand is syntactically valid; otherwise return nonzero.
        This does not check artifact availability or dependency satisfaction.

    pkg_install_resolve_one <package-spec>
        Resolve one request into an exact concrete identity and print it on
        success. An already installed matching concrete, or an installed
        current concrete for an unversioned request, may satisfy resolution
        without upstream discovery. Otherwise consult the selected catalog
        stream and its repository adapter. Return nonzero on failure.
        Requires an initialized package-install context, including its
        selected catalog snapshot and target m_OSARCH.

    pkg_install_resolve <package-spec>...
        Resolve a nonempty request list through pkg_install_resolve_one and
        print the resulting exact concrete identities as one shell-quoted,
        space-separated argument sequence. This is shell argument text, not
        a newline-delimited list or an installed-package inventory.
        Return nonzero if any request cannot be resolved or quoted.
        Requires the same initialized package-install context.

    pkg_install_one <package-spec>
        Resolve one package specification against the current installation catalog
        snapshot and install its concrete identity unless that concrete is already
        installed.

DEPENDENCIES
    pkg-common.lib.sh
    pkg-catalog.lib.sh
    pkg-depend.lib.sh
    pkg-download.lib.sh
    pkg-extract.lib.sh
    pkg-integration.lib.sh

SEE ALSO
    pkg
    pkg-depend.lib.sh
    pkg-catalog.lib.sh
