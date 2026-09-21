param(
    [string]$Image = 'theypsilon/quartus-lite-c5:17.0',
    [string]$DockerContext = 'desktop-linux',
    [ValidateSet(20, 40, 50, 60)]
    [int]$SystemClockMHz = 20,
    [ValidateSet('Zet', 'ao486')]
    [string]$Cpu = 'Zet',
    [ValidateSet(0, 16, 64)]
    [int]$ExtendedRamMB = 0,
    [ValidateSet('OPNA', 'PC9801_86')]
    [string]$SoundBoard = 'OPNA',
    [switch]$LowMemoryCache,
    [ValidateSet(8, 32, 64)]
    [int]$LowMemoryCacheKB = 8,
    [switch]$RawIde,
    [switch]$PrepareOnly
)

$ErrorActionPreference = 'Stop'
if ($ExtendedRamMB -ne 0 -and $Cpu -ne 'ao486') { throw 'Extended RAM requires ao486.' }
if ($LowMemoryCache -and $Cpu -ne 'ao486') { throw 'Low-memory read cache requires ao486.' }
if ($LowMemoryCacheKB -ne 8 -and -not $LowMemoryCache) { throw 'Cache size requires -LowMemoryCache.' }
$projectRoot = Split-Path -Parent $PSScriptRoot
$buildName = 'quartus-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6)
$buildRoot = Join-Path $projectRoot ('build/' + $buildName)
$sourceRoot = Join-Path $buildRoot 'source'
New-Item -ItemType Directory -Path $sourceRoot -Force | Out-Null

