NAME
    pkg-repository-podman.lib.sh - Podman macOS ARM64 package repository adapter

DESCRIPTION
    Resolves the official Podman GitHub Releases for the macOS ARM64 catalog
    package. Repository metadata is catalog scoped and contains type=podman,
    the exact current package URL, version anchor and SHA-256 digest.

    Version discovery and unversioned selection use GitHub's stable release
    endpoints. Stable tags must have the form vMAJOR.MINOR.PATCH; drafts and
    prereleases are excluded. A release-candidate tag with the exact form
    vMAJOR.MINOR.PATCH-rcNUMBER is also excluded if upstream incorrectly marks
    it as stable. Other unexpected stable tag forms fail closed. Exact version
    selection validates that the tag exists as a published stable release.
    Version comparison uses each exact release's creation/publication
    chronology. Artifact resolution validates the corresponding official
    release asset, positive size, HTTPS URL, archive name and SHA-256 digest.
    The catalog anchor result must match its declared URL and digest.

    The artifact is a macOS .pkg archive. m extracts its payload using the
    existing pkgutil expansion path; it does not run the package installer or
    configure Podman machine, launch agents or host services.

    Each metadata endpoint is requested once. HTTP transfer failures produce
    the adapter's upstream-request diagnostic. A nonzero http-fetch status
    (including HTTP API quota/rate-limit or upstream errors) is distinct from
    malformed release or asset metadata, which is rejected by adapter
    validation.

FUNCTIONS
    pkg_repository_list_versions <repository-dir>
        Print stable release tags in GitHub release chronology.

    pkg_repository_compare_versions <repository-dir> <left> <right>
        Print -1, 0 or 1 according to validated release chronology.

    pkg_repository_resolve_version <repository-dir> [version]
        Resolve the upstream stable latest release when omitted, or validate
        the requested exact stable tag.

    pkg_repository_resolve_artifact <repository-dir> <range-dir> <version>
        Print name, URL, positive size and SHA-256 digest for the official
        macOS ARM64 package asset.

STATUS
    Public functions return 0 on success, 1 when repository, range, upstream
    transfer or release data fails validation, and 2 for invalid invocation.

DEPENDENCIES
    json.lib.sh
    http-fetch
    pkgutil (macOS extraction path)

SEE ALSO
    pkg-repository-github.lib.sh
    pkg-install.lib.sh
    pkg-extract.lib.sh
