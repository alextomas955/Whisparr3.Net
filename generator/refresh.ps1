<#
.SYNOPSIS
  Move this SDK to a new Whisparr version, or re-verify the pinned one.

.DESCRIPTION
  Runs the whole pipeline in order, stops at the first failure, and names the step that failed and
  what to do about it. With no arguments it runs against the digest capture-spec.ps1 pins, which is
  a no-op re-verification: every gate is exercised and nothing in the repository changes.

  -ImageDigest is forwarded to capture-spec.ps1 only when it is supplied. The pin therefore stays
  in capture-spec.ps1 alone, rather than being copied here where the two could drift apart.

  Each step runs as its own pwsh process, so a child that throws rather than exiting still arrives
  here as an exit code and not as a stack trace over a half-finished pipeline.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\refresh.ps1
  # Re-verify the pinned digest end to end.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\refresh.ps1 -ImageDigest sha256:0123abcd...
  # Move to a new Whisparr image. Expect the map gate to refuse if the new version added or
  # removed operations; see its message.
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
$SpecPath    = Join-Path $RepoRoot 'spec/openapi.generated.json'
$CaptureArgs = @()
if (-not [string]::IsNullOrWhiteSpace($ImageDigest)) { $CaptureArgs = @('-ImageDigest', $ImageDigest) }

# Each step is what to run and the one thing a reader needs to know when it refuses.
$Steps = @(
    @{ Name = 'capture-spec'
       Run  = { pwsh -NoProfile -File (Join-Path $GenDir 'capture-spec.ps1') @CaptureArgs }
       Remedy = 'The capture failed, or its census refused what came back. Check that the digest names a Whisparr 3 (eros) image and that Docker can pull and boot it. Nothing downstream ran and nothing was replaced.' },
    @{ Name = 'preprocess-spec'
       Run  = { pwsh -NoProfile -File (Join-Path $GenDir 'preprocess-spec.ps1') }
       Remedy = 'Most often this is the map gate, which means this Whisparr added or removed operations. Review each proposed operationId printed above, add it to generator/operation-ids.json, delete every orphaned entry it also lists, and run this script again. The committed spec was not replaced.' },
    @{ Name = 'generate'
       Run  = { pwsh -NoProfile -File (Join-Path $GenDir 'generate.ps1') }
       Remedy = 'Generation refused or the generator container failed. Its own message says whether the generated tree was left touched or untouched; read that before re-running.' },
    @{ Name = 'build'
       Run  = { dotnet build $Solution -c Release --nologo }
       Remedy = 'The regenerated surface does not compile on both target frameworks. Directory.Build.props treats warnings as errors, so a new warning stops here too. Fix it in the spec pre-processing or in the hand-written layer, never inside src/Whisparr3.Net/.' },
    @{ Name = 'assert-generated-tree'
       Run  = { pwsh -NoProfile -File (Join-Path $GenDir 'assert-generated-tree.ps1') }
       Remedy = 'The generated tree no longer matches the expected counts. If the new Whisparr legitimately moved them, move the per-directory table in assert-generated-tree.ps1 and $ExpectedCs in generate.ps1 in the same commit as the tree.' },
    @{ Name = 'assert-spec-census'
       Run  = { pwsh -NoProfile -File (Join-Path $GenDir 'assert-spec-census.ps1') -Path $SpecPath -Artifact Patched }
       Remedy = 'The patched spec no longer carries the expected shape. The expected counts are constants in assert-spec-census.ps1 and are assertions, not configuration; move them only with the numbers a reviewer has seen.' }
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
