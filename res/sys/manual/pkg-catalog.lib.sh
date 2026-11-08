NAME
    pkg-catalog.lib.sh - package catalog snapshot and lookup operations

DESCRIPTION
    pkg-catalog.lib.sh owns acquisition and lookup of the package catalog used by
    package operations. It keeps catalog mechanics out of package request grammar
    and installation orchestration.

FUNCTIONS
    pkg_catalog_installed_versions_compare <repository-dir> <left-version> <right-version>
        Compare already-installed concrete versions using retained repository
        metadata without refreshing the catalog or querying the network. The
        repository adapter must support local ordering; a GitHub adapter additionally
        requires both versions in its retained versions index. Prints -1, 0 or 1.
        Returns 0 for a proven comparison, 1 when ordering cannot be established,
        and 2 for invalid invocation.

    pkg_catalog_init <catalog-variable> <head-variable> <work-root> <cache-root>
        Read the configured catalog repository, update or create the cached Git
        checkout, resolve one exact HEAD and export that revision into
        <work-root>/catalog.

        On success <catalog-variable> receives the v1 definition directory
        under the exported snapshot (or the original root for an explicitly
        unversioned legacy catalog) and <head-variable> receives the exact
        catalog Git revision. v1 preserves the old pkg/ and facility/ schemas;
        a catalog with both versioned and flat roots is invalid. The destination variable
        names must be distinct valid shell identifiers. <work-root> and
        <cache-root> must be existing real directories and <work-root>/catalog
        must not already exist. A snapshot containing both the versioned v1 root
        and flat legacy pkg/facility roots fails with status 3 and a
        schema-roots-conflict diagnostic. Catalog refresh command output is kept
        off standard output; results are returned through the assigned variables.

    pkg_catalog_stream_resolve <stream-variable> <identity-osarch-variable> <catalog> <package> <target-osarch>
        Resolve one package stream from an already materialized catalog snapshot.
        The target-osarch stream is preferred when present; otherwise the all
        stream is used.

        On success <stream-variable> receives the selected stream path.
        <identity-osarch-variable> receives <target-osarch> for a platform
        specific stream or the empty string for an all stream.

    pkg_catalog_request_resolve <concrete-variable> <target-variable> <catalog> <package-spec> <default-target>
        Resolve one package request against an already materialized catalog
        snapshot. An explicit osarch in <package-spec> overrides <default-target>;
        otherwise <default-target> selects the target stream and may fall back to
        the platform-independent all stream.

        The requested version is resolved exactly when present; otherwise the
        repository adapter selects its normal current/latest version. On success
        <concrete-variable> receives the exact concrete identity and
        <target-variable> receives the effective target osarch used for dependency
        planning.

    pkg_catalog_version_resolve <version-variable> <stream> [<requested-version>]
        Resolve a repository version through the adapter owned by one catalog
        stream. With <requested-version>, resolution must return that exact version;
        without it, the repository adapter selects its normal current/latest
        version. Failure of live latest discovery is not silently replaced
        with a historical version. If a valid repository/versions index exists,
        the diagnostic suggests an explicitly pinned known version for a
        separate installation attempt; artifact availability is not guaranteed.
        On success <version-variable> receives the validated version.

    pkg_catalog_range_resolve <range-variable> <catalog> <concrete>
        Resolve an already concrete package identity to its applicable catalog
        range directory in the supplied snapshot.

        The concrete identity determines the exact stream: identities carrying
        !<osarch> use that stream, while platform-independent identities use all.
        Range numbering must be contiguous from n0001 and anchors must be strictly
        increasing according to the stream repository adapter. Anchor ordering is
        validated once in ascending range order; after validation, selection walks
        from the newest range toward the oldest and stops at the first anchor not
        newer than the concrete version. This preserves range semantics while
        avoiding comparisons against older anchors that cannot affect the result.

        On success <range-variable> receives the selected range path.

RETURN STATUS
    0   Success.
    1   Catalog state, lookup, repository metadata or requested value is invalid
        or cannot be resolved.
    2   Invalid function invocation.
    3   Versioned and legacy catalog schema roots are both present.

DEPENDENCIES
    pkg-common.lib.sh
    state-path
    git
    tar
    the repository adapter selected by each catalog stream
