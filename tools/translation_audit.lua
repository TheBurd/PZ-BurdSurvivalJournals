--[[
    Translation Audit Utility for BurdSurvivalJournals

    Usage: lua translation_audit.lua [base_path]

    Compares all translation files against English (EN) as the reference
    and reports missing keys for each language.

    Output: Detailed report of missing translations per language/file
]]

local lfs = require("lfs")

-- Configuration
local BASE_PATH = arg[1] or "."
local TRANSLATION_DIRS = {
    "42/media/lua/shared/Translate",
    "42.15/media/lua/shared/Translate"
}

local PREFERRED_FILE_TYPES = {"ContextMenu", "IG_UI", "ItemName", "Items", "Recipes", "Sandbox", "Tooltip", "UI"}

local function listLanguages()
    local seen = {}
    local langs = {}
    for _, transDir in ipairs(TRANSLATION_DIRS) do
        local fullDir = BASE_PATH .. "/" .. transDir
        for entry in lfs.dir(fullDir) do
            if entry ~= "." and entry ~= ".." then
                local attr = lfs.attributes(fullDir .. "/" .. entry)
                if attr and attr.mode == "directory" and entry:match("^[A-Z0-9]+$") and not seen[entry] then
                    seen[entry] = true
                    table.insert(langs, entry)
                end
            end
        end
    end
    table.sort(langs)
    return langs
end

local function listFileTypes()
    local seen = {}
    local fileTypes = {}
    for _, transDir in ipairs(TRANSLATION_DIRS) do
        local enDir = BASE_PATH .. "/" .. transDir .. "/EN"
        for entry in lfs.dir(enDir) do
            if entry ~= "." and entry ~= ".." then
                local attr = lfs.attributes(enDir .. "/" .. entry)
                if attr and attr.mode == "file" then
                    local fileType = entry:match("^(.*)%.json$")
                    if not fileType then
                        fileType = entry:match("^(.*)_EN%.txt$")
                    end
                    if fileType then
                        seen[fileType] = true
                    end
                end
            end
        end
    end

    for _, preferred in ipairs(PREFERRED_FILE_TYPES) do
        if seen[preferred] then
            table.insert(fileTypes, preferred)
            seen[preferred] = nil
        end
    end

    local extras = {}
    for fileType in pairs(seen) do
        table.insert(extras, fileType)
    end
    table.sort(extras)
    for _, fileType in ipairs(extras) do
        table.insert(fileTypes, fileType)
    end

    return fileTypes
end

local LANGUAGES = listLanguages()
local FILE_TYPES = listFileTypes()

local function resolveTranslationPath(transDir, lang, fileType)
    local jsonPath = BASE_PATH .. "/" .. transDir .. "/" .. lang .. "/" .. fileType .. ".json"
    local legacyPath = BASE_PATH .. "/" .. transDir .. "/" .. lang .. "/" .. fileType .. "_" .. lang .. ".txt"
    local jsonFile = io.open(jsonPath, "r")
    if jsonFile then
        jsonFile:close()
        return jsonPath
    end
    local legacyFile = io.open(legacyPath, "r")
    if legacyFile then
        legacyFile:close()
        return legacyPath
    end
    return jsonPath
end

-- Parse a translation file and extract all keys
local function parseTranslationFile(filepath)
    local keys = {}
    local file = io.open(filepath, "r")
    if not file then
        return nil, "Could not open file: " .. filepath
    end

    local content = file:read("*all")
    file:close()

    if filepath:match("%.json$") then
        for line in content:gmatch("[^\r\n]+") do
            local key = line:match('^%s*"((?:[^"\\]|\\.)+)"%s*:%s*"')
            if key then
                keys[key] = true
            end
        end
    else
        -- Match keys like: KeyName = "value", or KeyName = 'value',
        -- Also handles module-prefixed keys like: ItemName_Module.Key = "value"
        for key in content:gmatch('([%w_%.]+)%s*=%s*["\']') do
            -- Skip the table declaration (e.g., Sandbox_EN, UI_FR)
            if not key:match("^%w+_%u%u%u?%u?$") then
                keys[key] = true
            end
        end
    end

    return keys
end

-- Compare two key sets and return missing keys
local function findMissingKeys(referenceKeys, targetKeys)
    local missing = {}
    for key, _ in pairs(referenceKeys) do
        if not targetKeys[key] then
            table.insert(missing, key)
        end
    end
    table.sort(missing)
    return missing
