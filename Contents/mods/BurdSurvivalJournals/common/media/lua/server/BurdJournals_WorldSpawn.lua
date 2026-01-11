--[[
    Burd's Survival Journals - World & Dev Menu Spawns
    Build 42 - Version 2.0

    Handles journal initialization for:
    1. World container spawns (LoadGridsquare) - Worn journals
    2. Zombie loot drops - Bloody journals (handled in ZombieLoot.lua)
    3. Dev menu spawning - All journal types

    Worn journals (world containers):
    - 1-2 skills, 25-75 XP each
    - XP ADDING mode (consumable)

    Bloody journals (zombie corpses):
    - 2-4 skills, 50-150 XP each
    - Rare trait chance (15%)
    - XP ADDING mode (consumable)
]]

require "BurdJournals_Shared"

-- ==================== LOOT DISTRIBUTION SETUP ====================
-- This adds worn journals to world container spawn tables.
-- We try both immediate execution AND event-based for maximum compatibility.

-- Debug removed
-- Debug removed
-- Debug removed

-- Check what events are available
if Events then
    -- Debug removed
    if Events.OnFillContainer then
        -- Debug removed
    else
    end
else
end

-- Distribution configuration (kept for reference but not used - we use OnFillContainer now)
local DISTRIBUTION_LIST = {
    -- Bookstores (high chance)
    {"BookstoreBooks", 3}, {"BookstorePersonal", 2.5}, {"BookstoreMisc", 2},
    {"BookstoreStationery", 2}, {"BookStoreCounter", 1.5}, {"BookstoreHobbies", 1.5},
    {"BookstoreOutdoors", 1.5}, {"BookstoreCrafts", 1.5}, {"BookstoreFarming", 1.5},
    -- Libraries
    {"LibraryBooks", 3}, {"LibraryCounter", 2}, {"LibraryMagazines", 1.5},
    {"LibraryPersonal", 2}, {"LibraryOutdoors", 1.5},
    -- Crates
    {"CrateBooks", 2.5}, {"CrateBooksSchool", 2},
    -- Post Office
    {"PostOfficeBooks", 2}, {"PostOfficeMagazines", 1},
    -- Camping
    {"CampingStoreBooks", 2},
    -- Safehouse
    {"SafehouseBookShelf", 3},
    -- Magazine Racks
    {"MagazineRackMixed", 1}, {"MagazineRackPaperback", 1.5},
    -- Schools
    {"SchoolDesk", 1.5}, {"SchoolLockers", 0.8},
    -- Offices
    {"OfficeDesk", 1}, {"OfficeDeskHome", 1}, {"OfficeDeskHomeClassy", 1.2},
    {"OfficeDrawers", 0.8},
    -- Generic
    {"BookShelf", 2}, {"ShelfGeneric", 1}, {"Desk", 1}, {"DeskGeneric", 1},
    {"FilingCabinet", 0.8}, {"ClosetShelfGeneric", 0.5},
    -- Residential
    {"BedroomDresser", 0.3}, {"BedroomDresserClassy", 0.5},
    {"BedroomSidetable", 0.6}, {"BedroomSidetableClassy", 0.8},
    {"Nightstand", 0.5}, {"Dresser", 0.3}, {"EndTable", 0.4},
    -- Motel
    {"MotelSideTable", 0.6},
}

local distributionsInitialized = false

-- ==================== DYNAMIC CONTAINER SPAWNING ====================
-- Instead of modifying ProceduralDistributions (which ignores sandbox settings),
-- we hook into OnFillContainer to dynamically add journals based on sandbox options.
-- This is the same approach used for bloody journals on zombie corpses.

