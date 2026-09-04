# Whisparr3.Net

C# SDK for Whisparr 3 (Eros), generated from Whisparr's own OpenAPI spec. The repo lives at
`i:\cove-dev\Whisparr3.Net\` alongside `cove\` and `extensions\`.

## Writing style

The environment instructions at `i:\cove-dev\.claude\CLAUDE.md` are authoritative and are not
restated here. The two rules broken most often: plain dash, never an em dash, and one idea per
sentence.

## Generated vs hand-written

Nothing under `src/Whisparr3.Net/` is ever hand-edited. That directory is openapi-generator output
and every edit inside it is destroyed on the next regeneration.

Customisation goes to one of three places instead:

- Spec pre-processing, before the generator runs.
- `Directory.Build.props` at the repo root, which owns target frameworks, language version,
  nullable, the warning policy, the deterministic-build flags and all NuGet package metadata.
- A hand-written directory outside the generated tree.

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

Two traps that a reader copying the sibling `extensions\` repo would walk into.

- Any future test or sample project must set `<IsPackable>false</IsPackable>`. `PackageId` is set
  in `Directory.Build.props` and therefore applies to every project in the tree, so a second
  packable project claims the same package id.
- Do not adopt central package management. `extensions\` has a `Directory.Packages.props`; this
  repo must not. The generated csproj writes versioned `PackageReference` elements, and central
  package management turns a versioned `PackageReference` into a hard `NU1008` error.

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
