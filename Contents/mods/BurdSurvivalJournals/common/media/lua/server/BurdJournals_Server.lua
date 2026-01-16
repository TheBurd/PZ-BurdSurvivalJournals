--[[
    Burd's Survival Journals - Server Module
    Build 42 - Version 2.0
    
    Server-side validation and command processing
    
    Commands:
    - logSkills: Record player skills to clean journal
    - learnSkills: Apply XP from clean journal (SET mode)
    - absorbSkill: Absorb XP from worn journal (ADD mode)
    - absorbTrait: Absorb trait from worn journal (bloody origin)
    - eraseJournal: Clear clean journal to blank
    - cleanBloody: Clean bloody journal to worn state
    - convertToClean: Convert worn journal to clean blank
]]

require "BurdJournals_Shared"

print("[BurdJournals] SERVER MODULE LOADING...")

BurdJournals = BurdJournals or {}
BurdJournals.Server = BurdJournals.Server or {}

-- Helper function to deep-copy journal data for sending to client
-- This ensures the client gets the latest data after server-side changes
-- NOTE: Only handles up to 3 levels of nesting (sufficient for journal data structure)
function BurdJournals.Server.copyJournalData(journal)
    if not journal then return nil end
    local modData = journal:getModData()
    if not modData or not modData.BurdJournals then return nil end

    local journalData = {}
    for k, v in pairs(modData.BurdJournals) do
        if type(v) == "table" then
            journalData[k] = {}
            for k2, v2 in pairs(v) do
                if type(v2) == "table" then
                    journalData[k][k2] = {}
                    for k3, v3 in pairs(v2) do
                        journalData[k][k2][k3] = v3
                    end
                else
                    journalData[k][k2] = v2
                end
            end
        else
            journalData[k] = v
        end
    end
    return journalData
end

-- ==================== SERVER TO CLIENT COMMUNICATION ====================
-- In multiplayer, sendServerCommand triggers OnServerCommand on the client.
-- In single-player, we need to directly invoke the client handler since
-- OnServerCommand events don't fire in pure SP mode.

function BurdJournals.Server.sendToClient(player, command, args)
    -- Always send via sendServerCommand (works in MP, does nothing harmful in SP)
    sendServerCommand(player, "BurdJournals", command, args)

    -- In single-player (NOT hosting MP), sendServerCommand doesn't trigger OnServerCommand.
    -- We detect true SP by checking: getPlayer() exists AND NOT isClient().
    -- isClient() returns true when connected to a server (including being host).
    -- In pure SP, isClient() returns false but getPlayer() returns the local player.
    local localPlayer = getPlayer and getPlayer()
    local isTrueSinglePlayer = localPlayer ~= nil and not isClient()

    if isTrueSinglePlayer then
        -- Directly invoke client handler in SP mode
        -- Use a slight delay to ensure server-side changes are complete
        local ticksToWait = 1
        local ticksWaited = 0
        local invokeClient
        invokeClient = function()
            ticksWaited = ticksWaited + 1
            if ticksWaited >= ticksToWait then
                Events.OnTick.Remove(invokeClient)
                if BurdJournals.Client and BurdJournals.Client.onServerCommand then
                    BurdJournals.Client.onServerCommand("BurdJournals", command, args)
                end
            end
        end
        Events.OnTick.Add(invokeClient)
    end
end

-- ==================== SERVER INITIALIZATION ====================

function BurdJournals.Server.init()
end

-- ==================== COMMAND ROUTER ====================

function BurdJournals.Server.onClientCommand(module, command, player, args)
    if module ~= "BurdJournals" then return end

    print("[BurdJournals] Server received command: " .. tostring(command) .. " from player: " .. tostring(player and player:getUsername() or "nil"))

    if not player then
        print("[BurdJournals] ERROR: No player in command")
        return
    end

    -- Rate limiting: 100ms cooldown between commands per player to prevent spam
    local playerModData = player:getModData()
    local now = getTimestampMs()
    local lastCmd = playerModData.BurdJournals_LastCommand or 0
    if now - lastCmd < 100 then
        return -- Too fast, ignore command
    end
    playerModData.BurdJournals_LastCommand = now

    if not BurdJournals.isEnabled() then
        -- Debug removed
        BurdJournals.Server.sendToClient(player, "error", {message = "Journals are disabled on this server."})
        return
    end

    if command == "logSkills" then
        BurdJournals.Server.handleLogSkills(player, args)
    elseif command == "learnSkills" then
        BurdJournals.Server.handleLearnSkills(player, args)
    elseif command == "absorbSkill" then
        BurdJournals.Server.handleAbsorbSkill(player, args)
    elseif command == "absorbTrait" then
        BurdJournals.Server.handleAbsorbTrait(player, args)
    elseif command == "claimSkill" then
        BurdJournals.Server.handleClaimSkill(player, args)
    elseif command == "claimTrait" then
        BurdJournals.Server.handleClaimTrait(player, args)
    elseif command == "eraseJournal" then
        BurdJournals.Server.handleEraseJournal(player, args)
    elseif command == "cleanBloody" then
        BurdJournals.Server.handleCleanBloody(player, args)
    elseif command == "convertToClean" then
        BurdJournals.Server.handleConvertToClean(player, args)
    elseif command == "initializeJournal" then
        BurdJournals.Server.handleInitializeJournal(player, args)
    elseif command == "recordProgress" then
        BurdJournals.Server.handleRecordProgress(player, args)
    elseif command == "syncJournalData" then
        BurdJournals.Server.handleSyncJournalData(player, args)
    elseif command == "claimRecipe" then
        BurdJournals.Server.handleClaimRecipe(player, args)
    elseif command == "absorbRecipe" then
        BurdJournals.Server.handleAbsorbRecipe(player, args)
    elseif command == "eraseEntry" then
        BurdJournals.Server.handleEraseEntry(player, args)
    end
end

-- ==================== HELPER: REMOVE JOURNAL COMPLETELY ====================
-- Robust removal function that ensures journal is removed from all possible locations

local function removeJournalCompletely(player, journal)
    -- Debug removed

    if not journal then
        return false
    end

    -- Get journal info for logging
    local journalType = journal:getFullType()
    local journalID = journal:getID()

    -- Method 1: Remove from hands first (important!)
    pcall(function()
        if player:getPrimaryHandItem() == journal then
            player:setPrimaryHandItem(nil)
            -- Debug removed
        end
        if player:getSecondaryHandItem() == journal then
            player:setSecondaryHandItem(nil)
            -- Debug removed
        end
    end)

    -- Method 2: Remove from the journal's actual container
    local container = journal:getContainer()
    if container then
        container:Remove(journal)
        container:setDrawDirty(true)
        -- Debug removed
    end

    -- Method 3: Also try removing from player's main inventory directly
    local mainInv = player:getInventory()
    if mainInv then
        if mainInv:contains(journal) then
            mainInv:Remove(journal)
            mainInv:setDrawDirty(true)
            -- Debug removed
        end

        -- Method 4: Check all bags/containers in inventory
        local items = mainInv:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item then
                pcall(function()
                    local subInv = item:getInventory()
                    if subInv and subInv:contains(journal) then
                        subInv:Remove(journal)
                        subInv:setDrawDirty(true)
                        -- Debug removed
                    end
                end)
            end
        end
    end

    -- Verify removal
    local stillExists = mainInv and mainInv:contains(journal)
    -- Debug removed

    return not stillExists
end

-- ==================== INITIALIZE JOURNAL (Server-side initialization) ====================
-- Client requests server to initialize an uninitialized journal
-- This ensures UUID and skills are generated SERVER-SIDE and synced to client

