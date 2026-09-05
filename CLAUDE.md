# Whisparr3.Net

C# SDK for Whisparr 3 (Eros), generated from Whisparr's own OpenAPI spec. The repo lives at
`i:\cove-dev\Whisparr3.Net\` alongside `cove\` and `extensions\`.

## Upstream

Upstream is `Whisparr/Whisparr-Eros`. That repository is Whisparr 3, and it is the only source of
truth for anything this library generates from. Its active branch is `eros-develop`, and `eros`
carries the releases.

`Whisparr/Whisparr` is Whisparr 2. It is a different codebase and it is not this project's
upstream. Do not read it to answer a question about v3 behaviour, and do not open a pull request
against it.

Two things make the wrong repository look right, and neither is evidence.

- Both repositories carry a branch named `eros`. Measured 2026-09-05: `Whisparr/Whisparr` is at
  `cc3fb2ab` and `Whisparr/Whisparr-Eros` is at `c3e56023`. The name alone identifies nothing.
- The captured spec names the wrong repository itself. `info.license.url` in
  `spec/openapi.raw.json` reads `https://github.com/Whisparr/Whisparr/blob/develop/LICENSE`. That
  string is hardcoded in the Eros source and is an upstream defect, not a pointer to follow.

`spec/PROVENANCE.json` is what settles which commit a question is about. It records the version,
the branch and the build time of the image the spec was captured from. The 3.4.0.1387 build
recorded there is commit `c3e5602` in `Whisparr/Whisparr-Eros`, committed thirty minutes before
the image was built. Match on those three fields rather than on a branch name.

## Writing style

The environment instructions at `i:\cove-dev\.claude\CLAUDE.md` are authoritative and are not
restated here. The two rules broken most often: plain dash, never an em dash, and one idea per
sentence.

## Generated vs hand-written

Nothing under `src/Whisparr3.Net/` is ever hand-edited. That directory is openapi-generator output
and every edit inside it is destroyed on the next regeneration.

`docs/SURFACE.md` is not hand-edited either. `generator/render_docs.py` writes it from the
committed spec and from the prose template at `generator/templates/SURFACE.md.in`, so an edit made
in `docs/` is overwritten on the next render. Edit the template. Both CI workflows run the renderer
with `--check`, so a hand edit fails the build before anyone notices it was lost.

Three lists in that script are judgement rather than derivation: which paths serve Whisparr's web
interface, which responses carry credentials, and which operations have effects the spec does
not describe. Each is checked against the spec on every run, so a path Whisparr removes fails
the render instead of leaving prose about an operation that no longer exists. The document
describes and does not instruct: what a caller does with an operation is their decision.

Customisation goes to one of three places instead:

- Spec pre-processing, before the generator runs.
- `Directory.Build.props` at the repo root, which owns target frameworks, language version,
  nullable, the warning policy, the deterministic-build flags and all NuGet package metadata.
- A hand-written directory outside the generated tree.

That directory is `src/hand-written/`, and what it holds is documented in
`docs/HAND-WRITTEN-LAYER.md`. One join makes it real: `src/Whisparr3.Net/Whisparr3.Net.csproj`
carries the `Compile` glob that pulls the directory into the library assembly. Without that glob,
files there compile into nothing while the build stays green and every test passes against
generated code alone. The glob lives in the library csproj and deliberately not in
`Directory.Build.props`, which would also compile those sources into the test assembly and define
every hand-written type twice.

`Directory.Build.props` sits at the repo root, which is outside every directory the generator writes to.
That is the property this repo currently has. The generator emits no props file at any setting,
measured 2026-09-04 by running it with `openapiGeneratorIgnoreList` removed entirely and listing
what it wrote: thirteen paths outside the five generated subdirectories, none of them a props file.
The props therefore survive a regeneration because they sit at a path the generator never writes
to, not because an ignore file protects them.

Two related facts a reader of this file needs.

