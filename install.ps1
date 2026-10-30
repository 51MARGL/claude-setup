#Requires -Version 7.2
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
$codeGraphPackage = '@colbymchenry/codegraph'
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

function Get-McpAddJsonArguments {
    param([string]$ServerName, [System.Collections.IDictionary]$Entry, [string]$ClaudePath)

    $entryJson = $Entry | ConvertTo-Json -Depth 10 -Compress
    $passingMode = (Get-Variable PSNativeCommandArgumentPassing -ErrorAction Ignore).Value
    $isBatchFile = $ClaudePath -match '\.(cmd|bat)$'
    if ($passingMode -notin 'Windows', 'Standard' -or ($passingMode -eq 'Windows' -and $isBatchFile)) {
        $entryJson = $entryJson.Replace('"', '\"')
    }
    return @('mcp', 'add-json', '--scope', 'user', $ServerName, $entryJson)
}

function Test-SameMcpDefinition {
    param([System.Collections.IDictionary]$Existing, [System.Collections.IDictionary]$Team)

    return $Existing['type'] -eq $Team['type'] -and
        $Existing['command'] -eq $Team['command'] -and
        (@($Existing['args']) -join "`n") -eq (@($Team['args']) -join "`n") -and
        ($null -eq $Existing['env'] -or ($Existing['env'] -is [System.Collections.IDictionary] -and $Existing['env'].Count -eq 0)) -and
        -not @($Existing.Keys | Where-Object { $_ -notin @('type', 'command', 'args', 'env', 'alwaysLoad') })
}

function Write-NpxWarning {
    param([string]$ServerName, [System.Collections.IDictionary]$Server)

    $serverArguments = @($Server['args'])
    $usesNpx = $Server['type'] -eq 'stdio' -and (
        $Server['command'] -eq 'npx' -or
        ($serverArguments.Count -ge 2 -and $serverArguments[0] -eq '/c' -and $serverArguments[1] -eq 'npx'))
    if ($usesNpx -and -not (Get-Command npx -ErrorAction SilentlyContinue)) {
        Write-Warning "The MCP server '$ServerName' needs Node.js 18 or later, and npx was not found on PATH. The server is added, but it does not start until Node.js is installed."
    }
}

function New-ClaudeConfigMcpEntry {
    param([System.Collections.IDictionary]$Server)

    $entry = [ordered]@{ type = $Server['type'] }
    if ($Server['alwaysLoad'] -eq $true) {
        if ($Server['type'] -eq 'stdio') {
            $entry['command'] = $Server['command']
            $entry['args'] = @($Server['args'])
        } else {
            $entry['url'] = $Server['url']
        }
        $entry['alwaysLoad'] = $true
    } elseif ($Server['type'] -eq 'stdio') {
        $entry['command'] = $Server['command']
        $entry['args'] = @($Server['args'])
        $entry['env'] = @{}
    } else {
        $entry['url'] = $Server['url']
    }
    return , [System.Text.Json.Nodes.JsonNode]::Parse(($entry | ConvertTo-Json -Depth 10 -Compress))
}

