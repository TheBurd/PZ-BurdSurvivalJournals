--[[
    Burd's Survival Journals - Zombie Corpse Loot & World Spawns
    Build 41 - Version 2.0
    
    Handles:
    1. Bloody journal spawns on zombie corpses (OnZombieDead)
    2. Worn journal spawns in world containers (OnFillContainer)
    
    Bloody journals (zombie corpses):
    - 2-4 skills, 50-150 XP each
    - Rare trait chance (15%)
    - Must be cleaned before use
    
    Worn journals (world containers):
    - 1-2 skills, 25-75 XP each
    - Ready to use immediately
]]

require "BurdJournals_Shared"

BurdJournals = BurdJournals or {}
BurdJournals.ZombieLoot = BurdJournals.ZombieLoot or {}

-- ==================== ZOMBIE PROFESSIONS ====================

BurdJournals.ZombieLoot.Professions = {
    {
        name = "Former Farmer",
        skills = {"Farming", "Cooking", "Foraging", "Trapping"},
        flavorText = "Notes scrawled by a farmer before the outbreak."
    },
    {
        name = "Former Mechanic",
        skills = {"Mechanics", "Electricity", "MetalWelding"},
        flavorText = "Grease-stained pages from a mechanic's workbook."
    },
    {
        name = "Former Doctor",
        skills = {"Doctor", "Cooking"},
        flavorText = "Medical notes written in precise handwriting."
    },
    {
        name = "Former Carpenter",
        skills = {"Carpentry", "Maintenance"},
        flavorText = "Woodworking tips from someone who knew their craft."
    },
    {
        name = "Former Hunter",
        skills = {"Aiming", "Reloading", "Sneak", "Trapping", "Foraging"},
        flavorText = "A hunter's journal, worn from the wilderness."
    },
    {
        name = "Former Soldier",
        skills = {"Aiming", "Reloading", "Fitness", "Strength", "Sneak"},
        flavorText = "Military field notes, discipline evident in every line."
    },
    {
        name = "Former Chef",
        skills = {"Cooking", "Farming", "Foraging"},
        flavorText = "Recipes and cooking tips from a professional kitchen."
    },
    {
        name = "Former Athlete",
        skills = {"Fitness", "Strength", "Sprinting", "Nimble"},
        flavorText = "Training notes from someone who pushed their limits."
    },
    {
        name = "Former Burglar",
        skills = {"Lightfoot", "Sneak", "Nimble", "SmallBlade"},
        flavorText = "Cryptic notes on moving unseen..."
    },
    {
        name = "Former Lumberjack",
        skills = {"Axe", "Strength", "Fitness", "Carpentry"},
        flavorText = "Rough notes from someone used to hard labor."
    },
    {
        name = "Former Fisherman",
        skills = {"Fishing", "Cooking", "Trapping"},
        flavorText = "Water-stained pages with fishing secrets."
    },
    {
        name = "Former Tailor",
        skills = {"Tailoring"},
        flavorText = "Neat stitching diagrams and fabric notes."
    },
    {
        name = "Former Electrician",
        skills = {"Electricity", "Mechanics"},
        flavorText = "Wiring diagrams and electrical safety tips."
    },
    {
        name = "Former Metalworker",
        skills = {"MetalWelding", "Mechanics", "Strength"},
        flavorText = "Notes on welding and metalcraft."
    },
    {
        name = "Former Survivalist",
        skills = {"Foraging", "Trapping", "Fishing", "Carpentry", "Farming"},
        flavorText = "Detailed survival strategies from a prepared mind."
    },
    {
        name = "Former Fighter",
        skills = {"Axe", "Blunt", "SmallBlunt", "LongBlade", "SmallBlade", "Spear", "Maintenance"},
        flavorText = "Combat techniques scribbled in a tattered notebook."
    },
}

-- ==================== GENERATE BLOODY JOURNAL DATA ====================

