print("[BurdJournals] SERVER FILE START - BEFORE REQUIRE")

require "BurdJournals_Shared"

print("[BurdJournals] SERVER MODULE LOADING... (require completed)")

BurdJournals = BurdJournals or {}
BurdJournals.Server = BurdJournals.Server or {}

BurdJournals.Server._rateLimitCache = {}

function BurdJournals.Server.cleanupRateLimitCache()
    local now = getTimestampMs and getTimestampMs() or 0
    local staleThreshold = 60000
    for playerId, timestamp in pairs(BurdJournals.Server._rateLimitCache) do
        if now - timestamp > staleThreshold then
            BurdJournals.Server._rateLimitCache[playerId] = nil
        end
    end
end

function BurdJournals.Server.deepCopy(orig, copies)
    copies = copies or {}
    local origType = type(orig)
    local copy

    if origType == 'table' then

        if copies[orig] then
            copy = copies[orig]
        else
            copy = {}
            copies[orig] = copy
            for origKey, origValue in pairs(orig) do

                local keyCopy = BurdJournals.Server.deepCopy(origKey, copies)
                local valueCopy = BurdJournals.Server.deepCopy(origValue, copies)
                copy[keyCopy] = valueCopy
            end

        end
    else

        copy = orig
    end
    return copy
end

-- Safe wrapper for shouldDissolve that re-fetches the journal by ID to avoid zombie object errors
-- This prevents "Object tried to call nil" crashes when the journal becomes invalid during processing
function BurdJournals.Server.safeShouldDissolve(player, journalId)
    if not player or not journalId then return false end

    -- Re-fetch the journal by ID to get a fresh reference
    local freshJournal = BurdJournals.findItemById(player, journalId)
    if not freshJournal then
        -- Journal no longer exists - treat as dissolved
        return false
    end

    -- Validate the item is still valid (not a zombie object) before calling shouldDissolve
    -- isValidItem uses instanceof which doesn't trigger error logging
    if not BurdJournals.isValidItem(freshJournal) then
        BurdJournals.debugPrint("[BurdJournals] safeShouldDissolve: Item is invalid/zombie, skipping dissolution check")
        return false
    end

    -- Call shouldDissolve with the validated reference
    if BurdJournals.shouldDissolve then
        return BurdJournals.shouldDissolve(freshJournal, player)
    end
    return false
end

function BurdJournals.Server.copyJournalData(journal)
    if not journal then return nil end
    local modData = journal:getModData()
    if not modData or not modData.BurdJournals then return nil end

    return BurdJournals.Server.deepCopy(modData.BurdJournals)
end

function BurdJournals.Server.validateSkillPayload(skills, player)
    if skills == nil then return nil end
    if type(skills) ~= "table" then
        print("[BurdJournals] WARNING: Invalid skills payload (not a table) from " .. tostring(player and player:getUsername() or "unknown"))
        return nil
    end

    local validSkills = {}
    local allowedSkills = BurdJournals.getAllowedSkills and BurdJournals.getAllowedSkills() or {}
    local allowedSet = {}
    for _, name in ipairs(allowedSkills) do allowedSet[name] = true end

    -- Get baseline using the correct accessor
    local useBaseline = BurdJournals.shouldEnforceBaseline and BurdJournals.shouldEnforceBaseline(player) or false

    for skillName, skillData in pairs(skills) do

        if type(skillName) ~= "string" then
            print("[BurdJournals] WARNING: Invalid skill name type: " .. type(skillName))

        elseif not allowedSet[skillName] then
            print("[BurdJournals] WARNING: Unknown skill name: " .. skillName)

        elseif type(skillData) ~= "table" then
            print("[BurdJournals] WARNING: Invalid skill data type for " .. skillName .. ": " .. type(skillData))
        else
            -- SERVER-SIDE VALIDATION: Get actual player XP, don't trust client values
            local perk = BurdJournals.getPerkByName(skillName)
            if perk then
                local actualXP = player:getXp():getXP(perk)
                local actualLevel = player:getPerkLevel(perk)

                -- Apply baseline if enabled (Only Record Earned Progress)
                local earnedXP = actualXP
                local baselineXP = 0
                if useBaseline then
                    baselineXP = BurdJournals.getSkillBaseline(player, skillName) or 0
                    earnedXP = math.max(0, actualXP - baselineXP)
                    BurdJournals.debugPrint("[BurdJournals] validateSkillPayload: " .. skillName .. " actualXP=" .. tostring(actualXP) .. ", baselineXP=" .. tostring(baselineXP) .. ", earnedXP=" .. tostring(earnedXP))
                else
                    BurdJournals.debugPrint("[BurdJournals] validateSkillPayload: " .. skillName .. " actualXP=" .. tostring(actualXP) .. " (baseline disabled)")
                end

                -- Only record if there's actual earned XP
                if earnedXP > 0 then
                    validSkills[skillName] = { xp = earnedXP, level = actualLevel }
                    BurdJournals.debugPrint("[BurdJournals] validateSkillPayload: " .. skillName .. " ACCEPTED")
                else
                    BurdJournals.debugPrint("[BurdJournals] validateSkillPayload: " .. skillName .. " REJECTED (no earned XP)")
                end
            else
                print("[BurdJournals] WARNING: Could not find perk for skill: " .. skillName)
            end
        end
    end

    return validSkills
end

