<#
.SYNOPSIS
  Assert that the dependency closure carries no vulnerable package on either target framework.

.DESCRIPTION
  Runs dotnet list package --vulnerable --include-transitive once per target framework and decides
  the verdict from the transcript text, never from the process exit code.

  The exit code is the trap this script exists for. Measured 2026-09-04 against a probe project
  referencing System.Text.RegularExpressions 4.3.0: dotnet list package printed a High severity
  advisory with its URL and then exited 0. A gate written as "run it, fail if the exit code is
  non-zero" passes on a High finding, which is the single most likely way GEN-08 gets a green tick
  it has not earned. The exit code is printed here as a report-only row and is labelled as reported
  rather than asserted.

  Three outcomes per framework, decided by two verbatim marker strings:
    - the finding marker present, which refuses and reprints the advisory rows and their URLs;
    - the clean marker present and the finding marker absent, which passes;
    - anything else, which refuses as an unrecognised third state and reprints the whole
      transcript.

  The third branch is not defensive padding. An unrestored or offline project prints neither
  marker, so without it a failed restore reads as an absence of findings, which is to say as clean.
  An empty transcript lands in the same branch for the same reason.

  $Frameworks is a hardcoded array and is deliberately not a parameter. A caller able to supply the
  framework set could audit one leg and call the closure clean, and a milestone constraint locks
  this library to net8.0 and net10.0 anyway. -ProjectPath is a parameter, because pointing the gate
  at a deliberately poisoned probe project is how the gate itself gets tested.

  This result is point in time. It is true against the nuget.org advisory database on the day it
  ran and no longer. The continuous gate is Directory.Build.props: NuGetAudit is true at
  NuGetAuditLevel low, and TreatWarningsAsErrors turns NU1901 through NU1904 into restore errors,
  so a new advisory fails the build before anyone runs this script.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\assert-package-audit.ps1
  # The ordinary run, over the shipped library. Expected to exit 0 with one clean row per framework.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\assert-package-audit.ps1 -ProjectPath C:\Temp\VulnProbe\VulnProbe.csproj
  # The negative control. Against a project referencing System.Text.RegularExpressions 4.3.0 this
  # exits non-zero and reprints the advisory row, while dotnet list package on the same project
  # exits 0. Build the probe outside this repository, or Directory.Build.props turns NU1903 into a
  # restore error and the gate refuses through the unrecognised-transcript branch instead.
#>

[CmdletBinding()]
param(
    # The project under audit. A path and nothing more. Every expected value in this script is a
    # constant below, so a caller can choose what is audited but never what counts as clean.
    [string]$ProjectPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src/Whisparr3.Net/Whisparr3.Net.csproj')
)

$ErrorActionPreference = 'Stop'
# Match the sibling scripts. Without strict mode a renamed member evaluates to $null, the marker
# test silently compares nothing against nothing, and the gate reports clean while proving nothing.
Set-StrictMode -Version Latest

# --- Constants (assertions, not configuration) ---
# The framework set is closed. A milestone constraint locks net8.0 and net10.0, and a caller-
# supplied set would let one leg be dropped from the audit while the verdict still read clean.
$Frameworks = @('net8.0', 'net10.0')

# The two verbatim strings dotnet list package prints. Measured 2026-09-04 on SDK 10.0.400, both
# against the real project and against a poisoned probe. Matched verbatim and case-sensitively: a
# looser match on the word vulnerable alone is satisfied by the echoed command line and by the
# table header, so it would be present on every branch and would separate nothing.
$CleanMarker   = 'has no vulnerable packages given the current sources'
$FindingMarker = 'has the following vulnerable packages'

# Every line carries an [audit] prefix so the output stays readable when this script is called as a
# child and two transcripts interleave, matching assert-spec-census.ps1.
function Write-Audit {
    param(
        [string]$Message,
        [string]$Colour = 'Gray'
    )
    Write-Host "[audit] $Message" -ForegroundColor $Colour
}

Write-Audit "package audit over $ProjectPath" 'Cyan'

