--[[
    Burd's Survival Journals - Recipe & OnCreate Callbacks
    Build 42

    Handles OnCreate callbacks for journal creation.

    IMPORTANT: OnCreate is called in TWO different contexts:
    1. Recipe crafting: (items, result, player, selectedItem) - result is the created item
    2. Loot spawning:   (item) - item is the created item directly

    Each callback must handle BOTH signatures to work with world loot spawns!
]]

-- Load the shared module
require "BurdJournals_Shared"

-- ============================================================
--                    HELPER FUNCTION
-- ============================================================

-- Determine the actual item from either call signature:
-- B42 Recipe:     (craftRecipeData, character) -> use craftRecipeData:getAllCreatedItems():get(0)
-- B41 Recipe:     (items, result, player, selectedItem) -> result is the item
-- Loot spawn:     (item) -> first param is the item directly
--
-- Returns: resultItem, player/character, inputItems (if available)
local function getItemFromArgs(arg1, arg2, arg3, arg4)
    -- Check for B42 craftRecipeData signature
    -- craftRecipeData has methods like getAllCreatedItems, getAllConsumedItems
    if arg1 and type(arg1) == "userdata" then
        local hasGetAllCreated = pcall(function() return arg1.getAllCreatedItems end)
        if hasGetAllCreated and arg1.getAllCreatedItems then
            -- B42 signature: (craftRecipeData, character)
            local createdItems = arg1:getAllCreatedItems()
            local resultItem = createdItems and createdItems:size() > 0 and createdItems:get(0) or nil
            local consumedItems = arg1:getAllConsumedItems()
            return resultItem, arg2, consumedItems
        end
    end

    -- Check for B41 recipe signature: (items, result, player, selectedItem)
    if arg2 and type(arg2) ~= "nil" then
        -- Verify arg2 is actually an item (has getModData)
        if arg2.getModData then
            return arg2, arg3, arg1
        end
    end

    -- Loot spawn signature: (item) - arg1 IS the item directly
    if arg1 and arg1.getModData then
        return arg1, nil, nil
    end

    -- Fallback: something went wrong
    return nil, nil, nil
end

