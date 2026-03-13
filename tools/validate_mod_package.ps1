<#
.SYNOPSIS
    Validates the BSJ dev mod layout for versioned Build 42 packaging.
#>

[CmdletBinding()]
param(
    [string]$BasePath = "c:\Users\Pepsi\Zomboid\Workshop\BurdSurvivalJournals\Contents\mods\BurdSurvivalJournals",
    [ValidateSet("auto", "json", "legacy")][string]$ExpectedTranslationFormat = "auto"
)

$ErrorActionPreference = "Stop"

$helperPath = Join-Path $PSScriptRoot "translation_helpers.ps1"
. $helperPath

$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$packageName = Split-Path -Path $BasePath -Leaf
$versionSummaries = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message) | Out-Null
}

function Add-Warning {
    param([string]$Message)
    $warnings.Add($Message) | Out-Null
}

function Resolve-ExpectedTranslationFormat {
    param(
        [string]$RequestedFormat,
        [version]$VersionDirVersion
    )

    if ($RequestedFormat -ne "auto") {
        return $RequestedFormat
    }

    if ($VersionDirVersion -ge ([version]"42.15")) {
        return "json"
    }

    return "legacy"
}

function Get-TranslationFileTypesForDir {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$TranslationDir
    )

    return Get-BSJTranslationFileTypes -BasePath $BasePath -TranslationDirs @($TranslationDir)
}

function Get-TranslationLanguagesForDir {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$TranslationDir
    )

    return Get-BSJTranslationLanguages -BasePath $BasePath -TranslationDirs @($TranslationDir)
}

$versionDirs = Get-BSJVersionDirs -BasePath $BasePath
if ($versionDirs.Count -eq 0) {
    Add-Failure "No versioned mod folders with mod.info were found under: $BasePath"
}

$commonTranslateRoot = Join-Path $BasePath "common\media\lua\shared\Translate"
if (Test-Path $commonTranslateRoot) {
    Add-Failure "Shared translations found at $commonTranslateRoot. Split-format packages must keep translations inside version folders only."
}

