-- CRITICAL: Capture Lua builtins at module load time BEFORE any other mod can overwrite them
-- Some mods overwrite global functions, causing "Object tried to call nil" errors
-- We use rawget to access the original builtins from _G to avoid any metatable shenanigans
local _G = _G or getfenv(0)
local _safePcall = rawget(_G, "pcall") or pcall
local _safeNext = rawget(_G, "next") or next
local _safePairs = rawget(_G, "pairs") or pairs
local _safeType = rawget(_G, "type") or type
local _safeTostring = rawget(_G, "tostring") or tostring
local _safeIpairs = rawget(_G, "ipairs") or ipairs

-- Verify captures worked (fallback to direct reference if rawget failed)
if not _safePcall then _safePcall = pcall end
if not _safeNext then _safeNext = next end
if not _safePairs then _safePairs = pairs end
if not _safeType then _safeType = type end

-- Safe wrapper that handles pcall being nil (returns false, nil if pcall unavailable)
local function safePcall(func, ...)
    if _safePcall then
        return _safePcall(func, ...)
    end
    -- Last resort: direct call (may throw)
    return true, func(...)
end

BurdJournals = BurdJournals or {}

BurdJournals.VERSION = "2.4.6"
BurdJournals.MOD_ID = "BurdSurvivalJournals"

-- Expose safePcall for use throughout the mod
BurdJournals.safePcall = safePcall

-- Sanitization version - increment to force re-sanitization of all journals
BurdJournals.SANITIZE_VERSION = 1

-- Check if an item reference is still valid (not a zombie/invalid Java object)
-- This check uses instanceof which does NOT trigger error logging for zombie objects
function BurdJournals.isValidItem(item)
    if not item then return false end
    -- instanceof returns false for zombie/invalid Java objects without triggering errors
    if instanceof and not instanceof(item, "InventoryItem") then
        return false
    end
    return true
end

BurdJournals.Limits = {

    CHUNK_SKILLS = 10,
    CHUNK_TRAITS = 10,
    CHUNK_RECIPES = 20,
    CHUNK_STATS = 10,

    CHUNK_DELAY_MS = 50,

}

BurdJournals.ModCompat = BurdJournals.ModCompat or {
    registeredRecipes = {},
    excludedRecipes = {},
    registeredMagazines = {},
    registeredTraits = {},
    excludedTraits = {},
}

function BurdJournals.registerRecipe(recipeName, magazineType)
    if not recipeName then return false end
    BurdJournals.ModCompat.registeredRecipes[recipeName] = magazineType or "CustomRecipe"

    BurdJournals._magazineRecipeCache = nil
    BurdJournals._magazineToRecipesCache = nil
    BurdJournals.debugPrint("[BurdJournals] Registered recipe: " .. recipeName .. (magazineType and (" from " .. magazineType) or ""))
    return true
end

function BurdJournals.excludeRecipe(recipeName)
    if not recipeName then return false end
    BurdJournals.ModCompat.excludedRecipes[recipeName] = true

    BurdJournals._magazineRecipeCache = nil
    BurdJournals._magazineToRecipesCache = nil
    BurdJournals.debugPrint("[BurdJournals] Excluded recipe: " .. recipeName)
    return true
end

function BurdJournals.registerMagazine(magazineType, recipes)
    if not magazineType or not recipes then return false end
    BurdJournals.ModCompat.registeredMagazines[magazineType] = recipes

    for _, recipeName in ipairs(recipes) do
        BurdJournals.ModCompat.registeredRecipes[recipeName] = magazineType
    end

    BurdJournals._magazineRecipeCache = nil
    BurdJournals._magazineToRecipesCache = nil
    BurdJournals.debugPrint("[BurdJournals] Registered magazine: " .. magazineType .. " with " .. #recipes .. " recipes")
    return true
end

function BurdJournals.registerTrait(traitId)
    if not traitId then return false end
    BurdJournals.ModCompat.registeredTraits[string.lower(traitId)] = true

    BurdJournals._cachedGrantableTraits = nil
    BurdJournals._cachedAllTraits = nil
    BurdJournals.debugPrint("[BurdJournals] Registered trait: " .. traitId)
    return true
end

function BurdJournals.excludeTrait(traitId)
    if not traitId then return false end
    BurdJournals.ModCompat.excludedTraits[string.lower(traitId)] = true

    table.insert(BurdJournals.EXCLUDED_TRAITS, string.lower(traitId))

    BurdJournals._cachedGrantableTraits = nil
    BurdJournals._cachedAllTraits = nil
    BurdJournals.debugPrint("[BurdJournals] Excluded trait: " .. traitId)
    return true
end

function BurdJournals.isRecipeExcluded(recipeName)
    if not recipeName then return false end
    return BurdJournals.ModCompat.excludedRecipes[recipeName] == true
end

function BurdJournals.isTraitExcludedByMod(traitId)
    if not traitId then return false end
    return BurdJournals.ModCompat.excludedTraits[string.lower(traitId)] == true
end

function BurdJournals.getModRegisteredRecipes()
    return BurdJournals.ModCompat.registeredRecipes
end

function BurdJournals.getModRegisteredMagazines()
    return BurdJournals.ModCompat.registeredMagazines
end

function BurdJournals.getModRegisteredTraits()
    return BurdJournals.ModCompat.registeredTraits
end

function BurdJournals.generateUUID()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    local uuid = string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and ZombRand(0, 16) or ZombRand(8, 12)
        return string.format("%x", v)
    end)
    return uuid
end

function BurdJournals.findJournalByUUID(player, uuid)
    if not player or not uuid then return nil end

    local inventory = player:getInventory()
    if inventory then
        local found = BurdJournals.findJournalByUUIDInContainer(inventory, uuid)
        if found then return found end
    end

    if getPlayerLoot and not isServer() then
        local playerNum = player:getPlayerNum()
        if playerNum then
            local lootInventory = getPlayerLoot(playerNum)
            if lootInventory and lootInventory.inventoryPane then
                local inventoryPane = lootInventory.inventoryPane
                if inventoryPane.inventories then
                    for i = 1, #inventoryPane.inventories do
                        local containerInfo = inventoryPane.inventories[i]
                        if containerInfo and containerInfo.inventory then
                            local found = BurdJournals.findJournalByUUIDInContainer(containerInfo.inventory, uuid)
                            if found then return found end
                        end
                    end
                end
            end
        end
    end

    local square = player:getCurrentSquare()
    if square then
        for dx = -1, 1 do
            for dy = -1, 1 do
                local nearSquare = getCell():getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ())
                if nearSquare then
                    local objects = nearSquare:getObjects()
                    if objects then
                        for i = 0, objects:size() - 1 do
                            local obj = objects:get(i)
                            if obj and obj.getContainer then
                                local container = obj:getContainer()
                                if container then
                                    local found = BurdJournals.findJournalByUUIDInContainer(container, uuid)
                                    if found then return found end
                                end
                            end
                            if obj and obj.getInventory then
                                local container = obj:getInventory()
                                if container then
                                    local found = BurdJournals.findJournalByUUIDInContainer(container, uuid)
                                    if found then return found end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return nil
end

function BurdJournals.findJournalByUUIDInContainer(container, uuid)
    if not container then return nil end

    local items = container:getItems()
    if not items then return nil end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            local fullType = item:getFullType()

            if fullType and fullType:find("^BurdJournals%.") then
                local modData = item:getModData()
                if modData and modData.BurdJournals and modData.BurdJournals.uuid == uuid then
                    return item
                end
            end

            if item.getInventory then
                local itemInventory = item:getInventory()
                if itemInventory then
                    local found = BurdJournals.findJournalByUUIDInContainer(itemInventory, uuid)
                    if found then return found end
                end
            end
        end
    end
    return nil
end

BurdJournals.SKILL_CATEGORIES = {
    Passive = {
        "Fitness",
        "Strength"
    },
    Firearm = {
        "Aiming",
        "Reloading"
    },
    Melee = {
        "Axe",
        "Blunt",
        "SmallBlunt",
        "LongBlade",
        "SmallBlade",
        "Spear",
        "Maintenance"
    },
    Crafting = {
        "Carpentry",
        "Cooking",
        "Electricity",
        "MetalWelding",
        "Mechanics",
        "Tailoring",
        "Blacksmith",
        "Glassmaking",
        "Pottery",
        "Masonry",
        "Carving",
        "FlintKnapping"
    },
    Farming = {
        "Farming",
        "Husbandry",
        "Butchering"
    },
    Survival = {
        "Fishing",
        "Trapping",
        "Foraging",
        "Tracking",
        "Doctor"
    },
    Agility = {
        "Sprinting",
        "Lightfoot",
        "Nimble",
        "Sneak"
    }
}

BurdJournals.SKILL_TO_PERK = {
    Foraging = "PlantScavenging",
    Carpentry = "Woodwork"
}

BurdJournals.ALL_SKILLS = {}
for category, skills in pairs(BurdJournals.SKILL_CATEGORIES) do
    for _, skill in ipairs(skills) do
        table.insert(BurdJournals.ALL_SKILLS, skill)
    end
end

BurdJournals._cachedDiscoveredSkills = nil

-- NOTE: Category/parent perks are now filtered using isTrainableSkill() which checks
-- perk:getParent():getId() ~= "None". This is more reliable than name-based exclusion.
-- The list below is kept for any edge cases or explicit exclusions.
BurdJournals.EXCLUDED_SKILLS = {
    -- System perks that should never appear
    "None",
    "MAX",
}

-- Helper: Check if a perk is an actual trainable skill (not a category/parent perk)
-- Parent perks have getParent():getId() == "None", trainable skills have a real parent
function BurdJournals.isTrainableSkill(perk)
    if not perk then return false end

    local isTrainable = false
    safePcall(function()
        local parent = perk:getParent()
        if parent then
            local parentId = parent:getId()
            -- If parent ID is "None", this IS a category perk, not trainable
            isTrainable = parentId ~= "None"
        end
    end)
    return isTrainable
end

