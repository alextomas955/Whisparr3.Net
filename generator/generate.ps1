<#
.SYNOPSIS
  Regenerate the Whisparr3.Net client tree from the committed spec, using the pinned generator.

.DESCRIPTION
  Stages the two inputs into a temporary root, runs the pinned generator image against it, gates
  the staged tree, then deletes the five generated subdirectories and copies the new ones back.
  The generator never prunes, so the delete is the pruner.

  Docker on this machine cannot bind-mount the I: drive. Measured 2026-09-04: a bind mount of an I:
  path lists an empty directory and exits 0, so the mount looks like it worked and is not.
  Generation therefore stages under the user temp directory on C: and the result is copied back.
  gen-config.yaml needs no edit for that, because its /local-rooted paths already resolve against a
  mirrored staging root. Do not try to repair the mount by restarting Docker Desktop or by running
  wsl --shutdown: this machine hosts live containers.

  Invoking Docker from pwsh needs no MSYS_NO_PATHCONV=1. The rewrite of /local/... into a path
  under the Git installation directory happens only when Docker is invoked from Git Bash.

  This script takes no output-root parameter on purpose. Its destination is the whole repository
  tree, and a redirect parameter without a promote guard is the fail-open shape preprocess-spec.ps1
  is hardened against. A sandbox run is a copy of the whole repository.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\generate.ps1
#>

[CmdletBinding()]
param(
    # openapi-generator-cli 7.25.0, the pin recorded at the top of generator/gen-config.yaml. By
    # digest and never by tag, so a retagged image cannot change this library's public surface.
    [string]$ImageDigest = 'sha256:2ab0a9680222de65dc9d3baf861aa02b99e1b80c211d8221ebf3ae8f8a102524'
)

$ErrorActionPreference = 'Stop'
# Without strict mode a count comparison silently compares nothing against nothing and the run
# prints Done. and exits 0. Strict mode does not catch the .Count unrolling trap; only @( ) does.
Set-StrictMode -Version Latest

$RepoRoot   = Split-Path -Parent $PSScriptRoot
$Image      = "openapitools/openapi-generator-cli@$ImageDigest"
$PkgDir     = Join-Path $RepoRoot 'src/Whisparr3.Net'
$GenMetaDir = Join-Path $RepoRoot '.openapi-generator'
# The generated tree is these five subdirectories, not src/Whisparr3.Net itself: the hand-owned
# csproj sits beside them and survives every run. One list, so the delete set and the copy set can
# never drift apart.
$GeneratedSubdirs = @('Api', 'Client', 'Extensions', 'Logging', 'Model')
# What the pinned image produces from the committed spec. A constant and never a parameter: a
# caller-supplied expected count makes the gate a tautology. .openapi-generator/FILES is written by
# the same run that wrote the files, so it agrees with a truncated tree as readily as a complete
# one, and without this count a generation emitting ten files would replace the committed 262 at
# exit 0. Move it in the same commit that moves the tree.
$ExpectedCs = 262
# A GUID suffix makes a collision between two concurrent runs impossible, and the finally below
# removes only this run's own root.
$Stage       = Join-Path ([System.IO.Path]::GetTempPath()) ("whisparr3-generate-" + [guid]::NewGuid().ToString('N'))
$StagePkgDir = Join-Path $Stage 'src/Whisparr3.Net'

# Count over the five generated subdirectories, never recursively over the package root: after any
# build obj/<config>/<tfm>/Whisparr3.Net.AssemblyInfo.cs sits under it and would be counted.
function Get-GeneratedCsFile {
    param([string]$PackageRoot)
    foreach ($Subdir in $GeneratedSubdirs) {
        $SubdirPath = Join-Path $PackageRoot $Subdir
        if (Test-Path -LiteralPath $SubdirPath) { Get-ChildItem -LiteralPath $SubdirPath -Recurse -File -Filter *.cs }
    }
}

Write-Host "Generate Whisparr3.Net client -> $PkgDir" -ForegroundColor Cyan
Write-Host "  - image $Image" -ForegroundColor DarkGray

# False until step 3 starts deleting. The catch branches on it, because whether the repository is
# mid-replace is the one fact a caller needs and the one a bare error record does not carry.
$TreeTouched = $false

