NAME
    context.lib.sh - activate package command selections in the current shell

DESCRIPTION
    context is a POSIX shell function loaded by the m core shell runtime.
    This initial implementation selects already installed package concrete
    command directories and publishes their ordered command lookup through
    the current shell PATH. It does not create filesystem projections and
    does not resolve package dependencies or facility provider environments.

    The caller must invoke the function in the shell whose PATH should change.
    Calling it in a pipeline, subshell or command substitution changes only
    that child environment.

FUNCTIONS
    context [pkg=<package>@<version>[!<osarch>] ...]

        With no arguments, clear the current context-owned package command
        selections and remove the previously published command block from PATH.

        With one or more pkg= arguments, select each installed concrete.
        Arguments are evaluated left-to-right. A later selection for the same
        package name replaces the earlier one; selections for other package
        names are retained across calls. The most recently selected package
        directory appears first in the context-owned PATH block.

        An osarch-qualified concrete must match the current m_OSARCH.
        A generic concrete has no osarch suffix. The installed concrete and
        its cmd directory must exist as real directories.

        Commands from two selected package directories must not collide with
        each other or with the protected m sys/sys-osarch commands. Collision
        causes failure, not an implicit winner. Selected package directories
        are prepended ahead of inherited PATH entries, which remain available.

        The function removes only its previously published PATH block when
        changing selection. Other PATH edits are retained. If the published
        block cannot be identified because it was removed or rewritten, the
        operation fails without changing PATH or the previous selection.

        Selection is validated before PATH or active selection state changes.
        Applying the same selection repeatedly does not grow PATH.

RETURN STATUS
    0    selection applied
    1    m runtime variables unavailable
    2    unsupported/invalid context operand
    3    invalid package concrete identity
    4    explicit package osarch incompatible with active m_OSARCH
    5    selected concrete or cmd directory unavailable
    6    previous PATH-owned command block no longer identifiable
    7    package store path cannot be represented as a PATH entry
    8    selected concrete disappeared before the PATH application
    9    invalid or non-executable package command
    10   package command collides with a protected m core command
    11   selected packages expose a colliding command name

LIMITATIONS
    This is the first package-command selection increment of the broader
    context design. It does not yet accept facility, provider, profile,
    locale, user/system, full-context or inheritance-policy operands.
    Provider environment/service coherence and child-context propagation
    are still handled by their existing owners, not by this function.
    The function makes no claim to an atomic filesystem snapshot during
    concurrent package uninstallation or publication.

DEPENDENCIES
    m_ROOT, m_PKG_DIR, optionally m_OSARCH, m_BIN_SYS_DIR and
    m_BIN_SYS_OSARCH_DIR; pkg-common.lib.sh; POSIX sh.

SEE ALSO
    core.lib.sh
    pkg-common.lib.sh
    pkg
