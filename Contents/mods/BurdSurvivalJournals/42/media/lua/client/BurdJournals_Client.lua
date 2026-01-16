--[[
    Burd's Survival Journals - Client Module
    Build 42 - Version 2.0

    Client-side initialization and event handlers

    Handles server commands:
    - applyXP: Apply XP to player (SET or ADD mode)
    - absorbSuccess: Feedback for skill absorption
    - journalDissolved: Journal has been emptied and removed
    - grantTrait: Grant a trait to the player
    - traitAlreadyKnown: Player already has the trait
    - logSuccess: Skills logged successfully
    - eraseSuccess: Journal erased
    - cleanSuccess: Bloody journal cleaned to worn
    - convertSuccess: Worn journal converted to clean
    - error: Error message display
]]

require "BurdJournals_Shared"

BurdJournals = BurdJournals or {}
BurdJournals.Client = BurdJournals.Client or {}

-- ==================== CLIENT INITIALIZATION ====================

-- Baseline data version - increment when baseline calculation logic changes
-- This allows automatic recalculation when users update the mod
BurdJournals.Client.BASELINE_VERSION = 2  -- v2: Fixed existing save detection and trait baseline

-- Track current language to detect changes and re-localize item names
BurdJournals.Client._currentLanguage = nil

-- Check if language changed and clear localization cache if so
function BurdJournals.Client.checkLanguageChange()
    local newLanguage = nil
    -- Try to get current language - different methods for different PZ versions
    if Translator and Translator.getLanguage then
        newLanguage = Translator.getLanguage()
    elseif getCore and getCore().getLanguage then
        newLanguage = getCore():getLanguage()
    end

    if newLanguage and BurdJournals.Client._currentLanguage and newLanguage ~= BurdJournals.Client._currentLanguage then
        -- Language changed! Clear the localization cache so items get re-localized
        if BurdJournals.clearLocalizedItemsCache then
            BurdJournals.clearLocalizedItemsCache()
        end
    end

    BurdJournals.Client._currentLanguage = newLanguage
end

-- Flag to indicate OnCreatePlayer will handle baseline capture
-- This prevents init() from racing with onCreatePlayer
BurdJournals.Client._pendingNewCharacterBaseline = false

function BurdJournals.Client.init()
    -- Initialize language tracking for localization
    BurdJournals.Client.checkLanguageChange()

    -- Try to capture baseline for existing characters that don't have it yet
    -- This handles:
    -- 1. Existing saves (characters created before the mod update)
    -- 2. Characters where OnCreatePlayer might have been missed
    -- 3. Saves with outdated baseline data that needs recalculation
    --
    -- IMPORTANT: For NEW characters, OnCreatePlayer sets _pendingNewCharacterBaseline flag
    -- and will do direct capture. We must check this flag AND hoursAlive to be safe.
    local player = getPlayer()
    if player then
        local hoursAlive = player:getHoursSurvived() or 0

        -- Skip if OnCreatePlayer is handling this (flag set)
        if BurdJournals.Client._pendingNewCharacterBaseline then
            print("[BurdJournals] init: OnCreatePlayer is handling baseline, skipping")
            return
        end

        -- Skip if this is a brand new character - OnCreatePlayer will handle it
        -- New characters have < 0.1 hours (6 minutes) of survival time
        if hoursAlive < 0.1 then
            print("[BurdJournals] init: New character detected (" .. hoursAlive .. " hours), deferring to OnCreatePlayer")
            return
        end

        local modData = player:getModData()
        local needsBaseline = not modData.BurdJournals or not modData.BurdJournals.baselineCaptured

        -- Check if baseline was captured with an older version
        if modData.BurdJournals and modData.BurdJournals.baselineCaptured then
            local currentVersion = modData.BurdJournals.baselineVersion or 1
            if currentVersion < BurdJournals.Client.BASELINE_VERSION then
                print("[BurdJournals] Baseline version " .. currentVersion .. " is outdated (current: " .. BurdJournals.Client.BASELINE_VERSION .. ")")
                -- Only recalculate for existing saves (players who have played for a while)
                if hoursAlive > 1 then
                    print("[BurdJournals] Existing save detected (" .. hoursAlive .. " hours survived), will recalculate baseline")
                    -- Clear old baseline to allow recapture
                    modData.BurdJournals.baselineCaptured = nil
                    modData.BurdJournals.skillBaseline = nil
                    modData.BurdJournals.traitBaseline = nil
                    needsBaseline = true
                end
            end
        end

        if needsBaseline then
            -- Small delay to ensure player is fully loaded
            local captureAfterDelay
            local ticksWaited = 0
            captureAfterDelay = function()
                ticksWaited = ticksWaited + 1
                if ticksWaited >= 10 then  -- Wait 10 ticks (~1 second) for game start
                    Events.OnTick.Remove(captureAfterDelay)
                    -- Double-check flag hasn't been set while we waited
                    if BurdJournals.Client._pendingNewCharacterBaseline then
                        print("[BurdJournals] init delayed: OnCreatePlayer took over, aborting")
                        return
                    end
                    -- Pass false for isNewCharacter - calculate baseline from profession/traits
                    BurdJournals.Client.captureBaseline(player, false)
                end
            end
            Events.OnTick.Add(captureAfterDelay)
        end
    end
end

-- ==================== HALO TEXT UTILITIES ====================

-- Color presets for halo text
BurdJournals.Client.HaloColors = {
    XP_GAIN = {r=0.3, g=0.9, b=0.3, a=1},       -- Green for XP gain
    TRAIT_GAIN = {r=0.9, g=0.7, b=0.2, a=1},    -- Gold for traits
    RECIPE_GAIN = {r=0.4, g=0.85, b=0.95, a=1}, -- Cyan/teal for recipes
    DISSOLVE = {r=0.7, g=0.5, b=0.3, a=1},      -- Brown for dissolution
    ERROR = {r=0.9, g=0.3, b=0.3, a=1},         -- Red for errors
    INFO = {r=1, g=1, b=1, a=1},                -- White for info
}

