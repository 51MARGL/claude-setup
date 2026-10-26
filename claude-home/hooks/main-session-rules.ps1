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

    $additionalContext = Get-Content -LiteralPath $rulesPath -Raw
    try {
        $repoRoot = [string]$payload.cwd
        while ($repoRoot -and -not (Test-Path -LiteralPath (Join-Path $repoRoot '.git'))) {
            $repoRoot = Split-Path -Parent $repoRoot
        }
        if ($repoRoot -and
            (Test-Path -LiteralPath (Join-Path $repoRoot '.codegraph\codegraph.db')) -and
            (Get-Command codegraph.cmd -CommandType Application -ErrorAction SilentlyContinue)) {
            $additionalContext += "`r`n`r`nThis repo has a CodeGraph index. Call the ``codegraph_explore`` tool first to find a symbol, its callers, or its usages. If the tool is deferred, load it with ToolSearch ``select:mcp__codegraph__codegraph_explore``. Send a question about how code works, and a symbol search, to the ``Explore`` agent in this session. It calls this tool and returns a short answer."
        }
    } catch {
        $additionalContext = Get-Content -LiteralPath $rulesPath -Raw
    }

    $hookOutput = @{
        hookSpecificOutput = @{
            hookEventName     = 'SessionStart'
            additionalContext = $additionalContext
        }
    }
    Write-Output ($hookOutput | ConvertTo-Json -Depth 5 -Compress -EscapeHandling EscapeNonAscii)
} catch {
    $hookOutput = @{ systemMessage = "main-session-rules.ps1 failed: $($_.Exception.Message) The main-session rules did not load." }
    Write-Output ($hookOutput | ConvertTo-Json -Depth 5 -Compress -EscapeHandling EscapeNonAscii)
    exit 0
}
exit 0
