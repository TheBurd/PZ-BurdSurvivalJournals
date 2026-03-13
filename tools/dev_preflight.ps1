<#
.SYNOPSIS
    Dev preflight checks for Burd's Survival Journals.

.DESCRIPTION
    Runs a fast local validation pass before workshop upload:
    0) Optional translation normalization/fix pass
    1) Package/layout validation for Build 42.15
    2) Lua syntax check (luac -p) for all mod Lua files
    3) Lua unit tests in tools/tests/run_tests.lua
    4) Translation audit report
    5) Hardcoded string scan report

    Syntax/test failures stop the run with non-zero exit code.
    Translation/string scans are informational by default.
#>

[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$ModRoot = "Contents\mods\BurdSurvivalJournals",
    [string]$LuaExe,
    [string]$LuacExe,
    [switch]$FixTranslations,
    [switch]$Strict,
    [int]$MaxMissingTranslations = 0,
    [int]$MaxExtraTranslations = 0,
    [int]$MaxCriticalStrings = 0,
    [int]$MaxHighStrings = 0,
    [int]$MaxStringDiscrepancies = 0,
    [switch]$SkipSyntax,
    [switch]$SkipTests,
    [switch]$SkipTranslationAudit,
    [switch]$SkipStringScan,
    [switch]$SkipPackageValidation,
    [switch]$SkipPrintLint,
    [int]$MaxNonErrorPrints = 0
)

$ErrorActionPreference = "Stop"

if (-not $ProjectRoot) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ProjectRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path
}

function Resolve-ExecutablePath {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$OverridePath
    )

    if ($OverridePath) {
        if (Test-Path $OverridePath) {
            return (Resolve-Path $OverridePath).Path
        }
        return $null
    }

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) {
        return $cmd.Source
    }

    $scoopShim = Join-Path $env:USERPROFILE ("scoop\shims\" + $Name + ".exe")
    if (Test-Path $scoopShim) {
        return $scoopShim
    }

    return $null
}

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host ("=" * 72) -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host ("=" * 72) -ForegroundColor Cyan
}

