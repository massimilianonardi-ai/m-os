NAME
    pkg-repository-temurin.lib.sh - Eclipse Temurin JDK repository adapter

DESCRIPTION
    Implements version discovery, exact release selection, version ordering and
    artifact resolution for the Eclipse Temurin JDK through the Adoptium API.

    Repository metadata contains:

        type = temurin
        os = linux | mac | windows
        architecture = x64 | aarch64
        feature_versions = ascending, distinct positive Java feature versions

    The supported OS and architecture pairs are linux/x64, linux/aarch64,
    mac/x64, mac/aarch64 and windows/x64. Release enumeration uses the upstream
    general-availability JDK assets API for the configured feature versions,
    platform and HotSpot/Eclipse distribution. Version strings follow the
    adapter's numeric release grammar, including a +build component.
    Comparison uses order from the validated upstream release listing.

    Artifact resolution requires an exact available release, a matching
    archive_regex and digest_type = sha256. It obtains the authoritative
    checksum from the Adoptium version checksum endpoint and a positive byte
    size from the corresponding binary URL. The output records name, HTTPS URL,
    size and SHA-256 digest for the ordinary package downloader.

    This adapter is selected through the repository type descriptor. It does
    not change the public pkg command, installation policy or package schema.

FUNCTIONS
    pkg_repository_list_versions <repository-dir>
        Print available releases from the configured Java feature lines.

    pkg_repository_compare_versions <repository-dir> <left> <right>
        Print -1, 0 or 1 according to the validated upstream listing order.

    pkg_repository_resolve_version <repository-dir> [version]
        Select the last discovered available release, or validate and print
        the requested exact release.

    pkg_repository_resolve_artifact <repository-dir> <range-dir> <version>
        Validate the exact release and range descriptors, and print the
        artifact name, download URL, positive size and SHA-256 digest records.

STATUS
    Public functions return 0 on success, 1 when repository/range/upstream
    data does not meet the contract, and 2 for invalid invocation.

DEPENDENCIES
    json.lib.sh
    http-fetch

SEE ALSO
    pkg-repository-apache-maven.lib.sh
    pkg-repository-artifact.lib.sh
    pkg-catalog.lib.sh
    pkg-install.lib.sh
