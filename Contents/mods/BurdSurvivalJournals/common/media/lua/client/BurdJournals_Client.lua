
require "BurdJournals_Shared"

BurdJournals = BurdJournals or {}
BurdJournals.Client = BurdJournals.Client or {}

-- Version 3: Fixed recipe baseline capture when SeeNotLearntRecipe sandbox option is enabled
BurdJournals.Client.BASELINE_VERSION = 4  -- v4: Clear recipe baseline for existing characters (fixes recipes not recordable bug)

BurdJournals.Client._activeTickHandlers = {}
BurdJournals.Client._tickHandlerIdCounter = 0

function BurdJournals.Client.registerTickHandler(handlerFunc, debugName)
    BurdJournals.Client._tickHandlerIdCounter = BurdJournals.Client._tickHandlerIdCounter + 1
    local handlerId = BurdJournals.Client._tickHandlerIdCounter

    local wrappedHandler = {
        id = handlerId,
        name = debugName or ("handler_" .. handlerId),
        func = handlerFunc,
        active = true,
        registered = getTimestampMs and getTimestampMs() or 0
    }

    BurdJournals.Client._activeTickHandlers[handlerId] = wrappedHandler
    Events.OnTick.Add(handlerFunc)

    return handlerId
end

function BurdJournals.Client.unregisterTickHandler(handlerId)
    local handler = BurdJournals.Client._activeTickHandlers[handlerId]
    if handler and handler.active then
        handler.active = false
        pcall(function() Events.OnTick.Remove(handler.func) end)
        BurdJournals.Client._activeTickHandlers[handlerId] = nil
        return true
    end
    return false
end

function BurdJournals.Client.cleanupAllTickHandlers()
    local count = 0
    for handlerId, handler in pairs(BurdJournals.Client._activeTickHandlers) do
        if handler.active then
            handler.active = false
            pcall(function() Events.OnTick.Remove(handler.func) end)
            count = count + 1
        end
    end
    BurdJournals.Client._activeTickHandlers = {}
    if count > 0 then
        BurdJournals.debugPrint("[BurdJournals] Cleaned up " .. count .. " orphaned tick handlers")
    end
end

BurdJournals.Client._lastKnownCharacterId = nil

BurdJournals.Client._currentLanguage = nil

function BurdJournals.Client.checkLanguageChange()
    local newLanguage = nil

    if Translator and Translator.getLanguage then
        newLanguage = Translator.getLanguage()
    elseif getCore and getCore().getLanguage then
        newLanguage = getCore():getLanguage()
    end

    if newLanguage and BurdJournals.Client._currentLanguage and newLanguage ~= BurdJournals.Client._currentLanguage then

        if BurdJournals.clearLocalizedItemsCache then
            BurdJournals.clearLocalizedItemsCache()
        end
    end

    BurdJournals.Client._currentLanguage = newLanguage
end

BurdJournals.Client._pendingNewCharacterBaseline = false

function BurdJournals.Client.init()

    BurdJournals.Client.checkLanguageChange()

    local player = getPlayer()
    if player then
        local hoursAlive = player:getHoursSurvived() or 0

        pcall(function()
            BurdJournals.Client._lastKnownCharacterId = BurdJournals.getPlayerCharacterId(player)
        end)

        if BurdJournals.Client._pendingNewCharacterBaseline then
            BurdJournals.debugPrint("[BurdJournals] init: OnCreatePlayer is handling baseline, skipping")
            return
        end

        if hoursAlive < 0.1 then
            BurdJournals.debugPrint("[BurdJournals] init: New character detected (" .. hoursAlive .. " hours), deferring to OnCreatePlayer")
            return
        end

        local handlerId = nil
        local requestAfterDelay
        local ticksWaited = 0
        local maxWaitTicks = 60
        requestAfterDelay = function()
            ticksWaited = ticksWaited + 1

            local currentPlayer = getPlayer()
            if not currentPlayer then
                BurdJournals.debugPrint("[BurdJournals] init delayed: Player became invalid, aborting")
                BurdJournals.Client.unregisterTickHandler(handlerId)
                return
            end

            if ticksWaited >= maxWaitTicks then
                BurdJournals.debugPrint("[BurdJournals] init delayed: Max wait reached, forcing baseline request")
                BurdJournals.Client.unregisterTickHandler(handlerId)
                BurdJournals.Client.requestServerBaseline()
                return
            end

            if ticksWaited >= 10 then
                BurdJournals.Client.unregisterTickHandler(handlerId)

                if BurdJournals.Client._pendingNewCharacterBaseline then
                    BurdJournals.debugPrint("[BurdJournals] init delayed: OnCreatePlayer took over, aborting")
                    return
                end

                BurdJournals.debugPrint("[BurdJournals] init: Existing character (" .. hoursAlive .. " hours), requesting baseline from server")
                BurdJournals.Client.requestServerBaseline()
            end
        end
        handlerId = BurdJournals.Client.registerTickHandler(requestAfterDelay, "init_baseline_request")
    end
end

BurdJournals.Client.HaloColors = {
    XP_GAIN = {r=0.3, g=0.9, b=0.3, a=1},
    TRAIT_GAIN = {r=0.9, g=0.7, b=0.2, a=1},
    RECIPE_GAIN = {r=0.4, g=0.85, b=0.95, a=1},
    DISSOLVE = {r=0.7, g=0.5, b=0.3, a=1},
    ERROR = {r=0.9, g=0.3, b=0.3, a=1},
    INFO = {r=1, g=1, b=1, a=1},
}

function BurdJournals.Client.showHaloMessage(player, message, color)
    if not player then return end
    color = color or BurdJournals.Client.HaloColors.INFO

    if HaloTextHelper then
        -- Use the correct HaloTextHelper methods based on color type
        -- Note: Only use addGoodText/addBadText - addText has internal issues in B42
        if color == BurdJournals.Client.HaloColors.ERROR then
            -- Bad/error messages (red)
            if HaloTextHelper.addBadText then
                HaloTextHelper.addBadText(player, message)
            else
                player:Say(message)
            end
        else
            -- All other messages use green (good) text for visibility
            if HaloTextHelper.addGoodText then
                HaloTextHelper.addGoodText(player, message)
            else
                player:Say(message)
            end
        end
    else
        player:Say(message)
    end
end

function BurdJournals.Client.onServerCommand(module, command, args)
    -- Debug: Log ALL incoming server commands
    if module == "BurdJournals" then
        local logMsg = "[BurdJournals] Client received server command: " .. tostring(command)
        if command == "error" and args and args.message then
            logMsg = logMsg .. " - MESSAGE: '" .. tostring(args.message) .. "'"
        end
        print(logMsg)
    end

    if module ~= "BurdJournals" then return end

    local player = getPlayer()
    if not player then return end

    if command == "applyXP" then
        BurdJournals.Client.handleApplyXP(player, args)

    elseif command == "absorbSuccess" then
        BurdJournals.Client.handleAbsorbSuccess(player, args)

    elseif command == "journalDissolved" then
        BurdJournals.Client.handleJournalDissolved(player, args)

    elseif command == "grantTrait" then
        BurdJournals.Client.handleGrantTrait(player, args)

    elseif command == "traitAlreadyKnown" then
        BurdJournals.Client.handleTraitAlreadyKnown(player, args)

    elseif command == "skillMaxed" then
        BurdJournals.Client.handleSkillMaxed(player, args)

    elseif command == "claimSuccess" then
        BurdJournals.Client.handleClaimSuccess(player, args)

    elseif command == "logSuccess" then
        BurdJournals.Client.showHaloMessage(player, getText("UI_BurdJournals_SkillsRecorded") or "Skills recorded!", BurdJournals.Client.HaloColors.INFO)

    elseif command == "recordSuccess" then
        BurdJournals.Client.handleRecordSuccess(player, args)

    elseif command == "eraseSuccess" then
        BurdJournals.Client.handleEraseSuccess(player, args)

    elseif command == "cleanSuccess" then
        local message = args and args.message or (getText("UI_BurdJournals_JournalCleaned") or "Journal cleaned")
        BurdJournals.Client.showHaloMessage(player, message, BurdJournals.Client.HaloColors.INFO)

    elseif command == "convertSuccess" then
        local message = args and args.message or (getText("UI_BurdJournals_JournalRebound") or "Journal rebound")
        BurdJournals.Client.showHaloMessage(player, message, BurdJournals.Client.HaloColors.INFO)

    elseif command == "removeJournal" then
        BurdJournals.Client.handleRemoveJournal(player, args)

    elseif command == "journalInitialized" then
        BurdJournals.Client.handleJournalInitialized(player, args)

    elseif command == "recipeAlreadyKnown" then
        BurdJournals.Client.handleRecipeAlreadyKnown(player, args)

    elseif command == "baselineResponse" then
        BurdJournals.Client.handleBaselineResponse(player, args)

    elseif command == "baselineRegistered" then
        BurdJournals.Client.handleBaselineRegistered(player, args)

    elseif command == "allBaselinesCleared" then
        BurdJournals.Client.handleAllBaselinesCleared(player, args)

    elseif command == "error" then
        if args and args.message then
            BurdJournals.Client.showHaloMessage(player, args.message, BurdJournals.Client.HaloColors.ERROR)
        end
    end
end

BurdJournals.Client._pendingInitCallbacks = {}
BurdJournals.Client._initRequestIdCounter = 0