function Get-RelativePathCompat {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    try {
        if ([System.IO.Path].GetMethod("GetRelativePath", [type[]]@([string], [string]))) {
            return [System.IO.Path]::GetRelativePath($BasePath, $TargetPath)
        }
    }
    catch {
    }

    $baseUri = New-Object System.Uri(((Resolve-Path $BasePath).Path.TrimEnd('\') + '\'))
    $targetUri = New-Object System.Uri((Resolve-Path $TargetPath).Path)
    $relativeUri = $baseUri.MakeRelativeUri($targetUri)
    return [System.Uri]::UnescapeDataString($relativeUri.ToString()).Replace('/', '\')
}

function Invoke-ToolScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [string[]]$Arguments = @()
    )

    $exe = (Get-Command powershell -ErrorAction SilentlyContinue).Source
    if (-not $exe) {
        throw "Could not resolve powershell executable for running tool script: $ScriptPath"
    }

    $output = & $exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1
    foreach ($line in $output) {
        Write-Host $line
    }

    return @{
        Output = $output
        ExitCode = $LASTEXITCODE
    }
}

function Parse-TranslationAuditSummary {
    param([string[]]$Lines)
    $joined = ($Lines -join "`n")

    $missing = $null
    $extra = $null

    $actionMatch = [regex]::Match($joined, 'ACTION REQUIRED:\s*(\d+)\s+missing translation\(s\)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($actionMatch.Success) {
        $missing = [int]$actionMatch.Groups[1].Value
    }

    $totalMatches = [regex]::Matches($joined, '^\s*TOTAL\s+(\d+)\s+(\d+)\s*$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if ($totalMatches.Count -gt 0) {
        $last = $totalMatches[$totalMatches.Count - 1]
        $missing = [int]$last.Groups[1].Value
        $extra = [int]$last.Groups[2].Value
    }

    if ($null -eq $missing) { $missing = 0 }
    if ($null -eq $extra) { $extra = 0 }

    return @{
        Missing = $missing
        Extra = $extra
    }
}

function Parse-StringScanSummary {
    param([string[]]$Lines)
    $joined = ($Lines -join "`n")

    $critical = 0
    $high = 0
    $medium = 0
    $discrepancies = 0

    $m = [regex]::Match($joined, 'Critical issues:\s*(\d+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) { $critical = [int]$m.Groups[1].Value }
    $m = [regex]::Match($joined, 'High priority:\s*(\d+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) { $high = [int]$m.Groups[1].Value }
    $m = [regex]::Match($joined, 'Medium priority:\s*(\d+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) { $medium = [int]$m.Groups[1].Value }
    $m = [regex]::Match($joined, 'File discrepancies:\s*(\d+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) { $discrepancies = [int]$m.Groups[1].Value }

    return @{
        Critical = $critical
        High = $high
        Medium = $medium
        Discrepancies = $discrepancies
    }
}

function Parse-BackfillTodoSummary {
    param([string[]]$Lines)
    $joined = ($Lines -join "`n")

    $count = 0
    $report = ""

    $m = [regex]::Match($joined, 'TODO_TRANSLATE_TOTAL:\s*(\d+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) {
        $count = [int]$m.Groups[1].Value
    }

    $m = [regex]::Match($joined, 'TODO_TRANSLATE_REPORT:\s*(.+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) {
        $report = $m.Groups[1].Value.Trim()
    }

    return @{
        Count = $count
        ReportPath = $report
    }
}

function Get-NonErrorPrintViolations {
    param(
        [Parameter(Mandatory = $true)][string]$ModRootPath
    )

    $helperPath = Join-Path $PSScriptRoot "translation_helpers.ps1"
    . $helperPath

    $scanRoots = New-Object System.Collections.Generic.List[string]
    foreach ($versionDir in (Get-BSJVersionDirs -BasePath $ModRootPath)) {
        foreach ($relative in @("media\lua\client", "media\lua\server")) {
            $scanRoots.Add((Join-Path $versionDir.FullName $relative)) | Out-Null
        }
    }

    foreach ($relative in @("common\media\lua\client", "common\media\lua\server")) {
        $scanRoots.Add((Join-Path $ModRootPath $relative)) | Out-Null
    }

    $violations = New-Object System.Collections.Generic.List[object]
    $allowedTags = @("ERROR", "WARNING", "ADMIN", "PROTECTED")
    $callPattern = '^\s*print\s*\('

    foreach ($root in $scanRoots) {
        if (-not (Test-Path $root)) { continue }

        $luaFiles = Get-ChildItem -Path $root -Recurse -File -Filter "*.lua"
        foreach ($file in $luaFiles) {
            $lineNumber = 0
            foreach ($line in Get-Content -Path $file.FullName) {
                $lineNumber++
                if ($line -notmatch $callPattern) { continue }

                $isAllowed = $false
                foreach ($tag in $allowedTags) {
                    if ($line -match $tag) {
                        $isAllowed = $true
                        break
                    }
                }
                if ($isAllowed) { continue }

                $relativePath = Get-RelativePathCompat -BasePath $ModRootPath -TargetPath $file.FullName
                $violations.Add([pscustomobject]@{
                    Path = $relativePath
                    Line = $lineNumber
                    Code = $line.Trim()
                })
            }
        }
    }

    return $violations
}

$resolvedProjectRoot = (Resolve-Path $ProjectRoot).Path
$resolvedModRoot = if ([System.IO.Path]::IsPathRooted($ModRoot)) {
    $ModRoot
}
else {
    Join-Path $resolvedProjectRoot $ModRoot
}

if (-not (Test-Path $resolvedModRoot)) {
    throw "Mod root not found: $resolvedModRoot"
}

$toolsDir = $PSScriptRoot
$testsRunner = Join-Path $toolsDir "tests\run_tests.lua"
$translationAuditScript = Join-Path $toolsDir "translation_audit.ps1"
$stringScanScript = Join-Path $toolsDir "hardcoded_string_detector.ps1"
$packageValidationScript = Join-Path $toolsDir "validate_mod_package.ps1"
$syncCommonENScript = Join-Path $toolsDir "sync_common_en_from_42.ps1"
$pruneExtrasScript = Join-Path $toolsDir "prune_extra_translations.ps1"
$backfillScript = Join-Path $toolsDir "backfill_missing_translations.ps1"
$rebuild4215JsonScript = Join-Path $toolsDir "rebuild_42_15_json_from_42_legacy.ps1"
$normalizeJsonPlaceholdersScript = Join-Path $toolsDir "normalize_json_translation_placeholders.ps1"
$translationTodoReport = Join-Path $toolsDir "translation_todo_report.md"

$luaPath = Resolve-ExecutablePath -Name "lua" -OverridePath $LuaExe
$luacPath = Resolve-ExecutablePath -Name "luac" -OverridePath $LuacExe

$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

Write-Host "Project Root : $resolvedProjectRoot"
Write-Host "Mod Root     : $resolvedModRoot"
Write-Host "Lua          : $(if ($luaPath) { $luaPath } else { '<not found>' })"
Write-Host "Luac         : $(if ($luacPath) { $luacPath } else { '<not found>' })"
Write-Host "Fix Translations: $FixTranslations"
Write-Host "Strict Mode  : $Strict"

if ($FixTranslations) {
    Write-Step "Step 0: Translation Normalization (Auto-Fix)"

    $scripts = @(
        @{ Name = "sync_common_en_from_42.ps1"; Path = $syncCommonENScript },
        @{ Name = "prune_extra_translations.ps1"; Path = $pruneExtrasScript },
        @{ Name = "backfill_missing_translations.ps1"; Path = $backfillScript },
        @{ Name = "rebuild_42_15_json_from_42_legacy.ps1"; Path = $rebuild4215JsonScript },
        @{ Name = "normalize_json_translation_placeholders.ps1"; Path = $normalizeJsonPlaceholdersScript }
    )

    foreach ($script in $scripts) {
        if (-not (Test-Path $script.Path)) {
            $failures.Add("Missing translation fixer script: $($script.Name)")
            continue
        }

        Write-Host ("Running {0}..." -f $script.Name)
        $args = @("-BasePath", $resolvedModRoot)
        if ($script.Name -eq "backfill_missing_translations.ps1") {
            $args += @("-TodoReportPath", $translationTodoReport)
        }

        $result = Invoke-ToolScript -ScriptPath $script.Path -Arguments $args
        if ($result.ExitCode -ne 0) {
            $failures.Add("$($script.Name) failed with exit code $($result.ExitCode).")
        }

        if ($script.Name -eq "backfill_missing_translations.ps1") {
            $todoSummary = Parse-BackfillTodoSummary -Lines $result.Output
            Write-Host ("Translation TODO summary: {0} key(s) need localization." -f $todoSummary.Count)
            if ($todoSummary.ReportPath) {
                Write-Host ("Translation TODO report: {0}" -f $todoSummary.ReportPath)
            }
            if ($todoSummary.Count -gt 0) {
                $warnings.Add("Translation placeholders inserted from EN: $($todoSummary.Count). See $($todoSummary.ReportPath).")
            }
        }
    }
}

if (-not $SkipPackageValidation) {
    if (Test-Path $packageValidationScript) {
        Write-Step "Step 1: Package Validation"
        $result = Invoke-ToolScript -ScriptPath $packageValidationScript -Arguments @("-BasePath", $resolvedModRoot)
        if ($result.ExitCode -ne 0) {
            $failures.Add("Package validation failed.")
        }
        else {
            Write-Host "Package validation passed." -ForegroundColor Green
        }
    }
    else {
        $warnings.Add("validate_mod_package.ps1 not found.")
    }
}

if (-not $SkipSyntax) {
    if (-not $luacPath) {
        $failures.Add("luac executable not found. Install Lua or pass -LuacExe.")
    }
    else {
        Write-Step "Step 2: Lua Syntax Check"
        $luaFiles = Get-ChildItem -Path $resolvedModRoot -Recurse -File -Filter "*.lua"
        $syntaxErrors = @()
        $checked = 0

        foreach ($file in $luaFiles) {
            $checked++
            $output = & $luacPath -p $file.FullName 2>&1
            if ($LASTEXITCODE -ne 0) {
                $syntaxErrors += @{
                    File = $file.FullName
                    Error = ($output | Out-String).Trim()
                }
            }
        }

        Write-Host "Checked $checked Lua files."
        if ($syntaxErrors.Count -gt 0) {
            Write-Host "Syntax failures: $($syntaxErrors.Count)" -ForegroundColor Red
            foreach ($err in $syntaxErrors | Select-Object -First 10) {
                Write-Host "- $($err.File)" -ForegroundColor Red
                if ($err.Error) {
                    Write-Host "  $($err.Error)" -ForegroundColor DarkRed
                }
            }
            if ($syntaxErrors.Count -gt 10) {
                Write-Host "... plus $($syntaxErrors.Count - 10) more syntax errors." -ForegroundColor DarkRed
            }
            $failures.Add("Lua syntax check failed.")
        }
        else {
            Write-Host "Lua syntax check passed." -ForegroundColor Green
        }
    }
}

if (-not $SkipTests) {
    if (-not $luaPath) {
        $failures.Add("lua executable not found. Install Lua or pass -LuaExe.")
    }
    elseif (-not (Test-Path $testsRunner)) {
        $failures.Add("Test runner not found: $testsRunner")
    }
    else {
        Write-Step "Step 3: Lua Tests"
        & $luaPath $testsRunner --mod-root $resolvedModRoot
        if ($LASTEXITCODE -ne 0) {
            $failures.Add("Lua tests failed.")
        }
        else {
            Write-Host "Lua tests passed." -ForegroundColor Green
        }
    }
}

if (-not $SkipTranslationAudit) {
    if (Test-Path $translationAuditScript) {
        Write-Step "Step 4: Translation Audit (Info)"
        $result = Invoke-ToolScript -ScriptPath $translationAuditScript -Arguments @("-BasePath", $resolvedModRoot)
        if ($result.ExitCode -ne 0) {
            $warnings.Add("translation_audit.ps1 returned non-zero exit code: $($result.ExitCode)")
        }

        $summary = Parse-TranslationAuditSummary -Lines $result.Output
        Write-Host ("Translation summary: missing={0}, extra={1}" -f $summary.Missing, $summary.Extra)

        if ($Strict -and $summary.Missing -gt $MaxMissingTranslations) {
            $failures.Add("Translation missing keys $($summary.Missing) exceeds strict threshold $MaxMissingTranslations.")
        }
        if ($Strict -and $summary.Extra -gt $MaxExtraTranslations) {
            $failures.Add("Translation extra keys $($summary.Extra) exceeds strict threshold $MaxExtraTranslations.")
        }
    }
    else {
        $warnings.Add("translation_audit.ps1 not found.")
    }
}

if (-not $SkipStringScan) {
    if (Test-Path $stringScanScript) {
        Write-Step "Step 5: Hardcoded String Scan (Info)"
        $result = Invoke-ToolScript -ScriptPath $stringScanScript
        if ($result.ExitCode -ne 0) {
            $warnings.Add("hardcoded_string_detector.ps1 returned non-zero exit code: $($result.ExitCode)")
        }

        $summary = Parse-StringScanSummary -Lines $result.Output
        Write-Host ("String scan summary: critical={0}, high={1}, medium={2}, discrepancies={3}" -f $summary.Critical, $summary.High, $summary.Medium, $summary.Discrepancies)

        if ($Strict) {
            if ($summary.Critical -gt $MaxCriticalStrings) {
                $failures.Add("Critical hardcoded-string issues $($summary.Critical) exceeds strict threshold $MaxCriticalStrings.")
            }
            if ($summary.High -gt $MaxHighStrings) {
                $failures.Add("High-priority hardcoded-string issues $($summary.High) exceeds strict threshold $MaxHighStrings.")
            }
            if ($summary.Discrepancies -gt $MaxStringDiscrepancies) {
                $failures.Add("42/common translation discrepancies $($summary.Discrepancies) exceeds strict threshold $MaxStringDiscrepancies.")
            }
        }
    }
    else {
        $warnings.Add("hardcoded_string_detector.ps1 not found.")
    }
}

if (-not $SkipPrintLint) {
    Write-Step "Step 6: Non-Error Print Lint"
    $violations = Get-NonErrorPrintViolations -ModRootPath $resolvedModRoot
    $count = $violations.Count
    Write-Host ("Non-error print() calls: {0}" -f $count)

    if ($count -gt 0) {
        Write-Host "Non-error print() violations (first 25):" -ForegroundColor Red
        foreach ($v in $violations | Select-Object -First 25) {
            Write-Host ("- {0}:{1} :: {2}" -f $v.Path, $v.Line, $v.Code) -ForegroundColor Red
        }
        if ($count -gt 25) {
            Write-Host ("... plus {0} more violation(s)." -f ($count - 25)) -ForegroundColor DarkRed
        }
    }

    if ($count -gt $MaxNonErrorPrints) {
        $failures.Add("Non-error print() violations $count exceeds threshold $MaxNonErrorPrints.")
    }
}

Write-Step "Preflight Summary"
if ($failures.Count -eq 0) {
    Write-Host "STATUS: PASS" -ForegroundColor Green
}
else {
    Write-Host "STATUS: FAIL" -ForegroundColor Red
}

if ($failures.Count -gt 0) {
    Write-Host "Blocking failures:" -ForegroundColor Red
    foreach ($msg in $failures) {
        Write-Host "- $msg" -ForegroundColor Red
    }
}

if ($warnings.Count -gt 0) {
    Write-Host "Warnings:" -ForegroundColor Yellow
    foreach ($msg in $warnings) {
        Write-Host "- $msg" -ForegroundColor Yellow
    }
}

if ($failures.Count -gt 0) {
    exit 1
}

exit 0
