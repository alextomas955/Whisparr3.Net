# Security repair: the measured evidence for the chosen variant

`PREP-02` requires the root `security` block to be repaired so that authentication is actually
generated, and requires the losing variant's measured counts to be recorded as the evidence for the
choice. This file is that record. Every number in it was produced by this repository's own pipeline
and counted from the generated C# sources, not copied from an earlier measurement (`D-04`).

## What was generated

- **Generator:** `openapitools/openapi-generator-cli` pinned by digest
  `sha256:2ab0a9680222de65dc9d3baf861aa02b99e1b80c211d8221ebf3ae8f8a102524`.
- **Config:** `generator/gen-config.yaml`, byte-for-byte, copied into each staging directory. The
  staging layout mirrors the repository, so `inputSpec` and `outputDir` resolved correctly without
  editing and what was measured is the committed configuration itself.
- **Inputs:** three specs produced by `generator/preprocess-spec.ps1` from the committed capture
  `spec/openapi.raw.json`, differing only in `-SecurityVariant`. Each run applied `T2` and `T3`
  identically, so all three inputs carry 189 paths, 272 operations and the same 272 operationIds.
- **Counting method:** over the generated `src/Whisparr3.Net/Api` directory only, the same
  directory and the same tokens the reconnaissance used, so the two sets are comparable.

The three inputs, each named by the `-SecurityVariant` value that produced it, with the root
`security` it carries and its sha256. Deliberately a list and not a table: the only table rows in
this file keyed by a validate-set value are the measured ones below, so a re-derivation cannot
accidentally read a second table as a set of results.

- `OptionalBothSchemes` writes `[{},{"X-Api-Key":[]},{"apikey":[]}]`, sha256
  `2d7fe58abddd7c6d5659227920c0e5df80afb4483cafc4743564aa26cf9b5ec1`
- `SingleSchemeMandatory` writes `[{"X-Api-Key":[]}]`, sha256
  `665f8dcf872cae6168039850e1ff030a11955346754236867a05f83662c2fcb6`
- `AsCaptured` leaves `[{},{}]` untouched, sha256
  `b5fbc720d37fd776b00e011b957411c5149807c0f8f9404d9ec138d9a38dc8fd`

The single-scheme value is a single-element JSON **array** in the generated spec, verified above by
its own sha256 and by reading `.security` back from it. That matters: a single-element array built
as a PowerShell array and piped into a serializer unrolls into an object, which would have made the
losing variant's count a fact about the shell rather than about the variant. The pipeline parses
every variant from a JSON literal for exactly this reason.

The mount was proven before generating: the staging directory was listed from inside a container
and the input spec was hashed there, and the in-container sha256 equalled the host's. Docker on
this machine returns an empty directory with exit 0 and no warning when asked to bind-mount the
`I:` drive, so an unproven mount produces a number that looks like evidence. A second, independent
proof is that each run emitted 76 files into `Api`.

## Measured, this phase, from the generated trees

| variant | API files | files reaching `UseInHeader` | `UseInHeader` | `UseInQuery` | `GetAsync("X-Api-Key"` | `GetAsync("apikey"` |
| --- | --- | --- | --- | --- | --- | --- |
| OptionalBothSchemes | 76 | 75 | 272 | 272 | 272 | 272 |
| SingleSchemeMandatory | 76 | 75 | 272 | 0 | 272 | 0 |
| AsCaptured | 76 | 0 | 0 | 0 | 0 | 0 |

`AsCaptured` is the **negative control**, not a candidate. It is the defect `PREP-02` exists to
repair: the spec Whisparr serves declares both API key schemes and then serves `[{}, {}]`, and the
client generated from it carries **zero** auth call sites across all 76 API files. Without that row
the two variant numbers have nothing to be measured against, and the claim that authentication is
generated rather than silently absent would stay inherited.

76 files is 75 tag APIs plus `IApi.cs`. `IApi.cs` declares no request, so 75 rather than 76 is the
correct count of files that reach the header helper in either repaired variant. The two repaired
trees differ from each other in exactly those 75 files and in no other file under `Api`.

