NAME
    pkg-install.lib.sh - orchestrate recursive package installation

DESCRIPTION
    pkg-install.lib.sh implements the public pkg install command. Complete
    request-list syntax validation precedes catalog initialization, planning,
    resolution and managed-store mutation. After validation, all requested
    roots are resolved to exact concrete identities using one catalog snapshot.

    pkg_depend_plan receives each exact root together with its original
    target osarch and that same initialized snapshot. For a platform-independent
    "all" root, the dependency-consumer target is preserved independently of
    its suffix-free concrete identity. Dependency concretes are installed
    first, followed by the same resolved roots, without independently refreshing
    the catalog or reselecting an unversioned root.

    Installed concrete dependencies are reused. An already-installed
    explicitly requested root is reported rather than replaced, including the
    configured current/default concrete identity when one exists. Other
    requested roots continue to be attempted. A root first installed as a
    dependency of another requested root in the same batch is fulfilled
    and not classified as a pre-existing root.

FUNCTIONS
    pkg_install <package-spec>...
        Validate original requests, resolve all roots and plan recursive
        dependencies against one immutable catalog snapshot, then install
        dependency concretes before those exact roots. Return 0 for complete
        success, 1 for execution failures (including already-installed
        explicit roots), and 2 for invalid invocation or request syntax.
        Catalog initialization failures identify the invalid schema; an
        incomplete versioned schema emits `pkg-catalog.schema-root-incomplete`
        and returns status 1.

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
        Resolve one request against the current installation snapshot,
        download/extract/validate/integrate it if absent, and reuse an already
        installed valid concrete with status 0. The public pkg_install
        entrypoint separately rejects already-installed explicit roots.

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
