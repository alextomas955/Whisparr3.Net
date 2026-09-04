<#
.SYNOPSIS
  Pre-process the captured Whisparr 3 (Eros) OpenAPI document into the spec the generator reads.

.DESCRIPTION
  Reads the byte-verbatim capture, applies three transforms, gates the result on a staging path,
  and only then replaces the committed spec.

    T1  Root security. Whisparr declares both API key schemes and then serves an empty
        requirement, so the generated client would carry no auth call site at all. Repaired to the
        auth-optional, both-schemes form (PREP-02).
    T2  Delete paths["/"], a StaticResource catch-all whose required in: path parameter is absent
        from its own URL template. 190 paths and 273 operations become 189 and 272 (PREP-03).
    T3  operationId, assigned from generator/operation-ids.json and from nothing else. The map is
        committed source; no path through this script writes it or derives a name for assignment
        (PREP-04, PREP-05).

  The map gate refuses in both directions and accumulates both into one refusal, because a map
  that is both incomplete and stale is the ordinary case during a spec refresh. Each unmapped
  operation is printed with a proposed operationId, which is authoring input for a human editing
  the map and is never assigned here. That is what makes a Whisparr version bump a short review.

  Everything is written to $OutFile.incoming first and promoted only after the census and the
  staged read-back have passed, so a run that refuses leaves the committed spec, manifest and
  report exactly as they were. Not ceremony: a code review found a gate running after the
  committed spec had already been overwritten.

  Parsing and serialization use System.Text.Json.Nodes.JsonNode rather than the JSON cmdlets the
  sibling scripts use. ConvertTo-Json's -Depth defaults to 2, and against this 10-deep document
  that default emits a valid 48,452-byte file in which every operation body has become a
  placeholder string, warns on the warning stream only, exits 0, and is then passed by
  assert-spec-census.ps1 at 190 paths and 273 operations. Do not harmonize this back.

  Nothing written here varies between two runs over the same capture: no timestamp, no GUID, no
  environment value and no absolute path. That is what PREP-01 asks for.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\preprocess-spec.ps1
  # Reads spec/openapi.raw.json and writes spec/openapi.generated.json inside the repository.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\preprocess-spec.ps1 -MapPath C:\scratch\broken-map.json -OutFile C:\scratch\out.json
  # A map-gate fixture run. Expected to refuse before staging, name every operation the map does
  # not cover and every map entry that matches no operation, print a proposed name for each
  # unmapped operation, and exit non-zero. -OutFile must be scratch; see the guard at step 0.
#>

[CmdletBinding()]
param(
    # The document to pre-process. A relative path resolves against the repository root.
    [string]$RawSpec = 'spec/openapi.raw.json',

    # Where to write the patched spec. A relative path resolves against the repository root, so
    # the default lands in the repo wherever this is run from.
    [string]$OutFile = 'spec/openapi.generated.json',

    # The committed operationId contract (PREP-05). The only source of an operationId this
    # pipeline will use. There is deliberately no parameter that writes it: a run that regenerates
    # the map from the spec is exactly the silent public-API rename PREP-05 forbids.
    [string]$MapPath = 'generator/operation-ids.json'
)

$ErrorActionPreference = 'Stop'
# Without strict mode a renamed or absent member evaluates to $null, the transform writes null
# into the patched spec, and the run prints Done. and exits 0.
Set-StrictMode -Version Latest

# --- Constants (edit here if the layout changes) ---
$RepoRoot = Split-Path -Parent $PSScriptRoot
function Resolve-RepoPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($(if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $RepoRoot $Path }))
}

# Auth-optional, header scheme only.
#
# This was both schemes until 2026-09-04. Whisparr declares the key twice, X-Api-Key in the header
# and apikey in the query string, as OR-alternatives. The generichost generator does not treat them
# as alternatives: it emits a call to every declared scheme on every operation, so the both-schemes
# form put the API key in the URL query string of all 272 requests as well as in the header.
# Measured before the change: 272 UseInQuery and 272 UseInHeader call sites.
#
# A credential in a URL reaches server access logs, reverse-proxy logs and Referer headers, which is
# not acceptable in a library other people install. Upstream openapi-generator issue 24138 has this
# open with maintainer discussion; the recommended workaround is to drop the extra scheme, which is
# what this literal now does at the spec level rather than undoing it downstream.
#
# devopsarr's Rust Whisparr client has the same defect. Their Python and Go clients avoid it only
# because the consumer chooses which schemes to populate. The one production consumer of any of
# them, terraform-provider-whisparr, bypasses the generated auth entirely and sets the header itself.
#
# Parsed from a literal rather than built from a PowerShell array: a single-element array piped
# through the serializer unrolls into an object, so a single-element variant would be corrupted.
$SecurityLiteral = '[{},{"X-Api-Key":[]}]'
# The floor below which the staged document cannot be an honest patched spec. The capture is
# 381,380 bytes and its depth-2 truncation is 48,452, so anything between is a wide margin.
$MinimumStagedBytes = 350000
$HttpMethods        = 'get', 'put', 'post', 'delete', 'options', 'head', 'patch', 'trace'
# A valid C# identifier of the shape this library's public method names take. Anchored on purpose.
# If nothing invalid ever reaches the generator, what the generator would do to an invalid name
# stops mattering.
$OperationIdPattern = '^[A-Z][A-Za-z0-9]*$'
$ReportIndent = '    '
# The schema names that would collide with a BCL type name, so the report can name the ones this
# document actually declares rather than repeat the inherited claim of five.
$BclCollisionNames = 'Command', 'Field', 'TimeSpan', 'HttpUri', 'Version'

