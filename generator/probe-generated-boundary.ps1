<#
.SYNOPSIS
  Prove that one generate.ps1 run removes everything inside the generated tree and reaches nothing
  outside it.

.DESCRIPTION
  This is the hostile probe SETUP-07's "and is protected from regeneration" clause was waiting for.
  Phase 18 arranged for the probe and correctly declined to claim the result, because the generator
  had never run. It runs here, once, against this repository (D-16, D-20).
    1. Refuse unless git status --porcelain is empty in the repository root, naming the offending
       paths. The probe plants files inside the committed tree, so without this gate it cannot tell
       its own residue from work already in progress.
    2. Snapshot the four guarded files by SHA-256.
    3. Snapshot the generated tree as a sorted "<repository-relative path> <sha256>" manifest.
    4. Plant three shapes: a file in Api, a file in Model, and a file inside a fabricated
       Client/Stale directory that no manifest entry mentions.
    5. Run generate.ps1 once, as a child process.
    6. Assert, printing every row actual beside expected, and exit once at the end.

  Byte identity is decided by Get-FileHash -Algorithm SHA256 compared as lowercase strings. Never
  by LastWriteTime: the copy step in generate.ps1 rewrites nothing at the four guarded paths, so a
  timestamp comparison would pass even if the content had changed. Never by file size or file
  count either, for the same reason.

  The three plant shapes are not redundant. Copy-Item -Recurse into an existing target merges,
  measured 2026-09-04, so it neither replaces the target nor nests inside it (D-17). Without the
  Remove-Item -Recurse in generate.ps1 step 4, a planted file survives the copy and compiles. The
  fabricated Client/Stale directory is the shape a real stale-file incident takes after an
  operationId rename moves a file: a delete implemented as "remove the files the old manifest
  listed" leaves the directory behind, and Remove-Item -Recurse does not.

  .openapi-generator-ignore is one of the four guarded files even though the generator rewrites it
  on every run. It comes out byte-identical, so the assertion holds, and asserting it is what would
  catch an accidental gen-config.yaml edit riding along with a regeneration.

  This script takes no parameters on purpose. The planted paths, the guarded paths and the expected
  file count are assertions, not configuration. A caller able to supply them could plant a file
  outside the tree and watch it survive, which proves nothing about the boundary.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\probe-generated-boundary.ps1
  # The ordinary run. Exits 0 with every row OK.

.EXAMPLE
  # A refusal run. With any uncommitted change in the working tree the probe stops at step 1,
  # names the offending paths, plants nothing and exits 1.
  New-Item -ItemType File -Path I:\cove-dev\Whisparr3.Net\scratch.txt
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\probe-generated-boundary.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
# Match both sibling scripts. Without strict mode a renamed member evaluates to $null, a hash
# comparison silently compares nothing against nothing, and the probe prints OK while proving
# nothing. Strict mode does not catch the .Count unrolling trap; only @( ) does.
Set-StrictMode -Version Latest

# --- Constants (edit here if the layout changes) ---
$RepoRoot     = Split-Path -Parent $PSScriptRoot
$RepoRootFull = (Resolve-Path -LiteralPath $RepoRoot).Path
$PkgDir       = Join-Path $RepoRoot 'src/Whisparr3.Net'
$GeneratePath = Join-Path $PSScriptRoot 'generate.ps1'

# The five generated subdirectories, read as GEN-03 means it and as D-07 settles it. The manifest
# is taken over these and never recursively over $PkgDir, because after any build
# obj/<configuration>/<tfm>/Whisparr3.Net.AssemblyInfo.cs sits under the package root and would
# join a manifest that is supposed to describe generator output.
$GeneratedSubdirs = @('Api', 'Client', 'Extensions', 'Logging', 'Model')

# The four hand-owned files the boundary must hold for: the file beside the deleted subdirectories,
# the file above them, the file outside the tree entirely, and the file the generator itself
# rewrites on every run.
$Guarded = @(
    'src/Whisparr3.Net/Whisparr3.Net.csproj',
    'Directory.Build.props',
    'src/hand-written/PLACEHOLDER.cs',
    '.openapi-generator-ignore'
)

# Three shapes, not one. See the .DESCRIPTION for why each is here.
$Planted = @(
    'src/Whisparr3.Net/Api/ZZ_PLANTED.cs',
    'src/Whisparr3.Net/Model/ZZ_PLANTED2.cs',
    'src/Whisparr3.Net/Client/Stale/ZZ_PLANTED3.cs'
)
$FabricatedDir = 'src/Whisparr3.Net/Client/Stale'

# A hardcoded assertion, not a derived number. An empty manifest compared against an empty manifest
# differs in 0 lines, so without this row a probe that snapshotted nothing would report a passing
# whole-tree comparison. Measured 2026-09-04 against openapi-generator 7.25.0 at the pinned digest.
$ExpectedTreeFiles = 262

