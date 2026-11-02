NAME
    core.lib.sh - establish the m shell-library loader and base runtime

DESCRIPTION
    lib/sys/sh/core.lib.sh is directly sourced by the root m bootstrap and
    by native POSIX shell commands requiring m shell functions. Its loadlib
    primitive loads base.lib.sh and context.lib.sh before returning to the caller.

FUNCTIONS
    loadlib <library-reference>
        Resolve a single reference below m_LIB_DIR, append .lib.sh and
        source the resulting readable regular shell file in this process.

        Return status:
            sourced library status  on successful source execution
            1                       wrong number of arguments
            2                       library file unavailable/unreadable

DEPENDENCIES
    m_LIB_DIR; sys/sh/base.lib.sh; sys/sh/context.lib.sh; POSIX sh.

SEE ALSO
    base.lib.sh
    context.lib.sh
