# Generation evidence: determinism, the boundary, and the dependency audit

Phase 20 makes three claims about its own output: the output is byte-identical run to run, the
generator provably cannot cross the directory boundary, and the dependency closure is clean on both
target frameworks. This file records the observation behind each claim. Every run below was made
against `I:/cove-dev/Whisparr3.Net` itself, not against a research sandbox or a repository copy, and
every number is quoted from the command printed beside it.

## Determinism

**Observed:** 2026-09-04.

- **Generator:** `openapitools/openapi-generator-cli` pinned by digest
  `sha256:2ab0a9680222de65dc9d3baf861aa02b99e1b80c211d8221ebf3ae8f8a102524`, which is
  openapi-generator 7.25.0.
- **Command:** `pwsh -NoProfile -File generator/generate.ps1`, run a second time over the tree
  committed at `0ab3248`.
- **Gate:** `git -C I:/cove-dev/Whisparr3.Net status --porcelain`.
- **Observed line count:** `0` before the run and `0` after it.

The run reported `+ staged 262 .cs files, expected 262, 262 manifest entries, 0 missing, 5 of 5
subdirectories present`, then `- deleted 5 of 5 generated subdirectories, and .openapi-generator/`,
then `+ copied 262 .cs files into I:\cove-dev\Whisparr3.Net\src\Whisparr3.Net`, and exited 0.

The staged line gained `expected 262` and the subdirectory count after the code review: gate 3's
only floor was a count of zero, so a short generation would have replaced the committed tree and
exited 0. Requoted from a real run on 2026-09-04, not edited by hand.

The gate is `git status --porcelain` rather than `git diff --exit-code`. `git diff` alone misses a
newly created file, and the whole point of the delete-and-replace is that files can appear and
disappear. No `git add -N` is needed. The comparison is taken over the committed tree after the copy
back (D-13), so an empty result also proves the copy step is faithful rather than proving only that
the container is deterministic. `.openapi-generator/FILES`, `.openapi-generator/VERSION` and
`.openapi-generator-ignore` sit inside that comparison and are not exempt from it.

Two mechanisms make the empty result possible.

1. **Generation always runs inside the image (D-14).** `.openapi-generator/FILES` is written with
   the platform line separator, so a host run writes CRLF there where a container run writes LF. The
   two would then differ in that one file for a reason that has nothing to do with the spec.
   `generate.ps1` has no host path at all, which is the enforcement rather than a convention.
2. **The solution file is suppressed, so `packageGuid` never reaches committed output (D-12).**
   `"*.sln"` is an entry in `openapiGeneratorIgnoreList`, and the generator log states the
   consequence: `Ignored /local/Whisparr3.Net.sln (Ignored by rule in ignore file.)`. The GUID
   reaches no other file. The ignore entry is what currently delivers determinism and the pin is
   insurance. Delete the entry and two unpinned runs then differ in exactly one file.

Line endings cannot fire this gate. `.gitattributes` declares `* text=auto eol=lf` and `*.cs text
eol=lf`, and `core.autocrlf` is `input`, so the container's LF output stays LF in the working tree.

**What this section does not claim.** The drift-injection negative control, in which a single
character is changed inside a generated file and the gate is then observed exiting non-zero, is
deliberately not performed here. It is `PIPE-02` in Phase 23, which owns the CI pipeline that runs
this gate. Recording the boundary is part of the evidence: this section shows the gate passing over
a correct tree, and `PIPE-02` is where it is shown refusing an incorrect one.

## Boundary probe

**Observed:** 2026-09-04.

- **Script:** `generator/probe-generated-boundary.ps1`, committed so a verifier can observe the
  boundary rather than trust this transcript.
- **Command:** `pwsh -NoProfile -File generator/probe-generated-boundary.ps1`.
- **Exit code:** `0`.

One run, as D-16 asks for. The probe refused to start until `git status --porcelain` reported 0
paths, snapshotted 262 generated files and 4 guarded files by SHA-256, planted three shapes inside
the generated tree, ran `generate.ps1` once as a child process, and then asserted.

| assertion | actual | expected |
| --- | --- | --- |
| `src/Whisparr3.Net/Api/ZZ_PLANTED.cs` | absent | absent |
| `src/Whisparr3.Net/Model/ZZ_PLANTED2.cs` | absent | absent |
| `src/Whisparr3.Net/Client/Stale/ZZ_PLANTED3.cs` | absent | absent |
| `src/Whisparr3.Net/Client/Stale/` as a directory | absent | absent |
| `treeFiles` | 262 | 262 |
| `treeManifestDiff` | 0 | 0 |

