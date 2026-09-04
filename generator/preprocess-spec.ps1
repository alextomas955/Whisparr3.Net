<#
.SYNOPSIS
  Pre-process the captured Whisparr 3 (Eros) OpenAPI document into the spec the generator reads.

.DESCRIPTION
  T1 repairs root security, T2 deletes the malformed paths["/"] so 273 operations become 272, and
  T3 derives an operationId for every operation from the document itself.

  The derivation is devopsarr's assign_operation_id.py, the algorithm behind the Go, Python and
  TypeScript *arr clients. $OperationIdOverrides names the 13 operations it cannot get right from
  the URL alone, mostly abbreviations only a human can expand: alttitle is AlternativeTitle.

  Nothing here pins a name against upstream change. If Whisparr renames a path, the derived method
  name follows it and the break surfaces in a consumer's build. That trade was accepted in exchange
  for deleting a 272-entry committed map that had to be reviewed on every version bump.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\preprocess-spec.ps1
#>

[CmdletBinding()]
param(
    [string]$RawSpec = 'spec/openapi.raw.json',
    [string]$OutFile = 'spec/openapi.generated.json'
)

$ErrorActionPreference = 'Stop'
# Without strict mode a renamed or absent member evaluates to $null, the transform writes null into
# the patched spec, and the run prints Done. and exits 0.
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $PSScriptRoot
function Resolve-RepoPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($(if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $RepoRoot $Path }))
}

# Mandatory auth, header scheme only. Both halves are load-bearing.
# Not optional: Whisparr's Startup.cs pins the fallback policy to the API-key scheme and consults
# neither AuthenticationMethod nor AuthenticationRequired, and no key measures 401 under every
# permissive configuration. A leading empty requirement is the OpenAPI spelling for "optional".
# Header only, though Whisparr also declares the query scheme: generichost does not treat the two
# as alternatives but emits a call to every declared scheme, so the both-schemes form put the key
# in the URL of all 272 requests, where it reaches access logs, proxy logs and Referer headers
# (upstream openapi-generator issue 24138). Parsed from a literal, not built from a PowerShell
# array: a single-element array piped through the serializer unrolls into an object.
$SecurityLiteral = '[{"X-Api-Key":[]}]'
# The inline census. The capture is 381,380 bytes and its depth-2 truncation is 48,452, so the
# floor is a wide margin.
$ExpectedOperations = 272
$MinimumStagedBytes = 350000
$HttpMethods        = 'get', 'put', 'post', 'delete', 'options', 'head', 'patch', 'trace'
# A valid C# identifier of the shape this library's public method names take. Anchored on purpose.
$OperationIdPattern = '^[A-Z][A-Za-z0-9]*$'

# The 13 operations the derivation cannot name from the URL, keyed "METHOD /path". Every other name
# in the SDK is computed. Lookups are case-insensitive because this is a PowerShell hashtable
# literal, which is harmless: keys are built with an upper-cased method and the path verbatim.
#
# GET /feed/v3/calendar/whisparr.ics is the one entry that is not cosmetic. It derives to
# GetFeedV3CalendarWhisparr.ics, which is not a C# identifier, and the shape assertion below
# refuses it. The rest expand an abbreviation or a lower-cased run the URL does not delimit.
$OperationIdOverrides = @{
    'GET /{path}'                                 = 'GetStaticResourceByPath'
    'GET /api'                                    = 'GetApiInfo'
    'GET /api/v3/alttitle'                        = 'ListAlternativeTitle'
    'GET /api/v3/alttitle/{id}'                   = 'GetAlternativeTitleById'
    'GET /api/v3/filesystem/mediafiles'           = 'GetFileSystemMediaFiles'
    'GET /api/v3/importlist/movie'                = 'GetImportListMovie'
    'GET /api/v3/mediacover/{movieId}/{filename}' = 'GetMediaCoverByMovieIdAndFilename'
    'GET /api/v3/movie/listbyperformerforeignid'  = 'ListMovieByPerformerForeignId'
    'GET /api/v3/movie/listbystudioforeignid'     = 'ListMovieByStudioForeignId'
    'GET /api/v3/qualityprofile/schema'           = 'GetQualityProfileSchema'
    'GET /feed/v3/calendar/whisparr.ics'          = 'GetCalendarFeed'
    'GET /login'                                  = 'GetLoginPage'
    'POST /api/v3/importlist/movie'               = 'CreateImportListMovie'
}

