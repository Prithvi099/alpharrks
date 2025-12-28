param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$Args
)

# Resolve repo root (script location)
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$script = Join-Path $repoRoot 'scripts\dc.ps1'

if (-not (Test-Path $script)) {
    Write-Error "Wrapper script not found: $script"
    exit 1
}

# Forward args to scripts\dc.ps1
Write-Host "Forwarding to scripts\dc.ps1 with args: $($Args -join ' ')" -ForegroundColor Cyan
& $script @Args
exit $LASTEXITCODE
