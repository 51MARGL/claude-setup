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

function Get-StatusLineSnapshot {
    param([string]$SnapshotFile, [int]$MaximumAgeMinutes)

    if (-not (Test-Path -LiteralPath $SnapshotFile)) { return $null }
    if ((Get-Item -LiteralPath $SnapshotFile).LastWriteTime -lt (Get-Date).AddMinutes(-$MaximumAgeMinutes)) { return $null }
    try {
        $snapshot = Get-Content -LiteralPath $SnapshotFile -Raw | ConvertFrom-Json
    } catch {
        return $null
    }
    if ($null -eq $snapshot.usedPercentage) { return $null }
    return $snapshot
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

    $staleLimit = (Get-Date).AddDays(-7)
    Get-ChildItem -LiteralPath $stateDirectory -File |
        Where-Object { $_.Extension -eq '.count' -or ($_.Extension -in '.json', '.tmp' -and $_.LastWriteTime -lt $staleLimit) } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    $safeSessionId = $sessionId -replace '[^A-Za-z0-9._-]', '_'
    $snapshot = Get-StatusLineSnapshot -SnapshotFile (Join-Path $stateDirectory ($safeSessionId + '.context.json')) -MaximumAgeMinutes 10

    $contextTokens = $null
    $reportedWindowTokens = $null
    if ($snapshot) {
        $percent = [int][Math]::Floor([double]$snapshot.usedPercentage)
        if ($snapshot.usedTokens -and $snapshot.totalTokens) {
            $contextTokens = [int64]$snapshot.usedTokens
            $reportedWindowTokens = [int64]$snapshot.totalTokens
        }
    } else {
        $contextTokens = Get-LastContextTokenCount -TranscriptPath $payload.transcript_path
        if ($contextTokens -le 0) { exit 0 }
        $percent = [int][Math]::Floor($contextTokens * 100 / $windowTokens)
        $reportedWindowTokens = $windowTokens
    }

    $stateFile = Join-Path $stateDirectory ($safeSessionId + '.json')
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

    $tokenDetail = ''
    if ($null -ne $contextTokens -and $null -ne $reportedWindowTokens) {
        $contextThousands = [Math]::Round($contextTokens / 1000)
        $windowThousands = [Math]::Round($reportedWindowTokens / 1000)
        $tokenDetail = " (${contextThousands}k of ${windowThousands}k tokens)"
    }
    $userMessage = "[StrategicCompact] Context is at $percent%$tokenDetail. Claude asks for /compact at the next gate."
    $modelMessage = "[StrategicCompact] Context is at $percent%$tokenDetail. Inside an agent chain, ask the user to run /compact at the next compact gate. Outside an agent chain, ask the user to run /compact at the end of the current answer."
    $hookEventName = if ([string]$payload.hook_event_name -eq 'UserPromptSubmit') { 'UserPromptSubmit' } else { 'PostToolUse' }
    @{
        systemMessage      = $userMessage
        suppressOutput     = $true
        hookSpecificOutput = @{ hookEventName = $hookEventName; additionalContext = $modelMessage }
    } | ConvertTo-Json -Compress -Depth 3
} catch {
    exit 0
}
exit 0
