param([Parameter(Mandatory=$true)][string]$FitterReport)
$ErrorActionPreference = 'Stop'
# QSF uses elaborated entity:instance paths, unlike TimeQuest's abbreviated
# register names. An unmatched GLOBAL_SIGNAL assignment can fail silently.
$rows = @(Get-Content -LiteralPath $FitterReport | Where-Object {
    $_ -match 'VTIMING:TIM\|clk3sft\[2\]' -and
    $_ -match ';\s*Clock\s*;'
})
if (@($rows).Count -ne 1) { throw 'Expected one pixel clock in Fitter Global Signal Details.' }
if ($rows[0] -notmatch ';\s*Clock\s*;\s*yes\s*;\s*Global Clock\s*;') {
    throw 'Pixel divider did not use a global clock network. Check the GLOBAL_SIGNAL destination.'
}
Write-Host 'Pixel divider uses a global clock network (confirmed in Fitter report).'
