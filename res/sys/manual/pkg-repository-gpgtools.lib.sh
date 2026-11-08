NAME
    pkg-repository-gpgtools.lib.sh - bounded GPGTools package repository adapter

DESCRIPTION
    Implements the `gpgtools` repository type for the catalog-declared
    `macgpg/macos-arm64` stream. The official GPGTools Nightlies page is the
    live authority for the current “Latest Hotfix” version, exact DMG URL and
    SHA-256 digest. The DMG response supplies the positive byte size through
    the normal `http-fetch -l` interface.

    The catalog's repository/version, url and digest identify its exact pinned
    release. The adapter supports that pin and the current official Latest
    Hotfix. It does not claim a historical version index: unknown historical
    versions and ordering outside the catalog pin/current latest pair fail
    closed. If the upstream page no longer has the expected shape, resolution
    fails rather than returning a stale catalog value as latest.

FUNCTIONS
    pkg_repository_list_versions <repository-dir>
        Print the catalog-pinned release and current upstream Latest Hotfix in
        release order, suppressing the duplicate when both are identical. This
        is the bounded known-version set, not a full GPGTools history.

    pkg_repository_compare_versions <repository-dir> <left> <right>
        Print -1, 0 or 1 for equality or the catalog-pin/current-latest pair.
        Other comparisons fail closed because the official index does not
        expose sufficient history.

    pkg_repository_resolve_version <repository-dir> [version]
        Validate and print the catalog-pinned version, or resolve and print the
        current official Latest Hotfix version when omitted. An exact version
        outside the catalog pin is accepted only when it is the current
        official Latest Hotfix.

    pkg_repository_resolve_artifact <repository-dir> <range-dir> <version>
        Print the canonical artifact descriptor for the catalog pin or current
        latest. The version, URL, archive_regex, SHA-256 digest and positive
        byte size must all validate. For the pinned version, URL and digest
        come from the immutable catalog snapshot; for current latest, they come
        from the exact official Latest Hotfix row.

STATUS
    Public functions return 0 on success, 1 when repository/upstream/range data
    does not satisfy this adapter's bounded contract, and 2 for invalid
    function invocation.

DEPENDENCIES
    http-fetch

SEE ALSO
    pkg-repository-artifact.lib.sh
    pkg-install.lib.sh
