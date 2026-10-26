$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$stateRoot = Join-Path $env:USERPROFILE '.claude\team-setup'
$logPath = Join-Path $stateRoot 'codegraph-init.log'
$logRotationBytes = 1MB
$initTimeoutSeconds = 570
$localGitTimeoutSeconds = 10
$excludeEntry = '.codegraph/'
$cmdMetacharacterPattern = '[&|<>^%!()"]'

function Write-InitLog {
    param([string]$Level, [string]$Text)

    try {
        New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
        if ((Test-Path -LiteralPath $logPath) -and (Get-Item -LiteralPath $logPath).Length -gt $logRotationBytes) {
            Move-Item -LiteralPath $logPath -Destination ($logPath + '.1') -Force
        }
        $line = '{0} [{1}] {2}' -f [DateTime]::UtcNow.ToString('o'), $Level, $Text
        Add-Content -LiteralPath $logPath -Value $line -Encoding utf8NoBOM
    } catch {
        return
    }
}

function Write-HookMessage {
    param([string]$Text, [string]$AdditionalContext)

    $hookOutput = @{ systemMessage = $Text }
    if ($AdditionalContext) {
        $hookOutput['hookSpecificOutput'] = @{ hookEventName = 'SessionStart'; additionalContext = $AdditionalContext }
    }
    Write-Output ($hookOutput | ConvertTo-Json -Depth 5 -Compress -EscapeHandling EscapeNonAscii)
}

function Invoke-ProcessWithTimeout {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [string]$WorkingDirectory,
        [int]$TimeoutSeconds,
        [hashtable]$Environment = @{}
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new($FilePath)
    foreach ($argument in $ArgumentList) { $startInfo.ArgumentList.Add($argument) }
    if ($WorkingDirectory) { $startInfo.WorkingDirectory = $WorkingDirectory }
    foreach ($variableName in $Environment.Keys) { $startInfo.Environment[$variableName] = $Environment[$variableName] }
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)

    $process = [System.Diagnostics.Process]::Start($startInfo)
    try {
        $process.StandardInput.Close()
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) { $process.Kill($true) }
        [void]$process.WaitForExit(10000)
        [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($outputTask, $errorTask), 5000)

        $standardOutput = if ($outputTask.IsCompleted) { $outputTask.Result } else { '' }
        $standardError = if ($errorTask.IsCompleted) { $errorTask.Result } else { '' }
        return [pscustomobject]@{
            ExitCode    = if ($timedOut) { -1 } else { $process.ExitCode }
            TimedOut    = $timedOut
            Output      = $standardOutput
            ErrorOutput = $standardError
        }
    } finally {
        $process.Dispose()
    }
}

function Get-FailureText {
    param($ProcessResult)

    if ($ProcessResult.TimedOut) { return 'timed out' }
    return "exit code $($ProcessResult.ExitCode). $($ProcessResult.ErrorOutput.Trim()) $($ProcessResult.Output.Trim())".Trim()
}