- The `.openapi-generator-ignore` committed at the repo root is a record of what
  `openapiGeneratorIgnoreList` in `generator/gen-config.yaml` produced, never an input. Generation
  stages only `spec/openapi.generated.json` and `generator/gen-config.yaml` into a fresh root, so
  the generator never reads the committed file and a hand edit to it is discarded on the next run.
  Edit the config key instead.
- `useSourceGeneration` is left at its generator default of `false`. The reason is recorded in
  `generator/gen-config.yaml`.

## Build and packaging

Traps that a reader copying the sibling `extensions\` repo would walk into.

- A test or sample project needs three things in its csproj, and the first two were each found by
  a measured failure rather than by reading.
  - `<IsPackable>false</IsPackable>`. `PackageId` is set in `Directory.Build.props` and therefore
    applies to every project in the tree, so a second packable project claims the same package id.
  - `<PackageId>$(MSBuildProjectName)</PackageId>`. The packable flag alone is necessary and not
    sufficient: restore still fails with `Ambiguous project name 'Whisparr3.Net'`, because the
    inherited `PackageId` applies whether or not the project packs.
  - No `<TargetFramework>` element at all. `Directory.Build.props` sets the plural
    `TargetFrameworks`, and a project that also sets the singular one builds green while the test
    runner reports `No test is available`. That is a silent zero-test pass. Omit the element and
    let the project cross-target.
- Do not adopt central package management. `extensions\` has a `Directory.Packages.props`; this
  repo must not. The generated csproj writes versioned `PackageReference` elements, and central
  package management turns a versioned `PackageReference` into a hard `NU1008` error.

## Tests

There are two test projects. `test/Whisparr3.Net.UnitTests/` needs no Docker and is what a
per-change check should run. `test/Whisparr3.Net.IntegrationTests/` drives a pinned Whisparr
container through Testcontainers and skips itself when Docker is unreachable, so a machine without
Docker still gets a green build. Both sit outside `src/` deliberately, so the generator's sweep
cannot reach them, and neither is packed.

The generator writes no tests of its own. It does write
`[assembly: InternalsVisibleTo("Whisparr3.Net.Test")]` into `Client/ClientUtils.cs`, naming a
project this repo does not have and will not add. Tests therefore stay on the public surface. Do
not add a second `InternalsVisibleTo` and do not rename the test project to match that attribute.

Both test projects reference the library project and call `AddWhisparr3` directly. That coupling is
load-bearing: it is what turns a broken `Compile` glob into a build error instead of a green build
over a hand-written layer that was never compiled. Do not test through an intermediate abstraction
and do not copy hand-written sources into a test project.

## Planning

Milestone v1.5 is planned at the environment tier, in `i:\cove-dev\.planning\`, because the
environment created this repo. Post-v1.5 work on this repo plans in this repo's own `.planning\`.
Do not migrate the v1.5 planning tree mid-milestone. See `.planning/README.md`.

## Secret hygiene

No repo under `i:\cove-dev` currently has pre-commit secret scanning. The v1.2 gitleaks hook was
displaced by lefthook and `core.hooksPath` is unset in every scope, so nothing scans a commit here.

This repo relies on `.gitignore` plus discipline. The tracked `.gitignore` covers `.planning/`,
`.serena/`, `.claude/settings.local.json`, `*.nupkg`, `*.snupkg`, `*.env`, `.env*`,
`**/config.local.*` and `**/*.secret.*`.

Restoring scanning across the environment is tracked as `SEC-F1`. Until that lands, do not assume
a commit is checked. Read what you are staging.

## Commits

- Conventional Commits.
- Author is `alextomas955 <295956354+alextomas955@users.noreply.github.com>`, wired through the
  `includeIf "gitdir:I:/cove-dev/"` include in `~/.gitconfig`. Verify it resolved with
  `git log -1 --format='%an <%ae>'` rather than assuming.
- No agent co-author trailer, no agent name, no planning content.
- Push over `origin`, the `git@github.com-alex` SSH alias. HTTPS authenticates as the wrong
  account on this machine. SourceLink reads `origin` and `Directory.Build.props` registers the
  alias as a GitHub host, so a clone needs no extra remote.
