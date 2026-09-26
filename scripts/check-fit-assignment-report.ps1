param([Parameter(Mandatory)][string]$MapReport)
$ErrorActionPreference='Stop'
if (!(Test-Path -LiteralPath $MapReport -PathType Leaf)) {throw 'Missing synthesis report'}
$rejected = @(Select-String -LiteralPath $MapReport -Pattern 'Critical Warning \(136021\): Ignored assignment')
if ($rejected.Count) {
    throw "Synthesis ignored $($rejected.Count) invalid-node assignments. Inspect $MapReport before accepting the build."
}
Write-Host 'PASS: no invalid-node synthesis assignments were ignored'
