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

The run reported `+ staged 262 .cs files, 262 manifest entries, 0 missing`, then `- deleted 5 of 5
generated subdirectories, and .openapi-generator/`, then `+ copied 262 .cs files`, and exited 0.

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