if (-not (Test-Path -LiteralPath $ProjectPath)) {
    Write-Host "ERROR: REFUSED - no project at $ProjectPath, so there is nothing to audit." -ForegroundColor Red
    exit 1
}

# --- 1. One transcript per framework, verdict read from its text ---
$Rows    = @()
$Details = [System.Collections.Generic.List[string]]::new()

foreach ($Framework in $Frameworks) {
    $Transcript = & dotnet list $ProjectPath package --vulnerable --include-transitive --framework $Framework 2>&1
    # Captured immediately, before anything else can overwrite it. It is reported and never
    # asserted; see the report-only row below.
    $DotnetExit = $LASTEXITCODE
    $Lines      = @($Transcript | ForEach-Object { $_.ToString() })
    $Text       = $Lines -join "`n"

    # Ordinal and case-sensitive, which is what String.Contains(string) does. The finding marker is
    # tested first: a transcript carrying it is a finding whatever else it also carries.
    $HasFinding = $Text.Contains($FindingMarker)
    $HasClean   = $Text.Contains($CleanMarker)
    $Verdict    = if ($HasFinding) { 'finding' } elseif ($HasClean) { 'clean' } else { 'unrecognised' }

    $Rows += [pscustomobject]@{
        Name     = $Framework
        Actual   = $Verdict
        Expected = 'clean'
        Matched  = ($Verdict -ceq 'clean')
    }

    if ($Verdict -ceq 'finding') {
        $Details.Add("  ! $Framework carries a vulnerable package. The advisory rows follow.")
        $Advisory = @($Lines | Where-Object {
            $_.Contains($FindingMarker) -or $_.TrimStart().StartsWith('>', [System.StringComparison]::Ordinal) -or $_.Contains('https://')
        })
        # If the shape of the table ever changes, print everything rather than print nothing.
        if ($Advisory.Count -eq 0) { $Advisory = $Lines }
        foreach ($Line in $Advisory) { $Details.Add("      $Line") }
    }
    elseif ($Verdict -ceq 'unrecognised') {
        $Details.Add("  ! $Framework produced a transcript carrying neither marker, $($Lines.Count) line(s). It is refused rather than read as clean, because an unrestored or offline project prints neither string. The whole transcript follows.")
        foreach ($Line in $Lines) { $Details.Add("      $Line") }
    }

    $Details.Add("  ! dotnet list package exited $DotnetExit for $Framework - reported only, not asserted. Measured 2026-09-04: this command exits 0 while printing a High severity finding, so it never decides the verdict here.")
}

# --- 2. Report actual beside expected on every row, pass or fail, then exit once ---
$Mismatches = 0
foreach ($Row in $Rows) {
    if (-not $Row.Matched) { $Mismatches++ }
    $Sigil   = if ($Row.Matched) { '+' } else { '!' }
    $Colour  = if ($Row.Matched) { 'Green' } else { 'Red' }
    $Status  = if ($Row.Matched) { 'OK' } else { 'MISMATCH' }
    Write-Audit ('  {0} {1,-10} actual {2,-14} expected {3,-14} {4}' -f $Sigil, $Row.Name, $Row.Actual, $Row.Expected, $Status) $Colour
}
foreach ($Line in $Details) {
    $Colour = if ($Line.Contains('reported only')) { 'Yellow' } else { 'Red' }
    Write-Audit $Line $Colour
}

if ($Mismatches -gt 0) {
    Write-Host "ERROR: package audit failed - $Mismatches of $(@($Frameworks).Count) framework(s) did not report a clean closure. See the actual-versus-expected lines above." -ForegroundColor Red
    Write-Host "  The verdict is read from the transcript text and not from the process exit code, which was reported above and is 0 even when a High severity advisory is printed." -ForegroundColor Red
    Write-Host "  A finding is a finding to report, never a dependency to remove: all four shipped packages are required, and Microsoft.Extensions.Http.Polly is required by ERGO-06 and by a milestone constraint." -ForegroundColor Red
    exit 1
}

Write-Audit "+ package audit passed, $(@($Frameworks).Count) of $(@($Frameworks).Count) frameworks clean - point in time against the nuget.org advisory database on the day this ran" 'Green'
exit 0