# Every line carries a [probe] prefix so the output stays readable while generate.ps1's own
# transcript interleaves with it, matching assert-spec-census.ps1 and assert-generated-tree.ps1.
function Write-Probe {
    param(
        [string]$Message,
        [string]$Colour = 'Gray'
    )
    Write-Host "[probe] $Message" -ForegroundColor $Colour
}

# Every refusal that can fire after step 4 must say the planted files are still in the tree. This
# probe is the one script here that deliberately dirties the committed tree, so a refusal claiming
# the repository is untouched would be false.
#
# A refusal writes to the host and then exits. The cmdlet that writes an error record instead
# throws under $ErrorActionPreference = 'Stop', which makes the exit after it unreachable.
function Write-PlantedResidue {
    Write-Host "  The three planted files are still in the working tree:" -ForegroundColor Red
    foreach ($Relative in $Planted) { Write-Host "    $Relative" -ForegroundColor Red }
    Write-Host "  The fabricated directory $FabricatedDir is still there too." -ForegroundColor Red
    Write-Host "  Recovery is: git -C $RepoRoot clean -fd $($Planted -join ' ') $FabricatedDir" -ForegroundColor Red
    Write-Host "  This probe planted nothing else, so nothing else needs cleaning." -ForegroundColor Red
}

function Get-GuardedHash {
    param([string]$Relative)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $RepoRoot $Relative)).Hash.ToLower()
}

# A sorted "<repository-relative path> <sha256>" manifest. Sorted by the relative path, so the
# comparison is independent of the order Get-ChildItem happens to enumerate in.
function Get-TreeManifest {
    $Hashes = @{}
    $Paths  = [System.Collections.Generic.List[string]]::new()
    foreach ($Subdir in $GeneratedSubdirs) {
        $SubdirPath = Join-Path $PkgDir $Subdir
        if (-not (Test-Path -LiteralPath $SubdirPath)) { continue }
        foreach ($File in @(Get-ChildItem -LiteralPath $SubdirPath -Recurse -File)) {
            $Relative = $File.FullName.Substring($RepoRootFull.Length).TrimStart('\', '/').Replace('\', '/')
            $Paths.Add($Relative)
            $Hashes[$Relative] = (Get-FileHash -Algorithm SHA256 -LiteralPath $File.FullName).Hash.ToLower()
        }
    }
    $Paths.Sort([System.StringComparer]::Ordinal)
    return @($Paths | ForEach-Object { "$_ $($Hashes[$_])" })
}

Write-Probe "boundary probe over $PkgDir" 'Cyan'

# --- 1. Refuse on a dirty working tree, before anything is planted ---
# The same gate-before-you-touch-the-deliverable discipline capture-spec.ps1 carries. Here it is
# what lets the probe attribute any residue afterwards to itself.
$Dirty = @(git -C $RepoRoot status --porcelain)
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: REFUSED - git status exited $LASTEXITCODE in $RepoRoot, so the clean-tree precondition could not be read." -ForegroundColor Red
    Write-Host "  Nothing was planted and nothing in $PkgDir was touched." -ForegroundColor Red
    exit 1
}
if ($Dirty.Count -gt 0) {
    Write-Host "ERROR: REFUSED - the working tree is not clean: $($Dirty.Count) path(s) reported by git status --porcelain." -ForegroundColor Red
    foreach ($Line in $Dirty) { Write-Host "    $Line" -ForegroundColor Red }
    Write-Host "  This probe plants files inside the committed tree, so on a dirty tree it cannot tell its own residue from work already in progress." -ForegroundColor Red
    Write-Host "  Nothing was planted and nothing in $PkgDir was touched." -ForegroundColor Red
    exit 1
}
Write-Probe '  + working tree clean, 0 paths reported by git status --porcelain' 'Green'

foreach ($Relative in $Guarded) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $Relative))) {
        Write-Host "ERROR: REFUSED - no file at $Relative, so the boundary has nothing to be shown holding for." -ForegroundColor Red
        Write-Host "  Nothing was planted and nothing in $PkgDir was touched." -ForegroundColor Red
        exit 1
    }
}

# --- 2. Snapshot the four guarded files by content, never by timestamp ---
$GuardedBefore = @{}
foreach ($Relative in $Guarded) { $GuardedBefore[$Relative] = Get-GuardedHash -Relative $Relative }

# --- 3. Snapshot the generated tree ---
$TreeBefore = @(Get-TreeManifest)
Write-Probe "  + snapshotted $($TreeBefore.Count) generated files and $(@($Guarded).Count) guarded files by sha256" 'Green'

# --- 4. Plant three shapes inside the generated tree ---
foreach ($Relative in $Planted) {
    $Full   = Join-Path $RepoRoot $Relative
    $Parent = Split-Path -Parent $Full
    New-Item -ItemType Directory -Force -Path $Parent | Out-Null
    Set-Content -LiteralPath $Full -Value '// planted by probe-generated-boundary.ps1'
    Write-Probe "  - planted $Relative" 'DarkGray'
}

