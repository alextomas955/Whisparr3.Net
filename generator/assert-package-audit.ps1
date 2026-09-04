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

  Four outcomes per framework, decided by three verbatim marker strings:
    - the finding marker present, which refuses and reprints the advisory rows and their URLs;
    - the clean marker present, the finding marker absent and the audit source named among the
      sources the run used, which passes;
    - the clean marker present without that source, which refuses as unsourced and reprints the
      whole transcript;
    - anything else, which refuses as an unrecognised state and reprints the whole transcript.

  Neither refusing branch is defensive padding. An unrestored or offline project prints neither
  marker, so without the unrecognised branch a failed restore reads as an absence of findings,
  which is to say as clean; an empty transcript lands there for the same reason. A project that is
  restored against a feed carrying no advisory data prints the clean marker verbatim and exits 0,
  which is the unsourced branch: measured 2026-09-04 with --source pointed at a directory that does
  not exist, and the reason the clean marker's own wording is "given the current sources".

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

# The three markers below are English strings and dotnet localizes its output, so on a runner with
# a non-English UI culture every one of them would miss and a correct closure would be refused
# through the unrecognised branch with no visible cause. This variable is what keeps them true. It
# is set on this process only, is inherited by the dotnet child processes, and dies with the run.
$env:DOTNET_CLI_UI_LANGUAGE = 'en'

# The verbatim strings dotnet list package prints. Measured 2026-09-04 on SDK 10.0.400, both
# against the real project and against a poisoned probe. Matched verbatim and case-sensitively: a
# looser match on the word vulnerable alone is satisfied by the echoed command line and by the
# table header, so it would be present on every branch and would separate nothing.
$CleanMarker   = 'has no vulnerable packages given the current sources'
$FindingMarker = 'has the following vulnerable packages'

# The advisory database is reachable only through a source that carries one, so the sources the run
# used are part of the assertion and not context. The clean marker says "given the current sources"
# because the answer is source-dependent, and nothing else in this transcript is. Measured
# 2026-09-04 against this project with --source pointed at a directory that does not exist:
#
#   The following sources were used:
#      C:/Users/raygo/AppData/Local/Temp/nonexistent-feed-xyz
#
#   The given project `Whisparr3.Net` has no vulnerable packages given the current sources.
#   EXIT=0
#
# That transcript carries the clean marker verbatim. Read on the clean marker alone it is a green
# tick for GEN-08 that no advisory database was consulted for, which is the same defect one level
# up from the exit code this script already refuses to trust.
$SourcesMarker = 'The following sources were used:'
$AuditSource   = 'https://api.nuget.org/v3/index.json'

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
    # The clean marker alone is not a clean verdict. It is a statement about the sources the run
    # read, so clean also requires the transcript to name the audit source among them.
    $HasSources = $Text.Contains($SourcesMarker) -and $Text.Contains($AuditSource)
    $Verdict    = if ($HasFinding) { 'finding' } elseif ($HasClean -and $HasSources) { 'clean' } elseif ($HasClean) { 'unsourced' } else { 'unrecognised' }

    $Rows += [pscustomobject]@{
        Name     = $Framework
        Actual   = $Verdict
        Expected = 'clean'
        Matched  = ($Verdict -ceq 'clean')
    }
    # A row of its own rather than only a condition on the verdict, so the passing transcript
    # records which source answered the question instead of leaving it to be assumed.
    $Rows += [pscustomobject]@{
        Name     = "$Framework sources"
        Actual   = $(if ($HasSources) { 'nuget.org consulted' } else { 'nuget.org absent' })
        Expected = 'nuget.org consulted'
        Matched  = $HasSources
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
    elseif ($Verdict -ceq 'unsourced') {
        $Details.Add("  ! $Framework printed the clean marker without naming $AuditSource among the sources it used, so no advisory database was consulted and the marker states only that the sources it did read carry no advisory. It is refused rather than read as clean. The whole transcript follows.")
        foreach ($Line in $Lines) { $Details.Add("      $Line") }
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
    Write-Audit ('  {0} {1,-16} actual {2,-20} expected {3,-20} {4}' -f $Sigil, $Row.Name, $Row.Actual, $Row.Expected, $Status) $Colour
}
foreach ($Line in $Details) {
    $Colour = if ($Line.Contains('reported only')) { 'Yellow' } else { 'Red' }
    Write-Audit $Line $Colour
}

if ($Mismatches -gt 0) {
    Write-Host "ERROR: package audit failed - $Mismatches of $(@($Rows).Count) assertion(s) across $(@($Frameworks).Count) framework(s) did not hold. See the actual-versus-expected lines above." -ForegroundColor Red
    Write-Host "  The verdict is read from the transcript text and not from the process exit code, which was reported above and is 0 even when a High severity advisory is printed." -ForegroundColor Red
    Write-Host "  A clean verdict also requires the transcript to name $AuditSource among the sources the run used. The clean marker is source-dependent by its own wording, and a restore against a feed carrying no advisory data prints it verbatim and exits 0." -ForegroundColor Red
    Write-Host "  A finding is a finding to report, never a dependency to remove: all four shipped packages are required, and Microsoft.Extensions.Http.Polly is required by ERGO-06 and by a milestone constraint." -ForegroundColor Red
    exit 1
}

Write-Audit "+ package audit passed, $(@($Frameworks).Count) of $(@($Frameworks).Count) frameworks clean against $AuditSource, named in each transcript - point in time against the nuget.org advisory database on the day this ran" 'Green'
exit 0
