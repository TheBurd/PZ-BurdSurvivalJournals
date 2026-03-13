<#
.SYNOPSIS
    Shared translation helpers for BSJ tooling.

.DESCRIPTION
    Supports both the legacy Lua-table translation files and the Build 42.15+
    JSON translation format while the repo migrates to JSON.
#>

$script:BSJTranslationPreferredFileTypes = @(
    "ContextMenu",
    "IG_UI",
    "ItemName",
    "Items",
    "Recipes",
    "Sandbox",
    "Tooltip",
    "UI"
)

function ConvertTo-BSJVersion {
    param([string]$VersionText)

    if (-not $VersionText) { return $null }
    try {
        if ($VersionText -match '^\d+$') {
            return [version]($VersionText + ".0")
        }
        return [version]$VersionText
    }
    catch {
        return $null
    }
}

function Get-BSJVersionDirs {
    param([Parameter(Mandatory = $true)][string]$BasePath)

    $versionDirs = @()
    Get-ChildItem -Path $BasePath -Directory | ForEach-Object {
        $modInfoPath = Join-Path $_.FullName "mod.info"
        $versionValue = ConvertTo-BSJVersion -VersionText $_.Name
        if ($versionValue -and (Test-Path $modInfoPath)) {
            $versionDirs += [pscustomobject]@{
                Name = $_.Name
                Version = $versionValue
                FullName = $_.FullName
            }
        }
    }

    return @($versionDirs | Sort-Object Version, Name)
}

function Get-BSJPrimaryVersionDir {
    param([Parameter(Mandatory = $true)][string]$BasePath)

    $versionDirs = Get-BSJVersionDirs -BasePath $BasePath
    if ($versionDirs.Count -eq 0) {
        return $null
    }

    return $versionDirs[-1]
}

function Get-BSJTranslationDirs {
    param([string]$BasePath)

    if (-not $BasePath) {
        return @(
            "42\media\lua\shared\Translate",
            "common\media\lua\shared\Translate"
        )
    }

    $dirs = New-Object System.Collections.Generic.List[string]
    foreach ($versionDir in (Get-BSJVersionDirs -BasePath $BasePath)) {
        $relativePath = Join-Path $versionDir.Name "media\lua\shared\Translate"
        if (Test-Path (Join-Path $BasePath $relativePath)) {
            $dirs.Add($relativePath)
        }
    }

    $commonPath = "common\media\lua\shared\Translate"
    if (Test-Path (Join-Path $BasePath $commonPath)) {
        $dirs.Add($commonPath)
    }

    return $dirs.ToArray()
}

function Get-BSJTranslationLanguages {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [string[]]$TranslationDirs = $(Get-BSJTranslationDirs)
    )

    $langs = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($dir in $TranslationDirs) {
        $fullDir = Join-Path $BasePath $dir
        if (-not (Test-Path $fullDir)) { continue }

        Get-ChildItem -Path $fullDir -Directory | ForEach-Object {
            if ($_.Name -match '^[A-Z0-9]+$') {
                [void]$langs.Add($_.Name.ToUpperInvariant())
            }
        }
    }

    return @([string[]]$langs | Sort-Object)
}

function Get-BSJTranslationFileTypes {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [string[]]$TranslationDirs = $(Get-BSJTranslationDirs)
    )

    $types = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($dir in $TranslationDirs) {
        $enDir = Join-Path $BasePath (Join-Path $dir "EN")
        if (-not (Test-Path $enDir)) { continue }

        Get-ChildItem -Path $enDir -File | ForEach-Object {
            if ($_.Extension -ieq ".json") {
                [void]$types.Add($_.BaseName)
            }
            elseif ($_.Extension -ieq ".txt" -and $_.BaseName -match '^(.*)_EN$') {
                [void]$types.Add($Matches[1])
            }
        }
    }

    $ordered = New-Object System.Collections.Generic.List[string]
    foreach ($preferred in $script:BSJTranslationPreferredFileTypes) {
        if ($types.Contains($preferred)) {
            $ordered.Add($preferred)
            [void]$types.Remove($preferred)
        }
    }

    foreach ($remaining in ([string[]]$types | Sort-Object)) {
        $ordered.Add($remaining)
    }

    return $ordered.ToArray()
}

function Get-BSJTranslationLegacyPath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$TranslationDir,
        [Parameter(Mandatory = $true)][string]$Language,
        [Parameter(Mandatory = $true)][string]$FileType
    )

    return Join-Path $BasePath (Join-Path $TranslationDir (Join-Path $Language ("{0}_{1}.txt" -f $FileType, $Language)))
}

