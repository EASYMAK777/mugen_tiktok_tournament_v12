# ============================================================
# IkemenGO Tournament Mode - Single Elimination Bracket
# ============================================================
# Runs an AI vs AI single-elimination tournament with automated
# match progression. User reports the winner with a single
# keypress after each fight, then the next fight launches
# automatically.
#
# Flow: IkemenGO launches -> fight plays -> user clicks terminal
#       -> presses 1 or 2 -> IkemenGO closes -> next fight
#
# Usage:
#   powershell.exe -ExecutionPolicy Bypass -File tournament.ps1
#   powershell.exe -ExecutionPolicy Bypass -File tournament.ps1 -BracketSize 32 -Difficulty 8
#
# Parameters:
#   -BracketSize   8, 16, 32, or 64 (default 16)
#   -Difficulty    AI difficulty 1-8 (default 7)
#   -MaxFightMinutes  Safety timeout per fight (default 10)
#   -MaxDrawRetries   Replays before coin flip on draw (default 3)
# ============================================================

param(
    [ValidateSet(8, 16, 32, 64)]
    [int]$BracketSize = 16,
    [ValidateRange(1, 8)]
    [int]$Difficulty = 8,
    [int]$MaxFightMinutes = 10,
    [int]$MaxDrawRetries = 3
)

$MaxFightMinutes = [Math]::Max(1, $MaxFightMinutes)

# ============================================================
# Paths
# ============================================================
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ikemenExe   = Join-Path $projectRoot "MGRev2.5.exe"
$configIni   = Join-Path $projectRoot "save\config.ini"
$selectDef   = Join-Path $projectRoot "data\select.def"
$charsDir    = Join-Path $projectRoot "chars"
$stagesDir   = Join-Path $projectRoot "stages"
$htmlOutput  = Join-Path $projectRoot "tournament_bracket.html"

# Validate paths
foreach ($path in @($ikemenExe, $selectDef, $configIni)) {
    if (-not (Test-Path $path)) {
        Write-Host "ERROR: Not found: $path" -ForegroundColor Red
        exit 1
    }
}

# ============================================================
# Win32 API for moving window to secondary monitor
# ============================================================
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Window {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    public const uint SWP_NOSIZE = 0x0001;
    public const uint SWP_NOZORDER = 0x0004;
}
"@
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Move-ToSecondaryMonitor($process) {
    $screens = [System.Windows.Forms.Screen]::AllScreens
    if ($screens.Count -lt 2) { return }
    # Use the primary/built-in monitor for the game (TikTok captures this screen)
    $target = $screens | Where-Object { $_.Primary } | Select-Object -First 1
    if (-not $target) { return }
    $bounds = $target.WorkingArea
    $x = $bounds.X + [Math]::Max(0, ($bounds.Width - 1280) / 2)
    $y = $bounds.Y + [Math]::Max(0, ($bounds.Height - 720) / 2)
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        if ($process.HasExited) { return }
        $process.Refresh()
        $hWnd = $process.MainWindowHandle
        if ($hWnd -ne [IntPtr]::Zero) {
            [Win32Window]::SetWindowPos($hWnd, [IntPtr]::Zero, [int]$x, [int]$y, 0, 0, [Win32Window]::SWP_NOSIZE -bor [Win32Window]::SWP_NOZORDER) | Out-Null
            return
        }
    }
}

# ============================================================
# Config backup and restore
# ============================================================
$script:originalConfig = $null

function Backup-Config {
    if (Test-Path $configJson) {
        $script:originalConfig = Get-Content $configJson -Raw
    }
}

function Restore-Config {
    if ($script:originalConfig) {
        Set-Content -Path $configJson -Value $script:originalConfig -NoNewline
    }
}

$script:htmlOpened = $false
$script:winCounts = @{}

# ============================================================
# Character .def resolution
# ============================================================
function Resolve-CharDefPath([string]$entry) {
    if ($entry -match '[\\/]') {
        $defPath = Join-Path $charsDir $entry
    } else {
        $defPath = Join-Path $charsDir "$entry\$entry.def"
    }
    if (Test-Path $defPath) { return $defPath }
    # Try finding any .def in the character folder
    $charFolder = Join-Path $charsDir $entry
    if (Test-Path $charFolder) {
        $defs = Get-ChildItem -Path $charFolder -Filter "*.def" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($defs) { return $defs.FullName }
    }
    return $null
}