function BurdJournals.Client.showHaloMessage(player, message, color)
    if not player then return end
    color = color or BurdJournals.Client.HaloColors.INFO

    -- Use HaloTextHelper if available (Build 42 uses addTextWithArrow)
    if HaloTextHelper and HaloTextHelper.addTextWithArrow then
        -- Map color to HaloTextHelper color methods
        local haloColor = HaloTextHelper.getColorWhite()
        if color == BurdJournals.Client.HaloColors.XP_GAIN then
            haloColor = HaloTextHelper.getColorGreen()
        elseif color == BurdJournals.Client.HaloColors.TRAIT_GAIN then
            haloColor = HaloTextHelper.getColorGreen()
        elseif color == BurdJournals.Client.HaloColors.RECIPE_GAIN then
            haloColor = HaloTextHelper.getColorBlue()  -- Closest to cyan/teal
        elseif color == BurdJournals.Client.HaloColors.ERROR then
            haloColor = HaloTextHelper.getColorRed()
        end
        HaloTextHelper.addTextWithArrow(player, message, true, haloColor)
    else
        -- Fallback to speech bubble
        player:Say(message)
    end
end

-- ==================== EVENT HANDLERS ====================

function BurdJournals.Client.onServerCommand(module, command, args)
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
        BurdJournals.Client.showHaloMessage(player, getText("UI_BurdJournals_JournalErased") or "Journal erased", BurdJournals.Client.HaloColors.INFO)

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

    elseif command == "error" then
        if args and args.message then
            BurdJournals.Client.showHaloMessage(player, args.message, BurdJournals.Client.HaloColors.ERROR)
        end
    end
end

-- ==================== REQUEST SERVER INITIALIZATION ====================

-- Request server to initialize a journal (ensures server-side UUID and data)
function BurdJournals.Client.requestJournalInitialization(journal, callback)
    if not journal then return end

    local itemType = journal:getFullType()
    local modData = journal:getModData()
    local clientUUID = modData and modData.BurdJournals and modData.BurdJournals.uuid


    -- Store callback for when server responds
    BurdJournals.Client.pendingInitCallback = callback

    sendClientCommand(getPlayer(), "BurdJournals", "initializeJournal", {
        itemType = itemType,
        clientUUID = clientUUID
    })
end

-- Handle server's initialization response
function BurdJournals.Client.handleJournalInitialized(player, args)
    if not args then return end


    -- Call pending callback if any
    if BurdJournals.Client.pendingInitCallback then
        local callback = BurdJournals.Client.pendingInitCallback
        BurdJournals.Client.pendingInitCallback = nil
        callback(args.uuid)
    end

    -- Refresh UI if open
    if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
        BurdJournals.UI.MainPanel.instance:refreshJournalData()
    end
end

