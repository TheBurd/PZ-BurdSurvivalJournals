--[[
    Burd's Survival Journals - Recipe & OnCreate Callbacks
    Build 41
    
    Handles OnCreate callbacks for journal creation.
    
    IMPORTANT: OnCreate is called in TWO different contexts:
    1. Recipe crafting: (items, result, player, selectedItem) - result is the created item
    2. Loot spawning:   (item) - item is the created item directly
    
    Each callback must handle BOTH signatures to work with world loot spawns!
]]

require "BurdJournals_Shared"

BurdJournals = BurdJournals or {}
BurdJournals.Recipes = BurdJournals.Recipes or {}

-- ============================================================
--                    HELPER FUNCTION
-- ============================================================

-- Determine the actual item from either call signature:
-- Recipe:     (items, result, player, selectedItem) -> result is the item
-- Loot spawn: (item) -> first param is the item directly
--
-- IMPORTANT: For loot spawns, PZ passes ONLY the item as the first argument!
local function getItemFromArgs(arg1, arg2)
    -- If arg2 (result) exists AND it's an InventoryItem, this is a recipe call
    if arg2 and type(arg2) ~= "nil" then
        -- Verify arg2 is actually an item (has getModData)
        if arg2.getModData then
            return arg2
        end
    end
    -- Otherwise arg1 IS the item (loot spawn)
    -- Verify it's an item
    if arg1 and arg1.getModData then
        return arg1
    end
    -- Fallback: something went wrong
    return nil
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
function BurdJournals_OnCreateBlankClean(items, result, player, selectedItem)
    local item = getItemFromArgs(items, result)
    if not item then return end

    local modData = item:getModData()
    modData.BurdJournals = {
        uuid = BurdJournals.generateUUID(),
        condition = 10,
        isWorn = false,
        isBloody = false,
        isWritten = false,
        createdBy = player and player:getUsername() or "World",
        createdTimestamp = getGameTime():getWorldAgeHours()
    }

    BurdJournals.updateJournalName(item)
    BurdJournals.updateJournalIcon(item)

    if BurdJournals.isDebug() then
        -- Debug removed
    end
end

-- Worn Blank - Found in world containers
function BurdJournals_OnCreateBlankWorn(items, result, player, selectedItem)
    local item = getItemFromArgs(items, result)
    if not item then return end

    local modData = item:getModData()
    modData.BurdJournals = {
        uuid = BurdJournals.generateUUID(),
        condition = ZombRand(3, 7),
        isWorn = true,
        isBloody = false,
        isWritten = false,
        createdTimestamp = getGameTime():getWorldAgeHours()
    }

    BurdJournals.updateJournalName(item)
    BurdJournals.updateJournalIcon(item)

    if BurdJournals.isDebug() then
        -- Debug removed
    end
end

-- Bloody Blank - Found on zombie corpses
function BurdJournals_OnCreateBlankBloody(items, result, player, selectedItem)
    local item = getItemFromArgs(items, result)
    if not item then return end

    local modData = item:getModData()
    modData.BurdJournals = {
        uuid = BurdJournals.generateUUID(),
        condition = ZombRand(1, 5),
        isWorn = false,
        isBloody = true,
        isWritten = false,
        createdTimestamp = getGameTime():getWorldAgeHours()
    }

    BurdJournals.updateJournalName(item)
    BurdJournals.updateJournalIcon(item)

    if BurdJournals.isDebug() then
        -- Debug removed
    end
end

-- ============================================================
--                   FILLED JOURNAL CALLBACKS
-- ============================================================

-- Clean Filled - Player-created (SET mode) OR dev menu/loot spawned (found journal)
function BurdJournals_OnCreateFilledClean(items, result, player, selectedItem)
    local item = getItemFromArgs(items, result)
    if not item then return end

    local modData = item:getModData()

    -- If spawned with a player context (crafting), create a player journal
    -- If spawned without player (dev menu/loot), create a found journal with random survivor
    if player then
        -- Player-created journal (crafting)
        modData.BurdJournals = {
            uuid = BurdJournals.generateUUID(),
            condition = 10,
            isWorn = false,
            isBloody = false,
            isWritten = true,
            wasFromBloody = false,
            isPlayerCreated = true,
            author = player:getUsername(),
            timestamp = getGameTime():getWorldAgeHours(),
            readCount = 0,
            skills = BurdJournals.generateRandomSkills(2, 4, 50, 150),
            claimedSkills = {},
            claimedTraits = {}
        }
        if BurdJournals.isDebug() then
            -- Debug removed
        end
    else
        -- Loot/dev menu spawn - create as found journal with random survivor
        local survivorName = BurdJournals.generateRandomSurvivorName()
        modData.BurdJournals = {
            uuid = BurdJournals.generateUUID(),
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
            skills = BurdJournals.generateRandomSkills(2, 4, 50, 150),
            claimedSkills = {},
            claimedTraits = {}
        }
        if BurdJournals.isDebug() then
            -- Debug removed
        end
    end

    BurdJournals.updateJournalName(item)
    BurdJournals.updateJournalIcon(item)

    -- Sync modData to clients in multiplayer
    if isServer() and item.transmitModData then
        item:transmitModData()
    end
