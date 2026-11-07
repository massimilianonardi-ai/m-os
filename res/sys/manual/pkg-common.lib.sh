NAME
    pkg-common.lib.sh - common package identity validation helpers

DESCRIPTION
    pkg-common.lib.sh provides shared syntax validation for package names,
    versions, supported osarch values, package requests and fully resolved
    package concrete identities. Its internal helpers also read the installed
    schema marker and validate v2 command target containment for package
    default publication and shell-local context selection.

FUNCTIONS
    pkg_name_valid <package>
        Return success when package is a valid package name.

        Return 1 when the function is invoked with the wrong number of operands
        and 2 when the supplied package name is invalid.

    pkg_version_valid <version>
        Return success when version is a valid package version.

        Return 1 when the function is invoked with the wrong number of operands
        and 2 when the supplied version is invalid.

    pkg_osarch_valid <osarch>
        Return success when osarch is one of the supported package target
        identities.

        Return 1 when the function is invoked with the wrong number of operands
        and 2 when the supplied osarch is invalid.

    pkg_name_version_osarch_valid <package> <version> [<osarch>]
        Validate the package name and version and, when non-empty, the optional
        osarch.

        Return 1 when fewer than package and version operands are supplied,
        2 when the package name is invalid, 3 when the version is invalid and
        4 when a non-empty osarch is invalid.

    pkg_request_read <name-variable> <version-variable> <osarch-variable> <request>
        Validate and split one package request of the form:

            <package>[@<version>][!<osarch>]

        The version and osarch outputs are empty when omitted.

    pkg_concrete_read <name-variable> <version-variable> <osarch-variable> <concrete>
        Validate and split one concrete identity of the form:

            <package>@<version>[!<osarch>]

        Unlike pkg_request_read, a concrete identity requires a version.

        For both read functions the first three operands are distinct valid shell
        identifiers. On success the function assigns the package name, version
        and osarch to those variables. Destination variables are assigned only
        after the complete input has been validated. The functions write no
        result to standard output.

RETURN STATUS
    pkg_request_read and pkg_concrete_read return 0 on success, 1 when their
    invocation arity or supplied package identity/request is invalid, and 2 when
    destination variable names are invalid or duplicated.

    Validator-specific non-zero statuses are documented with each validator
    above.
