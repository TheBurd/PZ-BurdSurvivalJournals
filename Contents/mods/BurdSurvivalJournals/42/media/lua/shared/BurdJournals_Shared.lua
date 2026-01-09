--[[
    Burd's Survival Journals - Shared Module
    Build 42 - Version 2.0

    Journal System Overview:

    CLEAN JOURNALS (Player-created):
    - XP SETTING mode (restores XP to recorded levels)
    - Reusable indefinitely
    - Can record appearance, skills, traits, etc.

    WORN JOURNALS (Found in world containers):
    - XP ADDING mode (adds XP on top of current)
    - Consumable - dissolves when all skills claimed
    - Light rewards: 1-2 skills, 25-75 XP each
    - Can convert to Clean Blank via context menu (Tailoring Lv1)

    BLOODY JOURNALS (Found on zombie corpses):
    - XP ADDING mode (adds XP on top of current)
    - Consumable - dissolves when all skills claimed
    - Better rewards: 2-4 skills, 50-150 XP each
    - Rare trait chance (15% default)
    - Can convert to Clean Blank via crafting menu (destroys rewards)

    State tracked in modData.BurdJournals:
    - isWorn: boolean
    - isBloody: boolean
    - wasFromBloody: boolean (for UI display purposes)
    - claimedSkills: table of skill names that have been claimed
    - claimedTraits: table of trait IDs that have been claimed
]]

BurdJournals = BurdJournals or {}

-- ==================== VERSION ====================

BurdJournals.VERSION = "2.4.3"
BurdJournals.MOD_ID = "BurdSurvivalJournals"

-- ==================== UUID GENERATION ====================

-- Generate a unique ID for journals (used for client/server communication in MP)
-- Item IDs differ between client and server, so we need our own identifier
function BurdJournals.generateUUID()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    local uuid = string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and ZombRand(0, 16) or ZombRand(8, 12)
        return string.format("%x", v)
    end)
    return uuid
end

-- Find a journal by its UUID in player's inventory OR any open/nearby containers
function BurdJournals.findJournalByUUID(player, uuid)
    if not player or not uuid then return nil end
    
    -- Search player's inventory first
    local inventory = player:getInventory()
    if inventory then
        local found = BurdJournals.findJournalByUUIDInContainer(inventory, uuid)
        if found then return found end
    end
    
    -- Search any open containers (loot window) - CLIENT ONLY
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
    
    -- Search nearby containers (works on both client and server)
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
            -- Check if it's a BurdJournals item
            if fullType and fullType:find("^BurdJournals%.") then
                local modData = item:getModData()
                if modData and modData.BurdJournals and modData.BurdJournals.uuid == uuid then
                    return item
                end
            end
            -- If item is a container (bag), search inside it recursively
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

-- ==================== SKILL DEFINITIONS ====================

-- Build 42 complete skill list organized by category
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
        "Carpentry",      -- Uses Perks.Woodwork
        "Cooking",
        "Electricity",
        "MetalWelding",
        "Mechanics",
        "Tailoring",
        "Blacksmith",     -- B42 new
        "Glassmaking",    -- B42 new
        "Pottery",        -- B42 new
        "Masonry",        -- B42 new
        "Carving",        -- B42 new
        "FlintKnapping"   -- B42 new (displayed as "Knapping")
    },
    Farming = {
        "Farming",
        "Husbandry",      -- B42 new (Animal Care)
        "Butchering"      -- B42 new
    },
    Survival = {
        "Fishing",
        "Trapping",
        "Foraging",       -- Uses Perks.PlantScavenging
        "Tracking",       -- B42 new
        "Doctor"
    },
    Agility = {
        "Sprinting",
        "Lightfoot",
        "Nimble",
        "Sneak"
    }
}

