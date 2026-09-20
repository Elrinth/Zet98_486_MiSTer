param(
    [Parameter(Mandatory)]
    [string]$SummaryPath
)

$ErrorActionPreference = 'Stop'
$summary = Get-Content -LiteralPath $SummaryPath -Raw
$entries = @([regex]::Matches($summary, '(?m)^Type\s*:\s*(.+)\r?\nSlack\s*:\s*(-?[0-9]+(?:\.[0-9]+)?)'))
if ($entries.Count -eq 0) { throw "No timing results found in $SummaryPath" }
$checks = @($entries | ForEach-Object {
    [pscustomobject]@{
        Type = $_.Groups[1].Value.Trim()
        SlackNs = [double]::Parse($_.Groups[2].Value, [Globalization.CultureInfo]::InvariantCulture)
    }
})
$violations = @($checks | Where-Object { $_.SlackNs -lt 0 })
[pscustomobject]@{
    Summary = $SummaryPath
    ReportedTimingViolations = $violations.Count
    WorstSlackNs = ($checks | Measure-Object -Property SlackNs -Minimum).Minimum
    # Constraint coverage and hardware behavior are not established by slack.
    Checks = $checks
}
