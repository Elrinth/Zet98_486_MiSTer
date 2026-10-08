#requires -Version 7.0
param(
    [string]$DockerContext = 'desktop-linux',
    [string]$QuartusImage = 'theypsilon/quartus-lite-c5:17.0.2',
    [string]$SimulationImage = 'zet98-mixed-sim:latest',
    [ValidateRange(1, 3)][int]$TestCpus = 1,
    [ValidateRange(1, 8)][int]$MemoryGB = 2,
    [string[]]$TestScript,
    [switch]$AdaptersOnly,
    [switch]$PrepareOnly,
    [switch]$StartOnly
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'docker-command.ps1')
$projectRoot = Split-Path -Parent $PSScriptRoot
if ($TestScript) {
    foreach ($script in $TestScript) {
        if ($script -notmatch '^tests/run(?:-[a-z0-9]+)*\.sh$' -or
            -not (Test-Path -LiteralPath (Join-Path $projectRoot $script) -PathType Leaf)) {
            throw "Expected an existing tests/run*.sh script: $script"
        }
    }
    $commands = @($TestScript | ForEach-Object { "bash $_" })
} else {
    $commands = @('bash tests/run.sh')
    if (-not $AdaptersOnly) {
        $commands += @('bash tests/run-cpu.sh',
                      'LOWMEM_CACHE=1 CPU_REP_COUNTS=1 bash tests/run-cpu.sh',
                      'bash tests/run-extmem.sh', 'bash tests/run-cache.sh',
                      'bash tests/run-upper-cache.sh')
    }
}
# Reuse an installed toolchain instead of rebuilding it on every invocation.
if (-not $PrepareOnly) {
    $activeJobs = Invoke-DockerCommand -Arguments @('--context',$DockerContext,'ps','--format','{{.Names}}')
    if (@($activeJobs -split '\r?\n' | Where-Object { $_ -match '^zet98-(quartus|simulation|timequest)-' }).Count) {
        throw 'An FPGA/test/timing job is already running; let it finish before starting simulation.'
    }
    $simulationId = Invoke-DockerCommand -Arguments @('--context',$DockerContext,'image','inspect',$SimulationImage,'--format','{{.Id}}')
}
$runName = 'simulation-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,6)
$runRoot = Join-Path $projectRoot ('build/' + $runName)
$sourceRoot = Join-Path $runRoot 'source'
New-Item -ItemType Directory -Path $sourceRoot -Force | Out-Null
Push-Location $projectRoot
try {
    # Match the FPGA snapshot exclusions: no firmware, games or old builds.
    $sourceFiles = @(git -c core.quotepath=false ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate simulation sources.' }
    foreach ($file in $sourceFiles) {
        if ($file -match '(^|/)(db|incremental_db|output_files|build|test-assets|\.idea|flat-regression-evidence|segment-regression-evidence|xms-sim-output)/' -or
            $file -match '^releases/' -or $file -match '\.(log|qws)$') { continue }
        $inputFile = Join-Path $projectRoot $file
        if (-not (Test-Path -LiteralPath $inputFile -PathType Leaf)) { continue }
        $outputFile = Join-Path $sourceRoot $file
        New-Item -ItemType Directory -Path (Split-Path -Parent $outputFile) -Force | Out-Null
        Copy-Item -LiteralPath $inputFile -Destination $outputFile
    }
    git rev-parse HEAD | Set-Content -LiteralPath (Join-Path $runRoot 'source-commit.txt')
    git diff --stat | Set-Content -LiteralPath (Join-Path $runRoot 'source-changes.txt')
    $commands | Set-Content -LiteralPath (Join-Path $runRoot 'test-commands.txt')
    if ($PrepareOnly) { Write-Host "Prepared simulation snapshot: $sourceRoot"; return }
    $simulationId | Set-Content -LiteralPath (Join-Path $runRoot 'toolchain-image.txt')
    @{cpus=$TestCpus; memoryGiB=$MemoryGB; swapExtraGiB=0; windowsBinds=$false} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runRoot 'resource-limits.json')
    if (-not $AdaptersOnly) {
        # A never-started container exposes the selected Quartus image's models.
        # Keep a per-run copy and hashes instead of trusting a previous cache.
        $modelImage = Invoke-DockerCommand -Arguments @('--context',$DockerContext,'image','inspect',$QuartusImage,'--format','{{.Id}}')
        $modelImage | Set-Content -LiteralPath (Join-Path $runRoot 'model-image.txt')
        $modelPath = Join-Path $runRoot 'intel-sim'
        New-Item -ItemType Directory -Path $modelPath | Out-Null
        $modelContainer = 'zet98-models-' + [guid]::NewGuid().ToString('N').Substring(0,12)
        Invoke-DockerCommand -Arguments @('--context',$DockerContext,'create','--name',$modelContainer,
            '--network','none','--cpus','1','--memory','1g','--memory-swap','1g',
            '--entrypoint','true',$modelImage) | Out-Null
        $modelContainer | Set-Content -LiteralPath (Join-Path $runRoot 'model-container-name.txt')
        foreach ($model in @('altera_mf.v','220model.v','cyclonev_atoms.v')) {
            Invoke-DockerCommand -Arguments @('--context',$DockerContext,'cp',
                "${modelContainer}:/opt/intelFPGA_lite/quartus/eda/sim_lib/$model",(Join-Path $modelPath $model)) -TimeoutSeconds 30 | Out-Null
        }
        Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $modelPath 'altera_mf.v'),(Join-Path $modelPath '220model.v'),(Join-Path $modelPath 'cyclonev_atoms.v') |
            Select-Object Hash,Path | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runRoot 'model-hashes.json')
        Invoke-DockerCommand -Arguments @('--context',$DockerContext,'rm',$modelContainer) | Out-Null
    }
    $container = 'zet98-' + $runName
    $id = Invoke-DockerCommand -Arguments @('--context',$DockerContext,'create','--name',$container,
        '--network','none','--init','--cpus',"$TestCpus",'--memory',"${MemoryGB}g",'--memory-swap',"${MemoryGB}g",
        '--env','INTEL_SIM_LIB=/project/intel-sim','--workdir','/project',$simulationId,'bash','-lc',($commands -join ' && '))
    $container | Set-Content -LiteralPath (Join-Path $runRoot 'container-name.txt')
    $id | Set-Content -LiteralPath (Join-Path $runRoot 'container-id.txt')
    Invoke-DockerCommand -Arguments @('--context',$DockerContext,'cp',"$sourceRoot/.","${container}:/project/") -TimeoutSeconds 60 | Out-Null
    if (-not $AdaptersOnly) {
        Invoke-DockerCommand -Arguments @('--context',$DockerContext,'cp',"$modelPath/.","${container}:/project/intel-sim/") -TimeoutSeconds 30 | Out-Null
    }
    Invoke-DockerCommand -Arguments @('--context',$DockerContext,'start',$container) | Out-Null
    Write-Host "Started detached simulation: $container"
    Write-Host "Evidence directory: $runRoot"
    if ($StartOnly) { return }
    do {
        $state = Invoke-DockerCommand -Arguments @('--context',$DockerContext,'inspect',$container,'--format','{{json .State}}') | ConvertFrom-Json
        if ($state.Paused) { throw "Simulation $container is paused; inspect before resuming." }
        if ($state.Running) { Start-Sleep -Seconds 10 }
    } while ($state.Running)
    if ($state.Status -notin @('exited','dead')) { throw "Unexpected container state: $($state.Status)" }
    Invoke-DockerCommand -Arguments @('--context',$DockerContext,'logs',$container) -TimeoutSeconds 30 |
        Set-Content -LiteralPath (Join-Path $runRoot 'tests.log')
    $state | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runRoot 'result.json')
    Invoke-DockerCommand -Arguments @('--context',$DockerContext,'rm',$container) | Out-Null
    if ($state.ExitCode -ne 0 -or $state.OOMKilled) { throw "Simulation failed. See $runRoot/tests.log" }
    Write-Host "Simulation passed. See $runRoot/tests.log"
} finally { Pop-Location }
