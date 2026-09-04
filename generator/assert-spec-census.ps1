<#
.SYNOPSIS
  Assert the Whisparr 3 (Eros) OpenAPI census over a captured spec file.

.DESCRIPTION
  Reads an OpenAPI JSON document and asserts the four counts the spec capture pins, so a
  silently different document cannot pass for the captured one.
    1. paths        - 190
    2. operations   - 273, counting only members named after an HTTP method
    3. schemas      - 162
    4. declared tags - 75

  It then checks the file against the specSha256 recorded in the PROVENANCE.json beside it.
  The four counts are a weak bound on their own - a different document with 190 paths and 273
  operations would pass them - and the recorded hash is the strongest integrity claim the repo
  makes, so it is asserted here rather than by hand. The check is skipped when no sibling
  manifest exists, so a scratch spec still censuses.

  Every actual value is printed beside its expected value, pass or fail, and any mismatch
  exits non-zero. Runnable standalone against the committed bytes, which is what SPEC-05's
  "before use" means, and also called as the gate on a staged capture in capture-spec.ps1.

  The operation count is 273 and not 272 on purpose. The raw capture still carries the
  malformed "GET /" path item; dropping it is PREP-03 in Phase 19, not a correction to make
  here.

  The document version and the info version are reported as a warning only. SPEC-05 names
  four numbers, so a future digest bump that moves the document to OpenAPI 3.1 stays visible
  without turning a specification-version change into a census failure.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\assert-spec-census.ps1 -Path I:\cove-dev\Whisparr3.Net\spec\openapi.raw.json
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
    # deadlock a deliberate digest bump. Nothing else should pass it.
    [switch]$SkipProvenanceHash
)

# Strict mode turns a typo'd property access on the parsed spec into an error instead of a
# silent $null, which is the same silent-pass class this census exists to close. It does not
# catch the .Count unrolling trap below - only @( ) does - so it is a complement, not a
# substitute.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Expected census (measured against ghcr.io/hotio/whisparr@sha256:fab9201..., 3.4.0.1387) ---
$ExpectedPaths      = 190
$ExpectedOperations = 273
$ExpectedSchemas    = 162
$ExpectedTags       = 75

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
        # Strict mode makes a missing specSha256 a terminating error, and a manifest without
        # one is a real thing to report rather than crash on.
        $ExpectedSha = if ($Provenance.PSObject.Properties.Name -contains 'specSha256') { $Provenance.specSha256 } else { $null }
        $ActualSha   = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLower()
        $ShaMatched  = ($null -ne $ExpectedSha) -and ($ActualSha -eq $ExpectedSha)
        if (-not $ShaMatched) { $Mismatches++ }
        Write-Census ('  {0} {1,-12} {2}' -f $(if ($ShaMatched) { '+' } else { '!' }), 'sha256', $(if ($ShaMatched) { 'OK' } else { 'MISMATCH' })) $(if ($ShaMatched) { 'Green' } else { 'Red' })
        Write-Census "      actual   $ActualSha" $(if ($ShaMatched) { 'Green' } else { 'Red' })
        Write-Census "      recorded $(if ($null -eq $ExpectedSha) { '(no specSha256 in the manifest)' } else { $ExpectedSha }) - $ProvenancePath" $(if ($ShaMatched) { 'Green' } else { 'Red' })
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
