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
$lockPath = Join-Path $stateRoot 'update.lock'
$installStatePath = Join-Path $stateRoot 'install-state.json'
$localGitTimeoutSeconds = 30
$mergeTimeoutSeconds = 60
$logRotationBytes = 1MB
$updateMessage = $null
$gitPath = $null
$lock = $null
$mergedCommitCount = 0
$changedSensitivePaths = @()
$sensitivePaths = @('install.ps1', 'update.ps1', 'claude-home/settings.json', 'claude-home/CLAUDE-TEAM.md', 'mcp/servers.json')

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

    $insideWorkTree = Invoke-Git @('rev-parse', '--is-inside-work-tree')
    if ($insideWorkTree.ExitCode -ne 0 -or $insideWorkTree.Output.Trim() -ne 'true') {
        Write-UpdateLog 'WARN' "$repoRoot is not a git clone. Update stopped."
        return
    }

    $branch = Invoke-Git @('symbolic-ref', '--quiet', '--short', 'HEAD')
    if ($branch.ExitCode -ne 0 -or $branch.Output.Trim() -ne 'master') {
        Write-UpdateLog 'INFO' 'The clone is not on master. Update stopped.'
        return
    }

    $status = Invoke-Git @('status', '--porcelain', '--untracked-files=no')
    if ($status.ExitCode -ne 0 -or $status.Output.Trim()) {
        Write-UpdateLog 'INFO' 'The clone has uncommitted changes. Update stopped.'
        return
    }

    $untrackedShippedFiles = Invoke-Git @('ls-files', '--others', '--exclude-standard', '--', 'claude-home')
    if ($untrackedShippedFiles.ExitCode -ne 0 -or $untrackedShippedFiles.Output.Trim()) {
        Write-UpdateLog 'INFO' 'The clone has untracked files in claude-home. Update stopped.'
        return
    }

    $mergeFailed = $false
    $fetch = Invoke-Git @('fetch', 'origin', 'master') -TimeoutSeconds $FetchTimeoutSeconds
    if ($fetch.ExitCode -ne 0) {
        Write-UpdateLog 'WARN' "git fetch failed: $(Get-FailureText $fetch)"
    } else {
        $behind = Invoke-Git @('rev-list', '--count', 'HEAD..origin/master')
        if ($behind.ExitCode -ne 0) {
            Write-UpdateLog 'WARN' "git rev-list failed: $(Get-FailureText $behind)"
        } elseif ([int]$behind.Output.Trim() -gt 0) {
            $incomingCommits = Invoke-Git @('log', '--oneline', 'HEAD..origin/master')
            $incomingDiffStat = Invoke-Git @('diff', '--stat', 'HEAD', 'origin/master')
            $incomingPaths = Invoke-Git @('diff', '--name-only', 'HEAD', 'origin/master')
            Write-UpdateLog 'INFO' "Incoming commits:`n$($incomingCommits.Output.Trim())`nIncoming changes:`n$($incomingDiffStat.Output.Trim())"
            $incomingCommitCount = [int]$behind.Output.Trim()
            $script:changedSensitivePaths = @($incomingPaths.Output -split '\r?\n' | Where-Object { $_ -in $sensitivePaths })
            $merge =Invoke-Git @('merge', '--ff-only', 'origin/master') -TimeoutSeconds $mergeTimeoutSeconds
            if ($merge.ExitCode -ne 0) {
                $mergeFailed = $true
                Write-UpdateLog 'WARN' "git merge --ff-only failed: $(Get-FailureText $merge)"
            } else {
                $script:mergedCommitCount = $incomingCommitCount
                Write-UpdateLog 'INFO' "Merged $incomingCommitCount new commit(s) from origin/master."
            }
        }
    }

    $head = Invoke-Git @('rev-parse', 'HEAD')
    if ($head.ExitCode -ne 0) {
        Write-UpdateLog 'WARN' "git rev-parse failed: $(Get-FailureText $head)"
        return
    }
    $headCommit = $head.Output.Trim()

    $installerFailed = $false
    $installedNewCommit = $false
    $installState = Get-Content -LiteralPath $installStatePath -Raw | ConvertFrom-Json -AsHashtable
    $installedCommit = [string]$installState['installedCommit']
    if ($headCommit -ne $installedCommit) {
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
            } else {
                Write-UpdateLog 'WARN' 'Could not compare with the installed commit. The message uses the commits merged in this run.'
            }
        } else {
            Write-UpdateLog 'WARN' 'The installed commit is unknown. The message uses the commits merged in this run.'
        }
        $script:lock.Dispose()
        $installer = Invoke-ProcessWithTimeout -FilePath ([Environment]::ProcessPath) -TimeoutSeconds $InstallTimeoutSeconds -ArgumentList @(
            '-NoProfile', '-NonInteractive', '-File', (Join-Path $repoRoot 'install.ps1'), '-UseSavedSwitches'
        )
        Write-UpdateLog 'INFO' "install.ps1 output:`n$($installer.Output.Trim())`n$($installer.ErrorOutput.Trim())"
        if ($installer.ExitCode -eq 0) {
            $installedNewCommit = $true
        } else {
            $installerFailed = $true
            Write-UpdateLog 'ERROR' "install.ps1 failed: $(Get-FailureText $installer)"
        }
    }

    if ($mergeFailed -or $installerFailed) {
        $script:updateMessage = "Team Claude setup auto-update failed. See $logPath."
        return
    }
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
    $hookOutput = @{
        systemMessage      = $updateMessage
        hookSpecificOutput = @{
            hookEventName     = 'SessionStart'
            additionalContext = $updateMessage
        }
    }
    Write-Output ($hookOutput | ConvertTo-Json -Depth 5 -Compress -EscapeHandling EscapeNonAscii)
}
exit 0
