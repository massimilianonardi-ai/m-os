NAME
    pkg-repository-chrome-for-testing.lib.sh - Chrome for Testing Stable adapter

DESCRIPTION
    Implements the chrome-for-testing repository type for the catalog's
    Stable Linux ARM64 stream. The repository descriptor must contain exactly:

        type = chrome-for-testing
        channel = Stable
        platform = linux-arm64

    Unversioned resolution reads the official Chrome for Testing
    LATEST_RELEASE_STABLE endpoint. Exact versions and current Stable are then
    checked against the official Chrome for Testing public Cloud Storage object
    metadata. The metadata response's object name, positive size and Base64
    md5Hash are validated; md5Hash is converted to lowercase hexadecimal for
    the generic verified downloader. Artifact bytes are fetched from the
    corresponding official chrome-for-testing-public object URL.

FUNCTIONS
    pkg_repository_compare_versions <repository-dir> <left> <right>
        Compare four canonical numeric Chrome version components locally and
        print -1, 0 or 1.

    pkg_repository_resolve_version <repository-dir> [version]
        Return the current Stable version, or validate and return the exact
        requested version when its Linux ARM64 object metadata exists.

    pkg_repository_resolve_artifact <repository-dir> <range-dir> <version>
        Validate the catalog's archive_regex and MD5 requirement, then print
        the canonical artifact name, HTTPS URL, positive size and MD5 digest.

STATUS
    Public functions return 0 on success, 1 for invalid descriptor, version,
    range or upstream evidence, and 2 for invalid invocation. Metadata failures
    emit distinct pkg-repository-cft diagnostic identities for fetch, JSON,
    object-name, size-type, size-value, MD5-type and MD5-encoding failures;
    public status remains 1.

DIAGNOSTICS
    pkg-repository-cft.metadata-fetch-failed
    pkg-repository-cft.metadata-json-invalid
    pkg-repository-cft.metadata-name-invalid
    pkg-repository-cft.metadata-name-mismatch
    pkg-repository-cft.metadata-size-type-invalid
    pkg-repository-cft.metadata-size-value-invalid
    pkg-repository-cft.metadata-md5-type-invalid
    pkg-repository-cft.metadata-md5-encoding-invalid

INTERNAL METADATA FAILURE STATUS
    The private metadata resolver returns distinct local statuses: 1 invalid
    invocation, 2 invalid repository descriptor, 3 invalid version, 4 metadata
    fetch failure, 5 invalid metadata JSON, 6 invalid object-name type, 7 object
    name mismatch, 8 invalid size type, 9 invalid size value, 10 invalid MD5
    type, and 11 invalid Base64 MD5. Public functions map these failures to the
    documented status 1.

DEPENDENCIES
    json.lib.sh
    http-fetch
    awk

SEE ALSO
    pkg-repository-chromium.lib.sh
    pkg-repository-artifact.lib.sh