function Merge-TeamMcpServersIntoClaudeConfig {
    param(
        [string]$ConfigText,
        [System.Collections.IDictionary]$TeamServers,
        [string[]]$ServerNames,
        [string]$ConfigPath
    )

    $result = [pscustomobject]@{
        Text            = $null
        AddedNames      = [System.Collections.Generic.List[string]]::new()
        AlwaysLoadNames = [System.Collections.Generic.List[string]]::new()
        Messages        = [System.Collections.Generic.List[string]]::new()
        Warnings        = [System.Collections.Generic.List[string]]::new()
    }

    $root = [System.Text.Json.Nodes.JsonNode]::Parse($ConfigText)
    if ($root -isnot [System.Text.Json.Nodes.JsonObject]) {
        throw "The root of '$ConfigPath' is not a JSON object."
    }
    $hasServersNode = $root.ContainsKey('mcpServers')
    $serversNode = $null
    if ($hasServersNode) { $serversNode = $root['mcpServers'] }
    if ($hasServersNode -and $serversNode -isnot [System.Text.Json.Nodes.JsonObject]) {
        throw "The key mcpServers in '$ConfigPath' is not a JSON object."
    }

    foreach ($serverName in $ServerNames) {
        $server = $TeamServers[$serverName]
        if ($hasServersNode -and $serversNode.ContainsKey($serverName)) {
            if ($server['alwaysLoad'] -ne $true) {
                $result.Messages.Add("MCP server '$serverName' already exists. Skipped.")
                continue
            }
            $existingNode = $serversNode[$serverName]
            $existingServer = if ($null -ne $existingNode) { $existingNode.ToJsonString() | ConvertFrom-Json -AsHashtable } else { $null }
            if ($existingServer -isnot [System.Collections.IDictionary] -or $existingServer['alwaysLoad'] -eq $true) {
                $result.Messages.Add("MCP server '$serverName' already exists. Skipped.")
                continue
            }
            if (Test-SameMcpDefinition -Existing $existingServer -Team $server) {
                $existingNode['alwaysLoad'] = [System.Text.Json.Nodes.JsonNode]::Parse('true')
                $result.AlwaysLoadNames.Add($serverName)
            } else {
                $result.Warnings.Add("The MCP server '$serverName' exists with a different definition and has no alwaysLoad. The installer leaves it unchanged. To replace it, delete the entry '$serverName' from mcpServers in '$ConfigPath'. Then run install.ps1 again.")
            }
            continue
        }

        if (-not $hasServersNode) {
            $serversNode = [System.Text.Json.Nodes.JsonObject]::new()
            $root.Add('mcpServers', $serversNode)
            $hasServersNode = $true
        }
        $serversNode.Add($serverName, (New-ClaudeConfigMcpEntry -Server $server))
        $result.AddedNames.Add($serverName)
    }

    if ($result.AddedNames.Count -gt 0 -or $result.AlwaysLoadNames.Count -gt 0) {
        $serializerOptions = [System.Text.Json.JsonSerializerOptions]::new()
        $serializerOptions.WriteIndented = $true
        $serializerOptions.Encoder = [System.Text.Encodings.Web.JavaScriptEncoder]::UnsafeRelaxedJsonEscaping
        $text = $root.ToJsonString($serializerOptions).Replace("`r`n", "`n")
        if ($ConfigText.EndsWith("`n")) { $text += "`n" }
        $result.Text = $text
    }
    return $result
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

$installCompleted = $false
$installLock = $null
if (-not $WhatIfPreference) {
    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    try {
        $installLock = [System.IO.File]::Open((Join-Path $stateRoot 'update.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    } catch [System.IO.IOException] {
        throw 'Another install or update runs. Try again in a minute.'
    }
}

$installedFiles = $null
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

    function Remove-TeamUpdateHook {
        param([System.Collections.IDictionary]$TeamSettings, [string]$UpdateScriptPath)

        $keptGroups = @(foreach ($group in @($TeamSettings['hooks']['SessionStart'])) {
            $group['hooks'] = @(@($group['hooks']) | Where-Object { @($_['args'])[-1] -ne $UpdateScriptPath })
            if ($group['hooks'].Count -gt 0) { $group }
        })
        if ($keptGroups.Count -gt 0) { $TeamSettings['hooks']['SessionStart'] = $keptGroups } else { $TeamSettings['hooks'].Remove('SessionStart') }
    }

    function Merge-Settings {
        param([System.Collections.IDictionary]$Existing, [System.Collections.IDictionary]$Team)

        $merged = $Existing

        if ($Team.Contains('permissions')) {
            if (-not $merged.Contains('permissions')) { $merged['permissions'] = [ordered]@{} }
            foreach ($listName in 'allow', 'deny', 'ask') {
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

    function Write-ClaudeConfigMcpServers {
        param([string]$ConfigPath, [System.Collections.IDictionary]$TeamServers, [string[]]$ServerNames)

        if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
            Write-Warning "The claude CLI was not found on PATH, and '$ConfigPath' does not exist. Start Claude Code or Claude Desktop once, then run install.ps1 again."
            return
        }

        try {
            $configText = [System.IO.File]::ReadAllText($ConfigPath)
            if ([string]::IsNullOrWhiteSpace($configText)) {
                Write-Warning "The claude CLI was not found on PATH, and '$ConfigPath' is empty. Start Claude Code or Claude Desktop once, then run install.ps1 again."
                return
            }
            $merge = Merge-TeamMcpServersIntoClaudeConfig -ConfigText $configText -TeamServers $TeamServers -ServerNames $ServerNames -ConfigPath $ConfigPath
        } catch {
            Write-Warning "The claude CLI was not found on PATH, and the installer cannot change '$ConfigPath'. $($_.Exception.Message)"
            return
        }

        foreach ($message in $merge.Messages) { Write-Host $message }
        foreach ($warning in $merge.Warnings) { Write-Warning $warning }
        if ($null -eq $merge.Text) { return }
        foreach ($addedName in $merge.AddedNames) {
            Write-NpxWarning -ServerName $addedName -Server $TeamServers[$addedName]
        }
        if (-not $PSCmdlet.ShouldProcess($ConfigPath, 'Write MCP servers')) { return }

        $temporaryPath = $ConfigPath + '.team-setup.tmp'
        $backupPath = $ConfigPath + '.bak'
        try {
            try {
                Set-Content -LiteralPath $temporaryPath -Value $merge.Text -NoNewline -Encoding utf8NoBOM
                $currentText = [System.IO.File]::ReadAllText($ConfigPath)
                if ($currentText -cne $configText) {
                    $merge = Merge-TeamMcpServersIntoClaudeConfig -ConfigText $currentText -TeamServers $TeamServers -ServerNames $ServerNames -ConfigPath $ConfigPath
                    if ($null -eq $merge.Text) { return }
                    Set-Content -LiteralPath $temporaryPath -Value $merge.Text -NoNewline -Encoding utf8NoBOM
                    if ([System.IO.File]::ReadAllText($ConfigPath) -cne $currentText) {
                        Write-Warning "'$ConfigPath' changed during the write. The installer tries again at the next run."
                        return
                    }
                }
                Copy-Item -LiteralPath $ConfigPath -Destination $backupPath -Force
                Move-Item -LiteralPath $temporaryPath -Destination $ConfigPath -Force
            } finally {
                if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
            }
        } catch {
            $mcpFailureText = "The installer could not write the MCP servers to '$ConfigPath'. $($_.Exception.Message)"
            if ($PSCmdlet.ParameterSetName -eq 'Saved') {
                Write-Warning $mcpFailureText
                return
            }
            throw $mcpFailureText
        }

        foreach ($addedName in $merge.AddedNames) {
            Write-Host "Added MCP server '$addedName' to .claude.json. Restart Claude Code or Claude Desktop."
        }
        foreach ($alwaysLoadName in $merge.AlwaysLoadNames) {
            Write-Host "Set alwaysLoad on MCP server '$alwaysLoadName' in .claude.json. Restart Claude Code or Claude Desktop."
        }
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
        if ($SkipAutoUpdate) { Remove-TeamUpdateHook -TeamSettings $teamSettings -UpdateScriptPath ($repoRootForwardSlashes + '/update.ps1') }
        if ($OutputStyle) { $teamSettings['outputStyle'] = $OutputStyle }

        $existingText = $null
        if (Test-Path -LiteralPath $TargetPath) { $existingText = Get-Content -LiteralPath $TargetPath -Raw }

        if ([string]::IsNullOrWhiteSpace($existingText)) {
            if ($SkipStatusLine -or $SkipAutoUpdate -or $OutputStyle) { return ($teamSettings | ConvertTo-Json -Depth 100) + "`n" }
            return $teamSettingsText
        }

        try {
            $existingSettings = $existingText | ConvertFrom-Json -AsHashtable
        } catch {
            throw "The existing settings file '$TargetPath' is not valid JSON. Fix or remove it, then run the installer again. $($_.Exception.Message)"
        }

        $existingNormalized = $existingSettings | ConvertTo-Json -Depth 100
        $mergedSettings = Merge-Settings -Existing $existingSettings -Team $teamSettings
        if ($OutputStyle) { $mergedSettings['outputStyle'] = $OutputStyle }
        $mergedNormalized = $mergedSettings | ConvertTo-Json -Depth 100
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

    function Install-CodeGraph {
        if (Get-Command codegraph -CommandType Application -ErrorAction SilentlyContinue) {
            Write-Host 'CodeGraph is already installed. Skipped.'
            return
        }
        if ($PSCmdlet.ParameterSetName -eq 'Saved') {
            Write-Warning "CodeGraph is not installed. Run: npm i -g $codeGraphPackage@latest"
            return
        }
        $npmCommand = Get-Command npm.cmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $npmCommand) {
            Write-Warning "npm was not found on PATH. Install Node.js 18 or later. Then run: npm i -g $codeGraphPackage@latest"
            return
        }
        if ($PSCmdlet.ShouldProcess($codeGraphPackage, 'Install npm package globally')) {
            & $npmCommand.Source i -g "$codeGraphPackage@latest" | Out-Host
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "npm failed to install $codeGraphPackage. Exit code $LASTEXITCODE. Run: npm i -g $codeGraphPackage@latest"
                return
            }
            Write-Host 'Installed CodeGraph'
        }
    }

    if (-not (Test-Path -LiteralPath $targetRoot)) {
        if ($PSCmdlet.ShouldProcess($targetRoot, 'Create directory')) {
            New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
        }
    }

    $sourceFiles = Get-ChildItem -LiteralPath $sourceRoot -Recurse -File
    if (@($sourceFiles).Count -eq 0) { throw "'$sourceRoot' holds no file. The clone may be broken." }
    $sourceRelativePaths = @($sourceFiles | ForEach-Object { [System.IO.Path]::GetRelativePath($sourceRoot, $_.FullName) })

    $outputStyleName = $null
    if (-not $SkipOutputStyle) {
        $outputStyleName = (Select-String -LiteralPath (Join-Path $sourceRoot 'output-styles\audhd.md') -Pattern '^name:\s*(.+?)\s*$' |
            Select-Object -First 1).Matches[0].Groups[1].Value
    }
    $outputStylePlan = if ($SkipOutputStyle) { [pscustomobject]@{ Action = 'Skipped'; Value = $null } } else { Get-OutputStylePlan }
    $outputStyleForSettingsJson = ''
    if ($outputStylePlan.Action -eq 'Set') { $outputStyleForSettingsJson = $outputStyleName }

    $excludedFiles = @()
    if ($SkipStatusLine) { $excludedFiles += 'statusline.ps1' }

    $settingsContent = Get-SettingsContent -SourcePath (Join-Path $sourceRoot 'settings.json') -TargetPath (Join-Path $targetRoot 'settings.json') -OutputStyle $outputStyleForSettingsJson

    $mcpServers = $null
    if (-not $SkipMcp) {
        try {
            $mcpServers = Get-Content -LiteralPath $mcpConfigPath -Raw | ConvertFrom-Json -AsHashtable
        } catch {
            throw "The MCP config file '$mcpConfigPath' is not valid JSON. Fix it, then run the installer again. $($_.Exception.Message)"
        }
    }

    $installedFiles = [System.Collections.Generic.List[string]]::new()
    foreach ($sourceFile in $sourceFiles) {
        $relativePath = [System.IO.Path]::GetRelativePath($sourceRoot, $sourceFile.FullName)
        if ($relativePath -in $excludedFiles) {
            Write-Host "Skipped $relativePath"
            if ($relativePath -in $previousInstalledFiles) { $installedFiles.Add($relativePath) }
            continue
        }

        $targetPath = Join-Path $targetRoot $relativePath
        $targetExists = Test-Path -LiteralPath $targetPath

        if ($relativePath -eq 'settings.json') {
            if ($targetExists -and $settingsContent -ceq (Get-Content -LiteralPath $targetPath -Raw)) {
                Write-Host "Unchanged $relativePath"
                continue
            }
            Write-TargetText -RelativePath $relativePath -Content $settingsContent
            continue
        }

        $sourceHash = (Get-FileHash -LiteralPath $sourceFile.FullName).Hash
        $targetHash = if ($targetExists) { (Get-FileHash -LiteralPath $targetPath).Hash }
        if ($targetHash -eq $sourceHash) {
            Write-Host "Unchanged $relativePath"
            $installedFiles.Add($relativePath)
            continue
        }
        if ($PSCmdlet.ShouldProcess($targetPath, 'Copy file')) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $targetPath) -Force | Out-Null
            Copy-Item -LiteralPath $sourceFile.FullName -Destination $targetPath -Force
            $installedFiles.Add($relativePath)
            Write-Host "Installed $relativePath"
        }
    }

    foreach ($previouslyShippedPath in $previousInstalledFiles) {
        if ($previouslyShippedPath -isnot [string] -or [string]::IsNullOrWhiteSpace($previouslyShippedPath) -or [System.IO.Path]::IsPathRooted($previouslyShippedPath) -or $previouslyShippedPath.Contains('..') -or $previouslyShippedPath.Contains(':')) {
            Write-Warning "Skipped the saved path '$previouslyShippedPath' because it is not a relative path inside the target folder."
            continue
        }
        if ($previouslyShippedPath -notin $sourceRelativePaths) {
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
        Install-CodeGraph
        $claudeCli = Get-Command claude -ErrorAction SilentlyContinue | Select-Object -First 1
        $userClaudeConfigPath = Join-Path $env:USERPROFILE '.claude.json'
        $userClaudeConfigReadable = $true
        $existingServerNames = @()
        $existingServers = @{}
        if (Test-Path -LiteralPath $userClaudeConfigPath) {
            try {
                $userClaudeConfigText = Get-Content -LiteralPath $userClaudeConfigPath -Raw
                if (-not [string]::IsNullOrWhiteSpace($userClaudeConfigText)) {
                    $userClaudeConfig = $userClaudeConfigText | ConvertFrom-Json -AsHashtable
                    if ($userClaudeConfig -is [System.Collections.IDictionary] -and $userClaudeConfig['mcpServers'] -is [System.Collections.IDictionary]) {
                        $existingServers = $userClaudeConfig['mcpServers']
                        $existingServerNames = @($existingServers.Keys)
                    }
                }
            } catch {
                $userClaudeConfigReadable = $false
                Write-Warning "Cannot read '$userClaudeConfigPath'. The installer asks the claude CLI which MCP servers exist instead. $($_.Exception.Message)"
            }
        }
        $fallbackServerNames = [System.Collections.Generic.List[string]]::new()
        foreach ($serverName in $mcpServers.Keys) {
            $server = $mcpServers[$serverName]
            $wantsAlwaysLoad = $server['alwaysLoad'] -eq $true
            if ($wantsAlwaysLoad) {
                $addArguments = Get-McpAddJsonArguments -ServerName $serverName -Entry $server -ClaudePath $claudeCli.Source
            } elseif ($server['type'] -eq 'stdio') {
                $addArguments = @('mcp', 'add', '--transport', 'stdio', '--scope', 'user', $serverName, '--', $server['command']) + @($server['args'])
            } elseif ($server['type'] -eq 'http') {
                $addArguments = @('mcp', 'add', '--transport', $server['type'], '--scope', 'user', $serverName, $server['url'])
            } else {
                Write-Warning "MCP server '$serverName' has the unsupported type '$($server['type'])'. Skipped."
                continue
            }

            if (-not $claudeCli) {
                if ($PSCmdlet.ShouldProcess($serverName, 'Add MCP server at user scope') -or $WhatIfPreference) {
                    $fallbackServerNames.Add($serverName)
                }
                continue
            }

            if ($userClaudeConfigReadable) {
                $serverExists = $serverName -in $existingServerNames
            } else {
                & claude mcp get $serverName *> $null
                $serverExists = $LASTEXITCODE -eq 0
            }
            if ($serverExists) {
                if (-not $wantsAlwaysLoad) {
                    Write-Host "MCP server '$serverName' already exists. Skipped."
                    continue
                }
                if (-not $userClaudeConfigReadable) {
                    Write-Warning "The installer cannot read '$userClaudeConfigPath', so it cannot see if the MCP server '$serverName' has alwaysLoad. Skipped."
                    continue
                }
                $existingServer = $existingServers[$serverName]
                if ($existingServer -isnot [System.Collections.IDictionary] -or $existingServer['alwaysLoad'] -eq $true) {
                    Write-Host "MCP server '$serverName' already exists. Skipped."
                    continue
                }
                $sameDefinition = Test-SameMcpDefinition -Existing $existingServer -Team $server
                if (-not $sameDefinition) {
                    Write-Warning "The MCP server '$serverName' exists with a different definition and has no alwaysLoad. The installer leaves it unchanged. To replace it, run: claude mcp remove $serverName --scope user. Then run install.ps1 again."
                    continue
                }
                if ($PSCmdlet.ShouldProcess($serverName, 'Replace MCP server to set alwaysLoad')) {
                    & claude mcp remove $serverName --scope user
                    if ($LASTEXITCODE -ne 0) {
                        $mcpFailureText = "claude mcp remove failed for '$serverName' with exit code $LASTEXITCODE."
                        if ($PSCmdlet.ParameterSetName -eq 'Saved') {
                            Write-Warning $mcpFailureText
                            continue
                        }
                        throw $mcpFailureText
                    }
                    & claude @addArguments
                    if ($LASTEXITCODE -ne 0) {
                        $mcpFailureText = "claude mcp add-json failed for '$serverName' with exit code $LASTEXITCODE. The installer adds the old entry again."
                        & claude @(Get-McpAddJsonArguments -ServerName $serverName -Entry $existingServer -ClaudePath $claudeCli.Source)
                        if ($LASTEXITCODE -ne 0) {
                            $mcpFailureText += " The old entry was not restored. Add the MCP server '$serverName' again by hand."
                        }
                        if ($PSCmdlet.ParameterSetName -eq 'Saved') {
                            Write-Warning $mcpFailureText
                            continue
                        }
                        throw $mcpFailureText
                    }
                    Write-Host "Replaced MCP server '$serverName' to set alwaysLoad"
                }
                continue
            }

            Write-NpxWarning -ServerName $serverName -Server $server

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
        if (-not $claudeCli -and $fallbackServerNames.Count -gt 0) {
            Write-ClaudeConfigMcpServers -ConfigPath $userClaudeConfigPath -TeamServers $mcpServers -ServerNames $fallbackServerNames.ToArray()
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
    $installCompleted = $true
} finally {
    if (-not $installCompleted -and -not $WhatIfPreference -and $null -ne $installedFiles) {
        try {
            $recoveryFiles = [System.Collections.Generic.List[string]]::new()
            foreach ($recoveryPath in @($previousInstalledFiles) + @($installedFiles)) {
                if ($recoveryPath -notin $removedFiles -and $recoveryPath -notin $recoveryFiles) { $recoveryFiles.Add($recoveryPath) }
            }
            Write-InstallState -State ([ordered]@{
                repoPath        = $PSScriptRoot
                switches        = [ordered]@{
                    SkipStatusLine  = [bool]$SkipStatusLine
                    SkipMcp         = [bool]$SkipMcp
                    SkipOutputStyle = [bool]$SkipOutputStyle
                    SkipAutoUpdate  = [bool]$SkipAutoUpdate
                }
                installedCommit = if ($installState) { $installState['installedCommit'] }
                installedFiles  = $recoveryFiles.ToArray()
            })
        } catch {
            Write-Warning "Could not write the recovery install state. $($_.Exception.Message)"
        }
    }
    if ($installLock) { $installLock.Dispose() }
}
