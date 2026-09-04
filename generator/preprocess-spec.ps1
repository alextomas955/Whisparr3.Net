<#
.SYNOPSIS
  Pre-process the captured Whisparr 3 (Eros) OpenAPI document into the spec the generator reads.

.DESCRIPTION
  Reads the byte-verbatim capture, applies the transforms this milestone owns, gates the result
  on a staging path, and only then replaces the committed spec and records its hash.
    1. Parse the raw capture and report its observed byte count and sha256.
    2. Transform T1, the root security repair. Whisparr declares both API key schemes and then
       serves an empty requirement, so the generated client would carry no auth call site at
       all. The repair sets the auth-optional, both-schemes form.
    3. Transform T2, the malformed root path. paths["/"] is a StaticResource catch-all whose
       operation the generator turns into a method that shadows the client root. Deleting it
       takes the document from 190 paths and 273 operations to 189 and 272.
    4. Load the committed operationId map. It is the only source of an operationId. Nothing
       here derives one for assignment, and no path through this script writes the map.
    5. Gate G3, the map gate, in both directions, accumulated into one refusal. G3a: every
       operation in the spec must have an entry in the map. G3b: every entry in the map must
       match an operation in the spec. Both directions are collected before refusing, because
       a map that is both incomplete and stale is the ordinary case during a spec refresh, and
       a run that reports only the first direction sends the reader round the loop twice.
    6. Gate G4a, the collision assertion. The ids the map assigns must be distinct. Not the
       generator's FIX_DUPLICATED_OPERATIONID normalizer, which de-duplicates by appending a
       positional suffix: that would mask this assertion, and inserting an operation upstream
       moves the suffix onto a different method and renames public API with no diff (D-20).
    7. Gate G4b, the identifier shape. Every map value must be a valid C# identifier, so no
       name the generator would silently sanitize ever reaches the generator.
    8. Transform T3, the operationId assignment, from the map only. It reports an
       assigned-from-map count and a derived count, and the derived zero is the evidence that
       nothing was invented rather than an accounting detail.
    9. Stage. The patched document is written to the output path plus an .incoming suffix,
       never to the output path itself.
    10. Gate G1, the census over the staged bytes, with the Patched profile. Its exit code is
        propagated rather than flattened.
    11. Gate G2, the depth and size guard over the staged bytes. This is the gate the census
        cannot be. See the parser note below.
    12. Promote. Only here is the committed spec replaced. A run that refuses at any earlier
        step leaves the committed spec and the committed manifest exactly as they were.
    13. Manifest. generatedSpecSha256 is added to the PROVENANCE.json beside the output.

  Steps 4 through 8 all run before the staged write, so none of them has a staging file to
  discard and none of them calls Write-Refusal. That is deliberate, not an oversight: the map
  is what decides whether T3 can assign anything at all, so it must be checked before T3 runs,
  and a refusal that happens before staging has nothing staged to throw away.

  This script parses and serializes with System.Text.Json.Nodes.JsonNode rather than with the
  JSON cmdlets its two sibling scripts use. That is a deliberate divergence from the house JSON
  handling, and the reason is measured: ConvertTo-Json's -Depth argument defaults to 2, and
  against this 10-deep document that default emits a valid 49,525-byte file as written with
  CRLF, 48,452 after LF normalization, in which every operation body has been replaced by a
  short placeholder string. It reports that only on the warning stream and exits 0, and
  assert-spec-census.ps1 then passes the result at 190 paths, 273 operations, 162 schemas and
  75 tags. JsonNode has no truncation mode, round-trips number tokens verbatim, and with the
  relaxed encoder plus LF normalization reproduces the capture to within three bytes. Do not
  harmonize the parser back to the cmdlets.

  assert-spec-census.ps1 stays on the cmdlets on purpose. It reads a document whose depth-2
  truncation it demonstrably cannot see anyway, which is exactly why the guard lives here.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\preprocess-spec.ps1
  # Reads spec/openapi.raw.json and writes spec/openapi.generated.json inside the repository.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\preprocess-spec.ps1 -RawSpec C:\scratch\truncated.json -OutFile C:\scratch\out.json
  # The depth-truncation refusal run. Expected to stage, pass the census gate at 189 and 272,
  # then be refused by the depth and size guard and exit non-zero without writing a spec.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\preprocess-spec.ps1 -MapPath C:\scratch\broken-map.json -OutFile C:\scratch\out.json -ProposeMissing
  # The map-gate fixture run (D-10, D-19). Expected to refuse before staging, name every
  # operation the map does not cover and every map entry that matches no operation, print a
  # proposed name for each unmapped operation, and exit non-zero without writing a spec.
  # -MapPath and -OutFile are both scratch on purpose: a killed fixture run must not be able
  # to leave a broken contract or an unverified spec in the working tree.
#>