The four guarded files, compared by SHA-256 before and after that single run, each unchanged:

- `src/Whisparr3.Net/Whisparr3.Net.csproj`
  `454992815688131bba7984f98a3ac9b674f3cf3c9ee90a5357cce9eeb409cc73`
- `Directory.Build.props`
  `3db1e06d0fed052dd501ebbdb6a11dbab7986f0715e8da40ac2da79b60e5871f`
- `src/hand-written/PLACEHOLDER.cs`
  `df0606231f4a1e38f4b89603ea5edb3e99a03311ee8c69599f54169d7961a296`
- `.openapi-generator-ignore`
  `8107aa8d9e5bc74560b8a46e69d290dd18e98cba3454aa74f347435e4d792c09`

Those four are the file beside the deleted subdirectories, the file above them, the file outside the
tree entirely, and the file the generator itself rewrites on every run. The last one is guarded even
though it is rewritten: it comes out byte-identical, so the assertion holds, and asserting it is what
would catch an accidental `gen-config.yaml` edit riding along with a regeneration.

Three plant shapes, not one. `Copy-Item -Recurse` into an existing target merges rather than
replaces, measured 2026-09-04, so without `generate.ps1`'s `Remove-Item -Recurse` a planted file
survives the copy and compiles (D-17). The fabricated `Client/Stale` directory is the shape a real
stale-file incident takes after an operationId rename moves a file: a delete implemented as "remove
the files the old manifest listed" would leave the directory behind, and `Remove-Item -Recurse` does
not. The row above shows the directory itself gone, not only the file inside it.

Byte identity here is decided by `Get-FileHash -Algorithm SHA256` compared as lowercase strings. It
is never decided by `LastWriteTime`, because `generate.ps1` rewrites nothing at the four guarded
paths and a timestamp comparison would therefore pass even if the content had changed. It is never
decided by file size or file count either. `treeManifestDiff` is a whole-tree comparison over all
262 files and not a spot check, and both manifests are sorted by repository-relative path before
they are compared, so the result is independent of enumeration order.

**This run is the demonstration `SETUP-07`'s "and is protected from regeneration" clause was waiting
for.** Phase 18 arranged for the probe and recorded `SETUP-07` as PARTIAL, correctly declining to
claim a boundary it had never watched hold, because the generator had not yet run. It has now run,
hostile, once, against this repository. The clause closes here (D-20).

The refusal branch was also observed rather than asserted by shape. Run against a working tree
carrying one uncommitted file, the probe exited 1, named the offending path, and planted nothing.

## Dependency audit baseline

**Observed:** 2026-09-04, .NET SDK `10.0.400`, restoring online against
`https://api.nuget.org/v3/index.json`.

**This whole section is point in time.** It is true against the nuget.org advisory database on the
date above and no longer. The continuous gate is the props, recorded at the end of this section.

- **Script:** `generator/assert-package-audit.ps1`.
- **Command:** `pwsh -NoProfile -File generator/assert-package-audit.ps1`.
- **Exit code:** `0`.

| framework | verdict | expected |
| --- | --- | --- |
| `net8.0` | clean | clean |
| `net10.0` | clean | clean |

The verdict on each row is read from the transcript text, never from the process exit code, which is
printed as a report-only row. Measured 2026-09-04: `dotnet list package --vulnerable` exits 0 while
printing a High severity finding, which is why the exit code decides nothing here.

There are **four** verdicts, not three. The code review found that reading `clean` from the marker
`has no vulnerable packages given the current sources` alone was itself a silent pass, because that
sentence is a statement about the sources the run read. Pointed at a feed carrying no advisory data
it prints verbatim and exits 0, having consulted no advisory database:

| verdict | condition |
|---|---|
| `finding` | the marker `has the following vulnerable packages` is present |
| `clean` | the clean marker is present **and** the transcript names `https://api.nuget.org/v3/index.json` among `The following sources were used:` |
| `unsourced` | the clean marker is present but the audit source is not named - refused, transcript reprinted |
| `unrecognised` | neither marker present, as an unrestored or offline project prints - refused, transcript reprinted |

A passing run therefore prints a `sources` row beside each framework row, so a green transcript
records what actually answered the question:

    [audit]   + net8.0           actual clean                expected clean                OK
    [audit]   + net8.0 sources   actual nuget.org consulted  expected nuget.org consulted  OK
    [audit]   + net10.0          actual clean                expected clean                OK
    [audit]   + net10.0 sources  actual nuget.org consulted  expected nuget.org consulted  OK

