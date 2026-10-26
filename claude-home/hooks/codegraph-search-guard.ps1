param([string]$Mode)

$ErrorActionPreference = 'Stop'

$scriptStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

$stateRoot = Join-Path $env:USERPROFILE '.claude\team-setup'
$gateDirectory = Join-Path $stateRoot 'codegraph-search-guard'
$logPath = Join-Path $stateRoot 'codegraph-search-guard.log'
$logRotationBytes = 1MB
$deniesBeforeOpen = 1
$staleGateDays = 7
$indexStatusTimeoutMilliseconds = 6000
$indexStatusBudgetMilliseconds = 8500
$unsafeIndexRootPattern = '[&|<>^%!(),;=\s"]'

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
$statementPrefixWords = @('{', '(', '!', 'if', 'while', 'until', 'do', 'then', 'else', 'elif', 'time', '%', '?', 'foreach', 'foreach-object', 'where-object')
$groupOpeningWords = @('!', '{', 'if', 'while', 'until', 'do', 'then', 'else', 'elif', 'time', 'foreach')
$directoryChangeCommandNames = @('cd', 'chdir', 'set-location', 'sl', 'pushd')
$blockOpenerNames = @('foreach-object', 'foreach', '%')
$powerShellValueFlagPattern = '(?i)^-(ea|erroraction|wa|warningaction|ia|informationaction|ev|errorvariable|ov|outvariable|pv|pipelinevariable|ob|outbuffer|attributes|encoding|de(p(t(h)?)?)?)$'
$uncPathPattern = '^(\\\\|//)'
$xargsValueFlagNames = @('--max-args', '--max-procs', '--delimiter', '--replace', '--max-lines', '--arg-file', '--eof')
$xargsCaseSensitiveValueFlagNames = @('-I', '-n', '-P', '-d', '-L', '-s', '-E', '-a')
$gitListFilesValueFlagNames = @('-x', '-X', '--exclude', '--exclude-from', '--exclude-per-directory', '--with-tree', '--format', '--abbrev')
$powerShellPathFlagPattern = '(?i)^-(pa(t(h)?)?|l(i(t(e(r(a(l(p(a(t(h)?)?)?)?)?)?)?)?)?)?)$'
$redirectionPattern = '^\d*>|^<'
$maxNamePatternParts = 32
$maxSearchPaths = 20
$indexedRootCache = @{}
$indexHasFilesByRoot = @{}

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
    $groupDepth = 0
    $wordBraceDepth = 0

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
        if ($character -eq '\' -and $index + 1 -lt $CommandText.Length -and $CommandText[$index + 1] -in '(', ')') {
            [void]$word.Append($character).Append($CommandText[$index + 1])
            $hasWord = $true
            $index++
            continue
        }
        $nextCharacter = if ($index + 1 -lt $CommandText.Length) { $CommandText[$index + 1] } else { [char]0 }
        $isGroupBoundary = $false
        if ($character -eq '(') {
            $lastWord = if ($words.Count -gt 0) { $words[$words.Count - 1] } else { $null }
            $followsExpansionSigil = $word.Length -gt 0 -and $word[$word.Length - 1] -in '$', '@'
            $startsStatement = -not $hasWord -and ($null -eq $lastWord -or $lastWord.EndsWith('=') -or $lastWord -in $groupOpeningWords)
            $isGroupBoundary = $followsExpansionSigil -or $startsStatement
            if ($isGroupBoundary) { $groupDepth++ }
        } elseif ($character -eq ')' -and $groupDepth -gt 0) {
            $isGroupBoundary = $true
            $groupDepth--
        } elseif ($character -eq '{') {
            $isGroupBoundary = -not $hasWord -and ($nextCharacter -eq [char]0 -or [char]::IsWhiteSpace($nextCharacter))
            if (-not $isGroupBoundary) { $wordBraceDepth++ }
        } elseif ($character -eq '}') {
            $isGroupBoundary = -not $hasWord -and $wordBraceDepth -eq 0
            if ($wordBraceDepth -gt 0) { $wordBraceDepth-- }
        }
        $isSeparator = $isGroupBoundary -or $character -in ';', '|', '&', "`n", "`r"
        if ([char]::IsWhiteSpace($character) -or $isSeparator) {
            if ($hasWord) {
                $words.Add($word.ToString())
                [void]$word.Clear()
                $hasWord = $false
            }
            $wordBraceDepth = 0
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

function Get-CommandWords {
    param([string[]]$Words)

    $startIndex = 0
    while ($startIndex -lt $Words.Count - 1) {
        $firstWord = $Words[$startIndex]
        if ($firstWord -match '^\w+=' -or $firstWord -in $statementPrefixWords) {
            $startIndex++
        } elseif ($firstWord -match '^\$\w+$' -and $Words[$startIndex + 1] -match '^[-+*/%]?=$') {
            $startIndex = [Math]::Min($startIndex + 2, $Words.Count - 1)
        } elseif ($firstWord -match '^\$\w+[-+*/%]?=(.+)$') {
            $assignedValue = $Matches[1]
            if ($startIndex + 1 -lt $Words.Count) { return @($assignedValue) + @($Words[($startIndex + 1)..($Words.Count - 1)]) }
            return @($assignedValue)
        } else {
            break
        }
    }
    return @($Words[$startIndex..($Words.Count - 1)])
}

function Get-XargsCommandName {
    param([string[]]$Words)

    for ($wordIndex = 1; $wordIndex -lt $Words.Count; $wordIndex++) {
        $word = $Words[$wordIndex]
        if ($word -cin $xargsCaseSensitiveValueFlagNames -or $word.ToLowerInvariant() -in $xargsValueFlagNames) {
            $wordIndex++
        } elseif (-not $word.StartsWith('-')) {
            return Get-CommandName $word
        }
    }
    return ''
}

function Get-BlockListingWords {
    param([object[]]$Segments, [int]$SegmentIndex)

    if ($SegmentIndex -lt 2 -or -not $Segments[$SegmentIndex - 1].AfterPipe) { return @() }
    $openerWords = @(Get-CommandWords -Words $Segments[$SegmentIndex - 1].Words)
    if ($openerWords.Count -ne 1 -or $openerWords[0] -notin $blockOpenerNames) { return @() }
    $listingWords = @(Get-CommandWords -Words $Segments[$SegmentIndex - 2].Words)
    if ((Get-CommandName $listingWords[0]) -in $directoryListingCommandNames) { return $listingWords }
    return @()
}

function Get-SearchSegmentWords {
    param([object[]]$Segments, [string[]]$SegmentDirectories)

    for ($segmentIndex = 0; $segmentIndex -lt $Segments.Count; $segmentIndex++) {
        $words = @(Get-CommandWords -Words $Segments[$segmentIndex].Words)
        $commandName = Get-CommandName $words[0]
        $nextWord = if ($words.Count -gt 1) { Get-CommandName $words[1] } else { '' }

        $isXargsSearch = $commandName -eq 'xargs' -and (Get-XargsCommandName -Words $words) -in 'grep', 'rg'
        if ($isXargsSearch) { return [pscustomobject]@{ Words = $words; PathWords = $words; Directory = $SegmentDirectories[$segmentIndex] } }
        if ($Segments[$segmentIndex].AfterPipe) {
            $listingWords = if ($segmentIndex -gt 0) { @(Get-CommandWords -Words $Segments[$segmentIndex - 1].Words) } else { @() }
            $isListingSearch = $commandName -in 'select-string', 'sls' -and $listingWords.Count -gt 0 -and
                (Get-CommandName $listingWords[0]) -in $directoryListingCommandNames
            if ($isListingSearch) {
                return [pscustomobject]@{ Words = $listingWords + $words; PathWords = $listingWords; Directory = $SegmentDirectories[$segmentIndex - 1] }
            }
            continue
        }
        $isGitGrep = $commandName -eq 'git' -and (
            $nextWord -eq 'grep' -or
            ($nextWord -eq '-c' -and 3 -lt $words.Count -and (Get-CommandName $words[3]) -eq 'grep'))
        $isSedSearch = $commandName -eq 'sed' -and $null -ne (Get-SedAddressPattern -Words $words)
        if ($commandName -in $searchCommandNames -or $isGitGrep -or $isSedSearch) {
            $blockListingWords = @(Get-BlockListingWords -Segments $Segments -SegmentIndex $segmentIndex)
            if ($blockListingWords.Count -gt 0) {
                return [pscustomobject]@{ Words = $blockListingWords + $words; PathWords = $blockListingWords; Directory = $SegmentDirectories[$segmentIndex - 2] }
            }
            return [pscustomobject]@{ Words = $words; PathWords = $words; Directory = $SegmentDirectories[$segmentIndex] }
        }
    }
    return $null
}

function Get-FileNameSearch {
    param([object[]]$Segments, [string]$ToolName, [string[]]$SegmentDirectories)

    for ($segmentIndex = 0; $segmentIndex -lt $Segments.Count; $segmentIndex++) {
        $segment = $Segments[$segmentIndex]
        if ($segment.AfterPipe) { continue }
        $words = @(Get-CommandWords -Words $segment.Words)
        $firstWordIndex = 0
        $commandName = Get-CommandName $words[0]
        $namePatterns = [System.Collections.Generic.List[string]]::new()
        $pathOperands = [System.Collections.Generic.List[string]]::new()
        $directory = $SegmentDirectories[$segmentIndex]
        $isCodeRegexSearch = $false

        if ($commandName -eq 'git') {
            $wordIndex = 1
            while ($wordIndex -lt $words.Count -and ($words[$wordIndex] -ceq '-C' -or $words[$wordIndex] -ceq '-c' -or $words[$wordIndex].StartsWith('--'))) {
                if ($words[$wordIndex] -ceq '-C' -and $wordIndex + 1 -lt $words.Count) { $pathOperands.Add($words[$wordIndex + 1]) }
                $wordIndex += if ($words[$wordIndex].StartsWith('--')) { 1 } else { 2 }
            }
            if ($wordIndex -ge $words.Count -or $words[$wordIndex] -cne 'ls-files') { continue }
            $afterDoubleDash = $false
            for ($wordIndex++; $wordIndex -lt $words.Count; $wordIndex++) {
                $word = $words[$wordIndex]
                if ($afterDoubleDash -or -not $word.StartsWith('-')) {
                    if (-not $word.StartsWith(':') -and ($word -replace '^.*[\\/]', '') -match '[*?.]') { $namePatterns.Add($word) }
                } elseif ($word -eq '--') {
                    $afterDoubleDash = $true
                } elseif ($word -cin $gitListFilesValueFlagNames) {
                    $wordIndex++
                }
            }
        } elseif ($commandName -eq 'find') {
            $isDirectorySearch = $false
            $operandIndex = 1
            while ($operandIndex -lt $words.Count -and $words[$operandIndex] -cmatch '^-(H|L|P|O\d?)$') { $operandIndex++ }
            while ($operandIndex -lt $words.Count -and $words[$operandIndex] -notmatch '^(-|!|\(|\\\()') {
                $pathOperands.Add($words[$operandIndex])
                $operandIndex++
            }
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
        } elseif ($commandName -in $directoryListingCommandNames) {
            $isDirectorySearch = $false
            $isRecursive = $false
            for ($wordIndex = $firstWordIndex + 1; $wordIndex -lt $words.Count; $wordIndex++) {
                $word = $words[$wordIndex]
                if ($word -match '(?i)^-(filt(e(r)?)?|inc(l(u(d(e)?)?)?)?)$') {
                    if ($wordIndex + 1 -lt $words.Count) { $namePatterns.Add($words[$wordIndex + 1]) }
                    $wordIndex++
                } elseif ($word -match '(?i)^-ex(c(l(u(d(e)?)?)?)?)?$' -or $word -match $powerShellValueFlagPattern) {
                    $wordIndex++
                } elseif ($ToolName -eq 'PowerShell' -and $word -match $powerShellPathFlagPattern) {
                    if ($wordIndex + 1 -lt $words.Count) { $pathOperands.AddRange([string[]]($words[$wordIndex + 1] -split ',')) }
                    $wordIndex++
                } elseif ($word -match '(?i)^-(ad|dir(e(c(t(o(r(y)?)?)?)?)?)?)$') {
                    $isDirectorySearch = $true
                } elseif ($ToolName -eq 'PowerShell' -and $word -match '(?i)^-r(e(c(u(r(s(e)?)?)?)?)?)?$') {
                    $isRecursive = $true
                } elseif ($ToolName -ne 'PowerShell' -and $word -cmatch '^-[A-Za-z]*R') {
                    $isRecursive = $true
                } elseif (-not $word.StartsWith('-')) {
                    $pathOperands.Add($word)
                    if ($word -match '[*?]') { $namePatterns.Add($word) }
                    if ($word.Contains('**')) { $isRecursive = $true }
                }
            }
            if ($isDirectorySearch -or -not $isRecursive) { continue }
        } else {
            continue
        }

        $searchPaths = @(Resolve-OperandPaths -Operands $pathOperands.ToArray() -Directory $directory)
        if ($isCodeRegexSearch) { return [pscustomobject]@{ CommandName = $commandName; SearchPaths = $searchPaths } }
        foreach ($namePattern in $namePatterns) {
            if (Test-NamePatternIsCodeSearch -NamePattern $namePattern) { return [pscustomobject]@{ CommandName = $commandName; SearchPaths = $searchPaths } }
        }
    }
    return $null
}

function Add-FilterValue {
    param($FilterValues, [string]$Value)

    $includedParts = @($Value -split '\s+' | Where-Object { $_ -and -not $_.StartsWith('!') })
    if ($includedParts.Count -gt 0) { $FilterValues.Add($includedParts -join ' ') }
}

function Get-ShellFilterValues {
    param([string[]]$Words)

    $filterValues = [System.Collections.Generic.List[string]]::new()
    for ($wordIndex = 1; $wordIndex -lt $Words.Count; $wordIndex++) {
        $word = $Words[$wordIndex]
        $attachedMatch = [regex]::Match($word, '^(--[A-Za-z]+)=(.*)$')
        if ($attachedMatch.Success -and $attachedMatch.Groups[1].Value.ToLowerInvariant() -in $filterFlagNames) {
            Add-FilterValue -FilterValues $filterValues -Value $attachedMatch.Groups[2].Value
        } elseif ($word.ToLowerInvariant() -in $filterFlagNames -and $wordIndex + 1 -lt $Words.Count) {
            Add-FilterValue -FilterValues $filterValues -Value $Words[$wordIndex + 1]
            $wordIndex++
        } elseif ($word -match '\*\.') {
            Add-FilterValue -FilterValues $filterValues -Value $word
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

function Expand-BraceAlternatives {
    param([string]$Text)

    $expandedTexts = [System.Collections.Generic.List[string]]::new()
    $pendingTexts = [System.Collections.Generic.Stack[string]]::new()
    $pendingTexts.Push($Text)
    while ($pendingTexts.Count -gt 0 -and $expandedTexts.Count + $pendingTexts.Count -le $maxNamePatternParts) {
        $currentText = $pendingTexts.Pop()
        $braceMatch = [regex]::Match($currentText, '\{([^{}]*,[^{}]*)\}')
        if (-not $braceMatch.Success -or $currentText.Length -gt 500) {
            $expandedTexts.Add($currentText)
            continue
        }
        $prefix = $currentText.Substring(0, $braceMatch.Index)
        $suffix = $currentText.Substring($braceMatch.Index + $braceMatch.Length)
        foreach ($alternative in $braceMatch.Groups[1].Value.Split(',')) { $pendingTexts.Push($prefix + $alternative + $suffix) }
    }
    return $expandedTexts.ToArray() + $pendingTexts.ToArray()
}

function Test-NamePatternIsCodeSearch {
    param([string]$NamePattern)

    $braceParts = @(Expand-BraceAlternatives -Text $NamePattern)
    if ($braceParts.Count -gt $maxNamePatternParts) { return $true }
    $namePatternParts = @($braceParts | ForEach-Object { $_.Split(',') })
    if ($namePatternParts.Count -gt $maxNamePatternParts) { return $true }
    foreach ($namePatternPart in $namePatternParts) {
        if (Test-SingleNamePatternIsCodeSearch -NamePattern $namePatternPart) { return $true }
    }
    return $false
}

function Test-SingleNamePatternIsCodeSearch {
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
        Add-FilterValue -FilterValues $filterValues -Value ([string]$ToolInput.$propertyName)
    }
    $searchPath = [string]$ToolInput.path
    if ($searchPath -match '\.[A-Za-z0-9]+$') {
        $fullPath = Resolve-SearchPath -Path $searchPath -Directory $WorkingDirectory
        if ($fullPath -and [System.IO.File]::Exists($fullPath)) { $filterValues.Add([System.IO.Path]::GetExtension($fullPath)) }
    }
    return $filterValues.ToArray()
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

function Read-ShellSearchArguments {
    param([string[]]$Words)

    $commandIndex = 0
    while ($commandIndex -lt $Words.Count -and (Get-CommandName $Words[$commandIndex]) -notin $patternSearchCommandNames) { $commandIndex++ }
    if ($commandIndex -ge $Words.Count) { return $null }

    $arguments = [pscustomobject]@{
        CommandName          = Get-CommandName $Words[$commandIndex]
        ExplicitPatterns     = [System.Collections.Generic.List[string]]::new()
        Positionals          = [System.Collections.Generic.List[string]]::new()
        PathFlagValues       = [System.Collections.Generic.List[string]]::new()
        PatternComesFromFile = $false
    }
    if ($arguments.CommandName -eq 'sed') { return $arguments }

    $isPowerShellSearch = $arguments.CommandName -in 'select-string', 'sls'
    $afterDoubleDash = $false
    for ($wordIndex = $commandIndex + 1; $wordIndex -lt $Words.Count; $wordIndex++) {
        $word = $Words[$wordIndex]
        $hasNextWord = $wordIndex + 1 -lt $Words.Count
        if ($word -match $redirectionPattern) {
            break
        } elseif ($afterDoubleDash) {
            $arguments.Positionals.Add($word)
        } elseif ($word -eq '--') {
            $afterDoubleDash = $true
        } elseif ($word -match '^--regexp=(.*)$' -or $word -match '(?i)^/c:(.*)$') {
            $arguments.ExplicitPatterns.Add($Matches[1])
        } elseif ($word -ceq '-e' -or $word -eq '--regexp' -or $word -match '(?i)^-patt(e(r(n)?)?)?$') {
            if ($hasNextWord) { $arguments.ExplicitPatterns.Add($Words[$wordIndex + 1]) }
            $wordIndex++
        } elseif ($word -ceq '-f' -or $word -eq '--file') {
            $arguments.PatternComesFromFile = $true
            $wordIndex++
        } elseif ($isPowerShellSearch -and $word -match $powerShellPathFlagPattern) {
            if ($hasNextWord) { $arguments.PathFlagValues.AddRange([string[]]($Words[$wordIndex + 1] -split ',')) }
            $wordIndex++
        } elseif ($word -cin $caseSensitiveValueFlagNames -or $word.ToLowerInvariant() -in $valueFlagNames -or ($isPowerShellSearch -and $word -match $powerShellValueFlagPattern)) {
            $wordIndex++
        } elseif ($word.StartsWith('-') -or $word -match '^/[A-Za-z](:.*)?$') {
            continue
        } else {
            $arguments.Positionals.Add($word)
        }
    }
    return $arguments
}

function Get-ShellSearchPattern {
    param([string[]]$Words)

    $arguments = Read-ShellSearchArguments -Words $Words
    if (-not $arguments) { return $null }
    if ($arguments.CommandName -eq 'sed') { return Get-SedAddressPattern -Words $Words }
    if ($arguments.ExplicitPatterns.Count -gt 0) { return $arguments.ExplicitPatterns -join '|' }
    if ($arguments.PatternComesFromFile -or $arguments.Positionals.Count -eq 0) { return $null }
    return $arguments.Positionals[0]
}

function Get-SedFileOperands {
    param([string[]]$Words)

    $commandIndex = 0
    while ($commandIndex -lt $Words.Count -and (Get-CommandName $Words[$commandIndex]) -ne 'sed') { $commandIndex++ }
    $hasExpression = $false
    $operands = [System.Collections.Generic.List[string]]::new()
    for ($wordIndex = $commandIndex + 1; $wordIndex -lt $Words.Count; $wordIndex++) {
        $word = $Words[$wordIndex]
        if ($word -match $redirectionPattern) {
            break
        } elseif ($word -match '^--expression=') {
            $hasExpression = $true
        } elseif ($word -ceq '--expression' -or $word -cmatch '^-[A-Za-z]*e$') {
            $hasExpression = $true
            $wordIndex++
        } elseif (-not $word.StartsWith('-')) {
            $operands.Add($word)
        }
    }
    if (-not $hasExpression -and $operands.Count -gt 0) { $operands.RemoveAt(0) }
    return $operands.ToArray()
}

function Get-ShellSearchPathOperands {
    param([string[]]$Words)

    $arguments = Read-ShellSearchArguments -Words $Words
    if (-not $arguments) { return @() }
    if ($arguments.CommandName -eq 'sed') { return Get-SedFileOperands -Words $Words }
    if ($arguments.PathFlagValues.Count -gt 0) { return $arguments.PathFlagValues.ToArray() }
    $patternIsExplicit = $arguments.ExplicitPatterns.Count -gt 0 -or $arguments.PatternComesFromFile
    $skippedCount = if ($patternIsExplicit) { 0 } else { 1 }
    return @($arguments.Positionals | Select-Object -Skip $skippedCount)
}

function Resolve-SearchPath {
    param([string]$Path, [string]$Directory)

    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -match $uncPathPattern) { return $null }
    $expandedPath = $Path
    if ($expandedPath -match '^~(?=$|[\\/])') {
        $expandedPath = $env:USERPROFILE + $expandedPath.Substring(1)
    } elseif ($expandedPath -match '^/([A-Za-z])(?=$|/)') {
        $expandedPath = $Matches[1].ToUpperInvariant() + ':' + $expandedPath.Substring(2)
        if ($expandedPath.Length -eq 2) { $expandedPath += '\' }
    }
    $wildcardIndex = $expandedPath.IndexOfAny([char[]]'*?[')
    if ($wildcardIndex -ge 0) {
        $separatorIndex = $expandedPath.LastIndexOfAny([char[]]'/\', $wildcardIndex)
        $expandedPath = if ($separatorIndex -ge 0) { $expandedPath.Substring(0, $separatorIndex + 1) } else { '.' }
    }
    try {
        if ([System.IO.Path]::IsPathFullyQualified($expandedPath)) {
            $fullPath = [System.IO.Path]::GetFullPath($expandedPath)
        } elseif ([System.IO.Path]::IsPathFullyQualified($Directory)) {
            $fullPath = [System.IO.Path]::GetFullPath($expandedPath, $Directory)
        } else {
            return $null
        }
    } catch {
        return $null
    }
    if ($fullPath -match $uncPathPattern) { return $null }
    if ($fullPath.Length -gt 3) { $fullPath = $fullPath.TrimEnd('\') }
    return $fullPath
}

function Resolve-OperandPaths {
    param([string[]]$Operands, [string]$Directory)

    $operandList = if ($Operands.Count -gt 0) { $Operands } else { @('.') }
    foreach ($operand in ($operandList | Select-Object -First $maxSearchPaths)) {
        $pathText = if ($operand -match '[$%`]') { '.' } else { $operand }
        $resolvedPath = Resolve-SearchPath -Path $pathText -Directory $Directory
        if ($resolvedPath) { $resolvedPath }
    }
}

function Get-IndexedFileCount {
    param([string]$IndexedRoot)

    # cmd.exe parses these characters in an unquoted argument, and ArgumentList quotes only whitespace and double quotes.
    if ($IndexedRoot -match $unsafeIndexRootPattern) { throw 'The index root has a character that cmd.exe parses.' }
    if ($scriptStopwatch.ElapsedMilliseconds + $indexStatusTimeoutMilliseconds -gt $indexStatusBudgetMilliseconds) { throw 'No time left for codegraph status.' }
    $statusCommand = (Get-Command codegraph.cmd -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new($statusCommand)
    foreach ($argument in @('status', '--json', $IndexedRoot)) { $startInfo.ArgumentList.Add($argument) }
    $startInfo.WorkingDirectory = $stateRoot
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $statusStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $statusProcess = [System.Diagnostics.Process]::Start($startInfo)
    try {
        $outputTask = $statusProcess.StandardOutput.ReadToEndAsync()
        $null = $statusProcess.StandardError.ReadToEndAsync()
        if (-not $statusProcess.WaitForExit($indexStatusTimeoutMilliseconds)) {
            $statusProcess.Kill($true)
            throw 'codegraph status timed out.'
        }
        $remainingMilliseconds = [Math]::Max(0, $indexStatusTimeoutMilliseconds - [int]$statusStopwatch.ElapsedMilliseconds)
        if (-not $outputTask.Wait($remainingMilliseconds)) {
            $statusProcess.Kill($true)
            throw 'codegraph status output timed out.'
        }
        return [int](($outputTask.Result | ConvertFrom-Json).fileCount)
    } finally {
        $statusProcess.Dispose()
    }
}

function Test-IndexHasFiles {
    param([string]$IndexedRoot)

    $rootKey = $IndexedRoot.ToLowerInvariant()
    if ($indexHasFilesByRoot.ContainsKey($rootKey)) { return $indexHasFilesByRoot[$rootKey] }
    try {
        $hasFiles = (Get-IndexedFileCount -IndexedRoot $IndexedRoot) -gt 0
    } catch {
        $hasFiles = $false
    }
    $indexHasFilesByRoot[$rootKey] = $hasFiles
    return $hasFiles
}

function Get-IndexedRoot {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -match $uncPathPattern) { return $null }
    $cacheKey = $Path.ToLowerInvariant()
    if ($indexedRootCache.ContainsKey($cacheKey)) { return $indexedRootCache[$cacheKey] }
    $indexedRoot = $null
    $level = $Path
    while ($level) {
        if ([System.IO.File]::Exists([System.IO.Path]::Combine($level, '.codegraph', 'codegraph.db')) -and (Test-IndexHasFiles -IndexedRoot $level)) {
            $indexedRoot = $level
            break
        }
        $gitPath = [System.IO.Path]::Combine($level, '.git')
        if ([System.IO.Directory]::Exists($gitPath) -or [System.IO.File]::Exists($gitPath)) { break }
        $level = [System.IO.Path]::GetDirectoryName($level)
    }
    $indexedRootCache[$cacheKey] = $indexedRoot
    return $indexedRoot
}

function Test-SearchReachesIndex {
    param([string[]]$SearchPaths, [string]$WorkingDirectory)

    $workingRoot = Get-IndexedRoot -Path $WorkingDirectory
    foreach ($searchPath in ($SearchPaths | Select-Object -First $maxSearchPaths)) {
        if (Get-IndexedRoot -Path $searchPath) { return $true }
        if ($workingRoot -and $workingRoot.StartsWith($searchPath.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-SegmentDirectories {
    param([object[]]$Segments, [string]$WorkingDirectory)

    $currentDirectory = $WorkingDirectory
    $directoryStack = [System.Collections.Generic.Stack[string]]::new()
    $directories = [System.Collections.Generic.List[string]]::new()
    foreach ($segment in $Segments) {
        $directories.Add($currentDirectory)
        if ($segment.AfterPipe) { continue }
        $words = @(Get-CommandWords -Words $segment.Words)
        $commandName = Get-CommandName $words[0]
        if ($commandName -eq 'popd') {
            if ($directoryStack.Count -gt 0) { $currentDirectory = $directoryStack.Pop() }
            continue
        }
        if ($commandName -notin $directoryChangeCommandNames) { continue }
        $operand = $words | Select-Object -Skip 1 | Where-Object { $_ -notmatch '(?i)^(-[A-Za-z]+|/d)$' } | Select-Object -First 1
        if ($operand -match '[$%`]' -or $operand -eq '-') { continue }
        if ($commandName -eq 'pushd') { $directoryStack.Push($currentDirectory) }
        $targetPath = if ($operand) { $operand } else { $env:USERPROFILE }
        $resolvedDirectory = Resolve-SearchPath -Path $targetPath -Directory $currentDirectory
        $currentDirectory = if ($resolvedDirectory) { $resolvedDirectory } else { '' }
    }
    return $directories.ToArray()
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

    $searchPaths = @()
    $contentPattern = $null
    if ($toolName -eq 'Grep') {
        $contentPattern = [string]$toolInput.pattern
        $filterValues = Get-GrepToolFilterValues -ToolInput $toolInput -WorkingDirectory $workingDirectory
        if (-not (Test-FiltersAllowCode -FilterValues $filterValues)) { exit 0 }
        $searchPaths = @(Resolve-OperandPaths -Operands @([string]$toolInput.path | Where-Object { $_ }) -Directory $workingDirectory)
        $searchCommandWord = 'Grep'
    } elseif ($toolName -eq 'Glob') {
        $globPattern = [string]$toolInput.pattern
        if (Test-NamePatternStartsWithClassName -NamePattern $globPattern) { exit 0 }
        if (-not (Test-NamePatternIsCodeSearch -NamePattern $globPattern)) { exit 0 }
        $searchPaths = @(Resolve-OperandPaths -Operands @([string]$toolInput.path | Where-Object { $_ }) -Directory $workingDirectory)
        $searchCommandWord = 'Glob'
    } else {
        $commandText = [string]$toolInput.command
        if ($commandText -notmatch $commandPrefilterPattern) { exit 0 }
        $commandSegments = ConvertTo-CommandSegments -CommandText $commandText
        $segmentDirectories = Get-SegmentDirectories -Segments $commandSegments -WorkingDirectory $workingDirectory
        $contentSearch = Get-SearchSegmentWords -Segments $commandSegments -SegmentDirectories $segmentDirectories
        $searchCommandWord = $null
        if ($contentSearch) {
            $searchWords = $contentSearch.Words
            $filterValues = Get-ShellFilterValues -Words $searchWords
            if (Test-FiltersAllowCode -FilterValues $filterValues) {
                $searchCommandWord = $searchWords | ForEach-Object { Get-CommandName $_ } | Where-Object { $_ -in $patternSearchCommandNames } | Select-Object -First 1
                if (-not $searchCommandWord) { $searchCommandWord = 'search' }
                $contentPattern = Get-ShellSearchPattern -Words $searchWords
                $pathOperands = @(Get-ShellSearchPathOperands -Words $contentSearch.PathWords)
                $searchPaths = @(Resolve-OperandPaths -Operands $pathOperands -Directory $contentSearch.Directory)
            }
        }
        if (-not $searchCommandWord) {
            $fileNameSearch = Get-FileNameSearch -Segments $commandSegments -ToolName $toolName -SegmentDirectories $segmentDirectories
            if (-not $fileNameSearch) { exit 0 }
            $searchCommandWord = $fileNameSearch.CommandName
            $searchPaths = @($fileNameSearch.SearchPaths)
        }
    }

    $agentType = [string]$payload.agent_type
    if ($agentType -in $exemptAgentTypes) { exit 0 }

    if (-not (Get-Command codegraph.cmd -CommandType Application -ErrorAction SilentlyContinue)) { exit 0 }
    if (-not (Test-SearchReachesIndex -SearchPaths $searchPaths -WorkingDirectory $workingDirectory)) { exit 0 }

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
