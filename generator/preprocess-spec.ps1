<#
.SYNOPSIS
  Pre-process the captured Whisparr 3 (Eros) OpenAPI document into the spec the generator reads.

.DESCRIPTION
  Reads the byte-verbatim capture, applies the transforms this milestone owns, gates the result
  on a staging path, and only then replaces the committed spec and records its hash.
    1. Parse the raw capture and report its observed byte count and sha256.
    2. Transform T1, the root security repair. Whisparr declares both API key schemes and then
       serves an empty requirement, so the generated client would carry no auth call site at
       all. The repair sets the auth-optional, both-schemes form.
    3. Transform T2, the malformed root path. paths["/"] is a StaticResource catch-all whose
       operation the generator turns into a method that shadows the client root. Deleting it
       takes the document from 190 paths and 273 operations to 189 and 272.
    4. Stage. The patched document is written to the output path plus an .incoming suffix,
       never to the output path itself.
    5. Gate G1, the census over the staged bytes, with the Patched profile. Its exit code is
       propagated rather than flattened.
    6. Gate G2, the depth and size guard over the staged bytes. This is the gate the census
       cannot be. See the parser note below.
    7. Promote. Only here is the committed spec replaced. A run that refuses at any earlier
       step leaves the committed spec and the committed manifest exactly as they were.
    8. Manifest. generatedSpecSha256 is added to the PROVENANCE.json beside the output.

  This script parses and serializes with System.Text.Json.Nodes.JsonNode rather than with the
  JSON cmdlets its two sibling scripts use. That is a deliberate divergence from the house JSON
  handling, and the reason is measured: ConvertTo-Json's -Depth argument defaults to 2, and
  against this 10-deep document that default emits a valid 49,525-byte file as written with
  CRLF, 48,452 after LF normalization, in which every operation body has been replaced by a
  short placeholder string. It reports that only on the warning stream and exits 0, and
  assert-spec-census.ps1 then passes the result at 190 paths, 273 operations, 162 schemas and
  75 tags. JsonNode has no truncation mode, round-trips number tokens verbatim, and with the
  relaxed encoder plus LF normalization reproduces the capture to within three bytes. Do not
  harmonize the parser back to the cmdlets.

  assert-spec-census.ps1 stays on the cmdlets on purpose. It reads a document whose depth-2
  truncation it demonstrably cannot see anyway, which is exactly why the guard lives here.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\preprocess-spec.ps1
  # Reads spec/openapi.raw.json and writes spec/openapi.generated.json inside the repository.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\preprocess-spec.ps1 -RawSpec C:\scratch\truncated.json -OutFile C:\scratch\out.json
  # The depth-truncation refusal run. Expected to stage, pass the census gate at 189 and 272,
  # then be refused by the depth and size guard and exit non-zero without writing a spec.
#>

[CmdletBinding()]
param(
    # The document to pre-process. Defaults to the committed byte-verbatim capture, which is
    # the only input this pipeline is designed for. A relative path resolves against the
    # repository root, not the current directory. Overriding it is a fixture run, not a normal
    # one, and it requires -OutFile as well.
    [string]$RawSpec = 'spec/openapi.raw.json',

    # Where to write the patched spec. Defaults to the committed deliverable that Phase 20
    # generates from. A relative path resolves against the repository root, not the current
    # directory, so the default lands in the repo wherever this is run from.
    [string]$OutFile = 'spec/openapi.generated.json'
)

$ErrorActionPreference = 'Stop'
# Match both sibling scripts. Without strict mode a renamed or absent member on the parsed
# document evaluates to $null, the transform writes null into the patched spec, and the run
# prints Done. and exits 0 - the "reports success while proving nothing" shape this whole
# pipeline is built against.
Set-StrictMode -Version Latest