foreach ($versionDir in $versionDirs) {
    $versionName = $versionDir.Name
    $expectedFormat = Resolve-ExpectedTranslationFormat -RequestedFormat $ExpectedTranslationFormat -VersionDirVersion $versionDir.Version
    $modInfoPath = Join-Path $versionDir.FullName "mod.info"
    $translationDir = Join-Path $versionName "media\lua\shared\Translate"
    $translationRoot = Join-Path $BasePath $translationDir
    $versionSummaries.Add(("{0} ({1})" -f $versionName, $expectedFormat)) | Out-Null

    if (-not (Test-Path $modInfoPath)) {
        Add-Failure "Missing required mod.info: $modInfoPath"
        continue
    }

    $modInfo = (Get-Content -Path $modInfoPath -Encoding UTF8) -join "`n"
    $versionMinMatch = [regex]::Match($modInfo, '(?m)^\s*versionMin\s*=\s*([0-9]+\.[0-9]+)\s*$')
    $versionMaxMatch = [regex]::Match($modInfo, '(?m)^\s*versionMax\s*=\s*([0-9]+\.[0-9]+)\s*$')
    $idMatch = [regex]::Match($modInfo, '(?m)^\s*id\s*=\s*(.+?)\s*$')

    if (-not $versionMinMatch.Success) {
        Add-Warning "$versionName mod.info is missing versionMin."
    }
    if ($modInfo -match '(?m)^\s*pack\s*=') {
        Add-Warning "$versionName mod.info declares pack=. Remove it unless this mod actually ships a packed archive."
    }
    if (-not $idMatch.Success) {
        Add-Failure "$versionName mod.info is missing id."
    }
    elseif ($idMatch.Groups[1].Value.Trim() -ne $packageName) {
        Add-Failure "$versionName mod.info id '$($idMatch.Groups[1].Value.Trim())' does not match package folder '$packageName'."
    }

    if ($expectedFormat -eq "json" -and $versionMaxMatch.Success) {
        Add-Failure "$versionName mod.info still declares versionMax; remove it for 42.15+ compatibility."
    }
    if ($expectedFormat -eq "legacy" -and -not $versionMaxMatch.Success) {
        Add-Warning "$versionName legacy folder has no versionMax. Recommend capping it below 42.15."
    }

    if (-not (Test-Path $translationRoot)) {
        Add-Failure "Missing translation root: $translationRoot"
        continue
    }

    $languages = Get-TranslationLanguagesForDir -BasePath $BasePath -TranslationDir $translationDir
    $fileTypes = Get-TranslationFileTypesForDir -BasePath $BasePath -TranslationDir $translationDir

    if ($languages.Count -eq 0) {
        Add-Failure "No translation languages found under: $translationRoot"
        continue
    }
    if ($fileTypes.Count -eq 0) {
        Add-Failure "No translation file types found under: $translationRoot"
        continue
    }

    $legacyFiles = Get-ChildItem -Path $translationRoot -Recurse -File -Filter "*.txt" |
        Where-Object { $_.BaseName -match '_.{2,4}$' -and $_.Name -ne "language.txt" -and $_.Name -ne "credits.txt" }
    $jsonFiles = Get-ChildItem -Path $translationRoot -Recurse -File -Filter "*.json"

    if ($expectedFormat -eq "json") {
        foreach ($legacy in $legacyFiles) {
            Add-Failure "Legacy translation file still present in ${versionName}: $($legacy.FullName)"
        }
        foreach ($json in $jsonFiles) {
            $rawJson = Get-Content -Path $json.FullName -Raw -Encoding UTF8
            if ($rawJson -match '(?<!%)%(?![%\d])[sSdDiIfF]') {
                Add-Failure "Unnumbered printf placeholder found in JSON translation file: $($json.FullName)"
            }
        }
    }
    else {
        foreach ($json in $jsonFiles) {
            Add-Failure "JSON translation file still present in legacy folder ${versionName}: $($json.FullName)"
        }
    }

    foreach ($lang in $languages) {
        $langDir = Join-Path $translationRoot $lang
        if (-not (Test-Path $langDir)) {
            Add-Warning "Missing language directory: $langDir"
            continue
        }

        foreach ($fileType in $fileTypes) {
            $targetPath = if ($expectedFormat -eq "legacy") {
                Get-BSJTranslationLegacyPath -BasePath $BasePath -TranslationDir $translationDir -Language $lang -FileType $fileType
            }
            else {
                Get-BSJTranslationJsonPath -BasePath $BasePath -TranslationDir $translationDir -Language $lang -FileType $fileType
            }

            if (-not (Test-Path $targetPath)) {
                Add-Failure "Missing $expectedFormat translation file: $targetPath"
                continue
            }

            $map = Get-BSJTranslationMap -Path $targetPath
            if ($map.Count -eq 0) {
                Add-Failure "Translation file has no parsed keys: $targetPath"
            }
        }
    }
}

Write-Host ("=" * 72) -ForegroundColor Cyan
Write-Host ("PACKAGE VALIDATION - {0}" -f $packageName) -ForegroundColor Cyan
Write-Host ("=" * 72) -ForegroundColor Cyan
Write-Host "Base Path: $BasePath"
Write-Host "Versions : $($versionSummaries -join ', ')"
Write-Host ""

if ($failures.Count -eq 0) {
    Write-Host "STATUS: PASS" -ForegroundColor Green
}
else {
    Write-Host "STATUS: FAIL" -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host "- $failure" -ForegroundColor Red
    }
}

if ($warnings.Count -gt 0) {
    Write-Host ""
    Write-Host "Warnings:" -ForegroundColor Yellow
    foreach ($warning in $warnings) {
        Write-Host "- $warning" -ForegroundColor Yellow
    }
}

if ($failures.Count -gt 0) {
    exit 1
}

exit 0
