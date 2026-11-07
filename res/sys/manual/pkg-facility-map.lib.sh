NAME
    pkg-facility-map.lib.sh - reconcile the derived installed facility map

DESCRIPTION
    pkg-facility-map.lib.sh builds the managed $m_ROOT/facility tree from
    installed concrete package facility declarations. The package store remains
    authoritative; this tree contains only relative symbolic links and can be
    removed and reconstructed. Facility contracts and provider selections remain
    owned by their existing catalog and state locations.

    Provider-local @latest selectors are ranked only within one
    facility/compatibility/platform-class/provider-package group through the
    provider repository adapter. Comparison uses repository metadata retained
    with installed concretes and never refreshes a catalog or makes a network
    request. If ordering cannot be established, membership links remain available
    and no guessed @latest link is published. The optional facility default link
    mirrors the configured system provider default only when that exact concrete
    belongs to the group.

FUNCTIONS
    pkg_facility_map_reconcile
        Rebuild the managed facility map from installed concrete package metadata.
        Creates one <package>@<version> relative link for every installed concrete
        declaring the exact facility compatibility, provider-local @latest links
        only when adapter ordering is established, and optional system default
        projections. A malformed installed declaration or an unsafe existing map
        root fails closed before publication. Concurrent reconciliations are
        serialized by a temporary lock. Repository-order uncertainty is
        reported and omits only the affected @latest selector. The derived map is
        staged and replaced with rollback of the previous tree if publication
        fails.

        Returns 0 when the derived map is published, 1 when installed metadata,
        filesystem state or publication is invalid, and 2 for invalid invocation.

DEPENDENCIES
    pkg-common.lib.sh
    pkg-facility.lib.sh
    pkg-catalog.lib.sh
    pkg-provider.lib.sh
    state-path
    POSIX shell utilities: awk, cat, ln, mkdir, mv, rm, sed and sort

SEE ALSO
    pkg-facility.lib.sh
    pkg-integration.lib.sh
    pkg-provider.lib.sh
