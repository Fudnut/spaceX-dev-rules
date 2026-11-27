# SpaceX commit gate (Rust). Lives in a project as .spacex/gate.ps1; see .spacex/REVIEW.md.
# Usage: gate.ps1 <check|stamp|pre-commit|commit-msg|post-commit|pre-push|baseline> [args]
# Native stderr is not redirected, and $ErrorActionPreference stays default: Windows PowerShell 5.1 turns cargo progress into errors.
$Cmd = $args[0]
$Rest = @($args | Select-Object -Skip 1)

function Fail($msg) { Write-Host "gate: FAILED: $msg"; exit 1 }
function Need($tool) { if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { Fail "$tool not found" } }
function ConvertFrom-JsonOrFail($text, $what) { try { $j = $text | ConvertFrom-Json -ErrorAction Stop } catch { Fail "invalid JSON in $what" }; if ($null -eq $j) { Fail "empty JSON in $what" }; $j }
function Read-Json($path) { ConvertFrom-JsonOrFail ([IO.File]::ReadAllText($path)) $path }
function Test-Hooks { $hp = git config core.hooksPath; if ($LASTEXITCODE -ne 0 -or $hp -ne '.githooks') { Fail 'core.hooksPath is not .githooks; run: git config core.hooksPath .githooks' } }

$root = git rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0 -or -not $root) { Fail 'not in a git repository' }
Set-Location -LiteralPath $root
$basePath = Join-Path $root '.spacex/baseline.json'
$stampDir = git rev-parse --git-path spacex/stamps
if ($LASTEXITCODE -ne 0 -or -not $stampDir) { Fail 'git rev-parse --git-path failed' }
if (-not [IO.Path]::IsPathRooted($stampDir)) { $stampDir = Join-Path $root $stampDir }
$diffFlags = @('--no-color', '--no-ext-diff', '--src-prefix=a/', '--dst-prefix=b/')
$curOs = if ($IsLinux) { 'linux' } elseif ($IsMacOS) { 'macos' } else { 'windows' }

# Settings: .spacex/config.json, with these defaults for missing keys.
$defaults = @{
    risky = @(); hotPaths = @(); maxDiffLines = 400; lightMaxLines = 20
    testCommand = @('cargo', 'test', '--workspace', '--locked'); testScope = 'full'; jscpdPaths = @('crates')
}
$cfgFile = Join-Path $root '.spacex/config.json'
$user = $null
if (Test-Path $cfgFile) { $user = Read-Json $cfgFile }
$cfg = @{}
foreach ($k in @($defaults.Keys)) { $cfg[$k] = if ($user -and $null -ne $user.$k) { $user.$k } else { $defaults[$k] } }

function Test-Glob($path, $globs) { foreach ($g in @($globs)) { if ($path -like $g) { return $true } }; $false }
function Get-Tree { $t = git write-tree; if ($LASTEXITCODE -ne 0 -or -not $t) { Fail 'git write-tree failed (unmerged files?)' }; $t }
function Get-StampPath($tree) { Join-Path $stampDir "$tree.json" }
function Get-Stamp($tree) { $p = Get-StampPath $tree; if (Test-Path $p) { Read-Json $p } }
function Get-Family($name) { ([string]$name -split '/')[0].Trim().ToLower() }
function Get-Deps { if (Test-Path Cargo.lock) { @(Get-Content Cargo.lock | Where-Object { $_ -eq '[[package]]' }).Count } else { 0 } }

function Get-Staged {
    $lines = @(git -c core.quotepath=off diff @diffFlags --cached --numstat --no-renames); if ($LASTEXITCODE -ne 0) { Fail 'git diff --numstat failed' }
    foreach ($l in $lines) {
        if (-not $l) { continue }
        $p = $l -split "`t", 3
        $a = 0; $d = 0
        if ($p[0] -ne '-') { $a = [int]$p[0]; $d = [int]$p[1] }
        [pscustomobject]@{ path = $p[2]; added = $a; deleted = $d; lines = $a + $d }
    }
}