function BurdJournals.Client.requestJournalInitialization(journal, callback)
    if not journal then return end

    local itemType = journal:getFullType()
    local modData = journal:getModData()
    local clientUUID = modData and modData.BurdJournals and modData.BurdJournals.uuid

    BurdJournals.Client._initRequestIdCounter = BurdJournals.Client._initRequestIdCounter + 1
    local requestId = BurdJournals.Client._initRequestIdCounter

    if callback then
        BurdJournals.Client._pendingInitCallbacks[requestId] = callback
    end

    sendClientCommand(getPlayer(), "BurdJournals", "initializeJournal", {
        itemType = itemType,
        clientUUID = clientUUID,
        requestId = requestId
    })
end

function BurdJournals.Client.handleJournalInitialized(player, args)
    if not args then return end

    local requestId = args.requestId
    if requestId and BurdJournals.Client._pendingInitCallbacks[requestId] then
        local callback = BurdJournals.Client._pendingInitCallbacks[requestId]
        BurdJournals.Client._pendingInitCallbacks[requestId] = nil
        callback(args.uuid)
    elseif BurdJournals.Client.pendingInitCallback then

        local callback = BurdJournals.Client.pendingInitCallback
        BurdJournals.Client.pendingInitCallback = nil
        callback(args.uuid)
    end

    if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
        BurdJournals.UI.MainPanel.instance:refreshJournalData()
    end
end