function BurdJournals.discoverAllSkills(forceRefresh)

    if not forceRefresh and BurdJournals._cachedDiscoveredSkills then
        return BurdJournals._cachedDiscoveredSkills
    end

    local discoveredSkills = {}
    local addedSkillSet = {}  -- Track what we've already added (lowercase for comparison)

    -- Build set of vanilla skill names (from our hardcoded list) for vanilla vs mod detection
    local vanillaSkillSet = {}
    for _, skill in ipairs(BurdJournals.ALL_SKILLS) do
        vanillaSkillSet[string.lower(skill)] = true
    end
    -- Also include perk ID mappings (e.g., PlantScavenging for Foraging)
    if BurdJournals.SKILL_TO_PERK then
        for skillName, perkId in pairs(BurdJournals.SKILL_TO_PERK) do
            vanillaSkillSet[string.lower(perkId)] = true
        end
    end

    -- First add vanilla skills from our known list
    for _, skill in ipairs(BurdJournals.ALL_SKILLS) do
        table.insert(discoveredSkills, skill)
        addedSkillSet[string.lower(skill)] = true
    end

    -- Now discover mod-added skills from PerkFactory
    -- IMPORTANT: Use getParent():getId() to filter out category perks
    local modSkillsFound = 0
    if PerkFactory and PerkFactory.PerkList then
        local perkList = PerkFactory.PerkList
        if perkList and perkList.size then
            for i = 0, perkList:size() - 1 do
                local perk = perkList:get(i)
                if perk then
                    -- CRITICAL: Only process if this is a TRAINABLE skill, not a category
                    if BurdJournals.isTrainableSkill(perk) then
                        local perkName = nil

                        safePcall(function()
                            if perk.getId then
                                perkName = tostring(perk:getId())
                            elseif perk.name then
                                perkName = tostring(perk.name())
                            else
                                perkName = tostring(perk)
                                perkName = perkName:gsub("^zombie%.characters%.skills%.PerkFactory%$Perk%.", "")
                                perkName = perkName:gsub("^Perks%.", "")
                            end
                        end)

                        if perkName and perkName ~= "" then
                            local perkNameLower = string.lower(perkName)

                            -- Only add if not already in our list (avoid duplicates)
                            if not addedSkillSet[perkNameLower] then
                                table.insert(discoveredSkills, perkName)
                                addedSkillSet[perkNameLower] = true

                                -- Only count as "mod skill" if not in vanilla set
                                if not vanillaSkillSet[perkNameLower] then
                                    modSkillsFound = modSkillsFound + 1
                                    BurdJournals.debugPrint("[BurdJournals] Found mod skill: " .. perkName)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if modSkillsFound > 0 then
        BurdJournals.debugPrint("[BurdJournals] Discovered " .. modSkillsFound .. " mod-added skills (total: " .. #discoveredSkills .. ")")
    end

    BurdJournals._cachedDiscoveredSkills = discoveredSkills
    return discoveredSkills
end

function BurdJournals.refreshSkillCache()
    BurdJournals._cachedDiscoveredSkills = nil
    BurdJournals.debugPrint("[BurdJournals] Skill cache cleared - will rediscover on next access")
end

BurdJournals.GRANTABLE_TRAITS = {

    "brave",
    "resilient",
    "thickskinned",
    "fasthealer",
    "adrenalinejunkie",

    "graceful",
    "inconspicuous",
    "nightvision",

    "keenhearing",
    "eagleeyed",

    "fastlearner",
    "fastreader",
    "inventive",
    "crafty",

    "lighteater",
    "lowthirst",
    "needslesssleep",
    "irongut",

    "organized",
    "dextrous",

    "outdoorsman",
    "nutritionist",

    "speeddemon",

    "baseballplayer",
    "jogger",
    "gymnast",
    "firstaid",
    "gardener",
    "herbalist",
    "fishing",
    "tailor",
    "mechanics",
    "cook",

    "hiker",
    "hunter",
    "brawler",
    "formerscout",
    "handy",
    "artisan",
    "blacksmith",
    "mason",
    "whittler",
    "wildernessknowledge",

}

BurdJournals.EXCLUDED_TRAITS = {

    "athletic", "strong", "stout", "fit", "feeble", "unfit", "outofshape", "veryheavy", "weak",

    "asthmatic", "deaf", "hardofhearing", "shortsighted", "eagleeyed",

    "illiterate",
}

BurdJournals._cachedGrantableTraits = nil
BurdJournals._cachedAllTraits = nil

BurdJournals._traitDisplayNameCache = {}

function BurdJournals.getTraitDisplayName(traitId)
    if not traitId then return "Unknown Trait" end

    if BurdJournals._traitDisplayNameCache[traitId] then
        return BurdJournals._traitDisplayNameCache[traitId]
    end

    local displayName = nil

    if CharacterTraitDefinition and CharacterTraitDefinition.getTraits then
        safePcall(function()
            local allTraits = CharacterTraitDefinition.getTraits()
            if allTraits then
                for i = 0, allTraits:size() - 1 do
                    local def = allTraits:get(i)
                    if def then
                        local thisTraitId = nil
                        safePcall(function()
                            local traitType = def:getType()
                            if traitType and traitType.getName then
                                thisTraitId = traitType:getName()
                            elseif traitType then
                                thisTraitId = tostring(traitType)
                                thisTraitId = string.gsub(thisTraitId, "^base:", "")
                            end
                        end)

                        if thisTraitId and string.lower(thisTraitId) == string.lower(traitId) then
                            if def.getLabel then
                                displayName = def:getLabel()
                            end
                            break
                        end
                    end
                end
            end
        end)
    end

    if not displayName and TraitFactory and TraitFactory.getTrait then
        safePcall(function()
            local trait = TraitFactory.getTrait(traitId)
            if trait and trait.getLabel then
                displayName = trait:getLabel()
            end
        end)
    end

    if not displayName then
        displayName = traitId:gsub("(%l)(%u)", "%1 %2")
    end

    BurdJournals._traitDisplayNameCache[traitId] = displayName

    return displayName
end

function BurdJournals.discoverGrantableTraits(includeNegative, forceRefresh)

    if includeNegative == nil then
        includeNegative = BurdJournals.getSandboxOption("AllowNegativeTraits") or false
    end

    local cacheKey = includeNegative and "_cachedAllTraits" or "_cachedGrantableTraits"
    if not forceRefresh and BurdJournals[cacheKey] then
        return BurdJournals[cacheKey]
    end

    local discoveredTraits = {}
    local excludedSet = {}

    for _, traitId in ipairs(BurdJournals.EXCLUDED_TRAITS) do
        excludedSet[string.lower(traitId)] = true
    end

    if CharacterTraitDefinition and CharacterTraitDefinition.getTraits then
        local allTraits = CharacterTraitDefinition.getTraits()
        if allTraits then
            for i = 0, allTraits:size() - 1 do
                local def = allTraits:get(i)
                if def then
                    local traitId = nil
                    local cost = 0
                    local isPositive = true

                    safePcall(function()
                        local traitType = def:getType()
                        if traitType and traitType.getName then
                            traitId = traitType:getName()
                        elseif traitType then
                            traitId = tostring(traitType)

                            traitId = string.gsub(traitId, "^base:", "")
                        end
                    end)

                    safePcall(function()
                        cost = def:getCost() or 0
                    end)

                    isPositive = cost > 0

                    if traitId then
                        local traitIdLower = string.lower(traitId)

                        if excludedSet[traitIdLower] then

                        elseif cost == 0 then

                        elseif isPositive then
                            table.insert(discoveredTraits, traitId)

                        elseif includeNegative and not isPositive then
                            table.insert(discoveredTraits, traitId)
                        end
                    end
                end
            end
        end
    end

    local modTraits = BurdJournals.getModRegisteredTraits()
    local addedModTraits = 0
    for traitId, _ in pairs(modTraits) do

        local alreadyExists = false
        for _, existing in ipairs(discoveredTraits) do
            if string.lower(existing) == string.lower(traitId) then
                alreadyExists = true
                break
            end
        end
        if not alreadyExists and not excludedSet[string.lower(traitId)] then
            table.insert(discoveredTraits, traitId)
            addedModTraits = addedModTraits + 1
        end
    end

    if #discoveredTraits > 0 then
        BurdJournals.debugPrint("[BurdJournals] Discovered " .. #discoveredTraits .. " grantable traits dynamically (includeNegative=" .. tostring(includeNegative) .. ", modAdded=" .. addedModTraits .. ")")
        BurdJournals[cacheKey] = discoveredTraits
        return discoveredTraits
    else
        BurdJournals.debugPrint("[BurdJournals] Using fallback hardcoded trait list (" .. #BurdJournals.GRANTABLE_TRAITS .. " traits)")
        return BurdJournals.GRANTABLE_TRAITS
    end
end

function BurdJournals.getGrantableTraits(includeNegative)
    return BurdJournals.discoverGrantableTraits(includeNegative, false)
end

function BurdJournals.isTraitGrantable(traitId, grantableList)
    if not traitId then return false end
    if not grantableList then
        grantableList = BurdJournals.getGrantableTraits()
    end

    local traitIdLower = string.lower(traitId)

    for _, grantable in ipairs(grantableList) do
        local grantableLower = string.lower(grantable)
        if traitIdLower == grantableLower then
            return true
        end
    end

    local baseTraitId = traitId:gsub("2$", "")
    if baseTraitId ~= traitId then
        local baseTraitIdLower = string.lower(baseTraitId)
        for _, grantable in ipairs(grantableList) do
            local grantableLower = string.lower(grantable)
            if baseTraitIdLower == grantableLower then
                return true
            end
        end
    end

    return false
end

function BurdJournals.refreshTraitCache()
    BurdJournals._cachedGrantableTraits = nil
    BurdJournals._cachedAllTraits = nil
    BurdJournals.debugPrint("[BurdJournals] Trait cache cleared - will rediscover on next access")
end

function BurdJournals.debugDumpTraits()
    if not BurdJournals.isDebug() then
        print("[BurdJournals] debugDumpTraits requires -debug mode")
        return
    end

    print("==================== BURD JOURNALS: TRAIT DISCOVERY DEBUG ====================")

    if not CharacterTraitDefinition or not CharacterTraitDefinition.getTraits then
        print("[BurdJournals] ERROR: CharacterTraitDefinition API not available!")
        return
    end

    local allTraits = CharacterTraitDefinition.getTraits()
    if not allTraits then
        print("[BurdJournals] ERROR: getTraits() returned nil!")
        return
    end

    local totalCount = allTraits:size()
    print("[BurdJournals] Total traits found in game: " .. totalCount)
    print("")

    local positiveTraits = {}
    local negativeTraits = {}
    local professionTraits = {}
    local excludedTraits = {}
    local unknownTraits = {}

    local excludedSet = {}
    for _, traitId in ipairs(BurdJournals.EXCLUDED_TRAITS) do
        excludedSet[string.lower(traitId)] = true
    end

    for i = 0, totalCount - 1 do
        local def = allTraits:get(i)
        if def then
            local traitId = nil
            local traitLabel = "?"
            local cost = 0
            local modSource = "vanilla"

            safePcall(function()
                local traitType = def:getType()
                if traitType and traitType.getName then
                    traitId = traitType:getName()
                elseif traitType then
                    traitId = tostring(traitType)
                    traitId = string.gsub(traitId, "^base:", "")
                end
            end)

            safePcall(function()
                traitLabel = def:getLabel() or traitId or "?"
            end)

            safePcall(function()
                cost = def:getCost() or 0
            end)

            if traitId then
                if string.find(traitId, "SOTO") or string.find(traitId, "soto") then
                    modSource = "SOTO"
                elseif string.find(traitId, "MT_") or string.find(traitId, "MoreTraits") then
                    modSource = "More Traits"
                elseif string.find(traitId, "_") and not string.find(traitId, "^[a-z]+$") then
                    modSource = "modded?"
                end
            end

            local entry = {
                id = traitId or "nil",
                label = traitLabel,
                cost = cost,
                source = modSource
            }

            if traitId then
                local traitIdLower = string.lower(traitId)
                if excludedSet[traitIdLower] then
                    table.insert(excludedTraits, entry)
                elseif cost == 0 then
                    table.insert(professionTraits, entry)
                elseif cost > 0 then
                    table.insert(positiveTraits, entry)
                else
                    table.insert(negativeTraits, entry)
                end
            else
                table.insert(unknownTraits, entry)
            end
        end
    end

    print("=== POSITIVE TRAITS (grantable, cost > 0): " .. #positiveTraits .. " ===")
    for _, t in ipairs(positiveTraits) do
        print("  [+] " .. t.id .. " (" .. t.label .. ") cost=" .. t.cost .. " [" .. t.source .. "]")
    end
    print("")

    print("=== NEGATIVE TRAITS (cost < 0): " .. #negativeTraits .. " ===")
    for _, t in ipairs(negativeTraits) do
        print("  [-] " .. t.id .. " (" .. t.label .. ") cost=" .. t.cost .. " [" .. t.source .. "]")
    end
    print("")

    print("=== PROFESSION-ONLY TRAITS (cost = 0): " .. #professionTraits .. " ===")
    for _, t in ipairs(professionTraits) do
        print("  [0] " .. t.id .. " (" .. t.label .. ") [" .. t.source .. "]")
    end
    print("")

    print("=== EXCLUDED TRAITS (physical/body): " .. #excludedTraits .. " ===")
    for _, t in ipairs(excludedTraits) do
        print("  [X] " .. t.id .. " (" .. t.label .. ") cost=" .. t.cost .. " [" .. t.source .. "]")
    end
    print("")

    if #unknownTraits > 0 then
        print("=== UNKNOWN/ERROR TRAITS: " .. #unknownTraits .. " ===")
        for _, t in ipairs(unknownTraits) do
            print("  [?] " .. t.id .. " (" .. t.label .. ")")
        end
        print("")
    end

    print("=== SUMMARY ===")
    print("  Positive (grantable): " .. #positiveTraits)
    print("  Negative (with AllowNegativeTraits): " .. #negativeTraits)
    print("  Profession-only (excluded): " .. #professionTraits)
    print("  Physical/excluded: " .. #excludedTraits)
    print("  Total discoverable: " .. (#positiveTraits + #negativeTraits))
    print("")

    local allowNeg = BurdJournals.getSandboxOption("AllowNegativeTraits") or false
    print("  Sandbox 'AllowNegativeTraits': " .. tostring(allowNeg))
    print("  Current getGrantableTraits() would return: " .. #BurdJournals.getGrantableTraits() .. " traits")

    BurdJournals.debugPrint("==================== END TRAIT DISCOVERY DEBUG ==")
end

function BurdJournals.debugDumpSkills()
    if not BurdJournals.isDebug() then
        print("[BurdJournals] debugDumpSkills requires -debug mode")
        return
    end

    print("==================== BURD JOURNALS: SKILL DISCOVERY DEBUG ====================")

    BurdJournals._cachedDiscoveredSkills = nil
    local allSkills = BurdJournals.discoverAllSkills(true)

    print("[BurdJournals] Total skills discovered: " .. #allSkills)
    print("")

    local vanillaSkills = {}
    local modSkills = {}

    local baseSkillSet = {}
    for _, skill in ipairs(BurdJournals.ALL_SKILLS) do
        baseSkillSet[string.lower(skill)] = true
    end

    for _, skillName in ipairs(allSkills) do
        local displayName = BurdJournals.getPerkDisplayName(skillName)
        local perk = BurdJournals.getPerkByName(skillName)
        local isValid = perk ~= nil

        local entry = {
            name = skillName,
            displayName = displayName or skillName,
            isValid = isValid
        }

        if baseSkillSet[string.lower(skillName)] then
            table.insert(vanillaSkills, entry)
        else
            table.insert(modSkills, entry)
        end
    end

    print("=== VANILLA/BASE SKILLS: " .. #vanillaSkills .. " ===")
    for _, s in ipairs(vanillaSkills) do
        local status = s.isValid and "[OK]" or "[!]"
        print("  " .. status .. " " .. s.name .. " -> \"" .. s.displayName .. "\"")
    end
    print("")

    print("=== MOD-ADDED SKILLS: " .. #modSkills .. " ===")
    if #modSkills == 0 then
        print("  (none detected - if you have skill mods, they may not be loaded yet)")
    else
        for _, s in ipairs(modSkills) do
            local status = s.isValid and "[OK]" or "[!]"
            print("  " .. status .. " " .. s.name .. " -> \"" .. s.displayName .. "\"")
        end
    end
    print("")

    print("=== RAW PERKFACTORY.PERKLIST ===")
    if PerkFactory and PerkFactory.PerkList then
        local perkList = PerkFactory.PerkList
        if perkList and perkList.size then
            local count = perkList:size()
            print("  PerkFactory.PerkList contains " .. count .. " entries")
            for i = 0, math.min(count - 1, 50) do
                local perk = perkList:get(i)
                if perk then
                    local name = "?"
                    safePcall(function()
                        if perk.getId then
                            name = tostring(perk:getId())
                        elseif perk.getName then
                            name = perk:getName()
                        else
                            name = tostring(perk)
                        end
                    end)
                    print("    [" .. i .. "] " .. name)
                end
            end
            if count > 50 then
                print("    ... and " .. (count - 50) .. " more")
            end
        end
    else
        print("  PerkFactory.PerkList not available")
    end
    print("")

    print("=== SUMMARY ===")
    print("  Vanilla skills: " .. #vanillaSkills)
    print("  Mod-added skills: " .. #modSkills)
    print("  Total available: " .. #allSkills)
    print("")
    print("  Note: Mod skills may only appear after game has fully loaded.")
    print("  If skills are missing, try running this command again in-game.")

    BurdJournals.debugPrint("==================== END SKILL DISCOVERY DEBUG ==")
end

BurdJournals.RECORDABLE_STATS = {

    {
        id = "zombieKills",
        nameKey = "UI_BurdJournals_StatZombieKills",
        nameFallback = "Zombie Kills",
        category = "Combat",
        descriptionKey = "UI_BurdJournals_StatZombieKillsDesc",
        descriptionFallback = "Total zombies killed",
        icon = "media/ui/zombie.png",
        getValue = function(player)
            if not player then return 0 end
            return player:getZombieKills() or 0
        end,
        format = function(value)
            return tostring(value)
        end,
    },
    {
        id = "hoursSurvived",
        nameKey = "UI_BurdJournals_StatHoursSurvived",
        nameFallback = "Hours Survived",
        category = "Survival",
        descriptionKey = "UI_BurdJournals_StatHoursSurvivedDesc",
        descriptionFallback = "Total hours alive in the apocalypse",
        icon = "media/ui/clock.png",
        getValue = function(player)
            if not player then return 0 end
            return math.floor(player:getHoursSurvived() or 0)
        end,
        format = function(value)
            local days = math.floor(value / 24)
            local hours = value % 24
            if days > 0 then
                local daysHoursText = getText("UI_BurdJournals_StatDaysHours")
                if daysHoursText and daysHoursText ~= "UI_BurdJournals_StatDaysHours" then
                    return string.format(daysHoursText, days, hours)
                end
                return days .. " days, " .. hours .. " hours"
            end
            local hoursText = getText("UI_BurdJournals_StatHours")
            if hoursText and hoursText ~= "UI_BurdJournals_StatHours" then
                return string.format(hoursText, hours)
            end
            return hours .. " hours"
        end,
    },
}

function BurdJournals.getStatName(stat)
    if not stat then return "Unknown" end
    if stat.nameKey and getText then
        local localized = getText(stat.nameKey)
        if localized and localized ~= stat.nameKey then
            return localized
        end
    end
    return stat.nameFallback or stat.name or "Unknown"
end

function BurdJournals.getStatDescription(stat)
    if not stat then return "" end
    if stat.descriptionKey and getText then
        local localized = getText(stat.descriptionKey)
        if localized and localized ~= stat.descriptionKey then
            return localized
        end
    end
    return stat.descriptionFallback or stat.description or ""
end

function BurdJournals.getStatById(statId)
    for _, stat in ipairs(BurdJournals.RECORDABLE_STATS) do
        if stat.id == statId then
            return stat
        end
    end
    return nil
end

function BurdJournals.getStatValue(player, statId)
    local stat = BurdJournals.getStatById(statId)
    if stat and stat.getValue then
        local ok, value = safePcall(stat.getValue, player)
        if ok then
            return value
        end
    end
    return nil
end

function BurdJournals.formatStatValue(statId, value)
    local stat = BurdJournals.getStatById(statId)
    if stat and stat.format then
        local ok, formatted = safePcall(stat.format, value)
        if ok then
            return formatted
        end
    end
    return tostring(value)
end

function BurdJournals.getStatsByCategory()
    local categories = {}
    for _, stat in ipairs(BurdJournals.RECORDABLE_STATS) do
        local cat = stat.category or "Other"
        if not categories[cat] then
            categories[cat] = {}
        end
        table.insert(categories[cat], stat)
    end
    return categories
end

function BurdJournals.recordStat(journal, statId, value, player)
    if not journal then return false end

    local modData = journal:getModData()
    if not modData.BurdJournals then
        modData.BurdJournals = {}
    end
    if not modData.BurdJournals.stats then
        modData.BurdJournals.stats = {}
    end

    local stat = BurdJournals.getStatById(statId)
    if not stat then return false end

    modData.BurdJournals.stats[statId] = {
        value = value,
        timestamp = getGameTime():getWorldAgeHours(),
        recordedBy = player and (player:getDescriptor():getForename() .. " " .. player:getDescriptor():getSurname()) or "Unknown",
    }

    return true
end

function BurdJournals.getRecordedStat(journal, statId)
    if not journal then return nil end

    local modData = journal:getModData()
    if modData.BurdJournals and modData.BurdJournals.stats then
        return modData.BurdJournals.stats[statId]
    end
    return nil
end

function BurdJournals.getAllRecordedStats(journal)
    if not journal then return {} end

    local modData = journal:getModData()
    if modData.BurdJournals and modData.BurdJournals.stats then
        return modData.BurdJournals.stats
    end
    return {}
end

function BurdJournals.canUpdateStat(journal, statId, player)
    if not journal or not player then return false, nil, nil end

    local stat = BurdJournals.getStatById(statId)
    if not stat then return false, nil, nil end

    local currentValue = BurdJournals.getStatValue(player, statId)
    local recorded = BurdJournals.getRecordedStat(journal, statId)
    local recordedValue = recorded and recorded.value or nil

    if stat.isText then
        if recordedValue == nil or recordedValue ~= currentValue then
            return true, currentValue, recordedValue
        end
    else
        if recordedValue == nil or currentValue > recordedValue then
            return true, currentValue, recordedValue
        end
    end

    return false, currentValue, recordedValue
end

function BurdJournals.isStatEnabled(statId)

    if not BurdJournals.getSandboxOption("EnableStatRecording") then
        return false
    end

    local statToggleMap = {
        zombieKills = "RecordZombieKills",
        hoursSurvived = "RecordHoursSurvived",
    }

    local toggleOption = statToggleMap[statId]
    if toggleOption then
        local enabled = BurdJournals.getSandboxOption(toggleOption)

        if enabled == nil then
            return true
        end
        return enabled
    end

    return true
end

BurdJournals.DissolutionMessageKeys = {
    "UI_BurdJournals_Dissolve1",
    "UI_BurdJournals_Dissolve2",
    "UI_BurdJournals_Dissolve3",
    "UI_BurdJournals_Dissolve4",
    "UI_BurdJournals_Dissolve5",
    "UI_BurdJournals_Dissolve6",
    "UI_BurdJournals_Dissolve7",
    "UI_BurdJournals_Dissolve8",
    "UI_BurdJournals_Dissolve9",
    "UI_BurdJournals_Dissolve10",
}

BurdJournals.DissolutionFallbacks = {
    "Looks like that journal was on its last read...",
    "The pages crumble to dust in your hands...",
    "That was all it had left to give...",
    "The journal falls apart as you close it...",
    "Nothing but scraps remain...",
    "The binding finally gives way...",
    "It served its purpose...",
    "The ink fades completely as you finish reading...",
    "The worn pages disintegrate...",
    "Knowledge absorbed, the journal fades away...",
}

function BurdJournals.getRandomDissolutionMessage()
    local index = ZombRand(#BurdJournals.DissolutionMessageKeys) + 1
    local key = BurdJournals.DissolutionMessageKeys[index]
    local translated = getText(key)

    if translated == key then
        return BurdJournals.DissolutionFallbacks[index]
    end
    return translated
end

function BurdJournals.getSandboxOption(optionName)
    local opts = SandboxVars.BurdJournals
    if opts and opts[optionName] ~= nil then
        return opts[optionName]
    end
    local defaults = {
        EnableJournals = true,

        XPRecoveryMode = 1,
        DiminishingFirstRead = 100,
        DiminishingDecayRate = 10,
        DiminishingMinimum = 10,

        RequirePenToWrite = true,
        PenUsesPerLog = 1,
        RequireEraserToErase = true,

        LearningTimePerSkill = 3.0,
        LearningTimePerTrait = 5.0,
        LearningTimePerRecipe = 2.0,
        LearningTimeMultiplier = 1.0,

        EnableStatRecording = true,
        RecordZombieKills = true,
        RecordHoursSurvived = true,

        EnableRecipeRecording = true,

        -- 0 = unlimited (must match sandbox-options.txt defaults)
        MaxSkillsPerJournal = 0,
        MaxTraitsPerJournal = 0,
        MaxRecipesPerJournal = 0,

        EnableWornJournalSpawns = true,
        WornJournalSpawnChance = 2.0,
        WornJournalMinSkills = 1,
        WornJournalMaxSkills = 2,
        WornJournalMinXP = 25,
        WornJournalMaxXP = 75,

        EnableBloodyJournalSpawns = true,
        BloodyJournalSpawnChance = 0.5,
        BloodyJournalMinSkills = 2,
        BloodyJournalMaxSkills = 4,
        BloodyJournalMinXP = 50,
        BloodyJournalMaxXP = 150,
        BloodyJournalTraitChance = 15,
        BloodyJournalMaxTraits = 2,

        EnablePlayerJournals = true,
        ReadingSkillAffectsSpeed = true,
        ReadingSpeedBonus = 0.1,
        EraseTime = 10.0,
        ConvertTime = 15.0,

        JournalXPMultiplier = 1.0,

        AllowOthersToOpenJournals = true,
        AllowOthersToClaimFromJournals = true,

        EnableBaselineRestriction = true,

        AllowPlayerJournalDissolution = false,
    }
    return defaults[optionName]
end

function BurdJournals.isEnabled()
    return BurdJournals.getSandboxOption("EnableJournals")
end

function BurdJournals.isPlayerJournalsEnabled()
    return BurdJournals.getSandboxOption("EnablePlayerJournals") ~= false
end

setmetatable(BurdJournals.Limits, {
    __index = function(t, key)

        if key == "MAX_SKILLS" then
            -- 0 = unlimited (sandbox option comment says "0 = unlimited")
            local val = BurdJournals.getSandboxOption("MaxSkillsPerJournal")
            if val == nil or val == 0 then return 999999 end
            return val
        elseif key == "MAX_TRAITS" then
            -- 0 = unlimited
            local val = BurdJournals.getSandboxOption("MaxTraitsPerJournal")
            if val == nil or val == 0 then return 999999 end
            return val
        elseif key == "MAX_RECIPES" then
            -- 0 = unlimited
            local val = BurdJournals.getSandboxOption("MaxRecipesPerJournal")
            if val == nil or val == 0 then return 999999 end
            return val

        elseif key == "WARN_SKILLS" then
            local val = BurdJournals.getSandboxOption("MaxSkillsPerJournal")
            if val == nil or val == 0 then return 999999 end
            return math.floor(val * 0.5)
        elseif key == "WARN_TRAITS" then
            local val = BurdJournals.getSandboxOption("MaxTraitsPerJournal")
            if val == nil or val == 0 then return 999999 end
            return math.floor(val * 0.4)
        elseif key == "WARN_RECIPES" then
            local val = BurdJournals.getSandboxOption("MaxRecipesPerJournal")
            if val == nil or val == 0 then return 999999 end
            return math.floor(val * 0.4)
        end
        return rawget(t, key)
    end
})

function BurdJournals.getPlayerSteamId(player)
    if not player then return nil end

    if player.getSteamID then
        local steamId = player:getSteamID()

        if steamId and steamId ~= "" and steamId ~= 0 and tostring(steamId) ~= "0" then
            return tostring(steamId)
        end
    end

    local username = player:getUsername()
    if username and username ~= "" then
        return "local_" .. username
    end

    return "local_unknown"
end

function BurdJournals.getPlayerCharacterId(player)
    if not player then return nil end

    local steamId = BurdJournals.getPlayerSteamId(player)
    if not steamId then return nil end

    local descriptor = player:getDescriptor()
    if not descriptor then return steamId .. "_Unknown" end

    local forename = descriptor:getForename() or "Unknown"
    local surname = descriptor:getSurname() or ""
    local charName = forename .. "_" .. surname

    charName = string.gsub(charName, " ", "_")

    return steamId .. "_" .. charName
end

function BurdJournals.getJournalOwnerSteamId(item)
    if not item then return nil end
    local modData = item:getModData()
    if modData.BurdJournals and modData.BurdJournals.ownerSteamId then
        return modData.BurdJournals.ownerSteamId
    end
    return nil
end

function BurdJournals.getJournalOwnerUsername(item)
    if not item then return nil end
    local modData = item:getModData()
    if modData.BurdJournals and modData.BurdJournals.ownerUsername then
        return modData.BurdJournals.ownerUsername
    end
    return nil
end

function BurdJournals.getJournalAuthorUsername(item)
    if not item then return nil end
    local modData = item:getModData()
    if modData.BurdJournals and modData.BurdJournals.author then
        return modData.BurdJournals.author
    end
    return nil
end

function BurdJournals.isJournalOwner(player, item)
    if not player or not item then return false end

    local modData = item:getModData()
    if not modData.BurdJournals then return true end

    local journalData = modData.BurdJournals

    local ownerSteamId = journalData.ownerSteamId
    if ownerSteamId then
        local playerSteamId = BurdJournals.getPlayerSteamId(player)
        if playerSteamId then

            if ownerSteamId == playerSteamId then
                return true
            end

        end
    end

    local ownerUsername = journalData.ownerUsername
    if ownerUsername then
        local playerUsername = player:getUsername()
        if playerUsername and ownerUsername == playerUsername then
            return true
        end
    end

    local author = journalData.author
    if author then
        local playerFullName = player:getDescriptor():getForename() .. " " .. player:getDescriptor():getSurname()
        if author == playerFullName then
            return true
        end

        local playerUsername = player:getUsername()
        if playerUsername and author == playerUsername then
            return true
        end
    end

    if not ownerSteamId and not ownerUsername and not author then
        return true
    end

    return false
end

function BurdJournals.canPlayerOpenJournal(player, item)
    if not player or not item then return false, "Invalid player or item" end

    if not BurdJournals.isPlayerJournal(item) then
        return true, nil
    end

    if BurdJournals.isWorn(item) or BurdJournals.isBloody(item) then
        return true, nil
    end

    if BurdJournals.isJournalOwner(player, item) then
        return true, nil
    end

    local allowOthersToOpen = BurdJournals.getSandboxOption("AllowOthersToOpenJournals")
    if allowOthersToOpen == false then
        return false, "You cannot open another player's personal journal."
    end

    return true, nil
end

function BurdJournals.canPlayerClaimFromJournal(player, item)
    if not player or not item then return false, "Invalid player or item" end

    if not BurdJournals.isPlayerJournal(item) then
        return true, nil
    end

    if BurdJournals.isWorn(item) or BurdJournals.isBloody(item) then
        return true, nil
    end

    if BurdJournals.isJournalOwner(player, item) then
        return true, nil
    end

    local allowOthersToOpen = BurdJournals.getSandboxOption("AllowOthersToOpenJournals")
    if allowOthersToOpen == false then
        return false, "You cannot access another player's personal journal."
    end

    local allowOthersToClaim = BurdJournals.getSandboxOption("AllowOthersToClaimFromJournals")
    if allowOthersToClaim == false then
        return false, "You cannot claim from another player's personal journal."
    end

    return true, nil
end

function BurdJournals.initClaimsStructure(journalData)
    if not journalData then return end

    if not journalData.claims or type(journalData.claims) ~= "table" then
        journalData.claims = {}
    end
end

function BurdJournals.getCharacterClaims(journalData, player)
    if not journalData or not player then return nil end

    local characterId = BurdJournals.getPlayerCharacterId(player)
    if not characterId then return nil end

    BurdJournals.initClaimsStructure(journalData)

    local charClaims = journalData.claims[characterId]

    if not charClaims or type(charClaims) ~= "table" then
        charClaims = { skills = {}, traits = {}, recipes = {} }
        journalData.claims[characterId] = charClaims
    else

        if not charClaims.skills or type(charClaims.skills) ~= "table" then
            charClaims.skills = {}
        end
        if not charClaims.traits or type(charClaims.traits) ~= "table" then
            charClaims.traits = {}
        end
        if not charClaims.recipes or type(charClaims.recipes) ~= "table" then
            charClaims.recipes = {}
        end
    end

    return charClaims
end

function BurdJournals.hasCharacterClaimedSkill(journalData, player, skillName)
    if not journalData or not player or not skillName then return false end

    local characterId = BurdJournals.getPlayerCharacterId(player)
    if not characterId then return false end

    if journalData.claims and type(journalData.claims) == "table" then
        local charClaims = journalData.claims[characterId]
        if charClaims and type(charClaims) == "table" then
            local skillClaims = charClaims.skills
            if skillClaims and type(skillClaims) == "table" and skillClaims[skillName] then
                return true
            end
        end
    end

    return false
end

function BurdJournals.hasCharacterClaimedTrait(journalData, player, traitId)
    if not journalData or not player or not traitId then return false end

    local characterId = BurdJournals.getPlayerCharacterId(player)
    if not characterId then return false end

    if journalData.claims and type(journalData.claims) == "table" then
        local charClaims = journalData.claims[characterId]
        if charClaims and type(charClaims) == "table" then
            local traitClaims = charClaims.traits
            if traitClaims and type(traitClaims) == "table" and traitClaims[traitId] then
                return true
            end
        end
    end

    return false
end

function BurdJournals.hasCharacterClaimedRecipe(journalData, player, recipeName)
    if not journalData or not player or not recipeName then return false end

    local characterId = BurdJournals.getPlayerCharacterId(player)
    if not characterId then return false end

    if journalData.claims and type(journalData.claims) == "table" then
        local charClaims = journalData.claims[characterId]
        if charClaims and type(charClaims) == "table" then
            local recipeClaims = charClaims.recipes
            if recipeClaims and type(recipeClaims) == "table" and recipeClaims[recipeName] then
                return true
            end
        end
    end

    return false
end

function BurdJournals.markSkillClaimedByCharacter(journalData, player, skillName)
    if not journalData or not player or not skillName then return false end

    local claims = BurdJournals.getCharacterClaims(journalData, player)
    if not claims then return false end

    claims.skills[skillName] = true

    if not journalData.claimedSkills then
        journalData.claimedSkills = {}
    end
    journalData.claimedSkills[skillName] = true

    return true
end

function BurdJournals.markTraitClaimedByCharacter(journalData, player, traitId)
    if not journalData or not player or not traitId then return false end

    local claims = BurdJournals.getCharacterClaims(journalData, player)
    if not claims then return false end

    claims.traits[traitId] = true

    if not journalData.claimedTraits then
        journalData.claimedTraits = {}
    end
    journalData.claimedTraits[traitId] = true

    return true
end

function BurdJournals.markRecipeClaimedByCharacter(journalData, player, recipeName)
    if not journalData or not player or not recipeName then return false end

    local claims = BurdJournals.getCharacterClaims(journalData, player)
    if not claims then return false end

    claims.recipes[recipeName] = true

    if not journalData.claimedRecipes then
        journalData.claimedRecipes = {}
    end
    journalData.claimedRecipes[recipeName] = true

    return true
end

function BurdJournals.migrateJournalIfNeeded(item, player)
    if not item then return end

    local modData = item:getModData()
    if not modData.BurdJournals then return end

    local journalData = modData.BurdJournals
    local migrated = false

    if not journalData.ownerSteamId and journalData.ownerUsername and player then
        local playerUsername = player:getUsername()
        if playerUsername and journalData.ownerUsername == playerUsername then

            journalData.ownerSteamId = BurdJournals.getPlayerSteamId(player)
            migrated = true
            BurdJournals.debugPrint("[BurdJournals] Migrated journal ownership: added Steam ID " .. tostring(journalData.ownerSteamId))
        end
    end

    if not journalData.ownerSteamId and journalData.ownerUsername then

        journalData.ownerSteamId = "legacy_" .. journalData.ownerUsername
        migrated = true
        BurdJournals.debugPrint("[BurdJournals] Marked legacy journal with placeholder Steam ID: " .. journalData.ownerSteamId)
    end

    if (journalData.claimedSkills or journalData.claimedTraits or journalData.claimedRecipes) and not journalData.claims then

        journalData.claims = {}
        journalData.claims["legacy_unknown"] = {
            skills = journalData.claimedSkills or {},
            traits = journalData.claimedTraits or {},
            recipes = journalData.claimedRecipes or {}
        }
        migrated = true
        BurdJournals.debugPrint("[BurdJournals] Migrated legacy claims to per-character structure")
    end

    -- Infer isPlayerCreated for legacy journals that have owner fields
    -- Without this, legacy player-created journals may be treated as looted and dissolve incorrectly
    if journalData.isPlayerCreated == nil then
        -- If journal has owner fields, it was likely player-created
        if journalData.ownerUsername or journalData.ownerSteamId or journalData.author then
            -- Check it's not a world-spawned journal (which might have author set)
            if not journalData.isWorn and not journalData.isBloody then
                journalData.isPlayerCreated = true
                migrated = true
                BurdJournals.debugPrint("[BurdJournals] Migrated legacy journal: inferred isPlayerCreated=true from owner fields")
            else
                journalData.isPlayerCreated = false
                migrated = true
                BurdJournals.debugPrint("[BurdJournals] Migrated legacy journal: inferred isPlayerCreated=false (worn/bloody)")
            end
        else
            -- No owner info - assume it's a world-spawned journal
            journalData.isPlayerCreated = false
            migrated = true
            BurdJournals.debugPrint("[BurdJournals] Migrated legacy journal: inferred isPlayerCreated=false (no owner)")
        end
    end

    -- Run sanitization if needed (checks version internally)
    local currentSanitizeVersion = BurdJournals.SANITIZE_VERSION or 1
    local journalSanitizeVersion = journalData.sanitizedVersion or 0
    if journalSanitizeVersion < currentSanitizeVersion then
        -- Note: sanitizeJournalData handles its own transmitModData
        local sanitizeResult = BurdJournals.sanitizeJournalData(item, player)
        if sanitizeResult and sanitizeResult.cleaned then
            migrated = true
        end
    end

    if migrated then
        -- Safety check: ensure transmitModData exists (in case item became invalid)
        if item.transmitModData then
            item:transmitModData()
        end
    end
end

-- Sanitize journal data by removing/auto-claiming invalid entries
-- Invalid entries include: removed mod content, skill category names, corrupted data
-- Returns a result table with what was cleaned
function BurdJournals.sanitizeJournalData(item, player)
    if not item then return { cleaned = false } end

    local modData = item:getModData()
    if not modData.BurdJournals then return { cleaned = false } end

    local data = modData.BurdJournals

    -- Check if already sanitized at current version
    local currentVersion = BurdJournals.SANITIZE_VERSION or 1
    if data.sanitizedVersion and data.sanitizedVersion >= currentVersion then
        return { cleaned = false, alreadySanitized = true }
    end

    local result = {
        cleaned = false,
        removedSkills = {},
        removedTraits = {},
        removedRecipes = {},
        autoClaimedSkills = {},
        autoClaimedTraits = {},
        autoClaimedRecipes = {}
    }

    -- Build set of valid skills (both name and lowercase for comparison)
    local validSkillSet = {}
    local allowedSkills = BurdJournals.getAllowedSkills and BurdJournals.getAllowedSkills() or {}
    for _, skill in ipairs(allowedSkills) do
        validSkillSet[skill] = true
        validSkillSet[string.lower(skill)] = true
    end

    -- Helper: Check if skill is valid (in allowed list AND has a real perk)
    local function isValidSkill(skillName)
        if not skillName then return false end
        if not validSkillSet[skillName] and not validSkillSet[string.lower(skillName)] then
            return false
        end
        local perk = BurdJournals.getPerkByName and BurdJournals.getPerkByName(skillName)
        return perk ~= nil
    end

    -- Helper: Check if trait exists in game
    local function isValidTrait(traitId)
        if not traitId then return false end
        -- Check TraitFactory (works for both Build 41 and 42)
        if TraitFactory and TraitFactory.getTrait then
            local trait = TraitFactory.getTrait(traitId)
            if trait then return true end
        end
        -- Build 42: iterate CharacterTraitDefinition.getTraits() to find by name
        -- Note: CharacterTraitDefinition.getCharacterTraitDefinition() expects a CharacterTrait enum,
        -- not a string, and throws a Java exception that pcall cannot catch
        if CharacterTraitDefinition and CharacterTraitDefinition.getTraits then
            local ok, found = safePcall(function()
                local allTraits = CharacterTraitDefinition.getTraits()
                if allTraits then
                    local traitIdLower = string.lower(traitId)
                    for i = 0, allTraits:size() - 1 do
                        local def = allTraits:get(i)
                        if def then
                            local defType = def:getType()
                            if defType then
                                local defName = defType:getName()
                                if defName and string.lower(defName) == traitIdLower then
                                    return true
                                end
                            end
                        end
                    end
                end
                return false
            end)
            if ok and found then return true end
        end
        return false
    end

    -- Build recipe name cache once for O(1) lookups (avoids O(n²) with validateRecipeName)
    local validRecipeSet = {}
    local recipeCacheBuilt = false
    local function buildRecipeCache()
        if recipeCacheBuilt then return end  -- Already built
        recipeCacheBuilt = true  -- Mark as built before iteration to prevent re-entry
        local ok, err = safePcall(function()
            local recipes = getAllRecipes()
            if recipes and recipes.size then
                local size = recipes:size()
                for i = 0, size - 1 do
                    local recipe = recipes:get(i)
                    if recipe and recipe.getName then
                        local nameOk, name = safePcall(function() return recipe:getName() end)
                        if nameOk and name and type(name) == "string" then
                            validRecipeSet[name] = true
                            validRecipeSet[string.lower(name)] = true
                        end
                    end
                end
            end
        end)
        if not ok then
            print("[BurdJournals] Warning: Failed to build recipe cache: " .. tostring(err))
        end
    end

    -- Helper: Check if recipe exists in game (uses cached set)
    local function isValidRecipe(recipeName)
        if not recipeName then return false end
        buildRecipeCache()
        return validRecipeSet[recipeName] or validRecipeSet[string.lower(recipeName)] or false
    end

    -- Sanitize skills
    if type(data.skills) == "table" then
        local cleanedSkills = {}
        for skillName, skillData in pairs(data.skills) do
            if isValidSkill(skillName) then
                cleanedSkills[skillName] = skillData
            else
                -- Invalid skill - remove from skills and auto-claim so it doesn't block dissolution
                table.insert(result.removedSkills, skillName)
                if not data.claimedSkills then data.claimedSkills = {} end
                data.claimedSkills[skillName] = true
                table.insert(result.autoClaimedSkills, skillName)
                result.cleaned = true
            end
        end
        data.skills = cleanedSkills
    end

    -- Sanitize traits
    if type(data.traits) == "table" then
        local cleanedTraits = {}
        for traitId, traitData in pairs(data.traits) do
            if isValidTrait(traitId) then
                cleanedTraits[traitId] = traitData
            else
                -- Invalid trait - remove and auto-claim
                table.insert(result.removedTraits, traitId)
                if not data.claimedTraits then data.claimedTraits = {} end
                data.claimedTraits[traitId] = true
                table.insert(result.autoClaimedTraits, traitId)
                result.cleaned = true
            end
        end
        data.traits = cleanedTraits
    end

    -- Sanitize recipes
    if type(data.recipes) == "table" then
        local cleanedRecipes = {}
        for recipeName, recipeData in pairs(data.recipes) do
            if isValidRecipe(recipeName) then
                cleanedRecipes[recipeName] = recipeData
            else
                -- Invalid recipe - remove and auto-claim
                table.insert(result.removedRecipes, recipeName)
                if not data.claimedRecipes then data.claimedRecipes = {} end
                data.claimedRecipes[recipeName] = true
                table.insert(result.autoClaimedRecipes, recipeName)
                result.cleaned = true
            end
        end
        data.recipes = cleanedRecipes
    end

    -- Mark as sanitized at current version
    data.sanitizedVersion = currentVersion

    -- Transmit changes if anything was cleaned
    if result.cleaned then
        if item.transmitModData then
            item:transmitModData()
        end

        -- Helper to safely convert entries to strings for logging
        local function safeConcat(tbl)
            local strs = {}
            for _, v in ipairs(tbl) do
                table.insert(strs, tostring(v))
            end
            return table.concat(strs, ", ")
        end

        -- Log what was cleaned (only in debug mode)
        if #result.removedSkills > 0 then
            BurdJournals.debugPrint("[BurdJournals] Sanitized: Removed " .. #result.removedSkills .. " invalid skills: " .. safeConcat(result.removedSkills))
        end
        if #result.removedTraits > 0 then
            BurdJournals.debugPrint("[BurdJournals] Sanitized: Removed " .. #result.removedTraits .. " invalid traits: " .. safeConcat(result.removedTraits))
        end
        if #result.removedRecipes > 0 then
            BurdJournals.debugPrint("[BurdJournals] Sanitized: Removed " .. #result.removedRecipes .. " invalid recipes: " .. safeConcat(result.removedRecipes))
        end

        local totalRemoved = #result.removedSkills + #result.removedTraits + #result.removedRecipes
        BurdJournals.debugPrint("[BurdJournals] Sanitized journal: removed " .. totalRemoved .. " invalid entries")
    else
        -- Even if nothing was cleaned, update sanitizedVersion to avoid re-checking
        if item.transmitModData then
            item:transmitModData()
        end
    end

    return result
end

function BurdJournals.isDebug()
    return isDebugEnabled and isDebugEnabled() or false
end

-- Debug logging helper - only prints when running with -debug flag
-- Use for verbose operational logs. Keep print() for errors/warnings.
function BurdJournals.debugPrint(msg)
    if BurdJournals.isDebug() then
        print(msg)
    end
end

function BurdJournals.isSkillAllowed(skillName)
    local allowedSkills = BurdJournals.getAllowedSkills()
    for _, skill in ipairs(allowedSkills) do
        if skill == skillName or string.lower(skill) == string.lower(skillName) then
            return true
        end
    end
    return false
end

function BurdJournals.getAllowedSkills()

    return BurdJournals.discoverAllSkills()
end

function BurdJournals.getPerkByName(perkName, allowCategories)
    local actualPerkName = BurdJournals.SKILL_TO_PERK[perkName] or perkName
    local perk = Perks[actualPerkName]
    if perk then
        -- By default, only return trainable skills (not category perks)
        -- Use allowCategories=true if you need to look up category perks
        if not allowCategories then
            -- Check if this is a trainable skill using PerkFactory
            local perkDef = PerkFactory and PerkFactory.getPerk and PerkFactory.getPerk(perk)
            if perkDef then
                -- Use isTrainableSkill to check parent - trainable skills have parent != "None"
                if BurdJournals.isTrainableSkill(perkDef) then
                    return perk
                else
                    -- This is a category perk, not trainable
                    return nil
                end
            end
            -- PerkFactory not available yet (early loading) - fall back to known category list
            -- Only exclude things that are DEFINITELY categories and NOT also skills
            local pureCategories = {
                None = true, MAX = true, Combat = true, Firearm = true,
                Agility = true, Crafting = true, Passive = true,
                Melee = true, Physical = true
                -- NOTE: "Farming" and "Survival" are NOT here because they are ALSO skill names
            }
            if pureCategories[actualPerkName] then
                return nil
            end
            -- Assume it's a valid skill if we can't verify
            return perk
        end
        return perk
    end
    return nil
end

function BurdJournals.getPerkDisplayName(perkName)
    local perk = BurdJournals.getPerkByName(perkName)
    if perk then
        return PerkFactory.getPerk(perk):getName()
    end
    return perkName
end

function BurdJournals.getSkillNameFromPerk(perk)
    if not perk then return nil end

    local perkName = nil

    if type(perk) == "string" then
        perkName = perk
    end

    if not perkName and PerkFactory and PerkFactory.getPerk then
        local ok, result = safePcall(function()
            local perkDef = PerkFactory.getPerk(perk)
            if perkDef then

                if perkDef.getId then
                    return tostring(perkDef:getId())
                elseif perkDef.getName then

                    return perkDef:getName()
                end
            end
            return nil
        end)
        if ok and result then
            perkName = result
        end
    end

    if not perkName and perk.name then
        perkName = tostring(perk.name)
    end

    if not perkName then
        perkName = tostring(perk)

        perkName = perkName:gsub("^Perks%.", "")
        perkName = perkName:gsub("^zombie%.characters%.skills%.PerkFactory%$Perk%.", "")
        perkName = perkName:gsub("^zombie%.characters%.skills%.PerkFactory%$", "")
    end

    if not perkName or perkName == "" then return nil end

    local reverseMap = {
        PlantScavenging = "Foraging",
        Woodwork = "Carpentry"
    }
    if reverseMap[perkName] then
        return reverseMap[perkName]
    end

    local allowedSkills = BurdJournals.getAllowedSkills()
    for _, skillName in ipairs(allowedSkills) do
        if skillName == perkName then
            return skillName
        end
    end

    local lowerPerkName = string.lower(perkName)
    for _, skillName in ipairs(allowedSkills) do
        if string.lower(skillName) == lowerPerkName then
            return skillName
        end
    end

    for _, skillName in ipairs(allowedSkills) do
        local displayName = BurdJournals.getPerkDisplayName(skillName)
        if displayName == perkName or string.lower(displayName) == lowerPerkName then
            return skillName
        end
    end

    return nil
end

function BurdJournals.findItemByIdInContainer(container, itemId)
    if not container then return nil end

    local items = container:getItems()
    if not items then return nil end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then

            if item:getID() == itemId then
                return item
            end

            if item.getInventory then
                local itemInventory = item:getInventory()
                if itemInventory then
                    local found = BurdJournals.findItemByIdInContainer(itemInventory, itemId)
                    if found then return found end
                end
            end
        end
    end
    return nil
end

function BurdJournals.findItemById(player, itemId)
    if not player then return nil end

    local inventory = player:getInventory()
    if inventory then
        local found = BurdJournals.findItemByIdInContainer(inventory, itemId)
        if found then return found end
    end

    if getPlayerLoot and not isServer() then
        local playerNum = player:getPlayerNum()
        if playerNum then
            local lootInventory = getPlayerLoot(playerNum)
            if lootInventory and lootInventory.inventoryPane then
                local inventoryPane = lootInventory.inventoryPane
                if inventoryPane.inventories then
                    for i = 1, #inventoryPane.inventories do
                        local containerInfo = inventoryPane.inventories[i]
                        if containerInfo and containerInfo.inventory then
                            local found = BurdJournals.findItemByIdInContainer(containerInfo.inventory, itemId)
                            if found then return found end
                        end
                    end
                end
            end
        end
    end

    local square = player:getCurrentSquare()
    if square then

        for dx = -1, 1 do
            for dy = -1, 1 do
                local nearSquare = getCell():getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ())
                if nearSquare then

                    local objects = nearSquare:getObjects()
                    if objects then
                        for i = 0, objects:size() - 1 do
                            local obj = objects:get(i)
                            if obj and obj.getContainer then
                                local container = obj:getContainer()
                                if container then
                                    local found = BurdJournals.findItemByIdInContainer(container, itemId)
                                    if found then return found end
                                end
                            end

                            if obj and obj.getInventory then
                                local container = obj:getInventory()
                                if container then
                                    local found = BurdJournals.findItemByIdInContainer(container, itemId)
                                    if found then return found end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return nil
end

BurdJournals.WRITING_TOOLS = {
    "Base.Pen",
    "Base.BluePen",
    "Base.GreenPen",
    "Base.RedPen",
    "Base.Pencil",
    "Base.PencilSpiffo",
    "Base.PenFancy",
    "Base.PenMultiColor",
    "Base.PenSpiffo",
    "Base.PenLight",
}

function BurdJournals.findWritingTool(player)
    if not player then return nil end
    local inventory = player:getInventory()
    if not inventory then return nil end

    for _, toolType in ipairs(BurdJournals.WRITING_TOOLS) do
        local tool = inventory:getFirstTypeRecurse(toolType)
        if tool then return tool end
    end

    return nil
end

function BurdJournals.findEraser(player)
    if not player then return nil end
    local inventory = player:getInventory()
    if not inventory then return nil end

    return inventory:getFirstTypeRecurse("Base.Eraser")
end

function BurdJournals.hasWritingTool(player)
    return BurdJournals.findWritingTool(player) ~= nil
end

function BurdJournals.hasEraser(player)
    return BurdJournals.findEraser(player) ~= nil
end

BurdJournals.CLEANING_ITEMS = {
    soap = {"Base.Soap2"},
    cloth = {"Base.RippedSheets", "Base.RippedSheetsBundle", "Base.DishCloth"},
}

BurdJournals.REPAIR_ITEMS = {
    leather = {"Base.LeatherStrips", "Base.LeatherStripsDirty"},
    thread = {"Base.Thread", "Base.Thread_Sinew", "Base.Thread_Aramid"},
    needle = {"Base.Needle", "Base.Needle_Bone", "Base.Needle_Brass", "Base.Needle_Forged", "Base.SutureNeedle"},
}

function BurdJournals.findCleaningItem(player, category)
    if not player then return nil end
    local inventory = player:getInventory()
    if not inventory then return nil end

    local items = BurdJournals.CLEANING_ITEMS[category]
    if not items then return nil end

    for _, itemType in ipairs(items) do
        local item = inventory:getFirstTypeRecurse(itemType)
        if item then return item end
    end
    return nil
end

function BurdJournals.findRepairItem(player, category)
    if not player then return nil end
    local inventory = player:getInventory()
    if not inventory then return nil end

    local items = BurdJournals.REPAIR_ITEMS[category]
    if not items then return nil end

    for _, itemType in ipairs(items) do
        local item = inventory:getFirstTypeRecurse(itemType)
        if item then return item end
    end
    return nil
end

function BurdJournals.canConvertToClean(player)
    local hasLeather = BurdJournals.findRepairItem(player, "leather") ~= nil
    local hasThread = BurdJournals.findRepairItem(player, "thread") ~= nil
    local hasNeedle = BurdJournals.findRepairItem(player, "needle") ~= nil
    local hasTailoring = player:getPerkLevel(Perks.Tailoring) >= 1
    return hasLeather and hasThread and hasNeedle and hasTailoring
end

function BurdJournals.consumeItemUses(item, uses, player)
    if not item then return end
    if not uses or uses <= 0 then return end
    if not player then
        player = getPlayer()
    end
    if not player then return end

    local inventory = player:getInventory()
    if not inventory then return end

    if item.getUsedDelta and item.setUsedDelta then
        local currentDelta = item:getUsedDelta()
        if currentDelta == nil then currentDelta = 1 end

        local perUse = 0.1
        if item.getUseDelta then
            local d = item:getUseDelta()
            if d and d > 0 then
                perUse = d
            end
        end

        local newDelta = currentDelta - (uses * perUse)
        if newDelta <= 0 then
            inventory:Remove(item)
        else
            item:setUsedDelta(newDelta)
        end
        return
    end

    if item.getDrainableUsesFloat and item.setDrainableUsesFloat then
        local currentUses = item:getDrainableUsesFloat()
        if currentUses == nil then currentUses = 1 end

        local newUses = currentUses - uses
        if newUses <= 0 then
            inventory:Remove(item)
        else
            item:setDrainableUsesFloat(newUses)
        end
        return
    end
end

BurdJournals.BLANK_JOURNAL_TYPES = {
    "BurdJournals.BlankSurvivalJournal",
    "BurdJournals.BlankSurvivalJournal_Worn",
    "BurdJournals.BlankSurvivalJournal_Bloody",
}

BurdJournals.FILLED_JOURNAL_TYPES = {
    "BurdJournals.FilledSurvivalJournal",
    "BurdJournals.FilledSurvivalJournal_Worn",
    "BurdJournals.FilledSurvivalJournal_Bloody",
}

function BurdJournals.isBlankJournal(item)
    if not item then return false end
    local fullType = item:getFullType()
    for _, jType in ipairs(BurdJournals.BLANK_JOURNAL_TYPES) do
        if fullType == jType then return true end
    end
    return false
end

function BurdJournals.isFilledJournal(item)
    if not item then return false end
    local fullType = item:getFullType()
    for _, jType in ipairs(BurdJournals.FILLED_JOURNAL_TYPES) do
        if fullType == jType then return true end
    end
    return false
end

function BurdJournals.isAnyJournal(item)
    if not item then return false end

    if BurdJournals.isBlankJournal(item) or BurdJournals.isFilledJournal(item) then
        return true
    end

    local fullType = item:getFullType()
    if fullType and fullType:find("BurdJournals") and fullType:find("SurvivalJournal") then
        return true
    end

    return false
end

function BurdJournals.isWorn(item)
    if not item then return false end

    -- Guard against zombie/invalid item objects
    local ok, modData = safePcall(function() return item:getModData() end)
    if not ok or not modData then return false end

    if modData.BurdJournals and modData.BurdJournals.isWorn == true then
        return true
    end

    -- Fallback: check item type name (also protected)
    local ok2, fullType = safePcall(function() return item:getFullType() end)
    if ok2 and fullType and fullType:find("_Worn") then
        return true
    end

    return false
end

function BurdJournals.isBloody(item)
    if not item then return false end

    -- Guard against zombie/invalid item objects
    local ok, modData = safePcall(function() return item:getModData() end)
    if not ok or not modData then return false end

    if modData.BurdJournals and modData.BurdJournals.isBloody == true then
        return true
    end

    -- Fallback: check item type name (also protected)
    local ok2, fullType = safePcall(function() return item:getFullType() end)
    if ok2 and fullType and fullType:find("_Bloody") then
        return true
    end

    return false
end

function BurdJournals.isClean(item)
    if not item then return false end
    return not BurdJournals.isWorn(item) and not BurdJournals.isBloody(item)
end

function BurdJournals.wasFromBloody(item)
    if not item then return false end
    local modData = item:getModData()
    return modData.BurdJournals and modData.BurdJournals.wasFromBloody == true
end

function BurdJournals.hasBloodyOrigin(item)
    return BurdJournals.isBloody(item) or BurdJournals.wasFromBloody(item)
end

function BurdJournals.isPlayerJournal(item)
    if not item then return false end
    local modData = item:getModData()
    return modData.BurdJournals and modData.BurdJournals.isPlayerCreated == true
end

function BurdJournals.isRestoredJournal(item)
    if not item then return false end
    local data = BurdJournals.getJournalData(item)
    if not data then return false end
    if not data.isPlayerCreated then return false end

    -- Player journal converted from worn/bloody blank
    -- Check both new format (wasFromWorn/wasFromBloody) and legacy format (isWorn/isBloody still set)
    -- Legacy saves may have isWorn/isBloody still true since the reset code wasn't in place
    return data.wasFromWorn == true
        or data.wasFromBloody == true
        or data.isWorn == true
        or data.isBloody == true
end

function BurdJournals.setWorn(item, worn)
    if not item then return end
    local modData = item:getModData()
    if not modData.BurdJournals then
        modData.BurdJournals = {}
    end
    modData.BurdJournals.isWorn = worn
    modData.BurdJournals.isBloody = false
    BurdJournals.updateJournalIcon(item)
    BurdJournals.updateJournalName(item)
end

function BurdJournals.setBloody(item, bloody)
    if not item then return end
    local modData = item:getModData()
    if not modData.BurdJournals then
        modData.BurdJournals = {}
    end
    modData.BurdJournals.isBloody = bloody
    modData.BurdJournals.isWorn = false
    BurdJournals.updateJournalIcon(item)
    BurdJournals.updateJournalName(item)
end

function BurdJournals.setClean(item)
    if not item then return end
    local modData = item:getModData()
    if not modData.BurdJournals then
        modData.BurdJournals = {}
    end
    modData.BurdJournals.isWorn = false
    modData.BurdJournals.isBloody = false
    modData.BurdJournals.wasFromBloody = false
    modData.BurdJournals.isPlayerCreated = true
    BurdJournals.updateJournalIcon(item)
    BurdJournals.updateJournalName(item)
end

function BurdJournals.isReadable(item)
    if not item then return false end

    if BurdJournals.isBlankJournal(item) then return false end

    if BurdJournals.isFilledJournal(item) then return true end
    return false
end

function BurdJournals.canAbsorbXP(item)
    if not item then return false end
    if not BurdJournals.isFilledJournal(item) then return false end

    return BurdJournals.isWorn(item) or BurdJournals.isBloody(item)
end

function BurdJournals.canSetXP(item)
    if not item then return false end
    if not BurdJournals.isFilledJournal(item) then return false end
    return BurdJournals.isClean(item)
end

function BurdJournals.getClaimedSkills(item)
    if not item then return {} end
    -- Guard against zombie/invalid item objects
    local ok, modData = safePcall(function() return item:getModData() end)
    if not ok or not modData then return {} end
    if modData.BurdJournals and modData.BurdJournals.claimedSkills then
        return modData.BurdJournals.claimedSkills
    end
    return {}
end

function BurdJournals.isSkillClaimed(item, skillName)
    local claimed = BurdJournals.getClaimedSkills(item)
    return claimed[skillName] == true
end

function BurdJournals.claimSkill(item, skillName)
    if not item then return false end
    local modData = item:getModData()
    if not modData.BurdJournals then
        modData.BurdJournals = {}
    end
    if not modData.BurdJournals.claimedSkills then
        modData.BurdJournals.claimedSkills = {}
    end
    modData.BurdJournals.claimedSkills[skillName] = true
    return true
end

function BurdJournals.getUnclaimedSkills(item, player)
    if not item then return {} end
    local data = BurdJournals.getJournalData(item)
    if not data or not data.skills then return {} end

    local unclaimed = {}

    for skillName, skillData in pairs(data.skills) do
        -- Use per-character claims if player provided, otherwise global
        local isClaimed = false
        if player then
            isClaimed = BurdJournals.hasCharacterClaimedSkill(data, player, skillName)
        else
            local claimed = BurdJournals.getClaimedSkills(item)
            isClaimed = claimed[skillName]
        end
        if not isClaimed then
            unclaimed[skillName] = skillData
        end
    end

    return unclaimed
end

function BurdJournals.getUnclaimedSkillCount(item, player)
    local unclaimed = BurdJournals.getUnclaimedSkills(item, player)
    return BurdJournals.countTable(unclaimed)
end

function BurdJournals.getTotalSkillCount(item)
    if not item then return 0 end
    local data = BurdJournals.getJournalData(item)
    if not data or not data.skills then return 0 end
    return BurdJournals.countTable(data.skills)
end

function BurdJournals.getClaimedTraits(item)
    if not item then return {} end
    -- Guard against zombie/invalid item objects
    local ok, modData = safePcall(function() return item:getModData() end)
    if not ok or not modData then return {} end
    if modData.BurdJournals and modData.BurdJournals.claimedTraits then
        return modData.BurdJournals.claimedTraits
    end
    return {}
end

function BurdJournals.isTraitClaimed(item, traitId)
    local claimed = BurdJournals.getClaimedTraits(item)
    return claimed[traitId] == true
end

function BurdJournals.claimTrait(item, traitId)
    if not item then return false end
    local modData = item:getModData()
    if not modData.BurdJournals then
        modData.BurdJournals = {}
    end
    if not modData.BurdJournals.claimedTraits then
        modData.BurdJournals.claimedTraits = {}
    end
    modData.BurdJournals.claimedTraits[traitId] = true
    return true
end

function BurdJournals.getUnclaimedTraits(item, player)
    if not item then return {} end
    local data = BurdJournals.getJournalData(item)
    if not data or not data.traits then return {} end

    local unclaimed = {}

    for traitId, traitData in pairs(data.traits) do
        -- Use per-character claims if player provided, otherwise global
        local isClaimed = false
        if player then
            isClaimed = BurdJournals.hasCharacterClaimedTrait(data, player, traitId)
        else
            local claimed = BurdJournals.getClaimedTraits(item)
            isClaimed = claimed[traitId]
        end
        if not isClaimed then
            unclaimed[traitId] = traitData
        end
    end

    return unclaimed
end

function BurdJournals.getUnclaimedTraitCount(item, player)
    local unclaimed = BurdJournals.getUnclaimedTraits(item, player)
    return BurdJournals.countTable(unclaimed)
end

-- Helper function to check if a table has any entries (avoids using next() which can fail on PZ server)
local function tableHasEntries(t)
    if type(t) ~= "table" then return false end
    for _ in pairs(t) do
        return true
    end
    return false
end

-- Helper function to count unclaimed entries (avoids next())
local function countUnclaimedEntries(dataTable, claimedTable)
    if type(dataTable) ~= "table" then return 0 end
    local count = 0
    for key, _ in pairs(dataTable) do
        if not claimedTable or not claimedTable[key] then
            count = count + 1
        end
    end
    return count
end

function BurdJournals.shouldDissolve(item, player)
    -- Bail if item is nil
    if not item then
        print("[BurdJournals] shouldDissolve: item is nil")
        return false
    end

    -- Try to get modData directly
    local modData = item:getModData()
    if not modData or not modData.BurdJournals then
        print("[BurdJournals] shouldDissolve: No BurdJournals modData")
        return false
    end
    local data = modData.BurdJournals

    -- Get item type for worn/bloody detection
    local fullType = item:getFullType()
    local isWornFromType = fullType and string.find(fullType, "_Worn") ~= nil
    local isBloodyFromType = fullType and string.find(fullType, "_Bloody") ~= nil
    local isWorn = data.isWorn or isWornFromType
    local isBloody = data.isBloody or isBloodyFromType

    print("[BurdJournals] shouldDissolve: fullType=" .. tostring(fullType) .. ", isWorn=" .. tostring(isWorn) .. ", isBloody=" .. tostring(isBloody))

    -- Player-created journals: check sandbox option for "Restored" dissolution
    if data.isPlayerCreated then
        local isRestored = data.wasFromWorn == true
            or data.wasFromBloody == true
            or data.isWorn == true
            or data.isBloody == true

        print("[BurdJournals] shouldDissolve: Player-created, isRestored=" .. tostring(isRestored))

        if not isRestored then
            print("[BurdJournals] shouldDissolve: Clean player journal, never dissolves")
            return false  -- Clean player journals never dissolve
        end

        local allowDissolution = BurdJournals.getSandboxOption("AllowPlayerJournalDissolution")
        print("[BurdJournals] shouldDissolve: AllowPlayerJournalDissolution=" .. tostring(allowDissolution))
        if not allowDissolution then
            return false
        end
    else
        -- Looted journals: must be worn or bloody to dissolve
        if not isWorn and not isBloody then
            print("[BurdJournals] shouldDissolve: Looted journal but not worn/bloody, cannot dissolve")
            return false
        end
    end

    -- Check if journal has any content (using helper to avoid next())
    local hasSkills = tableHasEntries(data.skills)
    local hasTraits = tableHasEntries(data.traits)
    local hasRecipes = tableHasEntries(data.recipes)

    -- Check claims
    local wasSanitized = data.sanitizedVersion and data.sanitizedVersion > 0
    local hasClaims = tableHasEntries(data.claimedSkills)
        or tableHasEntries(data.claimedTraits)
        or tableHasEntries(data.claimedRecipes)

    print("[BurdJournals] shouldDissolve: hasSkills=" .. tostring(hasSkills) .. ", hasTraits=" .. tostring(hasTraits) .. ", hasRecipes=" .. tostring(hasRecipes))

    -- Don't dissolve empty journals unless sanitized with claims
    if not hasSkills and not hasTraits and not hasRecipes then
        if wasSanitized and hasClaims then
            print("[BurdJournals] shouldDissolve: Empty but sanitized with claims, dissolving")
            return true
        end
        print("[BurdJournals] shouldDissolve: Empty journal, not dissolving")
        return false
    end

    -- Count unclaimed items using helper function
    local unclaimedSkills = countUnclaimedEntries(data.skills, data.claimedSkills)
    local unclaimedTraits = countUnclaimedEntries(data.traits, data.claimedTraits)
    local unclaimedRecipes = countUnclaimedEntries(data.recipes, data.claimedRecipes)

    print("[BurdJournals] shouldDissolve: unclaimedSkills=" .. tostring(unclaimedSkills) .. ", unclaimedTraits=" .. tostring(unclaimedTraits) .. ", unclaimedRecipes=" .. tostring(unclaimedRecipes))

    local shouldDis = unclaimedSkills == 0 and unclaimedTraits == 0 and unclaimedRecipes == 0
    print("[BurdJournals] shouldDissolve: RESULT=" .. tostring(shouldDis))
    return shouldDis
end

function BurdJournals.getRemainingRewards(item, player)
    local skills = BurdJournals.getUnclaimedSkillCount(item, player)
    local traits = BurdJournals.getUnclaimedTraitCount(item, player)
    local recipes = BurdJournals.getUnclaimedRecipeCount(item, player)
    return skills + traits + recipes
end

function BurdJournals.getTotalRewards(item)
    local skills = BurdJournals.getTotalSkillCount(item)
    local data = BurdJournals.getJournalData(item)
    local traits = data and data.traits and BurdJournals.countTable(data.traits) or 0
    local recipes = data and data.recipes and BurdJournals.countTable(data.recipes) or 0
    return skills + traits + recipes
end

function BurdJournals.updateJournalIcon(item)
    if not item then return end
    if not BurdJournals.isAnyJournal(item) then return end

    local fullType = item:getFullType()
    if fullType:find("_Worn") or fullType:find("_Bloody") then

        return
    end

    local isBlank = BurdJournals.isBlankJournal(item)
    local isWornState = BurdJournals.isWorn(item)
    local isBloodyState = BurdJournals.isBloody(item)

    local iconPrefix = isBlank and "BlankJournal" or "FilledJournal"
    local iconSuffix

    if isBloodyState then
        iconSuffix = "Bloody"
    elseif isWornState then
        iconSuffix = "Worn"
    else
        iconSuffix = "Clean"
    end

    local iconName = iconPrefix .. iconSuffix

    if item.setTexture then
        local texture = getTexture("Item_" .. iconName)
        if texture then
            item:setTexture(texture)
        end
    end
end

function BurdJournals.getJournalStateString(item)
    if not item then return "Unknown" end

    if BurdJournals.isBloody(item) then
        return "Bloody"
    elseif BurdJournals.isWorn(item) then
        return "Worn"
    else
        return "Clean"
    end
end

function BurdJournals.getJournalData(item)
    if not item then return nil end
    -- Guard against zombie/invalid item objects
    local ok, modData = safePcall(function() return item:getModData() end)
    if not ok or not modData then return nil end
    return modData.BurdJournals
end

function BurdJournals.safeGetText(key, fallback)
    if not key then return fallback end
    local result = getText(key)

    if result == key then
        return fallback
    end
    return result or fallback
end

function BurdJournals.computeLocalizedName(item)
    if not item then return nil end

    local modData = item:getModData()
    local data = modData.BurdJournals or {}

    local isWornState = data.isWorn
    local isBloodyState = data.isBloody
    local author = data.author
    local professionName = data.professionName
    local isPlayerCreated = data.isPlayerCreated

    local stateSuffix = ""
    if isBloodyState then
        stateSuffix = BurdJournals.safeGetText("UI_BurdJournals_StateBloody", "Bloody")
    elseif isWornState then
        stateSuffix = BurdJournals.safeGetText("UI_BurdJournals_StateWorn", "Worn")
    end

    local baseName
    if BurdJournals.isBlankJournal(item) then
        baseName = BurdJournals.safeGetText("UI_BurdJournals_BlankJournal", "Blank Survival Journal")
        if stateSuffix ~= "" then
            baseName = baseName .. " (" .. stateSuffix .. ")"
        end
    elseif BurdJournals.isFilledJournal(item) then
        baseName = BurdJournals.safeGetText("UI_BurdJournals_FilledJournal", "Filled Survival Journal")
        local suffixParts = {}

        if stateSuffix ~= "" then
            table.insert(suffixParts, stateSuffix)
        end

        if isPlayerCreated and author then

            table.insert(suffixParts, author)
        elseif not isPlayerCreated and professionName then

            if string.find(professionName, "^Former") or string.find(professionName, "^Previous") then
                table.insert(suffixParts, professionName)
            else
                local prevFormat = BurdJournals.safeGetText("UI_BurdJournals_PreviousProfession", "Previous %s")
                table.insert(suffixParts, string.format(prevFormat, professionName))
            end
        elseif author then

            table.insert(suffixParts, author)
        end

        if #suffixParts > 0 then
            baseName = baseName .. " (" .. table.concat(suffixParts, " - ") .. ")"
        end
    end

    return baseName
end

BurdJournals._localizedItems = BurdJournals._localizedItems or {}

function BurdJournals.clearLocalizedItemsCache()
    BurdJournals._localizedItems = {}
end

function BurdJournals.updateJournalName(item, forceUpdate)
    if not item then return end

    local modData = item:getModData()
    local data = modData.BurdJournals or {}

    if data.customName then
        if item:getName() ~= data.customName then
            item:setName(data.customName)
        end
        return
    end

    local itemId = item:getID()
    if not forceUpdate and BurdJournals._localizedItems[itemId] then

        return
    end

    local currentName = item:getName()
    local needsLocalization = not currentName
        or currentName == ""
        or currentName:find("UI_BurdJournals_")
        or currentName:find("^Item_")
        or currentName:find("^BurdJournals%.")
        or currentName:find("BlankSurvivalJournal")
        or currentName:find("FilledSurvivalJournal")

    local isNonPlayerJournal = not data.isPlayerCreated and (data.isWorn or data.isBloody or data.wasFromBloody)
    if isNonPlayerJournal then
        needsLocalization = true
    end

    if not needsLocalization and not forceUpdate then
        BurdJournals._localizedItems[itemId] = true
        return
    end

    local baseName = BurdJournals.computeLocalizedName(item)

    if baseName and item.setName then
        item:setName(baseName)

        BurdJournals._localizedItems[itemId] = true
    end
end

function BurdJournals.getAuthorFromJournal(item)
    local data = BurdJournals.getJournalData(item)
    if data and data.author then
        return data.author
    end
    return "Unknown"
end

function BurdJournals.countTable(tbl)
    if not tbl then return 0 end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

function BurdJournals.tableContains(tbl, value)
    for _, v in pairs(tbl) do
        if v == value then return true end
    end
    return false
end

function BurdJournals.formatXP(xp)
    if xp >= 1000 then
        return string.format("%.1fk", xp / 1000)
    end
    return tostring(math.floor(xp))
end

function BurdJournals.formatTimestamp(hours)
    local days = math.floor(hours / 24)
    local remainingHours = math.floor(hours % 24)
    return string.format("Day %d, Hour %d", days, remainingHours)
end

BurdJournals.RANDOM_FIRST_NAMES = {
    "James", "John", "Michael", "David", "Robert", "William", "Thomas", "Richard",
    "Mary", "Patricia", "Jennifer", "Linda", "Elizabeth", "Barbara", "Susan", "Jessica",
    "Daniel", "Matthew", "Anthony", "Mark", "Donald", "Steven", "Paul", "Andrew",
    "Sarah", "Karen", "Nancy", "Lisa", "Betty", "Margaret", "Sandra", "Ashley",
    "Joshua", "Kenneth", "Kevin", "Brian", "George", "Timothy", "Ronald", "Edward",
    "Kimberly", "Emily", "Donna", "Michelle", "Dorothy", "Carol", "Amanda", "Melissa",
}

BurdJournals.RANDOM_LAST_NAMES = {
    "Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis",
    "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson", "Thomas",
    "Taylor", "Moore", "Jackson", "Martin", "Lee", "Perez", "Thompson", "White",
    "Harris", "Sanchez", "Clark", "Ramirez", "Lewis", "Robinson", "Walker", "Young",
    "Allen", "King", "Wright", "Scott", "Torres", "Nguyen", "Hill", "Flores",
    "Green", "Adams", "Nelson", "Baker", "Hall", "Rivera", "Campbell", "Mitchell",
}

function BurdJournals.generateRandomSurvivorName()
    local firstName = BurdJournals.RANDOM_FIRST_NAMES[ZombRand(#BurdJournals.RANDOM_FIRST_NAMES) + 1]
    local lastName = BurdJournals.RANDOM_LAST_NAMES[ZombRand(#BurdJournals.RANDOM_LAST_NAMES) + 1]
    return firstName .. " " .. lastName
end

BurdJournals.PROFESSIONS = {
    {id = "fireofficer", name = "Fire Officer", nameKey = "UI_BurdJournals_ProfFireOfficer", flavorKey = "UI_BurdJournals_FlavorFireOfficer"},
    {id = "policeofficer", name = "Police Officer", nameKey = "UI_BurdJournals_ProfPoliceOfficer", flavorKey = "UI_BurdJournals_FlavorPoliceOfficer"},
    {id = "parkranger", name = "Park Ranger", nameKey = "UI_BurdJournals_ProfParkRanger", flavorKey = "UI_BurdJournals_FlavorParkRanger"},
    {id = "constructionworker", name = "Construction Worker", nameKey = "UI_BurdJournals_ProfConstructionWorker", flavorKey = "UI_BurdJournals_FlavorConstructionWorker"},
    {id = "securityguard", name = "Security Guard", nameKey = "UI_BurdJournals_ProfSecurityGuard", flavorKey = "UI_BurdJournals_FlavorSecurityGuard"},
    {id = "carpenter", name = "Carpenter", nameKey = "UI_BurdJournals_ProfCarpenter", flavorKey = "UI_BurdJournals_FlavorCarpenter"},
    {id = "burglar", name = "Burglar", nameKey = "UI_BurdJournals_ProfBurglar", flavorKey = "UI_BurdJournals_FlavorBurglar"},
    {id = "chef", name = "Chef", nameKey = "UI_BurdJournals_ProfChef", flavorKey = "UI_BurdJournals_FlavorChef"},
    {id = "repairman", name = "Repairman", nameKey = "UI_BurdJournals_ProfRepairman", flavorKey = "UI_BurdJournals_FlavorMechanic"},
    {id = "farmer", name = "Farmer", nameKey = "UI_BurdJournals_ProfFarmer", flavorKey = "UI_BurdJournals_FlavorFarmer"},
    {id = "fisherman", name = "Fisherman", nameKey = "UI_BurdJournals_ProfFisherman", flavorKey = "UI_BurdJournals_FlavorFisherman"},
    {id = "doctor", name = "Doctor", nameKey = "UI_BurdJournals_ProfDoctor", flavorKey = "UI_BurdJournals_FlavorDoctor"},
    {id = "nurse", name = "Nurse", nameKey = "UI_BurdJournals_ProfNurse", flavorKey = "UI_BurdJournals_FlavorNurse"},
    {id = "lumberjack", name = "Lumberjack", nameKey = "UI_BurdJournals_ProfLumberjack", flavorKey = "UI_BurdJournals_FlavorLumberjack"},
    {id = "fitnessInstructor", name = "Fitness Instructor", nameKey = "UI_BurdJournals_ProfFitnessInstructor", flavorKey = "UI_BurdJournals_FlavorFitnessInstructor"},
    {id = "burgerflipper", name = "Burger Flipper", nameKey = "UI_BurdJournals_ProfBurgerFlipper", flavorKey = "UI_BurdJournals_FlavorBurgerFlipper"},
    {id = "electrician", name = "Electrician", nameKey = "UI_BurdJournals_ProfElectrician", flavorKey = "UI_BurdJournals_FlavorElectrician"},
    {id = "engineer", name = "Engineer", nameKey = "UI_BurdJournals_ProfEngineer", flavorKey = "UI_BurdJournals_FlavorEngineer"},
    {id = "metalworker", name = "Metalworker", nameKey = "UI_BurdJournals_ProfMetalworker", flavorKey = "UI_BurdJournals_FlavorMetalworker"},
    {id = "mechanics", name = "Mechanic", nameKey = "UI_BurdJournals_ProfMechanic", flavorKey = "UI_BurdJournals_FlavorMechanic"},
    {id = "veteran", name = "Veteran", nameKey = "UI_BurdJournals_ProfVeteran", flavorKey = "UI_BurdJournals_FlavorVeteran"},
    {id = "unemployed", name = "Unemployed", nameKey = "UI_BurdJournals_ProfUnemployed", flavorKey = "UI_BurdJournals_FlavorUnemployed"},
}

function BurdJournals.getRandomProfession()
    local professions = BurdJournals.PROFESSIONS
    local prof = professions[ZombRand(#professions) + 1]

    local profName = prof.nameKey and getText(prof.nameKey) or prof.name
    return prof.id, profName, prof.flavorKey
end

function BurdJournals.generateRandomSkills(minSkills, maxSkills, minXP, maxXP)
    minSkills = minSkills or 1
    maxSkills = maxSkills or 2
    minXP = minXP or 25
    maxXP = maxXP or 75

    local skillCount = ZombRand(minSkills, maxSkills + 1)
    local allSkills = BurdJournals.getAllowedSkills()
    local availableSkills = {}

    for _, skill in ipairs(allSkills) do
        table.insert(availableSkills, skill)
    end

    local skills = {}
    for i = 1, skillCount do
        if #availableSkills == 0 then break end

        local index = ZombRand(#availableSkills) + 1
        local skillName = availableSkills[index]

        table.remove(availableSkills, index)

        local xp = ZombRand(minXP, maxXP + 1)

        skills[skillName] = {
            xp = xp,
            level = math.floor(xp / 75)
        }
    end

    return skills
end

function BurdJournals.mapPerkIdToSkillName(perkId)
    if not perkId then return nil end

    local mappings = {
        Woodwork = "Carpentry",
        PlantScavenging = "Foraging",
    }

    if mappings[perkId] then
        return mappings[perkId]
    end

    local allowedSkills = BurdJournals.getAllowedSkills()
    for _, skillName in ipairs(allowedSkills) do
        if skillName == perkId then
            return skillName
        end

        if string.lower(skillName) == string.lower(perkId) then
            return skillName
        end
    end

    return nil
end

function BurdJournals.getSkillBaseline(player, skillName)
    if not player then return 0 end
    local modData = player:getModData()
    if not modData.BurdJournals then return 0 end
    if not modData.BurdJournals.skillBaseline then return 0 end
    return modData.BurdJournals.skillBaseline[skillName] or 0
end

function BurdJournals.isStartingTrait(player, traitId)
    if not player then return false end
    if not traitId then return false end
    local modData = player:getModData()
    if not modData.BurdJournals then return false end
    if not modData.BurdJournals.traitBaseline then return false end

    return modData.BurdJournals.traitBaseline[traitId] == true
        or modData.BurdJournals.traitBaseline[string.lower(traitId)] == true
end

function BurdJournals.getTraitBaseline(player)
    if not player then return {} end
    local modData = player:getModData()
    if not modData.BurdJournals then return {} end
    return modData.BurdJournals.traitBaseline or {}
end

function BurdJournals.isStartingRecipe(player, recipeName)
    if not player then return false end
    if not recipeName then return false end
    local modData = player:getModData()
    if not modData.BurdJournals then return false end
    if not modData.BurdJournals.recipeBaseline then return false end
    return modData.BurdJournals.recipeBaseline[recipeName] == true
end

function BurdJournals.getRecipeBaseline(player)
    if not player then return {} end
    local modData = player:getModData()
    if not modData.BurdJournals then return {} end
    return modData.BurdJournals.recipeBaseline or {}
end

function BurdJournals.getEarnedXP(player, skillName)
    if not player then return 0 end
    local perk = BurdJournals.getPerkByName(skillName)
    if not perk then return 0 end

    local currentXP = player:getXp():getXP(perk)
    local baselineXP = BurdJournals.getSkillBaseline(player, skillName)

    return math.max(0, currentXP - baselineXP)
end

function BurdJournals.isBaselineRestrictionEnabled()
    return BurdJournals.getSandboxOption("EnableBaselineRestriction") ~= false
end

-- Check if baseline has been bypassed for this specific player (admin cleared it)
function BurdJournals.isBaselineBypassed(player)
    if not player then return false end
    local modData = player:getModData()
    if not modData.BurdJournals then return false end
    return modData.BurdJournals.baselineBypassed == true
end

-- Check if baseline restriction should be enforced for this specific player
-- Returns false if globally disabled OR if bypassed for this player
function BurdJournals.shouldEnforceBaseline(player)
    if not BurdJournals.isBaselineRestrictionEnabled() then
        return false
    end
    if BurdJournals.isBaselineBypassed(player) then
        return false
    end
    return true
end

function BurdJournals.hasBaselineCaptured(player)
    if not player then return false end
    local modData = player:getModData()
    if not modData.BurdJournals then return false end
    return modData.BurdJournals.baselineCaptured == true
end

function BurdJournals.collectPlayerSkills(player)
    if not player then return {} end

    local skills = {}
    local allowedSkills = BurdJournals.getAllowedSkills()
    local useBaseline = BurdJournals.shouldEnforceBaseline(player)

    for _, skillName in ipairs(allowedSkills) do
        local perk = BurdJournals.getPerkByName(skillName)
        if perk then
            local currentXP = player:getXp():getXP(perk)
            local level = player:getPerkLevel(perk)

            local recordXP = currentXP
            if useBaseline then
                local baseline = BurdJournals.getSkillBaseline(player, skillName)
                recordXP = math.max(0, currentXP - baseline)
            end

            if recordXP > 0 then
                skills[skillName] = {
                    xp = recordXP,
                    level = level
                }
            end
        end
    end

    return skills
end

function BurdJournals.collectPlayerTraits(player, excludeStarting)
    if not player then return {} end

    if excludeStarting == nil then
        excludeStarting = BurdJournals.shouldEnforceBaseline(player)
    end

    local traits = {}

    local ok, err = safePcall(function()
        local charTraits = player:getCharacterTraits()
        if charTraits then
            local knownTraits = charTraits:getKnownTraits()
            if knownTraits then
                for i = 0, knownTraits:size() - 1 do
                    local traitType = knownTraits:get(i)
                    if traitType then

                        local traitDef = CharacterTraitDefinition.getCharacterTraitDefinition(traitType)

                        local traitId = nil
                        safePcall(function()
                            if traitType.getName then
                                traitId = traitType:getName()
                            else
                                traitId = tostring(traitType)
                            end
                        end)

                        if traitId then

                            traitId = string.gsub(traitId, "^base:", "")

                            if excludeStarting and BurdJournals.isStartingTrait(player, traitId) then

                            else
                                local traitData = {
                                    name = traitId,
                                    cost = 0,
                                    isPositive = false
                                }

                                if traitDef then
                                    safePcall(function()
                                        traitData.name = traitDef:getLabel() or traitId
                                        traitData.cost = traitDef:getCost() or 0
                                        traitData.isPositive = (traitDef:getCost() or 0) < 0
                                    end)
                                end

                                traits[traitId] = traitData
                            end
                        end
                    end
                end
            end
        end
    end)

    if not ok then
        print("[BurdJournals] collectPlayerTraits error: " .. tostring(err))
    end

    return traits
end

function BurdJournals.collectCharacterInfo(player)
    if not player then return {} end

    local info = {}

    info.name = player:getUsername() or "Unknown"
    info.fullName = player:getDescriptor():getForename() .. " " .. player:getDescriptor():getSurname()

    local profession = player:getDescriptor():getProfession()
    if profession then
        info.profession = profession
        local professionData = ProfessionFactory.getProfession(profession)
        if professionData then
            info.professionName = professionData:getLabel() or profession
        else
            info.professionName = profession
        end
    end

    return info
end

function BurdJournals.collectAllPlayerData(player)
    if not player then return {} end

    return {
        skills = BurdJournals.collectPlayerSkills(player),
        traits = BurdJournals.collectPlayerTraits(player),
        recipes = BurdJournals.collectPlayerMagazineRecipes(player),
        character = BurdJournals.collectCharacterInfo(player),
        timestamp = getGameTime():getWorldAgeHours(),
        isPlayerCreated = true,
    }
end

function BurdJournals.playerHasTrait(player, traitId)

    local ok, result = safePcall(function()
        if not player then return false end
        if not traitId then return false end

        local traitObj = nil
        local traitIdLower = string.lower(traitId)
        local traitIdNorm = string.lower(traitId:gsub("%s", ""))

        if CharacterTraitDefinition and CharacterTraitDefinition.getTraits then
            local allTraits = CharacterTraitDefinition.getTraits()
            for i = 0, allTraits:size() - 1 do
                local def = allTraits:get(i)
                local defType = def:getType()
                local defLabel = def:getLabel() or ""
                local defName = ""

                if defType then
                    safePcall(function()
                        defName = defType:getName() or tostring(defType)
                    end)
                end

                local defLabelLower = string.lower(defLabel)
                local defNameLower = string.lower(defName)
                local defLabelNorm = defLabelLower:gsub("%s", "")
                local defNameNorm = defNameLower:gsub("%s", "")

                local exactMatch = (defLabel == traitId) or (defName == traitId)
                local lowerMatch = (defLabelLower == traitIdLower) or (defNameLower == traitIdLower)
                local normalizedMatch = (defLabelNorm == traitIdNorm) or (defNameNorm == traitIdNorm)
                local partialMatch = defLabelLower:find(traitIdLower, 1, true) or traitIdLower:find(defLabelLower, 1, true)

                if exactMatch or lowerMatch or normalizedMatch or partialMatch then
                    traitObj = defType
                    break
                end
            end
        end

        if not traitObj and CharacterTrait then
            local lookups = {
                string.upper(traitId),
                traitId:gsub("(%u)", "_%1"):sub(2):upper(),
                traitId,
            }
            for _, key in ipairs(lookups) do
                if CharacterTrait[key] then
                    local ct = CharacterTrait[key]
                    if type(ct) == "string" and CharacterTrait.get and ResourceLocation and ResourceLocation.of then
                        local ok2, res = safePcall(function()
                            return CharacterTrait.get(ResourceLocation.of(ct))
                        end)
                        if ok2 and res then
                            traitObj = res
                            break
                        end
                    else
                        traitObj = ct
                        break
                    end
                end
            end
        end

        if traitObj and player.hasTrait then
            return player:hasTrait(traitObj) == true
        end

        if type(player.HasTrait) == "function" then
            return player:HasTrait(traitId) == true
        end

        return false
    end)

    if ok then
        return result == true
    end

    print("[BurdJournals] playerHasTrait error (safe): " .. tostring(result))
    return false
end

function BurdJournals.isPlayerIlliterate(player)
    if not player then return false end
    return BurdJournals.playerHasTrait(player, "illiterate")
end

function BurdJournals.dumpAllTraits()

    if not CharacterTraitDefinition or not CharacterTraitDefinition.getTraits then

        return
    end

    local allTraits = CharacterTraitDefinition.getTraits()

    for i = 0, allTraits:size() - 1 do
        local def = allTraits:get(i)
        local defType = def:getType()
        local defLabel = def:getLabel() or "?"
        local defName = "?"

        if defType then
            safePcall(function()
                defName = defType:getName() or tostring(defType)
            end)
        end

        print(string.format("[BurdJournals] [%d] Label='%s' Name='%s' Type=%s", i, defLabel, defName, tostring(defType)))
    end

end

function BurdJournals.safeAddTrait(player, traitId)
    if not player or not traitId then return false end

    if BurdJournals.playerHasTrait(player, traitId) then

        return true
    end

    local traitObj = nil
    local traitDef = nil
    local traitIdLower = string.lower(traitId)

    local traitIdNorm = string.lower(traitId:gsub("%s", ""))

    if CharacterTraitDefinition and CharacterTraitDefinition.getTraits then
        local allTraits = CharacterTraitDefinition.getTraits()

        for i = 0, allTraits:size() - 1 do
            local def = allTraits:get(i)
            local defType = def:getType()
            local defLabel = def:getLabel() or ""
            local defName = ""

            if defType then
                safePcall(function()
                    defName = defType:getName() or tostring(defType)
                end)
            end

            local defLabelLower = string.lower(defLabel)
            local defNameLower = string.lower(defName)

            local defLabelNorm = defLabelLower:gsub("%s", "")
            local defNameNorm = defNameLower:gsub("%s", "")

            local labelMatch = (defLabel == traitId)
            local nameMatch = (defName == traitId)
            local labelLowerMatch = (defLabelLower == traitIdLower)
            local nameLowerMatch = (defNameLower == traitIdLower)

            local normalizedMatch = (defLabelNorm == traitIdNorm) or (defNameNorm == traitIdNorm)

            local partialMatch = defLabelLower:find(traitIdLower, 1, true) or traitIdLower:find(defLabelLower, 1, true)

            if labelMatch or nameMatch or labelLowerMatch or nameLowerMatch or normalizedMatch or partialMatch then
                traitDef = def
                traitObj = defType
                break
            end
        end

    else

    end

    if not traitObj and CharacterTrait and CharacterTrait.get and ResourceLocation and ResourceLocation.of then

        local formats = {
            "base:" .. string.lower(traitId),
            "base:" .. string.lower(traitId:gsub("(%u)", " %1"):sub(2)),
            "base:" .. string.lower(traitId:gsub("(%u)", "_%1"):sub(2)),
        }

        for _, resourceLoc in ipairs(formats) do
            local ok, result = safePcall(function()
                return CharacterTrait.get(ResourceLocation.of(resourceLoc))
            end)
            if ok and result then
                traitObj = result
                break
            end
        end
    end

    if not traitObj and CharacterTrait then
        local lookups = {
            string.upper(traitId),
            traitId:gsub("(%u)", "_%1"):sub(2):upper(),
            traitId,
        }

        for _, key in ipairs(lookups) do
            local ct = CharacterTrait[key]
            if ct then
                if type(ct) == "string" and CharacterTrait.get and ResourceLocation and ResourceLocation.of then
                    local ok, result = safePcall(function()
                        return CharacterTrait.get(ResourceLocation.of(ct))
                    end)
                    if ok and result then
                        traitObj = result
                        break
                    end
                else
                    traitObj = ct
                    break
                end
            end
        end
    end

    if traitObj then

        local ok, err = safePcall(function()

            player:getCharacterTraits():add(traitObj)

            local traitForBoost = traitDef and traitDef:getType() or traitObj
            if player.modifyTraitXPBoost then
                player:modifyTraitXPBoost(traitForBoost, false)
            end

            if SyncXp then
                SyncXp(player)
            end
        end)

        if ok then

            if traitDef and traitDef.getXpBoosts and transformIntoKahluaTable then
                local applyOk, applyErr = safePcall(function()
                    local xpBoosts = transformIntoKahluaTable(traitDef:getXpBoosts())
                    if xpBoosts then
                        for perk, level in pairs(xpBoosts) do
                            local perkId = tostring(perk)
                            local levelNum = tonumber(tostring(level))
                            if levelNum and levelNum > 0 then

                                local perkObj = Perks and Perks[perkId]
                                if perkObj and perkObj.getTotalXpForLevel then

                                    local currentLevel = 0
                                    if player.getPerkLevel then
                                        currentLevel = player:getPerkLevel(perkObj) or 0
                                    end

                                    local targetLevel = math.min(currentLevel + levelNum, 10)
                                    local targetXp = perkObj:getTotalXpForLevel(targetLevel)
                                    local currentXp = player:getXp():getXP(perkObj) or 0
                                    local xpToAdd = targetXp - currentXp
                                    if xpToAdd > 0 then
                                        player:getXp():AddXP(perkObj, xpToAdd, true, false, false)
                                        print("[BurdJournals] Trait " .. traitId .. " granted +" .. levelNum .. " " .. perkId .. " (+" .. math.floor(xpToAdd) .. " XP)")
                                    end
                                end
                            end
                        end
                    end
                end)
                if not applyOk then
                    print("[BurdJournals] Warning: Failed to apply trait XP boosts: " .. tostring(applyErr))
                end
            end

            if SyncXp then
                SyncXp(player)
            end

            return true
        else
        end
    else
    end

    return false
end

BurdJournals._magazineRecipeCache = nil

function BurdJournals.buildMagazineRecipeCache(forceRefresh)
    if not forceRefresh and BurdJournals._magazineRecipeCache then
        return BurdJournals._magazineRecipeCache
    end

    local cache = {}

    local modRecipes = BurdJournals.getModRegisteredRecipes()
    for recipeName, magazineType in pairs(modRecipes) do
        if not BurdJournals.isRecipeExcluded(recipeName) then
            cache[recipeName] = magazineType
            print("[BurdJournals] Added mod-registered recipe: " .. recipeName)
        end
    end

    local ok, err = safePcall(function()
        local scriptManager = getScriptManager()
        if not scriptManager then
            print("[BurdJournals] buildMagazineRecipeCache: no scriptManager")
            return
        end

        local allItems = scriptManager:getAllItems()
        if not allItems then
            print("[BurdJournals] buildMagazineRecipeCache: no allItems")
            return
        end

        print("[BurdJournals] buildMagazineRecipeCache: scanning " .. allItems:size() .. " items (including mods)")

        for i = 0, allItems:size() - 1 do
            local script = allItems:get(i)
            if script then
                local learnedRecipes = nil
                safePcall(function()
                    learnedRecipes = script:getLearnedRecipes()
                end)

                if learnedRecipes and not learnedRecipes:isEmpty() then
                    local fullType = script:getFullName()
                    print("[BurdJournals] Found magazine with recipes: " .. tostring(fullType))
                    for j = 0, learnedRecipes:size() - 1 do
                        local recipeName = learnedRecipes:get(j)
                        if recipeName then

                            if BurdJournals.isRecipeExcluded(recipeName) then
                                print("[BurdJournals]   - Recipe (EXCLUDED): " .. tostring(recipeName))
                            else
                                print("[BurdJournals]   - Recipe: " .. tostring(recipeName))

                                if not cache[recipeName] then
                                    cache[recipeName] = fullType
                                end
                            end
                        end
                    end
                end
            end
        end
    end)

    if not ok then
        print("[BurdJournals] buildMagazineRecipeCache error: " .. tostring(err))
    end

    BurdJournals._magazineRecipeCache = cache
    local count = 0
    for _ in pairs(cache) do count = count + 1 end
    print("[BurdJournals] Cached " .. count .. " magazine recipes (including mod-registered)")

    return cache
end

function BurdJournals.isMagazineRecipe(recipeName)
    local cache = BurdJournals.buildMagazineRecipeCache()
    return cache[recipeName] ~= nil
end

function BurdJournals.getMagazineForRecipe(recipeName)
    local cache = BurdJournals.buildMagazineRecipeCache()
    return cache[recipeName]
end

function BurdJournals.buildMagazineToRecipesCache(forceRefresh)
    if not forceRefresh and BurdJournals._magazineToRecipesCache then
        return BurdJournals._magazineToRecipesCache
    end

    local cache = {}

    local modMagazines = BurdJournals.getModRegisteredMagazines()
    for magazineType, recipes in pairs(modMagazines) do
        local recipeList = {}
        for _, recipeName in ipairs(recipes) do
            if not BurdJournals.isRecipeExcluded(recipeName) then
                table.insert(recipeList, recipeName)
            end
        end
        if #recipeList > 0 then
            cache[magazineType] = recipeList
        end
    end

    local ok, err = safePcall(function()
        local scriptManager = getScriptManager()
        if not scriptManager then return end

        local allItems = scriptManager:getAllItems()
        if not allItems then return end

        for i = 0, allItems:size() - 1 do
            local script = allItems:get(i)
            if script then
                local learnedRecipes = nil
                safePcall(function()
                    learnedRecipes = script:getLearnedRecipes()
                end)

                if learnedRecipes and not learnedRecipes:isEmpty() then
                    local fullType = script:getFullName()
                    local recipeList = cache[fullType] or {}
                    for j = 0, learnedRecipes:size() - 1 do
                        local recipeName = learnedRecipes:get(j)
                        if recipeName and not BurdJournals.isRecipeExcluded(recipeName) then

                            local isDupe = false
                            for _, existing in ipairs(recipeList) do
                                if existing == recipeName then
                                    isDupe = true
                                    break
                                end
                            end
                            if not isDupe then
                                table.insert(recipeList, recipeName)
                            end
                        end
                    end
                    if #recipeList > 0 then
                        cache[fullType] = recipeList
                    end
                end
            end
        end
    end)

    if not ok then
        print("[BurdJournals] buildMagazineToRecipesCache error: " .. tostring(err))
    end

    BurdJournals._magazineToRecipesCache = cache
    return cache
end

function BurdJournals.collectPlayerMagazineRecipes(player, excludeStarting)
    if not player then
        BurdJournals.debugPrint("[BurdJournals] collectPlayerMagazineRecipes: no player")
        return {}
    end

    if not BurdJournals.getSandboxOption("EnableRecipeRecording") then
        BurdJournals.debugPrint("[BurdJournals] collectPlayerMagazineRecipes: recipe recording disabled")
        return {}
    end

    if excludeStarting == nil then
        excludeStarting = BurdJournals.shouldEnforceBaseline(player)
    end

    local recipes = {}

    local magToRecipes = BurdJournals.buildMagazineToRecipesCache()
    local recipeToMag = BurdJournals.buildMagazineRecipeCache()

    local magCount = 0
    for _ in pairs(magToRecipes) do magCount = magCount + 1 end
    BurdJournals.debugPrint("[BurdJournals] collectPlayerMagazineRecipes: checking " .. magCount .. " magazine types")

    local ok, err = safePcall(function()

        BurdJournals.debugPrint("[BurdJournals] Method 1: Using isRecipeKnown() for each magazine recipe...")
        local method1Count = 0

        if player.isRecipeKnown then
            for magazineType, recipeList in pairs(magToRecipes) do
                for _, recipeName in ipairs(recipeList) do
                    if not recipes[recipeName] then
                        local isKnown = false
                        safePcall(function()
                            isKnown = player:isRecipeKnown(recipeName)
                        end)
                        if isKnown then
                            method1Count = method1Count + 1
                            recipes[recipeName] = true
                        end
                    end
                end
            end
            BurdJournals.debugPrint("[BurdJournals] Method 1 (isRecipeKnown): found " .. method1Count .. " known recipes")
        else
            BurdJournals.debugPrint("[BurdJournals] Method 1: isRecipeKnown not available, skipping")
        end

        BurdJournals.debugPrint("[BurdJournals] Method 2: Checking getAlreadyReadPages for each magazine...")
        local method2Count = 0

        for magazineType, recipeList in pairs(magToRecipes) do
            local pagesRead = 0
            safePcall(function()
                pagesRead = player:getAlreadyReadPages(magazineType) or 0
            end)

            if pagesRead > 0 then
                for _, recipeName in ipairs(recipeList) do
                    if not recipes[recipeName] then
                        method2Count = method2Count + 1
                        recipes[recipeName] = true
                    end
                end
            end
        end
        BurdJournals.debugPrint("[BurdJournals] Method 2 (getAlreadyReadPages): found " .. method2Count .. " additional recipes")

        BurdJournals.debugPrint("[BurdJournals] Method 3: Checking getAlreadyReadBook list...")
        local method3Count = 0
        local readBooks = nil
        safePcall(function()
            readBooks = player:getAlreadyReadBook()
        end)

        if readBooks then
            local hasSize, bookCount = safePcall(function() return readBooks:size() end)
            if hasSize and bookCount then
                BurdJournals.debugPrint("[BurdJournals] Method 3: player has " .. bookCount .. " items in getAlreadyReadBook")
                for i = 0, bookCount - 1 do
                    local bookType = nil
                    safePcall(function() bookType = readBooks:get(i) end)
                    if bookType then
                        local recipeList = magToRecipes[tostring(bookType)]
                        if recipeList then
                            for _, recipeName in ipairs(recipeList) do
                                if not recipes[recipeName] then
                                    method3Count = method3Count + 1
                                    recipes[recipeName] = true
                                end
                            end
                        end
                    end
                end
            end
        else
            BurdJournals.debugPrint("[BurdJournals] Method 3: getAlreadyReadBook returned nil")
        end
        BurdJournals.debugPrint("[BurdJournals] Method 3 (getAlreadyReadBook): found " .. method3Count .. " additional recipes")

        BurdJournals.debugPrint("[BurdJournals] Method 4: Checking getKnownRecipes...")
        local method4Count = 0
        local knownRecipes = nil
        safePcall(function()
            knownRecipes = player:getKnownRecipes()
        end)

        if knownRecipes then
            local hasSize, recipeCount = safePcall(function() return knownRecipes:size() end)
            if hasSize and recipeCount and recipeCount > 0 then
                BurdJournals.debugPrint("[BurdJournals] Method 4: player has " .. recipeCount .. " items in getKnownRecipes")
                for i = 0, recipeCount - 1 do
                    local recipeName = nil
                    safePcall(function() recipeName = knownRecipes:get(i) end)
                    if recipeName then
                        recipeName = tostring(recipeName)
                        local magazineType = recipeToMag[recipeName]
                        if magazineType and not recipes[recipeName] then
                            method4Count = method4Count + 1
                            recipes[recipeName] = true
                        end
                    end
                end
            end
        end
        BurdJournals.debugPrint("[BurdJournals] Method 4 (getKnownRecipes): found " .. method4Count .. " additional recipes")

        -- Method 5: Catch modded recipes not in our cache by checking needToBeLearn flag
        -- This handles mods that use non-standard magazine implementations
        BurdJournals.debugPrint("[BurdJournals] Method 5: Checking needToBeLearn recipes not in cache...")
        local method5Count = 0

        if knownRecipes then
            local scriptManager = getScriptManager()
            local hasSize, recipeCount = safePcall(function() return knownRecipes:size() end)
            if hasSize and recipeCount and recipeCount > 0 and scriptManager then
                for i = 0, recipeCount - 1 do
                    local recipeName = nil
                    safePcall(function() recipeName = knownRecipes:get(i) end)
                    if recipeName then
                        recipeName = tostring(recipeName)
                        -- Skip if already found by previous methods
                        if not recipes[recipeName] then
                            -- Check if this recipe requires learning (needToBeLearn=true)
                            local recipeScript = nil
                            safePcall(function()
                                recipeScript = scriptManager:getRecipe(recipeName)
                            end)
                            if recipeScript then
                                local needsLearning = false
                                safePcall(function()
                                    needsLearning = recipeScript:needToBeLearn()
                                end)
                                if needsLearning then
                                    -- This is a learnable recipe not in our cache - add it
                                    method5Count = method5Count + 1
                                    recipes[recipeName] = true
                                    BurdJournals.debugPrint("[BurdJournals] Method 5: Added '" .. recipeName .. "' (needToBeLearn but not in magazine cache)")
                                end
                            end
                        end
                    end
                end
            end
        end
        BurdJournals.debugPrint("[BurdJournals] Method 5 (needToBeLearn fallback): found " .. method5Count .. " additional recipes")
    end)

    if not ok then
        print("[BurdJournals] collectPlayerMagazineRecipes error: " .. tostring(err))
    end

    local foundCount = 0
    for _ in pairs(recipes) do foundCount = foundCount + 1 end
    BurdJournals.debugPrint("[BurdJournals] collectPlayerMagazineRecipes: TOTAL found " .. foundCount .. " magazine recipes known by player")

    if excludeStarting then
        local filteredRecipes = {}
        local excludedCount = 0
        for recipeName, _ in pairs(recipes) do
            if BurdJournals.isStartingRecipe(player, recipeName) then
                excludedCount = excludedCount + 1
            else
                filteredRecipes[recipeName] = true
            end
        end
        if excludedCount > 0 then
            BurdJournals.debugPrint("[BurdJournals] collectPlayerMagazineRecipes: Excluded " .. excludedCount .. " starting recipes from baseline")
        end
        return filteredRecipes
    end

    return recipes
end

function BurdJournals.playerKnowsRecipe(player, recipeName)
    if not player or not recipeName then return false end

    local DEBUG_RECIPE_CHECK = false

    local ok, result = safePcall(function()

        if player.isRecipeKnown then
            local known = player:isRecipeKnown(recipeName)
            if known then
                if DEBUG_RECIPE_CHECK then
                    print("[BurdJournals DEBUG] playerKnowsRecipe(" .. recipeName .. ") -> TRUE via isRecipeKnown()")
                end
                return true
            end
        end

        local knownRecipes = player:getKnownRecipes()
        if knownRecipes then

            local hasContains, containsResult = safePcall(function()
                return knownRecipes:contains(recipeName)
            end)
            if hasContains and containsResult then
                if DEBUG_RECIPE_CHECK then
                    print("[BurdJournals DEBUG] playerKnowsRecipe(" .. recipeName .. ") -> TRUE via getKnownRecipes():contains()")
                end
                return true
            end

            local hasSize, listSize = safePcall(function() return knownRecipes:size() end)
            if hasSize and listSize and listSize > 0 then
                for i = 0, listSize - 1 do
                    local known = knownRecipes:get(i)
                    if known and tostring(known) == recipeName then
                        if DEBUG_RECIPE_CHECK then
                            print("[BurdJournals DEBUG] playerKnowsRecipe(" .. recipeName .. ") -> TRUE via getKnownRecipes() iteration")
                        end
                        return true
                    end
                end
            end
        end

        local magazineType = BurdJournals.getMagazineForRecipe(recipeName)
        if magazineType then

            local pagesRead = player:getAlreadyReadPages(magazineType) or 0
            if pagesRead > 0 then
                if DEBUG_RECIPE_CHECK then
                    print("[BurdJournals DEBUG] playerKnowsRecipe(" .. recipeName .. ") -> TRUE via getAlreadyReadPages(" .. magazineType .. ")=" .. pagesRead)
                end
                return true
            end

            local readBooks = player:getAlreadyReadBook()
            if readBooks then
                local hasSize, bookCount = safePcall(function() return readBooks:size() end)
                if hasSize and bookCount and bookCount > 0 then
                    for i = 0, bookCount - 1 do
                        local bookType = readBooks:get(i)
                        if bookType and tostring(bookType) == magazineType then
                            if DEBUG_RECIPE_CHECK then
                                print("[BurdJournals DEBUG] playerKnowsRecipe(" .. recipeName .. ") -> TRUE via getAlreadyReadBook contains " .. magazineType)
                            end
                            return true
                        end
                    end
                end
            end
        end

        if DEBUG_RECIPE_CHECK then
            print("[BurdJournals DEBUG] playerKnowsRecipe(" .. recipeName .. ") -> FALSE (no method returned true)")
        end
        return false
    end)

    if ok then return result end
    return false
end

function BurdJournals.validateRecipeName(recipeName)
    if not recipeName then return nil end

    local ok, result = safePcall(function()
        local recipes = getAllRecipes()
        if not recipes then return nil end

        for i = 0, recipes:size() - 1 do
            local recipe = recipes:get(i)
            if recipe then
                local name = recipe:getName()
                if name == recipeName then
                    return name
                end
            end
        end

        local recipeNameLower = string.lower(recipeName)
        for i = 0, recipes:size() - 1 do
            local recipe = recipes:get(i)
            if recipe then
                local name = recipe:getName()
                if name and string.lower(name) == recipeNameLower then
                    return name
                end
            end
        end

        return nil
    end)

    if ok then return result end
    return nil
end

function BurdJournals.getRecipeByName(recipeName)
    if not recipeName then return nil end

    local ok, result = safePcall(function()
        local recipes = getAllRecipes()
        if not recipes then return nil end

        for i = 0, recipes:size() - 1 do
            local recipe = recipes:get(i)
            if recipe and recipe:getName() == recipeName then
                return recipe
            end
        end
        return nil
    end)

    if ok then return result end
    return nil
end

function BurdJournals.learnRecipeWithVerification(player, recipeName, logPrefix)
    if not player or not recipeName then return false end
    logPrefix = logPrefix or "[BurdJournals]"

    if BurdJournals.playerKnowsRecipe(player, recipeName) then
        print(logPrefix .. " Recipe already known: " .. recipeName)
        return true
    end

    local validatedName = BurdJournals.validateRecipeName(recipeName)
    if not validatedName then
        print(logPrefix .. " WARNING: Recipe '" .. recipeName .. "' not found in game recipes!")

        validatedName = recipeName
    elseif validatedName ~= recipeName then
        print(logPrefix .. " Recipe name corrected: '" .. recipeName .. "' -> '" .. validatedName .. "'")
        recipeName = validatedName
    end

    local learned = false

    local ok1, err1 = safePcall(function()
        player:learnRecipe(recipeName)
    end)

    if ok1 then

        if player.isRecipeKnown and player:isRecipeKnown(recipeName) then
            print(logPrefix .. " Learned recipe via learnRecipe(): " .. recipeName)
            learned = true
        else

            local knownRecipes = player:getKnownRecipes()
            if knownRecipes then
                local hasIt, containsIt = safePcall(function() return knownRecipes:contains(recipeName) end)
                if hasIt and containsIt then
                    print(logPrefix .. " Learned recipe via learnRecipe() (verified via getKnownRecipes): " .. recipeName)
                    learned = true
                end
            end
        end
    else
        print(logPrefix .. " learnRecipe() threw error: " .. tostring(err1))
    end

    if not learned then
        local magazineType = BurdJournals.getMagazineForRecipe(recipeName)
        if magazineType then
            print(logPrefix .. " Trying magazine method for: " .. recipeName .. " (magazine: " .. magazineType .. ")")

            local ok2, err2 = safePcall(function()
                local script = getScriptManager():getItem(magazineType)
                if script then
                    local pageCount = 1
                    if script.getPageToLearn then
                        pageCount = script:getPageToLearn() or 1
                    end

                    player:setAlreadyReadPages(magazineType, pageCount)
                    print(logPrefix .. " Set " .. pageCount .. " pages read for magazine: " .. magazineType)
                end
            end)

            if not ok2 then
                print(logPrefix .. " setAlreadyReadPages error: " .. tostring(err2))
            end

            local ok3, err3 = safePcall(function()
                local readBooks = player:getAlreadyReadBook()
                if readBooks then
                    local hasContains, alreadyHas = safePcall(function() return readBooks:contains(magazineType) end)
                    if not (hasContains and alreadyHas) then
                        readBooks:add(magazineType)
                        print(logPrefix .. " Added magazine to read books: " .. magazineType)
                    end
                end
            end)

            if not ok3 then
                print(logPrefix .. " getAlreadyReadBook error: " .. tostring(err3))
            end

            if BurdJournals.playerKnowsRecipe(player, recipeName) then
                print(logPrefix .. " Learned recipe via magazine system: " .. recipeName)
                learned = true
            end
        end
    end

    if not learned then
        print(logPrefix .. " FAILED to learn recipe: " .. recipeName)
    end

    return learned
end

function BurdJournals.debugRecipeSystem(player)
    if not player then
        print("[BurdJournals DEBUG] No player provided")
        return
    end

    BurdJournals.debugPrint("==================== RECIPE SYSTEM DEBUG ====================")

    print("\n[API Availability]")
    print("  player.isRecipeKnown: " .. tostring(player.isRecipeKnown ~= nil))
    print("  player.learnRecipe: " .. tostring(player.learnRecipe ~= nil))
    print("  player.getKnownRecipes: " .. tostring(player.getKnownRecipes ~= nil))
    print("  player.getAlreadyReadPages: " .. tostring(player.getAlreadyReadPages ~= nil))
    print("  player.setAlreadyReadPages: " .. tostring(player.setAlreadyReadPages ~= nil))
    print("  player.getAlreadyReadBook: " .. tostring(player.getAlreadyReadBook ~= nil))

    print("\n[getKnownRecipes Test]")
    local knownRecipes = nil
    local ok1, err1 = safePcall(function()
        knownRecipes = player:getKnownRecipes()
    end)
    if ok1 and knownRecipes then
        local hasSize, recipeCount = safePcall(function() return knownRecipes:size() end)
        if hasSize then
            print("  Count: " .. tostring(recipeCount))
            if recipeCount > 0 and recipeCount <= 10 then
                print("  First few recipes:")
                for i = 0, math.min(recipeCount - 1, 4) do
                    local r = knownRecipes:get(i)
                    print("    - " .. tostring(r))
                end
            elseif recipeCount > 10 then
                print("  (Showing first 5 of " .. recipeCount .. " recipes)")
                for i = 0, 4 do
                    local r = knownRecipes:get(i)
                    print("    - " .. tostring(r))
                end
            end
        else
            print("  Error getting size")
        end
    else
        print("  Error: " .. tostring(err1))
    end

    print("\n[getAlreadyReadBook Test]")
    local readBooks = nil
    local ok2, err2 = safePcall(function()
        readBooks = player:getAlreadyReadBook()
    end)
    if ok2 and readBooks then
        local hasSize, bookCount = safePcall(function() return readBooks:size() end)
        if hasSize then
            print("  Count: " .. tostring(bookCount))
            if bookCount > 0 and bookCount <= 20 then
                print("  Read books/magazines:")
                for i = 0, bookCount - 1 do
                    local b = readBooks:get(i)
                    print("    - " .. tostring(b))
                end
            elseif bookCount > 20 then
                print("  (Showing first 10 of " .. bookCount .. " items)")
                for i = 0, 9 do
                    local b = readBooks:get(i)
                    print("    - " .. tostring(b))
                end
            end
        else
            print("  Error getting size")
        end
    else
        print("  Error: " .. tostring(err2))
    end

    print("\n[Magazine Recipe Cache]")
    local magToRecipes = BurdJournals.buildMagazineToRecipesCache()
    local magCount = 0
    for _ in pairs(magToRecipes) do magCount = magCount + 1 end
    print("  Total magazine types: " .. magCount)

    local sampleCount = 0
    for magType, recipes in pairs(magToRecipes) do
        if sampleCount < 3 then
            print("  " .. magType .. ": " .. #recipes .. " recipes")
            sampleCount = sampleCount + 1
        end
    end

    print("\n[Testing Sample Recipe Check]")

    for magType, recipes in pairs(magToRecipes) do
        if #recipes > 0 then
            local testRecipe = recipes[1]
            print("  Testing: " .. testRecipe .. " (from " .. magType .. ")")

            if player.isRecipeKnown then
                local ok, result = safePcall(function() return player:isRecipeKnown(testRecipe) end)
                print("    isRecipeKnown: " .. tostring(ok and result))
            end

            local ourCheck = BurdJournals.playerKnowsRecipe(player, testRecipe)
            print("    playerKnowsRecipe: " .. tostring(ourCheck))

            local pagesRead = 0
            safePcall(function() pagesRead = player:getAlreadyReadPages(magType) or 0 end)
            print("    getAlreadyReadPages(" .. magType .. "): " .. pagesRead)

            break
        end
    end

    print("\n[Recipe Recording Status]")
    local enableRecording = BurdJournals.getSandboxOption("EnableRecipeRecording")
    print("  EnableRecipeRecording sandbox option: " .. tostring(enableRecording))

    local collectedRecipes = BurdJournals.collectPlayerMagazineRecipes(player)
    local collectedCount = 0
    for _ in pairs(collectedRecipes) do collectedCount = collectedCount + 1 end
    print("  Total magazine recipes player knows: " .. collectedCount)

    BurdJournals.debugPrint("==================== END DEBUG ====================")
end

function BurdJournals.getRecipeDisplayName(recipeName)
    if not recipeName then return "Unknown Recipe" end

    local ok, result = safePcall(function()
        local recipes = getAllRecipes()
        if recipes then
            for i = 0, recipes:size() - 1 do
                local recipe = recipes:get(i)
                if recipe and recipe:getName() == recipeName then

                    if recipe.getOriginalname then
                        local origName = recipe:getOriginalname()
                        if origName and origName ~= "" and origName ~= recipeName then
                            return origName
                        end
                    end

                    break
                end
            end
        end
        return nil
    end)

    if ok and result then return result end

    return BurdJournals.normalizeRecipeName(recipeName)
end

function BurdJournals.normalizeRecipeName(recipeName)
    if not recipeName then return "Unknown Recipe" end

    local displayName = recipeName

    displayName = displayName:gsub("_", " ")

    displayName = displayName:gsub("(%l)(%u)", "%1 %2")

    displayName = displayName:gsub("([%a])(%d)", "%1 %2")

    displayName = displayName:gsub("([Vv]) (%d+)", "%1%2")
    displayName = displayName:gsub("([Vv]ol) (%d+)", "%1%2")
    displayName = displayName:gsub("([Vv]ol)(%d+)", "Vol.%2")

    displayName = displayName:gsub(" To ", " to ")
    displayName = displayName:gsub(" From ", " from ")
    displayName = displayName:gsub(" With ", " with ")
    displayName = displayName:gsub(" And ", " and ")
    displayName = displayName:gsub(" Or ", " or ")
    displayName = displayName:gsub(" For ", " for ")
    displayName = displayName:gsub(" Of ", " of ")
    displayName = displayName:gsub(" In ", " in ")
    displayName = displayName:gsub(" On ", " on ")
    displayName = displayName:gsub(" At ", " at ")
    displayName = displayName:gsub(" By ", " by ")
    displayName = displayName:gsub(" The ", " the ")
    displayName = displayName:gsub(" A ", " a ")
    displayName = displayName:gsub(" An ", " an ")

    displayName = displayName:gsub("^%l", string.upper)

    displayName = displayName:gsub("%s+", " ")

    displayName = displayName:match("^%s*(.-)%s*$")

    return displayName
end

function BurdJournals.getMagazineDisplayName(magazineType)
    if not magazineType then return "Unknown Magazine" end

    local ok, result = safePcall(function()
        local script = getScriptManager():getItem(magazineType)
        if script then
            return script:getDisplayName()
        end
        return nil
    end)

    if ok and result then return result end

    local fallback = magazineType

    if fallback:find("%.") then
        fallback = fallback:match("%.(.+)") or fallback
    end

    fallback = fallback:gsub("(%l)(%u)", "%1 %2")
    fallback = fallback:gsub("(%a)(%d)", "%1 %2")
    return fallback
end

function BurdJournals.getClaimedRecipes(item)
    if not item then return {} end
    -- Guard against zombie/invalid item objects
    local ok, modData = safePcall(function() return item:getModData() end)
    if not ok or not modData then return {} end
    if modData.BurdJournals and modData.BurdJournals.claimedRecipes then
        return modData.BurdJournals.claimedRecipes
    end
    return {}
end

function BurdJournals.isRecipeClaimed(item, recipeName)
    local claimed = BurdJournals.getClaimedRecipes(item)
    return claimed[recipeName] == true
end

function BurdJournals.claimRecipe(item, recipeName)
    if not item then return false end
    local modData = item:getModData()
    if not modData.BurdJournals then
        modData.BurdJournals = {}
    end
    if not modData.BurdJournals.claimedRecipes then
        modData.BurdJournals.claimedRecipes = {}
    end
    modData.BurdJournals.claimedRecipes[recipeName] = true
    return true
end

function BurdJournals.getUnclaimedRecipes(item, player)
    if not item then return {} end
    local data = BurdJournals.getJournalData(item)
    if not data or not data.recipes then return {} end

    local unclaimed = {}

    for recipeName, recipeData in pairs(data.recipes) do
        -- Use per-character claims if player provided, otherwise global
        local isClaimed = false
        if player then
            isClaimed = BurdJournals.hasCharacterClaimedRecipe(data, player, recipeName)
        else
            local claimed = BurdJournals.getClaimedRecipes(item)
            isClaimed = claimed[recipeName]
        end
        if not isClaimed then
            unclaimed[recipeName] = recipeData
        end
    end

    return unclaimed
end

function BurdJournals.getUnclaimedRecipeCount(item, player)
    local unclaimed = BurdJournals.getUnclaimedRecipes(item, player)
    return BurdJournals.countTable(unclaimed)
end

function BurdJournals.getTotalRecipeCount(item)
    if not item then return 0 end
    local data = BurdJournals.getJournalData(item)
    if not data or not data.recipes then return 0 end
    return BurdJournals.countTable(data.recipes)
end

function BurdJournals.getAllMagazineRecipes()
    BurdJournals.debugPrint("[BurdJournals] getAllMagazineRecipes called (isServer=" .. tostring(isServer()) .. ", isClient=" .. tostring(isClient()) .. ")")
    local cache = BurdJournals.buildMagazineRecipeCache()
    local recipes = {}
    for recipeName, _ in pairs(cache) do
        table.insert(recipes, recipeName)
    end
    BurdJournals.debugPrint("[BurdJournals] getAllMagazineRecipes returning " .. #recipes .. " recipes")
    return recipes
end

function BurdJournals.generateRandomRecipes(count)
    if not count or count <= 0 then return {} end

    local recipes = {}

    local available = BurdJournals.getAllMagazineRecipes()
    BurdJournals.debugPrint("[BurdJournals] generateRandomRecipes: Requested " .. count .. " recipes, " .. #available .. " available in cache")

    if #available == 0 then
        print("[BurdJournals] WARNING: No magazine recipes found in cache!")
        -- Debug: Check if cache was even built
        local cacheExists = BurdJournals._magazineRecipeCache ~= nil
        local cacheCount = 0
        if BurdJournals._magazineRecipeCache then
            for _ in pairs(BurdJournals._magazineRecipeCache) do cacheCount = cacheCount + 1 end
        end
        print("[BurdJournals] DEBUG: Cache exists=" .. tostring(cacheExists) .. ", cacheCount=" .. cacheCount)
        return {}
    end

    for i = #available, 2, -1 do
        local j = ZombRand(i) + 1
        available[i], available[j] = available[j], available[i]
    end

    for i = 1, math.min(count, #available) do
        local recipeName = available[i]
        recipes[recipeName] = true
    end

    return recipes
end

function BurdJournals.generateRandomRecipesSeeded(count, seed)
    if not count or count <= 0 then return {} end

    local recipes = {}

    local available = BurdJournals.getAllMagazineRecipes()

    if #available == 0 then
        print("[BurdJournals] WARNING: No magazine recipes found in cache for seeded generation!")
        return {}
    end

    local seedVal = math.floor(seed * 31) % 1000
    for i = 1, math.min(count, #available) do

        local idx = ((seedVal * (i + 7)) % #available) + 1
        local recipeName = available[idx]
        if recipeName and not recipes[recipeName] then
            recipes[recipeName] = true

            table.remove(available, idx)
        end
    end

    return recipes
end

BurdJournals.UI = BurdJournals.UI or {}
BurdJournals.UI.FILTER_TAB_HEIGHT = 22
BurdJournals.UI.FILTER_TAB_SPACING = 2
BurdJournals.UI.FILTER_TAB_PADDING = 8
BurdJournals.UI.FILTER_ARROW_WIDTH = 20

BurdJournals._vanillaSkillSet = nil

function BurdJournals.getVanillaSkillSet()
    if BurdJournals._vanillaSkillSet then
        return BurdJournals._vanillaSkillSet
    end

    local set = {}

    for _, skills in pairs(BurdJournals.SKILL_CATEGORIES) do
        for _, skill in ipairs(skills) do
            set[string.lower(skill)] = true
        end
    end

    if BurdJournals.SKILL_TO_PERK then
        for skillName, perkId in pairs(BurdJournals.SKILL_TO_PERK) do
            set[string.lower(perkId)] = true
        end
    end
    BurdJournals._vanillaSkillSet = set
    return set
end

function BurdJournals.getModSourceFromFullType(fullType)
    if not fullType or fullType == "" then
        return "Vanilla"
    end

    local dotPos = string.find(fullType, "%.")
    if not dotPos then
        return "Vanilla"
    end

    local modulePrefix = string.sub(fullType, 1, dotPos - 1)

    if modulePrefix == "Base" or modulePrefix == "base" then
        return "Vanilla"
    end

    return modulePrefix
end

-- Cache for active mod info (maps mod ID patterns to display names)
BurdJournals._modInfoCache = nil

-- Build a cache of active mods with their display names
-- This helps us identify which mod added a skill/trait
function BurdJournals.getModInfoCache()
    if BurdJournals._modInfoCache then
        return BurdJournals._modInfoCache
    end

    local cache = {
        -- Map lowercase prefixes/patterns to display names
        prefixToName = {},
        -- List of mod IDs for pattern matching
        modIds = {},
    }

    -- Try to get active mods (only available in-game, not during load)
    local ok, err = safePcall(function()
        if getActivatedMods then
            local activeMods = getActivatedMods()
            if activeMods then
                for i = 0, activeMods:size() - 1 do
                    local modId = activeMods:get(i)
                    if modId then
                        table.insert(cache.modIds, modId)
                        local modIdLower = string.lower(modId)

                        -- Try to get the mod's display name
                        local modInfo = getModInfoByID and getModInfoByID(modId)
                        local displayName = modId
                        if modInfo and modInfo.getName then
                            displayName = modInfo:getName() or modId
                        end

                        -- Map various patterns to this mod
                        cache.prefixToName[modIdLower] = displayName

                        -- Also map common abbreviations/prefixes
                        -- e.g., "SoulFilchers_Traits" -> "SF" prefix
                        local underscorePos = string.find(modId, "_")
                        if underscorePos and underscorePos > 1 then
                            local prefix = string.sub(modId, 1, underscorePos - 1)
                            cache.prefixToName[string.lower(prefix)] = displayName
                        end

                        -- Handle mod IDs with capital letters as prefixes
                        -- e.g., "SOTOTraits" -> "SOTO"
                        local capsPrefix = string.match(modId, "^(%u+)")
                        if capsPrefix and #capsPrefix >= 2 then
                            cache.prefixToName[string.lower(capsPrefix)] = displayName
                        end
                    end
                end
            end
        end
    end)

    -- Add some well-known mod mappings as fallbacks
    local knownMods = {
        ["soto"] = "Soul's Trait Overhaul",
        ["mt"] = "More Traits",
        ["tbp"] = "The Only Cure",
        ["ss"] = "Simple Survivors",
        ["hc"] = "Hydrocraft",
        ["org"] = "Orgorealis",
        ["braven"] = "Braven's Mods",
        ["dyn"] = "Dynamic Traits",
        ["zre"] = "Zombie Re-Evolution",
    }
    for prefix, name in pairs(knownMods) do
        if not cache.prefixToName[prefix] then
            cache.prefixToName[prefix] = name
        end
    end

    BurdJournals._modInfoCache = cache
    return cache
end

-- Try to find a mod name from a prefix
function BurdJournals.getModNameFromPrefix(prefix)
    if not prefix or prefix == "" then
        return nil
    end

    local cache = BurdJournals.getModInfoCache()
    local prefixLower = string.lower(prefix)

    -- Direct match
    if cache.prefixToName[prefixLower] then
        return cache.prefixToName[prefixLower]
    end

    -- Try partial match against mod IDs
    for _, modId in ipairs(cache.modIds) do
        if string.find(string.lower(modId), prefixLower, 1, true) then
            return cache.prefixToName[string.lower(modId)] or modId
        end
    end

    -- Return the prefix itself (capitalized nicely) if no match found
    return prefix
end

function BurdJournals.getSkillModSource(skillName)
    if not skillName then
        return "Vanilla"
    end

    local vanillaSet = BurdJournals.getVanillaSkillSet()
    local skillLower = string.lower(skillName)

    if vanillaSet[skillLower] then
        return "Vanilla"
    end

    -- Check for colon separator (e.g., "ModName:SkillName")
    local colonPos = string.find(skillName, ":")
    if colonPos and colonPos > 1 then
        local prefix = string.sub(skillName, 1, colonPos - 1)
        return BurdJournals.getModNameFromPrefix(prefix) or prefix
    end

    -- Check for underscore separator (e.g., "SOTO_Blacksmith" or "ModName_Skill")
    local underscorePos = string.find(skillName, "_")
    if underscorePos and underscorePos > 1 then
        local prefix = string.sub(skillName, 1, underscorePos - 1)
        -- Accept prefixes that are all caps, or mixed case with 2+ chars
        if string.match(prefix, "^%u+$") or (string.match(prefix, "^%u") and #prefix >= 2) then
            return BurdJournals.getModNameFromPrefix(prefix) or prefix
        end
    end

    -- Check for CamelCase mod prefix (e.g., "SOTOBlacksmith")
    local capsPrefix = string.match(skillName, "^(%u%u+)")
    if capsPrefix and #capsPrefix >= 2 and #capsPrefix < #skillName then
        -- Make sure there's more after the prefix
        local remainder = string.sub(skillName, #capsPrefix + 1)
        if string.match(remainder, "^%u") then  -- Next char is also uppercase (like "SOTOBlacksmith")
            local modName = BurdJournals.getModNameFromPrefix(capsPrefix)
            if modName then
                return modName
            end
        end
    end

    -- If we get here, it's modded but we can't identify the source
    return "Modded"
end

-- Cache for vanilla trait IDs
BurdJournals._vanillaTraitSet = nil

-- Build a set of known vanilla trait IDs
function BurdJournals.getVanillaTraitSet()
    if BurdJournals._vanillaTraitSet then
        return BurdJournals._vanillaTraitSet
    end

    -- Known vanilla trait IDs (lowercase for comparison)
    local vanillaTraits = {
        -- Positive traits
        "adrenalinejunkie", "athletic", "axeman", "baseballer", "biker",
        "brave", "burglar", "cat", "chef", "dextrous",
        "eagle", "empath", "fastlearner", "fasthealer", "fastshover",
        "firefighter", "fisherman", "fit", "forager", "gardener",
        "graceful", "gymnast", "hardheaded", "hothead", "hunter",
        "inconspicuous", "inventive", "iron", "juggler", "keen",
        "light", "lowprofile", "lucky", "marksman", "nightowl",
        "nutritionist", "organized", "outdoorsman", "pathfinder", "resilient",
        "runner", "stout", "strong", "thickskinned", "tough",
        "tracker", "veteran", "wakeful",
        -- Negative traits
        "addictive", "agoraphobic", "allergic", "asthmatic", "clumsy",
        "conspicuous", "cowardly", "deaf", "disorganized", "fear",
        "feeble", "hardofhearing", "heavysleeper", "heartyappetite", "hemophobic",
        "highthirst", "illiterate", "outofshape", "overweight", "obese",
        "pacifist", "prone", "restless", "short", "slowhealer",
        "slowlearner", "slowreader", "smoker", "sunday", "thin",
        "underweight", "unfit", "unlucky", "weak", "weakstomach",
        -- Hobby/occupation related
        "amateur", "axe", "angler", "baseball", "blade",
        "blunt", "electrical", "firstaid", "fishing", "handy",
        "herbalist", "hiker", "hunter2", "mechanics", "mechanics2",
        "metalwork", "nutritionist2", "runner2", "sewer", "sprinter",
        "swimmer", "tailoring", "tailor",
    }

    local set = {}
    for _, trait in ipairs(vanillaTraits) do
        set[trait] = true
    end

    BurdJournals._vanillaTraitSet = set
    return set
end

function BurdJournals.getTraitModSource(traitId)
    if not traitId then
        return "Vanilla"
    end

    local traitIdLower = string.lower(traitId)

    -- Check against known vanilla traits first
    local vanillaSet = BurdJournals.getVanillaTraitSet()
    if vanillaSet[traitIdLower] then
        return "Vanilla"
    end

    -- Check for colon separator (e.g., "ModName:TraitName")
    local colonPos = string.find(traitId, ":")
    if colonPos and colonPos > 1 then
        local prefix = string.sub(traitId, 1, colonPos - 1)
        return BurdJournals.getModNameFromPrefix(prefix) or prefix
    end

    -- Check for underscore separator (e.g., "SOTO_Brave" or "MT_FastLearner")
    local underscorePos = string.find(traitId, "_")
    if underscorePos and underscorePos > 1 then
        local prefix = string.sub(traitId, 1, underscorePos - 1)
        -- Accept prefixes that look like mod identifiers
        if string.match(prefix, "^%u") and #prefix >= 2 then
            return BurdJournals.getModNameFromPrefix(prefix) or prefix
        end
    end

    -- Check for CamelCase mod prefix (e.g., "SOTOBrave")
    local capsPrefix = string.match(traitId, "^(%u%u+)")
    if capsPrefix and #capsPrefix >= 2 and #capsPrefix < #traitId then
        local remainder = string.sub(traitId, #capsPrefix + 1)
        if string.match(remainder, "^%u") then
            local modName = BurdJournals.getModNameFromPrefix(capsPrefix)
            if modName then
                return modName
            end
        end
    end

    -- Simple lowercase alphanumeric names are likely vanilla
    if string.match(traitId, "^[a-z][a-z0-9]*$") then
        return "Vanilla"
    end

    -- Single word starting with capital, no separators - likely vanilla
    if string.match(traitId, "^%u[a-z]+$") and not string.find(traitId, "[_:]") then
        return "Vanilla"
    end

    -- If we get here, it's modded but we can't identify the source
    return "Modded"
end

function BurdJournals.getRecipeModSource(recipeName, magazineSource)

    if magazineSource and magazineSource ~= "" then
        return BurdJournals.getModSourceFromFullType(magazineSource)
    end

    if recipeName then
        local magazine = BurdJournals.getMagazineForRecipe(recipeName)
        if magazine then
            return BurdJournals.getModSourceFromFullType(magazine)
        end
    end

    return "Vanilla"
end

function BurdJournals.collectModSources(itemType, journalData, player, mode)
    local sourceCounts = {}

    local function addSource(source)
        sourceCounts[source] = (sourceCounts[source] or 0) + 1
    end

    if itemType == "skills" then
        if mode == "log" then

            local allowedSkills = BurdJournals.getAllowedSkills()
            for _, skillName in ipairs(allowedSkills) do
                local perk = BurdJournals.getPerkByName(skillName)
                if perk and player then
                    local currentXP = player:getXp():getXP(perk)
                    local currentLevel = player:getPerkLevel(perk)
                    if currentXP > 0 or currentLevel > 0 then
                        local source = BurdJournals.getSkillModSource(skillName)
                        addSource(source)
                    end
                end
            end
        else

            if journalData and journalData.skills then
                for skillName, _ in pairs(journalData.skills) do
                    local source = BurdJournals.getSkillModSource(skillName)
                    addSource(source)
                end
            end
        end

    elseif itemType == "traits" then
        if mode == "log" then

            if player then
                local playerTraits = BurdJournals.collectPlayerTraits(player, false)
                for traitId, _ in pairs(playerTraits) do
                    local source = BurdJournals.getTraitModSource(traitId)
                    addSource(source)
                end
            end
        else

            if journalData and journalData.traits then
                for traitId, _ in pairs(journalData.traits) do
                    local source = BurdJournals.getTraitModSource(traitId)
                    addSource(source)
                end
            end
        end

    elseif itemType == "recipes" then
        if mode == "log" then

            if player then
                local playerRecipes = BurdJournals.collectPlayerMagazineRecipes(player)
                for recipeName, recipeData in pairs(playerRecipes) do
                    local magazineSource = (type(recipeData) == "table" and recipeData.source) or BurdJournals.getMagazineForRecipe(recipeName)
                    local source = BurdJournals.getRecipeModSource(recipeName, magazineSource)
                    addSource(source)
                end
            end
        else

            if journalData and journalData.recipes then
                for recipeName, recipeData in pairs(journalData.recipes) do
                    local magazineSource = (type(recipeData) == "table" and recipeData.source) or BurdJournals.getMagazineForRecipe(recipeName)
                    local source = BurdJournals.getRecipeModSource(recipeName, magazineSource)
                    addSource(source)
                end
            end
        end
    end

    local result = {}
    local totalCount = 0
    for source, count in pairs(sourceCounts) do
        totalCount = totalCount + count
        if source ~= "Vanilla" then
            table.insert(result, {source = source, count = count})
        end
    end

    table.sort(result, function(a, b) return a.source < b.source end)

    if sourceCounts["Vanilla"] then
        table.insert(result, 1, {source = "Vanilla", count = sourceCounts["Vanilla"]})
    end

    table.insert(result, 1, {source = "All", count = totalCount})

    return result
end
