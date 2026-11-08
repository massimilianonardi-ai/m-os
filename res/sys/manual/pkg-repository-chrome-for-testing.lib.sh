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
    range or upstream evidence, and 2 for invalid invocation.

DEPENDENCIES
    json.lib.sh
    http-fetch
    awk

SEE ALSO
    pkg-repository-chromium.lib.sh
    pkg-repository-artifact.lib.sh
