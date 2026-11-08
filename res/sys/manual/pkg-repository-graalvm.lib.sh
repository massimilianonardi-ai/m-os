NAME
    pkg-repository-graalvm.lib.sh - GraalVM Community package repository adapter

DESCRIPTION
    Implements package version discovery, chronology, exact release validation
    and artifact resolution for the catalog's GraalVM Community JDK streams.

    Repository metadata contains:

        type = graalvm
        owner = graalvm
        repository = graalvm-ce-builds

    The GitHub Releases API is the release authority. Stable tag prefixes map to
    package versions as follows: graal-<version>, jdk-<version>, and
    vm-<version>. Drafts and prereleases are excluded. Release timestamps, not
    tag spelling, determine chronology. When stable tag families map to the
    same package version, the newest release record represents that version;
    older duplicate records are omitted. Unknown tag forms fail closed so a
    new upstream naming scheme cannot silently disappear from the listing.

    The adapter selects exactly one uploaded release asset matching the
    catalog's archive_regex. GitHub API asset size and SHA-256 digest are
    validated and emitted with the exact release URL. Checksum sidecars and
    assets for other operating systems are not selected.

    Initial supported targets are the catalog-declared linux-arm64,
    linux-x86_64, macos-arm64, and windows-x86_64 streams. This adapter does not
    claim support for other targets.

FUNCTIONS
    pkg_repository_list_versions <repository-dir>
        Print mapped stable GraalVM package versions in ascending GitHub release
        chronology, using all API pages.

    pkg_repository_compare_versions <repository-dir> <left> <right>
        Print -1, 0 or 1 according to official release chronology. Equal version
        strings compare locally; distinct versions require exact stable release
        records.

    pkg_repository_resolve_version <repository-dir> [version]
        Validate an exact mapped stable release, or resolve the current stable
        GitHub latest release and print its mapped package version.

    pkg_repository_resolve_artifact <repository-dir> <range-dir> <version>
        Select the unique catalog-matching binary asset and print the canonical
        name, HTTPS URL, positive byte size and SHA-256 digest descriptor.

STATUS
    Public functions return 0 on success, 1 when repository/upstream/range data
    does not satisfy the adapter contract, and 2 for invalid function invocation.
    Upstream request failures are logged with operation-specific identities:
    pkg-repository-graalvm.release-list-request-failed,
    pkg-repository-graalvm.latest-release-request-failed,
    pkg-repository-graalvm.exact-release-request-failed, or
    pkg-repository-graalvm.artifact-metadata-request-failed.

DEPENDENCIES
    json.lib.sh
    http-fetch
    awk
    sort
    wc
    tr

SEE ALSO
    pkg-install.lib.sh
    pkg-repository-github.lib.sh