# ============================================================
# Parse chars directory for all valid characters
# ============================================================
function Get-AllCharacters {
    $chars = @()
    $dirs = Get-ChildItem -Path $charsDir -Directory -ErrorAction SilentlyContinue
    foreach ($dir in $dirs) {
        if ($dir.Name -eq "ALL JUS") { continue }
        # Check if FolderName/FolderName.def exists (standard layout)
        $standardDef = Join-Path $charsDir "$($dir.Name)\$($dir.Name).def"
        if (Test-Path $standardDef) {
            $chars += $dir.Name
            continue
        }
        # Otherwise find the actual .def and use relative path
        $defPath = Resolve-CharDefPath $dir.Name
        if ($defPath) {
            $defName = [System.IO.Path]::GetFileName($defPath)
            $chars += "$($dir.Name)/$defName"
        }
    }
    return $chars
}

# ============================================================
# Get all valid stages
# ============================================================
function Get-AllStages {
    $BLACKLIST = @("Lightning Desert.def", "The_Hopes_Gone_Super.def", "WastelandVP1.1.def")
    $stages = @()
    if (-not (Test-Path $stagesDir)) { return $stages }
    $defs = Get-ChildItem -Path $stagesDir -Filter "*.def" -ErrorAction SilentlyContinue
    foreach ($f in $defs) {
        if ($f.Name -in $BLACKLIST) { continue }
        $sff = [System.IO.Path]::ChangeExtension($f.FullName, ".sff")
        if (Test-Path $sff) {
            $stages += "stages/$($f.Name)"
        }
    }
    return $stages
}

# ============================================================
# Utility functions
# ============================================================
function Get-CharDisplayName([string]$entry) {
    if (-not $entry) { return "???" }
    if ($entry -match '\\') { return ($entry -split '\\')[0] }
    return $entry
}

function Get-RandomStage {
    if ($script:allStages.Count -eq 0) { return $null }
    return $script:allStages[(Get-Random -Maximum $script:allStages.Count)]
}

function Format-Duration([TimeSpan]$ts) {
    if ($ts.TotalMinutes -ge 1) {
        return "{0}m {1:D2}s" -f [int]$ts.TotalMinutes, $ts.Seconds
    }
    return "{0}s" -f [int]$ts.TotalSeconds
}

function Get-RoundName([int]$roundIdx, [int]$totalRounds) {
    $remaining = $totalRounds - $roundIdx
    switch ($remaining) {
        1 { return "GRAND FINALS" }
        2 { return "SEMIFINALS" }
        3 { return "QUARTERFINALS" }
        default {
            $participants = [Math]::Pow(2, $remaining)
            return "ROUND OF $([int]$participants)"
        }
    }
}

# ============================================================
# Bracket Data Structure
# ============================================================
function New-Bracket([string[]]$participants) {
    $numRounds = [int][Math]::Log($participants.Count, 2)
    $allRounds = @()

    # First round: pair participants
    $firstRound = @()
    for ($i = 0; $i -lt $participants.Count; $i += 2) {
        $firstRound += ,@{
            P1       = $participants[$i]
            P2       = $participants[$i + 1]
            Winner   = $null
            Loser    = $null
            Status   = "pending"
            MatchNum = ($i / 2) + 1
        }
    }
    $allRounds += ,@($firstRound)

    # Subsequent rounds: empty slots
    $matchesInRound = $firstRound.Count / 2
    for ($r = 1; $r -lt $numRounds; $r++) {
        $round = @()
        for ($m = 0; $m -lt $matchesInRound; $m++) {
            $round += ,@{
                P1       = $null
                P2       = $null
                Winner   = $null
                Loser    = $null
                Status   = "pending"
                MatchNum = $m + 1
            }
        }
        $allRounds += ,@($round)
        $matchesInRound = [Math]::Max(1, $matchesInRound / 2)
    }

    return $allRounds
}

function Advance-Winner($rounds, [int]$roundIdx, [int]$matchIdx) {
    if ($roundIdx -ge ($rounds.Count - 1)) { return }

    $nextRoundIdx = $roundIdx + 1
    $nextMatchIdx = [Math]::Floor($matchIdx / 2)
    $slot = if ($matchIdx % 2 -eq 0) { "P1" } else { "P2" }

    $winner = $rounds[$roundIdx][$matchIdx].Winner
    $rounds[$nextRoundIdx][$nextMatchIdx][$slot] = $winner
}

# ============================================================
# Character Selection
# ============================================================
function Select-TournamentParticipants([string[]]$allChars, [int]$count) {
    $pool = [System.Collections.ArrayList]::new($allChars)
    $selected = @()

    for ($i = 0; $i -lt $count -and $pool.Count -gt 0; $i++) {
        $idx = Get-Random -Maximum $pool.Count
        $entry = $pool[$idx]
        $pool.RemoveAt($idx)
        $selected += $entry
    }

    return $selected
}

