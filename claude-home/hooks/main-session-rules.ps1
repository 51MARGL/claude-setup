$ErrorActionPreference = 'Stop'

try {
    [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
    if (-not $payload) { exit 0 }
    if (-not [string]::IsNullOrEmpty([string]$payload.agent_id)) { exit 0 }

    $rulesPath = Join-Path $PSScriptRoot '..\CLAUDE-MAIN.md'
    if (-not (Test-Path -LiteralPath $rulesPath)) {
        $hookOutput = @{ systemMessage = 'CLAUDE-MAIN.md is missing. The main-session rules did not load.' }
        Write-Output ($hookOutput | ConvertTo-Json -Depth 5 -Compress -EscapeHandling EscapeNonAscii)
        exit 0
    }

    $hookOutput = @{
        hookSpecificOutput = @{
            hookEventName     = 'SessionStart'
            additionalContext = Get-Content -LiteralPath $rulesPath -Raw
        }
    }
    Write-Output ($hookOutput | ConvertTo-Json -Depth 5 -Compress -EscapeHandling EscapeNonAscii)
} catch {
    $hookOutput = @{ systemMessage = "main-session-rules.ps1 failed: $($_.Exception.Message) The main-session rules did not load." }
    Write-Output ($hookOutput | ConvertTo-Json -Depth 5 -Compress -EscapeHandling EscapeNonAscii)
    exit 0
}
exit 0
