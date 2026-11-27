# Installs or updates the commit gate in a project.
# Usage: install.ps1 [-Target <repo folder>] [-Update]
# -Update replaces the kit files and hooks; it never touches config.json or baseline.json.
param([string]$Target = '.', [switch]$Update)
$kit = $PSScriptRoot
$root = git -C $Target rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0 -or -not $root) { Write-Host 'install: FAILED: target is not a git repository'; exit 1 }
$sx = Join-Path $root '.spacex'
$hk = Join-Path $root '.githooks'
$null = New-Item -ItemType Directory -Force $sx, $hk

Copy-Item (Join-Path $kit 'gate.ps1'), (Join-Path $kit 'REVIEW.md') $sx -Force
$ver = git -C $kit rev-parse --short HEAD
[IO.File]::WriteAllText((Join-Path $sx 'VERSION'), "$ver $(Get-Date -Format 'yyyy-MM-dd')`n")

# Hooks are shell scripts: write them with LF line endings, whatever the kit checkout has.
$hooks = @(Get-ChildItem (Join-Path $kit 'hooks') -File)
foreach ($f in $hooks) {
    $dest = Join-Path $hk $f.Name
    [IO.File]::WriteAllText($dest, ((Get-Content -Raw $f.FullName) -replace "`r`n", "`n"))
    if ($IsLinux -or $IsMacOS) { chmod +x $dest }
}
git -C $root add .githooks
if ($LASTEXITCODE -ne 0) { Write-Host 'install: FAILED: git add .githooks failed'; exit 1 }
foreach ($f in $hooks) {
    git -C $root update-index --chmod=+x ".githooks/$($f.Name)"
    if ($LASTEXITCODE -ne 0) { Write-Host "install: FAILED: git update-index --chmod=+x .githooks/$($f.Name) failed"; exit 1 }
}

# Keep the shims LF in every clone, also with core.autocrlf=true.
$ga = Join-Path $root '.gitattributes'
if (-not ((Test-Path $ga) -and (Select-String -Quiet -SimpleMatch '.githooks/* text eol=lf' $ga))) { [IO.File]::AppendAllText($ga, "`n.githooks/* text eol=lf`n") }

$cfg = Join-Path $sx 'config.json'
if (-not (Test-Path $cfg)) { Copy-Item (Join-Path $kit 'config.example.json') $cfg }
git -C $root config core.hooksPath .githooks

if (-not $Update -or -not (Test-Path (Join-Path $sx 'baseline.json'))) {
    Push-Location $root
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sx 'gate.ps1') baseline
    $rc = $LASTEXITCODE
    Pop-Location
    if ($rc -ne 0) { Write-Host 'install: FAILED: baseline was not written'; exit 1 }
}

Write-Host "install: gate $ver installed in $root"
Write-Host 'Next steps:'
Write-Host '  1. Edit .spacex/config.json: set risky and hotPaths for this project.'
Write-Host "  2. Add the block from $(Join-Path (Split-Path $kit) 'templates/instruction-block.md') to AGENTS.md and CLAUDE.md."
Write-Host '  3. Commit .spacex/, .githooks/ and .gitattributes.'
