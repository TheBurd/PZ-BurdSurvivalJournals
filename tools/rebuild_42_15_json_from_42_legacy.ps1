<#
.SYNOPSIS
    Rebuilds the 42.15 JSON translations from the intact 42 legacy sources.
#>

[CmdletBinding()]
param(
    [string]$BasePath = "c:\Users\Pepsi\Zomboid\Workshop\BurdSurvivalJournals\Contents\mods\BurdSurvivalJournals",
    [string]$SourceVersion = "42",
    [string]$TargetVersion = "42.15"
)

$ErrorActionPreference = "Stop"

$helperPath = Join-Path $PSScriptRoot "translation_helpers.ps1"
. $helperPath

$sourceTranslationDir = Join-Path $SourceVersion "media\lua\shared\Translate"
$targetTranslationDir = Join-Path $TargetVersion "media\lua\shared\Translate"

$sourceRoot = Join-Path $BasePath $sourceTranslationDir
$targetRoot = Join-Path $BasePath $targetTranslationDir

if (-not (Test-Path $sourceRoot)) {
    throw "Source translation root not found: $sourceRoot"
}

if (-not (Test-Path $targetRoot)) {
    New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
}

$languages = Get-BSJTranslationLanguages -BasePath $BasePath -TranslationDirs @($sourceTranslationDir)
$fileTypes = Get-BSJTranslationFileTypes -BasePath $BasePath -TranslationDirs @($sourceTranslationDir)
$rebuilt = 0

Get-ChildItem -Path $targetRoot -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item -Path $_.FullName -Force
}

foreach ($lang in $languages) {
    foreach ($fileType in $fileTypes) {
        $legacyPath = Get-BSJTranslationLegacyPath -BasePath $BasePath -TranslationDir $sourceTranslationDir -Language $lang -FileType $fileType
        if (-not (Test-Path $legacyPath)) {
            continue
        }

        $referenceLegacyPath = Get-BSJTranslationLegacyPath -BasePath $BasePath -TranslationDir $sourceTranslationDir -Language "EN" -FileType $fileType
        $map = Get-BSJTranslationMap -Path $legacyPath
        $referenceMap = Get-BSJTranslationMap -Path $referenceLegacyPath
        $jsonPath = Get-BSJTranslationJsonPath -BasePath $BasePath -TranslationDir $targetTranslationDir -Language $lang -FileType $fileType

        Write-BSJTranslationJsonFile -Path $jsonPath -Map $map -ReferenceKeyOrder @($referenceMap.Keys)
        $rebuilt++
        Write-Host ("Rebuilt 42.15 JSON -> {0}" -f $jsonPath)
    }
}

Write-Host ""
Write-Host ("Rebuild complete. Generated {0} JSON file(s)." -f $rebuilt) -ForegroundColor Green
