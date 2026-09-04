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

  Every actual value is printed beside its expected value, pass or fail, and any mismatch
  exits non-zero. Runnable standalone against the committed bytes, which is what SPEC-05's
  "before use" means, and also called as the last step of capture-spec.ps1.

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
    [string]$Path
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

# --- 3. Document versions, reported and not asserted (SPEC-05 names four numbers) ---
Write-Census "  ! openapi $($Spec.openapi), info.version $($Spec.info.version) - reported only, not asserted" 'Yellow'

if ($Mismatches -gt 0) {
    Write-Host "ERROR: census failed - $Mismatches of 4 counts do not match this spec. See the actual-versus-expected lines above." -ForegroundColor Red
    exit 1
}

Write-Census '+ census passed' 'Green'
exit 0
