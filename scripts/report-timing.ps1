#requires -Version 7.0
param(
    [Parameter(Mandatory=$true)][string]$BuildDirectory,
    [string]$Image = 'theypsilon/quartus-lite-c5:17.0',
    [string]$DockerContext = 'desktop-linux',
    [ValidateRange(1, 3)][int]$BuildCpus = 1,
    [ValidateRange(2, 8)][int]$MemoryGB = 4,
    [switch]$Z486ChecksumPaths,
    [switch]$StartOnly
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'docker-command.ps1')
$buildRoot = (Resolve-Path -LiteralPath $BuildDirectory).Path
$sourceRoot = Join-Path $buildRoot 'source'
$projectPath = Join-Path $sourceRoot 'Zet98/v17'
if (-not (Test-Path -LiteralPath (Join-Path $projectPath 'db') -PathType Container)) {
    throw 'Expected a completed build snapshot with its Quartus database.'
}
$activeJobs = Invoke-DockerCommand -Arguments @('--context',$DockerContext,'ps','--format','{{.Names}}')
if (@($activeJobs -split '\r?\n' | Where-Object { $_ -match '^zet98-(quartus|simulation|timequest)-' }).Count) {
    throw 'An FPGA/test/timing job is already running; let it finish before starting TimeQuest.'
}
$analysisCommand = 'quartus_sta -t ../../scripts/report-timing.tcl'
if ($Z486ChecksumPaths) {
    # Copy this read-only report into the evidence snapshot so it can also be
    # used on older builds. Record exactly which report script was run.
    $reportScript = Join-Path $PSScriptRoot 'report-z486-checksum-timing.tcl'
    $savedScript = Join-Path $sourceRoot 'scripts/report-z486-checksum-timing.tcl'
    Copy-Item -LiteralPath $reportScript -Destination $savedScript
    Get-FileHash -LiteralPath $savedScript -Algorithm SHA256 |
        Select-Object Hash,Path | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $buildRoot 'checksum-report-script.json')
    $analysisCommand += ' && quartus_sta -t ../../scripts/report-z486-checksum-timing.tcl'
}
$containerName = 'zet98-timequest-' + [guid]::NewGuid().ToString('N').Substring(0, 12)
$containerId = Invoke-DockerCommand -Arguments @('--context',$DockerContext,'create','--name',$containerName,
    '--network','none','--cpus',"$BuildCpus",'--memory',"${MemoryGB}g",'--memory-swap',"${MemoryGB}g",
    '--workdir','/project/Zet98/v17',$Image,'bash','-lc',$analysisCommand)
$containerId | Set-Content -LiteralPath (Join-Path $buildRoot 'timequest-container-id.txt')
$containerName | Set-Content -LiteralPath (Join-Path $buildRoot 'timequest-container-name.txt')
Invoke-DockerCommand -Arguments @('--context',$DockerContext,'cp',"$sourceRoot/.","${containerName}:/project/") -TimeoutSeconds 60 | Out-Null
Invoke-DockerCommand -Arguments @('--context',$DockerContext,'start',$containerName) | Out-Null
Write-Host "Started detached TimeQuest container: $containerName"
if ($StartOnly) { return }
do {
    $state = Invoke-DockerCommand -Arguments @('--context',$DockerContext,'inspect',$containerName,'--format','{{json .State}}') | ConvertFrom-Json
    if ($state.Paused) { throw "TimeQuest $containerName is paused; inspect before resuming." }
    if ($state.Running) { Start-Sleep -Seconds 10 }
} while ($state.Running)
if ($state.Status -notin @('exited','dead')) { throw "Unexpected container state: $($state.Status)" }
Invoke-DockerCommand -Arguments @('--context',$DockerContext,'logs',$containerName) -TimeoutSeconds 30 |
    Set-Content -LiteralPath (Join-Path $buildRoot 'postfit.log')
Export-DockerDirectory -DockerContext $DockerContext -Container $containerName -Source /project/Zet98/v17/output_files -Destination (Join-Path $projectPath 'output_files')
Invoke-DockerCommand -Arguments @('--context',$DockerContext,'rm',$containerName) | Out-Null
if ($state.ExitCode -ne 0 -or $state.OOMKilled) { throw "TimeQuest failed. See $buildRoot/postfit.log" }
Write-Host "Timing reports: $projectPath/output_files"
