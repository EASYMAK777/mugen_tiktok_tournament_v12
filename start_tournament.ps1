# ============================================================
# Launches Tournament + TikTok Offline Tester side by side
# Usage:
#   powershell.exe -ExecutionPolicy Bypass -File start_tournament.ps1
#   powershell.exe -ExecutionPolicy Bypass -File start_tournament.ps1 -BracketSize 32 -Difficulty 8
# ============================================================

param(
    [ValidateSet(8, 16, 32, 64)]
    [int]$BracketSize = 16,
    [ValidateRange(1, 8)]
    [int]$Difficulty = 8,
    [int]$MaxFightMinutes = 10,
    [int]$MaxDrawRetries = 3
)

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Start the TikTok offline tester in a new window
$tiktokTest = Join-Path $projectRoot "tiktok_test.py"
Start-Process -FilePath "python" -ArgumentList "`"$tiktokTest`"" -WorkingDirectory $projectRoot

Write-Host "TikTok tester launched in separate window." -ForegroundColor Cyan
Write-Host ""

# Run the tournament in this window
$tournamentScript = Join-Path $projectRoot "tournament.ps1"
& $tournamentScript -BracketSize $BracketSize -Difficulty $Difficulty -MaxFightMinutes $MaxFightMinutes -MaxDrawRetries $MaxDrawRetries
