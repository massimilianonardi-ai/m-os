NAME
    pkg-facility-env.lib.sh - internal env facility-part conformance handler

DESCRIPTION
    pkg-facility-env.lib.sh implements the trusted internal validation semantics for
    the env typed facility part. It validates realization structure and descriptors
    using the root, root-path and literal grammar, and composes that validation with
    exact contract membership for provider conformance. Package integration reuses
    the same internal realization validation without acquiring catalog context.

    For v1, provider realizations are flat sorted NAME<TAB>descriptor records.
    For v2, the central facility contract supplies the variable-name set;
    the provider binds each declared name under facility-env/<facility>/<name>
    using one typed descriptor line, except PATH, which accepts multiple
    ordered root/root-path lines. Missing, duplicate or undeclared variable
    bindings are invalid. Integration turns validated v2 bindings into the
    same installed flat realization consumed by pkg-provider; context does not
    interpret or apply provider environments independently.

    PATH is a valid special env contract member. Provider realizations may contain
    multiple PATH records, but PATH accepts only root and root-path descriptors;
    a PATH root-path target must resolve to a directory inside the provider root.
    Literal PATH replacement is rejected. Ordinary environment variables remain
    single-record realization members.

    The library validates declarations only; it does not export variables, select a
    provider or modify bootstrap state.

FUNCTIONS
    This library exposes no public callable functions.

SEE ALSO
    pkg-facility.lib.sh
