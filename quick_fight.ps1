# Quick random AI vs AI fight
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$charsDir = Join-Path $projectRoot "chars"
$stagesDir = Join-Path $projectRoot "stages"

# Get all valid characters
$chars = @()
foreach ($dir in (Get-ChildItem -Path $charsDir -Directory)) {
    if ($dir.Name -eq "ALL JUS") { continue }
    $def = Join-Path $charsDir "$($dir.Name)\$($dir.Name).def"
    if (Test-Path $def) {
        $chars += $dir.Name
        continue
    }
    $anyDef = Get-ChildItem -Path $dir.FullName -Filter "*.def" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($anyDef) {
        $chars += "$($dir.Name)/$($anyDef.Name)"
    }
}

# Get all valid stages
$BLACKLIST = @("Lightning Desert.def", "The_Hopes_Gone_Super.def", "WastelandVP1.1.def")
$stages = @()
foreach ($f in (Get-ChildItem -Path $stagesDir -Filter "*.def" -ErrorAction SilentlyContinue)) {
    if ($f.Name -in $BLACKLIST) { continue }
    $sff = [System.IO.Path]::ChangeExtension($f.FullName, ".sff")
    if (Test-Path $sff) { $stages += "stages/$($f.Name)" }
}

# Pick two random characters and a stage
$p1 = $chars[(Get-Random -Maximum $chars.Count)]
$p2 = $p1
while ($p2 -eq $p1) { $p2 = $chars[(Get-Random -Maximum $chars.Count)] }
$stage = $stages[(Get-Random -Maximum $stages.Count)]

$p1Display = if ($p1 -match '/') { ($p1 -split '/')[0] } else { $p1 }
$p2Display = if ($p2 -match '/') { ($p2 -split '/')[0] } else { $p2 }
$stageDisplay = [System.IO.Path]::GetFileNameWithoutExtension(($stage -replace '^stages/', ''))

Write-Host ""
Write-Host "  QUICK FIGHT" -ForegroundColor Yellow
Write-Host "  $p1Display  vs  $p2Display" -ForegroundColor Cyan
Write-Host "  Stage: $stageDisplay" -ForegroundColor DarkGray
Write-Host ""

$aiLevel = 8
$exe = Join-Path $projectRoot "MGRev2.5.exe"
$argString = "-loadmotif -p1 `"$p1`" -p1.ai $aiLevel -p2 `"$p2`" -p2.ai $aiLevel -rounds 2 -s `"$stage`""
Start-Process -FilePath $exe -ArgumentList $argString -WorkingDirectory $projectRoot -Wait
