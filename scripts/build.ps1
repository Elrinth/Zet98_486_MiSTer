#requires -Version 7.0
param(
    [string]$Image = 'theypsilon/quartus-lite-c5:17.0',
    [string]$DockerContext = 'desktop-linux',
    [ValidateRange(1, 16)]
    [int]$BuildCpus = 8,
    [ValidateRange(4, 64)]
    [int]$BuildMemoryGB = 8,
    [ValidateRange(1, 3)]
    [int]$MaxConcurrentBuilds = 1,
    [ValidateSet(20, 40, 50, 60, 75, 90, 100)]
    [int]$SystemClockMHz = 20,
    [ValidateSet('Zet', 'ao486', 'z486')]
    [string]$Cpu = 'Zet',
    [ValidateSet(0, 16, 64)]
    [int]$ExtendedRamMB = 0,
    [ValidateSet('OPNA', 'PC9801_86')]
    [string]$SoundBoard = 'OPNA',
    [ValidateSet('Legacy','JT08')]
    [string]$OpnaBackend = 'Legacy',
    [ValidateSet('SparseAuto', 'Normal')]
    [string]$RegisterPacking = 'SparseAuto',
    [switch]$LowMemoryCache,
    [switch]$UpperRamICache,
    [ValidateSet(8, 32, 64)]
    [int]$LowMemoryCacheKB = 8,
    [switch]$RawIde,
    [switch]$MidiUart,
    [switch]$PackedGraphics,
    [switch]$Z486DebugUart,
    # With -Z486DebugUart: the crash recorder freezes on the first real-mode
    # divide error (INT 0) and logs real-mode interrupts.
    [switch]$RecorderDivide,
    # With -RecorderDivide: also freeze on the first far transfer into this
    # real-mode CS (hex, e.g. 0DE3) to catch a wild jump.
    [string]$RecorderFreezeCs,
    # With -RecorderFreezeCs: freeze when execution reaches that CS at this IP (hex).
    [string]$RecorderFreezeIp,
    # CD trace debug build: CD-ROM events on the UART (replaces MIDI).
    [switch]$CdTrace,
    [ValidateRange(1, 99)]
    [int]$Seed = 6,
    [switch]$StartOnly,
    [switch]$PrepareOnly,
    # Analysis & Synthesis only: a quick ALM estimate (map report), no RBF.
    [switch]$MapOnly,
    # Minutes without Quartus output before the watchdog stops it. Debug builds
    # route more slowly (the router can stay silent for over 25 minutes).
    [ValidateRange(10, 120)]
    [int]$StallMinutes = 25
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'docker-command.ps1')
if ($Z486DebugUart -and ($Cpu -ne 'z486' -or $MidiUart)) { throw 'Z486 debug UART requires z486 and exclusive use of UART (omit MidiUart).' }
if ($ExtendedRamMB -ne 0 -and $Cpu -eq 'Zet') { throw 'Extended RAM requires ao486 or z486.' }
if ($RawIde -and $Cpu -eq 'Zet') { throw 'The native hard-disk boot ROM requires ao486 or z486 (386 instructions).' }
if ($PackedGraphics -and $Cpu -eq 'Zet') { throw 'Packed graphics requires the ao486 or z486 physical-address/DDR router.' }
if ($RegisterPacking -ne 'SparseAuto' -and $Cpu -ne 'z486') { throw 'Register packing selection requires z486.' }
if ($LowMemoryCache -and $Cpu -ne 'ao486') { throw 'Low-memory read cache requires ao486.' }
if ($UpperRamICache -and $Cpu -eq 'Zet') { throw 'Upper conventional RAM instruction cache requires ao486 or z486.' }
if ($LowMemoryCacheKB -ne 8 -and -not $LowMemoryCache) { throw 'Cache size requires -LowMemoryCache.' }
# Avoid saturating an interactive workstation. This inventory does not use
# Docker stats, whose dashboard polling previously accumulated hung clients.
if (-not $PrepareOnly) {
    $inventory = Invoke-DockerCommand -Arguments @('--context',$DockerContext,'ps','--format','{{.Names}}')
    $activeJobs = @($inventory -split '\r?\n' | Where-Object { $_ })
    if (@($activeJobs | Where-Object { $_ -match '^zet98-(simulation|timequest)-' }).Count) {
        throw 'A test/timing job is already running; let it finish before starting Quartus.'
    }
    $activeBuilds = @($activeJobs | Where-Object { $_ -match '^zet98-quartus-' })
    if ($activeBuilds.Count -ge $MaxConcurrentBuilds) {
        throw "Already running $($activeBuilds.Count) Quartus build(s); limit is $MaxConcurrentBuilds. Let those finish before starting another."
    }
}
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
    $OpnaBackend | Set-Content -LiteralPath (Join-Path $buildRoot 'opna-backend.txt')
    [bool]$LowMemoryCache | Set-Content -LiteralPath (Join-Path $buildRoot 'low-memory-cache.txt')
    [bool]$UpperRamICache | Set-Content -LiteralPath (Join-Path $buildRoot 'upper-ram-icache.txt')
    $LowMemoryCacheKB | Set-Content -LiteralPath (Join-Path $buildRoot 'low-memory-cache-kb.txt')
    [bool]$RawIde | Set-Content -LiteralPath (Join-Path $buildRoot 'raw-ide.txt')
    [bool]$Z486DebugUart | Set-Content -LiteralPath (Join-Path $buildRoot 'z486-debug-uart.txt')
    [bool]$CdTrace | Set-Content -LiteralPath (Join-Path $buildRoot 'cd-trace.txt')
    [bool]$MidiUart | Set-Content -LiteralPath (Join-Path $buildRoot 'midi-uart.txt')
    [bool]$PackedGraphics | Set-Content -LiteralPath (Join-Path $buildRoot 'packed-graphics.txt')
    $RegisterPacking | Set-Content -LiteralPath (Join-Path $buildRoot 'register-packing.txt')
    'FullOnly' | Set-Content -LiteralPath (Join-Path $buildRoot 'cpu-execution-rate.txt')
    $Seed | Set-Content -LiteralPath (Join-Path $buildRoot 'fitter-seed.txt')
    $BuildCpus | Set-Content -LiteralPath (Join-Path $buildRoot 'build-cpus.txt')
    $BuildMemoryGB | Set-Content -LiteralPath (Join-Path $buildRoot 'build-memory-gb.txt')
    Add-Content -LiteralPath (Join-Path $sourceRoot 'Zet98/v17/release-Zet98MiSTer.qsf') `
        -Value "`nset_global_assignment -name NUM_PARALLEL_PROCESSORS $BuildCpus"
    if ($RecorderDivide -and -not $Z486DebugUart) { throw 'RecorderDivide needs -Z486DebugUart.' }
    if ($Z486DebugUart) {
        Add-Content -LiteralPath (Join-Path $sourceRoot 'Zet98/v17/release-Zet98MiSTer.qsf') -Value 'set_global_assignment -name VERILOG_MACRO ZET98_Z486_DEBUG=1'
        if ($RecorderDivide) {
            Add-Content -LiteralPath (Join-Path $sourceRoot 'Zet98/v17/release-Zet98MiSTer.qsf') -Value "`nset_global_assignment -name VERILOG_MACRO ZET98_RECORDER_DE=1"
            if ($RecorderFreezeCs) {
                if ($RecorderFreezeCs -notmatch '^[0-9A-Fa-f]{1,4}$') { throw 'RecorderFreezeCs must be 1-4 hex digits.' }
                Add-Content -LiteralPath (Join-Path $sourceRoot 'Zet98/v17/release-Zet98MiSTer.qsf') -Value "`nset_global_assignment -name VERILOG_MACRO ZET98_RECORDER_FREEZE_CS=$([Convert]::ToInt32($RecorderFreezeCs, 16))"
                if ($RecorderFreezeIp) {
                    if ($RecorderFreezeIp -notmatch '^[0-9A-Fa-f]{1,4}$') { throw 'RecorderFreezeIp must be 1-4 hex digits.' }
                    Add-Content -LiteralPath (Join-Path $sourceRoot 'Zet98/v17/release-Zet98MiSTer.qsf') -Value "`nset_global_assignment -name VERILOG_MACRO ZET98_RECORDER_FREEZE_IP=$([Convert]::ToInt32($RecorderFreezeIp, 16))"
                }
            }
        }
    }
    if ($CdTrace) {
        if ($MidiUart -or $Z486DebugUart) { throw 'CdTrace uses the UART: build it without MidiUart/Z486DebugUart.' }
        Add-Content -LiteralPath (Join-Path $sourceRoot 'Zet98/v17/release-Zet98MiSTer.qsf') `
            -Value "`nset_global_assignment -name VERILOG_MACRO ZET98_CD_TRACE=1"
    }
    if ($MidiUart) {
        Add-Content -LiteralPath (Join-Path $sourceRoot 'Zet98/v17/release-Zet98MiSTer.qsf') `
            -Value "`nset_global_assignment -name VERILOG_MACRO ZET98_MPU_UART=1"
    }
    if ($RawIde) {
        Add-Content -LiteralPath (Join-Path $sourceRoot 'Zet98/v17/release-Zet98MiSTer.qsf') `
            -Value "`nset_global_assignment -name VERILOG_MACRO ZET98_RAW_IDE=1"
    }
    if ($UpperRamICache) {
        Add-Content -LiteralPath (Join-Path $sourceRoot 'Zet98/v17/release-Zet98MiSTer.qsf') `
            -Value "`nset_global_assignment -name VERILOG_MACRO ZET98_UPPER_RAM_ICACHE=1"
    }
    if ($LowMemoryCache) {
        Add-Content -LiteralPath (Join-Path $sourceRoot 'Zet98/v17/release-Zet98MiSTer.qsf') `
            -Value "`nset_global_assignment -name VERILOG_MACRO ZET98_LOWMEM_CACHE=1"
        Add-Content -LiteralPath (Join-Path $sourceRoot 'Zet98/v17/release-Zet98MiSTer.qsf') `
            -Value "`nset_global_assignment -name VERILOG_MACRO ZET98_LOWMEM_CACHE_KB=$LowMemoryCacheKB"
    }
    if ($OpnaBackend -eq 'JT08') {
        Add-Content -LiteralPath (Join-Path $sourceRoot 'Zet98/v17/release-Zet98MiSTer.qsf') `
            -Value "`nset_global_assignment -name VERILOG_MACRO ZET98_JT08=1"
    }
    if ($SoundBoard -eq 'PC9801_86') {
        Add-Content -LiteralPath (Join-Path $sourceRoot 'Zet98/v17/release-Zet98MiSTer.qsf') `
            -Value "`nset_global_assignment -name VERILOG_MACRO ZET98_PCM86=1"
    }
    if ($PackedGraphics) {
        Add-Content -LiteralPath (Join-Path $sourceRoot 'Zet98/v17/release-Zet98MiSTer.qsf') `
            -Value 'set_global_assignment -name VERILOG_MACRO ZET98_PEGC=1'
        $packedSdc = Join-Path $sourceRoot 'Zet98/v17/Zet98MiSTer.sdc'
        $packedConstraints = Get-Content -LiteralPath $packedSdc -Raw
        if ($packedConstraints -notmatch '(?m)^set pegc_enabled 0\s*$') { throw 'Missing packed-graphics constraint profile marker' }
        $packedConstraints -replace '(?m)^set pegc_enabled 0\s*$', 'set pegc_enabled 1' | Set-Content -LiteralPath $packedSdc
    }
    if ($ExtendedRamMB -ne 0) {
        Add-Content -LiteralPath (Join-Path $sourceRoot 'Zet98/v17/release-Zet98MiSTer.qsf') `
            -Value "`nset_global_assignment -name VERILOG_MACRO ZET98_EXT_RAM_MB=$ExtendedRamMB"
    }
    if ($Cpu -in @('ao486','z486')) {
        $projectSettings = Join-Path $sourceRoot 'Zet98/v17/release-Zet98MiSTer.qsf'
        # The two CPU sources have incompatible headers both named defines.v.
        # Compile only the selected CPU, preserving the default Zet project.
        $assignments = Get-Content -LiteralPath $projectSettings | Where-Object { $_ -notmatch 'zet-1\.3\.1' }
        $assignments | Set-Content -LiteralPath $projectSettings
        Add-Content -LiteralPath $projectSettings -Value @(
            'set_global_assignment -name VERILOG_MACRO ZET98_AO486=1',
            'set_global_assignment -name VERILOG_MACRO ZET98_CYCLONEV_READY_MUX=1',
            ("set_global_assignment -name QIP_FILE ../../rtl/cpu/" + $(if ($Cpu -eq 'z486') { 'z486_pc98.qip' } else { 'ao486_pc98.qip' }))
        )
    }
    if ($Cpu -eq 'z486') {
        Add-Content -LiteralPath $projectSettings -Value 'set_global_assignment -name VERILOG_MACRO ZET98_Z486=1'
        # Keep the qualified sparse profile as default; Normal is a controlled
        # density experiment. The per-instance timing protections below remain.
        $packingSetting = if ($RegisterPacking -eq 'Normal') { 'NORMAL' } else { 'SPARSE AUTO' }
        Add-Content -LiteralPath $projectSettings -Value @(
            'set_global_assignment -name OPTIMIZATION_MODE "HIGH PERFORMANCE EFFORT"',
            ('set_global_assignment -name QII_AUTO_PACKED_REGISTERS "' + $packingSetting + '"'),
            'set_global_assignment -name ENABLE_BENEFICIAL_SKEW_OPTIMIZATION ON',
            "set_global_assignment -name SEED $Seed",
            # B120 packed this opposite-edge transfer onto a 0.632 ns local
            # ASDATA route despite a 2.097 ns hold violation. Leave these few
            # registers unpacked so the router can repair the short data path.
            'set_instance_assignment -name QII_AUTO_PACKED_REGISTERS OFF -to "*|vlines_pixel_source*"',
            'set_instance_assignment -name QII_AUTO_PACKED_REGISTERS OFF -to "*|VLINESC*"',
            # Keep FEC read capture out of packed local feedback paths so the
            # router can meet pc98-read-transfer.sdc's minimum-delay margin.
            'set_instance_assignment -name QII_AUTO_PACKED_REGISTERS OFF -to "*|ram|FECRDAT*"',
            # B146 still used a 0.269 ns local route into FECRDAT[2].asdata.
            # Disable secondary synchronous-load/enable recognition for this
            # bank so the data mux uses ordinary logic/routing. Keep all SDC
            # setup/hold requirements; post-fit analysis decides acceptance.
            'set_instance_assignment -name ALLOW_SYNCH_CTRL_USAGE OFF -to "*|ram|FECRDAT*"',
            'set_instance_assignment -name AUTO_CLOCK_ENABLE_RECOGNITION OFF -to "*|ram|FECRDAT*"'
        )
    }
    if ($SystemClockMHz -ne 20) {
        Add-Content -LiteralPath (Join-Path $sourceRoot 'Zet98/v17/release-Zet98MiSTer.qsf') `
            -Value "`nset_global_assignment -name VERILOG_MACRO ZET98_TURBO$SystemClockMHz=1"
    }
    if ($Cpu -eq 'z486' -or ($Cpu -eq 'ao486' -and $SystemClockMHz -ge 75)) {
        # Upstream ao486 explicitly enables these physical optimization knobs.
        # Keep all-corner timing analysis and our CDC bounds intact.
        Add-Content -LiteralPath (Join-Path $sourceRoot 'Zet98/v17/release-Zet98MiSTer.qsf') -Value @(
            'set_global_assignment -name FITTER_EFFORT "STANDARD FIT"',
            'set_global_assignment -name PHYSICAL_SYNTHESIS_COMBO_LOGIC ON',
            'set_global_assignment -name PHYSICAL_SYNTHESIS_EFFORT EXTRA',
            'set_global_assignment -name PHYSICAL_SYNTHESIS_REGISTER_RETIMING ON',
            'set_global_assignment -name OPTIMIZATION_TECHNIQUE SPEED',
            'set_global_assignment -name OPTIMIZE_POWER_DURING_SYNTHESIS OFF',
            'set_global_assignment -name ROUTER_REGISTER_DUPLICATION ON',
            'set_global_assignment -name FITTER_AGGRESSIVE_ROUTABILITY_OPTIMIZATION ALWAYS'
        )
    }
    if ($PrepareOnly) {
        Write-Host "Prepared $SystemClockMHz MHz source snapshot: $sourceRoot"
        return
    }
    Invoke-DockerCommand -Arguments @('--context',$DockerContext,'image','inspect',$Image,'--format','{{.Id}}') |
        Set-Content -LiteralPath (Join-Path $buildRoot 'toolchain-image.txt')
    Write-Host "Build directory: $buildRoot"
    # Quartus performs many small random database reads. Build on Docker's
    # Linux filesystem: Windows bind shares can stall these accesses in 9P.
    # Keep the source snapshot and export the complete database for TimeQuest.
    $containerName = 'zet98-' + $buildName
    $compileCommand = if ($MapOnly) { 'quartus_map Zet98 -c release-Zet98MiSTer' } else { 'quartus_sh --flow compile Zet98 -c release-Zet98MiSTer' }
    if ($Cpu -eq 'z486') {
        # QSF is not parsed like a sourced Tcl script: braces can become part
        # of the target name. Verify Quartus sees the intended exact targets.
        $compileCommand = 'quartus_sh -t ../../scripts/check-z486-fit-assignments.tcl && ' + $compileCommand
    }
    $requireUart = if ($MidiUart -or $Z486DebugUart -or $CdTrace) { 1 } else { 0 }
    if (-not $MapOnly) {
        $compileCommand += " && quartus_cdb -t ../../scripts/check-hps-peripherals.tcl $requireUart"
        # Physical FEC return buffers must survive fitting (as in the B161 flow).
        $compileCommand += ' && quartus_cdb -t ../../scripts/check-fec-route.tcl'
    }
    # The watchdog stops Quartus after -StallMinutes silent minutes (exit 125) or 150 minutes
    # in total (exit 124), keeping diagnostics under Zet98/v17/watchdog.
    if ((Get-Content -LiteralPath (Join-Path $sourceRoot 'scripts/quartus-watchdog.sh') -Raw).Contains("`r")) {
        throw 'scripts/quartus-watchdog.sh must use LF line endings'
    }
    $containerId = Invoke-DockerCommand -Arguments @('--context',$DockerContext,'create','--name',$containerName,
        '--cpus',"$BuildCpus",'--memory',"${BuildMemoryGB}g",'--memory-swap',"${BuildMemoryGB}g",
        '--network','none','--env',"STALL_MINUTES=$StallMinutes",'--workdir','/project/Zet98/v17',$Image,'bash','../../scripts/quartus-watchdog.sh',$compileCommand)
    $containerId | Set-Content -LiteralPath (Join-Path $buildRoot 'container-id.txt')
    $containerName | Set-Content -LiteralPath (Join-Path $buildRoot 'container-name.txt')
    Invoke-DockerCommand -Arguments @('--context',$DockerContext,'cp',"$sourceRoot/.","${containerName}:/project/") -TimeoutSeconds 60 | Out-Null
    Invoke-DockerCommand -Arguments @('--context',$DockerContext,'start',$containerName) | Out-Null
    Write-Host "Started detached container: $containerName"
    if ($StartOnly) {
        Write-Host 'Build is running; inspect this same container and export results before removing it.'
        return
    }
    do {
        $containerState = Invoke-DockerCommand -Arguments @('--context',$DockerContext,'inspect',$containerName,'--format','{{json .State}}') | ConvertFrom-Json
        if ($containerState.Paused) { throw "Build container $containerName is paused; inspect before resuming." }
        if ($containerState.Running) { Start-Sleep -Seconds 10 }
    } while ($containerState.Running)
    if ($containerState.Status -notin @('exited','dead')) { throw "Unexpected container state: $($containerState.Status)" }
    Invoke-DockerCommand -Arguments @('--context',$DockerContext,'logs',$containerName) -TimeoutSeconds 30 |
        Set-Content -LiteralPath (Join-Path $buildRoot 'quartus.log')
    Export-DockerDirectory -DockerContext $DockerContext -Container $containerName -Source /project/Zet98/v17 -Destination (Join-Path $sourceRoot 'Zet98/v17')
    Invoke-DockerCommand -Arguments @('--context',$DockerContext,'rm',$containerName) | Out-Null
    if ($containerState.ExitCode -ne 0 -or $containerState.OOMKilled) { throw "Quartus failed. See $buildRoot/quartus.log" }
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
