param([string]$OutputDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (!$OutputDirectory) { $OutputDirectory=Join-Path $root 'build/monitor' }
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$csc=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
& $csc /nologo /target:winexe /optimize+ /platform:x64 /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll /r:System.Core.dll ("/out:" + (Join-Path $OutputDirectory "Zet98Monitor.exe")) (Join-Path $PSScriptRoot "BuildMonitor.cs")
if ($LASTEXITCODE -ne 0) {throw 'Monitor compilation failed'}
Write-Host "Built $OutputDirectory/Zet98Monitor.exe"
