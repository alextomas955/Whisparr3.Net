<#
.SYNOPSIS
  Assert the Whisparr 3 (Eros) OpenAPI census over a captured spec file.

.DESCRIPTION
  Reads an OpenAPI JSON document and asserts the four counts the repository pins for that
  artifact, so a silently different document cannot pass for the expected one.
    1. paths
    2. operations, counting only members named after an HTTP method
    3. schemas
    4. declared tags

  Which four numbers are expected is selected by -Artifact, a closed set naming the artifact
  under census rather than accepting counts from the caller. Two profiles exist:

    Raw     - spec/openapi.raw.json, the byte-verbatim capture.
              190 paths, 273 operations, 162 schemas, 75 declared tags.
              Hash compared against the manifest field specSha256.
    Patched - spec/openapi.generated.json, the pre-processed spec.
              189 paths, 272 operations, 162 schemas, 75 declared tags.
              Hash compared against the manifest field generatedSpecSha256.

  The Patched profile expects one path and one operation fewer because PREP-03 deletes the
  malformed "GET /" path item in generator/preprocess-spec.ps1.

  It then checks the file against the hash its profile names, read from the PROVENANCE.json
  beside it. The four counts are a weak bound on their own - a different document with the same
  shape passes them, and a depth-truncated document measurably does - and the recorded hash is
  the strongest integrity claim the repo makes, so it is asserted here rather than by hand. The
  check is skipped when no sibling manifest exists, so a scratch spec still censuses.

  A manifest holding no generatedSpecSha256 fails the Patched profile, and that is correct: it
  means a capture has been re-run, which rebuilds the manifest from its own eleven observed
  fields and drops that key, so the patched spec is stale until pre-processing runs again.

  Every actual value is printed beside its expected value, pass or fail, and any mismatch
  exits non-zero. Runnable standalone against the committed bytes, which is what SPEC-05's
  "before use" means, and also called as the gate on a staged capture in capture-spec.ps1 and
  on a staged patched spec in preprocess-spec.ps1.

  The document version and the info version are reported as a warning only. SPEC-05 names
  four numbers, so a future digest bump that moves the document to OpenAPI 3.1 stays visible
  without turning a specification-version change into a census failure.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\assert-spec-census.ps1 -Path I:\cove-dev\Whisparr3.Net\spec\openapi.raw.json
  # The capture. -Artifact defaults to Raw, so capture-spec.ps1 needs no profile argument.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\assert-spec-census.ps1 -Path I:\cove-dev\Whisparr3.Net\spec\openapi.generated.json -Artifact Patched
  # The pre-processed spec. Expected to exit non-zero until preprocess-spec.ps1 has run and
  # written generatedSpecSha256 into the manifest.
#>

[CmdletBinding()]
param(
    # Spec file to census. Mandatory - there is no safe default, because the whole point of
    # this script is to be pointed at one specific file and say what is in it.
    [Parameter(Mandatory = $true)]
    [string]$Path,

    # Skip the recorded-hash check. capture-spec.ps1 passes this because it gates a staged
    # capture whose manifest is written only after the gate passes, so the sibling
    # PROVENANCE.json still holds the previous run's hash and comparing against it would
    # deadlock a deliberate digest bump. preprocess-spec.ps1 passes it for the same reason.
    # Nothing else should pass it.
    [switch]$SkipProvenanceHash,

    # Which artifact is under census. The set is closed on purpose. Expected counts supplied by
    # a caller would be fail-open: a caller can pass whatever it just observed and the gate
    # becomes a tautology that asserts nothing. That is the same failure shape D-15 rejects the
    # generator's path allowlist for. The numbers stay in this script, where they are
    # assertions rather than configuration. Raw is the default, so capture-spec.ps1 needs no
    # edit.
    [ValidateSet('Raw', 'Patched')]
    [string]$Artifact = 'Raw'
)

# Strict mode turns a typo'd property access on the parsed spec into an error instead of a
# silent $null, which is the same silent-pass class this census exists to close. It does not
# catch the .Count unrolling trap below - only @( ) does - so it is a complement, not a
# substitute.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Expected census, per artifact (the Raw row measured against
# ghcr.io/hotio/whisparr@sha256:fab9201..., 3.4.0.1387; the Patched row measured against the
# output of generator/preprocess-spec.ps1 over that same capture) ---
# The profile assigns the same four variables the report below already reads, plus the name of
# the manifest field to compare the file's hash against, so adding an artifact is a branch here
# and nothing else. Comparing the patched spec against the raw capture's specSha256 is a
# mismatch that is not a defect, which is why the field name rides with the profile.
switch ($Artifact) {
    'Raw' {
        $ExpectedPaths      = 190
        $ExpectedOperations = 273
        $ExpectedSchemas    = 162
        $ExpectedTags       = 75
        $ProvenanceField    = 'specSha256'
    }
    'Patched' {
        $ExpectedPaths      = 189
        $ExpectedOperations = 272
        $ExpectedSchemas    = 162
        $ExpectedTags       = 75
        $ProvenanceField    = 'generatedSpecSha256'
    }
}