[CmdletBinding()]
param(
    # The document to pre-process. Defaults to the committed byte-verbatim capture, which is
    # the only input this pipeline is designed for. A relative path resolves against the
    # repository root, not the current directory. Overriding it is a fixture run, not a normal
    # one, and it requires -OutFile as well.
    [string]$RawSpec = 'spec/openapi.raw.json',

    # Where to write the patched spec. Defaults to the committed deliverable that Phase 20
    # generates from. A relative path resolves against the repository root, not the current
    # directory, so the default lands in the repo wherever this is run from.
    [string]$OutFile = 'spec/openapi.generated.json',

    # The committed operationId contract (PREP-05, D-17). Defaults to generator/operation-ids.json,
    # which is committed source and the only source of an operationId this pipeline will use. A
    # relative path resolves against the repository root, the same way the two paths above do.
    # Overriding it points the run at a fixture map, which is what the D-10 gate demonstrations
    # do. There is no parameter that writes this file, by design: a run that regenerates the map
    # from the spec is exactly the silent public-API rename PREP-05 forbids.
    [string]$MapPath = 'generator/operation-ids.json',

    # A diagnostic that runs ONLY on the failure path and never assigns anything. When the map
    # gate refuses, print a proposed operationId beside each unmapped operation so a spec-refresh
    # PR gets an actionable message instead of a bare list of paths. The proposal is authoring
    # input for a human editing the committed map; the pipeline still exits non-zero.
    [switch]$ProposeMissing
)

$ErrorActionPreference = 'Stop'
# Match both sibling scripts. Without strict mode a renamed or absent member on the parsed
# document evaluates to $null, the transform writes null into the patched spec, and the run
# prints Done. and exits 0 - the "reports success while proving nothing" shape this whole
# pipeline is built against.
Set-StrictMode -Version Latest

# --- Constants (edit here if the layout changes) ---
$RepoRoot       = Split-Path -Parent $PSScriptRoot
$DefaultRawSpec = 'spec/openapi.raw.json'
$DefaultOutFile = 'spec/openapi.generated.json'
# The auth-optional, both-schemes form, chosen in D-01 against two measured alternatives. Held
# as a named constant, and parsed from a literal rather than built from a PowerShell array: a
# single-element array piped through the serializer unrolls into an object. The three-element
# form below is unaffected, but a later single-element variant would be corrupted silently.
$SecurityOptionalBothSchemes = '[{},{"X-Api-Key":[]},{"apikey":[]}]'
# The floor below which the staged document cannot be an honest patched spec. The capture is
# 381,380 bytes and its depth-2 truncation is 48,452 after LF normalization, so anything in
# between is a wide margin around a defect that has no near miss.
$MinimumStagedBytes = 350000
# A value eight levels below the root. In a depth-truncated document the whole operation body
# above it has become one placeholder string, so this read returns nothing.
$DeepProbePath     = @('paths', '/api/v3/movie', 'get', 'responses', '200', 'content', 'application/json', 'schema', 'type')
$DeepProbeExpected = 'array'
$HttpMethods       = 'get', 'put', 'post', 'delete', 'options', 'head', 'patch', 'trace'
# A valid C# identifier of the shape this library's public method names take. Anchored on
# purpose. Exactly one derived name in this spec fails it, GetFeedV3CalendarWhisparr.ics, and the
# committed map overrides it to GetCalendarFeed. If nothing invalid ever reaches the generator,
# what the generator would have done to an invalid name stops mattering (D-16).
$OperationIdPattern = '^[A-Z][A-Za-z0-9]*$'

# The provenance manifest is derived from the output file's own directory rather than
# hardcoded, so a run with a scratch output path cannot overwrite the committed manifest.
$RawPath        = [System.IO.Path]::GetFullPath($(if ([System.IO.Path]::IsPathRooted($RawSpec)) { $RawSpec } else { Join-Path $RepoRoot $RawSpec }))
$OutPath        = [System.IO.Path]::GetFullPath($(if ([System.IO.Path]::IsPathRooted($OutFile)) { $OutFile } else { Join-Path $RepoRoot $OutFile }))
$OutDir         = Split-Path -Parent $OutPath
$MapFullPath    = [System.IO.Path]::GetFullPath($(if ([System.IO.Path]::IsPathRooted($MapPath)) { $MapPath } else { Join-Path $RepoRoot $MapPath }))
$ProvenancePath = Join-Path $OutDir 'PROVENANCE.json'
# Every run lands here first and is promoted only once every gate has passed, so a refusal
# cannot leave the committed deliverable replaced by unverified bytes. Declared beside the other
# paths rather than inside the try so the finally block can clear a partial write.
$StagePath      = "$OutPath.incoming"

$DefaultRawPath = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $DefaultRawSpec))
$DefaultOutPath = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $DefaultOutFile))

# Print an ERROR block, discard the staged file, and state that nothing committed was touched.
# Every refusal after step 4 goes through this. The caller keeps its own exit statement, so the
# exit code stays visible at the refusal site rather than hidden inside a helper.
function Write-Refusal {
    param([string[]]$Message)
    if (Test-Path -LiteralPath $Script:StagePath) { Remove-Item -LiteralPath $Script:StagePath -Force }
    foreach ($Line in $Message) { Write-Host $Line -ForegroundColor Red }
    Write-Host "  The staged spec has been discarded. $Script:OutPath and $Script:ProvenancePath are untouched." -ForegroundColor Red
}

