<#
.SYNOPSIS
    Refreshes the prod workshop item to the versioned Build 42 layout.

.DESCRIPTION
    Keeps `42` as the editable legacy source for 42.0-42.14, creates or
    refreshes `42.15`, removes shared `common/Translate`, and updates mod.info
    gates so one workshop item can serve both old and new B42 translation
    formats safely.
#>

[CmdletBinding()]
param(
    [string]$WorkshopRoot = "c:\Users\Pepsi\Zomboid\Workshop\BurdSurvivalJournals",
    [string]$ModFolder = "BurdSurvivalJournals"
)

$ErrorActionPreference = "Stop"

function Set-ModInfoValue {
    param(
        [Parameter(Mandatory = $true)][string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][string]$Value
    )

    $output = New-Object System.Collections.Generic.List[string]
    $matched = $false

    foreach ($line in $Lines) {
        if ($line -match ("^\s*" + [regex]::Escape($Key) + "\s*=")) {
            $matched = $true
            if ($null -ne $Value) {
                $output.Add(($Key + "=" + $Value))
            }
            continue
        }
        $output.Add($line)
    }

    if (-not $matched -and $null -ne $Value) {
        $output.Add(($Key + "=" + $Value))
    }

    return $output.ToArray()
}

function Update-VersionModInfo {
    param(
        [Parameter(Mandatory = $true)][string]$ModInfoPath,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$VersionMin,
        [AllowNull()][string]$VersionMax
    )

    if ($VersionMax -eq "") {
        $VersionMax = $null
    }

    $lines = Get-Content -Path $ModInfoPath -Encoding UTF8
    $lines = Set-ModInfoValue -Lines $lines -Key "name" -Value $Name
    $lines = Set-ModInfoValue -Lines $lines -Key "id" -Value $Id
    $lines = Set-ModInfoValue -Lines $lines -Key "versionMin" -Value $VersionMin
    $lines = Set-ModInfoValue -Lines $lines -Key "versionMax" -Value $VersionMax
    $lines = Set-ModInfoValue -Lines $lines -Key "pack" -Value $null
    Set-Content -Path $ModInfoPath -Value $lines -Encoding UTF8
}

$resolvedWorkshopRoot = (Resolve-Path $WorkshopRoot).Path
$modsRoot = Join-Path $resolvedWorkshopRoot "Contents\mods"
$currentModRoot = Join-Path $modsRoot $ModFolder

if (-not (Test-Path $currentModRoot)) {
    throw "Current mod folder not found: $currentModRoot"
}

$current42Root = Join-Path $currentModRoot "42"
$current4215Root = Join-Path $currentModRoot "42.15"
$commonTranslateRoot = Join-Path $currentModRoot "common\media\lua\shared\Translate"

if (-not (Test-Path $current42Root)) {
    throw "Current 42 folder not found: $current42Root"
}

if (Test-Path $current4215Root) {
    Remove-Item -Path $current4215Root -Recurse -Force
}
Copy-Item -Path $current42Root -Destination $current4215Root -Recurse

if (Test-Path $commonTranslateRoot) {
    Remove-Item -Path $commonTranslateRoot -Recurse -Force
}

Update-VersionModInfo -ModInfoPath (Join-Path $current42Root "mod.info") `
    -Name "Burd's Survival Journals" `
    -Id $ModFolder `
    -VersionMin "42.0" `
    -VersionMax "42.14"

Update-VersionModInfo -ModInfoPath (Join-Path $current4215Root "mod.info") `
    -Name "Burd's Survival Journals" `
    -Id $ModFolder `
    -VersionMin "42.15" `
    -VersionMax $null

Write-Host ("Updated versioned package: {0}" -f $currentModRoot) -ForegroundColor Green
Write-Host ("Current version folder    : {0}" -f $current4215Root) -ForegroundColor Green
Write-Host ("Legacy version folder     : {0}" -f $current42Root) -ForegroundColor Green
