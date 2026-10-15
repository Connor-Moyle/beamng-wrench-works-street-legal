# Puts back the saves a save_backup.ps1 run made (settings/street_legal/backups/<stamp>/) and checks every
# file's hash against hashes.txt. Run with the game at the main menu or closed. Deletes slot saves the round
# added (careerN.json not in the backup), so the chooser is as it was.
param([Parameter(Mandatory = $true)][string]$Stamp, [string]$BeamUserPath = "$env:LOCALAPPDATA\BeamNG\BeamNG.drive\current")
$ErrorActionPreference = 'Stop'
$src = Join-Path $BeamUserPath "settings\street_legal\backups\$Stamp"
if (-not (Test-Path (Join-Path $src 'hashes.txt'))) { throw "no backup $src" }
$kept = @{}
foreach ($line in Get-Content (Join-Path $src 'hashes.txt')) {
  $hash, $rel = $line -split ' ', 2
  Copy-Item (Join-Path $src $rel) (Join-Path $BeamUserPath $rel) -Force
  $kept[$rel] = $true
  $now = (Get-FileHash (Join-Path $BeamUserPath $rel) -Algorithm SHA256).Hash
  if ($now -ne $hash) { throw "hash mismatch after restore: $rel" }
  "ok $rel"
}
foreach ($f in Get-ChildItem (Join-Path $BeamUserPath 'settings\street_legal') -File) {
  $rel = $f.FullName.Substring($BeamUserPath.Length + 1)
  if (-not $kept[$rel]) { Remove-Item $f.FullName; "removed $rel (added during the round)" }
}
"restored $($kept.Count) files from $src, hashes match"