try {
    # --- 5. One generation run, as a child process ---
    # A child process rather than an in-process call, because generate.ps1 returns without an
    # explicit exit on its success path. Called with & the surviving $LASTEXITCODE would then be
    # the last external command's, which is docker's, and the propagated code would be right by
    # accident. A child process makes the code the script's own.
    pwsh -NoProfile -File $GeneratePath
    $GenerateExit = $LASTEXITCODE
    if ($GenerateExit -ne 0) {
        Write-Host "ERROR: REFUSED - generate.ps1 exited $GenerateExit, so the boundary was never exercised." -ForegroundColor Red
        Write-PlantedResidue
        # Propagated, not flattened to 1, so the generator's own code survives the probe.
        exit $GenerateExit
    }

    # --- 6. Assert, one row per assertion, exit once at the end ---
    $Rows = @()

    foreach ($Relative in $Planted) {
        $Present = Test-Path -LiteralPath (Join-Path $RepoRoot $Relative)
        $Rows += [pscustomobject]@{
            Name     = $Relative
            Actual   = $(if ($Present) { 'present' } else { 'absent' })
            Expected = 'absent'
            Matched  = (-not $Present)
        }
    }

    $DirPresent = Test-Path -LiteralPath (Join-Path $RepoRoot $FabricatedDir)
    $Rows += [pscustomobject]@{
        Name     = "$FabricatedDir/"
        Actual   = $(if ($DirPresent) { 'present' } else { 'absent' })
        Expected = 'absent'
        Matched  = (-not $DirPresent)
    }

    foreach ($Relative in $Guarded) {
        $After = Get-GuardedHash -Relative $Relative
        $Rows += [pscustomobject]@{
            Name     = "sha256 $Relative"
            Actual   = $After
            Expected = $GuardedBefore[$Relative]
            # -cne, because a hash is an identifier and PowerShell's -ne is case-insensitive. Both
            # sides are already lowercased, so this compares what it appears to compare.
            Matched  = (-not ($After -cne $GuardedBefore[$Relative]))
        }
    }

    $TreeAfter = @(Get-TreeManifest)
    $Rows += [pscustomobject]@{
        Name     = 'treeFiles'
        Actual   = $TreeAfter.Count
        Expected = $ExpectedTreeFiles
        Matched  = ($TreeAfter.Count -eq $ExpectedTreeFiles)
    }
    $Differing = @(Compare-Object -ReferenceObject $TreeBefore -DifferenceObject $TreeAfter -CaseSensitive)
    $Rows += [pscustomobject]@{
        Name     = 'treeManifestDiff'
        Actual   = $Differing.Count
        Expected = 0
        Matched  = ($Differing.Count -eq 0)
    }

    # One column width for every row, so a 64-character hash and the word absent line up without
    # padding the short rows out to 64 characters.
    $Width = 8
    foreach ($Row in $Rows) { if ("$($Row.Actual)".Length -gt $Width) { $Width = "$($Row.Actual)".Length } }
    $Format = '  {0} {1,-45} actual {2,-' + $Width + '} expected {3} {4}'

    $Failures = 0
    foreach ($Row in $Rows) {
        if (-not $Row.Matched) { $Failures++ }
        $Sigil   = if ($Row.Matched) { '+' } else { '!' }
        $Verdict = if ($Row.Matched) { 'OK' } else { 'MISMATCH' }
        $Colour  = if ($Row.Matched) { 'Green' } else { 'Red' }
        Write-Probe ($Format -f $Sigil, $Row.Name, $Row.Actual, $Row.Expected, $Verdict) $Colour
    }

    if ($Differing.Count -gt 0) {
        # Name them. A bare count sends the reader back to hashing the tree by hand.
        foreach ($Line in @($Differing | Select-Object -First 10)) {
            Write-Probe "  ! $($Line.SideIndicator) $($Line.InputObject)" 'Red'
        }
    }

    if ($Failures -gt 0) {
        Write-Host "ERROR: boundary probe failed - $Failures assertion(s) do not match. See the actual-versus-expected lines above." -ForegroundColor Red
        if (@($Rows | Where-Object { $_.Expected -eq 'absent' -and -not $_.Matched }).Count -gt 0) { Write-PlantedResidue }
        exit 1
    }

    Write-Probe "+ boundary probe passed, $(@($Planted).Count) planted files and the fabricated directory removed, $(@($Guarded).Count) guarded files byte-unchanged, $($TreeAfter.Count) generated files identical" 'Green'
    exit 0
}
catch {
    # Any terminating error after the plant leaves the planted files behind. Say so, rather than
    # letting the default error record imply the repository is untouched.
    Write-Host "ERROR: the probe stopped after planting: $($_.Exception.Message)" -ForegroundColor Red
    Write-PlantedResidue
    exit 1
}