function Get-BSJTranslationJsonPath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$TranslationDir,
        [Parameter(Mandatory = $true)][string]$Language,
        [Parameter(Mandatory = $true)][string]$FileType
    )

    return Join-Path $BasePath (Join-Path $TranslationDir (Join-Path $Language ("{0}.json" -f $FileType)))
}

function Resolve-BSJTranslationPath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$TranslationDir,
        [Parameter(Mandatory = $true)][string]$Language,
        [Parameter(Mandatory = $true)][string]$FileType,
        [switch]$PreferLegacy
    )

    $jsonPath = Get-BSJTranslationJsonPath -BasePath $BasePath -TranslationDir $TranslationDir -Language $Language -FileType $FileType
    $legacyPath = Get-BSJTranslationLegacyPath -BasePath $BasePath -TranslationDir $TranslationDir -Language $Language -FileType $FileType

    if ($PreferLegacy) {
        if (Test-Path $legacyPath) { return $legacyPath }
        if (Test-Path $jsonPath) { return $jsonPath }
        return $legacyPath
    }

    if (Test-Path $jsonPath) { return $jsonPath }
    if (Test-Path $legacyPath) { return $legacyPath }
    return $jsonPath
}

function Get-BSJTranslationFileFormat {
    param([string]$Path)

    if (-not $Path) { return "unknown" }
    $ext = [System.IO.Path]::GetExtension($Path)
    if ($ext -ieq ".json") { return "json" }
    if ($ext -ieq ".txt") { return "legacy" }
    return "unknown"
}

function ConvertFrom-BSJJsonEscape {
    param([string]$Value)

    if ($null -eq $Value) { return "" }
    $sentinel = [string][char]0xE000
    $result = $Value.Replace([string]"\\", $sentinel)
    $result = $result.Replace([string]'\n', [string]"`n")
    $result = $result.Replace([string]'\r', [string]"`r")
    $result = $result.Replace([string]'\t', [string]"`t")
    $result = $result.Replace([string]'\"', [string]'"')
    $result = $result.Replace([string]'\/', [string]'/')
    $result = $result.Replace($sentinel, [string]'\')
    return $result
}

function ConvertTo-BSJJsonEscape {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) { return "" }
    $result = $Value.Replace([string]'\', [string]'\\')
    $result = $result.Replace([string]'"', [string]'\"')
    $result = $result.Replace([string]"`r", [string]'\r')
    $result = $result.Replace([string]"`n", [string]'\n')
    $result = $result.Replace([string]"`t", [string]'\t')
    return $result
}

function ConvertFrom-BSJLegacyEscape {
    param([string]$Value)

    if ($null -eq $Value) { return "" }
    $sentinel = [string][char]0xE000
    $result = $Value.Replace([string]"\\", $sentinel)
    $result = $result.Replace([string]'\n', [string]"`n")
    $result = $result.Replace([string]'\r', [string]"`r")
    $result = $result.Replace([string]'\t', [string]"`t")
    $result = $result.Replace([string]'\"', [string]'"')
    $result = $result.Replace($sentinel, [string]'\')
    return $result
}

function ConvertTo-BSJLegacyEscape {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) { return "" }
    $result = $Value.Replace([string]'\', [string]'\\')
    $result = $result.Replace([string]'"', [string]'\"')
    $result = $result.Replace([string]"`r", [string]'\r')
    $result = $result.Replace([string]"`n", [string]'\n')
    $result = $result.Replace([string]"`t", [string]'\t')
    return $result
}

function ConvertTo-BSJJsonPlaceholderSyntax {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) { return "" }

    $existingMatches = [regex]::Matches($Value, '%(\d+)')
    $nextIndex = 0
    foreach ($match in $existingMatches) {
        $index = [int]$match.Groups[1].Value
        if ($index -gt $nextIndex) {
            $nextIndex = $index
        }
    }

    $builder = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $Value.Length; $i++) {
        $currentChar = $Value[$i]
        if ($currentChar -ne '%') {
            [void]$builder.Append($currentChar)
            continue
        }

        if (($i + 1) -ge $Value.Length) {
            [void]$builder.Append($currentChar)
            continue
        }

        $nextChar = $Value[$i + 1]
        if ($nextChar -eq '%') {
            [void]$builder.Append('%%')
            $i++
            continue
        }

        if ([char]::IsDigit($nextChar)) {
            [void]$builder.Append('%')
            continue
        }

        if ("sSdDiIfF".Contains([string]$nextChar)) {
            $nextIndex++
            [void]$builder.Append('%')
            [void]$builder.Append([string]$nextIndex)
            $i++
            continue
        }

        [void]$builder.Append($currentChar)
    }

    return $builder.ToString()
}

