<#
.SYNOPSIS
    Convert legacy BSJ translation files to the Build 42.15+ JSON format.
#>

[CmdletBinding()]
param(
    [string]$BasePath = "c:\Users\Pepsi\Zomboid\Workshop\BurdSurvivalJournals\mods\BurdSurvivalJournals",
    [switch]$RemoveLegacyFiles
)

$ErrorActionPreference = "Stop"

$helperPath = Join-Path $PSScriptRoot "translation_helpers.ps1"
. $helperPath

$TranslationDirs = Get-BSJTranslationDirs -BasePath $BasePath
$Languages = Get-BSJTranslationLanguages -BasePath $BasePath -TranslationDirs $TranslationDirs
$FileTypes = Get-BSJTranslationFileTypes -BasePath $BasePath -TranslationDirs $TranslationDirs

$converted = 0
$removed = 0

foreach ($dir in $TranslationDirs) {
    foreach ($lang in $Languages) {
        foreach ($fileType in $FileTypes) {
            $legacyPath = Get-BSJTranslationLegacyPath -BasePath $BasePath -TranslationDir $dir -Language $lang -FileType $fileType
            if (-not (Test-Path $legacyPath)) {
                continue
            }

            $map = Get-BSJTranslationMap -Path $legacyPath
            if ($map.Count -eq 0) {
                Write-Warning "Skipping empty legacy translation file: $legacyPath"
                continue
            }

            $referencePath = Resolve-BSJTranslationPath -BasePath $BasePath -TranslationDir $dir -Language "EN" -FileType $fileType -PreferLegacy
            $referenceMap = Get-BSJTranslationMap -Path $referencePath
            $jsonPath = Get-BSJTranslationJsonPath -BasePath $BasePath -TranslationDir $dir -Language $lang -FileType $fileType
            Write-BSJTranslationJsonFile -Path $jsonPath -Map $map -ReferenceKeyOrder @($referenceMap.Keys)
            $converted++
            Write-Host ("Converted -> {0}" -f $jsonPath)

            if ($RemoveLegacyFiles) {
                Remove-Item -Path $legacyPath -Force
                $removed++
            }
        }
    }
}

Write-Host ""
Write-Host ("Migration complete. Converted {0} file(s)." -f $converted) -ForegroundColor Green
if ($RemoveLegacyFiles) {
    Write-Host ("Removed {0} legacy file(s)." -f $removed) -ForegroundColor Green
}

