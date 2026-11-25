param(
    [switch]$RecordClaude, [int]$FiveHour, [int]$Weekly, [string]$FiveHourReset, [string]$WeeklyReset,
    [string]$GeminiExhausted, [string]$Until, [string]$GeminiOk, [switch]$Json
)
$ErrorActionPreference = 'Stop'
$ledgerPath = Join-Path $PSScriptRoot 'ledger.json'
if ($env:AI_USAGE_LEDGER) {
    if (Test-Path -LiteralPath (Split-Path -Parent $env:AI_USAGE_LEDGER)) { $ledgerPath = $env:AI_USAGE_LEDGER }
    else { [Console]::Error.WriteLine("WARNING: shared ledger folder not reachable ($env:AI_USAGE_LEDGER). Using local ledger.") }
}
$inv = [System.Globalization.CultureInfo]::InvariantCulture

function Format-ShortTime([datetime]$dt) { $dt.ToString('ddd HH:mm', $inv) }
function Parse-Iso([string]$s) { [DateTimeOffset]::Parse($s, $inv) }
function From-Unix([double]$sec) { [datetime]::SpecifyKind([datetime]'1970-01-01', [DateTimeKind]::Utc).AddSeconds($sec).ToLocalTime() }

function Save-Ledger($claudeArr, $geminiArr) {
    $text = ([ordered]@{ claude = [object[]]@($claudeArr); gemini = [object[]]@($geminiArr) }) | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($ledgerPath, $text, (New-Object System.Text.UTF8Encoding($false)))
}

function Load-Ledger {
    if (-not (Test-Path -LiteralPath $ledgerPath)) {
        Save-Ledger @() @()
        return @{ claude = (New-Object System.Collections.ArrayList); gemini = (New-Object System.Collections.ArrayList) }
    }
    try {
        $parsed = (Get-Content -LiteralPath $ledgerPath -Raw) | ConvertFrom-Json
        if ($null -eq $parsed -or $null -eq $parsed.PSObject.Properties['claude'] -or $null -eq $parsed.PSObject.Properties['gemini']) {
            throw 'Missing claude or gemini array.'
        }
    } catch {
        [Console]::Error.WriteLine("Corrupt ledger ($ledgerPath): $($_.Exception.Message)"); exit 1
    }
    $c = New-Object System.Collections.ArrayList; foreach ($x in @($parsed.claude)) { if ($null -ne $x) { [void]$c.Add($x) } }
    $g = New-Object System.Collections.ArrayList; foreach ($x in @($parsed.gemini)) { if ($null -ne $x) { [void]$g.Add($x) } }
    return @{ claude = $c; gemini = $g }
}

function Find-RateLimits($obj) {
    if ($null -eq $obj) { return $null }
    if ($obj -is [System.Collections.IEnumerable] -and -not ($obj -is [string])) {
        foreach ($item in $obj) { $r = Find-RateLimits $item; if ($null -ne $r) { return $r } }
    } elseif ($obj -is [pscustomobject]) {
        foreach ($p in $obj.PSObject.Properties) {
            if ($p.Name -eq 'rate_limits' -and $null -ne $p.Value) { return $p.Value }
            $r = Find-RateLimits $p.Value; if ($null -ne $r) { return $r }
        }
    }
    return $null
}

function Get-CodexRow {
    $row = [ordered]@{ Tool = 'Codex'; Account = '-'; '5h%' = 'unknown'; '5hReset' = '-'; 'Week%' = 'unknown'; WeekReset = '-'; Updated = '-'; Status = 'OK' }
    $dir = Join-Path $HOME '.codex\sessions'
    if (-not (Test-Path -LiteralPath $dir)) { return [pscustomobject]$row }
    $files = Get-ChildItem -LiteralPath $dir -Filter '*.jsonl' -File -Recurse | Sort-Object LastWriteTime -Descending
    foreach ($f in $files) {
        $lines = @(Get-Content -LiteralPath $f.FullName)
        for ($i = $lines.Length - 1; $i -ge 0; $i--) {
            if ($lines[$i].IndexOf('rate_limits') -lt 0) { continue }
            try { $rl = Find-RateLimits ($lines[$i] | ConvertFrom-Json) } catch { continue }
            if ($null -eq $rl -or ($null -eq $rl.primary -and $null -eq $rl.secondary)) { continue }
            $p5 = $null; $pw = $null
            if ($null -ne $rl.primary -and $null -ne $rl.primary.used_percent) {
                $p5 = [double]$rl.primary.used_percent; $t = From-Unix ([double]$rl.primary.resets_at)
                if ($t -le (Get-Date)) { $p5 = 0; $row['5hReset'] = 'reset' } else { $row['5hReset'] = Format-ShortTime $t }
                $row['5h%'] = ('{0:0.#}%' -f $p5)
            }
            if ($null -ne $rl.secondary -and $null -ne $rl.secondary.used_percent) {
                $pw = [double]$rl.secondary.used_percent; $t = From-Unix ([double]$rl.secondary.resets_at)
                if ($t -le (Get-Date)) { $pw = 0; $row['WeekReset'] = 'reset' } else { $row['WeekReset'] = Format-ShortTime $t }
                $row['Week%'] = ('{0:0.#}%' -f $pw)
            }
            $row['Updated'] = Format-ShortTime $f.LastWriteTime
            if (($null -ne $p5 -and $p5 -ge 85) -or ($null -ne $pw -and $pw -ge 90)) { $row['Status'] = 'FALLBACK' }
            return [pscustomobject]$row
        }
    }
    return [pscustomobject]$row
}