end

-- Find extra keys in target that don't exist in reference
local function findExtraKeys(referenceKeys, targetKeys)
    local extra = {}
    for key, _ in pairs(targetKeys) do
        if not referenceKeys[key] then
            table.insert(extra, key)
        end
    end
    table.sort(extra)
    return extra
end

-- Count keys in a table
local function countKeys(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

-- Main audit function
local function runAudit()
    print("=" .. string.rep("=", 79))
    print("TRANSLATION AUDIT REPORT - BurdSurvivalJournals")
    print("=" .. string.rep("=", 79))
    print("")
    print("Base Path: " .. BASE_PATH)
    print("Reference Language: EN (English)")
    print("")

    local totalMissing = 0
    local totalExtra = 0
    local languageStats = {}

    for _, lang in ipairs(LANGUAGES) do
        languageStats[lang] = { missing = 0, extra = 0, files = {} }
    end

    -- Process each translation directory (42/ and 42.15/)
    for _, transDir in ipairs(TRANSLATION_DIRS) do
        local dirLabel = transDir:match("^(%w+)/") or transDir
        print("-" .. string.rep("-", 79))
        print("Directory: " .. dirLabel .. "/")
        print("-" .. string.rep("-", 79))

        -- Process each file type
        for _, fileType in ipairs(FILE_TYPES) do
            -- Get English reference file
            local enPath = resolveTranslationPath(transDir, "EN", fileType)
            local enKeys, enErr = parseTranslationFile(enPath)

            if not enKeys then
                print(string.format("  [%s] EN reference not found: %s", fileType, enErr or "unknown error"))
            else
                local enKeyCount = countKeys(enKeys)
                print(string.format("\n  [%s] EN has %d keys", fileType, enKeyCount))

                -- Compare each language against English
                for _, lang in ipairs(LANGUAGES) do
                    if lang ~= "EN" then
                        local langPath = resolveTranslationPath(transDir, lang, fileType)
                        local langKeys, langErr = parseTranslationFile(langPath)

                        if not langKeys then
                            print(string.format("    [%s] File not found", lang))
                        else
                            local langKeyCount = countKeys(langKeys)
                            local missing = findMissingKeys(enKeys, langKeys)
                            local extra = findExtraKeys(enKeys, langKeys)

                            if #missing > 0 or #extra > 0 then
                                print(string.format("    [%s] %d keys (missing: %d, extra: %d)",
                                    lang, langKeyCount, #missing, #extra))

                                if #missing > 0 then
                                    print("      MISSING:")
                                    for _, key in ipairs(missing) do
                                        print("        - " .. key)
                                    end
                                    languageStats[lang].missing = languageStats[lang].missing + #missing
                                    totalMissing = totalMissing + #missing
                                end

                                if #extra > 0 then
                                    print("      EXTRA (not in EN):")
                                    for _, key in ipairs(extra) do
                                        print("        + " .. key)
                                    end
                                    languageStats[lang].extra = languageStats[lang].extra + #extra
                                    totalExtra = totalExtra + #extra
                                end
                            else
                                print(string.format("    [%s] %d keys - OK (complete)", lang, langKeyCount))
                            end
                        end
                    end
                end
            end
        end
        print("")
    end

    -- Summary
    print("=" .. string.rep("=", 79))
    print("SUMMARY")
    print("=" .. string.rep("=", 79))
    print("")
    print(string.format("%-8s %10s %10s", "Language", "Missing", "Extra"))
    print(string.rep("-", 30))
    for _, lang in ipairs(LANGUAGES) do
        if lang ~= "EN" then
            local stats = languageStats[lang]
            local status = ""
            if stats.missing == 0 and stats.extra == 0 then
                status = " [COMPLETE]"
            end
            print(string.format("%-8s %10d %10d%s", lang, stats.missing, stats.extra, status))
        end
    end
    print(string.rep("-", 30))
    print(string.format("%-8s %10d %10d", "TOTAL", totalMissing, totalExtra))
    print("")

    if totalMissing > 0 then
        print("ACTION REQUIRED: " .. totalMissing .. " missing translation(s) need to be added.")
    else
        print("All translations are complete!")
    end

    return totalMissing, totalExtra
end

-- Run the audit
runAudit()