function Get-BSJTranslationMap {
    param([string]$Path)

    $map = [ordered]@{}
    if (-not $Path -or -not (Test-Path $Path)) {
        return $map
    }

    $format = Get-BSJTranslationFileFormat -Path $Path
    $content = Get-Content -Path $Path -Raw -Encoding UTF8

    if ($format -eq "json") {
        $matches = [regex]::Matches(
            $content,
            '(?m)^\s*"((?:[^"\\]|\\.)+)"\s*:\s*"((?:[^"\\]|\\.)*)"\s*,?\s*$'
        )

        foreach ($m in $matches) {
            $key = ConvertFrom-BSJJsonEscape $m.Groups[1].Value
            $value = ConvertFrom-BSJJsonEscape $m.Groups[2].Value
            $map[$key] = $value
        }

        return $map
    }

    $matches = [regex]::Matches(
        $content,
        '(?m)^\s*([A-Za-z0-9_\.]+)\s*=\s*"((?:\\.|[^"\\])*)"\s*,?\s*(?:--.*)?$'
    )

    foreach ($m in $matches) {
        $key = $m.Groups[1].Value
        if ($key -match '^[A-Za-z]+_[A-Z0-9]{2,4}$') {
            continue
        }
        $value = ConvertFrom-BSJLegacyEscape $m.Groups[2].Value
        $map[$key] = $value
    }

    return $map
}

function Write-BSJUtf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Lines
    )

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $content = [string]::Join("`r`n", $Lines)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $content, $utf8NoBom)
}

function Write-BSJTranslationJsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Map,
        [string[]]$ReferenceKeyOrder = @()
    )

    $orderedKeys = New-Object System.Collections.Generic.List[string]
    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::Ordinal)

    foreach ($key in $ReferenceKeyOrder) {
        if ($Map.Contains($key) -and $seen.Add($key)) {
            $orderedKeys.Add($key)
        }
    }

    foreach ($key in $Map.Keys) {
        if ($seen.Add([string]$key)) {
            $orderedKeys.Add([string]$key)
        }
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("{")
    for ($i = 0; $i -lt $orderedKeys.Count; $i++) {
        $key = $orderedKeys[$i]
        $value = ConvertTo-BSJJsonPlaceholderSyntax ([string]$Map[$key])
        $comma = if ($i -lt ($orderedKeys.Count - 1)) { "," } else { "" }
        $lines.Add(('    "{0}": "{1}"{2}' -f (ConvertTo-BSJJsonEscape $key), (ConvertTo-BSJJsonEscape $value), $comma))
    }
    $lines.Add("}")

    Write-BSJUtf8NoBomFile -Path $Path -Lines $lines.ToArray()
}

function Write-BSJTranslationLegacyFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Map,
        [Parameter(Mandatory = $true)][string]$FileType,
        [Parameter(Mandatory = $true)][string]$Language,
        [string[]]$ReferenceKeyOrder = @()
    )

    $orderedKeys = New-Object System.Collections.Generic.List[string]
    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::Ordinal)

    foreach ($key in $ReferenceKeyOrder) {
        if ($Map.Contains($key) -and $seen.Add($key)) {
            $orderedKeys.Add($key)
        }
    }

    foreach ($key in $Map.Keys) {
        if ($seen.Add([string]$key)) {
            $orderedKeys.Add([string]$key)
        }
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(("{0}_{1} = {{" -f $FileType, $Language))
    foreach ($key in $orderedKeys) {
        $value = [string]$Map[$key]
        $lines.Add(('    {0} = "{1}",' -f $key, (ConvertTo-BSJLegacyEscape $value)))
    }
    $lines.Add("}")

    Write-BSJUtf8NoBomFile -Path $Path -Lines $lines.ToArray()
}

function Write-BSJTranslationFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Map,
        [string]$FileType,
        [string]$Language,
        [string[]]$ReferenceKeyOrder = @()
    )

    $format = Get-BSJTranslationFileFormat -Path $Path
    if ($format -eq "legacy") {
        if (-not $FileType -or -not $Language) {
            throw "Legacy translation writes require FileType and Language."
        }
        Write-BSJTranslationLegacyFile -Path $Path -Map $Map -FileType $FileType -Language $Language -ReferenceKeyOrder $ReferenceKeyOrder
        return
    }

    Write-BSJTranslationJsonFile -Path $Path -Map $Map -ReferenceKeyOrder $ReferenceKeyOrder
}