-- Handle successful recording (MP-safe response from server)
function BurdJournals.Client.handleRecordSuccess(player, args)
    if not args then return end

    print("[BurdJournals] Client: handleRecordSuccess received, newJournalId=" .. tostring(args.newJournalId) .. ", journalId=" .. tostring(args.journalId))

    -- Build specific feedback message with actual names
    local recordedItems = {}

    -- Add skill names (get display names)
    if args.skillNames then
        for _, skillName in ipairs(args.skillNames) do
            local displayName = BurdJournals.getPerkDisplayName(skillName) or skillName
            table.insert(recordedItems, displayName)
        end
    end

    -- Add trait names (get display names using shared helper)
    if args.traitNames then
        for _, traitId in ipairs(args.traitNames) do
            local traitName = BurdJournals.getTraitDisplayName(traitId)
            table.insert(recordedItems, traitName)
        end
    end

    -- Add recipe names (get display names)
    if args.recipeNames then
        for _, recipeName in ipairs(args.recipeNames) do
            local displayName = BurdJournals.getRecipeDisplayName and BurdJournals.getRecipeDisplayName(recipeName) or recipeName
            table.insert(recordedItems, displayName)
        end
    end

    -- Create concise message
    local message
    if #recordedItems == 0 then
        message = getText("UI_BurdJournals_ProgressSaved") or "Progress saved!"
    elseif #recordedItems == 1 then
        message = string.format(getText("UI_BurdJournals_RecordedItem") or "Recorded %s", recordedItems[1])
    elseif #recordedItems <= 3 then
        message = string.format(getText("UI_BurdJournals_RecordedItems") or "Recorded %s", table.concat(recordedItems, ", "))
    else
        -- More than 3 items, abbreviate
        message = string.format(getText("UI_BurdJournals_RecordedItemsMore") or "Recorded %s, %s +%d more", recordedItems[1], recordedItems[2], #recordedItems - 2)
    end

    BurdJournals.Client.showHaloMessage(player, message, BurdJournals.Client.HaloColors.XP_GAIN)

    -- CRITICAL: Apply journal data directly from server response (bypasses transmitModData timing issues)
    -- We need to update BOTH:
    -- 1. The journal found by ID (for consistency)
    -- 2. The UI panel's journal reference directly (to ensure UI sees the update)
    local journalId = args.newJournalId or args.journalId
    print("[BurdJournals] Client: handleRecordSuccess - journalId=" .. tostring(journalId) .. ", has journalData=" .. tostring(args.journalData ~= nil))
    if journalId and args.journalData then
        print("[BurdJournals] Client: Applying journal data from server for ID " .. tostring(journalId))
        -- Debug: show what recipes are in the server response
        if args.journalData.recipes then
            local recipeCount = 0
            for _ in pairs(args.journalData.recipes) do recipeCount = recipeCount + 1 end
            print("[BurdJournals] Client: Server journalData contains " .. recipeCount .. " recipes")
        else
            print("[BurdJournals] Client: Server journalData has NO recipes table")
        end
        local journal = BurdJournals.findItemById(player, journalId)
        if journal then
            local modData = journal:getModData()
            modData.BurdJournals = args.journalData
            print("[BurdJournals] Client: Journal data applied successfully to found journal")
        else
            print("[BurdJournals] Client: Could not find journal by ID to apply data")
        end
    elseif journalId and not args.journalData then
        print("[BurdJournals] Client: WARNING - No journalData in server response (journal too large?)")
    end

    -- Update UI if open
    if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
        local panel = BurdJournals.UI.MainPanel.instance
        local panelJournalId = panel.journal and panel.journal:getID() or nil
        print("[BurdJournals] Client: Panel exists, panel.journal ID=" .. tostring(panelJournalId) .. ", server journalId=" .. tostring(journalId))

        -- If journal was converted (blank -> filled), update the panel's journal reference
        if args.newJournalId then
            print("[BurdJournals] Client: Looking for new journal ID " .. tostring(args.newJournalId))
            local newJournal = BurdJournals.findItemById(player, args.newJournalId)
            if newJournal then
                print("[BurdJournals] Client: Found new journal, updating panel reference")
                panel.journal = newJournal
                panel.pendingNewJournalId = nil
                -- Also apply journalData to the new panel.journal reference directly
                if args.journalData then
                    local panelModData = panel.journal:getModData()
                    panelModData.BurdJournals = args.journalData
                    print("[BurdJournals] Client: Applied journalData to new panel.journal")
                end
            else
                print("[BurdJournals] Client: New journal NOT found in inventory yet!")
                -- Store the pending journal ID - we'll try to find it on next UI refresh
                panel.pendingNewJournalId = args.newJournalId
            end
        elseif journalId and panel.journal and panel.journal:getID() == journalId then
            -- Same journal, just update modData directly on panel's reference
            if args.journalData then
                local panelModData = panel.journal:getModData()
                panelModData.BurdJournals = args.journalData
                print("[BurdJournals] Client: Applied journalData to existing panel.journal (IDs match)")
            else
                print("[BurdJournals] Client: IDs match but no journalData to apply")
            end
        else
            print("[BurdJournals] Client: WARNING - Journal ID mismatch or missing! Panel has " .. tostring(panelJournalId) .. ", server sent " .. tostring(journalId))
            -- Try to update the panel's journal reference to match what the server is talking about
            if journalId and args.journalData then
                local serverJournal = BurdJournals.findItemById(player, journalId)
                if serverJournal then
                    print("[BurdJournals] Client: Found server's journal, updating panel reference")
                    panel.journal = serverJournal
                    local panelModData = panel.journal:getModData()
                    panelModData.BurdJournals = args.journalData
                end
            end
        end

        -- Show success feedback in UI
        if panel.showFeedback then
            panel:showFeedback(message, {r=0.5, g=0.8, b=0.6})
        end

        -- Refresh the UI to show updated data
        -- Skip refreshJournalData if we have override data - it will call populateRecordList without override
        -- which would read potentially stale data
        if args.journalData then
            -- We have fresh data from server, use it directly
            print("[BurdJournals] Client: Calling populateRecordList with server journalData (skipping refreshJournalData)")
            if panel.populateRecordList then
                pcall(function() panel:populateRecordList(args.journalData) end)
            end
        else
            -- No server data, do a full refresh which will read from modData
            print("[BurdJournals] Client: No server journalData, doing full refreshJournalData")
            if panel.refreshJournalData then
                panel:refreshJournalData()
            end
        end
    else
        print("[BurdJournals] Client: No UI panel instance to update")
    end
end

-- ==================== COMMAND HANDLERS ====================

function BurdJournals.Client.handleApplyXP(player, args)
    if not args or not args.skills then
        return
    end

    local mode = args.mode or "set"
    local totalXPGained = 0
    local skillsApplied = 0


    for skillName, data in pairs(args.skills) do

        -- Use getPerkByName for proper skill name mapping (e.g., Foraging -> PlantScavenging)
        local perk = BurdJournals.getPerkByName(skillName)

        if perk then
            local xpToApply = data.xp or 0
            local skillMode = data.mode or mode

            local beforeXP = player:getXp():getXP(perk)

            if skillMode == "add" then
                -- ADD mode: Add XP to current value
                -- Use sendAddXp - works in both SP and MP (like Skill Recovery Journal does)
                if sendAddXp then
                    sendAddXp(player, perk, xpToApply, true)
                    skillsApplied = skillsApplied + 1
                    totalXPGained = totalXPGained + xpToApply
                    print("[BurdJournals] Applied +" .. tostring(xpToApply) .. " XP to " .. tostring(skillName))
                else
                    -- Fallback: direct AddXP (should rarely happen)
                    player:getXp():AddXP(perk, xpToApply)
                    local afterXP = player:getXp():getXP(perk)
                    totalXPGained = totalXPGained + (afterXP - beforeXP)
                    skillsApplied = skillsApplied + 1
                    print("[BurdJournals] Fallback: Applied XP to " .. tostring(skillName))
                end
            else
                -- SET mode: Only apply if journal XP is higher
                if xpToApply > beforeXP then
                    local xpDiff = xpToApply - beforeXP
                    if sendAddXp then
                        sendAddXp(player, perk, xpDiff, true)
                        print("[BurdJournals] Set " .. tostring(skillName) .. " to " .. tostring(xpToApply) .. " (added " .. tostring(xpDiff) .. ")")
                    else
                        player:getXp():AddXP(perk, xpDiff)
                    end
                    totalXPGained = totalXPGained + xpDiff
                    skillsApplied = skillsApplied + 1
                end
            end
        end
    end

    -- Note: Halo text is shown by handleAbsorbSuccess which has more detail (skill name)
    -- Don't show duplicate halo text here
    if skillsApplied > 0 then
        -- Debug removed
    end
end

function BurdJournals.Client.handleAbsorbSuccess(player, args)
    if not args then return end

    print("[BurdJournals] Client: handleAbsorbSuccess received, journalId=" .. tostring(args.journalId))

    -- Show halo text feedback for skill absorption AND apply the reward
    if args.skillName and args.xpGained then
        local displayName = BurdJournals.getPerkDisplayName(args.skillName)
        local xpGained = args.xpGained or 0

        -- Show halo text above player's head
        local message = "+" .. BurdJournals.formatXP(xpGained) .. " " .. displayName
        BurdJournals.Client.showHaloMessage(player, message, BurdJournals.Client.HaloColors.XP_GAIN)
        -- Note: XP is applied via separate applyXP command from server
    elseif args.traitId then
        local traitName = BurdJournals.getTraitDisplayName(args.traitId)
        local message = string.format(getText("UI_BurdJournals_LearnedTrait") or "Learned: %s", traitName)
        BurdJournals.Client.showHaloMessage(player, message, BurdJournals.Client.HaloColors.TRAIT_GAIN)
        -- CRITICAL: Also add trait on client side for MP sync
        pcall(function()
            BurdJournals.safeAddTrait(player, args.traitId)
        end)
    elseif args.recipeName then
        local displayName = BurdJournals.getRecipeDisplayName(args.recipeName)
        local message = "+" .. displayName
        BurdJournals.Client.showHaloMessage(player, message, BurdJournals.Client.HaloColors.RECIPE_GAIN)
        -- CRITICAL: Learn recipe on client side for MP sync
        pcall(function()
            player:learnRecipe(args.recipeName)
            print("[BurdJournals] Client: Learned recipe '" .. args.recipeName .. "' on absorb")
        end)
    end

    -- CRITICAL: Apply full journal data from server response (bypasses transmitModData timing issues)
    -- We need to update BOTH:
    -- 1. The journal found by ID (for consistency)
    -- 2. The UI panel's journal reference directly (to ensure UI sees the update)
    if args.journalId and args.journalData then
        print("[BurdJournals] Client: Applying journal data from server for absorb")

        -- Update journal found by ID
        local journal = BurdJournals.findItemById(player, args.journalId)
        if journal then
            local modData = journal:getModData()
            -- Debug: show claimed skills before
            local claimedBefore = modData.BurdJournals and modData.BurdJournals.claimedSkills or {}
            print("[BurdJournals] Client: claimedSkills BEFORE: " .. tostring(BurdJournals.countTable(claimedBefore)))

            modData.BurdJournals = args.journalData

            -- Debug: show claimed skills after
            local claimedAfter = modData.BurdJournals and modData.BurdJournals.claimedSkills or {}
            print("[BurdJournals] Client: claimedSkills AFTER: " .. tostring(BurdJournals.countTable(claimedAfter)))
            print("[BurdJournals] Client: Journal data applied successfully for absorb")
        else
            print("[BurdJournals] Client: Could not find journal to apply absorb data")
        end

        -- ALSO update the UI panel's journal directly if it matches
        if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
            local panel = BurdJournals.UI.MainPanel.instance
            if panel.journal and panel.journal:getID() == args.journalId then
                local panelModData = panel.journal:getModData()
                print("[BurdJournals] Client: Also updating panel.journal modData directly")
                panelModData.BurdJournals = args.journalData
            end
        end
    elseif args.journalId then
        -- Fallback: Mark skill/trait/recipe as claimed locally if no journalData provided
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

        -- Also mark on panel's journal
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

    -- Refresh UI if open
    if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
        local panel = BurdJournals.UI.MainPanel.instance
        -- Debug: Check if UI panel's journal matches the one we updated
        local panelJournalId = panel.journal and panel.journal:getID() or "nil"
        print("[BurdJournals] Client: UI panel journal ID = " .. tostring(panelJournalId) .. ", server response journalId = " .. tostring(args.journalId))

        -- Double-check: Read the claimed skills from panel's journal directly
        if panel.journal then
            local panelModData = panel.journal:getModData()
            local panelClaimed = panelModData.BurdJournals and panelModData.BurdJournals.claimedSkills or {}
            print("[BurdJournals] Client: Panel's journal claimedSkills count = " .. tostring(BurdJournals.countTable(panelClaimed)))
        end

        panel:refreshAbsorptionList()
    end
end

-- Handle claim success (SET mode - for player journals)
function BurdJournals.Client.handleClaimSuccess(player, args)
    if not args then return end

    print("[BurdJournals] Client: handleClaimSuccess received, journalId=" .. tostring(args.journalId))

    -- Show halo text feedback AND apply the actual reward on client
    if args.skillName and args.xpGained then
        local displayName = BurdJournals.getPerkDisplayName(args.skillName)
        local message = string.format(getText("UI_BurdJournals_ClaimedSkill") or "Claimed: %s (+%s XP)", displayName, BurdJournals.formatXP(args.xpGained))
        BurdJournals.Client.showHaloMessage(player, message, BurdJournals.Client.HaloColors.XP_GAIN)
        -- Note: XP is applied via separate applyXP command from server
    elseif args.traitId then
        local traitName = BurdJournals.getTraitDisplayName(args.traitId)
        local message = string.format(getText("UI_BurdJournals_LearnedTrait") or "Learned: %s", traitName)
        BurdJournals.Client.showHaloMessage(player, message, BurdJournals.Client.HaloColors.TRAIT_GAIN)
        -- CRITICAL: Also add trait on client side for MP sync
        -- Server already added it, but client needs to know too
        pcall(function()
            BurdJournals.safeAddTrait(player, args.traitId)
        end)
    elseif args.recipeName then
        local displayName = BurdJournals.getRecipeDisplayName(args.recipeName)
        local message = "+" .. displayName
        BurdJournals.Client.showHaloMessage(player, message, BurdJournals.Client.HaloColors.RECIPE_GAIN)
        -- CRITICAL: Learn recipe on client side for MP sync
        -- Server already learned it, but client needs to apply it too
        pcall(function()
            player:learnRecipe(args.recipeName)
            print("[BurdJournals] Client: Learned recipe '" .. args.recipeName .. "' on client")
        end)
    end

    -- CRITICAL: Apply full journal data from server response (bypasses transmitModData timing issues)
    -- We need to update BOTH:
    -- 1. The journal found by ID (for consistency)
    -- 2. The UI panel's journal reference directly (to ensure UI sees the update)
    if args.journalId and args.journalData then
        print("[BurdJournals] Client: Applying journal data from server for claimSuccess")
        local journal = BurdJournals.findItemById(player, args.journalId)
        if journal then
            local modData = journal:getModData()
            modData.BurdJournals = args.journalData
            print("[BurdJournals] Client: Journal data applied successfully for claimSuccess")
        else
            print("[BurdJournals] Client: Could not find journal to apply claimSuccess data")
        end

        -- ALSO update the UI panel's journal directly if it matches
        if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
            local panel = BurdJournals.UI.MainPanel.instance
            if panel.journal and panel.journal:getID() == args.journalId then
                local panelModData = panel.journal:getModData()
                print("[BurdJournals] Client: Also updating panel.journal modData directly for claimSuccess")
                panelModData.BurdJournals = args.journalData
            end
        end
    end

    -- Refresh UI if open
    if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
        local panel = BurdJournals.UI.MainPanel.instance
        -- Use refreshJournalData which handles both absorption and log UIs
        -- In SP, this is synchronous. In MP, sendAddXp is async but should still work.
        print("[BurdJournals] Client: Refreshing UI for claimSuccess")
        if panel.refreshJournalData then
            panel:refreshJournalData()
        elseif panel.refreshAbsorptionList then
            panel:refreshAbsorptionList()
        end
    end
end

function BurdJournals.Client.handleJournalDissolved(player, args)

    -- Get the random dissolution message
    local message = args and args.message or BurdJournals.getRandomDissolutionMessage()

    -- Show as player speech (character says the message)
    if player and player.Say then
        player:Say(message)
    end

    -- Play sound effect
    pcall(function()
        player:getEmitter():playSound("PaperRip")
    end)

    -- BACKUP: Remove journal from client inventory (server should have done this already)
    if args and args.journalId then
        local journal = BurdJournals.findItemById(player, args.journalId)
        if journal then
            -- Debug removed
            local container = journal:getContainer()
            if container then
                container:Remove(journal)
            end
            player:getInventory():Remove(journal)
        end
    end

    -- Close the journal UI if open
    if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
        BurdJournals.UI.MainPanel.instance:onClose()
    end

end

function BurdJournals.Client.handleRemoveJournal(player, args)
    -- Server requested we remove a journal by UUID
    if not args or not args.journalUUID then
        -- Debug removed
        return
    end

    local journalUUID = args.journalUUID

    -- Find the journal in player's inventory
    local journal = BurdJournals.findJournalByUUID(player, journalUUID)
    if journal then
        -- Remove the journal from inventory
        player:getInventory():Remove(journal)
        -- Debug removed
    else
    end
end

function BurdJournals.Client.handleGrantTrait(player, args)
    if not args or not args.traitId then return end

    local traitId = args.traitId
    -- Get trait display name using shared helper
    local traitName = BurdJournals.getTraitDisplayName(traitId)

    -- Grant the trait using EXACT pattern from ISPlayerStatsUI:onAddTrait
    -- This is the CLIENT-side authoritative way to add traits mid-game
    -- Debug removed

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
            -- Debug removed

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

            -- EXACT pattern from ISPlayerStatsUI:onAddTrait (lines 658-660)
            -- Step 1: Add trait
            player:getCharacterTraits():add(characterTrait)
            -- Debug removed

            -- Step 2: Modify XP boost
            if player.modifyTraitXPBoost then
                player:modifyTraitXPBoost(characterTrait, false)
                -- Debug removed
            end

            -- Step 3: SYNC - this is the critical part!
            if SyncXp then
                SyncXp(player)
                -- Debug removed
            else
            end

            -- Verify
            local hasNow = player:hasTrait(characterTrait)
        else
        end
    end)

    if not success then
        print("[BurdJournals] Client: ERROR in trait grant: " .. tostring(err))
    end

    -- Show halo text feedback
    local message = string.format(getText("UI_BurdJournals_LearnedTrait") or "Learned: %s", traitName)
    BurdJournals.Client.showHaloMessage(player, message, BurdJournals.Client.HaloColors.TRAIT_GAIN)

    -- CRITICAL: Apply full journal data from server response (bypasses transmitModData timing issues)
    -- We need to update BOTH:
    -- 1. The journal found by ID (for consistency)
    -- 2. The UI panel's journal reference directly (to ensure UI sees the update)
    if args.journalId and args.journalData then
        print("[BurdJournals] Client: Applying journal data from server for grantTrait")
        local journal = BurdJournals.findItemById(player, args.journalId)
        if journal then
            local modData = journal:getModData()
            modData.BurdJournals = args.journalData
            print("[BurdJournals] Client: Journal data applied successfully for grantTrait")
        else
            print("[BurdJournals] Client: Could not find journal to apply grantTrait data")
        end

        -- ALSO update the UI panel's journal directly if it matches
        if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
            local panel = BurdJournals.UI.MainPanel.instance
            if panel.journal and panel.journal:getID() == args.journalId then
                local panelModData = panel.journal:getModData()
                print("[BurdJournals] Client: Also updating panel.journal modData directly for grantTrait")
                panelModData.BurdJournals = args.journalData
            end
        end
    elseif args.journalId then
        -- Fallback: Mark trait as claimed locally if no journalData provided
        local journal = BurdJournals.findItemById(player, args.journalId)
        if journal then
            BurdJournals.claimTrait(journal, traitId)
        end

        -- Also mark on panel's journal
        if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
            local panel = BurdJournals.UI.MainPanel.instance
            if panel.journal and panel.journal:getID() == args.journalId then
                BurdJournals.claimTrait(panel.journal, traitId)
            end
        end
    end

    -- Refresh UI if open
    if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
        BurdJournals.UI.MainPanel.instance:refreshAbsorptionList()
    end