-- Safe wrapper for generating random skills (handles if BurdJournals.generateRandomSkills isn't loaded yet)
local function safeGenerateRandomSkills(minSkills, maxSkills, minXP, maxXP)
    if BurdJournals and BurdJournals.generateRandomSkills then
        return BurdJournals.generateRandomSkills(minSkills, maxSkills, minXP, maxXP)
    end
    -- Fallback: generate minimal skills manually
    local skills = {}
    local fallbackSkills = {"Carpentry", "Cooking", "Farming", "Foraging", "Fishing"}
    local numSkills = ZombRand(minSkills or 1, (maxSkills or 2) + 1)
    for i = 1, numSkills do
        local skill = fallbackSkills[ZombRand(#fallbackSkills) + 1]
        skills[skill] = {
            xp = ZombRand(minXP or 25, (maxXP or 75) + 1),
            level = 0
        }
    end
    return skills
end

-- Safe wrapper for generating survivor name
local function safeGenerateSurvivorName()
    if BurdJournals and BurdJournals.generateRandomSurvivorName then
        return BurdJournals.generateRandomSurvivorName()
    end
    local names = {"John", "Jane", "Mike", "Sarah", "David", "Lisa", "Tom", "Emily"}
    return names[ZombRand(#names) + 1] .. " Survivor"
end

-- Safe wrapper for generating UUID
local function safeGenerateUUID()
    if BurdJournals and BurdJournals.generateUUID then
        return BurdJournals.generateUUID()
    end
    return tostring(ZombRand(100000, 999999))
end

-- ============================================================
--                    BLANK JOURNAL CALLBACKS
-- ============================================================

-- Clean Blank - Pristine, craftable
-- Supports B42 (craftRecipeData, character), B41 (items, result, player), and loot (item)
function BurdJournals_OnCreateBlankClean(arg1, arg2, arg3, arg4)
    local ok, err = pcall(function()
        local item, player, _ = getItemFromArgs(arg1, arg2, arg3, arg4)
        if not item then return end

        local modData = item:getModData()
        modData.BurdJournals = {
            uuid = safeGenerateUUID(),
            condition = 10,
            isWorn = false,
            isBloody = false,
            isWritten = false,
            createdBy = player and player:getUsername() or "World",
            createdTimestamp = getGameTime():getWorldAgeHours()
        }

        if BurdJournals and BurdJournals.updateJournalName then
            BurdJournals.updateJournalName(item)
        end
        if BurdJournals and BurdJournals.updateJournalIcon then
            BurdJournals.updateJournalIcon(item)
        end
    end)

    if not ok then
        print("[BurdJournals] ERROR in OnCreateBlankClean: " .. tostring(err))
    end
end

-- Worn Blank - Found in world containers
function BurdJournals_OnCreateBlankWorn(arg1, arg2, arg3, arg4)
    local ok, err = pcall(function()
        local item, player, _ = getItemFromArgs(arg1, arg2, arg3, arg4)
        if not item then return end

        local modData = item:getModData()
        modData.BurdJournals = {
            uuid = safeGenerateUUID(),
            condition = ZombRand(3, 7),
            isWorn = true,
            isBloody = false,
            isWritten = false,
            createdTimestamp = getGameTime():getWorldAgeHours()
        }

        if BurdJournals and BurdJournals.updateJournalName then
            BurdJournals.updateJournalName(item)
        end
        if BurdJournals and BurdJournals.updateJournalIcon then
            BurdJournals.updateJournalIcon(item)
        end
    end)

    if not ok then
        print("[BurdJournals] ERROR in OnCreateBlankWorn: " .. tostring(err))
    end
end

-- Bloody Blank - Found on zombie corpses
function BurdJournals_OnCreateBlankBloody(arg1, arg2, arg3, arg4)
    local ok, err = pcall(function()
        local item, player, _ = getItemFromArgs(arg1, arg2, arg3, arg4)
        if not item then return end

        local modData = item:getModData()
        modData.BurdJournals = {
            uuid = safeGenerateUUID(),
            condition = ZombRand(1, 5),
            isWorn = false,
            isBloody = true,
            isWritten = false,
            createdTimestamp = getGameTime():getWorldAgeHours()
        }

        if BurdJournals and BurdJournals.updateJournalName then
            BurdJournals.updateJournalName(item)
        end
        if BurdJournals and BurdJournals.updateJournalIcon then
            BurdJournals.updateJournalIcon(item)
        end
    end)

    if not ok then
        print("[BurdJournals] ERROR in OnCreateBlankBloody: " .. tostring(err))
    end
end

-- ============================================================
--                   FILLED JOURNAL CALLBACKS
-- ============================================================

-- Clean Filled - Player-created (SET mode) OR dev menu/loot spawned (found journal)
function BurdJournals_OnCreateFilledClean(arg1, arg2, arg3, arg4)
    local ok, err = pcall(function()
        local item, player, _ = getItemFromArgs(arg1, arg2, arg3, arg4)
        if not item then return end

        local modData = item:getModData()

        -- If spawned with a player context (crafting), create a player journal
        -- If spawned without player (dev menu/loot), create a found journal with random survivor
        if player then
            -- Player-created journal (crafting)
            modData.BurdJournals = {
                uuid = safeGenerateUUID(),
                condition = 10,
                isWorn = false,
                isBloody = false,
                isWritten = true,
                wasFromBloody = false,
                isPlayerCreated = true,
                author = player:getUsername(),
                timestamp = getGameTime():getWorldAgeHours(),
                readCount = 0,
                skills = safeGenerateRandomSkills(2, 4, 50, 150),
                claimedSkills = {},
                claimedTraits = {}
            }
        else
            -- Loot/dev menu spawn - create as found journal with random survivor
            local survivorName = safeGenerateSurvivorName()
            modData.BurdJournals = {
                uuid = safeGenerateUUID(),
                condition = 10,
                isWorn = false,
                isBloody = false,
                isWritten = true,
                wasFromBloody = false,
                wasRestored = true,
                isPlayerCreated = false,
                author = survivorName,
                timestamp = getGameTime():getWorldAgeHours() - ZombRand(24, 720),
                readCount = 0,
                skills = safeGenerateRandomSkills(2, 4, 50, 150),
                claimedSkills = {},
                claimedTraits = {}
            }
        end

        if BurdJournals and BurdJournals.updateJournalName then
            BurdJournals.updateJournalName(item)
        end
        if BurdJournals and BurdJournals.updateJournalIcon then
            BurdJournals.updateJournalIcon(item)
        end

        -- Sync modData to clients in multiplayer
        if isServer() and item.transmitModData then
            item:transmitModData()
        end
    end)

    if not ok then
        print("[BurdJournals] ERROR in OnCreateFilledClean: " .. tostring(err))
    end
end

-- Worn Filled - Found in world containers, consumable (ADD mode, light rewards)
-- THIS IS THE PRIMARY CALLBACK FOR WORLD LOOT SPAWNS!
-- Wrapped in pcall to prevent errors from blocking item creation
function BurdJournals_OnCreateFilledWorn(arg1, arg2, arg3, arg4)
    local ok, err = pcall(function()
        local item, player, _ = getItemFromArgs(arg1, arg2, arg3, arg4)
        if not item then
            return
        end


        -- Get sandbox settings for worn journal rewards (with safe fallbacks)
        local minSkills = 1
        local maxSkills = 2
        local minXP = 25
        local maxXP = 75

        if BurdJournals and BurdJournals.getSandboxOption then
            minSkills = BurdJournals.getSandboxOption("WornJournalMinSkills") or minSkills
            maxSkills = BurdJournals.getSandboxOption("WornJournalMaxSkills") or maxSkills
            minXP = BurdJournals.getSandboxOption("WornJournalMinXP") or minXP
            maxXP = BurdJournals.getSandboxOption("WornJournalMaxXP") or maxXP
        end

        -- Get random profession for the previous owner (with fallback)
        local professionId, professionName = "unemployed", "Survivor"
        if BurdJournals and BurdJournals.WorldSpawn and BurdJournals.WorldSpawn.getRandomProfession then
            professionId, professionName = BurdJournals.WorldSpawn.getRandomProfession()
        end

        local modData = item:getModData()
        modData.BurdJournals = {
            uuid = safeGenerateUUID(),
            condition = ZombRand(3, 7),
            isWorn = true,
            isBloody = false,
            isWritten = true,
            wasFromBloody = false,
            isPlayerCreated = false,
            author = safeGenerateSurvivorName(),
            profession = professionId,
            professionName = professionName,
            timestamp = getGameTime():getWorldAgeHours() - ZombRand(24, 720),
            readCount = 0,
            skills = safeGenerateRandomSkills(minSkills, maxSkills, minXP, maxXP),
            traits = {}, -- Worn journals from world don't have traits
            claimedSkills = {},
            claimedTraits = {}
        }

        -- Update name/icon (with safety check)
        if BurdJournals and BurdJournals.updateJournalName then
            BurdJournals.updateJournalName(item)
        end
        if BurdJournals and BurdJournals.updateJournalIcon then
            BurdJournals.updateJournalIcon(item)
        end

        -- Sync modData to clients in multiplayer
        if isServer() and item.transmitModData then
            item:transmitModData()
        end

        -- Debug removed
        local skillCount = 0
        for _ in pairs(modData.BurdJournals.skills or {}) do skillCount = skillCount + 1 end
    end)

    if not ok then
        print("[BurdJournals] ERROR in OnCreateFilledWorn: " .. tostring(err))
    end
end

-- Bloody Filled - Found on zombie corpses (rare rewards + traits)
function BurdJournals_OnCreateFilledBloody(arg1, arg2, arg3, arg4)
    local ok, err = pcall(function()
        local item, player, _ = getItemFromArgs(arg1, arg2, arg3, arg4)
        if not item then return end

        -- Get sandbox settings for bloody journal rewards (with safe fallbacks)
        local minSkills = 2
        local maxSkills = 4
        local minXP = 50
        local maxXP = 150
        local traitChance = 15

        if BurdJournals and BurdJournals.getSandboxOption then
            minSkills = BurdJournals.getSandboxOption("BloodyJournalMinSkills") or minSkills
            maxSkills = BurdJournals.getSandboxOption("BloodyJournalMaxSkills") or maxSkills
            minXP = BurdJournals.getSandboxOption("BloodyJournalMinXP") or minXP
            maxXP = BurdJournals.getSandboxOption("BloodyJournalMaxXP") or maxXP
            traitChance = BurdJournals.getSandboxOption("BloodyJournalTraitChance") or traitChance
        end

        -- Get random profession for the previous owner (with fallback)
        local professionId, professionName = "unemployed", "Survivor"
        if BurdJournals and BurdJournals.WorldSpawn and BurdJournals.WorldSpawn.getRandomProfession then
            professionId, professionName = BurdJournals.WorldSpawn.getRandomProfession()
        end

        -- Generate traits if lucky (1-4 random traits)
        local traits = {}
        if ZombRand(100) < traitChance then
            local grantableTraits = (BurdJournals and BurdJournals.GRANTABLE_TRAITS) or {
                "brave", "organized", "fastlearner", "needslesssleep",
                "lighteater", "dextrous", "graceful", "inconspicuous", "lowthirst"
            }
            if #grantableTraits > 0 then
                -- Generate 1-4 random unique traits
                local numTraits = ZombRand(1, 5)  -- 1 to 4 traits
                local availableTraits = {}
                for _, t in ipairs(grantableTraits) do
                    table.insert(availableTraits, t)
                end

                for i = 1, numTraits do
                    if #availableTraits == 0 then break end
                    local idx = ZombRand(#availableTraits) + 1
                    local randomTrait = availableTraits[idx]
                    if randomTrait then
                        traits[randomTrait] = {
                            name = randomTrait,
                            isPositive = true
                        }
                        -- Remove from available to avoid duplicates
                        table.remove(availableTraits, idx)
                    end
                end
            end
        end

        local modData = item:getModData()
        modData.BurdJournals = {
            uuid = safeGenerateUUID(),
            condition = ZombRand(1, 4),
            isWorn = false,
            isBloody = true,
            isWritten = true,
            wasFromBloody = true,
            isPlayerCreated = false,
            author = safeGenerateSurvivorName(),
            profession = professionId,
            professionName = professionName,
            timestamp = getGameTime():getWorldAgeHours() - ZombRand(24, 720),
            readCount = 0,
            skills = safeGenerateRandomSkills(minSkills, maxSkills, minXP, maxXP),
            traits = traits,
            claimedSkills = {},
            claimedTraits = {}
        }

        if BurdJournals and BurdJournals.updateJournalName then
            BurdJournals.updateJournalName(item)
        end
        if BurdJournals and BurdJournals.updateJournalIcon then
            BurdJournals.updateJournalIcon(item)
        end

        -- Sync modData to clients in multiplayer
        if isServer() and item.transmitModData then
            item:transmitModData()
        end
    end)

    if not ok then
        print("[BurdJournals] ERROR in OnCreateFilledBloody: " .. tostring(err))
    end
end

-- ============================================================
--                    LEGACY/RECIPE CALLBACKS
-- ============================================================

-- Legacy callback for crafting recipes (alias to clean blank)
function BurdJournals_OnCreateBlankJournal(arg1, arg2, arg3, arg4)
    BurdJournals_OnCreateBlankClean(arg1, arg2, arg3, arg4)
end

-- Called when a worn journal is cleaned/repaired (RECIPE ONLY - not loot spawn)
-- Supports B42 (craftRecipeData, character) and B41 (items, result, player)
function BurdJournals_OnCleanWornJournal(arg1, arg2, arg3, arg4)
    local ok, err = pcall(function()
        local result, player, inputItems = getItemFromArgs(arg1, arg2, arg3, arg4)
        if not result then return end

        -- Find the worn journal in the input items
        local wornJournal = nil
        if inputItems and inputItems.size then
            for i = 0, inputItems:size() - 1 do
                local item = inputItems:get(i)
                if item and BurdJournals and BurdJournals.isWorn and BurdJournals.isWorn(item) then
                    wornJournal = item
                    break
                end
            end
        end

        if not wornJournal then
            return
        end

        local wornModData = wornJournal:getModData()
        local journalData = wornModData.BurdJournals

        if journalData then
            local resultModData = result:getModData()
            resultModData.BurdJournals = {
                uuid = safeGenerateUUID(),
                author = journalData.author,
                flavorText = journalData.flavorText,
                timestamp = journalData.timestamp,
                readCount = journalData.readCount or 0,
                skills = journalData.skills,
                traits = journalData.traits,
                isWritten = true,
                isWorn = false,
                isBloody = false,
                condition = 10,
                wasRestored = true,
                wasFromBloody = journalData.wasFromBloody or journalData.isBloody,
                restoredBy = player and player:getUsername() or "Unknown",
                restoredTimestamp = getGameTime():getWorldAgeHours(),
                claimedSkills = journalData.claimedSkills or {},
                claimedTraits = journalData.claimedTraits or {}
            }

            if BurdJournals and BurdJournals.updateJournalName then
                BurdJournals.updateJournalName(result)
            end
            if BurdJournals and BurdJournals.updateJournalIcon then
                BurdJournals.updateJournalIcon(result)
            end
        end
    end)

    if not ok then
        print("[BurdJournals] ERROR in OnCleanWornJournal: " .. tostring(err))
    end
end

-- ============================================================
--           FILLED JOURNAL CONVERSION CALLBACKS
-- ============================================================

-- Convert Worn Filled -> Clean Filled (preserves data)
function BurdJournals_OnCreateFilledCleanFromWorn(arg1, arg2, arg3, arg4)
    local ok, err = pcall(function()
        local result, player, inputItems = getItemFromArgs(arg1, arg2, arg3, arg4)
        if not result then return end

        -- Find the worn journal in the input items
        local wornJournal = nil
        if inputItems and inputItems.size then
            for i = 0, inputItems:size() - 1 do
                local item = inputItems:get(i)
                if item and string.find(item:getFullType(), "FilledSurvivalJournal_Worn") then
                    wornJournal = item
                    break
                end
            end
        end

        if wornJournal then
            local wornModData = wornJournal:getModData()
            local journalData = wornModData.BurdJournals

            if journalData then
                local resultModData = result:getModData()
                resultModData.BurdJournals = {
                    uuid = journalData.uuid or safeGenerateUUID(),
                    author = journalData.author,
                    flavorText = journalData.flavorText,
                    timestamp = journalData.timestamp,
                    readCount = journalData.readCount or 0,
                    skills = journalData.skills or {},
                    traits = journalData.traits or {},
                    isWritten = true,
                    isWorn = false,
                    isBloody = false,
                    bloodyOrigin = journalData.bloodyOrigin,
                    isPlayerCreated = journalData.isPlayerCreated,
                    claimedSkills = journalData.claimedSkills or {},
                    claimedTraits = journalData.claimedTraits or {},
                    wasRestored = true,
                    restoredBy = player and player:getUsername() or "Unknown",
                    restoredTimestamp = getGameTime():getWorldAgeHours(),
                }

                if BurdJournals and BurdJournals.updateJournalName then
                    BurdJournals.updateJournalName(result)
                end
                if BurdJournals and BurdJournals.updateJournalIcon then
                    BurdJournals.updateJournalIcon(result)
                end
            end
        else
            -- Fallback: Initialize as new clean filled journal
            local modData = result:getModData()
            modData.BurdJournals = {
                uuid = safeGenerateUUID(),
                isWritten = false,
                isWorn = false,
                isBloody = false,
                isPlayerCreated = true,
            }
        end
    end)

    if not ok then
        print("[BurdJournals] ERROR in OnCreateFilledCleanFromWorn: " .. tostring(err))
    end
end

-- Convert Bloody Filled -> Worn Filled (preserves data)
function BurdJournals_OnCreateFilledWornFromBloody(arg1, arg2, arg3, arg4)
    local ok, err = pcall(function()
        local result, player, inputItems = getItemFromArgs(arg1, arg2, arg3, arg4)
        if not result then return end

        -- Find the bloody journal in the input items
        local bloodyJournal = nil
        if inputItems and inputItems.size then
            for i = 0, inputItems:size() - 1 do
                local item = inputItems:get(i)
                if item and string.find(item:getFullType(), "FilledSurvivalJournal_Bloody") then
                    bloodyJournal = item
                    break
                end
            end
        end

        if bloodyJournal then
            local bloodyModData = bloodyJournal:getModData()
            local journalData = bloodyModData.BurdJournals

            if journalData then
                local resultModData = result:getModData()
                resultModData.BurdJournals = {
                    uuid = journalData.uuid or safeGenerateUUID(),
                    author = journalData.author,
                    flavorText = journalData.flavorText,
                    timestamp = journalData.timestamp,
                    readCount = journalData.readCount or 0,
                    skills = journalData.skills or {},
                    traits = journalData.traits or {},
                    isWritten = true,
                    isWorn = true,
                    isBloody = false,
                    bloodyOrigin = true,
                    isPlayerCreated = false,
                    claimedSkills = journalData.claimedSkills or {},
                    claimedTraits = journalData.claimedTraits or {},
                    wasCleaned = true,
                    cleanedBy = player and player:getUsername() or "Unknown",
                    cleanedTimestamp = getGameTime():getWorldAgeHours(),
                }

                if BurdJournals and BurdJournals.updateJournalName then
                    BurdJournals.updateJournalName(result)
                end
                if BurdJournals and BurdJournals.updateJournalIcon then
                    BurdJournals.updateJournalIcon(result)
                end
            end
        else
            -- Fallback: Initialize with random data
            BurdJournals_OnCreateFilledWorn(arg1, arg2, arg3, arg4)
        end
    end)

    if not ok then
        print("[BurdJournals] ERROR in OnCreateFilledWornFromBloody: " .. tostring(err))
    end
end

-- Convert Worn or Bloody Filled -> Clean Filled (preserves data)
-- Universal restore callback that handles both worn and bloody inputs
function BurdJournals_OnCreateFilledCleanFromWornOrBloody(arg1, arg2, arg3, arg4)
    local ok, err = pcall(function()
        local result, player, inputItems = getItemFromArgs(arg1, arg2, arg3, arg4)
        if not result then return end

        -- Find the worn or bloody journal in the input items
        local sourceJournal = nil
        if inputItems and inputItems.size then
            for i = 0, inputItems:size() - 1 do
                local item = inputItems:get(i)
                if item then
                    local itemType = item:getFullType()
                    if string.find(itemType, "FilledSurvivalJournal_Worn") or
                       string.find(itemType, "FilledSurvivalJournal_Bloody") then
                        sourceJournal = item
                        break
                    end
                end
            end
        end

        if sourceJournal then
            local sourceModData = sourceJournal:getModData()
            local journalData = sourceModData.BurdJournals
            local wasBloodySouce = string.find(sourceJournal:getFullType(), "_Bloody") ~= nil

            if journalData then
                local resultModData = result:getModData()
                resultModData.BurdJournals = {
                    uuid = journalData.uuid or safeGenerateUUID(),
                    author = journalData.author,
                    flavorText = journalData.flavorText,
                    timestamp = journalData.timestamp,
                    readCount = journalData.readCount or 0,
                    skills = journalData.skills or {},
                    traits = journalData.traits or {},
                    isWritten = true,
                    isWorn = false,
                    isBloody = false,
                    bloodyOrigin = wasBloodySouce or journalData.bloodyOrigin,
                    isPlayerCreated = journalData.isPlayerCreated,
                    claimedSkills = journalData.claimedSkills or {},
                    claimedTraits = journalData.claimedTraits or {},
                    wasRestored = true,
                    restoredBy = player and player:getUsername() or "Unknown",
                    restoredTimestamp = getGameTime():getWorldAgeHours(),
                }

                if BurdJournals and BurdJournals.updateJournalName then
                    BurdJournals.updateJournalName(result)
                end
                if BurdJournals and BurdJournals.updateJournalIcon then
                    BurdJournals.updateJournalIcon(result)
                end
            end
        else
            -- Fallback: Initialize as new clean filled journal
            local modData = result:getModData()
            modData.BurdJournals = {
                uuid = safeGenerateUUID(),
                isWritten = false,
                isWorn = false,
                isBloody = false,
                isPlayerCreated = true,
            }
        end
    end)

    if not ok then
        print("[BurdJournals] ERROR in OnCreateFilledCleanFromWornOrBloody: " .. tostring(err))
    end
end

-- Convert Bloody Filled -> Clean Filled directly (preserves data)
function BurdJournals_OnCreateFilledCleanFromBloody(arg1, arg2, arg3, arg4)
    local ok, err = pcall(function()
        local result, player, inputItems = getItemFromArgs(arg1, arg2, arg3, arg4)
        if not result then return end

        -- Find the bloody journal in the input items
        local bloodyJournal = nil
        if inputItems and inputItems.size then
            for i = 0, inputItems:size() - 1 do
                local item = inputItems:get(i)
                if item and string.find(item:getFullType(), "FilledSurvivalJournal_Bloody") then
                    bloodyJournal = item
                    break
                end
            end
        end

        if bloodyJournal then
            local bloodyModData = bloodyJournal:getModData()
            local journalData = bloodyModData.BurdJournals

            if journalData then
                local resultModData = result:getModData()
                resultModData.BurdJournals = {
                    uuid = journalData.uuid or safeGenerateUUID(),
                    author = journalData.author,
                    flavorText = journalData.flavorText,
                    timestamp = journalData.timestamp,
                    readCount = journalData.readCount or 0,
                    skills = journalData.skills or {},
                    traits = journalData.traits or {},
                    isWritten = true,
                    isWorn = false,
                    isBloody = false,
                    bloodyOrigin = true,
                    isPlayerCreated = false,
                    claimedSkills = journalData.claimedSkills or {},
                    claimedTraits = journalData.claimedTraits or {},
                    wasRestored = true,
                    wasCleaned = true,
                    restoredBy = player and player:getUsername() or "Unknown",
                    restoredTimestamp = getGameTime():getWorldAgeHours(),
                }

                if BurdJournals and BurdJournals.updateJournalName then
                    BurdJournals.updateJournalName(result)
                end
                if BurdJournals and BurdJournals.updateJournalIcon then
                    BurdJournals.updateJournalIcon(result)
                end
            end
        else
            -- Fallback: Initialize as new clean filled journal
            local modData = result:getModData()
            modData.BurdJournals = {
                uuid = safeGenerateUUID(),
                isWritten = false,
                isWorn = false,
                isBloody = false,
                isPlayerCreated = true,
            }
        end
    end)

    if not ok then
        print("[BurdJournals] ERROR in OnCreateFilledCleanFromBloody: " .. tostring(err))
    end
end