# Include current edits and new source files, but never include Git metadata,
# user firmware/disks, or an earlier build's generated databases.
Push-Location $projectRoot
try {
    $sourceFiles = @(git -c core.quotepath=false ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate project source files.' }
    foreach ($sourceFile in $sourceFiles) {
        if ($sourceFile -match '(^|/)(db|incremental_db|output_files|build|test-assets|\.idea)/' -or
            $sourceFile -match '^releases/' -or $sourceFile -match '\.(log|qws)$') { continue }
        $inputFile = Join-Path $projectRoot $sourceFile
        if (-not (Test-Path -LiteralPath $inputFile -PathType Leaf)) { continue }
        $outputFile = Join-Path $sourceRoot $sourceFile
        New-Item -ItemType Directory -Path (Split-Path -Parent $outputFile) -Force | Out-Null
        Copy-Item -LiteralPath $inputFile -Destination $outputFile
    }
    git rev-parse HEAD | Set-Content -LiteralPath (Join-Path $buildRoot 'source-commit.txt')
    git diff --stat | Set-Content -LiteralPath (Join-Path $buildRoot 'source-changes.txt')
    $SystemClockMHz | Set-Content -LiteralPath (Join-Path $buildRoot 'system-clock-mhz.txt')
    $Cpu | Set-Content -LiteralPath (Join-Path $buildRoot 'cpu.txt')
    $ExtendedRamMB | Set-Content -LiteralPath (Join-Path $buildRoot 'extended-ram-mb.txt')
    $SoundBoard | Set-Content -LiteralPath (Join-Path $buildRoot 'sound-board.txt')
    [bool]$LowMemoryCache | Set-Content -LiteralPath (Join-Path $buildRoot 'low-memory-cache.txt')
    $LowMemoryCacheKB | Set-Content -LiteralPath (Join-Path $buildRoot 'low-memory-cache-kb.txt')
    [bool]$RawIde | Set-Content -LiteralPath (Join-Path $buildRoot 'raw-ide.txt')
    if ($RawIde) {
        Add-Content -LiteralPath (Join-Path $sourceRoot 'Zet98/v17/release-Zet98MiSTer.qsf') `
            -Value "`nset_global_assignment -name VERILOG_MACRO ZET98_RAW_IDE=1"
    }
    if ($LowMemoryCache) {
        Add-Content -LiteralPath (Join-Path $sourceRoot 'Zet98/v17/release-Zet98MiSTer.qsf') `
            -Value "`nset_global_assignment -name VERILOG_MACRO ZET98_LOWMEM_CACHE=1"
        Add-Content -LiteralPath (Join-Path $sourceRoot 'Zet98/v17/release-Zet98MiSTer.qsf') `
            -Value "`nset_global_assignment -name VERILOG_MACRO ZET98_LOWMEM_CACHE_KB=$LowMemoryCacheKB"
    }
    if ($SoundBoard -eq 'PC9801_86') {
        Add-Content -LiteralPath (Join-Path $sourceRoot 'Zet98/v17/release-Zet98MiSTer.qsf') `
            -Value "`nset_global_assignment -name VERILOG_MACRO ZET98_PCM86=1"
    }
    if ($ExtendedRamMB -ne 0) {
        Add-Content -LiteralPath (Join-Path $sourceRoot 'Zet98/v17/release-Zet98MiSTer.qsf') `
            -Value "`nset_global_assignment -name VERILOG_MACRO ZET98_EXT_RAM_MB=$ExtendedRamMB"
    }
    if ($Cpu -eq 'ao486') {
        $projectSettings = Join-Path $sourceRoot 'Zet98/v17/release-Zet98MiSTer.qsf'
        # The two CPU sources have incompatible headers both named defines.v.
        # Compile only the selected CPU, preserving the default Zet project.
        $assignments = Get-Content -LiteralPath $projectSettings | Where-Object { $_ -notmatch 'zet-1\.3\.1' }
        $assignments | Set-Content -LiteralPath $projectSettings
        Add-Content -LiteralPath $projectSettings -Value @(
            'set_global_assignment -name VERILOG_MACRO ZET98_AO486=1',
            'set_global_assignment -name QIP_FILE ../../rtl/cpu/ao486_pc98.qip'
        )
    }
    if ($SystemClockMHz -ne 20) {
        Add-Content -LiteralPath (Join-Path $sourceRoot 'Zet98/v17/release-Zet98MiSTer.qsf') `
            -Value "`nset_global_assignment -name VERILOG_MACRO ZET98_TURBO$SystemClockMHz=1"
    }
    if ($PrepareOnly) {
        Write-Host "Prepared $SystemClockMHz MHz source snapshot: $sourceRoot"
        return
    }
    & docker --context $DockerContext image inspect $Image --format '{{.Id}}' |
        Set-Content -LiteralPath (Join-Path $buildRoot 'toolchain-image.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Quartus Docker image is not installed.' }
    Write-Host "Build directory: $buildRoot"
    # Quartus performs many small random database reads. Build on Docker's
    # Linux filesystem: Windows bind shares can stall these accesses in 9P.
    # Keep the source snapshot and export the complete database for TimeQuest.
    $containerName = 'zet98-' + $buildName
    $containerId = & docker --context $DockerContext create --name $containerName `
        --network none --workdir /project/Zet98/v17 $Image bash -lc `
        'quartus_sh --flow compile Zet98 -c release-Zet98MiSTer'
    if ($LASTEXITCODE -ne 0) { throw 'Cannot create isolated Quartus container.' }
    $containerId | Set-Content -LiteralPath (Join-Path $buildRoot 'container-id.txt')
    & docker --context $DockerContext cp "$sourceRoot/." "${containerName}:/project/"
    if ($LASTEXITCODE -ne 0) { throw "Cannot copy source into $containerName; container retained." }
    & docker --context $DockerContext start -a $containerName 2>&1 |
        Tee-Object -FilePath (Join-Path $buildRoot 'quartus.log')
    $compileExit = & docker --context $DockerContext inspect $containerName --format '{{.State.ExitCode}}'
    if ($LASTEXITCODE -ne 0) { throw "Cannot inspect $containerName; container retained." }
    & python (Join-Path $PSScriptRoot 'docker-export.py') --context $DockerContext `
        $containerName /project/Zet98/v17 (Join-Path $sourceRoot 'Zet98/v17')
    if ($LASTEXITCODE -ne 0) { throw "Cannot export results from $containerName; container retained." }
    & docker --context $DockerContext rm $containerName | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Warning "Export succeeded; cleanup of $containerName failed." }
    if ($compileExit -ne '0') { throw "Quartus failed. See $buildRoot/quartus.log" }
    Write-Host "RBF and reports: $sourceRoot/Zet98/v17/output_files"
    $timing = & (Join-Path $PSScriptRoot 'read-timing.ps1') -SummaryPath `
        (Join-Path $sourceRoot 'Zet98/v17/output_files/release-Zet98MiSTer.sta.summary')
    $timing | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $buildRoot 'timing-results.json')
    & (Join-Path $PSScriptRoot 'check-pixel-clock.ps1') -FitterReport `
        (Join-Path $sourceRoot 'Zet98/v17/output_files/release-Zet98MiSTer.fit.rpt')
    if ($timing.ReportedTimingViolations -gt 0) {
        throw "RBF generated, but timing FAILED: $($timing.ReportedTimingViolations) checks with negative slack; worst $($timing.WorstSlackNs) ns. This is not a verified release. See $buildRoot/timing-results.json"
    }
    Write-Host 'No negative slack reported. Constraint coverage and hardware verification are still required.'
} finally {
    Pop-Location
}