try {
    # --- 1. Stage the two inputs, mirroring the repository layout ---
    New-Item -ItemType Directory -Force -Path (Join-Path $Stage 'spec')      | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Stage 'generator') | Out-Null
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'spec/openapi.generated.json') -Destination (Join-Path $Stage 'spec')      -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'generator/gen-config.yaml')   -Destination (Join-Path $Stage 'generator') -Force

    # --- 2. Run the pinned image, then gate the staged tree before anything committed is deleted ---
    # The image runs as uid 0. On a Linux runner that makes every directory it creates inside the
    # bind mount root-owned, and the finally below then cannot unlink under them. Windows bind
    # mounts carry no POSIX ownership, so the flag is added only where it means something.
    $UserArgs  = if ($IsWindows) { @() } else { @('--user', "$(id -u):$(id -g)") }
    $RunOutput = docker run --rm @UserArgs -v "${Stage}:/local" $Image generate -c /local/generator/gen-config.yaml 2>&1
    if ($LASTEXITCODE -ne 0) {
        $GeneratorExit = $LASTEXITCODE
        Write-Host ($RunOutput -join [Environment]::NewLine) -ForegroundColor Red
        Write-Host "ERROR: REFUSED - the generator exited $GeneratorExit for $Image. Nothing in $PkgDir was touched." -ForegroundColor Red
        exit $GeneratorExit
    }
    $StagedCs       = @(Get-GeneratedCsFile -PackageRoot $StagePkgDir)
    # A subdirectory the generator did not emit at all is invisible to the count, because
    # Get-GeneratedCsFile skips a missing one. Step 4 would then throw partway through the copy,
    # after the delete, which is the expensive place to discover it.
    $MissingSubdirs = @($GeneratedSubdirs | Where-Object { -not (Test-Path -LiteralPath (Join-Path $StagePkgDir $_)) })
    if ($StagedCs.Count -ne $ExpectedCs -or $MissingSubdirs.Count -gt 0) {
        Write-Host "ERROR: REFUSED - the staged tree holds $($StagedCs.Count) .cs files across the five generated subdirectories, expected $ExpectedCs, with $($MissingSubdirs.Count) subdirectories absent. Nothing in $PkgDir was touched." -ForegroundColor Red
        exit 1
    }
    Write-Host "  + generator exited 0, staged $($StagedCs.Count) .cs files" -ForegroundColor Green

    # --- 3. Replace, never merge ---
    # Copy-Item -Recurse into an existing target merges: it neither replaces the target nor nests
    # inside it, so without this delete a stale file inside Api/ survives the copy and compiles.
    # Set before the first unlink: from here to the end of step 4 the repository is mid-replace.
    $TreeTouched = $true
    foreach ($Subdir in $GeneratedSubdirs) {
        $Target = Join-Path $PkgDir $Subdir
        if (Test-Path -LiteralPath $Target) { Remove-Item -LiteralPath $Target -Recurse -Force }
    }
    if (Test-Path -LiteralPath $GenMetaDir) { Remove-Item -LiteralPath $GenMetaDir -Recurse -Force }

    # --- 4. Copy back exactly what the generator owns, and nothing else ---
    # Not the whole staged tree, which would drag spec/ and generator/ over the committed originals.
    New-Item -ItemType Directory -Force -Path $PkgDir | Out-Null
    foreach ($Subdir in $GeneratedSubdirs) {
        Copy-Item -LiteralPath (Join-Path $StagePkgDir $Subdir) -Destination $PkgDir -Recurse -Force
    }
    Copy-Item -LiteralPath (Join-Path $Stage '.openapi-generator')     -Destination $RepoRoot -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $Stage '.openapi-generator-ignore') -Destination $RepoRoot -Force

    $CopiedCs = @(Get-GeneratedCsFile -PackageRoot $PkgDir)
    if ($CopiedCs.Count -ne $StagedCs.Count) {
        Write-Host "ERROR: copied $($CopiedCs.Count) .cs files but staged $($StagedCs.Count). The tree under $PkgDir is now partially written. Recovery is to re-run generate.ps1, which deletes and rewrites the whole tree." -ForegroundColor Red
        exit 1
    }
    Write-Host "  + copied $($CopiedCs.Count) .cs files into $PkgDir" -ForegroundColor Green
    Write-Host "Done. $PkgDir" -ForegroundColor Green
}
catch {
    # Without this, a terminating error between the delete and the count assertion escapes as a raw
    # error record that says nothing about the repository, by which point the five subdirectories
    # are gone. This is the only script here that deletes a committed deliverable.
    if ($TreeTouched) {
        $Present = @(Get-GeneratedCsFile -PackageRoot $PkgDir)
        Write-Host "ERROR: generate.ps1 stopped after it had begun replacing the tree: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  $PkgDir now holds $($Present.Count) .cs files where a complete tree holds $ExpectedCs. Recovery is to re-run generate.ps1, or git -C $RepoRoot checkout -- src/Whisparr3.Net .openapi-generator .openapi-generator-ignore" -ForegroundColor Red
    } else {
        Write-Host "ERROR: generate.ps1 stopped before it had begun replacing the tree: $($_.Exception.Message). Nothing in $PkgDir was touched." -ForegroundColor Red
    }
    exit 1
}
finally {
    # Non-fatal on purpose. A terminating error here would replace the pending exit code and rewrite
    # the verdict of the run above it. A leftover staging root is a nuisance to name, not a reason
    # to call a correct generation a failure.
    if (Test-Path -LiteralPath $Stage) {
        try { Remove-Item -LiteralPath $Stage -Recurse -Force }
        catch { Write-Host "  ! could not remove the staging root $Stage. Remove it by hand. The verdict above stands." -ForegroundColor Yellow }
    }
}
