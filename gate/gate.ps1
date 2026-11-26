# SpaceX commit gate (Rust). Lives in a project as .spacex/gate.ps1; see .spacex/REVIEW.md.
# Usage: gate.ps1 <check|stamp|pre-commit|commit-msg|post-commit|pre-push|baseline> [args]
# Native stderr is not redirected, and $ErrorActionPreference stays default: Windows PowerShell 5.1 turns cargo progress into errors.
$Cmd = $args[0]
$Rest = @($args | Select-Object -Skip 1)

function Fail($msg) { Write-Host "gate: FAILED: $msg"; exit 1 }
function Need($tool) { if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { Fail "$tool not found" } }

$root = git rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0 -or -not $root) { Fail 'not in a git repository' }
Set-Location -LiteralPath $root
$basePath = Join-Path $root '.spacex/baseline.json'
$stampDir = git rev-parse --git-path spacex/stamps
if (-not [IO.Path]::IsPathRooted($stampDir)) { $stampDir = Join-Path $root $stampDir }

# Settings: .spacex/config.json, with these defaults for missing keys.
$defaults = @{
    risky = @(); hotPaths = @(); maxDiffLines = 400; lightMaxLines = 20
    testCommand = @('cargo', 'test', '--workspace', '--locked'); jscpdPaths = @('crates')
}
$cfgFile = Join-Path $root '.spacex/config.json'
$user = $null
if (Test-Path $cfgFile) { $user = Get-Content -Raw $cfgFile | ConvertFrom-Json }
$cfg = @{}
foreach ($k in @($defaults.Keys)) { $cfg[$k] = if ($user -and $null -ne $user.$k) { $user.$k } else { $defaults[$k] } }

function Test-Glob($path, $globs) { foreach ($g in @($globs)) { if ($path -like $g) { return $true } }; $false }
function Get-Tree { $t = git write-tree; if ($LASTEXITCODE -ne 0 -or -not $t) { Fail 'git write-tree failed (unmerged files?)' }; $t }
function Get-StampPath($tree) { Join-Path $stampDir "$tree.json" }
function Get-Stamp($tree) { $p = Get-StampPath $tree; if (Test-Path $p) { Get-Content -Raw $p | ConvertFrom-Json } }
function Get-Family($name) { ([string]$name -split '/')[0].Trim().ToLower() }
function Get-Deps { if (Test-Path Cargo.lock) { @(Get-Content Cargo.lock | Where-Object { $_ -eq '[[package]]' }).Count } else { 0 } }

function Get-Staged {
    foreach ($l in @(git -c core.quotepath=off diff --cached --numstat --no-renames)) {
        if (-not $l) { continue }
        $p = $l -split "`t", 3
        $a = 0; $d = 0
        if ($p[0] -ne '-') { $a = [int]$p[0]; $d = [int]$p[1] }
        [pscustomobject]@{ path = $p[2]; added = $a; deleted = $d; lines = $a + $d }
    }
}

function Get-Counted {   # added lines in staged .rs files that are not blank, comments or test code
    $n = 0; $cut = 0; $ln = 0; $skip = $true
    foreach ($l in @(git -c core.quotepath=off diff --cached -U0 --no-renames -- '*.rs')) {
        if ($l -match '^\+\+\+ (b/(.*)|/dev/null)') {
            $p = "$($Matches[2])".TrimEnd("`t")
            $skip = (-not $p) -or $p -match '(^|/)tests/' -or $p -like '*tests.rs'
            if (-not $skip) {
                $i = [array]::FindIndex([string[]]@(git show ":$p"), [Predicate[string]] { $args[0].Trim() -eq '#[cfg(test)]' })
                $cut = if ($i -ge 0) { $i + 1 } else { [int]::MaxValue }   # line number of the first #[cfg(test)]
            }
        }
        elseif ($l -match '^@@ -\S+ \+(\d+)') { $ln = [int]$Matches[1] }
        elseif ($l.StartsWith('+') -and -not $skip) {
            if ($ln -lt $cut -and $l.Substring(1).Trim() -notmatch '^(//|$)') { $n++ }
            $ln++
        }
    }
    $n
}

function Get-Tier($st, $size) {
    if (@($st | Where-Object { Test-Glob $_.path $cfg.risky }).Count) { return 'Risky' }
    if ($size -le $cfg.lightMaxLines) { return 'Light' }
    'Normal'
}

