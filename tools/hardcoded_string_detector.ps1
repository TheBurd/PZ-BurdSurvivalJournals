# Hardcoded English String Detector for BurdSurvivalJournals
# This tool scans Lua source files for English strings that should be using getText()
# Version 2.0 - Improved accuracy with better false-positive filtering

param(
    [string]$ModPath = "..\mods\BurdSurvivalJournals",
    [switch]$Verbose,
    [switch]$ShowFalsePositives
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$modRoot = Join-Path $scriptDir $ModPath
$helperPath = Join-Path $scriptDir "translation_helpers.ps1"
. $helperPath
$primaryVersionDir = Get-BSJPrimaryVersionDir -BasePath $modRoot

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  HARDCODED STRING DETECTOR v2.0" -ForegroundColor Cyan
Write-Host "  BurdSurvivalJournals Translation QA Tool" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan

# Known internal identifiers that are NOT user-facing (false positives to ignore)
$internalIdentifiers = @(
    '"skills"', '"traits"', '"recipes"', '"settings"',  # Tab identifiers
    '"empty"', '"empty_traits"', '"empty_skills"',      # List item keys
    '"zombie"', '"world"', '"crafted"', '"found"',      # Internal source types
    '"BurdJournals"',                                    # Module name
    'tabId', 'currentTab',                               # Variable context
    '== "skills"', '== "traits"', '== "recipes"',       # Comparisons
    '\.lua"', 'require'                                  # File/module references
)

# Patterns that indicate REAL hardcoded English strings needing translation
$suspiciousPatterns = @(
    # User-facing text patterns
    @{
        Pattern = 'text\s*=\s*"[A-Z][a-zA-Z\s]+'
        Description = "UI text property with English sentence"
        Severity = "HIGH"
        MustContain = @('text =', 'text=')
        MustNotContain = @('getText', '== "')
    },
    @{
        Pattern = 'return\s+"[A-Z][a-z]+\s+[A-Za-z]+'
        Description = "Return statement with English phrase"
        Severity = "HIGH"
        MustContain = @('return "')
        MustNotContain = @('getText')
    },
    @{
        Pattern = '"(Today|Yesterday|\d+\s+day[s]?\s+ago)"'
        Description = "Hardcoded date/time text"
        Severity = "CRITICAL"
        MustNotContain = @('getText')
    },
    @{
        Pattern = '"(Owner|Author|Skills|Traits|Recipes|Condition|Origin|Created):\s'
        Description = "Hardcoded label text (Label: value pattern)"
        Severity = "CRITICAL"
        MustNotContain = @('getText')
    },
    @{
        Pattern = '"\s*\(all claimed\)"'
        Description = "Hardcoded 'all claimed' status text"
        Severity = "CRITICAL"
        MustNotContain = @('getText')
    },
    @{
        Pattern = '"\s*\(You\)"'
        Description = "Hardcoded ownership indicator"
        Severity = "HIGH"
        MustNotContain = @('getText')
    },
    @{
        Pattern = '"No\s+(rare\s+)?traits\s+(recorded|found)"'
        Description = "Hardcoded empty state message"
        Severity = "HIGH"
        MustNotContain = @('getText')
    },
    @{
        Pattern = '"(Recipe|Skill|Trait|Stat)\s+recording\s+is\s+disabled"'
        Description = "Hardcoded disabled feature message"
        Severity = "HIGH"
        MustNotContain = @('getText')
    },
    @{
        Pattern = '"No\s+stats\s+enabled"'
        Description = "Hardcoded empty state message"
        Severity = "HIGH"
        MustNotContain = @('getText')
    },
    @{
        Pattern = '"Unknown\s+Trait"'
        Description = "Hardcoded fallback text"
        Severity = "MEDIUM"
        MustNotContain = @('getText')
    },
    @{
        Pattern = '"Recipe\s+knowledge'
        Description = "Hardcoded recipe bonus text"
        Severity = "HIGH"
        MustNotContain = @('getText')
    },
    @{
        Pattern = '"Absorb\s+all'
        Description = "Hardcoded confirmation dialog text"
        Severity = "HIGH"
        MustNotContain = @('getText')
    },
    @{
        Pattern = '"Other"'
        Description = "Hardcoded 'Other' category text"
        Severity = "MEDIUM"
        MustNotContain = @('getText')
        Context = "return"  # Only flag if it's a return statement
    }
)

# Get all Lua files in client directories
$luaFiles = @()
$clientDirs = @()
if ($primaryVersionDir) {
    $clientDirs += (Join-Path $primaryVersionDir.FullName "media\lua\client")
}
$clientDirs += (Join-Path $modRoot "common\media\lua\client")

foreach ($dir in $clientDirs) {
    if (Test-Path $dir) {
        $files = Get-ChildItem -Path $dir -Filter "*.lua" -Recurse
        $luaFiles += $files
    }
}

Write-Host "Scanning $($luaFiles.Count) Lua files for hardcoded English strings...`n" -ForegroundColor Yellow

$allIssues = @()
$falsePositives = @()

foreach ($file in $luaFiles) {
    $relativePath = $file.FullName.Replace($modRoot, "").TrimStart('\')
    $lines = Get-Content $file.FullName

    for ($lineNum = 0; $lineNum -lt $lines.Count; $lineNum++) {
        $line = $lines[$lineNum]
        $lineNumber = $lineNum + 1

        # Skip comments
        if ($line -match '^\s*--') { continue }

        # Skip lines that already use getText properly
        if ($line -match 'getText\s*\([^)]+\)\s*or\s*"') { continue }

        # Check each suspicious pattern
        foreach ($patternInfo in $suspiciousPatterns) {
            if ($line -match $patternInfo.Pattern) {
                $isValid = $true

                # Check MustContain requirements
                if ($patternInfo.MustContain) {
                    $containsRequired = $false
                    foreach ($req in $patternInfo.MustContain) {
                        if ($line -match [regex]::Escape($req)) {
                            $containsRequired = $true
                            break
                        }
                    }
                    if (-not $containsRequired) { $isValid = $false }
                }

                # Check MustNotContain requirements
                if ($patternInfo.MustNotContain -and $isValid) {
                    foreach ($forbidden in $patternInfo.MustNotContain) {
                        if ($line -match $forbidden) {
                            $isValid = $false
                            break
                        }
                    }
                }

                # Check Context requirements
                if ($patternInfo.Context -and $isValid) {
                    if ($line -notmatch $patternInfo.Context) {
                        $isValid = $false
                    }
                }

                # Check against internal identifiers (false positives)
                if ($isValid) {
                    foreach ($internal in $internalIdentifiers) {
                        if ($line -match [regex]::Escape($internal)) {
                            $falsePositives += @{
                                File = $relativePath
                                Line = $lineNumber
                                Content = $line.Trim()
                                Reason = "Internal identifier: $internal"
                            }
                            $isValid = $false
                            break
                        }
                    }
                }

                if ($isValid) {
                    $allIssues += @{
                        File = $relativePath
                        Line = $lineNumber
                        Content = $line.Trim()
                        Pattern = $patternInfo.Description
                        Severity = $patternInfo.Severity
                    }
                }
            }
        }
    }
}

# Compare 42/ vs common/ for getText() discrepancies
Write-Host "Comparing 42/ and common/ directories for translation coverage...`n" -ForegroundColor Yellow

$discrepancies = @()
$dir42 = if ($primaryVersionDir) { Join-Path $primaryVersionDir.FullName "media\lua\client" } else { $null }
$dirCommon = Join-Path $modRoot "common\media\lua\client"

if ($dir42 -and (Test-Path $dir42) -and (Test-Path $dirCommon)) {
    $files42 = Get-ChildItem -Path $dir42 -Filter "*.lua" -Recurse

    foreach ($file42 in $files42) {
        $relativeName = $file42.FullName.Replace($dir42, "").TrimStart('\')
        $commonFile = Join-Path $dirCommon $relativeName

        if (Test-Path $commonFile) {
            $content42 = Get-Content $file42.FullName -Raw
            $contentCommon = Get-Content $commonFile -Raw

            # Count getText() calls
            $getText42 = ([regex]::Matches($content42, 'getText\s*\(')).Count
            $getTextCommon = ([regex]::Matches($contentCommon, 'getText\s*\(')).Count

            if ($getText42 -ne $getTextCommon) {
                $discrepancies += @{
                    File = $relativeName
                    GetText42 = $getText42
                    GetTextCommon = $getTextCommon
                    Difference = $getText42 - $getTextCommon
                }
            }
        }
    }
}

# Output results
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SCAN RESULTS" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan

# Group by severity
$criticalIssues = $allIssues | Where-Object { $_.Severity -eq "CRITICAL" }
$highIssues = $allIssues | Where-Object { $_.Severity -eq "HIGH" }
$mediumIssues = $allIssues | Where-Object { $_.Severity -eq "MEDIUM" }

# Deduplicate (same line might match multiple patterns)
$uniqueIssues = @{}
foreach ($issue in $allIssues) {
    $key = "$($issue.File):$($issue.Line)"
    if (-not $uniqueIssues.ContainsKey($key)) {
        $uniqueIssues[$key] = $issue
    }
    elseif ($issue.Severity -eq "CRITICAL") {
        $uniqueIssues[$key] = $issue  # Prefer higher severity
    }
}

$allIssues = $uniqueIssues.Values | Sort-Object {
    switch ($_.Severity) { "CRITICAL" { 0 } "HIGH" { 1 } "MEDIUM" { 2 } default { 3 } }
}, File, Line

# Recalculate after dedup
$criticalIssues = $allIssues | Where-Object { $_.Severity -eq "CRITICAL" }
$highIssues = $allIssues | Where-Object { $_.Severity -eq "HIGH" }
$mediumIssues = $allIssues | Where-Object { $_.Severity -eq "MEDIUM" }

if ($allIssues.Count -eq 0 -and $discrepancies.Count -eq 0) {
    Write-Host "No hardcoded English strings detected!" -ForegroundColor Green
    Write-Host "All UI text appears to be using getText() for translation.`n" -ForegroundColor Green
}
else {
    if ($criticalIssues.Count -gt 0) {
        Write-Host "CRITICAL ISSUES ($($criticalIssues.Count)):" -ForegroundColor Red
        Write-Host "These strings are definitely user-facing and MUST use getText():`n" -ForegroundColor Red
        foreach ($issue in $criticalIssues) {
            Write-Host "  File: $($issue.File)" -ForegroundColor White
            Write-Host "  Line: $($issue.Line)" -ForegroundColor Gray
            Write-Host "  Code: $($issue.Content)" -ForegroundColor Yellow
            Write-Host "  Issue: $($issue.Pattern)`n" -ForegroundColor Magenta
        }
    }

    if ($highIssues.Count -gt 0) {
        Write-Host "HIGH PRIORITY ($($highIssues.Count)):" -ForegroundColor Yellow
        Write-Host "These strings are likely user-facing and should use getText():`n" -ForegroundColor Yellow
        foreach ($issue in $highIssues) {
            Write-Host "  File: $($issue.File)" -ForegroundColor White
            Write-Host "  Line: $($issue.Line)" -ForegroundColor Gray
            Write-Host "  Code: $($issue.Content)" -ForegroundColor Yellow
            Write-Host "  Issue: $($issue.Pattern)`n" -ForegroundColor Magenta
        }
    }

    if ($mediumIssues.Count -gt 0 -and $Verbose) {
        Write-Host "MEDIUM PRIORITY ($($mediumIssues.Count)):" -ForegroundColor DarkYellow
        Write-Host "These might be hardcoded strings (manual review recommended):`n" -ForegroundColor DarkYellow
        foreach ($issue in $mediumIssues) {
            Write-Host "  File: $($issue.File)" -ForegroundColor White
            Write-Host "  Line: $($issue.Line)" -ForegroundColor Gray
            Write-Host "  Code: $($issue.Content)" -ForegroundColor Yellow
            Write-Host "  Issue: $($issue.Pattern)`n" -ForegroundColor Magenta
        }
    }
    elseif ($mediumIssues.Count -gt 0) {
        Write-Host "MEDIUM PRIORITY: $($mediumIssues.Count) potential issues (use -Verbose to see)`n" -ForegroundColor DarkYellow
    }

    if ($discrepancies.Count -gt 0) {
        Write-Host "============================================" -ForegroundColor Cyan
        Write-Host "  VERSION/ vs COMMON/ DISCREPANCIES" -ForegroundColor Cyan
        Write-Host "============================================`n" -ForegroundColor Cyan
        Write-Host "Files where the active version folder has more getText() calls than common/:" -ForegroundColor Yellow
        Write-Host "(This indicates common/ may be missing translation support)`n" -ForegroundColor Yellow

        foreach ($disc in ($discrepancies | Where-Object { $_.Difference -gt 0 } | Sort-Object Difference -Descending)) {
            Write-Host "  File: $($disc.File)" -ForegroundColor White
            Write-Host "    version: $($disc.GetText42) getText() calls" -ForegroundColor Cyan
            Write-Host "    common/: $($disc.GetTextCommon) getText() calls" -ForegroundColor Cyan
            Write-Host "    MISSING: $($disc.Difference) translation(s) in common/`n" -ForegroundColor Red
        }
    }
}

if ($ShowFalsePositives -and $falsePositives.Count -gt 0) {
    Write-Host "`n============================================" -ForegroundColor Gray
    Write-Host "  FILTERED FALSE POSITIVES ($($falsePositives.Count))" -ForegroundColor Gray
    Write-Host "============================================`n" -ForegroundColor Gray
    foreach ($fp in $falsePositives | Select-Object -First 20) {
        Write-Host "  $($fp.File):$($fp.Line) - $($fp.Reason)" -ForegroundColor DarkGray
    }
    if ($falsePositives.Count -gt 20) {
        Write-Host "  ... and $($falsePositives.Count - 20) more`n" -ForegroundColor DarkGray
    }
}

# Summary
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  SUMMARY" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Files scanned:        $($luaFiles.Count)" -ForegroundColor White
Write-Host "Critical issues:      $($criticalIssues.Count)" -ForegroundColor $(if ($criticalIssues.Count -gt 0) { "Red" } else { "Green" })
Write-Host "High priority:        $($highIssues.Count)" -ForegroundColor $(if ($highIssues.Count -gt 0) { "Yellow" } else { "Green" })
Write-Host "Medium priority:      $($mediumIssues.Count)" -ForegroundColor $(if ($mediumIssues.Count -gt 0) { "DarkYellow" } else { "Green" })
Write-Host "File discrepancies:   $($discrepancies.Count)" -ForegroundColor $(if ($discrepancies.Count -gt 0) { "Yellow" } else { "Green" })
Write-Host ""

if ($allIssues.Count -gt 0 -or ($discrepancies | Where-Object { $_.Difference -gt 0 }).Count -gt 0) {
    Write-Host "ACTION REQUIRED:" -ForegroundColor Red
    Write-Host "1. Fix hardcoded strings: Replace with getText(`"Key`") or `"Fallback`"" -ForegroundColor Yellow
    Write-Host "2. Fix discrepancies: Copy getText() patterns from the active version folder to common/" -ForegroundColor Yellow
    Write-Host "3. Add missing keys to all translation files" -ForegroundColor Yellow
}
else {
    Write-Host "All translations appear to be properly exposed!" -ForegroundColor Green
}

