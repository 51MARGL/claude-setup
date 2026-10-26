param([string]$Mode)

$ErrorActionPreference = 'Stop'

$stateRoot = Join-Path $env:USERPROFILE '.claude\team-setup'
$gateDirectory = Join-Path $stateRoot 'codegraph-search-guard'
$logPath = Join-Path $stateRoot 'codegraph-search-guard.log'
$logRotationBytes = 1MB
$deniesBeforeOpen = 3
$staleGateDays = 7

$searchToolNames = @('Grep', 'Glob', 'Bash', 'PowerShell')
$commandPrefilterPattern = '(?i)grep|\brg\b|findstr|select-string|\bsls\b|\bfind\b|get-childitem|\bgci\b|\bdir\b|\bls\b|\bsed\b'
$searchCommandNames = @('grep', 'egrep', 'fgrep', 'rg', 'findstr', 'select-string', 'sls')
$directoryListingCommandNames = @('get-childitem', 'gci', 'dir', 'ls')
$patternSearchCommandNames = $searchCommandNames + 'sed'
$valueFlagNames = @('--include', '--exclude', '--exclude-dir', '--glob', '--iglob', '--type', '--type-not', '--max-count', '--context', '--after-context', '--before-context', '--max-depth', '--label', '--threads', '--encoding', '--color', '--colour', '-path', '-literalpath', '-include', '-exclude', '-context', '-encoding', '-filter')
$caseSensitiveValueFlagNames = @('-A', '-B', '-C', '-m', '-g', '-t', '-T', '-d', '-j')
$sedAddressPattern = '(?:^|[;{}\n])\s*(?:(?:\d+|\$)?\s*[,~+]?\s*)/((?:[^/\\]|\\.)*)/'
$symbolMinimumLength = 4
$filterFlagNames = @('--include', '--glob', '-g', '-t', '--type', '-include', '-filter')
$codeFilterTokens = @('cs', 'csharp', 'ts', 'tsx', 'typescript', 'js', 'jsx', 'javascript')
$extensionlessFileNames = @('Dockerfile', 'Makefile', 'Jenkinsfile', 'LICENSE', 'CODEOWNERS', 'README', 'NOTICE', 'CHANGELOG', 'Procfile', 'Gemfile', 'Rakefile', 'Vagrantfile', 'gradlew')
$findNameFlagNames = @('-name', '-iname', '-path', '-ipath', '-wholename', '-iwholename', '-regex', '-iregex')
$findPathFlagNames = @('-path', '-ipath', '-wholename', '-iwholename')
$findRegexFlagNames = @('-regex', '-iregex')
$findRegexCodePattern = '(?i)\\\.(cs|tsx?|jsx?)\b'
$exemptAgentTypes = @('git', 'devops', 'pr-reviewer', 'claude-code-guide', 'statusline-setup')

