
require "BurdJournals_Shared"

BurdJournals = BurdJournals or {}
BurdJournals.ZombieLoot = BurdJournals.ZombieLoot or {}

BurdJournals.ZombieLoot.Professions = {
    {
        id = "formerfarmer",
        name = "Former Farmer",
        nameKey = "UI_BurdJournals_ProfFormerFarmer",
        skills = {"Farming", "Cooking", "Foraging", "Trapping"},
        flavorKey = "UI_BurdJournals_FlavorFarmer"
    },
    {
        id = "formermechanic",
        name = "Former Mechanic",
        nameKey = "UI_BurdJournals_ProfFormerMechanic",
        skills = {"Mechanics", "Electricity", "MetalWelding"},
        flavorKey = "UI_BurdJournals_FlavorMechanic"
    },
    {
        id = "formerdoctor",
        name = "Former Doctor",
        nameKey = "UI_BurdJournals_ProfFormerDoctor",
        skills = {"Doctor", "Cooking"},
        flavorKey = "UI_BurdJournals_FlavorDoctor"
    },
    {
        id = "formercarpenter",
        name = "Former Carpenter",
        nameKey = "UI_BurdJournals_ProfFormerCarpenter",
        skills = {"Carpentry", "Maintenance"},
        flavorKey = "UI_BurdJournals_FlavorCarpenter"
    },
    {
        id = "formerhunter",
        name = "Former Hunter",
        nameKey = "UI_BurdJournals_ProfFormerHunter",
        skills = {"Aiming", "Reloading", "Sneak", "Trapping", "Foraging"},
        flavorKey = "UI_BurdJournals_FlavorHunter"
    },
    {
        id = "formersoldier",
        name = "Former Soldier",
        nameKey = "UI_BurdJournals_ProfFormerSoldier",
        skills = {"Aiming", "Reloading", "Fitness", "Strength", "Sneak"},
        flavorKey = "UI_BurdJournals_FlavorSoldier"
    },
    {
        id = "formerchef",
        name = "Former Chef",
        nameKey = "UI_BurdJournals_ProfFormerChef",
        skills = {"Cooking", "Farming", "Foraging"},
        flavorKey = "UI_BurdJournals_FlavorChef"
    },
    {
        id = "formerathlete",
        name = "Former Athlete",
        nameKey = "UI_BurdJournals_ProfFormerAthlete",
        skills = {"Fitness", "Strength", "Sprinting", "Nimble"},
        flavorKey = "UI_BurdJournals_FlavorAthlete"
    },
    {
        id = "formerburglar",
        name = "Former Burglar",
        nameKey = "UI_BurdJournals_ProfFormerBurglar",
        skills = {"Lightfoot", "Sneak", "Nimble", "SmallBlade"},
        flavorKey = "UI_BurdJournals_FlavorBurglar"
    },
    {
        id = "formerlumberjack",
        name = "Former Lumberjack",
        nameKey = "UI_BurdJournals_ProfFormerLumberjack",
        skills = {"Axe", "Strength", "Fitness", "Carpentry"},
        flavorKey = "UI_BurdJournals_FlavorLumberjack"
    },
    {
        id = "formerfisherman",
        name = "Former Fisherman",
        nameKey = "UI_BurdJournals_ProfFormerFisherman",
        skills = {"Fishing", "Cooking", "Trapping"},
        flavorKey = "UI_BurdJournals_FlavorFisherman"
    },
    {
        id = "formertailor",
        name = "Former Tailor",
        nameKey = "UI_BurdJournals_ProfFormerTailor",
        skills = {"Tailoring"},
        flavorKey = "UI_BurdJournals_FlavorTailor"
    },
    {
        id = "formerelectrician",
        name = "Former Electrician",
        nameKey = "UI_BurdJournals_ProfFormerElectrician",
        skills = {"Electricity", "Mechanics"},
        flavorKey = "UI_BurdJournals_FlavorElectrician"
    },
    {
        id = "formermetalworker",
        name = "Former Metalworker",
        nameKey = "UI_BurdJournals_ProfFormerMetalworker",
        skills = {"MetalWelding", "Mechanics", "Strength"},
        flavorKey = "UI_BurdJournals_FlavorMetalworker"
    },
    {
        id = "formersurvivalist",
        name = "Former Survivalist",
        nameKey = "UI_BurdJournals_ProfFormerSurvivalist",
        skills = {"Foraging", "Trapping", "Fishing", "Carpentry", "Farming"},
        flavorKey = "UI_BurdJournals_FlavorSurvivalist"
    },
    {
        id = "formerfighter",
        name = "Former Fighter",
        nameKey = "UI_BurdJournals_ProfFormerFighter",
        skills = {"Axe", "Blunt", "SmallBlunt", "LongBlade", "SmallBlade", "Spear", "Maintenance"},
        flavorKey = "UI_BurdJournals_FlavorFighter"
    },
}

