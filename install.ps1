#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Manual')]
param(
    [Parameter(ParameterSetName = 'Manual')][switch]$SkipStatusLine,
    [Parameter(ParameterSetName = 'Manual')][switch]$SkipMcp,
    [Parameter(ParameterSetName = 'Manual')][switch]$SkipOutputStyle,
    [Parameter(ParameterSetName = 'Manual')][switch]$SkipAutoUpdate,
    [Parameter(ParameterSetName = 'Saved', Mandatory)][switch]$UseSavedSwitches
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$sourceRoot = Join-Path $PSScriptRoot 'claude-home'
$mcpConfigPath = Join-Path $PSScriptRoot 'mcp\servers.json'
$targetRoot = Join-Path $env:USERPROFILE '.claude'
$targetRootForwardSlashes = $targetRoot -replace '\\', '/'
$placeholder = '{{CLAUDE_HOME}}'
$repoPlaceholder = '{{TEAM_SETUP_REPO}}'
$repoRootForwardSlashes = $PSScriptRoot -replace '\\', '/'
$removedFiles = [System.Collections.Generic.List[string]]::new()
$stateRoot = Join-Path $targetRoot 'team-setup'
$statePath = Join-Path $stateRoot 'install-state.json'
$teamImportLine = '@~/.claude/CLAUDE-TEAM.md'

function Read-InstallState {
    if (-not (Test-Path -LiteralPath $statePath)) { return $null }
    try {
        return Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
    } catch {
        throw "The install state file '$statePath' is not valid JSON. Fix or remove it, then run the installer again. $($_.Exception.Message)"
    }
}

$installState = Read-InstallState
if ($PSCmdlet.ParameterSetName -eq 'Saved') {
    if (-not $installState -or $installState['switches'] -isnot [System.Collections.IDictionary]) {
        throw "No saved switches in $statePath. Run install.ps1 by hand once."
    }
    $savedSwitches = $installState['switches']
    $SkipStatusLine = [bool]$savedSwitches['SkipStatusLine']
    $SkipMcp = [bool]$savedSwitches['SkipMcp']
    $SkipOutputStyle = [bool]$savedSwitches['SkipOutputStyle']
    $SkipAutoUpdate = [bool]$savedSwitches['SkipAutoUpdate']
}

$previousInstalledFiles = @()
if ($installState -and $installState['installedFiles'] -is [System.Collections.IList]) {
    $previousInstalledFiles = @($installState['installedFiles'])
}

$installLock = $null
if (-not $WhatIfPreference) {
    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    try {
        $installLock = [System.IO.File]::Open((Join-Path $stateRoot 'update.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    } catch [System.IO.IOException] {
        throw 'Another install or update runs. Try again in a minute.'
    }
}

try {
    function Get-InstalledCommit {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
        $commit = & git -C $PSScriptRoot rev-parse HEAD 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return ([string]$commit).Trim()
    }

    foreach ($requiredTool in 'pwsh', 'git') {
        if (-not (Get-Command $requiredTool -ErrorAction SilentlyContinue)) {
            Write-Warning "$requiredTool was not found on PATH. The hook and the status line run through pwsh, so they will not work without it."
        }
    }

    function Merge-UniqueList {
        param([object[]]$Existing, [object[]]$Team)

        $merged = [System.Collections.Generic.List[object]]::new()
        foreach ($item in @($Existing) + @($Team)) {
            if ($null -ne $item -and -not $merged.Contains($item)) {
                $merged.Add($item)
            }
        }
        return , $merged.ToArray()
    }

    function Get-HookIdentity {
        param([System.Collections.IDictionary]$Hook)

        return (@{ command = $Hook['command']; args = @($Hook['args']) } | ConvertTo-Json -Compress)
    }

    function Get-MatcherKey {
        param([System.Collections.IDictionary]$Group)

        $matcher = [string]$Group['matcher']
        if ($matcher -eq '*') { return '' }
        return $matcher
    }

    function Merge-Settings {
        param([System.Collections.IDictionary]$Existing, [System.Collections.IDictionary]$Team)

        $merged = $Existing

        if ($Team.Contains('permissions')) {
            if (-not $merged.Contains('permissions')) { $merged['permissions'] = [ordered]@{} }
            foreach ($listName in 'deny', 'ask') {
                if ($Team['permissions'].Contains($listName)) {
                    $merged['permissions'][$listName] = Merge-UniqueList -Existing $merged['permissions'][$listName] -Team $Team['permissions'][$listName]
                }
            }
        }

        if ($Team.Contains('hooks')) {
            if (-not $merged.Contains('hooks')) { $merged['hooks'] = [ordered]@{} }
            foreach ($eventName in $Team['hooks'].Keys) {
                $eventGroups = [System.Collections.Generic.List[object]]::new()
                if ($merged['hooks'].Contains($eventName)) {
                    foreach ($group in @($merged['hooks'][$eventName])) { $eventGroups.Add($group) }
                }

                foreach ($teamGroup in @($Team['hooks'][$eventName])) {
                    $teamMatcherKey = Get-MatcherKey $teamGroup
                    foreach ($teamHook in @($teamGroup['hooks'])) {
                        $teamHookIdentity = Get-HookIdentity $teamHook
                        $sameMatcherGroups = @($eventGroups | Where-Object { (Get-MatcherKey $_) -ceq $teamMatcherKey })
                        $existingHook = $sameMatcherGroups |
                            ForEach-Object { @($_['hooks']) } |
                            Where-Object { (Get-HookIdentity $_) -eq $teamHookIdentity } |
                            Select-Object -First 1
                        if ($existingHook) { continue }

                        if ($sameMatcherGroups.Count -gt 0) {
                            $sameMatcherGroups[0]['hooks'] = @($sameMatcherGroups[0]['hooks']) + @($teamHook)
                        } else {
                            $newGroup = [ordered]@{}
                            foreach ($groupKey in $teamGroup.Keys) {
                                if ($groupKey -ne 'hooks') { $newGroup[$groupKey] = $teamGroup[$groupKey] }
                            }
                            $newGroup['hooks'] = @($teamHook)
                            $eventGroups.Add($newGroup)
                        }
                    }
                }

                $merged['hooks'][$eventName] = $eventGroups.ToArray()
            }
        }

        if ($Team.Contains('statusLine')) {
            $merged['statusLine'] = $Team['statusLine']
        }

        if ($Team.Contains('env')) {
            if ($merged['env'] -isnot [System.Collections.IDictionary]) { $merged['env'] = [ordered]@{} }
            foreach ($variableName in $Team['env'].Keys) {
                if (-not $merged['env'].Contains($variableName)) {
                    $merged['env'][$variableName] = $Team['env'][$variableName]
                }
            }
        }

        foreach ($key in $Team.Keys) {
            if ($key -notin 'permissions', 'hooks', 'statusLine', 'env' -and -not $merged.Contains($key)) {
                $merged[$key] = $Team[$key]
            }
        }

        return $merged
    }

    function Remove-TargetFile {
        param([string]$RelativePath)

        $resolvedTargetRoot = [System.IO.Path]::GetFullPath($targetRoot)
        $targetPath = [System.IO.Path]::GetFullPath((Join-Path $targetRoot $RelativePath))
        if (-not $targetPath.StartsWith($resolvedTargetRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) { return }
        if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) { return }

        if (-not $PSCmdlet.ShouldProcess($targetPath, 'Delete file that the team setup no longer ships')) { return }

        Remove-Item -LiteralPath $targetPath -Force
        Write-Host "Removed $RelativePath"
        $removedFiles.Add($RelativePath)

        $parentPath = Split-Path -Parent $targetPath
        while ($parentPath -ne $resolvedTargetRoot -and $parentPath.StartsWith($resolvedTargetRoot, [System.StringComparison]::OrdinalIgnoreCase) -and -not (Get-ChildItem -LiteralPath $parentPath -Force | Select-Object -First 1)) {
            Remove-Item -LiteralPath $parentPath -Force
            $parentPath = Split-Path -Parent $parentPath
        }
    }

    function Write-InstallState {
        param([System.Collections.IDictionary]$State)

        if (-not $PSCmdlet.ShouldProcess($statePath, 'Write install state')) { return }
        New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
        $temporaryPath = $statePath + '.tmp'
        Set-Content -LiteralPath $temporaryPath -Value (($State | ConvertTo-Json -Depth 20) + "`n") -NoNewline -Encoding utf8NoBOM
        Move-Item -LiteralPath $temporaryPath -Destination $statePath -Force
    }

    function Write-TargetText {
        param([string]$RelativePath, [string]$Content)

        $targetPath = Join-Path $targetRoot $RelativePath
        if ($PSCmdlet.ShouldProcess($targetPath, 'Write file')) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $targetPath) -Force | Out-Null
            $temporaryPath = $targetPath + '.tmp'
            Set-Content -LiteralPath $temporaryPath -Value $Content -NoNewline -Encoding utf8NoBOM
            Move-Item -LiteralPath $temporaryPath -Destination $targetPath -Force
            Write-Host "Installed $RelativePath"
        }
    }

    function Test-HasTeamImportLine {
        param([string]$Path)

        $insideFence = $false
        foreach ($line in (Get-Content -LiteralPath $Path)) {
            if ($line -match '^\s*(```|~~~)') {
                $insideFence = -not $insideFence
                continue
            }
            if (-not $insideFence -and $line.Trim() -eq $teamImportLine) { return $true }
        }
        return $false
    }

    function Write-BytesBesideTarget {
        param([string]$Path, [byte[]]$Bytes)

        $temporaryPath = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
        try {
            [System.IO.File]::WriteAllBytes($temporaryPath, $Bytes)
            Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
        } finally {
            if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
        }
    }

    function Add-TeamImportLine {
        $relativePath = 'CLAUDE.md'
        $targetPath = Join-Path $targetRoot $relativePath

        if (-not (Test-Path -LiteralPath $targetPath)) {
            Write-TargetText -RelativePath $relativePath -Content ($teamImportLine + "`n")
            return
        }

        if (Test-HasTeamImportLine -Path $targetPath) {
            Write-Host "Unchanged $relativePath"
            return
        }

        $existingBytes = [System.IO.File]::ReadAllBytes($targetPath)
        $isUtf32LittleEndian = $existingBytes.Length -ge 4 -and $existingBytes[0] -eq 0xFF -and $existingBytes[1] -eq 0xFE -and $existingBytes[2] -eq 0 -and $existingBytes[3] -eq 0
        $isUtf32BigEndian = $existingBytes.Length -ge 4 -and $existingBytes[0] -eq 0 -and $existingBytes[1] -eq 0 -and $existingBytes[2] -eq 0xFE -and $existingBytes[3] -eq 0xFF
        if ($isUtf32LittleEndian -or $isUtf32BigEndian) {
            Write-Warning "$targetPath uses UTF-32, which this script does not edit. Add the line $teamImportLine to the file by hand."
            return
        }

        $linkTarget = (Get-Item -LiteralPath $targetPath).ResolveLinkTarget($true)
        $writePath = if ($linkTarget) { $linkTarget.FullName } else { $targetPath }

        if (-not $PSCmdlet.ShouldProcess($writePath, 'Add team import line')) { return }

        $preambleLength = 0
        $encoding = [System.Text.UTF8Encoding]::new($false)
        if ($existingBytes.Length -ge 3 -and $existingBytes[0] -eq 0xEF -and $existingBytes[1] -eq 0xBB -and $existingBytes[2] -eq 0xBF) {
            $preambleLength = 3
        } elseif ($existingBytes.Length -ge 2 -and $existingBytes[0] -eq 0xFF -and $existingBytes[1] -eq 0xFE) {
            $preambleLength = 2
            $encoding = [System.Text.UnicodeEncoding]::new($false, $false)
        } elseif ($existingBytes.Length -ge 2 -and $existingBytes[0] -eq 0xFE -and $existingBytes[1] -eq 0xFF) {
            $preambleLength = 2
            $encoding = [System.Text.UnicodeEncoding]::new($true, $false)
        }

        $existingText = $encoding.GetString($existingBytes, $preambleLength, $existingBytes.Length - $preambleLength)
        $newline = if ($existingText.Contains("`r`n")) { "`r`n" } else { "`n" }
        $importBytes = $encoding.GetBytes($teamImportLine + $newline)

        $combinedBytes = [byte[]]::new($existingBytes.Length + $importBytes.Length)
        [System.Array]::Copy($existingBytes, 0, $combinedBytes, 0, $preambleLength)
        [System.Array]::Copy($importBytes, 0, $combinedBytes, $preambleLength, $importBytes.Length)
        [System.Array]::Copy($existingBytes, $preambleLength, $combinedBytes, $preambleLength + $importBytes.Length, $existingBytes.Length - $preambleLength)

        Write-BytesBesideTarget -Path $writePath -Bytes $combinedBytes
        Write-Host "Added the team import line to $relativePath"
    }

    function Get-SettingsContent {
        param([string]$SourcePath, [string]$TargetPath, [string]$OutputStyle)

        $teamSettingsText = (Get-Content -LiteralPath $SourcePath -Raw).Replace($placeholder, $targetRootForwardSlashes).Replace($repoPlaceholder, $repoRootForwardSlashes)
        $teamSettings = $teamSettingsText | ConvertFrom-Json -AsHashtable
        if ($SkipStatusLine) { $teamSettings.Remove('statusLine') }
        if ($SkipAutoUpdate) { $teamSettings['hooks'].Remove('SessionStart') }
        if ($OutputStyle) { $teamSettings['outputStyle'] = $OutputStyle }

        $existingText = $null
        if (Test-Path -LiteralPath $TargetPath) { $existingText = Get-Content -LiteralPath $TargetPath -Raw }

        if ([string]::IsNullOrWhiteSpace($existingText)) {
            if ($SkipStatusLine -or $SkipAutoUpdate -or $OutputStyle) { return ($teamSettings | ConvertTo-Json -Depth 20) + "`n" }
            return $teamSettingsText
        }

        try {
            $existingSettings = $existingText | ConvertFrom-Json -AsHashtable
        } catch {
            throw "The existing settings file '$TargetPath' is not valid JSON. Fix or remove it, then run the installer again. $($_.Exception.Message)"
        }

        $existingNormalized = $existingSettings | ConvertTo-Json -Depth 20
        $mergedSettings = Merge-Settings -Existing $existingSettings -Team $teamSettings
        if ($OutputStyle) { $mergedSettings['outputStyle'] = $OutputStyle }
        $mergedNormalized = $mergedSettings | ConvertTo-Json -Depth 20
        if ($mergedNormalized -eq $existingNormalized) { return $existingText }
        return $mergedNormalized + "`n"
    }

    function Read-SettingsFile {
        param([string]$Path)

        if (-not (Test-Path -LiteralPath $Path)) { return $null }
        $text = Get-Content -LiteralPath $Path -Raw
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        return $text | ConvertFrom-Json -AsHashtable
    }

    function Get-OutputStylePlan {
        $plan = [pscustomobject]@{ Action = 'Skipped'; Value = $null }

        try {
            $settings = Read-SettingsFile -Path (Join-Path $targetRoot 'settings.json')
        } catch {
            Write-Warning "Cannot read outputStyle because 'settings.json' is not valid JSON. Fix the file to get the output style. $($_.Exception.Message)"
            return $plan
        }
        $currentValue = if ($settings -and $settings.Contains('outputStyle')) { [string]$settings['outputStyle'] }

        if ([string]::IsNullOrWhiteSpace($currentValue) -or $currentValue -cin 'default', 'Default') {
            $plan.Action = 'Set'
        } else {
            $plan.Action = 'Kept'
            $plan.Value = $currentValue
        }
        return $plan
    }

    if (-not (Test-Path -LiteralPath $targetRoot)) {
        if ($PSCmdlet.ShouldProcess($targetRoot, 'Create directory')) {
            New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
        }
    }

    $outputStyleName = (Select-String -LiteralPath (Join-Path $sourceRoot 'output-styles\audhd.md') -Pattern '^name:\s*(.+?)\s*$' |
        Select-Object -First 1).Matches[0].Groups[1].Value
    $outputStylePlan = if ($SkipOutputStyle) { [pscustomobject]@{ Action = 'Skipped'; Value = $null } } else { Get-OutputStylePlan }
    $outputStyleForSettingsJson = ''
    if ($outputStylePlan.Action -eq 'Set') { $outputStyleForSettingsJson = $outputStyleName }

    $excludedFiles = @()
    if ($SkipStatusLine) { $excludedFiles += 'statusline.ps1' }

    $sourceFiles = Get-ChildItem -LiteralPath $sourceRoot -Recurse -File
    $sourceRelativePaths = @($sourceFiles | ForEach-Object { [System.IO.Path]::GetRelativePath($sourceRoot, $_.FullName) })
    $installedFiles = [System.Collections.Generic.List[string]]::new()
    foreach ($sourceFile in $sourceFiles) {
        $relativePath = [System.IO.Path]::GetRelativePath($sourceRoot, $sourceFile.FullName)
        if ($relativePath -in $excludedFiles) {
            Write-Host "Skipped $relativePath"
            continue
        }

        $targetPath = Join-Path $targetRoot $relativePath
        $targetExists = Test-Path -LiteralPath $targetPath

        if ($relativePath -eq 'settings.json') {
            $settingsContent = Get-SettingsContent -SourcePath $sourceFile.FullName -TargetPath $targetPath -OutputStyle $outputStyleForSettingsJson
            if ($targetExists -and $settingsContent -ceq (Get-Content -LiteralPath $targetPath -Raw)) {
                Write-Host "Unchanged $relativePath"
                continue
            }
            Write-TargetText -RelativePath $relativePath -Content $settingsContent
            continue
        }

        $sourceHash = (Get-FileHash -LiteralPath $sourceFile.FullName).Hash
        $installedFiles.Add($relativePath)
        $targetHash = if ($targetExists) { (Get-FileHash -LiteralPath $targetPath).Hash }
        if ($targetHash -eq $sourceHash) {
            Write-Host "Unchanged $relativePath"
            continue
        }
        if ($PSCmdlet.ShouldProcess($targetPath, 'Copy file')) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $targetPath) -Force | Out-Null
            Copy-Item -LiteralPath $sourceFile.FullName -Destination $targetPath -Force
            Write-Host "Installed $relativePath"
        }
    }

    $shippedTopLevelNames = @($sourceRelativePaths | ForEach-Object { ($_ -split '[\\/]')[0] } | Select-Object -Unique)
    foreach ($previouslyShippedPath in $previousInstalledFiles) {
        if ($previouslyShippedPath -notin $sourceRelativePaths) {
            $topLevelName = ($previouslyShippedPath -split '[\\/]')[0]
            if ($topLevelName -notin $shippedTopLevelNames) {
                Write-Warning "Skipped the removal of '$previouslyShippedPath' because the team setup ships no top-level entry named '$topLevelName'."
                continue
            }
            Remove-TargetFile -RelativePath $previouslyShippedPath
        }
    }

    Add-TeamImportLine

    switch ($outputStylePlan.Action) {
        'Set' {
            $verb = if ($WhatIfPreference) { 'Would set' } else { 'Set' }
            Write-Host "$verb outputStyle to $outputStyleName in settings.json"
        }
        'Kept' { Write-Host "Kept outputStyle '$($outputStylePlan.Value)' from settings.json" }
        default { Write-Host 'Skipped outputStyle' }
    }

    if ($SkipMcp) {
        Write-Host 'Skipped MCP servers'
    } else {
        $mcpServers = Get-Content -LiteralPath $mcpConfigPath -Raw | ConvertFrom-Json -AsHashtable
        $claudeCli = Get-Command claude -ErrorAction SilentlyContinue
        foreach ($serverName in $mcpServers.Keys) {
            $server = $mcpServers[$serverName]
            $addArguments = @('mcp', 'add', '--transport', $server['type'], '--scope', 'user', $serverName, $server['url'])

            if (-not $claudeCli) {
                Write-Warning "The claude CLI was not found on PATH. Run this command to add the MCP server '$serverName': claude $($addArguments -join ' ')"
                continue
            }

            & claude mcp get $serverName *> $null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "MCP server '$serverName' already exists. Skipped."
                continue
            }

            if ($PSCmdlet.ShouldProcess($serverName, 'Add MCP server at user scope')) {
                & claude @addArguments
                if ($LASTEXITCODE -ne 0) {
                    $mcpFailureText = "claude mcp add failed for '$serverName' with exit code $LASTEXITCODE."
                    if ($PSCmdlet.ParameterSetName -eq 'Saved') {
                        Write-Warning $mcpFailureText
                        continue
                    }
                    throw $mcpFailureText
                }
                Write-Host "Added MCP server '$serverName'"
            }
        }
    }

    $savedSwitchNames = @(
        foreach ($switchName in 'SkipStatusLine', 'SkipMcp', 'SkipOutputStyle', 'SkipAutoUpdate') {
            if ((Get-Variable -Name $switchName).Value) { "-$switchName" }
        }
    )
    $newInstallState = [ordered]@{
        repoPath       = $PSScriptRoot
        switches        = [ordered]@{
            SkipStatusLine  = [bool]$SkipStatusLine
            SkipMcp         = [bool]$SkipMcp
            SkipOutputStyle = [bool]$SkipOutputStyle
            SkipAutoUpdate  = [bool]$SkipAutoUpdate
        }
        installedCommit = Get-InstalledCommit
        installedFiles  = $installedFiles.ToArray()
        lastRun         = [ordered]@{
            finishedUtc  = [DateTime]::UtcNow.ToString('o')
            removedFiles = $removedFiles.ToArray()
        }
    }
    Write-InstallState -State $newInstallState
    if (-not $WhatIfPreference) {
        $savedSwitchText = if ($savedSwitchNames.Count -gt 0) { $savedSwitchNames -join ' ' } else { 'none' }
        Write-Host "Saved switches: $savedSwitchText. update.ps1 uses these."
    }
} finally {
    if ($installLock) { $installLock.Dispose() }
}
