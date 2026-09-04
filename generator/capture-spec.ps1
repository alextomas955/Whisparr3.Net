<#
.SYNOPSIS
  Capture the Whisparr 3 (Eros) OpenAPI document from a digest-pinned container.

.DESCRIPTION
  Boots the pinned image, polls the spec endpoint until it answers, asserts the instance really is
  Whisparr 3 (Eros), captures the bytes verbatim, and writes spec/PROVENANCE.json beside them.

  The image is referenced only by digest. The moving tags point at Whisparr 2, a different
  application that also serves /api/v3, so an unpinned pull yields a client that compiles and looks
  entirely plausible and is wrong.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\capture-spec.ps1
#>

[CmdletBinding()]
param(
    # The pinned Whisparr 3.4.0.1387 (eros) digest.
    [string]$ImageDigest = 'sha256:fab920114a75f1c86bbadf24c66f1e35a912ace9c7527e971f1032a569589ee6',
    [string]$OutFile = 'spec/openapi.raw.json',
    # The pinned digest is ready in 13 to 19s. Whisparr 2 never becomes ready and consumes the
    # whole budget, which is the refusal working rather than a hang.
    [int]$TimeoutSec = 90
)

$ErrorActionPreference = 'Stop'
# Without strict mode a renamed or dropped member on the status response evaluates to $null, the
# manifest records null, and the run prints Done. and exits 0.
Set-StrictMode -Version Latest

$RepoRoot      = Split-Path -Parent $PSScriptRoot
$Image         = "ghcr.io/hotio/whisparr@$ImageDigest"
$ContainerName = 'whisparr3-capture'
# Not a credential: a fixed constant handed to a container that is destroyed at the end of the run
# and published on 127.0.0.1 only. It is needed for the status read that feeds provenance; the spec
# endpoint itself is served unauthenticated.
$ApiKey    = '0123456789abcdef0123456789abcdef'
$BaseUrl   = 'http://localhost:6969'
$SpecUrl   = "$BaseUrl/docs/v3/openapi.json"
$StatusUrl = "$BaseUrl/api/v3/system/status"

$SpecPath = if ([System.IO.Path]::IsPathRooted($OutFile)) { $OutFile } else { Join-Path $RepoRoot $OutFile }
$SpecDir  = Split-Path -Parent $SpecPath
# Derived from the output file's own directory, so a scratch run cannot overwrite the committed one.
$ProvenancePath = Join-Path $SpecDir 'PROVENANCE.json'

# Read a member the remote API owns, not this script. Returns $null when absent instead of raising
# the strict-mode property error, so the absence is a refusal that names the field, not a trace.
function Get-Observed {
    param($Object, [string]$Name)
    if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name) { $Object.$Name } else { $null }
}

Write-Host "Capture Whisparr 3 openapi -> $SpecPath" -ForegroundColor Cyan
Write-Host "  - image $Image" -ForegroundColor DarkGray

