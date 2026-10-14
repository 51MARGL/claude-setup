$stdin = [Console]::In.ReadToEnd()
$data = $stdin | ConvertFrom-Json

$cwd = $data.workspace.current_dir
if (-not $cwd) { $cwd = $data.cwd }
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
    $cacheFile = Join-Path $cacheDir "$SessionId.json"

    $offset = [int64]0
    $total = [int64]0
    $seenIds = @{}
    # Ordered alongside $seenIds so we can cap to the most recent N ids without
    # relying on hashtable enumeration order (which is not insertion order).
    $seenOrder = New-Object System.Collections.Generic.List[string]
    $cacheExists = $false

    if (Test-Path -LiteralPath $cacheFile) {
        $cache = Get-Content -LiteralPath $cacheFile -Raw | ConvertFrom-Json
        $offset = [int64]$cache.Offset
        $total = [int64]$cache.Total
        if ($cache.SeenIds) {
            foreach ($id in $cache.SeenIds) {
                if (-not $seenIds.ContainsKey($id)) {
                    $seenIds[$id] = $true
                    $seenOrder.Add($id)
                }
            }
        }
        $cacheExists = $true
    }

    $fileLength = (Get-Item -LiteralPath $TranscriptPath).Length
    $stateChanged = $false

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
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            $reader = New-Object System.IO.StreamReader($fs, $utf8NoBom, $false)
            try {
                while (-not $reader.EndOfStream) {
                    $line = $reader.ReadLine()
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }
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
            } finally {
                $reader.Dispose()
            }
        } finally {
            $fs.Dispose()
        }
        $offset = $fileLength
        $stateChanged = $true
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
        $cacheObj | ConvertTo-Json -Compress -Depth 3 | Set-Content -LiteralPath $cacheFile -Force
    }

    return $total
}

try {
    $sessionTokens = Get-SessionTokenTotal -TranscriptPath $data.transcript_path -SessionId $data.session_id
    if ($sessionTokens -gt 0) {
        $parts += "${green}$(Format-TokenCount $sessionTokens) tok${reset}"
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
