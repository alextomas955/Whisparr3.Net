# Changelog

Every release of Whisparr3.Net is recorded here, newest first. The stability policy the version
numbers refer to is at the bottom of this file and does not move.

## 0.1.0

The first release. Not yet published to nuget.org.

- Covers all 272 operations the Whisparr 3 (Eros) API declares, generated from Whisparr's own
  OpenAPI specification. The one malformed root path is excluded.
- Targets `net8.0` and `net10.0`, with an assembly and an XML documentation file shipped for each.
- One registration entry point, `AddWhisparr3`, which validates the base URL and the API key and
  registers nothing until both pass.
- One typed error, `Whisparr3ApiException`, carrying the status, the route template, the request
  URI and the raw body, and distinguishing a failed request from a success with no readable body.
- `EnsureSuccess` classifies a response, which the generated success accessor does not.
- 92 of the 272 operations return no value, because the specification declares no response content
  for them. They are listed with their cause in [docs/SURFACE.md](docs/SURFACE.md), along with the
  six operations that are generated but not useful from C#.

## Public API stability policy

Version numbers follow semantic versioning, and what they apply to is the public API surface of
the `Whisparr3.Net` package: the hand-written entry points, and every generated API interface,
method signature and model type the package exposes.

**While the major version is 0, that surface is not frozen.** A minor release may rename, change or
remove a public member. In practice this means you should pin an exact version rather than a range,
and read this file before you move.

### A specification refresh can rename a public method

This is the clause that matters most, because it is the one that can break a consumer without
anyone deciding to break it.

Method names in this library are derived from the specification's operation identifiers at
generation time. They are not pinned by a committed map. A Whisparr release that renames an
operation, or that moves the path an operation identifier is derived from, therefore renames the
corresponding public method here.

What that does to your build is concrete: it stops compiling, at your own call site, with an error
saying the name no longer exists. It is not a silent behaviour change and it is not deferred to
runtime.

When it happens:

- The rename moves the minor version component while the major version is 0, and will move the
  major component once the major version reaches 1.
- Every renamed method is listed individually, old name and new name, in the changelog entry for
  the release that carries the rename. A refresh is never summarised as a version bump alone.

### How you find out

Two ways, and both are meant to reach you before you upgrade.

- The changelog entry for the release, above. It names every rename by name.
- The refresh itself. Moving to a new Whisparr version arrives in this repository as a pull
  request that shows the regenerated tree, rather than as a direct commit to the default branch, so
  the renamed methods are visible in a diff before they are ever released.
