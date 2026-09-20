param(
    [string]$Image = 'theypsilon/quartus-lite-c5:17.0',
    [string]$DockerContext = 'desktop-linux',
    [ValidateSet(20, 40)]
    [int]$SystemClockMHz = 20,
    [switch]$PrepareOnly
)

$ErrorActionPreference = 'Stop'
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
    if ($SystemClockMHz -eq 40) {
        Add-Content -LiteralPath (Join-Path $sourceRoot 'Zet98/v17/release-Zet98MiSTer.qsf') `
            -Value "`nset_global_assignment -name VERILOG_MACRO ZET98_TURBO40=1"
    }
    if ($PrepareOnly) {
        Write-Host "Prepared $SystemClockMHz MHz source snapshot: $sourceRoot"
        return
    }
    & docker --context $DockerContext image inspect $Image --format '{{.Id}}' |
        Set-Content -LiteralPath (Join-Path $buildRoot 'toolchain-image.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Quartus Docker image is not installed.' }
    Write-Host "Build directory: $buildRoot"
    & docker --context $DockerContext run --rm --network none `
        --mount "type=bind,source=$sourceRoot,target=/project" `
        --workdir /project/Zet98/v17 $Image bash -lc `
        'quartus_sh --flow compile Zet98 -c release-Zet98MiSTer' 2>&1 |
        Tee-Object -FilePath (Join-Path $buildRoot 'quartus.log')
    if ($LASTEXITCODE -ne 0) { throw "Quartus failed. See $buildRoot/quartus.log" }
    Write-Host "RBF and reports: $sourceRoot/Zet98/v17/output_files"
    $timing = & (Join-Path $PSScriptRoot 'read-timing.ps1') -SummaryPath `
        (Join-Path $sourceRoot 'Zet98/v17/output_files/release-Zet98MiSTer.sta.summary')
    $timing | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $buildRoot 'timing-results.json')
    if ($timing.ReportedTimingViolations -gt 0) {
        throw "RBF generated, but timing FAILED: $($timing.ReportedTimingViolations) checks with negative slack; worst $($timing.WorstSlackNs) ns. This is not a verified release. See $buildRoot/timing-results.json"
    }
    Write-Host 'No negative slack reported. Constraint coverage and hardware verification are still required.'
} finally {
    Pop-Location
}