function BurdJournals.Server.handleInitializeJournal(player, args)
    if not args or not args.itemType then
        -- Debug removed
        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid request."})
        return
    end

    local itemType = args.itemType
    local clientUUID = args.clientUUID  -- Client may have generated one, we'll use it or create new

    -- Find the journal in player's inventory by type that needs initialization
    local inventory = player:getInventory()
    if not inventory then
        BurdJournals.Server.sendToClient(player, "error", {message = "Inventory not found."})
        return
    end

    local journal = nil
    local allItems = inventory:getItems()

    -- First, try to find by clientUUID if provided (in case modData partially synced)
    if clientUUID then
        for i = 0, allItems:size() - 1 do
            local item = allItems:get(i)
            if item then
                local modData = item:getModData()
                if modData and modData.BurdJournals and modData.BurdJournals.uuid == clientUUID then
                    journal = item
                    -- Debug removed
                    break
                end
            end
        end
    end

    -- If not found by UUID, find by type that's uninitialized or partially initialized
    if not journal then
        for i = 0, allItems:size() - 1 do
            local item = allItems:get(i)
            if item and item:getFullType() == itemType then
                local modData = item:getModData()
                local needsInit = not modData.BurdJournals or
                                  not modData.BurdJournals.uuid or
                                  not modData.BurdJournals.skills
                if needsInit then
                    journal = item
                    break
                end
            end
        end
    end

    -- Also check bags
    if not journal then
        for i = 0, allItems:size() - 1 do
            local item = allItems:get(i)
            if item and item.getInventory then
                local bagInv = item:getInventory()
                if bagInv then
                    local bagItems = bagInv:getItems()
                    for j = 0, bagItems:size() - 1 do
                        local bagItem = bagItems:get(j)
                        if bagItem and bagItem:getFullType() == itemType then
                            local modData = bagItem:getModData()
                            local needsInit = not modData.BurdJournals or
                                              not modData.BurdJournals.uuid or
                                              not modData.BurdJournals.skills
                            if needsInit then
                                journal = bagItem
                                -- Debug removed
                                break
                            end
                        end
                    end
                    if journal then break end
                end
            end
        end
    end

    if not journal then
        -- Debug removed
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal not found for initialization."})
        return
    end

    -- Initialize the journal SERVER-SIDE
    local modData = journal:getModData()
    if not modData.BurdJournals then
        modData.BurdJournals = {}
    end

    -- Use client's UUID if provided, otherwise generate new
    local uuid = clientUUID or BurdJournals.generateUUID()
    modData.BurdJournals.uuid = uuid

    -- Initialize based on journal type
    local journalType = journal:getFullType()
    local isWorn = string.find(journalType, "_Worn") ~= nil
    local isBloody = string.find(journalType, "_Bloody") ~= nil
    local isFilled = string.find(journalType, "Filled") ~= nil

    if isFilled and not modData.BurdJournals.skills then
        -- Generate skills for this journal
        local minSkills, maxSkills, minXP, maxXP

        if isBloody then
            minSkills = BurdJournals.getSandboxOption("BloodyJournalMinSkills") or 2
            maxSkills = BurdJournals.getSandboxOption("BloodyJournalMaxSkills") or 4
            minXP = BurdJournals.getSandboxOption("BloodyJournalMinXP") or 50
            maxXP = BurdJournals.getSandboxOption("BloodyJournalMaxXP") or 150
        else
            minSkills = BurdJournals.getSandboxOption("WornJournalMinSkills") or 1
            maxSkills = BurdJournals.getSandboxOption("WornJournalMaxSkills") or 2
            minXP = BurdJournals.getSandboxOption("WornJournalMinXP") or 25
            maxXP = BurdJournals.getSandboxOption("WornJournalMaxXP") or 75
        end

        local numSkills = ZombRand(minSkills, maxSkills + 1)
        local skills = {}
        local availableSkills = BurdJournals.getAvailableSkills and BurdJournals.getAvailableSkills() or
                                {"Carpentry", "Cooking", "Farming", "Fishing", "Foraging", "Mechanics", "Electricity"}

        for i = 1, numSkills do
            if #availableSkills > 0 then
                local idx = ZombRand(1, #availableSkills + 1)
                local skill = availableSkills[idx]
                table.remove(availableSkills, idx)
                skills[skill] = {
                    xp = ZombRand(minXP, maxXP + 1),
                    level = 0
                }
            end
        end

        modData.BurdJournals.skills = skills
        modData.BurdJournals.claimedSkills = {}

        -- Add traits for bloody journals (1-4 random traits)
        if isBloody then
            local traitChance = BurdJournals.getSandboxOption("BloodyJournalTraitChance") or 15
            if ZombRand(100) < traitChance then
                local grantableTraits = (BurdJournals.getGrantableTraits and BurdJournals.getGrantableTraits()) or
                                        BurdJournals.GRANTABLE_TRAITS or {
                    "Brave", "Organized", "FastLearner", "Wakeful", "Lucky",
                    "LightEater", "Dextrous", "Graceful", "Inconspicuous", "LowThirst"
                }
                local traits = {}
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
                            traits[randomTrait] = true  -- Simplified: just mark trait as present
                            table.remove(availableTraits, idx)
                        end
                    end
                end
                modData.BurdJournals.traits = traits
                modData.BurdJournals.claimedTraits = {}
                -- bloodyOrigin removed - wasFromBloody already tracks this
            end
        end

        -- Generate author name
        modData.BurdJournals.author = BurdJournals.generateRandomName and BurdJournals.generateRandomName() or "Unknown Survivor"
        modData.BurdJournals.isWritten = true
    end


    -- CRITICAL: Sync to client
    if journal.transmitModData then
        journal:transmitModData()
        -- Debug removed
    end

    -- Update item name
    if BurdJournals.updateJournalName then
        BurdJournals.updateJournalName(journal)
    end

    -- Send success response with the UUID
    BurdJournals.Server.sendToClient(player, "journalInitialized", {
        uuid = uuid,
        itemType = itemType,
        skillCount = modData.BurdJournals.skills and BurdJournals.countTable(modData.BurdJournals.skills) or 0
    })
end

-- ==================== LOG SKILLS (Clean Journals) ====================

function BurdJournals.Server.handleLogSkills(player, args)
    if not args or not args.journalId then
        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid request."})
        return
    end

    local journal = BurdJournals.findItemById(player, args.journalId)
    if not journal then
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal not found."})
        return
    end

    if not BurdJournals.isBlankJournal(journal) then
        BurdJournals.Server.sendToClient(player, "error", {message = "This journal already has content."})
        return
    end

    -- Check for writing tool
    if BurdJournals.getSandboxOption("RequirePenToWrite") then
        local pen = BurdJournals.findWritingTool(player)
        if not pen then
            BurdJournals.Server.sendToClient(player, "error", {message = "You need a pen or pencil to write."})
            return
        end
        local usesPerLog = BurdJournals.getSandboxOption("PenUsesPerLog") or 1
        BurdJournals.consumeItemUses(pen, usesPerLog, player)
    end

    -- Collect player data for clean journal
    local journalContent = BurdJournals.collectAllPlayerData(player)

    -- Filter to only selected skills if provided
    local selectedSkills = args.skills
    if selectedSkills and next(selectedSkills) then
        local filteredSkills = {}
        for skillName, _ in pairs(selectedSkills) do
            if journalContent.skills[skillName] then
                filteredSkills[skillName] = journalContent.skills[skillName]
            end
        end
        journalContent.skills = filteredSkills
    end

    -- Create filled journal
    local inventory = player:getInventory()
    inventory:Remove(journal)
    sendRemoveItemFromContainer(inventory, journal)  -- CRITICAL: Notify clients!

    local filledJournal = inventory:AddItem("BurdJournals.FilledSurvivalJournal")
    if filledJournal then
        local modData = filledJournal:getModData()
        modData.BurdJournals = {
            author = player:getDescriptor():getForename() .. " " .. player:getDescriptor():getSurname(),
            ownerUsername = player:getUsername(),  -- Store username for ownership checks (legacy fallback)
            ownerSteamId = BurdJournals.getPlayerSteamId(player),  -- Store Steam ID for ownership (primary)
            ownerCharacterName = player:getDescriptor():getForename() .. " " .. player:getDescriptor():getSurname(),
            timestamp = getGameTime():getWorldAgeHours(),
            readCount = 0,
            -- Clean journal state
            isWorn = false,
            isBloody = false,
            wasFromBloody = false,
            isPlayerCreated = true,
            -- Content
            skills = journalContent.skills,
            traits = journalContent.traits,
        }
        BurdJournals.updateJournalName(filledJournal)
        BurdJournals.updateJournalIcon(filledJournal)

        -- CRITICAL: Sync modData to clients in multiplayer
        if filledJournal.transmitModData then
            filledJournal:transmitModData()
            print("[BurdJournals] Server: transmitModData called for filled journal in handleLogSkills")
        end

        -- CRITICAL: Notify clients about the new item!
        sendAddItemToContainer(inventory, filledJournal)
        print("[BurdJournals] Server: sendAddItemToContainer called for filled journal in handleLogSkills")
    end

    BurdJournals.Server.sendToClient(player, "logSuccess", {})
end

-- ==================== RECORD PROGRESS (Incremental Updates - MP Safe) ====================
-- Handles incremental skill/trait recording from the UI
-- This is the MP-safe version that updates modData server-side

function BurdJournals.Server.handleRecordProgress(player, args)
    if not args or not args.journalId then
        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid request."})
        return
    end

    local journal = BurdJournals.findItemById(player, args.journalId)
    if not journal then
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal not found."})
        return
    end

    -- Check for writing tool if required
    if BurdJournals.getSandboxOption("RequirePenToWrite") then
        local pen = BurdJournals.findWritingTool(player)
        if not pen then
            BurdJournals.Server.sendToClient(player, "error", {message = "You need a pen or pencil to write."})
            return
        end
        local usesPerLog = BurdJournals.getSandboxOption("PenUsesPerLog") or 1
        BurdJournals.consumeItemUses(pen, usesPerLog, player)
    end

    -- Get or create modData
    local modData = journal:getModData()
    if not modData.BurdJournals then
        modData.BurdJournals = {}
    end
    if not modData.BurdJournals.skills then
        modData.BurdJournals.skills = {}
    end
    if not modData.BurdJournals.traits then
        modData.BurdJournals.traits = {}
    end
    if not modData.BurdJournals.stats then
        modData.BurdJournals.stats = {}
    end
    if not modData.BurdJournals.recipes then
        modData.BurdJournals.recipes = {}
    end

    local skillsRecorded = 0
    local traitsRecorded = 0
    local statsRecorded = 0
    local recipesRecorded = 0
    local skillNames = {}
    local traitNames = {}
    local recipeNames = {}

    -- Validate payload size to prevent oversized data issues
    local limits = BurdJournals.Limits or {}
    local existingSkillCount = 0
    local existingTraitCount = 0
    local existingRecipeCount = 0
    for _ in pairs(modData.BurdJournals.skills) do existingSkillCount = existingSkillCount + 1 end
    for _ in pairs(modData.BurdJournals.traits) do existingTraitCount = existingTraitCount + 1 end
    for _ in pairs(modData.BurdJournals.recipes) do existingRecipeCount = existingRecipeCount + 1 end

    local incomingSkillCount = 0
    local incomingTraitCount = 0
    local incomingRecipeCount = 0
    if args.skills then for _ in pairs(args.skills) do incomingSkillCount = incomingSkillCount + 1 end end
    if args.traits then for _ in pairs(args.traits) do incomingTraitCount = incomingTraitCount + 1 end end
    if args.recipes then for _ in pairs(args.recipes) do incomingRecipeCount = incomingRecipeCount + 1 end end

    -- Check against hard limits
    local maxSkills = limits.MAX_SKILLS or 50
    local maxTraits = limits.MAX_TRAITS or 100
    local maxRecipes = limits.MAX_RECIPES or 200

    if existingSkillCount + incomingSkillCount > maxSkills then
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal skill limit reached (" .. maxSkills .. " max)."})
        return
    end
    if existingTraitCount + incomingTraitCount > maxTraits then
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal trait limit reached (" .. maxTraits .. " max)."})
        return
    end
    if existingRecipeCount + incomingRecipeCount > maxRecipes then
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal recipe limit reached (" .. maxRecipes .. " max)."})
        return
    end

    -- Apply skills from client
    if args.skills then
        for skillName, skillData in pairs(args.skills) do
            local existingXP = modData.BurdJournals.skills[skillName] and modData.BurdJournals.skills[skillName].xp or 0
            if skillData.xp and skillData.xp > existingXP then
                modData.BurdJournals.skills[skillName] = {
                    xp = skillData.xp,
                    level = skillData.level or 0
                }
                skillsRecorded = skillsRecorded + 1
                table.insert(skillNames, skillName)
            end
        end
    end

    -- Apply traits from client
    -- Optimized storage: just store true (key is the trait ID, positivity looked up at display time)
    if args.traits then
        for traitId, _ in pairs(args.traits) do
            if not modData.BurdJournals.traits[traitId] then
                modData.BurdJournals.traits[traitId] = true  -- Simplified: just mark trait as present
                traitsRecorded = traitsRecorded + 1
                table.insert(traitNames, traitId)
            end
        end
    end

    -- Apply stats from client
    -- Optimized storage: only store value (owner tracked at journal level)
    if args.stats then
        for statId, statData in pairs(args.stats) do
            -- Stats can always be updated (overwrite with current value)
            modData.BurdJournals.stats[statId] = {
                value = statData.value
            }
            statsRecorded = statsRecorded + 1
        end
    end

    -- Apply recipes from client
    -- Optimized storage: just store true (key is recipe name, source looked up at display time)
    if args.recipes then
        for recipeName, _ in pairs(args.recipes) do
            if not modData.BurdJournals.recipes[recipeName] then
                modData.BurdJournals.recipes[recipeName] = true  -- Simplified: just mark recipe as known
                recipesRecorded = recipesRecorded + 1
                table.insert(recipeNames, recipeName)
            end
        end
    end

    -- Update journal metadata
    modData.BurdJournals.author = player:getDescriptor():getForename() .. " " .. player:getDescriptor():getSurname()
    modData.BurdJournals.ownerUsername = player:getUsername()  -- Store username for ownership checks (legacy fallback)
    modData.BurdJournals.ownerSteamId = BurdJournals.getPlayerSteamId(player)  -- Store Steam ID for ownership (primary)
    modData.BurdJournals.ownerCharacterName = player:getDescriptor():getForename() .. " " .. player:getDescriptor():getSurname()
    modData.BurdJournals.timestamp = getGameTime():getWorldAgeHours()
    modData.BurdJournals.isPlayerCreated = true
    modData.BurdJournals.isWritten = true

    -- Check if this is a blank journal that needs to become filled
    local journalType = journal:getFullType()
    local isBlank = string.find(journalType, "Blank") ~= nil
    local totalItems = BurdJournals.countTable(modData.BurdJournals.skills) + BurdJournals.countTable(modData.BurdJournals.traits) + BurdJournals.countTable(modData.BurdJournals.stats) + BurdJournals.countTable(modData.BurdJournals.recipes)

    print("[BurdJournals] handleRecordProgress: journalType=" .. tostring(journalType) .. ", isBlank=" .. tostring(isBlank) .. ", totalItems=" .. tostring(totalItems))

    local newJournalId = nil

    if isBlank and totalItems > 0 then
        print("[BurdJournals] Converting blank journal to filled...")
        -- Convert blank to filled journal
        local inventory = journal:getContainer()
        if inventory then
            print("[BurdJournals] Got inventory container: " .. tostring(inventory))
            -- Store the modData before removing
            local savedData = {}
            for k, v in pairs(modData.BurdJournals) do
                savedData[k] = v
            end

            -- Remove the blank journal and notify clients (CRITICAL for MP sync!)
            inventory:Remove(journal)
            sendRemoveItemFromContainer(inventory, journal)
            print("[BurdJournals] Removed blank journal and notified clients")

            -- Create a new filled journal and notify clients (CRITICAL for MP sync!)
            local filledJournal = inventory:AddItem("BurdJournals.FilledSurvivalJournal")
            if filledJournal then
                print("[BurdJournals] Created filled journal: " .. tostring(filledJournal:getID()))
                -- Copy the modData to the new journal
                local newModData = filledJournal:getModData()
                newModData.BurdJournals = savedData

                -- Update name and icon
                BurdJournals.updateJournalName(filledJournal)
                BurdJournals.updateJournalIcon(filledJournal)

                -- Sync modData to clients in multiplayer
                if filledJournal.transmitModData then
                    filledJournal:transmitModData()
                    print("[BurdJournals] transmitModData called on filled journal")
                end

                -- Notify clients about the new item in inventory (CRITICAL for MP sync!)
                sendAddItemToContainer(inventory, filledJournal)
                print("[BurdJournals] sendAddItemToContainer called for filled journal")

                newJournalId = filledJournal:getID()
                print("[BurdJournals] Conversion complete, newJournalId=" .. tostring(newJournalId))
            else
                print("[BurdJournals] ERROR: Failed to create filled journal!")
            end
        else
            print("[BurdJournals] ERROR: No inventory container found!")
        end
    else
        print("[BurdJournals] Not converting (isBlank=" .. tostring(isBlank) .. ", totalItems=" .. tostring(totalItems) .. ")")
        -- Just update the existing journal
        BurdJournals.updateJournalName(journal)
        BurdJournals.updateJournalIcon(journal)

        -- Sync modData to clients in multiplayer
        if journal.transmitModData then
            journal:transmitModData()
            print("[BurdJournals] transmitModData called on existing journal")
        end
    end

    -- Get the final journal reference (either new filled or existing)
    local finalJournal = newJournalId and BurdJournals.findItemById(player, newJournalId) or journal
    local journalData = nil
    local finalJournalId = newJournalId or (journal and journal:getID())

    -- Always include journalData in response for immediate UI update
    -- The bandwidth cost is minimal compared to the UX benefit of instant updates
    -- transmitModData is async and unreliable for immediate UI feedback in MP
    local includeJournalData = true

    if includeJournalData and finalJournal then
        local modData = finalJournal:getModData()
        if modData and modData.BurdJournals then
            -- Deep copy the journal data to send to client
            journalData = {}
            for k, v in pairs(modData.BurdJournals) do
                if type(v) == "table" then
                    journalData[k] = {}
                    for k2, v2 in pairs(v) do
                        if type(v2) == "table" then
                            journalData[k][k2] = {}
                            for k3, v3 in pairs(v2) do
                                journalData[k][k2][k3] = v3
                            end
                        else
                            journalData[k][k2] = v2
                        end
                    end
                else
                    journalData[k] = v
                end
            end
        end
    end

    -- Send success response with feedback data AND the updated journal data (if not too large)
    print("[BurdJournals] Sending recordSuccess response, newJournalId=" .. tostring(newJournalId) .. ", journalId=" .. tostring(finalJournalId) .. ", includeJournalData=" .. tostring(includeJournalData))
    BurdJournals.Server.sendToClient(player, "recordSuccess", {
        skillsRecorded = skillsRecorded,
        traitsRecorded = traitsRecorded,
        statsRecorded = statsRecorded,
        recipesRecorded = recipesRecorded,
        skillNames = skillNames,
        traitNames = traitNames,
        recipeNames = recipeNames,
        newJournalId = newJournalId,
        journalId = finalJournalId,
        journalData = journalData  -- May be nil for large journals (client uses transmitModData)
    })
end

-- ==================== SYNC JOURNAL DATA ====================
-- Called by client after local modData changes to sync to server

function BurdJournals.Server.handleSyncJournalData(player, args)
    if not args or not args.journalId then
        print("[BurdJournals] handleSyncJournalData: Invalid request (no journalId)")
        return
    end

    local journal = BurdJournals.findItemById(player, args.journalId)
    if not journal then
        print("[BurdJournals] handleSyncJournalData: Journal not found: " .. tostring(args.journalId))
        return
    end

    -- Just transmit the current modData to ensure sync
    if journal.transmitModData then
        journal:transmitModData()
        print("[BurdJournals] handleSyncJournalData: transmitModData called for journal " .. tostring(args.journalId))
    end
end

-- ==================== LEARN SKILLS (Clean Journals - SET Mode) ====================

function BurdJournals.Server.handleLearnSkills(player, args)
    if not args or not args.journalId then
        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid request."})
        return
    end

    local journal = BurdJournals.findItemById(player, args.journalId)
    if not journal then
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal not found."})
        return
    end

    -- Must be a clean filled journal
    if not BurdJournals.canSetXP(journal) then
        BurdJournals.Server.sendToClient(player, "error", {message = "Cannot learn from this journal."})
        return
    end

    local modData = journal:getModData()
    if not modData.BurdJournals or not modData.BurdJournals.skills then
        BurdJournals.Server.sendToClient(player, "error", {message = "This journal has no skill data."})
        return
    end

    -- Calculate multiplier based on read count (diminishing returns)
    local multiplier = 1.0
    local recoveryMode = BurdJournals.getSandboxOption("XPRecoveryMode") or 1

    if recoveryMode == 2 then
        local readCount = modData.BurdJournals.readCount or 0
        local firstRead = (BurdJournals.getSandboxOption("DiminishingFirstRead") or 100) / 100
        local decayRate = (BurdJournals.getSandboxOption("DiminishingDecayRate") or 10) / 100
        local minimum = (BurdJournals.getSandboxOption("DiminishingMinimum") or 10) / 100

        if readCount == 0 then
            multiplier = firstRead
        else
            multiplier = math.max(minimum, firstRead - (decayRate * readCount))
        end
        modData.BurdJournals.readCount = readCount + 1
    end

    -- Get selected skills from args, or use all skills if not specified
    local selectedSkills = args.skills
    local journalSkills = modData.BurdJournals.skills

    -- Prepare skills to apply (SET mode - only apply if journal XP is higher)
    local skillsToSet = {}
    for skillName, storedData in pairs(journalSkills) do
        -- Only include if no selection provided, or skill is in selection
        if not selectedSkills or not next(selectedSkills) or selectedSkills[skillName] then
            skillsToSet[skillName] = {
                xp = math.floor(storedData.xp * multiplier),
                level = storedData.level,
                mode = "set" -- SET mode for clean journals
            }
        end
    end

    BurdJournals.Server.sendToClient(player, "applyXP", {skills = skillsToSet, mode = "set"})
end

-- ==================== CLAIM SKILL (Player Journals - SET Mode, Individual) ====================
-- Used by the timed learning UI for player journals

function BurdJournals.Server.handleClaimSkill(player, args)
    -- Debug removed
    if not args or not args.skillName then
        -- Debug removed
        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid request."})
        return
    end

    local journalId = args.journalId
    local skillName = args.skillName

    -- Find the journal
    local journal = BurdJournals.findItemById(player, journalId)
    if not journal then
        print("[BurdJournals] Server ERROR: Journal not found by ID " .. tostring(journalId))
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal not found."})
        return
    end

    -- Check permission to claim from this journal
    local canClaim, reason = BurdJournals.canPlayerClaimFromJournal(player, journal)
    if not canClaim then
        BurdJournals.Server.sendToClient(player, "error", {message = reason or "Permission denied."})
        return
    end

    -- Get modData
    local modData = journal:getModData()
    local journalData = modData.BurdJournals

    if not journalData or not journalData.skills then
        BurdJournals.Server.sendToClient(player, "error", {message = "This journal has no skill data."})
        return
    end

    -- Check if skill exists in journal
    if not journalData.skills[skillName] then
        print("[BurdJournals] Server ERROR: Skill '" .. skillName .. "' not found in journal")
        BurdJournals.Server.sendToClient(player, "error", {message = "Skill not found in journal."})
        return
    end

    -- Get skill data from journal
    local skillData = journalData.skills[skillName]
    local recordedXP = skillData.xp or 0
    local recordedLevel = skillData.level or 0

    -- Get player's current XP for comparison
    local perk = BurdJournals.getPerkByName(skillName)
    if not perk then
        print("[BurdJournals] Server ERROR: Could not find perk for skill '" .. skillName .. "'")
        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid skill: " .. skillName})
        return
    end

    local playerXP = player:getXp():getXP(perk)

    -- SET mode: Only apply if recorded XP is higher than player's current
    if recordedXP > playerXP then
        local xpDiff = recordedXP - playerXP

        -- Send the SET mode command to client
        BurdJournals.Server.sendToClient(player, "applyXP", {
            skills = {
                [skillName] = {
                    xp = recordedXP,  -- Total XP to set to
                    level = recordedLevel,
                    mode = "set"
                }
            },
            mode = "set"
        })

        -- Mark skill as claimed in journal using per-character tracking
        BurdJournals.markSkillClaimedByCharacter(journalData, player, skillName)

        -- Sync modData
        if journal.transmitModData then
            journal:transmitModData()
        end

        -- Send success response with journal data for UI update
        BurdJournals.Server.sendToClient(player, "claimSuccess", {
            skillName = skillName,
            xpSet = recordedXP,
            xpGained = xpDiff,
            journalId = journal:getID(),
            journalData = BurdJournals.Server.copyJournalData(journal)
        })
    else
        -- Player already at or above this level
        -- Debug removed
        BurdJournals.Server.sendToClient(player, "skillMaxed", {
            skillName = skillName,
            message = "You already have higher or equal skill level."
        })
    end
end

-- ==================== CLAIM TRAIT (Player Journals - SET Mode) ====================
-- Used by the timed learning UI for player journals

function BurdJournals.Server.handleClaimTrait(player, args)
    -- Debug removed
    if not args or not args.traitId then
        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid request."})
        return
    end

    local journalId = args.journalId
    local traitId = args.traitId

    -- Find the journal
    local journal = BurdJournals.findItemById(player, journalId)
    if not journal then
        print("[BurdJournals] Server ERROR: Journal not found by ID " .. tostring(journalId))
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal not found."})
        return
    end

    -- Check permission to claim from this journal
    local canClaim, reason = BurdJournals.canPlayerClaimFromJournal(player, journal)
    if not canClaim then
        BurdJournals.Server.sendToClient(player, "error", {message = reason or "Permission denied."})
        return
    end

    -- Get modData
    local modData = journal:getModData()
    local journalData = modData.BurdJournals

    if not journalData or not journalData.traits then
        BurdJournals.Server.sendToClient(player, "error", {message = "This journal has no trait data."})
        return
    end

    -- Check if trait exists in journal
    if not journalData.traits[traitId] then
        print("[BurdJournals] Server ERROR: Trait '" .. traitId .. "' not found in journal")
        BurdJournals.Server.sendToClient(player, "error", {message = "Trait not found in journal."})
        return
    end

    -- Check if player already has this trait
    if BurdJournals.playerHasTrait(player, traitId) then
        BurdJournals.Server.sendToClient(player, "traitAlreadyKnown", {traitId = traitId})
        return
    end

    -- Try to add the trait (using same logic as absorbTrait)
    local traitWasAdded = BurdJournals.safeAddTrait(player, traitId)

    if traitWasAdded then
        -- Mark trait as claimed using per-character tracking
        BurdJournals.markTraitClaimedByCharacter(journalData, player, traitId)

        -- Sync modData
        if journal.transmitModData then
            journal:transmitModData()
        end

        -- Send success response with journal data for UI update
        BurdJournals.Server.sendToClient(player, "claimSuccess", {
            traitId = traitId,
            journalId = journal:getID(),
            journalData = BurdJournals.Server.copyJournalData(journal)
        })
    else
        BurdJournals.Server.sendToClient(player, "error", {message = "Could not learn trait."})
    end
end

-- ==================== ABSORB SKILL (Worn Journals - ADD Mode) ====================

function BurdJournals.Server.handleAbsorbSkill(player, args)
    if not args or not args.skillName then
        -- Debug removed
        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid request."})
        return
    end

    local journalId = args.journalId
    local skillName = args.skillName
    -- Debug removed)

    -- Find the journal by item ID (same as clean journals)
    local journal = BurdJournals.findItemById(player, journalId)

    if not journal then
        print("[BurdJournals] Server ERROR: Journal not found by ID " .. tostring(journalId))
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal not found."})
        return
    end


    -- Must be a worn/bloody journal (readable for absorption)
    if not BurdJournals.canAbsorbXP(journal) then
        BurdJournals.Server.sendToClient(player, "error", {message = "Cannot absorb from this journal."})
        return
    end

    -- Get modData
    local modData = journal:getModData()

    if modData then
        -- Debug removed
        for k, v in pairs(modData) do
            print("  - " .. tostring(k) .. " = " .. type(v))
        end
    end

    local journalData = modData.BurdJournals

    if not journalData then
        BurdJournals.Server.sendToClient(player, "error", {message = "This journal has no data."})
        return
    end

    -- Debug removed
    for k, v in pairs(journalData) do
        local valueStr = tostring(v)
        if type(v) == "table" then
            valueStr = "table with " .. BurdJournals.countTable(v) .. " entries"
        end
        print("  - " .. tostring(k) .. " = " .. valueStr)
    end

    if not journalData.skills then
        BurdJournals.Server.sendToClient(player, "error", {message = "This journal has no skill data."})
        return
    end

    -- Debug: Print ALL skills in the journal with full detail
    local skillCount = BurdJournals.countTable(journalData.skills)
    -- Debug removed
    for skillKey, skillVal in pairs(journalData.skills) do
        if type(skillVal) == "table" then
            print("  - '" .. tostring(skillKey) .. "': xp=" .. tostring(skillVal.xp) .. ", level=" .. tostring(skillVal.level))
        else
            print("  - '" .. tostring(skillKey) .. "': INVALID (not a table, is " .. type(skillVal) .. ")")
        end
    end

    -- Debug removed

    -- Check if skill exists in journal
    if not journalData.skills[skillName] then
        print("[BurdJournals] Server ERROR: Skill '" .. tostring(skillName) .. "' not found in journal!")
        -- Debug removed
        for k, _ in pairs(journalData.skills) do
            print("  - '" .. tostring(k) .. "'")
        end
        BurdJournals.Server.sendToClient(player, "error", {message = "Skill not found in journal."})
        return
    end

    -- Check if THIS CHARACTER has already claimed this skill (per-character tracking)
    if BurdJournals.hasCharacterClaimedSkill(journalData, player, skillName) then
        BurdJournals.Server.sendToClient(player, "error", {message = "This skill has already been claimed."})
        return
    end

    -- Get skill data
    local skillData = journalData.skills[skillName]

    if type(skillData) ~= "table" then
        print("[BurdJournals] Server ERROR: skillData is not a table! It's: " .. type(skillData) .. " = " .. tostring(skillData))
        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid skill data."})
        return
    end

    -- Get base XP
    local baseXP = skillData.xp
    -- Debug removed

    if baseXP == nil then
        -- Debug removed
        for k, v in pairs(skillData) do
            print("  - " .. tostring(k) .. " = " .. tostring(v))
        end
        -- Try to recover
        baseXP = 0
    end

    if type(baseXP) ~= "number" then
        -- print removed
        baseXP = tonumber(baseXP) or 0
    end

    -- Get journal XP multiplier from sandbox (default 1.0)
    local journalMultiplier = BurdJournals.getSandboxOption("JournalXPMultiplier") or 1.0
    local xpToAdd = baseXP * journalMultiplier


    -- Get the perk
    local perk = BurdJournals.getPerkByName(skillName)

    if not perk then
        -- Debug removed
        perk = Perks[skillName]

        if not perk and BurdJournals.SKILL_TO_PERK and BurdJournals.SKILL_TO_PERK[skillName] then
            local mappedName = BurdJournals.SKILL_TO_PERK[skillName]
            -- Debug removed
            perk = Perks[mappedName]
        end
    end

    if not perk then
        print("[BurdJournals] Server ERROR: Could not find perk for skill '" .. skillName .. "'")
        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid skill: " .. skillName})
        return
    end

    -- MULTIPLAYER: Client must apply XP (server proxy can't modify XP directly)
    -- Server validates, marks claimed, and tells client to apply XP
    if xpToAdd > 0 then
        -- Mark skill as claimed on server FIRST (per-character tracking)
        BurdJournals.markSkillClaimedByCharacter(journalData, player, skillName)
        -- Debug removed

        -- Check dissolution state using shared function (includes skills, traits, AND recipes)
        local shouldDis = BurdJournals.shouldDissolve(journal)

        -- Send applyXP command to CLIENT - client will apply XP
        -- Debug removed
        BurdJournals.Server.sendToClient(player, "applyXP", {
            skills = {
                [skillName] = {
                    xp = xpToAdd,
                    mode = "add"
                }
            },
            mode = "add"
        })

        -- Handle dissolution or continuation
        if shouldDis then
            -- Get fresh reference to journal by ID to ensure we have valid object
            local journalId = journal:getID()
            local freshJournal = BurdJournals.findItemById(player, journalId)

            if freshJournal then
                -- AGGRESSIVE DELETION
                local container = freshJournal:getContainer()

                if container then
                    container:Remove(freshJournal)
                end

                -- Also remove from player inventory directly
                local inv = player:getInventory()
                if inv:contains(freshJournal) then
                    inv:Remove(freshJournal)
                end
            end

            -- Notify client
            BurdJournals.Server.sendToClient(player, "journalDissolved", {
                message = BurdJournals.getRandomDissolutionMessage(),
                journalId = journalId
            })
        else
            -- Sync modData since we're keeping the journal
            if journal.transmitModData then
                journal:transmitModData()
            end

            -- Tell client to update UI with journal data
            local remainingRewards = BurdJournals.getUnclaimedSkillCount(journal) +
                                     BurdJournals.getUnclaimedTraitCount(journal) +
                                     BurdJournals.getUnclaimedRecipeCount(journal)
            BurdJournals.Server.sendToClient(player, "absorbSuccess", {
                skillName = skillName,
                xpGained = xpToAdd,
                remaining = remainingRewards,
                total = BurdJournals.getTotalRewards(journal),
                journalId = journal:getID(),
                journalData = BurdJournals.Server.copyJournalData(journal)
            })
        end
    else
        -- xpToAdd was 0 or negative - this is the "maxed" case
        BurdJournals.Server.sendToClient(player, "skillMaxed", {
            skillName = skillName
        })
    end

end

-- ==================== ABSORB TRAIT (Worn Journals from Bloody) ====================

function BurdJournals.Server.handleAbsorbTrait(player, args)
    if not args or not args.traitId then
        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid request."})
        return
    end

    local journalId = args.journalId
    local traitId = args.traitId

    -- Find the journal by item ID (same as clean journals)
    local journal = BurdJournals.findItemById(player, journalId)

    if not journal then
        print("[BurdJournals] Server ERROR: Journal not found by ID " .. tostring(journalId))
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal not found."})
        return
    end


    -- Must be a worn/bloody journal
    if not BurdJournals.canAbsorbXP(journal) then
        BurdJournals.Server.sendToClient(player, "error", {message = "Cannot absorb from this journal."})
        return
    end

    local modData = journal:getModData()
    local journalData = modData.BurdJournals

    if not journalData or not journalData.traits then
        BurdJournals.Server.sendToClient(player, "error", {message = "This journal has no trait data."})
        return
    end

    -- Check if trait exists in journal (double-check after fallback)
    if not journalData.traits[traitId] then
        BurdJournals.Server.sendToClient(player, "error", {message = "Trait not found in journal."})
        return
    end

    -- Check if THIS CHARACTER has already claimed this trait (per-character tracking)
    if BurdJournals.hasCharacterClaimedTrait(journalData, player, traitId) then
        BurdJournals.Server.sendToClient(player, "error", {message = "This trait has already been claimed."})
        return
    end

    -- Check if player already has this trait - DON'T claim if they do
    if BurdJournals.playerHasTrait(player, traitId) then
        -- Player already knows this trait - leave it unclaimed in journal
        BurdJournals.Server.sendToClient(player, "traitAlreadyKnown", {traitId = traitId})
        return  -- Don't dissolve check - trait stays in journal
    end

    -- Try to grant the trait using Build 42 API
    -- B42 trait enums are UPPERCASE (e.g., CharacterTrait.BRAVE)
    -- Debug removed

    local traitWasAdded = false
    local success, err = pcall(function()
        local characterTrait = nil

        -- METHOD 1: Use CharacterTrait.get() with ResourceLocation object (B42 way)
        if CharacterTrait and CharacterTrait.get and ResourceLocation and ResourceLocation.of then
            -- Try "base:traitname" format (lowercase)
            local resourceLoc = "base:" .. string.lower(traitId)

            local ok, result = pcall(function()
                return CharacterTrait.get(ResourceLocation.of(resourceLoc))
            end)
            if ok and result then
                characterTrait = result
            end

            -- If that didn't work, try with spaces inserted before capitals (FastLearner -> fast learner)
            if not characterTrait then
                local withSpaces = string.lower(traitId:gsub("(%u)", " %1"):sub(2))
                local resourceLocSpaces = "base:" .. withSpaces
                if resourceLocSpaces ~= resourceLoc then
                    ok, result = pcall(function()
                        return CharacterTrait.get(ResourceLocation.of(resourceLocSpaces))
                    end)
                    if ok and result then
                        characterTrait = result
                    end
                end
            end
        end

        -- METHOD 2: Try direct table lookup with UPPERCASE_UNDERSCORE format
        if not characterTrait and CharacterTrait then
            local underscored = traitId:gsub("(%u)", "_%1"):sub(2):upper()

            local ct = CharacterTrait[underscored]
            if ct then
                if type(ct) == "string" and CharacterTrait.get and ResourceLocation and ResourceLocation.of then
                    local ok, result = pcall(function()
                        return CharacterTrait.get(ResourceLocation.of(ct))
                    end)
                    if ok and result then
                        characterTrait = result
                    end
                else
                    characterTrait = ct
                end
            end
        end

        -- METHOD 3: Try CharacterTraitDefinition iteration as last resort
        if not characterTrait and CharacterTraitDefinition and CharacterTraitDefinition.getTraits then
            local allTraits = CharacterTraitDefinition.getTraits()

            for i = 0, allTraits:size() - 1 do
                local def = allTraits:get(i)
                local defType = def:getType()
                local defLabel = def:getLabel()
                local defName = "?"
                if defType then
                    pcall(function() defName = defType:getName() or tostring(defType) end)
                end

                if defLabel == traitId or defName == traitId or string.upper(defName) == string.upper(traitId) then
                    characterTrait = defType
                    break
                end
            end
        end


        if characterTrait then
            local charTraits = player:getCharacterTraits()

            -- Check BEFORE
            local hadBefore = player:hasTrait(characterTrait)

            -- Use the EXACT pattern from ISPlayerStatsUI:onAddTrait
            -- Step 1: Add the trait
            charTraits:add(characterTrait)
            -- Debug removed

            -- Step 2: Modify trait XP boost (false = adding trait)
            if player.modifyTraitXPBoost then
                player:modifyTraitXPBoost(characterTrait, false)
                -- Debug removed
            end

            -- Step 3: SYNC the changes - THIS IS CRITICAL!
            if SyncXp then
                SyncXp(player)
                -- Debug removed
            else
                -- print removed
            end

            -- Verify AFTER
            local hasAfter = player:hasTrait(characterTrait)

            if hasAfter and not hadBefore then
                -- Debug removed
                return true
            elseif hasAfter and hadBefore then
                -- Debug removed
                return false
            else
                -- Debug removed
                return false
            end
        else
            print("[BurdJournals] Server: ERROR - Could not find CharacterTrait for: " .. traitId)
            return false
        end
    end)

    if success then
        traitWasAdded = (err == true)
    else
        print("[BurdJournals] Server: pcall error: " .. tostring(err))
    end
    -- Debug removed

    if traitWasAdded then
        -- Trait was granted - NOW mark as claimed (per-character tracking)
        BurdJournals.markTraitClaimedByCharacter(journalData, player, traitId)

        -- Check dissolution state using shared function (includes skills, traits, AND recipes)
        local shouldDis = BurdJournals.shouldDissolve(journal)

        -- Send command to show feedback on client with journal data for UI sync
        BurdJournals.Server.sendToClient(player, "grantTrait", {
            traitId = traitId,
            journalId = journal:getID(),
            journalData = BurdJournals.Server.copyJournalData(journal)
        })

        -- Handle dissolution or continuation
        if shouldDis then
            -- Get fresh reference to journal by ID
            local journalId = journal:getID()
            local freshJournal = BurdJournals.findItemById(player, journalId)

            if freshJournal then
                -- AGGRESSIVE DELETION
                local container = freshJournal:getContainer()

                if container then
                    container:Remove(freshJournal)
                end

                -- Also remove from player inventory directly
                local inv = player:getInventory()
                if inv:contains(freshJournal) then
                    inv:Remove(freshJournal)
                end
            end

            -- Notify client
            BurdJournals.Server.sendToClient(player, "journalDissolved", {
                message = BurdJournals.getRandomDissolutionMessage(),
                journalId = journalId
            })
        else
            -- Only sync modData if we're keeping the journal
            if journal.transmitModData then
                journal:transmitModData()
            end

            -- Send success response with journal data for UI update
            local remainingRewards = BurdJournals.getUnclaimedSkillCount(journal) +
                                     BurdJournals.getUnclaimedTraitCount(journal) +
                                     BurdJournals.getUnclaimedRecipeCount(journal)
            BurdJournals.Server.sendToClient(player, "absorbSuccess", {
                traitId = traitId,
                remaining = remainingRewards,
                total = BurdJournals.getTotalRewards(journal),
                journalId = journal:getID(),
                journalData = BurdJournals.Server.copyJournalData(journal)
            })
        end
    else
        -- Failed to grant trait - don't claim
        BurdJournals.Server.sendToClient(player, "error", {message = "Could not learn trait."})
    end
end

-- ==================== ERASE JOURNAL (Clean Journals Only) ====================

function BurdJournals.Server.handleEraseJournal(player, args)
    if not args or not args.journalId then
        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid request."})
        return
    end
    
    local journal = BurdJournals.findItemById(player, args.journalId)
    if not journal then
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal not found."})
        return
    end
    
    -- Can only erase clean journals
    if not BurdJournals.isClean(journal) then
        BurdJournals.Server.sendToClient(player, "error", {message = "Can only erase clean journals."})
        return
    end
    
    -- Check for eraser
    if BurdJournals.getSandboxOption("RequireEraserToErase") then
        local eraser = BurdJournals.findEraser(player)
        if not eraser then
            BurdJournals.Server.sendToClient(player, "error", {message = "You need an eraser to wipe the journal."})
            return
        end
    end
    
    -- Replace with blank journal
    local inventory = player:getInventory()
    inventory:Remove(journal)
    sendRemoveItemFromContainer(inventory, journal)  -- CRITICAL: Notify clients!

    local blankJournal = inventory:AddItem("BurdJournals.BlankSurvivalJournal")
    if blankJournal then
        local modData = blankJournal:getModData()
        modData.BurdJournals = {
            isWorn = false,
            isBloody = false,
            isPlayerCreated = true,
        }
        BurdJournals.updateJournalName(blankJournal)
        BurdJournals.updateJournalIcon(blankJournal)

        -- CRITICAL: Sync modData to clients in multiplayer
        if blankJournal.transmitModData then
            blankJournal:transmitModData()
            print("[BurdJournals] Server: transmitModData called for blank journal in handleEraseJournal")
        end

        -- CRITICAL: Notify clients about the new item!
        sendAddItemToContainer(inventory, blankJournal)
        print("[BurdJournals] Server: sendAddItemToContainer called for blank journal in handleEraseJournal")
    end

    BurdJournals.Server.sendToClient(player, "eraseSuccess", {})
end

-- ==================== CLEAN BLOODY -> WORN (DEPRECATED) ====================
-- NOTE: Bloody journals can now be read directly without cleaning.
-- This handler is kept for backwards compatibility but returns an info message.

function BurdJournals.Server.handleCleanBloody(player, args)
    -- Bloody journals no longer need cleaning - they can be read directly
    BurdJournals.Server.sendToClient(player, "error", {
        message = "Bloody journals can now be read directly. Right-click to open and absorb XP."
    })
end

-- ==================== CONVERT WORN -> CLEAN BLANK ====================

function BurdJournals.Server.handleConvertToClean(player, args)
    if not args or not args.journalId then
        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid request."})
        return
    end
    
    local journal = BurdJournals.findItemById(player, args.journalId)
    if not journal then
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal not found."})
        return
    end
    
    -- Must be worn
    if not BurdJournals.isWorn(journal) then
        BurdJournals.Server.sendToClient(player, "error", {message = "Only worn journals can be converted."})
        return
    end
    
    -- Check for materials and skill
    if not BurdJournals.canConvertToClean(player) then
        BurdJournals.Server.sendToClient(player, "error", {message = "You need leather, thread, needle, and Tailoring Lv1."})
        return
    end
    
    -- Consume materials
    local leather = BurdJournals.findRepairItem(player, "leather")
    local thread = BurdJournals.findRepairItem(player, "thread")
    local needle = BurdJournals.findRepairItem(player, "needle")
    
    player:getInventory():Remove(leather)
    BurdJournals.consumeItemUses(thread, 1, player)
    BurdJournals.consumeItemUses(needle, 1, player)
    
    -- Replace with clean blank journal
    local inventory = player:getInventory()
    inventory:Remove(journal)
    sendRemoveItemFromContainer(inventory, journal)  -- CRITICAL: Notify clients!

    local cleanJournal = inventory:AddItem("BurdJournals.BlankSurvivalJournal")
    if cleanJournal then
        local modData = cleanJournal:getModData()
        modData.BurdJournals = {
            isWorn = false,
            isBloody = false,
            wasFromBloody = false,
            isPlayerCreated = true,
        }
        BurdJournals.updateJournalName(cleanJournal)
        BurdJournals.updateJournalIcon(cleanJournal)

        -- CRITICAL: Sync modData to clients in multiplayer
        if cleanJournal.transmitModData then
            cleanJournal:transmitModData()
            print("[BurdJournals] Server: transmitModData called for clean journal in handleConvertToClean")
        end

        -- CRITICAL: Notify clients about the new item!
        sendAddItemToContainer(inventory, cleanJournal)
        print("[BurdJournals] Server: sendAddItemToContainer called for clean journal in handleConvertToClean")
    end

    BurdJournals.Server.sendToClient(player, "convertSuccess", {
        message = "The worn journal has been restored to a clean blank journal."
    })
end

-- ==================== CLAIM RECIPE (Player Journals - SET Mode) ====================
-- Used by the timed learning UI for player journals

function BurdJournals.Server.handleClaimRecipe(player, args)
    if not args or not args.recipeName then
        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid request."})
        return
    end

    local journalId = args.journalId
    local recipeName = args.recipeName

    -- Find the journal
    local journal = BurdJournals.findItemById(player, journalId)
    if not journal then
        print("[BurdJournals] Server ERROR: Journal not found by ID " .. tostring(journalId))
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal not found."})
        return
    end

    -- Check permission to claim from this journal
    local canClaim, reason = BurdJournals.canPlayerClaimFromJournal(player, journal)
    if not canClaim then
        BurdJournals.Server.sendToClient(player, "error", {message = reason or "Permission denied."})
        return
    end

    -- Get modData
    local modData = journal:getModData()
    local journalData = modData.BurdJournals

    if not journalData or not journalData.recipes then
        BurdJournals.Server.sendToClient(player, "error", {message = "This journal has no recipe data."})
        return
    end

    -- Check if recipe exists in journal
    if not journalData.recipes[recipeName] then
        print("[BurdJournals] Server ERROR: Recipe '" .. recipeName .. "' not found in journal")
        BurdJournals.Server.sendToClient(player, "error", {message = "Recipe not found in journal."})
        return
    end

    -- Check if player already knows this recipe
    if BurdJournals.playerKnowsRecipe(player, recipeName) then
        BurdJournals.Server.sendToClient(player, "recipeAlreadyKnown", {recipeName = recipeName})
        return
    end

    -- Use the comprehensive shared utility for learning recipes
    local recipeWasLearned = BurdJournals.learnRecipeWithVerification(player, recipeName, "[BurdJournals Server]")

    if recipeWasLearned then
        -- Mark recipe as claimed using per-character tracking
        BurdJournals.markRecipeClaimedByCharacter(journalData, player, recipeName)

        -- Sync modData
        if journal.transmitModData then
            journal:transmitModData()
        end

        -- Sync player fields (recipes) - bit flags for recipe sync
        if sendSyncPlayerFields then
            sendSyncPlayerFields(player, 0x00000007)
        end

        -- Send success response with journal data for UI update
        BurdJournals.Server.sendToClient(player, "claimSuccess", {
            recipeName = recipeName,
            journalId = journal:getID(),
            journalData = BurdJournals.Server.copyJournalData(journal)
        })
    else
        BurdJournals.Server.sendToClient(player, "error", {message = "Could not learn recipe."})
    end
end

-- ==================== ABSORB RECIPE (Worn/Bloody Journals - ADD Mode) ====================

function BurdJournals.Server.handleAbsorbRecipe(player, args)
    if not args or not args.recipeName then
        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid request."})
        return
    end

    local journalId = args.journalId
    local recipeName = args.recipeName

    -- Find the journal by item ID
    local journal = BurdJournals.findItemById(player, journalId)
    if not journal then
        print("[BurdJournals] Server ERROR: Journal not found by ID " .. tostring(journalId))
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal not found."})
        return
    end

    -- Must be a worn/bloody journal (readable for absorption)
    if not BurdJournals.canAbsorbXP(journal) then
        BurdJournals.Server.sendToClient(player, "error", {message = "Cannot absorb from this journal."})
        return
    end

    -- Get modData
    local modData = journal:getModData()
    local journalData = modData.BurdJournals

    if not journalData or not journalData.recipes then
        BurdJournals.Server.sendToClient(player, "error", {message = "This journal has no recipe data."})
        return
    end

    -- Check if recipe exists in journal
    if not journalData.recipes[recipeName] then
        print("[BurdJournals] Server ERROR: Recipe '" .. recipeName .. "' not found in journal")
        BurdJournals.Server.sendToClient(player, "error", {message = "Recipe not found in journal."})
        return
    end

    -- Check if THIS CHARACTER has already claimed this recipe (per-character tracking)
    if BurdJournals.hasCharacterClaimedRecipe(journalData, player, recipeName) then
        BurdJournals.Server.sendToClient(player, "error", {message = "Recipe already claimed."})
        return
    end

    -- Check if player already knows this recipe
    if BurdJournals.playerKnowsRecipe(player, recipeName) then
        -- Mark as claimed but notify player they already know it
        BurdJournals.markRecipeClaimedByCharacter(journalData, player, recipeName)

        if journal.transmitModData then
            journal:transmitModData()
        end

        BurdJournals.Server.sendToClient(player, "recipeAlreadyKnown", {
            recipeName = recipeName,
            journalId = journal:getID(),
            journalData = BurdJournals.Server.copyJournalData(journal)
        })

        -- Check for dissolution after claiming
        if BurdJournals.shouldDissolve(journal) then
            local dissolutionMessage = BurdJournals.getRandomDissolutionMessage()
            removeJournalCompletely(player, journal)
            BurdJournals.Server.sendToClient(player, "journalDissolved", {
                message = dissolutionMessage
            })
        end
        return
    end

    -- Use the comprehensive shared utility for learning recipes
    local recipeWasLearned = BurdJournals.learnRecipeWithVerification(player, recipeName, "[BurdJournals Server]")

    if recipeWasLearned then
        -- Mark recipe as claimed using per-character tracking
        BurdJournals.markRecipeClaimedByCharacter(journalData, player, recipeName)

        -- Sync modData
        if journal.transmitModData then
            journal:transmitModData()
        end

        -- Sync player fields (recipes) - bit flags for recipe sync
        if sendSyncPlayerFields then
            sendSyncPlayerFields(player, 0x00000007)
        end

        -- Get updated journal data for client
        local updatedJournalData = BurdJournals.Server.copyJournalData(journal)

        -- Check for dissolution
        if BurdJournals.shouldDissolve(journal) then
            local dissolutionMessage = BurdJournals.getRandomDissolutionMessage()
            removeJournalCompletely(player, journal)

            BurdJournals.Server.sendToClient(player, "absorbSuccess", {
                recipeName = recipeName,
                journalData = updatedJournalData,
                dissolved = true,
                dissolutionMessage = dissolutionMessage
            })
        else
            BurdJournals.Server.sendToClient(player, "absorbSuccess", {
                recipeName = recipeName,
                journalId = journal:getID(),
                journalData = updatedJournalData,
                dissolved = false
            })
        end
    else
        BurdJournals.Server.sendToClient(player, "error", {message = "Could not learn recipe."})
    end
end

-- ==================== ERASE ENTRY HANDLER ====================

function BurdJournals.Server.handleEraseEntry(player, args)
    if not args then
        print("[BurdJournals] Server: EraseEntry - No args provided")
        return
    end

    local journalId = args.journalId
    local entryType = args.entryType  -- "skill", "trait", or "recipe"
    local entryName = args.entryName

    if not journalId or not entryType or not entryName then
        print("[BurdJournals] Server: EraseEntry - Missing required args")
        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid erase request."})
        return
    end

    print("[BurdJournals] Server: Processing erase request - type: " .. entryType .. ", name: " .. entryName)

    -- Find journal by ID
    local journal = BurdJournals.findItemById(player, journalId)
    if not journal then
        print("[BurdJournals] Server: EraseEntry - Journal not found: " .. tostring(journalId))
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal not found."})
        return
    end

    -- Get journal data
    local modData = journal:getModData()
    if not modData or not modData.BurdJournals then
        print("[BurdJournals] Server: EraseEntry - No journal data")
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal has no data."})
        return
    end

    local journalData = modData.BurdJournals
    local erased = false

    -- Remove entry based on type
    if entryType == "skill" then
        if journalData.skills and journalData.skills[entryName] then
            journalData.skills[entryName] = nil
            erased = true
            print("[BurdJournals] Server: Erased skill entry: " .. entryName)
        end
        -- Also remove from claimed skills if present
        if journalData.claimedSkills and journalData.claimedSkills[entryName] then
            journalData.claimedSkills[entryName] = nil
        end
    elseif entryType == "trait" then
        if journalData.traits and journalData.traits[entryName] then
            journalData.traits[entryName] = nil
            erased = true
            print("[BurdJournals] Server: Erased trait entry: " .. entryName)
        end
        -- Also remove from claimed traits if present
        if journalData.claimedTraits and journalData.claimedTraits[entryName] then
            journalData.claimedTraits[entryName] = nil
        end
    elseif entryType == "recipe" then
        if journalData.recipes and journalData.recipes[entryName] then
            journalData.recipes[entryName] = nil
            erased = true
            print("[BurdJournals] Server: Erased recipe entry: " .. entryName)
        end
        -- Also remove from claimed recipes if present
        if journalData.claimedRecipes and journalData.claimedRecipes[entryName] then
            journalData.claimedRecipes[entryName] = nil
        end
    end

    if erased then
        -- Sync modData
        if journal.transmitModData then
            journal:transmitModData()
        end

        -- Get updated journal data for client
        local updatedJournalData = BurdJournals.Server.copyJournalData(journal)

        BurdJournals.Server.sendToClient(player, "eraseSuccess", {
            entryType = entryType,
            entryName = entryName,
            journalId = journal:getID(),
            journalData = updatedJournalData
        })
        print("[BurdJournals] Server: Erase successful, sent confirmation to client")
    else
        print("[BurdJournals] Server: Entry not found to erase: " .. entryType .. " - " .. entryName)
        BurdJournals.Server.sendToClient(player, "error", {message = "Entry not found."})
    end
end

-- ==================== EVENT REGISTRATION ====================

print("[BurdJournals] Registering OnClientCommand handler...")
Events.OnClientCommand.Add(BurdJournals.Server.onClientCommand)
Events.OnServerStarted.Add(BurdJournals.Server.init)
print("[BurdJournals] Server module fully loaded!")