function Write-GuardLog {
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

function ConvertTo-CommandSegments {
    param([string]$CommandText)

    $segments = [System.Collections.Generic.List[object]]::new()
    $words = [System.Collections.Generic.List[string]]::new()
    $word = [System.Text.StringBuilder]::new()
    $hasWord = $false
    $openQuote = [char]0
    $afterPipe = $false

    for ($index = 0; $index -lt $CommandText.Length; $index++) {
        $character = $CommandText[$index]
        if ($openQuote -ne [char]0) {
            if ($character -eq $openQuote) { $openQuote = [char]0 } else { [void]$word.Append($character) }
            continue
        }
        if ($character -eq [char]39 -or $character -eq [char]34) {
            $openQuote = $character
            $hasWord = $true
            continue
        }
        $isSeparator = $character -in ';', '|', '&', "`n", "`r"
        if ([char]::IsWhiteSpace($character) -or $isSeparator) {
            if ($hasWord) {
                $words.Add($word.ToString())
                [void]$word.Clear()
                $hasWord = $false
            }
        }
        if ($isSeparator) {
            if ($words.Count -gt 0) {
                $segments.Add([pscustomobject]@{ Words = $words.ToArray(); AfterPipe = $afterPipe })
                $words.Clear()
            }
            $isDoubleOperator = $index + 1 -lt $CommandText.Length -and $CommandText[$index + 1] -eq $character -and $character -in '|', '&'
            $afterPipe = $character -eq '|' -and -not $isDoubleOperator
            if ($isDoubleOperator) { $index++ }
            continue
        }
        if (-not [char]::IsWhiteSpace($character)) {
            [void]$word.Append($character)
            $hasWord = $true
        }
    }
    if ($hasWord) { $words.Add($word.ToString()) }
    if ($words.Count -gt 0) {
        $segments.Add([pscustomobject]@{ Words = $words.ToArray(); AfterPipe = $afterPipe })
    }
    return $segments.ToArray()
}

function Get-CommandName {
    param([string]$Word)

    return ($Word -replace '^.*[\\/]', '' -replace '(?i)\.exe$', '').ToLowerInvariant()
}

function Get-SearchSegmentWords {
    param([object[]]$Segments)

    for ($segmentIndex = 0; $segmentIndex -lt $Segments.Count; $segmentIndex++) {
        $words = @($Segments[$segmentIndex].Words)
        $firstWordIndex = 0
        while ($firstWordIndex -lt $words.Count - 1 -and $words[$firstWordIndex] -match '^\w+=') { $firstWordIndex++ }
        $commandName = Get-CommandName $words[$firstWordIndex]
        $nextWord = if ($firstWordIndex + 1 -lt $words.Count) { Get-CommandName $words[$firstWordIndex + 1] } else { '' }

        if ($Segments[$segmentIndex].AfterPipe) {
            $isXargsSearch = $commandName -eq 'xargs' -and $nextWord -in 'grep', 'rg'
            $isListingSearch = $commandName -in 'select-string', 'sls' -and $segmentIndex -gt 0 -and
                (Get-CommandName @($Segments[$segmentIndex - 1].Words)[0]) -in $directoryListingCommandNames
            if ($isListingSearch) { return @($Segments[$segmentIndex - 1].Words) + $words }
            if ($isXargsSearch) { return $words }
            continue
        }
        $isGitGrep = $commandName -eq 'git' -and (
            $nextWord -eq 'grep' -or
            ($nextWord -eq '-c' -and $firstWordIndex + 3 -lt $words.Count -and (Get-CommandName $words[$firstWordIndex + 3]) -eq 'grep'))
        $isSedSearch = $commandName -eq 'sed' -and $null -ne (Get-SedAddressPattern -Words $words)
        if ($commandName -in $searchCommandNames -or $isGitGrep -or $isSedSearch) { return $words }
    }
    return $null
}

function Get-FileNameSearch {
    param([object[]]$Segments, [string]$ToolName)

    foreach ($segment in $Segments) {
        if ($segment.AfterPipe) { continue }
        $words = @($segment.Words)
        $firstWordIndex = 0
        while ($firstWordIndex -lt $words.Count - 1 -and $words[$firstWordIndex] -match '^\w+=') { $firstWordIndex++ }
        $commandName = Get-CommandName $words[$firstWordIndex]
        $namePatterns = [System.Collections.Generic.List[string]]::new()

        if ($commandName -eq 'find') {
            $isDirectorySearch = $false
            $isCodeRegexSearch = $false
            for ($wordIndex = $firstWordIndex + 1; $wordIndex -lt $words.Count; $wordIndex++) {
                $hasNextWord = $wordIndex + 1 -lt $words.Count
                $flagName = $words[$wordIndex].ToLowerInvariant()
                if ($hasNextWord -and $flagName -in $findNameFlagNames) {
                    $flagValue = $words[$wordIndex + 1]
                    if ($flagName -in $findRegexFlagNames) {
                        if ($flagValue -match $findRegexCodePattern) { $isCodeRegexSearch = $true }
                    } elseif ($flagName -notin $findPathFlagNames -or $flagValue -match '[*?]') {
                        $namePatterns.Add($flagValue)
                    }
                    $wordIndex++
                } elseif ($hasNextWord -and $words[$wordIndex] -eq '-type' -and $words[$wordIndex + 1] -eq 'd') {
                    $isDirectorySearch = $true
                }
            }
            if ($isDirectorySearch) { continue }
            if ($isCodeRegexSearch) { return $commandName }
        } elseif ($commandName -in $directoryListingCommandNames) {
            $isDirectorySearch = $false
            $isRecursive = $false
            for ($wordIndex = $firstWordIndex + 1; $wordIndex -lt $words.Count; $wordIndex++) {
                $word = $words[$wordIndex]
                if ($word -match '(?i)^-(filt(e(r)?)?|inc(l(u(d(e)?)?)?)?)$') {
                    if ($wordIndex + 1 -lt $words.Count) { $namePatterns.Add($words[$wordIndex + 1]) }
                    $wordIndex++
                } elseif ($word -match '(?i)^-ex(c(l(u(d(e)?)?)?)?)?$') {
                    $wordIndex++
                } elseif ($word -match '(?i)^-(ad|dir(e(c(t(o(r(y)?)?)?)?)?)?)$') {
                    $isDirectorySearch = $true
                } elseif ($ToolName -eq 'PowerShell' -and $word -match '(?i)^-r(e(c(u(r(s(e)?)?)?)?)?)?$') {
                    $isRecursive = $true
                } elseif ($ToolName -ne 'PowerShell' -and $word -cmatch '^-[A-Za-z]*R') {
                    $isRecursive = $true
                } elseif (-not $word.StartsWith('-') -and $word -match '[*?]') {
                    $namePatterns.Add($word)
                    if ($word.Contains('**')) { $isRecursive = $true }
                }
            }
            if ($isDirectorySearch -or -not $isRecursive) { continue }
        } else {
            continue
        }

        foreach ($namePattern in $namePatterns) {
            if (Test-NamePatternIsCodeSearch -NamePattern $namePattern) { return $commandName }
        }
    }
    return $null
}

function Get-ShellFilterValues {
    param([string[]]$Words)

    $filterValues = [System.Collections.Generic.List[string]]::new()
    for ($wordIndex = 1; $wordIndex -lt $Words.Count; $wordIndex++) {
        $word = $Words[$wordIndex]
        $attachedMatch = [regex]::Match($word, '^(--[A-Za-z]+)=(.*)$')
        if ($attachedMatch.Success -and $attachedMatch.Groups[1].Value.ToLowerInvariant() -in $filterFlagNames) {
            $filterValues.Add($attachedMatch.Groups[2].Value)
        } elseif ($word.ToLowerInvariant() -in $filterFlagNames -and $wordIndex + 1 -lt $Words.Count) {
            $filterValues.Add($Words[$wordIndex + 1])
            $wordIndex++
        } elseif ($word -match '\*\.') {
            $filterValues.Add($word)
        }
    }
    return $filterValues.ToArray()
}

function Test-FiltersAllowCode {
    param([string[]]$FilterValues)

    if ($FilterValues.Count -eq 0) { return $true }
    foreach ($filterValue in $FilterValues) {
        foreach ($filterToken in [regex]::Matches($filterValue, '[A-Za-z0-9]+')) {
            if ($filterToken.Value.ToLowerInvariant() -in $codeFilterTokens) { return $true }
        }
    }
    return $false
}

function Test-NamePatternStartsWithClassName {
    param([string]$NamePattern)

    $fileName = $NamePattern -replace '^.*[\\/]', ''
    return $fileName -match '^[A-Za-z0-9_-]*[A-Za-z][A-Za-z0-9_-]*'
}

function Test-NamePatternIsCodeSearch {
    param([string]$NamePattern)

    $fileName = $NamePattern -replace '^.*[\\/]', ''
    if ($fileName -notmatch '[A-Za-z0-9]') { return $false }
    if ($fileName.Replace('*', '').Replace('?', '') -in $extensionlessFileNames) { return $false }
    $lastDotIndex = $fileName.LastIndexOf('.')
    if ($lastDotIndex -lt 0) { return $true }
    if ($lastDotIndex -eq 0) { return $false }
    $extensionText = $fileName.Substring($lastDotIndex + 1)
    if ($extensionText -notmatch '[A-Za-z0-9]') { return $true }
    foreach ($extensionToken in [regex]::Matches($extensionText, '[A-Za-z0-9]+')) {
        if ($extensionToken.Value.ToLowerInvariant() -in $codeFilterTokens) { return $true }
    }
    return $false
}

function Get-GrepToolFilterValues {
    param($ToolInput, [string]$WorkingDirectory)

    $filterValues = [System.Collections.Generic.List[string]]::new()
    foreach ($propertyName in 'glob', 'type') {
        $propertyValue = [string]$ToolInput.$propertyName
        if ($propertyValue) { $filterValues.Add($propertyValue) }
    }
    $searchPath = [string]$ToolInput.path
    $isNetworkPath = $searchPath -match '^(\\\\|//)'
    if ($searchPath -match '\.[A-Za-z0-9]+$' -and -not $isNetworkPath) {
        $repoRoot = Get-RepoRoot -WorkingDirectory $WorkingDirectory
        if ($repoRoot -and (Test-PathInsideRoot -Path $searchPath -Root $repoRoot -WorkingDirectory $WorkingDirectory)) {
            $fullPath = [System.IO.Path]::GetFullPath($searchPath, $WorkingDirectory)
            if (Test-Path -LiteralPath $fullPath -PathType Leaf) { $filterValues.Add([System.IO.Path]::GetExtension($fullPath)) }
        }
    }
    return $filterValues.ToArray()
}

function Get-RepoRoot {
    param([string]$WorkingDirectory)

    $repoRoot = $WorkingDirectory
    while ($repoRoot -and -not (Test-Path -LiteralPath (Join-Path $repoRoot '.git'))) {
        $repoRoot = Split-Path -Parent $repoRoot
    }
    return $repoRoot
}

function Test-PathInsideRoot {
    param([string]$Path, [string]$Root, [string]$WorkingDirectory)

    $fullPath = [System.IO.Path]::GetFullPath($Path, $WorkingDirectory).TrimEnd('\')
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
    return $fullPath -ieq $fullRoot -or $fullPath.StartsWith($fullRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-SedAddressPattern {
    param([string[]]$Words)

    $commandIndex = 0
    while ($commandIndex -lt $Words.Count -and (Get-CommandName $Words[$commandIndex]) -ne 'sed') { $commandIndex++ }
    $scripts = [System.Collections.Generic.List[string]]::new()
    $positionalWords = [System.Collections.Generic.List[string]]::new()
    for ($wordIndex = $commandIndex + 1; $wordIndex -lt $Words.Count; $wordIndex++) {
        $word = $Words[$wordIndex]
        if ($word -cmatch '^(--in-place(=.*)?|-[A-Za-z]*i.*)$') { return $null }
        if ($word -cmatch '^(--file(=.*)?|-[A-Za-z]*f)$') { return $null }
        if ($word -match '^--expression=(.*)$') {
            $scripts.Add($Matches[1])
        } elseif ($word -ceq '--expression' -or $word -cmatch '^-[A-Za-z]*e$') {
            if ($wordIndex + 1 -lt $Words.Count) { $scripts.Add($Words[$wordIndex + 1]) }
            $wordIndex++
        } elseif (-not $word.StartsWith('-')) {
            $positionalWords.Add($word)
        }
    }
    if ($scripts.Count -eq 0 -and $positionalWords.Count -gt 0) { $scripts.Add($positionalWords[0]) }
    foreach ($script in $scripts) {
        $addressMatch = [regex]::Match($script, $sedAddressPattern)
        if ($addressMatch.Success) { return $addressMatch.Groups[1].Value }
    }
    return $null
}

function Get-ShellSearchPattern {
    param([string[]]$Words)

    $commandIndex = 0
    while ($commandIndex -lt $Words.Count -and (Get-CommandName $Words[$commandIndex]) -notin $patternSearchCommandNames) { $commandIndex++ }
    if ($commandIndex -ge $Words.Count) { return $null }
    if ((Get-CommandName $Words[$commandIndex]) -eq 'sed') { return Get-SedAddressPattern -Words $Words }

    $explicitPatterns = [System.Collections.Generic.List[string]]::new()
    $firstPositionalWord = $null
    $patternComesFromFile = $false
    $afterDoubleDash = $false
    for ($wordIndex = $commandIndex + 1; $wordIndex -lt $Words.Count; $wordIndex++) {
        $word = $Words[$wordIndex]
        $hasNextWord = $wordIndex + 1 -lt $Words.Count
        if ($afterDoubleDash) {
            if ($null -eq $firstPositionalWord) { $firstPositionalWord = $word }
        } elseif ($word -eq '--') {
            $afterDoubleDash = $true
        } elseif ($word -match '^--regexp=(.*)$' -or $word -match '(?i)^/c:(.*)$') {
            $explicitPatterns.Add($Matches[1])
        } elseif ($word -ceq '-e' -or $word -eq '--regexp' -or $word -match '(?i)^-patt(e(r(n)?)?)?$') {
            if ($hasNextWord) { $explicitPatterns.Add($Words[$wordIndex + 1]) }
            $wordIndex++
        } elseif ($word -ceq '-f' -or $word -eq '--file') {
            $patternComesFromFile = $true
            $wordIndex++
        } elseif ($word -cin $caseSensitiveValueFlagNames -or $word.ToLowerInvariant() -in $valueFlagNames) {
            $wordIndex++
        } elseif ($word.StartsWith('-') -or $word -match '^/[A-Za-z](:.*)?$') {
            continue
        } elseif ($null -eq $firstPositionalWord) {
            $firstPositionalWord = $word
        }
    }
    if ($explicitPatterns.Count -gt 0) { return $explicitPatterns -join '|' }
    if ($patternComesFromFile) { return $null }
    return $firstPositionalWord
}

function Get-SymbolNames {
    param([string]$Pattern)

    $symbolNames = [System.Collections.Generic.List[string]]::new()
    foreach ($alternative in ($Pattern -split '\\\||\|')) {
        $name = $alternative -replace '\\b|\\<|\\>', '' -replace '^\^|\$$', '' -replace '^\\\.', '' -replace '(\\\(|\()$', ''
        if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$' -or $name.Length -lt $symbolMinimumLength) { return @() }
        $hasMixedCase = $name -cmatch '[a-z]' -and $name -cmatch '[A-Z]'
        if (-not ($hasMixedCase -or $name -match '[A-Za-z]_[A-Za-z]')) { return @() }
        if ($name -cnotin $symbolNames) { $symbolNames.Add($name) }
    }
    return $symbolNames.ToArray()
}

function Get-SafeName {
    param([string]$Value)

    return $Value -replace '[^A-Za-z0-9._-]', '_'
}

function Get-DenyCount {
    param([string]$DenyCountPath)

    $parsedCount = 0
    if ((Test-Path -LiteralPath $DenyCountPath) -and [int]::TryParse((Get-Content -LiteralPath $DenyCountPath -Raw).Trim(), [ref]$parsedCount)) { return $parsedCount }
    return 0
}

try {
    [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
    $payloadText = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($payloadText)) { exit 0 }
    if ($Mode -eq 'pre' -and $payloadText -notmatch '"tool_name"\s*:\s*"(Grep|Glob)"' -and $payloadText -notmatch $commandPrefilterPattern) { exit 0 }
    $payload = $payloadText | ConvertFrom-Json
    if (-not $payload) { exit 0 }

    $sessionId = [string]$payload.session_id
    if ([string]::IsNullOrWhiteSpace($sessionId)) { exit 0 }
    $agentId = [string]$payload.agent_id
    $gateKey = '{0}-{1}' -f (Get-SafeName $sessionId), $(if ($agentId) { Get-SafeName $agentId } else { 'main' })
    $openMarkerPath = Join-Path $gateDirectory ($gateKey + '.open')
    $denyCountPath = Join-Path $gateDirectory ($gateKey + '.denies')
    $symbolDeniesPath = Join-Path $gateDirectory ($gateKey + '.symbol-denies')
    $symbolsDeniedPath = Join-Path $gateDirectory ($gateKey + '.symbols-denied')
    $symbolsExploredPath = Join-Path $gateDirectory ($gateKey + '.symbols-explored')

    if ($Mode -eq 'post') {
        New-Item -ItemType Directory -Path $gateDirectory -Force | Out-Null
        New-Item -ItemType File -Path $openMarkerPath -Force | Out-Null
        if (Test-Path -LiteralPath $symbolsDeniedPath) {
            Add-Content -LiteralPath $symbolsExploredPath -Value (Get-Content -LiteralPath $symbolsDeniedPath) -Encoding utf8NoBOM
            Remove-Item -LiteralPath $symbolsDeniedPath -Force
        }
        Remove-Item -LiteralPath $symbolDeniesPath -Force -ErrorAction SilentlyContinue
        exit 0
    }
    if ($Mode -ne 'pre') { exit 0 }

    $toolName = [string]$payload.tool_name
    if ($toolName -notin $searchToolNames) { exit 0 }
    $workingDirectory = [string]$payload.cwd
    if ([string]::IsNullOrWhiteSpace($workingDirectory)) { exit 0 }
    $toolInput = $payload.tool_input

    $toolSearchPath = ''
    $contentPattern = $null
    if ($toolName -eq 'Grep') {
        $contentPattern = [string]$toolInput.pattern
        $filterValues = Get-GrepToolFilterValues -ToolInput $toolInput -WorkingDirectory $workingDirectory
        if (-not (Test-FiltersAllowCode -FilterValues $filterValues)) { exit 0 }
        $toolSearchPath = [string]$toolInput.path
        $searchCommandWord = 'Grep'
    } elseif ($toolName -eq 'Glob') {
        $globPattern = [string]$toolInput.pattern
        if (Test-NamePatternStartsWithClassName -NamePattern $globPattern) { exit 0 }
        if (-not (Test-NamePatternIsCodeSearch -NamePattern $globPattern)) { exit 0 }
        $toolSearchPath = [string]$toolInput.path
        $searchCommandWord = 'Glob'
    } else {
        $commandText = [string]$toolInput.command
        if ($commandText -notmatch $commandPrefilterPattern) { exit 0 }
        $commandSegments = ConvertTo-CommandSegments -CommandText $commandText
        $searchWords = Get-SearchSegmentWords -Segments $commandSegments
        $searchCommandWord = $null
        if ($searchWords) {
            $filterValues = Get-ShellFilterValues -Words $searchWords
            if (Test-FiltersAllowCode -FilterValues $filterValues) {
                $searchCommandWord = $searchWords | ForEach-Object { Get-CommandName $_ } | Where-Object { $_ -in $patternSearchCommandNames } | Select-Object -First 1
                if (-not $searchCommandWord) { $searchCommandWord = 'search' }
                $contentPattern = Get-ShellSearchPattern -Words $searchWords
            }
        }
        if (-not $searchCommandWord) {
            $searchCommandWord = Get-FileNameSearch -Segments $commandSegments -ToolName $toolName
            if (-not $searchCommandWord) { exit 0 }
        }
    }

    $agentType = [string]$payload.agent_type
    if ($agentType -in $exemptAgentTypes) { exit 0 }

    if (-not (Get-Command codegraph.cmd -CommandType Application -ErrorAction SilentlyContinue)) { exit 0 }
    $repoRoot = Get-RepoRoot -WorkingDirectory $workingDirectory
    if (-not $repoRoot) { exit 0 }
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.codegraph\codegraph.db'))) { exit 0 }
    if ($toolSearchPath -and -not (Test-PathInsideRoot -Path $toolSearchPath -Root $repoRoot -WorkingDirectory $workingDirectory)) { exit 0 }

    $symbolNames = if ($contentPattern) { @(Get-SymbolNames -Pattern $contentPattern) } else { @() }
    $blockedSymbolNames = $symbolNames
    if (Test-Path -LiteralPath $openMarkerPath) {
        if ($symbolNames.Count -eq 0) { exit 0 }
        $exploredSymbolNames = if (Test-Path -LiteralPath $symbolsExploredPath) { @(Get-Content -LiteralPath $symbolsExploredPath) } else { @() }
        $blockedSymbolNames = @($symbolNames | Where-Object { $_ -cnotin $exploredSymbolNames })
        if ($blockedSymbolNames.Count -eq 0) { exit 0 }
        $activeDenyCountPath = $symbolDeniesPath
    } else {
        $activeDenyCountPath = $denyCountPath
    }
    $isSymbolDeny = $blockedSymbolNames.Count -gt 0
    $previousDenies = Get-DenyCount -DenyCountPath $activeDenyCountPath
    if ($previousDenies -ge $deniesBeforeOpen) { exit 0 }

    New-Item -ItemType Directory -Path $gateDirectory -Force | Out-Null
    $staleLimit = (Get-Date).AddDays(-$staleGateDays)
    Get-ChildItem -LiteralPath $gateDirectory -File |
        Where-Object { $_.LastWriteTime -lt $staleLimit } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    $remainingDenies = $deniesBeforeOpen - $previousDenies - 1
    [System.IO.File]::WriteAllText($activeDenyCountPath, [string]($previousDenies + 1), [System.Text.UTF8Encoding]::new($false))
    if ($isSymbolDeny) {
        Add-Content -LiteralPath $symbolsDeniedPath -Value $blockedSymbolNames -Encoding utf8NoBOM
    }

    $logWord = if ($isSymbolDeny) { "$searchCommandWord symbol" } else { $searchCommandWord }
    Write-GuardLog 'INFO' ('Denied {0} for agent type "{1}": {2}' -f $toolName, $agentType, $logWord)

    $denyReason = 'This repo has a CodeGraph index. Call the `codegraph_explore` tool first to find a symbol, its callers, or its usages. If the tool is deferred, load it with ToolSearch `select:mcp__codegraph__codegraph_explore`. Do not repeat the blocked search with Glob, find, Get-ChildItem, or another tool.'
    if ($isSymbolDeny) {
        $denyReason += " This hook blocked a search for these symbol names: $($blockedSymbolNames -join ', '). Call ``codegraph_explore`` with these names. Add the file names when you know them. After one CodeGraph call, a search for the same names runs."
        $denyReason += if ($remainingDenies -gt 0) { " After $remainingDenies more blocked symbol searches, this hook lets the next symbol search run." } else { ' This hook lets the next symbol search run.' }
    } else {
        $denyReason += ' After one CodeGraph call, this hook lets a search for text that is not a symbol name run. A search for a symbol name runs only after a CodeGraph call for that name.'
        $denyReason += if ($remainingDenies -gt 0) { " After $remainingDenies more blocked searches, this hook lets all searches run." } else { ' This hook lets the next search run.' }
    }
    $hookOutput = @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = 'deny'
            permissionDecisionReason = $denyReason
        }
    }
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    Write-Output ($hookOutput | ConvertTo-Json -Depth 5 -Compress -EscapeHandling EscapeNonAscii)
} catch {
    Write-GuardLog 'ERROR' "$($_.Exception.Message) $($_.ScriptStackTrace)"
    exit 0
}
exit 0