end

function BurdJournals.Client.handleTraitAlreadyKnown(player, args)
    if not args or not args.traitId then return end

    local traitId = args.traitId
    -- Get trait display name using shared helper
    local traitName = BurdJournals.getTraitDisplayName(traitId)

    -- Show feedback that player already has this trait (as speech bubble)
    player:Say(string.format(getText("UI_BurdJournals_AlreadyKnowTrait") or "Already know: %s", traitName))

    -- Refresh UI if open
    if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
        BurdJournals.UI.MainPanel.instance:refreshAbsorptionList()
    end
end

function BurdJournals.Client.handleSkillMaxed(player, args)
    if not args or not args.skillName then return end

    local skillName = args.skillName
    local displayName = BurdJournals.getPerkDisplayName(skillName)

    -- Show feedback that skill is already maxed (as speech bubble)
    player:Say(string.format(getText("UI_BurdJournals_SkillAlreadyMaxedMsg") or "%s is already maxed!", displayName))

    -- Refresh UI if open
    if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
        BurdJournals.UI.MainPanel.instance:refreshAbsorptionList()
    end
end

function BurdJournals.Client.handleRecipeAlreadyKnown(player, args)
    if not args or not args.recipeName then return end

    local recipeName = args.recipeName
    local displayName = BurdJournals.getRecipeDisplayName(recipeName)

    -- Show feedback that recipe is already known (as speech bubble)
    player:Say(string.format(getText("UI_BurdJournals_AlreadyKnowRecipe") or "Already know: %s", displayName))

    -- Apply journal data if provided (for worn/bloody journals - marks as claimed)
    if args.journalId and args.journalData then
        local journal = BurdJournals.findItemById(player, args.journalId)
        if journal then
            local modData = journal:getModData()
            modData.BurdJournals = args.journalData
        end

        -- Also update UI panel if matching
        if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
            local panel = BurdJournals.UI.MainPanel.instance
            if panel.journal and panel.journal:getID() == args.journalId then
                local panelModData = panel.journal:getModData()
                panelModData.BurdJournals = args.journalData
            end
        end
    end

    -- Refresh UI if open
    if BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance then
        local panel = BurdJournals.UI.MainPanel.instance
        if panel.refreshJournalData then
            panel:refreshJournalData()
        elseif panel.refreshAbsorptionList then
            panel:refreshAbsorptionList()
        end
    end
