#requires -Version 7.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../scripts/docker-command.ps1')
$testRoot = Join-Path (Join-Path $PSScriptRoot '../build') ('docker-command-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$fixture = Join-Path $testRoot 'client.py'
$witness = Join-Path $testRoot 'child.pid'
@'
import json, subprocess, sys, time
from pathlib import Path
mode=sys.argv[1]
if mode=='echo':
    print(json.dumps(sys.argv[2:]))
elif mode=='fail':
    print('intentional client failure',file=sys.stderr)
    sys.exit(7)
elif mode=='flood':
    print('x'*200000)
    print('y'*200000,file=sys.stderr)
elif mode=='timeout':
    child=subprocess.Popen([sys.executable,'-c','import time; time.sleep(60)'])
    Path(sys.argv[2]).write_text(str(child.pid))
    time.sleep(60)
'@ | Set-Content -LiteralPath $fixture -Encoding utf8
try {
    $literalArguments = @('two words','a"b','$(not-a-command)','semi;colon','back`tick')
    $actual = Invoke-DockerCommand -Executable python -Arguments (@($fixture,'echo')+$literalArguments) | ConvertFrom-Json
    if (($actual | ConvertTo-Json -Compress) -ne ($literalArguments | ConvertTo-Json -Compress)) { throw 'Argument fidelity failed' }
    $binaryOutput = Join-Path $testRoot 'output.bin'
    Invoke-DockerCommand -Executable python -Arguments (@($fixture,'echo')+$literalArguments) -OutputFile $binaryOutput | Out-Null
    $binaryActual = Get-Content -Raw -LiteralPath $binaryOutput | ConvertFrom-Json
    if (($actual | ConvertTo-Json -Compress) -ne ($binaryActual | ConvertTo-Json -Compress)) { throw 'Binary stream output changed' }
    $failed = $false
    try { Invoke-DockerCommand -Executable python -Arguments @($fixture,'fail') | Out-Null }
    catch { if ($_ -notmatch 'Docker exited 7:.*intentional client failure') { throw }; $failed=$true }
    if (-not $failed) { throw 'Failed client was accepted' }
    Invoke-DockerCommand -Executable python -Arguments @($fixture,'flood') *> (Join-Path $testRoot 'flood.log')
    $timedOut = $false
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try { Invoke-DockerCommand -Executable python -Arguments @($fixture,'timeout',$witness) -TimeoutSeconds 2 | Out-Null }
    catch { if ($_ -notmatch 'timed out') { throw }; $timedOut=$true }
    if (-not $timedOut -or $clock.Elapsed.TotalSeconds -gt 10) { throw 'Timeout did not bound execution' }
    $childId = [int](Get-Content -LiteralPath $witness)
    if (Get-Process -Id $childId -ErrorAction SilentlyContinue) { throw "Timed-out client left child $childId alive" }
    Write-Host 'PASS bounded client: literal arguments, error propagation, full pipes, timeout and child-tree cleanup'
} finally {
    # Keep test evidence. No other processes, Docker/WSL services or containers
    # are used by this regression.
    Write-Host "Test evidence: $testRoot"
}
