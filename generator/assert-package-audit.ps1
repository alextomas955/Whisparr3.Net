<#
.SYNOPSIS
  Assert that the dependency closure carries no vulnerable package on either target framework.

.DESCRIPTION
  Runs dotnet list package --vulnerable --include-transitive once per target framework and reads
  the verdict from the transcript text, never from the exit code. Two measurements, both
  2026-09-04, are why. Against a probe referencing System.Text.RegularExpressions 4.3.0 the
  command printed a High severity advisory and exited 0, so a gate on the exit code passes a
  finding. And with --source pointed at a directory that does not exist it printed the clean
  marker verbatim and exited 0, which is what the marker's own "given the current sources" wording
  warns about, so clean also requires the transcript to name the nuget.org source. Everything else
  is refused with the transcript reprinted, including a transcript carrying neither marker, which
  is what an unrestored or offline project prints and would otherwise read as clean.

  The verdict is point in time. The continuous gate is Directory.Build.props, where NuGetAudit at
  NuGetAuditLevel low plus TreatWarningsAsErrors turns NU1901 through NU1904 into restore errors.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\assert-package-audit.ps1
#>

[CmdletBinding()]
param(
    # What is audited. What counts as clean is a constant below and never a parameter, so a caller
    # can point the gate at a poisoned probe project but cannot soften its verdict.
    [string]$ProjectPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src/Whisparr3.Net/Whisparr3.Net.csproj')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Closed on purpose. A caller-supplied framework set could drop one leg and still read clean.
$Frameworks = @('net8.0', 'net10.0')
# dotnet localizes its output, so on a non-English runner every marker below would miss and a
# correct closure would be refused with no visible cause. Set on this process only.
$env:DOTNET_CLI_UI_LANGUAGE = 'en'
$CleanMarker   = 'has no vulnerable packages given the current sources'
$FindingMarker = 'has the following vulnerable packages'
$SourcesMarker = 'The following sources were used:'
$AuditSource   = 'https://api.nuget.org/v3/index.json'

if (-not (Test-Path -LiteralPath $ProjectPath)) {
    Write-Host "ERROR: REFUSED - no project at $ProjectPath, so there is nothing to audit." -ForegroundColor Red
    exit 1
}
Write-Host "[audit] package audit over $ProjectPath" -ForegroundColor Cyan

foreach ($Framework in $Frameworks) {
    $Lines = @(& dotnet list $ProjectPath package --vulnerable --include-transitive --framework $Framework 2>&1 |
        ForEach-Object { $_.ToString() })
    $Text  = $Lines -join "`n"
    # String.Contains(string) is ordinal and case-sensitive, which is what these verbatim markers
    # need. A looser match on the word vulnerable is satisfied by the echoed command line.
    $Clean = -not $Text.Contains($FindingMarker) -and $Text.Contains($CleanMarker) -and
             $Text.Contains($SourcesMarker) -and $Text.Contains($AuditSource)
    if (-not $Clean) {
        Write-Host "ERROR: package audit failed on $Framework. Its whole transcript follows." -ForegroundColor Red
        foreach ($Line in $Lines) { Write-Host "      $Line" -ForegroundColor Red }
        Write-Host "  Clean requires that transcript to carry ""$CleanMarker"", not ""$FindingMarker"", and to name $AuditSource among the sources it used." -ForegroundColor Red
        Write-Host '  The process exit code decides nothing here: dotnet list package exits 0 while printing a High severity finding.' -ForegroundColor Red
        Write-Host '  A finding is a finding to report, never a dependency to remove. All four shipped packages are required.' -ForegroundColor Red
        exit 1
    }
    Write-Host "[audit]   + $Framework clean, $AuditSource named in its transcript" -ForegroundColor Green
}

Write-Host "[audit] + package audit passed, $($Frameworks.Count) of $($Frameworks.Count) frameworks - point in time against the nuget.org advisory database on the day this ran" -ForegroundColor Green
exit 0
