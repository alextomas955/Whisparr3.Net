<#
.SYNOPSIS
  Move this SDK to a new Whisparr version, or re-verify the pinned one.

.DESCRIPTION
  Runs the whole pipeline in order, stops at the first failure, and names the step that failed and
  what to do about it. With no arguments it re-verifies the digest capture-spec.ps1 pins: every gate
  is exercised and nothing changes but the capturedAt wall clock in spec/PROVENANCE.json.

  -ImageDigest is forwarded to capture-spec.ps1 only when supplied, so the pin stays there alone
  rather than being copied here where the two could drift apart. Each step runs as its own pwsh
  process, so a child that throws still arrives here as an exit code rather than as a stack trace.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\refresh.ps1 -ImageDigest sha256:0123abcd...
  # Move to a new Whisparr image. Expect an operationId assertion to refuse if the new version
  # moved a path; see its message. Omit -ImageDigest to re-verify the pinned one.
#>

[CmdletBinding()]
param(
    # A Whisparr 3 (eros) image digest. Omitted, capture-spec.ps1's own pin is used.
    [string]$ImageDigest = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$GenDir      = $PSScriptRoot
$RepoRoot    = Split-Path -Parent $GenDir
$Solution    = Join-Path $RepoRoot 'Whisparr3.Net.slnx'
$Project     = Join-Path $RepoRoot 'src/Whisparr3.Net/Whisparr3.Net.csproj'
$CaptureArgs = @()
if (-not [string]::IsNullOrWhiteSpace($ImageDigest)) { $CaptureArgs = @('-ImageDigest', $ImageDigest) }

# dotnet localizes its output, so on a non-English runner the marker below would miss and a
# vulnerable closure would read as clean. Set on this process only.
$env:DOTNET_CLI_UI_LANGUAGE = 'en'
$FindingMarker = 'has the following vulnerable packages'

# Each step is what to run and the one thing a reader needs to know when it refuses.
$Steps = @(
    @{ Name = 'capture-spec'
       Run  = { pwsh -NoProfile -File (Join-Path $GenDir 'capture-spec.ps1') @CaptureArgs }
       Remedy = 'The capture failed, or the identity assertion refused what came back. Check that the digest names a Whisparr 3 (eros) image and that Docker can pull and boot it. Nothing downstream ran.' },
    @{ Name = 'preprocess-spec'
       Run  = { pwsh -NoProfile -File (Join-Path $GenDir 'preprocess-spec.ps1') }
       Remedy = 'Most often this is an assertion on the derived operationIds, which means this Whisparr moved a path. Read which assertion refused: a stale override names a path that has moved, and a shape or collision failure names an operation that needs an override. Edit $OperationIdOverrides in preprocess-spec.ps1 and run this script again. The committed spec was not replaced.' },
    @{ Name = 'generate'
       Run  = { pwsh -NoProfile -File (Join-Path $GenDir 'generate.ps1') }
       Remedy = 'Generation refused or the generator container failed. Its own message says whether the generated tree was left touched or untouched; read that before re-running.' },
    @{ Name = 'build'
       Run  = { dotnet build $Solution -c Release --nologo }
       Remedy = 'The regenerated surface does not compile on both target frameworks. Directory.Build.props treats warnings as errors, so a new warning stops here too. A build that passes here is also what proves the derivation delivered one method per operation. Fix it in the spec pre-processing or in the hand-written layer, never inside src/Whisparr3.Net/.' },
    @{ Name = 'package-audit'
       # The verdict is read from the transcript text and never from the exit code. Measured
       # 2026-09-04: against a probe referencing System.Text.RegularExpressions 4.3.0 this command
       # printed a High severity advisory and exited 0, so a gate on the exit code passes a finding.
       # --include-transitive covers both frameworks in one pass. The continuous gate is
       # Directory.Build.props, where NuGetAudit plus TreatWarningsAsErrors turns NU1901 through
       # NU1904 into restore errors; this is the point-in-time confirmation of it.
       Run  = {
           $Transcript = @(dotnet list $Project package --vulnerable --include-transitive 2>&1 | ForEach-Object { $_.ToString() })
           # String.Contains is ordinal, which is what this verbatim marker needs. A looser match on
           # the word vulnerable is satisfied by the echoed command line itself.
           if (($Transcript -join "`n").Contains($FindingMarker)) {
               foreach ($Line in $Transcript) { Write-Host "    $Line" -ForegroundColor Red }
               Write-Host "ERROR: the dependency closure carries a vulnerable package." -ForegroundColor Red
               $global:LASTEXITCODE = 1
           } else {
               Write-Host "  + no vulnerable packages reported across the transitive closure" -ForegroundColor Green
               $global:LASTEXITCODE = 0
           }
       }
       Remedy = 'A finding is a finding to report, never a dependency to remove on reflex. All four shipped packages are required. The transcript above names the package and its advisory.' }
)

Write-Host "Refreshing Whisparr3.Net from $(if ($CaptureArgs.Count -gt 0) { $ImageDigest } else { "capture-spec.ps1's pinned digest" })" -ForegroundColor Cyan

foreach ($Step in $Steps) {
    Write-Host "==> $($Step.Name)" -ForegroundColor Cyan
    & $Step.Run
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: refresh stopped at $($Step.Name), which exited $LASTEXITCODE." -ForegroundColor Red
        Write-Host "  $($Step.Remedy)" -ForegroundColor Red
        exit 1
    }
}

Write-Host "Refresh complete. All $($Steps.Count) steps passed." -ForegroundColor Green
exit 0