# The 18 editorial overrides on the derived names, transcribed from 19-RESEARCH.md's override
# table with its reason per row. Read ONLY by the -ProposeMissing diagnostic below. The committed
# map is authoritative either way, so these have no effect on a passing run; they live beside the
# algorithm that made them necessary so the editorial reason is not separated from it.
$OperationIdOverrides = [ordered]@{
    'GET /feed/v3/calendar/whisparr.ics'           = 'GetCalendarFeed'                  # GetFeedV3CalendarWhisparr.ics is not a valid C# identifier. Tag is CalendarFeed.
    'GET /{path}'                                  = 'GetStaticResourceByPath'          # GetByPath names no resource.
    'GET /api'                                     = 'GetApiInfo'                       # Returns ApiInfoResource. Tag is ApiInfo.
    'GET /login'                                   = 'GetLoginPage'                     # Returns the HTML login page, tagged StaticResource. POST /login is the one that authenticates.
    'POST /api/v3/downloadclient/testall'          = 'TestAllDownloadClient'            # Casing. Derived TestallDownloadClient.
    'POST /api/v3/importlist/testall'              = 'TestAllImportList'                # Casing. Derived TestallImportList.
    'POST /api/v3/indexer/testall'                 = 'TestAllIndexer'                   # Casing. Derived TestallIndexer.
    'POST /api/v3/metadata/testall'                = 'TestAllMetadata'                  # Casing. Derived TestallMetadata.
    'POST /api/v3/notification/testall'            = 'TestAllNotification'              # Casing. Derived TestallNotification.
    'GET /api/v3/alttitle'                         = 'ListAlternativeTitle'             # The path abbreviates; the tag and the schema are AlternativeTitle.
    'GET /api/v3/alttitle/{id}'                    = 'GetAlternativeTitleById'          # Same.
    'GET /api/v3/importlist/movie'                 = 'GetImportListMovie'               # Casing. The tag is ImportListMovies, so the segment misses the tag-casing rule.
    'POST /api/v3/importlist/movie'                = 'CreateImportListMovie'            # Same.
    'GET /api/v3/qualityprofile/schema'            = 'GetQualityProfileSchema'          # Casing. The tag is QualityProfileSchema, so the segment misses the rule.
    'GET /api/v3/filesystem/mediafiles'            = 'GetFileSystemMediaFiles'          # Casing. Derived GetFileSystemMediafiles.
    'GET /api/v3/movie/listbyperformerforeignid'   = 'ListMovieByPerformerForeignId'    # Unreadable. Derived ListMovieListbyperformerforeignid.
    'GET /api/v3/movie/listbystudioforeignid'      = 'ListMovieByStudioForeignId'       # Unreadable. Derived ListMovieListbystudioforeignid.
    'GET /api/v3/mediacover/{movieId}/{filename}'  = 'GetMediaCoverByMovieIdAndFilename' # The derived GetMediaCoverByFilename silently drops movieId, a required path parameter.
}

# devopsarr's assign_operation_id.py algorithm, ported faithfully, with one deliberate fix.
# Faithful because it is measured collision-free on this exact spec and it is the shape every
# other *arr SDK consumer already reads; a new naming scheme would only add surprises at the next
# spec refresh. The fix: iterate the segment list BACKWARDS in the placeholder-removal and
# tag-casing loop. devopsarr's forward loop mutates the list it is enumerating, so a removal makes
# it skip the following element. Only /api/v3/mediacover/{movieId}/{filename} has a middle
# placeholder in this spec, so the defect is latent rather than active today, but a future capture
# with two adjacent middle placeholders would leave a {placeholder} in a public method name.
# This function never assigns anything. It is reached only from the -ProposeMissing failure path.
function Get-DerivedOperationId {
    param([string]$Method, [string]$Path, [string]$Tag, [bool]$ReturnsArray)

    $Stripped = [regex]::Replace($Path, '^/api/v\d/(.*)$', '$1')
    $Parts    = [System.Collections.Generic.List[string]]([regex]::Split($Stripped, '/|-'))

    if ($Parts[$Parts.Count - 1].StartsWith('{')) {
        $Parts[$Parts.Count - 1] = $Parts[$Parts.Count - 1].Trim('{', '}')
        $Parts.Insert($Parts.Count - 1, 'by')
    }

    $Verb = $Method
    if ($Method -eq 'delete' -and $Parts.Count -gt 1 -and $Parts[$Parts.Count - 2] -eq 'by') {
        $Parts.RemoveRange($Parts.Count - 2, 2)
    }
    if ($Method -eq 'put' -and $Parts.Count -gt 1 -and $Parts[$Parts.Count - 2] -eq 'by') {
        $Verb = 'update'
        $Parts.RemoveRange($Parts.Count - 2, 2)
    }
    if ($Method -eq 'post') {
        $Verb = 'create'
        if ($Parts[$Parts.Count - 1].StartsWith('test')) {
            $Verb = $Parts[$Parts.Count - 1]
            $Parts.RemoveAt($Parts.Count - 1)
        }
    }
    if ($Method -eq 'get' -and $ReturnsArray) { $Verb = 'list' }

    if ($Parts.Count -gt 1 -and $Parts[0] -eq 'config') {
        $Parts[0] = $Parts[1] + 'config'
        $Parts.RemoveAt(1)
    }
    if ($Parts.Count -gt 1 -and $Parts[1] -eq 'settings') { $Parts.RemoveAt(1) }

    for ($i = $Parts.Count - 1; $i -ge 0; $i--) {
        if ($Parts[$i].StartsWith('{')) { $Parts.RemoveAt($i); continue }
        if ($Parts[$i].ToLowerInvariant() -eq $Tag.ToLowerInvariant()) { $Parts[$i] = $Tag }
    }
    $Parts.Insert(0, $Verb)

    -join ($Parts | Where-Object { $_.Length -gt 0 } | ForEach-Object {
        $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1)
    })
}

