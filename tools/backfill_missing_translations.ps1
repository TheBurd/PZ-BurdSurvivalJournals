<#
.SYNOPSIS
    Backfills missing translation keys using EN as the source of truth.

.DESCRIPTION
    Supports the JSON translation format used by Build 42.15+ and legacy Lua
    translation files during migration. Missing keys are written back as JSON.
#>

[CmdletBinding()]
param(
    [string]$BasePath = "c:\Users\Pepsi\Zomboid\Workshop\BurdSurvivalJournals\mods\BurdSurvivalJournals",
    [string]$TodoReportPath = ""
)

$ErrorActionPreference = "Stop"

$helperPath = Join-Path $PSScriptRoot "translation_helpers.ps1"
. $helperPath

$TranslationDirs = Get-BSJTranslationDirs -BasePath $BasePath
$Languages = @(Get-BSJTranslationLanguages -BasePath $BasePath -TranslationDirs $TranslationDirs | Where-Object { $_ -ne "EN" })
$FileTypes = Get-BSJTranslationFileTypes -BasePath $BasePath -TranslationDirs $TranslationDirs

if (-not $TodoReportPath) {
    $TodoReportPath = Join-Path $PSScriptRoot "translation_todo_report.md"
}

$totalAdded = 0
$todoItems = New-Object System.Collections.Generic.List[object]
$todoByLanguage = @{}
foreach ($lang in $Languages) {
    $todoByLanguage[$lang] = 0
}

foreach ($dir in $TranslationDirs) {
    $otherDir = @($TranslationDirs | Where-Object { $_ -ne $dir } | Select-Object -First 1)
    $otherDir = if ($otherDir.Count -gt 0) { $otherDir[0] } else { $null }

    foreach ($fileType in $FileTypes) {
        $enPath = Resolve-BSJTranslationPath -BasePath $BasePath -TranslationDir $dir -Language "EN" -FileType $fileType
        $otherEnPath = if ($otherDir) { Resolve-BSJTranslationPath -BasePath $BasePath -TranslationDir $otherDir -Language "EN" -FileType $fileType } else { $null }
        $enMap = Get-BSJTranslationMap -Path $enPath
        $otherEnMap = Get-BSJTranslationMap -Path $otherEnPath

        if ($enMap.Count -eq 0) {
            Write-Warning "Missing EN reference: $enPath"
            continue
        }

        $referenceKeyOrder = @($enMap.Keys)

        foreach ($lang in $Languages) {
            $targetPath = Resolve-BSJTranslationPath -BasePath $BasePath -TranslationDir $dir -Language $lang -FileType $fileType
            $otherLangPath = if ($otherDir) { Resolve-BSJTranslationPath -BasePath $BasePath -TranslationDir $otherDir -Language $lang -FileType $fileType } else { $null }

            if (-not (Test-Path $targetPath) -and -not (Test-Path $otherLangPath)) {
                continue
            }

            $targetMap = Get-BSJTranslationMap -Path $targetPath
            $otherLangMap = Get-BSJTranslationMap -Path $otherLangPath
            $updatedMap = [ordered]@{}
            foreach ($key in $targetMap.Keys) {
                $updatedMap[$key] = $targetMap[$key]
            }

            $missing = @()
            foreach ($key in $enMap.Keys) {
                if (-not $updatedMap.Contains($key)) {
                    $missing += $key
                }
            }

            if ($missing.Count -eq 0) {
                continue
            }

            foreach ($key in ($missing | Sort-Object)) {
                $value = $null
                $source = $null
                $needsTranslation = $false

                if ($otherLangMap.Contains($key)) {
                    $value = [string]$otherLangMap[$key]
                    $source = "same_language_other_dir"
                }
                elseif ($enMap.Contains($key)) {
                    $value = [string]$enMap[$key]
                    $source = "english_current_dir"
                    $needsTranslation = $true
                }
                elseif ($otherEnMap.Contains($key)) {
                    $value = [string]$otherEnMap[$key]
                    $source = "english_other_dir"
                    $needsTranslation = $true
                }
                else {
                    $value = "TODO"
                    $source = "missing_all_sources"
                    $needsTranslation = $true
                }

                $updatedMap[$key] = $value

                if ($needsTranslation) {
                    $todoItems.Add([PSCustomObject]@{
                        Language = $lang
                        Directory = $dir.Split('\')[0]
                        FileType = $fileType
                        Key = $key
                        Value = $value
                        Source = $source
                    })
                    $todoByLanguage[$lang] = $todoByLanguage[$lang] + 1
                }
            }

            Write-BSJTranslationFile -Path $targetPath -Map $updatedMap -FileType $fileType -Language $lang -ReferenceKeyOrder $referenceKeyOrder
            $totalAdded += $missing.Count
            Write-Host ("Added {0,3} keys -> {1}" -f $missing.Count, $targetPath)
        }
    }
}

if ($todoItems.Count -gt 0) {
    $reportDir = Split-Path -Parent $TodoReportPath
    if ($reportDir -and -not (Test-Path $reportDir)) {
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Translation TODO Report")
    $lines.Add("")
    $lines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $lines.Add("BasePath: $BasePath")
    $lines.Add("Total keys needing translation: $($todoItems.Count)")
    $lines.Add("")
    $lines.Add("## Summary By Language")
    foreach ($lang in $Languages) {
        $lines.Add("- ${lang}: $($todoByLanguage[$lang])")
    }
    $lines.Add("")
    $lines.Add("## Keys Filled From English")
    $lines.Add("| Language | Directory | File | Key | Source | Value |")
    $lines.Add("|---|---|---|---|---|---|")
    foreach ($item in $todoItems | Sort-Object Language, Directory, FileType, Key) {
        $safeValue = ($item.Value -replace '\|', '\\|')
        $lines.Add("| $($item.Language) | $($item.Directory) | $($item.FileType) | $($item.Key) | $($item.Source) | $safeValue |")
    }
    Set-Content -Path $TodoReportPath -Value $lines -Encoding UTF8
}
else {
    $lines = @(
        "# Translation TODO Report",
        "",
        "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "BasePath: $BasePath",
        "Total keys needing translation: 0",
        "",
        "No English fallback inserts were needed."
    )
    Set-Content -Path $TodoReportPath -Value $lines -Encoding UTF8
}

Write-Host ""
Write-Host ("Backfill complete. Added {0} keys total." -f $totalAdded) -ForegroundColor Green
Write-Host ("TODO_TRANSLATE_TOTAL: {0}" -f $todoItems.Count)
Write-Host ("TODO_TRANSLATE_REPORT: {0}" -f $TodoReportPath)

