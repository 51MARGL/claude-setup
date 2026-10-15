$ErrorActionPreference = 'Stop'

function Get-PositiveIntegerSetting {
    param([string]$Value, [int]$Default)

    $parsed = 0
    if ($Value -and [int]::TryParse($Value, [ref]$parsed) -and $parsed -gt 0) { return $parsed }
    return $Default
}

function Get-LastContextTokenCount {
    param([string]$TranscriptPath)

    if (-not $TranscriptPath -or -not (Test-Path -LiteralPath $TranscriptPath)) { return 0 }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $chunkSize = [int64]524288
    $fs = [System.IO.File]::Open($TranscriptPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        while ($true) {
            $fileLength = $fs.Length
            $start = [Math]::Max([int64]0, $fileLength - $chunkSize)
            $fs.Seek($start, [System.IO.SeekOrigin]::Begin) | Out-Null
            $buffer = New-Object byte[] ($fileLength - $start)
            $read = 0
            while ($read -lt $buffer.Length) {
                $count = $fs.Read($buffer, $read, $buffer.Length - $read)
                if ($count -le 0) { break }
                $read += $count
            }
            $lines = $utf8NoBom.GetString($buffer, 0, $read) -split "`n"
            $firstCompleteLine = if ($start -gt 0) { 1 } else { 0 }

            for ($index = $lines.Count - 1; $index -ge $firstCompleteLine; $index--) {
                $line = $lines[$index]
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                try {
                    $entry = $line | ConvertFrom-Json
                } catch {
                    continue
                }
                if ($entry.isSidechain) { continue }
                $usage = $entry.message.usage
                if (-not $usage) { continue }

                $tokens = [int64]0
                if ($usage.input_tokens) { $tokens += [int64]$usage.input_tokens }
                if ($usage.cache_creation_input_tokens) { $tokens += [int64]$usage.cache_creation_input_tokens }
                if ($usage.cache_read_input_tokens) { $tokens += [int64]$usage.cache_read_input_tokens }
                if ($tokens -gt 0) { return $tokens }
            }

            if ($start -eq 0) { return 0 }
            $chunkSize *= 4
        }
    } finally {
        $fs.Dispose()
    }
}

try {
    [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
    if ($payload.agent_id) { exit 0 }

    $sessionId = $payload.session_id
    if (-not $sessionId) { exit 0 }

    $windowTokens = Get-PositiveIntegerSetting -Value $env:COMPACT_CONTEXT_WINDOW -Default 1000000
    $thresholdPercent = Get-PositiveIntegerSetting -Value $env:COMPACT_CONTEXT_PERCENT -Default 15
    $reminderStepPercent = 10

    $stateDirectory = Join-Path $env:USERPROFILE '.claude\cache\strategic-compact'
    if (-not (Test-Path -LiteralPath $stateDirectory)) {
        New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    }

    Get-ChildItem -LiteralPath $stateDirectory -File |
        Where-Object { $_.Extension -in '.json', '.count' -and $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $stateDirectory -Filter '*.count' -File |
        Remove-Item -Force -ErrorAction SilentlyContinue

    $contextTokens = Get-LastContextTokenCount -TranscriptPath $payload.transcript_path
    if ($contextTokens -le 0) { exit 0 }

    $percent = [int][Math]::Floor($contextTokens * 100 / $windowTokens)

    $stateFile = Join-Path $stateDirectory (($sessionId -replace '[^A-Za-z0-9._-]', '_') + '.json')
    $lastReportedLevel = -1
    if (Test-Path -LiteralPath $stateFile) {
        try {
            $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
            if ($null -ne $state.lastReportedLevel) { $lastReportedLevel = [int]$state.lastReportedLevel }
        } catch {
            $lastReportedLevel = -1
        }
    }

    if ($lastReportedLevel -ge 0 -and $percent -lt $thresholdPercent) {
        Remove-Item -LiteralPath $stateFile -Force
        $lastReportedLevel = -1
    }

    if ($percent -lt $thresholdPercent) { exit 0 }

    $currentLevel = $thresholdPercent + $reminderStepPercent * [int][Math]::Floor(($percent - $thresholdPercent) / $reminderStepPercent)
    if ($currentLevel -le $lastReportedLevel) { exit 0 }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $temporaryStateFile = $stateFile + '.tmp'
    [System.IO.File]::WriteAllText($temporaryStateFile, (@{ lastReportedLevel = $currentLevel } | ConvertTo-Json -Compress), $utf8NoBom)
    Move-Item -LiteralPath $temporaryStateFile -Destination $stateFile -Force

    $contextThousands = [Math]::Round($contextTokens / 1000)
    $windowThousands = [Math]::Round($windowTokens / 1000)
    $message = "[StrategicCompact] Context is at $percent% (${contextThousands}k of ${windowThousands}k tokens). At the next compact gate, ask the user to run /compact."
    @{ systemMessage = $message; suppressOutput = $true } | ConvertTo-Json -Compress
} catch {
    exit 0
}
exit 0