end

-- ==================== BASELINE CAPTURE (Anti-Exploit System) ====================

-- Calculate the expected starting XP from profession and traits
-- This allows us to retroactively determine baseline for existing saves
-- Based on Skill Recovery Journal's approach - proven to work in Build 42
function BurdJournals.Client.calculateProfessionBaseline(player)
    if not player then return {}, {} end

    local skillBaseline = {}
    local traitBaseline = {}

    -- Step 1: Collect bonus LEVELS from profession and traits
    -- We store levels first (like SRJ does), then convert to XP
    local bonusLevels = {}

    local desc = player:getDescriptor()
    if not desc then
        print("[BurdJournals] calculateProfessionBaseline: No descriptor found!")
        return skillBaseline, traitBaseline
    end

    -- Get profession
    local playerProfessionID = desc:getCharacterProfession()
    print("[BurdJournals] calculateProfessionBaseline: profession=" .. tostring(playerProfessionID))

    if playerProfessionID and CharacterProfessionDefinition then
        local profDef = CharacterProfessionDefinition.getCharacterProfessionDefinition(playerProfessionID)
        if profDef then
            -- Get profession's XP boosts (these are skill level bonuses)
            local profXpBoost = transformIntoKahluaTable(profDef:getXpBoosts())
            if profXpBoost then
                for perk, level in pairs(profXpBoost) do
                    -- Use tostring() to get the perk ID string (e.g., "Carpentry", "Mechanics")
                    local perkId = tostring(perk)
                    local levelNum = tonumber(tostring(level))
                    if levelNum and levelNum > 0 then
                        bonusLevels[perkId] = (bonusLevels[perkId] or 0) + levelNum
                        print("[BurdJournals] Profession grants " .. perkId .. " +" .. levelNum .. " levels")
                    end
                end
            end

            -- Get profession's granted (free) traits
            local grantedTraits = profDef:getGrantedTraits()
            if grantedTraits then
                for i = 0, grantedTraits:size() - 1 do
                    local traitName = tostring(grantedTraits:get(i))
                    traitBaseline[traitName] = true
                    print("[BurdJournals] Profession grants trait: " .. traitName)
                end
            end
        end
    end

    -- Get trait XP boosts
    -- NOTE: For existing saves, we can't definitively know which traits are from character
    -- creation vs earned in-game. We only mark traits as baseline if:
    -- 1. They were granted by the profession (already handled above)
    -- 2. They have XP boosts (skill bonus traits are always chosen at character creation)
    -- Traits without XP boosts (like Illiterate, etc.) could be earned later, so we use
    -- a conservative approach: only mark XP-boosting traits as baseline
    local playerTraits = player:getCharacterTraits()
    if playerTraits and playerTraits.getKnownTraits then
        local knownTraits = playerTraits:getKnownTraits()
        for i = 0, knownTraits:size() - 1 do
            local traitTrait = knownTraits:get(i)
            local traitId = tostring(traitTrait)

            -- Get trait's XP boosts - only mark as baseline if it has skill bonuses
            -- Traits with skill bonuses are always from character creation
            if CharacterTraitDefinition then
                local traitDef = CharacterTraitDefinition.getCharacterTraitDefinition(traitTrait)
                if traitDef then
                    local traitXpBoost = transformIntoKahluaTable(traitDef:getXpBoosts())
                    local hasSkillBonus = false
                    if traitXpBoost then
                        for perk, level in pairs(traitXpBoost) do
                            local perkId = tostring(perk)
                            local levelNum = tonumber(tostring(level))
                            if levelNum and levelNum > 0 then
                                bonusLevels[perkId] = (bonusLevels[perkId] or 0) + levelNum
                                print("[BurdJournals] Trait " .. traitId .. " grants " .. perkId .. " +" .. levelNum .. " levels")
                                hasSkillBonus = true
                            end
                        end
                    end

                    -- Only mark trait as baseline if it has skill bonuses
                    -- This is conservative: we'd rather let a starting trait be recordable
                    -- than incorrectly block an earned trait from being recorded
                    if hasSkillBonus then
                        traitBaseline[traitId] = true
                        print("[BurdJournals] Trait marked as baseline (has skill bonus): " .. traitId)
                    end
                end
            end
        end
    end

    -- Step 2: Convert bonus levels to XP values
    -- Use PZ's perk:getTotalXpForLevel() method for accurate conversion
    for perkId, level in pairs(bonusLevels) do
        -- Get the actual perk object from Perks global
        local perk = Perks[perkId]
        if perk then
            -- Use PZ's built-in method to get XP for this level
            local xp = perk:getTotalXpForLevel(level)
            if xp and xp > 0 then
                -- Map perk ID to our skill names
                local skillName = BurdJournals.mapPerkIdToSkillName(perkId)
                if skillName then
                    skillBaseline[skillName] = (skillBaseline[skillName] or 0) + xp
                    print("[BurdJournals] Baseline: " .. skillName .. " = " .. xp .. " XP (Lv" .. level .. ")")
                end
            end
        else
            print("[BurdJournals] WARNING: Unknown perk ID: " .. perkId)
        end
    end

    print("[BurdJournals] Final skill baseline:")
    for skill, xp in pairs(skillBaseline) do
        print("[BurdJournals]   " .. skill .. " = " .. xp .. " XP")
    end

    return skillBaseline, traitBaseline
