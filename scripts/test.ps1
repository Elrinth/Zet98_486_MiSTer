param(
    [string]$DockerContext = 'desktop-linux',
    [string]$QuartusImage = 'theypsilon/quartus-lite-c5:17.0',
    [string]$SimulationImage = 'zet98-sim',
    [switch]$AdaptersOnly
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    & docker --context $DockerContext build -t $SimulationImage -f tests/Dockerfile .
    if ($LASTEXITCODE -ne 0) { throw 'Simulation image build failed.' }
    $sourceMount = "type=bind,source=$projectRoot,target=/project,readonly"
    & docker --context $DockerContext run --rm --network none --mount $sourceMount $SimulationImage bash tests/run.sh
    if ($LASTEXITCODE -ne 0) { throw 'Adapter/peripheral tests failed.' }
    if (-not $AdaptersOnly) {
        # Use models from the locally installed Quartus toolchain. They remain
        # under ignored build output and are never copied into source control.
        $modelPath = Join-Path $projectRoot 'build/intel-sim'
        New-Item -ItemType Directory -Force -Path $modelPath | Out-Null
        & docker --context $DockerContext run --rm --network none `
            --mount "type=bind,source=$modelPath,target=/models" $QuartusImage bash -lc `
            'cp /opt/intelFPGA_lite/quartus/eda/sim_lib/altera_mf.v /models/'
        if ($LASTEXITCODE -ne 0) { throw 'Unable to read the installed Intel simulation models.' }
        & docker --context $DockerContext run --rm --network none --mount $sourceMount $SimulationImage bash tests/run-cpu.sh
        if ($LASTEXITCODE -ne 0) { throw 'Full ao486 CPU test failed.' }
    }
} finally {
    Pop-Location
}
