param([Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{32}$')][string]$CaptureId)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'docker-command.ps1')
$root=Split-Path $PSScriptRoot -Parent
$folder=Join-Path $root "build/monitor/captures/$CaptureId"
New-Item -ItemType Directory -Force $folder | Out-Null
$credential=Import-Clixml (Join-Path $root 'build/monitor/mister-credential.xml')
$password=$credential.GetNetworkCredential().Password
$target=$credential.UserName+'@192.168.0.161'
$plink='C:\Program Files\PuTTY\plink.exe'
$pscp='C:\Program Files\PuTTY\pscp.exe'
$token='Z98Monitor'+$CaptureId
$remoteScript=Join-Path $folder 'capture.sh'
$script=@'
printf '%s\n' 'screenshot TOKEN' > /dev/MiSTer_cmd
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    found=$(find /media/fat/screenshots -type f -name '*TOKEN*.png')
    if [ -n "$found" ]; then printf '%s\n' "$found"; exit 0; fi
done
exit 1
'@
[IO.File]::WriteAllText($remoteScript,$script.Replace('TOKEN',$token).Replace("`r`n","`n"))
$activityId='screenshot-'+$CaptureId
& (Join-Path $PSScriptRoot 'write-monitor-activity.ps1') -Title 'Capturing MiSTer screenshot' -Status Running -Id $activityId
try {
    $remote=Invoke-DockerCommand -Executable $plink -Arguments @('-ssh','-batch','-pw',$password,$target,'-m',$remoteScript) -TimeoutSeconds 15
    $remote=$remote.Trim()
    if ($remote -notmatch '^/media/fat/screenshots/[a-zA-Z0-9 _./()\-]+\.png$' -or !$remote.Contains($token) -or $remote.Contains('..')) { throw 'Unexpected screenshot path; no file deleted.' }
    $capturedAt=[datetime]::UtcNow.ToString('o')
    $local=Join-Path $folder 'screenshot.png'
    Invoke-DockerCommand -Executable $pscp -Arguments @('-batch','-pw',$password,($target+':'+$remote),$local) -TimeoutSeconds 25 | Out-Null
    $image=[Drawing.Image]::FromFile($local)
    try { if ($image.Width -lt 1 -or $image.Height -lt 1) {throw 'Invalid downloaded image'} } finally {$image.Dispose()}
    $cleanup=Join-Path $folder 'cleanup.sh'
    [IO.File]::WriteAllText($cleanup,"rm -- '$remote'`n")
    $warning=''
    try { Invoke-DockerCommand -Executable $plink -Arguments @('-ssh','-batch','-pw',$password,$target,'-m',$cleanup) -TimeoutSeconds 10 | Out-Null }
    catch { $warning='Downloaded, but remote cleanup failed; the original remains on MiSTer.' }
    @{path=$local;warning=$warning;capturedAt=$capturedAt} | ConvertTo-Json | Set-Content (Join-Path $folder 'result.json')
    & (Join-Path $PSScriptRoot 'write-monitor-activity.ps1') -Title $(if($warning){$warning}else{'Screenshot downloaded; captured file removed from MiSTer'}) -Status Completed -Id $activityId
} catch {
    & (Join-Path $PSScriptRoot 'write-monitor-activity.ps1') -Title 'Screenshot failed; undownloaded images are retained on MiSTer' -Status Failed -Id $activityId
    throw
}