$RawPath     = Resolve-RepoPath $RawSpec
$OutPath     = Resolve-RepoPath $OutFile
$MapFullPath = Resolve-RepoPath $MapPath
$OutDir      = Split-Path -Parent $OutPath
# The manifest and the report are derived from the output file's own directory rather than
# hardcoded, so a run with a scratch output path cannot overwrite either committed artifact.
$ProvenancePath = Join-Path $OutDir 'PROVENANCE.json'
$ReportFullPath = Join-Path $OutDir 'transform-report.txt'
# Every run lands here first and is promoted only once every gate has passed. Declared beside the
# other paths so the finally block can clear a partial write.
$StagePath = "$OutPath.incoming"

$DefaultRawPath     = Resolve-RepoPath 'spec/openapi.raw.json'
$DefaultOutPath     = Resolve-RepoPath 'spec/openapi.generated.json'
$DefaultMapFullPath = Resolve-RepoPath 'generator/operation-ids.json'

# Every path the report prints is repository-relative with forward slashes. An absolute path would
# carry a drive letter into a committed review artifact and two checkouts would produce different
# reports. A scratch path on another volume keeps its own spelling; that report is never committed.
function Get-ReportPathLabel {
    param([string]$FullPath)
    return ([System.IO.Path]::GetRelativePath($Script:RepoRoot, $FullPath)).Replace('\', '/')
}

function Write-Refusal {
    param([string[]]$Message)
    if (Test-Path -LiteralPath $Script:StagePath) { Remove-Item -LiteralPath $Script:StagePath -Force }
    foreach ($Line in $Message) { Write-Host $Line -ForegroundColor Red }
    Write-Host "  The staged spec has been discarded. $Script:OutPath and $Script:ProvenancePath are untouched." -ForegroundColor Red
}

# devopsarr's list rule keys on the 200 response declaring a JSON array. Walk the chain
# defensively and stop at the first non-object rather than calling GetValue<T>(), which throws on
# a JsonObject and would turn a diagnostic into a stack trace.
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

# devopsarr's assign_operation_id.py algorithm, ported faithfully, with one deliberate fix: this
# iterates the segment list BACKWARDS in the placeholder-removal and tag-casing loop, because
# devopsarr's forward loop mutates the list it is enumerating and a removal makes it skip the
# following element. Reached only from the map gate's failure path, and it never assigns anything.
# The name it returns is a starting point for a human editing the committed map.
function Get-ProposedOperationId {
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

Write-Host "Pre-process Whisparr 3 openapi -> $OutPath" -ForegroundColor Cyan
Write-Host "  - reading $RawPath" -ForegroundColor DarkGray

try {
    # --- 0. A fixture run must never be able to promote itself onto the committed deliverable ---
    # The map reaches the committed spec through T3 just as surely as the input document does: a
    # substituted map identical to the committed one except for one value renames a public method
    # and passes every gate below with each line green.
    #
    # The two operands take different comparers on purpose, and both directions fail closed on
    # both platforms. "Is this a non-default input" is ordinal, so on a Linux CI target
    # spec/OPENAPI.RAW.JSON is not spec/openapi.raw.json and the guard fires. "Is this the
    # committed output path" stays case-insensitive, because on NTFS a differently-cased spelling
    # IS the committed file and an ordinal test there would let it through.
    if (($RawPath -cne $DefaultRawPath -or $MapFullPath -cne $DefaultMapFullPath) -and $OutPath -eq $DefaultOutPath) {
        Write-Host 'ERROR: REFUSED - a non-default input may not be written to the committed output path.' -ForegroundColor Red
        Write-Host "  input  $RawPath" -ForegroundColor Red
        Write-Host "  map    $MapFullPath" -ForegroundColor Red
        Write-Host "  output $OutPath" -ForegroundColor Red
        Write-Host '  Pass -OutFile with a scratch path as well. Only the committed capture and the committed map may produce spec/openapi.generated.json.' -ForegroundColor Red
        exit 1
    }
    if (-not (Test-Path -LiteralPath $RawPath)) {
        Write-Host "ERROR: REFUSED - no input document at $RawPath." -ForegroundColor Red
        exit 1
    }

    # --- 1. Parse ---
    $RawBytes = (Get-Item -LiteralPath $RawPath).Length
    $RawSha   = (Get-FileHash -Algorithm SHA256 -LiteralPath $RawPath).Hash.ToLower()
    $RawText  = Get-Content -Raw -LiteralPath $RawPath
    $Document = [System.Text.Json.Nodes.JsonNode]::Parse($RawText)
    Write-Host "  + parsed $RawBytes bytes, sha256 $RawSha" -ForegroundColor Green

    # --- 1b. The PREP-06 observed values, measured on the input before any transform ---
    # Every reason the report prints that CAN be checked is measured here, so a reviewer can
    # re-derive it straight from the capture. Prose that merely names a value is not a check.
    $ObservedSecondSuccessCodes = 0
    $ObservedMultiTagOperations = 0
    $ObservedUntaggedOperations = 0
    $OperationCountBefore       = 0
    $PathCountBefore            = $Document['paths'].AsObject().Count
    foreach ($PathEntry in $Document['paths'].AsObject()) {
        if ($PathEntry.Value -isnot [System.Text.Json.Nodes.JsonObject]) { continue }
        foreach ($Member in $PathEntry.Value.AsObject()) {
            if ($HttpMethods -notcontains $Member.Key) { continue }
            $OperationCountBefore++
            $Operation = $Member.Value
            if ($Operation -isnot [System.Text.Json.Nodes.JsonObject]) { continue }
            $Responses = $Operation['responses']
            if ($Responses -is [System.Text.Json.Nodes.JsonObject]) {
                # A second documented 2xx code beside 200. This is the overlap the "200" to "2XX"
                # rewrite would create, counted rather than asserted.
                foreach ($Response in $Responses.AsObject()) {
                    if ($Response.Key.StartsWith('2') -and $Response.Key -cne '200') { $ObservedSecondSuccessCodes++ }
                }
            }
            $Tags     = $Operation['tags']
            $TagCount = if ($Tags -is [System.Text.Json.Nodes.JsonArray]) { $Tags.Count } else { 0 }
            if ($TagCount -gt 1) { $ObservedMultiTagOperations++ }
            if ($TagCount -eq 0) { $ObservedUntaggedOperations++ }
        }
    }

    # devopsarr's fixes.py rewrites three schemas to {"type": "string"}. Counted over the raw text
    # rather than over the schema names, because the honest form of the claim is "absent from the
    # whole document", not "absent from components.schemas".
    $ObservedTimeSpan = ([regex]::Matches($RawText, 'TimeSpan')).Count
    $ObservedHttpUri  = ([regex]::Matches($RawText, 'HttpUri')).Count

    # Plain assignment inside an if BLOCK, never `$x = if (...) { $node['k'] }`. A JsonObject is
    # enumerable, so an if-expression's output is unrolled by the pipeline into key-value pairs
    # and the -is test below then silently fails against a well-formed document.
    $SchemaNames = [System.Collections.Generic.List[string]]::new()
    $Components  = $Document['components']
    $Schemas     = $null
    if ($Components -is [System.Text.Json.Nodes.JsonObject]) { $Schemas = $Components['schemas'] }
    if ($Schemas -is [System.Text.Json.Nodes.JsonObject]) {
        foreach ($Schema in $Schemas.AsObject()) { $SchemaNames.Add($Schema.Key) }
    }
    # Schemas NAMED Version, not substring hits. The substring occurs inside other property names
    # and a raw count would read as five, which is where the inherited claim came from.
    $ObservedVersionSchema = @($SchemaNames | Where-Object { $_ -ceq 'Version' }).Count
    $ObservedBclNames      = (@($SchemaNames | Where-Object { $BclCollisionNames -ccontains $_ }) -join ' and ')
    if ([string]::IsNullOrEmpty($ObservedBclNames)) { $ObservedBclNames = 'none' }

    $ObservedImportListType = '(absent)'
    if ($Schemas -is [System.Text.Json.Nodes.JsonObject]) {
        $ImportListType = $Schemas['ImportListType']
        if ($ImportListType -is [System.Text.Json.Nodes.JsonObject]) {
            $ImportListEnum = $ImportListType['enum']
            if ($ImportListEnum -is [System.Text.Json.Nodes.JsonArray]) {
                $Members = [System.Collections.Generic.List[string]]::new()
                foreach ($Member in $ImportListEnum) { $Members.Add($Member.GetValue[string]()) }
                $ObservedImportListType = $Members -join ','
            }
        }
    }

    $ObservedTags = if ($Document['tags'] -is [System.Text.Json.Nodes.JsonArray]) { $Document['tags'].Count } else { 0 }

    Write-Host "  + measured the input document: $ObservedTags tags, $ObservedSecondSuccessCodes second 2xx codes, BCL-looking schema names $ObservedBclNames" -ForegroundColor Green

    # --- 2. T1, the root security repair (PREP-02) ---
    # Replaced in place, which keeps security at its position in the root key order. A removal
    # followed by an add would move it to the end and inflate the diff against the capture.
    $SecurityBefore = if ($null -eq $Document['security']) { '(absent)' } else { $Document['security'].ToJsonString() }
    $Document['security'] = [System.Text.Json.Nodes.JsonNode]::Parse($SecurityLiteral)
    $SecurityAfter = $Document['security'].ToJsonString()
    Write-Host "  + T1 security $SecurityBefore -> $SecurityAfter" -ForegroundColor Green

    # --- 3. T2, the malformed root path (PREP-03) ---
    # Assert the removal from the call's own return value rather than trusting it. Deleting a key
    # that was already gone would otherwise produce a plausible 272-operation spec from a document
    # this pipeline has never seen, which is the fail-open direction PREP-03 forbids.
    $PathsObject = $Document['paths'].AsObject()
    # Read the doomed path item BEFORE removing it, so the report can name the method, the tag and
    # the malformed parameter from the document rather than from a transcribed description.
    $RemovedOperations = [System.Collections.Generic.List[string]]::new()
    $RootPathItemKey   = '/'
    $RootPathItem      = $PathsObject[$RootPathItemKey]
    if ($RootPathItem -is [System.Text.Json.Nodes.JsonObject]) {
        foreach ($Member in $RootPathItem.AsObject()) {
            if ($HttpMethods -notcontains $Member.Key) { continue }
            $Operation = $Member.Value
            $Tag       = 'untagged'
            $BadParams = [System.Collections.Generic.List[string]]::new()
            if ($Operation -is [System.Text.Json.Nodes.JsonObject]) {
                $Tags = $Operation['tags']
                if ($Tags -is [System.Text.Json.Nodes.JsonArray] -and $Tags.Count -gt 0) { $Tag = $Tags[0].GetValue[string]() }
                $Parameters = $Operation['parameters']
                if ($Parameters -is [System.Text.Json.Nodes.JsonArray]) {
                    foreach ($Parameter in $Parameters) {
                        if ($Parameter -isnot [System.Text.Json.Nodes.JsonObject]) { continue }
                        if ($null -eq $Parameter['in'] -or $Parameter['in'].GetValue[string]() -ne 'path') { continue }
                        $ParamName = if ($null -eq $Parameter['name']) { 'unnamed' } else { $Parameter['name'].GetValue[string]() }
                        # in: path only makes sense for a name that appears in the URL template.
                        if (-not $RootPathItemKey.Contains("{$ParamName}")) { $BadParams.Add($ParamName) }
                    }
                }
            }
            $Reason = if ($BadParams.Count -eq 0) { 'no path parameter is declared' } else { "required parameter '$($BadParams -join ", ")' (in: path) absent from the URL template" }
            $RemovedOperations.Add("$($Member.Key.ToUpperInvariant()) $RootPathItemKey   [tag $Tag]  $Reason")
        }
    }
    if (-not $PathsObject.Remove($RootPathItemKey)) {
        Write-Host 'ERROR: REFUSED - paths["/"] is not present in this document.' -ForegroundColor Red
        Write-Host "  $RawPath is not what this pipeline expects. The capture carries a malformed StaticResource catch-all at the key ""/"", and PREP-03 exists to delete exactly that key. Nothing was written." -ForegroundColor Red
        exit 1
    }
    Write-Host "  + T2 deleted paths[""/""], $($PathsObject.Count) path items remain" -ForegroundColor Green

    # --- 4. Load the committed operationId map (PREP-05) ---
    # Steps 4 to 8 all run before the staged write, so none of them has a staging file to discard
    # and none of them calls Write-Refusal. The post-staging gates do.
    if (-not (Test-Path -LiteralPath $MapFullPath)) {
        Write-Host "ERROR: REFUSED - no operationId map at $MapFullPath." -ForegroundColor Red
        Write-Host '  The map is committed source and the only source of an operationId. This script never writes it. Nothing was written.' -ForegroundColor Red
        exit 1
    }
    $MapNode = [System.Text.Json.Nodes.JsonNode]::Parse((Get-Content -Raw -LiteralPath $MapFullPath))
    if ($MapNode -isnot [System.Text.Json.Nodes.JsonObject]) {
        Write-Host "ERROR: REFUSED - the operationId map at $MapFullPath is not a JSON object." -ForegroundColor Red
        Write-Host '  The map is an object keyed "METHOD /path" whose values are operationId strings. Nothing was written.' -ForegroundColor Red
        exit 1
    }
    # Ordinal comparison throughout. A case-insensitive dictionary would accept a map key whose
    # method is lower-cased; the key shape is the upper-cased method, one space, then the path
    # exactly as the document spells it.
    $Map     = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $MapKeys = [System.Collections.Generic.List[string]]::new()
    foreach ($Entry in $MapNode.AsObject()) {
        if ($null -eq $Entry.Value -or $Entry.Value.GetValueKind() -ne [System.Text.Json.JsonValueKind]::String -or
            [string]::IsNullOrWhiteSpace($Entry.Value.GetValue[string]())) {
            Write-Host "ERROR: REFUSED - the operationId map entry ""$($Entry.Key)"" does not carry a non-empty string." -ForegroundColor Red
            Write-Host '  Every map value is an operationId. Nothing was written.' -ForegroundColor Red
            exit 1
        }
        $Map[$Entry.Key] = $Entry.Value.GetValue[string]()
        $MapKeys.Add($Entry.Key)
    }
    Write-Host "  + loaded $($MapKeys.Count) operationId map entries from $MapFullPath" -ForegroundColor Green

    # The spec side of the comparison, keyed the same way.
    $SpecOps = [System.Collections.Generic.List[object]]::new()
    foreach ($PathEntry in $PathsObject) {
        if ($PathEntry.Value -isnot [System.Text.Json.Nodes.JsonObject]) {
            Write-Host "ERROR: REFUSED - the path item $($PathEntry.Key) is not a JSON object, so this document cannot be enumerated for operations. Nothing was written." -ForegroundColor Red
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

    # --- 5. The map gate, both directions accumulated into one refusal (PREP-05) ---
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
                $Tag = ''
                $Tags = $Op.Node['tags']
                if ($Tags -is [System.Text.Json.Nodes.JsonArray] -and $Tags.Count -gt 0 -and
                    $Tags[0].GetValueKind() -eq [System.Text.Json.JsonValueKind]::String) {
                    $Tag = $Tags[0].GetValue[string]()
                }
                $Proposed = Get-ProposedOperationId -Method $Op.Method -Path $Op.Path -Tag $Tag -ReturnsArray (Test-ReturnsJsonArray -Operation $Op.Node)
                Write-Host "    $($Op.Key) -> $Proposed" -ForegroundColor Red
            }
        }
        if ($Orphans.Count -gt 0) {
            Write-Host '  Orphaned map entries:' -ForegroundColor Red
            foreach ($Key in $Orphans) { Write-Host "    $Key" -ForegroundColor Red }
        }
        Write-Host "  Bring $(Get-ReportPathLabel -FullPath $MapFullPath) back in step with the spec and run again: review each proposed name above and add it, and delete each orphaned entry. A proposal is authoring input for a human; this script never assigns one." -ForegroundColor Red
        Write-Host '  Nothing was staged and nothing was promoted.' -ForegroundColor Red
        exit 1
    }
    Write-Host "  + map gate passed - $($SpecOps.Count) operations, $($MapKeys.Count) map entries, key sets identical in both directions" -ForegroundColor Green

    # --- 6. The collision and identifier-shape assertions (PREP-04) ---
    # Not the generator's FIX_DUPLICATED_OPERATIONID normalizer, which de-duplicates by appending
    # a positional suffix: that would mask this assertion, and inserting an operation upstream
    # moves the suffix onto a different method and renames public API with no diff.
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
            Write-Host "  the operationId $($Collision.Key) is assigned to:" -ForegroundColor Red
            foreach ($Key in $Collision.Value) { Write-Host "    $Key" -ForegroundColor Red }
        }
        Write-Host '  The generator emits one class per tag, so two operations sharing an operationId are two methods with one name on one class. Nothing was staged and nothing was promoted.' -ForegroundColor Red
        exit 1
    }
    # -cnotmatch, not -notmatch. PowerShell's -match is case-insensitive, so the anchored pattern
    # would accept listMovie and the gate would pass a name the generator has to sanitize.
    $BadShape = [System.Collections.Generic.List[string]]::new()
    foreach ($Key in $MapKeys) { if ($Map[$Key] -cnotmatch $OperationIdPattern) { $BadShape.Add($Key) } }
    if ($BadShape.Count -gt 0) {
        Write-Host "ERROR: identifier shape assertion failed - $($BadShape.Count) map values do not match $OperationIdPattern." -ForegroundColor Red
        foreach ($Key in $BadShape) { Write-Host "    $Key carries the invalid identifier $($Map[$Key])" -ForegroundColor Red }
        Write-Host '  An invalid name reaching the generator would be sanitized into a name of the generator''s own choosing, which is the silent public-API rename PREP-05 exists to prevent. Nothing was staged and nothing was promoted.' -ForegroundColor Red
        exit 1
    }
    Write-Host "  + collision and shape assertions passed - $($ById.Count) distinct operationIds, all matching $OperationIdPattern" -ForegroundColor Green

    # --- 7. T3, operationId, from the map only (PREP-04, PREP-05) ---
    $AssignedFromMap = 0
    # No code path increments this. The pipeline never derives a name for assignment, and the zero
    # it prints is the evidence of that rather than an accounting detail.
    $DerivedAtRuntime = 0
    foreach ($Op in $SpecOps) {
        if ($Op.Node -isnot [System.Text.Json.Nodes.JsonObject]) {
            Write-Host "ERROR: REFUSED - the operation $($Op.Key) is not a JSON object. An operation body replaced by a scalar is the depth-truncation signature. Nothing was staged." -ForegroundColor Red
            exit 1
        }
        # Appended as a new last member, which is deterministic run to run.
        $Op.Node['operationId'] = [System.Text.Json.Nodes.JsonValue]::Create($Map[$Op.Key])
        $AssignedFromMap++
    }
    Write-Host "  + T3 assigned $AssignedFromMap operationIds from map, $DerivedAtRuntime derived" -ForegroundColor Green

    # --- 8. Stage. Never the output path itself ---
    # The relaxed encoder leaves the 25 apostrophes already in the document literal, so the patched
    # spec's diff against the capture shows the transforms and nothing else. The indented writer
    # emits the platform newline, which is CRLF here, and .gitattributes declares *.json as eol=lf,
    # so the newline is normalized explicitly: the same code on a Linux runner would otherwise
    # produce a different hash from a dev machine. Exactly one trailing newline, per .editorconfig.
    $Writer = [System.Text.Json.JsonSerializerOptions]::new()
    $Writer.WriteIndented = $true
    $Writer.Encoder = [System.Text.Encodings.Web.JavaScriptEncoder]::UnsafeRelaxedJsonEscaping
    $StagedJson = (($Document.ToJsonString($Writer)) -replace "`r`n", "`n").TrimEnd("`n") + "`n"
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    [System.IO.File]::WriteAllText($StagePath, $StagedJson, [System.Text.UTF8Encoding]::new($false))
    $StagedBytes = (Get-Item -LiteralPath $StagePath).Length
    $StagedSha   = (Get-FileHash -Algorithm SHA256 -LiteralPath $StagePath).Hash.ToLower()
    Write-Host "  + staged $StagedBytes bytes at $StagePath, sha256 $StagedSha" -ForegroundColor Green

    # --- 9. The census over the staged bytes ---
    # $LASTEXITCODE is the only reliable way to read a child script's exit code; the stop error
    # preference does not intercept it. -SkipProvenanceHash because the manifest beside the output
    # still describes the previous run.
    & (Join-Path $PSScriptRoot 'assert-spec-census.ps1') -Path $StagePath -Artifact Patched -SkipProvenanceHash
    if ($LASTEXITCODE -ne 0) {
        $CensusExit = $LASTEXITCODE
        Write-Refusal @("ERROR: census gate failed (exit $CensusExit) for the spec staged at $StagePath.")
        exit $CensusExit
    }

    # --- 10. Read the two transforms back out of the staged bytes (PREP-02, PREP-04) ---
    # The census counts keys and cannot see a truncated document, because truncation preserves keys
    # at every level and destroys only values. The T1 and T3 lines above report on the object that
    # was mutated rather than on the file about to be promoted. This is the only place the promoted
    # spec is compared against the committed map; nothing else reads the two files against each
    # other. Every expected value comes from a named constant or from the map, never from the
    # document being checked.
    if ($StagedBytes -lt $MinimumStagedBytes) {
        Write-Refusal @(
            "ERROR: staged spec is $StagedBytes bytes, below the floor of $MinimumStagedBytes.",
            '  A patched spec of this document is above 381,000 bytes. A depth-2 serialization of it is 48,452.'
        )
        exit 1
    }
    $Staged         = [System.Text.Json.Nodes.JsonNode]::Parse((Get-Content -Raw -LiteralPath $StagePath))
    $StagedSecurity = if ($null -eq $Staged['security']) { '(absent)' } else { $Staged['security'].ToJsonString() }
    if ($StagedSecurity -cne $SecurityLiteral) {
        Write-Refusal @("ERROR: the staged root security is $StagedSecurity, expected $SecurityLiteral.")
        exit 1
    }
    $StagedIds = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($PathEntry in $Staged['paths'].AsObject()) {
        foreach ($Member in $PathEntry.Value.AsObject()) {
            if ($HttpMethods -notcontains $Member.Key) { continue }
            # An operation must be a JSON object carrying a string operationId. In a truncated
            # document the body is a plain string, so this is also the truncation check.
            $Id = if ($Member.Value -is [System.Text.Json.Nodes.JsonObject] -and
                      $null -ne $Member.Value['operationId'] -and
                      $Member.Value['operationId'].GetValueKind() -eq [System.Text.Json.JsonValueKind]::String) {
                $Member.Value['operationId'].GetValue[string]()
            } else { '(absent)' }
            $StagedIds["$($Member.Key.ToUpperInvariant()) $($PathEntry.Key)"] = $Id
        }
    }
    $Disagree = @($StagedIds.Keys | Where-Object { -not $Map.ContainsKey($_) -or $Map[$_] -cne $StagedIds[$_] })
    if ($StagedIds.Count -ne $Map.Count -or $Disagree.Count -gt 0) {
        $Message = @("ERROR: the staged spec carries $($StagedIds.Count) operations against $($Map.Count) map entries, $($Disagree.Count) of them disagreeing with the map.")
        foreach ($Key in $Disagree) { $Message += "    $Key carries $($StagedIds[$Key]), the map says $(if ($Map.ContainsKey($Key)) { $Map[$Key] } else { '(no map entry)' })" }
        Write-Refusal $Message
        exit 1
    }
    Write-Host "  + staged read-back passed - root security $StagedSecurity, $($StagedIds.Count) operationIds equal to the map" -ForegroundColor Green

    # --- 11. Promote. The first write to anything committed ---
    Move-Item -LiteralPath $StagePath -Destination $OutPath -Force
    Write-Host "  + promoted to $OutPath" -ForegroundColor Green

    # --- 12. The manifest ---
    # capture-spec.ps1 rebuilds this file from its own observed fields, so a re-capture DROPS
    # generatedSpecSha256. That is deliberate: a new capture invalidates the patched spec, and the
    # next census with the Patched profile fails until this script runs again.
    if (Test-Path -LiteralPath $ProvenancePath) {
        $PromotedSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $OutPath).Hash.ToLower()
        # -DateKind String, matching capture-spec.ps1. Without it capturedAt and whisparrBuildTime
        # are parsed into [DateTime] and re-serialized, which makes the committed bytes depend on
        # the writing machine's timezone. -Depth is explicit and the truncation warning is a
        # terminating error, because nothing here may truncate in silence.
        $Provenance = Get-Content -Raw -LiteralPath $ProvenancePath | ConvertFrom-Json -DateKind String
        if ($Provenance.PSObject.Properties.Name -contains 'generatedSpecSha256') {
            $Provenance.generatedSpecSha256 = $PromotedSha
        } else {
            $Provenance | Add-Member -NotePropertyName 'generatedSpecSha256' -NotePropertyValue $PromotedSha
        }
        $ProvenanceJson = ((ConvertTo-Json -InputObject $Provenance -Depth 8 -WarningAction Stop) -replace "`r`n", "`n").TrimEnd("`n") + "`n"
        [System.IO.File]::WriteAllText($ProvenancePath, $ProvenanceJson, [System.Text.UTF8Encoding]::new($false))
        Write-Host "  + wrote generatedSpecSha256 $PromotedSha to $ProvenancePath" -ForegroundColor Green
    } else {
        # Only reachable with a scratch output path, which by design has no manifest beside it.
        Write-Host "  - no PROVENANCE.json beside $OutPath, generatedSpecSha256 not recorded" -ForegroundColor DarkGray
    }

    # --- 13. The transform report (PREP-08) ---
    # What each transform changed with its count, and why each devopsarr transform this pipeline
    # does not reuse was rejected. Every number quoted in section 4 is measured at step 1b against
    # the capture, so a reader can re-derive it rather than take the sentence on trust, and a
    # future capture that invalidates a reason changes the report.
    #
    # The report carries no timestamp, no GUID, no environment value and no absolute path, so two
    # runs over the same capture produce a byte-identical report. A timestamp would produce a diff
    # on every run even when nothing changed, which is exactly the signal this file exists to
    # carry. Provenance timestamps belong in PROVENANCE.json, which already has one.
    #
    # The 272 assigned operationIds are deliberately not listed here. generator/operation-ids.json
    # is committed source, is keyed the same way, and is where a reviewer reads them.
    $ReportBytes = (Get-Item -LiteralPath $OutPath).Length
    $ReportSha   = (Get-FileHash -Algorithm SHA256 -LiteralPath $OutPath).Hash.ToLower()

    $Report = [System.Collections.Generic.List[string]]::new()
    $Report.Add('Whisparr3.Net spec pre-processing report (PREP-08)')
    $Report.Add('')
    $Report.Add("input   $((Get-ReportPathLabel -FullPath $RawPath).PadRight(28))$RawBytes bytes  sha256 $RawSha")
    $Report.Add("output  $((Get-ReportPathLabel -FullPath $OutPath).PadRight(28))$ReportBytes bytes  sha256 $ReportSha")
    $Report.Add('')

    $Report.Add('[1] root security repair (PREP-02)')
    $Report.Add("${ReportIndent}before  $SecurityBefore")
    $Report.Add("${ReportIndent}after   $SecurityAfter")
    $Report.Add("${ReportIndent}Whisparr declares both API key schemes and then serves an empty requirement, so without")
    $Report.Add("${ReportIndent}this repair the generated client carries no auth call site at all.")
    $Report.Add('')

    $Report.Add('[2] delete paths["/"] (PREP-03)')
    foreach ($Removed in $RemovedOperations) { $Report.Add("${ReportIndent}removed     $Removed") }
    $Report.Add("${ReportIndent}paths       $PathCountBefore -> $($PathsObject.Count)")
    $Report.Add("${ReportIndent}operations  $OperationCountBefore -> $($SpecOps.Count)")
    $Report.Add('')

    $Report.Add('[3] operationId assignment (PREP-04, PREP-05)')
    $Report.Add("${ReportIndent}map               $(Get-ReportPathLabel -FullPath $MapFullPath), $($MapKeys.Count) entries")
    $Report.Add("${ReportIndent}assigned          $AssignedFromMap from map, $DerivedAtRuntime derived")
    $Report.Add("${ReportIndent}unmapped          $($Unmapped.Count) operations missing from the map")
    $Report.Add("${ReportIndent}orphaned          $($Orphans.Count) map entries matching no operation")
    $Report.Add("${ReportIndent}collisions        $($Collisions.Count)")
    $Report.Add("${ReportIndent}identifier shape  $($MapKeys.Count - $BadShape.Count)/$($MapKeys.Count) match $OperationIdPattern")
    $Report.Add('')

    $Report.Add('[4] devopsarr transforms deliberately not reused (PREP-06)')
    foreach ($Line in @(
        '"200" -> "2XX"',
        "  Rejected. $ObservedSecondSuccessCodes operations declare a second 2xx code beside 200: POST /api/v3/performer",
        '  (201) and PUT /api/v3/performer/{id} (202). The range key would sit beside a literal code',
        '  inside its own range, and the generichost accessor for that range is unreachable code',
        '  whose generated comparison can never be true.',
        'FIX_DUPLICATED_OPERATIONID',
        '  Rejected. It de-duplicates by appending a positional suffix, which would mask the PREP-04',
        '  collision assertion, and inserting an operation upstream moves the suffix onto a different',
        '  method, renaming public API with no diff.',
        'fixes.py type fixes for TimeSpan, HttpUri and Version',
        "  Not applicable. TimeSpan occurs $ObservedTimeSpan times in this document and HttpUri $ObservedHttpUri times, and",
        "  $ObservedVersionSchema schemas are named Version. The schema names that look like BCL types are $ObservedBclNames,",
        '  but System.Command and System.Field do not exist, so nothing collides and no name mapping',
        '  is needed. A 0-error two-framework compile settled it.',
        'fixes.py ImportListType += "plex"',
        '  Rejected. devopsarr generate their whisparr client from Radarr''s spec, so the patch repairs',
        "  a Radarr gap. Eros serves a different value set, observed here as $ObservedImportListType,",
        '  and adding a member the server cannot send teaches the deserializer to accept something',
        '  this API never returns.',
        'SECURITY_SCHEMES_FILTER',
        '  Rejected. It would drop the query scheme and tidy the generated surface, but ERGO-01',
        '  requires both declared schemes to reach the wire.',
        'FILTER (path allowlist)',
        '  Rejected. It is a prefix allowlist, so excluding one path means enumerating every other',
        '  top-level path, and a future Whisparr adding one would be dropped silently, with the',
        '  operation count falling and nothing reported.',
        'KEEP_ONLY_FIRST_TAG_IN_OPERATION',
        "  No-op. This document declares $ObservedTags tags and every operation carries exactly one:",
        "  $ObservedMultiTagOperations operations carry more than one, $ObservedUntaggedOperations carry none."
    )) { $Report.Add("$ReportIndent$Line") }

    # The same LF, no byte order mark, exactly one trailing newline discipline every other artifact
    # in this repository uses.
    $ReportText = (($Report -join "`n") -replace "`r`n", "`n").TrimEnd("`n") + "`n"
    [System.IO.File]::WriteAllText($ReportFullPath, $ReportText, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  + wrote the transform report to $ReportFullPath" -ForegroundColor Green

    Write-Host "Done. $OutPath" -ForegroundColor Green
}
finally {
    # A run killed mid-write leaves a partial staging file. It is never the deliverable, and
    # .gitignore does not cover the .incoming suffix, so clearing it here is the only thing keeping
    # a killed run from leaving an untracked file in the working tree.
    if (Test-Path -LiteralPath $StagePath) { Remove-Item -LiteralPath $StagePath -Force }
}
