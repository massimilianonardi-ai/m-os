NAME
    pkg-depend.lib.sh - resolve package dependency installation plans

DESCRIPTION
    pkg-depend.lib.sh implements the read-only pkg depend planner used by
    pkg install before installing the returned concrete dependency identities.

    Planning resolves explicit package requests only to discover their recursive
    facility dependencies until provider selection and the dependency graph
    stabilize. Requested root packages are not part of pkg depend output unless
    the same concrete is also selected as a dependency of another request. No
    package is downloaded, extracted, integrated or installed.

    Provider selection preserves explicit intent: consumer binding precedes system
    facility default. Without a selector, already planned compatible providers are
    preferred, then compatible installed providers, then catalog providers. Multiple
    compatible provider packages are ambiguous and are not silently ranked.
    Multiple compatible installed versions of one provider package use that
    package's normal provider/default selection when it identifies one candidate.

    Catalog fallback may add a missing provider only when the compatible provider
    package is unambiguous. A provider package's repository-selected current/latest
    version is preferred when compatible; otherwise the newest compatible catalog
    range anchor is used as the concrete version.

FUNCTIONS
    pkg_depend_plan <catalog-root> <exact-concrete>|<target-osarch>...
        Each operand is one exact concrete identity and its already-selected
        dependency-consumer target osarch separated by a vertical bar. Both
        components are mandatory; the concrete's package identity is unchanged.
        This matters for a platform-independent concrete from catalog "all":
        it has no !osarch identity suffix but still plans provider dependencies
        for the target osarch of the original request.

        Resolve dependencies of these exact root/target contexts against
        the caller's immutable catalog snapshot, without another repository
        version lookup or mutable current/latest selection. The planner
        validates the selected stream/class and installed concrete or matching
        catalog range before planning.

        Return a shell-quoted operand sequence suitable for controlled POSIX
        eval/set -- consumption. Omit explicit roots unless they are also
        dependencies. This function does not initialize a catalog snapshot
        or install packages; the caller owns the snapshot lifecycle.

        The public pkg_depend command separately accepts original package
        requests and uses its own invocation-private snapshot.

    pkg_depend <package-spec>...
        Public pkg depend command implementation. Validate all request syntax before
        catalog initialization, create one invocation-private catalog snapshot,
        resolve the complete dependency closure and print only dependency concrete
        identities, one per line in dependency-first order. Explicit requested
        roots are omitted unless they are also selected dependency nodes. Every
        emitted identity is directly valid as a package operand.

        When an original request cannot be resolved, status 1 is accompanied by
        diagnostic context identifying reason=request-unresolvable, the original
        request, the default target and the internal status. When a provider bucket
        cannot be resolved, diagnostic context identifies
        reason=provider-unresolvable together with the facility, combined
        constraints, target, selector and internal status.

        Provider ambiguity remains a distinct diagnostic:
        reason=provider-ambiguous identifies the facility, combined compatibility
        constraints, target osarch and exact compatible provider candidates.

        These diagnostics refine failure context only; they do not add public
        status classes. Returns 0 on success, 1 when the dependency plan cannot be
        resolved, and 2 for invalid invocation or package-spec syntax.

DEPENDENCIES
    pkg-common.lib.sh
    pkg-catalog.lib.sh
    pkg-default.lib.sh
    pkg-provider.lib.sh
    pkg-facility.lib.sh
    pkg-dependency.lib.sh

SEE ALSO
    pkg
    pkg-catalog.lib.sh
    pkg-install.lib.sh