function BurdJournals.ZombieLoot.generateBloodyJournalData()
    -- Pick random profession for thematic skills
    local profession = BurdJournals.ZombieLoot.Professions[ZombRand(#BurdJournals.ZombieLoot.Professions) + 1]

    -- Generate a random survivor name for the author
    local survivorName = BurdJournals.generateRandomSurvivorName()

    -- Get sandbox settings for bloody journals (better rewards)
    local minXP = BurdJournals.getSandboxOption("BloodyJournalMinXP") or 50
    local maxXP = BurdJournals.getSandboxOption("BloodyJournalMaxXP") or 150
    local minSkills = BurdJournals.getSandboxOption("BloodyJournalMinSkills") or 2
    local maxSkills = BurdJournals.getSandboxOption("BloodyJournalMaxSkills") or 4
    local traitChance = BurdJournals.getSandboxOption("BloodyJournalTraitChance") or 15

    -- Determine number of skills
    local numSkills = ZombRand(minSkills, maxSkills + 1)

    -- Build available skills from profession first (thematic skills)
    local availableSkills = {}
    local usedSkills = {}
    for _, skill in ipairs(profession.skills) do
        table.insert(availableSkills, skill)
        usedSkills[skill] = true
    end

    -- If profession has fewer skills than needed, fill with random skills from ALL_SKILLS
    if #availableSkills < numSkills then
        local allSkills = BurdJournals.ALL_SKILLS
        local extraSkills = {}

        -- Collect skills not already in profession
        for _, skill in ipairs(allSkills) do
            if not usedSkills[skill] then
                table.insert(extraSkills, skill)
            end
        end

        -- Shuffle extra skills
        for i = #extraSkills, 2, -1 do
            local j = ZombRand(i) + 1
            extraSkills[i], extraSkills[j] = extraSkills[j], extraSkills[i]
        end

        -- Add extra skills to fill the gap
        local needed = numSkills - #availableSkills
        for i = 1, math.min(needed, #extraSkills) do
            table.insert(availableSkills, extraSkills[i])
        end
    end

    if #availableSkills == 0 then
        return nil
    end

    -- Shuffle all available skills
    for i = #availableSkills, 2, -1 do
        local j = ZombRand(i) + 1
        availableSkills[i], availableSkills[j] = availableSkills[j], availableSkills[i]
    end

    -- Build skills table with better XP values
    local skills = {}
    local xpThresholds = {0, 75, 150, 300, 750, 1500, 3000, 4500, 6000, 7500, 9000}
    for i = 1, math.min(numSkills, #availableSkills) do
        local skillName = availableSkills[i]
        local skillXP = ZombRand(minXP, maxXP + 1)

        local level = 0
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
    
    -- Maybe include a rare trait reward
    local traits = nil
    if ZombRand(100) < traitChance then
        -- Pick a random grantable trait
        local availableTraits = BurdJournals.GRANTABLE_TRAITS
        if availableTraits and #availableTraits > 0 then
            local traitId = availableTraits[ZombRand(#availableTraits) + 1]
            if traitId then
                -- Just use the trait ID as the name - we'll look up the display name when showing UI
                -- Avoids calling TraitFactory.getTrait during zombie death (can cause crashes)
                traits = {}
                traits[traitId] = {
                    name = traitId,  -- Will be resolved to display name in UI
                    id = traitId,
                }
            end
        end
    end
    
    -- Build journal data structure (consistent with WorldSpawn format)
    local journalData = {
        author = survivorName,
        professionName = profession.name,  -- e.g., "Former Farmer"
        flavorText = profession.flavorText,
        timestamp = getGameTime():getWorldAgeHours() - ZombRand(24, 720),
        skills = skills,
        traits = traits, -- May be nil or contain one trait
        -- Bloody journal state
        isBloody = true,
        isWorn = false,
        wasFromBloody = true, -- Will be true after cleaning
        isPlayerCreated = false,
        isZombieJournal = true,
        condition = ZombRand(1, 4),
        -- Claim tracking (starts empty)
        claimedSkills = {},
        claimedTraits = {},
    }

    return journalData
end

-- ==================== ZOMBIE DEATH HANDLER ====================

function BurdJournals.ZombieLoot.onZombieDead(zombie)
    -- Only run on server in multiplayer
    if isClient() and not isServer() then return end
    if not zombie then return end
    if not BurdJournals.isEnabled() then return end

    local spawnsEnabled = BurdJournals.getSandboxOption("EnableBloodyJournalSpawns")
    if spawnsEnabled == false then return end

    -- Roll for drop chance
    local dropChance = BurdJournals.getSandboxOption("BloodyJournalSpawnChance") or 0.5
    local roll = ZombRandFloat(0, 100)
    if roll > dropChance then return end

    -- Generate journal data
    local journalData = BurdJournals.ZombieLoot.generateBloodyJournalData()
    if not journalData then return end

    -- Get zombie's position
    local square = zombie:getSquare()
    if not square then return end

    -- Try to add to zombie inventory first
    local container = zombie:getInventory()
    local journal = nil

    if container then
        journal = container:AddItem("BurdJournals.FilledSurvivalJournal_Bloody")
    end

    -- If inventory add failed, drop on ground
    if not journal then
        journal = InventoryItemFactory.CreateItem("BurdJournals.FilledSurvivalJournal_Bloody")
        if journal then
            square:AddWorldInventoryItem(journal, ZombRandFloat(0, 0.8), ZombRandFloat(0, 0.8), 0)
        end
    end

    if journal then
        -- Set the mod data
        local modData = journal:getModData()
        modData.BurdJournals = {}
        for key, value in pairs(journalData) do
            modData.BurdJournals[key] = value
        end

        -- Ensure bloody state is explicitly set
        modData.BurdJournals.isBloody = true
        modData.BurdJournals.isWorn = false
        modData.BurdJournals.wasFromBloody = true
        modData.BurdJournals.isZombieJournal = true

        -- Update visuals
        BurdJournals.updateJournalName(journal)
        BurdJournals.updateJournalIcon(journal)

        -- Force sync in multiplayer
        if isServer() then
            journal:transmitModData()
        end
    end
end

-- ==================== EVENT REGISTRATION ====================

Events.OnZombieDead.Add(BurdJournals.ZombieLoot.onZombieDead)

-- ==================== WORN JOURNAL CONTAINER SPAWNING ====================
-- OnFillContainer handler for spawning worn journals in world containers
-- This runs when containers are first generated and adds journals based on sandbox settings

-- Container types that can spawn worn journals (with base weight for spawn chance scaling)
-- NOTE: These are the ACTUAL container type names from OnFillContainer (lowercase!)
local WORN_JOURNAL_CONTAINERS = {
    -- Shelves (literature likely)
    ["shelves"] = 2.0,
    ["metal_shelves"] = 1.5,
    -- Desks and tables
    ["desk"] = 1.5,
    ["sidetable"] = 0.8,
    ["endtable"] = 0.6,
    ["nightstand"] = 0.6,
    -- Dressers
    ["dresser"] = 0.5,
    -- Storage containers
    ["wardrobe"] = 0.3,
    ["locker"] = 0.5,
    ["filingcabinet"] = 1.0,
    -- Boxes
    ["smallbox"] = 0.4,
    ["cardboardbox"] = 0.4,
    ["crate"] = 0.5,
    -- Counters (low chance)
    ["counter"] = 0.2,
    -- Mailbox
    ["postbox"] = 0.3,
}

-- Track containers we've already processed
local processedContainers = {}

local function getContainerKey(container)
    if not container then return nil end
    local parent = container:getParent()
    if parent and parent.getSquare then
        local sq = parent:getSquare()
        if sq then
            return string.format("%d_%d_%d_%s", sq:getX(), sq:getY(), sq:getZ(), tostring(container:getType()))
        end
    end
    return nil
end

local function onFillContainerWornJournals(roomName, containerType, itemContainer)
    -- Only run on server/single player
    if isClient() and not isServer() then return end
    
    -- Check if mod is enabled
    if not BurdJournals or not BurdJournals.isEnabled or not BurdJournals.isEnabled() then return end
    
    -- Check if worn journal spawns are enabled
    local spawnsEnabled = BurdJournals.getSandboxOption("EnableWornJournalSpawns")
    if spawnsEnabled == false then return end
    
    -- Check if this container type can spawn journals
    local baseWeight = WORN_JOURNAL_CONTAINERS[containerType]
    if not baseWeight then return end
    
    -- Avoid processing the same container twice
    local containerKey = getContainerKey(itemContainer)
    if containerKey then
        if processedContainers[containerKey] then
            return
        end
        processedContainers[containerKey] = true
    end
    
    -- Get spawn chance from sandbox (0.1 to 100.0, default 2.0)
    local spawnChance = BurdJournals.getSandboxOption("WornJournalSpawnChance") or 2.0
    
    -- Calculate final spawn chance: (sandbox % * base weight) / 100
    local finalChance = (spawnChance * baseWeight) / 100.0
    
    -- Roll for spawn
    local roll = ZombRandFloat(0, 1)
    if roll > finalChance then
        return
    end
    
    -- Spawn a worn journal
    local journal = itemContainer:AddItem("BurdJournals.FilledSurvivalJournal_Worn")
    if journal then
        -- Initialize if OnCreate didn't run
        local modData = journal:getModData()
        if not modData.BurdJournals or not modData.BurdJournals.skills then
            if BurdJournals.WorldSpawn and BurdJournals.WorldSpawn.initializeJournalIfNeeded then
                BurdJournals.WorldSpawn.initializeJournalIfNeeded(journal)
            else
                -- Fallback initialization if WorldSpawn isn't loaded
                modData.BurdJournals = {
                    uuid = BurdJournals.generateUUID and BurdJournals.generateUUID() or tostring(ZombRand(999999)),
                    author = "Unknown Survivor",
                    profession = "unemployed",
                    professionName = "Survivor",
                    timestamp = getGameTime():getWorldAgeHours() - ZombRand(24, 720),
                    skills = BurdJournals.generateRandomSkills and BurdJournals.generateRandomSkills(1, 2, 25, 75) or {},
                    isWorn = true,
                    isBloody = false,
                    wasFromBloody = false,
                    isPlayerCreated = false,
                    traits = nil,
                    claimedSkills = {},
                    claimedTraits = {},
                }
                if BurdJournals.updateJournalName then
                    BurdJournals.updateJournalName(journal)
                end
                if BurdJournals.updateJournalIcon then
                    BurdJournals.updateJournalIcon(journal)
                end
            end
        end
    end
end

-- Register OnFillContainer event for worn journal spawning
if Events.OnFillContainer then
    Events.OnFillContainer.Add(onFillContainerWornJournals)
end