# devopsarr's list rule keys on the 200 response declaring a JSON array. Walk the chain
# defensively and stop at the first non-object rather than calling GetValue<T>(), which throws on
# a JsonObject and would turn a diagnostic into a stack trace. Same shape as the G2 deep probe.
function Test-ReturnsJsonArray {
    param([System.Text.Json.Nodes.JsonNode]$Operation)
    $Node = $Operation
    foreach ($Key in @('responses', '200', 'content', 'application/json', 'schema', 'type')) {
        if ($null -eq $Node -or $Node -isnot [System.Text.Json.Nodes.JsonObject]) { return $false }
        $Node = $Node[$Key]
    }
    if ($null -eq $Node) { return $false }
    return $Node.ToJsonString() -eq '"array"'
}

# Derive, then override. The override table is applied last so a name the algorithm gets wrong is
# corrected in one reviewable place rather than by bending the algorithm around one path.
function Get-ProposedOperationId {
    param([string]$Key, [string]$Method, [string]$Path, [string]$Tag, [bool]$ReturnsArray)
    if ($OperationIdOverrides.Contains($Key)) { return $OperationIdOverrides[$Key] }
    return Get-DerivedOperationId -Method $Method -Path $Path -Tag $Tag -ReturnsArray $ReturnsArray
}

Write-Host "Pre-process Whisparr 3 openapi -> $OutPath" -ForegroundColor Cyan
Write-Host "  - reading $RawPath" -ForegroundColor DarkGray

