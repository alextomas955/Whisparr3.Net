# Reproducing the generated tree

Everything under `src/Whisparr3.Net/` is openapi-generator output. This document is how you
reproduce it from a fresh clone and get the committed bytes back.

You do not need to be the author of this repository to do it. One command regenerates the tree, and
one comparison tells you whether what came out matches what is committed.

## Provenance

The committed specification was captured from one digest-pinned Whisparr container, and the
committed tree was produced from that specification by one digest-pinned generator image. Both pins
are recorded, and neither is a moving tag.

| Field | Value |
| --- | --- |
| Whisparr image | `ghcr.io/hotio/whisparr@sha256:fab920114a75f1c86bbadf24c66f1e35a912ace9c7527e971f1032a569589ee6` |
| Whisparr version | `3.4.0.1387` |
| Whisparr branch | `eros` |
| Whisparr build time | `2026-08-30T11:26:49Z` |
| Whisparr package version | `v3-7f610bc` |
| Spec endpoint | `/docs/v3/openapi.json` |
| Raw spec SHA-256 | `8ac2dbceedf65de542c6a8d2c7bb8d8f8fa6e155b651956079f9b192e8bedf18` |
| Raw spec bytes | `381380` |
| Spec OpenAPI version | `3.0.4` |
| Processed spec SHA-256 | `665f8dcf872cae6168039850e1ff030a11955346754236867a05f83662c2fcb6` |
| Generator image | `openapitools/openapi-generator-cli@sha256:2ab0a9680222de65dc9d3baf861aa02b99e1b80c211d8221ebf3ae8f8a102524` |
| Generator version | openapi-generator-cli 7.25.0 |

`spec/PROVENANCE.json` is the authoritative copy of all of it, along with the wall clock of the
capture and the URL it was captured from. The table above restates it so a reader does not have to
open the file, and the file wins if the two ever disagree.

The generator image digest is a constant inside `generator/generate.py` and the generator version
it corresponds to is recorded at the top of `generator/gen-config.yaml`.

## Prerequisites

- A reachable Docker daemon. Generation always runs inside the pinned generator image, never on
  the host.
- Python 3. The generator scripts import only the standard library, so there is nothing to install
  alongside it.
- The .NET 8 and .NET 10 SDKs, which are the two framework lines this library targets. These are
  needed only to build the regenerated tree, not to generate it.

## Regenerate from the committed specification

One command, from the repository root.

On Linux and macOS:

```
python3 generator/generate.py
```

On Windows:

```
python generator/generate.py
```

The two forms differ only in the interpreter name, and the difference is not cosmetic. `python3`
is the name that resolves on a typical Linux or macOS installation, and it does not resolve on
every Windows installation, where `python` does. A document that gave one form only would fail for
half of its readers on the first step.

The command takes no arguments. The generator image is pinned by digest inside the script rather
than passed on the command line, and there is deliberately no output-root option, because the
destination is the repository tree the script was invoked from.

What it does, in order: stages the committed specification and the generator configuration into a
temporary root, runs the pinned image against that root, refuses unless every `Model/` and `Api/`
file the specification implies was generated and nothing else was, then deletes those five
subdirectories in the repository and copies the new ones back. That check is derived from the
specification rather than pinned to a file count, so a Whisparr release that adds an operation
passes it. The delete is what prunes a file the generator no longer emits, since the generator
itself never prunes.

`generate.py` does not write `docs/SURFACE.md`. That document is written by
`generator/render_docs.py` from the same committed specification, and `refresh.py` runs it as its
own step. Running `generate.py` alone leaves the document behind, and continuous integration then
fails on `render_docs.py --check`. Run the renderer too, or use `refresh.py`, which runs both.

## Move to a new Whisparr version

`generator/refresh.py` is the entry point for changing which Whisparr the library is generated
from. It runs the whole pipeline in order and stops at the first failure, naming the step that
failed and what to do about it: capture, preprocess, generate, render docs, build, package
audit.

```
python3 generator/refresh.py --image-digest sha256:0123abcd...
```

Run with no digest, it re-verifies the one that is already pinned. Every gate is exercised and
nothing changes except the capture wall clock in `spec/PROVENANCE.json`.

Expect the preprocess step to refuse when a new Whisparr version has moved a path. Method names are
derived from the specification's paths rather than read from a committed map, so a moved path
either produces a name the derivation cannot form, or collides with another, or leaves a stale
override pointing at a path that no longer exists. The assertion names which of those it hit. The
fix is to edit `OPERATION_ID_OVERRIDES` in `generator/preprocess_spec.py` and run the script again.
The committed specification is not replaced until the step passes.

## Check the result

Regenerate, stage the three generated paths, then compare against the index.

```
python3 generator/generate.py
git add -A -- src/Whisparr3.Net .openapi-generator .openapi-generator-ignore
git diff --cached --exit-code
```

An exit code of 0 means the regenerated tree is byte-identical to what is committed.

Staging before diffing is required rather than tidy. A bare `git diff` compares the working tree to
the index and reports nothing at all for an untracked path, so a generation that emitted a file the
committed tree does not have would pass an unstaged comparison while having changed the output.

This is the same command the repository runs on every push, in `.github/workflows/determinism.yml`.
It is written here in the same form on purpose. If this document and that workflow ever describe
different procedures, the workflow keeps passing while the documented procedure stops reproducing
the tree, and only a stranger would find out.

If the comparison reports a difference, `git status --porcelain` is the fastest way to read what
kind. A difference in file mode alone can appear on Linux and not on Windows, because Git's
`core.fileMode` setting defaults differently on the two.

## Note: why generation stages into a temporary directory

This section explains an automatic behaviour. It is not a step, and there is nothing here for you
to do.

`generate.py` never runs the generator directly against the repository. It copies the two inputs
into a temporary directory first, runs the image against that, and copies the output back.

The reason is a Docker limitation measured on one machine in this project's history. On that
machine Docker cannot bind-mount the `I:` drive, where the repository lives. A bind mount of a path
on that drive lists an empty directory and exits 0, so the generation looks like it worked and
produces nothing. Staging elsewhere sidesteps it.

The staging directory is chosen by the Python standard library, which picks the user temporary
directory on whatever platform it is running on. You do not select a drive, a path, or a
filesystem, and the same code path runs on Linux, macOS and Windows alike.
