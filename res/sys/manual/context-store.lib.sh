NAME
    context-store.lib.sh - private account-scoped context record storage

DESCRIPTION
    This internal POSIX shell library provides strict, account-owned storage
    primitives for context defaults and named presets. It is loaded by
    context.lib.sh after pkg-common.lib.sh. It exposes no public callable
    functions; every function name begins with an underscore and is private to
    the implementation.

    Records are bounded, versioned data containing only validated package
    selection operands. They are never sourced or evaluated. The effective UID
    is obtained with the system command path, independently from the logical
    user dimension in the active context. Storage is beneath
    $m_ROOT/state/<effective-UID>/context. The shared state parent must be a
    real directory owned by root or the effective account and must not be
    group/world writable. Account and context directories must be owned by the
    effective account with mode 0700; record files must be owned by that
    account with mode 0600. Symlinks and unsupported permissions fail closed.

    A user-owned installation can create only its own account/context leaves
    below a trusted writable state parent. A shared or read-only installation
    must have the account leaf provisioned by its installer or account
    lifecycle administrator. These functions never elevate privileges or
    loosen parent permissions. Writes stage a private file in the target
    directory and atomically rename it into place. Default read/merge/write
    operations use a private atomic directory lock so concurrent updates retain
    changes to unspecified package selections. A lock left by an uncatchable
    process termination fails closed; the account owner may remove it and any
    matching `._defaults-owner.*` marker only after confirming no update is
    active. Empty reads and deletes do not create storage directories.

FUNCTIONS
    No public functions. Private implementation helpers are not callable API.

RETURN STATUS
    Private helper return values are consumed only by context.lib.sh and are
    not a supported external interface.

LIMITATIONS
    The record format currently supports exact package concrete selectors for
    the initial command/library context phase. It does not yet resolve system
    profiles, logical user state, providers, locale, platform preferences or
    child-context envelopes. Account-store primitives do not authenticate the
    process or grant service, CA or host-administrative authority.

DEPENDENCIES
    POSIX sh; system id, ls, awk, wc, mkdir, chmod, mv, rm and sleep utilities
    through the POSIX default command path; pkg-common.lib.sh for package
    selector parsing.

SEE ALSO
    context.lib.sh
    pkg-common.lib.sh
