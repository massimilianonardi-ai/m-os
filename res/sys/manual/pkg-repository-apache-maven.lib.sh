NAME
    pkg-repository-apache-maven.lib.sh - Apache Maven 4 package repository adapter

DESCRIPTION
    Implements package version discovery, ordering, exact release validation and
    artifact resolution for Apache Maven 4 distributions.

    Repository metadata contains:

        type = apache-maven

    Supported versions use the adapter's Maven 4 release grammar, including
    numeric release-candidate suffixes. Available releases are discovered from
    the current Apache Maven 4 distribution index and ordered by that grammar.

    Artifact resolution selects the canonical apache-maven-<version>-bin.tar.gz
    distribution, requires digest_type = sha512, obtains the authoritative
    digest from Apache's digest-only SHA-512 sidecar and obtains a positive byte
    size from the selected download URL.

    The artifact-name/download-URL template mechanism and checksum-sidecar
    mechanism are delegated to pkg-repository-artifact.lib.sh. The apache-maven
    repository type remains a
    complete adapter; this internal reuse does not require an artifact override
    in catalog metadata.

FUNCTIONS
    pkg_repository_list_versions <repository-dir>
        Print available supported Maven 4 releases in ascending adapter version
        order.

    pkg_repository_compare_versions <repository-dir> <left> <right>
        Print -1, 0 or 1 according to Maven 4 version ordering after validating
        the compared releases against the current distribution authority.

    pkg_repository_resolve_version <repository-dir> [version]
        Validate and print an exact available release, or resolve and print the
        latest available supported release when version is omitted.

    pkg_repository_resolve_artifact <repository-dir> <range-dir> <version>
        Print the canonical package artifact descriptor containing artifact
        name, Apache download URL, positive byte size and SHA-512 digest.

STATUS
    Public functions return 0 on success, 1 when repository/upstream/range data
    does not satisfy the adapter contract, and 2 for invalid function invocation.

DEPENDENCIES
    pkg-repository-artifact.lib.sh
    http-fetch
    awk
    sort
    tr
    wc

SEE ALSO
    pkg-repository-artifact.lib.sh
    pkg-install.lib.sh