end

-- Capture and store the player's starting skills/traits as baseline
-- This is called on character creation to track what they spawned with
-- For existing saves, it calculates baseline from profession + traits
-- Parameters:
--   player: the player object
--   isNewCharacter: true if called from OnCreatePlayer (fresh spawn)
function BurdJournals.Client.captureBaseline(player, isNewCharacter)
    if not player then return end

    local modData = player:getModData()
    if not modData.BurdJournals then modData.BurdJournals = {} end

    -- Don't overwrite if already captured (reconnect, save load, etc.)
    if modData.BurdJournals.baselineCaptured then
        print("[BurdJournals] Baseline already captured, skipping")
        return
    end

    -- Safety check: If we think this is a new character but they have significant
    -- survival time, they're actually an existing save (edge case detection)
    -- This handles cases where OnCreatePlayer fires on save load
    if isNewCharacter then
        local hoursAlive = player:getHoursSurvived() or 0
        if hoursAlive > 1 then  -- More than 1 hour of survival = definitely not new
            print("[BurdJournals] WARNING: isNewCharacter=true but player has " .. hoursAlive .. " hours survived!")
            print("[BurdJournals] Treating as existing save to avoid incorrect baseline capture")
            isNewCharacter = false
        end
    end

    if isNewCharacter then
        -- NEW CHARACTER: Capture current XP directly (it IS their spawn XP)
        print("[BurdJournals] Capturing baseline for NEW character (direct capture)")
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

        -- Capture trait baseline (all current traits are "starting" traits)
        modData.BurdJournals.traitBaseline = {}
        local traits = BurdJournals.collectPlayerTraits(player, false)
        for traitId, _ in pairs(traits) do
            modData.BurdJournals.traitBaseline[traitId] = true
        end

        -- Capture recipe baseline (all currently known recipes are "starting" recipes)
        -- This captures recipes from profession, traits, or any other spawn-time grants
        -- Pass false for excludeStarting to capture ALL recipes (don't filter baseline against itself)
        modData.BurdJournals.recipeBaseline = {}
        local recipes = BurdJournals.collectPlayerMagazineRecipes(player, false)
        for recipeName, _ in pairs(recipes) do
            modData.BurdJournals.recipeBaseline[recipeName] = true
        end
    else
        -- EXISTING SAVE: Calculate baseline from profession + traits
        print("[BurdJournals] Calculating baseline for EXISTING save (retroactive)")
        local calcSkills, calcTraits = BurdJournals.Client.calculateProfessionBaseline(player)
        modData.BurdJournals.skillBaseline = calcSkills
        modData.BurdJournals.traitBaseline = calcTraits
        -- For existing saves, we can't know which recipes were from spawn vs earned
        -- So we don't set a recipe baseline (all recipes are recordable)
        modData.BurdJournals.recipeBaseline = {}
    end

    modData.BurdJournals.baselineCaptured = true
    modData.BurdJournals.baselineVersion = BurdJournals.Client.BASELINE_VERSION

    -- Capture player identity for ownership tracking
    modData.BurdJournals.steamId = BurdJournals.getPlayerSteamId(player)
    modData.BurdJournals.characterId = BurdJournals.getPlayerCharacterId(player)

    -- Detailed logging for debugging
    local method = isNewCharacter and "direct capture" or "calculated from profession/traits"
    local recipeCount = BurdJournals.countTable(modData.BurdJournals.recipeBaseline or {})
    print("[BurdJournals] Baseline captured (" .. method .. "): " ..
          tostring(BurdJournals.countTable(modData.BurdJournals.skillBaseline)) .. " skills, " ..
          tostring(BurdJournals.countTable(modData.BurdJournals.traitBaseline)) .. " traits, " ..
          tostring(recipeCount) .. " recipes")

    -- Log each baseline item for debugging
    for skillName, xp in pairs(modData.BurdJournals.skillBaseline) do
        print("[BurdJournals]   Baseline skill: " .. skillName .. " = " .. tostring(xp) .. " XP")
    end
    for traitId, _ in pairs(modData.BurdJournals.traitBaseline) do
        print("[BurdJournals]   Baseline trait: " .. traitId)
    end
    for recipeName, _ in pairs(modData.BurdJournals.recipeBaseline or {}) do
        print("[BurdJournals]   Baseline recipe: " .. recipeName)
    end

    -- CRITICAL: Transmit modData to ensure persistence in saves (especially multiplayer)
    if player.transmitModData then
        player:transmitModData()
        print("[BurdJournals] Player modData transmitted for persistence")
    end
end

-- Force recalculate baseline (for testing/admin use)
-- Call from console: BurdJournals.Client.forceRecalculateBaseline()
function BurdJournals.Client.forceRecalculateBaseline()
    local player = getPlayer()
    if not player then
        print("[BurdJournals] No player found")
        return
    end

    local modData = player:getModData()
    if modData.BurdJournals then
        modData.BurdJournals.baselineCaptured = nil
        modData.BurdJournals.skillBaseline = nil
        modData.BurdJournals.traitBaseline = nil
    end

    print("[BurdJournals] Baseline cleared, recalculating...")
    BurdJournals.Client.captureBaseline(player, false)
    print("[BurdJournals] Baseline recalculated from profession/traits")
end

-- Handler for OnCreatePlayer event (NEW characters only)
function BurdJournals.Client.onCreatePlayer(playerIndex)
    local player = getSpecificPlayer(playerIndex)
    if player then
        -- IMMEDIATELY set flag to tell init() we're handling baseline capture
        -- This must happen BEFORE any delay to win the race with init()
        BurdJournals.Client._pendingNewCharacterBaseline = true
        print("[BurdJournals] onCreatePlayer: Set pending flag, will capture baseline for new character")

        -- CRITICAL: Clear any existing baseline data to ensure fresh capture
        -- This handles respawn case where old baseline might persist
        local modData = player:getModData()
        if modData then
            if not modData.BurdJournals then
                modData.BurdJournals = {}
            end
            -- Force baseline recapture for this new/respawned character
            modData.BurdJournals.baselineCaptured = false
            modData.BurdJournals.skillBaseline = nil
            modData.BurdJournals.traitBaseline = nil
            modData.BurdJournals.recipeBaseline = nil
        end

        -- Wait for player to be fully initialized with traits loaded
        -- We need to wait longer than before because traits may not be applied immediately
        local captureAfterDelay
        local ticksWaited = 0
        local maxWaitTicks = 300  -- Max 5 seconds wait (300 ticks at 60fps)
        local minWaitTicks = 30   -- Minimum 0.5 seconds before checking

        captureAfterDelay = function()
            ticksWaited = ticksWaited + 1

            -- After minimum wait, check if traits are loaded
            if ticksWaited >= minWaitTicks then
                -- Check if traits have been applied to the player
                local hasTraits = false
                pcall(function()
                    local charTraits = player:getCharacterTraits()
                    if charTraits then
                        local knownTraits = charTraits:getKnownTraits()
                        if knownTraits and knownTraits:size() > 0 then
                            hasTraits = true
                        end
                    end
                end)

                -- Capture baseline if traits are loaded OR we've waited too long
                if hasTraits or ticksWaited >= maxWaitTicks then
                    Events.OnTick.Remove(captureAfterDelay)
                    -- Clear the pending flag now that we're capturing
                    BurdJournals.Client._pendingNewCharacterBaseline = false
                    if not hasTraits then
                        print("[BurdJournals] WARNING: Max wait reached, capturing baseline without traits")
                    else
                        print("[BurdJournals] Traits loaded after " .. ticksWaited .. " ticks, capturing baseline")
                    end
                    -- Pass true for isNewCharacter - direct capture of spawn XP
                    BurdJournals.Client.captureBaseline(player, true)
                end
            end
        end
        Events.OnTick.Add(captureAfterDelay)
    end
end

-- ==================== PLAYER DEATH CLEANUP ====================

-- Clean up on player death to prevent orphaned tick handlers and UI issues
function BurdJournals.Client.onPlayerDeath(player)
    -- Close UI and clean up all tick handlers
    if BurdJournals.UI and BurdJournals.UI.MainPanel then
        -- Remove all possible tick handlers defensively
        pcall(function() Events.OnTick.Remove(BurdJournals.UI.MainPanel.onLearningTickStatic) end)
        pcall(function() Events.OnTick.Remove(BurdJournals.UI.MainPanel.onRecordingTickStatic) end)
        pcall(function() Events.OnTick.Remove(BurdJournals.UI.MainPanel.onPendingJournalRetryStatic) end)
        
        -- Close the UI panel if open
        if BurdJournals.UI.MainPanel.instance then
            pcall(function() 
                BurdJournals.UI.MainPanel.instance:setVisible(false)
                BurdJournals.UI.MainPanel.instance:removeFromUIManager()
                BurdJournals.UI.MainPanel.instance = nil
            end)
        end
    end
    
    -- Clear timed action queue for this player
    if ISTimedActionQueue and player then
        pcall(function() ISTimedActionQueue.clear(player) end)
    end

    -- CRITICAL: Clear baseline so it gets recaptured for new character after respawn
    -- This prevents balance mode bypass where old character's skills/traits are used as baseline
    if player then
        local modData = player:getModData()
        if modData and modData.BurdJournals then
            modData.BurdJournals.baselineCaptured = false
            modData.BurdJournals.skillBaseline = nil
            modData.BurdJournals.traitBaseline = nil
            modData.BurdJournals.recipeBaseline = nil
            print("[BurdJournals] Baseline cleared for respawn")
        end
    end

    print("[BurdJournals] Player death cleanup completed")
end

-- ==================== EVENT REGISTRATION ====================

Events.OnServerCommand.Add(BurdJournals.Client.onServerCommand)
Events.OnGameStart.Add(BurdJournals.Client.init)
Events.OnCreatePlayer.Add(BurdJournals.Client.onCreatePlayer)
Events.OnPlayerDeath.Add(BurdJournals.Client.onPlayerDeath)

-- Periodic language check (runs every game minute, approximately 1 real second)
-- Clears localization cache if player changes language in options
if Events.EveryOneMinute then
    Events.EveryOneMinute.Add(BurdJournals.Client.checkLanguageChange)
end