$RawPath = Resolve-RepoPath $RawSpec
$OutPath = Resolve-RepoPath $OutFile
$OutDir  = Split-Path -Parent $OutPath
# Derived from the output file's own directory, so a scratch run cannot overwrite the committed one.
$ProvenancePath = Join-Path $OutDir 'PROVENANCE.json'
# Every run lands here first and is promoted only once every gate has passed. Not ceremony: a code
# review found a gate running after the committed spec had already been overwritten.
$StagePath = "$OutPath.incoming"

$DefaultRawPath = Resolve-RepoPath 'spec/openapi.raw.json'
$DefaultOutPath = Resolve-RepoPath 'spec/openapi.generated.json'

# A refusal writes to the host and then exits. Write-Error throws under $ErrorActionPreference =
# 'Stop', which makes the exit after it unreachable.
function Write-Refusal {
    param([string[]]$Message)
    if (Test-Path -LiteralPath $Script:StagePath) { Remove-Item -LiteralPath $Script:StagePath -Force }
    foreach ($Line in $Message) { Write-Host $Line -ForegroundColor Red }
    Write-Host "  Nothing was promoted. $Script:OutPath and $Script:ProvenancePath are untouched." -ForegroundColor Red
}

# devopsarr's list rule keys on the 200 response declaring a JSON array. Walk the chain defensively
# and stop at the first non-object rather than calling GetValue<T>(), which throws on a JsonObject.
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