function BurdJournals.Server.validateTraitPayload(traits, player)
    if traits == nil then return nil end
    if type(traits) ~= "table" then
        print("[BurdJournals] WARNING: Invalid traits payload (not a table) from " .. tostring(player and player:getUsername() or "unknown"))
        return nil
    end

    local validTraits = {}

    -- Check if baseline restriction is enabled
    local useBaseline = BurdJournals.shouldEnforceBaseline and BurdJournals.shouldEnforceBaseline(player) or false

    for traitId, _ in pairs(traits) do

        if type(traitId) ~= "string" then
            print("[BurdJournals] WARNING: Invalid trait ID type: " .. type(traitId))

        elseif string.len(traitId) > 100 then
            print("[BurdJournals] WARNING: Trait ID too long: " .. string.sub(traitId, 1, 50) .. "...")
        else
            -- SERVER-SIDE VALIDATION: Verify player actually has this trait
            if BurdJournals.playerHasTrait(player, traitId) then
                -- Check if trait was in baseline (shouldn't record starting traits if enabled)
                local isBaselineTrait = useBaseline and BurdJournals.isStartingTrait(player, traitId)
                if not isBaselineTrait then
                    validTraits[traitId] = true
                end
            else
                BurdJournals.debugPrint("[BurdJournals] Rejected trait " .. traitId .. " - player doesn't have it")
            end
        end
    end

    return validTraits
end

function BurdJournals.Server.validateStatsPayload(stats, player)
    if stats == nil then return nil end
    if type(stats) ~= "table" then
        print("[BurdJournals] WARNING: Invalid stats payload (not a table) from " .. tostring(player and player:getUsername() or "unknown"))
        return nil
    end

    local validStats = {}

    for statId, statData in pairs(stats) do

        if type(statId) ~= "string" then
            print("[BurdJournals] WARNING: Invalid stat ID type: " .. type(statId))

        elseif string.len(statId) > 100 then
            print("[BurdJournals] WARNING: Stat ID too long: " .. string.sub(statId, 1, 50) .. "...")

        elseif type(statData) ~= "table" then
            print("[BurdJournals] WARNING: Invalid stat data type for " .. statId .. ": " .. type(statData))
        else

            local value = statData.value
            if type(value) ~= "number" and type(value) ~= "string" then
                value = tostring(value)
            end
            validStats[statId] = { value = value }
        end
    end

    return validStats
end

function BurdJournals.Server.validateRecipePayload(recipes, player)
    if recipes == nil then return nil end
    if type(recipes) ~= "table" then
        print("[BurdJournals] WARNING: Invalid recipes payload (not a table) from " .. tostring(player and player:getUsername() or "unknown"))
        return nil
    end

    local validRecipes = {}

    -- Check if baseline restriction is enabled
    local useBaseline = BurdJournals.shouldEnforceBaseline and BurdJournals.shouldEnforceBaseline(player) or false

    for recipeName, _ in pairs(recipes) do

        if type(recipeName) ~= "string" then
            print("[BurdJournals] WARNING: Invalid recipe name type: " .. type(recipeName))

        elseif string.len(recipeName) > 200 then
            print("[BurdJournals] WARNING: Recipe name too long: " .. string.sub(recipeName, 1, 50) .. "...")
        else
            -- SERVER-SIDE VALIDATION: Verify player actually knows this recipe
            if BurdJournals.playerKnowsRecipe(player, recipeName) then
                -- Check if recipe was in baseline (shouldn't record starting recipes if enabled)
                local isBaselineRecipe = useBaseline and BurdJournals.isStartingRecipe(player, recipeName)
                if not isBaselineRecipe then
                    validRecipes[recipeName] = true
                end
            else
                BurdJournals.debugPrint("[BurdJournals] Rejected recipe " .. recipeName .. " - player doesn't know it")
            end
        end
    end

    return validRecipes
end

function BurdJournals.Server.sendToClient(player, command, args)

    sendServerCommand(player, "BurdJournals", command, args)

    local localPlayer = getPlayer and getPlayer()
    local isTrueSinglePlayer = localPlayer ~= nil and not isClient()

    if isTrueSinglePlayer then

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

function BurdJournals.Server.init()
end

function BurdJournals.Server.onClientCommand(module, command, player, args)
    -- Only process BurdJournals commands (return early for other mods)
    if module ~= "BurdJournals" then return end

    BurdJournals.debugPrint("[BurdJournals] Server received command: " .. tostring(command) .. " from player: " .. tostring(player and player.getUsername and player:getUsername() or "unknown"))

    if not player then
        print("[BurdJournals] ERROR: No player in command")
        return
    end

    -- Get player ID safely - getOnlineID may not exist on older builds
    local playerId
    if player.getOnlineID then
        playerId = tostring(player:getOnlineID())
    elseif player.getUsername then
        playerId = tostring(player:getUsername())
    else
        playerId = "unknown"
    end

    -- Rate limiting - only enforce when timestamp function exists
    -- IMPORTANT: Don't rate-limit timed-action-based commands (recordProgress, claim*, absorb*)
    -- These commands can be sent in rapid batches from LearnFromJournalAction and RecordToJournalAction
    local rateLimitExempt = {
        recordProgress = true,
        claimSkill = true,
        claimTrait = true,
        claimRecipe = true,
        absorbSkill = true,
        absorbTrait = true,
        absorbRecipe = true,
    }
    if getTimestampMs and not rateLimitExempt[command] then
        local now = getTimestampMs()
        local lastCmd = BurdJournals.Server._rateLimitCache[playerId] or 0
        if now - lastCmd < 100 then
            BurdJournals.debugPrint("[BurdJournals] Server: RATE LIMITED command " .. tostring(command) .. " (only " .. tostring(now - lastCmd) .. "ms since last)")
            return
        end
        BurdJournals.Server._rateLimitCache[playerId] = now

        -- Periodic cleanup (1% chance per command) - use ZombRand for PZ compatibility
        local rand = ZombRand and ZombRand(100) or 1
        if rand == 0 then
            BurdJournals.Server.cleanupRateLimitCache()
        end
    end

    local isEnabled = BurdJournals.isEnabled()
    print("[BurdJournals] onClientCommand: isEnabled=" .. tostring(isEnabled))
    if not isEnabled then
        print("[BurdJournals] onClientCommand ERROR: Journals disabled!")
        BurdJournals.Server.sendToClient(player, "error", {message = "Journals are disabled on this server."})
        return
    end

    print("[BurdJournals] onClientCommand: Routing command '" .. tostring(command) .. "'")
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
        print("[BurdJournals] ROUTING recordProgress to handler NOW")
        BurdJournals.Server.handleRecordProgress(player, args)
    elseif command == "syncJournalData" then
        BurdJournals.Server.handleSyncJournalData(player, args)
    elseif command == "claimRecipe" then
        BurdJournals.Server.handleClaimRecipe(player, args)
    elseif command == "absorbRecipe" then
        BurdJournals.Server.handleAbsorbRecipe(player, args)
    elseif command == "eraseEntry" then
        BurdJournals.Server.handleEraseEntry(player, args)
    elseif command == "registerBaseline" then
        BurdJournals.Server.handleRegisterBaseline(player, args)
    elseif command == "requestBaseline" then
        BurdJournals.Server.handleRequestBaseline(player, args)
    elseif command == "deleteBaseline" then
        BurdJournals.Server.handleDeleteBaseline(player, args)
    elseif command == "dissolveJournal" then
        BurdJournals.Server.handleDissolveJournal(player, args)
    elseif command == "sanitizeJournal" then
        BurdJournals.Server.handleSanitizeJournal(player, args)
    elseif command == "clearAllBaselines" then
        BurdJournals.Server.handleClearAllBaselines(player, args)
    end
end

-- Server-side sanitization handler (called when client opens journal in MP)
function BurdJournals.Server.handleSanitizeJournal(player, args)
    if not args or not args.journalId then
        return
    end

    local journal = BurdJournals.findItemById(player, args.journalId)
    if not journal then
        return
    end

    -- Sanitize the journal data (server-side, authoritative)
    if BurdJournals.sanitizeJournalData then
        local sanitizeResult = BurdJournals.sanitizeJournalData(journal, player)
        if sanitizeResult and sanitizeResult.cleaned then
            BurdJournals.debugPrint("[BurdJournals] Server: Sanitized journal " .. tostring(args.journalId))
            -- Transmit sanitized data to all clients
            if journal.transmitModData then
                journal:transmitModData()
            end

            -- Re-fetch journal by ID before calling shouldDissolve to avoid zombie object errors
            local freshJournal = BurdJournals.findItemById(player, args.journalId)
            if freshJournal and BurdJournals.isValidItem(freshJournal) and BurdJournals.shouldDissolve and BurdJournals.shouldDissolve(freshJournal, player) then
                BurdJournals.Server.dissolveJournal(player, freshJournal)
                BurdJournals.Server.sendToClient(player, "journalDissolved", {
                    journalId = args.journalId,
                    reason = "sanitized"
                })
                return
            end
        end
    end

    -- Also run migration if needed
    if BurdJournals.migrateJournalIfNeeded then
        BurdJournals.migrateJournalIfNeeded(journal, player)
        if journal.transmitModData then
            journal:transmitModData()
        end
    end
end

-- Dissolution handler - manual dissolve from UI button (no shouldDissolve check - user confirmed action)
function BurdJournals.Server.handleDissolveJournal(player, args)
    if not args or not args.journalId then
        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid request."})
        return
    end

    local journal = BurdJournals.findItemById(player, args.journalId)
    if not journal then
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal not found."})
        return
    end

    -- Validate item is not a zombie object
    if not BurdJournals.isValidItem(journal) then
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal is no longer valid."})
        return
    end

    -- Only require that it's a worn/bloody journal (or has worn/bloody origin)
    -- The manual Dissolve button should work regardless of claim status
    local modData = journal:getModData()
    local data = modData and modData.BurdJournals
    local fullType = journal:getFullType()
    local isWornFromType = fullType and string.find(fullType, "_Worn") ~= nil
    local isBloodyFromType = fullType and string.find(fullType, "_Bloody") ~= nil
    local isWorn = (data and data.isWorn) or isWornFromType
    local isBloody = (data and data.isBloody) or isBloodyFromType
    local hasWornBloodyOrigin = data and (data.wasFromWorn or data.wasFromBloody)

    if not isWorn and not isBloody and not hasWornBloodyOrigin then
        BurdJournals.Server.sendToClient(player, "error", {message = "Only worn or bloody journals can be manually dissolved."})
        return
    end

    print("[BurdJournals] Server: Manual dissolve requested for journal " .. tostring(args.journalId))

    -- Remove the journal using the complete removal path
    BurdJournals.Server.dissolveJournal(player, journal)

    -- Send dissolution notification
    local message = BurdJournals.getRandomDissolutionMessage and BurdJournals.getRandomDissolutionMessage() or "The journal crumbles to dust..."
    BurdJournals.Server.sendToClient(player, "journalDissolved", {
        message = message,
        journalId = args.journalId
    })
end

local function removeJournalCompletely(player, journal)

    if not journal then
        return false
    end

    local journalType = journal:getFullType()
    local journalID = journal:getID()

    BurdJournals.safePcall(function()
        if player:getPrimaryHandItem() == journal then
            player:setPrimaryHandItem(nil)

        end
        if player:getSecondaryHandItem() == journal then
            player:setSecondaryHandItem(nil)

        end
    end)

    local container = journal:getContainer()
    if container then
        container:Remove(journal)
        container:setDrawDirty(true)

    end

    local mainInv = player:getInventory()
    if mainInv then
        if mainInv:contains(journal) then
            mainInv:Remove(journal)
            mainInv:setDrawDirty(true)

        end

        local items = mainInv:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            -- Only check containers (bags, backpacks, etc.) - regular items don't have getInventory
            if item and item.getInventory then
                BurdJournals.safePcall(function()
                    local subInv = item:getInventory()
                    if subInv and subInv:contains(journal) then
                        subInv:Remove(journal)
                        subInv:setDrawDirty(true)
                    end
                end)
            end
        end
    end

    local stillExists = mainInv and mainInv:contains(journal)

    return not stillExists
end

-- Public dissolve function that uses complete removal
function BurdJournals.Server.dissolveJournal(player, journal)
    if not player or not journal then return false end
    return removeJournalCompletely(player, journal)
end

function BurdJournals.Server.handleInitializeJournal(player, args)
    if not args or not args.itemType then

        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid request."})
        return
    end

    local itemType = args.itemType
    local clientUUID = args.clientUUID

    local inventory = player:getInventory()
    if not inventory then
        BurdJournals.Server.sendToClient(player, "error", {message = "Inventory not found."})
        return
    end

    local journal = nil
    local allItems = inventory:getItems()

    if clientUUID then
        for i = 0, allItems:size() - 1 do
            local item = allItems:get(i)
            if item then
                local modData = item:getModData()
                if modData and modData.BurdJournals and modData.BurdJournals.uuid == clientUUID then
                    journal = item

                    break
                end
            end
        end
    end

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

        BurdJournals.Server.sendToClient(player, "error", {message = "Journal not found for initialization."})
        return
    end

    local modData = journal:getModData()
    if not modData.BurdJournals then
        modData.BurdJournals = {}
    end

    local uuid = clientUUID or BurdJournals.generateUUID()
    modData.BurdJournals.uuid = uuid

    local journalType = journal:getFullType()
    local isWorn = string.find(journalType, "_Worn") ~= nil
    local isBloody = string.find(journalType, "_Bloody") ~= nil
    local isFilled = string.find(journalType, "Filled") ~= nil

    if isFilled and not modData.BurdJournals.skills then

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

                    local numTraits = ZombRand(1, 5)
                    local availableTraits = {}
                    for _, t in ipairs(grantableTraits) do
                        table.insert(availableTraits, t)
                    end

                    for i = 1, numTraits do
                        if #availableTraits == 0 then break end
                        local idx = ZombRand(#availableTraits) + 1
                        local randomTrait = availableTraits[idx]
                        if randomTrait then
                            traits[randomTrait] = true
                            table.remove(availableTraits, idx)
                        end
                    end
                end
                modData.BurdJournals.traits = traits
                modData.BurdJournals.claimedTraits = {}

            end

            -- Generate recipes for bloody journals
            local recipeChance = BurdJournals.getSandboxOption("BloodyJournalRecipeChance") or 35
            local recipeRoll = ZombRand(100)
            BurdJournals.debugPrint("[BurdJournals] Server init Bloody: recipeChance=" .. recipeChance .. ", roll=" .. recipeRoll)
            if recipeRoll < recipeChance then
                local maxRecipes = BurdJournals.getSandboxOption("BloodyJournalMaxRecipes") or 2
                local numRecipes = ZombRand(1, maxRecipes + 1)
                BurdJournals.debugPrint("[BurdJournals] Server init Bloody: Generating " .. numRecipes .. " recipes")
                local recipes = BurdJournals.generateRandomRecipes(numRecipes)
                local recipeCount = 0
                if recipes then
                    for _ in pairs(recipes) do recipeCount = recipeCount + 1 end
                end
                BurdJournals.debugPrint("[BurdJournals] Server init Bloody: Generated " .. recipeCount .. " recipes")
                if recipeCount > 0 then
                    modData.BurdJournals.recipes = recipes
                    modData.BurdJournals.claimedRecipes = {}
                end
            end
        elseif isWorn then
            -- Generate recipes for worn journals too
            local recipeChance = BurdJournals.getSandboxOption("WornJournalRecipeChance") or 20
            local recipeRoll = ZombRand(100)
            BurdJournals.debugPrint("[BurdJournals] Server init Worn: recipeChance=" .. recipeChance .. ", roll=" .. recipeRoll)
            if recipeRoll < recipeChance then
                local maxRecipes = BurdJournals.getSandboxOption("WornJournalMaxRecipes") or 1
                local numRecipes = ZombRand(1, maxRecipes + 1)
                BurdJournals.debugPrint("[BurdJournals] Server init Worn: Generating " .. numRecipes .. " recipes")
                local recipes = BurdJournals.generateRandomRecipes(numRecipes)
                local recipeCount = 0
                if recipes then
                    for _ in pairs(recipes) do recipeCount = recipeCount + 1 end
                end
                BurdJournals.debugPrint("[BurdJournals] Server init Worn: Generated " .. recipeCount .. " recipes")
                if recipeCount > 0 then
                    modData.BurdJournals.recipes = recipes
                    modData.BurdJournals.claimedRecipes = {}
                end
            end
        end

        modData.BurdJournals.author = BurdJournals.generateRandomName and BurdJournals.generateRandomName() or "Unknown Survivor"
        modData.BurdJournals.isWritten = true
    end

    if journal.transmitModData then
        journal:transmitModData()

    end

    if BurdJournals.updateJournalName then
        BurdJournals.updateJournalName(journal)
    end

    BurdJournals.Server.sendToClient(player, "journalInitialized", {
        uuid = uuid,
        itemType = itemType,
        skillCount = modData.BurdJournals.skills and BurdJournals.countTable(modData.BurdJournals.skills) or 0,
        requestId = args.requestId
    })
end

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

    if BurdJournals.getSandboxOption("RequirePenToWrite") then
        local pen = BurdJournals.findWritingTool(player)
        if not pen then
            BurdJournals.Server.sendToClient(player, "error", {message = "You need a pen or pencil to write."})
            return
        end
        local usesPerLog = BurdJournals.getSandboxOption("PenUsesPerLog") or 1
        BurdJournals.consumeItemUses(pen, usesPerLog, player)
    end

    local journalContent = BurdJournals.collectAllPlayerData(player)

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

    local inventory = player:getInventory()
    inventory:Remove(journal)
    sendRemoveItemFromContainer(inventory, journal)

    local filledJournal = inventory:AddItem("BurdJournals.FilledSurvivalJournal")
    if filledJournal then
        local modData = filledJournal:getModData()
        -- Track whether baseline was enforced when recording
        -- This affects how XP is applied on claim (add mode vs set mode)
        local baselineEnforced = BurdJournals.shouldEnforceBaseline and BurdJournals.shouldEnforceBaseline(player) or false

        modData.BurdJournals = {
            author = player:getDescriptor():getForename() .. " " .. player:getDescriptor():getSurname(),
            ownerUsername = player:getUsername(),
            ownerSteamId = BurdJournals.getPlayerSteamId(player),
            ownerCharacterName = player:getDescriptor():getForename() .. " " .. player:getDescriptor():getSurname(),
            timestamp = getGameTime():getWorldAgeHours(),
            readCount = 0,

            isWorn = false,
            isBloody = false,
            wasFromBloody = false,
            isPlayerCreated = true,

            -- XP mode tracking: if baseline was enforced, XP values are deltas (earned XP)
            -- If baseline was NOT enforced, XP values are absolute (total XP)
            recordedWithBaseline = baselineEnforced,

            contributors = {},

            skills = journalContent.skills,
            traits = journalContent.traits,
        }
        BurdJournals.updateJournalName(filledJournal)
        BurdJournals.updateJournalIcon(filledJournal)

        if filledJournal.transmitModData then
            filledJournal:transmitModData()
            BurdJournals.debugPrint("[BurdJournals] Server: transmitModData called for filled journal in handleLogSkills")
        end

        sendAddItemToContainer(inventory, filledJournal)
        BurdJournals.debugPrint("[BurdJournals] Server: sendAddItemToContainer called for filled journal in handleLogSkills")
    end

    BurdJournals.Server.sendToClient(player, "logSuccess", {})
end

function BurdJournals.Server.handleRecordProgress(player, args)
    print("[BurdJournals] SERVER handleRecordProgress ENTRY")
    BurdJournals.debugPrint("[BurdJournals] Server: handleRecordProgress CALLED, player=" .. tostring(player and player:getUsername() or "nil"))

    if not args or not args.journalId then
        print("[BurdJournals] SERVER handleRecordProgress ERROR: no args or journalId")
        BurdJournals.debugPrint("[BurdJournals] Server: handleRecordProgress - Invalid request (no args or journalId)")
        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid request."})
        return
    end

    print("[BurdJournals] SERVER handleRecordProgress: journalId=" .. tostring(args.journalId))
    BurdJournals.debugPrint("[BurdJournals] Server: handleRecordProgress - journalId=" .. tostring(args.journalId))

    local journal = BurdJournals.findItemById(player, args.journalId)
    if not journal then
        print("[BurdJournals] SERVER handleRecordProgress ERROR: Journal not found for ID " .. tostring(args.journalId))
        BurdJournals.debugPrint("[BurdJournals] Server: handleRecordProgress - Journal not found for ID " .. tostring(args.journalId))
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal not found."})
        return
    end

    print("[BurdJournals] SERVER handleRecordProgress: Journal found OK")
    BurdJournals.debugPrint("[BurdJournals] Server: handleRecordProgress - Journal found: " .. tostring(journal:getFullType()))

    if BurdJournals.getSandboxOption("RequirePenToWrite") then
        print("[BurdJournals] SERVER handleRecordProgress: Pen required, checking...")
        local pen = BurdJournals.findWritingTool(player)
        if not pen then
            print("[BurdJournals] SERVER handleRecordProgress ERROR: No pen found!")
            BurdJournals.Server.sendToClient(player, "error", {message = "You need a pen or pencil to write."})
            return
        end
        print("[BurdJournals] SERVER handleRecordProgress: Pen found OK")
        local usesPerLog = BurdJournals.getSandboxOption("PenUsesPerLog") or 1
        BurdJournals.consumeItemUses(pen, usesPerLog, player)
    end
    print("[BurdJournals] SERVER handleRecordProgress: Past pen check, processing data...")

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

    -- Debug: Log baseline state
    local useBaseline = BurdJournals.shouldEnforceBaseline and BurdJournals.shouldEnforceBaseline(player) or false
    local hasBaselineCaptured = BurdJournals.hasBaselineCaptured and BurdJournals.hasBaselineCaptured(player) or false
    local isBaselineBypassed = BurdJournals.isBaselineBypassed and BurdJournals.isBaselineBypassed(player) or false
    BurdJournals.debugPrint("[BurdJournals] handleRecordProgress: useBaseline=" .. tostring(useBaseline) .. ", hasBaselineCaptured=" .. tostring(hasBaselineCaptured) .. ", isBaselineBypassed=" .. tostring(isBaselineBypassed))

    -- Count incoming items (before validation)
    local debugInSkills = args.skills and BurdJournals.countTable(args.skills) or 0
    local debugInTraits = args.traits and BurdJournals.countTable(args.traits) or 0
    local debugInRecipes = args.recipes and BurdJournals.countTable(args.recipes) or 0
    BurdJournals.debugPrint("[BurdJournals] handleRecordProgress: Incoming skills=" .. debugInSkills .. ", traits=" .. debugInTraits .. ", recipes=" .. debugInRecipes)

    local validatedSkills = BurdJournals.Server.validateSkillPayload(args.skills, player)
    local validatedTraits = BurdJournals.Server.validateTraitPayload(args.traits, player)
    local validatedStats = BurdJournals.Server.validateStatsPayload(args.stats, player)
    local validatedRecipes = BurdJournals.Server.validateRecipePayload(args.recipes, player)

    -- Debug: Log validated counts
    local validSkillCount = validatedSkills and BurdJournals.countTable(validatedSkills) or 0
    local validTraitCount = validatedTraits and BurdJournals.countTable(validatedTraits) or 0
    local validRecipeCount = validatedRecipes and BurdJournals.countTable(validatedRecipes) or 0
    BurdJournals.debugPrint("[BurdJournals] handleRecordProgress: Validated skills=" .. validSkillCount .. ", traits=" .. validTraitCount .. ", recipes=" .. validRecipeCount)

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
    if validatedSkills then for _ in pairs(validatedSkills) do incomingSkillCount = incomingSkillCount + 1 end end
    if validatedTraits then for _ in pairs(validatedTraits) do incomingTraitCount = incomingTraitCount + 1 end end
    if validatedRecipes then for _ in pairs(validatedRecipes) do incomingRecipeCount = incomingRecipeCount + 1 end end

    local maxSkills = limits.MAX_SKILLS or 50
    local maxTraits = limits.MAX_TRAITS or 100
    local maxRecipes = limits.MAX_RECIPES or 200

    if existingSkillCount + incomingSkillCount > maxSkills then
        print("[BurdJournals] SERVER handleRecordProgress ERROR: Skill limit reached")
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal skill limit reached (" .. maxSkills .. " max)."})
        return
    end
    if existingTraitCount + incomingTraitCount > maxTraits then
        print("[BurdJournals] SERVER handleRecordProgress ERROR: Trait limit reached")
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal trait limit reached (" .. maxTraits .. " max)."})
        return
    end
    if existingRecipeCount + incomingRecipeCount > maxRecipes then
        print("[BurdJournals] SERVER handleRecordProgress ERROR: Recipe limit reached")
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal recipe limit reached (" .. maxRecipes .. " max)."})
        return
    end
    print("[BurdJournals] SERVER handleRecordProgress: Limits OK, recording data...")

    if validatedSkills then
        for skillName, skillData in pairs(validatedSkills) do
            local existingXP = modData.BurdJournals.skills[skillName] and modData.BurdJournals.skills[skillName].xp or 0
            if skillData.xp > existingXP then
                modData.BurdJournals.skills[skillName] = {
                    xp = skillData.xp,
                    level = skillData.level
                }
                skillsRecorded = skillsRecorded + 1
                table.insert(skillNames, skillName)
            end
        end
    end

    if validatedTraits then
        for traitId, _ in pairs(validatedTraits) do
            if not modData.BurdJournals.traits[traitId] then
                modData.BurdJournals.traits[traitId] = true
                traitsRecorded = traitsRecorded + 1
                table.insert(traitNames, traitId)
            end
        end
    end

    if validatedStats then
        for statId, statData in pairs(validatedStats) do

            modData.BurdJournals.stats[statId] = {
                value = statData.value
            }
            statsRecorded = statsRecorded + 1
        end
    end

    if validatedRecipes then
        for recipeName, _ in pairs(validatedRecipes) do
            if not modData.BurdJournals.recipes[recipeName] then
                modData.BurdJournals.recipes[recipeName] = true
                recipesRecorded = recipesRecorded + 1
                table.insert(recipeNames, recipeName)
            end
        end
    end

    local playerSteamId = BurdJournals.getPlayerSteamId(player)
    local playerCharName = player:getDescriptor():getForename() .. " " .. player:getDescriptor():getSurname()

    if not modData.BurdJournals.ownerSteamId then

        modData.BurdJournals.author = playerCharName
        modData.BurdJournals.ownerUsername = player:getUsername()
        modData.BurdJournals.ownerSteamId = playerSteamId
        modData.BurdJournals.ownerCharacterName = playerCharName
        modData.BurdJournals.contributors = {}
        BurdJournals.debugPrint("[BurdJournals] Journal owner set to: " .. playerCharName .. " (" .. playerSteamId .. ")")
    else

        if modData.BurdJournals.ownerSteamId ~= playerSteamId then

            if not modData.BurdJournals.contributors then
                modData.BurdJournals.contributors = {}
            end

            modData.BurdJournals.contributors[playerSteamId] = {
                characterName = playerCharName,
                username = player:getUsername(),
                addedAt = getGameTime():getWorldAgeHours()
            }
            BurdJournals.debugPrint("[BurdJournals] Added contributor: " .. playerCharName .. " (" .. playerSteamId .. ")")
        else

            if modData.BurdJournals.ownerCharacterName ~= playerCharName then
                local oldName = modData.BurdJournals.ownerCharacterName or "(none)"
                BurdJournals.debugPrint("[BurdJournals] Owner character name updated: " .. oldName .. " -> " .. playerCharName)
                modData.BurdJournals.ownerCharacterName = playerCharName
                modData.BurdJournals.author = playerCharName
            end
        end
    end

    modData.BurdJournals.lastModified = getGameTime():getWorldAgeHours()
    modData.BurdJournals.isPlayerCreated = true
    modData.BurdJournals.isWritten = true

    local journalType = journal:getFullType()
    local isBlank = string.find(journalType, "Blank") ~= nil
    local totalItems = BurdJournals.countTable(modData.BurdJournals.skills) + BurdJournals.countTable(modData.BurdJournals.traits) + BurdJournals.countTable(modData.BurdJournals.stats) + BurdJournals.countTable(modData.BurdJournals.recipes)

    BurdJournals.debugPrint("[BurdJournals] handleRecordProgress: journalType=" .. tostring(journalType) .. ", isBlank=" .. tostring(isBlank) .. ", totalItems=" .. tostring(totalItems))

    local newJournalId = nil

    if isBlank and totalItems > 0 then
        BurdJournals.debugPrint("[BurdJournals] Converting blank journal to filled...")

        local inventory = journal:getContainer()
        if inventory then
            BurdJournals.debugPrint("[BurdJournals] Got inventory container: " .. tostring(inventory))

            local savedData = BurdJournals.Server.deepCopy(modData.BurdJournals)
            if not savedData then
                print("[BurdJournals] ERROR: Failed to deep copy journal data!")
                savedData = {}
            end

            -- Reset worn/bloody flags - preserve origin for "Restored" status logic
            -- The sandbox option controls display and dissolution behavior at runtime
            if savedData.isWorn then
                savedData.wasFromWorn = true
                savedData.isWorn = false
                BurdJournals.debugPrint("[BurdJournals] Reset isWorn flag, set wasFromWorn=true")
            end
            if savedData.isBloody then
                savedData.wasFromBloody = true
                savedData.isBloody = false
                BurdJournals.debugPrint("[BurdJournals] Reset isBloody flag, set wasFromBloody=true")
            end

            inventory:Remove(journal)
            sendRemoveItemFromContainer(inventory, journal)
            BurdJournals.debugPrint("[BurdJournals] Removed blank journal and notified clients")

            local filledJournal = inventory:AddItem("BurdJournals.FilledSurvivalJournal")
            if filledJournal then
                BurdJournals.debugPrint("[BurdJournals] Created filled journal: " .. tostring(filledJournal:getID()))

                local newModData = filledJournal:getModData()
                newModData.BurdJournals = savedData

                BurdJournals.updateJournalName(filledJournal)
                BurdJournals.updateJournalIcon(filledJournal)

                if filledJournal.transmitModData then
                    filledJournal:transmitModData()
                    BurdJournals.debugPrint("[BurdJournals] transmitModData called on filled journal")
                end

                sendAddItemToContainer(inventory, filledJournal)
                BurdJournals.debugPrint("[BurdJournals] sendAddItemToContainer called for filled journal")

                newJournalId = filledJournal:getID()
                BurdJournals.debugPrint("[BurdJournals] Conversion complete, newJournalId=" .. tostring(newJournalId))
            else
                print("[BurdJournals] ERROR: Failed to create filled journal!")
            end
        else
            print("[BurdJournals] ERROR: No inventory container found!")
        end
    else
        BurdJournals.debugPrint("[BurdJournals] Not converting (isBlank=" .. tostring(isBlank) .. ", totalItems=" .. tostring(totalItems) .. ")")

        BurdJournals.updateJournalName(journal)
        BurdJournals.updateJournalIcon(journal)

        if journal.transmitModData then
            journal:transmitModData()
            BurdJournals.debugPrint("[BurdJournals] transmitModData called on existing journal")
        end
    end

    local finalJournal = newJournalId and BurdJournals.findItemById(player, newJournalId) or journal
    local journalData = nil
    local finalJournalId = newJournalId or (journal and journal:getID())

    local includeJournalData = true

    if includeJournalData and finalJournal then
        local modData = finalJournal:getModData()
        if modData and modData.BurdJournals then

            journalData = BurdJournals.Server.deepCopy(modData.BurdJournals)
        end
    end

    BurdJournals.debugPrint("[BurdJournals] Sending recordSuccess response, newJournalId=" .. tostring(newJournalId) .. ", journalId=" .. tostring(finalJournalId) .. ", includeJournalData=" .. tostring(includeJournalData))
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
        journalData = journalData
    })
end

function BurdJournals.Server.handleSyncJournalData(player, args)
    if not args or not args.journalId then
        BurdJournals.debugPrint("[BurdJournals] handleSyncJournalData: Invalid request (no journalId)")
        return
    end

    local journal = BurdJournals.findItemById(player, args.journalId)
    if not journal then
        BurdJournals.debugPrint("[BurdJournals] handleSyncJournalData: Journal not found: " .. tostring(args.journalId))
        return
    end

    if journal.transmitModData then
        journal:transmitModData()
        BurdJournals.debugPrint("[BurdJournals] handleSyncJournalData: transmitModData called for journal " .. tostring(args.journalId))
    end
end

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

    if not BurdJournals.canSetXP(journal) then
        BurdJournals.Server.sendToClient(player, "error", {message = "Cannot learn from this journal."})
        return
    end

    local modData = journal:getModData()
    if not modData.BurdJournals or not modData.BurdJournals.skills then
        BurdJournals.Server.sendToClient(player, "error", {message = "This journal has no skill data."})
        return
    end

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

    local selectedSkills = args.skills
    local journalSkills = modData.BurdJournals.skills

    local skillsToSet = {}
    local skillsApplied = 0
    for skillName, storedData in pairs(journalSkills) do

        if not selectedSkills or not next(selectedSkills) or selectedSkills[skillName] then
            local targetXP = math.floor(storedData.xp * multiplier)
            skillsToSet[skillName] = {
                xp = targetXP,
                level = storedData.level,
                mode = "set"
            }

            -- Apply XP directly on server using vanilla addXp function (42.13.2+ compatible)
            -- For "set" mode, we need to calculate the difference
            local perk = BurdJournals.getPerkByName(skillName)
            if perk and addXp then
                local currentXP = player:getXp():getXP(perk)
                if targetXP > currentXP then
                    local xpToAdd = targetXP - currentXP
                    print("[BurdJournals] Server: LearnSkills - Applying " .. tostring(xpToAdd) .. " XP to " .. skillName .. " via addXp()")
                    addXp(player, perk, xpToAdd)
                    skillsApplied = skillsApplied + 1
                end
            end
        end
    end

    -- Fallback: send to client if addXp not available (SP mode)
    if not addXp then
        print("[BurdJournals] Server: LearnSkills fallback - sending applyXP to client")
        BurdJournals.Server.sendToClient(player, "applyXP", {skills = skillsToSet, mode = "set"})
    else
        -- Notify client of success (for UI update)
        BurdJournals.Server.sendToClient(player, "learnSuccess", {skillCount = skillsApplied})
    end
end

function BurdJournals.Server.handleClaimSkill(player, args)

    if not args or not args.skillName then

        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid request."})
        return
    end

    local journalId = args.journalId
    local skillName = args.skillName

    local journal = BurdJournals.findItemById(player, journalId)
    if not journal then
        print("[BurdJournals] Server ERROR: Journal not found by ID " .. tostring(journalId))
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal not found."})
        return
    end

    local canClaim, reason = BurdJournals.canPlayerClaimFromJournal(player, journal)
    if not canClaim then
        BurdJournals.Server.sendToClient(player, "error", {message = reason or "Permission denied."})
        return
    end

    local modData = journal:getModData()
    local journalData = modData.BurdJournals

    if not journalData or not journalData.skills then
        BurdJournals.Server.sendToClient(player, "error", {message = "This journal has no skill data."})
        return
    end

    if not journalData.skills[skillName] then
        print("[BurdJournals] Server ERROR: Skill '" .. skillName .. "' not found in journal")
        BurdJournals.Server.sendToClient(player, "error", {message = "Skill not found in journal."})
        return
    end

    local skillData = journalData.skills[skillName]
    local recordedXP = skillData.xp or 0
    local recordedLevel = skillData.level or 0

    local perk = BurdJournals.getPerkByName(skillName)
    if not perk then
        print("[BurdJournals] Server ERROR: Could not find perk for skill '" .. skillName .. "'")
        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid skill: " .. skillName})
        return
    end

    -- Determine XP application mode:
    -- - Journals recorded with baseline: ADD mode (XP values are deltas/earned XP)
    -- - Journals recorded without baseline: SET mode (XP values are absolute totals)
    -- Player journals use SET mode to restore exact XP state
    -- Found journals (Worn/Bloody) without baseline also use SET mode
    local useAddMode = journalData.recordedWithBaseline == true
    local isPlayerJournal = journalData.isPlayerCreated == true

    -- Debug logging
    print("[BurdJournals] Server ClaimSkill DEBUG:")
    print("  - skillName: " .. tostring(skillName))
    print("  - recordedXP: " .. tostring(recordedXP))
    print("  - recordedLevel: " .. tostring(recordedLevel))
    print("  - isPlayerCreated: " .. tostring(isPlayerJournal))
    print("  - recordedWithBaseline: " .. tostring(journalData.recordedWithBaseline))
    print("  - useAddMode: " .. tostring(useAddMode))

    if recordedXP > 0 then
        local xpToApply = recordedXP

        -- For "set" mode (absolute XP), cap at recorded value to prevent over-grant
        -- Player should end up with AT MOST the recorded XP, not more
        if not useAddMode then
            local currentXP = player:getXp():getXP(perk)
            local currentLevel = player:getPerkLevel(perk)
            print("  - currentXP: " .. tostring(currentXP))
            print("  - currentLevel: " .. tostring(currentLevel))
            if currentXP >= recordedXP then
                -- Player already has equal or more XP than recorded - nothing to grant
                BurdJournals.markSkillClaimedByCharacter(journalData, player, skillName)
                if journal.transmitModData then
                    journal:transmitModData()
                end
                BurdJournals.Server.sendToClient(player, "skillMaxed", {
                    skillName = skillName,
                    journalId = journalId,
                    message = "You already have this much XP in " .. skillName .. "."
                })
                -- Re-fetch journal by ID before calling shouldDissolve to avoid zombie object errors
                local freshJournal = BurdJournals.findItemById(player, journalId)
                if freshJournal and BurdJournals.isValidItem(freshJournal) and BurdJournals.shouldDissolve and BurdJournals.shouldDissolve(freshJournal, player) then
                    BurdJournals.Server.dissolveJournal(player, freshJournal)
                end
                return
            end
            -- Only grant the difference to reach recorded XP
            xpToApply = recordedXP - currentXP
            print("  - xpToApply (after SET calc): " .. tostring(xpToApply))
        end

        print("  - FINAL xpToApply: " .. tostring(xpToApply))

        -- Apply XP directly using player:getXp():AddXP() with useMultipliers=false
        -- This bypasses sandbox XP multiplier settings to give exact recorded XP
        -- Signature: AddXP(perk, amount, ?, useMultipliers, ?, ?)
        local success = pcall(function()
            player:getXp():AddXP(perk, xpToApply, false, false, false, false)
        end)
        if success then
            print("[BurdJournals] Server: Applied " .. tostring(xpToApply) .. " XP to " .. skillName .. " via AddXP (no multipliers)")
        else
            -- Fallback to addXp if AddXP fails
            if addXp then
                print("[BurdJournals] Server: Fallback to addXp() for " .. skillName)
                addXp(player, perk, xpToApply)
            else
                -- Last resort - send to client
                print("[BurdJournals] Server: Fallback - sending applyXP to client for " .. skillName)
                BurdJournals.Server.sendToClient(player, "applyXP", {
                    skills = {
                        [skillName] = {
                            xp = xpToApply,
                            mode = "add"
                        }
                    },
                    mode = "add"
                })
            end
        end

        BurdJournals.markSkillClaimedByCharacter(journalData, player, skillName)

        if journal.transmitModData then
            journal:transmitModData()
        end

        BurdJournals.Server.sendToClient(player, "claimSuccess", {
            skillName = skillName,
            xpAdded = xpToApply,  -- Send actual XP added for client-side instant feedback
            journalId = journalId,
            journalData = journalData,
        })
        -- Re-fetch journal by ID before calling shouldDissolve to avoid zombie object errors
        local freshJournal = BurdJournals.findItemById(player, journalId)
        print("[BurdJournals] Server: Post-claim skill check - freshJournal=" .. tostring(freshJournal ~= nil) .. ", journalId=" .. tostring(journalId))
        if freshJournal then
            local isValid = BurdJournals.isValidItem(freshJournal)
            local hasShouldDissolve = BurdJournals.shouldDissolve ~= nil
            local shouldDis = hasShouldDissolve and BurdJournals.shouldDissolve(freshJournal, player)
            print("[BurdJournals] Server: isValid=" .. tostring(isValid) .. ", hasShouldDissolve=" .. tostring(hasShouldDissolve) .. ", shouldDis=" .. tostring(shouldDis))
            if isValid and shouldDis then
                print("[BurdJournals] Server: DISSOLVING JOURNAL after skill claim!")
                BurdJournals.Server.dissolveJournal(player, freshJournal)
            end
        end
    else
        -- Zero XP recorded - mark as claimed but no XP to add
        BurdJournals.markSkillClaimedByCharacter(journalData, player, skillName)
        if journal.transmitModData then
            journal:transmitModData()
        end
        BurdJournals.Server.sendToClient(player, "skillMaxed", {
            skillName = skillName,
            journalId = journalId,
            journalData = journalData,
            message = "No XP to claim from this skill."
        })
        -- Re-fetch journal by ID before calling shouldDissolve to avoid zombie object errors
        local freshJournal = BurdJournals.findItemById(player, journalId)
        print("[BurdJournals] Server: Post-skillMaxed check - freshJournal=" .. tostring(freshJournal ~= nil) .. ", journalId=" .. tostring(journalId))
        if freshJournal then
            local isValid = BurdJournals.isValidItem(freshJournal)
            local hasShouldDissolve = BurdJournals.shouldDissolve ~= nil
            local shouldDis = hasShouldDissolve and BurdJournals.shouldDissolve(freshJournal, player)
            print("[BurdJournals] Server: isValid=" .. tostring(isValid) .. ", hasShouldDissolve=" .. tostring(hasShouldDissolve) .. ", shouldDis=" .. tostring(shouldDis))
            if isValid and shouldDis then
                print("[BurdJournals] Server: DISSOLVING JOURNAL after skillMaxed!")
                BurdJournals.Server.dissolveJournal(player, freshJournal)
            end
        end
    end
end

function BurdJournals.Server.handleClaimTrait(player, args)

    if not args or not args.traitId then
        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid request."})
        return
    end

    local journalId = args.journalId
    local traitId = args.traitId

    local journal = BurdJournals.findItemById(player, journalId)
    if not journal then
        print("[BurdJournals] Server ERROR: Journal not found by ID " .. tostring(journalId))
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal not found."})
        return
    end

    local canClaim, reason = BurdJournals.canPlayerClaimFromJournal(player, journal)
    if not canClaim then
        BurdJournals.Server.sendToClient(player, "error", {message = reason or "Permission denied."})
        return
    end

    local modData = journal:getModData()
    local journalData = modData.BurdJournals

    if not journalData or not journalData.traits then
        BurdJournals.Server.sendToClient(player, "error", {message = "This journal has no trait data."})
        return
    end

    if not journalData.traits[traitId] then
        print("[BurdJournals] Server ERROR: Trait '" .. traitId .. "' not found in journal")
        BurdJournals.Server.sendToClient(player, "error", {message = "Trait not found in journal."})
        return
    end

    if BurdJournals.playerHasTrait(player, traitId) then
        -- Mark as claimed even though player already has this trait (allows journal dissolution)
        BurdJournals.markTraitClaimedByCharacter(journalData, player, traitId)
        if journal.transmitModData then
            journal:transmitModData()
        end
        BurdJournals.Server.sendToClient(player, "traitAlreadyKnown", {
            traitId = traitId,
            journalId = journalId,
        })
        -- Re-fetch journal by ID before calling shouldDissolve to avoid zombie object errors
        local freshJournal = BurdJournals.findItemById(player, journalId)
        if freshJournal and BurdJournals.isValidItem(freshJournal) and BurdJournals.shouldDissolve and BurdJournals.shouldDissolve(freshJournal, player) then
            BurdJournals.Server.dissolveJournal(player, freshJournal)
        end
        return
    end

    local traitWasAdded = BurdJournals.safeAddTrait(player, traitId)

    if traitWasAdded then

        BurdJournals.markTraitClaimedByCharacter(journalData, player, traitId)

        if journal.transmitModData then
            journal:transmitModData()
        end

        BurdJournals.Server.sendToClient(player, "claimSuccess", {
            traitId = traitId,
            journalId = journalId,
            journalData = journalData,
        })
        -- Re-fetch journal by ID before calling shouldDissolve to avoid zombie object errors
        local freshJournal = BurdJournals.findItemById(player, journalId)
        print("[BurdJournals] Server: Post-trait claim check - freshJournal=" .. tostring(freshJournal ~= nil) .. ", journalId=" .. tostring(journalId))
        if freshJournal then
            local isValid = BurdJournals.isValidItem(freshJournal)
            local hasShouldDissolve = BurdJournals.shouldDissolve ~= nil
            local shouldDis = hasShouldDissolve and BurdJournals.shouldDissolve(freshJournal, player)
            print("[BurdJournals] Server: isValid=" .. tostring(isValid) .. ", hasShouldDissolve=" .. tostring(hasShouldDissolve) .. ", shouldDis=" .. tostring(shouldDis))
            if isValid and shouldDis then
                print("[BurdJournals] Server: DISSOLVING JOURNAL after trait claim!")
                BurdJournals.Server.dissolveJournal(player, freshJournal)
            end
        end
    else
        BurdJournals.Server.sendToClient(player, "error", {message = "Could not learn trait."})
    end
end

function BurdJournals.Server.handleAbsorbSkill(player, args)
    if not args or not args.skillName then

        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid request."})
        return
    end

    local journalId = args.journalId
    local skillName = args.skillName

    local journal = BurdJournals.findItemById(player, journalId)

    if not journal then
        print("[BurdJournals] Server ERROR: Journal not found by ID " .. tostring(journalId))
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal not found."})
        return
    end

    if not BurdJournals.canAbsorbXP(journal) then
        BurdJournals.Server.sendToClient(player, "error", {message = "Cannot absorb from this journal."})
        return
    end

    local modData = journal:getModData()

    if modData and BurdJournals.isDebug() then
        for k, v in pairs(modData) do
            print("  - " .. tostring(k) .. " = " .. type(v))
        end
    end

    local journalData = modData.BurdJournals

    if not journalData then
        BurdJournals.Server.sendToClient(player, "error", {message = "This journal has no data."})
        return
    end

    if BurdJournals.isDebug() then
        for k, v in pairs(journalData) do
            local valueStr = tostring(v)
            if type(v) == "table" then
                valueStr = "table with " .. BurdJournals.countTable(v) .. " entries"
            end
            print("  - " .. tostring(k) .. " = " .. valueStr)
        end
    end

    if not journalData.skills then
        BurdJournals.Server.sendToClient(player, "error", {message = "This journal has no skill data."})
        return
    end

    local skillCount = BurdJournals.countTable(journalData.skills)

    if BurdJournals.isDebug() then
        for skillKey, skillVal in pairs(journalData.skills) do
            if type(skillVal) == "table" then
                print("  - '" .. tostring(skillKey) .. "': xp=" .. tostring(skillVal.xp) .. ", level=" .. tostring(skillVal.level))
            else
                print("  - '" .. tostring(skillKey) .. "': INVALID (not a table, is " .. type(skillVal) .. ")")
            end
        end
    end

    if not journalData.skills[skillName] then
        print("[BurdJournals] Server ERROR: Skill '" .. tostring(skillName) .. "' not found in journal!")

        if BurdJournals.isDebug() then
            for k, _ in pairs(journalData.skills) do
                print("  - '" .. tostring(k) .. "'")
            end
        end
        BurdJournals.Server.sendToClient(player, "error", {message = "Skill not found in journal."})
        return
    end

    if BurdJournals.hasCharacterClaimedSkill(journalData, player, skillName) then
        BurdJournals.Server.sendToClient(player, "error", {message = "This skill has already been claimed."})
        return
    end

    local skillData = journalData.skills[skillName]

    if type(skillData) ~= "table" then
        print("[BurdJournals] Server ERROR: skillData is not a table! It's: " .. type(skillData) .. " = " .. tostring(skillData))
        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid skill data."})
        return
    end

    local baseXP = skillData.xp

    if baseXP == nil then
        if BurdJournals.isDebug() then
            for k, v in pairs(skillData) do
                print("  - " .. tostring(k) .. " = " .. tostring(v))
            end
        end
        baseXP = 0
    end

    if type(baseXP) ~= "number" then

        baseXP = tonumber(baseXP) or 0
    end

    local journalMultiplier = BurdJournals.getSandboxOption("JournalXPMultiplier") or 1.0
    local xpToAdd = baseXP * journalMultiplier

    local perk = BurdJournals.getPerkByName(skillName)

    if not perk then

        perk = Perks[skillName]

        if not perk and BurdJournals.SKILL_TO_PERK and BurdJournals.SKILL_TO_PERK[skillName] then
            local mappedName = BurdJournals.SKILL_TO_PERK[skillName]

            perk = Perks[mappedName]
        end
    end

    if not perk then
        print("[BurdJournals] Server ERROR: Could not find perk for skill '" .. skillName .. "'")
        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid skill: " .. skillName})
        return
    end

    if xpToAdd > 0 then

        BurdJournals.markSkillClaimedByCharacter(journalData, player, skillName)

        -- Re-fetch journal by ID before calling shouldDissolve to avoid zombie object errors
        local freshJournal = BurdJournals.findItemById(player, journalId)
        local shouldDis = false
        if freshJournal and BurdJournals.isValidItem(freshJournal) then
            shouldDis = BurdJournals.shouldDissolve(freshJournal, player)
        end

        -- Apply XP directly on server using vanilla addXp function (42.13.2+ compatible)
        if addXp and perk then
            print("[BurdJournals] Server: Absorb - Applying " .. tostring(xpToAdd) .. " XP to " .. skillName .. " via addXp()")
            addXp(player, perk, xpToAdd)
        else
            -- Fallback for SP or if addXp unavailable
            print("[BurdJournals] Server: Absorb fallback - sending applyXP to client for " .. skillName)
            BurdJournals.Server.sendToClient(player, "applyXP", {
                skills = {
                    [skillName] = {
                        xp = xpToAdd,
                        mode = "add"
                    }
                },
                mode = "add"
            })
        end

        if shouldDis and freshJournal then

            local container = freshJournal:getContainer()

            if container then
                container:Remove(freshJournal)
            end

            local inv = player:getInventory()
            if inv:contains(freshJournal) then
                inv:Remove(freshJournal)
            end

            BurdJournals.Server.sendToClient(player, "journalDissolved", {
                message = BurdJournals.getRandomDissolutionMessage(),
                journalId = journalId
            })
        else

            if freshJournal and freshJournal.transmitModData then
                freshJournal:transmitModData()
            end

            -- Use per-character unclaimed counts (use freshJournal if available)
            local jnl = freshJournal or journal
            local remainingRewards = 0
            local totalRewards = 0
            if jnl then
                remainingRewards = BurdJournals.getUnclaimedSkillCount(jnl, player) +
                                   BurdJournals.getUnclaimedTraitCount(jnl, player) +
                                   BurdJournals.getUnclaimedRecipeCount(jnl, player)
                totalRewards = BurdJournals.getTotalRewards(jnl)
            end
            BurdJournals.Server.sendToClient(player, "absorbSuccess", {
                skillName = skillName,
                xpGained = xpToAdd,
                remaining = remainingRewards,
                total = totalRewards,
                journalId = journalId,
                journalData = journalData,
                })
        end
    else
        -- Still mark as claimed even if no XP to add (allows journal dissolution)
        BurdJournals.markSkillClaimedByCharacter(journalData, player, skillName)

        -- Re-fetch journal by ID to avoid zombie object errors
        local freshJournal = BurdJournals.findItemById(player, journalId)
        if freshJournal and freshJournal.transmitModData then
            freshJournal:transmitModData()
        end
        BurdJournals.Server.sendToClient(player, "skillMaxed", {
            skillName = skillName,
            journalId = journalId,
            journalData = journalData,
        })
        -- Check if journal should dissolve after marking this claim
        if freshJournal and BurdJournals.isValidItem(freshJournal) and BurdJournals.shouldDissolve and BurdJournals.shouldDissolve(freshJournal, player) then
            BurdJournals.Server.dissolveJournal(player, freshJournal)
        end
    end

end

function BurdJournals.Server.handleAbsorbTrait(player, args)
    if not args or not args.traitId then
        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid request."})
        return
    end

    local journalId = args.journalId
    local traitId = args.traitId

    local journal = BurdJournals.findItemById(player, journalId)

    if not journal then
        print("[BurdJournals] Server ERROR: Journal not found by ID " .. tostring(journalId))
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal not found."})
        return
    end

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

    if not journalData.traits[traitId] then
        BurdJournals.Server.sendToClient(player, "error", {message = "Trait not found in journal."})
        return
    end

    if BurdJournals.hasCharacterClaimedTrait(journalData, player, traitId) then
        BurdJournals.Server.sendToClient(player, "error", {message = "This trait has already been claimed."})
        return
    end

    if BurdJournals.playerHasTrait(player, traitId) then
        -- Mark as claimed even though player already has this trait (allows journal dissolution)
        BurdJournals.markTraitClaimedByCharacter(journalData, player, traitId)

        -- Re-fetch journal to avoid zombie object errors
        local freshJournal = BurdJournals.findItemById(player, journalId)
        if freshJournal and freshJournal.transmitModData then
            freshJournal:transmitModData()
        end
        BurdJournals.Server.sendToClient(player, "traitAlreadyKnown", {
            traitId = traitId,
            journalId = journalId,
        })
        -- Check if journal should dissolve after marking this claim (use safe wrapper)
        if BurdJournals.Server.safeShouldDissolve(player, journalId) then
            local jnl = BurdJournals.findItemById(player, journalId)
            if jnl then BurdJournals.Server.dissolveJournal(player, jnl) end
        end
        return
    end

    local traitWasAdded = false
    local success, err = BurdJournals.safePcall(function()
        local characterTrait = nil

        if CharacterTrait and CharacterTrait.get and ResourceLocation and ResourceLocation.of then

            local resourceLoc = "base:" .. string.lower(traitId)

            local ok, result = BurdJournals.safePcall(function()
                return CharacterTrait.get(ResourceLocation.of(resourceLoc))
            end)
            if ok and result then
                characterTrait = result
            end

            if not characterTrait then
                local withSpaces = string.lower(traitId:gsub("(%u)", " %1"):sub(2))
                local resourceLocSpaces = "base:" .. withSpaces
                if resourceLocSpaces ~= resourceLoc then
                    ok, result = BurdJournals.safePcall(function()
                        return CharacterTrait.get(ResourceLocation.of(resourceLocSpaces))
                    end)
                    if ok and result then
                        characterTrait = result
                    end
                end
            end
        end

        if not characterTrait and CharacterTrait then
            local underscored = traitId:gsub("(%u)", "_%1"):sub(2):upper()

            local ct = CharacterTrait[underscored]
            if ct then
                if type(ct) == "string" and CharacterTrait.get and ResourceLocation and ResourceLocation.of then
                    local ok, result = BurdJournals.safePcall(function()
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

        if not characterTrait and CharacterTraitDefinition and CharacterTraitDefinition.getTraits then
            local allTraits = CharacterTraitDefinition.getTraits()

            for i = 0, allTraits:size() - 1 do
                local def = allTraits:get(i)
                local defType = def:getType()
                local defLabel = def:getLabel()
                local defName = "?"
                if defType then
                    BurdJournals.safePcall(function() defName = defType:getName() or tostring(defType) end)
                end

                if defLabel == traitId or defName == traitId or string.upper(defName) == string.upper(traitId) then
                    characterTrait = defType
                    break
                end
            end
        end

        if characterTrait then
            local charTraits = player:getCharacterTraits()

            local hadBefore = player:hasTrait(characterTrait)

            charTraits:add(characterTrait)

            if player.modifyTraitXPBoost then
                player:modifyTraitXPBoost(characterTrait, false)

            end

            if SyncXp then
                SyncXp(player)

            else

            end

            local hasAfter = player:hasTrait(characterTrait)

            if hasAfter and not hadBefore then

                return true
            elseif hasAfter and hadBefore then

                return false
            else

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

    if traitWasAdded then

        BurdJournals.markTraitClaimedByCharacter(journalData, player, traitId)

        -- Re-fetch journal by ID before calling shouldDissolve to avoid zombie object errors
        local freshJournal = BurdJournals.findItemById(player, journalId)
        local shouldDis = false
        if freshJournal and BurdJournals.isValidItem(freshJournal) then
            shouldDis = BurdJournals.shouldDissolve(freshJournal, player)
        end

        BurdJournals.Server.sendToClient(player, "grantTrait", {
            traitId = traitId,
            journalId = journalId,
        })

        if shouldDis and freshJournal then

            local container = freshJournal:getContainer()

            if container then
                container:Remove(freshJournal)
            end

            local inv = player:getInventory()
            if inv:contains(freshJournal) then
                inv:Remove(freshJournal)
            end

            BurdJournals.Server.sendToClient(player, "journalDissolved", {
                message = BurdJournals.getRandomDissolutionMessage(),
                journalId = journalId
            })
        else

            if freshJournal and freshJournal.transmitModData then
                freshJournal:transmitModData()
            end

            -- Use per-character unclaimed counts (use freshJournal if available)
            local jnl = freshJournal or journal
            local remainingRewards = 0
            local totalRewards = 0
            if jnl then
                remainingRewards = BurdJournals.getUnclaimedSkillCount(jnl, player) +
                                   BurdJournals.getUnclaimedTraitCount(jnl, player) +
                                   BurdJournals.getUnclaimedRecipeCount(jnl, player)
                totalRewards = BurdJournals.getTotalRewards(jnl)
            end
            BurdJournals.Server.sendToClient(player, "absorbSuccess", {
                traitId = traitId,
                remaining = remainingRewards,
                total = totalRewards,
                journalId = journalId,
                journalData = journalData,
                })
        end
    else

        BurdJournals.Server.sendToClient(player, "error", {message = "Could not learn trait."})
    end
end

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

    if not BurdJournals.isClean(journal) then
        BurdJournals.Server.sendToClient(player, "error", {message = "Can only erase clean journals."})
        return
    end

    if BurdJournals.getSandboxOption("RequireEraserToErase") then
        local eraser = BurdJournals.findEraser(player)
        if not eraser then
            BurdJournals.Server.sendToClient(player, "error", {message = "You need an eraser to wipe the journal."})
            return
        end
    end

    local inventory = player:getInventory()
    inventory:Remove(journal)
    sendRemoveItemFromContainer(inventory, journal)

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

        if blankJournal.transmitModData then
            blankJournal:transmitModData()
            BurdJournals.debugPrint("[BurdJournals] Server: transmitModData called for blank journal in handleEraseJournal")
        end

        sendAddItemToContainer(inventory, blankJournal)
        BurdJournals.debugPrint("[BurdJournals] Server: sendAddItemToContainer called for blank journal in handleEraseJournal")
    end

    BurdJournals.Server.sendToClient(player, "eraseSuccess", {})
end

function BurdJournals.Server.handleCleanBloody(player, args)

    BurdJournals.Server.sendToClient(player, "error", {
        message = "Bloody journals can now be read directly. Right-click to open and absorb XP."
    })
end

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

    if not BurdJournals.isWorn(journal) then
        BurdJournals.Server.sendToClient(player, "error", {message = "Only worn journals can be converted."})
        return
    end

    if not BurdJournals.canConvertToClean(player) then
        BurdJournals.Server.sendToClient(player, "error", {message = "You need leather, thread, needle, and Tailoring Lv1."})
        return
    end

    local leather = BurdJournals.findRepairItem(player, "leather")
    local thread = BurdJournals.findRepairItem(player, "thread")
    local needle = BurdJournals.findRepairItem(player, "needle")

    player:getInventory():Remove(leather)
    BurdJournals.consumeItemUses(thread, 1, player)
    BurdJournals.consumeItemUses(needle, 1, player)

    local inventory = player:getInventory()
    inventory:Remove(journal)
    sendRemoveItemFromContainer(inventory, journal)

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

        if cleanJournal.transmitModData then
            cleanJournal:transmitModData()
            BurdJournals.debugPrint("[BurdJournals] Server: transmitModData called for clean journal in handleConvertToClean")
        end

        sendAddItemToContainer(inventory, cleanJournal)
        BurdJournals.debugPrint("[BurdJournals] Server: sendAddItemToContainer called for clean journal in handleConvertToClean")
    end

    BurdJournals.Server.sendToClient(player, "convertSuccess", {
        message = "The worn journal has been restored to a clean blank journal."
    })
end

function BurdJournals.Server.handleClaimRecipe(player, args)
    if not args or not args.recipeName then
        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid request."})
        return
    end

    local journalId = args.journalId
    local recipeName = args.recipeName

    local journal = BurdJournals.findItemById(player, journalId)
    if not journal then
        print("[BurdJournals] Server ERROR: Journal not found by ID " .. tostring(journalId))
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal not found."})
        return
    end

    local canClaim, reason = BurdJournals.canPlayerClaimFromJournal(player, journal)
    if not canClaim then
        BurdJournals.Server.sendToClient(player, "error", {message = reason or "Permission denied."})
        return
    end

    local modData = journal:getModData()
    local journalData = modData.BurdJournals

    if not journalData or not journalData.recipes then
        BurdJournals.Server.sendToClient(player, "error", {message = "This journal has no recipe data."})
        return
    end

    if not journalData.recipes[recipeName] then
        print("[BurdJournals] Server ERROR: Recipe '" .. recipeName .. "' not found in journal")
        BurdJournals.Server.sendToClient(player, "error", {message = "Recipe not found in journal."})
        return
    end

    if BurdJournals.playerKnowsRecipe(player, recipeName) then
        -- Mark as claimed even though player already knows the recipe (allows journal dissolution)
        BurdJournals.markRecipeClaimedByCharacter(journalData, player, recipeName)
        if journal.transmitModData then
            journal:transmitModData()
        end
        BurdJournals.Server.sendToClient(player, "recipeAlreadyKnown", {
            recipeName = recipeName,
            journalId = journalId,
        })
        -- Re-fetch journal by ID before calling shouldDissolve to avoid zombie object errors
        local freshJournal = BurdJournals.findItemById(player, journalId)
        if freshJournal and BurdJournals.isValidItem(freshJournal) and BurdJournals.shouldDissolve and BurdJournals.shouldDissolve(freshJournal, player) then
            BurdJournals.Server.dissolveJournal(player, freshJournal)
        end
        return
    end

    local recipeWasLearned = BurdJournals.learnRecipeWithVerification(player, recipeName, "[BurdJournals Server]")

    if recipeWasLearned then

        BurdJournals.markRecipeClaimedByCharacter(journalData, player, recipeName)

        if journal.transmitModData then
            journal:transmitModData()
        end

        if sendSyncPlayerFields then
            sendSyncPlayerFields(player, 0x00000007)
        end

        BurdJournals.Server.sendToClient(player, "claimSuccess", {
            recipeName = recipeName,
            journalId = journalId,
            journalData = journalData,
        })
        -- Re-fetch journal by ID before calling shouldDissolve to avoid zombie object errors
        local freshJournal = BurdJournals.findItemById(player, journalId)
        print("[BurdJournals] Server: Post-recipe claim check - freshJournal=" .. tostring(freshJournal ~= nil) .. ", journalId=" .. tostring(journalId))
        if freshJournal then
            local isValid = BurdJournals.isValidItem(freshJournal)
            local hasShouldDissolve = BurdJournals.shouldDissolve ~= nil
            local shouldDis = hasShouldDissolve and BurdJournals.shouldDissolve(freshJournal, player)
            print("[BurdJournals] Server: isValid=" .. tostring(isValid) .. ", hasShouldDissolve=" .. tostring(hasShouldDissolve) .. ", shouldDis=" .. tostring(shouldDis))
            if isValid and shouldDis then
                print("[BurdJournals] Server: DISSOLVING JOURNAL after recipe claim!")
                BurdJournals.Server.dissolveJournal(player, freshJournal)
            end
        end
    else
        BurdJournals.Server.sendToClient(player, "error", {message = "Could not learn recipe."})
    end
end

function BurdJournals.Server.handleAbsorbRecipe(player, args)
    if not args or not args.recipeName then
        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid request."})
        return
    end

    local journalId = args.journalId
    local recipeName = args.recipeName

    local journal = BurdJournals.findItemById(player, journalId)
    if not journal then
        print("[BurdJournals] Server ERROR: Journal not found by ID " .. tostring(journalId))
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal not found."})
        return
    end

    if not BurdJournals.canAbsorbXP(journal) then
        BurdJournals.Server.sendToClient(player, "error", {message = "Cannot absorb from this journal."})
        return
    end

    local modData = journal:getModData()
    local journalData = modData.BurdJournals

    if not journalData or not journalData.recipes then
        BurdJournals.Server.sendToClient(player, "error", {message = "This journal has no recipe data."})
        return
    end

    if not journalData.recipes[recipeName] then
        print("[BurdJournals] Server ERROR: Recipe '" .. recipeName .. "' not found in journal")
        BurdJournals.Server.sendToClient(player, "error", {message = "Recipe not found in journal."})
        return
    end

    if BurdJournals.hasCharacterClaimedRecipe(journalData, player, recipeName) then
        BurdJournals.Server.sendToClient(player, "error", {message = "Recipe already claimed."})
        return
    end

    if BurdJournals.playerKnowsRecipe(player, recipeName) then

        BurdJournals.markRecipeClaimedByCharacter(journalData, player, recipeName)

        if journal.transmitModData then
            journal:transmitModData()
        end

        BurdJournals.Server.sendToClient(player, "recipeAlreadyKnown", {
            recipeName = recipeName,
            journalId = journalId,
        })

        -- Re-fetch journal by ID before calling shouldDissolve to avoid zombie object errors
        local freshJournal = BurdJournals.findItemById(player, journalId)
        if freshJournal and BurdJournals.isValidItem(freshJournal) and BurdJournals.shouldDissolve(freshJournal, player) then
            local dissolutionMessage = BurdJournals.getRandomDissolutionMessage()
            removeJournalCompletely(player, freshJournal)
            BurdJournals.Server.sendToClient(player, "journalDissolved", {
                message = dissolutionMessage
            })
        end
        return
    end

    local recipeWasLearned = BurdJournals.learnRecipeWithVerification(player, recipeName, "[BurdJournals Server]")

    if recipeWasLearned then

        BurdJournals.markRecipeClaimedByCharacter(journalData, player, recipeName)

        if journal.transmitModData then
            journal:transmitModData()
        end

        if sendSyncPlayerFields then
            sendSyncPlayerFields(player, 0x00000007)
        end

        local updatedJournalData = BurdJournals.Server.copyJournalData(journal)

        -- Re-fetch journal by ID before calling shouldDissolve to avoid zombie object errors
        local freshJournal = BurdJournals.findItemById(player, journalId)
        local shouldDis = freshJournal and BurdJournals.isValidItem(freshJournal) and BurdJournals.shouldDissolve(freshJournal, player)

        if shouldDis then
            local dissolutionMessage = BurdJournals.getRandomDissolutionMessage()
            removeJournalCompletely(player, freshJournal)

            BurdJournals.Server.sendToClient(player, "absorbSuccess", {
                recipeName = recipeName,
                journalData = updatedJournalData,
                dissolved = true,
                dissolutionMessage = dissolutionMessage
            })
        else
            BurdJournals.Server.sendToClient(player, "absorbSuccess", {
                recipeName = recipeName,
                journalId = journalId,
                journalData = updatedJournalData,
                dissolved = false
            })
        end
    else
        BurdJournals.Server.sendToClient(player, "error", {message = "Could not learn recipe."})
    end
end

function BurdJournals.Server.handleEraseEntry(player, args)
    if not args then
        BurdJournals.debugPrint("[BurdJournals] Server: EraseEntry - No args provided")
        return
    end

    local journalId = args.journalId
    local entryType = args.entryType
    local entryName = args.entryName

    if not journalId or not entryType or not entryName then
        BurdJournals.debugPrint("[BurdJournals] Server: EraseEntry - Missing required args")
        BurdJournals.Server.sendToClient(player, "error", {message = "Invalid erase request."})
        return
    end

    BurdJournals.debugPrint("[BurdJournals] Server: Processing erase request - type: " .. entryType .. ", name: " .. entryName)

    local journal = BurdJournals.findItemById(player, journalId)
    if not journal then
        BurdJournals.debugPrint("[BurdJournals] Server: EraseEntry - Journal not found: " .. tostring(journalId))
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal not found."})
        return
    end

    local modData = journal:getModData()
    if not modData or not modData.BurdJournals then
        BurdJournals.debugPrint("[BurdJournals] Server: EraseEntry - No journal data")
        BurdJournals.Server.sendToClient(player, "error", {message = "Journal has no data."})
        return
    end

    local journalData = modData.BurdJournals
    local erased = false

    if entryType == "skill" then
        if journalData.skills and journalData.skills[entryName] then
            journalData.skills[entryName] = nil
            erased = true
            BurdJournals.debugPrint("[BurdJournals] Server: Erased skill entry: " .. entryName)
        end

        if journalData.claimedSkills and journalData.claimedSkills[entryName] then
            journalData.claimedSkills[entryName] = nil
        end
    elseif entryType == "trait" then
        if journalData.traits and journalData.traits[entryName] then
            journalData.traits[entryName] = nil
            erased = true
            BurdJournals.debugPrint("[BurdJournals] Server: Erased trait entry: " .. entryName)
        end

        if journalData.claimedTraits and journalData.claimedTraits[entryName] then
            journalData.claimedTraits[entryName] = nil
        end
    elseif entryType == "recipe" then
        if journalData.recipes and journalData.recipes[entryName] then
            journalData.recipes[entryName] = nil
            erased = true
            BurdJournals.debugPrint("[BurdJournals] Server: Erased recipe entry: " .. entryName)
        end

        if journalData.claimedRecipes and journalData.claimedRecipes[entryName] then
            journalData.claimedRecipes[entryName] = nil
        end
    end

    if erased then

        if journal.transmitModData then
            journal:transmitModData()
        end

        local updatedJournalData = BurdJournals.Server.copyJournalData(journal)

        BurdJournals.Server.sendToClient(player, "eraseSuccess", {
            entryType = entryType,
            entryName = entryName,
            journalId = journal:getID(),
            journalData = updatedJournalData
        })
        BurdJournals.debugPrint("[BurdJournals] Server: Erase successful, sent confirmation to client")
    else
        BurdJournals.debugPrint("[BurdJournals] Server: Entry not found to erase: " .. entryType .. " - " .. entryName)
        BurdJournals.Server.sendToClient(player, "error", {message = "Entry not found."})
    end
end

function BurdJournals.Server.getBaselineCache()
    local cache = ModData.getOrCreate("BurdJournals_PlayerBaselines")
    if not cache.players then
        cache.players = {}
    end
    return cache
end

function BurdJournals.Server.getCachedBaseline(characterId)
    if not characterId then return nil end
    local cache = BurdJournals.Server.getBaselineCache()
    return cache.players[characterId]
end

function BurdJournals.Server.storeCachedBaseline(characterId, baselineData, forceOverwrite)
    if not characterId or not baselineData then return false end

    local cache = BurdJournals.Server.getBaselineCache()

    if cache.players[characterId] and not forceOverwrite then
        BurdJournals.debugPrint("[BurdJournals] Baseline already cached for " .. characterId .. ", ignoring new registration")
        return false
    end

    cache.players[characterId] = {
        skillBaseline = baselineData.skillBaseline or {},
        traitBaseline = baselineData.traitBaseline or {},
        recipeBaseline = baselineData.recipeBaseline or {},
        capturedAt = getGameTime():getWorldAgeHours(),
        steamId = baselineData.steamId,
        characterName = baselineData.characterName
    }

    -- Persist to disk so baseline survives server restart
    if ModData.transmit then
        ModData.transmit("BurdJournals_PlayerBaselines")
    end

    BurdJournals.debugPrint("[BurdJournals] Baseline cached and persisted for " .. characterId)
    return true
end

function BurdJournals.Server.handleRegisterBaseline(player, args)
    if not player or not args then return end

    local characterId = args.characterId
    if not characterId then
        print("[BurdJournals] ERROR: No characterId in registerBaseline")
        return
    end

    local serverCharacterId = BurdJournals.getPlayerCharacterId(player)
    if serverCharacterId ~= characterId then
        print("[BurdJournals] WARNING: Character ID mismatch! Client sent: " .. characterId .. ", Server computed: " .. tostring(serverCharacterId))

        characterId = serverCharacterId
    end

    local stored = BurdJournals.Server.storeCachedBaseline(characterId, {
        skillBaseline = args.skillBaseline,
        traitBaseline = args.traitBaseline,
        recipeBaseline = args.recipeBaseline,
        steamId = args.steamId,
        characterName = args.characterName
    }, false)

    BurdJournals.Server.sendToClient(player, "baselineRegistered", {
        success = stored,
        characterId = characterId,
        alreadyExisted = not stored
    })
end

function BurdJournals.Server.handleDeleteBaseline(player, args)
    if not player then return end

    -- Security: Require admin access to delete baseline (prevents exploit)
    local accessLevel = player:getAccessLevel()
    if not accessLevel or accessLevel == "None" then
        print("[BurdJournals] WARNING: Non-admin player attempted deleteBaseline: " .. tostring(player.getUsername and player:getUsername() or "unknown"))
        BurdJournals.Server.sendToClient(player, "error", {message = "Admin access required."})
        return
    end

    local characterId = args and args.characterId
    if not characterId then
        print("[BurdJournals] ERROR: No characterId in deleteBaseline")
        return
    end

    local serverCharacterId = BurdJournals.getPlayerCharacterId(player)
    if serverCharacterId ~= characterId then
        print("[BurdJournals] WARNING: Character ID mismatch in deleteBaseline! Client sent: " .. characterId .. ", Server computed: " .. tostring(serverCharacterId))
        characterId = serverCharacterId
    end

    local cache = BurdJournals.Server.getBaselineCache()
    if cache.players[characterId] then
        cache.players[characterId] = nil
        -- Persist deletion to disk
        if ModData.transmit then
            ModData.transmit("BurdJournals_PlayerBaselines")
        end
        BurdJournals.debugPrint("[BurdJournals] Deleted cached baseline for: " .. characterId)
    else
        BurdJournals.debugPrint("[BurdJournals] No cached baseline to delete for: " .. characterId)
    end
end

-- Admin command to clear ALL baseline caches server-wide
-- This allows a fresh start for all players - baselines will be captured on next character creation
function BurdJournals.Server.handleClearAllBaselines(player, _args)
    if not player then return end

    -- Check if player is admin
    local accessLevel = player:getAccessLevel()
    if not accessLevel or accessLevel == "None" then
        print("[BurdJournals] WARNING: Non-admin player attempted clearAllBaselines: " .. tostring(player:getUsername()))
        BurdJournals.Server.sendToClient(player, "error", {message = "Admin access required."})
        return
    end

    local cache = BurdJournals.Server.getBaselineCache()
    local clearedCount = 0

    -- Count entries before clearing
    for _ in pairs(cache.players) do
        clearedCount = clearedCount + 1
    end

    -- Clear all cached baselines
    cache.players = {}

    -- Persist to disk
    if ModData.transmit then
        ModData.transmit("BurdJournals_PlayerBaselines")
    end

    print("[BurdJournals] ADMIN " .. tostring(player:getUsername()) .. " cleared ALL baseline caches (" .. clearedCount .. " entries)")

    -- Notify the admin
    BurdJournals.Server.sendToClient(player, "allBaselinesCleared", {
        clearedCount = clearedCount
    })
end

function BurdJournals.Server.handleRequestBaseline(player, args)
    if not player then return end

    local characterId = BurdJournals.getPlayerCharacterId(player)
    if not characterId then
        print("[BurdJournals] ERROR: Could not compute characterId for baseline request")
        BurdJournals.Server.sendToClient(player, "baselineResponse", {
            found = false,
            characterId = nil
        })
        return
    end

    local cachedBaseline = BurdJournals.Server.getCachedBaseline(characterId)

    if cachedBaseline then
        BurdJournals.debugPrint("[BurdJournals] Found cached baseline for " .. characterId)
        BurdJournals.Server.sendToClient(player, "baselineResponse", {
            found = true,
            characterId = characterId,
            skillBaseline = cachedBaseline.skillBaseline,
            traitBaseline = cachedBaseline.traitBaseline,
            recipeBaseline = cachedBaseline.recipeBaseline
        })
    else
        BurdJournals.debugPrint("[BurdJournals] No cached baseline for " .. characterId .. " (new player or migration needed)")
        BurdJournals.Server.sendToClient(player, "baselineResponse", {
            found = false,
            characterId = characterId
        })
    end
end

BurdJournals.Server.BASELINE_CACHE_TTL_HOURS = 720

BurdJournals.Server._lastBaselineCleanup = 0

BurdJournals.Server.BASELINE_CLEANUP_INTERVAL = 24

function BurdJournals.Server.pruneBaselineCache()
    local cache = BurdJournals.Server.getBaselineCache()
    if not cache.players then return 0 end

    local currentHours = getGameTime():getWorldAgeHours()
    local ttl = BurdJournals.Server.BASELINE_CACHE_TTL_HOURS
    local prunedCount = 0
    local toRemove = {}

    for characterId, baseline in pairs(cache.players) do
        local capturedAt = baseline.capturedAt or 0
        local age = currentHours - capturedAt

        if age > ttl then
            table.insert(toRemove, characterId)
        end
    end

    for _, characterId in ipairs(toRemove) do
        cache.players[characterId] = nil
        prunedCount = prunedCount + 1
        BurdJournals.debugPrint("[BurdJournals] Pruned stale baseline for: " .. characterId)
    end

    if prunedCount > 0 then
        -- Persist pruned cache to disk
        if ModData.transmit then
            ModData.transmit("BurdJournals_PlayerBaselines")
        end
        BurdJournals.debugPrint("[BurdJournals] Baseline cache cleanup: removed " .. prunedCount .. " stale entries")
    end

    return prunedCount
end

function BurdJournals.Server.checkBaselineCleanup()
    local currentHours = getGameTime():getWorldAgeHours()
    local timeSinceCleanup = currentHours - BurdJournals.Server._lastBaselineCleanup

    if timeSinceCleanup >= BurdJournals.Server.BASELINE_CLEANUP_INTERVAL then
        BurdJournals.Server._lastBaselineCleanup = currentHours
        BurdJournals.Server.pruneBaselineCache()
    end
end

function BurdJournals.Server.forceBaselineCleanup()
    BurdJournals.debugPrint("[BurdJournals] Admin: Forcing baseline cache cleanup...")
    local pruned = BurdJournals.Server.pruneBaselineCache()
    BurdJournals.debugPrint("[BurdJournals] Admin: Cleanup complete, removed " .. pruned .. " entries")
    return pruned
end

print("[BurdJournals] Registering OnClientCommand handler...")
print("[BurdJournals] Events table exists: " .. tostring(Events ~= nil))
print("[BurdJournals] Events.OnClientCommand exists: " .. tostring(Events and Events.OnClientCommand ~= nil))
print("[BurdJournals] BurdJournals.Server.onClientCommand exists: " .. tostring(BurdJournals.Server.onClientCommand ~= nil))

local ok, err = pcall(function()
    Events.OnClientCommand.Add(BurdJournals.Server.onClientCommand)
end)
if ok then
    print("[BurdJournals] OnClientCommand handler registered SUCCESSFULLY")
else
    print("[BurdJournals] ERROR registering OnClientCommand: " .. tostring(err))
end

Events.OnServerStarted.Add(BurdJournals.Server.init)
Events.EveryHours.Add(BurdJournals.Server.checkBaselineCleanup)

print("[BurdJournals] Server module fully loaded!")
