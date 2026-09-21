param(
    [Parameter(Mandatory=$true)][string]$BuildDirectory,
    [string]$Image = 'theypsilon/quartus-lite-c5:17.0',
    [string]$DockerContext = 'desktop-linux',
    [ValidateRange(1, 16)][int]$BuildCpus = 1
)
$ErrorActionPreference = 'Stop'
$buildRoot = (Resolve-Path -LiteralPath $BuildDirectory).Path
$sourceRoot = Join-Path $buildRoot 'source'
$projectPath = Join-Path $sourceRoot 'Zet98/v17'
if (-not (Test-Path -LiteralPath (Join-Path $projectPath 'db') -PathType Container)) {
    throw 'Expected a completed build snapshot with its Quartus database.'
}
$containerName = 'zet98-timequest-' + [guid]::NewGuid().ToString('N').Substring(0, 12)
$containerId = & docker --context $DockerContext create --name $containerName --network none --cpus $BuildCpus `
    --workdir /project/Zet98/v17 $Image bash -lc 'quartus_sta -t ../../scripts/report-timing.tcl'
if ($LASTEXITCODE -ne 0) { throw 'Cannot create TimeQuest container.' }
$containerId | Set-Content -LiteralPath (Join-Path $buildRoot 'timequest-container-id.txt')
& docker --context $DockerContext cp "$sourceRoot/." "${containerName}:/project/"
if ($LASTEXITCODE -ne 0) { throw "Cannot copy snapshot; $containerName retained." }
& docker --context $DockerContext start -a $containerName 2>&1 |
    Tee-Object -FilePath (Join-Path $buildRoot 'postfit.log')
$reportExit = & docker --context $DockerContext inspect $containerName --format '{{.State.ExitCode}}'
if ($LASTEXITCODE -ne 0) { throw "Cannot inspect result; $containerName retained." }
& python (Join-Path $PSScriptRoot 'docker-export.py') --context $DockerContext `
    $containerName /project/Zet98/v17/output_files (Join-Path $projectPath 'output_files')
if ($LASTEXITCODE -ne 0) { throw "Cannot export reports; $containerName retained." }
& docker --context $DockerContext rm $containerName | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Warning "Reports exported, but cleanup of $containerName failed." }
if ($reportExit -ne '0') { throw "TimeQuest failed. See $buildRoot/postfit.log" }
Write-Host "Timing reports: $projectPath/output_files"
