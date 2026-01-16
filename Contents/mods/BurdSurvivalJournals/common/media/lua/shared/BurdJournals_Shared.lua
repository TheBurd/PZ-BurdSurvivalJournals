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

-- ==================== DATA SAFETY LIMITS ====================
-- These limits prevent server/client issues with large journal payloads
-- Soft limits trigger warnings; hard limits prevent recording beyond capacity
-- MAX_SKILLS/TRAITS/RECIPES are read from sandbox settings (configurable by server admin)

BurdJournals.Limits = {
    -- Chunk sizes for batched recording (items per server command)
    CHUNK_SKILLS = 10,      -- Skills per chunk
    CHUNK_TRAITS = 10,      -- Traits per chunk
    CHUNK_RECIPES = 20,     -- Recipes per chunk
    CHUNK_STATS = 10,       -- Stats per chunk

    -- Soft limits (warnings shown at this threshold - 50% of max)
    -- These are calculated dynamically based on MAX values
    WARN_SKILLS = 25,       -- Default, will be recalculated
    WARN_TRAITS = 40,       -- Default, will be recalculated
    WARN_RECIPES = 200,     -- Default, will be recalculated

    -- Hard limits - now read from sandbox settings
    -- Note: After storage optimization (recipes/traits stored as boolean), higher limits are safe
    MAX_SKILLS = 50,        -- Default, sandbox setting: MaxSkillsPerJournal
    MAX_TRAITS = 100,       -- Default, sandbox setting: MaxTraitsPerJournal
    MAX_RECIPES = 500,      -- Default, sandbox setting: MaxRecipesPerJournal

    -- Delay between chunks in milliseconds (prevents server overload)
    CHUNK_DELAY_MS = 50,
}

-- ==================== MOD COMPATIBILITY API ====================
--[[
    Third-party mods can use these functions to integrate with Burd's Survival Journals.

    RECIPE COMPATIBILITY:
    The mod automatically scans ALL items in the game (including modded items) for magazines
    that teach recipes via getLearnedRecipes(). This means most mod magazines work automatically.

    However, if your mod needs custom behavior, use these registration functions:

    -- Register additional recipes that can be recorded (even if not from a magazine)
    BurdJournals.registerRecipe("MyMod.MyRecipeName", "MyMod.MyMagazine")

    -- Exclude a recipe from being recorded
    BurdJournals.excludeRecipe("MyMod.MySecretRecipe")

    -- Register a custom magazine type that teaches recipes
    BurdJournals.registerMagazine("MyMod.MyCustomMagazine", {"Recipe1", "Recipe2"})

    TRAIT COMPATIBILITY:
    Traits are automatically discovered via CharacterTraitDefinition.getTraits().
    Positive traits (cost > 0) are included by default.

    -- Register additional traits that can be granted
    BurdJournals.registerTrait("MyModTrait")

    -- Exclude a trait from being granted
    BurdJournals.excludeTrait("MyModSecretTrait")

    SKILL COMPATIBILITY:
    Skills are discovered via PerkFactory.PerkList automatically.
    All skills should work by default.

    IMPORTANT: Call registration functions in your mod's OnGameBoot or OnPreMapLoad event
    to ensure they run before the journal system initializes its caches.
]]

-- Storage for mod-registered content
BurdJournals.ModCompat = BurdJournals.ModCompat or {
    registeredRecipes = {},      -- recipeName -> magazineType
    excludedRecipes = {},        -- recipeName -> true
    registeredMagazines = {},    -- magazineType -> {recipes}
    registeredTraits = {},       -- traitId -> true
    excludedTraits = {},         -- traitId -> true
}

-- Register a recipe that can be recorded in journals
-- @param recipeName string - The internal recipe name (e.g., "MyMod.CraftWidget")
-- @param magazineType string (optional) - The magazine that teaches it (e.g., "MyMod.WidgetMagazine")
function BurdJournals.registerRecipe(recipeName, magazineType)
    if not recipeName then return false end
    BurdJournals.ModCompat.registeredRecipes[recipeName] = magazineType or "CustomRecipe"
    -- Clear cache to force rebuild
    BurdJournals._magazineRecipeCache = nil
    BurdJournals._magazineToRecipesCache = nil
    print("[BurdJournals] Registered recipe: " .. recipeName .. (magazineType and (" from " .. magazineType) or ""))
    return true
end

-- Exclude a recipe from being recorded in journals
-- @param recipeName string - The internal recipe name to exclude
function BurdJournals.excludeRecipe(recipeName)
    if not recipeName then return false end
    BurdJournals.ModCompat.excludedRecipes[recipeName] = true
    -- Clear cache to force rebuild
    BurdJournals._magazineRecipeCache = nil
    BurdJournals._magazineToRecipesCache = nil
    print("[BurdJournals] Excluded recipe: " .. recipeName)
    return true
end

