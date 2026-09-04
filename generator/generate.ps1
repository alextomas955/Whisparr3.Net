<#
.SYNOPSIS
  Regenerate the Whisparr3.Net client tree from the committed spec, using the pinned generator.

.DESCRIPTION
  Runs openapi-generator inside a digest-pinned container and replaces this repository's generated
  tree with what that run produced.
    1. Stage the two inputs, spec/openapi.generated.json and generator/gen-config.yaml, into a
       fresh temporary root laid out to mirror the repository.
    2. Run the pinned image against that root and check its exit code immediately.
    3. Gate the staged tree, before anything committed is deleted. The manifest must exist, every
       path it lists must exist on disk under the stage, and the staged .cs count must equal the
       count this script pins. The count is what makes the gate mean something: the manifest is
       written by the run that wrote the files, so it agrees with a truncated tree as readily as
       with a complete one.
    4. Delete the five generated subdirectories and .openapi-generator/, so the replace is a
       replace. The generator never prunes stale files, so the delete is the pruner.
    5. Copy back exactly what the generator owns, and nothing else.
    6. Assert the copied .cs count equals the staged .cs count.

  Docker on this machine cannot bind-mount the I: drive. Measured 2026-09-04: a bind mount of an
  I: path lists an empty directory and exits 0, so the mount looks like it worked and is not
  (D-01). Generation therefore runs against a staging root under the user temp directory on C:
  and the result is copied back (D-02, D-03). The committed gen-config.yaml needs no edit for
  that, because its /local-rooted paths already resolve against a mirrored staging root. Do not
  try to repair the mount by restarting Docker Desktop or by running wsl --shutdown: this machine
  hosts a live Whisparr instance and a Testcontainers suite, and that repair is the owner's call
  at a quiet moment (D-04).

  Invoking Docker from pwsh needs no MSYS_NO_PATHCONV=1, measured 2026-09-04. The rewrite of
  /local/... into a path under the Git installation directory happens only when Docker is invoked
  from Git Bash, which is where a verifier reproducing this run by hand is most likely to hit it
  (D-05).

  This script has no scratch mode on purpose, and takes no output-root parameter. Its destination
  is the whole repository tree, and a redirect parameter without a promote guard is exactly the
  fail-open shape preprocess-spec.ps1 was hardened against. A sandbox run is a copy of the whole
  repository.

  The script writes no file of its own. Everything that lands arrives by Copy-Item from a tree the
  container produced, so the repository's LF, no BOM, one trailing newline convention is the
  container's to satisfy and not this script's to apply.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\generate.ps1
  # The ordinary run. Replaces the five generated subdirectories, .openapi-generator/ and
  # .openapi-generator-ignore with the output of the pinned image.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\generate.ps1 -ImageDigest sha256:0000000000000000000000000000000000000000000000000000000000000000
  # A refusal run. No such image exists, docker exits non-zero, and the script refuses at step 2
  # with the container transcript printed and nothing in src/Whisparr3.Net touched.
#>

[CmdletBinding()]
param(
    # Generator image digest. Defaults to the pin recorded at the top of generator/gen-config.yaml,
    # openapi-generator-cli 7.25.0. The image is referenced by digest and never by tag, so a
    # retagged image cannot change this library's public surface silently. Nothing in this phase
    # detects a caller passing a different digest; the default is the pin.
    [string]$ImageDigest = 'sha256:2ab0a9680222de65dc9d3baf861aa02b99e1b80c211d8221ebf3ae8f8a102524'
)

$ErrorActionPreference = 'Stop'
# Match both sibling scripts. Without strict mode a renamed or absent member evaluates to $null,
# a count comparison silently compares nothing against nothing, and the run prints Done. and exits
# 0 - the "reports success while proving nothing" shape this pipeline is built against. Strict
# mode does not catch the .Count unrolling trap; only @( ) does.
Set-StrictMode -Version Latest

