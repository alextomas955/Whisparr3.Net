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
