<#
.SYNOPSIS
  Assert the generated Whisparr3.Net tree against the counts this repository pins for it.

.DESCRIPTION
  Reads the committed generated tree, its manifest and the built assembly, and asserts what a
  correct generation run produces, so a silently different tree cannot pass for the expected one.
    1. The five per-directory .cs counts and their total.
    2. The .openapi-generator manifest: its line count, that every path it lists exists on disk,
       that every .cs file in the tree is listed in it, that it lists no .csproj, and that it
       lists the one file library=generichost emits.
    3. The recorded generator version.
    4. The 272-operation gate, taken over the compiled public surface rather than over source
       text. Every operationId in generator/operation-ids.json must appear as a public
       <id>Async method on an exported type in namespace Whisparr3.Net.Api.

  The expected numbers are constants in this script and are deliberately not parameters. Counts
  supplied by a caller are fail-open: a caller can pass whatever it just observed and the gate
  becomes a tautology that asserts nothing. That is the reasoning assert-spec-census.ps1 records
  for its own closed -Artifact set, applied here.

  Step 4 is the reason this script needs a build. A source-text search for <id>Async also matches
  a comment and matches an OrDefaultAsync variant, so it proves the token is in a file rather than
  that the operation is callable. Reflection over the compiled assembly proves the public surface.
  When the assembly is absent the gate refuses; it never passes by skipping itself. An assembly
  older than the newest file under census is refused for the same reason: a present assembly is
  not necessarily this tree's assembly, and generate.ps1 replaces the tree without building it, so
  present-but-stale is the ordinary state after a regeneration rather than an exotic one.

  Every actual value is printed beside its expected value, pass or fail. Mismatches accumulate and
  the script exits once at the end, so a regeneration that moves several counts prints all of them
  in one run.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\assert-generated-tree.ps1
  # The ordinary run, over the Release build.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\assert-generated-tree.ps1 -Configuration Debug
  # The same census against the Debug output. Expected to refuse with a named message until
  # dotnet build -c Debug has produced bin/Debug/net8.0/Whisparr3.Net.dll.
#>

[CmdletBinding()]
param(
    # Which build output carries the public surface under census. The set is closed, and no
    # expected count is a parameter of this script at all; see the constants block below.
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release'
)

# Strict mode turns a typo'd property access into an error instead of a silent $null, which is the
# same silent-pass class this census exists to close. It does not catch the .Count unrolling trap
# below - only @( ) does - so it is a complement, not a substitute.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Expected census (edit here only when the spec or the generator changes) ---
# Measured 2026-09-04 against openapi-generator 7.25.0 at the digest pinned in gen-config.yaml,
# over spec/openapi.generated.json.
$RepoRoot                 = Split-Path -Parent $PSScriptRoot
$PkgDir                   = Join-Path $RepoRoot 'src/Whisparr3.Net'
$CsprojPath               = Join-Path $PkgDir 'Whisparr3.Net.csproj'
$ManifestPath             = Join-Path $RepoRoot '.openapi-generator/FILES'
$VersionPath              = Join-Path $RepoRoot '.openapi-generator/VERSION'
$ConfigPath               = Join-Path $PSScriptRoot 'gen-config.yaml'
$MapPath                  = Join-Path $PSScriptRoot 'operation-ids.json'
$AssemblyPath             = Join-Path $PkgDir "bin/$Configuration/net8.0/Whisparr3.Net.dll"
$ExpectedPerDir           = [ordered]@{ Api = 76; Client = 20; Model = 162; Extensions = 3; Logging = 1 }
# Derived from the table above rather than restated, so the two can never disagree. A partial edit
# after a spec refresh - moving one per-directory value and not the total - is otherwise undetected,
# because both are compared against the tree and neither is compared against the other. The other
# two statements of this number, $ExpectedManifestLines below and $ExpectedCs in generate.ps1, are
# deliberate independent copies and must be moved in the same commit as this table.
$ExpectedCs               = [int](($ExpectedPerDir.Values | Measure-Object -Sum).Sum)
$ExpectedManifestLines    = 262
$ExpectedOperations       = 272
$ExpectedGeneratorVersion = '7.25.0'
# library=generichost is not echoed into any file this script can read, so it is asserted through
# its one observable consequence: this file exists only under that library.
$GenericHostMarker        = 'src/Whisparr3.Net/Extensions/IHostBuilderExtensions.cs'

