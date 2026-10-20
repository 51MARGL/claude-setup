$ErrorActionPreference = 'Stop'

function Test-SessionWrittenSince {
    param([string]$TranscriptPath, [datetime]$Since)

    if (-not $TranscriptPath -or -not (Test-Path -LiteralPath $TranscriptPath)) { return $false }
    return (Get-Item -LiteralPath $TranscriptPath).LastWriteTimeUtc -gt $Since
}

try {
    [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $eventTime = [datetime]::UtcNow
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
    if (-not $payload) { exit 0 }
    if (-not [string]::IsNullOrEmpty([string]$payload.agent_id)) { exit 0 }

    $waitLine = 'Waiting for agents. Nothing needed from you now.'
    $verifyAfterDelay = $false
    $title = $null
    $body = $null
    switch ($payload.hook_event_name) {
        'Stop' {
            if (@($payload.background_tasks | Where-Object { $null -ne $_ }).Count -gt 0) { exit 0 }
            $lastMessageLines = ([string]$payload.last_assistant_message) -split '\r?\n' | ForEach-Object { $_.Trim() }
            if ($lastMessageLines -ccontains $waitLine) { exit 0 }
            $title = 'Claude: done'
            $body = 'Waiting for your next message'
        }
        'Notification' {
            $title = switch ($payload.notification_type) {
                'permission_prompt' { 'Claude: permission needed' }
                'elicitation_dialog' { 'Claude: input needed' }
                'elicitation_url_dialog' { 'Claude: input needed' }
                default { $null }
            }
            $body = [string]$payload.message
            $verifyAfterDelay = $true
        }
        'PreToolUse' {
            if ($payload.tool_name -eq 'AskUserQuestion') {
                $title = 'Claude: decision needed'
                $body = [string]@($payload.tool_input.questions)[0].question
                $maxQuestionLength = 120
                if ($body.Length -gt $maxQuestionLength) {
                    $body = $body.Substring(0, $maxQuestionLength - 3) + '...'
                }
            }
        }
    }
    if (-not $title) { exit 0 }

    if ($verifyAfterDelay) {
        Start-Sleep -Seconds 5
        if (Test-SessionWrittenSince -TranscriptPath ([string]$payload.transcript_path) -Since $eventTime.AddSeconds(2)) { exit 0 }
    }

    if ($payload.cwd) {
        $body = "[$(Split-Path -Leaf $payload.cwd)] $body"
    }

    $stateDirectory = Join-Path $env:USERPROFILE '.claude\cache\notify'
    if (-not (Test-Path $stateDirectory)) {
        New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    }

    $sessionId = if ($payload.session_id) { [string]$payload.session_id } else { 'unknown' }
    $stampFile = Join-Path $stateDirectory (($sessionId -replace '[^A-Za-z0-9._-]', '_') + '.last')

    if (Test-Path $stampFile) {
        if ((Get-Item $stampFile).LastWriteTimeUtc -gt [datetime]::UtcNow.AddSeconds(-5)) { exit 0 }
    } else {
        Get-ChildItem -Path $stateDirectory -Filter '*.last' |
            Where-Object { $_.LastWriteTimeUtc -lt [datetime]::UtcNow.AddDays(-7) } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
    Set-Content -Path $stampFile -Value ([datetime]::UtcNow.ToString('o')) -NoNewline

    # WinRT toast types load only in Windows PowerShell 5.1, not in pwsh 7.
    $toastScript = @'
$ErrorActionPreference = 'Stop'
[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
[void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
$xml.LoadXml('<toast><visual><binding template="ToastGeneric"><text/><text/></binding></visual></toast>')
$textNodes = $xml.GetElementsByTagName('text')
[void]$textNodes.Item(0).AppendChild($xml.CreateTextNode($env:CLAUDE_NOTIFY_TITLE))
[void]$textNodes.Item(1).AppendChild($xml.CreateTextNode($env:CLAUDE_NOTIFY_BODY))
$toast = New-Object Windows.UI.Notifications.ToastNotification $xml
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($env:CLAUDE_NOTIFY_APP_ID).Show($toast)
'@
    $encodedToastScript = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($toastScript))

    $env:CLAUDE_NOTIFY_TITLE = $title
    $env:CLAUDE_NOTIFY_BODY = $body
    $env:CLAUDE_NOTIFY_APP_ID = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
    $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $windowsPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encodedToastScript *> $null
} catch {
    exit 0
}
exit 0