local function addGeneratedJournalItemToContainer(container, itemType)
    if not container or type(itemType) ~= "string" or itemType == "" then
        return nil
    end

    if InventoryItemFactory and InventoryItemFactory.CreateItem and container.AddItem then
        local item = InventoryItemFactory.CreateItem(itemType)
        if item then
            return container:AddItem(item) or item
        end
    end


    if container.AddItem then
        return container:AddItem(itemType)
    end

    return nil
end

function BurdJournals.ZombieLoot.generateBloodyJournalData()

    local profession = BurdJournals.ZombieLoot.Professions[ZombRand(#BurdJournals.ZombieLoot.Professions) + 1]

    local survivorName = BurdJournals.generateRandomSurvivorName()

    local minXP = BurdJournals.getSandboxOption("BloodyJournalMinXP") or 50
    local maxXP = BurdJournals.getSandboxOption("BloodyJournalMaxXP") or 150
    local minSkills = BurdJournals.getSandboxOption("BloodyJournalMinSkills") or 2
    local maxSkills = BurdJournals.getSandboxOption("BloodyJournalMaxSkills") or 4
    local traitChance = BurdJournals.getSandboxOption("BloodyJournalTraitChance") or 15

    local skills, coreCount, fallbackCount = nil, 0, 0
    if BurdJournals.rollCoherentSkillsFromCoreSkills then
        skills, coreCount, fallbackCount = BurdJournals.rollCoherentSkillsFromCoreSkills(profession.skills or {}, minSkills, maxSkills, minXP, maxXP)
    else
        skills = BurdJournals.generateRandomSkills(minSkills, maxSkills, minXP, maxXP)
    end
    -- The coherent roll returns an empty set when the allowed-skills pool is empty
    -- (e.g. a heavily skill-restricted sandbox). Fall back to the simple generator
    -- before giving up, so bloody journals still spawn instead of silently never.
    if (not skills or not BurdJournals.hasAnyEntries(skills)) and BurdJournals.generateRandomSkills then
        skills = BurdJournals.generateRandomSkills(minSkills, maxSkills, minXP, maxXP)
    end
    if not skills or not BurdJournals.hasAnyEntries(skills) then
        if BurdJournals.debugPrint then
            BurdJournals.debugPrint("[BurdJournals] WARNING: bloody journal generation produced no skills (allowed-skills pool may be empty); no journal spawned.")
        end
        return nil
    end

    local traits = nil
    if ZombRand(100) < traitChance then
        -- Use getGrantableTraits() for proper trait discovery, with fallback
        local traitList = (BurdJournals.getGrantableTraitsForJournal
            and BurdJournals.getGrantableTraitsForJournal({ isBloody = true, wasFromBloody = true, isPlayerCreated = false }))
            or (BurdJournals.getGrantableTraits and BurdJournals.getGrantableTraits())
            or BurdJournals.GRANTABLE_TRAITS or {}
        local listSize = #traitList
        
        if listSize > 0 then
            local maxTraits = BurdJournals.getSandboxOption("BloodyJournalMaxTraits") or 2
            if maxTraits < 1 then maxTraits = 1 end
            if maxTraits > listSize then maxTraits = listSize end

            local numTraits = ZombRand(1, maxTraits + 1)
            
            traits = {}
            local availableTraits = {}
            for _, t in ipairs(traitList) do
                table.insert(availableTraits, t)
            end
            
            for i = #availableTraits, 2, -1 do
                local j = ZombRand(i) + 1
                availableTraits[i], availableTraits[j] = availableTraits[j], availableTraits[i]
            end
            
            for i = 1, numTraits do
                if #availableTraits == 0 then break end
                local idx = ZombRand(#availableTraits) + 1
                local traitId = availableTraits[idx]
                if traitId and type(traitId) == "string" then
                    traits[traitId] = true
                    table.remove(availableTraits, idx)
                end
            end
            
            local traitCount = 0
            for _ in pairs(traits) do
                traitCount = traitCount + 1
                break
            end
            if traitCount == 0 then
                traits = nil
            end
        end
    end

    local recipes = nil
    local recipeChance = BurdJournals.getSandboxOption("BloodyJournalRecipeChance") or 35
    if ZombRand(100) < recipeChance then
        local maxRecipes = BurdJournals.getSandboxOption("BloodyJournalMaxRecipes") or 2
        local numRecipes = ZombRand(1, maxRecipes + 1)
        local worldAge = getGameTime():getWorldAgeHours()
        recipes = BurdJournals.generateRandomRecipesSeeded(numRecipes, worldAge)
    end

    local professionId = profession.id
    local flavorKey = profession.flavorKey
    local forgetSlot = BurdJournals.rollForgetSlotForType and BurdJournals.rollForgetSlotForType("bloody")

    -- Get translated name, with robust fallback for server-side getText() issues
    local professionName = nil
    if profession.nameKey then
        local translated = getText(profession.nameKey)
        if translated and translated ~= "" and translated ~= profession.nameKey then
            professionName = translated
        end
    end
    if not professionName or professionName == "" then
        professionName = profession.name
    end
    
    if BurdJournals.resolveProfessionForGeneratedEntries then
        professionId, professionName, flavorKey = BurdJournals.resolveProfessionForGeneratedEntries(
            professionId,
            professionName,
            flavorKey,
            skills,
            traits,
            recipes,
            coreCount,
            fallbackCount
        )
    end

    local journalData = {
        uuid = BurdJournals.generateUUID and BurdJournals.generateUUID() or tostring(ZombRand(999999999)),
        author = survivorName,
        profession = professionId,  -- Also store the profession ID for lookup
        professionName = professionName,
        flavorKey = flavorKey,
        loreNoteTemplateVersion = 1,
        loreNoteTemplateFamily = "bloody",
        timestamp = getGameTime():getWorldAgeHours() - ZombRand(24, 720),
        skills = skills,
        traits = traits,
        recipes = recipes,
        forgetSlot = forgetSlot,

        isBloody = true,
        isWorn = false,
        wasFromBloody = true,
        isPlayerCreated = false,
        isZombieJournal = true,
        condition = ZombRand(1, 4),

        claimedSkills = {},
        claimedTraits = {},
        claimedRecipes = {},
        claimedForgetSlot = {},
    }

    if BurdJournals.Server and BurdJournals.Server.tryAttachGeneratedLootNotes then
        BurdJournals.Server.tryAttachGeneratedLootNotes(nil, nil, journalData, "bloody")
    end

    return journalData
end

function BurdJournals.ZombieLoot.onZombieDead(zombie)

    if isClient() and not isServer() then return end
    if not zombie then return end
    if not BurdJournals.isEnabled() then return end

    local funLootEnabled = not BurdJournals.getSandboxOption
        or BurdJournals.getSandboxOption("EnableLootJournalsFun") ~= false
    local yuletideSpawnsEnabled = BurdJournals.getSandboxOption
        and BurdJournals.getSandboxOption("EnableYuletideJournalSpawns") ~= false
    local yuletideSeason = (funLootEnabled and yuletideSpawnsEnabled and BurdJournals.getYuletideSeasonContext)
        and BurdJournals.getYuletideSeasonContext()
        or nil
    local useKrampusIdentity = funLootEnabled
        and yuletideSpawnsEnabled
        and (not BurdJournals.getSandboxOption
            or BurdJournals.getSandboxOption("EnableYuletideKrampusCursedAuthors") ~= false)
        and type(yuletideSeason) == "table"
        and yuletideSeason.active == true

    local cursedSpawnsEnabled = funLootEnabled and BurdJournals.getSandboxOption("EnableCursedJournalSpawns")
    if cursedSpawnsEnabled ~= false then
        local cursedDropChance = tonumber(BurdJournals.getSandboxOption("CursedJournalSpawnChance")) or 0.08
        local cursedRoll = ZombRandFloat(0, 100)
        if cursedRoll <= cursedDropChance then
            local square = zombie:getSquare()
            if square then
                local container = zombie:getInventory()
                local cursedJournal = nil
                local disguiseAsBloody = BurdJournals.isDisguiseCursedJournalsAsBloodyEnabled
                    and BurdJournals.isDisguiseCursedJournalsAsBloodyEnabled()
                local cursedItemType = disguiseAsBloody
                    and "BurdJournals.FilledSurvivalJournal_Bloody"
                    or (BurdJournals.CURSED_ITEM_TYPE or "BurdJournals.CursedJournal")
                if container then
                    cursedJournal = addGeneratedJournalItemToContainer(container, cursedItemType)
                end
                if not cursedJournal and InventoryItemFactory then
                    cursedJournal = InventoryItemFactory.CreateItem(cursedItemType)
                    if cursedJournal then
                        square:AddWorldInventoryItem(cursedJournal, ZombRandFloat(0, 0.8), ZombRandFloat(0, 0.8), 0)
                    end
                end

                if cursedJournal then
                    local modData = cursedJournal:getModData()
                    modData.BurdJournals = modData.BurdJournals or {}
                    local data = modData.BurdJournals
                    data.uuid = data.uuid or (BurdJournals.generateUUID and BurdJournals.generateUUID()) or ("cursed-" .. tostring(ZombRand(999999999)))
                    data.timestamp = getGameTime():getWorldAgeHours() - ZombRand(24, 720)
                    if disguiseAsBloody then
                        -- NB: "X and X() or default" truncates X()'s multiple return
                        -- values to one; assign with an explicit branch instead.
                        local professionId, professionName, flavorKey
                        if BurdJournals.getRandomProfession then
                            professionId, professionName, flavorKey = BurdJournals.getRandomProfession()
                        else
                            professionId, professionName, flavorKey = "survivor", "Survivor", "UI_BurdJournals_BloodyFlavor"
                        end
                        local disguisedSeed = {
                            uuid = data.uuid,
                            timestamp = data.timestamp,
                            author = data.author
                                or ((BurdJournals.generateRandomSurvivorName and BurdJournals.generateRandomSurvivorName()) or "Unknown Survivor"),
                            profession = data.profession or professionId,
                            professionName = data.professionName or professionName,
                            flavorKey = data.flavorKey or flavorKey or "UI_BurdJournals_BloodyFlavor",
                            lootNotesEligible = true,
                        }
                        data.cursedPendingRewards = {
                            uuid = disguisedSeed.uuid,
                            timestamp = disguisedSeed.timestamp,
                            author = disguisedSeed.author,
                            profession = disguisedSeed.profession,
                            professionName = disguisedSeed.professionName,
                            flavorKey = disguisedSeed.flavorKey,
                            lootNotesEligible = true,
                            cursedDeferredRewards = true,
                        }
                        data.author = data.author or disguisedSeed.author
                        data.profession = data.profession or disguisedSeed.profession
                        data.professionName = data.professionName or disguisedSeed.professionName
                        data.flavorKey = data.flavorKey or disguisedSeed.flavorKey
                        local insightEffectType = BurdJournals.Server.rollCursedInsightEffectType
                            and BurdJournals.Server.rollCursedInsightEffectType(nil, nil)
                            or nil
                        if insightEffectType then
                            data.cursedInsightEffectType = insightEffectType
                            if BurdJournals.Server.getCurseEffectOmenCategory then
                                data.cursedOmenCategory = BurdJournals.Server.getCurseEffectOmenCategory(insightEffectType)
                            end
                        end
                        data.isHiddenCursedJournal = true
                        data.isCursedJournal = false
                        data.cursedState = "hidden"
                        -- Expired curses: record spawn time so old curses can go dormant.
                        data.cursedSpawnedAtHours = data.cursedSpawnedAtHours
                            or (BurdJournals.Server.getWorldAgeHoursSafe and BurdJournals.Server.getWorldAgeHoursSafe())
                            or (getGameTime() and getGameTime():getWorldAgeHours())
                            or nil
                        data.isCursedReward = false
                        data.cursedEffectType = nil
                        data.cursedUnleashedByCharacterId = nil
                        data.cursedUnleashedByUsername = nil
                        data.cursedUnleashedAtHours = nil
                        data.cursedSealSoundEvent = nil
                        data.cursedForcedEffectType = nil
                        data.cursedForcedTraitId = nil
                        data.cursedForcedSkillName = nil
                        data.isBloody = true
                        data.isWorn = false
                        data.wasFromBloody = true
                        data.hasBloodyOrigin = true
                        data.isPlayerCreated = false
                        data.isZombieJournal = true
                        data.loreNoteTemplateVersion = tonumber(BurdJournals.Server and BurdJournals.Server.LORE_NOTE_TEMPLATE_VERSION) or 1
                        data.loreNoteTemplateFamily = "bloody"
                        data.loreNoteText = nil
                        data.claims = data.claims or {}
                        data.claimedSkills = data.claimedSkills or {}
                        data.claimedTraits = data.claimedTraits or {}
                        data.claimedRecipes = data.claimedRecipes or {}
                        data.claimedForgetSlot = data.claimedForgetSlot or {}
                    else
                        local cursedAuthor = useKrampusIdentity
                            and ((getText("UI_BurdJournals_KrampusAuthor") ~= "UI_BurdJournals_KrampusAuthor"
                                and getText("UI_BurdJournals_KrampusAuthor"))
                                or "Krampus")
                            or ((BurdJournals.generateRandomSurvivorName and BurdJournals.generateRandomSurvivorName()) or "Unknown Survivor")
                        data.author = data.author or cursedAuthor
                        data.profession = data.profession or (useKrampusIdentity and "yuletide_krampus" or data.profession)
                        data.professionName = data.professionName or (useKrampusIdentity
                            and (((getText("UI_BurdJournals_KrampusProfession") ~= "UI_BurdJournals_KrampusProfession"
                                and getText("UI_BurdJournals_KrampusProfession"))
                                or "Yule Punisher"))
                            or data.professionName)
                        data.loreNoteTemplateVersion = 1
                        data.loreNoteTemplateFamily = "cursed"
                        data.lootNotesEligible = true
                        data.isHiddenCursedJournal = false
                        data.isCursedJournal = true
                        data.cursedState = "dormant"
                        -- Expired curses: record spawn time so old curses can go dormant.
                        data.cursedSpawnedAtHours = data.cursedSpawnedAtHours
                            or (BurdJournals.Server.getWorldAgeHoursSafe and BurdJournals.Server.getWorldAgeHoursSafe())
                            or (getGameTime() and getGameTime():getWorldAgeHours())
                            or nil
                        data.isCursedReward = false
                        data.cursedEffectType = nil
                        data.cursedUnleashedByCharacterId = nil
                        data.cursedUnleashedByUsername = nil
                        data.cursedUnleashedAtHours = nil
                        data.cursedSealSoundEvent = nil
                        data.cursedForcedEffectType = nil
                        data.cursedForcedTraitId = nil
                        data.cursedForcedSkillName = nil
                        data.cursedPendingRewards = nil
                        data.isBloody = false
                        data.isWorn = false
                        data.wasFromBloody = false
                        data.hasBloodyOrigin = false
                        data.isPlayerCreated = false
                        data.isZombieJournal = true
                        data.claims = data.claims or {}
                        data.claimedSkills = data.claimedSkills or {}
                        data.claimedTraits = data.claimedTraits or {}
                        data.claimedRecipes = data.claimedRecipes or {}
                        data.claimedForgetSlot = data.claimedForgetSlot or {}
                    end

                    BurdJournals.updateJournalName(cursedJournal)
                    BurdJournals.updateJournalIcon(cursedJournal)
                    if isServer() and cursedJournal.transmitModData then
                        cursedJournal:transmitModData()
                    end
                    return
                end
            end
        end
    end

    local spawnsEnabled = BurdJournals.getSandboxOption("EnableBloodyJournalSpawns")
    if spawnsEnabled == false then return end

    local dropChance = BurdJournals.getSandboxOption("BloodyJournalSpawnChance") or 0.3
    local roll = ZombRandFloat(0, 100)
    if roll > dropChance then return end

    local useYuletide = false
    if funLootEnabled and yuletideSpawnsEnabled and type(yuletideSeason) == "table" and yuletideSeason.active == true then
        local yuletideChance = tonumber(BurdJournals.getSandboxOption("YuletideBloodyReplacementChance")) or 8
        if ZombRandFloat(0, 100) <= yuletideChance then
            useYuletide = true
        end
    end

    local journalData = useYuletide
        and BurdJournals.Server.generateYuletideJournalProfile({ isZombieJournal = true, lootNotesEligible = true })
        or BurdJournals.ZombieLoot.generateBloodyJournalData()
    if not journalData then return end

    local square = zombie:getSquare()
    if not square then return end

    local container = zombie:getInventory()
    local journal = nil

    local journalItemType = useYuletide and (BurdJournals.YULETIDE_ITEM_TYPE or "BurdJournals.YuletideJournal")
        or "BurdJournals.FilledSurvivalJournal_Bloody"
    if container then
        journal = addGeneratedJournalItemToContainer(container, journalItemType)
    end

    if not journal then
        journal = InventoryItemFactory.CreateItem(journalItemType)
        if journal then
            square:AddWorldInventoryItem(journal, ZombRandFloat(0, 0.8), ZombRandFloat(0, 0.8), 0)
        end
    end

    if journal then

        local modData = journal:getModData()
        modData.BurdJournals = {}
        for key, value in pairs(journalData) do
            modData.BurdJournals[key] = value
        end

        if useYuletide then
            modData.BurdJournals.isYuletideJournal = true
            modData.BurdJournals.yuletideState = BurdJournals.YULETIDE_STATE_WRAPPED
            modData.BurdJournals.isBloody = false
            modData.BurdJournals.isWorn = false
            modData.BurdJournals.wasFromBloody = false
            modData.BurdJournals.isZombieJournal = true
        else
            modData.BurdJournals.isBloody = true
            modData.BurdJournals.isWorn = false
            modData.BurdJournals.wasFromBloody = true
            modData.BurdJournals.isZombieJournal = true
        end

        BurdJournals.updateJournalName(journal)
        BurdJournals.updateJournalIcon(journal)

        if isServer() and journal.transmitModData then
            journal:transmitModData()
        end
    end
end

Events.OnZombieDead.Add(BurdJournals.ZombieLoot.onZombieDead)

local WORN_JOURNAL_CONTAINERS = {

    ["shelves"] = 2.0,
    ["metal_shelves"] = 1.5,

    ["desk"] = 1.5,
    ["sidetable"] = 0.8,
    ["endtable"] = 0.6,
    ["nightstand"] = 0.6,

    ["dresser"] = 0.5,

    ["wardrobe"] = 0.3,
    ["locker"] = 0.5,
    ["filingcabinet"] = 1.0,

    ["smallbox"] = 0.4,
    ["cardboardbox"] = 0.4,
    ["crate"] = 0.5,

    ["counter"] = 0.2,

    ["postbox"] = 0.3,
}

local processedContainers = {}
local processedContainersLastCleanup = 0
local PROCESSED_CONTAINERS_CLEANUP_MS = 300000

local function cleanupProcessedContainers()
    local nowMs = getTimestampMs and getTimestampMs() or 0
    if nowMs > 0 and (nowMs - processedContainersLastCleanup) >= PROCESSED_CONTAINERS_CLEANUP_MS then
        processedContainers = {}
        processedContainersLastCleanup = nowMs
    end
end

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

    if isClient() and not isServer() then return end

    if not BurdJournals or not BurdJournals.isEnabled or not BurdJournals.isEnabled() then return end
    if BurdJournals.WorldSpawn and BurdJournals.WorldSpawn.handlesWornJournalContainerSpawns == true then
        return
    end

    local spawnsEnabled = BurdJournals.getSandboxOption("EnableWornJournalSpawns")
    if spawnsEnabled == false then return end

    local baseWeight = WORN_JOURNAL_CONTAINERS[containerType]
    if not baseWeight then return end

    local containerKey = getContainerKey(itemContainer)
    if containerKey then
        cleanupProcessedContainers()
        if processedContainers[containerKey] then
            return
        end
        processedContainers[containerKey] = true
    end

    local spawnChance = BurdJournals.getSandboxOption("WornJournalSpawnChance") or 1.0

    local finalChance = (spawnChance * baseWeight) / 100.0

    local roll = ZombRandFloat(0, 1)
    if roll > finalChance then
        return
    end

    local funLootEnabled = not BurdJournals.getSandboxOption
        or BurdJournals.getSandboxOption("EnableLootJournalsFun") ~= false
    local yuletideSpawnsEnabled = BurdJournals.getSandboxOption
        and BurdJournals.getSandboxOption("EnableYuletideJournalSpawns") ~= false
    local yuletideSeason = (funLootEnabled and yuletideSpawnsEnabled and BurdJournals.getYuletideSeasonContext)
        and BurdJournals.getYuletideSeasonContext()
        or nil
    local useYuletide = false
    if funLootEnabled and yuletideSpawnsEnabled and type(yuletideSeason) == "table" and yuletideSeason.active == true then
        local yuletideChance = tonumber(BurdJournals.getSandboxOption("YuletideWornReplacementChance")) or 4
        if ZombRandFloat(0, 100) <= yuletideChance then
            useYuletide = true
        end
    end

    local journalItemType = useYuletide and (BurdJournals.YULETIDE_ITEM_TYPE or "BurdJournals.YuletideJournal")
        or "BurdJournals.FilledSurvivalJournal_Worn"
    local journal = addGeneratedJournalItemToContainer(itemContainer, journalItemType)
    if journal then

        local modData = journal:getModData()
        if not modData.BurdJournals or not modData.BurdJournals.skills then
            if BurdJournals.WorldSpawn and BurdJournals.WorldSpawn.initializeJournalIfNeeded then
                BurdJournals.WorldSpawn.initializeJournalIfNeeded(journal)
            else

                if useYuletide then
                    modData.BurdJournals = BurdJournals.Server.generateYuletideJournalProfile({
                        timestamp = getGameTime():getWorldAgeHours(),
                        yuletideState = BurdJournals.YULETIDE_STATE_WRAPPED,
                        lootNotesEligible = true,
                    })
                else
                    modData.BurdJournals = {
                        uuid = BurdJournals.generateUUID and BurdJournals.generateUUID() or tostring(ZombRand(999999)),
                        author = getText("UI_BurdJournals_UnknownSurvivor") or "Unknown Survivor",
                        profession = "unemployed",
                        professionName = getText("UI_BurdJournals_ProfSurvivor") or "Survivor",
                        timestamp = getGameTime():getWorldAgeHours() - ZombRand(24, 720),
                        skills = BurdJournals.generateRandomSkills and BurdJournals.generateRandomSkills(1, 2, 25, 75) or {},
                        loreNoteTemplateVersion = tonumber(BurdJournals.Server and BurdJournals.Server.LORE_NOTE_TEMPLATE_VERSION) or 1,
                        loreNoteTemplateFamily = "worn",
                        isWorn = true,
                        isBloody = false,
                        wasFromBloody = false,
                        isPlayerCreated = false,
                        lootNotesEligible = true,
                        traits = nil,
                        forgetSlot = BurdJournals.rollForgetSlotForType and BurdJournals.rollForgetSlotForType("worn") or nil,
                        claimedSkills = {},
                        claimedTraits = {},
                        claimedForgetSlot = {},
                    }
                    if BurdJournals.Server and BurdJournals.Server.tryAttachGeneratedLootNotes then
                        BurdJournals.Server.tryAttachGeneratedLootNotes(nil, nil, modData.BurdJournals, "worn")
                    end
                end
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

if Events.OnFillContainer then
    if not (BurdJournals.WorldSpawn and BurdJournals.WorldSpawn.handlesWornJournalContainerSpawns == true) then
        Events.OnFillContainer.Add(onFillContainerWornJournals)
    end
end