$ledger = Load-Ledger
$mutated = $false
if ($RecordClaude) {
    if (-not $PSBoundParameters.ContainsKey('FiveHour') -or -not $PSBoundParameters.ContainsKey('Weekly') -or -not $FiveHourReset -or -not $WeeklyReset) {
        [Console]::Error.WriteLine('Usage: -RecordClaude -FiveHour <int> -Weekly <int> -FiveHourReset <ISO> -WeeklyReset <ISO>'); exit 1
    }
    $r5Iso = (Parse-Iso $FiveHourReset).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', $inv)
    $rwIso = (Parse-Iso $WeeklyReset).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', $inv)
    $cfgDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { $HOME }
    $cfgPath = Join-Path $cfgDir '.claude.json'
    if (-not (Test-Path -LiteralPath $cfgPath)) { [Console]::Error.WriteLine("Claude config not found: $cfgPath"); exit 1 }
    $cfg = (Get-Content -LiteralPath $cfgPath -Raw) | ConvertFrom-Json
    if ($null -eq $cfg.oauthAccount -or -not $cfg.oauthAccount.accountUuid) { [Console]::Error.WriteLine('Missing oauthAccount.accountUuid.'); exit 1 }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes([string]$cfg.oauthAccount.accountUuid)); $sha.Dispose()
    $hash = ([System.BitConverter]::ToString($bytes).Replace('-', '').ToLower()).Substring(0, 12)
    $nowIso = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', $inv)
    $existing = $null; foreach ($e in $ledger.claude) { if ($e.hash -eq $hash) { $existing = $e; break } }
    if ($null -ne $existing) {
        $existing.fiveHour = $FiveHour; $existing.weekly = $Weekly; $existing.fiveHourReset = $r5Iso; $existing.weeklyReset = $rwIso; $existing.updated = $nowIso
    } else {
        $used = @($ledger.claude | ForEach-Object { $_.label }); $label = 'Z'
        for ($code = 65; $code -le 90; $code++) { $cand = [string][char]$code; if ($used -notcontains $cand) { $label = $cand; break } }
        [void]$ledger.claude.Add([pscustomobject][ordered]@{ label = $label; hash = $hash; fiveHour = $FiveHour; weekly = $Weekly; fiveHourReset = $r5Iso; weeklyReset = $rwIso; updated = $nowIso })
    }
    Save-Ledger $ledger.claude $ledger.gemini; $mutated = $true
}
if ($GeminiExhausted) {
    if (-not $Until) { [Console]::Error.WriteLine('Usage: -GeminiExhausted <model> -Until <ISO>'); exit 1 }
    $untilIso = (Parse-Iso $Until).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', $inv)
    $next = New-Object System.Collections.ArrayList; foreach ($g in $ledger.gemini) { if ($g.model -ine $GeminiExhausted) { [void]$next.Add($g) } }
    [void]$next.Add([pscustomobject][ordered]@{ model = $GeminiExhausted; exhaustedUntil = $untilIso })
    $ledger.gemini = $next; Save-Ledger $ledger.claude $ledger.gemini; $mutated = $true
}
if ($GeminiOk) {
    $next = New-Object System.Collections.ArrayList; foreach ($g in $ledger.gemini) { if ($g.model -ine $GeminiOk) { [void]$next.Add($g) } }
    $ledger.gemini = $next; Save-Ledger $ledger.claude $ledger.gemini; $mutated = $true
}
if ($mutated -and -not $Json) { exit 0 }

$now = [DateTimeOffset]::Now; $rows = New-Object System.Collections.ArrayList
[void]$rows.Add((Get-CodexRow))
foreach ($c in $ledger.claude) {
    $r5 = Parse-Iso $c.fiveHourReset; $rw = Parse-Iso $c.weeklyReset
    $v5 = if ($r5 -le $now) { 0 } else { [int]$c.fiveHour }; $vw = if ($rw -le $now) { 0 } else { [int]$c.weekly }
    $t5 = if ($r5 -le $now) { 'reset' } else { Format-ShortTime $r5.LocalDateTime }
    $tw = if ($rw -le $now) { 'reset' } else { Format-ShortTime $rw.LocalDateTime }
    $st = if ($v5 -ge 95 -or $vw -ge 95) { 'STOP' } else { 'OK' }
    [void]$rows.Add([pscustomobject][ordered]@{ Tool = 'Claude'; Account = $c.label; '5h%' = "$v5%"; '5hReset' = $t5; 'Week%' = "$vw%"; WeekReset = $tw; Updated = (Format-ShortTime (Parse-Iso $c.updated).LocalDateTime); Status = $st })
}
foreach ($g in $ledger.gemini) {
    $u = Parse-Iso $g.exhaustedUntil
    $st = if ($u -gt $now) { 'EXHAUSTED until ' + (Format-ShortTime $u.LocalDateTime) } else { 'OK' }
    [void]$rows.Add([pscustomobject][ordered]@{ Tool = 'Gemini'; Account = $g.model; '5h%' = '-'; '5hReset' = '-'; 'Week%' = '-'; WeekReset = '-'; Updated = '-'; Status = $st })
}
if ($Json) { ConvertTo-Json -InputObject @($rows) -Depth 5 } else { ($rows | Format-Table -AutoSize | Out-String -Width 200).Trim() }