-- Container types that can spawn worn journals (with base weight for spawn chance scaling)
local CONTAINER_SPAWN_WEIGHTS = {
    -- High chance containers (books/literature)
    ["BookstoreBooks"] = 3.0,
    ["BookstorePersonal"] = 2.5,
    ["BookstoreMisc"] = 2.0,
    ["LibraryBooks"] = 3.0,
    ["LibraryCounter"] = 2.0,
    ["CrateBooks"] = 2.5,
    ["SafehouseBookShelf"] = 3.0,
    ["BookShelf"] = 2.0,
    -- Medium chance containers
    ["SchoolDesk"] = 1.5,
    ["OfficeDesk"] = 1.0,
    ["OfficeDeskHome"] = 1.0,
    ["Desk"] = 1.0,
    ["DeskGeneric"] = 1.0,
    ["FilingCabinet"] = 0.8,
    -- Low chance residential containers
    ["BedroomDresser"] = 0.3,
    ["BedroomSidetable"] = 0.6,
    ["Nightstand"] = 0.5,
    ["Dresser"] = 0.3,
    ["EndTable"] = 0.4,
    ["MotelSideTable"] = 0.6,
    ["ClosetShelfGeneric"] = 0.5,
    ["ShelfGeneric"] = 0.5,
}

-- Track containers we've already processed (to avoid duplicates on save/load)
local processedContainers = {}

-- Clean up tracking periodically to avoid memory buildup
local lastCleanup = 0
local CLEANUP_INTERVAL = 300000 -- 5 minutes in milliseconds

local function cleanupTracking()
    local now = getTimestampMs and getTimestampMs() or 0
    if now - lastCleanup > CLEANUP_INTERVAL then
        processedContainers = {}
        lastCleanup = now
    end
end

-- Generate a unique ID for a container
local function getContainerKey(container)
    if not container then return nil end
    local parent = container:getParent()
    if parent and parent:getSquare() then
        local sq = parent:getSquare()
        return string.format("%d_%d_%d_%s", sq:getX(), sq:getY(), sq:getZ(), tostring(container:getType()))
    end
    return nil
end

-- OnFillContainer event handler - dynamically spawn worn journals
local function onFillContainer(roomName, containerType, itemContainer)
    -- Only run on server in multiplayer
    if isClient() and not isServer() then return end
    
    -- Check if mod is enabled
    if not BurdJournals.isEnabled() then return end
    
    -- Check if worn journal spawns are enabled
    local spawnsEnabled = BurdJournals.getSandboxOption("EnableWornJournalSpawns")
    if spawnsEnabled == false then return end
    
    -- Check if this container type can spawn journals
    local baseWeight = CONTAINER_SPAWN_WEIGHTS[containerType]
    if not baseWeight then return end
    
    -- Avoid processing the same container twice
    local containerKey = getContainerKey(itemContainer)
    if containerKey then
        if processedContainers[containerKey] then
            return
        end
        processedContainers[containerKey] = true
    end
    
    -- Clean up tracking periodically
    cleanupTracking()
    
    -- Get spawn chance from sandbox (0.1 to 100.0, default 2.0)
    local spawnChance = BurdJournals.getSandboxOption("WornJournalSpawnChance") or 2.0
    
    -- Calculate final spawn chance: (sandbox % * base weight) / 100
    -- Example: 2% sandbox * 3.0 weight = 6% chance for BookstoreBooks
    local finalChance = (spawnChance * baseWeight) / 100.0
    
    -- Roll for spawn
    local roll = ZombRandFloat(0, 1)
    if roll > finalChance then
        return -- No spawn this time
    end
    
    -- Spawn a worn journal!
    -- Debug removed
    
    local journal = itemContainer:AddItem("BurdJournals.FilledSurvivalJournal_Worn")
    if journal then
        -- The OnCreate callback should handle initialization, but let's make sure
        local modData = journal:getModData()
        if not modData.BurdJournals or not modData.BurdJournals.skills then
            -- Initialize if OnCreate didn't run
            BurdJournals.WorldSpawn.initializeJournalIfNeeded(journal)
        end
        
        if BurdJournals.isDebug() then
            local data = modData.BurdJournals
            -- Debug removed)
        end
    end
end

-- Register the OnFillContainer event
if Events and Events.OnFillContainer then
    Events.OnFillContainer.Add(onFillContainer)
    -- Debug removed
end

-- ==================== END DISTRIBUTION SETUP ====================

BurdJournals = BurdJournals or {}
BurdJournals.WorldSpawn = BurdJournals.WorldSpawn or {}

-- ==================== META SURVIVOR NAMES ====================

