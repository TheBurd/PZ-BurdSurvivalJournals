<#
.SYNOPSIS
    Sync missing EN translation keys from 42 -> common.

.DESCRIPTION
    Supports JSON translations used by Build 42.15+ and rewrites synced files
    as JSON.
#>

[CmdletBinding()]
param(
    [string]$BasePath = "c:\Users\Pepsi\Zomboid\Workshop\BurdSurvivalJournals\mods\BurdSurvivalJournals"
)

$ErrorActionPreference = "Stop"

$helperPath = Join-Path $PSScriptRoot "translation_helpers.ps1"
. $helperPath

$commonTranslateDir = "common\media\lua\shared\Translate"
if (-not (Test-Path (Join-Path $BasePath $commonTranslateDir))) {
    Write-Host "No common translation directory found. Skipping sync." -ForegroundColor Yellow
    exit 0
}

$primaryVersionDir = Get-BSJPrimaryVersionDir -BasePath $BasePath
if (-not $primaryVersionDir) {
    throw "Could not resolve a version directory under: $BasePath"
}

$primaryTranslateDir = Join-Path $primaryVersionDir.Name "media\lua\shared\Translate"
$FileTypes = Get-BSJTranslationFileTypes -BasePath $BasePath -TranslationDirs @($primaryTranslateDir, $commonTranslateDir)
$totalAdded = 0

foreach ($fileType in $FileTypes) {
    $srcPath = Resolve-BSJTranslationPath -BasePath $BasePath -TranslationDir $primaryTranslateDir -Language "EN" -FileType $fileType
    $dstPath = Resolve-BSJTranslationPath -BasePath $BasePath -TranslationDir $commonTranslateDir -Language "EN" -FileType $fileType
    if (-not (Test-Path $srcPath) -or -not (Test-Path $dstPath)) {
        continue
    }

    $src = Get-BSJTranslationMap -Path $srcPath
    $dst = Get-BSJTranslationMap -Path $dstPath
    $updated = [ordered]@{}
    foreach ($key in $dst.Keys) {
        $updated[$key] = $dst[$key]
    }

    $missing = @()
    foreach ($key in $src.Keys) {
        if (-not $updated.Contains($key)) {
            $updated[$key] = $src[$key]
            $missing += $key
        }
    }

    if ($missing.Count -eq 0) {
        continue
    }

    $jsonPath = Get-BSJTranslationJsonPath -BasePath $BasePath -TranslationDir $commonTranslateDir -Language "EN" -FileType $fileType
    Write-BSJTranslationJsonFile -Path $jsonPath -Map $updated -ReferenceKeyOrder @($src.Keys)
    $totalAdded += $missing.Count
    Write-Host ("Added {0,3} keys -> {1}" -f $missing.Count, $jsonPath)
}

Write-Host ""
Write-Host ("Sync complete. Added {0} EN keys to common." -f $totalAdded) -ForegroundColor Green