# --- Constants (edit here if the layout changes) ---
$RepoRoot   = Split-Path -Parent $PSScriptRoot
$Image      = "openapitools/openapi-generator-cli@$ImageDigest"
$SpecRel    = 'spec/openapi.generated.json'
$ConfigRel  = 'generator/gen-config.yaml'
$IgnoreRel  = '.openapi-generator-ignore'
$PkgDir     = Join-Path $RepoRoot 'src/Whisparr3.Net'
$GenMetaDir = Join-Path $RepoRoot '.openapi-generator'
# The generated tree, read as GEN-03 means it: these five subdirectories, not src/Whisparr3.Net
# itself. The hand-owned Whisparr3.Net.csproj sits beside them at the package root and survives
# every run, which is what GEN-04 names explicitly (D-07). This list is both the delete set and
# the copy set, so the two can never drift apart.
$GeneratedSubdirs = @('Api', 'Client', 'Extensions', 'Logging', 'Model')
# The count the pinned image produces from the committed spec, measured 2026-09-04. A constant and
# never a parameter, matching assert-generated-tree.ps1 and probe-generated-boundary.ps1: a
# caller-supplied expected count makes the gate a tautology. Without it the only volume condition
# in this script was "at least one", and .openapi-generator/FILES is written by the same run that
# wrote the files, so a truncated generation listing ten paths satisfies the manifest cross-check
# by construction and the 262-file committed tree is replaced by ten files at exit 0. Edit here
# when the spec or the generator moves, in the same commit that moves the committed tree, and in
# the same commit as the two sibling scripts.
$ExpectedCs = 262
# Staged under GetTempPath rather than mktemp -d, which resolves differently under pwsh -File and
# pwsh -Command. The GUID suffix is what makes a collision between two concurrent runs impossible:
# each run creates its own root, and the finally block removes only that root.
$Stage       = Join-Path ([System.IO.Path]::GetTempPath()) ("whisparr3-generate-" + [guid]::NewGuid().ToString('N'))
$StagePkgDir = Join-Path $Stage 'src/Whisparr3.Net'

# Every refusal that fires BEFORE step 4 leaves the committed tree exactly as it was, and says so
# in the same sentence every time. The sentence is written once here rather than repeated at each
# gate, which is how its wording drifted in the prototype.
#
# The post-copy refusal at step 6 deliberately does NOT call this helper. It is the one refusal
# that fires after the delete, so the tree is not untouched and saying otherwise would be false.
#
# A refusal writes to the host and then exits. The cmdlet that writes an error record instead
# throws under $ErrorActionPreference = 'Stop', which makes the exit after it unreachable.
function Write-Refusal {
    param([string[]]$Message)
    foreach ($Line in $Message) { Write-Host $Line -ForegroundColor Red }
    Write-Host "  Nothing in $PkgDir was touched." -ForegroundColor Red
}

# Count .cs files over the five generated subdirectories of a package root, never recursively over
# the package root itself. After any build, obj/<configuration>/<tfm>/Whisparr3.Net.AssemblyInfo.cs
# sits under the committed package root, and a recursive count would refuse a correct run in any
# repository where a build has happened.
#
# The staged side and the committed side stay comparable only while src/Whisparr3.Net/ holds no
# hand-written .cs file. Whisparr3.Net/CLAUDE.md forbids one, so that invariant holds by contract
# rather than by accident.
function Get-GeneratedCsFile {
    param([string]$PackageRoot)
    foreach ($Subdir in $GeneratedSubdirs) {
        $SubdirPath = Join-Path $PackageRoot $Subdir
        if (Test-Path -LiteralPath $SubdirPath) {
            Get-ChildItem -LiteralPath $SubdirPath -Recurse -File -Filter *.cs
        }
    }
}

Write-Host "Generate Whisparr3.Net client -> $PkgDir" -ForegroundColor Cyan
Write-Host "  - image $Image" -ForegroundColor DarkGray
Write-Host "  - staging root $Stage" -ForegroundColor DarkGray

