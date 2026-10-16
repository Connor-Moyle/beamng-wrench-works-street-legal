# Copies your Windows desktop wallpaper into BeamNG's user folder, where Wrench Works: Street Legal's laptop picks it up
# (the game's interface can only read the game's own files, not the registry or your Pictures folder).
#   powershell -ExecutionPolicy Bypass -File tools\wallpaper.ps1 [-UserFolder "<BeamNG user folder>"]
# The default user folder is %LOCALAPPDATA%\BeamNG\BeamNG.drive\current. Choose "Built-in" under Settings > Street Legal > Laptop wallpaper
# to go back to the laptop's own wallpaper.
param([string]$UserFolder = '')
$ErrorActionPreference = 'Stop'
$wall = (Get-ItemProperty 'HKCU:\Control Panel\Desktop').WallPaper
if (-not $wall -or -not (Test-Path $wall)) { $wall = Join-Path $env:APPDATA 'Microsoft\Windows\Themes\TranscodedWallpaper' }
if (-not (Test-Path $wall)) { Write-Host 'No wallpaper file found (a slideshow or solid colour?).'; exit 1 }
if (-not $UserFolder) {
  $base = Join-Path $env:LOCALAPPDATA 'BeamNG\BeamNG.drive'
  $UserFolder = Join-Path $base 'current'
  if (-not (Test-Path $UserFolder)) {
    $newest = Get-ChildItem $base -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $newest) { Write-Host "No BeamNG user folder under $base."; exit 1 }
    $UserFolder = $newest.FullName
  }
}
$dest = Join-Path $UserFolder 'settings\street_legal'
New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item $wall (Join-Path $dest 'wallpaper.jpg') -Force
Write-Host "Copied $wall to $dest\wallpaper.jpg"
