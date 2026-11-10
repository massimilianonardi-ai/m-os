NAME
    context.lib.sh - activate validated system-profile and package selections in the current shell

DESCRIPTION
    context is a POSIX shell function loaded by the m core shell runtime.
    It selects one installation-managed system profile and already installed package concrete
    command and published library directories, composing executable and
    non-executable shell source lookup through PATH and selected Java JAR
    directories through CLASSPATH. It does not create filesystem projections and
    does not resolve package dependencies or facility provider environments.
    It stores explicit system-profile and package dimensions for per-account
    defaults and named presets in the strict context-store library. The system
    profile registry at $m_ROOT/state/system/profile/.inventory is read-only
    to m; installation administrators provision it. A versioned, data-only
    child envelope carries the validated system identity and package selections
    and is checked against the current root, effective UID and registry.
    Logical user-state, provider, locale, migration and complete environment
    dimensions remain unimplemented.

    The caller must invoke the function in the shell whose PATH should change.
    Calling it in a pipeline, subshell or command substitution changes only
    that child environment.

FUNCTIONS
    context [system=<profile> | pkg=<package>@<version>[!<osarch>] | full-context=<name> ...]

        With no arguments, initialize the system profile from its persisted
        per-account preference or the validated installation-managed baseline,
        and initialize package selections from persisted defaults. If the
        account record is absent, no packages are selected. An absent or
        invalid profile inventory fails closed. The operation does not change
        system/current; m_STATE_SYS_DIR is set only in this process.

        system= selects one identity present in the validated installation
        inventory. pkg= selects one installed concrete; full-context= expands
        a saved named preset at its command-line position. Selections start
        from persisted defaults and fold left-to-right. A later system= replaces
        the prior profile; a later selection for the same package replaces its
        earlier version, and unrelated package selections remain. The most recent
        package directory appears first in the context-owned PATH block. A v1
        concrete contributes cmd and lib/sh/lib/java views; a v2 concrete
        contributes link/bin and link/lib/sh/link/lib/java views. Each selected
        concrete's shell libraries join PATH and its Java JAR view contributes
        one literal wildcard entry (<directory>/*) to CLASSPATH.

    context --set-defaults [system=<profile> | pkg=<package>@<version>[!<osarch>] ...]

        Validate the supplied system identity and complete merged package
        selection, then atomically replace only the supplied dimensions in the
        current POSIX account's defaults. Unspecified dimensions are retained.
        This operation does not change the current shell context and does not
        install packages.

    context --clear-defaults

        Remove the current POSIX account's persisted system/package defaults. This is
        idempotent, leaves the active shell context unchanged, and leaves saved
        presets intact. A later no-argument context selects the validated
        installation baseline and no packages unless package defaults are set.

    context --define-preset <name> [system=<profile> | pkg=<package>@<version>[!<osarch>] ...]

        Validate and atomically create or replace a named system/package
        selection preset under the current POSIX account. Preset names contain only ASCII
        letters, digits, underscore, dot or hyphen and begin with a letter or
        digit. Preset definitions do not change the active shell context.

    context --delete-preset <name>

        Delete one saved preset. Deleting an absent preset succeeds; the active
        shell context and other saved selections are unchanged.

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
    19   account context store missing, unsafe, malformed or inaccessible
    20   invalid or unavailable named preset
    21   account default or preset could not be atomically written
    22   account default update lock remained busy beyond the bounded wait
    23   selected system profile is invalid or absent from the managed inventory
    24   installation-managed profile inventory or selected profile is unavailable
    25   a validated context envelope could not be built

LIMITATIONS
    This is an incremental system-profile and package command/library slice of
    the broader context design. It does not yet accept logical user-state,
    facility/provider, locale, migration or inheritance-policy operands.
    The account record accepts v1 package-only data and writes v2 system/package
    data. The inherited envelope validates root, UID, profile and exact package
    selections. Packages with mutable var/ state remain tied to system/current;
    their launch fails closed when a different profile is selected.
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

    All account-record mutations (default merge/clear and preset create/delete)
    serialize through one private lock, so replacement and deletion cannot
    race another context-store mutation. If an uncatchable termination leaves
    the private update-lock directory behind, mutations fail closed after a
    bounded wait. The account owner may remove that lock and any matching
    `._defaults-owner.*` marker only after confirming no context store mutation
    is running.

DEPENDENCIES
    m_ROOT, m_PKG_DIR, optionally m_OSARCH, m_BIN_SYS_DIR and
    m_BIN_SYS_OSARCH_DIR; pkg-common.lib.sh; POSIX sh.

SEE ALSO
    core.lib.sh
    pkg-common.lib.sh
    pkg