function BurdJournals.Client.handleRecordSuccess(player, args)
    if not args then return end

    BurdJournals.debugPrint("[BurdJournals] Client: handleRecordSuccess received, newJournalId=" .. tostring(args.newJournalId) .. ", journalId=" .. tostring(args.journalId))

    local recordedItems = {}

    if args.skillNames then
        for _, skillName in ipairs(args.skillNames) do
            local displayName = BurdJournals.getPerkDisplayName(skillName) or skillName
            table.insert(recordedItems, displayName)
        end
    end

    if args.traitNames then
        for _, traitId in ipairs(args.traitNames) do
            local traitName = BurdJournals.getTraitDisplayName(traitId)
            table.insert(recordedItems, traitName)
        end
    end

    if args.recipeNames then
        for _, recipeName in ipairs(args.recipeNames) do
            local displayName = BurdJournals.getRecipeDisplayName and BurdJournals.getRecipeDisplayName(recipeName) or recipeName
            table.insert(recordedItems, displayName)
        end
    end

    local message
    if #recordedItems == 0 then
        message = getText("UI_BurdJournals_ProgressSaved") or "Progress saved!"
    elseif #recordedItems == 1 then
        message = string.format(getText("UI_BurdJournals_RecordedItem") or "Recorded %s", recordedItems[1])
    elseif #recordedItems <= 3 then
        message = string.format(getText("UI_BurdJournals_RecordedItems") or "Recorded %s", table.concat(recordedItems, ", "))
    else

        message = string.format(getText("UI_BurdJournals_RecordedItemsMore") or "Recorded %s, %s +%d more", recordedItems[1], recordedItems[2], #recordedItems - 2)
    end

    BurdJournals.Client.showHaloMessage(player, message, BurdJournals.Client.HaloColors.XP_GAIN)

    local journalId = args.newJournalId or args.journalId
    BurdJournals.debugPrint("[BurdJournals] Client: handleRecordSuccess - journalId=" .. tostring(journalId) .. ", has journalData=" .. tostring(args.journalData ~= nil))
    if journalId and args.journalData then
        BurdJournals.debugPrint("[BurdJournals] Client: Applying journal data from server for ID " .. tostring(journalId))

        if args.journalData.recipes then
            local recipeCount = 0
            for _ in pairs(args.journalData.recipes) do recipeCount = recipeCount + 1 end
            BurdJournals.debugPrint("[BurdJournals] Client: Server journalData contains " .. recipeCount .. " recipes")
        else
            BurdJournals.debugPrint("[BurdJournals] Client: Server journalData has NO recipes table")
        end
        local journal = BurdJournals.findItemById(player, journalId)
        if journal then
            local modData = journal:getModData()
            modData.BurdJournals = args.journalData
            BurdJournals.debugPrint("[BurdJournals] Client: Journal data applied successfully to found journal")
        else
            BurdJournals.debugPrint("[BurdJournals] Client: Could not find journal by ID to apply data")
        end
    elseif journalId and not args.journalData then
        BurdJournals.debugPrint("[BurdJournals] Client: WARNING - No journalData in server response (journal too large?)")
    end

    if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
        local panel = BurdJournals.UI.MainPanel.instance
        local panelJournalId = panel.journal and panel.journal:getID() or nil
        BurdJournals.debugPrint("[BurdJournals] Client: Panel exists, panel.journal ID=" .. tostring(panelJournalId) .. ", server journalId=" .. tostring(journalId))

        if args.newJournalId then
            BurdJournals.debugPrint("[BurdJournals] Client: Looking for new journal ID " .. tostring(args.newJournalId))
            local newJournal = BurdJournals.findItemById(player, args.newJournalId)
            if newJournal then
                BurdJournals.debugPrint("[BurdJournals] Client: Found new journal, updating panel reference")
                panel.journal = newJournal
                panel.pendingNewJournalId = nil

                if args.journalData then
                    local panelModData = panel.journal:getModData()
                    panelModData.BurdJournals = args.journalData
                    BurdJournals.debugPrint("[BurdJournals] Client: Applied journalData to new panel.journal")
                end
            else
                BurdJournals.debugPrint("[BurdJournals] Client: New journal NOT found in inventory yet!")

                panel.pendingNewJournalId = args.newJournalId
            end
        elseif journalId and panel.journal and panel.journal:getID() == journalId then

            if args.journalData then
                local panelModData = panel.journal:getModData()
                panelModData.BurdJournals = args.journalData
                BurdJournals.debugPrint("[BurdJournals] Client: Applied journalData to existing panel.journal (IDs match)")
            else
                BurdJournals.debugPrint("[BurdJournals] Client: IDs match but no journalData to apply")
            end
        else
            BurdJournals.debugPrint("[BurdJournals] Client: WARNING - Journal ID mismatch or missing! Panel has " .. tostring(panelJournalId) .. ", server sent " .. tostring(journalId))

            if journalId and args.journalData then
                local serverJournal = BurdJournals.findItemById(player, journalId)
                if serverJournal then
                    BurdJournals.debugPrint("[BurdJournals] Client: Found server's journal, updating panel reference")
                    panel.journal = serverJournal
                    local panelModData = panel.journal:getModData()
                    panelModData.BurdJournals = args.journalData
                end
            end
        end

        if panel.showFeedback then
            panel:showFeedback(message, {r=0.5, g=0.8, b=0.6})
        end

        if args.journalData then

            BurdJournals.debugPrint("[BurdJournals] Client: Calling populateRecordList with server journalData (skipping refreshJournalData)")
            if panel.populateRecordList then
                pcall(function() panel:populateRecordList(args.journalData) end)
            end
        else

            BurdJournals.debugPrint("[BurdJournals] Client: No server journalData, delaying refresh for modData sync")
            local ticksWaited = 0
            local maxWaitTicks = 5
            local delayedRefresh
            delayedRefresh = function()
                ticksWaited = ticksWaited + 1
                if ticksWaited >= maxWaitTicks then
                    Events.OnTick.Remove(delayedRefresh)

                    if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
                        local currentPanel = BurdJournals.UI.MainPanel.instance
                        if currentPanel.refreshJournalData then
                            BurdJournals.debugPrint("[BurdJournals] Client: Executing delayed refreshJournalData")
                            currentPanel:refreshJournalData()
                        end
                    end
                end
            end
            Events.OnTick.Add(delayedRefresh)
        end
    else
        BurdJournals.debugPrint("[BurdJournals] Client: No UI panel instance to update")
    end
end

function BurdJournals.Client.handleApplyXP(player, args)
    if not args or not args.skills then
        return
    end

    local mode = args.mode or "set"
    local totalXPGained = 0
    local skillsApplied = 0

    for skillName, data in pairs(args.skills) do

        local perk = BurdJournals.getPerkByName(skillName)

        if perk then
            local xpToApply = data.xp or 0
            local skillMode = data.mode or mode

            local beforeXP = player:getXp():getXP(perk)

            if skillMode == "add" then

                if sendAddXp then
                    sendAddXp(player, perk, xpToApply, true)
                    skillsApplied = skillsApplied + 1
                    totalXPGained = totalXPGained + xpToApply
                    BurdJournals.debugPrint("[BurdJournals] Applied +" .. tostring(xpToApply) .. " XP to " .. tostring(skillName))
                else

                    player:getXp():AddXP(perk, xpToApply)
                    local afterXP = player:getXp():getXP(perk)
                    totalXPGained = totalXPGained + (afterXP - beforeXP)
                    skillsApplied = skillsApplied + 1
                    BurdJournals.debugPrint("[BurdJournals] Fallback: Applied XP to " .. tostring(skillName))
                end
            else

                if xpToApply > beforeXP then
                    local xpDiff = xpToApply - beforeXP
                    if sendAddXp then
                        sendAddXp(player, perk, xpDiff, true)
                        BurdJournals.debugPrint("[BurdJournals] Set " .. tostring(skillName) .. " to " .. tostring(xpToApply) .. " (added " .. tostring(xpDiff) .. ")")
                    else
                        player:getXp():AddXP(perk, xpDiff)
                    end
                    totalXPGained = totalXPGained + xpDiff
                    skillsApplied = skillsApplied + 1
                end
            end
        end
    end

    if skillsApplied > 0 then

    end
end

function BurdJournals.Client.handleAbsorbSuccess(player, args)
    if not args then return end

    BurdJournals.debugPrint("[BurdJournals] Client: handleAbsorbSuccess received, journalId=" .. tostring(args.journalId))

    if args.skillName and args.xpGained then
        local displayName = BurdJournals.getPerkDisplayName(args.skillName)
        local xpGained = args.xpGained or 0

        -- DEBUG: Print what the server sent back
        print("[BurdJournals] Client: SERVER RETURNED xpGained=" .. tostring(xpGained) .. " for skill=" .. tostring(args.skillName))
        print("[BurdJournals] Client: SERVER DEBUG - baseXP=" .. tostring(args.debug_baseXP) .. ", journalMult=" .. tostring(args.debug_journalMult) .. ", bookMult=" .. tostring(args.debug_bookMult) .. ", receivedMult=" .. tostring(args.debug_receivedMult))

        local message = "+" .. BurdJournals.formatXP(xpGained) .. " " .. displayName
        BurdJournals.Client.showHaloMessage(player, message, BurdJournals.Client.HaloColors.XP_GAIN)

    elseif args.traitId then
        local traitName = BurdJournals.getTraitDisplayName(args.traitId)
        local message = string.format(getText("UI_BurdJournals_LearnedTrait") or "Learned: %s", traitName)
        BurdJournals.Client.showHaloMessage(player, message, BurdJournals.Client.HaloColors.TRAIT_GAIN)

        pcall(function()
            BurdJournals.safeAddTrait(player, args.traitId)
        end)
    elseif args.recipeName then
        local displayName = BurdJournals.getRecipeDisplayName(args.recipeName)
        local message = "+" .. displayName
        BurdJournals.Client.showHaloMessage(player, message, BurdJournals.Client.HaloColors.RECIPE_GAIN)

        pcall(function()
            player:learnRecipe(args.recipeName)
            BurdJournals.debugPrint("[BurdJournals] Client: Learned recipe '" .. args.recipeName .. "' on absorb")
        end)
    end

    if args.journalId and args.journalData then
        BurdJournals.debugPrint("[BurdJournals] Client: Applying journal data from server for absorb")

        local journal = BurdJournals.findItemById(player, args.journalId)
        if journal then
            local modData = journal:getModData()

            local claimedBefore = modData.BurdJournals and modData.BurdJournals.claimedSkills or {}
            BurdJournals.debugPrint("[BurdJournals] Client: claimedSkills BEFORE: " .. tostring(BurdJournals.countTable(claimedBefore)))

            modData.BurdJournals = args.journalData

            local claimedAfter = modData.BurdJournals and modData.BurdJournals.claimedSkills or {}
            BurdJournals.debugPrint("[BurdJournals] Client: claimedSkills AFTER: " .. tostring(BurdJournals.countTable(claimedAfter)))
            BurdJournals.debugPrint("[BurdJournals] Client: Journal data applied successfully for absorb")
        else
            BurdJournals.debugPrint("[BurdJournals] Client: Could not find journal to apply absorb data")
        end

        if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
            local panel = BurdJournals.UI.MainPanel.instance
            if panel.journal and panel.journal:getID() == args.journalId then
                local panelModData = panel.journal:getModData()
                BurdJournals.debugPrint("[BurdJournals] Client: Also updating panel.journal modData directly")
                panelModData.BurdJournals = args.journalData
            end
        end
    elseif args.journalId then

        local journal = BurdJournals.findItemById(player, args.journalId)
        if journal then
            if args.skillName then
                BurdJournals.claimSkill(journal, args.skillName)
            end
            if args.traitId then
                BurdJournals.claimTrait(journal, args.traitId)
            end
            if args.recipeName then
                BurdJournals.claimRecipe(journal, args.recipeName)
            end
        end

        if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
            local panel = BurdJournals.UI.MainPanel.instance
            if panel.journal and panel.journal:getID() == args.journalId then
                if args.skillName then
                    BurdJournals.claimSkill(panel.journal, args.skillName)
                end
                if args.traitId then
                    BurdJournals.claimTrait(panel.journal, args.traitId)
                end
                if args.recipeName then
                    BurdJournals.claimRecipe(panel.journal, args.recipeName)
                end
            end
        end
    end

    if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
        local panel = BurdJournals.UI.MainPanel.instance

        local panelJournalId = panel.journal and panel.journal:getID() or "nil"
        BurdJournals.debugPrint("[BurdJournals] Client: UI panel journal ID = " .. tostring(panelJournalId) .. ", server response journalId = " .. tostring(args.journalId))

        if panel.journal then
            local panelModData = panel.journal:getModData()
            local panelClaimed = panelModData.BurdJournals and panelModData.BurdJournals.claimedSkills or {}
            BurdJournals.debugPrint("[BurdJournals] Client: Panel's journal claimedSkills count = " .. tostring(BurdJournals.countTable(panelClaimed)))
        end

        panel:refreshAbsorptionList()
    end
end

function BurdJournals.Client.handleClaimSuccess(player, args)
    if not args then return end

    BurdJournals.debugPrint("[BurdJournals] Client: handleClaimSuccess received, journalId=" .. tostring(args.journalId))

    -- Handle skill XP claims
    local xpAmount = args.xpAdded or args.xpGained  -- Support both field names
    if args.skillName and xpAmount then
        local displayName = BurdJournals.getPerkDisplayName(args.skillName)
        local message = string.format(getText("UI_BurdJournals_ClaimedSkill") or "Claimed: %s (+%s XP)", displayName, BurdJournals.formatXP(xpAmount))
        BurdJournals.Client.showHaloMessage(player, message, BurdJournals.Client.HaloColors.XP_GAIN)

    elseif args.traitId then
        local traitName = BurdJournals.getTraitDisplayName(args.traitId)
        local message = string.format(getText("UI_BurdJournals_LearnedTrait") or "Learned: %s", traitName)
        BurdJournals.Client.showHaloMessage(player, message, BurdJournals.Client.HaloColors.TRAIT_GAIN)

        pcall(function()
            BurdJournals.safeAddTrait(player, args.traitId)
        end)
    elseif args.recipeName then
        local displayName = BurdJournals.getRecipeDisplayName(args.recipeName)
        local message = "+" .. displayName
        BurdJournals.Client.showHaloMessage(player, message, BurdJournals.Client.HaloColors.RECIPE_GAIN)

        pcall(function()
            player:learnRecipe(args.recipeName)
            BurdJournals.debugPrint("[BurdJournals] Client: Learned recipe '" .. args.recipeName .. "' on client")
        end)

    elseif args.statId then
        -- Handle stat absorption (zombie kills, hours survived, etc.)
        local statName = BurdJournals.getStatDisplayName and BurdJournals.getStatDisplayName(args.statId) or args.statId
        local value = args.value or 0
        local message = string.format(getText("UI_BurdJournals_StatClaimed") or "%s claimed!", statName)
        BurdJournals.Client.showHaloMessage(player, message, BurdJournals.Client.HaloColors.XP_GAIN)

        -- Apply the stat to the player on the client side
        pcall(function()
            if BurdJournals.applyStatAbsorption then
                local applied = BurdJournals.applyStatAbsorption(player, args.statId, value)
                if applied then
                    BurdJournals.debugPrint("[BurdJournals] Client: Applied stat '" .. args.statId .. "' = " .. tostring(value))
                else
                    BurdJournals.debugPrint("[BurdJournals] Client: Failed to apply stat '" .. args.statId .. "'")
                end
            end
        end)
    end

    if args.journalId and args.journalData then
        BurdJournals.debugPrint("[BurdJournals] Client: Applying journal data from server for claimSuccess")
        local journal = BurdJournals.findItemById(player, args.journalId)
        if journal then
            local modData = journal:getModData()
            modData.BurdJournals = args.journalData
            BurdJournals.debugPrint("[BurdJournals] Client: Journal data applied successfully for claimSuccess")
        else
            BurdJournals.debugPrint("[BurdJournals] Client: Could not find journal to apply claimSuccess data")
        end

        if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
            local panel = BurdJournals.UI.MainPanel.instance
            if panel.journal and panel.journal:getID() == args.journalId then
                local panelModData = panel.journal:getModData()
                BurdJournals.debugPrint("[BurdJournals] Client: Also updating panel.journal modData directly for claimSuccess")
                panelModData.BurdJournals = args.journalData
            end
        end
    end

    if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
        local panel = BurdJournals.UI.MainPanel.instance

        BurdJournals.debugPrint("[BurdJournals] Client: Refreshing UI for claimSuccess")
        if panel.refreshJournalData then
            panel:refreshJournalData()
        elseif panel.refreshAbsorptionList then
            panel:refreshAbsorptionList()
        end
    end
end

function BurdJournals.Client.handleEraseSuccess(player, args)
    if not args then return end

    BurdJournals.debugPrint("[BurdJournals] Client: handleEraseSuccess received, journalId=" .. tostring(args.journalId))

    -- Show the halo message
    BurdJournals.Client.showHaloMessage(player, getText("UI_BurdJournals_JournalErased") or "Entry erased", BurdJournals.Client.HaloColors.INFO)

    -- Apply updated journal data from server
    if args.journalId and args.journalData then
        BurdJournals.debugPrint("[BurdJournals] Client: Applying journal data from server for eraseSuccess")
        local journal = BurdJournals.findItemById(player, args.journalId)
        if journal then
            local modData = journal:getModData()
            modData.BurdJournals = args.journalData
            BurdJournals.debugPrint("[BurdJournals] Client: Journal data applied successfully for eraseSuccess")
        else
            BurdJournals.debugPrint("[BurdJournals] Client: Could not find journal to apply eraseSuccess data")
        end

        -- Also update the panel's journal if it matches
        if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
            local panel = BurdJournals.UI.MainPanel.instance
            if panel.journal and panel.journal:getID() == args.journalId then
                local panelModData = panel.journal:getModData()
                BurdJournals.debugPrint("[BurdJournals] Client: Also updating panel.journal modData directly for eraseSuccess")
                panelModData.BurdJournals = args.journalData
            end
        end
    end

    -- Refresh the UI to reflect the erased entry
    if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
        local panel = BurdJournals.UI.MainPanel.instance

        BurdJournals.debugPrint("[BurdJournals] Client: Refreshing UI for eraseSuccess")
        if panel.refreshCurrentList then
            panel:refreshCurrentList()
        elseif panel.refreshJournalData then
            panel:refreshJournalData()
        end
    end
end

function BurdJournals.Client.handleJournalDissolved(player, args)
    -- Debug info from skill absorption before dissolution
    if args and args.skillName and args.xpGained then
        print("[BurdJournals] Client: DISSOLVED - SERVER RETURNED xpGained=" .. tostring(args.xpGained) .. " for skill=" .. tostring(args.skillName))
        print("[BurdJournals] Client: DISSOLVED - SERVER DEBUG - baseXP=" .. tostring(args.debug_baseXP) .. ", journalMult=" .. tostring(args.debug_journalMult) .. ", bookMult=" .. tostring(args.debug_bookMult) .. ", receivedMult=" .. tostring(args.debug_receivedMult))
    end

    local message = args and args.message or BurdJournals.getRandomDissolutionMessage()

    if player and player.Say then
        player:Say(message)
    end

    pcall(function()
        player:getEmitter():playSound("PaperRip")
    end)

    if args and args.journalId then
        local journal = BurdJournals.findItemById(player, args.journalId)
        if journal then

            local container = journal:getContainer()
            if container then
                container:Remove(journal)
            end
            player:getInventory():Remove(journal)
        end
    end

    if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
        BurdJournals.UI.MainPanel.instance:onClose()
    end

end

function BurdJournals.Client.handleRemoveJournal(player, args)

    if not args or not args.journalUUID then

        return
    end

    local journalUUID = args.journalUUID

    local journal = BurdJournals.findJournalByUUID(player, journalUUID)
    if journal then

        player:getInventory():Remove(journal)

    else
    end
end

function BurdJournals.Client.handleGrantTrait(player, args)
    if not args or not args.traitId then return end

    local traitId = args.traitId

    local traitName = BurdJournals.getTraitDisplayName(traitId)

    local success, err = pcall(function()
        local characterTrait = nil

        if CharacterTrait and CharacterTrait.get and ResourceLocation and ResourceLocation.of then

            local resourceLoc = "base:" .. string.lower(traitId)

            local ok, result = pcall(function()
                return CharacterTrait.get(ResourceLocation.of(resourceLoc))
            end)
            if ok and result then
                characterTrait = result
            end

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

            player:getCharacterTraits():add(characterTrait)

            if player.modifyTraitXPBoost then
                player:modifyTraitXPBoost(characterTrait, false)

            end

            if SyncXp then
                SyncXp(player)

            else
            end

            local hasNow = player:hasTrait(characterTrait)
        else
        end
    end)

    if not success then
        BurdJournals.debugPrint("[BurdJournals] Client: ERROR in trait grant: " .. tostring(err))
    end

    local message = string.format(getText("UI_BurdJournals_LearnedTrait") or "Learned: %s", traitName)
    BurdJournals.Client.showHaloMessage(player, message, BurdJournals.Client.HaloColors.TRAIT_GAIN)

    if args.journalId and args.journalData then
        BurdJournals.debugPrint("[BurdJournals] Client: Applying journal data from server for grantTrait")
        local journal = BurdJournals.findItemById(player, args.journalId)
        if journal then
            local modData = journal:getModData()
            modData.BurdJournals = args.journalData
            BurdJournals.debugPrint("[BurdJournals] Client: Journal data applied successfully for grantTrait")
        else
            BurdJournals.debugPrint("[BurdJournals] Client: Could not find journal to apply grantTrait data")
        end

        if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
            local panel = BurdJournals.UI.MainPanel.instance
            if panel.journal and panel.journal:getID() == args.journalId then
                local panelModData = panel.journal:getModData()
                BurdJournals.debugPrint("[BurdJournals] Client: Also updating panel.journal modData directly for grantTrait")
                panelModData.BurdJournals = args.journalData
            end
        end
    elseif args.journalId then

        local journal = BurdJournals.findItemById(player, args.journalId)
        if journal then
            BurdJournals.claimTrait(journal, traitId)
        end

        if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
            local panel = BurdJournals.UI.MainPanel.instance
            if panel.journal and panel.journal:getID() == args.journalId then
                BurdJournals.claimTrait(panel.journal, traitId)
            end
        end
    end

    if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
        BurdJournals.UI.MainPanel.instance:refreshAbsorptionList()
    end
end

function BurdJournals.Client.handleTraitAlreadyKnown(player, args)
    if not args or not args.traitId then return end

    local traitId = args.traitId

    local traitName = BurdJournals.getTraitDisplayName(traitId)

    player:Say(string.format(getText("UI_BurdJournals_AlreadyKnowTrait") or "Already know: %s", traitName))

    if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
        BurdJournals.UI.MainPanel.instance:refreshAbsorptionList()
    end
end

function BurdJournals.Client.handleSkillMaxed(player, args)
    if not args or not args.skillName then return end

    local skillName = args.skillName
    local displayName = BurdJournals.getPerkDisplayName(skillName)

    player:Say(string.format(getText("UI_BurdJournals_SkillAlreadyMaxedMsg") or "%s is already maxed!", displayName))

    if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
        BurdJournals.UI.MainPanel.instance:refreshAbsorptionList()
    end
end

function BurdJournals.Client.handleRecipeAlreadyKnown(player, args)
    if not args or not args.recipeName then return end

    local recipeName = args.recipeName
    local displayName = BurdJournals.getRecipeDisplayName(recipeName)

    player:Say(string.format(getText("UI_BurdJournals_AlreadyKnowRecipe") or "Already know: %s", displayName))

    if args.journalId and args.journalData then
        local journal = BurdJournals.findItemById(player, args.journalId)
        if journal then
            local modData = journal:getModData()
            modData.BurdJournals = args.journalData
        end

        if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
            local panel = BurdJournals.UI.MainPanel.instance
            if panel.journal and panel.journal:getID() == args.journalId then
                local panelModData = panel.journal:getModData()
                panelModData.BurdJournals = args.journalData
            end
        end
    end

    if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
        local panel = BurdJournals.UI.MainPanel.instance
        if panel.refreshJournalData then
            panel:refreshJournalData()
        elseif panel.refreshAbsorptionList then
            panel:refreshAbsorptionList()
        end
    end
end

function BurdJournals.Client.calculateProfessionBaseline(player)
    if not player then return {}, {} end

    local skillBaseline = {}
    local traitBaseline = {}

    -- Track level ADJUSTMENTS (can be positive or negative)
    local levelAdjustments = {}

    local desc = player:getDescriptor()
    if not desc then
        print("[BurdJournals] calculateProfessionBaseline: No descriptor found!")
        return skillBaseline, traitBaseline
    end

    local playerProfessionID = desc:getCharacterProfession()
    BurdJournals.debugPrint("[BurdJournals] calculateProfessionBaseline: profession=" .. tostring(playerProfessionID))

    if playerProfessionID and CharacterProfessionDefinition then
        local profDef = CharacterProfessionDefinition.getCharacterProfessionDefinition(playerProfessionID)
        if profDef then

            local profXpBoost = transformIntoKahluaTable(profDef:getXpBoosts())
            if profXpBoost then
                for perk, level in pairs(profXpBoost) do

                    local perkId = tostring(perk)
                    local levelNum = tonumber(tostring(level))
                    if levelNum and levelNum ~= 0 then
                        levelAdjustments[perkId] = (levelAdjustments[perkId] or 0) + levelNum
                        BurdJournals.debugPrint("[BurdJournals] Profession grants " .. perkId .. " " .. (levelNum > 0 and "+" or "") .. levelNum .. " levels")
                    end
                end
            end

            local grantedTraits = profDef:getGrantedTraits()
            if grantedTraits then
                for i = 0, grantedTraits:size() - 1 do
                    local traitName = tostring(grantedTraits:get(i))
                    traitBaseline[traitName] = true
                    BurdJournals.debugPrint("[BurdJournals] Profession grants trait: " .. traitName)
                end
            end
        end
    end

    local playerTraits = player:getCharacterTraits()
    if playerTraits and playerTraits.getKnownTraits then
        local knownTraits = playerTraits:getKnownTraits()
        for i = 0, knownTraits:size() - 1 do
            local traitTrait = knownTraits:get(i)
            local traitId = tostring(traitTrait)

            if CharacterTraitDefinition then
                local traitDef = CharacterTraitDefinition.getCharacterTraitDefinition(traitTrait)
                if traitDef then
                    local traitXpBoost = transformIntoKahluaTable(traitDef:getXpBoosts())
                    local hasSkillBonus = false
                    if traitXpBoost then
                        for perk, level in pairs(traitXpBoost) do
                            local perkId = tostring(perk)
                            local levelNum = tonumber(tostring(level))
                            if levelNum and levelNum ~= 0 then
                                levelAdjustments[perkId] = (levelAdjustments[perkId] or 0) + levelNum
                                BurdJournals.debugPrint("[BurdJournals] Trait " .. traitId .. " grants " .. perkId .. " " .. (levelNum > 0 and "+" or "") .. levelNum .. " levels")
                                hasSkillBonus = true
                            end
                        end
                    end

                    if hasSkillBonus then
                        traitBaseline[traitId] = true
                        BurdJournals.debugPrint("[BurdJournals] Trait marked as baseline (has skill bonus): " .. traitId)
                    end
                end
            end
        end
    end

    -- IMPORTANT: Fitness and Strength start at Level 5 by default in PZ
    -- Other skills start at Level 0. We need to account for base levels + adjustments.
    local BASE_PASSIVE_LEVEL = 5  -- PZ default starting level for Fitness/Strength
    local passiveSkills = { Fitness = true, Strength = true }

    for perkId, adjustment in pairs(levelAdjustments) do
        local perk = Perks[perkId]
        if perk then
            local skillName = BurdJournals.mapPerkIdToSkillName(perkId)
            if skillName then
                -- Calculate final starting level
                local baseLevel = passiveSkills[skillName] and BASE_PASSIVE_LEVEL or 0
                local finalLevel = math.max(0, math.min(10, baseLevel + adjustment))

                local xp = perk:getTotalXpForLevel(finalLevel)
                if xp and xp > 0 then
                    skillBaseline[skillName] = xp
                    BurdJournals.debugPrint("[BurdJournals] Baseline: " .. skillName .. " = " .. xp .. " XP (base Lv" .. baseLevel .. " + adj " .. adjustment .. " = Lv" .. finalLevel .. ")")
                end
            end
        else
            print("[BurdJournals] WARNING: Unknown perk ID: " .. perkId)
        end
    end

    -- Also set baseline for passive skills that have no adjustments but still have base Level 5
    for skillName, _ in pairs(passiveSkills) do
        if not skillBaseline[skillName] then
            local perkId = BurdJournals.SKILL_TO_PERK and BurdJournals.SKILL_TO_PERK[skillName] or skillName
            local perk = Perks[perkId]
            if perk then
                local xp = perk:getTotalXpForLevel(BASE_PASSIVE_LEVEL)
                if xp and xp > 0 then
                    skillBaseline[skillName] = xp
                    BurdJournals.debugPrint("[BurdJournals] Baseline: " .. skillName .. " = " .. xp .. " XP (default base Lv" .. BASE_PASSIVE_LEVEL .. ")")
                end
            end
        end
    end

    BurdJournals.debugPrint("[BurdJournals] Final skill baseline:")
    for skill, xp in pairs(skillBaseline) do
        BurdJournals.debugPrint("[BurdJournals]   " .. skill .. " = " .. xp .. " XP")
    end

    return skillBaseline, traitBaseline
end

function BurdJournals.Client.captureBaseline(player, isNewCharacter)
    if not player then return end

    local modData = player:getModData()
    if not modData.BurdJournals then modData.BurdJournals = {} end

    if modData.BurdJournals.baselineCaptured then
        local storedVersion = modData.BurdJournals.baselineVersion or 0
        if storedVersion >= BurdJournals.Client.BASELINE_VERSION then

            BurdJournals.debugPrint("[BurdJournals] Baseline already captured (v" .. storedVersion .. "), skipping")
            return
        else

            BurdJournals.debugPrint("[BurdJournals] Baseline version mismatch: stored v" .. storedVersion .. " vs current v" .. BurdJournals.Client.BASELINE_VERSION)
            local hoursAlive = player:getHoursSurvived() or 0
            if hoursAlive > 1 then
                -- Existing character with outdated baseline - update version flag
                -- Also clear recipe baseline to fix issue where recipes were incorrectly baselined
                -- (recipes should never be baselined for existing characters)
                BurdJournals.debugPrint("[BurdJournals] Existing character - updating version flag and clearing recipe baseline")
                modData.BurdJournals.baselineVersion = BurdJournals.Client.BASELINE_VERSION
                modData.BurdJournals.recipeBaseline = {}  -- Clear incorrectly captured recipe baseline
                if player.transmitModData then
                    player:transmitModData()
                end
                return
            end

            BurdJournals.debugPrint("[BurdJournals] New character with outdated baseline - recalculating")
            modData.BurdJournals.baselineCaptured = false
            modData.BurdJournals.skillBaseline = nil
            modData.BurdJournals.traitBaseline = nil
            modData.BurdJournals.recipeBaseline = nil
        end
    end

    if isNewCharacter then
        local hoursAlive = player:getHoursSurvived() or 0
        if hoursAlive > 1 then
            print("[BurdJournals] WARNING: isNewCharacter=true but player has " .. hoursAlive .. " hours survived!")
            BurdJournals.debugPrint("[BurdJournals] Treating as existing save to avoid incorrect baseline capture")
            isNewCharacter = false
        end
    end

    if isNewCharacter then

        BurdJournals.debugPrint("[BurdJournals] Capturing baseline for NEW character (direct capture)")
        modData.BurdJournals.skillBaseline = {}
        local allowedSkills = BurdJournals.getAllowedSkills()
        for _, skillName in ipairs(allowedSkills) do
            local perk = BurdJournals.getPerkByName(skillName)
            if perk then
                local xp = player:getXp():getXP(perk)
                if xp > 0 then
                    modData.BurdJournals.skillBaseline[skillName] = xp
                end
            end
        end

        modData.BurdJournals.traitBaseline = {}
        local traits = BurdJournals.collectPlayerTraits(player, false)
        for traitId, _ in pairs(traits) do
            modData.BurdJournals.traitBaseline[traitId] = true
        end

        modData.BurdJournals.recipeBaseline = {}
        local recipes = BurdJournals.collectPlayerMagazineRecipes(player, false)
        for recipeName, _ in pairs(recipes) do
            modData.BurdJournals.recipeBaseline[recipeName] = true
        end
    else

        BurdJournals.debugPrint("[BurdJournals] Calculating baseline for EXISTING save (retroactive)")
        local calcSkills, calcTraits = BurdJournals.Client.calculateProfessionBaseline(player)
        modData.BurdJournals.skillBaseline = calcSkills
        modData.BurdJournals.traitBaseline = calcTraits

        modData.BurdJournals.recipeBaseline = {}
    end

    modData.BurdJournals.baselineCaptured = true
    modData.BurdJournals.baselineVersion = BurdJournals.Client.BASELINE_VERSION

    modData.BurdJournals.steamId = BurdJournals.getPlayerSteamId(player)
    modData.BurdJournals.characterId = BurdJournals.getPlayerCharacterId(player)

    local method = isNewCharacter and "direct capture" or "calculated from profession/traits"
    local recipeCount = BurdJournals.countTable(modData.BurdJournals.recipeBaseline or {})
    BurdJournals.debugPrint("[BurdJournals] Baseline captured (" .. method .. "): " ..
          tostring(BurdJournals.countTable(modData.BurdJournals.skillBaseline)) .. " skills, " ..
          tostring(BurdJournals.countTable(modData.BurdJournals.traitBaseline)) .. " traits, " ..
          tostring(recipeCount) .. " recipes")

    for skillName, xp in pairs(modData.BurdJournals.skillBaseline) do
        BurdJournals.debugPrint("[BurdJournals]   Baseline skill: " .. skillName .. " = " .. tostring(xp) .. " XP")
    end
    for traitId, _ in pairs(modData.BurdJournals.traitBaseline) do
        BurdJournals.debugPrint("[BurdJournals]   Baseline trait: " .. traitId)
    end
    for recipeName, _ in pairs(modData.BurdJournals.recipeBaseline or {}) do
        BurdJournals.debugPrint("[BurdJournals]   Baseline recipe: " .. recipeName)
    end

    if player.transmitModData then
        player:transmitModData()
        BurdJournals.debugPrint("[BurdJournals] Player modData transmitted for persistence")
    end

    BurdJournals.Client.registerBaselineWithServer(player)
end

function BurdJournals.Client.forceRecalculateBaseline()
    local player = getPlayer()
    if not player then
        BurdJournals.debugPrint("[BurdJournals] No player found")
        return
    end

    local modData = player:getModData()
    if modData.BurdJournals then
        modData.BurdJournals.baselineCaptured = nil
        modData.BurdJournals.skillBaseline = nil
        modData.BurdJournals.traitBaseline = nil
    end

    BurdJournals.debugPrint("[BurdJournals] Baseline cleared, recalculating...")
    BurdJournals.Client.captureBaseline(player, false)
    BurdJournals.debugPrint("[BurdJournals] Baseline recalculated from profession/traits")
end

BurdJournals.Client._awaitingServerBaseline = false

function BurdJournals.Client.requestServerBaseline()
    local player = getPlayer()
    if not player then return end

    BurdJournals.Client._awaitingServerBaseline = true
    BurdJournals.debugPrint("[BurdJournals] Requesting cached baseline from server...")

    sendClientCommand(player, "BurdJournals", "requestBaseline", {})
end

function BurdJournals.Client.registerBaselineWithServer(player)
    if not player then return end

    local modData = player:getModData()
    if not modData.BurdJournals or not modData.BurdJournals.baselineCaptured then
        BurdJournals.debugPrint("[BurdJournals] No baseline to register with server")
        return
    end

    local characterId = BurdJournals.getPlayerCharacterId(player)
    local steamId = BurdJournals.getPlayerSteamId(player)

    local descriptor = player:getDescriptor()
    local characterName = "Unknown"
    if descriptor then
        local forename = descriptor:getForename() or "Unknown"
        local surname = descriptor:getSurname() or ""
        characterName = forename .. " " .. surname
    end

    BurdJournals.debugPrint("[BurdJournals] Registering baseline with server for: " .. characterId)

    sendClientCommand(player, "BurdJournals", "registerBaseline", {
        characterId = characterId,
        steamId = steamId,
        characterName = characterName,
        skillBaseline = modData.BurdJournals.skillBaseline or {},
        traitBaseline = modData.BurdJournals.traitBaseline or {},
        recipeBaseline = modData.BurdJournals.recipeBaseline or {}
    })
end

function BurdJournals.Client.handleBaselineResponse(player, args)
    BurdJournals.Client._awaitingServerBaseline = false

    if not args then
        print("[BurdJournals] ERROR: No args in baselineResponse")
        return
    end

    if args.found then

        BurdJournals.debugPrint("[BurdJournals] Received cached baseline from server for: " .. tostring(args.characterId))

        local modData = player:getModData()
        if not modData.BurdJournals then modData.BurdJournals = {} end

        modData.BurdJournals.skillBaseline = args.skillBaseline or {}
        modData.BurdJournals.traitBaseline = args.traitBaseline or {}
        modData.BurdJournals.recipeBaseline = args.recipeBaseline or {}
        modData.BurdJournals.baselineCaptured = true
        modData.BurdJournals.baselineVersion = BurdJournals.Client.BASELINE_VERSION
        modData.BurdJournals.fromServerCache = true

        BurdJournals.debugPrint("[BurdJournals] Applied server-cached baseline: " ..
              tostring(BurdJournals.countTable(modData.BurdJournals.skillBaseline)) .. " skills, " ..
              tostring(BurdJournals.countTable(modData.BurdJournals.traitBaseline)) .. " traits, " ..
              tostring(BurdJournals.countTable(modData.BurdJournals.recipeBaseline or {})) .. " recipes")

        for skillName, xp in pairs(modData.BurdJournals.skillBaseline) do
            BurdJournals.debugPrint("[BurdJournals]   Cached skill: " .. skillName .. " = " .. tostring(xp) .. " XP")
        end
        for traitId, _ in pairs(modData.BurdJournals.traitBaseline) do
            BurdJournals.debugPrint("[BurdJournals]   Cached trait: " .. traitId)
        end

        if player.transmitModData then
            player:transmitModData()
        end
    else

        BurdJournals.debugPrint("[BurdJournals] No cached baseline on server for: " .. tostring(args.characterId))

        local hoursAlive = player:getHoursSurvived() or 0
        local isNewCharacter = hoursAlive < 0.1

        if isNewCharacter then

            BurdJournals.debugPrint("[BurdJournals] New character without server cache - OnCreatePlayer will handle")
        else

            BurdJournals.debugPrint("[BurdJournals] Existing character (" .. hoursAlive .. " hours) has no server cache")
            BurdJournals.debugPrint("[BurdJournals] NOT migrating baseline - character will have no baseline restrictions")
            BurdJournals.debugPrint("[BurdJournals] Baseline restrictions will apply to new characters only")

            local modData = player:getModData()
            if modData.BurdJournals then
                modData.BurdJournals.baselineCaptured = false
                modData.BurdJournals.skillBaseline = nil
                modData.BurdJournals.traitBaseline = nil
                modData.BurdJournals.recipeBaseline = nil
            end
        end
    end
end

function BurdJournals.Client.handleBaselineRegistered(player, args)
    if not args then return end

    if args.success then
        BurdJournals.debugPrint("[BurdJournals] Baseline successfully registered with server for: " .. tostring(args.characterId))
    elseif args.alreadyExisted then
        BurdJournals.debugPrint("[BurdJournals] Server already had baseline for: " .. tostring(args.characterId) .. " (ignored our registration)")
    else
        print("[BurdJournals] Failed to register baseline with server")
    end
end

-- Handler for server-wide baseline clear (admin command response)
function BurdJournals.Client.handleAllBaselinesCleared(player, args)
    if not args then return end

    local clearedCount = args.clearedCount or 0
    local message = getText("UI_BurdJournals_AllBaselinesCleared") or "Server baseline cache cleared!"
    message = message .. " (" .. clearedCount .. " entries)"

    print("[BurdJournals] ADMIN: Server confirmed all baselines cleared - " .. clearedCount .. " entries removed")

    -- Show feedback to admin
    BurdJournals.Client.showHaloMessage(player, message, BurdJournals.Client.HaloColors.INFO)

    -- Update any open panel - refresh the list and show feedback
    if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
        local panel = BurdJournals.UI.MainPanel.instance
        -- Refresh the skill/trait/recipe list to reflect cleared baselines
        if panel.populateRecordList then
            panel:populateRecordList()
        end
        if panel.showFeedback then
            panel:showFeedback(message, {r=0.3, g=1, b=0.5})
        end
    end
end

function BurdJournals.Client.onCreatePlayer(playerIndex)
    local player = getSpecificPlayer(playerIndex)
    if player then

        local hoursAlive = player:getHoursSurvived() or 0
        if hoursAlive > 0.1 then

            BurdJournals.debugPrint("[BurdJournals] onCreatePlayer: Skipping (existing character with " .. hoursAlive .. " hours)")
            return
        end

        BurdJournals.Client._pendingNewCharacterBaseline = true
        BurdJournals.debugPrint("[BurdJournals] onCreatePlayer: Set pending flag, will capture baseline for new character")

        pcall(function()
            BurdJournals.Client._lastKnownCharacterId = BurdJournals.getPlayerCharacterId(player)
        end)

        local modData = player:getModData()
        if modData then
            if not modData.BurdJournals then
                modData.BurdJournals = {}
            end

            modData.BurdJournals.baselineCaptured = false
            modData.BurdJournals.skillBaseline = nil
            modData.BurdJournals.traitBaseline = nil
            modData.BurdJournals.recipeBaseline = nil
            -- Clear bypass flag on new character - baseline will be enforced normally
            modData.BurdJournals.baselineBypassed = nil
        end

        local handlerId = nil
        local captureAfterDelay
        local ticksWaited = 0
        local maxWaitTicks = 300
        local minWaitTicks = 30

        captureAfterDelay = function()
            ticksWaited = ticksWaited + 1

            local currentPlayer = getSpecificPlayer(playerIndex)
            if not currentPlayer then
                BurdJournals.debugPrint("[BurdJournals] onCreatePlayer: Player became invalid during wait, aborting baseline capture")
                BurdJournals.Client.unregisterTickHandler(handlerId)
                BurdJournals.Client._pendingNewCharacterBaseline = false
                return
            end

            if ticksWaited >= minWaitTicks then

                local hasTraits = false
                pcall(function()
                    local charTraits = currentPlayer:getCharacterTraits()
                    if charTraits then
                        local knownTraits = charTraits:getKnownTraits()
                        if knownTraits and knownTraits:size() > 0 then
                            hasTraits = true
                        end
                    end
                end)

                if hasTraits or ticksWaited >= maxWaitTicks then
                    BurdJournals.Client.unregisterTickHandler(handlerId)

                    BurdJournals.Client._pendingNewCharacterBaseline = false
                    if not hasTraits then
                        print("[BurdJournals] WARNING: Max wait reached (" .. ticksWaited .. " ticks), capturing baseline without full traits")
                    else
                        BurdJournals.debugPrint("[BurdJournals] Traits loaded after " .. ticksWaited .. " ticks, capturing baseline")
                    end

                    BurdJournals.Client.captureBaseline(currentPlayer, true)
                end
            end
        end
        handlerId = BurdJournals.Client.registerTickHandler(captureAfterDelay, "onCreatePlayer_baseline")
    end
end

function BurdJournals.Client.onPlayerDeath(player)

    BurdJournals.Client.cleanupAllTickHandlers()

    if BurdJournals.UI and BurdJournals.UI.MainPanel then

        pcall(function() Events.OnTick.Remove(BurdJournals.UI.MainPanel.onLearningTickStatic) end)
        pcall(function() Events.OnTick.Remove(BurdJournals.UI.MainPanel.onRecordingTickStatic) end)
        pcall(function() Events.OnTick.Remove(BurdJournals.UI.MainPanel.onPendingJournalRetryStatic) end)

        if BurdJournals.UI.MainPanel.instance then
            pcall(function()
                BurdJournals.UI.MainPanel.instance:setVisible(false)
                BurdJournals.UI.MainPanel.instance:removeFromUIManager()
                BurdJournals.UI.MainPanel.instance = nil
            end)
        end
    end

    if ISTimedActionQueue and player then
        pcall(function() ISTimedActionQueue.clear(player) end)
    end

    if player then

        local characterId = BurdJournals.Client._lastKnownCharacterId
        if not characterId then

            pcall(function()
                characterId = BurdJournals.getPlayerCharacterId(player)
            end)
        end

        if characterId then
            BurdJournals.debugPrint("[BurdJournals] Notifying server to delete cached baseline for: " .. characterId)
            pcall(function()
                sendClientCommand(player, "BurdJournals", "deleteBaseline", {
                    characterId = characterId
                })
            end)
        else
            print("[BurdJournals] WARNING: Could not determine character ID for baseline deletion")
        end

        pcall(function()
            local modData = player:getModData()
            if modData and modData.BurdJournals then
                modData.BurdJournals.baselineCaptured = false
                modData.BurdJournals.skillBaseline = nil
                modData.BurdJournals.traitBaseline = nil
                modData.BurdJournals.recipeBaseline = nil
                BurdJournals.debugPrint("[BurdJournals] Local baseline cleared for respawn")
            end
        end)
    end

    BurdJournals.Client._lastKnownCharacterId = nil

    BurdJournals.Client._pendingNewCharacterBaseline = false

    BurdJournals.debugPrint("[BurdJournals] Player death cleanup completed")
end

Events.OnServerCommand.Add(BurdJournals.Client.onServerCommand)
Events.OnGameStart.Add(BurdJournals.Client.init)
Events.OnCreatePlayer.Add(BurdJournals.Client.onCreatePlayer)
Events.OnPlayerDeath.Add(BurdJournals.Client.onPlayerDeath)

if Events.EveryOneMinute then
    Events.EveryOneMinute.Add(BurdJournals.Client.checkLanguageChange)
end

-- Restore custom journal names when inventory UI refreshes (MP fix)
-- This catches cases where item display names reset during MP item transfers
BurdJournals.Client.restoreJournalNamesInContainer = function(container)
    if not container then return end
    
    local items = container:getItems()
    if not items then return end
    
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            local fullType = item:getFullType()
            if fullType and fullType:find("^BurdJournals%.") then
                local modData = item:getModData()
                if modData.BurdJournals and modData.BurdJournals.customName then
                    if item:getName() ~= modData.BurdJournals.customName then
                        BurdJournals.updateJournalName(item)
                    end
                end
            end
        end
    end
end

if Events.OnRefreshInventoryWindowContainers then
    Events.OnRefreshInventoryWindowContainers.Add(function(inventoryUI, reason)
        local player = getPlayer()
        if not player then return end
        
        -- Check main inventory
        local inventory = player:getInventory()
        if inventory then
            BurdJournals.Client.restoreJournalNamesInContainer(inventory)
        end
        
        -- Check equipped bags
        local backpack = player:getClothingItem_Back()
        if backpack and backpack:getInventory() then
            BurdJournals.Client.restoreJournalNamesInContainer(backpack:getInventory())
        end
    end)
end

-- Chat command handler for /clearbaseline
-- NOTE: This command requires admin access in MP to prevent exploit
function BurdJournals.Client.onChatCommand(command)
    if not command then return end

    local cmd = string.lower(command)
    if cmd == "/clearbaseline" or cmd == "/resetbaseline" or cmd == "/journalreset" then
        local player = getPlayer()
        if not player then return true end

        -- In MP, require admin access to prevent baseline bypass exploit
        -- In SP, allow freely since it's the player's own game
        if isClient() and not isCoopHost() then
            local accessLevel = player:getAccessLevel()
            if not accessLevel or accessLevel == "None" then
                player:Say(getText("UI_BurdJournals_AdminOnly") or "This command requires admin access.")
                return true
            end
        end

        print("[BurdJournals] Command: Clearing baseline for player...")

        -- Clear local player baseline data AND set bypass flag
        local modData = player:getModData()
        if not modData.BurdJournals then
            modData.BurdJournals = {}
        end

        modData.BurdJournals.baselineCaptured = nil
        modData.BurdJournals.skillBaseline = nil
        modData.BurdJournals.traitBaseline = nil
        modData.BurdJournals.recipeBaseline = nil
        modData.BurdJournals.baselineVersion = nil

        -- Set bypass flag - this makes restrictions not apply to this character immediately
        modData.BurdJournals.baselineBypassed = true

        -- Send command to server to delete cached baseline
        if isClient() then
            local characterId = BurdJournals.getPlayerCharacterId and BurdJournals.getPlayerCharacterId(player) or nil
            sendClientCommand(player, "BurdJournals", "deleteBaseline", {
                characterId = characterId
            })
        end

        -- Do NOT recapture baseline - leave it cleared so player can record everything
        -- Baseline will be captured fresh on next character creation

        -- Refresh any open journal panel UI
        if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
            local panel = BurdJournals.UI.MainPanel.instance
            if panel.populateRecordList then
                panel:populateRecordList()
            end
            if panel.showFeedback then
                local feedbackMsg = getText("UI_BurdJournals_BaselineBypassEnabled") or "Baseline cleared! All skills/traits/recipes now recordable."
                panel:showFeedback(feedbackMsg, {r=0.3, g=1, b=0.5})
            end
        end

        -- Show feedback to player via speech bubble
        local msg = getText("UI_BurdJournals_CmdBaselineBypassed") or "[Journals] Baseline cleared! All skills/traits/recipes now recordable for this character."
        player:Say(msg)

        print("[BurdJournals] Command: Baseline clear complete - bypass active")
        return true  -- Command was handled
    end

    return false  -- Not our command
end

-- Hook into chat/command system
if Events.OnCustomCommand then
    Events.OnCustomCommand.Add(BurdJournals.Client.onChatCommand)
end

-- ============================================================================
-- DIAGNOSTIC SYSTEM FOR MP DEBUGGING
-- These functions help track down data loss issues in multiplayer
-- ============================================================================

BurdJournals.Client.Diagnostics = {}

-- Track key events for diagnostic purposes
BurdJournals.Client.Diagnostics.eventLog = {}
BurdJournals.Client.Diagnostics.maxLogEntries = 100

function BurdJournals.Client.Diagnostics.log(category, message, data)
    local timestamp = getTimestampMs and getTimestampMs() or os.time()
    local entry = {
        time = timestamp,
        category = category,
        message = message,
        data = data
    }
    table.insert(BurdJournals.Client.Diagnostics.eventLog, entry)

    -- Trim old entries
    while #BurdJournals.Client.Diagnostics.eventLog > BurdJournals.Client.Diagnostics.maxLogEntries do
        table.remove(BurdJournals.Client.Diagnostics.eventLog, 1)
    end

    -- Always print diagnostic logs to console for debugging
    local dataStr = ""
    if data then
        local parts = {}
        for k, v in pairs(data) do
            table.insert(parts, tostring(k) .. "=" .. tostring(v))
        end
        dataStr = " {" .. table.concat(parts, ", ") .. "}"
    end
    print("[BurdJournals DIAG] [" .. category .. "] " .. message .. dataStr)
end

-- Scan all journals in player inventory and report their state
function BurdJournals.Client.Diagnostics.scanJournals(player)
    if not player then
        player = getPlayer()
    end
    if not player then
        print("[BurdJournals DIAG] ERROR: No player available")
        return nil
    end

    local results = {
        timestamp = getTimestampMs and getTimestampMs() or os.time(),
        journals = {},
        summary = {
            total = 0,
            withData = 0,
            withSkills = 0,
            withTraits = 0,
            withRecipes = 0,
            totalSkillEntries = 0,
            totalTraitEntries = 0,
            totalRecipeEntries = 0
        }
    }

    local inventory = player:getInventory()
    if not inventory then
        print("[BurdJournals DIAG] ERROR: Could not access player inventory")
        return results
    end

    local items = inventory:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            local itemType = item:getFullType()
            if itemType and (string.find(itemType, "SurvivalJournal") or string.find(itemType, "BurdJournal")) then
                results.summary.total = results.summary.total + 1

                local journalInfo = {
                    id = item:getID(),
                    type = itemType,
                    hasModData = false,
                    hasBurdData = false,
                    skills = {},
                    traits = {},
                    recipes = {},
                    skillCount = 0,
                    traitCount = 0,
                    recipeCount = 0
                }

                local modData = item:getModData()
                if modData then
                    journalInfo.hasModData = true
                    local burdData = modData.BurdJournals
                    if burdData then
                        journalInfo.hasBurdData = true
                        results.summary.withData = results.summary.withData + 1

                        if burdData.skills then
                            for skillName, skillData in pairs(burdData.skills) do
                                journalInfo.skillCount = journalInfo.skillCount + 1
                                journalInfo.skills[skillName] = {
                                    level = skillData.level,
                                    xp = skillData.xp
                                }
                            end
                            if journalInfo.skillCount > 0 then
                                results.summary.withSkills = results.summary.withSkills + 1
                                results.summary.totalSkillEntries = results.summary.totalSkillEntries + journalInfo.skillCount
                            end
                        end

                        if burdData.traits then
                            for traitId, _ in pairs(burdData.traits) do
                                journalInfo.traitCount = journalInfo.traitCount + 1
                                table.insert(journalInfo.traits, traitId)
                            end
                            if journalInfo.traitCount > 0 then
                                results.summary.withTraits = results.summary.withTraits + 1
                                results.summary.totalTraitEntries = results.summary.totalTraitEntries + journalInfo.traitCount
                            end
                        end

                        if burdData.recipes then
                            for recipeName, _ in pairs(burdData.recipes) do
                                journalInfo.recipeCount = journalInfo.recipeCount + 1
                                table.insert(journalInfo.recipes, recipeName)
                            end
                            if journalInfo.recipeCount > 0 then
                                results.summary.withRecipes = results.summary.withRecipes + 1
                                results.summary.totalRecipeEntries = results.summary.totalRecipeEntries + journalInfo.recipeCount
                            end
                        end
                    end
                end

                table.insert(results.journals, journalInfo)
            end
        end
    end

    return results
end

-- Get player state snapshot for comparison
function BurdJournals.Client.Diagnostics.getPlayerSnapshot(player)
    if not player then
        player = getPlayer()
    end
    if not player then
        return nil
    end

    local snapshot = {
        timestamp = getTimestampMs and getTimestampMs() or os.time(),
        username = player:getUsername(),
        steamId = BurdJournals.getPlayerSteamId and BurdJournals.getPlayerSteamId(player) or "unknown",
        characterId = BurdJournals.getPlayerCharacterId and BurdJournals.getPlayerCharacterId(player) or "unknown",
        hoursAlive = player:getHoursSurvived(),
        skills = {},
        traits = {},
        knownRecipeCount = 0
    }

    -- Capture skill levels
    local allSkills = BurdJournals.getAllSkills and BurdJournals.getAllSkills() or {}
    for _, skillName in ipairs(allSkills) do
        local perk = BurdJournals.getPerkByName(skillName)
        if perk then
            local level = player:getPerkLevel(perk)
            local xp = player:getXp():getXP(perk)
            if level > 0 or xp > 0 then
                snapshot.skills[skillName] = {level = level, xp = math.floor(xp)}
            end
        end
    end

    -- Capture traits
    local traitList = player:getTraits()
    if traitList then
        for i = 0, traitList:size() - 1 do
            local trait = traitList:get(i)
            if trait then
                table.insert(snapshot.traits, tostring(trait))
            end
        end
    end

    -- Count known recipes
    local knownRecipes = player:getKnownRecipes()
    if knownRecipes then
        snapshot.knownRecipeCount = knownRecipes:size()
    end

    return snapshot
end

-- Print full diagnostic report
function BurdJournals.Client.Diagnostics.printReport()
    local player = getPlayer()
    if not player then
        print("[BurdJournals DIAG] ERROR: No player - cannot generate report")
        return
    end

    print("")
    print("================================================================================")
    print("BURD'S SURVIVAL JOURNALS - DIAGNOSTIC REPORT")
    print("================================================================================")
    print("Generated: " .. (getTimestampMs and tostring(getTimestampMs()) or tostring(os.time())))
    print("Game Version: " .. (getCore and getCore():getVersionNumber() or "unknown"))
    print("Is Multiplayer: " .. tostring(isClient()))
    print("Is Server: " .. tostring(isServer()))
    print("Is Coop Host: " .. tostring(isCoopHost and isCoopHost() or false))
    print("")

    -- Player info
    print("--- PLAYER INFO ---")
    local snapshot = BurdJournals.Client.Diagnostics.getPlayerSnapshot(player)
    if snapshot then
        print("Username: " .. tostring(snapshot.username))
        print("Steam ID: " .. tostring(snapshot.steamId))
        print("Character ID: " .. tostring(snapshot.characterId))
        print("Hours Survived: " .. string.format("%.2f", snapshot.hoursAlive))

        local skillCount = 0
        for _ in pairs(snapshot.skills) do skillCount = skillCount + 1 end
        print("Skills with XP: " .. skillCount)
        print("Traits: " .. #snapshot.traits)
        print("Known Recipes: " .. snapshot.knownRecipeCount)
    end
    print("")

    -- Player modData state
    print("--- PLAYER MODDATA ---")
    local modData = player:getModData()
    if modData and modData.BurdJournals then
        local bd = modData.BurdJournals
        print("baselineCaptured: " .. tostring(bd.baselineCaptured))
        print("baselineVersion: " .. tostring(bd.baselineVersion))
        print("baselineBypassed: " .. tostring(bd.baselineBypassed))
        if bd.skillBaseline then
            local count = 0
            for _ in pairs(bd.skillBaseline) do count = count + 1 end
            print("skillBaseline entries: " .. count)
        else
            print("skillBaseline: nil")
        end
        if bd.traitBaseline then
            print("traitBaseline entries: " .. #bd.traitBaseline)
        else
            print("traitBaseline: nil")
        end
        if bd.recipeBaseline then
            local count = 0
            for _ in pairs(bd.recipeBaseline) do count = count + 1 end
            print("recipeBaseline entries: " .. count)
        else
            print("recipeBaseline: nil")
        end
    else
        print("No BurdJournals modData on player")
    end
    print("")

    -- Journal scan
    print("--- JOURNAL INVENTORY SCAN ---")
    local scanResults = BurdJournals.Client.Diagnostics.scanJournals(player)
    if scanResults then
        print("Total journals found: " .. scanResults.summary.total)
        print("Journals with data: " .. scanResults.summary.withData)
        print("Journals with skills: " .. scanResults.summary.withSkills .. " (total entries: " .. scanResults.summary.totalSkillEntries .. ")")
        print("Journals with traits: " .. scanResults.summary.withTraits .. " (total entries: " .. scanResults.summary.totalTraitEntries .. ")")
        print("Journals with recipes: " .. scanResults.summary.withRecipes .. " (total entries: " .. scanResults.summary.totalRecipeEntries .. ")")
        print("")

        for i, journal in ipairs(scanResults.journals) do
            print("  Journal #" .. i .. " (ID: " .. tostring(journal.id) .. ")")
            print("    Type: " .. tostring(journal.type))
            print("    Has ModData: " .. tostring(journal.hasModData))
            print("    Has BurdData: " .. tostring(journal.hasBurdData))
            print("    Skills: " .. journal.skillCount .. ", Traits: " .. journal.traitCount .. ", Recipes: " .. journal.recipeCount)
        end
    end
    print("")

    -- Recent event log
    print("--- RECENT EVENT LOG (last 20) ---")
    local log = BurdJournals.Client.Diagnostics.eventLog
    local startIdx = math.max(1, #log - 19)
    for i = startIdx, #log do
        local entry = log[i]
        print(string.format("  [%s] %s: %s", tostring(entry.time), entry.category, entry.message))
    end
    print("")

    print("================================================================================")
    print("END OF DIAGNOSTIC REPORT")
    print("================================================================================")
    print("")
end

-- Chat command handler for /journaldiag
function BurdJournals.Client.Diagnostics.onChatCommand(command)
    if not command then return false end

    local cmd = string.lower(command)
    if cmd == "/journaldiag" or cmd == "/jdiag" or cmd == "/burdjournaldiag" then
        BurdJournals.Client.Diagnostics.printReport()

        local player = getPlayer()
        if player then
            player:Say("[Journals] Diagnostic report printed to console.txt")
        end
        return true
    end

    if cmd == "/journalscan" or cmd == "/jscan" then
        local player = getPlayer()
        local results = BurdJournals.Client.Diagnostics.scanJournals(player)
        if results and player then
            local msg = string.format("[Journals] Found %d journals: %d skills, %d traits, %d recipes",
                results.summary.total,
                results.summary.totalSkillEntries,
                results.summary.totalTraitEntries,
                results.summary.totalRecipeEntries)
            player:Say(msg)
        end
        return true
    end

    return false
end

-- Hook diagnostic commands
if Events.OnCustomCommand then
    Events.OnCustomCommand.Add(BurdJournals.Client.Diagnostics.onChatCommand)
end

-- Hook into key events to log them
local originalOnServerCommand = BurdJournals.Client.onServerCommand
BurdJournals.Client.onServerCommand = function(module, command, args)
    if module == "BurdJournals" then
        -- Log server commands for diagnostics
        local logData = {command = command}
        if args then
            if args.journalId then logData.journalId = args.journalId end
            if args.skillName then logData.skillName = args.skillName end
            if args.traitId then logData.traitId = args.traitId end
            if args.recipeName then logData.recipeName = args.recipeName end
            if args.journalData then
                local skillCount = args.journalData.skills and BurdJournals.countTable(args.journalData.skills) or 0
                local traitCount = args.journalData.traits and BurdJournals.countTable(args.journalData.traits) or 0
                local recipeCount = args.journalData.recipes and BurdJournals.countTable(args.journalData.recipes) or 0
                logData.dataSkills = skillCount
                logData.dataTraits = traitCount
                logData.dataRecipes = recipeCount
            end
        end
        BurdJournals.Client.Diagnostics.log("SERVER_CMD", "Received: " .. command, logData)
    end

    -- Call original handler
    return originalOnServerCommand(module, command, args)
end

-- Log on game start
local originalInit = BurdJournals.Client.init
BurdJournals.Client.init = function(player)
    BurdJournals.Client.Diagnostics.log("LIFECYCLE", "OnGameStart/init called", {
        username = player and player:getUsername() or "nil",
        hoursAlive = player and player:getHoursSurvived() or 0,
        isClient = isClient(),
        isServer = isServer()
    })
    return originalInit(player)
end

-- Log on player create
local originalOnCreatePlayer = BurdJournals.Client.onCreatePlayer
BurdJournals.Client.onCreatePlayer = function(playerIndex, player)
    BurdJournals.Client.Diagnostics.log("LIFECYCLE", "OnCreatePlayer called", {
        playerIndex = playerIndex,
        username = player and player:getUsername() or "nil",
        hoursAlive = player and player:getHoursSurvived() or 0
    })
    return originalOnCreatePlayer(playerIndex, player)
end

-- Log connection events if available
if Events.OnConnected then
    Events.OnConnected.Add(function()
        BurdJournals.Client.Diagnostics.log("NETWORK", "OnConnected fired", {})
    end)
end

if Events.OnDisconnect then
    Events.OnDisconnect.Add(function()
        BurdJournals.Client.Diagnostics.log("NETWORK", "OnDisconnect fired", {})
    end)
end

if Events.OnConnectionStateChanged then
    Events.OnConnectionStateChanged.Add(function(state, reason)
        BurdJournals.Client.Diagnostics.log("NETWORK", "ConnectionStateChanged", {
            state = tostring(state),
            reason = tostring(reason)
        })
    end)
end

print("[BurdJournals] Diagnostic system loaded - use /journaldiag or /jdiag for report")
