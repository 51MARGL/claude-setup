#Requires -Version 7.2
[CmdletBinding()]
param(
    [int]$CheckIntervalMinutes = 60,
    [int]$FetchTimeoutSeconds = 30,
    [int]$InstallTimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = $PSScriptRoot
$stateRoot = Join-Path $env:USERPROFILE '.claude\team-setup'
$logPath = Join-Path $stateRoot 'update.log'
$lastCheckPath = Join-Path $stateRoot 'update-last-check.txt'
$lastStopPath = Join-Path $stateRoot 'update-last-stop.json'
$stopMessageRepeatHours = 24
$lockPath = Join-Path $stateRoot 'update.lock'
$installStatePath = Join-Path $stateRoot 'install-state.json'
$localGitTimeoutSeconds = 10
$mergeTimeoutSeconds = 60
$logRotationBytes = 1MB
$updateMessage = $null
$gitPath = $null
$lock = $null
$mergedCommitCount = 0
$changedSensitivePaths = @()
$sensitivePaths = @(
    'install.ps1',
    'update.ps1',
    'claude-home/settings.json',
    'claude-home/CLAUDE-TEAM.md',
    'claude-home/CLAUDE-MAIN.md',
    'claude-home/STE.md',
    'mcp/servers.json',
    'claude-home/hooks/main-session-rules.ps1',
    'claude-home/hooks/notify.ps1',
    'claude-home/statusline.ps1',
    'claude-home/skills/strategic-compact/suggest-compact.ps1',
    'claude-home/commands/orchestrate.md',
    'claude-home/orchestrate/design.md',
    'claude-home/orchestrate/feature.md',
    'claude-home/orchestrate/bugfix.md',
    'claude-home/orchestrate/test.md',
    'claude-home/orchestrate/refactor.md',
    'claude-home/orchestrate/review.md',
    'claude-home/orchestrate/custom.md',
    'claude-home/orchestrate/shared-steps.md',
    'claude-home/output-styles/audhd.md',
    'claude-home/skills/mistakes-log/SKILL.md',
    'claude-home/skills/strategic-compact/SKILL.md',
    'claude-home/agents/architect.md',
    'claude-home/agents/planner.md',
    'claude-home/agents/dotnet-developer.md',
    'claude-home/agents/frontend-developer.md',
    'claude-home/agents/powershell-developer.md',
    'claude-home/agents/container-developer.md',
    'claude-home/agents/tester.md',
    'claude-home/agents/code-reviewer.md',
    'claude-home/agents/style-reviewer.md',
    'claude-home/agents/security-reviewer.md',
    'claude-home/agents/migration-reviewer.md',
    'claude-home/agents/docs-updater.md',
    'claude-home/agents/devops.md',
    'claude-home/agents/pr-reviewer.md',
    'claude-home/agents/git.md',
    'claude-home/agents/explore.md'
)

function Write-UpdateLog {
    param([string]$Level, [string]$Text)

    try {
        New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
        if ((Test-Path -LiteralPath $logPath) -and (Get-Item -LiteralPath $logPath).Length -gt $logRotationBytes) {
            Move-Item -LiteralPath $logPath -Destination ($logPath + '.1') -Force
        }
        $redactedText = $Text -replace '(https?://)[^/@\s]+@', '$1***@'
        $line = '{0} [{1}] {2}' -f [DateTime]::UtcNow.ToString('o'), $Level, $redactedText
        Add-Content -LiteralPath $logPath -Value $line -Encoding utf8NoBOM
    } catch {
        return
    }
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

    $process = [System.Diagnostics.Process]::Start($startInfo)
    try {
        $process.StandardInput.Close()
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) { $process.Kill($true) }
        $process.WaitForExit()
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

function Invoke-Git {
    param([string[]]$GitArguments, [int]$TimeoutSeconds = $localGitTimeoutSeconds)

    return Invoke-ProcessWithTimeout -FilePath $gitPath -ArgumentList (@('-C', $repoRoot) + $GitArguments) -TimeoutSeconds $TimeoutSeconds -Environment @{
        GIT_TERMINAL_PROMPT = '0'
        GCM_INTERACTIVE     = 'never'
        GIT_OPTIONAL_LOCKS  = '0'
    }
}

function Get-FailureText {
    param($ProcessResult)

    if ($ProcessResult.TimedOut) { return 'timed out' }
    return "exit code $($ProcessResult.ExitCode). $($ProcessResult.ErrorOutput.Trim()) $($ProcessResult.Output.Trim())".Trim()
}

function Test-CheckIntervalElapsed {
    if (-not (Test-Path -LiteralPath $lastCheckPath)) { return $true }
    $lastCheckText = (Get-Content -LiteralPath $lastCheckPath -Raw -ErrorAction SilentlyContinue)
    if ([string]::IsNullOrWhiteSpace($lastCheckText)) { return $true }

    $isoFormats = [string[]]@(
        "yyyy-MM-dd'T'HH:mm:ss.FFFFFFFK",
        "yyyy-MM-dd'T'HH:mmK",
        "yyyy-MM-dd'T'HH:mm:ss.FFFFFFF",
        "yyyy-MM-dd'T'HH:mm",
        'yyyy-MM-dd'
    )
    $lastCheck = [DateTimeOffset]::MinValue
    $parsed = [DateTimeOffset]::TryParseExact($lastCheckText.Trim().TrimStart([char]0xFEFF).Trim(), $isoFormats, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeLocal, [ref]$lastCheck)
    if (-not $parsed) {
        Write-UpdateLog 'WARN' "Cannot parse the last check time in $lastCheckPath. The check interval counts as elapsed."
        return $true
    }

    $now = [DateTimeOffset]::UtcNow
    if ($lastCheck.UtcDateTime -gt $now.UtcDateTime.AddMinutes(5)) {
        Write-UpdateLog 'WARN' "The last check time in $lastCheckPath is in the future. The check interval counts as elapsed."
        return $true
    }
    return $lastCheck.UtcDateTime -le $now.UtcDateTime.AddMinutes(-$CheckIntervalMinutes)
}

function Set-StopMessage {
    param([string]$Reason, [string]$Text)

    $storedReason = $null
    $storedShownUtc = [DateTimeOffset]::MinValue
    try {
        $stored = Get-Content -LiteralPath $lastStopPath -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable
        $storedReason = [string]$stored['reason']
        $storedShownUtc = [DateTimeOffset]::Parse([string]$stored['shownUtc'], [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
    } catch {
        $storedReason = $null
    }

    $now = [DateTimeOffset]::UtcNow
    $isRepeat = $storedReason -eq $Reason -and $storedShownUtc -gt $now.AddHours(-$stopMessageRepeatHours) -and $storedShownUtc -le $now.AddMinutes(5)
    if ($isRepeat) { return }

    $script:updateMessage = $Text
    try {
        $temporaryPath = $lastStopPath + '.tmp'
        $stopState = [ordered]@{ reason = $Reason; shownUtc = $now.ToString('o') }
        Set-Content -LiteralPath $temporaryPath -Value ($stopState | ConvertTo-Json -Compress) -Encoding utf8NoBOM
        Move-Item -LiteralPath $temporaryPath -Destination $lastStopPath -Force
    } catch {
        Write-UpdateLog 'WARN' "Cannot write $lastStopPath. $($_.Exception.Message)"
    }
}

function Update-TeamSetup {
    if (-not (Test-Path -LiteralPath $installStatePath)) {
        Write-UpdateLog 'WARN' "No install state at $installStatePath. Run install.ps1 by hand once."
        return
    }

    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCommand) {
        Write-UpdateLog 'WARN' 'git was not found on PATH.'
        return
    }
    $script:gitPath = $gitCommand.Source

    $gitFailedText = "Team Claude setup auto-update skipped: git failed in the clone at $repoRoot. See $logPath."
    $mergeFailedText = "Team Claude setup auto-update failed: git could not fast-forward the clone at $repoRoot. See $logPath."

    $branch = Invoke-Git @('symbolic-ref', '--quiet', '--short', 'HEAD')
    if ($branch.TimedOut -or $branch.ExitCode -notin 0, 1) {
        Write-UpdateLog 'WARN' "git symbolic-ref failed: $(Get-FailureText $branch)"
        Set-StopMessage -Reason 'git-failed' -Text $gitFailedText
        return
    }
    if ($branch.ExitCode -eq 1 -or $branch.Output.Trim() -ne 'master') {
        Write-UpdateLog 'INFO' 'The clone is not on master. Update stopped.'
        Set-StopMessage -Reason 'not-on-master' -Text "Team Claude setup auto-update skipped: the clone at $repoRoot is not on master. Run: git -C `"$repoRoot`" switch master"
        return
    }

    $status = Invoke-Git @('status', '--porcelain', '--untracked-files=no')
    if ($status.TimedOut -or $status.ExitCode -ne 0) {
        Write-UpdateLog 'WARN' "git status failed: $(Get-FailureText $status)"
        Set-StopMessage -Reason 'git-failed' -Text $gitFailedText
        return
    }
    if ($status.Output.Trim()) {
        Write-UpdateLog 'INFO' 'The clone has uncommitted changes. Update stopped.'
        Set-StopMessage -Reason 'uncommitted-changes' -Text "Team Claude setup auto-update skipped: the clone at $repoRoot has uncommitted changes. Commit or stash them."
        return
    }

    $untrackedShippedFiles = Invoke-Git @('ls-files', '--others', '--exclude-standard', '--', 'claude-home')
    if ($untrackedShippedFiles.TimedOut -or $untrackedShippedFiles.ExitCode -ne 0) {
        Write-UpdateLog 'WARN' "git ls-files failed: $(Get-FailureText $untrackedShippedFiles)"
        Set-StopMessage -Reason 'git-failed' -Text $gitFailedText
        return
    }
    if ($untrackedShippedFiles.Output.Trim()) {
        Write-UpdateLog 'INFO' 'The clone has untracked files in claude-home. Update stopped.'
        Set-StopMessage -Reason 'untracked-files' -Text "Team Claude setup auto-update skipped: the clone at $repoRoot has untracked files in claude-home. Commit or delete them."
        return
    }

    $mergeFailed = $false
    $headBeforeMerge = $null
    $fetch = Invoke-Git @('fetch', 'origin', 'master') -TimeoutSeconds $FetchTimeoutSeconds
    if ($fetch.TimedOut -or $fetch.ExitCode -ne 0) {
        Write-UpdateLog 'WARN' "git fetch failed: $(Get-FailureText $fetch)"
        Set-StopMessage -Reason 'git-failed' -Text $gitFailedText
        return
    }

    $behind = Invoke-Git @('rev-list', '--count', 'HEAD..origin/master')
    if ($behind.TimedOut -or $behind.ExitCode -ne 0) {
        Write-UpdateLog 'WARN' "git rev-list failed: $(Get-FailureText $behind)"
        Set-StopMessage -Reason 'git-failed' -Text $gitFailedText
        return
    }
    if ([int]$behind.Output.Trim() -gt 0) {
        $incomingCommits = Invoke-Git @('log', '--oneline', 'HEAD..origin/master')
        $headBeforeMergeResult = Invoke-Git @('rev-parse', 'HEAD')
        if ($headBeforeMergeResult.ExitCode -eq 0) { $headBeforeMerge = $headBeforeMergeResult.Output.Trim() }
        Write-UpdateLog 'INFO' "Incoming commits:`n$($incomingCommits.Output.Trim())"
        $incomingCommitCount = [int]$behind.Output.Trim()
        $merge = Invoke-Git @('merge', '--ff-only', 'origin/master') -TimeoutSeconds $mergeTimeoutSeconds
        if ($merge.TimedOut) {
            Write-UpdateLog 'WARN' "git merge --ff-only failed: $(Get-FailureText $merge)"
            Set-StopMessage -Reason 'merge-failed' -Text $mergeFailedText
            return
        }
        if ($merge.ExitCode -ne 0) {
            $mergeFailed = $true
            Write-UpdateLog 'WARN' "git merge --ff-only failed: $(Get-FailureText $merge)"
        } else {
            $script:mergedCommitCount = $incomingCommitCount
            Write-UpdateLog 'INFO' "Merged $incomingCommitCount new commit(s) from origin/master."
        }
    }

    $head = Invoke-Git @('rev-parse', 'HEAD')
    if ($head.ExitCode -ne 0) {
        Write-UpdateLog 'WARN' "git rev-parse failed: $(Get-FailureText $head)"
        Set-StopMessage -Reason 'git-failed' -Text $gitFailedText
        return
    }
    $headCommit = $head.Output.Trim()

    $installerFailed = $false
    $installedNewCommit = $false
    $installState = Get-Content -LiteralPath $installStatePath -Raw | ConvertFrom-Json -AsHashtable
    $installedCommit = [string]$installState['installedCommit']
    if ($headCommit -ne $installedCommit) {
        $comparedWithInstalledCommit = $false
        $installedCommitKnown = $false
        if ($installedCommit) {
            $installedCommitCheck = Invoke-Git @('cat-file', '-e', "$installedCommit^{commit}")
            $installedCommitKnown = $installedCommitCheck.ExitCode -eq 0
        }
        if ($installedCommitKnown) {
            $sinceInstalledCount = Invoke-Git @('rev-list', '--count', "$installedCommit..HEAD")
            $sinceInstalledPaths = Invoke-Git @('diff', '--name-only', $installedCommit, 'HEAD')
            if ($sinceInstalledCount.ExitCode -eq 0 -and $sinceInstalledPaths.ExitCode -eq 0) {
                $script:mergedCommitCount = [int]$sinceInstalledCount.Output.Trim()
                $script:changedSensitivePaths = @($sinceInstalledPaths.Output -split '\r?\n' | Where-Object { $_ -in $sensitivePaths })
                $comparedWithInstalledCommit = $true
            } else {
                Write-UpdateLog 'WARN' 'Could not compare with the installed commit. The message uses the commits merged in this run.'
            }
        } else {
            Write-UpdateLog 'WARN' 'The installed commit is unknown. The message uses the commits merged in this run.'
        }
        if (-not $comparedWithInstalledCommit -and $headBeforeMerge -and $headBeforeMerge -ne $headCommit) {
            $mergedPaths = Invoke-Git @('diff', '--name-only', $headBeforeMerge, 'HEAD')
            if ($mergedPaths.ExitCode -eq 0) {
                $script:changedSensitivePaths = @($mergedPaths.Output -split '\r?\n' | Where-Object { $_ -in $sensitivePaths })
            }
        }
        $script:lock.Dispose()
        $installerArguments = @('-NoProfile', '-NonInteractive', '-File', (Join-Path $repoRoot 'install.ps1'), '-UseSavedSwitches')
        $installer = Invoke-ProcessWithTimeout -FilePath ([Environment]::ProcessPath) -TimeoutSeconds $InstallTimeoutSeconds -ArgumentList $installerArguments
        if ($installer.ExitCode -ne 0 -and "$($installer.Output) $($installer.ErrorOutput)" -match 'Another install or update runs') {
            Write-UpdateLog 'INFO' 'Another install runs. Waiting 2 seconds, then running install.ps1 once more.'
            Start-Sleep -Seconds 2
            $installer = Invoke-ProcessWithTimeout -FilePath ([Environment]::ProcessPath) -TimeoutSeconds $InstallTimeoutSeconds -ArgumentList $installerArguments
        }
        Write-UpdateLog 'INFO' "install.ps1 output:`n$($installer.Output.Trim())`n$($installer.ErrorOutput.Trim())"
        if ($installer.ExitCode -eq 0) {
            $installedNewCommit = $true
        } else {
            $installerFailed = $true
            Write-UpdateLog 'ERROR' "install.ps1 failed: $(Get-FailureText $installer)"
        }
    }

    if ($mergeFailed) {
        Set-StopMessage -Reason 'merge-failed' -Text $mergeFailedText
        return
    }
    if ($installerFailed) {
        Set-StopMessage -Reason 'install-failed' -Text "Team Claude setup auto-update failed: install.ps1 reported an error. See $logPath."
        return
    }
    Remove-Item -LiteralPath $lastStopPath -Force -ErrorAction SilentlyContinue
    if (-not $installedNewCommit) { return }

    $message = "Team Claude setup updated to $($headCommit.Substring(0, 7))"
    if ($mergedCommitCount -gt 0) {
        $message += " ($mergedCommitCount new $(if ($mergedCommitCount -eq 1) { 'commit' } else { 'commits' }))"
    }
    $message += '. Restart Claude Code to use all changes.'
    if ($changedSensitivePaths.Count -gt 0) {
        $message += " Changed: $($changedSensitivePaths -join ', ')."
    }
    $script:updateMessage = $message
}

function Invoke-Update {
    if (-not (Test-CheckIntervalElapsed)) { return }

    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    try {
        $script:lock = [System.IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
    } catch [System.IO.IOException] {
        Write-UpdateLog 'INFO' 'Another update runs.'
        return
    }

    try {
        if (-not (Test-CheckIntervalElapsed)) { return }
        Set-Content -LiteralPath $lastCheckPath -Value ([DateTimeOffset]::Now.ToString('o')) -Encoding utf8NoBOM
        Update-TeamSetup
    } finally {
        $script:lock.Dispose()
    }
}

try {
    $null = Invoke-Update
} catch {
    Write-UpdateLog 'ERROR' "$($_.Exception.Message) $($_.ScriptStackTrace)"
    $updateMessage = "Team Claude setup auto-update failed. See $logPath."
}

if ($updateMessage) {
    $hookOutput = @{ systemMessage = $updateMessage }
    Write-Output ($hookOutput | ConvertTo-Json -Depth 5 -Compress -EscapeHandling EscapeNonAscii)
}
exit 0
