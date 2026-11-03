NAME
    pkg-facility.lib.sh - validate facility contracts and provider realizations

DESCRIPTION
    pkg-facility.lib.sh owns provider-independent facility identity/compatibility
    parsing and the trusted conformance boundary between an exact facility contract
    and one package provider realization.

    Facility/provider definitions are inert declarations. Validation does not create
    a facility default, create a consumer binding, publish commands or export
    environment variables. Installed concrete facility declarations are also the
    source used by dependency resolution to discover installed providers; no
    separate mutable provider-index registry is authoritative.

    The generic facility contract envelope is:

        facility/<facility>/<compatibility>/<part>/...

    The current trusted part types are cmd, env and service. Their schemas and
    provider realization validation are delegated to internal type handlers.
    Unknown part types and unknown provider realization surfaces are rejected.

FUNCTIONS
    pkg_facility_compatibility_read <compatibility-variable> <definition-dir> <facility>
        Validate the facility declaration in <definition-dir>/facility and assign
        the declared compatibility for <facility> to the caller-selected variable.

        Returns 0 when the facility is declared, 1 when the facility metadata is
        invalid, 2 for invalid invocation or facility syntax, and 3 when a valid
        facility declaration does not contain the requested facility.

    pkg_facility_contract_validate <contract-dir>
        Validate one exact provider-independent facility contract directory and all
        of its supported typed parts.

        Returns 0 when the contract is valid, 1 when its structure or typed content
        is invalid, and 2 for invalid invocation.

    pkg_facility_provider_validate <catalog-root> <provider-definition-dir> <provider-root>
        Validate every facility declared by one provider definition against the
        exact contract under <catalog-root>/facility and validate the provider's
        provider realization against that contract and useful root. The v1
        layout retains facility-cmd, flat facility-env and facility-service
        members. In v2, facility-bin names a provider-specific useful-root
        directory for centrally declared command members, and/or explicitly
        declared link/bin entries bind to the exact concrete; facility-env uses
        contract-keyed variable bindings rather than repeating a NAME column.
        Each declared facility part has exactly one validated member set.
        Service start resolves to the selected concrete's link/bin entry in v2,
        while v1 retains its package cmd entrypoint behavior.
        provider-definition-dir must resolve beneath the same <catalog-root>/pkg
        tree, mechanically preserving the same-snapshot conformance boundary.

        A provider definition with no facility declaration is valid only when it
        also contains no facility-cmd, facility-bin, facility-env or
        facility-service realization.

        The function performs no provider selection and no state mutation.

        Returns 0 when the provider realization conforms, 1 when declaration,
        contract or realization data is invalid/non-conforming, and 2 for invalid
        invocation.

    pkg_facility_service_start_resolve <facility> <concrete-provider>
        Validate the installed concrete's declared facility and materialized
        facility-service start realization, then print the exact executable
        entrypoint belonging to that concrete (v1 cmd, v2 link/bin). It reads installed
        validated realization only; it does not read pkg-catalog, select a provider
        or start a process.

        Returns 0 on success, 1 for invalid/corrupt installed realization and 2 for
        invalid invocation.

DEPENDENCIES
    The library runs inside the m bootstrap environment and loads the trusted cmd,
    env and service facility-part handler libraries.

SEE ALSO
    pkg-dependency.lib.sh
    pkg-provider.lib.sh
