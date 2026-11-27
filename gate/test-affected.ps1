# Tests for testScope "affected": Get-TestCrates in gate.ps1 maps pushed files to crates, or says why all tests run.
# Run: powershell -NoProfile -File gate/test-affected.ps1   (needs git and cargo; builds a throwaway workspace in the temp folder)
$gate = Join-Path $PSScriptRoot 'gate.ps1'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('gate-test-' + [guid]::NewGuid())
$null = New-Item -ItemType Directory $tmp
Push-Location -LiteralPath $tmp

function Write-File($path, $text) { $p = Join-Path $tmp $path; $null = New-Item -ItemType Directory -Force (Split-Path $p); [IO.File]::WriteAllText($p, $text) }
function New-Crate($name, $deps) { Write-File "crates/$name/Cargo.toml" "[package]`nname = `"$name`"`nversion = `"0.1.0`"`nedition = `"2021`"`n$deps"; Write-File "crates/$name/src/lib.rs" '' }
function New-Head($files) { git checkout -q --detach $base; foreach ($f in @($files)) { Write-File $f 'x' }; git add -A; git commit -qm change; git rev-parse HEAD }
function Test-Case($name, $pairs, $want) {
    $got = Get-TestCrates $pairs
    $g = if ($got -is [string]) { "full: $got" } elseif (-not $got.Count) { 'none' } else { "test: $($got -join ' ')" }
    if ($g -like $want) { Write-Host "ok   $name" } else { Write-Host "FAIL $name`: got '$g', want '$want'"; $script:fails++ }
}

# Workspace: b depends on a, c has a dev-dependency on b, d stands alone.
git init -q; git config user.name test; git config user.email test@example.invalid; git config commit.gpgsign false
Write-File 'Cargo.toml' "[workspace]`nresolver = `"2`"`nmembers = [`"crates/a`", `"crates/b`", `"crates/c`", `"crates/d`"]`n"
New-Crate a ''
New-Crate b "[dependencies]`na = { path = `"../a`" }`n"
New-Crate c "[dev-dependencies]`nb = { path = `"../b`" }`n"
New-Crate d ''
Write-File 'README.md' ''
git add -A; git commit -qm base
$base = git rev-parse HEAD
. $gate   # defines the functions only
$fails = 0
$z = '0' * 40

Test-Case 'docs only: no tests' @(, @($base, (New-Head 'README.md', 'docs/guide.md'))) 'none'
Test-Case 'non-.md file in no crate' @(, @($base, (New-Head 'fixtures/input.json'))) 'full: fixtures/input.json is in no crate'
Test-Case 'leaf crate' @(, @($base, (New-Head 'crates/d/src/lib.rs'))) 'test: d'
Test-Case 'reverse deps, transitive, dev-dependency' @(, @($base, (New-Head 'crates/a/src/lib.rs'))) 'test: a b c'
Test-Case 'middle crate' @(, @($base, (New-Head 'crates/b/src/lib.rs'))) 'test: b c'
Test-Case 'non-.rs file in a crate' @(, @($base, (New-Head 'crates/c/tests/data.txt'))) 'test: c'
Test-Case 'two crates' @(, @($base, (New-Head 'crates/d/src/x.rs', 'crates/b/src/lib.rs'))) 'test: b c d'
Test-Case 'deletion: no tests' @(, @($base, $z)) 'none'
Test-Case 'root Cargo.toml' @(, @($base, (New-Head 'Cargo.toml'))) 'full: Cargo.toml changed'
Test-Case 'crate Cargo.toml' @(, @($base, (New-Head 'crates/a/Cargo.toml'))) 'full: crates/a/Cargo.toml changed'
Test-Case 'Cargo.lock' @(, @($base, (New-Head 'Cargo.lock'))) 'full: Cargo.lock changed'
Test-Case 'rust-toolchain.toml' @(, @($base, (New-Head 'rust-toolchain.toml'))) 'full: rust-toolchain.toml changed'
Test-Case '.cargo/' @(, @($base, (New-Head '.cargo/config.toml'))) 'full: .cargo/config.toml changed'
Test-Case '.spacex/' @(, @($base, (New-Head '.spacex/config.json'))) 'full: .spacex/config.json changed'
Test-Case '.spacex/baseline.json only: no tests' @(, @($base, (New-Head '.spacex/baseline.json'))) 'none'
Test-Case '.spacex/baseline.json and a crate' @(, @($base, (New-Head '.spacex/baseline.json', 'crates/d/src/lib.rs'))) 'test: d'
Test-Case '.rs file in no crate' @(, @($base, (New-Head 'tools/gen.rs'))) 'full: tools/gen.rs is in no crate'
Test-Case 'crate folder prefix is not a match' @(, @($base, (New-Head 'crates/ab/src/x.rs'))) 'full: crates/ab/src/x.rs is in no crate'
Test-Case 'new branch' @(, @($z, (New-Head 'README.md'))) 'full: new branch'
$cfg.testCommand = @('cargo', 'nextest', 'run')
Test-Case 'testCommand without --workspace' @(, @($base, (New-Head 'crates/d/src/lib.rs'))) 'full: testCommand has no --workspace to narrow'
$cfg.testCommand = $defaults.testCommand
Test-Case 'remote sha unknown here' @(, @(('f' * 40), (New-Head 'README.md'))) 'full: git diff * failed'
$h = New-Head 'crates/d/src/lib.rs'; Write-File 'crates/d/Cargo.toml' 'not toml ['   # last: leaves the work tree broken
Test-Case 'cargo metadata fails' @(, @($base, $h)) 'full: cargo metadata exited *'

Pop-Location
Remove-Item -Recurse -Force -LiteralPath $tmp
Write-Host "$fails failed"
exit [int]($fails -gt 0)
