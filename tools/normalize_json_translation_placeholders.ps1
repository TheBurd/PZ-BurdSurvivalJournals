<#
.SYNOPSIS
    Rewrites BSJ JSON translation files so placeholder syntax matches Build 42.15.
#>

[CmdletBinding()]
param(
    [string]$BasePath = "c:\Users\Pepsi\Zomboid\Workshop\BurdSurvivalJournals\mods\BurdSurvivalJournals"
)

$ErrorActionPreference = "Stop"

$helperPath = Join-Path $PSScriptRoot "translation_helpers.ps1"
. $helperPath

$rewritten = 0

foreach ($translationDir in (Get-BSJTranslationDirs -BasePath $BasePath)) {
    $translationRoot = Join-Path $BasePath $translationDir
    if (-not (Test-Path $translationRoot)) {
        continue
    }

    foreach ($jsonFile in (Get-ChildItem -Path $translationRoot -Recurse -File -Filter "*.json")) {
        $map = Get-BSJTranslationMap -Path $jsonFile.FullName
        if ($map.Count -eq 0) {
            continue
        }

        Write-BSJTranslationJsonFile -Path $jsonFile.FullName -Map $map -ReferenceKeyOrder @($map.Keys)
        $rewritten++
        Write-Host ("Normalized JSON placeholders -> {0}" -f $jsonFile.FullName)
    }
}

Write-Host ""
Write-Host ("Normalization complete. Rewrote {0} JSON file(s)." -f $rewritten) -ForegroundColor Green