try {
    # --- 0. A fixture input must never be able to promote itself onto the deliverable ---
    # The manifest derivation above already protects the committed PROVENANCE.json from a
    # scratch output path. This protects the committed spec from a scratch input path.
    if ($RawPath -ne $DefaultRawPath -and $OutPath -eq $DefaultOutPath) {
        Write-Host 'ERROR: REFUSED - a non-default input may not be written to the committed output path.' -ForegroundColor Red
        Write-Host "  input  $RawPath" -ForegroundColor Red
        Write-Host "  output $OutPath" -ForegroundColor Red
        Write-Host '  Pass -OutFile with a scratch path as well. A fixture run must not promote itself onto the committed spec.' -ForegroundColor Red
        exit 1
    }
    if (-not (Test-Path -LiteralPath $RawPath)) {
        Write-Host "ERROR: REFUSED - no input document at $RawPath." -ForegroundColor Red
        exit 1
    }

    # --- 1. Parse ---
    $RawBytes = (Get-Item -LiteralPath $RawPath).Length
    $RawSha   = (Get-FileHash -Algorithm SHA256 -LiteralPath $RawPath).Hash.ToLower()
    $Document = [System.Text.Json.Nodes.JsonNode]::Parse((Get-Content -Raw -LiteralPath $RawPath))
    Write-Host "  + parsed $RawBytes bytes, sha256 $RawSha" -ForegroundColor Green

    # --- 2. T1, the root security repair (D-01) ---
    $SecurityBefore = if ($null -eq $Document['security']) { '(absent)' } else { $Document['security'].ToJsonString() }
    # Replaced in place, which keeps security at its position in the root key order. A removal
    # followed by an add would move it to the end and inflate the diff against the capture.
    $Document['security'] = [System.Text.Json.Nodes.JsonNode]::Parse($SecurityOptionalBothSchemes)
    Write-Host "  + T1 security $SecurityBefore -> $($Document['security'].ToJsonString())" -ForegroundColor Green

    # --- 3. T2, the malformed root path (PREP-03, D-14) ---
    # Assert the removal from the call's own return value rather than trusting it. Deleting a
    # key that was already gone would otherwise produce a plausible 272-operation spec from a
    # document this pipeline has never seen, which is the fail-open direction PREP-03 forbids.
    # Not the generator's path allowlist normalizer: it is a prefix allowlist, so excluding one
    # path means enumerating every other top-level path, and a future Whisparr adding a new one
    # would be dropped silently with the count falling below 272 and no error (D-15).
    $PathsObject = $Document['paths'].AsObject()
    if (-not $PathsObject.Remove('/')) {
        Write-Host 'ERROR: REFUSED - paths["/"] is not present in this document.' -ForegroundColor Red
        Write-Host "  $RawPath is not what this pipeline expects. The capture carries a malformed StaticResource catch-all at the key ""/"", and PREP-03 exists to delete exactly that key." -ForegroundColor Red
        Write-Host '  A capture that renamed or repaired it must stop this pipeline rather than silently produce a plausible 272-operation spec. Nothing was written.' -ForegroundColor Red
        exit 1
    }
    Write-Host "  + T2 deleted paths[""/""], $($PathsObject.Count) path items remain" -ForegroundColor Green

    # --- 4. Load the committed operationId map (PREP-05, D-17) ---
    # The map is the only source of an operationId. A pipeline that derives a name when the map
    # lacks one is not fail-closed, it is fail-open with extra steps. Steps 4 to 8 all run before
    # the staged write, so none of them has a staging file to discard and none calls
    # Write-Refusal; the post-staging gates below do, and the difference is deliberate.
    if (-not (Test-Path -LiteralPath $MapFullPath)) {
        Write-Host "ERROR: REFUSED - no operationId map at $MapFullPath." -ForegroundColor Red
        Write-Host '  The map is committed source and the only source of an operationId. This script never writes it. Nothing was written.' -ForegroundColor Red
        exit 1
    }
    try {
        $MapNode = [System.Text.Json.Nodes.JsonNode]::Parse((Get-Content -Raw -LiteralPath $MapFullPath))
    } catch {
        Write-Host "ERROR: REFUSED - the operationId map at $MapFullPath does not parse as JSON." -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    if ($MapNode -isnot [System.Text.Json.Nodes.JsonObject]) {
        $MapKind = if ($null -eq $MapNode) { 'null' } else { $MapNode.GetType().Name }
        Write-Host "ERROR: REFUSED - the operationId map at $MapFullPath is a $MapKind, not a JSON object." -ForegroundColor Red
        Write-Host '  The map is an object keyed "METHOD /path" whose values are operationId strings. Nothing was written.' -ForegroundColor Red
        exit 1
    }
    # Ordinal comparison throughout. A case-insensitive dictionary would accept a map key whose
    # method is lower-cased, and D-17 fixes the key shape as the upper-cased method, one space,
    # then the path exactly as the document spells it.
    $Map     = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $MapKeys = [System.Collections.Generic.List[string]]::new()
    foreach ($Entry in $MapNode.AsObject()) {
        if ($null -eq $Entry.Value -or $Entry.Value.GetValueKind() -ne [System.Text.Json.JsonValueKind]::String) {
            $Observed = if ($null -eq $Entry.Value) { 'null' } else { $Entry.Value.ToJsonString() }
            Write-Host "ERROR: REFUSED - the operationId map entry ""$($Entry.Key)"" carries $Observed, which is not a string." -ForegroundColor Red
            Write-Host '  Every map value is an operationId. Nothing was written.' -ForegroundColor Red
            exit 1
        }
        $Value = $Entry.Value.GetValue[string]()
        if ([string]::IsNullOrWhiteSpace($Value)) {
            Write-Host "ERROR: REFUSED - the operationId map entry ""$($Entry.Key)"" carries an empty operationId." -ForegroundColor Red
            Write-Host '  Every map value is an operationId. Nothing was written.' -ForegroundColor Red
            exit 1
        }
        $Map[$Entry.Key] = $Value
        $MapKeys.Add($Entry.Key)
    }
    Write-Host "  + loaded $($MapKeys.Count) operationId map entries from $MapFullPath" -ForegroundColor Green

    # The spec side of the comparison, keyed the way D-17 fixes it.
    $SpecOps = [System.Collections.Generic.List[object]]::new()
    foreach ($PathEntry in $PathsObject) {
        if ($PathEntry.Value -isnot [System.Text.Json.Nodes.JsonObject]) {
            $Observed = if ($null -eq $PathEntry.Value) { 'null' } else { $PathEntry.Value.GetType().Name }
            Write-Host "ERROR: REFUSED - the path item $($PathEntry.Key) is a $Observed, not a JSON object." -ForegroundColor Red
            Write-Host '  This document cannot be enumerated for operations, so the map gate below cannot be honest about it. Nothing was written.' -ForegroundColor Red
            exit 1
        }
        foreach ($Member in $PathEntry.Value.AsObject()) {
            if ($HttpMethods -notcontains $Member.Key) { continue }
            $SpecOps.Add([pscustomobject]@{
                Key    = "$($Member.Key.ToUpperInvariant()) $($PathEntry.Key)"
                Method = $Member.Key
                Path   = $PathEntry.Key
                Node   = $Member.Value
            })
        }
    }

    # --- 5. Gate G3, the map gate, both directions accumulated into one refusal (PREP-05, D-18) ---
    # Both directions are computed before refusing. A map that is both incomplete and stale is the
    # ordinary case during a spec refresh, and two sequential exiting gates would report only the
    # first, sending the reader round the loop twice.
    $SpecKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($Op in $SpecOps) { [void]$SpecKeys.Add($Op.Key) }

    $Unmapped = [System.Collections.Generic.List[object]]::new()
    foreach ($Op in $SpecOps) { if (-not $Map.ContainsKey($Op.Key)) { $Unmapped.Add($Op) } }

    $Orphans = [System.Collections.Generic.List[string]]::new()
    foreach ($Key in $MapKeys) { if (-not $SpecKeys.Contains($Key)) { $Orphans.Add($Key) } }

    if ($Unmapped.Count -gt 0 -or $Orphans.Count -gt 0) {
        Write-Host 'ERROR: map gate failed - the operationId map and the spec disagree.' -ForegroundColor Red
        Write-Host "  G3a, spec to map: $($Unmapped.Count) operations in the spec have no entry in the map." -ForegroundColor Red
        Write-Host "  G3b, map to spec: $($Orphans.Count) map entries match no operation in the spec." -ForegroundColor Red
        if ($Unmapped.Count -gt 0) {
            Write-Host '  Unmapped operations, G3a:' -ForegroundColor Red
            foreach ($Op in $Unmapped) {
                if ($ProposeMissing) {
                    $Tag = ''
                    if ($Op.Node -is [System.Text.Json.Nodes.JsonObject]) {
                        $Tags = $Op.Node['tags']
                        if ($null -ne $Tags -and $Tags -is [System.Text.Json.Nodes.JsonArray] -and $Tags.Count -gt 0 -and
                            $null -ne $Tags[0] -and $Tags[0].GetValueKind() -eq [System.Text.Json.JsonValueKind]::String) {
                            $Tag = $Tags[0].GetValue[string]()
                        }
                    }
                    $Proposed = Get-ProposedOperationId -Key $Op.Key -Method $Op.Method -Path $Op.Path -Tag $Tag -ReturnsArray (Test-ReturnsJsonArray -Operation $Op.Node)
                    Write-Host "    $($Op.Key) -> $Proposed" -ForegroundColor Red
                } else {
                    Write-Host "    $($Op.Key)" -ForegroundColor Red
                }
            }
        }
        if ($Orphans.Count -gt 0) {
            Write-Host '  Orphaned map entries, G3b:' -ForegroundColor Red
            foreach ($Key in $Orphans) { Write-Host "    $Key" -ForegroundColor Red }
        }
        if ($Unmapped.Count -gt 0 -and -not $ProposeMissing) {
            Write-Host '  Re-run with -ProposeMissing for a proposed operationId beside each unmapped operation. A proposal is authoring input for a human editing the map; this script never assigns one.' -ForegroundColor Red
        }
        Write-Host '  Nothing was staged and nothing was promoted. The map changes in a commit a human reads, never by this script.' -ForegroundColor Red
        exit 1
    }
    Write-Host "  + G3 map gate passed - $($SpecOps.Count) operations, $($MapKeys.Count) map entries, key sets identical in both directions" -ForegroundColor Green

    # --- 6. Gate G4a, the collision assertion (PREP-04, D-19, D-20) ---
    $ById = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new([System.StringComparer]::Ordinal)
    foreach ($Op in $SpecOps) {
        $Id = $Map[$Op.Key]
        if (-not $ById.ContainsKey($Id)) { $ById[$Id] = [System.Collections.Generic.List[string]]::new() }
        $ById[$Id].Add($Op.Key)
    }
    $Collisions = @($ById.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 })
    if ($Collisions.Count -gt 0) {
        Write-Host "ERROR: collision assertion failed - $($Collisions.Count) operationIds are carried by more than one operation." -ForegroundColor Red
        foreach ($Collision in $Collisions) {
            Write-Host "  the operationId $($Collision.Key) is assigned to $($Collision.Value.Count) operations:" -ForegroundColor Red
            foreach ($Key in $Collision.Value) { Write-Host "    $Key" -ForegroundColor Red }
        }
        Write-Host '  The generator emits one class per tag, so two operations sharing an operationId are two methods with one name on one class.' -ForegroundColor Red
        Write-Host '  FIX_DUPLICATED_OPERATIONID is deliberately not used to paper over this: it appends a positional suffix, which masks the collision and moves the suffix onto a different method when an operation is inserted upstream, renaming public API with no diff (D-20).' -ForegroundColor Red
        Write-Host '  Nothing was staged and nothing was promoted.' -ForegroundColor Red
        exit 1
    }
    Write-Host "  + G4a collision assertion passed - $($ById.Count) distinct operationIds across $($SpecOps.Count) operations" -ForegroundColor Green

    # --- 7. Gate G4b, the identifier shape (PREP-04, D-16) ---
    # -cnotmatch, not -notmatch. PowerShell's -match is case-insensitive, so the anchored pattern
    # would accept listMovie and the gate would pass a name the generator has to sanitize.
    $BadShape = [System.Collections.Generic.List[string]]::new()
    foreach ($Key in $MapKeys) {
        if ($Map[$Key] -cnotmatch $OperationIdPattern) { $BadShape.Add($Key) }
    }
    if ($BadShape.Count -gt 0) {
        Write-Host "ERROR: identifier shape assertion failed - $($BadShape.Count) map values are not valid C# identifiers." -ForegroundColor Red
        Write-Host "  Every operationId must match $OperationIdPattern." -ForegroundColor Red
        foreach ($Key in $BadShape) { Write-Host "    $Key carries the invalid identifier $($Map[$Key])" -ForegroundColor Red }
        Write-Host '  An invalid name reaching the generator would be sanitized into a name of the generator''s own choosing, which is the silent public-API rename PREP-05 exists to prevent.' -ForegroundColor Red
        Write-Host '  Nothing was staged and nothing was promoted.' -ForegroundColor Red
        exit 1
    }
    Write-Host "  + G4b identifier shape assertion passed - $($MapKeys.Count) values match $OperationIdPattern" -ForegroundColor Green

    # --- 8. Transform T3, operationId, from the map only (PREP-04, PREP-05, D-16) ---
    $AssignedFromMap = 0
    # No code path increments this. The pipeline never derives a name for assignment, and the zero
    # it prints is the evidence of that rather than an accounting detail. A non-zero value here
    # would mean the gate above had been made fail-open.
    $DerivedAtRuntime = 0
    foreach ($Op in $SpecOps) {
        if ($Op.Node -isnot [System.Text.Json.Nodes.JsonObject]) {
            $Observed = if ($null -eq $Op.Node) { 'null' } else { $Op.Node.GetType().Name }
            Write-Host "ERROR: REFUSED - the operation $($Op.Key) is a $Observed, not a JSON object." -ForegroundColor Red
            Write-Host '  An operation body replaced by a scalar is the depth-truncation signature. T3 asserts the type rather than throwing on it, so a truncated input stays a refusal that names the operation.' -ForegroundColor Red
            Write-Host '  Nothing was staged and nothing was promoted.' -ForegroundColor Red
            exit 1
        }
        # Appended as a new last member, which is deterministic run to run.
        $Op.Node['operationId'] = [System.Text.Json.Nodes.JsonValue]::Create($Map[$Op.Key])
        $AssignedFromMap++
    }
    Write-Host "  + T3 assigned $AssignedFromMap operationIds from map, $DerivedAtRuntime derived" -ForegroundColor Green

    # --- 9. Stage. Never the output path itself ---
    # The relaxed encoder leaves the 25 apostrophes already in the document literal, so the
    # patched spec's diff against the capture shows the transforms and nothing else.
    $Writer = [System.Text.Json.JsonSerializerOptions]::new()
    $Writer.WriteIndented = $true
    $Writer.Encoder = [System.Text.Encodings.Web.JavaScriptEncoder]::UnsafeRelaxedJsonEscaping
    # The indented writer emits the platform newline, which is CRLF here, and .gitattributes
    # declares *.json as eol=lf. Normalize explicitly: the same code on a Linux CI runner would
    # otherwise produce a different hash from a dev machine and defeat PIPE-02 for a reason that
    # has nothing to do with the spec. Exactly one trailing newline, per .editorconfig.
    $StagedJson = (($Document.ToJsonString($Writer)) -replace "`r`n", "`n").TrimEnd("`n") + "`n"
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    [System.IO.File]::WriteAllText($StagePath, $StagedJson, [System.Text.UTF8Encoding]::new($false))
    $StagedBytes = (Get-Item -LiteralPath $StagePath).Length
    $StagedSha   = (Get-FileHash -Algorithm SHA256 -LiteralPath $StagePath).Hash.ToLower()
    Write-Host "  + staged $StagedBytes bytes at $StagePath, sha256 $StagedSha" -ForegroundColor Green

    # --- 10. Gate G1, the census over the staged bytes ---
    # $LASTEXITCODE is the only reliable way to read a child script's exit code: the stop error
    # preference does not intercept it. -SkipProvenanceHash because the manifest beside the
    # output still describes the previous run, and the hash this run records is written at
    # step 8, so comparing against the old manifest here would refuse every legitimate re-run.
    & (Join-Path $PSScriptRoot 'assert-spec-census.ps1') -Path $StagePath -Artifact Patched -SkipProvenanceHash
    if ($LASTEXITCODE -ne 0) {
        $CensusExit = $LASTEXITCODE
        Write-Refusal @("ERROR: census gate failed (exit $CensusExit) for the spec staged at $StagePath.")
        exit $CensusExit
    }

    # --- 11. Gate G2, the depth and size guard ---
    # The census cannot be this gate. Measured: it passes a depth-truncated copy of this
    # document with all four counts green and exit 0, because truncation preserves keys at every
    # level and destroys only values. Three independent assertions, each naming its observed
    # value when it fails.
    if ($StagedBytes -lt $MinimumStagedBytes) {
        Write-Refusal @(
            "ERROR: depth and size guard failed - the staged spec is $StagedBytes bytes, below the floor of $MinimumStagedBytes.",
            '  A patched spec of this document is above 381,000 bytes. A depth-2 serialization of it is 48,452.'
        )
        exit 1
    }

    # Re-parse the staged bytes rather than reasoning about the in-memory document. The point of
    # this gate is to check what was actually written.
    $Staged = [System.Text.Json.Nodes.JsonNode]::Parse((Get-Content -Raw -LiteralPath $StagePath))
    $Probe  = $Staged
    foreach ($Key in $DeepProbePath) {
        if ($null -eq $Probe -or $Probe -isnot [System.Text.Json.Nodes.JsonObject]) { $Probe = $null; break }
        $Probe = $Probe[$Key]
    }
    $ProbeValue = if ($null -eq $Probe) { '(absent)' } else { $Probe.ToJsonString() }
    if ($ProbeValue -ne """$DeepProbeExpected""") {
        Write-Refusal @(
            "ERROR: depth and size guard failed - the value at $($DeepProbePath -join ' -> ') is $ProbeValue, expected ""$DeepProbeExpected"".",
            '  That value sits eight levels below the root. In a depth-truncated document the operation body above it has become a single placeholder string.'
        )
        exit 1
    }

    # An operation must be a JSON object. In a truncated document it is a plain string.
    $OperationsChecked = 0
    foreach ($PathEntry in $Staged['paths'].AsObject()) {
        foreach ($Member in $PathEntry.Value.AsObject()) {
            if ($HttpMethods -notcontains $Member.Key) { continue }
            $OperationsChecked++
            if ($Member.Value -isnot [System.Text.Json.Nodes.JsonObject]) {
                Write-Refusal @(
                    "ERROR: depth and size guard failed - the operation $($Member.Key.ToUpperInvariant()) $($PathEntry.Key) is a $($Member.Value.GetType().Name), not a JSON object.",
                    "  Its serialized value is $($Member.Value.ToJsonString()). An operation body replaced by a scalar is the depth-truncation signature."
                )
                exit 1
            }
        }
    }
    Write-Host "  + depth and size guard passed - $StagedBytes bytes, deep probe ""$DeepProbeExpected"", $OperationsChecked operation bodies are objects" -ForegroundColor Green

    # --- 12. Promote. The first write to anything committed ---
    Move-Item -LiteralPath $StagePath -Destination $OutPath -Force
    Write-Host "  + promoted to $OutPath" -ForegroundColor Green

    # --- 13. The manifest ---
    # capture-spec.ps1 rebuilds this file from its own eleven observed fields, so a re-capture
    # DROPS generatedSpecSha256. That is deliberate: a new capture invalidates the patched spec,
    # and the next census with the Patched profile fails until this script runs again. Without
    # this note the first person to bump the image digest reads that failure as a bug.
    if (Test-Path -LiteralPath $ProvenancePath) {
        $PromotedSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $OutPath).Hash.ToLower()
        $Provenance  = Get-Content -Raw -LiteralPath $ProvenancePath | ConvertFrom-Json
        if ($Provenance.PSObject.Properties.Name -contains 'generatedSpecSha256') {
            $Provenance.generatedSpecSha256 = $PromotedSha
        } else {
            $Provenance | Add-Member -NotePropertyName 'generatedSpecSha256' -NotePropertyValue $PromotedSha
        }
        # The same LF, no-BOM, one-trailing-newline writer capture-spec.ps1 uses for this file.
        # -Depth is explicit and the truncation warning is a terminating error, because this
        # phase must not author a second serializer call that can truncate in silence.
        $ProvenanceJson = ((ConvertTo-Json -InputObject $Provenance -Depth 8 -WarningAction Stop) -replace "`r`n", "`n").TrimEnd("`n") + "`n"
        [System.IO.File]::WriteAllText($ProvenancePath, $ProvenanceJson, [System.Text.UTF8Encoding]::new($false))
        Write-Host "  + wrote generatedSpecSha256 $PromotedSha to $ProvenancePath" -ForegroundColor Green
    } else {
        # Only reachable with a scratch output path, which by design has no manifest beside it.
        Write-Host "  - no PROVENANCE.json beside $OutPath, generatedSpecSha256 not recorded" -ForegroundColor DarkGray
    }

    Write-Host "Done. $OutPath" -ForegroundColor Green
}
finally {
    # A run killed mid-write leaves a partial staging file. It is never the deliverable, and
    # .gitignore does not cover the .incoming suffix, so clearing it here is the only thing
    # keeping a killed run from leaving an untracked file in the working tree.
    if (Test-Path -LiteralPath $StagePath) { Remove-Item -LiteralPath $StagePath -Force }
}