# --- Constants (edit here if the layout changes) ---
$RepoRoot       = Split-Path -Parent $PSScriptRoot
$DefaultRawSpec = 'spec/openapi.raw.json'
$DefaultOutFile = 'spec/openapi.generated.json'
# The auth-optional, both-schemes form, chosen in D-01 against two measured alternatives. Held
# as a named constant, and parsed from a literal rather than built from a PowerShell array: a
# single-element array piped through the serializer unrolls into an object. The three-element
# form below is unaffected, but a later single-element variant would be corrupted silently.
$SecurityOptionalBothSchemes = '[{},{"X-Api-Key":[]},{"apikey":[]}]'
# The floor below which the staged document cannot be an honest patched spec. The capture is
# 381,380 bytes and its depth-2 truncation is 48,452 after LF normalization, so anything in
# between is a wide margin around a defect that has no near miss.
$MinimumStagedBytes = 350000
# A value eight levels below the root. In a depth-truncated document the whole operation body
# above it has become one placeholder string, so this read returns nothing.
$DeepProbePath     = @('paths', '/api/v3/movie', 'get', 'responses', '200', 'content', 'application/json', 'schema', 'type')
$DeepProbeExpected = 'array'
$HttpMethods       = 'get', 'put', 'post', 'delete', 'options', 'head', 'patch', 'trace'

# The provenance manifest is derived from the output file's own directory rather than
# hardcoded, so a run with a scratch output path cannot overwrite the committed manifest.
$RawPath        = [System.IO.Path]::GetFullPath($(if ([System.IO.Path]::IsPathRooted($RawSpec)) { $RawSpec } else { Join-Path $RepoRoot $RawSpec }))
$OutPath        = [System.IO.Path]::GetFullPath($(if ([System.IO.Path]::IsPathRooted($OutFile)) { $OutFile } else { Join-Path $RepoRoot $OutFile }))
$OutDir         = Split-Path -Parent $OutPath
$ProvenancePath = Join-Path $OutDir 'PROVENANCE.json'
# Every run lands here first and is promoted only once every gate has passed, so a refusal
# cannot leave the committed deliverable replaced by unverified bytes. Declared beside the other
# paths rather than inside the try so the finally block can clear a partial write.
$StagePath      = "$OutPath.incoming"

$DefaultRawPath = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $DefaultRawSpec))
$DefaultOutPath = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $DefaultOutFile))

# Print an ERROR block, discard the staged file, and state that nothing committed was touched.
# Every refusal after step 4 goes through this. The caller keeps its own exit statement, so the
# exit code stays visible at the refusal site rather than hidden inside a helper.
function Write-Refusal {
    param([string[]]$Message)
    if (Test-Path -LiteralPath $Script:StagePath) { Remove-Item -LiteralPath $Script:StagePath -Force }
    foreach ($Line in $Message) { Write-Host $Line -ForegroundColor Red }
    Write-Host "  The staged spec has been discarded. $Script:OutPath and $Script:ProvenancePath are untouched." -ForegroundColor Red
}

Write-Host "Pre-process Whisparr 3 openapi -> $OutPath" -ForegroundColor Cyan
Write-Host "  - reading $RawPath" -ForegroundColor DarkGray

