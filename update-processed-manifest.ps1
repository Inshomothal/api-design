param(
    [string]$LogsDirectory = ".\\logs",
    [string]$ManifestPath = ".\\processed_manifest.json"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $LogsDirectory)) {
    throw "Logs directory not found: $LogsDirectory"
}

$logFiles = @(
    Get-ChildItem -LiteralPath $LogsDirectory -File |
        Where-Object { $_.Name -match '^operations_(\d{4}-\d{2}-\d{2})_(\d{2}-\d{2}-\d{2})\.log$' } |
        ForEach-Object {
            if ($_.Name -match '^operations_(\d{4}-\d{2}-\d{2})_(\d{2})-(\d{2})-(\d{2})\.log$') {
                [pscustomobject]@{
                    FileInfo = $_
                    Timestamp = [datetime]::ParseExact(
                        ("{0} {1}:{2}:{3}" -f $Matches[1], $Matches[2], $Matches[3], $Matches[4]),
                        "yyyy-MM-dd HH:mm:ss",
                        [System.Globalization.CultureInfo]::InvariantCulture
                    )
                }
            }
        }
)

if ($logFiles.Count -eq 0) {
    throw "No log files matching operations_<yyyy-mm-dd_hh-mm-ss>.log were found in $LogsDirectory"
}

$latestLog = $logFiles |
    Sort-Object -Property Timestamp -Descending |
    Select-Object -First 1

$statusMap = @{
    START   = "processing"
    SUCCESS = "done"
    FAIL    = "failure"
}

$entries = foreach ($line in (Get-Content -LiteralPath $latestLog.FileInfo.FullName)) {
    if ($line -match '^\s*(?<timestamp>[^|]+?)\s*\|\s*REENCODE_MP3_(?<state>START|SUCCESS|FAIL)\s*\|\s*(?<path>.+?)\s*$') {
        [pscustomobject]@{
            path          = $Matches['path']
            status        = $statusMap[$Matches['state']]
            lastProcessed = [datetime]::Parse($Matches['timestamp']).ToString("yyyy-MM-dd HH:mm:ss")
        }
    }
}

if (-not $entries) {
    throw "No valid REENCODE_MP3_<START|SUCCESS|FAIL> entries were found in $($latestLog.FileInfo.FullName)"
}

$manifest = @()
if (Test-Path -LiteralPath $ManifestPath) {
    $raw = Get-Content -LiteralPath $ManifestPath -Raw
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        $parsed = $raw | ConvertFrom-Json
        if ($parsed -is [System.Collections.IEnumerable] -and -not ($parsed -is [string])) {
            $manifest = @($parsed)
        }
        else {
            $manifest = @($parsed)
        }
    }
}

$manifest += $entries

$manifest |
    ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath $ManifestPath -Encoding utf8

Write-Host ("Processed {0} entries from latest log: {1}" -f $entries.Count, $latestLog.FileInfo.FullName)
Write-Host ("Manifest updated: {0}" -f (Resolve-Path -LiteralPath $ManifestPath))
