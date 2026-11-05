NAME
    pkg-install.lib.sh - orchestrate recursive package installation

DESCRIPTION
    pkg-install.lib.sh implements the public pkg install command. Complete
    request-list syntax validation precedes catalog initialization, planning,
    resolution and managed-store mutation. After validation, all requested
    roots are resolved to exact concrete identities using one catalog snapshot.

    pkg_depend_plan receives those exact roots and that same initialized
    snapshot. Dependency concretes are installed first, followed by the same
    resolved roots, without independently refreshing the catalog or reselecting
    an unversioned root.

    Installed concrete dependencies are reused. An already-installed
    explicitly requested root is reported rather than replaced, including the
    configured current/default concrete identity when one exists. Other
    requested roots continue to be attempted.

FUNCTIONS
    pkg_install <package-spec>...
        Validate original requests, resolve all roots and plan recursive
        dependencies against one immutable catalog snapshot, then install
        dependency concretes before those exact roots. Return 0 for complete
        success, 1 for execution failures (including already-installed
        explicit roots), and 2 for invalid invocation or request syntax.

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
