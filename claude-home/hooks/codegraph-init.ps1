param([string]$Mode)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$stateRoot = Join-Path $env:USERPROFILE '.claude\team-setup'
$logPath = Join-Path $stateRoot 'codegraph-init.log'
$logRotationBytes = 1MB
$initTimeoutSeconds = 570
$localGitTimeoutSeconds = 10
$excludeEntry = '.codegraph/'
$cmdMetacharacterPattern = '[&|<>^%!()"]'
$worktreeRunBudgetSeconds = 600
$worktreeMinimumRemainingSeconds = 60
$worktreeFinishMarginSeconds = 30
$newWorktreeMaxAge = [TimeSpan]::FromMinutes(10)
$staleMarkerAge = [TimeSpan]::FromDays(30)
$uncPathPattern = '^(\\\\|//)'

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

function Initialize-CodeGraphIndex {
    param([string]$TopLevel, [string]$CodeGraphPath, [string]$GitPath, [int]$TimeoutSeconds, [switch]$Report)

    if (Test-IsExcludedRoot -Path $TopLevel) { return }
    if ($TopLevel -match $cmdMetacharacterPattern) {
        Write-InitLog 'WARN' "codegraph init skipped in ${TopLevel}: the path has a cmd.exe metacharacter."
        return
    }

    $mutexKey = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($TopLevel.ToLowerInvariant()))).Replace('-', '')
    $mutex = [System.Threading.Mutex]::new($false, "Local\codegraph-init-$mutexKey")
    $ownsMutex = $false
    try {
        $ownsMutex = $mutex.WaitOne(0)
        if (-not $ownsMutex) { return }

        $trackedResult = Invoke-ProcessWithTimeout -FilePath $GitPath -ArgumentList @('--icase-pathspecs', '-C', $TopLevel, 'ls-files', '--', '.codegraph') -TimeoutSeconds $localGitTimeoutSeconds
        if ($trackedResult.TimedOut -or $trackedResult.ExitCode -ne 0) {
            Write-InitLog 'WARN' "git ls-files failed in ${TopLevel}: $(Get-FailureText $trackedResult)"
            return
        }
        if ($trackedResult.Output.Trim()) {
            Write-InitLog 'WARN' "codegraph init skipped in ${TopLevel}: the repo tracks .codegraph, so the hook leaves it unchanged."
            return
        }

        $indexFolder = Join-Path $TopLevel '.codegraph'
        $pendingMarkerPath = Join-Path $stateRoot "codegraph-init-$mutexKey.pending"
        $failureMarkerPath = Join-Path $stateRoot "codegraph-init-$mutexKey.failed"
        if (Test-Path -LiteralPath $failureMarkerPath) {
            $failureAge = [DateTime]::UtcNow - (Get-Item -LiteralPath $failureMarkerPath).LastWriteTimeUtc
            if ($failureAge -ge [TimeSpan]::Zero -and $failureAge -lt [TimeSpan]::FromHours(24)) {
                Write-InitLog 'INFO' "codegraph init skipped in ${TopLevel}: the last init failed less than 24 h ago."
                return
            }
        }
        if ((Test-Path -LiteralPath (Join-Path $indexFolder 'codegraph.db')) -and -not (Test-Path -LiteralPath $pendingMarkerPath)) { return }
        if (Test-Path -LiteralPath $indexFolder) { Remove-Item -LiteralPath $indexFolder -Recurse -Force }

        $excludeResult = Invoke-ProcessWithTimeout -FilePath $GitPath -ArgumentList @('-C', $TopLevel, 'rev-parse', '--git-path', 'info/exclude') -TimeoutSeconds $localGitTimeoutSeconds
        if ($excludeResult.TimedOut -or $excludeResult.ExitCode -ne 0) {
            Write-InitLog 'WARN' "git rev-parse --git-path failed in ${TopLevel}: $(Get-FailureText $excludeResult)"
            return
        }
        Add-ExcludeEntry -ExcludePath ([System.IO.Path]::GetFullPath($excludeResult.Output.Trim(), $TopLevel))

        New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
        New-Item -ItemType File -Path $pendingMarkerPath -Force | Out-Null
        $initStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $initResult = Invoke-ProcessWithTimeout -FilePath $CodeGraphPath -ArgumentList @('init', '--yes', $TopLevel) -TimeoutSeconds $TimeoutSeconds -Environment @{ CODEGRAPH_TELEMETRY = '0' }
        $initStopwatch.Stop()
        $databaseMissing = -not (Test-Path -LiteralPath (Join-Path $indexFolder 'codegraph.db'))
        if ($initResult.TimedOut -or $initResult.ExitCode -ne 0 -or $databaseMissing) {
            if (Test-Path -LiteralPath $indexFolder) { Remove-Item -LiteralPath $indexFolder -Recurse -Force }
            Remove-Item -LiteralPath $pendingMarkerPath -Force
            New-Item -ItemType File -Path $failureMarkerPath -Force | Out-Null
            (Get-Item -LiteralPath $failureMarkerPath).LastWriteTimeUtc = [DateTime]::UtcNow
            $failureText = if ($initResult.TimedOut -or $initResult.ExitCode -ne 0) { Get-FailureText $initResult } else { 'codegraph.db is missing after init.' }
            Write-InitLog 'WARN' "codegraph init failed in ${TopLevel}: $failureText"
            if ($Report) { Write-HookMessage "CodeGraph init failed in $TopLevel. The hook tries again after 24 h. See $logPath." }
            return
        }
        Remove-Item -LiteralPath $pendingMarkerPath -Force
        Remove-Item -LiteralPath $failureMarkerPath -Force -ErrorAction SilentlyContinue
        Write-InitLog 'INFO' "codegraph init finished in $TopLevel."
        if ($Report) {
            Write-HookMessage "CodeGraph indexed $TopLevel in $([int][Math]::Round($initStopwatch.Elapsed.TotalSeconds)) s." -AdditionalContext 'This repo has a CodeGraph index. Call the `codegraph_explore` tool first to find a symbol, its callers, or its usages. If the tool is deferred, load it with ToolSearch `select:mcp__codegraph__codegraph_explore`. Send a question about how code works, and a symbol search, to the `Explore` agent in this session. It calls this tool and returns a short answer.'
        }
    } finally {
        if ($ownsMutex) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Get-NewWorktreePaths {
    param([string]$GitPath, [string]$GitDirectory)

    $listResult = Invoke-ProcessWithTimeout -FilePath $GitPath -ArgumentList @('-C', $GitDirectory, 'worktree', 'list', '--porcelain') -TimeoutSeconds $localGitTimeoutSeconds
    if ($listResult.TimedOut -or $listResult.ExitCode -ne 0) { return @() }
    $worktreePaths = @($listResult.Output -split '\r?\n' | Where-Object { $_ -like 'worktree *' } | ForEach-Object { $_.Substring(9).Trim() })
    foreach ($worktreePath in ($worktreePaths | Select-Object -Skip 1)) {
        if ($worktreePath -match $uncPathPattern) { continue }
        $gitFilePath = Join-Path $worktreePath '.git'
        if (-not (Test-Path -LiteralPath $gitFilePath -PathType Leaf)) { continue }
        if (Test-Path -LiteralPath (Join-Path $worktreePath '.codegraph\codegraph.db')) { continue }
        $gitFileAge = [DateTime]::UtcNow - [System.IO.File]::GetCreationTimeUtc($gitFilePath)
        if ($gitFileAge -ge [TimeSpan]::Zero -and $gitFileAge -lt $newWorktreeMaxAge) { [System.IO.Path]::GetFullPath($worktreePath) }
    }
}

function Test-ParentHasIndex {
    param([string]$GitPath, [string]$WorktreePath)

    $commonDirectoryResult = Invoke-ProcessWithTimeout -FilePath $GitPath -ArgumentList @('-C', $WorktreePath, 'rev-parse', '--path-format=absolute', '--git-common-dir') -TimeoutSeconds $localGitTimeoutSeconds
    if ($commonDirectoryResult.TimedOut -or $commonDirectoryResult.ExitCode -ne 0) { return $false }
    $commonDirectory = [System.IO.Path]::GetFullPath($commonDirectoryResult.Output.Trim()).TrimEnd('\')
    if ((Split-Path -Leaf $commonDirectory) -ne '.git') { return $false }
    return Test-Path -LiteralPath (Join-Path (Split-Path -Parent $commonDirectory) '.codegraph\codegraph.db')
}

function Resolve-GitDirectory {
    param([string]$DirectoryText, [string]$BaseDirectory)

    if ($DirectoryText -match $uncPathPattern) { return $null }
    $pathText = $DirectoryText
    if ($pathText -match '^/([A-Za-z])(?=$|/)') {
        $pathText = $Matches[1].ToUpperInvariant() + ':' + $pathText.Substring(2)
        if ($pathText.Length -eq 2) { $pathText += '\' }
    }
    $fullPath = [System.IO.Path]::GetFullPath($pathText, $BaseDirectory)
    if ($fullPath -match $uncPathPattern) { return $null }
    return $fullPath
}

function Remove-StaleMarkers {
    $staleLimit = [DateTime]::UtcNow - $staleMarkerAge
    Get-ChildItem -LiteralPath $stateRoot -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^codegraph-init-.*\.(failed|pending)$' -and $_.LastWriteTimeUtc -lt $staleLimit } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

try {
    [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
    $payloadText = [Console]::In.ReadToEnd()
    $isWorktreeMode = $Mode -eq 'worktree'
    if ($isWorktreeMode -and $payloadText -notmatch 'worktree\s+add' -and $payloadText -notmatch '"tool_name"\s*:\s*"EnterWorktree"') { exit 0 }
    $payload = $payloadText | ConvertFrom-Json
    if (-not $payload) { exit 0 }
    if (-not $isWorktreeMode -and -not [string]::IsNullOrEmpty([string]$payload.agent_id)) { exit 0 }
    if ([string]::IsNullOrWhiteSpace([string]$payload.cwd)) { exit 0 }

    $codeGraphCommand = Get-Command codegraph.cmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $gitCommand = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $codeGraphCommand -or -not $gitCommand) { exit 0 }

    if ($isWorktreeMode) {
        if ([string]$payload.cwd -match $uncPathPattern) { exit 0 }
        $gitDirectory = [string]$payload.cwd
        if ([string]$payload.tool_name -ne 'EnterWorktree') {
            $commandText = [string]$payload.tool_input.command
            if ($commandText -notmatch '(?i)\bgit\b.*\bworktree\s+add\b') { exit 0 }
            $worktreeCommand = $commandText -split '[;&|\r\n]+' | Where-Object { $_ -match '(?i)\bgit\b.*\bworktree\s+add\b' } | Select-Object -First 1
            $optionMatch = [regex]::Match($worktreeCommand, '\bgit((?:\s+(?:-c\s+\S+|-C\s+(?:"[^"]*"|''[^'']*''|\S+)|--\S+))*)\s+worktree\s+add\b')
            foreach ($directoryMatch in [regex]::Matches($optionMatch.Groups[1].Value, '-C\s+(?:"([^"]*)"|''([^'']*)''|(\S+))')) {
                $directoryText = ($directoryMatch.Groups[1].Value, $directoryMatch.Groups[2].Value, $directoryMatch.Groups[3].Value | Where-Object { $_ } | Select-Object -First 1)
                $resolvedDirectory = Resolve-GitDirectory -DirectoryText $directoryText -BaseDirectory $gitDirectory
                if ($resolvedDirectory) { $gitDirectory = $resolvedDirectory }
            }
        }
        $runStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        Remove-StaleMarkers
        foreach ($worktreePath in @(Get-NewWorktreePaths -GitPath $gitCommand.Source -GitDirectory $gitDirectory)) {
            $remainingSeconds = $worktreeRunBudgetSeconds - $runStopwatch.Elapsed.TotalSeconds
            if ($remainingSeconds -lt $worktreeMinimumRemainingSeconds) { break }
            if (-not (Test-ParentHasIndex -GitPath $gitCommand.Source -WorktreePath $worktreePath)) { continue }
            $timeoutSeconds = [int][Math]::Min($initTimeoutSeconds, $remainingSeconds - $worktreeFinishMarginSeconds)
            try {
                Initialize-CodeGraphIndex -TopLevel $worktreePath -CodeGraphPath $codeGraphCommand.Source -GitPath $gitCommand.Source -TimeoutSeconds $timeoutSeconds
            } catch {
                Write-InitLog 'ERROR' "$($_.Exception.Message) $($_.ScriptStackTrace)"
            }
        }
        exit 0
    }

    $topLevelResult = Invoke-ProcessWithTimeout -FilePath $gitCommand.Source -ArgumentList @('-C', [string]$payload.cwd, 'rev-parse', '--show-toplevel') -TimeoutSeconds $localGitTimeoutSeconds
    if ($topLevelResult.TimedOut -or $topLevelResult.ExitCode -ne 0) { exit 0 }
    $topLevel = [System.IO.Path]::GetFullPath($topLevelResult.Output.Trim())
    Initialize-CodeGraphIndex -TopLevel $topLevel -CodeGraphPath $codeGraphCommand.Source -GitPath $gitCommand.Source -TimeoutSeconds $initTimeoutSeconds -Report
} catch {
    Write-InitLog 'ERROR' "$($_.Exception.Message) $($_.ScriptStackTrace)"
    exit 0
}
exit 0