function Get-Counts {
    Need cargo
    $out = cargo clippy --workspace --all-targets --message-format=json -- -D clippy::all -W clippy::pedantic -W clippy::cognitive_complexity -W clippy::too_many_lines
    $rc = $LASTEXITCODE
    $clippy = [ordered]@{}
    $errs = @()
    foreach ($l in $out) {
        if ($l -notmatch '"reason":"compiler-message"') { continue }
        $m = ($l | ConvertFrom-Json).message
        if ($m.level -eq 'error') { $errs += $m.rendered }
        elseif ($m.level -eq 'warning' -and $m.code -and $m.code.code) { $clippy[$m.code.code] = 1 + [int]$clippy[$m.code.code] }
    }
    if ($errs) { Write-Host ($errs -join "`n"); Fail "cargo clippy reports $($errs.Count) error(s)" }
    if ($rc -ne 0) { Fail "cargo clippy exited $rc" }
    $mo = cargo machete   # exit 1 = unused dependencies found; each one is on its own indented line
    if ($LASTEXITCODE -gt 1) { Fail "cargo machete exited $LASTEXITCODE (is cargo-machete installed?)" }
    $mach = @($mo | Where-Object { $_ -match '^[\t ]+\S' }).Count
    [ordered]@{ clippy = $clippy; machete = $mach; deps = Get-Deps }
}

function Get-Jscpd {
    Need jscpd
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('jscpd-' + [guid]::NewGuid())
    $null = jscpd @($cfg.jscpdPaths) --min-lines 10 --format rust --reporters json --output $tmp --silent
    $rc = $LASTEXITCODE
    $rep = Join-Path $tmp 'jscpd-report.json'
    if ($rc -ne 0 -or -not (Test-Path $rep)) { Fail "jscpd failed (exit $rc)" }
    $n = [int](Get-Content -Raw $rep | ConvertFrom-Json).statistics.total.clones
    Remove-Item -Recurse -Force $tmp
    $n
}

function Read-Baseline {
    if (-not (Test-Path $basePath)) { Fail 'no .spacex/baseline.json; ask Steve to run gate.ps1 baseline' }
    $j = Get-Content -Raw $basePath | ConvertFrom-Json
    $b = @{ clippy = @{}; machete = 0; deps = 0; jscpd = 0 }
    if ($j.clippy) { foreach ($p in $j.clippy.PSObject.Properties) { $b.clippy[$p.Name] = [int]$p.Value } }
    foreach ($k in 'machete', 'deps', 'jscpd') { if ($null -ne $j.$k) { $b[$k] = [int]$j.$k } }
    $b
}
function Write-Baseline($b) {
    $null = New-Item -ItemType Directory -Force (Split-Path $basePath)
    [IO.File]::WriteAllText($basePath, ($b | ConvertTo-Json -Depth 5))
}

function Invoke-Check($testArgs) {
    Need cargo
    $st = @(Get-Staged)
    $size = Get-Counted
    $tier = Get-Tier $st $size
    $bad = @()
    if ($size -gt $cfg.maxDiffLines) {
        $s = Get-Stamp (Get-Tree)
        if (-not ($s -and $s.large -and $s.largeApproved -eq 'Steve')) { $bad += "$size counted lines (max $($cfg.maxDiffLines)): split into stamped commits (.spacex/REVIEW.md), or add Large: <reason> and Large-approved: Steve" }
    }
    cargo fmt --all -- --check | Out-Host
    if ($LASTEXITCODE -ne 0) { $bad += 'cargo fmt --check failed (run cargo fmt)' }
    $base = Read-Baseline
    $cur = Get-Counts
    foreach ($c in $cur.clippy.Keys) {
        $b = [int]$base.clippy[$c]
        if ($cur.clippy[$c] -gt $b) { $bad += "$c $($cur.clippy[$c]) > $b" }
    }
    if ($cur.machete -gt $base.machete) { $bad += "unused dependencies (machete) $($cur.machete) > $($base.machete)" }
    if ($cur.deps -gt $base.deps) {
        $s = Get-Stamp (Get-Tree)
        if (-not ($s -and $s.depsReason)) { $bad += "dependency count $($cur.deps) > $($base.deps) and the review has no Dependency-reason" }
    }
    Write-Host "gate: tier $tier, $size counted lines"
    if ($bad) { Fail ($bad -join '; ') }
    if ($testArgs) {
        cargo test @testArgs | Out-Host
        if ($LASTEXITCODE -ne 0) { Fail 'cargo test failed' }
    }
}

