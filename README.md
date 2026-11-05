# m

This repository contains the technical `m` foundation: the POSIX-shell
bootstrap, `pkg`, essential commands and library facilities, technical
localization and manuals, managed public TLS-CA trust, and local services.

The initial implementation files in this checkout were imported from
`massimilianonardi-ai/rumiai-os` revision
`673df1a2d5476ad57d54c7bc7e1fc2deeaf16195`; package-only manuals
missing from that source have been added here.

`mk` and Node.js are **not** bootstrap prerequisites. The package catalog
is kept in the separate `pkg-catalog` repository and is consulted by package
operations rather than by the `m` bootstrap.

## First use of the versioned package catalog (v1 + v2)

A separate v2 repository is not needed: `pkg-catalog` already owns both
generations. The `pkg-schema-v2` branches are the current trial deployment
path; they have not been promoted to the mainlines.

In a **fresh development directory**, clone the two existing repositories,
select the local v2 catalog checkout and use the real public `m` commands:

```sh
git clone --branch pkg-schema-v2 https://github.com/massimilianonardi-ai/m-os.git
git clone --branch pkg-schema-v2 https://github.com/massimilianonardi-ai/pkg-catalog.git
cd m-os
./m osarch update
conf=$(./m state-path system sys pkg conf)
mkdir -p -- "$conf"
catalog=$(CDPATH= cd -- ../pkg-catalog && pwd -P)
printf '%s\n' "$catalog" > "$conf/catalog"
./m osarch show
./m pkg install nodejs
./m node --version
# The following also exercises the independently released technical tools:
./m pkg install mk jsc
./m pkg default mk
./m pkg default jsc
```

This selects the existing `pkg-catalog` working-tree branch via the
existing catalog-URL configuration mechanism, without changing `pkg` or
creating a new repository. The catalog cache is created by the normal
`pkg` path from that local Git checkout. Both repositories must remain
available at these relative locations during use. The catalog URL file is
tracked in this development checkout, so this setup deliberately changes
local configuration; it does **not** publish a new default for other users.

The catalog's `v1/` definitions remain available for packages without
a `v2/` definition. Packages with a v2 definition (`jq`, `nodejs`,
`ollama`, `mk` and `jsc` at this branch) use that complete v2 definition,
never a mixture of v1 and v2 descriptors. The new `mk`/`jsc` v2
catalog entries reuse their already-released `m-mk`/`m-jsc` source
archives and preserve their `nodejs =26` dependency; this new migration
has not yet completed a live installation test. Only the specific hosted v1/v2 acceptance
scenarios already recorded in `rumiai-dev` have passed; this example
is **not** evidence of an execution on the operator's host.

Live package installation requires access to upstream archives and API
endpoints. In particular, the jq v1 GitHub Releases request has previously
received an upstream HTTP 403 from a GitHub-hosted macOS runner. A transfer
failure must not be interpreted as proof of an incompatible package schema.

## First-use commands

From the root of this checkout:

```sh
./m osarch update
./m osarch show
./m manual --no-pager pkg
./m lang-set
./m pkg versions nodejs
```

The last command lists installed versions and can return nonzero when none
are installed. `./m pkg install <package>` reads the selected catalog and
requires appropriate host networking, tools and authorization.

The source checkout preserves the existing `m` state and platform-selection
contract. `osarch update` materializes the platform-specific technical paths
for the current host. There is no implicit platform mutation in bootstrap.

The current repository adapters cover GitHub, Node.js, Google Chrome's
Linux Debian repository, Chromium snapshots and shared artifact resolution.
The `pkg-schema-v2` branch additionally includes the existing Apache Maven
and Temurin adapters ported from `rumiai-os`; their full catalog-backed Java
integration is not yet validated. Other legacy adapters remain outside this
minimal technical checkout.

On Linux, managed Chrome, Chromium and Electron package commands use
`launcher_nss` to reconcile approved additional system TLS CAs into the
browser's effective HOME before launching. Browser package installation and
native browser execution still require the appropriate upstream artifacts,
host dependencies and permissions.

Operational manuals are under `res/sys/manual`. Current development
contracts and ongoing source-composition work live in `rumiai-dev`.

This is a technical foundation checkout, not a complete `rumiai-os` product
distribution. The first-stage extraction does not migrate host installations.