### The closure that was audited

The scan is not vacuous. `dotnet list package --include-transitive` reports **4 top-level and 29
transitive** packages on each framework, 33 in total per leg.

| top-level package | net8.0 resolved | net10.0 resolved |
| --- | --- | --- |
| `Microsoft.Extensions.Hosting` | 8.0.1 | 10.0.1 |
| `Microsoft.Extensions.Http` | 8.0.1 | 10.0.1 |
| `Microsoft.Extensions.Http.Polly` | 8.0.20 | 10.0.1 |
| `Microsoft.Net.Http.Headers` | 8.0.17 | 10.0.1 |

Both legs resolve `Polly 7.2.4` and `Polly.Extensions.Http 3.0.0`, at the same versions, because
those two come in through `Microsoft.Extensions.Http.Polly` rather than from the framework.

All four are kept (D-09). A finding here would be a finding to report, never a dependency to
remove: `Microsoft.Extensions.Http.Polly` is required by `ERGO-06` and by a milestone constraint,
so resolving an advisory by dropping it would trade a reported risk for a broken requirement.

### The exit-code trap, reproduced rather than asserted

`dotnet list package --vulnerable --include-transitive` exits **0** while printing a High severity
advisory. Observed on a poisoned probe project built under the system temp directory, referencing
`System.Text.RegularExpressions 4.3.0`:

```
Project `VulnProbe` has the following vulnerable packages
   [net8.0]:
   Top-level Package                     Requested   Resolved   Severity   Advisory URL
   > System.Text.RegularExpressions      4.3.0       4.3.0      High       https://github.com/advisories/GHSA-cmhx-cq75-c4mj
```

- `dotnet list package` exit code on that project: **0**.
- `assert-package-audit.ps1` exit code on that same project: **1**, both framework rows reading
  `actual finding expected clean MISMATCH`, with the advisory row and its URL reprinted.

A gate written as "run it and fail when the exit code is non-zero" passes on that project. That is
the silent pass this script exists to prevent, and it is why the gate matches text.

The probe is built under the system temp directory and never inside this repository. A project
under `I:/cove-dev/Whisparr3.Net` inherits `Directory.Build.props`, whose `TreatWarningsAsErrors`
turns `NU1903` into a restore error, so the probe would fail to restore and the gate would refuse
through the unrecognised-transcript branch. It would still exit non-zero, and it would prove the
wrong thing. The probe was deleted after the run.

### Two measurements to read rather than re-derive

**1. The props already convert any advisory into a restore error.** Resolved on the real project,
2026-09-04: `NuGetAudit=true`, `NuGetAuditLevel=low`, `TreatWarningsAsErrors=true`. Reproduced by
copying this repository's `Directory.Build.props` beside a throwaway project outside the repository
and restoring it with the same poisoned reference:

```
error NU1903: Warning As Error: Package 'System.Text.RegularExpressions' 4.3.0
  has a known high severity vulnerability, https://github.com/advisories/GHSA-cmhx-cq75-c4mj
Failed to restore ...
```

`dotnet restore` exited 1. Any severity, down to low, on any package the audit covers, already
fails the build before anyone runs this script. That transcript also carried an unrelated `NU1510`
pruning error, so the exit code alone does not isolate the advisory; the `NU1903` line does. The
build-time gate is continuous and this script is the point-in-time artifact. They do different
jobs, and both are wanted.

**2. `NuGetAuditMode` needs no change in the props.** Resolved 2026-09-04: `direct` for `net8.0`,
`all` for `net10.0`, and `direct` on the outer evaluation with no `TargetFramework` set. That looks
like a gap on the `net8.0` leg and is not one. A probe with `TargetFrameworks` of `net8.0;net10.0`
and a `net8.0`-conditioned reference to `System.IdentityModel.Tokens.Jwt 6.10.0` still reported the
transitive `Microsoft.IdentityModel.JsonWebTokens 6.10.0`, as `NU1902` at restore and again under
`[net8.0]` in `dotnet list package --vulnerable --include-transitive`. The multi-target restore
audits at the `all` level contributed by the `net10.0` leg. Setting `<NuGetAuditMode>all</NuGetAuditMode>`
would be insurance against a future in which `net10.0` is dropped, and a milestone constraint locks
`net8.0;net10.0`, so it is not added here.