function Invoke-Stamp($file) {
    if (-not $file -or -not (Test-Path $file)) { Fail 'usage: gate.ps1 stamp <review file>' }
    $text = [IO.File]::ReadAllText((Resolve-Path $file).ProviderPath)   # plain string: Get-Content adds PSPath notes that ConvertTo-Json writes out on 5.1
    $tree = Get-Tree
    $st = @(Get-Staged)
    $size = Get-Counted
    $tier = Get-Tier $st $size
    $h = @{}
    foreach ($k in 'Writer', 'Reviewer-A', 'Reviewer-B', 'Test-first', 'Timing', 'Dependency-reason', 'Large', 'Large-approved', 'Final') {
        $h[$k] = [regex]::Match($text, "(?mi)^$k[ \t]*:[ \t]*(.*?)[ \t]*\r?$").Groups[1].Value
    }
    $w = Get-Family $h['Writer']; $a = Get-Family $h['Reviewer-A']; $b = Get-Family $h['Reviewer-B']
    $bad = @()
    if (-not $w) { $bad += 'Writer missing' }
    if (-not $b) { $bad += 'Reviewer-B missing' }
    if ($tier -ne 'Light' -and -not $a) { $bad += "Reviewer-A missing (tier $tier needs A and B)" }
    if ($a -and $a -eq $b) { $bad += 'Reviewer-A and Reviewer-B are the same family' }
    if ($w -and ($a -eq $w -or $b -eq $w)) { $bad += "a reviewer is the writer's family ($w)" }
    if ($tier -eq 'Risky' -and -not $h['Test-first']) { $bad += 'Risky tier needs Test-first' }
    if ($tier -eq 'Risky' -and $h['Reviewer-B'] -notmatch 'opus') { $bad += 'Risky tier needs Reviewer-B on Opus (claude/opus-high)' }
    if (-not $h['Timing'] -and @($st | Where-Object { Test-Glob $_.path $cfg.hotPaths }).Count) { $bad += 'a hot path is staged: Timing is required' }
    if ($h['Large'] -and $h['Large-approved'] -ne 'Steve') { $bad += 'Large: needs Large-approved: Steve (add it only after Steve says so in chat)' }
    if ($h['Final'] -notmatch '^\S+\s+OK$') { $bad += "no 'Final: <model> OK' line: the orchestrator must review the whole staged diff before the stamp" }
    $n = @{ fixed = 0; rejected = 0; accepted = 0 }
    foreach ($l in ($text -split '\r?\n')) {
        if ($l -notmatch '^\s*\|') { continue }
        $cells = @($l.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        if ($cells[0] -notmatch '^[AB]\d+$') { continue }
        $s = $cells[-1]
        if ($s -eq 'FIXED') { $n.fixed++ }
        elseif ($s -match '^REJECTED \(.+\)$') { $n.rejected++ }
        elseif ($s -eq 'ACCEPTED (Steve)') { $n.accepted++ }
        else { $bad += "finding $($cells[0]) has status '$s'" }
    }
    if ($bad) { Fail ($bad -join '; ') }
    $obj = [ordered]@{
        tree = $tree; tier = $tier; writer = $h['Writer']
        reviewers = @($h['Reviewer-A'], $h['Reviewer-B'] | Where-Object { $_ })
        fixed = $n.fixed; rejected = $n.rejected; accepted = $n.accepted
        depsReason = $h['Dependency-reason']; large = $h['Large']; largeApproved = $h['Large-approved']; review = $text
    }
    $null = New-Item -ItemType Directory -Force $stampDir
    [IO.File]::WriteAllText((Get-StampPath $tree), ($obj | ConvertTo-Json -Depth 5))
    Write-Host "gate: stamped $tree ($tier)"
}

function Invoke-PreCommit {
    $un = @(git -c core.quotepath=off diff --name-only | Where-Object { $_ -ne '.spacex/baseline.json' })
    if ($un.Count) { Fail "stage or stash unstaged changes: the checks must see the staged content ($($un -join ', '))" }
    $tree = Get-Tree
    if (-not (Test-Path (Get-StampPath $tree))) { Fail "no review stamp for staged tree $tree; run the review in .spacex/REVIEW.md, then gate.ps1 stamp <file>" }
    Invoke-Check @()
}

function Invoke-CommitMsg($file) {
    $s = Get-Stamp (Get-Tree)
    if (-not $s) { Fail 'no review stamp for the staged tree' }
    $st = @(Get-Staged)
    $net = [int]($st | Measure-Object added -Sum).Sum - [int]($st | Measure-Object deleted -Sum).Sum
    git interpret-trailers --in-place --if-exists replace `
        --trailer "Reviewed-by: $(@($s.reviewers) -join ', ')" `
        --trailer "Findings: $($s.fixed) fixed, $($s.rejected) rejected, $($s.accepted) accepted" `
        --trailer ('Net-lines: {0:+0;-0;+0}' -f $net) $file
    if ($LASTEXITCODE -ne 0) { Fail 'git interpret-trailers failed' }
}

function Invoke-PostCommit {   # the commit already happened: warn, never fail
    $s = Get-Stamp (git rev-parse 'HEAD^{tree}')
    if (-not $s) { Write-Host 'gate: warning: this commit has no review stamp, no note stored'; return }
    $tmp = [IO.Path]::GetTempFileName()
    [IO.File]::WriteAllText($tmp, $s.review)
    git notes --ref=review add -f -F $tmp HEAD | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host 'gate: warning: git notes failed' }
    Remove-Item $tmp
    if ($s.depsReason -and (Test-Path $basePath)) { $b = Read-Baseline; $b.deps = Get-Deps; Write-Baseline $b }
}

function Invoke-PrePush {
    $un = @(git status --porcelain --untracked-files=no | ForEach-Object { $_.Substring(3) } | Where-Object { $_ -ne '.spacex/baseline.json' })
    if ($un.Count) { Fail "commit or stash changes first ($($un -join ', '))" }
    $base = Read-Baseline
    $tc = @($cfg.testCommand)
    Need $tc[0]
    $exe, $targs = $tc
    & $exe @targs | Out-Host
    if ($LASTEXITCODE -ne 0) { Fail "tests failed: $($tc -join ' ')" }
    $dup = Get-Jscpd
    if ($dup -gt $base.jscpd) { Fail "duplicate count (jscpd) $dup > $($base.jscpd)" }
    $cur = Get-Counts
    $new = [ordered]@{ clippy = [ordered]@{}; machete = [Math]::Min($cur.machete, $base.machete); deps = [Math]::Min($cur.deps, $base.deps); jscpd = [Math]::Min($dup, $base.jscpd) }
    $down = @()
    foreach ($c in ($base.clippy.Keys | Sort-Object)) {
        $v = [Math]::Min([int]$cur.clippy[$c], $base.clippy[$c])
        if ($v -gt 0) { $new.clippy[$c] = $v }
        if ($v -lt $base.clippy[$c]) { $down += "$c $($base.clippy[$c]) -> $v" }
    }
    foreach ($k in 'machete', 'deps', 'jscpd') { if ($new[$k] -lt $base[$k]) { $down += "$k $($base[$k]) -> $($new[$k])" } }
    Write-Baseline $new
    if ($down) { Write-Host "gate: counts went down: $($down -join '; ')"; Write-Host 'gate: commit .spacex/baseline.json with your next change' }
}

switch ($Cmd) {
    'check' { Invoke-Check $Rest }
    'stamp' { Invoke-Stamp $Rest[0] }
    'pre-commit' { Invoke-PreCommit }
    'commit-msg' { Invoke-CommitMsg $Rest[0] }
    'post-commit' { Invoke-PostCommit }
    'pre-push' { Invoke-PrePush }
    'baseline' {
        $cur = Get-Counts
        $b = [ordered]@{ clippy = $cur.clippy; machete = $cur.machete; deps = $cur.deps; jscpd = Get-Jscpd }
        Write-Baseline $b
        Write-Host ($b | ConvertTo-Json -Depth 5)
    }
    default { Fail 'usage: gate.ps1 <check|stamp|pre-commit|commit-msg|post-commit|pre-push|baseline> [args]' }
}
Write-Host "gate: $Cmd OK"
