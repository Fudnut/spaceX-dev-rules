# Runs the project gates in order. Stops at the first failure and returns its exit code.
# Copy to the project root and replace the steps with the project's own format, lint, type and test commands
# (take them from CI or the project's CLAUDE.md; do not add new tools).
# Usage: .\check.ps1                 all gates, whole test suite
#        .\check.ps1 <test args>     all gates, only the given test arguments (focused run)
# Pilot: F:\AI_Projects_3\File_manager\check.ps1 (Rust: cargo fmt, clippy, Linux check, cargo test).
Set-Location $PSScriptRoot
$testArgs = if ($args.Count) { $args } else { @('--workspace') }   # default: the whole suite

# One array per step: the program first, then its arguments.
$steps = @(
    , @('cargo', 'fmt', '--all', '--', '--check')                                    # format
    , @('cargo', 'clippy', '--workspace', '--all-targets', '--locked', '--', '-D', 'warnings')  # lint and types
    , (@('cargo', 'test', '--locked') + $testArgs)                                    # tests
)
foreach ($step in $steps) {
    $exe, $rest = $step
    Write-Host "==> $($step -join ' ')"
    & $exe @rest
    if ($LASTEXITCODE -ne 0) {
        Write-Host "check.ps1 FAILED (exit $LASTEXITCODE): $($step -join ' ')"
        exit $LASTEXITCODE
    }
}
Write-Host 'check.ps1: all gates passed'
exit 0