try {
    # --- 1. Stage the two inputs, mirroring the repository layout ---
    New-Item -ItemType Directory -Force -Path (Join-Path $Stage 'spec')      | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Stage 'generator') | Out-Null
    Copy-Item -LiteralPath (Join-Path $RepoRoot $SpecRel)   -Destination (Join-Path $Stage 'spec')      -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot $ConfigRel) -Destination (Join-Path $Stage 'generator') -Force
    $StagedSpecBytes = (Get-Item -LiteralPath (Join-Path $Stage $SpecRel)).Length
    Write-Host "  + staged 2 input files, spec $StagedSpecBytes bytes" -ForegroundColor Green

    # --- 2. Run the pinned image ---
    # The transcript is captured rather than streamed, matching capture-spec.ps1. The run prints
    # one line per generated file, and that volume buries the message that matters when it fails.
    # The whole transcript is printed on the failure path below, where it is the diagnosis.
    $RunOutput = docker run --rm -v "${Stage}:/local" $Image generate -c /local/generator/gen-config.yaml 2>&1
    if ($LASTEXITCODE -ne 0) {
        $GeneratorExit = $LASTEXITCODE
        Write-Host ($RunOutput -join [Environment]::NewLine) -ForegroundColor Red
        Write-Refusal @("ERROR: REFUSED - the generator exited $GeneratorExit for $Image.")
        exit $GeneratorExit
    }
    Write-Host "  + generator exited 0, $(@($RunOutput).Count) transcript lines" -ForegroundColor Green

    # --- 3. Gate the staged tree, before anything committed is deleted ---
    # capture-spec.ps1 records the incident this discipline came from: its gate used to run after
    # the committed deliverable had already been replaced. Three conditions, and the message names
    # all three observed counts whichever one of them fired.
    $StageManifest = Join-Path $Stage '.openapi-generator/FILES'
    if (-not (Test-Path -LiteralPath $StageManifest)) {
        Write-Refusal @("ERROR: REFUSED - the run wrote no .openapi-generator/FILES under $Stage.")
        exit 1
    }
    $Listed   = @(Get-Content -LiteralPath $StageManifest | Where-Object { $_.Trim() -ne '' })
    $Absent   = @($Listed | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Stage $_)) })
    $StagedCs = @(Get-GeneratedCsFile -PackageRoot $StagePkgDir)
    if ($Listed.Count -eq 0 -or $Absent.Count -gt 0 -or $StagedCs.Count -ne $ExpectedCs) {
        Write-Refusal @("ERROR: REFUSED - the staged tree is not the expected tree: $($Listed.Count) paths listed in the manifest, $($Absent.Count) of them missing on disk, $($StagedCs.Count) .cs files across the five generated subdirectories, expected $ExpectedCs.")
        exit 1
    }
    Write-Host "  + staged $($StagedCs.Count) .cs files, expected $ExpectedCs, $($Listed.Count) manifest entries, 0 missing" -ForegroundColor Green

    # --- 4. Replace, never merge. The generator never prunes, so the delete is the pruner ---
    # Measured 2026-09-04: Copy-Item -Recurse into an existing target merges. It neither replaces
    # the target nor nests inside it, so without this delete a stale file inside Api/ survives the
    # copy and compiles (D-17).
    $DeletedSubdirs = 0
    foreach ($Subdir in $GeneratedSubdirs) {
        $Target = Join-Path $PkgDir $Subdir
        if (Test-Path -LiteralPath $Target) {
            Remove-Item -LiteralPath $Target -Recurse -Force
            $DeletedSubdirs++
        }
    }
    if (Test-Path -LiteralPath $GenMetaDir) { Remove-Item -LiteralPath $GenMetaDir -Recurse -Force }
    Write-Host "  - deleted $DeletedSubdirs of $(@($GeneratedSubdirs).Count) generated subdirectories, and .openapi-generator/" -ForegroundColor DarkGray

    # --- 5. Copy back exactly what the generator owns ---
    # Only these paths, not the whole staged tree. Copying the whole tree back would drag spec/ and
    # generator/ over the committed originals, which is harmless only until someone edits the
    # staged copy. .openapi-generator-ignore is overwritten in place rather than deleted first,
    # because it comes out byte-identical on every run.
    New-Item -ItemType Directory -Force -Path $PkgDir | Out-Null
    foreach ($Subdir in $GeneratedSubdirs) {
        Copy-Item -LiteralPath (Join-Path $StagePkgDir $Subdir) -Destination $PkgDir -Recurse -Force
    }
    Copy-Item -LiteralPath (Join-Path $Stage '.openapi-generator') -Destination $RepoRoot -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $Stage $IgnoreRel)          -Destination $RepoRoot -Force

    # --- 6. Assert the copied count equals the staged count ---
    # A cheap post-condition that catches a partially failed copy, which is otherwise silent. This
    # is the one refusal in the script that fires after the delete, so it must not carry the
    # untouched sentence Write-Refusal appends. It names the state the tree is actually in.
    $CopiedCs = @(Get-GeneratedCsFile -PackageRoot $PkgDir)
    if ($CopiedCs.Count -ne $StagedCs.Count) {
        Write-Host "ERROR: REFUSED - copied $($CopiedCs.Count) .cs files but staged $($StagedCs.Count)." -ForegroundColor Red
        Write-Host "  The generated tree under $PkgDir is now partially written: the five generated subdirectories were deleted and only $($CopiedCs.Count) of the $($StagedCs.Count) staged files were copied back." -ForegroundColor Red
        Write-Host "  Recovery is to re-run generate.ps1, which deletes and rewrites the whole tree from a fresh generator run." -ForegroundColor Red
        exit 1
    }
    Write-Host "  + copied $($CopiedCs.Count) .cs files into $PkgDir" -ForegroundColor Green
    Write-Host "  ! generated from image digest $ImageDigest - reported only, not asserted" -ForegroundColor Yellow

    Write-Host "Done. $PkgDir" -ForegroundColor Green
}
finally {
    # Removes this run's own GUID-suffixed root and nothing else, so a concurrent run is
    # unaffected. Unconditional, because an interrupted run would otherwise leave a full generated
    # tree sitting under the user temp directory.
    if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
}