function Get-Counted {   # added lines in staged .rs files that are not blank, comments or test code
    $lines = @(git -c core.quotepath=off diff @diffFlags --cached -U0 --no-renames -- '*.rs'); if ($LASTEXITCODE -ne 0) { Fail 'git diff -U0 failed' }
    $n = 0; $cut = 0; $ln = 0; $skip = $true
    foreach ($l in $lines) {
        if ($l -match '^\+\+\+ (b/(.*)|/dev/null)') {
            $p = "$($Matches[2])".TrimEnd("`t")
            $skip = (-not $p) -or $p -match '(^|/)tests/' -or $p -like '*tests.rs'
            if (-not $skip) {
                $src = @(git show ":$p"); if ($LASTEXITCODE -ne 0) { Fail "git show :$p failed" }
                $cut = [int]::MaxValue
                for ($i = 0; $i -lt $src.Count; $i++) {
                    if ($src[$i].Trim() -cne '#[cfg(test)]') { continue }
                    $j = $i + 1; while ($j -lt $src.Count -and -not $src[$j].Trim()) { $j++ }
                    if ($j -lt $src.Count -and $src[$j] -match '^\s*(pub(\([^)]*\))?\s+)?mod\s+\w+\s*\{') { $cut = $i + 1; break }
                }
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
    $out = cargo clippy --locked --workspace --all-targets --message-format=json -- -D clippy::all -W clippy::pedantic -W clippy::cognitive_complexity -W clippy::too_many_lines
    $rc = $LASTEXITCODE
    $clippy = [ordered]@{}
    $errs = @()
    foreach ($l in $out) {
        if ($l -notmatch '"reason":"compiler-message"') { continue }
        $m = (ConvertFrom-JsonOrFail $l 'cargo clippy output').message
        if ($m.level -eq 'error') { $errs += $m.rendered }
        elseif ($m.level -eq 'warning' -and $m.code -and $m.code.code) { $clippy[$m.code.code] = 1 + [int]$clippy[$m.code.code] }
    }
    if ($errs) { Write-Host ($errs -join "`n"); Fail "cargo clippy reports $($errs.Count) error(s)" }
    if ($rc -ne 0) { Fail "cargo clippy exited $rc" }
    $mo = @(cargo machete)   # exit 0 = none; exit 1 = unused deps on indented rows
    if ($LASTEXITCODE -eq 0) { $mach = 0 }
    elseif ($LASTEXITCODE -eq 1) { $mach = @($mo | Where-Object { $_ -match '^[\t ]+\S' }).Count; if ($mach -eq 0) { Fail 'cargo machete exited 1 with no unused rows' } }
    else { Fail "cargo machete exited $LASTEXITCODE (is cargo-machete installed?)" }
    [ordered]@{ clippy = $clippy; machete = $mach; deps = Get-Deps }
}

function Get-Excess($cur, $base) {   # clippy and machete counts above the baseline
    foreach ($c in $cur.clippy.Keys) { $b = [int]$base.clippy[$c]; if ($cur.clippy[$c] -gt $b) { "$c $($cur.clippy[$c]) > $b" } }
    if ($cur.machete -gt $base.machete) { "unused dependencies (machete) $($cur.machete) > $($base.machete)" }
}

function Get-Jscpd {
    Need jscpd
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('jscpd-' + [guid]::NewGuid())
    $null = jscpd @($cfg.jscpdPaths) --min-lines 10 --format rust --reporters json --output $tmp --silent
    $rc = $LASTEXITCODE; $rep = Join-Path $tmp 'jscpd-report.json'
    if ($rc -ne 0 -or -not (Test-Path $rep)) { if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }; Fail "jscpd failed (exit $rc)" }
    $j = Read-Json $rep
    Remove-Item -Recurse -Force $tmp
    $v = if ($j -and $j.statistics -and $j.statistics.total -and $j.statistics.total.PSObject.Properties['clones']) { $j.statistics.total.clones } else { $null }
    if (-not ($v -is [int] -or $v -is [long]) -or $v -lt 0) { Fail 'jscpd report missing valid statistics.total.clones' }
    [int]$v
}

function Read-Baseline($spec) {
    $raw = git show $spec
    if ($LASTEXITCODE -ne 0 -or -not $raw) { Fail "cannot read $spec (stage .spacex/baseline.json, or ask Steve to run gate.ps1 baseline)" }
    $j = ConvertFrom-JsonOrFail ($raw -join "`n") $spec
    $b = [ordered]@{ clippy = [ordered]@{}; machete = 0; deps = 0; jscpd = 0 }
    if ($j.os) { $b.os = [string]$j.os }
    if ($j.clippy) { foreach ($p in $j.clippy.PSObject.Properties) { $b.clippy[$p.Name] = [int]$p.Value } }
    foreach ($k in 'machete', 'deps', 'jscpd') { if ($null -ne $j.$k) { $b[$k] = [int]$j.$k } }
    $b
}
function Write-Baseline($b) {
    try { $null = New-Item -ItemType Directory -Force (Split-Path $basePath); [IO.File]::WriteAllText($basePath, ($b | ConvertTo-Json -Depth 5)) }
    catch { Fail "could not write $basePath`: $_" }
}

function Invoke-Check($mode, $testArgs) {
    if ($mode -eq 'check') { Test-Hooks }
    Need cargo
    $st = @(Get-Staged); $size = Get-Counted; $tier = Get-Tier $st $size; $bad = @()
    if ($size -gt $cfg.maxDiffLines) {
        if ($mode -eq 'check') { Write-Host "gate: note: $size counted lines (max $($cfg.maxDiffLines)): needs Large approval in the stamp" }
        elseif (-not (($s = Get-Stamp (Get-Tree)) -and $s.large -and $s.largeApproved -eq 'Steve')) { $bad += "$size counted lines (max $($cfg.maxDiffLines)): split into stamped commits (.spacex/REVIEW.md), or add Large: <reason> and Large-approved: Steve" }
    }
    cargo fmt --all -- --check | Out-Host
    if ($LASTEXITCODE -ne 0) { $bad += 'cargo fmt --check failed (run cargo fmt)' }
    $base = Read-Baseline ':.spacex/baseline.json'
    $cur = Get-Counts
    $bad += @(Get-Excess $cur $base)
    if ($cur.deps -gt $base.deps) {
        if ($mode -eq 'check') { Write-Host "gate: note: dependency count $($cur.deps) > $($base.deps): needs Dependency-reason in the stamp" }
        else { $bad += "dependency count $($cur.deps) > $($base.deps): add Dependency-reason to the review and stamp again" }
    }
    Write-Host "gate: tier $tier, $size counted lines"
    if ($bad) { Fail ($bad -join '; ') }
    if ($testArgs) { cargo test --locked @testArgs | Out-Host; if ($LASTEXITCODE -ne 0) { Fail 'cargo test failed' } }
}

function Invoke-Stamp($file) {
    Test-Hooks
    if (-not $file -or -not (Test-Path $file)) { Fail 'usage: gate.ps1 stamp <review file>' }
    $text = [IO.File]::ReadAllText((Resolve-Path $file).ProviderPath)   # plain string: Get-Content adds PSPath notes that ConvertTo-Json writes out on 5.1
    $st = @(Get-Staged); $size = Get-Counted; $tier = Get-Tier $st $size
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
    if ($tier -eq 'Risky' -and $h['Reviewer-B'] -notmatch 'opus' -and -not ($w -eq 'claude' -and $b -eq 'codex')) { $bad += 'Risky tier needs Reviewer-B on Opus, or Codex when the writer is Claude' }
    if (-not $h['Timing'] -and @($st | Where-Object { Test-Glob $_.path $cfg.hotPaths }).Count) { $bad += 'a hot path is staged: Timing is required' }
    if ($h['Large'] -and $h['Large-approved'] -ne 'Steve') { $bad += 'Large: needs Large-approved: Steve (add it only after Steve says so in chat)' }
    if ($h['Final'] -cnotmatch '^claude/\S+\s+OK$') { $bad += "no 'Final: claude/<model> OK' line: the Claude orchestrator must review the whole staged diff before the stamp" }
    $n = @{ fixed = 0; rejected = 0; accepted = 0 }
    foreach ($l in ($text -split '\r?\n')) {
        if ($l -notmatch '^\s*\|') { continue }
        $cells = @(($l.Trim().Trim('|') -split '(?<!\\)\|') | ForEach-Object { $_.Trim() })
        if ($cells[0] -eq 'ID' -or $cells[0] -match '^:?-+:?$') { continue }
        if ($cells[0] -notmatch '^[AB]\d+$' -or $cells.Count -ne 12) { $bad += "finding $($cells[0]): malformed row"; continue }
        $s = $cells[11]
        if ($s -eq 'FIXED') { if ($tier -ne 'Light' -and ($cells[9] -cne 'CONFIRMED' -or $cells[10] -cne 'CONFIRMED')) { $bad += "finding $($cells[0]): FIXED needs CONFIRMED from A and B" }; $n.fixed++ }
        elseif ($s -match '^REJECTED \(.+\)$') { $n.rejected++ }
        elseif ($s -eq 'ACCEPTED (Steve)') { $n.accepted++ }
        else { $bad += "finding $($cells[0]) has status '$s'" }
    }
    $base = Read-Baseline ':.spacex/baseline.json'; $deps = Get-Deps
    if ($deps -gt $base.deps -and -not $h['Dependency-reason']) { $bad += "dependency count $deps > $($base.deps): Dependency-reason is required" }
    if ($bad) { Fail ($bad -join '; ') }
    if ($deps -gt $base.deps) { $base.deps = $deps; Write-Baseline $base; git add .spacex/baseline.json; if ($LASTEXITCODE -ne 0) { Fail 'git add .spacex/baseline.json failed' } }
    $tree = Get-Tree
    $obj = [ordered]@{
        tree = $tree; tier = $tier; writer = $h['Writer']
        reviewers = @($h['Reviewer-A'], $h['Reviewer-B'] | Where-Object { $_ })
        fixed = $n.fixed; rejected = $n.rejected; accepted = $n.accepted
        depsReason = $h['Dependency-reason']; large = $h['Large']; largeApproved = $h['Large-approved']; review = $text
    }
    try { $null = New-Item -ItemType Directory -Force $stampDir; [IO.File]::WriteAllText((Get-StampPath $tree), ($obj | ConvertTo-Json -Depth 5)) }
    catch { Fail "could not write stamp: $_" }
    Write-Host "gate: stamped $tree ($tier)"
}

function Invoke-PreCommit {
    $u1 = @(git -c core.quotepath=off diff @diffFlags --name-only); if ($LASTEXITCODE -ne 0) { Fail 'git diff --name-only failed' }
    $u2 = @(git -c core.quotepath=off ls-files --others --exclude-standard); if ($LASTEXITCODE -ne 0) { Fail 'git ls-files failed' }
    $un = @(($u1 + $u2) | Where-Object { $_ -and $_ -ne '.spacex/baseline.json' })
    if ($un.Count) { Fail "stage or stash unstaged or untracked changes: the checks must see the staged content ($($un -join ', '))" }
    $tree = Get-Tree
    if (-not (Test-Path (Get-StampPath $tree))) { Fail "no review stamp for staged tree $tree; run the review in .spacex/REVIEW.md, then gate.ps1 stamp <file>" }
    Invoke-Check 'pre-commit' @()
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
    $tree = git rev-parse 'HEAD^{tree}'
    if ($LASTEXITCODE -ne 0 -or -not $tree) { Write-Host 'gate: warning: git rev-parse HEAD^{tree} failed, no note stored'; return }
    $s = Get-Stamp $tree
    if (-not $s) { Write-Host 'gate: warning: this commit has no review stamp, no note stored'; return }
    $tmp = [IO.Path]::GetTempFileName()
    [IO.File]::WriteAllText($tmp, $s.review)
    git notes --ref=review add -f -F $tmp HEAD | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host 'gate: warning: git notes failed' }
    Remove-Item $tmp
}

function Get-TestCrates($pairs) {   # testScope affected: workspace crates whose tests can see the pushed change (pairs of remote sha, local sha) and whether it touches a risky path, or a string that says why all tests must run
    if (@($cfg.testCommand) -notcontains '--workspace') { return 'testCommand has no --workspace to narrow' }
    $files = @()
    foreach ($pr in $pairs) {
        if ($pr[1] -match '^0+$') { continue }   # deletion: no code goes out
        if ($pr[0] -match '^0+$') { return 'new branch' }
        $f = @(git -c core.quotepath=off diff --name-only --no-renames $pr[0] $pr[1]); if ($LASTEXITCODE -ne 0) { return "git diff $($pr[0]) $($pr[1]) failed" }
        $files += $f
    }
    $slow = [bool]@($files | Where-Object { $_ -eq '.spacex/config.json' -or (Test-Glob $_ $cfg.risky) }).Count   # config.json may change risky itself
    $files = @($files | Where-Object { $_ -notlike '.spacex/*' })   # kit files and gate settings: no test reads them
    $f = @($files | Where-Object { $_ -match '(^|/)(Cargo\.(toml|lock)|rust-toolchain(\.toml)?)$|^\.cargo/' })
    if ($f) { return "$($f[0]) changed" }
    $raw = cargo metadata --no-deps --format-version 1
    if ($LASTEXITCODE -ne 0) { return "cargo metadata exited $LASTEXITCODE" }
    try { $meta = ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop } catch { return 'cargo metadata gave invalid JSON' }
    $top = ($root -replace '\\', '/').TrimEnd('/') + '/'
    $dirs = @{}; $deps = @{}
    foreach ($pk in @($meta.packages)) {
        $d = ([IO.Path]::GetDirectoryName($pk.manifest_path) -replace '\\', '/') + '/'
        if (-not $d.StartsWith($top, 'OrdinalIgnoreCase')) { return "crate $($pk.name) is outside the repository" }
        $dirs[$pk.name] = $d.Substring($top.Length)   # '' for a crate at the repository root
        $deps[$pk.name] = @($pk.dependencies | ForEach-Object { $_.name })   # all kinds: normal, dev, build
    }
    if (-not $dirs.Count) { return 'cargo metadata lists no crates' }
    $hit = @{}
    foreach ($f in $files) {   # a file belongs to the crate with the longest matching folder
        $best = $null
        foreach ($n in $dirs.Keys) { if ($f.StartsWith($dirs[$n], 'OrdinalIgnoreCase') -and (-not $best -or $dirs[$n].Length -gt $dirs[$best].Length)) { $best = $n } }
        if ($best) { $hit[$best] = 1 } elseif ($f -notlike '*.md') { return "$f is in no crate" }   # only docs may sit outside crates
    }
    do {   # add the crates that depend on a selected crate, transitively
        $more = @($deps.Keys | Where-Object { -not $hit[$_] -and @($deps[$_] | Where-Object { $hit[$_] }).Count })
        foreach ($n in $more) { $hit[$n] = 1 }
    } while ($more.Count)
    [pscustomobject]@{ crates = @($hit.Keys | Sort-Object); slow = $slow }
}

function Invoke-PrePush {
    $head = git rev-parse HEAD; if ($LASTEXITCODE -ne 0 -or -not $head) { Fail 'git rev-parse HEAD failed' }
    $scope = [string]$cfg.testScope
    if ($scope -notin 'full', 'affected') { Fail "config.json testScope must be full or affected, not '$scope'" }
    $code = 0; $notes = 0; $pairs = @()
    foreach ($l in ([Console]::In.ReadToEnd() -split '\r?\n')) {
        if (-not $l.Trim()) { continue }
        $p = $l.Trim() -split '\s+'
        if ($p.Count -lt 4) { Fail "unexpected pre-push ref line: $l" }
        if ($p[0] -like 'refs/notes/*' -and $p[2] -like 'refs/notes/*') { $notes++; continue }   # notes hold no code
        $code++
        if ($p[1] -notmatch '^0+$' -and $p[1] -ne $head) { Fail "pre-push checks only the checked-out HEAD; check out $($p[0]) and push it alone" }
        $pairs += , @($p[3], $p[1])
    }
    if ($notes -and -not $code) { Write-Host 'gate: notes refs only; no tests'; return }
    $st = @(git -c core.quotepath=off status --porcelain --untracked-files=normal); if ($LASTEXITCODE -ne 0) { Fail 'git status failed' }
    $un = @($st | Where-Object { $_ } | ForEach-Object { $_.Substring(3) } | Where-Object { $_ -ne '.spacex/baseline.json' })
    if ($un.Count) { Fail "commit or stash changes first ($($un -join ', '))" }
    $base = Read-Baseline 'HEAD:.spacex/baseline.json'
    $tc = @($cfg.testCommand)
    $env:SPACEX_SLOW_TESTS = '1'   # slow tests run unless the push is narrowed to crates and touches no risky path
    if ($scope -eq 'affected') {
        $r = Get-TestCrates $pairs
        if ($r -is [string]) { Write-Host "gate: tests: full, because $r" }
        elseif (-not $r.crates.Count) { Write-Host 'gate: tests: none, no crate changed'; $tc = @() }
        else {
            $tc = @($tc | ForEach-Object { if ($_ -eq '--workspace') { $r.crates | ForEach-Object { '-p'; $_ } } else { $_ } })
            if (-not $r.slow) { $env:SPACEX_SLOW_TESTS = $null }
            Write-Host "gate: tests: changed crates and their dependents, slow tests $(if ($r.slow) { 'on (risky path or config.json changed)' } else { 'off' }): $($tc -join ' ')"
        }
    }
    if ($tc) {
        Need $tc[0]
        $exe, $targs = $tc
        & $exe @targs | Out-Host
        if ($LASTEXITCODE -ne 0) { Fail "tests failed: $($tc -join ' ')" }
    }
    $dup = Get-Jscpd
    $cur = Get-Counts
    $bad = @(Get-Excess $cur $base)
    if ($cur.deps -gt $base.deps) { $bad += "dependency count $($cur.deps) > $($base.deps)" }
    if ($dup -gt $base.jscpd) { $bad += "duplicate count (jscpd) $dup > $($base.jscpd)" }
    if ($bad) { Fail ($bad -join '; ') }
    if (-not $base.os) { Write-Host 'gate: baseline has no os; counts not lowered'; return }
    if ($base.os -ne $curOs) { return }
    $new = [ordered]@{ os = $curOs; clippy = $cur.clippy; machete = $cur.machete; deps = $cur.deps; jscpd = $dup }
    $down = @()
    foreach ($c in $base.clippy.Keys) { $v = [int]$cur.clippy[$c]; if ($v -lt $base.clippy[$c]) { $down += "$c $($base.clippy[$c]) -> $v" } }
    foreach ($k in 'machete', 'deps', 'jscpd') { if ($new[$k] -lt $base[$k]) { $down += "$k $($base[$k]) -> $($new[$k])" } }
    if ($down) { Write-Baseline $new; Write-Host "gate: counts went down: $($down -join '; ')"; Write-Host 'gate: commit .spacex/baseline.json with your next change' }
}

if ($MyInvocation.InvocationName -eq '.') { return }   # dot-sourced by test-affected.ps1: define the functions only
switch ($Cmd) {
    'check' { Invoke-Check 'check' $Rest }
    'stamp' { Invoke-Stamp $Rest[0] }
    'pre-commit' { Invoke-PreCommit }
    'commit-msg' { Invoke-CommitMsg $Rest[0] }
    'post-commit' { Invoke-PostCommit }
    'pre-push' { Invoke-PrePush }
    'baseline' {
        $cur = Get-Counts
        $b = [ordered]@{ os = $curOs; clippy = $cur.clippy; machete = $cur.machete; deps = $cur.deps; jscpd = Get-Jscpd }
        Write-Baseline $b
        Write-Host ($b | ConvertTo-Json -Depth 5)
    }
    default { Fail 'usage: gate.ps1 <check|stamp|pre-commit|commit-msg|post-commit|pre-push|baseline> [args]' }
}
Write-Host "gate: $Cmd OK"
