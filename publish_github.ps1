# publish_github.ps1 - Initializes Git & publishes chip-core to GitHub via GitHub CLI (`gh`)
$ErrorActionPreference = "Stop"

if (-not (Get-Command "git" -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: git not found in PATH." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path ".git")) {
    git init -b main
}

git add .
git commit -m "Release chip-core v7.0: Programmable 1.58-Bit Ternary & Transformer AI SoC with UART Host Bridge"

if (Get-Command "gh" -ErrorAction SilentlyContinue) {
    $repoExists = gh repo view nicks0098/chip-core 2>$null
    if (-not $repoExists) {
        Write-Host "Creating public GitHub repository nicks0098/chip-core..." -ForegroundColor Cyan
        gh repo create nicks0098/chip-core --public --source=. --remote=origin --push --description "Custom 1.58-Bit Ternary & Transformer Self-Attention AI Accelerator SoC in Synthesizable Verilog RTL"
    } else {
        Write-Host "Pushing updates to nicks0098/chip-core..." -ForegroundColor Cyan
        git push -u origin main
    }
    Write-Host "Published! View at: https://github.com/nicks0098/chip-core" -ForegroundColor Green
} else {
    Write-Host "Git commit created! Install GitHub CLI (`gh`) or add a remote URL to push." -ForegroundColor Yellow
}
