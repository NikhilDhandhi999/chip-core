# publish_github.ps1 - Commits and pushes updates to NikhilDhandhi999/chip-core
$ErrorActionPreference = "Stop"

git add .
git commit -m "Update chip-core v7.2: Evidence-separated PPA report, dual-workload regression, and AI disclosure"
git push -u origin main
Write-Host "Published! View at: https://github.com/NikhilDhandhi999/chip-core" -ForegroundColor Green
