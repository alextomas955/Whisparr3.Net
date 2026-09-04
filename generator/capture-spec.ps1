<#
.SYNOPSIS
  Capture the Whisparr 3 (Eros) OpenAPI document from a digest-pinned container.

.DESCRIPTION
  Boots ghcr.io/hotio/whisparr at a pinned digest, waits for the spec endpoint, writes the
  document byte-verbatim, records an observed-value provenance manifest beside it, and runs
  the census assertion.
    1. Readiness poll on /docs/v3/openapi.json until it returns HTTP 200.
    2. Diagnosis on timeout. An image that answers on / but returns 404 for the spec endpoint
       is almost certainly Whisparr 2, and the message says so instead of reporting a bare
       readiness timeout.
    3. Identity assertion against /api/v3/system/status - branch eros, major version 3.
    4. Capture with Invoke-WebRequest -OutFile, which is byte-verbatim. Out-File and
       Set-Content append a trailing CRLF and change the sha256.
    5. Provenance manifest, written into the output file's own directory.
    6. Census gate, whose exit code is propagated.

  The image is referenced only by digest. The moving tags point at Whisparr 2, a different
  application that also serves /api/v3, so an unpinned pull yields a client that compiles and
  looks entirely plausible and is wrong.

  The container is named whisparr3-capture and is force-removed in a finally block, so a
  failed run cannot leave a stale container holding port 6969. Host port 6969 is deliberate:
  docker fails loudly if it is already bound, and this script must never capture from an
  instance it did not start.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\capture-spec.ps1
  # Captures to spec/openapi.raw.json inside the repository.

.EXAMPLE
  pwsh -File I:\cove-dev\Whisparr3.Net\generator\capture-spec.ps1 -ImageDigest sha256:35092d45d41f52bd798dd207566d459252b6a7625a607f7bbb59aecb2e4f9ed6 -OutFile scratch.json
  # The Whisparr 2 refusal run. Expected to consume the full timeout and exit non-zero
  # without writing a spec.
#>

[CmdletBinding()]
param(
    # Image digest to boot. Defaults to the pinned Whisparr 3.4.0.1387 (eros) digest.
    # Overriding it with the Whisparr 2 digest is the refusal test, not a normal run.
    [string]$ImageDigest = 'sha256:fab920114a75f1c86bbadf24c66f1e35a912ace9c7527e971f1032a569589ee6',

    # Where to write the captured spec. A relative path resolves against the repository root,
    # not the current directory, so the default lands in the repo wherever this is run from.
    [string]$OutFile = 'spec/openapi.raw.json',

    # Seconds to wait for the spec endpoint. The pinned digest is ready in 13-19s. Whisparr 2
    # never becomes ready and consumes the whole budget - that wait is the design, not a hang.
    [int]$TimeoutSec = 90
)

$ErrorActionPreference = 'Stop'

# --- Constants (edit here if the layout changes) ---
$RepoRoot      = Split-Path -Parent $PSScriptRoot
$Image         = "ghcr.io/hotio/whisparr@$ImageDigest"
$ContainerName = 'whisparr3-capture'
# Not a credential: a fixed constant handed to a container that is destroyed at the end of the
# run. Never substitute a real key. It is needed only for the status read that feeds
# provenance - the spec endpoint itself is served unauthenticated.
$ApiKey        = '0123456789abcdef0123456789abcdef'
$BaseUrl       = 'http://localhost:6969'
$SpecUrl       = "$BaseUrl/docs/v3/openapi.json"
$StatusUrl     = "$BaseUrl/api/v3/system/status"

# The provenance manifest is derived from the output file's own directory rather than
# hardcoded, so a run with a scratch output path cannot overwrite the committed manifest.
$SpecPath       = if ([System.IO.Path]::IsPathRooted($OutFile)) { $OutFile } else { Join-Path $RepoRoot $OutFile }
$SpecDir        = Split-Path -Parent $SpecPath
$ProvenancePath = Join-Path $SpecDir 'PROVENANCE.json'

Write-Host "Capture Whisparr 3 openapi -> $SpecPath" -ForegroundColor Cyan
Write-Host "  - image $Image" -ForegroundColor DarkGray