# devopsarr's assign_operation_id.py, ported with two fixes. This iterates the segment list
# BACKWARDS in the placeholder-removal loop, because devopsarr's forward loop mutates the list it is
# enumerating and a removal makes it skip the following element. And the POST test-verb rule spells
# testall as testAll, so the five /testall endpoints derive TestAllIndexer rather than
# TestallIndexer without needing five override entries of their own.
function Get-DerivedOperationId {
    param([string]$Method, [string]$Path, [string]$Tag, [bool]$ReturnsArray)
    $Stripped = [regex]::Replace($Path, '^/api/v\d/(.*)$', '$1')
    $Parts    = [System.Collections.Generic.List[string]]([regex]::Split($Stripped, '/|-'))

    if ($Parts[$Parts.Count - 1].StartsWith('{')) {
        $Parts[$Parts.Count - 1] = $Parts[$Parts.Count - 1].Trim('{', '}')
        $Parts.Insert($Parts.Count - 1, 'by')
    }
    $Verb = $Method
    $TailIsById = $Parts.Count -gt 1 -and $Parts[$Parts.Count - 2] -eq 'by'
    if ($Method -eq 'delete' -and $TailIsById) { $Parts.RemoveRange($Parts.Count - 2, 2) }
    if ($Method -eq 'put' -and $TailIsById) { $Verb = 'update'; $Parts.RemoveRange($Parts.Count - 2, 2) }
    if ($Method -eq 'post') {
        $Verb = 'create'
        if ($Parts[$Parts.Count - 1].StartsWith('test')) {
            $Verb = $Parts[$Parts.Count - 1] -replace '^testall$', 'testAll'
            $Parts.RemoveAt($Parts.Count - 1)
        }
    }
    if ($Method -eq 'get' -and $ReturnsArray) { $Verb = 'list' }
    if ($Parts.Count -gt 1 -and $Parts[0] -eq 'config') { $Parts[0] = $Parts[1] + 'config'; $Parts.RemoveAt(1) }
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

Write-Host "Pre-process Whisparr 3 openapi -> $OutPath" -ForegroundColor Cyan

try {
    # --- 0. A fixture run must never promote itself onto the committed deliverable ---
    # The two operands take different comparers on purpose. "Non-default input" is ordinal, so on
    # Linux spec/OPENAPI.RAW.JSON is not spec/openapi.raw.json. "Committed output path" is
    # case-insensitive, because on NTFS a differently-cased spelling IS the committed file.
    if ($RawPath -cne $DefaultRawPath -and $OutPath -eq $DefaultOutPath) {
        Write-Host "ERROR: REFUSED - a non-default input may not be written to the committed output path. Pass -OutFile with a scratch path too. input $RawPath / output $OutPath" -ForegroundColor Red
        exit 1
    }
    if (-not (Test-Path -LiteralPath $RawPath)) {
        Write-Host "ERROR: REFUSED - no input document at $RawPath." -ForegroundColor Red
        exit 1
    }

    # --- 1. Parse ---
    # JsonNode, never ConvertTo-Json: its -Depth defaults to 2, and against this 10-deep document
    # that default emits a valid 48,452-byte file in which every operation body has become a
    # placeholder string, warns on the warning stream only, and exits 0.
    $Document = [System.Text.Json.Nodes.JsonNode]::Parse((Get-Content -Raw -LiteralPath $RawPath))
    Write-Host "  + parsed $((Get-Item -LiteralPath $RawPath).Length) bytes from $RawPath" -ForegroundColor Green

    # --- 2. T1, root security ---
    # Replaced in place, which keeps security at its position in the root key order. Removing then
    # adding would move it to the end and inflate the diff against the capture.
    $Document['security'] = [System.Text.Json.Nodes.JsonNode]::Parse($SecurityLiteral)
    Write-Host "  + T1 root security set to $SecurityLiteral" -ForegroundColor Green

    # --- 3. T2, the malformed root path ---
    # Assert the removal from the call's own return value. Deleting a key that was already gone
    # would produce a plausible 272-operation spec from a document this pipeline has never seen.
    $PathsObject = $Document['paths'].AsObject()
    if (-not $PathsObject.Remove('/')) {
        Write-Host "ERROR: REFUSED - paths[""/""] is not present, so $RawPath is not what this pipeline expects. Nothing was written." -ForegroundColor Red
        exit 1
    }
    Write-Host "  + T2 deleted paths[""/""], $($PathsObject.Count) path items remain" -ForegroundColor Green

    # --- 4. Derive a name for every operation ---
    $SpecOps      = [System.Collections.Generic.List[object]]::new()
    $OverrideUsed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($PathEntry in $PathsObject) {
        if ($PathEntry.Value -isnot [System.Text.Json.Nodes.JsonObject]) {
            Write-Host "ERROR: REFUSED - the path item $($PathEntry.Key) is not a JSON object. Nothing was written." -ForegroundColor Red
            exit 1
        }
        foreach ($Member in $PathEntry.Value.AsObject()) {
            if ($HttpMethods -notcontains $Member.Key) { continue }
            if ($Member.Value -isnot [System.Text.Json.Nodes.JsonObject]) {
                Write-Host "ERROR: REFUSED - the operation $($Member.Key) $($PathEntry.Key) is not a JSON object. An operation body replaced by a scalar is the depth-truncation signature. Nothing was staged." -ForegroundColor Red
                exit 1
            }
            $Key = "$($Member.Key.ToUpperInvariant()) $($PathEntry.Key)"
            if ($OperationIdOverrides.ContainsKey($Key)) {
                $Id = $OperationIdOverrides[$Key]
                [void]$OverrideUsed.Add($Key)
            } else {
                $Tag  = ''
                $Tags = $Member.Value['tags']
                if ($Tags -is [System.Text.Json.Nodes.JsonArray] -and $Tags.Count -gt 0 -and
                    $Tags[0].GetValueKind() -eq [System.Text.Json.JsonValueKind]::String) { $Tag = $Tags[0].GetValue[string]() }
                $Id = Get-DerivedOperationId -Method $Member.Key -Path $PathEntry.Key -Tag $Tag -ReturnsArray (Test-ReturnsJsonArray -Operation $Member.Value)
            }
            $SpecOps.Add([pscustomobject]@{ Key = $Key; Id = $Id; Node = $Member.Value })
        }
    }
    Write-Host "  + derived $($SpecOps.Count) operationIds, $($OverrideUsed.Count) of them from the override table" -ForegroundColor Green

    # --- 5. The assertions the derivation makes necessary ---
    # An override that matches no operation is the only remaining signal that Whisparr moved a path.
    $StaleOverrides = @($OperationIdOverrides.Keys | Where-Object { -not $OverrideUsed.Contains($_) })
    if ($StaleOverrides.Count -gt 0) {
        Write-Host "ERROR: $($StaleOverrides.Count) override entries match no operation in this spec. Whisparr has moved or removed a path, so the name it pinned is now derived instead. Nothing was staged." -ForegroundColor Red
        foreach ($Key in $StaleOverrides) { Write-Host "    $Key -> $($OperationIdOverrides[$Key])" -ForegroundColor Red }
        exit 1
    }
    # Not the generator's FIX_DUPLICATED_OPERATIONID normalizer, which de-duplicates by appending a
    # positional suffix: that masks this assertion, and inserting an operation upstream then moves
    # the suffix onto a different method and renames public API with no diff.
    $ById = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new([System.StringComparer]::Ordinal)
    foreach ($Op in $SpecOps) {
        if (-not $ById.ContainsKey($Op.Id)) { $ById[$Op.Id] = [System.Collections.Generic.List[string]]::new() }
        $ById[$Op.Id].Add($Op.Key)
    }
    $Collisions = @($ById.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 })
    if ($Collisions.Count -gt 0) {
        Write-Host "ERROR: collision assertion failed - $($Collisions.Count) operationIds are carried by more than one operation." -ForegroundColor Red
        foreach ($Collision in $Collisions) { Write-Host "    $($Collision.Key) is assigned to: $($Collision.Value -join ', ')" -ForegroundColor Red }
        Write-Host '  The generator emits one class per tag, so two operations sharing an operationId are two methods with one name on one class. Add an override for one of them. Nothing was staged.' -ForegroundColor Red
        exit 1
    }
    # -cnotmatch, not -notmatch. PowerShell's -match is case-insensitive, so the anchored pattern
    # would accept listMovie and pass a name the generator then sanitizes into one of its own
    # choosing. This is the assertion that catches GetFeedV3CalendarWhisparr.ics.
    $BadShape = @($SpecOps | Where-Object { $_.Id -cnotmatch $OperationIdPattern })
    if ($BadShape.Count -gt 0) {
        Write-Host "ERROR: identifier shape assertion failed - $($BadShape.Count) names do not match $OperationIdPattern. Add an override for each. Nothing was staged." -ForegroundColor Red
        foreach ($Op in $BadShape) { Write-Host "    $($Op.Key) derived the invalid identifier $($Op.Id)" -ForegroundColor Red }
        exit 1
    }
    Write-Host "  + stale-override, collision and shape assertions passed - $($ById.Count) distinct operationIds" -ForegroundColor Green

    # --- 6. T3, assign ---
    # Appended as a new last member, which is deterministic run to run.
    foreach ($Op in $SpecOps) { $Op.Node['operationId'] = [System.Text.Json.Nodes.JsonValue]::Create($Op.Id) }
    Write-Host "  + T3 assigned $($SpecOps.Count) operationIds" -ForegroundColor Green

    # --- 7. The inline census, count half ---
    if ($SpecOps.Count -ne $ExpectedOperations) {
        Write-Host "ERROR: REFUSED - the patched document carries $($SpecOps.Count) operations, expected $ExpectedOperations. Nothing was staged." -ForegroundColor Red
        exit 1
    }

    # --- 8. Stage. Never the output path itself ---
    # The relaxed encoder leaves the 25 apostrophes in the document literal, so the diff against
    # the capture shows the transforms and nothing else. The indented writer emits the platform
    # newline, CRLF here, and .gitattributes declares *.json as eol=lf, so LF is applied explicitly
    # or a Linux runner would produce a different hash. One trailing newline, per .editorconfig.
    $Writer = [System.Text.Json.JsonSerializerOptions]::new()
    $Writer.WriteIndented = $true
    $Writer.Encoder = [System.Text.Encodings.Web.JavaScriptEncoder]::UnsafeRelaxedJsonEscaping
    $StagedJson = (($Document.ToJsonString($Writer)) -replace "`r`n", "`n").TrimEnd("`n") + "`n"
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    [System.IO.File]::WriteAllText($StagePath, $StagedJson, [System.Text.UTF8Encoding]::new($false))
    $StagedBytes = (Get-Item -LiteralPath $StagePath).Length
    # The size half of the census, and the only half that catches a depth-truncated document:
    # truncation preserves keys at every level and destroys only values, so counts still agree.
    if ($StagedBytes -lt $MinimumStagedBytes) {
        Write-Refusal @("ERROR: the staged spec is $StagedBytes bytes, below the floor of $MinimumStagedBytes. A depth-2 serialization of this document is 48,452.")
        exit 1
    }
    Write-Host "  + staged $StagedBytes bytes, sha256 $((Get-FileHash -Algorithm SHA256 -LiteralPath $StagePath).Hash.ToLower())" -ForegroundColor Green

    # --- 9. Promote. The first write to anything committed ---
    Move-Item -LiteralPath $StagePath -Destination $OutPath -Force
    Write-Host "  + promoted to $OutPath" -ForegroundColor Green

    # --- 10. The manifest ---
    # capture-spec.ps1 rebuilds this file from its own observed fields, so a re-capture DROPS
    # generatedSpecSha256. Deliberate: a new capture invalidates the patched spec, and this script
    # is what puts the field back.
    if (Test-Path -LiteralPath $ProvenancePath) {
        $PromotedSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $OutPath).Hash.ToLower()
        # -DateKind String, matching capture-spec.ps1. Without it capturedAt and whisparrBuildTime
        # are parsed into [DateTime] and re-serialized, making the committed bytes depend on the
        # writing machine's timezone. -Depth is explicit and the truncation warning terminates.
        $Provenance = Get-Content -Raw -LiteralPath $ProvenancePath | ConvertFrom-Json -DateKind String
        if ($Provenance.PSObject.Properties.Name -contains 'generatedSpecSha256') {
            $Provenance.generatedSpecSha256 = $PromotedSha
        } else {
            $Provenance | Add-Member -NotePropertyName 'generatedSpecSha256' -NotePropertyValue $PromotedSha
        }
        $ProvenanceJson = ((ConvertTo-Json -InputObject $Provenance -Depth 8 -WarningAction Stop) -replace "`r`n", "`n").TrimEnd("`n") + "`n"
        [System.IO.File]::WriteAllText($ProvenancePath, $ProvenanceJson, [System.Text.UTF8Encoding]::new($false))
        Write-Host "  + wrote generatedSpecSha256 $PromotedSha to $ProvenancePath" -ForegroundColor Green
    }

    Write-Host "Done. $OutPath" -ForegroundColor Green
}
finally {
    # A run killed mid-write leaves a partial staging file, and .gitignore does not cover the
    # .incoming suffix, so clearing it here is what keeps the working tree clean.
    if (Test-Path -LiteralPath $StagePath) { Remove-Item -LiteralPath $StagePath -Force }
}