## Reconnaissance, cited and NOT re-run

Recorded in `19-SECURITY-VARIANT-RECON.md`, measured during the Phase 19 discussion with the same
pinned image. Rows are keyed by that document's own variant letters, deliberately: they are not
part of the set measured above and must not be read as if they were.

| recon variant | root `security` | files reaching header helper | header helper | query helper |
| --- | --- | --- | --- | --- |
| A single, mandatory | `[{"X-Api-Key":[]}]` | 75 | 272 | 0 |
| B optional, both | `[{}, {"X-Api-Key":[]}, {"apikey":[]}]` | 75 | 272 | 272 |
| C both, mandatory | `[{"X-Api-Key":[]}, {"apikey":[]}]` | 75 | 272 | 272 |

Row C is the only reason this phase generated three trees rather than four. The reconnaissance
found B and C **byte-identical**: `diff -r` over the two `src/` trees reported exactly one
difference, and it was the generator's own `README.md` line naming the input file. Re-running C
would reproduce the B row and nothing else. Rows A and B were re-derived above through this
phase's own pipeline and reproduce exactly.

## The choice, and the three grounds for it

`OptionalBothSchemes` is committed. It is chosen on three independent grounds, not because it ties
with the mandatory-both-schemes form:

1. **`ERGO-01` requires both declared schemes to reach the wire.** The single-scheme variant emits
   zero query call sites, so the `apikey` query scheme Whisparr declares would be dead code under
   it. That is the ground the measured `UseInQuery` column above settles.
2. **The repair must not assert mandatory authentication** (ROADMAP Phase 19 criterion 2,
   `ERGO-01`, `LIVE-05`). The chosen value leads with an empty requirement object, so an instance
   with authentication disabled remains usable by the generated client. The mandatory forms assert
   it; this one does not.
3. **It costs nothing.** The generated output is identical to the mandatory-both-schemes form.

## The ROADMAP's recorded risk is refuted, not hedged against

`ROADMAP.md` records that "the semantically-truer auth-optional form is untested and may regress to
dead code". That is measured false and the design must not hedge against it (`D-02`). The leading
empty requirement object does **not** suppress auth generation: the chosen variant emits 272 header
call sites and 272 query call sites, the same 272 the mandatory single-scheme variant emits on the
header side, and the reconnaissance found the optional and mandatory both-schemes forms generate
byte-identical code. The risk was measured away rather than argued away.

## Reproduction

1. Stage on a `C:` path. **Docker on this machine cannot bind-mount the `I:` drive**: it returns an
   empty directory with exit 0 and no warning, so a generation over an `I:` mount silently measures
   nothing. Do not try to clear it by restarting the engine; the machine hosts a live Whisparr
   instance and a Testcontainers suite, and that is the owner's call at a quiet moment (`D-05`,
   `D-07`).
2. Issue every Docker command from `pwsh`. Under Git Bash a container path such as `/local` is
   silently rewritten to a Windows path and the run fails with "spec file not found" for a file
   that plainly exists (`D-08`).
3. For each variant, run
   `generator/preprocess-spec.ps1 -SecurityVariant <value> -OutFile <staging>/spec/openapi.generated.json`,
   copy `generator/gen-config.yaml` to `<staging>/generator/`, then
   `docker run --rm -v "<staging>:/local" <image@digest> generate -c /local/generator/gen-config.yaml`.
4. Count over `<staging>/src/Whisparr3.Net/Api`. The scheme-name column headers above are
   abbreviated: the generated call is
   `ApiKeyProvider.GetAsync("X-Api-Key", cancellationToken)`, so a pattern ending in a closing
   parenthesis directly after the scheme name matches nothing.

Nothing generated by this measurement is committed and no generated tree was written inside the
repository. The staging root was deleted once the numbers had been re-derived from it. Phase 20
owns the first committed generation.