# Every line carries a [census] prefix so the output stays readable when capture-spec.ps1
# calls this script as a child and the two transcripts interleave.
function Write-Census {
    param(
        [string]$Message,
        [string]$Colour = 'Gray'
    )
    Write-Host "[census] $Message" -ForegroundColor $Colour
}

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "ERROR: no spec file at $Path" -ForegroundColor Red
    exit 1
}

Write-Census "census over $Path" 'Cyan'

$Spec = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json

# --- 1. Count. The @( ) wrapper is load-bearing, not decoration ---
# $Spec.paths.PSObject.Properties.Count does not return 190. PowerShell unrolls .Count across
# the property collection and returns an array of 190 ones. Compared with -eq that array is
# empty and therefore falsy, so the assertion would pass against any spec at all; compared
# with -ne it is all 190 elements and therefore truthy, so it would fail against a correct
# one. Both directions are wrong. Wrap first, then take the count.
$PathItems   = @($Spec.paths.PSObject.Properties)
$ActualPaths = $PathItems.Count

# A path item can legitimately carry parameters, summary, description, servers and $ref
# beside its operations, so counting every member would inflate the operation total.
$HttpMethods      = 'get', 'put', 'post', 'delete', 'options', 'head', 'patch', 'trace'
$ActualOperations = 0
foreach ($PathItem in $PathItems) {
    foreach ($Member in @($PathItem.Value.PSObject.Properties)) {
        if ($HttpMethods -contains $Member.Name.ToLower()) { $ActualOperations++ }
    }
}

$ActualSchemas = @($Spec.components.schemas.PSObject.Properties).Count
$ActualTags    = @($Spec.tags).Count

# --- 2. Report actual beside expected on every row, pass or fail ---
$Rows = @(
    [pscustomobject]@{ Name = 'paths';        Actual = $ActualPaths;      Expected = $ExpectedPaths }
    [pscustomobject]@{ Name = 'operations';   Actual = $ActualOperations; Expected = $ExpectedOperations }
    [pscustomobject]@{ Name = 'schemas';      Actual = $ActualSchemas;    Expected = $ExpectedSchemas }
    [pscustomobject]@{ Name = 'declaredTags'; Actual = $ActualTags;       Expected = $ExpectedTags }
)

$Mismatches = 0
foreach ($Row in $Rows) {
    $Matched = $Row.Actual -eq $Row.Expected
    if (-not $Matched) { $Mismatches++ }
    $Sigil   = if ($Matched) { '+' } else { '!' }
    $Verdict = if ($Matched) { 'OK' } else { 'MISMATCH' }
    $Colour  = if ($Matched) { 'Green' } else { 'Red' }
    Write-Census ('  {0} {1,-12} actual {2,-6} expected {3,-6} {4}' -f $Sigil, $Row.Name, $Row.Actual, $Row.Expected, $Verdict) $Colour
}

# --- 3. The file against the hash recorded beside it ---
# The four counts above cannot see content, only shape. This is what actually bounds the bytes.
if (-not $SkipProvenanceHash) {
    $ProvenancePath = Join-Path (Split-Path -Parent (Resolve-Path -LiteralPath $Path)) 'PROVENANCE.json'
    if (Test-Path -LiteralPath $ProvenancePath) {
        $Provenance = Get-Content -Raw -LiteralPath $ProvenancePath | ConvertFrom-Json
        # Strict mode makes a missing field a terminating error, and a manifest without the
        # one this profile names is a real thing to report rather than crash on.
        $ExpectedSha = if ($Provenance.PSObject.Properties.Name -contains $ProvenanceField) { $Provenance.$ProvenanceField } else { $null }
        $ActualSha   = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLower()
        $ShaMatched  = ($null -ne $ExpectedSha) -and ($ActualSha -eq $ExpectedSha)
        if (-not $ShaMatched) { $Mismatches++ }
        Write-Census ('  {0} {1,-12} {2}' -f $(if ($ShaMatched) { '+' } else { '!' }), 'sha256', $(if ($ShaMatched) { 'OK' } else { 'MISMATCH' })) $(if ($ShaMatched) { 'Green' } else { 'Red' })
        Write-Census "      actual   $ActualSha" $(if ($ShaMatched) { 'Green' } else { 'Red' })
        Write-Census "      recorded $(if ($null -eq $ExpectedSha) { "(no $ProvenanceField in the manifest)" } else { $ExpectedSha }) - $ProvenancePath" $(if ($ShaMatched) { 'Green' } else { 'Red' })
    } else {
        Write-Census "  - sha256       no PROVENANCE.json beside this file, recorded-hash check skipped" 'DarkGray'
    }
}

# --- 4. Document versions, reported and not asserted (SPEC-05 names four numbers) ---
Write-Census "  ! openapi $($Spec.openapi), info.version $($Spec.info.version) - reported only, not asserted" 'Yellow'

if ($Mismatches -gt 0) {
    Write-Host "ERROR: census failed - $Mismatches assertion(s) do not match this spec. See the actual-versus-expected lines above." -ForegroundColor Red
    exit 1
}

Write-Census '+ census passed' 'Green'
exit 0
