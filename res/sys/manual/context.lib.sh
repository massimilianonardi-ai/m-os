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
    context
    context [pkg=<package>@<version>[!<osarch>] | preset=<name> ...]
    context reset
    context defaults set pkg=<package>@<version>[!<osarch>] ...
    context defaults clear
    context preset set <name> pkg=<package>@<version>[!<osarch>] ...
    context preset clear <name>

        With no arguments, replace the active context with the current
        POSIX account's saved package defaults. Missing preferences mean an
        empty package selection; they are never imported from global current
        links or package/facility defaults. `context reset` clears active
        package selections and restores the host PATH/CLASSPATH contributions.

        `context defaults set` updates only the package dimensions supplied
        and preserves other saved dimensions. `context defaults clear` removes
        persisted defaults but leaves the active context unchanged.
        `context preset set` replaces a named data-only package selection list;
        `preset=<name>` expands that list inline. `context preset clear` removes
        only the named preset. These operations do not change package defaults,
        facility defaults, consumer bindings or global current selectors.

        Account preferences are stored under
        `$m_ROOT/state/<effective-UID>/context/`. The effective UID comes from
        `id -u` and identifies only the preference owner, not the logical m
        user or an authentication principal. Records use versioned plain data,
        are never sourced as shell code, and use private 0700 directories and
        0600 files. `$m_ROOT/state` must not be group- or world-writable. A
        protected shared installation requires an administrator-provisioned
        account directory. Unsafe or unavailable storage fails closed; no
        `$HOME` fallback is used.

        `context reset` is distinct from `context defaults clear`: the former
        affects only this shell, while the latter affects future initialization.

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

        A v2 command link is revalidated at selection time: direct targets must
        remain executable within that concrete's root, and wrapper targets
        must refer to its matching cmd entry. Invalid links prevent activation
        without changing PATH, CLASSPATH or the previous selection.

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
    18   v2 installed command link target no longer satisfies its validated
         concrete-local direct or wrapper layout
    19   account default storage is unavailable or unsafe during initialization
    20   named preset is unavailable
    21   preference/preset record is unsafe or invalid
    22   preference/preset record version is unsupported
    23   preference/preset record contains an invalid line
    24   preference/preset record is empty or incomplete
    25   default clear could not remove its record
    26   preset clear could not remove its record
    27   account default update could not be committed atomically
    28   named preset update could not be committed atomically
    29   preset storage is unavailable or unsafe during activation
    30   default clear could not access account storage
    31   default clear found an unsafe preference record
    32   preset clear could not access account storage
    33   preset clear found an unsafe preset record
    34   default update could not access account storage
    35   preset update could not access account storage
    36   selected preset record is unsafe

LIMITATIONS
    This increment persists package concrete selections and named package
    presets. It does not yet apply facility/provider, system profile, logical
    user-state, locale or protected inheritance selections. It does not
    propagate a validated context envelope to child m processes. An unsupported
    context dimension fails before changing the shell or persisted records.
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
    concurrent package uninstallation or publication. Activation-time
    validation cannot prevent subsequent external mutation of a direct
    command symlink already placed on PATH; package-local materialization
    remains the immutable installation owned by pkg.

DEPENDENCIES
    m_ROOT, m_PKG_DIR, optionally m_OSARCH, m_BIN_SYS_DIR and
    m_BIN_SYS_OSARCH_DIR; pkg-common.lib.sh; POSIX sh.

SEE ALSO
    core.lib.sh
    pkg-common.lib.sh
    pkg
