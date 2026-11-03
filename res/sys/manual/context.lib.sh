NAME
    context.lib.sh - activate package command selections in the current shell

DESCRIPTION
    context is a POSIX shell function loaded by the m core shell runtime.
    This initial implementation selects already installed package concrete
    command and published library directories, composing executable and
    non-executable shell source lookup through PATH and selected Java JAR
    directories through CLASSPATH. It does not create filesystem projections and
    does not resolve package dependencies or facility provider environments.

    The caller must invoke the function in the shell whose PATH should change.
    Calling it in a pipeline, subshell or command substitution changes only
    that child environment.

FUNCTIONS
    context [pkg=<package>@<version>[!<osarch>] ...]

        With no arguments, clear the current context-owned package command
        selections and remove the previously published command/library block
        from PATH and Java JAR contributions from CLASSPATH.

        With one or more pkg= arguments, select each installed concrete.
        Arguments are evaluated left-to-right. A later selection for the same
        package name replaces the earlier one; selections for other package
        names are retained across calls. The most recently selected package
        directory appears first in the context-owned PATH block. A v1 concrete
        contributes cmd and lib/sh/lib/java views; a v2 concrete contributes
        link/bin and link/lib/sh/link/lib/java views. Each selected concrete's
        shell libraries join PATH and its Java JAR view contributes one literal
        wildcard entry (<directory>/*) to CLASSPATH.

        An osarch-qualified concrete must match the current m_OSARCH.
        A generic concrete has no osarch suffix. The installed concrete and
        any published schema-specific command or library view directories must
        be real directories. Library-only installed concretes are supported;
        missing command views do not require invented links.

        Commands from two selected package directories must not collide with
        each other or with the protected m sys/sys-osarch commands. Collision
        causes failure, not an implicit winner. Selected package directories
        are prepended ahead of inherited PATH entries, which remain available.

        Selected shell libraries must be non-executable *.lib.sh links and
        selected Java libraries *.jar links; duplicate library leaf names
        of the same runtime across selected packages are rejected. A shell
        source library name must also not collide with an executable name
        from the selected packages or protected m system command roots.

        The function removes only its previously published PATH and CLASSPATH
        blocks when changing selection. Other edits are retained. A pre-existing
        unset or set-but-empty CLASSPATH is restored exactly on reset. If either
        published block is lost or rewritten, activation fails without changing
        PATH, CLASSPATH or the previous active selection.

        Selection is validated before PATH, CLASSPATH or active selection state
        changes. Applying the same selection repeatedly does not grow either
        search path. Shell source files can be loaded with POSIX dot lookup;
        m-owned loadlib/loadsyslib still use their established contract.

RETURN STATUS
    0    selection applied
    1    m runtime variables unavailable
    2    unsupported/invalid context operand
    3    invalid package concrete identity
    4    explicit package osarch incompatible with active m_OSARCH
    5    selected concrete unavailable
    6    previous PATH-owned command block no longer identifiable
    7    package store path cannot be represented as a PATH entry
    8    selected concrete disappeared before the PATH application
    9    invalid concrete schema or non-executable command view
    10   package command collides with a protected m core command
    11   selected packages expose a colliding command name
    12   invalid selected library view directory
    13   invalid selected library symlink or library type
    14   selected packages export the same library leaf name
    15   previous context-owned CLASSPATH block unavailable or modified
    16   PATH is readonly in the invoking shell
    17   CLASSPATH is readonly in the invoking shell
    18   invalid concrete schema for a selected view

LIMITATIONS
    This is the first package-command and library selection increment of the broader
    context design. It does not yet accept facility, provider, profile,
    locale, user/system, full-context or inheritance-policy operands.
    Only sh and Java ordinary library search views are supported; other
    runtimes need their own defined import/loader semantics. CLASSPATH may be
    overridden by explicit Java -cp or launcher-specific class loading;
    wildcard expansion order within one directory is unspecified.
    Provider environment/service coherence and child-context propagation
    are still handled by their existing owners, not by this function.
    In particular v2 contract-keyed provider environment values are
    materialized by pkg and applied by the existing pkg-provider machinery;
    activating context does not apply a second facility environment.
    The function makes no claim to an atomic filesystem snapshot during
    concurrent package uninstallation or publication.

DEPENDENCIES
    m_ROOT, m_PKG_DIR, optionally m_OSARCH, m_BIN_SYS_DIR and
    m_BIN_SYS_OSARCH_DIR; pkg-common.lib.sh; POSIX sh.

SEE ALSO
    core.lib.sh
    pkg-common.lib.sh
    pkg