try {
    # --- Boot the digest-pinned container ---
    docker rm -f $ContainerName 2>&1 | Out-Null
    $RunOutput = docker run -d --name $ContainerName -p 6969:6969 -e "WHISPARR__AUTH__APIKEY=$ApiKey" $Image 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: docker run failed for $Image. If port 6969 is already bound, free it rather than repointing this script - it must never capture from an instance it did not start." -ForegroundColor Red
        Write-Host ($RunOutput -join [Environment]::NewLine) -ForegroundColor Red
        exit 1
    }
    Write-Host "  + started $ContainerName, host port 6969" -ForegroundColor Green

    # --- 1. Readiness poll on the spec endpoint, at one-second intervals ---
    # Poll rather than sleep a fixed interval. The spec endpoint needs no authentication:
    # Whisparr Eros mounts Swagger before authentication deliberately.
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
        if ([int]$Clock.Elapsed.TotalSeconds % 10 -eq 0) {
            Write-Host ("  - waiting for {0} ({1:n0}s, last HTTP {2})" -f $SpecUrl, $Clock.Elapsed.TotalSeconds, $LastStatus) -ForegroundColor DarkGray
        }
        Start-Sleep -Seconds 1
    }
    $Clock.Stop()

    # --- 2. Diagnosis on timeout. This is where the Whisparr 2 refusal actually fires ---
    # Whisparr 2 returns 404 for the spec endpoint for the whole poll window and 401 for the
    # status endpoint even with the API key environment variable set, so step 3 is never
    # reached. Without this diagnosis the refusal arrives as a bare readiness timeout that
    # never mentions Whisparr 2 - which exits non-zero while proving nothing.
    if (-not $Ready) {
        $RootStatus = 0
        $SpecStatus = 0
        try { $RootStatus = (Invoke-WebRequest "$BaseUrl/" -SkipHttpErrorCheck -TimeoutSec 5 -MaximumRedirection 0).StatusCode } catch { $RootStatus = 0 }
        try { $SpecStatus = (Invoke-WebRequest $SpecUrl -SkipHttpErrorCheck -TimeoutSec 5).StatusCode } catch { $SpecStatus = 0 }

        if ($RootStatus -gt 0 -and $RootStatus -lt 400 -and $SpecStatus -eq 404) {
            Write-Host "ERROR: REFUSED after ${TimeoutSec}s - this image is not Whisparr 3 (Eros)." -ForegroundColor Red
            Write-Host "  The image at $ImageDigest answers on port 6969 (GET / returned $RootStatus)" -ForegroundColor Red
            Write-Host "  but returns HTTP 404 for /docs/v3/openapi.json." -ForegroundColor Red
            Write-Host "  Whisparr 3 (Eros) always serves that endpoint unauthenticated, so this is almost" -ForegroundColor Red
            Write-Host "  certainly Whisparr 2 - a different application that also serves /api/v3 and would" -ForegroundColor Red
            Write-Host "  therefore yield a client that compiles and looks entirely plausible and is wrong." -ForegroundColor Red
            Write-Host "  Whisparr 2 also answers /api/v3/system/status with HTTP 401 even with the API key" -ForegroundColor Red
            Write-Host "  environment variable set, so the identity assertion is never reached." -ForegroundColor Red
            Write-Host "  The moving tags both point at the Whisparr 2 digest" -ForegroundColor Red
            Write-Host "  sha256:35092d45d41f52bd798dd207566d459252b6a7625a607f7bbb59aecb2e4f9ed6." -ForegroundColor Red
            Write-Host "  No spec was written to $SpecPath." -ForegroundColor Red
        } else {
            Write-Host "ERROR: REFUSED - $SpecUrl did not return HTTP 200 within ${TimeoutSec}s (GET / returned $RootStatus, spec endpoint returned $SpecStatus). No spec was written to $SpecPath." -ForegroundColor Red
        }

        Write-Host '  - last 40 container log lines:' -ForegroundColor DarkGray
        docker logs $ContainerName --tail 40 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        exit 1
    }
    Write-Host ("  + spec endpoint ready after {0:n1}s" -f $Clock.Elapsed.TotalSeconds) -ForegroundColor Green

    # --- 3. Identity assertion, the second net. Reached only when a spec IS being served ---
    # Its message must not claim a branch mismatch when the truth is that no spec was
    # retrieved at all - that case is step 2's.
    $StatusResponse = Invoke-WebRequest $StatusUrl -Headers @{ 'X-Api-Key' = $ApiKey } -SkipHttpErrorCheck -TimeoutSec 10
    if ($StatusResponse.StatusCode -ne 200) {
        Write-Host "ERROR: REFUSED - the instance serves a spec but answered $StatusUrl with HTTP $($StatusResponse.StatusCode) with the API key header set. Whisparr 3 (Eros) returns 200 there. No spec was written to $SpecPath." -ForegroundColor Red
        exit 1
    }
    # -DateKind String keeps buildTime as the string the API returned. Without it the parser
    # converts it to a local DateTime and provenance would record a converted value rather
    # than an observed one.
    $Status = $StatusResponse.Content | ConvertFrom-Json -DateKind String
    if ($Status.branch -ne 'eros' -or ([version]$Status.version).Major -ne 3) {
        Write-Host "ERROR: REFUSED - the instance serves a spec but reports branch '$($Status.branch)' version '$($Status.version)'. Required: branch 'eros' and major version 3. No spec was written to $SpecPath." -ForegroundColor Red
        exit 1
    }
    Write-Host "  + identity ok - Whisparr $($Status.version), branch $($Status.branch)" -ForegroundColor Green

    # --- 4. Capture, byte-verbatim ---
    # -OutFile reproduces the source bytes exactly. Out-File and Set-Content append a trailing
    # CRLF, two extra bytes, and change the sha256. -OutFile also sidesteps the response
    # content being a string for a 200 and a byte array for an error.
    New-Item -ItemType Directory -Force -Path $SpecDir | Out-Null
    Invoke-WebRequest $SpecUrl -OutFile $SpecPath
    $Sha   = (Get-FileHash -Algorithm SHA256 -Path $SpecPath).Hash.ToLower()
    $Bytes = (Get-Item -LiteralPath $SpecPath).Length
    Write-Host "  + captured $Bytes bytes, sha256 $Sha" -ForegroundColor Green

    # --- 5. Provenance, from observed values only ---
    # No generator keys here. The generator is not pinned until Phase 20, and writing them now
    # would be transcription rather than measurement.
    $Spec = Get-Content -Raw -LiteralPath $SpecPath | ConvertFrom-Json
    [pscustomobject][ordered]@{
        capturedAt             = (Get-Date).ToUniversalTime().ToString('o')
        capturedFrom           = $SpecUrl
        imageDigest            = $Image
        whisparrVersion        = $Status.version
        whisparrBranch         = $Status.branch
        whisparrBuildTime      = $Status.buildTime
        whisparrPackageVersion = $Status.packageVersion
        specEndpoint           = '/docs/v3/openapi.json'
        specSha256             = $Sha
        specBytes              = $Bytes
        specOpenApiVersion     = $Spec.openapi
    } | ConvertTo-Json | Set-Content -LiteralPath $ProvenancePath -Encoding utf8NoBOM
    Write-Host "  + wrote $ProvenancePath" -ForegroundColor Green

    # --- 6. Census gate ---
    # $LASTEXITCODE is the only reliable way to read a child script's exit code: the stop
    # error preference does not intercept it.
    & (Join-Path $PSScriptRoot 'assert-spec-census.ps1') -Path $SpecPath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: census gate failed for $SpecPath (exit $LASTEXITCODE). The spec was captured but does not match the pinned census." -ForegroundColor Red
        exit $LASTEXITCODE
    }

    Write-Host "Done. $SpecPath" -ForegroundColor Green
}
finally {
    # Force-remove by name so a failed run cannot leave a stale container that poisons the
    # next one or keeps host port 6969 bound.
    docker rm -f $ContainerName 2>&1 | Out-Null
}
