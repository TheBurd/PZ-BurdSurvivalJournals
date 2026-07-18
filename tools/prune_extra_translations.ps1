<#
.SYNOPSIS
    Remove translation keys that are not in EN reference files.

.DESCRIPTION
    Supports the JSON translation format used by Build 42.15+ and rewrites
    files as JSON.
#>

[CmdletBinding()]
param(
    [string]$BasePath = "c:\Users\Pepsi\Zomboid\Workshop\BurdSurvivalJournals\mods\BurdSurvivalJournals"
)

$ErrorActionPreference = "Stop"

$helperPath = Join-Path $PSScriptRoot "translation_helpers.ps1"
. $helperPath

$TranslationDirs = Get-BSJTranslationDirs -BasePath $BasePath
$Languages = @(Get-BSJTranslationLanguages -BasePath $BasePath -TranslationDirs $TranslationDirs | Where-Object { $_ -ne "EN" })
$FileTypes = Get-BSJTranslationFileTypes -BasePath $BasePath -TranslationDirs $TranslationDirs

$totalRemoved = 0

foreach ($dir in $TranslationDirs) {
    foreach ($fileType in $FileTypes) {
        $enPath = Resolve-BSJTranslationPath -BasePath $BasePath -TranslationDir $dir -Language "EN" -FileType $fileType
        $reference = Get-BSJTranslationMap -Path $enPath
        if ($reference.Count -eq 0) {
            continue
        }

        $referenceKeyOrder = @($reference.Keys)

        foreach ($lang in $Languages) {
            $path = Resolve-BSJTranslationPath -BasePath $BasePath -TranslationDir $dir -Language $lang -FileType $fileType
            if (-not (Test-Path $path)) { continue }

            $current = Get-BSJTranslationMap -Path $path
            $kept = [ordered]@{}
            $removed = 0
            foreach ($key in $current.Keys) {
                if ($reference.Contains($key)) {
                    $kept[$key] = $current[$key]
                }
                else {
                    $removed++
                }
            }

            if ($removed -gt 0) {
                Write-BSJTranslationFile -Path $path -Map $kept -FileType $fileType -Language $lang -ReferenceKeyOrder $referenceKeyOrder
                $totalRemoved += $removed
                Write-Host ("Removed {0,3} keys -> {1}" -f $removed, $path)
            }
        }
    }
}

Write-Host ""
Write-Host ("Prune complete. Removed {0} extra keys total." -f $totalRemoved) -ForegroundColor Green

