# Backs up the career saves (settings/street_legal: every slot, .bak, slots.json, hud.json, options.json) and
# Wrench Works' save.json before a QA round, with their hashes, into settings/street_legal/backups/<stamp>/.
# Prints the stamp; save_restore.ps1 <stamp> puts them back and checks the hashes.
param([string]$BeamUserPath = "$env:LOCALAPPDATA\BeamNG\BeamNG.drive\current")
$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
$dst = Join-Path $BeamUserPath "settings\street_legal\backups\$stamp"
New-Item -ItemType Directory -Force $dst | Out-Null
$files = @(Get-ChildItem (Join-Path $BeamUserPath 'settings\street_legal') -File) + @(Get-ChildItem (Join-Path $BeamUserPath 'settings\slrr_garage') -File -Filter save.json -ErrorAction SilentlyContinue)
$lines = foreach ($f in $files) {
  $rel = $f.FullName.Substring($BeamUserPath.Length + 1)
  $to = Join-Path $dst $rel
  New-Item -ItemType Directory -Force (Split-Path $to) | Out-Null
  Copy-Item $f.FullName $to
  "$((Get-FileHash $f.FullName -Algorithm SHA256).Hash) $rel"
}
$lines | Set-Content (Join-Path $dst 'hashes.txt') -Encoding utf8
"backed up $($files.Count) files to $dst"
$stamp
