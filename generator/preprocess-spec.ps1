<#
.SYNOPSIS
  Pre-process the captured Whisparr 3 (Eros) OpenAPI document into the spec the generator reads.

.DESCRIPTION
  T1 repairs root security, T2 deletes the malformed paths["/"] so 273 operations become 272, and
  T3 assigns operationId from generator/operation-ids.json and from nothing else. The result is
  gated on a staging path and only then replaces the committed spec.

  The map gate refuses in both directions and prints a proposed operationId for every unmapped
  operation. That is what makes a Whisparr version bump a short review rather than a silent
  public-API rename.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\preprocess-spec.ps1
#>

[CmdletBinding()]
param(
    [string]$RawSpec = 'spec/openapi.raw.json',
    [string]$OutFile = 'spec/openapi.generated.json',
    # The committed operationId contract, and the only source of an operationId this pipeline uses.
    # There is deliberately no parameter that writes it.
    [string]$MapPath = 'generator/operation-ids.json'
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
# (upstream openapi-generator issue 24138).
# Parsed from a literal, not built from a PowerShell array: a single-element array piped through
# the serializer unrolls into an object.
$SecurityLiteral = '[{"X-Api-Key":[]}]'
# The inline census, standing in for the standalone assert-spec-census.ps1 this replaced. The
# capture is 381,380 bytes and its depth-2 truncation is 48,452, so the floor is a wide margin.
$ExpectedOperations = 272
$MinimumStagedBytes = 350000
$HttpMethods        = 'get', 'put', 'post', 'delete', 'options', 'head', 'patch', 'trace'
# A valid C# identifier of the shape this library's public method names take. Anchored on purpose.
$OperationIdPattern = '^[A-Z][A-Za-z0-9]*$'

$RawPath     = Resolve-RepoPath $RawSpec
$OutPath     = Resolve-RepoPath $OutFile
$MapFullPath = Resolve-RepoPath $MapPath
$OutDir      = Split-Path -Parent $OutPath
# Derived from the output file's own directory, so a scratch run cannot overwrite the committed one.
$ProvenancePath = Join-Path $OutDir 'PROVENANCE.json'
# Every run lands here first and is promoted only once every gate has passed. Not ceremony: a code
# review found a gate running after the committed spec had already been overwritten.
$StagePath = "$OutPath.incoming"

$DefaultRawPath     = Resolve-RepoPath 'spec/openapi.raw.json'
$DefaultOutPath     = Resolve-RepoPath 'spec/openapi.generated.json'
$DefaultMapFullPath = Resolve-RepoPath 'generator/operation-ids.json'

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

# devopsarr's assign_operation_id.py, ported faithfully with one fix: this iterates the segment list
# BACKWARDS in the placeholder-removal loop, because devopsarr's forward loop mutates the list it is
# enumerating and a removal makes it skip the following element. Reached only from the map gate's
# failure path, and it never assigns anything. What it returns is authoring input for a human.
function Get-ProposedOperationId {
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
        if ($Parts[$Parts.Count - 1].StartsWith('test')) { $Verb = $Parts[$Parts.Count - 1]; $Parts.RemoveAt($Parts.Count - 1) }
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
    # The map reaches the committed spec through T3 as surely as the document does: a substituted
    # map differing in one value renames a public method. The two operands take different comparers
    # on purpose. "Non-default input" is ordinal, so on Linux spec/OPENAPI.RAW.JSON is not
    # spec/openapi.raw.json and the guard fires. "Committed output path" stays case-insensitive,
    # because on NTFS a differently-cased spelling IS the committed file.
    if (($RawPath -cne $DefaultRawPath -or $MapFullPath -cne $DefaultMapFullPath) -and $OutPath -eq $DefaultOutPath) {
        Write-Host "ERROR: REFUSED - a non-default input may not be written to the committed output path. Pass -OutFile with a scratch path too. input $RawPath / map $MapFullPath / output $OutPath" -ForegroundColor Red
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

    # --- 4. Load the committed operationId map ---
    if (-not (Test-Path -LiteralPath $MapFullPath)) {
        Write-Host "ERROR: REFUSED - no operationId map at $MapFullPath. This script never writes it." -ForegroundColor Red
        exit 1
    }
    $MapNode = [System.Text.Json.Nodes.JsonNode]::Parse((Get-Content -Raw -LiteralPath $MapFullPath))
    if ($MapNode -isnot [System.Text.Json.Nodes.JsonObject]) {
        Write-Host "ERROR: REFUSED - the map at $MapFullPath is not a JSON object keyed ""METHOD /path""." -ForegroundColor Red
        exit 1
    }
    # Ordinal throughout. A case-insensitive dictionary would accept a lower-cased method; the key
    # shape is the upper-cased method, one space, then the path verbatim.
    $Map     = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $MapKeys = [System.Collections.Generic.List[string]]::new()
    foreach ($Entry in $MapNode.AsObject()) {
        if ($null -eq $Entry.Value -or $Entry.Value.GetValueKind() -ne [System.Text.Json.JsonValueKind]::String -or
            [string]::IsNullOrWhiteSpace($Entry.Value.GetValue[string]())) {
            Write-Host "ERROR: REFUSED - the map entry ""$($Entry.Key)"" does not carry a non-empty string." -ForegroundColor Red
            exit 1
        }
        $Map[$Entry.Key] = $Entry.Value.GetValue[string]()
        $MapKeys.Add($Entry.Key)
    }
    Write-Host "  + loaded $($MapKeys.Count) operationId map entries" -ForegroundColor Green

    # The spec side of the comparison, keyed the same way.
    $SpecOps = [System.Collections.Generic.List[object]]::new()
    foreach ($PathEntry in $PathsObject) {
        if ($PathEntry.Value -isnot [System.Text.Json.Nodes.JsonObject]) {
            Write-Host "ERROR: REFUSED - the path item $($PathEntry.Key) is not a JSON object. Nothing was written." -ForegroundColor Red
            exit 1
        }
        foreach ($Member in $PathEntry.Value.AsObject()) {
            if ($HttpMethods -notcontains $Member.Key) { continue }
            $SpecOps.Add([pscustomobject]@{
                Key = "$($Member.Key.ToUpperInvariant()) $($PathEntry.Key)"; Method = $Member.Key
                Path = $PathEntry.Key; Node = $Member.Value
            })
        }
    }

    # --- 5. The map gate, both directions accumulated into one refusal ---
    # This gate is why the separate census and tree-count scripts were removed. If Whisparr adds an
    # operation it refuses as unmapped; if Whisparr removes one it refuses as orphaned. With a
    # fail-closed map of N entries and a generation that then compiles, the compiler itself proves
    # N methods exist, so counting them again proved nothing new.
    $SpecKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($Op in $SpecOps) { [void]$SpecKeys.Add($Op.Key) }
    $Unmapped = [System.Collections.Generic.List[object]]::new()
    foreach ($Op in $SpecOps) { if (-not $Map.ContainsKey($Op.Key)) { $Unmapped.Add($Op) } }
    $Orphans = [System.Collections.Generic.List[string]]::new()
    foreach ($Key in $MapKeys) { if (-not $SpecKeys.Contains($Key)) { $Orphans.Add($Key) } }

    if ($Unmapped.Count -gt 0 -or $Orphans.Count -gt 0) {
        Write-Host 'ERROR: map gate failed - the operationId map and the spec disagree.' -ForegroundColor Red
        Write-Host "  spec to map: $($Unmapped.Count) operations in the spec have no entry in the map." -ForegroundColor Red
        Write-Host "  map to spec: $($Orphans.Count) map entries match no operation in the spec." -ForegroundColor Red
        if ($Unmapped.Count -gt 0) {
            Write-Host '  Unmapped operations, with a proposed operationId for each:' -ForegroundColor Red
            foreach ($Op in $Unmapped) {
                $Tag  = ''
                $Tags = $Op.Node['tags']
                if ($Tags -is [System.Text.Json.Nodes.JsonArray] -and $Tags.Count -gt 0 -and
                    $Tags[0].GetValueKind() -eq [System.Text.Json.JsonValueKind]::String) { $Tag = $Tags[0].GetValue[string]() }
                $Proposed = Get-ProposedOperationId -Method $Op.Method -Path $Op.Path -Tag $Tag -ReturnsArray (Test-ReturnsJsonArray -Operation $Op.Node)
                Write-Host "    $($Op.Key) -> $Proposed" -ForegroundColor Red
            }
        }
        if ($Orphans.Count -gt 0) {
            Write-Host '  Orphaned map entries:' -ForegroundColor Red
            foreach ($Key in $Orphans) { Write-Host "    $Key" -ForegroundColor Red }
        }
        Write-Host '  Review each proposed name above and add it to the map, delete each orphaned entry, and run again. A proposal is authoring input for a human; this script never assigns one. Nothing was staged and nothing was promoted.' -ForegroundColor Red
        exit 1
    }
    Write-Host "  + map gate passed - $($SpecOps.Count) operations, $($MapKeys.Count) map entries, key sets identical in both directions" -ForegroundColor Green

    # --- 6. The collision and identifier-shape assertions ---
    # Not the generator's FIX_DUPLICATED_OPERATIONID normalizer, which de-duplicates by appending a
    # positional suffix: that masks this assertion, and inserting an operation upstream then moves
    # the suffix onto a different method and renames public API with no diff.
    $ById = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new([System.StringComparer]::Ordinal)
    foreach ($Op in $SpecOps) {
        $Id = $Map[$Op.Key]
        if (-not $ById.ContainsKey($Id)) { $ById[$Id] = [System.Collections.Generic.List[string]]::new() }
        $ById[$Id].Add($Op.Key)
    }
    $Collisions = @($ById.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 })
    if ($Collisions.Count -gt 0) {
        Write-Host "ERROR: collision assertion failed - $($Collisions.Count) operationIds are carried by more than one operation." -ForegroundColor Red
        foreach ($Collision in $Collisions) { Write-Host "    $($Collision.Key) is assigned to: $($Collision.Value -join ', ')" -ForegroundColor Red }
        Write-Host '  The generator emits one class per tag, so two operations sharing an operationId are two methods with one name on one class. Nothing was staged.' -ForegroundColor Red
        exit 1
    }
    # -cnotmatch, not -notmatch. PowerShell's -match is case-insensitive, so the anchored pattern
    # would accept listMovie and pass a name the generator then sanitizes into one of its own
    # choosing, which is the silent public-API rename this map exists to stop.
    $BadShape = @($MapKeys | Where-Object { $Map[$_] -cnotmatch $OperationIdPattern })
    if ($BadShape.Count -gt 0) {
        Write-Host "ERROR: identifier shape assertion failed - $($BadShape.Count) map values do not match $OperationIdPattern. Nothing was staged." -ForegroundColor Red
        foreach ($Key in $BadShape) { Write-Host "    $Key carries the invalid identifier $($Map[$Key])" -ForegroundColor Red }
        exit 1
    }
    Write-Host "  + collision and shape assertions passed - $($ById.Count) distinct operationIds" -ForegroundColor Green

    # --- 7. T3, operationId, from the map only ---
    foreach ($Op in $SpecOps) {
        if ($Op.Node -isnot [System.Text.Json.Nodes.JsonObject]) {
            Write-Host "ERROR: REFUSED - the operation $($Op.Key) is not a JSON object. An operation body replaced by a scalar is the depth-truncation signature. Nothing was staged." -ForegroundColor Red
            exit 1
        }
        # Appended as a new last member, which is deterministic run to run.
        $Op.Node['operationId'] = [System.Text.Json.Nodes.JsonValue]::Create($Map[$Op.Key])
    }
    Write-Host "  + T3 assigned $($SpecOps.Count) operationIds from the map, 0 derived" -ForegroundColor Green

    # --- 8. The inline census, count half ---
    if ($SpecOps.Count -ne $ExpectedOperations) {
        Write-Host "ERROR: REFUSED - the patched document carries $($SpecOps.Count) operations, expected $ExpectedOperations. Nothing was staged." -ForegroundColor Red
        exit 1
    }

    # --- 9. Stage. Never the output path itself ---
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

    # --- 10. Promote. The first write to anything committed ---
    Move-Item -LiteralPath $StagePath -Destination $OutPath -Force
    Write-Host "  + promoted to $OutPath" -ForegroundColor Green

    # --- 11. The manifest ---
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