try {
    # --- 0. A fixture input must never be able to promote itself onto the deliverable ---
    # The manifest derivation above already protects the committed PROVENANCE.json from a
    # scratch output path. This protects the committed spec from a scratch input path.
    if ($RawPath -ne $DefaultRawPath -and $OutPath -eq $DefaultOutPath) {
        Write-Host 'ERROR: REFUSED - a non-default input may not be written to the committed output path.' -ForegroundColor Red
        Write-Host "  input  $RawPath" -ForegroundColor Red
        Write-Host "  output $OutPath" -ForegroundColor Red
        Write-Host '  Pass -OutFile with a scratch path as well. A fixture run must not promote itself onto the committed spec.' -ForegroundColor Red
        exit 1
    }
    if (-not (Test-Path -LiteralPath $RawPath)) {
        Write-Host "ERROR: REFUSED - no input document at $RawPath." -ForegroundColor Red
        exit 1
    }

    # --- 1. Parse ---
    $RawBytes = (Get-Item -LiteralPath $RawPath).Length
    $RawSha   = (Get-FileHash -Algorithm SHA256 -LiteralPath $RawPath).Hash.ToLower()
    $Document = [System.Text.Json.Nodes.JsonNode]::Parse((Get-Content -Raw -LiteralPath $RawPath))
    Write-Host "  + parsed $RawBytes bytes, sha256 $RawSha" -ForegroundColor Green

    # --- 2. T1, the root security repair (D-01) ---
    $SecurityBefore = if ($null -eq $Document['security']) { '(absent)' } else { $Document['security'].ToJsonString() }
    # Replaced in place, which keeps security at its position in the root key order. A removal
    # followed by an add would move it to the end and inflate the diff against the capture.
    $Document['security'] = [System.Text.Json.Nodes.JsonNode]::Parse($SecurityOptionalBothSchemes)
    Write-Host "  + T1 security $SecurityBefore -> $($Document['security'].ToJsonString())" -ForegroundColor Green

    # --- 3. T2, the malformed root path (PREP-03, D-14) ---
    # Assert the removal from the call's own return value rather than trusting it. Deleting a
    # key that was already gone would otherwise produce a plausible 272-operation spec from a
    # document this pipeline has never seen, which is the fail-open direction PREP-03 forbids.
    # Not the generator's path allowlist normalizer: it is a prefix allowlist, so excluding one
    # path means enumerating every other top-level path, and a future Whisparr adding a new one
    # would be dropped silently with the count falling below 272 and no error (D-15).
    $PathsObject = $Document['paths'].AsObject()
    if (-not $PathsObject.Remove('/')) {
        Write-Host 'ERROR: REFUSED - paths["/"] is not present in this document.' -ForegroundColor Red
        Write-Host "  $RawPath is not what this pipeline expects. The capture carries a malformed StaticResource catch-all at the key ""/"", and PREP-03 exists to delete exactly that key." -ForegroundColor Red
        Write-Host '  A capture that renamed or repaired it must stop this pipeline rather than silently produce a plausible 272-operation spec. Nothing was written.' -ForegroundColor Red
        exit 1
    }
    Write-Host "  + T2 deleted paths[""/""], $($PathsObject.Count) path items remain" -ForegroundColor Green

    # --- 4. Stage. Never the output path itself ---
    # The relaxed encoder leaves the 25 apostrophes already in the document literal, so the
    # patched spec's diff against the capture shows the transforms and nothing else.
    $Writer = [System.Text.Json.JsonSerializerOptions]::new()
    $Writer.WriteIndented = $true
    $Writer.Encoder = [System.Text.Encodings.Web.JavaScriptEncoder]::UnsafeRelaxedJsonEscaping
    # The indented writer emits the platform newline, which is CRLF here, and .gitattributes
    # declares *.json as eol=lf. Normalize explicitly: the same code on a Linux CI runner would
    # otherwise produce a different hash from a dev machine and defeat PIPE-02 for a reason that
    # has nothing to do with the spec. Exactly one trailing newline, per .editorconfig.
    $StagedJson = (($Document.ToJsonString($Writer)) -replace "`r`n", "`n").TrimEnd("`n") + "`n"
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    [System.IO.File]::WriteAllText($StagePath, $StagedJson, [System.Text.UTF8Encoding]::new($false))
    $StagedBytes = (Get-Item -LiteralPath $StagePath).Length
    $StagedSha   = (Get-FileHash -Algorithm SHA256 -LiteralPath $StagePath).Hash.ToLower()
    Write-Host "  + staged $StagedBytes bytes at $StagePath, sha256 $StagedSha" -ForegroundColor Green

    # --- 5. Gate G1, the census over the staged bytes ---
    # $LASTEXITCODE is the only reliable way to read a child script's exit code: the stop error
    # preference does not intercept it. -SkipProvenanceHash because the manifest beside the
    # output still describes the previous run, and the hash this run records is written at
    # step 8, so comparing against the old manifest here would refuse every legitimate re-run.
    & (Join-Path $PSScriptRoot 'assert-spec-census.ps1') -Path $StagePath -Artifact Patched -SkipProvenanceHash
    if ($LASTEXITCODE -ne 0) {
        $CensusExit = $LASTEXITCODE
        Write-Refusal @("ERROR: census gate failed (exit $CensusExit) for the spec staged at $StagePath.")
        exit $CensusExit
    }

    # --- 6. Gate G2, the depth and size guard ---
    # The census cannot be this gate. Measured: it passes a depth-truncated copy of this
    # document with all four counts green and exit 0, because truncation preserves keys at every
    # level and destroys only values. Three independent assertions, each naming its observed
    # value when it fails.
    if ($StagedBytes -lt $MinimumStagedBytes) {
        Write-Refusal @(
            "ERROR: depth and size guard failed - the staged spec is $StagedBytes bytes, below the floor of $MinimumStagedBytes.",
            '  A patched spec of this document is above 381,000 bytes. A depth-2 serialization of it is 48,452.'
        )
        exit 1
    }

    # Re-parse the staged bytes rather than reasoning about the in-memory document. The point of
    # this gate is to check what was actually written.
    $Staged = [System.Text.Json.Nodes.JsonNode]::Parse((Get-Content -Raw -LiteralPath $StagePath))
    $Probe  = $Staged
    foreach ($Key in $DeepProbePath) {
        if ($null -eq $Probe -or $Probe -isnot [System.Text.Json.Nodes.JsonObject]) { $Probe = $null; break }
        $Probe = $Probe[$Key]
    }
    $ProbeValue = if ($null -eq $Probe) { '(absent)' } else { $Probe.ToJsonString() }
    if ($ProbeValue -ne """$DeepProbeExpected""") {
        Write-Refusal @(
            "ERROR: depth and size guard failed - the value at $($DeepProbePath -join ' -> ') is $ProbeValue, expected ""$DeepProbeExpected"".",
            '  That value sits eight levels below the root. In a depth-truncated document the operation body above it has become a single placeholder string.'
        )
        exit 1
    }

    # An operation must be a JSON object. In a truncated document it is a plain string.
    $OperationsChecked = 0
    foreach ($PathEntry in $Staged['paths'].AsObject()) {
        foreach ($Member in $PathEntry.Value.AsObject()) {
            if ($HttpMethods -notcontains $Member.Key) { continue }
            $OperationsChecked++
            if ($Member.Value -isnot [System.Text.Json.Nodes.JsonObject]) {
                Write-Refusal @(
                    "ERROR: depth and size guard failed - the operation $($Member.Key.ToUpperInvariant()) $($PathEntry.Key) is a $($Member.Value.GetType().Name), not a JSON object.",
                    "  Its serialized value is $($Member.Value.ToJsonString()). An operation body replaced by a scalar is the depth-truncation signature."
                )
                exit 1
            }
        }
    }
    Write-Host "  + depth and size guard passed - $StagedBytes bytes, deep probe ""$DeepProbeExpected"", $OperationsChecked operation bodies are objects" -ForegroundColor Green

    # --- 7. Promote. The first write to anything committed ---
    Move-Item -LiteralPath $StagePath -Destination $OutPath -Force
    Write-Host "  + promoted to $OutPath" -ForegroundColor Green

    # --- 8. The manifest ---
    # capture-spec.ps1 rebuilds this file from its own eleven observed fields, so a re-capture
    # DROPS generatedSpecSha256. That is deliberate: a new capture invalidates the patched spec,
    # and the next census with the Patched profile fails until this script runs again. Without
    # this note the first person to bump the image digest reads that failure as a bug.
    if (Test-Path -LiteralPath $ProvenancePath) {
        $PromotedSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $OutPath).Hash.ToLower()
        $Provenance  = Get-Content -Raw -LiteralPath $ProvenancePath | ConvertFrom-Json
        if ($Provenance.PSObject.Properties.Name -contains 'generatedSpecSha256') {
            $Provenance.generatedSpecSha256 = $PromotedSha
        } else {
            $Provenance | Add-Member -NotePropertyName 'generatedSpecSha256' -NotePropertyValue $PromotedSha
        }
        # The same LF, no-BOM, one-trailing-newline writer capture-spec.ps1 uses for this file.
        # -Depth is explicit and the truncation warning is a terminating error, because this
        # phase must not author a second serializer call that can truncate in silence.
        $ProvenanceJson = ((ConvertTo-Json -InputObject $Provenance -Depth 8 -WarningAction Stop) -replace "`r`n", "`n").TrimEnd("`n") + "`n"
        [System.IO.File]::WriteAllText($ProvenancePath, $ProvenanceJson, [System.Text.UTF8Encoding]::new($false))
        Write-Host "  + wrote generatedSpecSha256 $PromotedSha to $ProvenancePath" -ForegroundColor Green
    } else {
        # Only reachable with a scratch output path, which by design has no manifest beside it.
        Write-Host "  - no PROVENANCE.json beside $OutPath, generatedSpecSha256 not recorded" -ForegroundColor DarkGray
    }

    Write-Host "Done. $OutPath" -ForegroundColor Green
}
finally {
    # A run killed mid-write leaves a partial staging file. It is never the deliverable, and
    # .gitignore does not cover the .incoming suffix, so clearing it here is the only thing
    # keeping a killed run from leaving an untracked file in the working tree.
    if (Test-Path -LiteralPath $StagePath) { Remove-Item -LiteralPath $StagePath -Force }
}