end

-- Worn Filled - Found in world containers, consumable (ADD mode, light rewards)
-- THIS IS THE PRIMARY CALLBACK FOR WORLD LOOT SPAWNS!
-- Wrapped in pcall to prevent errors from blocking item creation
function BurdJournals_OnCreateFilledWorn(items, result, player, selectedItem)
    -- ALWAYS log that we were called
    -- Debug removed
    
    local ok, err = pcall(function()
        local item = getItemFromArgs(items, result)
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
function BurdJournals_OnCreateFilledBloody(items, result, player, selectedItem)
    local item = getItemFromArgs(items, result)
    if not item then return end

    -- Debug removed

    -- Get sandbox settings for bloody journal rewards
    local minSkills = BurdJournals.getSandboxOption("BloodyJournalMinSkills") or 2
    local maxSkills = BurdJournals.getSandboxOption("BloodyJournalMaxSkills") or 4
    local minXP = BurdJournals.getSandboxOption("BloodyJournalMinXP") or 50
    local maxXP = BurdJournals.getSandboxOption("BloodyJournalMaxXP") or 150
    local traitChance = BurdJournals.getSandboxOption("BloodyJournalTraitChance") or 15

    -- Get random profession for the previous owner (with fallback)
    local professionId, professionName = "unemployed", "Survivor"
    if BurdJournals.WorldSpawn and BurdJournals.WorldSpawn.getRandomProfession then
        professionId, professionName = BurdJournals.WorldSpawn.getRandomProfession()
    end

    -- Generate traits if lucky (1-4 random traits)
    local traits = {}
    if ZombRand(100) < traitChance then
        local grantableTraits = BurdJournals.GRANTABLE_TRAITS or {
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
        uuid = BurdJournals.generateUUID(),
        condition = ZombRand(1, 4),
        isWorn = false,
        isBloody = true,
        isWritten = true,
        wasFromBloody = true,
        isPlayerCreated = false,
        author = BurdJournals.generateRandomSurvivorName(),
        profession = professionId,
        professionName = professionName,
        timestamp = getGameTime():getWorldAgeHours() - ZombRand(24, 720),
        readCount = 0,
        skills = BurdJournals.generateRandomSkills(minSkills, maxSkills, minXP, maxXP),
        traits = traits,
        claimedSkills = {},
        claimedTraits = {}
    }

    BurdJournals.updateJournalName(item)
    BurdJournals.updateJournalIcon(item)

    -- Sync modData to clients in multiplayer
    if isServer() and item.transmitModData then
        item:transmitModData()
    end

    local traitCount = 0
    for _ in pairs(traits) do traitCount = traitCount + 1 end
end

-- ============================================================
--                    LEGACY/RECIPE CALLBACKS
-- ============================================================

-- Legacy callback for crafting recipes (alias to clean blank)
function BurdJournals_OnCreateBlankJournal(items, result, player, selectedItem)
    BurdJournals_OnCreateBlankClean(items, result, player, selectedItem)
end

-- Called when a worn journal is cleaned/repaired (RECIPE ONLY - not loot spawn)
-- This callback uses the recipe signature since it requires input items
function BurdJournals_OnCleanWornJournal(items, result, player, selectedItem)
    -- This is always a recipe context, so result is the created item
    if not result then return end
    
    local wornJournal = nil
    if items and items.size then
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item and BurdJournals.isWorn(item) then
                wornJournal = item
                break
            end
        end
    end
    
    if not wornJournal and selectedItem and BurdJournals.isWorn(selectedItem) then
        wornJournal = selectedItem
    end
    
    if not wornJournal then
        return
    end
    
    local wornModData = wornJournal:getModData()
    local journalData = wornModData.BurdJournals
    
    if journalData then
        local resultModData = result:getModData()
        resultModData.BurdJournals = {
            uuid = BurdJournals.generateUUID(),
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
        
        BurdJournals.updateJournalName(result)
        BurdJournals.updateJournalIcon(result)
        
        if BurdJournals.isDebug() then
            local authorName = journalData.author or "Unknown Survivor"
            -- Debug removed .. " cleaned journal from " .. authorName)
        end
    end
end

-- ============================================================
--                   CLEANING CALLBACKS
-- ============================================================

-- ============================================================
--           FILLED JOURNAL CONVERSION CALLBACKS
-- ============================================================

-- Convert Worn Filled Ã¢â€ â€™ Clean Filled (preserves data)
function BurdJournals_OnCreateFilledCleanFromWorn(items, result, player, selectedItem)
    if not result then return end
    
    -- Find the worn journal in the input items
    local wornJournal = nil
    if items and items.size then
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item and string.find(item:getFullType(), "FilledSurvivalJournal_Worn") then
                wornJournal = item
                break
            end
        end
    end
    
    if not wornJournal and selectedItem then
        wornJournal = selectedItem
    end
    
    if wornJournal then
        local wornModData = wornJournal:getModData()
        local journalData = wornModData.BurdJournals
        
        if journalData then
            local resultModData = result:getModData()
            resultModData.BurdJournals = {
                uuid = journalData.uuid or BurdJournals.generateUUID(),
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
            
            BurdJournals.updateJournalName(result)
            BurdJournals.updateJournalIcon(result)
            -- Debug removed
        end
    else
        -- Fallback: Initialize as new clean filled journal
        local modData = result:getModData()
        modData.BurdJournals = {
            uuid = BurdJournals.generateUUID(),
            isWritten = false,
            isWorn = false,
            isBloody = false,
            isPlayerCreated = true,
        }
    end
end

-- Convert Bloody Filled Ã¢â€ â€™ Worn Filled (preserves data)
function BurdJournals_OnCreateFilledWornFromBloody(items, result, player, selectedItem)
    if not result then return end
    
    -- Find the bloody journal in the input items
    local bloodyJournal = nil
    if items and items.size then
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item and string.find(item:getFullType(), "FilledSurvivalJournal_Bloody") then
                bloodyJournal = item
                break
            end
        end
    end
    
    if not bloodyJournal and selectedItem then
        bloodyJournal = selectedItem
    end
    
    if bloodyJournal then
        local bloodyModData = bloodyJournal:getModData()
        local journalData = bloodyModData.BurdJournals
        
        if journalData then
            local resultModData = result:getModData()
            resultModData.BurdJournals = {
                uuid = journalData.uuid or BurdJournals.generateUUID(),
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
            
            BurdJournals.updateJournalName(result)
            BurdJournals.updateJournalIcon(result)
            -- Debug removed
        end
    else
        -- Fallback: Initialize with random data
        BurdJournals_OnCreateFilledWorn(items, result, player, selectedItem)
    end
end

-- Convert Worn or Bloody Filled -> Clean Filled (preserves data)
-- Universal restore callback that handles both worn and bloody inputs
function BurdJournals_OnCreateFilledCleanFromWornOrBloody(items, result, player, selectedItem)
    if not result then return end

    -- Find the worn or bloody journal in the input items
    local sourceJournal = nil
    if items and items.size then
        for i = 0, items:size() - 1 do
            local item = items:get(i)
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

    if not sourceJournal and selectedItem then
        sourceJournal = selectedItem
    end

    if sourceJournal then
        local sourceModData = sourceJournal:getModData()
        local journalData = sourceModData.BurdJournals
        local wasBloodySouce = string.find(sourceJournal:getFullType(), "_Bloody") ~= nil

        if journalData then
            local resultModData = result:getModData()
            resultModData.BurdJournals = {
                uuid = journalData.uuid or BurdJournals.generateUUID(),
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

            BurdJournals.updateJournalName(result)
            BurdJournals.updateJournalIcon(result)
        end
    else
        -- Fallback: Initialize as new clean filled journal
        local modData = result:getModData()
        modData.BurdJournals = {
            uuid = BurdJournals.generateUUID(),
            isWritten = false,
            isWorn = false,
            isBloody = false,
            isPlayerCreated = true,
        }
    end
end

-- Convert Bloody Filled -> Clean Filled directly (preserves data)
function BurdJournals_OnCreateFilledCleanFromBloody(items, result, player, selectedItem)
    if not result then return end

    -- Find the bloody journal in the input items
    local bloodyJournal = nil
    if items and items.size then
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item and string.find(item:getFullType(), "FilledSurvivalJournal_Bloody") then
                bloodyJournal = item
                break
            end
        end
    end

    if not bloodyJournal and selectedItem then
        bloodyJournal = selectedItem
    end

    if bloodyJournal then
        local bloodyModData = bloodyJournal:getModData()
        local journalData = bloodyModData.BurdJournals

        if journalData then
            local resultModData = result:getModData()
            resultModData.BurdJournals = {
                uuid = journalData.uuid or BurdJournals.generateUUID(),
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

            BurdJournals.updateJournalName(result)
            BurdJournals.updateJournalIcon(result)
        end
    else
        -- Fallback: Initialize as new clean filled journal
        local modData = result:getModData()
        modData.BurdJournals = {
            uuid = BurdJournals.generateUUID(),
            isWritten = false,
            isWorn = false,
            isBloody = false,
            isPlayerCreated = true,
        }
    end
end



