# embed-images.ps1
# Re-embeds all journal/button images as base64 data URIs inside donate-animation.html.
# Run this once after cloning, or whenever you update any of the source PNGs.
#
# Usage (from the docs/ folder):
#   powershell -ExecutionPolicy Bypass -File embed-images.ps1

$htmlPath  = Join-Path $PSScriptRoot "donate-animation.html"
$assetsDir = Join-Path $PSScriptRoot "assets"

if (-not (Test-Path $htmlPath))  { Write-Error "donate-animation.html not found"; exit 1 }
if (-not (Test-Path $assetsDir)) { Write-Error "assets/ folder not found";        exit 1 }

function ToDataUri($filename) {
  $path = Join-Path $assetsDir $filename
  if (-not (Test-Path $path)) { Write-Warning "Missing: $filename"; return "assets/$filename" }
  $bytes = [IO.File]::ReadAllBytes($path)
  return "data:image/png;base64," + [Convert]::ToBase64String($bytes)
}

$html = [IO.File]::ReadAllText($htmlPath, [Text.Encoding]::UTF8)
$sizeBefore = [math]::Round($html.Length / 1024, 1)

$images = [ordered]@{
  "assets/BSJ-DonationButton-Image.png"                  = "BSJ-DonationButton-Image.png"
  "assets/BurdJournal-FilledClean-Icon-Med.png"          = "BurdJournal-FilledClean-Icon-Med.png"
  "assets/BurdJournal-FilledWorn-Icon-Med.png"           = "BurdJournal-FilledWorn-Icon-Med.png"
  "assets/BurdJournal-FilledBloody-Icon-Med.png"         = "BurdJournal-FilledBloody-Icon-Med.png"
  "assets/BurdJournal-CursedBloody-Icon-IndexBig.png"    = "BurdJournal-CursedBloody-Icon-IndexBig.png"
  "assets/BurdJournal-YuletideFilled-Icon-Index-Big.png" = "BurdJournal-YuletideFilled-Icon-Index-Big.png"
}

foreach ($assetPath in $images.Keys) {
  $dataUri = ToDataUri $images[$assetPath]
  $html = $html.Replace($assetPath, $dataUri)
  Write-Host "  Embedded: $($images[$assetPath])"
}

[IO.File]::WriteAllText($htmlPath, $html, [Text.Encoding]::UTF8)
$sizeAfter = [math]::Round((Get-Item $htmlPath).Length / 1024, 1)
Write-Host "`nDone. donate-animation.html: ${sizeAfter} KB (was ${sizeBefore} KB)"
Write-Host "GIF export will now work from file:// without a web server."