# Every line carries a [tree] prefix so the output stays readable when this script is called as a
# child and two transcripts interleave, matching assert-spec-census.ps1.
function Write-TreeCensus {
    param(
        [string]$Message,
        [string]$Colour = 'Gray'
    )
    Write-Host "[tree] $Message" -ForegroundColor $Colour
}

$RepoRootFull = (Resolve-Path -LiteralPath $RepoRoot).Path

# Repository-root-relative, forward slashes, which is the form .openapi-generator/FILES uses.
function Get-RepoRelativePath {
    param([string]$FullName)
    $Relative = $FullName.Substring($RepoRootFull.Length).TrimStart('\', '/')
    return $Relative.Replace('\', '/')
}

Write-TreeCensus "census over $PkgDir ($Configuration build)" 'Cyan'

foreach ($Required in @($ManifestPath, $VersionPath, $MapPath)) {
    if (-not (Test-Path -LiteralPath $Required)) {
        Write-Host "ERROR: REFUSED - no file at $Required, so the census has nothing to assert against." -ForegroundColor Red
        exit 1
    }
}

# --- 1. Count .cs over the five generated subdirectories, and never recursively over $PkgDir ---
# After any build, obj/<configuration>/<tfm>/Whisparr3.Net.AssemblyInfo.cs sits under the package
# root. A recursive count rooted there would report 264 for a correct tree and refuse it.
$Rows    = @()
$CsFiles = @()
foreach ($Subdir in $ExpectedPerDir.Keys) {
    $SubdirPath = Join-Path $PkgDir $Subdir
    # The @( ) wrapper is load-bearing, not decoration. PowerShell unrolls .Count across a
    # property collection and returns an array of ones, which is falsy under -eq and truthy under
    # -ne, so the assertion would be wrong in both directions. Wrap first, then take the count.
    $Found = @()
    if (Test-Path -LiteralPath $SubdirPath) {
        $Found = @(Get-ChildItem -LiteralPath $SubdirPath -Recurse -File -Filter *.cs)
    }
    $CsFiles += $Found
    $Rows += [pscustomobject]@{
        Name     = $Subdir
        Actual   = $Found.Count
        Expected = $ExpectedPerDir[$Subdir]
        Matched  = ($Found.Count -eq $ExpectedPerDir[$Subdir])
    }
}
$CsFiles = @($CsFiles)
$Rows += [pscustomobject]@{ Name = 'csTotal'; Actual = $CsFiles.Count; Expected = $ExpectedCs; Matched = ($CsFiles.Count -eq $ExpectedCs) }

# --- 2. The manifest ---
$Listed = @(Get-Content -LiteralPath $ManifestPath | Where-Object { $_.Trim() -ne '' })
$Rows += [pscustomobject]@{ Name = 'manifestLines'; Actual = $Listed.Count; Expected = $ExpectedManifestLines; Matched = ($Listed.Count -eq $ExpectedManifestLines) }

$ManifestSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($Entry in $Listed) { [void]$ManifestSet.Add($Entry.Trim()) }

$AbsentOnDisk = @($Listed | Where-Object { -not (Test-Path -LiteralPath (Join-Path $RepoRoot $_)) })
$Rows += [pscustomobject]@{ Name = 'listedAbsent'; Actual = $AbsentOnDisk.Count; Expected = 0; Matched = ($AbsentOnDisk.Count -eq 0) }

# The only check that catches a file hand-added to the generated tree between two regenerations.
# The delete in generate.ps1 removes such a file on the next run; this reports it before then.
$Unlisted = @($CsFiles | Where-Object { -not $ManifestSet.Contains((Get-RepoRelativePath $_.FullName)) })
$Rows += [pscustomobject]@{ Name = 'csUnlisted'; Actual = $Unlisted.Count; Expected = 0; Matched = ($Unlisted.Count -eq 0) }

# GEN-04. The csproj is hand-owned, so the generator must claim no csproj at all.
$ListedCsproj = @($Listed | Where-Object { $_.Trim().EndsWith('.csproj', [System.StringComparison]::Ordinal) })
$Rows += [pscustomobject]@{ Name = 'listedCsproj'; Actual = $ListedCsproj.Count; Expected = 0; Matched = ($ListedCsproj.Count -eq 0) }

$MarkerPresent = $ManifestSet.Contains($GenericHostMarker)
$Rows += [pscustomobject]@{ Name = 'genericHost'; Actual = $(if ($MarkerPresent) { 1 } else { 0 }); Expected = 1; Matched = $MarkerPresent }

# --- 3. The recorded generator version ---
# Compared with -cne. PowerShell's -ne is case-insensitive, and a version string is an identifier.
$ActualVersion  = (Get-Content -Raw -LiteralPath $VersionPath).Trim()
$VersionMatched = -not ($ActualVersion -cne $ExpectedGeneratorVersion)
$Rows += [pscustomobject]@{ Name = 'generatorVersion'; Actual = $ActualVersion; Expected = $ExpectedGeneratorVersion; Matched = $VersionMatched }

# --- 4. The 272-operation gate, over the compiled public surface ---
# Read the map's values, not its keys: the shape is "<METHOD> <path>": "<OperationId>".
$Map    = Get-Content -Raw -LiteralPath $MapPath | ConvertFrom-Json
$MapIds = @($Map.PSObject.Properties | ForEach-Object { $_.Value })
$Rows  += [pscustomobject]@{ Name = 'mapOperations'; Actual = $MapIds.Count; Expected = $ExpectedOperations; Matched = ($MapIds.Count -eq $ExpectedOperations) }

$AssemblyPresent = Test-Path -LiteralPath $AssemblyPath
$Rows += [pscustomobject]@{ Name = 'apiAssembly'; Actual = $(if ($AssemblyPresent) { 1 } else { 0 }); Expected = 1; Matched = $AssemblyPresent }

$MissingIds = @()
if ($AssemblyPresent) {
    # The gate reads a compiled surface, so it must assert that the surface it reads was compiled
    # from the tree it is counting. Existence is not enough. generate.ps1 does not build, so the
    # ordinary state right after a regeneration is a present-but-stale assembly, and an operationId
    # renamed without moving the file count would pass against the previous build - the exact
    # failure the reflection gate was chosen over a source-text search to close. Measured in the
    # committed working tree on 2026-09-04, before this row existed: every generated source was
    # five minutes newer than bin/Release/net8.0/Whisparr3.Net.dll and the census still reported
    # missingOps 0 and exited 0.
    #
    # Timestamps rather than content. The assembly carries no cheap identity of the sources it was
    # built from, and last-write time is the signal MSBuild's own up-to-date check uses. It is a
    # weaker statement than a content hash and a much stronger one than existence.
    $AssemblyTime = (Get-Item -LiteralPath $AssemblyPath).LastWriteTimeUtc
    if ($CsFiles.Count -eq 0) {
        # csTotal has already failed. Recorded as a failing row rather than skipped, because a
        # skipped row reads as a passing one.
        $NewestCs      = $null
        $AssemblyFresh = $false
    }
    else {
        $NewestCs      = @($CsFiles | Sort-Object LastWriteTimeUtc -Descending)[0]
        $AssemblyFresh = ($AssemblyTime -ge $NewestCs.LastWriteTimeUtc)
    }
    $Rows += [pscustomobject]@{
        Name     = 'assemblyFresh'
        Actual   = $(if ($AssemblyFresh) { 'current' } elseif ($null -eq $NewestCs) { 'no source' } else { 'stale' })
        Expected = 'current'
        Matched  = $AssemblyFresh
    }

    $Assembly    = [System.Reflection.Assembly]::LoadFrom($AssemblyPath)
    $MethodNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $ApiTypes    = 0
    foreach ($Type in $Assembly.GetExportedTypes()) {
        # Exactly this namespace, not a prefix match. Whisparr3.Net.Client and
        # Whisparr3.Net.Model expose plenty of public methods that are not operations.
        if ($Type.Namespace -cne 'Whisparr3.Net.Api') { continue }
        $ApiTypes++
        foreach ($Method in $Type.GetMethods()) { [void]$MethodNames.Add($Method.Name) }
    }
    $MissingIds = @($MapIds | Where-Object { -not $MethodNames.Contains("$($_)Async") })
    $Rows += [pscustomobject]@{ Name = 'missingOps'; Actual = $MissingIds.Count; Expected = 0; Matched = ($MissingIds.Count -eq 0) }
} else {
    Write-Host "ERROR: REFUSED - no built assembly at $AssemblyPath." -ForegroundColor Red
    Write-Host "  The 272-operation gate reads the public surface out of Whisparr3.Net.dll, so it cannot run and must not pass by skipping itself." -ForegroundColor Red
    Write-Host "  Build first: dotnet build $CsprojPath -c $Configuration" -ForegroundColor Red
}

# --- 5. Report actual beside expected on every row, pass or fail ---
$Mismatches = 0
foreach ($Row in $Rows) {
    if (-not $Row.Matched) { $Mismatches++ }
    $Sigil   = if ($Row.Matched) { '+' } else { '!' }
    $Verdict = if ($Row.Matched) { 'OK' } else { 'MISMATCH' }
    $Colour  = if ($Row.Matched) { 'Green' } else { 'Red' }
    Write-TreeCensus ('  {0} {1,-17} actual {2,-8} expected {3,-8} {4}' -f $Sigil, $Row.Name, $Row.Actual, $Row.Expected, $Verdict) $Colour
}

if ($AssemblyPresent) {
    Write-TreeCensus "  - $ApiTypes exported types in namespace Whisparr3.Net.Api, $($MethodNames.Count) distinct public method names" 'DarkGray'
    if (-not $AssemblyFresh) {
        # Name both timestamps, the way the absent-assembly refusal names the path and the build
        # command. A bare stale sends the reader to compare file times by hand.
        $NewestLine = if ($null -eq $NewestCs) { 'there is no generated source to compare against' } else { "the newest generated source is $(Get-RepoRelativePath $NewestCs.FullName) at $($NewestCs.LastWriteTimeUtc.ToString('u'))" }
        Write-TreeCensus "  ! the assembly is older than the tree under census: $AssemblyPath is $($AssemblyTime.ToString('u')) and $NewestLine." 'Red'
        Write-TreeCensus "  ! the operation gate reflects over that build, so it would be asserting a public surface this tree did not produce. Rebuild first: dotnet build $CsprojPath -c $Configuration" 'Red'
    }
    if ($MissingIds.Count -gt 0) {
        # Name them. A bare count sends the reader back to reflection by hand.
        $FirstTen = @($MissingIds | Select-Object -First 10)
        Write-TreeCensus "  ! first $($FirstTen.Count) map ids with no public <id>Async method: $($FirstTen -join ', ')" 'Red'
    }
}

# --- 6. Point-in-time facts, reported and never asserted ---
# Pinning these as assertions would turn an ordinary dependency bump into a census failure, and
# the version a package is pinned at is Phase 22's question, not this gate's.
$DigestMatch = [regex]::Match((Get-Content -Raw -LiteralPath $ConfigPath), 'sha256:[0-9a-f]{64}')
$Digest      = if ($DigestMatch.Success) { $DigestMatch.Value } else { '(no sha256 digest found in gen-config.yaml)' }
Write-TreeCensus "  ! generator image $Digest - reported only, not asserted" 'Yellow'

$Csproj   = [xml](Get-Content -Raw -LiteralPath $CsprojPath)
$PackageRefs = @($Csproj.SelectNodes('//PackageReference'))
foreach ($Group in @($PackageRefs | Group-Object -Property Include)) {
    $Versions = @($Group.Group | ForEach-Object { $_.Version })
    Write-TreeCensus ("  ! {0} pinned at {1} - reported only, not asserted" -f $Group.Name, ($Versions -join ' and ')) 'Yellow'
}

if ($Mismatches -gt 0) {
    Write-Host "ERROR: tree census failed - $Mismatches assertion(s) do not match this tree. See the actual-versus-expected lines above." -ForegroundColor Red
    exit 1
}

Write-TreeCensus "+ tree census passed, $($MapIds.Count) of $ExpectedOperations operations present on the public surface" 'Green'
exit 0
