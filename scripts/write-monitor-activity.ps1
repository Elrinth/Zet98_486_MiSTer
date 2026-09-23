param(
 [Parameter(Mandatory)][string]$Title,
 [ValidateSet('Running','Completed','Failed','Info')][string]$Status='Info',
 [string]$Id=([guid]::NewGuid().ToString('N')),
 [datetime]$StartedAt=[datetime]::UtcNow
)
$ErrorActionPreference='Stop'
if ($Id -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Invalid activity ID' }
$directory=Join-Path (Split-Path $PSScriptRoot -Parent) 'build/monitor-events'
New-Item -ItemType Directory -Force $directory | Out-Null
$existing=Join-Path $directory "$Id.json"
if (!( $PSBoundParameters.ContainsKey('StartedAt') ) -and (Test-Path -LiteralPath $existing)) {
    $StartedAt=[datetime]((Get-Content -LiteralPath $existing -Raw | ConvertFrom-Json).startedAt)
}
$event=[ordered]@{id=$Id;title=$Title;status=$Status;startedAt=$StartedAt.ToUniversalTime().ToString('o');finishedAt=$null}
if ($Status -ne 'Running') { $event.finishedAt=[datetime]::UtcNow.ToString('o') }
$path=Join-Path $directory "$Id.json"
$temp=Join-Path $directory "$Id.tmp"
$event | ConvertTo-Json | Set-Content -LiteralPath $temp -Encoding utf8
Move-Item -LiteralPath $temp -Destination $path -Force
