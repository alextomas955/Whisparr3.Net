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

- Both repositories carry a branch named `eros`, and the two point at unrelated commits. The name
  alone identifies nothing, so resolve the repository before resolving the branch.
- The captured spec names the wrong repository itself. `info.license.url` in
  `spec/openapi.raw.json` reads `https://github.com/Whisparr/Whisparr/blob/develop/LICENSE`. That
  string is hardcoded in the Eros source and is an upstream defect, not a pointer to follow.

`spec/PROVENANCE.json` is what settles which commit a question is about. It records the version,
the branch and the build time of the image the spec was captured from. The 3.6.2.1727 build
recorded there is release `v3.6.2-release.1727`, commit `b88e972` in `Whisparr/Whisparr-Eros`.
Match on those three fields rather than on a branch name, which names nothing on its own.

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

That directory is `src/hand-written/`, and the XML documentation comments in it are the reference
for what it holds. One join makes it real: `src/Whisparr3.Net/Whisparr3.Net.csproj`
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

## Regenerating

`generator/refresh.py` runs the whole pipeline and stops at the first failure, naming the step and
what to do about it: capture, preprocess, generate, build, package audit. It needs Docker, Python 3
and both .NET SDKs.

```
python generator/refresh.py
```

With no arguments it re-verifies the digest `generator/capture_spec.py` pins, and nothing changes
but the `capturedAt` wall clock in `spec/PROVENANCE.json`. To move to a new Whisparr, resolve
hotio's moving tag to a digest and pass it:

```
docker buildx imagetools inspect ghcr.io/hotio/whisparr:v3 --format "{{.Manifest.Digest}}"
python generator/refresh.py --image-digest sha256:...
```

Then set that digest as `DEFAULT_IMAGE_DIGEST` in `capture_spec.py`, so the pin and the committed
spec stay in step, and update the Whisparr version README.md names at the top. That version is the
one fact about the capture written by hand rather than read from `spec/PROVENANCE.json`.

Generation alone is `python generator/generate.py`. It stages the committed spec and
`gen-config.yaml` into a temp root, runs the pinned generator image there, gates the output against
the spec, then deletes the five generated subdirectories and copies the new ones back. It never
bind-mounts the repository: the generator does not prune, and a repository on a mapped drive is not
always bind-mountable, which Docker reports as an empty mount and exit 0.

To confirm a regeneration reproduces what is committed:

```
python generator/generate.py
git add -A -- src/Whisparr3.Net .openapi-generator .openapi-generator-ignore
git diff --cached --exit-code
```

Staging before diffing is required rather than tidy: a bare `git diff` reports nothing for an
untracked path, so a run that emitted a new file would pass an unstaged comparison. This is what
`.github/workflows/determinism.yml` runs on every push.

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
Do not migrate the v1.5 planning tree mid-milestone.

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