-- Register a magazine that teaches recipes
-- @param magazineType string - The full item type (e.g., "MyMod.ElectronicsMagazine")
-- @param recipes table - Array of recipe names this magazine teaches
function BurdJournals.registerMagazine(magazineType, recipes)
    if not magazineType or not recipes then return false end
    BurdJournals.ModCompat.registeredMagazines[magazineType] = recipes
    -- Also register each recipe
    for _, recipeName in ipairs(recipes) do
        BurdJournals.ModCompat.registeredRecipes[recipeName] = magazineType
    end
    -- Clear cache to force rebuild
    BurdJournals._magazineRecipeCache = nil
    BurdJournals._magazineToRecipesCache = nil
    print("[BurdJournals] Registered magazine: " .. magazineType .. " with " .. #recipes .. " recipes")
    return true
end

-- Register a trait that can be granted via journals
-- @param traitId string - The trait ID (e.g., "MyModTrait")
function BurdJournals.registerTrait(traitId)
    if not traitId then return false end
    BurdJournals.ModCompat.registeredTraits[string.lower(traitId)] = true
    -- Clear cache to force rebuild
    BurdJournals._cachedGrantableTraits = nil
    BurdJournals._cachedAllTraits = nil
    print("[BurdJournals] Registered trait: " .. traitId)
    return true
end

-- Exclude a trait from being granted via journals
-- @param traitId string - The trait ID to exclude
function BurdJournals.excludeTrait(traitId)
    if not traitId then return false end
    BurdJournals.ModCompat.excludedTraits[string.lower(traitId)] = true
    -- Also add to the main exclusion list
    table.insert(BurdJournals.EXCLUDED_TRAITS, string.lower(traitId))
    -- Clear cache to force rebuild
    BurdJournals._cachedGrantableTraits = nil
    BurdJournals._cachedAllTraits = nil
    print("[BurdJournals] Excluded trait: " .. traitId)
    return true
end

-- Check if a recipe is excluded by mods
function BurdJournals.isRecipeExcluded(recipeName)
    if not recipeName then return false end
    return BurdJournals.ModCompat.excludedRecipes[recipeName] == true
end

-- Check if a trait is excluded by mods (checks both mod exclusions and main list)
function BurdJournals.isTraitExcludedByMod(traitId)
    if not traitId then return false end
    return BurdJournals.ModCompat.excludedTraits[string.lower(traitId)] == true
end

-- Get all mod-registered recipes (for cache building)
function BurdJournals.getModRegisteredRecipes()
    return BurdJournals.ModCompat.registeredRecipes
end

-- Get all mod-registered magazines (for cache building)
function BurdJournals.getModRegisteredMagazines()
    return BurdJournals.ModCompat.registeredMagazines
end

-- Get all mod-registered traits (for trait discovery)
function BurdJournals.getModRegisteredTraits()
    return BurdJournals.ModCompat.registeredTraits
end

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

-- Build flat list of all skills (fallback/base list)
BurdJournals.ALL_SKILLS = {}
for category, skills in pairs(BurdJournals.SKILL_CATEGORIES) do
    for _, skill in ipairs(skills) do
        table.insert(BurdJournals.ALL_SKILLS, skill)
    end
end

-- Cache for dynamically discovered skills
BurdJournals._cachedDiscoveredSkills = nil

-- Skills to exclude from discovery (passive stats, special perks, etc.)
BurdJournals.EXCLUDED_SKILLS = {
    -- These are special/passive and typically shouldn't be recorded
    "None",
    "MAX",
    -- Add any other special perks here
}

-- Dynamically discover all skills from PerkFactory (includes mod-added skills)
-- This runs at runtime after all mods have loaded their perks
function BurdJournals.discoverAllSkills(forceRefresh)
    -- Use cache if available
    if not forceRefresh and BurdJournals._cachedDiscoveredSkills then
        return BurdJournals._cachedDiscoveredSkills
    end

    local discoveredSkills = {}
    local excludedSet = {}

    -- Build excluded set for fast lookup
    for _, skillName in ipairs(BurdJournals.EXCLUDED_SKILLS) do
        excludedSet[string.lower(skillName)] = true
    end

    -- Also exclude skills already in our base list (to avoid duplicates)
    local baseSkillSet = {}
    for _, skill in ipairs(BurdJournals.ALL_SKILLS) do
        baseSkillSet[string.lower(skill)] = true
    end

    -- Start with our known base skills
    for _, skill in ipairs(BurdJournals.ALL_SKILLS) do
        table.insert(discoveredSkills, skill)
    end

    -- Try to discover additional skills from PerkFactory
    local modSkillsFound = 0
    if PerkFactory and PerkFactory.PerkList then
        local perkList = PerkFactory.PerkList
        if perkList and perkList:size() then
            for i = 0, perkList:size() - 1 do
                local perk = perkList:get(i)
                if perk then
                    local perkName = nil

                    -- Try to get the perk name
                    pcall(function()
                        if perk.getId then
                            perkName = tostring(perk:getId())
                        elseif perk.name then
                            perkName = tostring(perk.name())
                        else
                            perkName = tostring(perk)
                            -- Clean up Java class prefixes
                            perkName = perkName:gsub("^zombie%.characters%.skills%.PerkFactory%$Perk%.", "")
                            perkName = perkName:gsub("^Perks%.", "")
                        end
                    end)

                    if perkName and perkName ~= "" then
                        local perkNameLower = string.lower(perkName)

                        -- Skip excluded skills
                        if not excludedSet[perkNameLower] then
                            -- Skip if already in base list
                            if not baseSkillSet[perkNameLower] then
                                -- This is a mod-added skill!
                                table.insert(discoveredSkills, perkName)
                                baseSkillSet[perkNameLower] = true
                                modSkillsFound = modSkillsFound + 1
                            end
                        end
                    end
                end
            end
        end
    end

    if modSkillsFound > 0 then
        print("[BurdJournals] Discovered " .. modSkillsFound .. " mod-added skills (total: " .. #discoveredSkills .. ")")
    end

    BurdJournals._cachedDiscoveredSkills = discoveredSkills
    return discoveredSkills
end

-- Force refresh of skill cache (call after mods are loaded)
function BurdJournals.refreshSkillCache()
    BurdJournals._cachedDiscoveredSkills = nil
    print("[BurdJournals] Skill cache cleared - will rediscover on next access")
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

    -- Note: The following are excluded by default:
    -- "athletic", "strong", "stout", "fit" - Physical stats that affect character model
    -- "desensitized", "burglar", "marksman" etc. - Profession-only (cost=0)
    -- "axeman", "cook2", "mechanics2" etc. - Profession boosters (cost=0)
}

-- Traits that should never be grantable (physical body traits, etc.)
BurdJournals.EXCLUDED_TRAITS = {
    -- Physical stats that affect character model/base stats
    "athletic", "strong", "stout", "fit", "feeble", "unfit", "outofshape", "veryheavy", "weak",
    -- Permanent physical conditions
    "asthmatic", "deaf", "hardofhearing", "shortsighted", "eagleeyed",
    -- Illiterate - cannot read journals, and should never be granted
    "illiterate",
}

-- Cache for dynamically discovered traits
BurdJournals._cachedGrantableTraits = nil
BurdJournals._cachedAllTraits = nil

-- Cache for trait display names (traitId -> displayName)
BurdJournals._traitDisplayNameCache = {}

-- Get the display name for a trait (with proper capitalization)
-- This is used across the mod whenever we need to show a trait name to the user
-- Uses multiple fallback methods to ensure we always get a readable name
function BurdJournals.getTraitDisplayName(traitId)
    if not traitId then return "Unknown Trait" end

    -- Check cache first
    if BurdJournals._traitDisplayNameCache[traitId] then
        return BurdJournals._traitDisplayNameCache[traitId]
    end

    local displayName = nil

    -- Method 1: Try CharacterTraitDefinition (Build 42)
    if CharacterTraitDefinition and CharacterTraitDefinition.getTraits then
        pcall(function()
            local allTraits = CharacterTraitDefinition.getTraits()
            if allTraits then
                for i = 0, allTraits:size() - 1 do
                    local def = allTraits:get(i)
                    if def then
                        local thisTraitId = nil
                        pcall(function()
                            local traitType = def:getType()
                            if traitType and traitType.getName then
                                thisTraitId = traitType:getName()
                            elseif traitType then
                                thisTraitId = tostring(traitType)
                                thisTraitId = string.gsub(thisTraitId, "^base:", "")
                            end
                        end)

                        -- Check if this is the trait we're looking for (case-insensitive)
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

    -- Method 2: Try TraitFactory (Build 41 compatibility)
    if not displayName and TraitFactory and TraitFactory.getTrait then
        pcall(function()
            local trait = TraitFactory.getTrait(traitId)
            if trait and trait.getLabel then
                displayName = trait:getLabel()
            end
        end)
    end

    -- Method 3: Make traitId more readable (insert spaces before capitals)
    -- "FastLearner" -> "Fast Learner"
    if not displayName then
        displayName = traitId:gsub("(%l)(%u)", "%1 %2")
    end

    -- Cache the result
    BurdJournals._traitDisplayNameCache[traitId] = displayName

    return displayName
end

-- Dynamically discover all grantable traits from the game (including modded traits)
-- This runs once and caches the result
-- Parameters:
--   includeNegative: if true, includes negative traits (cost < 0)
--   forceRefresh: if true, rebuilds the cache
function BurdJournals.discoverGrantableTraits(includeNegative, forceRefresh)
    -- Check sandbox setting for negative traits if not explicitly specified
    if includeNegative == nil then
        includeNegative = BurdJournals.getSandboxOption("AllowNegativeTraits") or false
    end

    -- Use cache if available and not forcing refresh
    local cacheKey = includeNegative and "_cachedAllTraits" or "_cachedGrantableTraits"
    if not forceRefresh and BurdJournals[cacheKey] then
        return BurdJournals[cacheKey]
    end

    local discoveredTraits = {}
    local excludedSet = {}

    -- Build excluded set for fast lookup
    for _, traitId in ipairs(BurdJournals.EXCLUDED_TRAITS) do
        excludedSet[string.lower(traitId)] = true
    end

    -- Try to use CharacterTraitDefinition API (Build 42)
    if CharacterTraitDefinition and CharacterTraitDefinition.getTraits then
        local allTraits = CharacterTraitDefinition.getTraits()
        if allTraits then
            for i = 0, allTraits:size() - 1 do
                local def = allTraits:get(i)
                if def then
                    local traitId = nil
                    local cost = 0
                    local isPositive = true

                    -- Get trait ID
                    pcall(function()
                        local traitType = def:getType()
                        if traitType and traitType.getName then
                            traitId = traitType:getName()
                        elseif traitType then
                            traitId = tostring(traitType)
                            -- Clean up "base:" prefix if present
                            traitId = string.gsub(traitId, "^base:", "")
                        end
                    end)

                    -- Get cost to determine positive/negative
                    pcall(function()
                        cost = def:getCost() or 0
                    end)

                    isPositive = cost > 0

                    if traitId then
                        local traitIdLower = string.lower(traitId)

                        -- Skip excluded traits
                        if excludedSet[traitIdLower] then
                            -- Skip
                        -- Skip profession-only traits (cost = 0)
                        elseif cost == 0 then
                            -- Skip profession-only traits
                        -- Include positive traits always
                        elseif isPositive then
                            table.insert(discoveredTraits, traitId)
                        -- Include negative traits if allowed
                        elseif includeNegative and not isPositive then
                            table.insert(discoveredTraits, traitId)
                        end
                    end
                end
            end
        end
    end

    -- Add mod-registered traits
    local modTraits = BurdJournals.getModRegisteredTraits()
    local addedModTraits = 0
    for traitId, _ in pairs(modTraits) do
        -- Check if already in list
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

    -- If we discovered traits, use them; otherwise fall back to hardcoded list
    if #discoveredTraits > 0 then
        print("[BurdJournals] Discovered " .. #discoveredTraits .. " grantable traits dynamically (includeNegative=" .. tostring(includeNegative) .. ", modAdded=" .. addedModTraits .. ")")
        BurdJournals[cacheKey] = discoveredTraits
        return discoveredTraits
    else
        print("[BurdJournals] Using fallback hardcoded trait list (" .. #BurdJournals.GRANTABLE_TRAITS .. " traits)")
        return BurdJournals.GRANTABLE_TRAITS
    end
end

-- Get grantable traits (uses dynamic discovery with caching)
function BurdJournals.getGrantableTraits(includeNegative)
    return BurdJournals.discoverGrantableTraits(includeNegative, false)
end

-- Check if a trait is in the grantable list, including profession variants
-- Many mods (like SOTO) have paired traits: "traitname" (purchasable) and "traitname2" (profession-only)
-- This function checks both the exact ID and the base variant (without trailing "2")
function BurdJournals.isTraitGrantable(traitId, grantableList)
    if not traitId then return false end
    if not grantableList then
        grantableList = BurdJournals.getGrantableTraits()
    end

    local traitIdLower = string.lower(traitId)

    -- Direct check
    for _, grantable in ipairs(grantableList) do
        local grantableLower = string.lower(grantable)
        if traitIdLower == grantableLower then
            return true
        end
    end

    -- Check for profession variant pattern (e.g., "soto:slaughterer2" -> "soto:slaughterer")
    -- This handles mods that have paired traits where the "2" suffix is profession-only
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

-- Force refresh of trait cache (call after mods are loaded)
function BurdJournals.refreshTraitCache()
    BurdJournals._cachedGrantableTraits = nil
    BurdJournals._cachedAllTraits = nil
    print("[BurdJournals] Trait cache cleared - will rediscover on next access")
end

-- Debug function: Dump all discovered traits with details
-- Call from console: BurdJournals.debugDumpTraits()
function BurdJournals.debugDumpTraits()
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

    -- Categorize traits
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

            pcall(function()
                local traitType = def:getType()
                if traitType and traitType.getName then
                    traitId = traitType:getName()
                elseif traitType then
                    traitId = tostring(traitType)
                    traitId = string.gsub(traitId, "^base:", "")
                end
            end)

            pcall(function()
                traitLabel = def:getLabel() or traitId or "?"
            end)

            pcall(function()
                cost = def:getCost() or 0
            end)

            -- Try to detect mod source (heuristic: non-standard trait IDs often have prefixes)
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

    -- Print categorized results
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

    -- Summary
    print("=== SUMMARY ===")
    print("  Positive (grantable): " .. #positiveTraits)
    print("  Negative (with AllowNegativeTraits): " .. #negativeTraits)
    print("  Profession-only (excluded): " .. #professionTraits)
    print("  Physical/excluded: " .. #excludedTraits)
    print("  Total discoverable: " .. (#positiveTraits + #negativeTraits))
    print("")

    -- Check current sandbox setting
    local allowNeg = BurdJournals.getSandboxOption("AllowNegativeTraits") or false
    print("  Sandbox 'AllowNegativeTraits': " .. tostring(allowNeg))
    print("  Current getGrantableTraits() would return: " .. #BurdJournals.getGrantableTraits() .. " traits")

    print("==================== END TRAIT DISCOVERY DEBUG ==")
end

-- Debug function: Dump all discovered skills with details
-- Call from console: BurdJournals.debugDumpSkills()
function BurdJournals.debugDumpSkills()
    print("==================== BURD JOURNALS: SKILL DISCOVERY DEBUG ====================")

    -- Force refresh to get latest
    BurdJournals._cachedDiscoveredSkills = nil
    local allSkills = BurdJournals.discoverAllSkills(true)

    print("[BurdJournals] Total skills discovered: " .. #allSkills)
    print("")

    -- Categorize skills
    local vanillaSkills = {}
    local modSkills = {}

    -- Build set of base skills for comparison
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

    -- Try to list ALL perks from PerkFactory for comprehensive view
    print("=== RAW PERKFACTORY.PERKLIST ===")
    if PerkFactory and PerkFactory.PerkList then
        local perkList = PerkFactory.PerkList
        if perkList and perkList.size then
            local count = perkList:size()
            print("  PerkFactory.PerkList contains " .. count .. " entries")
            for i = 0, math.min(count - 1, 50) do  -- Limit to first 50
                local perk = perkList:get(i)
                if perk then
                    local name = "?"
                    pcall(function()
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

    print("==================== END SKILL DISCOVERY DEBUG ==")
end

-- ==================== PLAYER STATS (For player journals) ====================

-- Player statistics that can be recorded to journals
-- These represent character meta-information and achievements
BurdJournals.RECORDABLE_STATS = {
    -- ============ SURVIVAL MILESTONES ============
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

-- Helper to get localized stat name
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

-- Helper to get localized stat description
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

-- Translation keys for dissolution messages
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

-- Fallback messages in case translations aren't loaded
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
    -- If getText returns the key itself (translation not found), use fallback
    if translated == key then
        return BurdJournals.DissolutionFallbacks[index]
    end
    return translated
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
        LearningTimePerRecipe = 2.0,
        LearningTimeMultiplier = 1.0,
        -- Player stats recording
        EnableStatRecording = true,
        RecordZombieKills = true,
        RecordHoursSurvived = true,
        -- Recipe recording
        EnableRecipeRecording = true,
        -- Journal capacity limits
        MaxSkillsPerJournal = 50,
        MaxTraitsPerJournal = 100,
        MaxRecipesPerJournal = 500,
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

-- Initialize Limits metatable to read MAX_* values from sandbox settings dynamically
-- This must be done after getSandboxOption is defined
setmetatable(BurdJournals.Limits, {
    __index = function(t, key)
        -- Map MAX_* keys to sandbox option names
        if key == "MAX_SKILLS" then
            return BurdJournals.getSandboxOption("MaxSkillsPerJournal") or 50
        elseif key == "MAX_TRAITS" then
            return BurdJournals.getSandboxOption("MaxTraitsPerJournal") or 100
        elseif key == "MAX_RECIPES" then
            return BurdJournals.getSandboxOption("MaxRecipesPerJournal") or 500
        -- Calculate WARN_* as percentage of MAX_*
        elseif key == "WARN_SKILLS" then
            local maxSkills = BurdJournals.getSandboxOption("MaxSkillsPerJournal") or 50
            return math.floor(maxSkills * 0.5)
        elseif key == "WARN_TRAITS" then
            local maxTraits = BurdJournals.getSandboxOption("MaxTraitsPerJournal") or 100
            return math.floor(maxTraits * 0.4)
        elseif key == "WARN_RECIPES" then
            local maxRecipes = BurdJournals.getSandboxOption("MaxRecipesPerJournal") or 500
            return math.floor(maxRecipes * 0.4)
        end
        return rawget(t, key)
    end
})

-- ==================== JOURNAL OWNERSHIP & PERMISSIONS ====================

-- ==================== PLAYER IDENTIFICATION ====================
-- Steam ID is the primary identifier for ownership (persistent across servers)
-- Username is the fallback for legacy journals and non-Steam players
-- Character ID (SteamID + CharacterName) is used for per-character claim tracking

-- Get the player's Steam ID (primary identifier for ownership)
-- Returns Steam ID as string, or "local_username" for offline/non-Steam players
function BurdJournals.getPlayerSteamId(player)
    if not player then return nil end

    -- Try Steam ID first (most reliable for multiplayer)
    if player.getSteamID then
        local steamId = player:getSteamID()
        -- getSteamID() returns 0 or "" for non-Steam players
        if steamId and steamId ~= "" and steamId ~= 0 and tostring(steamId) ~= "0" then
            return tostring(steamId)
        end
    end

    -- Fallback to username for non-Steam (offline mode, GOG players, LAN)
    local username = player:getUsername()
    if username and username ~= "" then
        return "local_" .. username
    end

    return "local_unknown"
end

-- Get character-specific ID for claim tracking (SteamID + CharacterName)
-- This allows each character to claim independently, even on the same account
function BurdJournals.getPlayerCharacterId(player)
    if not player then return nil end

    local steamId = BurdJournals.getPlayerSteamId(player)
    if not steamId then return nil end

    -- Get character name (forename + surname)
    local descriptor = player:getDescriptor()
    if not descriptor then return steamId .. "_Unknown" end

    local forename = descriptor:getForename() or "Unknown"
    local surname = descriptor:getSurname() or ""
    local charName = forename .. "_" .. surname

    -- Sanitize character name (replace spaces with underscores)
    charName = string.gsub(charName, " ", "_")

    return steamId .. "_" .. charName
end

-- Get the owner Steam ID of a journal
function BurdJournals.getJournalOwnerSteamId(item)
    if not item then return nil end
    local modData = item:getModData()
    if modData.BurdJournals and modData.BurdJournals.ownerSteamId then
        return modData.BurdJournals.ownerSteamId
    end
    return nil
end

-- ==================== JOURNAL OWNERSHIP GETTERS ====================

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
-- Uses a 3-tier fallback system: Steam ID -> Username -> Character Name
function BurdJournals.isJournalOwner(player, item)
    if not player or not item then return false end

    local modData = item:getModData()
    if not modData.BurdJournals then return true end  -- No data = anyone can use

    local journalData = modData.BurdJournals

    -- PRIMARY: Check ownerSteamId field (new format - most reliable)
    local ownerSteamId = journalData.ownerSteamId
    if ownerSteamId then
        local playerSteamId = BurdJournals.getPlayerSteamId(player)
        if playerSteamId then
            -- Direct Steam ID match
            if ownerSteamId == playerSteamId then
                return true
            end
            -- If journal has Steam ID but player doesn't match, check legacy fallbacks
            -- (owner might have migrated from legacy journal)
        end
    end

    -- FALLBACK 1: Check ownerUsername field (for legacy journals without Steam ID)
    local ownerUsername = journalData.ownerUsername
    if ownerUsername then
        local playerUsername = player:getUsername()
        if playerUsername and ownerUsername == playerUsername then
            return true
        end
    end

    -- FALLBACK 2: For older journals, check author against character's full name
    local author = journalData.author
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

    -- No ownership info = allow (non-player created journals like worn/bloody)
    if not ownerSteamId and not ownerUsername and not author then
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

-- ==================== PER-CHARACTER CLAIM TRACKING ====================
-- Claims are tracked per-character (SteamID + CharacterName) so that:
-- 1. Each character can claim independently from the same journal
-- 2. Different characters on the same Steam account can each claim
-- 3. Legacy claims are migrated but don't block new characters

-- Initialize the claims structure for a journal if needed
function BurdJournals.initClaimsStructure(journalData)
    if not journalData then return end
    if not journalData.claims then
        journalData.claims = {}
    end
end

-- Get or create the claim entry for a specific character
function BurdJournals.getCharacterClaims(journalData, player)
    if not journalData or not player then return nil end

    local characterId = BurdJournals.getPlayerCharacterId(player)
    if not characterId then return nil end

    BurdJournals.initClaimsStructure(journalData)

    if not journalData.claims[characterId] then
        journalData.claims[characterId] = {
            skills = {},
            traits = {},
            recipes = {}
        }
    end

    return journalData.claims[characterId]
end

-- Check if a character has claimed a specific skill from a journal
function BurdJournals.hasCharacterClaimedSkill(journalData, player, skillName)
    if not journalData or not player or not skillName then return false end

    local characterId = BurdJournals.getPlayerCharacterId(player)
    if not characterId then return false end

    -- Check new per-character claims structure
    if journalData.claims and journalData.claims[characterId] then
        if journalData.claims[characterId].skills and journalData.claims[characterId].skills[skillName] then
            return true
        end
    end

    -- Note: We intentionally DO NOT fall back to legacy claimedSkills
    -- This ensures new characters can claim from existing worn/bloody journals
    return false
end

-- Check if a character has claimed a specific trait from a journal
function BurdJournals.hasCharacterClaimedTrait(journalData, player, traitId)
    if not journalData or not player or not traitId then return false end

    local characterId = BurdJournals.getPlayerCharacterId(player)
    if not characterId then return false end

    -- Check new per-character claims structure
    if journalData.claims and journalData.claims[characterId] then
        if journalData.claims[characterId].traits and journalData.claims[characterId].traits[traitId] then
            return true
        end
    end

    return false
end

-- Check if a character has claimed a specific recipe from a journal
function BurdJournals.hasCharacterClaimedRecipe(journalData, player, recipeName)
    if not journalData or not player or not recipeName then return false end

    local characterId = BurdJournals.getPlayerCharacterId(player)
    if not characterId then return false end

    -- Check new per-character claims structure
    if journalData.claims and journalData.claims[characterId] then
        if journalData.claims[characterId].recipes and journalData.claims[characterId].recipes[recipeName] then
            return true
        end
    end

    return false
end

-- Mark a skill as claimed by a specific character
function BurdJournals.markSkillClaimedByCharacter(journalData, player, skillName)
    if not journalData or not player or not skillName then return false end

    local claims = BurdJournals.getCharacterClaims(journalData, player)
    if not claims then return false end

    claims.skills[skillName] = true

    -- Also update legacy field for backward compatibility with old UI/displays
    if not journalData.claimedSkills then
        journalData.claimedSkills = {}
    end
    journalData.claimedSkills[skillName] = true

    return true
end

-- Mark a trait as claimed by a specific character
function BurdJournals.markTraitClaimedByCharacter(journalData, player, traitId)
    if not journalData or not player or not traitId then return false end

    local claims = BurdJournals.getCharacterClaims(journalData, player)
    if not claims then return false end

    claims.traits[traitId] = true

    -- Also update legacy field for backward compatibility
    if not journalData.claimedTraits then
        journalData.claimedTraits = {}
    end
    journalData.claimedTraits[traitId] = true

    return true
end

-- Mark a recipe as claimed by a specific character
function BurdJournals.markRecipeClaimedByCharacter(journalData, player, recipeName)
    if not journalData or not player or not recipeName then return false end

    local claims = BurdJournals.getCharacterClaims(journalData, player)
    if not claims then return false end

    claims.recipes[recipeName] = true

    -- Also update legacy field for backward compatibility
    if not journalData.claimedRecipes then
        journalData.claimedRecipes = {}
    end
    journalData.claimedRecipes[recipeName] = true

    return true
end

-- ==================== JOURNAL MIGRATION ====================
-- Migrate legacy journals to the new ownership/claims format

function BurdJournals.migrateJournalIfNeeded(item, player)
    if not item then return end

    local modData = item:getModData()
    if not modData.BurdJournals then return end

    local journalData = modData.BurdJournals
    local migrated = false

    -- Migration 1: Add Steam ID to journals that don't have it
    -- Only migrate if we can determine the owner (player is the owner)
    if not journalData.ownerSteamId and journalData.ownerUsername and player then
        local playerUsername = player:getUsername()
        if playerUsername and journalData.ownerUsername == playerUsername then
            -- This player is the owner, add their Steam ID
            journalData.ownerSteamId = BurdJournals.getPlayerSteamId(player)
            migrated = true
            print("[BurdJournals] Migrated journal ownership: added Steam ID " .. tostring(journalData.ownerSteamId))
        end
    end

    -- Migration 2: Mark legacy journals without Steam ID
    if not journalData.ownerSteamId and journalData.ownerUsername then
        -- Can't recover Steam ID from username alone, mark as legacy
        journalData.ownerSteamId = "legacy_" .. journalData.ownerUsername
        migrated = true
        print("[BurdJournals] Marked legacy journal with placeholder Steam ID: " .. journalData.ownerSteamId)
    end

    -- Migration 3: Migrate legacy claims to per-character structure
    -- Note: We do NOT move legacy claims to block new characters
    -- Instead, we just initialize the claims structure if missing
    if (journalData.claimedSkills or journalData.claimedTraits or journalData.claimedRecipes) and not journalData.claims then
        -- Initialize claims structure but put legacy claims under special key
        -- This preserves the display of what's been claimed while allowing new chars to claim
        journalData.claims = {}
        journalData.claims["legacy_unknown"] = {
            skills = journalData.claimedSkills or {},
            traits = journalData.claimedTraits or {},
            recipes = journalData.claimedRecipes or {}
        }
        migrated = true
        print("[BurdJournals] Migrated legacy claims to per-character structure")
    end

    -- If we migrated, sync the data
    if migrated then
        item:transmitModData()
    end
end

function BurdJournals.isDebug()
    return isDebugEnabled and isDebugEnabled() or false
end

-- ==================== SKILL UTILITIES ====================

function BurdJournals.isSkillAllowed(skillName)
    local allowedSkills = BurdJournals.getAllowedSkills()
    for _, skill in ipairs(allowedSkills) do
        if skill == skillName or string.lower(skill) == string.lower(skillName) then
            return true
        end
    end
    return false
end

-- Get all allowed skills (uses dynamic discovery to include mod-added skills)
function BurdJournals.getAllowedSkills()
    -- Use dynamic discovery which includes mod-added skills
    return BurdJournals.discoverAllSkills()
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

-- Check if journal should dissolve (all skills, traits, and recipes claimed)
function BurdJournals.shouldDissolve(item)
    if not item then return false end
    -- Both worn and bloody journals dissolve when fully consumed
    if not BurdJournals.isWorn(item) and not BurdJournals.isBloody(item) then return false end

    -- Safety: Don't dissolve if journal has no valid data (prevents premature dissolution on corrupted data)
    local data = BurdJournals.getJournalData(item)
    if not data or not data.skills then return false end

    local unclaimedSkills = BurdJournals.getUnclaimedSkillCount(item)
    local unclaimedTraits = BurdJournals.getUnclaimedTraitCount(item)
    local unclaimedRecipes = BurdJournals.getUnclaimedRecipeCount(item)

    return unclaimedSkills == 0 and unclaimedTraits == 0 and unclaimedRecipes == 0
end

-- Get remaining rewards count for display
function BurdJournals.getRemainingRewards(item)
    local skills = BurdJournals.getUnclaimedSkillCount(item)
    local traits = BurdJournals.getUnclaimedTraitCount(item)
    local recipes = BurdJournals.getUnclaimedRecipeCount(item)
    return skills + traits + recipes
end

function BurdJournals.getTotalRewards(item)
    local skills = BurdJournals.getTotalSkillCount(item)
    local data = BurdJournals.getJournalData(item)
    local traits = data and data.traits and BurdJournals.countTable(data.traits) or 0
    local recipes = data and data.recipes and BurdJournals.countTable(data.recipes) or 0
    return skills + traits + recipes
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

-- Helper to safely get translated text with proper fallback
-- getText() returns the key itself when translation is missing, not nil
function BurdJournals.safeGetText(key, fallback)
    if not key then return fallback end
    local result = getText(key)
    -- If getText returns the key itself (untranslated), use the fallback
    if result == key then
        return fallback
    end
    return result or fallback
end

-- Compute the localized display name for a journal based on current client's language
-- This is a pure function that does NOT modify the item - just returns the name string
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

        -- For player journals, show the author name (character name)
        -- For found journals (non-player), show the profession
        if isPlayerCreated and author then
            -- Player-created journal: show character name
            table.insert(suffixParts, author)
        elseif not isPlayerCreated and professionName then
            -- Found journal: show profession
            -- Don't add "Previous" if name already starts with "Former" (zombie professions)
            if string.find(professionName, "^Former") or string.find(professionName, "^Previous") then
                table.insert(suffixParts, professionName)
            else
                local prevFormat = BurdJournals.safeGetText("UI_BurdJournals_PreviousProfession", "Previous %s")
                table.insert(suffixParts, string.format(prevFormat, professionName))
            end
        elseif author then
            -- Fallback: show author if available (for any journal type)
            table.insert(suffixParts, author)
        end

        if #suffixParts > 0 then
            baseName = baseName .. " (" .. table.concat(suffixParts, " - ") .. ")"
        end
    end

    return baseName
end

-- Client-side cache to track which items we've already localized this session
-- This is NOT synced to server - each client maintains their own cache
BurdJournals._localizedItems = BurdJournals._localizedItems or {}

-- Clear the local cache (call on game reload, etc.)
function BurdJournals.clearLocalizedItemsCache()
    BurdJournals._localizedItems = {}
end

-- Update the journal's display name for the LOCAL client only
-- IMPORTANT: In multiplayer, this does NOT sync the name to other players!
-- Each client computes their own localized name based on their language.
--
-- Parameters:
--   item: the journal item
--   forceUpdate: if true, will update even if already localized
function BurdJournals.updateJournalName(item, forceUpdate)
    if not item then return end

    local modData = item:getModData()
    local data = modData.BurdJournals or {}

    -- If journal has a custom name set by player, always use that
    if data.customName then
        if item:getName() ~= data.customName then
            item:setName(data.customName)
        end
        return
    end

    -- Use item ID to track what we've already localized this session
    -- This prevents redundant updates on inventory transfers
    local itemId = item:getID()
    if not forceUpdate and BurdJournals._localizedItems[itemId] then
        -- Already localized this item this session
        return
    end

    -- Check if the current name looks like it needs localization
    -- (contains internal key patterns or looks like a raw item type)
    local currentName = item:getName()
    local needsLocalization = not currentName
        or currentName == ""
        or currentName:find("UI_BurdJournals_")
        or currentName:find("^Item_")
        or currentName:find("^BurdJournals%.")
        or currentName:find("BlankSurvivalJournal")
        or currentName:find("FilledSurvivalJournal")

    -- For non-player-created journals (worn/bloody found in world), ALWAYS re-localize
    -- This ensures each client sees the name in their own language
    -- The server sets a name in English, but the client should override with localized version
    local isNonPlayerJournal = not data.isPlayerCreated and (data.isWorn or data.isBloody or data.wasFromBloody)
    if isNonPlayerJournal then
        needsLocalization = true
    end

    -- If already has a localized-looking name and not forced, just mark as done
    if not needsLocalization and not forceUpdate then
        BurdJournals._localizedItems[itemId] = true
        return
    end

    -- Compute and apply the localized name for THIS client
    local baseName = BurdJournals.computeLocalizedName(item)

    if baseName and item.setName then
        item:setName(baseName)
        -- Mark as localized for this session (client-side only, not synced!)
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

-- ==================== SHARED PROFESSION DATA ====================
-- This is available on both client and server for OnCreate callbacks

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

-- Get a random profession (available on both client and server)
-- Returns: professionId, professionName, flavorKey
function BurdJournals.getRandomProfession()
    local professions = BurdJournals.PROFESSIONS
    local prof = professions[ZombRand(#professions) + 1]
    -- Use translated name if available, fallback to English
    local profName = prof.nameKey and getText(prof.nameKey) or prof.name
    return prof.id, profName, prof.flavorKey
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
    if not traitId then return false end
    local modData = player:getModData()
    if not modData.BurdJournals then return false end
    if not modData.BurdJournals.traitBaseline then return false end
    -- Check both exact case and lowercase for consistency
    return modData.BurdJournals.traitBaseline[traitId] == true 
        or modData.BurdJournals.traitBaseline[string.lower(traitId)] == true
end

-- Get the full trait baseline table for a player
function BurdJournals.getTraitBaseline(player)
    if not player then return {} end
    local modData = player:getModData()
    if not modData.BurdJournals then return {} end
    return modData.BurdJournals.traitBaseline or {}
end

-- Check if a recipe is part of the player's starting baseline
function BurdJournals.isStartingRecipe(player, recipeName)
    if not player then return false end
    if not recipeName then return false end
    local modData = player:getModData()
    if not modData.BurdJournals then return false end
    if not modData.BurdJournals.recipeBaseline then return false end
    return modData.BurdJournals.recipeBaseline[recipeName] == true
end

-- Get the full recipe baseline table for a player
function BurdJournals.getRecipeBaseline(player)
    if not player then return {} end
    local modData = player:getModData()
    if not modData.BurdJournals then return {} end
    return modData.BurdJournals.recipeBaseline or {}
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
        recipes = BurdJournals.collectPlayerMagazineRecipes(player),
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

-- Check if a player has the Illiterate trait (blocks journal usage)
function BurdJournals.isPlayerIlliterate(player)
    if not player then return false end
    return BurdJournals.playerHasTrait(player, "illiterate")
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

            -- Step 2: Modify XP boost (use traitDef:getType() if available)
            local traitForBoost = traitDef and traitDef:getType() or traitObj
            if player.modifyTraitXPBoost then
                player:modifyTraitXPBoost(traitForBoost, false)
            end

            -- Step 3: Apply perk boosts from trait (e.g., Gardener gives +1 Farming)
            -- Instead of setting to a fixed level, we ADD levels relative to current level
            -- This way a +1 Farming trait always grants one full level's worth of XP
            -- NOTE: xpBoosts iteration is handled in a separate protected call below

            -- Step 4: SYNC - critical for MP and persistence
            if SyncXp then
                SyncXp(player)
            end
        end)


        -- If pcall succeeded, the trait was added - now apply skill bonuses
        -- (Don't verify with playerHasTrait because traitId might be display name like "Wakeful"
        -- but the actual trait name is "needslesssleep")
        if ok then
            -- Apply skill level bonuses from traits (e.g., Gardener gives +1 Farming)
            -- modifyTraitXPBoost only affects XP gain RATE, not starting levels!
            -- We need to manually grant the skill XP for the bonus levels
            if traitDef and traitDef.getXpBoosts and transformIntoKahluaTable then
                local applyOk, applyErr = pcall(function()
                    local xpBoosts = transformIntoKahluaTable(traitDef:getXpBoosts())
                    if xpBoosts then
                        for perk, level in pairs(xpBoosts) do
                            local perkId = tostring(perk)
                            local levelNum = tonumber(tostring(level))
                            if levelNum and levelNum > 0 then
                                -- Get the perk object to calculate XP needed
                                local perkObj = Perks and Perks[perkId]
                                if perkObj and perkObj.getTotalXpForLevel then
                                    -- Get player's current level in this skill
                                    local currentLevel = 0
                                    if player.getPerkLevel then
                                        currentLevel = player:getPerkLevel(perkObj) or 0
                                    end
                                    -- Calculate XP needed to reach current + bonus level
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

            -- Sync again after applying XP
            if SyncXp then
                SyncXp(player)
            end

            return true
        else
        end
    else
    end

    -- Debug removed
    return false
end

-- ==================== RECIPE TRACKING (Magazine Recipes) ====================

-- Cache for magazine recipes (recipeName -> magazineItemType)
BurdJournals._magazineRecipeCache = nil

-- Build a cache of all recipes that come from magazines
-- Maps recipe name -> magazine item full type that teaches it
-- Includes mod-registered recipes and excludes mod-excluded recipes
function BurdJournals.buildMagazineRecipeCache(forceRefresh)
    if not forceRefresh and BurdJournals._magazineRecipeCache then
        return BurdJournals._magazineRecipeCache
    end

    local cache = {}

    -- First, add mod-registered recipes
    local modRecipes = BurdJournals.getModRegisteredRecipes()
    for recipeName, magazineType in pairs(modRecipes) do
        if not BurdJournals.isRecipeExcluded(recipeName) then
            cache[recipeName] = magazineType
            print("[BurdJournals] Added mod-registered recipe: " .. recipeName)
        end
    end

    -- Iterate through all script items to find magazines with LearnedRecipes
    local ok, err = pcall(function()
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
                pcall(function()
                    learnedRecipes = script:getLearnedRecipes()
                end)

                if learnedRecipes and not learnedRecipes:isEmpty() then
                    local fullType = script:getFullName()
                    print("[BurdJournals] Found magazine with recipes: " .. tostring(fullType))
                    for j = 0, learnedRecipes:size() - 1 do
                        local recipeName = learnedRecipes:get(j)
                        if recipeName then
                            -- Skip excluded recipes
                            if BurdJournals.isRecipeExcluded(recipeName) then
                                print("[BurdJournals]   - Recipe (EXCLUDED): " .. tostring(recipeName))
                            else
                                print("[BurdJournals]   - Recipe: " .. tostring(recipeName))
                                -- Store the first magazine that teaches this recipe
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

-- Check if a recipe is learned from a magazine (vs innate/profession)
function BurdJournals.isMagazineRecipe(recipeName)
    local cache = BurdJournals.buildMagazineRecipeCache()
    return cache[recipeName] ~= nil
end

-- Get the magazine item type that teaches a recipe
function BurdJournals.getMagazineForRecipe(recipeName)
    local cache = BurdJournals.buildMagazineRecipeCache()
    return cache[recipeName]
end

-- Build a reverse cache: magazineFullType -> list of recipe names
-- This allows us to look up recipes by which magazine was read
-- Includes mod-registered magazines and excludes mod-excluded recipes
function BurdJournals.buildMagazineToRecipesCache(forceRefresh)
    if not forceRefresh and BurdJournals._magazineToRecipesCache then
        return BurdJournals._magazineToRecipesCache
    end

    local cache = {}

    -- First, add mod-registered magazines
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

    local ok, err = pcall(function()
        local scriptManager = getScriptManager()
        if not scriptManager then return end

        local allItems = scriptManager:getAllItems()
        if not allItems then return end

        for i = 0, allItems:size() - 1 do
            local script = allItems:get(i)
            if script then
                local learnedRecipes = nil
                pcall(function()
                    learnedRecipes = script:getLearnedRecipes()
                end)

                if learnedRecipes and not learnedRecipes:isEmpty() then
                    local fullType = script:getFullName()
                    local recipeList = cache[fullType] or {}  -- Preserve mod-registered recipes
                    for j = 0, learnedRecipes:size() - 1 do
                        local recipeName = learnedRecipes:get(j)
                        if recipeName and not BurdJournals.isRecipeExcluded(recipeName) then
                            -- Avoid duplicates
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

-- Get all magazine recipes known by a player
-- Returns table: { recipeName = true }
-- Uses Build 42's APIs with multiple fallback methods for maximum compatibility
-- Parameters:
--   player: the player object
--   excludeStarting: if true/nil, excludes recipes in baseline when baseline restriction enabled
--                    if false, includes all recipes (used for baseline capture)
function BurdJournals.collectPlayerMagazineRecipes(player, excludeStarting)
    if not player then
        print("[BurdJournals] collectPlayerMagazineRecipes: no player")
        return {}
    end

    -- Check if recipe recording is enabled
    if not BurdJournals.getSandboxOption("EnableRecipeRecording") then
        print("[BurdJournals] collectPlayerMagazineRecipes: recipe recording disabled")
        return {}
    end

    -- If excludeStarting not specified, check sandbox option
    if excludeStarting == nil then
        excludeStarting = BurdJournals.isBaselineRestrictionEnabled()
    end

    local recipes = {}

    -- Build magazine -> recipes cache
    local magToRecipes = BurdJournals.buildMagazineToRecipesCache()
    local recipeToMag = BurdJournals.buildMagazineRecipeCache()

    local magCount = 0
    for _ in pairs(magToRecipes) do magCount = magCount + 1 end
    print("[BurdJournals] collectPlayerMagazineRecipes: checking " .. magCount .. " magazine types")

    local ok, err = pcall(function()
        -- Method 1 (PRIMARY): Use isRecipeKnown() to check each magazine recipe directly
        -- This is the most reliable B42 method
        print("[BurdJournals] Method 1: Using isRecipeKnown() for each magazine recipe...")
        local method1Count = 0

        if player.isRecipeKnown then
            for magazineType, recipeList in pairs(magToRecipes) do
                for _, recipeName in ipairs(recipeList) do
                    if not recipes[recipeName] then
                        local isKnown = false
                        pcall(function()
                            isKnown = player:isRecipeKnown(recipeName)
                        end)
                        if isKnown then
                            method1Count = method1Count + 1
                            recipes[recipeName] = true  -- Simplified: just mark recipe as known
                        end
                    end
                end
            end
            print("[BurdJournals] Method 1 (isRecipeKnown): found " .. method1Count .. " known recipes")
        else
            print("[BurdJournals] Method 1: isRecipeKnown not available, skipping")
        end

        -- Method 2: Check getAlreadyReadPages for each magazine type
        -- In B42, when a player reads a magazine fully, the pages read = total pages
        print("[BurdJournals] Method 2: Checking getAlreadyReadPages for each magazine...")
        local method2Count = 0

        for magazineType, recipeList in pairs(magToRecipes) do
            local pagesRead = 0
            pcall(function()
                pagesRead = player:getAlreadyReadPages(magazineType) or 0
            end)

            -- If pages read > 0, they've read this magazine (magazines typically have 1 page)
            if pagesRead > 0 then
                for _, recipeName in ipairs(recipeList) do
                    if not recipes[recipeName] then
                        method2Count = method2Count + 1
                        recipes[recipeName] = true  -- Simplified: just mark recipe as known
                    end
                end
            end
        end
        print("[BurdJournals] Method 2 (getAlreadyReadPages): found " .. method2Count .. " additional recipes")

        -- Method 3: Check getAlreadyReadBook list as fallback
        print("[BurdJournals] Method 3: Checking getAlreadyReadBook list...")
        local method3Count = 0
        local readBooks = nil
        pcall(function()
            readBooks = player:getAlreadyReadBook()
        end)

        if readBooks then
            local hasSize, bookCount = pcall(function() return readBooks:size() end)
            if hasSize and bookCount then
                print("[BurdJournals] Method 3: player has " .. bookCount .. " items in getAlreadyReadBook")
                for i = 0, bookCount - 1 do
                    local bookType = nil
                    pcall(function() bookType = readBooks:get(i) end)
                    if bookType then
                        local recipeList = magToRecipes[tostring(bookType)]
                        if recipeList then
                            for _, recipeName in ipairs(recipeList) do
                                if not recipes[recipeName] then
                                    method3Count = method3Count + 1
                                    recipes[recipeName] = true  -- Simplified: just mark recipe as known
                                end
                            end
                        end
                    end
                end
            end
        else
            print("[BurdJournals] Method 3: getAlreadyReadBook returned nil")
        end
        print("[BurdJournals] Method 3 (getAlreadyReadBook): found " .. method3Count .. " additional recipes")

        -- Method 4: Check getKnownRecipes list (for recipes learned via learnRecipe())
        print("[BurdJournals] Method 4: Checking getKnownRecipes...")
        local method4Count = 0
        local knownRecipes = nil
        pcall(function()
            knownRecipes = player:getKnownRecipes()
        end)

        if knownRecipes then
            local hasSize, recipeCount = pcall(function() return knownRecipes:size() end)
            if hasSize and recipeCount and recipeCount > 0 then
                print("[BurdJournals] Method 4: player has " .. recipeCount .. " items in getKnownRecipes")
                for i = 0, recipeCount - 1 do
                    local recipeName = nil
                    pcall(function() recipeName = knownRecipes:get(i) end)
                    if recipeName then
                        recipeName = tostring(recipeName)
                        local magazineType = recipeToMag[recipeName]
                        if magazineType and not recipes[recipeName] then
                            method4Count = method4Count + 1
                            recipes[recipeName] = true  -- Simplified: just mark recipe as known
                        end
                    end
                end
            end
        end
        print("[BurdJournals] Method 4 (getKnownRecipes): found " .. method4Count .. " additional recipes")
    end)

    if not ok then
        print("[BurdJournals] collectPlayerMagazineRecipes error: " .. tostring(err))
    end

    local foundCount = 0
    for _ in pairs(recipes) do foundCount = foundCount + 1 end
    print("[BurdJournals] collectPlayerMagazineRecipes: TOTAL found " .. foundCount .. " magazine recipes known by player")

    -- Filter out starting recipes if baseline restriction is enabled
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
            print("[BurdJournals] collectPlayerMagazineRecipes: Excluded " .. excludedCount .. " starting recipes from baseline")
        end
        return filteredRecipes
    end

    return recipes
end

-- Check if player knows a specific recipe
-- Uses Build 42-compatible detection methods with multiple fallbacks
-- Priority: isRecipeKnown() > getKnownRecipes():contains() > magazine read status
function BurdJournals.playerKnowsRecipe(player, recipeName)
    if not player or not recipeName then return false end

    -- Enable verbose debug logging (set to false in production)
    local DEBUG_RECIPE_CHECK = false

    local ok, result = pcall(function()
        -- Method 1 (PRIMARY): Use isRecipeKnown() - the B42 dedicated API
        -- This is the most reliable method in Build 42
        if player.isRecipeKnown then
            local known = player:isRecipeKnown(recipeName)
            if known then
                if DEBUG_RECIPE_CHECK then
                    print("[BurdJournals DEBUG] playerKnowsRecipe(" .. recipeName .. ") -> TRUE via isRecipeKnown()")
                end
                return true
            end
        end

        -- Method 2: Check getKnownRecipes list (ArrayList<String>)
        -- This works for recipes learned via learnRecipe()
        local knownRecipes = player:getKnownRecipes()
        if knownRecipes then
            -- Try contains() first (ArrayList method)
            local hasContains, containsResult = pcall(function()
                return knownRecipes:contains(recipeName)
            end)
            if hasContains and containsResult then
                if DEBUG_RECIPE_CHECK then
                    print("[BurdJournals DEBUG] playerKnowsRecipe(" .. recipeName .. ") -> TRUE via getKnownRecipes():contains()")
                end
                return true
            end

            -- Fallback: iterate through the list
            local hasSize, listSize = pcall(function() return knownRecipes:size() end)
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

        -- Method 3: Check if player has read the magazine that teaches this recipe
        -- Magazine-based recipes may not appear in getKnownRecipes until crafting
        local magazineType = BurdJournals.getMagazineForRecipe(recipeName)
        if magazineType then
            -- Check getAlreadyReadPages for this magazine
            local pagesRead = player:getAlreadyReadPages(magazineType) or 0
            if pagesRead > 0 then
                if DEBUG_RECIPE_CHECK then
                    print("[BurdJournals DEBUG] playerKnowsRecipe(" .. recipeName .. ") -> TRUE via getAlreadyReadPages(" .. magazineType .. ")=" .. pagesRead)
                end
                return true
            end

            -- Check getAlreadyReadBook list (ArrayList<String>)
            local readBooks = player:getAlreadyReadBook()
            if readBooks then
                local hasSize, bookCount = pcall(function() return readBooks:size() end)
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

-- Validate that a recipe name exists in the game's recipe list
-- Returns the exact recipe name if found, nil otherwise
-- This helps catch typos and case-sensitivity issues
function BurdJournals.validateRecipeName(recipeName)
    if not recipeName then return nil end

    local ok, result = pcall(function()
        local recipes = getAllRecipes()
        if not recipes then return nil end

        -- First try exact match
        for i = 0, recipes:size() - 1 do
            local recipe = recipes:get(i)
            if recipe then
                local name = recipe:getName()
                if name == recipeName then
                    return name  -- Exact match found
                end
            end
        end

        -- Try case-insensitive match
        local recipeNameLower = string.lower(recipeName)
        for i = 0, recipes:size() - 1 do
            local recipe = recipes:get(i)
            if recipe then
                local name = recipe:getName()
                if name and string.lower(name) == recipeNameLower then
                    return name  -- Case-insensitive match, return correct casing
                end
            end
        end

        return nil
    end)

    if ok then return result end
    return nil
end

-- Get the Recipe object by name (useful for advanced operations)
function BurdJournals.getRecipeByName(recipeName)
    if not recipeName then return nil end

    local ok, result = pcall(function()
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

-- Learn a recipe with comprehensive verification
-- Returns true if recipe was successfully learned, false otherwise
-- Includes detailed logging for debugging
function BurdJournals.learnRecipeWithVerification(player, recipeName, logPrefix)
    if not player or not recipeName then return false end
    logPrefix = logPrefix or "[BurdJournals]"

    -- Check if already known
    if BurdJournals.playerKnowsRecipe(player, recipeName) then
        print(logPrefix .. " Recipe already known: " .. recipeName)
        return true
    end

    -- Validate the recipe exists
    local validatedName = BurdJournals.validateRecipeName(recipeName)
    if not validatedName then
        print(logPrefix .. " WARNING: Recipe '" .. recipeName .. "' not found in game recipes!")
        -- Continue anyway - it might be a magazine recipe that's not in getAllRecipes()
        validatedName = recipeName
    elseif validatedName ~= recipeName then
        print(logPrefix .. " Recipe name corrected: '" .. recipeName .. "' -> '" .. validatedName .. "'")
        recipeName = validatedName
    end

    local learned = false

    -- Method 1: Try standard learnRecipe()
    local ok1, err1 = pcall(function()
        player:learnRecipe(recipeName)
    end)

    if ok1 then
        -- Verify it worked using isRecipeKnown
        if player.isRecipeKnown and player:isRecipeKnown(recipeName) then
            print(logPrefix .. " Learned recipe via learnRecipe(): " .. recipeName)
            learned = true
        else
            -- Fallback verification via getKnownRecipes
            local knownRecipes = player:getKnownRecipes()
            if knownRecipes then
                local hasIt, containsIt = pcall(function() return knownRecipes:contains(recipeName) end)
                if hasIt and containsIt then
                    print(logPrefix .. " Learned recipe via learnRecipe() (verified via getKnownRecipes): " .. recipeName)
                    learned = true
                end
            end
        end
    else
        print(logPrefix .. " learnRecipe() threw error: " .. tostring(err1))
    end

    -- Method 2: If standard method didn't work, try magazine-based approach
    if not learned then
        local magazineType = BurdJournals.getMagazineForRecipe(recipeName)
        if magazineType then
            print(logPrefix .. " Trying magazine method for: " .. recipeName .. " (magazine: " .. magazineType .. ")")

            -- Get the magazine script to find page count
            local ok2, err2 = pcall(function()
                local script = getScriptManager():getItem(magazineType)
                if script then
                    local pageCount = 1
                    if script.getPageToLearn then
                        pageCount = script:getPageToLearn() or 1
                    end
                    -- Mark all pages as read
                    player:setAlreadyReadPages(magazineType, pageCount)
                    print(logPrefix .. " Set " .. pageCount .. " pages read for magazine: " .. magazineType)
                end
            end)

            if not ok2 then
                print(logPrefix .. " setAlreadyReadPages error: " .. tostring(err2))
            end

            -- Also add to read books list
            local ok3, err3 = pcall(function()
                local readBooks = player:getAlreadyReadBook()
                if readBooks then
                    local hasContains, alreadyHas = pcall(function() return readBooks:contains(magazineType) end)
                    if not (hasContains and alreadyHas) then
                        readBooks:add(magazineType)
                        print(logPrefix .. " Added magazine to read books: " .. magazineType)
                    end
                end
            end)

            if not ok3 then
                print(logPrefix .. " getAlreadyReadBook error: " .. tostring(err3))
            end

            -- Verify magazine method worked
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

-- Debug function to diagnose recipe system issues
-- Call this to print detailed info about the player's recipe knowledge state
function BurdJournals.debugRecipeSystem(player)
    if not player then
        print("[BurdJournals DEBUG] No player provided")
        return
    end

    print("==================== RECIPE SYSTEM DEBUG ====================")

    -- Test isRecipeKnown availability
    print("\n[API Availability]")
    print("  player.isRecipeKnown: " .. tostring(player.isRecipeKnown ~= nil))
    print("  player.learnRecipe: " .. tostring(player.learnRecipe ~= nil))
    print("  player.getKnownRecipes: " .. tostring(player.getKnownRecipes ~= nil))
    print("  player.getAlreadyReadPages: " .. tostring(player.getAlreadyReadPages ~= nil))
    print("  player.setAlreadyReadPages: " .. tostring(player.setAlreadyReadPages ~= nil))
    print("  player.getAlreadyReadBook: " .. tostring(player.getAlreadyReadBook ~= nil))

    -- Test getKnownRecipes
    print("\n[getKnownRecipes Test]")
    local knownRecipes = nil
    local ok1, err1 = pcall(function()
        knownRecipes = player:getKnownRecipes()
    end)
    if ok1 and knownRecipes then
        local hasSize, recipeCount = pcall(function() return knownRecipes:size() end)
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

    -- Test getAlreadyReadBook
    print("\n[getAlreadyReadBook Test]")
    local readBooks = nil
    local ok2, err2 = pcall(function()
        readBooks = player:getAlreadyReadBook()
    end)
    if ok2 and readBooks then
        local hasSize, bookCount = pcall(function() return readBooks:size() end)
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

    -- Test magazine cache
    print("\n[Magazine Recipe Cache]")
    local magToRecipes = BurdJournals.buildMagazineToRecipesCache()
    local magCount = 0
    for _ in pairs(magToRecipes) do magCount = magCount + 1 end
    print("  Total magazine types: " .. magCount)

    -- Show a sample magazine
    local sampleCount = 0
    for magType, recipes in pairs(magToRecipes) do
        if sampleCount < 3 then
            print("  " .. magType .. ": " .. #recipes .. " recipes")
            sampleCount = sampleCount + 1
        end
    end

    -- Test specific recipe check
    print("\n[Testing Sample Recipe Check]")
    -- Pick a magazine recipe to test
    for magType, recipes in pairs(magToRecipes) do
        if #recipes > 0 then
            local testRecipe = recipes[1]
            print("  Testing: " .. testRecipe .. " (from " .. magType .. ")")

            -- Test isRecipeKnown
            if player.isRecipeKnown then
                local ok, result = pcall(function() return player:isRecipeKnown(testRecipe) end)
                print("    isRecipeKnown: " .. tostring(ok and result))
            end

            -- Test our comprehensive check
            local ourCheck = BurdJournals.playerKnowsRecipe(player, testRecipe)
            print("    playerKnowsRecipe: " .. tostring(ourCheck))

            -- Test pages read for this magazine
            local pagesRead = 0
            pcall(function() pagesRead = player:getAlreadyReadPages(magType) or 0 end)
            print("    getAlreadyReadPages(" .. magType .. "): " .. pagesRead)

            break  -- Only test one
        end
    end

    -- Summary
    print("\n[Recipe Recording Status]")
    local enableRecording = BurdJournals.getSandboxOption("EnableRecipeRecording")
    print("  EnableRecipeRecording sandbox option: " .. tostring(enableRecording))

    local collectedRecipes = BurdJournals.collectPlayerMagazineRecipes(player)
    local collectedCount = 0
    for _ in pairs(collectedRecipes) do collectedCount = collectedCount + 1 end
    print("  Total magazine recipes player knows: " .. collectedCount)

    print("==================== END DEBUG ====================")
end

-- Get display name for a recipe
-- Tries to find a readable name from the recipe script
function BurdJournals.getRecipeDisplayName(recipeName)
    if not recipeName then return "Unknown Recipe" end

    -- Try to get the recipe from RecipeManager
    local ok, result = pcall(function()
        local recipes = getAllRecipes()
        if recipes then
            for i = 0, recipes:size() - 1 do
                local recipe = recipes:get(i)
                if recipe and recipe:getName() == recipeName then
                    -- Recipe:getName() returns internal name, try getOriginalname() for display
                    if recipe.getOriginalname then
                        local origName = recipe:getOriginalname()
                        if origName and origName ~= "" and origName ~= recipeName then
                            return origName
                        end
                    end
                    -- If getOriginalname didn't work, break and use fallback
                    break
                end
            end
        end
        return nil
    end)

    if ok and result then return result end

    -- Fallback: Make the recipe name more readable
    return BurdJournals.normalizeRecipeName(recipeName)
end

-- Normalize a recipe name into a human-readable format
-- "AddMotionSensorV1ToBomb" -> "Add Motion Sensor V1 to Bomb"
-- "Forge_Tongs" -> "Forge Tongs"
-- "Make_MetalSheet" -> "Make Metal Sheet"
function BurdJournals.normalizeRecipeName(recipeName)
    if not recipeName then return "Unknown Recipe" end

    local displayName = recipeName

    -- Replace underscores with spaces
    displayName = displayName:gsub("_", " ")

    -- Insert space before capital letters (camelCase to Title Case)
    -- "AddMotion" -> "Add Motion"
    displayName = displayName:gsub("(%l)(%u)", "%1 %2")

    -- Insert space between letter and number (but not number and letter)
    -- "Sensor2" -> "Sensor 2", but keep "V1" as "V1" initially
    displayName = displayName:gsub("([%a])(%d)", "%1 %2")

    -- Now fix version patterns: "V 1" -> "V1", "V 2" -> "V2", etc.
    displayName = displayName:gsub("([Vv]) (%d+)", "%1%2")
    displayName = displayName:gsub("([Vv]ol) (%d+)", "%1%2")
    displayName = displayName:gsub("([Vv]ol)(%d+)", "Vol.%2")

    -- Clean up common prepositions to lowercase (when not at start)
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

    -- Fix start of string - capitalize first letter
    displayName = displayName:gsub("^%l", string.upper)

    -- Clean up multiple spaces
    displayName = displayName:gsub("%s+", " ")

    -- Trim leading/trailing spaces
    displayName = displayName:match("^%s*(.-)%s*$")

    return displayName
end

-- Get display name for a magazine (item) from its full type
-- Converts "Base.MagazineElectronics02" to "Electronics Magazine Vol.2" (or whatever the game calls it)
function BurdJournals.getMagazineDisplayName(magazineType)
    if not magazineType then return "Unknown Magazine" end

    local ok, result = pcall(function()
        local script = getScriptManager():getItem(magazineType)
        if script then
            return script:getDisplayName()
        end
        return nil
    end)

    if ok and result then return result end

    -- Fallback: Clean up the type string
    -- "Base.MagazineElectronics02" -> "MagazineElectronics02" -> "Magazine Electronics 02"
    local fallback = magazineType
    -- Remove module prefix (e.g., "Base.")
    if fallback:find("%.") then
        fallback = fallback:match("%.(.+)") or fallback
    end
    -- Insert spaces before capital letters and numbers
    fallback = fallback:gsub("(%l)(%u)", "%1 %2")  -- camelCase -> camel Case
    fallback = fallback:gsub("(%a)(%d)", "%1 %2")  -- letters before numbers
    return fallback
end

-- ==================== RECIPE CLAIM TRACKING ====================

function BurdJournals.getClaimedRecipes(item)
    if not item then return {} end
    local modData = item:getModData()
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

function BurdJournals.getUnclaimedRecipes(item)
    if not item then return {} end
    local data = BurdJournals.getJournalData(item)
    if not data or not data.recipes then return {} end

    local claimed = BurdJournals.getClaimedRecipes(item)
    local unclaimed = {}

    for recipeName, recipeData in pairs(data.recipes) do
        if not claimed[recipeName] then
            unclaimed[recipeName] = recipeData
        end
    end

    return unclaimed
end

function BurdJournals.getUnclaimedRecipeCount(item)
    local unclaimed = BurdJournals.getUnclaimedRecipes(item)
    return BurdJournals.countTable(unclaimed)
end

function BurdJournals.getTotalRecipeCount(item)
    if not item then return 0 end
    local data = BurdJournals.getJournalData(item)
    if not data or not data.recipes then return 0 end
    return BurdJournals.countTable(data.recipes)
end

-- ==================== MAGAZINE RECIPE GENERATION ====================

-- Get all available magazine recipes from the game's dynamic cache
-- Returns a list of recipe names (internal PZ names)
function BurdJournals.getAllMagazineRecipes()
    local cache = BurdJournals.buildMagazineRecipeCache()
    local recipes = {}
    for recipeName, _ in pairs(cache) do
        table.insert(recipes, recipeName)
    end
    return recipes
end

-- Generate random recipes for a journal
-- count: number of recipes to generate
-- Returns: table of {recipeName = {name = ..., source = ...}}
-- Uses DYNAMICALLY DISCOVERED recipes from the game's magazine system
function BurdJournals.generateRandomRecipes(count)
    if not count or count <= 0 then return {} end

    local recipes = {}

    -- Get all available magazine recipes from the game cache
    local available = BurdJournals.getAllMagazineRecipes()

    if #available == 0 then
        print("[BurdJournals] WARNING: No magazine recipes found in cache!")
        return {}
    end

    -- Shuffle and pick
    for i = #available, 2, -1 do
        local j = ZombRand(i) + 1
        available[i], available[j] = available[j], available[i]
    end

    for i = 1, math.min(count, #available) do
        local recipeName = available[i]
        recipes[recipeName] = true  -- Simplified: just mark recipe as known
    end

    return recipes
end

-- Generate random recipes using a seed (for OnZombieDead where ZombRand doesn't work)
-- count: number of recipes to generate
-- seed: number to use for pseudo-random generation
-- Returns: table of {recipeName = {name = ..., source = ...}}
-- Uses DYNAMICALLY DISCOVERED recipes from the game's magazine system
function BurdJournals.generateRandomRecipesSeeded(count, seed)
    if not count or count <= 0 then return {} end

    local recipes = {}

    -- Get all available magazine recipes from the game cache
    local available = BurdJournals.getAllMagazineRecipes()

    if #available == 0 then
        print("[BurdJournals] WARNING: No magazine recipes found in cache for seeded generation!")
        return {}
    end

    -- Use seed-based selection (deterministic but varied)
    local seedVal = math.floor(seed * 31) % 1000
    for i = 1, math.min(count, #available) do
        -- Pick based on seed, varying by iteration
        local idx = ((seedVal * (i + 7)) % #available) + 1
        local recipeName = available[idx]
        if recipeName and not recipes[recipeName] then
            recipes[recipeName] = true  -- Simplified: just mark recipe as known
            -- Remove to avoid duplicates
            table.remove(available, idx)
        end
    end

    return recipes
end