BurdJournals.WorldSpawn.SurvivorNames = {
    -- Generic survivor names
    "John", "Jane", "Mike", "Sarah", "David", "Lisa", "Tom", "Emily",
    "Chris", "Amanda", "James", "Jennifer", "Robert", "Michelle", "William", "Jessica",
    "Daniel", "Ashley", "Matthew", "Stephanie", "Anthony", "Nicole", "Mark", "Elizabeth",
    -- More thematic names
    "Doc", "Sarge", "Coach", "Chief", "Gramps", "Pops", "Red",
    "Lucky", "Ace", "Shadow", "Ghost", "Hawk", "Wolf", "Bear", "Fox",
}

-- ==================== PROFESSIONS FOR RANDOM JOURNALS ====================

-- Profession IDs and their display names for random journal generation
BurdJournals.WorldSpawn.Professions = {
    {id = "fireofficer", name = "Fire Officer"},
    {id = "policeofficer", name = "Police Officer"},
    {id = "parkranger", name = "Park Ranger"},
    {id = "constructionworker", name = "Construction Worker"},
    {id = "securityguard", name = "Security Guard"},
    {id = "carpenter", name = "Carpenter"},
    {id = "burglar", name = "Burglar"},
    {id = "chef", name = "Chef"},
    {id = "repairman", name = "Repairman"},
    {id = "farmer", name = "Farmer"},
    {id = "fisherman", name = "Fisherman"},
    {id = "doctor", name = "Doctor"},
    {id = "nurse", name = "Nurse"},
    {id = "lumberjack", name = "Lumberjack"},
    {id = "fitnessInstructor", name = "Fitness Instructor"},
    {id = "burgerflipper", name = "Burger Flipper"},
    {id = "electrician", name = "Electrician"},
    {id = "engineer", name = "Engineer"},
    {id = "metalworker", name = "Metalworker"},
    {id = "mechanics", name = "Mechanic"},
    {id = "veteran", name = "Veteran"},
    {id = "unemployed", name = "Unemployed"},
}