try {
    # -v removes the anonymous volume the image declares for /config, which every run would
    # otherwise leak. 127.0.0.1 explicitly: a bare -p binds 0.0.0.0 and docker punches its own
    # firewall rule, which would put this constant API key on every interface for the whole run.
    docker rm -f -v $ContainerName 2>&1 | Out-Null
    $RunOutput = docker run -d --name $ContainerName -p 127.0.0.1:6969:6969 -e "WHISPARR__AUTH__APIKEY=$ApiKey" $Image 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: docker run failed for $Image. If port 6969 is already bound, free it rather than repointing this script: it must never capture from an instance it did not start." -ForegroundColor Red
        Write-Host ($RunOutput -join [Environment]::NewLine) -ForegroundColor Red
        exit 1
    }
    Write-Host "  + started $ContainerName on host port 6969" -ForegroundColor Green

    # --- 1. Poll the spec endpoint. It needs no authentication ---
    $Clock      = [System.Diagnostics.Stopwatch]::StartNew()
    $Ready      = $false
    $LastStatus = 0
    while ($Clock.Elapsed.TotalSeconds -lt $TimeoutSec) {
        try {
            $LastStatus = (Invoke-WebRequest $SpecUrl -SkipHttpErrorCheck -TimeoutSec 5).StatusCode
            if ($LastStatus -eq 200) { $Ready = $true; break }
        } catch {
            # Connection refused while the container is still starting. Not an error yet.
            $LastStatus = 0
        }
        Start-Sleep -Seconds 1
    }
    $Clock.Stop()
    if (-not $Ready) {
        # Naming the observed status and the digest is the whole diagnosis. Whisparr 2 answers 404
        # here for the entire window, because only Eros serves this endpoint.
        Write-Host "ERROR: REFUSED - $SpecUrl returned HTTP $LastStatus, not 200, within ${TimeoutSec}s for $ImageDigest." -ForegroundColor Red
        Write-Host "  A 404 across the whole window means this is not Whisparr 3 (Eros). No spec was written to $SpecPath." -ForegroundColor Red
        docker logs $ContainerName --tail 40 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        exit 1
    }
    Write-Host ("  + spec endpoint ready after {0:n1}s" -f $Clock.Elapsed.TotalSeconds) -ForegroundColor Green

    # --- 2. Identity assertion. Reached only when a spec IS being served ---
    $StatusResponse = Invoke-WebRequest $StatusUrl -Headers @{ 'X-Api-Key' = $ApiKey } -SkipHttpErrorCheck -TimeoutSec 10
    if ($StatusResponse.StatusCode -ne 200) {
        Write-Host "ERROR: REFUSED - the instance serves a spec but answered $StatusUrl with HTTP $($StatusResponse.StatusCode). Whisparr 3 (Eros) returns 200 there. No spec was written." -ForegroundColor Red
        exit 1
    }
    # -DateKind String keeps buildTime as the string the API returned, so provenance records an
    # observed value rather than one converted to this machine's local time.
    $Status  = $StatusResponse.Content | ConvertFrom-Json -DateKind String
    $Branch  = Get-Observed $Status 'branch'
    $Version = Get-Observed $Status 'version'
    # An absent or unparseable version is a failed assertion, not a crash: casting [version] on a
    # missing member would throw before this refusal could be printed.
    $ParsedVersion = $null
    if ($null -ne $Version) { $null = [version]::TryParse([string]$Version, [ref]$ParsedVersion) }
    if ($Branch -ne 'eros' -or $null -eq $ParsedVersion -or $ParsedVersion.Major -ne 3) {
        Write-Host "ERROR: REFUSED - the instance reports branch '$Branch' version '$Version'. Required: branch 'eros' and major version 3. No spec was written." -ForegroundColor Red
        exit 1
    }
    Write-Host "  + identity ok - Whisparr $Version, branch $Branch" -ForegroundColor Green

    # --- 3. Capture, byte-verbatim ---
    # -OutFile reproduces the source bytes exactly. Out-File and Set-Content append a trailing CRLF,
    # two extra bytes, and change the sha256.
    New-Item -ItemType Directory -Force -Path $SpecDir | Out-Null
    Invoke-WebRequest $SpecUrl -OutFile $SpecPath
    $Sha   = (Get-FileHash -Algorithm SHA256 -LiteralPath $SpecPath).Hash.ToLower()
    $Bytes = (Get-Item -LiteralPath $SpecPath).Length
    Write-Host "  + captured $Bytes bytes, sha256 $Sha" -ForegroundColor Green

    # --- 4. Provenance, from observed values only ---
    # generatedSpecSha256 is deliberately absent: a new capture invalidates the patched spec, and
    # preprocess-spec.ps1 is what puts that field back.
    $Spec = Get-Content -Raw -LiteralPath $SpecPath | ConvertFrom-Json
    $Provenance = [pscustomobject][ordered]@{
        capturedAt             = (Get-Date).ToUniversalTime().ToString('o')
        capturedFrom           = $SpecUrl
        imageDigest            = $Image
        whisparrVersion        = $Version
        whisparrBranch         = $Branch
        whisparrBuildTime      = Get-Observed $Status 'buildTime'
        whisparrPackageVersion = Get-Observed $Status 'packageVersion'
        specEndpoint           = '/docs/v3/openapi.json'
        specSha256             = $Sha
        specBytes              = $Bytes
        specOpenApiVersion     = Get-Observed $Spec 'openapi'
    }
    # A null is not an observation. Without this a Whisparr that renames a status member writes
    # null into the committed manifest and the run still prints Done.
    $Unobserved = @($Provenance.PSObject.Properties | Where-Object { $null -eq $_.Value -or ($_.Value -is [string] -and $_.Value.Trim() -eq '') })
    if ($Unobserved.Count -gt 0) {
        Write-Host "ERROR: REFUSED - provenance would record no observed value for: $($Unobserved.Name -join ', '). $ProvenancePath is untouched." -ForegroundColor Red
        exit 1
    }
    # ConvertTo-Json emits the platform newline, CRLF here, and .gitattributes declares *.json as
    # eol=lf. Write LF explicitly so the working tree matches what a clone gets.
    $ProvenanceJson = (($Provenance | ConvertTo-Json) -replace "`r`n", "`n").TrimEnd("`n") + "`n"
    [System.IO.File]::WriteAllText($ProvenancePath, $ProvenanceJson, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  + wrote $ProvenancePath" -ForegroundColor Green

    Write-Host "Done. $SpecPath" -ForegroundColor Green
}
finally {
    # Force-remove by name so a failed run cannot leave a stale container holding host port 6969.
    docker rm -f -v $ContainerName 2>&1 | Out-Null
}
