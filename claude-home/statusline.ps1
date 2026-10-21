try {
    [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch {
}
$data = $null
try {
    $data = [Console]::In.ReadToEnd() | ConvertFrom-Json
} catch {
}

$cwd = $data.workspace.current_dir
if (-not $cwd) { $cwd = $data.cwd }
if (-not $cwd) { $cwd = (Get-Location).Path }
$dirName = Split-Path -Leaf $cwd
$modelName = $data.model.display_name

function Get-GitBranch {
    param([string]$Cwd)

    # Reads .git/HEAD directly instead of shelling out to `git`, which costs
    # ~245ms across two process launches on this machine.
    $dir = $Cwd
    $gitEntry = $null
    while ($dir) {
        $candidate = Join-Path $dir ".git"
        if (Test-Path -LiteralPath $candidate) {
            $gitEntry = $candidate
            break
        }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    if (-not $gitEntry) { return $null }

    $gitDir = $gitEntry
    if (Test-Path -LiteralPath $gitEntry -PathType Leaf) {
        # Worktrees/submodules: .git is a file containing "gitdir: <path>".
        $content = Get-Content -LiteralPath $gitEntry -Raw -ErrorAction SilentlyContinue
        if ($content -notmatch 'gitdir:\s*(.+)') { return $null }
        $target = $matches[1].Trim()
        if (-not [System.IO.Path]::IsPathRooted($target)) {
            $target = Join-Path (Split-Path -Parent $gitEntry) $target
        }
        $gitDir = $target
    }

    $headFile = Join-Path $gitDir "HEAD"
    if (-not (Test-Path -LiteralPath $headFile)) { return $null }
    $head = Get-Content -LiteralPath $headFile -Raw -ErrorAction SilentlyContinue
    if (-not $head) { return $null }
    $head = $head.Trim()

    if ($head -match '^ref:\s*refs/heads/(.+)$') { return $matches[1].Trim() }
    if ($head -match '^[0-9a-fA-F]{40}$') { return $head.Substring(0, 7) }
    return $null
}

$branch = $null
try {
    $branch = Get-GitBranch -Cwd $cwd
} catch {
    # Any failure here must not break the status line.
}

$esc = [char]27
$dim = "$esc[2m"
$reset = "$esc[0m"
$sep = " ${dim}|${reset} "

$red = "$esc[31m"
$yellow = "$esc[33m"

$purple = "$esc[38;2;168;85;247m"
$purpleLight = "$esc[38;2;192;132;252m"
$pink = "$esc[38;2;236;72;153m"
$pinkLight = "$esc[38;2;244;114;182m"
$cyan = "$esc[38;2;34;211;238m"
$green = "$esc[38;2;74;222;128m"
$emerald = "$esc[38;2;16;185;129m"

$parts = @("${purple}${dirName}${reset}")
if ($branch) { $parts += "${pink}${branch}${reset}" }
$parts += "${cyan}${modelName}${reset}"

$ctxPct = $data.context_window.used_percentage
if ($null -ne $ctxPct) {
    $ctxRounded = [Math]::Round($ctxPct)
    if ($ctxRounded -ge 80) {
        $parts += "${red}ctx ${ctxRounded}%${reset}"
    } elseif ($ctxRounded -ge 60) {
        $parts += "${yellow}ctx ${ctxRounded}%${reset}"
    } else {
        $parts += "${emerald}ctx ${ctxRounded}%${reset}"
    }
}

function Save-ContextSnapshot {
    param([string]$SessionId, $ContextWindow)

    if (-not $SessionId -or $null -eq $ContextWindow.used_percentage) { return }

    $snapshot = @{ usedPercentage = [double]$ContextWindow.used_percentage }
    if ($ContextWindow.context_window_size) {
        $snapshot.totalTokens = [int64]$ContextWindow.context_window_size
    }
    $currentUsage = $ContextWindow.current_usage
    if ($currentUsage) {
        $snapshot.usedTokens = [int64]$currentUsage.input_tokens + [int64]$currentUsage.cache_creation_input_tokens + [int64]$currentUsage.cache_read_input_tokens
    }

    $snapshotDirectory = Join-Path $env:USERPROFILE '.claude\cache\strategic-compact'
    if (-not (Test-Path -LiteralPath $snapshotDirectory)) {
        New-Item -ItemType Directory -Path $snapshotDirectory -Force -ErrorAction Stop | Out-Null
    }
    $snapshotFile = Join-Path $snapshotDirectory (($SessionId -replace '[^A-Za-z0-9._-]', '_') + '.context.json')
    if (Test-Path -LiteralPath $snapshotFile) {
        $isFresh = (Get-Item -LiteralPath $snapshotFile).LastWriteTime -gt (Get-Date).AddMinutes(-5)
        if ($isFresh) {
            try {
                $stored = Get-Content -LiteralPath $snapshotFile -Raw | ConvertFrom-Json
                if ($null -ne $stored.usedPercentage -and [double]$stored.usedPercentage -eq $snapshot.usedPercentage) { return }
            } catch {
            }
        }
    }
    $temporaryFile = "$snapshotFile.$([guid]::NewGuid().ToString('N')).tmp"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    try {
        [System.IO.File]::WriteAllText($temporaryFile, ($snapshot | ConvertTo-Json -Compress), $utf8NoBom)
        Move-Item -LiteralPath $temporaryFile -Destination $snapshotFile -Force -ErrorAction Stop
    } finally {
        if (Test-Path -LiteralPath $temporaryFile) { Remove-Item -LiteralPath $temporaryFile -Force -ErrorAction SilentlyContinue }
    }
}

try {
    Save-ContextSnapshot -SessionId $data.session_id -ContextWindow $data.context_window
} catch {
}

function Format-TokenCount {
    param([int64]$Count)
    if ($Count -lt 1000) {
        return "$Count"
    } elseif ($Count -lt 1000000) {
        return "$([Math]::Round($Count / 1000))k"
    } else {
        return "$([Math]::Round($Count / 1000000, 1))M"
    }
}

function Get-SessionTokenTotal {
    param([string]$TranscriptPath, [string]$SessionId)

    if (-not $TranscriptPath -or -not $SessionId) { return 0 }
    if (-not (Test-Path -LiteralPath $TranscriptPath)) { return 0 }

    $cacheDir = Join-Path $env:USERPROFILE '.claude\statusline-cache'
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    $cacheFile = Join-Path $cacheDir (($SessionId -replace '[^A-Za-z0-9._-]', '_') + '.json')

    $offset = [int64]0
    $total = [int64]0
    $seenIds = @{}
    # Ordered alongside $seenIds so we can cap to the most recent N ids without
    # relying on hashtable enumeration order (which is not insertion order).
    $seenOrder = New-Object System.Collections.Generic.List[string]
    $cacheExists = $false

    if (Test-Path -LiteralPath $cacheFile) {
        try {
            $cache = Get-Content -LiteralPath $cacheFile -Raw | ConvertFrom-Json -ErrorAction Stop
            $cachedOffset = [int64]$cache.Offset
            $cachedTotal = [int64]$cache.Total
            $offset = $cachedOffset
            $total = $cachedTotal
            if ($cache.SeenIds) {
                foreach ($id in $cache.SeenIds) {
                    if (-not $seenIds.ContainsKey($id)) {
                        $seenIds[$id] = $true
                        $seenOrder.Add($id)
                    }
                }
            }
            $cacheExists = $true
        } catch {
            $offset = [int64]0
            $total = [int64]0
            $seenIds = @{}
            $seenOrder.Clear()
        }
    } else {
        Get-ChildItem -LiteralPath $cacheDir -File |
            Where-Object { $_.Extension -in '.json', '.tmp' -and $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    $fileLength = (Get-Item -LiteralPath $TranscriptPath).Length
    $stateChanged = $false

    if (-not $cacheExists) {
        $offset = $fileLength
        $total = [int64]0
    }

    if ($fileLength -lt $offset) {
        $offset = [int64]0
        $total = [int64]0
        $seenIds = @{}
        $seenOrder.Clear()
        $stateChanged = $true
    }

    if ($fileLength -gt $offset) {
        $fs = [System.IO.File]::Open($TranscriptPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $fs.Seek($offset, [System.IO.SeekOrigin]::Begin) | Out-Null
            $buffer = New-Object byte[] ($fileLength - $offset)
            $bytesRead = 0
            while ($bytesRead -lt $buffer.Length) {
                $count = $fs.Read($buffer, $bytesRead, $buffer.Length - $bytesRead)
                if ($count -le 0) { break }
                $bytesRead += $count
            }
        } finally {
            $fs.Dispose()
        }

        $lastNewlineIndex = -1
        if ($bytesRead -gt 0) { $lastNewlineIndex = [Array]::LastIndexOf($buffer, [byte]10, $bytesRead - 1) }
        if ($lastNewlineIndex -ge 0) {
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            foreach ($line in $utf8NoBom.GetString($buffer, 0, $lastNewlineIndex + 1).Split("`n")) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                if (-not $line.Contains('"usage"')) { continue }
                try {
                    $entry = $line | ConvertFrom-Json
                } catch {
                    continue
                }
                $usage = $entry.message.usage
                if (-not $usage) { continue }
                $id = $entry.message.id
                if (-not $id) { $id = $entry.requestId }
                if (-not $id) { continue }
                if ($seenIds.ContainsKey($id)) { continue }
                $seenIds[$id] = $true
                $seenOrder.Add($id)

                $tokens = [int64]0
                if ($usage.input_tokens) { $tokens += [int64]$usage.input_tokens }
                if ($usage.cache_creation_input_tokens) { $tokens += [int64]$usage.cache_creation_input_tokens }
                if ($usage.cache_read_input_tokens) { $tokens += [int64]$usage.cache_read_input_tokens }
                if ($usage.output_tokens) { $tokens += [int64]$usage.output_tokens }
                $total += $tokens
            }
            $offset += $lastNewlineIndex + 1
            $stateChanged = $true
        }
    }

    if ($stateChanged -or -not $cacheExists) {
        # Cap the persisted id list so the cache file (and the JSON encode/decode cost
        # paid on every single redraw) cannot grow without bound over a long session.
        # Only recent ids are needed to catch a message id reappearing after the
        # transcript is rewritten (e.g. /compact or /resume); the offset already
        # prevents re-reading anything older than that.
        $maxSeenIds = 500
        if ($seenOrder.Count -gt $maxSeenIds) {
            $recentIds = $seenOrder.GetRange($seenOrder.Count - $maxSeenIds, $maxSeenIds)
        } else {
            $recentIds = $seenOrder
        }
        $cacheObj = [PSCustomObject]@{
            Offset  = $offset
            Total   = $total
            SeenIds = @($recentIds)
        }
        $temporaryFile = "$cacheFile.$([guid]::NewGuid().ToString('N')).tmp"
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        try {
            [System.IO.File]::WriteAllText($temporaryFile, ($cacheObj | ConvertTo-Json -Compress -Depth 3), $utf8NoBom)
            Move-Item -LiteralPath $temporaryFile -Destination $cacheFile -Force -ErrorAction Stop
        } finally {
            if (Test-Path -LiteralPath $temporaryFile) { Remove-Item -LiteralPath $temporaryFile -Force -ErrorAction SilentlyContinue }
        }
    }

    return $total
}

try {
    $sessionTokens = Get-SessionTokenTotal -TranscriptPath $data.transcript_path -SessionId $data.session_id
    if ($sessionTokens -gt 0) {
        $parts += "${green}session $(Format-TokenCount $sessionTokens) tok${reset}"
    }
} catch {
    # Any failure here must not break the status line.
}

# "~" marks these as of the last completed API response, not live — Claude Code
# only refreshes rate_limits data when a response finishes, and the host gives
# no way to poll it more often than that.
$fiveHourPct = $data.rate_limits.five_hour.used_percentage
if ($null -ne $fiveHourPct) {
    $parts += "${purpleLight}5h ~$([Math]::Round($fiveHourPct))%${reset}"
}

$sevenDayPct = $data.rate_limits.seven_day.used_percentage
if ($null -ne $sevenDayPct) {
    $parts += "${pinkLight}7d ~$([Math]::Round($sevenDayPct))%${reset}"
}

[Console]::Out.Write($parts -join $sep)