-- Get a random profession
function BurdJournals.WorldSpawn.getRandomProfession()
    local professions = BurdJournals.WorldSpawn.Professions
    local prof = professions[ZombRand(#professions) + 1]
    return prof.id, prof.name
end

-- ==================== GENERATE WORN JOURNAL DATA ====================

function BurdJournals.WorldSpawn.generateWornJournalData()
    local survivorName = BurdJournals.WorldSpawn.SurvivorNames[ZombRand(#BurdJournals.WorldSpawn.SurvivorNames) + 1]
    local professionId, professionName = BurdJournals.WorldSpawn.getRandomProfession()

    -- Get sandbox settings for worn journals (light rewards)
    local minXP = BurdJournals.getSandboxOption("WornJournalMinXP") or 25
    local maxXP = BurdJournals.getSandboxOption("WornJournalMaxXP") or 75
    local minSkills = BurdJournals.getSandboxOption("WornJournalMinSkills") or 1
    local maxSkills = BurdJournals.getSandboxOption("WornJournalMaxSkills") or 2

    -- Determine number of skills (light: 1-2)
    local numSkills = ZombRand(minSkills, maxSkills + 1)

    -- Get all skills (uses dynamic discovery to include mod-added skills) and shuffle
    local availableSkills = {}
    local allSkills = BurdJournals.getAllowedSkills()
    for _, skill in ipairs(allSkills) do
        table.insert(availableSkills, skill)
    end

    if #availableSkills == 0 then
        return nil
    end

    -- Shuffle skills
    for i = #availableSkills, 2, -1 do
        local j = ZombRand(i) + 1
        availableSkills[i], availableSkills[j] = availableSkills[j], availableSkills[i]
    end

    -- Build skills table with light XP values
    local skills = {}
    for i = 1, math.min(numSkills, #availableSkills) do
        local skillName = availableSkills[i]
        -- Each skill gets its own random XP in the light range
        local skillXP = ZombRand(minXP, maxXP + 1)

        -- Calculate approximate level from XP
        local level = 0
        local xpThresholds = {0, 75, 150, 300, 750, 1500, 3000, 4500, 6000, 7500, 9000}
        for lvl = 10, 0, -1 do
            if skillXP >= (xpThresholds[lvl + 1] or 0) then
                level = lvl
                break
            end
        end

        skills[skillName] = {
            xp = skillXP,
            level = level
        }
    end

    -- Build journal data structure
    local journalData = {
        uuid = BurdJournals.generateUUID(),
        author = survivorName,
        profession = professionId,
        professionName = professionName,
        timestamp = getGameTime():getWorldAgeHours() - ZombRand(24, 720),
        skills = skills,
        -- Worn journal state
        isWorn = true,
        isBloody = false,
        wasFromBloody = false, -- World-found worn, NOT from bloody
        isPlayerCreated = false,
        -- No traits for world-found worn journals
        traits = nil,
        -- Claim tracking (starts empty)
        claimedSkills = {},
        claimedTraits = {},
    }

    return journalData
end

-- ==================== GENERATE BLOODY JOURNAL DATA ====================

function BurdJournals.WorldSpawn.generateBloodyJournalData()
    local survivorName = BurdJournals.generateRandomSurvivorName()
    local professionId, professionName = BurdJournals.WorldSpawn.getRandomProfession()

    -- Get sandbox settings for bloody journals (better rewards)
    local minXP = BurdJournals.getSandboxOption("BloodyJournalMinXP") or 50
    local maxXP = BurdJournals.getSandboxOption("BloodyJournalMaxXP") or 150
    local minSkills = BurdJournals.getSandboxOption("BloodyJournalMinSkills") or 2
    local maxSkills = BurdJournals.getSandboxOption("BloodyJournalMaxSkills") or 4
    local traitChance = BurdJournals.getSandboxOption("BloodyJournalTraitChance") or 15

    -- Determine number of skills (better: 2-4)
    local numSkills = ZombRand(minSkills, maxSkills + 1)

    -- Get all skills (uses dynamic discovery to include mod-added skills) and shuffle
    local availableSkills = {}
    local allSkills = BurdJournals.getAllowedSkills()
    for _, skill in ipairs(allSkills) do
        table.insert(availableSkills, skill)
    end

    if #availableSkills == 0 then
        return nil
    end

    -- Shuffle skills
    for i = #availableSkills, 2, -1 do
        local j = ZombRand(i) + 1
        availableSkills[i], availableSkills[j] = availableSkills[j], availableSkills[i]
    end

    -- Build skills table with higher XP values
    local skills = {}
    for i = 1, math.min(numSkills, #availableSkills) do
        local skillName = availableSkills[i]
        local skillXP = ZombRand(minXP, maxXP + 1)

        -- Calculate approximate level from XP
        local level = 0
        local xpThresholds = {0, 75, 150, 300, 750, 1500, 3000, 4500, 6000, 7500, 9000}
        for lvl = 10, 0, -1 do
            if skillXP >= (xpThresholds[lvl + 1] or 0) then
                level = lvl
                break
            end
        end

        skills[skillName] = {
            xp = skillXP,
            level = level
        }
    end

    -- Generate traits if lucky (1 to maxTraits random traits)
    local traits = {}
    if ZombRand(100) < traitChance then
        local grantableTraits = (BurdJournals.getGrantableTraits and BurdJournals.getGrantableTraits()) or BurdJournals.GRANTABLE_TRAITS or {}
        if #grantableTraits > 0 then
            -- Generate 1 to maxTraits random unique traits (respecting sandbox setting)
            local maxTraits = SandboxVars.BurdJournals and SandboxVars.BurdJournals.BloodyJournalMaxTraits or 2
            local numTraits = ZombRand(1, maxTraits + 1)  -- 1 to maxTraits
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

    -- Build journal data structure
    local journalData = {
        uuid = BurdJournals.generateUUID(),
        author = survivorName,
        profession = professionId,
        professionName = professionName,
        timestamp = getGameTime():getWorldAgeHours() - ZombRand(24, 720),
        skills = skills,
        traits = traits,
        -- Bloody journal state
        isWorn = false,
        isBloody = true,
        wasFromBloody = true,
        isPlayerCreated = false,
        condition = ZombRand(1, 4),
        -- Claim tracking (starts empty)
        claimedSkills = {},
        claimedTraits = {},
    }

    return journalData
end

-- ==================== ITEM INITIALIZATION ====================

-- Initialize a journal if it doesn't have modData yet
-- This handles dev menu spawning and any other case where OnCreate didn't run
function BurdJournals.WorldSpawn.initializeJournalIfNeeded(item)
    if not item then return false end

    local fullType = item:getFullType()
    local modData = item:getModData()

    -- Skip if already has BurdJournals data (check for uuid OR skills OR any key)
    -- This prevents overwriting existing data when reloading saves
    if modData.BurdJournals then
        -- Check if it has any meaningful data
        local hasData = modData.BurdJournals.uuid or
                        modData.BurdJournals.skills or
                        modData.BurdJournals.author or
                        modData.BurdJournals.isWritten ~= nil
        if hasData then
            -- Add UUID if missing (migrate old journals)
            if not modData.BurdJournals.uuid then
                modData.BurdJournals.uuid = BurdJournals.generateUUID()
                -- Debug removed
                if item.transmitModData then
                    item:transmitModData()
                end
            end
            return false
        end
    end

    local journalData = nil

    -- Handle each journal type
    if fullType == "BurdJournals.FilledSurvivalJournal_Worn" then
        journalData = BurdJournals.WorldSpawn.generateWornJournalData()
        if BurdJournals.isDebug() then
            -- Debug removed
        end

    elseif fullType == "BurdJournals.FilledSurvivalJournal_Bloody" then
        journalData = BurdJournals.WorldSpawn.generateBloodyJournalData()
        if BurdJournals.isDebug() then
            -- Debug removed
        end

    elseif fullType == "BurdJournals.FilledSurvivalJournal" then
        -- Clean filled journal - generate as a "restored" found journal for dev testing
        -- Use profession-based name like worn/bloody journals
        local survivorName = BurdJournals.WorldSpawn.SurvivorNames[ZombRand(#BurdJournals.WorldSpawn.SurvivorNames) + 1]
        journalData = {
            uuid = BurdJournals.generateUUID(),
            author = survivorName,
            timestamp = getGameTime():getWorldAgeHours() - ZombRand(24, 720),
            skills = BurdJournals.generateRandomSkills(2, 4, 50, 150),
            traits = {},
            isWorn = false,
            isBloody = false,
            wasFromBloody = false,
            wasRestored = true,  -- Indicate this was a restored journal
            isPlayerCreated = false,  -- NOT a player journal - it's a found journal
            condition = 10,
            claimedSkills = {},
            claimedTraits = {},
        }
        if BurdJournals.isDebug() then
            -- Debug removed
        end

    elseif fullType == "BurdJournals.BlankSurvivalJournal" then
        journalData = {
            uuid = BurdJournals.generateUUID(),
            condition = 10,
            isWorn = false,
            isBloody = false,
            isWritten = false,
        }

    elseif fullType == "BurdJournals.BlankSurvivalJournal_Worn" then
        journalData = {
            uuid = BurdJournals.generateUUID(),
            condition = ZombRand(3, 7),
            isWorn = true,
            isBloody = false,
            isWritten = false,
        }

    elseif fullType == "BurdJournals.BlankSurvivalJournal_Bloody" then
        journalData = {
            uuid = BurdJournals.generateUUID(),
            condition = ZombRand(1, 4),
            isWorn = false,
            isBloody = true,
            isWritten = false,
        }
    end

    if journalData then
        modData.BurdJournals = journalData
        BurdJournals.updateJournalName(item)
        BurdJournals.updateJournalIcon(item)

        -- Sync modData to clients in multiplayer
        if isServer() and item.transmitModData then
            item:transmitModData()
        end

        return true
    end

    return false
end

function BurdJournals.WorldSpawn.onItemCreated(item)
    if not item then return end
    if not BurdJournals.isEnabled() then return end

    -- Use the unified initialization function
    BurdJournals.WorldSpawn.initializeJournalIfNeeded(item)
end

-- ==================== EVENT HOOKS ====================

-- Helper to check if item is a journal that needs initialization
local function isUninitializedJournal(item)
    if not item then return false end
    local fullType = item:getFullType()
    if not fullType then return false end

    -- Check if it's a BurdJournals item
    if not fullType:find("^BurdJournals%.") then
        return false
    end

    -- Check if it's a filled journal that needs skills data
    if fullType:find("FilledSurvivalJournal") then
        local modData = item:getModData()
        -- Needs init if no BurdJournals data OR no skills table
        return not modData.BurdJournals or not modData.BurdJournals.skills
    end

    -- Blank journals just need basic state
    if fullType:find("BlankSurvivalJournal") then
        local modData = item:getModData()
        return not modData.BurdJournals
    end

    return false
end

-- Safely get items from a container, handling various container types
local function safeGetContainerItems(container)
    if not container then return nil end

    -- Check if this is an actual ItemContainer (has getItems method that works)
    -- Use instanceof to filter out IsoDeadBody and other non-container objects
    if instanceof(container, "ItemContainer") then
        local items = container:getItems()
        return items
    end

    -- If it's an IsoObject with a container (like IsoDeadBody), get the actual container first
    if container.getContainer then
        local actualContainer = container:getContainer()
        if actualContainer and instanceof(actualContainer, "ItemContainer") then
            local items = actualContainer:getItems()
            return items
        end
    end

    return nil
end

-- Hook into LoadGridsquare to initialize items in world containers
-- Only runs on server in multiplayer
Events.LoadGridsquare.Add(function(square)
    -- Only run on server
    if isClient() and not isServer() then return end

    if not square then return end
    if not BurdJournals.isEnabled() then return end

    local objects = square:getObjects()
    if not objects then return end

    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if obj then
            local container = obj:getContainer()
            if container then
                local items = safeGetContainerItems(container)
                if items then
                    for j = 0, items:size() - 1 do
                        local item = items:get(j)
                        if isUninitializedJournal(item) then
                            BurdJournals.WorldSpawn.initializeJournalIfNeeded(item)
                        end
                    end
                end
            end
        end
    end
end)

-- Hook into OnPlayerUpdate to catch dev menu spawned items in player inventory
-- This is a lightweight check that only scans when needed
local lastInventoryCheck = {}

local function checkPlayerInventory(player)
    if not player then return end
    if not BurdJournals.isEnabled() then return end

    local inventory = player:getInventory()
    if not inventory then return end

    -- Safely get all items - getAllRecursive might not exist in all contexts
    local allItems = nil
    local success = pcall(function()
        if inventory.getAllRecursive then
            allItems = inventory:getAllRecursive()
        elseif inventory.getItems then
            allItems = inventory:getItems()
        end
    end)

    if not success or not allItems then return end

    -- Check all items
    for i = 0, allItems:size() - 1 do
        local item = allItems:get(i)
        if isUninitializedJournal(item) then
            BurdJournals.WorldSpawn.initializeJournalIfNeeded(item)
        end
    end
end

-- Check player inventory periodically (every 2 seconds in game time)
-- Only runs on server in multiplayer
Events.OnPlayerUpdate.Add(function(player)
    -- Only run on server
    if isClient() and not isServer() then return end

    if not player then return end
    local playerId = player:getOnlineID() or 0

    -- Throttle checks to every 120 ticks (~2 seconds)
    local tick = getTimestamp and getTimestamp() or 0
    if lastInventoryCheck[playerId] and (tick - lastInventoryCheck[playerId]) < 2000 then
        return
    end
    lastInventoryCheck[playerId] = tick

    checkPlayerInventory(player)
end)

-- Also hook into inventory transfer events for immediate initialization
-- Only runs on server in multiplayer
if Events.OnContainerUpdate then
    Events.OnContainerUpdate.Add(function(container)
        -- Only run on server
        if isClient() and not isServer() then return end

        if not container then return end
        if not BurdJournals.isEnabled() then return end

        -- Safely get items - OnContainerUpdate can receive IsoDeadBody or other objects
        -- not just ItemContainer, so we need to handle this carefully
        local items = safeGetContainerItems(container)
        if not items then return end

        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if isUninitializedJournal(item) then
                BurdJournals.WorldSpawn.initializeJournalIfNeeded(item)
            end
        end
    end)
end



