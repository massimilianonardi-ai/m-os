NAME
    pkg-repository-geoserver.lib.sh - GeoServer package repository adapter

DESCRIPTION
    Implements the complete GeoServer package repository type. Stable release
    discovery and chronology come from the official GeoServer GitHub Releases
    repository (geoserver/geoserver). The current stable endpoint is queried for
    an unversioned request; exact releases are validated by tag. Stable release
    listings are paginated, and drafts and prereleases are excluded.

    The platform independent GeoServer binary is published on SourceForge. For
    each exact version, the adapter selects only
    geoserver-<version>-bin.zip from /GeoServer/<version>/ and obtains its
    authoritative positive size and MD5 from the SourceForge RSS record matching
    the exact download URL. Other files in that directory, including Windows,
    WAR, documentation and extension artifacts, are not candidates.

    The catalog range must provide an archive_regex matching the selected binary,
    digest_type = md5, and no digest_regex. Optional typed download/metadata
    overrides are validated and applied only to their declared responsibility.
    The adapter still validates the exact GeoServer stable release before
    resolving an artifact; SourceForge metadata never determines release order.

    An optional repository/versions file is a newline-separated, duplicate-free
    ordering index. Comparisons for two indexed versions are local. When either
    version is absent from that index, the adapter obtains both stable-release
    timestamps from the official GitHub Releases API; equal timestamps fail closed
    because no distinct chronology can be established.

FUNCTIONS
    pkg_repository_list_versions <repository-dir>
        Print stable GeoServer release tags in ascending GitHub release chronology.
        The official releases API is paginated in pages of 100.

    pkg_repository_compare_versions <repository-dir> <left> <right>
        Print -1, 0 or 1 according to indexed order or official stable-release
        chronology. Equality is resolved locally; indexed comparisons do not use
        the network.

    pkg_repository_resolve_version <repository-dir> [version]
        Validate and print an exact stable release, or resolve the current stable
        version through the official GitHub latest-release endpoint.

    pkg_repository_resolve_artifact <repository-dir> <range-dir> <version>
        Validate the stable release and catalog range, then print the canonical
        artifact descriptor with exact SourceForge download URL, positive byte
        size and MD5 digest.

STATUS
    Public functions return 0 on success, 1 when repository/upstream/range data
    does not satisfy the adapter contract, and 2 for invalid function invocation.

DIAGNOSTICS
    Failed official GitHub requests emit a branch-specific error identity under
    pkg-repository-geoserver: release-list-request-failed,
    latest-release-request-failed, exact-release-request-failed,
    version-comparison-request-failed, or artifact-metadata-request-failed.
    Each record includes the operation, request URL and child status. An
    unsupported internal request operation emits
    request-operation-unsupported and returns status 2.

DEPENDENCIES
    json.lib.sh
    pkg-repository-artifact.lib.sh
    http-fetch
    awk
    sort
    wc

SEE ALSO
    pkg-repository-artifact.lib.sh
    pkg-install.lib.sh
