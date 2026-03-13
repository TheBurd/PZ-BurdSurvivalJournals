# Translation HTML Sync Checker for BurdSurvivalJournals
# Compares the mod's EN translation files with the HTML localization tool.

param(
    [string]$ModPath = "..\Contents\mods\BurdSurvivalJournals",
    [string]$HtmlPath = "..\docs\index.html",
    [switch]$Verbose
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$modRoot = Join-Path $scriptDir $ModPath
$htmlFile = Join-Path $scriptDir $HtmlPath
$helperPath = Join-Path $scriptDir "translation_helpers.ps1"
. $helperPath
$primaryVersionDir = Get-BSJPrimaryVersionDir -BasePath $modRoot

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  TRANSLATION HTML SYNC CHECKER v2.0" -ForegroundColor Cyan
Write-Host "  BurdSurvivalJournals QA Tool" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan

Write-Host "Extracting keys from mod translation files..." -ForegroundColor Yellow
$modKeys = @{}
$translationFiles = @(
    @{ File = "Sandbox"; Prefix = "Sandbox_" },
    @{ File = "UI"; Prefix = "UI_" },
    @{ File = "IG_UI"; Prefix = "IG_UI_" },
    @{ File = "ContextMenu"; Prefix = "ContextMenu_" },
    @{ File = "Tooltip"; Prefix = "Tooltip_" },
    @{ File = "ItemName"; Prefix = "ItemName_" },
    @{ File = "Recipes"; Prefix = "" }
)

if (-not $primaryVersionDir) {
    Write-Host "  ERROR: No versioned mod directory found under: $modRoot" -ForegroundColor Red
    exit 1
}

$translateDir = Join-Path $primaryVersionDir.FullName "media\lua\shared\Translate\EN"

foreach ($fileInfo in $translationFiles) {
    $filePath = Resolve-BSJTranslationPath -BasePath $modRoot -TranslationDir (Join-Path $primaryVersionDir.Name "media\lua\shared\Translate") -Language "EN" -FileType $fileInfo.File
    if (-not (Test-Path $filePath)) {
        Write-Host "  Warning: File not found: $($fileInfo.File)" -ForegroundColor Yellow
        continue
    }

    $map = Get-BSJTranslationMap -Path $filePath
    foreach ($key in $map.Keys) {
        $modKeys[$key] = @{
            Value = [string]$map[$key]
            File = Split-Path -Leaf $filePath
        }
    }
}

Write-Host "  Found $($modKeys.Count) keys in mod files`n" -ForegroundColor Green

Write-Host "Extracting keys from HTML localization tool..." -ForegroundColor Yellow
$htmlKeys = @{}

if (Test-Path $htmlFile) {
    $htmlContent = Get-Content $htmlFile -Raw
    $matches = [regex]::Matches($htmlContent, '"([\w\.\-_]+)":\s*"([^"]*)"')
    foreach ($match in $matches) {
        $key = $match.Groups[1].Value
        $value = $match.Groups[2].Value
        if ($key -match '^(Sandbox_|UI_|IG_UI_|ContextMenu_|Tooltip_|ItemName_|Recipe_|Bind_|Restore|Erase)') {
            $htmlKeys[$key] = $value
        }
    }

    Write-Host "  Found $($htmlKeys.Count) keys in HTML file`n" -ForegroundColor Green
}
else {
    Write-Host "  ERROR: HTML file not found at: $htmlFile" -ForegroundColor Red
    exit 1
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  COMPARISON RESULTS" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan

$missingInHtml = @()
foreach ($key in $modKeys.Keys) {
    if (-not $htmlKeys.ContainsKey($key)) {
        $missingInHtml += @{
            Key = $key
            Value = $modKeys[$key].Value
            File = $modKeys[$key].File
        }
    }
}

$missingInMod = @()
foreach ($key in $htmlKeys.Keys) {
    if (-not $modKeys.ContainsKey($key)) {
        $missingInMod += @{
            Key = $key
            Value = $htmlKeys[$key]
        }
    }
}

$valuesDiffer = @()
foreach ($key in $modKeys.Keys) {
    if ($htmlKeys.ContainsKey($key)) {
        $modValue = $modKeys[$key].Value
        $htmlValue = $htmlKeys[$key]
        if ($modValue -ne $htmlValue) {
            $valuesDiffer += @{
                Key = $key
                ModValue = $modValue
                HtmlValue = $htmlValue
                File = $modKeys[$key].File
            }
        }
    }
}

if ($missingInHtml.Count -gt 0) {
    Write-Host "MISSING IN HTML TOOL ($($missingInHtml.Count)):" -ForegroundColor Red
    Write-Host "These keys exist in the mod but are NOT in the HTML localization tool:`n" -ForegroundColor Red
    $byFile = $missingInHtml | Group-Object { $_.File }
    foreach ($group in $byFile) {
        Write-Host "  [$($group.Name)]" -ForegroundColor Cyan
        foreach ($item in $group.Group) {
            Write-Host "    $($item.Key)" -ForegroundColor White
            if ($Verbose) {
                Write-Host "      = `"$($item.Value)`"" -ForegroundColor Gray
            }
        }
        Write-Host ""
    }
}
else {
    Write-Host "MISSING IN HTML TOOL: None" -ForegroundColor Green
    Write-Host "  All mod keys are present in the HTML tool`n" -ForegroundColor Green
}

if ($missingInMod.Count -gt 0) {
    Write-Host "OBSOLETE IN HTML TOOL ($($missingInMod.Count)):" -ForegroundColor Yellow
    Write-Host "These keys exist in the HTML tool but NOT in the mod (may be obsolete):`n" -ForegroundColor Yellow
    foreach ($item in $missingInMod) {
        Write-Host "  $($item.Key)" -ForegroundColor White
        if ($Verbose) {
            Write-Host "    = `"$($item.Value)`"" -ForegroundColor Gray
        }
    }
    Write-Host ""
}
else {
    Write-Host "OBSOLETE IN HTML TOOL: None" -ForegroundColor Green
    Write-Host "  No extra keys in HTML tool`n" -ForegroundColor Green
}

if ($valuesDiffer.Count -gt 0) {
    Write-Host "VALUE DIFFERENCES ($($valuesDiffer.Count)):" -ForegroundColor Magenta
    Write-Host "These keys have different values between mod and HTML:`n" -ForegroundColor Magenta
    foreach ($item in $valuesDiffer) {
        Write-Host "  Key: $($item.Key)" -ForegroundColor White
        Write-Host "    Mod:  `"$($item.ModValue)`"" -ForegroundColor Cyan
        Write-Host "    HTML: `"$($item.HtmlValue)`"" -ForegroundColor Yellow
        Write-Host ""
    }
}
else {
    Write-Host "VALUE DIFFERENCES: None" -ForegroundColor Green
    Write-Host "  All shared keys have matching values`n" -ForegroundColor Green
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SUMMARY" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Mod translation keys:     $($modKeys.Count)" -ForegroundColor White
Write-Host "HTML tool keys:           $($htmlKeys.Count)" -ForegroundColor White
Write-Host "Missing in HTML tool:     $($missingInHtml.Count)" -ForegroundColor $(if ($missingInHtml.Count -gt 0) { "Red" } else { "Green" })
Write-Host "Obsolete in HTML tool:    $($missingInMod.Count)" -ForegroundColor $(if ($missingInMod.Count -gt 0) { "Yellow" } else { "Green" })
Write-Host "Value differences:        $($valuesDiffer.Count)" -ForegroundColor $(if ($valuesDiffer.Count -gt 0) { "Magenta" } else { "Green" })
Write-Host ""

if ($missingInHtml.Count -gt 0 -or $missingInMod.Count -gt 0 -or $valuesDiffer.Count -gt 0) {
    Write-Host "ACTION REQUIRED:" -ForegroundColor Red
    if ($missingInHtml.Count -gt 0) {
        Write-Host "  1. Add missing keys to docs/index.html englishData object" -ForegroundColor Yellow
    }
    if ($missingInMod.Count -gt 0) {
        Write-Host "  2. Review obsolete keys in HTML tool - remove if no longer needed" -ForegroundColor Yellow
    }
    if ($valuesDiffer.Count -gt 0) {
        Write-Host "  3. Update HTML tool with correct values from mod files" -ForegroundColor Yellow
    }
}
else {
    Write-Host "All translation keys are in sync!" -ForegroundColor Green
}

Write-Host ""
