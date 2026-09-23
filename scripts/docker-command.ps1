#requires -Version 7.0
# Short, bounded Docker commands only. Start workloads detached and inspect
# their container state; never hold a Docker client open for an entire build.
function Invoke-DockerCommand {
    param(
        [Parameter(Mandatory)] [string[]]$Arguments,
        [ValidateRange(1, 60)] [int]$TimeoutSeconds = 15,
        [string]$Executable = 'docker',
        [string]$OutputFile
    )
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command $Executable -ErrorAction Stop).Source
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $startInfo.ArgumentList.Add($argument) }
    $client = [System.Diagnostics.Process]::new()
    $client.StartInfo = $startInfo
    $started = $false
    $outputStream = $null
    # Publish only a safe operation label, never command arguments/passwords.
    $activityId = $null
    $activityStart = [datetime]::UtcNow
    $activityWriter = Join-Path $PSScriptRoot 'write-monitor-activity.ps1'
    if ($Executable -match '(plink|pscp)(\.exe)?$' -and
        ($Arguments -join ' ') -match '192\.168\.0\.161' -and
        (Test-Path -LiteralPath $activityWriter)) {
        $activityId = [guid]::NewGuid().ToString('N')
        $activityTitle = if ($Executable -match 'pscp') { 'MiSTer file transfer' } else { 'MiSTer SSH operation' }
        $commandFileIndex = [array]::IndexOf($Arguments, '-m')
        if ($commandFileIndex -ge 0 -and $commandFileIndex + 1 -lt $Arguments.Count) {
            $activityTitle += ' · ' + [IO.Path]::GetFileName($Arguments[$commandFileIndex + 1])
        }
        try { & $activityWriter -Title $activityTitle -Status Running -Id $activityId -StartedAt $activityStart } catch { }
    }
    $operationSucceeded = $false
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        if ($OutputFile) {
            $outputStream = [IO.File]::Open($OutputFile, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
        }
        $started = $client.Start()
        if (-not $started) { throw 'Docker client did not start.' }
        $stdout = if ($outputStream) { $client.StandardOutput.BaseStream.CopyToAsync($outputStream) }
                  else { $client.StandardOutput.ReadToEndAsync() }
        $stderr = $client.StandardError.ReadToEndAsync()
        if (-not $client.WaitForExit($TimeoutSeconds * 1000)) {
            throw "Docker command timed out after $TimeoutSeconds seconds. Inspect the same container before retrying."
        }
        $remaining = [math]::Max(1, $TimeoutSeconds * 1000 - [int]$watch.ElapsedMilliseconds)
        if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout,$stderr), $remaining)) {
            throw 'Docker output did not close before its deadline; inspect the same container before retrying.'
        }
        $outputText = if ($outputStream) { '' } else { $stdout.GetAwaiter().GetResult() }
        $errorText = $stderr.GetAwaiter().GetResult()
        if ($client.ExitCode -ne 0) {
            throw "Docker exited $($client.ExitCode): $errorText $outputText"
        }
        if ($errorText.Trim()) { Write-Host $errorText.Trim() }
        $operationSucceeded = $true
        $outputText.TrimEnd()
    } finally {
        # Also executes on cancellation/error: an interrupted command must not
        # leave its still-running Windows client or child clients behind.
        if ($started -and -not $client.HasExited) {
            $client.Kill($true)
            if (-not $client.WaitForExit(5000)) { Write-Warning 'Docker client did not terminate after being killed.' }
        }
        $client.Dispose()
        if ($outputStream) { $outputStream.Dispose() }
        $watch.Stop()
        if ($activityId) {
            $activityStatus = if ($operationSucceeded) { 'Completed' } else { 'Failed' }
            try { & $activityWriter -Title $activityTitle -Status $activityStatus -Id $activityId -StartedAt $activityStart } catch { }
        }
    }
}

function Export-DockerDirectory {
    param([string]$DockerContext, [string]$Container, [string]$Source, [string]$Destination)
    $Destination = [IO.Path]::GetFullPath($Destination)
    $archive = Join-Path (Split-Path -Parent $Destination) ('docker-export-' + [guid]::NewGuid().ToString('N') + '.tar')
    Invoke-DockerCommand -Arguments @('--context',$DockerContext,'cp',"${Container}:$($Source.TrimEnd('/'))/.",'-') `
        -OutputFile $archive -TimeoutSeconds 60 | Out-Null
    & python (Join-Path $PSScriptRoot 'docker-export.py') --archive $archive $Container $Source $Destination
    if ($LASTEXITCODE -ne 0) { throw "Cannot unpack export; container $Container and archive $archive retained." }
}
