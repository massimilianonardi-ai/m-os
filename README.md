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

## First use of the current package catalog (v1 + v2)

A separate v2 repository is not needed: `pkg-catalog` owns both generations,
and v2 is promoted to `pkg-catalog/main`. The runtime support is integrated
in `m-os/master`. Use these mainline revisions for current development; the
`pkg-schema-v2` branches are historical feature branches.

In a **fresh development directory**, clone the two existing repositories,
select the local catalog checkout and use the real public `m` commands:

```sh
git clone --branch master https://github.com/massimilianonardi-ai/m-os.git
git clone --branch main https://github.com/massimilianonardi-ai/pkg-catalog.git
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
a `v2/` definition. Packages with a v2 definition use that complete v2
definition, never a mixture of v1 and v2 descriptors. The promoted `mk` and
`jsc` definitions reuse their released `m-mk` and `m-jsc` source archives and
retain the `nodejs =26` dependency. This documented command sequence is an
operator procedure, not evidence that it was run on your host. Revision-pinned
hosted evidence for the merged runtime/catalog and public package consumers is
recorded in the `rumiai-dev` validation handoff; it does not claim privileged
host-system service validation or full M01–M15 acceptance.

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

### Portable services in a source checkout

`srv start` and `srv stop` use the native supervisor built for the current
host. A source-checkout user must have a C compiler and run
`./tools/build-srv-supervisor.sh` once before using portable services. The
helper is written to `libexec/sys/srv-supervisor` in this checkout; `m`
bootstrap remains POSIX-shell-only and never invokes a compiler. A complete
RumiAI installation must package a helper built for each supported host and
architecture at the same path.

To build and validate a relocatable technical `m` distribution for the current
Linux or macOS host, use:

```sh
./tools/package-m-distribution.sh
```

The command packages the exact clean Git revision as
`dist/m-os-<osarch>.tar.gz`, builds the native supervisor inside that package,
records the source commit and target in `M-DISTRIBUTION`, and exercises the
extracted archive's public supervisor checks. It requires a C compiler and `tar`
with gzip support. The archive is a technical `m` source distribution, not a full
branded RumiAI-OS installer.

The current repository adapters cover GitHub, Node.js, Google Chrome's
Linux Debian repository, Chromium snapshots, shared artifact resolution,
Apache Maven and Temurin. Hosted V2 validation includes real Java/Maven
consumers on the merged runtime/catalog revisions; see the validation handoff
for exact run IDs and scope. Other legacy adapters remain outside this
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
