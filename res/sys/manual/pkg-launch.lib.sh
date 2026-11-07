NAME
    pkg-launch.lib.sh - launch integrated package commands with managed runtime state

DESCRIPTION
    pkg-launch.lib.sh validates an integrated package command, resolves package HOME
    and configuration, applies runtime environment layers and executes the real
    upstream target.

    Normal package commands use user-scoped package HOME/configuration. The trusted
    srv system-host execution path reuses the same launcher with system-scoped
    package state and State Instance equal to the service identity; this does not
    create a second package launcher or infer state scope from POSIX account identity.

    Facility dependencies are re-resolved at every launch. Resolution uses the
    consumer's configured binding when present, otherwise the configured system
    facility default, and otherwise an unambiguous compatible installed provider.
    Multiple compatible provider packages without explicit selection are rejected
    as ambiguous. A platform-independent consumer concrete uses the active m_OSARCH as
    its applicable dependency platform class; its concrete identity remains
    platform-independent. Selected provider projections are interpreted generically from
    facility-cmd and facility-env metadata; package-specific provider logic is not
    part of the launcher contract.

FUNCTIONS
    launcher <package> [<argument>...]
        Launch the integrated command identified by the invoking native shell
        script's $0 for the named package. The function resolves that pathname
        physically, validates the managed concrete/root/link target, creates
        the selected package HOME when needed and preserves caller arguments.
        Normal invocation selects user state. An internal srv system-host context
        selects system package state with the service identity as State Instance.

        When the consumer package's installed env source is evaluated,
        pkg_launch_root names the already validated canonical useful root of
        that concrete. Package env source may derive package payload paths
        from this launcher-local value; it must not use the retired
        m_COMMAND_BIN inherited command identity. This local evaluation
        context is not an exported process environment API.

        Runtime precedence is:

            consumer package environment
            selected provider facility projections
            user package environment
            exec

        Each selected provider facility command directory is prepended to PATH.
        Facility environment records are applied through pkg-provider.lib.sh
        without shell evaluation, using the same projection interpreter as global
        facility-default bootstrap environment. PATH is a valid special
        facility-env member: root/root-path entries prepend managed directories
        rather than replacing the inherited PATH.

        When m_ENV_DO_NOT_OVERRIDE is set, it must contain a nonempty list
        of valid POSIX variable names separated by single ASCII spaces.
        Every listed variable must be present in the incoming environment
        (an empty value is permitted); duplicate names and malformed lists
        fail. The launcher applies package, provider and user configuration
        normally, then gives the final target the original values of the
        listed variables. Only the delivered environment is overridden:
        HOME/state-path resolution, package identity and service context
        remain unchanged. The request is consumed and is not forwarded to
        further package launches.

        m_ENV_DO_NOT_OVERRIDE, m_PKG_LAUNCH_CONTEXT and
        m_PKG_LAUNCH_STATE_INSTANCE are control-plane variables and
        cannot be listed. Requests naming these variables fail rather
        than reintroducing a privileged service-launch context.
        An unset m_ENV_DO_NOT_OVERRIDE leaves existing launch semantics
        unchanged, including HOME selection and direct exec of the target.

        The launcher replaces the current process with the upstream command and
        therefore returns only when validation/runtime preparation fails.

    launcher_nss <package> [<argument>...]
        Browser-specific trusted package entrypoints use this variant of
        launcher to request Linux NSS CA reconciliation immediately before
        executing the real target. It preserves all normal launcher semantics.
        The sync receives the HOME actually delivered to the browser, including
        the inherited HOME preserved by a one-shot m_ENV_DO_NOT_OVERRIDE=HOME
        request for nested Electron execution. It invokes the fixed m-owned
        tls-nss-sync entrypoint and fails launch if synchronization fails.
        This is not a general callback facility or a TLS bypass.

RETURN STATUS
    2   Invalid invocation.
    1   Managed command, package state, dependency/provider resolution or runtime
        projection could not be validated/applied.
    3   Environment-preservation list malformed.
    4   Listed inherited environment variable missing.
    5   Environment-preservation list includes a launcher control variable.
    6   Trusted POSIX env executor unavailable for the requested preservation.
    7   Environment-preservation list contains duplicate names.
    8   Requested NSS trust synchronization failed; browser was not launched.
    On successful preparation, the upstream process exit status becomes the process
    exit status because launcher uses exec.

DEPENDENCIES
    The library runs in the invoking package command's native POSIX shell,
    with an initialized m environment and the required m shell libraries loaded
    by the command. It uses state-path, pkg-dependency.lib.sh and provider
    projection metadata materialized by package integration.

SEE ALSO
    pkg
    pkg-dependency.lib.sh
    pkg-provider.lib.sh
    tls-nss-sync