# ============================================================
# Run a single match via IkemenGO CLI
# ============================================================
function Run-Match([string]$char1, [string]$char2, [string]$stage) {
    # AI jitter for variety
    $p1Ai = [Math]::Min(8, [Math]::Max(1, $Difficulty + (Get-Random -Minimum -1 -Maximum 2)))
    $p2Ai = [Math]::Min(8, [Math]::Max(1, $Difficulty + (Get-Random -Minimum -1 -Maximum 2)))

    # Build IkemenGO command line
    # -loadmotif ensures full engine init (mods, hooks, lifebars) before the fight
    $ikemenArgs = @()
    $ikemenArgs += "-loadmotif"
    $ikemenArgs += "-p1"
    $ikemenArgs += "`"$char1`""
    $ikemenArgs += "-p1.ai"
    $ikemenArgs += "$p1Ai"
    $ikemenArgs += "-p2"
    $ikemenArgs += "`"$char2`""
    $ikemenArgs += "-p2.ai"
    $ikemenArgs += "$p2Ai"
    $ikemenArgs += "-rounds"
    $ikemenArgs += "2"
    if ($stage) {
        $ikemenArgs += "-s"
        $ikemenArgs += "`"$stage`""
    }

    $argString = $ikemenArgs -join " "
    $fightStart = Get-Date

    $p1Display = Get-CharDisplayName $char1
    $p2Display = Get-CharDisplayName $char2

    $process = Start-Process -FilePath $ikemenExe -ArgumentList $argString -WorkingDirectory $projectRoot -PassThru

    # Move window to secondary monitor if available
    Move-ToSecondaryMonitor $process

    # Auto-detect match result from Lua mod
    $resultFile = Join-Path $projectRoot "match_result.json"

    # Clear any old result
    if (Test-Path $resultFile) { "" | Set-Content $resultFile }

    Write-Host ""
    Write-Host "    ================================================" -ForegroundColor DarkYellow
    Write-Host "    FIGHT IN PROGRESS! (AI: P1=$p1Ai P2=$p2Ai)" -ForegroundColor Yellow
    Write-Host "    $p1Display  vs  $p2Display" -ForegroundColor White
    Write-Host "    Auto-detecting winner..." -ForegroundColor DarkGray
    Write-Host "    (Press 1/2/D to override manually)" -ForegroundColor DarkGray
    Write-Host "    ================================================" -ForegroundColor DarkYellow
    Write-Host ""

    $result = $null
    $maxWaitSeconds = $MaxFightMinutes * 60
    $elapsed = 0

    while (-not $result) {
        # Check for auto-detected result from Lua mod
        if (Test-Path $resultFile) {
            $content = Get-Content $resultFile -Raw -ErrorAction SilentlyContinue
            if ($content -and $content.Trim().Length -gt 2) {
                try {
                    $matchResult = $content | ConvertFrom-Json
                    if ($matchResult.winner -eq "1") {
                        $result = @{ Result = "win"; WinnerSide = 1 }
                        Write-Host "    AUTO-DETECTED: $p1Display wins!" -ForegroundColor Green
                    } elseif ($matchResult.winner -eq "2") {
                        $result = @{ Result = "win"; WinnerSide = 2 }
                        Write-Host "    AUTO-DETECTED: $p2Display wins!" -ForegroundColor Green
                    } elseif ($matchResult.winner -eq "draw") {
                        $result = @{ Result = "draw"; WinnerSide = 0 }
                        Write-Host "    AUTO-DETECTED: Draw!" -ForegroundColor DarkYellow
                    }
                } catch {}
            }
        }

        # Allow manual override via keyboard (non-blocking)
        if (-not $result -and [Console]::KeyAvailable) {
            $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            switch ($key.Character) {
                '1' { $result = @{ Result = "win"; WinnerSide = 1 }; Write-Host "    MANUAL: $p1Display wins!" -ForegroundColor Cyan }
                '2' { $result = @{ Result = "win"; WinnerSide = 2 }; Write-Host "    MANUAL: $p2Display wins!" -ForegroundColor Cyan }
                'd' { $result = @{ Result = "draw"; WinnerSide = 0 }; Write-Host "    MANUAL: Draw!" -ForegroundColor Cyan }
                'D' { $result = @{ Result = "draw"; WinnerSide = 0 }; Write-Host "    MANUAL: Draw!" -ForegroundColor Cyan }
            }
        }

        # Check if game crashed/exited without a result
        if (-not $result -and $process.HasExited) {
            Start-Sleep -Milliseconds 500
            # One last check for the result file
            if (Test-Path $resultFile) {
                $content = Get-Content $resultFile -Raw -ErrorAction SilentlyContinue
                if ($content -and $content.Trim().Length -gt 2) {
                    try {
                        $matchResult = $content | ConvertFrom-Json
                        if ($matchResult.winner -eq "1") {
                            $result = @{ Result = "win"; WinnerSide = 1 }
                            Write-Host "    AUTO-DETECTED: $p1Display wins!" -ForegroundColor Green
                        } elseif ($matchResult.winner -eq "2") {
                            $result = @{ Result = "win"; WinnerSide = 2 }
                            Write-Host "    AUTO-DETECTED: $p2Display wins!" -ForegroundColor Green
                        } elseif ($matchResult.winner -eq "draw") {
                            $result = @{ Result = "draw"; WinnerSide = 0 }
                            Write-Host "    AUTO-DETECTED: Draw!" -ForegroundColor DarkYellow
                        }
                    } catch {}
                }
            }
            if (-not $result) {
                Write-Host "    IkemenGO exited with no result. Press 1/2/D:" -ForegroundColor DarkYellow
                $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                switch ($key.Character) {
                    '1' { $result = @{ Result = "win"; WinnerSide = 1 } }
                    '2' { $result = @{ Result = "win"; WinnerSide = 2 } }
                    default { $result = @{ Result = "draw"; WinnerSide = 0 } }
                }
            }
        }

        # Timeout safety
        if (-not $result) {
            Start-Sleep -Milliseconds 500
            $elapsed += 0.5
            if ($elapsed -ge $maxWaitSeconds) {
                Write-Host "    TIMEOUT: Fight exceeded $MaxFightMinutes minutes. Marking as draw." -ForegroundColor DarkYellow
                $result = @{ Result = "draw"; WinnerSide = 0 }
            }
        }
    }

    $duration = (Get-Date) - $fightStart

    # Kill IkemenGO
    if (-not $process.HasExited) {
        try { $process.Kill() } catch {}
        $process.WaitForExit(5000)
    }

    $result.Duration = $duration
    return $result
}

# ============================================================
# Console Bracket Display
# ============================================================
function Get-WinLabel([string]$charEntry) {
    $name = Get-CharDisplayName $charEntry
    $wins = if ($script:winCounts.ContainsKey($name)) { $script:winCounts[$name] } else { 0 }
    if ($wins -gt 0) { return "$name (W:$wins)" }
    return $name
}

function Show-ConsoleBracket($rounds) {
    Write-Host ""
    Write-Host "  ================ TOURNAMENT BRACKET ================" -ForegroundColor Cyan

    for ($r = 0; $r -lt $rounds.Count; $r++) {
        $roundName = Get-RoundName $r $rounds.Count
        Write-Host ""
        Write-Host "  --- $roundName ---" -ForegroundColor DarkCyan

        foreach ($match in $rounds[$r]) {
            $p1Name = Get-WinLabel $match.P1
            $p2Name = Get-WinLabel $match.P2

            $statusIcon = switch ($match.Status) {
                "completed" { "[OK]" }
                "active"    { "[>>]" }
                "pending"   { "[..]" }
            }

            $color = switch ($match.Status) {
                "completed" { "Green" }
                "active"    { "Yellow" }
                "pending"   { "DarkGray" }
            }

            if ($match.Winner) {
                $winName = Get-WinLabel $match.Winner
                Write-Host "    $statusIcon $p1Name vs $p2Name  ->  $winName" -ForegroundColor $color
            } else {
                Write-Host "    $statusIcon $p1Name vs $p2Name" -ForegroundColor $color
            }
        }
    }
    Write-Host ""
    Write-Host "  ====================================================" -ForegroundColor Cyan
    Write-Host ""
}

# ============================================================
# HTML Bracket Generation
# ============================================================
function Update-HtmlBracket($rounds, [int]$activeRound = -1, [int]$activeMatch = -1) {
    $numRounds = $rounds.Count

    $roundsHtml = ""
    for ($r = 0; $r -lt $numRounds; $r++) {
        $roundName = Get-RoundName $r $numRounds
        $roundsHtml += "      <div class='round'>`n"
        $roundsHtml += "        <div class='round-title'>$roundName</div>`n"

        foreach ($match in $rounds[$r]) {
            $p1Raw = Get-CharDisplayName $match.P1
            $p2Raw = Get-CharDisplayName $match.P2
            $p1Name = [System.Net.WebUtility]::HtmlEncode($p1Raw)
            $p2Name = [System.Net.WebUtility]::HtmlEncode($p2Raw)

            $p1Wins = if ($p1Raw -and $script:winCounts.ContainsKey($p1Raw)) { $script:winCounts[$p1Raw] } else { 0 }
            $p2Wins = if ($p2Raw -and $script:winCounts.ContainsKey($p2Raw)) { $script:winCounts[$p2Raw] } else { 0 }
            $p1Badge = if ($p1Wins -gt 0) { " <span class='win-badge'>$p1Wins W</span>" } else { "" }
            $p2Badge = if ($p2Wins -gt 0) { " <span class='win-badge'>$p2Wins W</span>" } else { "" }

            $matchClass = "match"
            $p1Class = "player"
            $p2Class = "player"

            switch ($match.Status) {
                "completed" {
                    $matchClass += " completed"
                    if ($match.P1 -and $match.Winner -eq $match.P1) { $p1Class += " winner" }
                    elseif ($match.P2 -and $match.Winner -eq $match.P2) { $p2Class += " winner" }
                }
                "active" { $matchClass += " active" }
                "pending" { $matchClass += " pending" }
            }

            $roundsHtml += @"
        <div class='$matchClass'>
          <div class='$p1Class'>$p1Name$p1Badge</div>
          <div class='vs'>VS</div>
          <div class='$p2Class'>$p2Name$p2Badge</div>
        </div>

"@
        }
        $roundsHtml += "      </div>`n"
    }

    # Champion victory screen
    $championHtml = ""
    $finalMatch = $rounds[-1][0]
    if ($finalMatch.Winner) {
        $champRaw = Get-CharDisplayName $finalMatch.Winner
        $champName = [System.Net.WebUtility]::HtmlEncode($champRaw)
        $champWins = if ($script:winCounts.ContainsKey($champRaw)) { $script:winCounts[$champRaw] } else { 0 }

        # Try to find a character portrait image
        $champEntry = $finalMatch.Winner
        $champFolder = if ($champEntry -match '[\\/]') { ($champEntry -split '[\\/]')[0] } else { $champEntry }
        $champDir = Join-Path $charsDir $champFolder
        $portraitSrc = ""
        if (Test-Path $champDir) {
            # Look for portrait.png, thumbnail.png, or any *portrait*.png
            $portraitCandidates = @(
                (Join-Path $champDir "portrait.png"),
                (Join-Path $champDir "thumbnail.png")
            )
            foreach ($candidate in $portraitCandidates) {
                if (Test-Path $candidate) {
                    $portraitSrc = $candidate
                    break
                }
            }
            if (-not $portraitSrc) {
                $found = Get-ChildItem -Path $champDir -Filter "*portrait*" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($found) { $portraitSrc = $found.FullName }
            }
            if (-not $portraitSrc) {
                $found = Get-ChildItem -Path $champDir -Filter "thumbnail*" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($found) { $portraitSrc = $found.FullName }
            }
        }

        $portraitImg = ""
        if ($portraitSrc) {
            # Convert image to base64 for embedding
            $imgBytes = [System.IO.File]::ReadAllBytes($portraitSrc)
            $imgBase64 = [Convert]::ToBase64String($imgBytes)
            $portraitImg = "<img class='champ-portrait' src='data:image/png;base64,$imgBase64' alt='$champName'>"
        }

        # Convert winner background to base64
        $bgPath = Join-Path $projectRoot "winner_bg1.png"
        $bgBase64 = ""
        if (Test-Path $bgPath) {
            $bgBytes = [System.IO.File]::ReadAllBytes($bgPath)
            $bgBase64 = [Convert]::ToBase64String($bgBytes)
        }

        $championHtml = @"
    <div class='victory-overlay' id='victoryScreen'>
      <div class='victory-bg' style='background-image: url(data:image/png;base64,$bgBase64);'></div>
      <div class='victory-content'>
        <div class='victory-crown'>&#128081;</div>
        <div class='victory-title'>TOURNAMENT CHAMPION</div>
        $portraitImg
        <div class='victory-name'>$champName</div>
        <div class='victory-record'>$champWins WINS - 0 LOSSES</div>
        <div class='victory-subtitle'>UNDEFEATED</div>
      </div>
      <div class='victory-scanlines'></div>
    </div>
"@
    }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta http-equiv="refresh" content="5">
<title>IkemenGO Tournament</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    background: #1a1a2e;
    color: #eee;
    font-family: 'Segoe UI', Tahoma, sans-serif;
    padding: 20px;
    min-height: 100vh;
  }
  h1 {
    text-align: center;
    color: #e94560;
    font-size: 2.2em;
    margin-bottom: 5px;
    text-shadow: 0 0 20px rgba(233,69,96,0.5);
    letter-spacing: 3px;
  }
  .subtitle {
    text-align: center;
    color: #888;
    margin-bottom: 30px;
    font-size: 1.1em;
  }
  .bracket {
    display: flex;
    justify-content: center;
    gap: 30px;
    overflow-x: auto;
    padding: 20px 10px;
    align-items: stretch;
  }
  .round {
    display: flex;
    flex-direction: column;
    justify-content: space-around;
    min-width: 190px;
    gap: 15px;
    flex-shrink: 0;
  }
  .round-title {
    text-align: center;
    color: #e94560;
    font-weight: bold;
    font-size: 0.85em;
    text-transform: uppercase;
    letter-spacing: 2px;
    padding-bottom: 8px;
    border-bottom: 2px solid #e94560;
    margin-bottom: 5px;
  }
  .match {
    background: #16213e;
    border: 2px solid #0f3460;
    border-radius: 8px;
    padding: 8px 12px;
    transition: all 0.3s;
  }
  .match.active {
    border-color: #f0c040;
    box-shadow: 0 0 15px rgba(240,192,64,0.4);
    animation: pulse 1.5s infinite;
  }
  .match.completed { border-color: #2ecc71; }
  .match.pending { border-color: #333; opacity: 0.5; }
  .player {
    padding: 4px 8px;
    font-size: 1.05em;
    color: #ffffff;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    max-width: 180px;
  }
  .player.winner {
    color: #2ecc71;
    font-weight: bold;
    text-shadow: 0 0 8px rgba(46,204,113,0.3);
  }
  .vs {
    text-align: center;
    color: #e94560;
    font-size: 0.65em;
    font-weight: bold;
    padding: 2px 0;
  }
  .win-badge {
    display: inline-block;
    background: #e94560;
    color: #fff;
    font-size: 0.7em;
    font-weight: bold;
    padding: 1px 5px;
    border-radius: 8px;
    margin-left: 4px;
    vertical-align: middle;
  }
  .champion {
    text-align: center;
    font-size: 1.8em;
    color: #f0c040;
    margin-top: 30px;
    padding: 20px;
    background: linear-gradient(135deg, #1a1a2e, #16213e);
    border: 3px solid #f0c040;
    border-radius: 12px;
    text-shadow: 0 0 20px rgba(240,192,64,0.5);
    animation: glow 2s ease-in-out infinite;
  }
  @keyframes pulse {
    0%, 100% { box-shadow: 0 0 15px rgba(240,192,64,0.4); }
    50% { box-shadow: 0 0 25px rgba(240,192,64,0.7); }
  }
  @keyframes glow {
    0%, 100% { box-shadow: 0 0 20px rgba(240,192,64,0.3); }
    50% { box-shadow: 0 0 40px rgba(240,192,64,0.6); }
  }
  .footer {
    text-align: center;
    color: #555;
    margin-top: 20px;
    font-size: 0.8em;
  }
  /* Victory screen */
  .victory-overlay {
    position: fixed;
    top: 0; left: 0; right: 0; bottom: 0;
    z-index: 9999;
    display: flex;
    align-items: center;
    justify-content: center;
    animation: victoryFadeIn 1.5s ease-out;
  }
  .victory-bg {
    position: absolute;
    top: 0; left: 0; right: 0; bottom: 0;
    background-size: cover;
    background-position: center;
    background-repeat: no-repeat;
    image-rendering: pixelated;
  }
  .victory-scanlines {
    position: absolute;
    top: 0; left: 0; right: 0; bottom: 0;
    background: repeating-linear-gradient(
      0deg,
      transparent,
      transparent 2px,
      rgba(0,0,0,0.15) 2px,
      rgba(0,0,0,0.15) 4px
    );
    pointer-events: none;
  }
  .victory-content {
    position: relative;
    z-index: 2;
    text-align: center;
    padding: 40px 60px;
    background: rgba(0, 0, 0, 0.65);
    border: 3px solid #f0c040;
    border-radius: 16px;
    box-shadow: 0 0 60px rgba(240, 192, 64, 0.4), inset 0 0 30px rgba(0,0,0,0.5);
    animation: victoryPulse 3s ease-in-out infinite;
  }
  .victory-crown {
    font-size: 4em;
    margin-bottom: 10px;
    animation: crownBounce 2s ease-in-out infinite;
  }
  .victory-title {
    font-size: 1.4em;
    color: #e94560;
    letter-spacing: 6px;
    text-transform: uppercase;
    font-weight: bold;
    margin-bottom: 20px;
    text-shadow: 0 0 15px rgba(233, 69, 96, 0.7);
  }
  .champ-portrait {
    max-width: 200px;
    max-height: 250px;
    margin: 15px auto;
    display: block;
    image-rendering: pixelated;
    filter: drop-shadow(0 0 20px rgba(240, 192, 64, 0.6));
    border: 2px solid #f0c040;
    border-radius: 8px;
  }
  .victory-name {
    font-size: 3.5em;
    color: #f0c040;
    font-weight: bold;
    text-shadow: 0 0 30px rgba(240, 192, 64, 0.8), 0 4px 8px rgba(0,0,0,0.8);
    letter-spacing: 4px;
    margin: 15px 0;
    animation: nameGlow 2s ease-in-out infinite alternate;
  }
  .victory-record {
    font-size: 1.6em;
    color: #2ecc71;
    font-weight: bold;
    letter-spacing: 3px;
    text-shadow: 0 0 10px rgba(46, 204, 113, 0.5);
    margin-bottom: 8px;
  }
  .victory-subtitle {
    font-size: 1.1em;
    color: #e94560;
    letter-spacing: 8px;
    text-transform: uppercase;
    opacity: 0.8;
  }
  @keyframes victoryFadeIn {
    from { opacity: 0; }
    to { opacity: 1; }
  }
  @keyframes victoryPulse {
    0%, 100% { box-shadow: 0 0 60px rgba(240, 192, 64, 0.4), inset 0 0 30px rgba(0,0,0,0.5); }
    50% { box-shadow: 0 0 80px rgba(240, 192, 64, 0.6), inset 0 0 30px rgba(0,0,0,0.5); }
  }
  @keyframes crownBounce {
    0%, 100% { transform: translateY(0); }
    50% { transform: translateY(-10px); }
  }
  @keyframes nameGlow {
    from { text-shadow: 0 0 30px rgba(240, 192, 64, 0.8), 0 4px 8px rgba(0,0,0,0.8); }
    to { text-shadow: 0 0 50px rgba(240, 192, 64, 1), 0 0 80px rgba(233, 69, 96, 0.4), 0 4px 8px rgba(0,0,0,0.8); }
  }
</style>
</head>
<body>
  <h1>JUS TOURNAMENT</h1>
  <div class="subtitle">$BracketSize-Fighter Single Elimination &bull; AI Difficulty $Difficulty/8</div>
  <div class="bracket">
$roundsHtml
  </div>
$championHtml
  <div class="footer">Auto-refreshes every 5s &bull; $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>
</body>
</html>
"@

    Set-Content -Path $htmlOutput -Value $html -Encoding UTF8

    if (-not $script:htmlOpened) {
        Start-Process $htmlOutput
        $script:htmlOpened = $true
    }
}

# ============================================================
# Main Tournament Logic
# ============================================================
Clear-Host
Write-Host "========================================================" -ForegroundColor Magenta
Write-Host "     JUS - TOURNAMENT MODE" -ForegroundColor Magenta
Write-Host "========================================================" -ForegroundColor Magenta
Write-Host ""

# Gather characters and stages
$script:allChars = Get-AllCharacters
$script:allStages = Get-AllStages

Write-Host "  Bracket Size : $BracketSize fighters" -ForegroundColor White
Write-Host "  Match Format : 1v1 AI vs AI" -ForegroundColor White
Write-Host "  AI Difficulty: $Difficulty / 8" -ForegroundColor White
Write-Host "  Fight Timeout: $MaxFightMinutes min" -ForegroundColor White
Write-Host "  Draw Retries : $MaxDrawRetries" -ForegroundColor White
Write-Host "  Characters   : $($script:allChars.Count) in roster" -ForegroundColor White
Write-Host "  Stages       : $($script:allStages.Count) available" -ForegroundColor White
Write-Host ""
Write-Host "  Flow: IkemenGO launches -> watch fight -> click terminal" -ForegroundColor DarkGray
Write-Host "        -> press 1 or 2 -> IkemenGO closes -> next fight" -ForegroundColor DarkGray
Write-Host ""

if ($script:allChars.Count -lt $BracketSize) {
    Write-Host "ERROR: Need at least $BracketSize characters (found $($script:allChars.Count))" -ForegroundColor Red
    exit 1
}

# Select tournament participants
Write-Host "Selecting $BracketSize random fighters..." -ForegroundColor Cyan
$participants = Select-TournamentParticipants $script:allChars $BracketSize

Write-Host ""
Write-Host "  TOURNAMENT ROSTER:" -ForegroundColor Yellow
for ($i = 0; $i -lt $participants.Count; $i++) {
    $seed = $i + 1
    $name = Get-CharDisplayName $participants[$i]
    $color = if ($i % 2 -eq 0) { "Cyan" } else { "White" }
    Write-Host "    #$seed  $name" -ForegroundColor $color
}
Write-Host ""

# Create bracket
$rounds = New-Bracket $participants

# Generate initial HTML bracket
Update-HtmlBracket $rounds

# Show initial console bracket
Show-ConsoleBracket $rounds

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "  Bracket generated! Review the bracket above." -ForegroundColor Cyan
Write-Host "  Press Enter to start the tournament..." -ForegroundColor Yellow
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""

Read-Host "  Press Enter to begin"

Write-Host ""
Write-Host "  Tournament starting!" -ForegroundColor Green
Write-Host "  Press Ctrl+C at any time to stop the tournament." -ForegroundColor DarkGray
Write-Host ""

# Count total matches
$totalMatches = 0
foreach ($round in $rounds) { $totalMatches += $round.Count }
$matchNumber = 0
$sessionStart = Get-Date

try {
    for ($roundIdx = 0; $roundIdx -lt $rounds.Count; $roundIdx++) {
        $roundName = Get-RoundName $roundIdx $rounds.Count

        Write-Host ""
        Write-Host "============================================" -ForegroundColor Magenta
        Write-Host "  $roundName" -ForegroundColor Magenta
        Write-Host "============================================" -ForegroundColor Magenta

        for ($matchIdx = 0; $matchIdx -lt $rounds[$roundIdx].Count; $matchIdx++) {
            $match = $rounds[$roundIdx][$matchIdx]
            $matchNumber++
            $match.Status = "active"

            $p1 = $match.P1
            $p2 = $match.P2
            $p1Display = Get-CharDisplayName $p1
            $p2Display = Get-CharDisplayName $p2
            $stage = Get-RandomStage

            Write-Host ""
            Write-Host "  Match $matchNumber/$totalMatches  |  $roundName" -ForegroundColor Yellow
            Write-Host "  $p1Display  vs  $p2Display" -ForegroundColor White
            if ($stage) {
                $stageDisplay = [System.IO.Path]::GetFileNameWithoutExtension(($stage -replace '^stages[\\/]', ''))
                Write-Host "  Stage: $stageDisplay" -ForegroundColor DarkGray
            }

            # Update HTML
            Update-HtmlBracket $rounds $roundIdx $matchIdx

            # Run match with draw retry logic
            $drawRetries = 0
            $resolved = $false

            while (-not $resolved -and $drawRetries -le $MaxDrawRetries) {
                $stageForFight = if ($drawRetries -eq 0) { $stage } else { Get-RandomStage }
                $fightResult = Run-Match $p1 $p2 $stageForFight
                $durationStr = Format-Duration $fightResult.Duration

                switch ($fightResult.Result) {
                    "win" {
                        if ($fightResult.WinnerSide -eq 1) {
                            $match.Winner = $p1
                            $match.Loser = $p2
                        } else {
                            $match.Winner = $p2
                            $match.Loser = $p1
                        }
                        $resolved = $true
                        $winDisplay = Get-CharDisplayName $match.Winner
                        $loseDisplay = Get-CharDisplayName $match.Loser

                        if (-not $script:winCounts.ContainsKey($winDisplay)) { $script:winCounts[$winDisplay] = 0 }
                        $script:winCounts[$winDisplay]++
                        $totalWins = $script:winCounts[$winDisplay]

                        Write-Host ""
                        Write-Host "    ================================================" -ForegroundColor Green
                        Write-Host "    WINNER: $winDisplay" -ForegroundColor Green
                        Write-Host "    defeated $loseDisplay ($durationStr)" -ForegroundColor DarkGreen
                        Write-Host "    Tournament wins: $totalWins" -ForegroundColor DarkGreen
                        Write-Host "    ================================================" -ForegroundColor Green
                    }
                    "draw" {
                        $drawRetries++
                        if ($drawRetries -gt $MaxDrawRetries) {
                            $coinFlip = Get-Random -Maximum 2
                            $match.Winner = if ($coinFlip -eq 0) { $p1 } else { $p2 }
                            $match.Loser = if ($coinFlip -eq 0) { $p2 } else { $p1 }
                            $resolved = $true
                            $winDisplay = Get-CharDisplayName $match.Winner
                            if (-not $script:winCounts.ContainsKey($winDisplay)) { $script:winCounts[$winDisplay] = 0 }
                            $script:winCounts[$winDisplay]++
                            Write-Host "  DRAW x$MaxDrawRetries - Coin flip: $winDisplay advances" -ForegroundColor DarkYellow
                        } else {
                            Write-Host "  DRAW - Replaying ($drawRetries/$MaxDrawRetries)..." -ForegroundColor DarkYellow
                        }
                    }
                }
            }

            $match.Status = "completed"
            Advance-Winner $rounds $roundIdx $matchIdx

            # Update displays after result
            Update-HtmlBracket $rounds
            Show-ConsoleBracket $rounds

            # Brief pause between matches
            Start-Sleep -Seconds 3
        }
    }

    # ============================================================
    # Tournament Complete!
    # ============================================================
    $champion = $rounds[-1][0].Winner
    $champDisplay = Get-CharDisplayName $champion
    $champWins = if ($script:winCounts.ContainsKey($champDisplay)) { $script:winCounts[$champDisplay] } else { 0 }
    $totalDuration = Format-Duration ((Get-Date) - $sessionStart)

    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "              TOURNAMENT CHAMPION" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "                $champDisplay" -ForegroundColor Green
    Write-Host "                $champWins wins / 0 losses" -ForegroundColor DarkGreen
    Write-Host ""
    Write-Host "  Matches played : $totalMatches" -ForegroundColor White
    Write-Host "  Total time     : $totalDuration" -ForegroundColor White
    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Yellow
    Write-Host ""

    # Final HTML update
    Update-HtmlBracket $rounds

}
finally {
    # Kill any remaining IkemenGO processes from the tournament
    Get-Process -Name "MGRev2.5" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Host "Tournament ended." -ForegroundColor DarkGray
}