function Test-IsExcludedRoot {
    param([string]$Path)

    $normalizedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    $homePath = [System.IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd('\')
    if ($normalizedPath -ieq $homePath) { return $true }
    return [System.IO.Path]::GetPathRoot($Path).TrimEnd('\') -ieq $normalizedPath
}

function Add-ExcludeEntry {
    param([string]$ExcludePath)

    New-Item -ItemType Directory -Path (Split-Path -Parent $ExcludePath) -Force | Out-Null
    $currentText = if (Test-Path -LiteralPath $ExcludePath) { Get-Content -LiteralPath $ExcludePath -Raw } else { '' }
    if ($null -eq $currentText) { $currentText = '' }
    if (@($currentText -split '\r?\n') -contains $excludeEntry) { return }

    $newLine = if ($currentText.Contains("`r`n")) { "`r`n" } else { "`n" }
    $separator = if ($currentText -and -not $currentText.EndsWith("`n")) { $newLine } else { '' }
    [System.IO.File]::WriteAllText($ExcludePath, $currentText + $separator + $excludeEntry + $newLine, [System.Text.UTF8Encoding]::new($false))
}

$mutex = $null
$ownsMutex = $false
try {
    [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
    if (-not $payload) { exit 0 }
    if (-not [string]::IsNullOrEmpty([string]$payload.agent_id)) { exit 0 }
    if ([string]::IsNullOrWhiteSpace([string]$payload.cwd)) { exit 0 }

    $codeGraphCommand = Get-Command codegraph.cmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $gitCommand = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $codeGraphCommand -or -not $gitCommand) { exit 0 }

    $topLevelResult = Invoke-ProcessWithTimeout -FilePath $gitCommand.Source -ArgumentList @('-C', [string]$payload.cwd, 'rev-parse', '--show-toplevel') -TimeoutSeconds $localGitTimeoutSeconds
    if ($topLevelResult.TimedOut -or $topLevelResult.ExitCode -ne 0) { exit 0 }
    $topLevel = [System.IO.Path]::GetFullPath($topLevelResult.Output.Trim())
    if (Test-IsExcludedRoot -Path $topLevel) { exit 0 }
    if ($topLevel -match $cmdMetacharacterPattern) {
        Write-InitLog 'WARN' "codegraph init skipped in ${topLevel}: the path has a cmd.exe metacharacter."
        exit 0
    }

    $mutexKey = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($topLevel.ToLowerInvariant()))).Replace('-', '')
    $mutex = [System.Threading.Mutex]::new($false, "Local\codegraph-init-$mutexKey")
    $ownsMutex = $mutex.WaitOne(0)
    if (-not $ownsMutex) { exit 0 }

    $trackedResult = Invoke-ProcessWithTimeout -FilePath $gitCommand.Source -ArgumentList @('--icase-pathspecs', '-C', $topLevel, 'ls-files', '--', '.codegraph') -TimeoutSeconds $localGitTimeoutSeconds
    if ($trackedResult.TimedOut -or $trackedResult.ExitCode -ne 0) {
        Write-InitLog 'WARN' "git ls-files failed in ${topLevel}: $(Get-FailureText $trackedResult)"
        exit 0
    }
    if ($trackedResult.Output.Trim()) {
        Write-InitLog 'WARN' "codegraph init skipped in ${topLevel}: the repo tracks .codegraph, so the hook leaves it unchanged."
        exit 0
    }

    $indexFolder = Join-Path $topLevel '.codegraph'
    $pendingMarkerPath = Join-Path $stateRoot "codegraph-init-$mutexKey.pending"
    $failureMarkerPath = Join-Path $stateRoot "codegraph-init-$mutexKey.failed"
    if (Test-Path -LiteralPath $failureMarkerPath) {
        $failureAge = [DateTime]::UtcNow - (Get-Item -LiteralPath $failureMarkerPath).LastWriteTimeUtc
        if ($failureAge -ge [TimeSpan]::Zero -and $failureAge -lt [TimeSpan]::FromHours(24)) {
            Write-InitLog 'INFO' "codegraph init skipped in ${topLevel}: the last init failed less than 24 h ago."
            exit 0
        }
    }
    if ((Test-Path -LiteralPath (Join-Path $indexFolder 'codegraph.db')) -and -not (Test-Path -LiteralPath $pendingMarkerPath)) { exit 0 }
    if (Test-Path -LiteralPath $indexFolder) { Remove-Item -LiteralPath $indexFolder -Recurse -Force }

    $excludeResult = Invoke-ProcessWithTimeout -FilePath $gitCommand.Source -ArgumentList @('-C', $topLevel, 'rev-parse', '--git-path', 'info/exclude') -TimeoutSeconds $localGitTimeoutSeconds
    if ($excludeResult.TimedOut -or $excludeResult.ExitCode -ne 0) {
        Write-InitLog 'WARN' "git rev-parse --git-path failed in ${topLevel}: $(Get-FailureText $excludeResult)"
        exit 0
    }
    Add-ExcludeEntry -ExcludePath ([System.IO.Path]::GetFullPath($excludeResult.Output.Trim(), $topLevel))

    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    New-Item -ItemType File -Path $pendingMarkerPath -Force | Out-Null
    $initStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $initResult = Invoke-ProcessWithTimeout -FilePath $codeGraphCommand.Source -ArgumentList @('init', '--yes', $topLevel) -TimeoutSeconds $initTimeoutSeconds -Environment @{ CODEGRAPH_TELEMETRY = '0' }
    $initStopwatch.Stop()
    $databaseMissing = -not (Test-Path -LiteralPath (Join-Path $indexFolder 'codegraph.db'))
    if ($initResult.TimedOut -or $initResult.ExitCode -ne 0 -or $databaseMissing) {
        if (Test-Path -LiteralPath $indexFolder) { Remove-Item -LiteralPath $indexFolder -Recurse -Force }
        Remove-Item -LiteralPath $pendingMarkerPath -Force
        New-Item -ItemType File -Path $failureMarkerPath -Force | Out-Null
        (Get-Item -LiteralPath $failureMarkerPath).LastWriteTimeUtc = [DateTime]::UtcNow
        $failureText = if ($initResult.TimedOut -or $initResult.ExitCode -ne 0) { Get-FailureText $initResult } else { 'codegraph.db is missing after init.' }
        Write-InitLog 'WARN' "codegraph init failed in ${topLevel}: $failureText"
        Write-HookMessage "CodeGraph init failed in $topLevel. The hook tries again after 24 h. See $logPath."
        exit 0
    }
    Remove-Item -LiteralPath $pendingMarkerPath -Force
    Remove-Item -LiteralPath $failureMarkerPath -Force -ErrorAction SilentlyContinue
    Write-InitLog 'INFO' "codegraph init finished in $topLevel."
    Write-HookMessage "CodeGraph indexed $topLevel in $([int][Math]::Round($initStopwatch.Elapsed.TotalSeconds)) s." -AdditionalContext 'This repo has a CodeGraph index. Call the `codegraph_explore` tool first to find a symbol, its callers, or its usages. If the tool is deferred, load it with ToolSearch `select:mcp__codegraph__codegraph_explore`. Send a question about how code works, and a symbol search, to the `Explore` agent in this session. It calls this tool and returns a short answer.'
} catch {
    Write-InitLog 'ERROR' "$($_.Exception.Message) $($_.ScriptStackTrace)"
    exit 0
} finally {
    if ($mutex) {
        if ($ownsMutex) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}
exit 0