-- Mapping from display/storage name to actual Perks enum name
-- (for skills where the name doesn't match the perk)
BurdJournals.SKILL_TO_PERK = {
    Foraging = "PlantScavenging",
    Carpentry = "Woodwork"
}

-- Build flat list of all skills
BurdJournals.ALL_SKILLS = {}
for category, skills in pairs(BurdJournals.SKILL_CATEGORIES) do
    for _, skill in ipairs(skills) do
        table.insert(BurdJournals.ALL_SKILLS, skill)
    end
end

-- ==================== TRAIT REWARDS (For bloody journals) ====================

-- All positive traits that can be granted via journals
-- Based on character_traits.txt from Build 42
-- Excludes profession-only traits (cost=0) and physical body traits (Athletic, Strong, etc.)
BurdJournals.GRANTABLE_TRAITS = {
    -- ============ COMBAT & SURVIVAL (High Value) ============
    "brave",              -- Brave (4 pts) - Less panic
    "resilient",          -- Resilient (4 pts) - Better zombie resistance
    "thickskinned",       -- Thick Skinned (8 pts) - Less bite/scratch chance
    "fasthealer",         -- Fast Healer (6 pts) - Heal wounds faster
    "adrenalinejunkie",   -- Adrenaline Junkie (4 pts) - Speed boost when panicked

    -- ============ MOVEMENT & STEALTH ============
    "graceful",           -- Graceful (4 pts) - Less noise, trips less
    "inconspicuous",      -- Inconspicuous (4 pts) - Zombies notice you less
    "nightvision",        -- Night Vision (2 pts) - See better at night

    -- ============ PERCEPTION ============
    "keenhearing",        -- Keen Hearing (6 pts) - Larger perception radius
    "eagleeyed",          -- Eagle Eyed (4 pts) - Better spotting range

    -- ============ LEARNING & CRAFTING ============
    "fastlearner",        -- Fast Learner (6 pts) - +30% XP gain
    "fastreader",         -- Fast Reader (2 pts) - Read books faster
    "inventive",          -- Inventive (2 pts) - Extra recipe XP (B42)
    "crafty",             -- Crafty (3 pts) - Better crafting results (B42)

    -- ============ METABOLISM & NEEDS ============
    "lighteater",         -- Light Eater (2 pts) - Less food needed
    "lowthirst",          -- Low Thirst (2 pts) - Less water needed
    "needslesssleep",     -- Needs Less Sleep (2 pts) - Sleep less
    "irongut",            -- Iron Gut (3 pts) - Resist food poisoning

    -- ============ ORGANIZATION & UTILITY ============
    "organized",          -- Organized (4 pts) - +30% container capacity
    "dextrous",           -- Dextrous (2 pts) - Faster inventory transfers

    -- ============ ENVIRONMENTAL ============
    "outdoorsman",        -- Outdoorsman (2 pts) - Weather resistance
    "nutritionist",       -- Nutritionist (4 pts) - See food nutrition values

    -- ============ DRIVING ============
    "speeddemon",         -- Speed Demon (1 pt) - Faster driving

    -- ============ SKILL BOOST TRAITS (Medium Value) ============
    -- These grant starting skill levels and XP boosts
    "baseballplayer",     -- Baseball Player (4 pts) - Blunt +1
    "jogger",             -- Jogger (4 pts) - Sprinting +1
    "gymnast",            -- Gymnast (5 pts) - Lightfoot +1, Nimble +1
    "firstaid",           -- First Aid (4 pts) - Doctor +1
    "gardener",           -- Gardener (2 pts) - Farming +1
    "herbalist",          -- Herbalist (4 pts) - Foraging +1
    "fishing",            -- Angler (4 pts) - Fishing +1
    "tailor",             -- Tailor (4 pts) - Tailoring +1
    "mechanics",          -- Amateur Mechanic (3 pts) - Mechanics +1
    "cook",               -- Cook (3 pts) - Cooking +2, Butchering +1

    -- ============ BUILD 42 NEW TRAITS ============
    "hiker",              -- Hiker (6 pts) - Foraging +1, Trapping +1
    "hunter",             -- Hunter (8 pts) - Aiming +1, Trapping +1, Sneak +1, etc.
    "brawler",            -- Brawler (6 pts) - Axe +1, Blunt +1
    "formerscout",        -- Former Scout (6 pts) - Doctor +1, Foraging +1, Fishing +1
    "handy",              -- Handy (8 pts) - Multiple crafting +1
    "artisan",            -- Artisan (2 pts) - Glassmaking +1, Pottery +1 (B42)
    "blacksmith",         -- Blacksmith (6 pts) - Blacksmith +2, Maintenance +1 (B42)
    "mason",              -- Mason (2 pts) - Masonry +2 (B42)
    "whittler",           -- Whittler (2 pts) - Carving +2 (B42)
    "wildernessknowledge", -- Wilderness Knowledge (8 pts) - Multiple survival skills (B42)

    -- Note: The following are excluded:
    -- "athletic", "strong", "stout", "fit" - Physical stats that affect character model
    -- "desensitized", "burglar", "marksman" etc. - Profession-only (cost=0)
    -- "axeman", "cook2", "mechanics2" etc. - Profession boosters (cost=0)
}

-- ==================== PLAYER STATS (For player journals) ====================

-- Player statistics that can be recorded to journals
-- These represent character meta-information and achievements
BurdJournals.RECORDABLE_STATS = {
    -- ============ SURVIVAL MILESTONES ============
    {
        id = "zombieKills",
        name = "Zombie Kills",
        category = "Combat",
        description = "Total zombies killed",
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
        name = "Hours Survived",
        category = "Survival",
        description = "Total hours alive in the apocalypse",
        icon = "media/ui/clock.png",
        getValue = function(player)
            if not player then return 0 end
            return math.floor(player:getHoursSurvived() or 0)
        end,
        format = function(value)
            local days = math.floor(value / 24)
            local hours = value % 24
            if days > 0 then
                return days .. " days, " .. hours .. " hours"
            end
            return hours .. " hours"
        end,
    },
}

-- Get a stat definition by ID
function BurdJournals.getStatById(statId)
    for _, stat in ipairs(BurdJournals.RECORDABLE_STATS) do
        if stat.id == statId then
            return stat
        end
    end
    return nil
end

-- Get current value of a stat for a player
function BurdJournals.getStatValue(player, statId)
    local stat = BurdJournals.getStatById(statId)
    if stat and stat.getValue then
        local ok, value = pcall(stat.getValue, player)
        if ok then
            return value
        end
    end
    return nil
end

-- Format a stat value for display
function BurdJournals.formatStatValue(statId, value)
    local stat = BurdJournals.getStatById(statId)
    if stat and stat.format then
        local ok, formatted = pcall(stat.format, value)
        if ok then
            return formatted
        end
    end
    return tostring(value)
end

-- Get all stats grouped by category
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

-- Record a stat to a journal
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

    -- Store both raw value and formatted display
    modData.BurdJournals.stats[statId] = {
        value = value,
        timestamp = getGameTime():getWorldAgeHours(),
        recordedBy = player and (player:getDescriptor():getForename() .. " " .. player:getDescriptor():getSurname()) or "Unknown",
    }

    return true
end

-- Get recorded stat from journal
function BurdJournals.getRecordedStat(journal, statId)
    if not journal then return nil end

    local modData = journal:getModData()
    if modData.BurdJournals and modData.BurdJournals.stats then
        return modData.BurdJournals.stats[statId]
    end
    return nil
end

-- Get all recorded stats from journal
function BurdJournals.getAllRecordedStats(journal)
    if not journal then return {} end

    local modData = journal:getModData()
    if modData.BurdJournals and modData.BurdJournals.stats then
        return modData.BurdJournals.stats
    end
    return {}
end

-- Check if a stat can be updated (current value is different/higher)
function BurdJournals.canUpdateStat(journal, statId, player)
    if not journal or not player then return false, nil, nil end

    local stat = BurdJournals.getStatById(statId)
    if not stat then return false, nil, nil end

    local currentValue = BurdJournals.getStatValue(player, statId)
    local recorded = BurdJournals.getRecordedStat(journal, statId)
    local recordedValue = recorded and recorded.value or nil

    -- For numeric stats, only allow update if current is higher
    -- For text stats, allow update if different
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

-- Check if a specific stat type is enabled via sandbox options
function BurdJournals.isStatEnabled(statId)
    -- First check master toggle
    if not BurdJournals.getSandboxOption("EnableStatRecording") then
        return false
    end

    -- Check individual stat toggles
    local statToggleMap = {
        zombieKills = "RecordZombieKills",
        hoursSurvived = "RecordHoursSurvived",
    }

    local toggleOption = statToggleMap[statId]
    if toggleOption then
        local enabled = BurdJournals.getSandboxOption(toggleOption)
        -- Default to true if option not found
        if enabled == nil then
            return true
        end
        return enabled
    end

    -- Unknown stat, default to enabled
    return true
end

-- ==================== DISSOLUTION MESSAGES ====================

BurdJournals.DissolutionMessages = {
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
    local index = ZombRand(#BurdJournals.DissolutionMessages) + 1
    return BurdJournals.DissolutionMessages[index]
end

-- ==================== SANDBOX OPTIONS ====================

function BurdJournals.getSandboxOption(optionName)
    local opts = SandboxVars.BurdJournals
    if opts and opts[optionName] ~= nil then
        return opts[optionName]
    end
    local defaults = {
        EnableJournals = true,
        -- Clean journal XP recovery settings
        XPRecoveryMode = 1,
        DiminishingFirstRead = 100,
        DiminishingDecayRate = 10,
        DiminishingMinimum = 10,
        -- Writing requirements
        RequirePenToWrite = true,
        PenUsesPerLog = 1,
        RequireEraserToErase = true,
        -- Learning time settings
        LearningTimePerSkill = 3.0,
        LearningTimePerTrait = 5.0,
        LearningTimeMultiplier = 1.0,
        -- Player stats recording
        EnableStatRecording = true,
        RecordZombieKills = true,
        RecordHoursSurvived = true,
        -- Worn journal spawns (world containers)
        EnableWornJournalSpawns = true,
        WornJournalSpawnChance = 2.0,
        WornJournalMinSkills = 1,
        WornJournalMaxSkills = 2,
        WornJournalMinXP = 25,
        WornJournalMaxXP = 75,
        -- Bloody journal spawns (zombie corpses)
        EnableBloodyJournalSpawns = true,
        BloodyJournalSpawnChance = 0.5,
        BloodyJournalMinSkills = 2,
        BloodyJournalMaxSkills = 4,
        BloodyJournalMinXP = 50,
        BloodyJournalMaxXP = 150,
        BloodyJournalTraitChance = 15, -- 15% chance to include a trait
        BloodyJournalMaxTraits = 2,
        -- Advanced settings
        EnablePlayerJournals = true,
        ReadingSkillAffectsSpeed = true,
        ReadingSpeedBonus = 0.1, -- 10% faster per reading level
        EraseTime = 10.0,
        ConvertTime = 15.0,
        -- XP Multiplier
        JournalXPMultiplier = 1.0,
        -- Multiplayer sharing settings
        AllowOthersToOpenJournals = true,
        AllowOthersToClaimFromJournals = true,
        -- Baseline restriction (anti-exploit)
        EnableBaselineRestriction = true,
    }
    return defaults[optionName]
end

function BurdJournals.isEnabled()
    return BurdJournals.getSandboxOption("EnableJournals")
end

-- ==================== JOURNAL OWNERSHIP & PERMISSIONS ====================

-- Get the owner username of a journal (for ownership checks)
function BurdJournals.getJournalOwnerUsername(item)
    if not item then return nil end
    local modData = item:getModData()
    if modData.BurdJournals and modData.BurdJournals.ownerUsername then
        return modData.BurdJournals.ownerUsername
    end
    return nil
end

-- Get the display name of the journal's author (character name for display)
function BurdJournals.getJournalAuthorUsername(item)
    if not item then return nil end
    local modData = item:getModData()
    if modData.BurdJournals and modData.BurdJournals.author then
        return modData.BurdJournals.author
    end
    return nil
end

-- Check if a player is the owner/author of a journal
function BurdJournals.isJournalOwner(player, item)
    if not player or not item then return false end

    local modData = item:getModData()
    if not modData.BurdJournals then return true end  -- No data = anyone can use

    -- PRIMARY: Check ownerUsername field (new format)
    local ownerUsername = modData.BurdJournals.ownerUsername
    if ownerUsername then
        local playerUsername = player:getUsername()
        if playerUsername then
            return ownerUsername == playerUsername
        end
    end

    -- FALLBACK: For older journals, check author against character's full name
    local author = modData.BurdJournals.author
    if author then
        local playerFullName = player:getDescriptor():getForename() .. " " .. player:getDescriptor():getSurname()
        if author == playerFullName then
            return true
        end
        -- Also check against username (in case author was set to username)
        local playerUsername = player:getUsername()
        if playerUsername and author == playerUsername then
            return true
        end
    end

    -- No ownership info = allow (non-player created journals)
    if not ownerUsername and not author then
        return true
    end

    return false
end

-- Check if a player can open a personal journal (view mode)
-- Returns: canOpen, reason
function BurdJournals.canPlayerOpenJournal(player, item)
    if not player or not item then return false, "Invalid player or item" end

    -- Only applies to player-created journals (clean filled journals)
    if not BurdJournals.isPlayerJournal(item) then
        return true, nil  -- Non-player journals have no ownership restrictions
    end

    -- Worn and bloody journals have no ownership restrictions
    if BurdJournals.isWorn(item) or BurdJournals.isBloody(item) then
        return true, nil
    end

    -- Check if player is the owner
    if BurdJournals.isJournalOwner(player, item) then
        return true, nil  -- Owner can always open
    end

    -- Check sandbox option for allowing others to open
    local allowOthersToOpen = BurdJournals.getSandboxOption("AllowOthersToOpenJournals")
    if allowOthersToOpen == false then
        return false, "You cannot open another player's personal journal."
    end

    return true, nil
end

-- Check if a player can claim from a personal journal
-- Returns: canClaim, reason
function BurdJournals.canPlayerClaimFromJournal(player, item)
    if not player or not item then return false, "Invalid player or item" end

    -- Only applies to player-created journals (clean filled journals)
    if not BurdJournals.isPlayerJournal(item) then
        return true, nil  -- Non-player journals have no ownership restrictions
    end

    -- Worn and bloody journals have no ownership restrictions
    if BurdJournals.isWorn(item) or BurdJournals.isBloody(item) then
        return true, nil
    end

    -- Check if player is the owner
    if BurdJournals.isJournalOwner(player, item) then
        return true, nil  -- Owner can always claim
    end

    -- Check sandbox option for allowing others to open (required to claim)
    local allowOthersToOpen = BurdJournals.getSandboxOption("AllowOthersToOpenJournals")
    if allowOthersToOpen == false then
        return false, "You cannot access another player's personal journal."
    end

    -- Check sandbox option for allowing others to claim
    local allowOthersToClaim = BurdJournals.getSandboxOption("AllowOthersToClaimFromJournals")
    if allowOthersToClaim == false then
        return false, "You cannot claim from another player's personal journal."
    end

    return true, nil
end

function BurdJournals.isDebug()
    return isDebugEnabled and isDebugEnabled() or false
end

-- ==================== SKILL UTILITIES ====================

function BurdJournals.isSkillAllowed(skillName)
    for _, skill in ipairs(BurdJournals.ALL_SKILLS) do
        if skill == skillName then return true end
    end
    return false
end

function BurdJournals.getAllowedSkills()
    return BurdJournals.ALL_SKILLS
end

function BurdJournals.getPerkByName(perkName)
    -- Check if there's a mapping (e.g., "Foraging" -> "PlantScavenging")
    local actualPerkName = BurdJournals.SKILL_TO_PERK[perkName] or perkName
    local perk = Perks[actualPerkName]
    if perk then
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

-- Reverse lookup: get our skill name from a perk object
-- Used when processing profession/trait XP boosts which give us perk objects
function BurdJournals.getSkillNameFromPerk(perk)
    if not perk then return nil end

    -- Get the perk's internal name using multiple methods
    local perkName = nil

    -- Method 1: If it's already a string
    if type(perk) == "string" then
        perkName = perk
    end

    -- Method 2: Try PerkFactory to get the perk definition and name
    if not perkName and PerkFactory and PerkFactory.getPerk then
        local ok, result = pcall(function()
            local perkDef = PerkFactory.getPerk(perk)
            if perkDef then
                -- Try to get internal ID name
                if perkDef.getId then
                    return tostring(perkDef:getId())
                elseif perkDef.getName then
                    -- This returns display name, not ID - but we can try
                    return perkDef:getName()
                end
            end
            return nil
        end)
        if ok and result then
            perkName = result
        end
    end

    -- Method 3: Try direct name access on Java enum
    if not perkName and perk.name then
        perkName = tostring(perk.name)
    end

    -- Method 4: Convert to string and clean up
    if not perkName then
        perkName = tostring(perk)
        -- Clean up common prefixes
        perkName = perkName:gsub("^Perks%.", "")
        perkName = perkName:gsub("^zombie%.characters%.skills%.PerkFactory%$Perk%.", "")
        perkName = perkName:gsub("^zombie%.characters%.skills%.PerkFactory%$", "")
    end

    if not perkName or perkName == "" then return nil end

    -- Debug output
    -- print("[BurdJournals] getSkillNameFromPerk: input=" .. tostring(perk) .. " -> perkName=" .. tostring(perkName))

    -- Check reverse mappings (PlantScavenging -> Foraging, Woodwork -> Carpentry)
    local reverseMap = {
        PlantScavenging = "Foraging",
        Woodwork = "Carpentry"
    }
    if reverseMap[perkName] then
        return reverseMap[perkName]
    end

    -- Check if it matches any of our allowed skills directly
    local allowedSkills = BurdJournals.getAllowedSkills()
    for _, skillName in ipairs(allowedSkills) do
        if skillName == perkName then
            return skillName
        end
    end

    -- Try case-insensitive match
    local lowerPerkName = string.lower(perkName)
    for _, skillName in ipairs(allowedSkills) do
        if string.lower(skillName) == lowerPerkName then
            return skillName
        end
    end

    -- If we got here with a display name, try matching it
    -- (e.g., "Carpentry" display name should match "Carpentry" skill)
    for _, skillName in ipairs(allowedSkills) do
        local displayName = BurdJournals.getPerkDisplayName(skillName)
        if displayName == perkName or string.lower(displayName) == lowerPerkName then
            return skillName
        end
    end

    return nil
end

-- ==================== ITEM UTILITIES ====================

-- Recursively search for an item by ID in a container and all sub-containers (bags)
function BurdJournals.findItemByIdInContainer(container, itemId)
    if not container then return nil end

    local items = container:getItems()
    if not items then return nil end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            -- Check if this is the item we're looking for
            if item:getID() == itemId then
                return item
            end
            -- If item is a container (bag), search inside it recursively
            -- Only call getInventory if the method exists (bags have it, clothing doesn't)
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
    
    -- Search player's inventory first
    local inventory = player:getInventory()
    if inventory then
        local found = BurdJournals.findItemByIdInContainer(inventory, itemId)
        if found then return found end
    end
    
    -- Search any open containers (loot window) - CLIENT ONLY
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
    
    -- Search nearby containers (works on both client and server)
    -- This allows server to find items in containers near the player
    local square = player:getCurrentSquare()
    if square then
        -- Check current square and adjacent squares (3x3 area)
        for dx = -1, 1 do
            for dy = -1, 1 do
                local nearSquare = getCell():getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ())
                if nearSquare then
                    -- Check all objects on this square for containers
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
                            -- Also check if object IS a container (like IsoDeadBody)
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

-- All vanilla writing tools
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

-- ==================== CLEANING/REPAIR MATERIALS ====================

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

-- NOTE: canCleanBloodyJournal has been removed. Bloody journals are now directly
-- readable (no cleaning required). Conversion to clean blank is via crafting menu.

-- Can convert worn -> clean (leather + thread + needle + Tailoring 1)
function BurdJournals.canConvertToClean(player)
    local hasLeather = BurdJournals.findRepairItem(player, "leather") ~= nil
    local hasThread = BurdJournals.findRepairItem(player, "thread") ~= nil
    local hasNeedle = BurdJournals.findRepairItem(player, "needle") ~= nil
    local hasTailoring = player:getPerkLevel(Perks.Tailoring) >= 1
    return hasLeather and hasThread and hasNeedle and hasTailoring
end

-- ==================== ITEM CONSUMPTION ====================

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

-- ==================== JOURNAL TYPE CHECKS ====================

-- All blank journal item types (clean, worn, bloody variants)
BurdJournals.BLANK_JOURNAL_TYPES = {
    "BurdJournals.BlankSurvivalJournal",
    "BurdJournals.BlankSurvivalJournal_Worn",
    "BurdJournals.BlankSurvivalJournal_Bloody",
}

-- All filled journal item types (clean, worn, bloody variants)
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
    
    -- First try exact type match
    if BurdJournals.isBlankJournal(item) or BurdJournals.isFilledJournal(item) then
        return true
    end
    
    -- Fallback: check if fullType contains "BurdJournals" and "SurvivalJournal"
    local fullType = item:getFullType()
    if fullType and fullType:find("BurdJournals") and fullType:find("SurvivalJournal") then
        return true
    end
    
    return false
end

-- ==================== JOURNAL STATE CHECKS ====================

function BurdJournals.isWorn(item)
    if not item then return false end
    local modData = item:getModData()
    
    -- Check modData first
    if modData.BurdJournals and modData.BurdJournals.isWorn == true then
        return true
    end
    
    -- Fallback: check item type name contains "_Worn"
    local fullType = item:getFullType()
    if fullType and fullType:find("_Worn") then
        return true
    end
    
    return false
end

function BurdJournals.isBloody(item)
    if not item then return false end
    local modData = item:getModData()
    
    -- Check modData first
    if modData.BurdJournals and modData.BurdJournals.isBloody == true then
        return true
    end
    
    -- Fallback: check item type name contains "_Bloody"
    local fullType = item:getFullType()
    if fullType and fullType:find("_Bloody") then
        return true
    end
    
    return false
end

function BurdJournals.isClean(item)
    if not item then return false end
    return not BurdJournals.isWorn(item) and not BurdJournals.isBloody(item)
end

-- Check if this worn journal was cleaned from a bloody journal (has trait rewards)
function BurdJournals.wasFromBloody(item)
    if not item then return false end
    local modData = item:getModData()
    return modData.BurdJournals and modData.BurdJournals.wasFromBloody == true
end

-- Check if item has bloody origin (is bloody OR was from bloody)
-- Use this consistently when checking for trait availability
function BurdJournals.hasBloodyOrigin(item)
    return BurdJournals.isBloody(item) or BurdJournals.wasFromBloody(item)
end

-- Check if this is a player-created journal (not found loot)
function BurdJournals.isPlayerJournal(item)
    if not item then return false end
    local modData = item:getModData()
    return modData.BurdJournals and modData.BurdJournals.isPlayerCreated == true
end

function BurdJournals.setWorn(item, worn)
    if not item then return end
    local modData = item:getModData()
    if not modData.BurdJournals then
        modData.BurdJournals = {}
    end
    modData.BurdJournals.isWorn = worn
    modData.BurdJournals.isBloody = false -- Can't be both
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
    modData.BurdJournals.isWorn = false -- Can't be both
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

-- NOTE: cleanBloodyToWorn has been removed. Bloody journals are now directly
-- readable for XP absorption (like worn journals but with better rewards).
-- Players can convert bloody journals to clean blanks via the crafting menu,
-- but there's no bloody -> worn conversion path.

-- ==================== READABILITY ====================

-- Readable means you can open the journal UI
-- Clean journals: XP setting mode (reusable)
-- Worn journals: XP absorption mode (consumable, light rewards)
-- Bloody journals: XP absorption mode (consumable, better rewards + traits)
function BurdJournals.isReadable(item)
    if not item then return false end
    -- Blank journals are not readable (no content to show)
    if BurdJournals.isBlankJournal(item) then return false end
    -- All filled journals are readable (Clean, Worn, and Bloody)
    if BurdJournals.isFilledJournal(item) then return true end
    return false
end

-- Can absorb XP from this journal? Worn OR Bloody journals (both are consumable)
function BurdJournals.canAbsorbXP(item)
    if not item then return false end
    if not BurdJournals.isFilledJournal(item) then return false end
    -- Both worn and bloody journals use absorption mode
    return BurdJournals.isWorn(item) or BurdJournals.isBloody(item)
end

-- Can set XP from this journal? Only clean journals
function BurdJournals.canSetXP(item)
    if not item then return false end
    if not BurdJournals.isFilledJournal(item) then return false end
    return BurdJournals.isClean(item)
end

-- ==================== SKILL CLAIM TRACKING ====================

function BurdJournals.getClaimedSkills(item)
    if not item then return {} end
    local modData = item:getModData()
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

function BurdJournals.getUnclaimedSkills(item)
    if not item then return {} end
    local data = BurdJournals.getJournalData(item)
    if not data or not data.skills then return {} end
    
    local claimed = BurdJournals.getClaimedSkills(item)
    local unclaimed = {}
    
    for skillName, skillData in pairs(data.skills) do
        if not claimed[skillName] then
            unclaimed[skillName] = skillData
        end
    end
    
    return unclaimed
end

function BurdJournals.getUnclaimedSkillCount(item)
    local unclaimed = BurdJournals.getUnclaimedSkills(item)
    return BurdJournals.countTable(unclaimed)
end

function BurdJournals.getTotalSkillCount(item)
    if not item then return 0 end
    local data = BurdJournals.getJournalData(item)
    if not data or not data.skills then return 0 end
    return BurdJournals.countTable(data.skills)
end

-- ==================== TRAIT CLAIM TRACKING ====================

function BurdJournals.getClaimedTraits(item)
    if not item then return {} end
    local modData = item:getModData()
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

function BurdJournals.getUnclaimedTraits(item)
    if not item then return {} end
    local data = BurdJournals.getJournalData(item)
    if not data or not data.traits then return {} end
    
    local claimed = BurdJournals.getClaimedTraits(item)
    local unclaimed = {}
    
    for traitId, traitData in pairs(data.traits) do
        if not claimed[traitId] then
            unclaimed[traitId] = traitData
        end
    end
    
    return unclaimed
end

function BurdJournals.getUnclaimedTraitCount(item)
    local unclaimed = BurdJournals.getUnclaimedTraits(item)
    return BurdJournals.countTable(unclaimed)
end

-- ==================== DISSOLUTION CHECK ====================

-- Check if journal should dissolve (all skills and traits claimed)
function BurdJournals.shouldDissolve(item)
    if not item then return false end
    -- Both worn and bloody journals dissolve when fully consumed
    if not BurdJournals.isWorn(item) and not BurdJournals.isBloody(item) then return false end

    -- Safety: Don't dissolve if journal has no valid data (prevents premature dissolution on corrupted data)
    local data = BurdJournals.getJournalData(item)
    if not data or not data.skills then return false end

    local unclaimedSkills = BurdJournals.getUnclaimedSkillCount(item)
    local unclaimedTraits = BurdJournals.getUnclaimedTraitCount(item)

    return unclaimedSkills == 0 and unclaimedTraits == 0
end

-- Get remaining rewards count for display
function BurdJournals.getRemainingRewards(item)
    local skills = BurdJournals.getUnclaimedSkillCount(item)
    local traits = BurdJournals.getUnclaimedTraitCount(item)
    return skills + traits
end

function BurdJournals.getTotalRewards(item)
    local skills = BurdJournals.getTotalSkillCount(item)
    local data = BurdJournals.getJournalData(item)
    local traits = data and data.traits and BurdJournals.countTable(data.traits) or 0
    return skills + traits
end

-- ==================== ICON MANAGEMENT ====================

function BurdJournals.updateJournalIcon(item)
    if not item then return end
    if not BurdJournals.isAnyJournal(item) then return end
    
    -- Check if this is a variant item type (_Worn or _Bloody)
    -- These already have correct icons from item definition, no need to update
    local fullType = item:getFullType()
    if fullType:find("_Worn") or fullType:find("_Bloody") then
        -- Icon is already correct from item script, don't override
        return
    end
    
    -- Only update icons for base item types based on modData state
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

-- ==================== JOURNAL DATA ====================

function BurdJournals.getJournalData(item)
    if not item then return nil end
    local modData = item:getModData()
    return modData.BurdJournals
end

-- ==================== JOURNAL NAME FORMATTING ====================

function BurdJournals.updateJournalName(item)
    if not item then return end

    local modData = item:getModData()
    local data = modData.BurdJournals or {}
    local isWornState = data.isWorn
    local isBloodyState = data.isBloody
    local author = data.author
    local professionName = data.professionName
    local isPlayerCreated = data.isPlayerCreated

    local stateSuffix = ""
    if isBloodyState then
        stateSuffix = "Bloody"
    elseif isWornState then
        stateSuffix = "Worn"
    end

    local baseName
    if BurdJournals.isBlankJournal(item) then
        baseName = "Blank Survival Journal"
        if stateSuffix ~= "" then
            baseName = baseName .. " (" .. stateSuffix .. ")"
        end
    elseif BurdJournals.isFilledJournal(item) then
        baseName = "Filled Survival Journal"
        local suffixParts = {}

        if stateSuffix ~= "" then
            table.insert(suffixParts, stateSuffix)
        end

        -- For found journals (non-player), show the profession
        -- Don't add "Previous" if name already starts with "Former" (zombie professions)
        -- For player journals, show the author name
        if not isPlayerCreated and professionName then
            -- Check if profession already has a past-tense prefix
            if string.find(professionName, "^Former") or string.find(professionName, "^Previous") then
                table.insert(suffixParts, professionName)
            else
                table.insert(suffixParts, "Previous " .. professionName)
            end
        elseif author then
            table.insert(suffixParts, author)
        end

        if #suffixParts > 0 then
            baseName = baseName .. " (" .. table.concat(suffixParts, " - ") .. ")"
        end
    end

    if baseName and item.setName then
        item:setName(baseName)
    end
end

function BurdJournals.getAuthorFromJournal(item)
    local data = BurdJournals.getJournalData(item)
    if data and data.author then
        return data.author
    end
    return "Unknown"
end

-- ==================== TABLE UTILITIES ====================

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

-- ==================== FORMATTING ====================

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

-- ==================== RANDOM GENERATION (For spawned journals) ====================

-- First names for random survivor journals
BurdJournals.RANDOM_FIRST_NAMES = {
    "James", "John", "Michael", "David", "Robert", "William", "Thomas", "Richard",
    "Mary", "Patricia", "Jennifer", "Linda", "Elizabeth", "Barbara", "Susan", "Jessica",
    "Daniel", "Matthew", "Anthony", "Mark", "Donald", "Steven", "Paul", "Andrew",
    "Sarah", "Karen", "Nancy", "Lisa", "Betty", "Margaret", "Sandra", "Ashley",
    "Joshua", "Kenneth", "Kevin", "Brian", "George", "Timothy", "Ronald", "Edward",
    "Kimberly", "Emily", "Donna", "Michelle", "Dorothy", "Carol", "Amanda", "Melissa",
}

-- Last names for random survivor journals
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

-- Generate random skills with XP values for spawned journals
function BurdJournals.generateRandomSkills(minSkills, maxSkills, minXP, maxXP)
    minSkills = minSkills or 1
    maxSkills = maxSkills or 2
    minXP = minXP or 25
    maxXP = maxXP or 75
    
    local skillCount = ZombRand(minSkills, maxSkills + 1)
    local allSkills = BurdJournals.getAllowedSkills()
    local availableSkills = {}
    
    -- Copy skills to a mutable table
    for _, skill in ipairs(allSkills) do
        table.insert(availableSkills, skill)
    end
    
    local skills = {}
    for i = 1, skillCount do
        if #availableSkills == 0 then break end
        
        -- Pick a random skill
        local index = ZombRand(#availableSkills) + 1
        local skillName = availableSkills[index]
        
        -- Remove from available
        table.remove(availableSkills, index)
        
        -- Generate random XP
        local xp = ZombRand(minXP, maxXP + 1)
        
        skills[skillName] = {
            xp = xp,
            level = math.floor(xp / 75) -- Approximate level from XP
        }
    end
    
    return skills
end

-- ==================== BASELINE TRACKING (Anti-Exploit System) ====================

-- Map PZ perk IDs (like "Woodwork") to our skill names (like "Carpentry")
-- This is needed because PZ uses different internal names for some skills
function BurdJournals.mapPerkIdToSkillName(perkId)
    if not perkId then return nil end

    -- Known mappings where PZ uses different internal names
    local mappings = {
        Woodwork = "Carpentry",
        PlantScavenging = "Foraging",
    }

    if mappings[perkId] then
        return mappings[perkId]
    end

    -- Check if perkId directly matches an allowed skill
    local allowedSkills = BurdJournals.getAllowedSkills()
    for _, skillName in ipairs(allowedSkills) do
        if skillName == perkId then
            return skillName
        end
        -- Case insensitive fallback
        if string.lower(skillName) == string.lower(perkId) then
            return skillName
        end
    end

    return nil
end

-- Get skill baseline XP (what the character started with from profession/traits)
function BurdJournals.getSkillBaseline(player, skillName)
    if not player then return 0 end
    local modData = player:getModData()
    if not modData.BurdJournals then return 0 end
    if not modData.BurdJournals.skillBaseline then return 0 end
    return modData.BurdJournals.skillBaseline[skillName] or 0
end

-- Check if trait was a starting trait (not acquired during gameplay)
function BurdJournals.isStartingTrait(player, traitId)
    if not player then return false end
    local modData = player:getModData()
    if not modData.BurdJournals then return false end
    if not modData.BurdJournals.traitBaseline then return false end
    return modData.BurdJournals.traitBaseline[traitId] == true
end

-- Get the full trait baseline table for a player
function BurdJournals.getTraitBaseline(player)
    if not player then return {} end
    local modData = player:getModData()
    if not modData.BurdJournals then return {} end
    return modData.BurdJournals.traitBaseline or {}
end

-- Get earned XP for a skill (current - baseline)
function BurdJournals.getEarnedXP(player, skillName)
    if not player then return 0 end
    local perk = BurdJournals.getPerkByName(skillName)
    if not perk then return 0 end

    local currentXP = player:getXp():getXP(perk)
    local baselineXP = BurdJournals.getSkillBaseline(player, skillName)

    return math.max(0, currentXP - baselineXP)
end

-- Check if baseline restriction is enabled (sandbox option)
function BurdJournals.isBaselineRestrictionEnabled()
    return BurdJournals.getSandboxOption("EnableBaselineRestriction") ~= false
end

-- Check if baseline has been captured for this player
function BurdJournals.hasBaselineCaptured(player)
    if not player then return false end
    local modData = player:getModData()
    if not modData.BurdJournals then return false end
    return modData.BurdJournals.baselineCaptured == true
end

-- ==================== PLAYER DATA COLLECTION (Clean journals only) ====================

function BurdJournals.collectPlayerSkills(player)
    if not player then return {} end

    local skills = {}
    local allowedSkills = BurdJournals.getAllowedSkills()
    local useBaseline = BurdJournals.isBaselineRestrictionEnabled()

    for _, skillName in ipairs(allowedSkills) do
        local perk = BurdJournals.getPerkByName(skillName)
        if perk then
            local currentXP = player:getXp():getXP(perk)
            local level = player:getPerkLevel(perk)

            -- If baseline restriction enabled, subtract starting XP
            local recordXP = currentXP
            if useBaseline then
                local baseline = BurdJournals.getSkillBaseline(player, skillName)
                recordXP = math.max(0, currentXP - baseline)
            end

            -- Only record if there's earned progress (or any XP if baseline disabled)
            if recordXP > 0 then
                skills[skillName] = {
                    xp = recordXP,
                    level = level  -- Keep display level for UI
                }
            end
        end
    end

    return skills
end

-- Collect player traits for journal recording
-- excludeStarting: if nil, uses sandbox option; if true/false, overrides
function BurdJournals.collectPlayerTraits(player, excludeStarting)
    if not player then return {} end

    -- If excludeStarting not specified, check sandbox option
    if excludeStarting == nil then
        excludeStarting = BurdJournals.isBaselineRestrictionEnabled()
    end

    local traits = {}

    -- Build 42 method: player:getCharacterTraits():getKnownTraits()
    local ok, err = pcall(function()
        local charTraits = player:getCharacterTraits()
        if charTraits then
            local knownTraits = charTraits:getKnownTraits()
            if knownTraits then
                for i = 0, knownTraits:size() - 1 do
                    local traitType = knownTraits:get(i)  -- This is a CharacterTrait enum
                    if traitType then
                        -- Get the trait definition using CharacterTraitDefinition
                        local traitDef = CharacterTraitDefinition.getCharacterTraitDefinition(traitType)

                        -- Get trait ID from the type
                        local traitId = nil
                        pcall(function()
                            if traitType.getName then
                                traitId = traitType:getName()
                            else
                                traitId = tostring(traitType)
                            end
                        end)

                        if traitId then
                            -- Clean up the trait ID (remove "base:" prefix if present)
                            traitId = string.gsub(traitId, "^base:", "")

                            -- Skip starting traits if baseline restriction is enabled
                            if excludeStarting and BurdJournals.isStartingTrait(player, traitId) then
                                -- Skip this trait - it was spawned with
                            else
                                local traitData = {
                                    name = traitId,
                                    cost = 0,
                                    isPositive = false
                                }

                                -- Get details from definition if available
                                if traitDef then
                                    pcall(function()
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

-- Collect ALL data for clean journal logging
function BurdJournals.collectAllPlayerData(player)
    if not player then return {} end
    
    return {
        skills = BurdJournals.collectPlayerSkills(player),
        traits = BurdJournals.collectPlayerTraits(player),
        character = BurdJournals.collectCharacterInfo(player),
        timestamp = getGameTime():getWorldAgeHours(),
        isPlayerCreated = true,
    }
end

-- ==================== PLAYER TRAIT CHECK ====================

function BurdJournals.playerHasTrait(player, traitId)
    -- Ultra-safe trait check: never throw, returns false on any unexpected state
    local ok, result = pcall(function()
        if not player then return false end
        if not traitId then return false end

        local traitObj = nil
        local traitIdLower = string.lower(traitId)
        local traitIdNorm = string.lower(traitId:gsub("%s", ""))

        -- METHOD 1 (PRIMARY): Use CharacterTraitDefinition to find trait by label/name
        -- This handles cases like "Wakeful" -> "needslesssleep", "Fast Learner" -> "fastlearner"
        if CharacterTraitDefinition and CharacterTraitDefinition.getTraits then
            local allTraits = CharacterTraitDefinition.getTraits()
            for i = 0, allTraits:size() - 1 do
                local def = allTraits:get(i)
                local defType = def:getType()
                local defLabel = def:getLabel() or ""
                local defName = ""

                if defType then
                    pcall(function()
                        defName = defType:getName() or tostring(defType)
                    end)
                end

                local defLabelLower = string.lower(defLabel)
                local defNameLower = string.lower(defName)
                local defLabelNorm = defLabelLower:gsub("%s", "")
                local defNameNorm = defNameLower:gsub("%s", "")

                -- Match by: exact, case-insensitive, normalized (no spaces), or partial
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

        -- METHOD 2: Try direct CharacterTrait lookups
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
                        local ok2, res = pcall(function()
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

        -- Check if player has the trait
        if traitObj and player.hasTrait then
            return player:hasTrait(traitObj) == true
        end

        -- Fallback: try old HasTrait method with string
        if type(player.HasTrait) == "function" then
            return player:HasTrait(traitId) == true
        end

        return false
    end)

    if ok then
        return result == true
    end

    -- Swallow any errors and report false
    print("[BurdJournals] playerHasTrait error (safe): " .. tostring(result))
    return false
end


-- ==================== DEBUG: DUMP ALL B42 TRAITS ====================

-- Call this once to see all available trait names in B42
function BurdJournals.dumpAllTraits()
    -- Debug removed
    if not CharacterTraitDefinition or not CharacterTraitDefinition.getTraits then
        -- Debug removed
        return
    end
    
    local allTraits = CharacterTraitDefinition.getTraits()
    -- Debug removed
    
    for i = 0, allTraits:size() - 1 do
        local def = allTraits:get(i)
        local defType = def:getType()
        local defLabel = def:getLabel() or "?"
        local defName = "?"
        
        if defType then
            pcall(function()
                defName = defType:getName() or tostring(defType)
            end)
        end
        
        print(string.format("[BurdJournals] [%d] Label='%s' Name='%s' Type=%s", i, defLabel, defName, tostring(defType)))
    end
    -- Debug removed
end

-- ==================== SAFE TRAIT ADDITION (Build 42 Compatible) ====================

function BurdJournals.safeAddTrait(player, traitId)
    if not player or not traitId then return false end

    -- Debug removed

    -- Already has trait? Early exit
    if BurdJournals.playerHasTrait(player, traitId) then
        -- Debug removed
        return true
    end

    local traitObj = nil
    local traitDef = nil
    local traitIdLower = string.lower(traitId)
    -- Normalize: remove spaces and lowercase for flexible matching
    local traitIdNorm = string.lower(traitId:gsub("%s", ""))

    -- METHOD 1 (PRIMARY): Use CharacterTraitDefinition.getTraits() iteration
    -- This is EXACTLY what ISPlayerStatsChooseTraitUI does - most reliable method
    if CharacterTraitDefinition and CharacterTraitDefinition.getTraits then
        local allTraits = CharacterTraitDefinition.getTraits()

        for i = 0, allTraits:size() - 1 do
            local def = allTraits:get(i)
            local defType = def:getType()
            local defLabel = def:getLabel() or ""
            local defName = ""

            -- Get the trait name safely
            if defType then
                pcall(function()
                    defName = defType:getName() or tostring(defType)
                end)
            end

            local defLabelLower = string.lower(defLabel)
            local defNameLower = string.lower(defName)
            -- Normalized versions (no spaces)
            local defLabelNorm = defLabelLower:gsub("%s", "")
            local defNameNorm = defNameLower:gsub("%s", "")

            -- Match by: exact, case-insensitive, normalized (no spaces), or partial
            local labelMatch = (defLabel == traitId)
            local nameMatch = (defName == traitId)
            local labelLowerMatch = (defLabelLower == traitIdLower)
            local nameLowerMatch = (defNameLower == traitIdLower)
            -- Normalized match: "FastLearner" matches "Fast Learner"
            local normalizedMatch = (defLabelNorm == traitIdNorm) or (defNameNorm == traitIdNorm)
            -- Partial match: trait name contains our search term or vice versa
            local partialMatch = defLabelLower:find(traitIdLower, 1, true) or traitIdLower:find(defLabelLower, 1, true)

            if labelMatch or nameMatch or labelLowerMatch or nameLowerMatch or normalizedMatch or partialMatch then
                traitDef = def
                traitObj = defType
                break
            end
        end
        
        -- Trait not found in iteration - will try other methods below
    else
        -- Debug removed
    end

    -- METHOD 2: Try CharacterTrait.get() with ResourceLocation
    if not traitObj and CharacterTrait and CharacterTrait.get and ResourceLocation and ResourceLocation.of then
        -- Debug removed

        -- Try various formats
        local formats = {
            "base:" .. string.lower(traitId),                                    -- base:wakeful
            "base:" .. string.lower(traitId:gsub("(%u)", " %1"):sub(2)),        -- base:fast learner
            "base:" .. string.lower(traitId:gsub("(%u)", "_%1"):sub(2)),        -- base:fast_learner
        }

        for _, resourceLoc in ipairs(formats) do
            local ok, result = pcall(function()
                return CharacterTrait.get(ResourceLocation.of(resourceLoc))
            end)
            if ok and result then
                traitObj = result
                break
            end
        end
    end

    -- METHOD 3: Try direct CharacterTrait table lookup
    if not traitObj and CharacterTrait then
        local lookups = {
            string.upper(traitId),                                              -- WAKEFUL
            traitId:gsub("(%u)", "_%1"):sub(2):upper(),                        -- FAST_LEARNER
            traitId,                                                            -- Wakeful
        }

        for _, key in ipairs(lookups) do
            local ct = CharacterTrait[key]
            if ct then
                if type(ct) == "string" and CharacterTrait.get and ResourceLocation and ResourceLocation.of then
                    local ok, result = pcall(function()
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

    -- Now try to add the trait
    if traitObj then

        -- Use the EXACT pattern from ISPlayerStatsUI:onAddTrait
        local ok, err = pcall(function()
            -- Step 1: Add to character traits
            player:getCharacterTraits():add(traitObj)
            -- Debug removed

            -- Step 2: Modify XP boost (use traitDef:getType() if available)
            local traitForBoost = traitDef and traitDef:getType() or traitObj
            if player.modifyTraitXPBoost then
                player:modifyTraitXPBoost(traitForBoost, false)
                -- Debug removed
            end

            -- Step 3: SYNC - critical for MP and persistence
            if SyncXp then
                SyncXp(player)
                -- Debug removed
            end
        end)


        -- If pcall succeeded, the trait was added - return success
        -- (Don't verify with playerHasTrait because traitId might be display name like "Wakeful"
        -- but the actual trait name is "needslesssleep")
        if ok then
            -- Debug removed
            return true
        else
        end
    else
    end

    -- Debug removed
    return false
end


