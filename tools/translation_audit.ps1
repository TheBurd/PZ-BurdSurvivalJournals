<#
.SYNOPSIS
    Translation Audit Utility for BurdSurvivalJournals.

.DESCRIPTION
    Compares translation files against English (EN) as the reference and
    reports missing/extra keys for each language. Supports the Build 42.15+
    JSON translation format and the legacy Lua-table format during migration.
#>

param(
    [string]$BasePath = "c:\Users\Pepsi\Zomboid\Workshop\BurdSurvivalJournals\mods\BurdSurvivalJournals"
)

$helperPath = Join-Path $PSScriptRoot "translation_helpers.ps1"
. $helperPath

$TranslationDirs = Get-BSJTranslationDirs -BasePath $BasePath
$Languages = Get-BSJTranslationLanguages -BasePath $BasePath -TranslationDirs $TranslationDirs
$FileTypes = Get-BSJTranslationFileTypes -BasePath $BasePath -TranslationDirs $TranslationDirs

function Get-MissingKeys {
    param(
        [System.Collections.IDictionary]$Reference,
        [System.Collections.IDictionary]$Target
    )

    $missing = @()
    foreach ($key in $Reference.Keys) {
        if (-not $Target.Contains($key)) {
            $missing += $key
        }
    }
    return $missing | Sort-Object
}

function Get-ExtraKeys {
    param(
        [System.Collections.IDictionary]$Reference,
        [System.Collections.IDictionary]$Target
    )

    $extra = @()
    foreach ($key in $Target.Keys) {
        if (-not $Reference.Contains($key)) {
            $extra += $key
        }
    }
    return $extra | Sort-Object
}

Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "TRANSLATION AUDIT REPORT - BurdSurvivalJournals" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""
Write-Host "Base Path: $BasePath"
Write-Host "Reference Language: EN (English)"
Write-Host "File Format: JSON (legacy .txt supported for migration)"
Write-Host ""

$totalMissing = 0
$totalExtra = 0
$languageStats = @{}
foreach ($lang in $Languages) {
    $languageStats[$lang] = @{ Missing = 0; Extra = 0 }
}

$detailedResults = @()

foreach ($transDir in $TranslationDirs) {
    $dirLabel = $transDir.Split('\')[0]
    Write-Host ("-" * 80) -ForegroundColor Yellow
    Write-Host "Directory: $dirLabel/" -ForegroundColor Yellow
    Write-Host ("-" * 80) -ForegroundColor Yellow

    foreach ($fileType in $FileTypes) {
        $enPath = Resolve-BSJTranslationPath -BasePath $BasePath -TranslationDir $transDir -Language "EN" -FileType $fileType
        $enMap = Get-BSJTranslationMap -Path $enPath
        if ($enMap.Count -eq 0) {
            Write-Host "  [$fileType] EN reference not found: $enPath" -ForegroundColor Red
            continue
        }

        Write-Host ""
        Write-Host "  [$fileType] EN has $($enMap.Count) keys" -ForegroundColor White

        foreach ($lang in $Languages) {
            if ($lang -eq "EN") { continue }

            $langPath = Resolve-BSJTranslationPath -BasePath $BasePath -TranslationDir $transDir -Language $lang -FileType $fileType
            if (-not (Test-Path $langPath)) {
                Write-Host "    [$lang] File not found" -ForegroundColor DarkGray
                continue
            }

            $langMap = Get-BSJTranslationMap -Path $langPath
            $missing = Get-MissingKeys -Reference $enMap -Target $langMap
            $extra = Get-ExtraKeys -Reference $enMap -Target $langMap

            if ($missing.Count -gt 0 -or $extra.Count -gt 0) {
                $color = if ($missing.Count -gt 0) { "Red" } else { "Yellow" }
                Write-Host "    [$lang] $($langMap.Count) keys (missing: $($missing.Count), extra: $($extra.Count))" -ForegroundColor $color

                if ($missing.Count -gt 0) {
                    Write-Host "      MISSING:" -ForegroundColor Red
                    foreach ($key in $missing) {
                        Write-Host "        - $key" -ForegroundColor Red
                        $detailedResults += [PSCustomObject]@{
                            Directory = $dirLabel
                            File      = $fileType
                            Language  = $lang
                            Type      = "MISSING"
                            Key       = $key
                            ENValue   = [string]$enMap[$key]
                        }
                    }
                    $languageStats[$lang].Missing += $missing.Count
                    $totalMissing += $missing.Count
                }

                if ($extra.Count -gt 0) {
                    Write-Host "      EXTRA (not in EN):" -ForegroundColor DarkYellow
                    foreach ($key in $extra) {
                        Write-Host "        + $key" -ForegroundColor DarkYellow
                    }
                    $languageStats[$lang].Extra += $extra.Count
                    $totalExtra += $extra.Count
                }
            }
            else {
                Write-Host "    [$lang] $($langMap.Count) keys - OK" -ForegroundColor Green
            }
        }
    }

    Write-Host ""
}

Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""
Write-Host ("{0,-8} {1,10} {2,10}" -f "Language", "Missing", "Extra")
Write-Host ("-" * 30)

foreach ($lang in $Languages) {
    if ($lang -eq "EN") { continue }
    $stats = $languageStats[$lang]
    $status = if ($stats.Missing -eq 0 -and $stats.Extra -eq 0) { " [COMPLETE]" } else { "" }
    $color = if ($stats.Missing -gt 0) { "Red" } elseif ($stats.Extra -gt 0) { "Yellow" } else { "Green" }
    Write-Host ("{0,-8} {1,10} {2,10}{3}" -f $lang, $stats.Missing, $stats.Extra, $status) -ForegroundColor $color
}

Write-Host ("-" * 30)
Write-Host ("{0,-8} {1,10} {2,10}" -f "TOTAL", $totalMissing, $totalExtra) -ForegroundColor White
Write-Host ""

if ($detailedResults.Count -gt 0) {
    Write-Host ("=" * 80) -ForegroundColor Magenta
    Write-Host "DETAILED MISSING KEYS (with English values for translation)" -ForegroundColor Magenta
    Write-Host ("=" * 80) -ForegroundColor Magenta
    Write-Host ""

    $grouped = $detailedResults | Group-Object -Property Language, Directory, File
    foreach ($group in $grouped) {
        Write-Host "--- $($group.Name) ---" -ForegroundColor Cyan
        foreach ($item in $group.Group) {
            Write-Host "    $($item.Key) = `"$($item.ENValue)`"," -ForegroundColor White
        }
        Write-Host ""
    }
}

if ($totalMissing -gt 0) {
    Write-Host "ACTION REQUIRED: $totalMissing missing translation(s) need to be added." -ForegroundColor Red
}
else {
    Write-Host "All translations are complete!" -ForegroundColor Green
}

