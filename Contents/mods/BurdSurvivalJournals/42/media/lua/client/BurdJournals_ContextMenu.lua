
require "BurdJournals_Shared"
require "BurdJournals_TimedActions"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISInventoryTransferAction"

BurdJournals = BurdJournals or {}
BurdJournals.ContextMenu = BurdJournals.ContextMenu or {}

function BurdJournals.ContextMenu.isInPlayerMainInventory(player, item)
    if not player or not item then return false end
    local mainInventory = player:getInventory()
    if not mainInventory then return false end

    local itemContainer = item:getContainer()
    return itemContainer == mainInventory
end

function BurdJournals.ContextMenu.isInPlayerContainers(player, item)
    if not player or not item then return false end

    local itemContainer = item:getContainer()
    if not itemContainer then return false end

    if itemContainer == player:getInventory() then
        return true
    end

    local wornItems = player:getWornItems()
    if wornItems then

        for i = 1, wornItems:size() do
            local wornItem = wornItems:get(i - 1)
            if wornItem then
                local actualItem = wornItem:getItem()
                if actualItem and actualItem:IsInventoryContainer() then
                    local bagContainer = actualItem:getItemContainer()
                    if bagContainer and itemContainer == bagContainer then
                        return true
                    end
                end
            end
        end
    end

    return false
end

function BurdJournals.ContextMenu.getExternalReturnContainer(player, sourceContainer)
    if not player or not sourceContainer then return nil end
    if sourceContainer.getType and sourceContainer:getType() == "floor" then
        return nil
    end
    if sourceContainer.isInCharacterInventory and sourceContainer:isInCharacterInventory(player) then
        return nil
    end
    return sourceContainer
end

function BurdJournals.ContextMenu.pickUpThenDo(player, item, callback)
    if not player or not item or not callback then return end

    -- Already in main inventory - just call callback immediately
    if BurdJournals.ContextMenu.isInPlayerMainInventory(player, item) then
        callback(player, item, nil)
        return
    end

    local sourceContainer = item:getContainer()
    if not sourceContainer then
        callback(player, item, nil)
        return
    end

    local returnContainer = BurdJournals.ContextMenu.getExternalReturnContainer(player, sourceContainer)

    -- Store item ID for lookup after transfer (item reference may become stale)
    local itemId = item:getID()
    local destContainer = player:getInventory()

    -- Queue transfer action
    ISTimedActionQueue.add(ISInventoryTransferAction:new(player, item, sourceContainer, destContainer))

    -- Wait for transfer to complete, using ID to find item
    local checkTicks = 0
    local maxTicks = 300
    local pollEveryTicks = 6
    local checkTransfer
    checkTransfer = function()
        checkTicks = checkTicks + 1

        -- The transfer destination is known. Poll only that inventory and do it at
        -- a bounded cadence; the general resolver recursively scans nearby world
        -- containers and must never run from this tick handler.
        if checkTicks == 1 or checkTicks % pollEveryTicks == 0 then
            local foundItem = BurdJournals.findItemByIdInPlayerInventory(player, itemId)
            if foundItem and BurdJournals.ContextMenu.isInPlayerMainInventory(player, foundItem) then
                Events.OnTick.Remove(checkTransfer)
                callback(player, foundItem, returnContainer)  -- Use found item, not original reference
                return
            end
        end

        if checkTicks >= maxTicks then
            Events.OnTick.Remove(checkTransfer)
            BurdJournals.debugPrint("[BurdJournals] pickUpThenDo: Transfer timed out for item ID " .. tostring(itemId))
            return
        end
    end
    Events.OnTick.Add(checkTransfer)
end

function BurdJournals.ContextMenu.getTooDarkMessage()
    local msg = (getText and getText("ContextMenu_TooDark")) or "Too dark to read."
    if msg == "ContextMenu_TooDark" then
        msg = "Too dark to read."
    end
    return msg
end

function BurdJournals.ContextMenu.requireLightOrNotify(player)
    if not BurdJournals.canUseJournalInCurrentLight then
        return true
    end

    local canUse, reason = BurdJournals.canUseJournalInCurrentLight(player)
    if canUse then
        return true
    end

    local message = reason or BurdJournals.ContextMenu.getTooDarkMessage()
    if HaloTextHelper and HaloTextHelper.addBadText and player then
        HaloTextHelper.addBadText(player, message)
    elseif player and player.Say then
        player:Say(message)
    end
    return false
end

local function notifyLimitedLootClaimRule(player, textKey, fallback)
    local message = (getText and getText(textKey)) or fallback
    if not message or message == textKey then
        message = fallback
    end
    if HaloTextHelper and HaloTextHelper.addBadText and player then
        HaloTextHelper.addBadText(player, message)
    elseif player and player.Say then
        player:Say(message)
    end
    return false
end

local function normalizeTooltipTextForDisplay(text)
    if text == nil then return text end
    local normalized = tostring(text)
    normalized = normalized:gsub("\\n", "\n")
    normalized = normalized:gsub("/n", "\n")
    return normalized
end

local function shouldHideLootDetailsInContext(journal)
    return BurdJournals.shouldHideLootRewardDetails
        and BurdJournals.shouldHideLootRewardDetails(journal)
        or false
end

local function getContextJournalDataRoot(journal, normalizeForRead)
    if not (journal and journal.getModData) then
        return nil, nil
    end

    local modData = journal:getModData()
    local data = (BurdJournals.getJournalData and BurdJournals.getJournalData(journal))
        or (modData and modData.BurdJournals)
        or nil

    if normalizeForRead ~= false and data ~= nil and BurdJournals.normalizeTable then
        data = BurdJournals.normalizeTable(data) or data
    end
    if normalizeForRead ~= false and type(data) == "table" and BurdJournals.normalizeJournalData then
        data = BurdJournals.normalizeJournalData(data) or data
    end

    return data, modData
end

local function getMutableContextJournalData(journal)
    local data, modData = getContextJournalDataRoot(journal, false)
    if type(data) == "table" then
        return data
    end
    if data ~= nil and modData and BurdJournals.normalizeTable then
        local normalized = BurdJournals.normalizeTable(data)
        if type(normalized) == "table" then
            modData.BurdJournals = normalized
            return normalized
        end
    end
    return nil
end

local function getNormalizedContextJournalData(journal)
    local journalData = getContextJournalDataRoot(journal, true)
    return journalData or {}
end

local function getStaticAbsorbAllContextLabel()
    local tooltipText = getText("Tooltip_BurdJournals_AbsorbAll")
    if tooltipText ~= "Tooltip_BurdJournals_AbsorbAll" then
        return tooltipText
    end

    local contextText = getText("ContextMenu_BurdJournals_AbsorbAll")
    if contextText ~= "ContextMenu_BurdJournals_AbsorbAll" then
        return contextText
    end

    local uiText = getText("UI_BurdJournals_AbsorbAll")
    if uiText ~= "UI_BurdJournals_AbsorbAll" then
        return uiText
    end

    return nil
end

local function appendRewardAvailabilityLine(lines, key, availableCount, totalCount)
    if type(lines) ~= "table" then
        return
    end
    if not (tonumber(totalCount) and tonumber(totalCount) > 0) then
        return
    end
    local template = getText(key)
    if template == key then
        return
    end
    lines[#lines + 1] = BurdJournals.formatText(
        template,
        tonumber(availableCount) or 0,
        tonumber(totalCount) or 0
    )
end

local function finalizePromptModalForPlayer(player, modal)
    if not modal then
        return nil
    end
    if modal.addToUIManager then
        modal:addToUIManager()
    end
    if BurdJournals.applyJoypadSupportToModal then
        BurdJournals.applyJoypadSupportToModal(modal, player)
    end
    return modal
end

function BurdJournals.ContextMenu.applyLightRequirement(option, player)
    if not option then return end
    if not BurdJournals.requiresLightForJournalUse or not BurdJournals.requiresLightForJournalUse() then
        return
    end

    local canUse, reason = BurdJournals.canUseJournalInCurrentLight(player)
    if canUse then
        return
    end

    local message = reason or BurdJournals.ContextMenu.getTooDarkMessage()
    option.notAvailable = true

    local tooltip = option.toolTip
    if not tooltip then
        tooltip = ISToolTip:new()
        tooltip:initialise()
        tooltip:setVisible(false)
        tooltip:setName(getText("ContextMenu_TooDark") or "Too dark")
    end

    if tooltip.description and tooltip.description ~= "" then
        if not string.find(tooltip.description, message, 1, true) then
            tooltip.description = normalizeTooltipTextForDisplay(tooltip.description .. "\n\n" .. message)
        end
    else
        tooltip.description = normalizeTooltipTextForDisplay(message)
    end

    option.toolTip = tooltip
end

local function markLootRewardsRevealedLocally(journal, player)
    if not journal then
        return false
    end

    local data = getMutableContextJournalData(journal)
    if type(data) ~= "table" or data.isPlayerCreated == true or data.lootRewardsRevealed == true then
        return false
    end

    if BurdJournals.resolveJournalUUIDForRuntime then
        BurdJournals.resolveJournalUUIDForRuntime(data, journal, false)
    end
    data.lootRewardsRevealed = true
    if player then
        data.lootRewardsRevealedByName = (player.getDisplayName and player:getDisplayName())
            or (player.getUsername and player:getUsername())
            or data.lootRewardsRevealedByName
    end
    if getGameTime and getGameTime() and getGameTime().getWorldAgeHours then
        data.lootRewardsRevealedAtHours = getGameTime():getWorldAgeHours()
    end
    if BurdJournals.Client and BurdJournals.Client.markLootRewardRevealedLocally then
        BurdJournals.Client.markLootRewardRevealedLocally(journal, data)
    end
    if BurdJournals.updateJournalName then
        BurdJournals.updateJournalName(journal, true)
    end
    if BurdJournals.updateJournalIcon then
        BurdJournals.updateJournalIcon(journal)
    end
    local container = journal.getContainer and journal:getContainer() or nil
    if container and container.setDrawDirty then
        BurdJournals.safePcall(function()
            container:setDrawDirty(true)
        end)
    end
    return true
end

function BurdJournals.ContextMenu.onFillInventoryObjectContextMenu(playerNum, context, items)

    if not BurdJournals.isEnabled() then

        return
    end

    local player = getSpecificPlayer(playerNum)
    if not player then

        return
    end

    local itemList = {}
    for i, v in ipairs(items) do
        if instanceof(v, "InventoryItem") then

            table.insert(itemList, v)
        elseif type(v) == "table" and v.items then

            local stackItems = v.items
            if stackItems.size then

                for j = 0, stackItems:size() - 1 do
                    local item = stackItems:get(j)
                    table.insert(itemList, item)
                end
            else

                for j, item in ipairs(stackItems) do
                    table.insert(itemList, item)
                end
            end
        end
    end

    for _, item in ipairs(itemList) do
        local fullType = item:getFullType()
        local isJournal = BurdJournals.isAnyJournal(item)

        if isJournal then
            BurdJournals.ContextMenu.addJournalOptions(context, player, item)
            break
        end
    end
end

function BurdJournals.ContextMenu.removeVanillaReadOptions(context)

    local vanillaReadTexts = {
        getText("ContextMenu_Read") or "Read",
        getText("ContextMenu_ReRead") or "Re-read",
        getText("ContextMenu_Look_at_picture") or "Look at picture",
        getText("ContextMenu_Look_at_pictures") or "Look at pictures",
        getText("ContextMenu_ReLook_at_picture") or "Re-look at picture",
        getText("ContextMenu_ReLook_at_pictures") or "Re-look at pictures",
    }

    local optionsToRemove = {}
    if context.options then
        for i, option in ipairs(context.options) do
            if option.name then
                for _, vanillaText in ipairs(vanillaReadTexts) do
                    if option.name == vanillaText then
                        table.insert(optionsToRemove, i)
                        break
                    end
                end
            end
        end
    end

    for i = #optionsToRemove, 1, -1 do
        table.remove(context.options, optionsToRemove[i])
    end
end

function BurdJournals.ContextMenu.addJournalOptions(context, player, journal)

    if not context or not player or not journal then return end

    BurdJournals.ContextMenu.removeVanillaReadOptions(context)

    if BurdJournals.isPlayerIlliterate(player) then
        local illiterateOption = context:addOption(
            getText("ContextMenu_BurdJournals_CannotRead") or "Cannot Read (Illiterate)",
            nil, nil
        )
        illiterateOption.notAvailable = true
        local tooltip = ISToolTip:new()
        tooltip:initialise()
        tooltip:setVisible(false)
        tooltip:setName(getText("Tooltip_BurdJournals_IlliterateName") or "Illiterate")
        tooltip.description = normalizeTooltipTextForDisplay(getText("Tooltip_BurdJournals_IlliterateDesc") or "You cannot read or write. Journals are useless to you.")
        illiterateOption.toolTip = tooltip
        return
    end

    local isBloody = BurdJournals.isBloody(journal)
    local isWorn = BurdJournals.isWorn(journal)
    local isClean = BurdJournals.isClean(journal)
    local isBlank = BurdJournals.isBlankJournal(journal)
    local isFilled = BurdJournals.isFilledJournal(journal)
    local isCursedItem = BurdJournals.isCursedJournalItem and BurdJournals.isCursedJournalItem(journal)
    local isWrappedYuletide = BurdJournals.isWrappedYuletideJournal and BurdJournals.isWrappedYuletideJournal(journal)
    local isUnwrappedYuletide = BurdJournals.isUnwrappedYuletideJournal and BurdJournals.isUnwrappedYuletideJournal(journal)
    local isHiddenCursed = BurdJournals.isHiddenCursedJournal and BurdJournals.isHiddenCursedJournal(journal) or false

    if isHiddenCursed then
        isCursedItem = false
        isBloody = true
        isClean = false
        isFilled = true
    end

    if isWrappedYuletide then
        BurdJournals.ContextMenu.addYuletideJournalOptions(context, player, journal)
        return
    end

    if isUnwrappedYuletide then
        BurdJournals.ContextMenu.addUnwrappedYuletideJournalOptions(context, player, journal)
        return
    end

    if isCursedItem then
        BurdJournals.ContextMenu.addCursedJournalOptions(context, player, journal)
        return
    end

    -- Registered sealed archetypes (e.g. Blessed) that are still sealed offer a
    -- generic "Break the Seal" option. Built-in cursed journals are routed above
    -- so Cursed Insight can corrupt the cursed-specific seal label.
    if BurdJournals.isJournalSealed and BurdJournals.isJournalSealed(journal) then
        BurdJournals.ContextMenu.addSealedJournalOptions(context, player, journal)
        return
    end

    if BurdJournals.isBrokenSealedLootRewardJournal
        and BurdJournals.isBrokenSealedLootRewardJournal(journal)
    then
        BurdJournals.ContextMenu.addSealedLootRewardJournalOptions(context, player, journal)
        return
    end

    if isBloody then

        BurdJournals.ContextMenu.addBloodyJournalOptions(context, player, journal, isBlank)
    elseif isWorn then

        BurdJournals.ContextMenu.addWornJournalOptions(context, player, journal, isBlank)
    elseif isClean then

        if isFilled then
            BurdJournals.ContextMenu.addCleanFilledJournalOptions(context, player, journal)
        else
            BurdJournals.ContextMenu.addCleanBlankJournalOptions(context, player, journal)
        end
    else
    end
end

function BurdJournals.ContextMenu.getCursedInsightContextLabel(player, journal, isHiddenCursed, isSealedCursed, baseLabel)
    baseLabel = baseLabel or getText("ContextMenu_BurdJournals_OpenJournal") or "Open Journal..."
    local insightLevel = BurdJournals.getCursedInsightLevel
        and select(1, BurdJournals.getCursedInsightLevel(player))
        or 0
    if isHiddenCursed == true then
        if BurdJournals.Client and BurdJournals.Client.requestCursedInsightPreview then
            BurdJournals.Client.requestCursedInsightPreview(player, journal)
        end
        if insightLevel >= 3 then
            return BurdJournals.safeGetText("ContextMenu_BurdJournals_OpenJournalCorrupt3", "Op e n J ou r na l . ..")
        elseif insightLevel >= 2 then
            return BurdJournals.safeGetText("ContextMenu_BurdJournals_OpenJournalCorrupt2", "Ope n Jo u rnal...")
        elseif insightLevel >= 1 then
            return BurdJournals.safeGetText("ContextMenu_BurdJournals_OpenJournalCorrupt1", "Open Jou rnal...")
        end
    elseif isSealedCursed == true and insightLevel >= 2 then
        if BurdJournals.Client and BurdJournals.Client.requestCursedInsightPreview then
            BurdJournals.Client.requestCursedInsightPreview(player, journal)
        end
        if insightLevel >= 3 then
            return BurdJournals.safeGetText("ContextMenu_BurdJournals_BreakSealCorrupt3", "Br e ak t he S e al . ..")
        end
        return BurdJournals.safeGetText("ContextMenu_BurdJournals_BreakSealCorrupt2", "Break t he Se al...")
    end
    return baseLabel
end

function BurdJournals.ContextMenu.addYuletideJournalOptions(context, player, journal)
    local openOption = context:addOption(
        BurdJournals.safeGetText("ContextMenu_BurdJournals_OpenYuletideJournal", "Unwrap Gift Journal..."),
        player,
        BurdJournals.ContextMenu.onOpenYuletideJournal,
        journal
    )
    local tooltip = ISToolTip:new()
    tooltip:initialise()
    tooltip:setVisible(false)
    tooltip:setName(BurdJournals.safeGetText("Tooltip_BurdJournals_YuletideJournalName", "Yuletide Journal (Wrapped)"))
    tooltip.description = normalizeTooltipTextForDisplay(BurdJournals.safeGetText("Tooltip_BurdJournals_YuletideJournalDesc"))
        or "A wrapped holiday journal. Unwrap it to reveal the journal and its bundled supplies."
    openOption.toolTip = tooltip
    BurdJournals.ContextMenu.applyLightRequirement(openOption, player)
end

function BurdJournals.ContextMenu.addSealedLootRewardJournalOptions(context, player, journal)
    if not context or not player or not journal then return end

    local journalData = getNormalizedContextJournalData(journal)
    local sealedEntry = BurdJournals.getSealedJournalType and BurdJournals.getSealedJournalType(journal) or nil
    local displayName = nil
    if sealedEntry and sealedEntry.displayNameKey then
        displayName = BurdJournals.safeGetText(sealedEntry.displayNameKey, nil)
    end
    displayName = displayName or BurdJournals.safeGetText("Tooltip_BurdJournals_LootRewardJournal", "Reward Journal")

    local openOption = context:addOption(
        getText("ContextMenu_BurdJournals_OpenJournal") or "Open Journal...",
        player,
        BurdJournals.ContextMenu.onOpenSealedLootRewardJournal,
        journal
    )

    local tooltip = ISToolTip:new()
    tooltip:initialise()
    tooltip:setVisible(false)
    tooltip:setName(displayName)

    local skillCount = 0
    local totalSkills = 0
    local traitCount = 0
    local totalTraits = 0
    local recipeCount = 0
    local totalRecipes = 0
    if journalData then
        if journalData.skills then
            for skillName, _ in pairs(journalData.skills) do
                totalSkills = totalSkills + 1
                if not BurdJournals.hasCharacterClaimedSkill(journalData, player, skillName) then
                    skillCount = skillCount + 1
                end
            end
        end
        if journalData.traits then
            for traitId, _ in pairs(journalData.traits) do
                totalTraits = totalTraits + 1
                if not BurdJournals.hasCharacterClaimedTrait(journalData, player, traitId) then
                    traitCount = traitCount + 1
                end
            end
        end
        if journalData.recipes then
            for recipeName, _ in pairs(journalData.recipes) do
                totalRecipes = totalRecipes + 1
                if not BurdJournals.hasCharacterClaimedRecipe(journalData, player, recipeName) then
                    recipeCount = recipeCount + 1
                end
            end
        end
    end

    local tooltipLines = {}
    appendRewardAvailabilityLine(tooltipLines, "Tooltip_BurdJournals_SkillsAvailable", skillCount, totalSkills)
    appendRewardAvailabilityLine(tooltipLines, "Tooltip_BurdJournals_TraitsAvailable", traitCount, totalTraits)
    appendRewardAvailabilityLine(tooltipLines, "Tooltip_BurdJournals_RecipesAvailable", recipeCount, totalRecipes)
    if #tooltipLines == 0 then
        tooltipLines[#tooltipLines + 1] = BurdJournals.safeGetText("Tooltip_BurdJournals_NoRewardsFound", "No rewards found")
    end
    tooltip.description = normalizeTooltipTextForDisplay(table.concat(tooltipLines, "\n"))
    openOption.toolTip = tooltip
    BurdJournals.ContextMenu.applyLightRequirement(openOption, player)
end

function BurdJournals.ContextMenu.addUnwrappedYuletideJournalOptions(context, player, journal)
    local journalData = getNormalizedContextJournalData(journal)
    local hideDetails = shouldHideLootDetailsInContext(journal)
    local openOption = context:addOption(
        getText("ContextMenu_BurdJournals_OpenJournal") or "Open Journal...",
        player,
        BurdJournals.ContextMenu.onOpenYuletideRewardJournal,
        journal
    )

    if journalData then
        local skillCount, totalSkills = 0, 0
        local traitCount, totalTraits = 0, 0
        local recipeCount, totalRecipes = 0, 0
        local statCount, totalStats = 0, 0

        if journalData.skills then
            for skillName, _ in pairs(journalData.skills) do
                totalSkills = totalSkills + 1
                if not BurdJournals.hasCharacterClaimedSkill(journalData, player, skillName) then
                    skillCount = skillCount + 1
                end
            end
        end
        if journalData.traits then
            for traitId, _ in pairs(journalData.traits) do
                totalTraits = totalTraits + 1
                if not BurdJournals.hasCharacterClaimedTrait(journalData, player, traitId) then
                    traitCount = traitCount + 1
                end
            end
        end
        if journalData.recipes then
            for recipeName, _ in pairs(journalData.recipes) do
                totalRecipes = totalRecipes + 1
                if not BurdJournals.hasCharacterClaimedRecipe(journalData, player, recipeName) then
                    recipeCount = recipeCount + 1
                end
            end
        end
        if journalData.stats then
            for statId, _ in pairs(journalData.stats) do
                totalStats = totalStats + 1
                if not BurdJournals.hasCharacterClaimedStat or not BurdJournals.hasCharacterClaimedStat(journalData, player, statId) then
                    statCount = statCount + 1
                end
            end
        end

        local tooltip = ISToolTip:new()
        tooltip:initialise()
        tooltip:setVisible(false)
        tooltip:setName(BurdJournals.safeGetText("Tooltip_BurdJournals_YuletideJournalUnwrappedName", "Yuletide Journal"))
        local author = (BurdJournals.getJournalDisplayAuthor and BurdJournals.getJournalDisplayAuthor(journalData))
            or BurdJournals.safeGetText("UI_BurdJournals_Unknown", "Unknown")
        local desc = BurdJournals.formatText(BurdJournals.safeGetText("Tooltip_BurdJournals_WrittenBy", "Written by: %s"), author) .. "\n"
        local professionName = BurdJournals.resolveProfessionName and BurdJournals.resolveProfessionName(journalData) or journalData.professionName
        if professionName and professionName ~= "" then
            desc = desc .. BurdJournals.formatText(BurdJournals.safeGetText("Tooltip_BurdJournals_Profession", "Profession: %s"), professionName) .. "\n"
        end
        if hideDetails then
            desc = desc .. BurdJournals.safeGetText("Tooltip_BurdJournals_UnopenedLootRewardDesc", "Open to inspect the contents.") .. "\n"
        else
            if totalSkills > 0 then
                desc = desc .. BurdJournals.formatText(BurdJournals.safeGetText("Tooltip_BurdJournals_SkillsAvailable", "Skills: %d/%d available"), skillCount, totalSkills) .. "\n"
            end
            if totalTraits > 0 then
                desc = desc .. BurdJournals.formatText(BurdJournals.safeGetText("Tooltip_BurdJournals_TraitsAvailable", "Traits: %d/%d available"), traitCount, totalTraits) .. "\n"
            end
            if totalRecipes > 0 then
                desc = desc .. BurdJournals.formatText(BurdJournals.safeGetText("Tooltip_BurdJournals_RecipesAvailable", "Recipes: %d/%d available"), recipeCount, totalRecipes) .. "\n"
            end
            if totalStats > 0 then
                desc = desc .. BurdJournals.formatText(BurdJournals.safeGetText("Tooltip_BurdJournals_StatsAvailable", "Stats: %d/%d available"), statCount, totalStats) .. "\n"
            end
        end
        desc = desc .. "\n" .. BurdJournals.safeGetText("Tooltip_BurdJournals_YuletideJournalOpenedDesc", "A festive loot journal filled with rewards and notes from Santa.")
        tooltip.description = normalizeTooltipTextForDisplay(desc)
        openOption.toolTip = tooltip
    end

    BurdJournals.ContextMenu.applyLightRequirement(openOption, player)

    if BurdJournals.isPlayerJournalCraftingEnabled and BurdJournals.isPlayerJournalCraftingEnabled() then
        local canConvert = BurdJournals.canConvertToClean(player)
        local convertOption = context:addOption(
            getText("ContextMenu_BurdJournals_ConvertToClean") or "Convert to Personal Journal",
            player,
            BurdJournals.ContextMenu.onConvertToClean,
            journal
        )
        if not canConvert then
            convertOption.notAvailable = true
            local tooltip = ISToolTip:new()
            tooltip:initialise()
            tooltip:setVisible(false)
            tooltip:setName(getText("Tooltip_BurdJournals_CannotConvert") or "Cannot Convert")
            tooltip.description = normalizeTooltipTextForDisplay(getText("Tooltip_BurdJournals_NeedsConvertMaterials") or "Requires: Leather + Thread + Needle + Tailoring Lv1")
            convertOption.toolTip = tooltip
        else
            local tooltip = ISToolTip:new()
            tooltip:initialise()
            tooltip:setVisible(false)
            tooltip:setName(getText("Tooltip_BurdJournals_ConvertToClean") or "Convert to Personal Journal")
            tooltip.description = normalizeTooltipTextForDisplay(getText("Tooltip_BurdJournals_ConvertToCleanDesc") or "Restore this worn journal to a clean blank journal for personal use.")
            convertOption.toolTip = tooltip
        end
    end
end

function BurdJournals.ContextMenu.addCursedJournalOptions(context, player, journal)
    local openOption = context:addOption(
        BurdJournals.ContextMenu.getCursedInsightContextLabel(
            player,
            journal,
            false,
            true,
            getText("ContextMenu_BurdJournals_OpenCursedJournal") or "Break the Seal..."
        ),
        player,
        BurdJournals.ContextMenu.onOpenCursedJournal,
        journal
    )
    local tooltip = ISToolTip:new()
    tooltip:initialise()
    tooltip:setVisible(false)
    tooltip:setName(getText("Tooltip_BurdJournals_CursedJournalName") or "Cursed Journal")
    tooltip.description = normalizeTooltipTextForDisplay(getText("Tooltip_BurdJournals_CursedJournalDesc"))
        or "An unsettling journal. The first reader will pay a price."
    openOption.toolTip = tooltip
    BurdJournals.ContextMenu.applyLightRequirement(openOption, player)
end

-- Generic "Break the Seal" option for any registered sealed journal type still
-- in the sealed state. The label/tooltip come from the registered type's
-- theme so add-ons don't need to patch this file.
function BurdJournals.ContextMenu.addSealedJournalOptions(context, player, journal)
    local entry = BurdJournals.getSealedJournalType and BurdJournals.getSealedJournalType(journal) or nil
    local themeKey = entry and entry.themeKey or nil
    local labelKey = themeKey and ("ContextMenu_BurdJournals_BreakSeal_" .. themeKey) or nil
    local label = (labelKey and BurdJournals.safeGetText(labelKey, nil))
        or BurdJournals.safeGetText("ContextMenu_BurdJournals_BreakSeal", "Break the Seal...")

    local openOption = context:addOption(
        label,
        player,
        BurdJournals.ContextMenu.onBreakJournalSeal,
        journal
    )
    local tooltip = ISToolTip:new()
    tooltip:initialise()
    tooltip:setVisible(false)
    local nameKey = themeKey and ("Tooltip_BurdJournals_SealedName_" .. themeKey) or nil
    local descKey = themeKey and ("Tooltip_BurdJournals_SealedDesc_" .. themeKey) or nil
    tooltip:setName((nameKey and BurdJournals.safeGetText(nameKey, nil)) or BurdJournals.safeGetText("Tooltip_BurdJournals_SealedName", "Sealed Journal"))
    tooltip.description = normalizeTooltipTextForDisplay(
        (descKey and BurdJournals.safeGetText(descKey, nil))
        or BurdJournals.safeGetText("Tooltip_BurdJournals_SealedDesc", "A sealed journal. Break the seal to reveal what lies within.")
    )
    openOption.toolTip = tooltip
    BurdJournals.ContextMenu.applyLightRequirement(openOption, player)
end

function BurdJournals.ContextMenu.addBloodyJournalOptions(context, player, journal, isBlank)
    local journalData = getNormalizedContextJournalData(journal)
    local isHiddenCursed = BurdJournals.isHiddenCursedJournal and BurdJournals.isHiddenCursedJournal(journal) or false
    local isFilled = (BurdJournals.isFilledJournal and BurdJournals.isFilledJournal(journal)) or isHiddenCursed
    local hideDetails = shouldHideLootDetailsInContext(journal)

    if isHiddenCursed and not journalData then
        local openOption = context:addOption(
            BurdJournals.ContextMenu.getCursedInsightContextLabel(player, journal, true, false),
            player,
            BurdJournals.ContextMenu.onOpenBloodyJournal,
            journal
        )
        local tooltip = ISToolTip:new()
        tooltip:initialise()
        tooltip:setVisible(false)
        tooltip:setName(getText("Tooltip_BurdJournals_BloodyJournal") or "Bloody Journal")
        tooltip.description = normalizeTooltipTextForDisplay(
            BurdJournals.safeGetText("Tooltip_BurdJournals_UnopenedLootRewardDesc", "Open to inspect the contents.")
        )
        openOption.toolTip = tooltip
        BurdJournals.ContextMenu.applyLightRequirement(openOption, player)
        return
    end

    if isFilled and journalData then

        local skillCount = 0
        local totalSkills = 0
        local traitCount = 0
        local totalTraits = 0
        local recipeCount = 0
        local totalRecipes = 0

        if journalData.skills then
            for skillName, _ in pairs(journalData.skills) do
                totalSkills = totalSkills + 1
                if not BurdJournals.hasCharacterClaimedSkill(journalData, player, skillName) then
                    skillCount = skillCount + 1
                end
            end
        end
        if journalData.traits then
            for traitId, _ in pairs(journalData.traits) do
                totalTraits = totalTraits + 1
                if not BurdJournals.hasCharacterClaimedTrait(journalData, player, traitId) then
                    traitCount = traitCount + 1
                end
            end
        end
        if journalData.recipes then
            for recipeName, _ in pairs(journalData.recipes) do
                totalRecipes = totalRecipes + 1
                if not BurdJournals.hasCharacterClaimedRecipe(journalData, player, recipeName) then
                    recipeCount = recipeCount + 1
                end
            end
        end

        local remaining = skillCount + traitCount + recipeCount

        local openOption = context:addOption(
            BurdJournals.ContextMenu.getCursedInsightContextLabel(player, journal, isHiddenCursed, false),
            player,
            BurdJournals.ContextMenu.onOpenBloodyJournal,
            journal
        )
        local tooltip = ISToolTip:new()
        tooltip:initialise()
        tooltip:setVisible(false)
        tooltip:setName(getText("Tooltip_BurdJournals_BloodyJournal") or "Bloody Journal")

        local tooltipLines = {}
        if hideDetails then
            tooltipLines[#tooltipLines + 1] = BurdJournals.safeGetText("Tooltip_BurdJournals_UnopenedLootRewardDesc", "Open to inspect the contents.")
        else
            appendRewardAvailabilityLine(tooltipLines, "Tooltip_BurdJournals_SkillsAvailable", skillCount, totalSkills)
            appendRewardAvailabilityLine(tooltipLines, "Tooltip_BurdJournals_TraitsAvailable", traitCount, totalTraits)
            appendRewardAvailabilityLine(tooltipLines, "Tooltip_BurdJournals_RecipesAvailable", recipeCount, totalRecipes)
        end
        if #tooltipLines == 0 then
            tooltipLines[#tooltipLines + 1] = BurdJournals.safeGetText("Tooltip_BurdJournals_NoRewardsFound", "No rewards found")
        end
        local tooltipDesc = table.concat(tooltipLines, "\n")
        tooltipDesc = tooltipDesc .. "\n\n" .. (BurdJournals.safeGetText("Tooltip_BurdJournals_BloodyDesc", "Rare find! May contain valuable traits.") or "Rare find! May contain valuable traits.")
        tooltip.description = normalizeTooltipTextForDisplay(tooltipDesc)
        openOption.toolTip = tooltip
        BurdJournals.ContextMenu.applyLightRequirement(openOption, player)

        if remaining > 0 and not BurdJournals.isLimitedClaimLootJournalActive(journal) then

            local parts = {}
            if skillCount > 0 then
                local skillKey = skillCount > 1 and "ContextMenu_BurdJournals_SkillsCount" or "ContextMenu_BurdJournals_SkillCount"
                table.insert(parts, BurdJournals.formatText(getText(skillKey) or "%d skills", skillCount))
            end
            if traitCount > 0 then
                local traitKey = traitCount > 1 and "ContextMenu_BurdJournals_TraitsCount" or "ContextMenu_BurdJournals_TraitCount"
                table.insert(parts, BurdJournals.formatText(getText(traitKey) or "%d traits", traitCount))
            end
            if recipeCount > 0 then
                local recipeKey = recipeCount > 1 and "ContextMenu_BurdJournals_RecipesCount" or "ContextMenu_BurdJournals_RecipeCount"
                table.insert(parts, BurdJournals.formatText(getText(recipeKey) or "%d recipes", recipeCount))
            end

            local absorbLabel
            if hideDetails then
                absorbLabel = getStaticAbsorbAllContextLabel()
            elseif #parts > 0 then
                local absorbAllBase = getText("ContextMenu_BurdJournals_AbsorbAllFormat") or "Absorb All (%s)"
                absorbLabel = BurdJournals.formatText(absorbAllBase, table.concat(parts, ", "))
            else
                absorbLabel = getText("Tooltip_BurdJournals_AbsorbAllRewards") or "Absorb All Rewards"
            end

            local absorbAllOption = context:addOption(
                absorbLabel,
                player,
                BurdJournals.ContextMenu.onAbsorbAllConfirm,
                journal
            )
            local tooltip2 = ISToolTip:new()
            tooltip2:initialise()
            tooltip2:setVisible(false)
            tooltip2:setName(getText("Tooltip_BurdJournals_AbsorbAllRewards") or "Absorb All Rewards")
            tooltip2.description = normalizeTooltipTextForDisplay(getText("Tooltip_BurdJournals_AbsorbAllDesc") or "Opens the journal and begins reading all rewards.\nRequires time to absorb each skill, trait, and recipe.\nMaxed skills and known items will be skipped.")
            absorbAllOption.toolTip = tooltip2
            BurdJournals.ContextMenu.applyLightRequirement(absorbAllOption, player)
        end
    else

        local infoOption = context:addOption(
            getText("ContextMenu_BurdJournals_BloodyBlank") or "Bloody Blank Journal",
            nil, nil
        )
        infoOption.notAvailable = true
    end

    if BurdJournals.isPlayerJournalCraftingEnabled and BurdJournals.isPlayerJournalCraftingEnabled() then
        local craftOption = context:addOption(
            getText("ContextMenu_BurdJournals_ConvertViaCrafting") or "Convert to Personal Journal...",
            nil, nil
        )
        craftOption.notAvailable = true
        local tooltip3 = ISToolTip:new()
        tooltip3:initialise()
        tooltip3:setVisible(false)
        tooltip3:setName(getText("Tooltip_BurdJournals_CraftingRequired") or "Crafting Required")
        tooltip3.description = normalizeTooltipTextForDisplay(getText("Tooltip_BurdJournals_ConvertBloodyDesc") or "Open the crafting menu (B) to find 'Clean and Convert Bloody Journal'.\nRequires: Soap, Cloth, Leather, Thread, Needle, Tailoring Lv1.\nWARNING: Destroys any remaining rewards!")
        craftOption.toolTip = tooltip3
    end
end

function BurdJournals.ContextMenu.addWornJournalOptions(context, player, journal, isBlank)

    if not context or not player or not journal then return end

    local journalData = getNormalizedContextJournalData(journal)
        local isFilled = BurdJournals.isFilledJournal(journal)
        local hideDetails = shouldHideLootDetailsInContext(journal)

        if isFilled and journalData then

            local skillCount = 0
            local totalSkills = 0
            local traitCount = 0
            local totalTraits = 0
            local recipeCount = 0
            local totalRecipes = 0

            if journalData.skills then
                for skillName, _ in pairs(journalData.skills) do
                    totalSkills = totalSkills + 1
                    if not BurdJournals.hasCharacterClaimedSkill(journalData, player, skillName) then
                        skillCount = skillCount + 1
                    end
                end
            end
            if journalData.traits then
                for traitId, _ in pairs(journalData.traits) do
                    totalTraits = totalTraits + 1
                    if not BurdJournals.hasCharacterClaimedTrait(journalData, player, traitId) then
                        traitCount = traitCount + 1
                    end
                end
            end
            if journalData.recipes then
                for recipeName, _ in pairs(journalData.recipes) do
                    totalRecipes = totalRecipes + 1
                    if not BurdJournals.hasCharacterClaimedRecipe(journalData, player, recipeName) then
                        recipeCount = recipeCount + 1
                    end
                end
            end

            local remaining = skillCount + traitCount + recipeCount

            local openText = getText("ContextMenu_BurdJournals_OpenJournal") or "Open Journal..."

            local openOption = context:addOption(
                openText,
                player,
                BurdJournals.ContextMenu.onOpenWornJournal,
                journal
            )
        local tooltip = ISToolTip:new()
        tooltip:initialise()
        tooltip:setVisible(false)
        tooltip:setName(getText("Tooltip_BurdJournals_WornJournal") or "Worn Journal")

        local tooltipLines = {}
        if hideDetails then
            tooltipLines[#tooltipLines + 1] = BurdJournals.safeGetText("Tooltip_BurdJournals_UnopenedLootRewardDesc", "Open to inspect the contents.")
        else
            appendRewardAvailabilityLine(tooltipLines, "Tooltip_BurdJournals_SkillsAvailable", skillCount, totalSkills)
            appendRewardAvailabilityLine(tooltipLines, "Tooltip_BurdJournals_RecipesAvailable", recipeCount, totalRecipes)
        end
        if #tooltipLines == 0 then
            tooltipLines[#tooltipLines + 1] = BurdJournals.safeGetText("Tooltip_BurdJournals_NoRewardsFound", "No rewards found")
        end
        local tooltipDesc = table.concat(tooltipLines, "\n")
        tooltip.description = normalizeTooltipTextForDisplay(tooltipDesc)
        openOption.toolTip = tooltip
        BurdJournals.ContextMenu.applyLightRequirement(openOption, player)

        if remaining > 0 and not BurdJournals.isLimitedClaimLootJournalActive(journal) then

            local parts = {}
            if skillCount > 0 then
                local skillKey = skillCount > 1 and "ContextMenu_BurdJournals_SkillsCount" or "ContextMenu_BurdJournals_SkillCount"
                table.insert(parts, BurdJournals.formatText(getText(skillKey) or "%d skills", skillCount))
            end
            if traitCount > 0 then
                local traitKey = traitCount > 1 and "ContextMenu_BurdJournals_TraitsCount" or "ContextMenu_BurdJournals_TraitCount"
                table.insert(parts, BurdJournals.formatText(getText(traitKey) or "%d traits", traitCount))
            end
            if recipeCount > 0 then
                local recipeKey = recipeCount > 1 and "ContextMenu_BurdJournals_RecipesCount" or "ContextMenu_BurdJournals_RecipeCount"
                table.insert(parts, BurdJournals.formatText(getText(recipeKey) or "%d recipes", recipeCount))
            end

            local absorbLabel
            if hideDetails then
                absorbLabel = getStaticAbsorbAllContextLabel()
            elseif #parts > 0 then
                local absorbAllBase = getText("ContextMenu_BurdJournals_AbsorbAllFormat") or "Absorb All (%s)"
                absorbLabel = BurdJournals.formatText(absorbAllBase, table.concat(parts, ", "))
            else
                absorbLabel = getText("Tooltip_BurdJournals_AbsorbAllRewards") or "Absorb All Rewards"
            end

            local absorbAllOption = context:addOption(
                absorbLabel,
                player,
                BurdJournals.ContextMenu.onAbsorbAllConfirm,
                journal
            )
            local tooltip2 = ISToolTip:new()
            tooltip2:initialise()
            tooltip2:setVisible(false)
            tooltip2:setName(getText("Tooltip_BurdJournals_AbsorbAllRewards") or "Absorb All Rewards")
            tooltip2.description = normalizeTooltipTextForDisplay(getText("Tooltip_BurdJournals_AbsorbAllDesc") or "Opens the journal and begins reading all rewards.\nRequires time to absorb each skill, trait, and recipe.\nMaxed skills and known items will be skipped.")
            absorbAllOption.toolTip = tooltip2
            BurdJournals.ContextMenu.applyLightRequirement(absorbAllOption, player)
        end
    else

        local infoOption = context:addOption(
            getText("ContextMenu_BurdJournals_WornBlank") or "Worn Blank Journal",
            nil, nil
        )
        infoOption.notAvailable = true
    end

    if BurdJournals.isPlayerJournalCraftingEnabled and BurdJournals.isPlayerJournalCraftingEnabled() then
        local canConvert = BurdJournals.canConvertToClean(player)
        local convertOption = context:addOption(
            getText("ContextMenu_BurdJournals_ConvertToClean") or "Convert to Personal Journal",
            player,
            BurdJournals.ContextMenu.onConvertToClean,
            journal
        )
        if not canConvert then
            convertOption.notAvailable = true
            local tooltip3 = ISToolTip:new()
            tooltip3:initialise()
            tooltip3:setVisible(false)
            tooltip3:setName(getText("Tooltip_BurdJournals_CannotConvert") or "Cannot Convert")
            tooltip3.description = normalizeTooltipTextForDisplay(getText("Tooltip_BurdJournals_NeedsConvertMaterials") or "Requires: Leather + Thread + Needle + Tailoring Lv1")
            convertOption.toolTip = tooltip3
        else
            local tooltip3 = ISToolTip:new()
            tooltip3:initialise()
            tooltip3:setVisible(false)
            tooltip3:setName(getText("Tooltip_BurdJournals_ConvertToClean") or "Convert to Personal Journal")
            tooltip3.description = normalizeTooltipTextForDisplay(getText("Tooltip_BurdJournals_ConvertToCleanDesc") or "Restore this worn journal to a clean blank journal for personal use.")
            convertOption.toolTip = tooltip3
        end
    end

end

function BurdJournals.ContextMenu.addCleanFilledJournalOptions(context, player, journal)
    local journalData = BurdJournals.getJournalData(journal)
    local penRequired = BurdJournals.getSandboxOption("RequirePenToWrite") ~= false
    local hasPen = (not penRequired) or BurdJournals.hasWritingTool(player)
    local hasEraser = BurdJournals.hasEraser(player)

    local canOpen, openReason = BurdJournals.canPlayerOpenJournal(player, journal)
    local canClaim, claimReason = BurdJournals.canPlayerClaimFromJournal(player, journal)
    local isOwner = BurdJournals.isJournalOwner(player, journal)

    local claimableSkills = 0
    local claimableTraits = 0
    local totalRecorded = 0
    if journalData then
        if journalData.skills then
            for skillName, skillData in pairs(journalData.skills) do
                totalRecorded = totalRecorded + 1
                local perk = BurdJournals.getPerkByName(skillName)
                if perk then
                    local playerXP = player:getXp():getXP(perk)
                    if playerXP < (skillData.xp or 0) then
                        claimableSkills = claimableSkills + 1
                    end
                end
            end
        end
        if journalData.traits then
            for traitId, _ in pairs(journalData.traits) do
                totalRecorded = totalRecorded + 1
                if not BurdJournals.playerHasTrait(player, traitId) then
                    claimableTraits = claimableTraits + 1
                end
            end
        end
    end
    local totalClaimable = claimableSkills + claimableTraits

    local openOption = context:addOption(
        getText("ContextMenu_BurdJournals_OpenJournal") or "Open Journal...",
        player,
        BurdJournals.ContextMenu.onOpenCleanJournal,
        journal
    )
    if not canOpen then
        openOption.notAvailable = true
        local tooltip = ISToolTip:new()
        tooltip:initialise()
        tooltip:setVisible(false)
        tooltip:setName(getText("Tooltip_BurdJournals_CannotOpen") or "Cannot Open")
        tooltip.description = normalizeTooltipTextForDisplay(openReason or "You don't have permission to open this journal.")
        openOption.toolTip = tooltip
    elseif journalData then
        local tooltip = ISToolTip:new()
        tooltip:initialise()
        tooltip:setVisible(false)
        tooltip:setName(getText("Tooltip_BurdJournals_PersonalJournal") or "Personal Survival Journal")
        local author = (BurdJournals.getJournalDisplayAuthor and BurdJournals.getJournalDisplayAuthor(journalData))
            or (getText("UI_BurdJournals_Unknown") or "Unknown")
        local desc = (getText("Tooltip_BurdJournals_WrittenBy") or "Written by: %s"):gsub("%%s", author) .. "\n"
        local itemText = totalRecorded > 1 and (getText("Tooltip_BurdJournals_RecordedItems") or "Contains %d recorded items") or (getText("Tooltip_BurdJournals_RecordedItem") or "Contains %d recorded item")
        desc = desc .. BurdJournals.formatText(itemText, totalRecorded) .. "\n\n"
        if claimableSkills > 0 or claimableTraits > 0 then
            if canClaim then
                desc = desc .. (getText("Tooltip_BurdJournals_ClaimableRewards") or "Claimable rewards:") .. "\n"
                if claimableSkills > 0 then
                    local skillText = claimableSkills > 1 and (getText("Tooltip_BurdJournals_SkillsCount") or "  - %d skills") or (getText("Tooltip_BurdJournals_SkillCount") or "  - %d skill")
                    desc = desc .. BurdJournals.formatText(skillText, claimableSkills) .. "\n"
                end
                if claimableTraits > 0 then
                    local traitText = claimableTraits > 1 and (getText("Tooltip_BurdJournals_TraitsCount") or "  - %d traits") or (getText("Tooltip_BurdJournals_TraitCount") or "  - %d trait")
                    desc = desc .. BurdJournals.formatText(traitText, claimableTraits) .. "\n"
                end
            else
                desc = desc .. (getText("Tooltip_BurdJournals_ViewOnly") or "View only") .. " - " .. (claimReason or (getText("Tooltip_BurdJournals_CannotClaimDefault") or "Cannot claim from this journal.")) .. "\n"
            end
        else
            desc = desc .. (getText("Tooltip_BurdJournals_NoNewRewards") or "No new rewards available.") .. "\n"
        end
        desc = desc .. "\n" .. (getText("Tooltip_BurdJournals_ClaimingInfo") or "Claiming sets your XP to the recorded level (if higher).")
        tooltip.description = normalizeTooltipTextForDisplay(desc)
        openOption.toolTip = tooltip
    end
    BurdJournals.ContextMenu.applyLightRequirement(openOption, player)

    if isOwner then
        local recordOption = context:addOption(
            getText("ContextMenu_BurdJournals_UpdateRecords") or "Update Records",
            player,
            BurdJournals.ContextMenu.onRecordProgress,
            journal
        )
        local tooltip = ISToolTip:new()
        tooltip:initialise()
        tooltip:setVisible(false)
        tooltip:setName(getText("Tooltip_BurdJournals_UpdateRecords") or "Update Journal Records")
        tooltip.description = normalizeTooltipTextForDisplay(getText("Tooltip_BurdJournals_UpdateRecordsDesc") or "Opens journal to update your recorded skills.\nRecorded values are only updated if your current level is higher.")
        recordOption.toolTip = tooltip
        if not hasPen then
            recordOption.notAvailable = true
            recordOption.toolTip.description = normalizeTooltipTextForDisplay(
                tostring(recordOption.toolTip.description or "")
                .. "\n\n"
                .. (getText("Tooltip_BurdJournals_BlankJournalDesc") or "Requires a writing tool.")
            )
        end
        BurdJournals.ContextMenu.applyLightRequirement(recordOption, player)
    end

    if totalClaimable > 0 and canOpen then
        local claimAllOption = context:addOption(
            getText("ContextMenu_BurdJournals_ClaimAll") or "Claim All",
            player,
            BurdJournals.ContextMenu.onClaimAllConfirm,
            journal
        )
        if not canClaim then
            claimAllOption.notAvailable = true
            local tooltip = ISToolTip:new()
            tooltip:initialise()
            tooltip:setVisible(false)
            tooltip:setName(getText("Tooltip_BurdJournals_CannotClaim") or "Cannot Claim")
            tooltip.description = normalizeTooltipTextForDisplay(claimReason or (getText("Tooltip_BurdJournals_NoPermissionClaim") or "You don't have permission to claim from this journal."))
            claimAllOption.toolTip = tooltip
        else
            local tooltip = ISToolTip:new()
            tooltip:initialise()
            tooltip:setVisible(false)
            tooltip:setName(getText("Tooltip_BurdJournals_ClaimAll") or "Claim All Skills")
            local desc = (getText("Tooltip_BurdJournals_ClaimAllDesc") or "Opens journal and claims all available skills.") .. "\n\n"
            local skillText = claimableSkills > 1 and (getText("Tooltip_BurdJournals_AvailableSkills") or "Available: %d skills") or (getText("Tooltip_BurdJournals_AvailableSkill") or "Available: %d skill")
            desc = desc .. BurdJournals.formatText(skillText, claimableSkills)
            if claimableTraits > 0 then
                local traitText = claimableTraits > 1 and (getText("Tooltip_BurdJournals_AndTraits") or ", %d traits") or (getText("Tooltip_BurdJournals_AndTrait") or ", %d trait")
                desc = desc .. BurdJournals.formatText(traitText, claimableTraits)
            end
            desc = desc .. "\n\n" .. (getText("Tooltip_BurdJournals_ReadingSpeedNote") or "This will take time based on your reading speed.")
            tooltip.description = normalizeTooltipTextForDisplay(desc)
            claimAllOption.toolTip = tooltip
        end
        BurdJournals.ContextMenu.applyLightRequirement(claimAllOption, player)
    end

    if isOwner then
        context:addOption(
            getText("ContextMenu_BurdJournals_Rename") or "Rename",
            player,
            BurdJournals.ContextMenu.onRenameJournal,
            journal
        )
    end

    if hasEraser and isOwner then
        local eraseOption = context:addOption(
            getText("ContextMenu_BurdJournals_EraseJournal") or "Erase Journal",
            player,
            BurdJournals.ContextMenu.onEraseJournal,
            journal
        )
        local tooltip = ISToolTip:new()
        tooltip:initialise()
        tooltip:setVisible(false)
        tooltip:setName(getText("Tooltip_BurdJournals_EraseContents") or "Erase All Contents")
        tooltip.description = normalizeTooltipTextForDisplay(getText("Tooltip_BurdJournals_EraseContentsDesc") or "Erases all recorded data, returning the journal to a blank state.\nRequires an eraser.")
        eraseOption.toolTip = tooltip
    end
end

function BurdJournals.ContextMenu.addCleanBlankJournalOptions(context, player, journal)
    local penRequired = BurdJournals.getSandboxOption("RequirePenToWrite") ~= false
    local hasPen = (not penRequired) or BurdJournals.hasWritingTool(player)

    local openOption = context:addOption(
        getText("ContextMenu_BurdJournals_OpenJournal") or "Open Journal...",
        player,
        BurdJournals.ContextMenu.onOpenCleanJournal,
        journal
    )
    local tooltip = ISToolTip:new()
    tooltip:initialise()
    tooltip:setVisible(false)
    tooltip:setName(getText("Tooltip_BurdJournals_BlankJournal") or "Blank Survival Journal")
    tooltip.description = normalizeTooltipTextForDisplay(
        getText("Tooltip_BurdJournals_BlankJournalDesc")
        or "Opens the journal.\nRecording progress requires a pen or pencil."
    )
    openOption.toolTip = tooltip
    BurdJournals.ContextMenu.applyLightRequirement(openOption, player)

    local recordOption = context:addOption(
        getText("ContextMenu_BurdJournals_RecordProgress") or "Record Progress",
        player,
        BurdJournals.ContextMenu.onRecordProgress,
        journal
    )
    local recordTooltip = ISToolTip:new()
    recordTooltip:initialise()
    recordTooltip:setVisible(false)
    recordTooltip:setName(getText("Tooltip_BurdJournals_RecordProgress") or "Record Your Progress")
    recordTooltip.description = normalizeTooltipTextForDisplay(
        getText("Tooltip_BurdJournals_RecordProgressDesc")
        or "Opens journal to record your current skills and traits.\nRecorded values are only updated if your current level is higher."
    )
    recordOption.toolTip = recordTooltip
    if not hasPen then
        recordOption.notAvailable = true
        recordOption.toolTip.description = normalizeTooltipTextForDisplay(
            tostring(recordOption.toolTip.description or "")
            .. "\n\n"
            .. (getText("Tooltip_BurdJournals_BlankJournalDesc") or "Requires a writing tool.")
        )
    end
    BurdJournals.ContextMenu.applyLightRequirement(recordOption, player)

    context:addOption(
        getText("ContextMenu_BurdJournals_Rename") or "Rename",
        player,
        BurdJournals.ContextMenu.onRenameJournal,
        journal
    )

    local disassembleOption = context:addOption(
        getText("ContextMenu_BurdJournals_Disassemble") or "Disassemble Journal",
        player,
        BurdJournals.ContextMenu.onDisassembleJournal,
        journal
    )
    local tooltip2 = ISToolTip:new()
    tooltip2:initialise()
    tooltip2:setVisible(false)
    tooltip2:setName(getText("Tooltip_BurdJournals_Disassemble") or "Disassemble Journal")
    tooltip2.description = normalizeTooltipTextForDisplay(getText("Tooltip_BurdJournals_DisassembleDesc") or "Tear apart this journal for materials.\n\nYou will receive:\n  2x Paper\n  1x Leather Strips")
    disassembleOption.toolTip = tooltip2
end

function BurdJournals.ContextMenu.onAbsorbAllConfirm(player, journal)
    if not BurdJournals.ContextMenu.requireLightOrNotify(player) then
        return
    end
    if BurdJournals.isLimitedClaimLootJournalActive and BurdJournals.isLimitedClaimLootJournalActive(journal) then
        notifyLimitedLootClaimRule(player, "UI_BurdJournals_LimitedLootClaimsNoBatch", "Batch absorb is disabled for limited-claim loot journals.")
        return
    end

    local journalData = BurdJournals.getJournalData(journal)

    local skillCount = 0
    local traitCount = 0
    local recipeCount = 0
    if journalData and journalData.skills then
        for skillName, _ in pairs(journalData.skills) do
            if not BurdJournals.hasCharacterClaimedSkill(journalData, player, skillName) then
                skillCount = skillCount + 1
            end
        end
    end
    if journalData and journalData.traits then
        for traitId, _ in pairs(journalData.traits) do
            if not BurdJournals.hasCharacterClaimedTrait(journalData, player, traitId) then
                traitCount = traitCount + 1
            end
        end
    end
    if journalData and journalData.recipes then
        for recipeName, _ in pairs(journalData.recipes) do
            if not BurdJournals.hasCharacterClaimedRecipe(journalData, player, recipeName) then
                recipeCount = recipeCount + 1
            end
        end
    end

    local confirmText = (getText("UI_BurdJournals_ConfirmAbsorbAll") or "Absorb all remaining rewards?") .. "\n\n"
    if skillCount > 0 then
        local skillText = skillCount > 1 and (getText("UI_BurdJournals_SkillsCount") or "%d skills") or (getText("UI_BurdJournals_SkillCount") or "%d skill")
        confirmText = confirmText .. BurdJournals.formatText(skillText, skillCount) .. "\n"
    end
    if traitCount > 0 then
        local traitText = traitCount > 1 and (getText("UI_BurdJournals_RareTraitsCount") or "%d rare traits") or (getText("UI_BurdJournals_RareTraitCount") or "%d rare trait")
        confirmText = confirmText .. BurdJournals.formatText(traitText, traitCount) .. "\n"
    end
    if recipeCount > 0 then
        local recipeText = recipeCount > 1 and (getText("UI_BurdJournals_RecipesCount") or "%d recipes") or (getText("UI_BurdJournals_RecipeCount") or "%d recipe")
        confirmText = confirmText .. BurdJournals.formatText(recipeText, recipeCount) .. "\n"
    end
    confirmText = confirmText .. "\n" .. (getText("UI_BurdJournals_MaxedSkillsSkipped") or "Maxed skills and known items will be skipped.")

    if BurdJournals.createAdaptiveModalDialog then
        BurdJournals.createAdaptiveModalDialog({
            player = player,
            target = player,
            text = confirmText,
            yesNo = true,
            onClick = BurdJournals.ContextMenu.onConfirmAbsorbAll,
            param2 = journal,
            minWidth = 380,
            maxWidth = 760,
            minHeight = 180,
        })
    else
        local modal = ISModalDialog:new(
            getCore():getScreenWidth() / 2 - 150,
            getCore():getScreenHeight() / 2 - 75,
            300, 150,
            confirmText,
            true,
            player,
            BurdJournals.ContextMenu.onConfirmAbsorbAll,
            nil,
            journal
        )
        modal:initialise()
        finalizePromptModalForPlayer(player, modal)
    end
end

local function captureDelayedJournalIdentity(journal)
    local data = BurdJournals.getJournalData and BurdJournals.getJournalData(journal) or nil
    return {
        uuid = type(data) == "table" and data.uuid or nil,
        id = journal and journal.getID and journal:getID() or nil,
    }
end

local function delayedMainPanelStillTargets(panel, player, journal, expectedIdentity)
    local current = BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance or nil
    if not panel or current ~= panel or panel.player ~= player or not panel.journal then
        return false
    end
    if panel.journal == journal then
        return true
    end
    local currentData = BurdJournals.getJournalData and BurdJournals.getJournalData(panel.journal) or nil
    local expectedUUID = expectedIdentity and expectedIdentity.uuid or nil
    local currentUUID = type(currentData) == "table" and currentData.uuid or nil
    if expectedUUID and currentUUID then
        return tostring(expectedUUID) == tostring(currentUUID)
    end
    local expectedId = expectedIdentity and expectedIdentity.id or nil
    local currentId = panel.journal.getID and panel.journal:getID() or nil
    return expectedId ~= nil and currentId ~= nil and tostring(expectedId) == tostring(currentId)
end

function BurdJournals.ContextMenu.onConfirmAbsorbAll(target, button, journal)
    if button.internal == "YES" then
        if not BurdJournals.ContextMenu.requireLightOrNotify(target) then
            return
        end
        if BurdJournals.isLimitedClaimLootJournalActive and BurdJournals.isLimitedClaimLootJournalActive(journal) then
            notifyLimitedLootClaimRule(target, "UI_BurdJournals_LimitedLootClaimsNoBatch", "Batch absorb is disabled for limited-claim loot journals.")
            return
        end

        BurdJournals.ContextMenu.pickUpThenDo(target, journal, function(player, j, returnContainer)
            if not BurdJournals.ContextMenu.requireLightOrNotify(player) then
                return
            end
            if BurdJournals.isLimitedClaimLootJournalActive and BurdJournals.isLimitedClaimLootJournalActive(j) then
                notifyLimitedLootClaimRule(player, "UI_BurdJournals_LimitedLootClaimsNoBatch", "Batch absorb is disabled for limited-claim loot journals.")
                return
            end
            if not BurdJournals.UI.MainPanel then
                require "UI/BurdJournals_MainPanel"
            end

            if BurdJournals.UI and BurdJournals.UI.MainPanel then

                BurdJournals.UI.MainPanel.show(player, j, "absorb", returnContainer)
                local panel = BurdJournals.UI.MainPanel.instance
                local journalIdentity = captureDelayedJournalIdentity(j)

                local ticksWaited = 0
                local startLearning
                startLearning = function()
                    ticksWaited = ticksWaited + 1
                    if ticksWaited >= 2 then
                        Events.OnTick.Remove(startLearning)
                        if delayedMainPanelStillTargets(panel, player, j, journalIdentity) and panel.startLearningAll then
                            panel:startLearningAll()
                        end
                    end
                end
                Events.OnTick.Add(startLearning)
            end
        end)
    end
end

function BurdJournals.ContextMenu.onOpenWornJournal(player, journal)
    if not BurdJournals.ContextMenu.requireLightOrNotify(player) then
        return
    end

    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j, returnContainer)
        if not BurdJournals.ContextMenu.requireLightOrNotify(p) then
            return
        end
        if not BurdJournals.UI or not BurdJournals.UI.MainPanel then
            require "UI/BurdJournals_MainPanel"
        end

        if BurdJournals.UI and BurdJournals.UI.MainPanel then
            markLootRewardsRevealedLocally(j, p)
            BurdJournals.UI.MainPanel.show(p, j, "absorb", returnContainer)
        end
    end)
end

function BurdJournals.ContextMenu.onOpenBloodyJournal(player, journal)
    if not BurdJournals.ContextMenu.requireLightOrNotify(player) then
        return
    end

    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j, returnContainer)
        if not BurdJournals.ContextMenu.requireLightOrNotify(p) then
            return
        end
        if BurdJournals.isHiddenCursedJournal and BurdJournals.isHiddenCursedJournal(j) then
            if j and j.getID then
                local journalData = BurdJournals.getJournalData and BurdJournals.getJournalData(j) or nil
                local lookupArgs = BurdJournals.buildJournalCommandPayload
                    and BurdJournals.buildJournalCommandPayload(j, journalData, true)
                    or { journalId = j:getID(), journalUUID = journalData and journalData.uuid or nil, journalFingerprint = nil }
                sendClientCommand(p, "BurdJournals", "openCursedJournal", {
                    journalId = lookupArgs.journalId,
                    journalUUID = lookupArgs.journalUUID,
                    journalFingerprint = lookupArgs.journalFingerprint,
                    journalData = lookupArgs.journalData,
                    itemFullType = lookupArgs.itemFullType,
                    exactJournalItem = true,
                    confirm = false,
                })
            end
            return
        end
        if not BurdJournals.UI or not BurdJournals.UI.MainPanel then
            require "UI/BurdJournals_MainPanel"
        end

        if BurdJournals.UI and BurdJournals.UI.MainPanel then
            markLootRewardsRevealedLocally(j, p)
            BurdJournals.UI.MainPanel.show(p, j, "absorb", returnContainer)
        end
    end)
end

function BurdJournals.ContextMenu.onOpenCursedJournal(player, journal)
    if not BurdJournals.ContextMenu.requireLightOrNotify(player) then
        return
    end

    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j, returnContainer)
        if not BurdJournals.ContextMenu.requireLightOrNotify(p) then
            return
        end
        if j and j.getID then
            local journalData = BurdJournals.getJournalData and BurdJournals.getJournalData(j) or nil
            local lookupArgs = BurdJournals.buildJournalCommandPayload
                and BurdJournals.buildJournalCommandPayload(j, journalData, true)
                or { journalId = j:getID(), journalUUID = journalData and journalData.uuid or nil, journalFingerprint = nil }
            lookupArgs.exactJournalItem = true
            sendClientCommand(p, "BurdJournals", "openCursedJournal", {
                journalId = lookupArgs.journalId,
                journalUUID = lookupArgs.journalUUID,
                journalFingerprint = lookupArgs.journalFingerprint,
                journalData = lookupArgs.journalData,
                itemFullType = lookupArgs.itemFullType,
                exactJournalItem = true,
                confirm = false,
            })
        end
    end)
end

-- Generic seal-break for any registered sealed journal type. Sends the base
-- "breakJournalSeal" command; the server flips the state, reveals contents,
-- and fires the OnJournalSealBroken hook (where add-ons apply their payload).
function BurdJournals.ContextMenu.onBreakJournalSeal(player, journal)
    if not BurdJournals.ContextMenu.requireLightOrNotify(player) then
        return
    end

    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j)
        if not BurdJournals.ContextMenu.requireLightOrNotify(p) then
            return
        end
        if j and j.getID then
            local journalData = BurdJournals.getJournalData and BurdJournals.getJournalData(j) or nil
            local lookupArgs = BurdJournals.buildJournalCommandPayload
                and BurdJournals.buildJournalCommandPayload(j, journalData, true)
                or { journalId = j:getID(), journalUUID = journalData and journalData.uuid or nil, journalFingerprint = nil }
            lookupArgs.exactJournalItem = true
            if BurdJournals.Client
                and BurdJournals.Client.handleSealedJournalBreakPrompt
                and BurdJournals.Client.handleSealedJournalBreakPrompt(p, lookupArgs, j)
            then
                return
            elseif BurdJournals.queueBreakJournalSealAction then
                BurdJournals.queueBreakJournalSealAction(p, lookupArgs)
            end
        end
    end)
end

function BurdJournals.ContextMenu.onOpenYuletideJournal(player, journal)
    if not BurdJournals.ContextMenu.requireLightOrNotify(player) then
        return
    end

    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j)
        if not BurdJournals.ContextMenu.requireLightOrNotify(p) then
            return
        end
        if j and j.getID then
            local journalData = BurdJournals.getJournalData and BurdJournals.getJournalData(j) or nil
            local lookupArgs = BurdJournals.buildJournalCommandPayload
                and BurdJournals.buildJournalCommandPayload(j, journalData, true)
                or { journalId = j:getID(), journalUUID = journalData and journalData.uuid or nil, journalFingerprint = nil }
            sendClientCommand(p, "BurdJournals", "openYuletideJournal", {
                journalId = lookupArgs.journalId,
                journalUUID = lookupArgs.journalUUID,
                journalFingerprint = lookupArgs.journalFingerprint,
                journalData = lookupArgs.journalData,
                itemFullType = lookupArgs.itemFullType,
                exactJournalItem = true,
                confirm = false,
            })
        end
    end)
end

function BurdJournals.ContextMenu.onOpenYuletideRewardJournal(player, journal)
    if not BurdJournals.ContextMenu.requireLightOrNotify(player) then
        return
    end

    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j, returnContainer)
        if not BurdJournals.ContextMenu.requireLightOrNotify(p) then
            return
        end
        if not BurdJournals.UI or not BurdJournals.UI.MainPanel then
            require "UI/BurdJournals_MainPanel"
        end

        if BurdJournals.UI and BurdJournals.UI.MainPanel then
            markLootRewardsRevealedLocally(j, p)
            BurdJournals.UI.MainPanel.show(p, j, "absorb", returnContainer)
        end
    end)
end

function BurdJournals.ContextMenu.onOpenSealedLootRewardJournal(player, journal)
    if not BurdJournals.ContextMenu.requireLightOrNotify(player) then
        return
    end

    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j, returnContainer)
        if not BurdJournals.ContextMenu.requireLightOrNotify(p) then
            return
        end
        if not BurdJournals.UI or not BurdJournals.UI.MainPanel then
            require "UI/BurdJournals_MainPanel"
        end

        if BurdJournals.UI and BurdJournals.UI.MainPanel then
            markLootRewardsRevealedLocally(j, p)
            BurdJournals.UI.MainPanel.show(p, j, "absorb", returnContainer)
        end
    end)
end

function BurdJournals.ContextMenu.onAbsorbAllFromJournal(player, journal)

    local playerNum = player and player:getPlayerNum() or 0
    player = getSpecificPlayer(playerNum) or getSpecificPlayer(0)
    if not player then

        return
    end
    if BurdJournals.isHiddenCursedJournal and BurdJournals.isHiddenCursedJournal(journal) then
        if not BurdJournals.ContextMenu.requireLightOrNotify(player) then
            return
        end
        BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j)
            if not BurdJournals.ContextMenu.requireLightOrNotify(p) then
                return
            end
            if j and j.getID then
                local journalData = BurdJournals.getJournalData and BurdJournals.getJournalData(j) or nil
                local lookupArgs = BurdJournals.buildJournalCommandPayload
                    and BurdJournals.buildJournalCommandPayload(j, journalData, true)
                    or { journalId = j:getID(), journalUUID = journalData and journalData.uuid or nil, journalFingerprint = nil }
                sendClientCommand(p, "BurdJournals", "openCursedJournal", {
                    journalId = lookupArgs.journalId,
                    journalUUID = lookupArgs.journalUUID,
                    journalFingerprint = lookupArgs.journalFingerprint,
                    journalData = lookupArgs.journalData,
                    itemFullType = lookupArgs.itemFullType,
                    exactJournalItem = true,
                    confirm = false,
                })
            end
        end)
        return
    end
    if BurdJournals.isLimitedClaimLootJournalActive and BurdJournals.isLimitedClaimLootJournalActive(journal) then
        notifyLimitedLootClaimRule(player, "UI_BurdJournals_LimitedLootClaimsNoBatch", "Batch absorb is disabled for limited-claim loot journals.")
        return
    end

    local totalXP = 0
    local skillsAbsorbed = 0
    local skillsSkipped = 0
    local traitsAbsorbed = 0
    local traitsSkipped = 0
    local recipesAbsorbed = 0
    local recipesSkipped = 0

    -- Use per-character unclaimed for this player
    local unclaimed = BurdJournals.getUnclaimedSkills(journal, player)
    local journalData = BurdJournals.getJournalData(journal)

    if BurdJournals.clientShouldUseServerAuthority() then
        -- Queue rewards for time-gated pacing instead of sending all at once
        -- This prevents server rate-limiting from dropping commands in MP
        -- Server rate-limits at 100ms, so we send one command every 120ms to be safe
        local rewardQueue = {}
        local lookupArgs = BurdJournals.buildJournalCommandPayload
            and BurdJournals.buildJournalCommandPayload(journal, journalData, true)
            or { journalId = journal:getID(), journalUUID = journalData and journalData.uuid or nil, journalFingerprint = nil }
        local journalId = lookupArgs.journalId

        for skillName, _ in pairs(unclaimed) do
            table.insert(rewardQueue, {type = "skill", name = skillName})
        end
        local unclaimedTraits = BurdJournals.getUnclaimedTraits(journal, player)
        for traitId, _ in pairs(unclaimedTraits) do
            table.insert(rewardQueue, {type = "trait", name = traitId})
        end
        local unclaimedRecipes = BurdJournals.getUnclaimedRecipes and BurdJournals.getUnclaimedRecipes(journal, player) or {}
        for recipeName, _ in pairs(unclaimedRecipes) do
            table.insert(rewardQueue, {type = "recipe", name = recipeName})
        end

        -- Process rewards with 120ms minimum spacing to respect server's 100ms rate limit
        local idx = 1
        local lastSendTime = 0
        local ticksSinceLastSend = 0  -- Fallback for builds without getTimestampMs
        local SEND_INTERVAL_MS = 120 -- Server rate-limits at 100ms, use 120ms to be safe
        local SEND_INTERVAL_TICKS = 4 -- ~120ms at 30 FPS as fallback
        local processNextReward
        processNextReward = function()
            if idx > #rewardQueue then
                Events.OnTick.Remove(processNextReward)
                return
            end

            -- Check if enough time has passed since last send
            local now = getTimestampMs and getTimestampMs() or 0
            if now > 0 and lastSendTime > 0 then
                -- Use millisecond timing when available
                if (now - lastSendTime) < SEND_INTERVAL_MS then
                    return -- Wait for next tick, not enough time elapsed
                end
            else
                -- Fallback: use tick counting when getTimestampMs unavailable
                ticksSinceLastSend = ticksSinceLastSend + 1
                if ticksSinceLastSend < SEND_INTERVAL_TICKS then
                    return -- Wait for more ticks
                end
                ticksSinceLastSend = 0
            end

            local reward = rewardQueue[idx]
            idx = idx + 1
            lastSendTime = now

            if reward.type == "skill" then
                -- Calculate skill book multiplier on the client (where the state is known)
                local skillBookMultiplier = 1.0
                if BurdJournals.shouldApplySkillBookMultiplierForJournal(journal) then
                    skillBookMultiplier = BurdJournals.getSkillBookMultiplier(player, reward.name)
                end
                sendClientCommand(player, "BurdJournals", "absorbSkill",
                    {journalId = journalId, journalUUID = lookupArgs.journalUUID, journalFingerprint = lookupArgs.journalFingerprint, journalData = lookupArgs.journalData, skillName = reward.name, skillBookMultiplier = skillBookMultiplier})
            elseif reward.type == "trait" then
                sendClientCommand(player, "BurdJournals", "absorbTrait",
                    {journalId = journalId, journalUUID = lookupArgs.journalUUID, journalFingerprint = lookupArgs.journalFingerprint, journalData = lookupArgs.journalData, traitId = reward.name})
            elseif reward.type == "recipe" then
                sendClientCommand(player, "BurdJournals", "absorbRecipe",
                    {journalId = journalId, journalUUID = lookupArgs.journalUUID, journalFingerprint = lookupArgs.journalFingerprint, journalData = lookupArgs.journalData, recipeName = reward.name})
            end
        end
        Events.OnTick.Add(processNextReward)
    else
        -- SP/host path - use per-character claims to match server behavior
        local journalMultiplier = BurdJournals.getSandboxOption("JournalXPMultiplier") or 1.0
        local modData = journal:getModData()
        local jData = modData and modData.BurdJournals

        for skillName, _ in pairs(unclaimed) do
            local skillData = journalData and journalData.skills and journalData.skills[skillName]
            local xp = skillData and skillData.xp or 0

            local perk = BurdJournals.getPerkByName(skillName)
            if perk and xp > 0 then
                local xpObj = player:getXp()
                local beforeXP = BurdJournals.getPlayerSkillTotalXP and BurdJournals.getPlayerSkillTotalXP(player, perk, skillName) or xpObj:getXP(perk)

                -- Apply skill book multiplier for Worn/Bloody journals
                local skillBookMultiplier = 1.0
                if BurdJournals.shouldApplySkillBookMultiplierForJournal(journal) then
                    skillBookMultiplier = BurdJournals.getSkillBookMultiplier(player, skillName)
                end
                local xpToApply = xp * journalMultiplier * skillBookMultiplier

                local isPassiveSkill = (skillName == "Fitness" or skillName == "Strength")
                if isPassiveSkill then
                    xpToApply = xpToApply * 5
                end

                if BurdJournals.applySkillXPCompat then
                    BurdJournals.applySkillXPCompat(player, perk, skillName, xpToApply, "add")
                else
                    if BurdJournals.applyXPDeltaCompat then
                        BurdJournals.applyXPDeltaCompat(player, perk, xpToApply)
                    else
                        xpObj:AddXP(perk, xpToApply)
                    end
                end

                local afterXP = BurdJournals.getPlayerSkillTotalXP and BurdJournals.getPlayerSkillTotalXP(player, perk, skillName) or xpObj:getXP(perk)
                local actualGain = afterXP - beforeXP

                -- Always mark as claimed (per-character) even if no gain
                if jData then
                    BurdJournals.markSkillClaimedByCharacter(jData, player, skillName)
                end

                if actualGain > 0 then
                    totalXP = totalXP + actualGain
                    skillsAbsorbed = skillsAbsorbed + 1
                else
                    skillsSkipped = skillsSkipped + 1
                end
            else
                -- Mark as claimed even if no XP (0 XP skill)
                if jData then
                    BurdJournals.markSkillClaimedByCharacter(jData, player, skillName)
                end
                skillsSkipped = skillsSkipped + 1
            end
        end

        local unclaimedTraits = BurdJournals.getUnclaimedTraits(journal, player)
        for traitId, _ in pairs(unclaimedTraits) do
            if BurdJournals.playerHasTrait(player, traitId) then
                -- Mark as claimed even if already known (allows dissolution)
                if jData then
                    BurdJournals.markTraitClaimedByCharacter(jData, player, traitId)
                end
                traitsSkipped = traitsSkipped + 1
            else
                local success = BurdJournals.safeAddTrait(player, traitId)
                if success then
                    local allowCancellation = BurdJournals.getSandboxOption("AllowMutualExclusionCancellation")
                    if allowCancellation == nil then
                        allowCancellation = true
                    end
                    if allowCancellation and BurdJournals.getConflictingTraits and BurdJournals.safeRemoveTrait then
                        local conflicts = BurdJournals.getConflictingTraits(player, traitId)
                        for _, conflictId in ipairs(conflicts) do
                            BurdJournals.safeRemoveTrait(player, conflictId)
                        end
                    end
                end
                if jData then
                    BurdJournals.markTraitClaimedByCharacter(jData, player, traitId)
                end
                if success then
                    traitsAbsorbed = traitsAbsorbed + 1
                else
                    traitsSkipped = traitsSkipped + 1
                end
            end
        end

        -- Process recipes for SP/host
        local unclaimedRecipes = BurdJournals.getUnclaimedRecipes and BurdJournals.getUnclaimedRecipes(journal, player) or {}
        for recipeName, _ in pairs(unclaimedRecipes) do
            if BurdJournals.playerKnowsRecipe(player, recipeName) then
                -- Mark as claimed even if already known (allows dissolution)
                if jData then
                    BurdJournals.markRecipeClaimedByCharacter(jData, player, recipeName)
                end
                recipesSkipped = recipesSkipped + 1
            else
                local success = BurdJournals.learnRecipeWithVerification(player, recipeName, "[BurdJournals SP]")
                if jData then
                    BurdJournals.markRecipeClaimedByCharacter(jData, player, recipeName)
                end
                if success then
                    recipesAbsorbed = recipesAbsorbed + 1
                else
                    recipesSkipped = recipesSkipped + 1
                end
            end
        end

        -- Transmit changes once after all claims
        if jData and journal.transmitModData
            and (not BurdJournals.shouldTransmitJournalItemModData
                or BurdJournals.shouldTransmitJournalItemModData(journal, "contextMenuAbsorbAllLocal"))
        then
            journal:transmitModData()
        end

        if totalXP > 0 or traitsAbsorbed > 0 or recipesAbsorbed > 0 then
            local message = "+" .. BurdJournals.formatXP(totalXP) .. " XP"
            if traitsAbsorbed > 0 then
                local traitText = traitsAbsorbed > 1 and (getText("UI_BurdJournals_PlusTraits") or ", +%d traits") or (getText("UI_BurdJournals_PlusTrait") or ", +%d trait")
                message = message .. BurdJournals.formatText(traitText, traitsAbsorbed)
            end
            if recipesAbsorbed > 0 then
                local recipeText = recipesAbsorbed > 1 and (getText("UI_BurdJournals_PlusRecipes") or ", +%d recipes") or (getText("UI_BurdJournals_PlusRecipe") or ", +%d recipe")
                message = message .. BurdJournals.formatText(recipeText, recipesAbsorbed)
            end
            if HaloTextHelper and HaloTextHelper.addTextWithArrow then
                HaloTextHelper.addTextWithArrow(player, message, true, HaloTextHelper.getColorGreen())
            else
                player:Say(message)
            end
        end

        if skillsSkipped > 0 or traitsSkipped > 0 or recipesSkipped > 0 then
            local skipMsg = ""
            if skillsSkipped > 0 then
                local skillText = skillsSkipped > 1 and (getText("UI_BurdJournals_SkillsAlreadyMaxed") or "%d skills already maxed") or (getText("UI_BurdJournals_SkillAlreadyMaxed") or "%d skill already maxed")
                skipMsg = BurdJournals.formatText(skillText, skillsSkipped)
            end
            if traitsSkipped > 0 then
                if skipMsg ~= "" then skipMsg = skipMsg .. ", " end
                local traitText = traitsSkipped > 1 and (getText("UI_BurdJournals_TraitsAlreadyKnown") or "%d traits already known") or (getText("UI_BurdJournals_TraitAlreadyKnown") or "%d trait already known")
                skipMsg = skipMsg .. BurdJournals.formatText(traitText, traitsSkipped)
            end
            if recipesSkipped > 0 then
                if skipMsg ~= "" then skipMsg = skipMsg .. ", " end
                local recipeText = recipesSkipped > 1 and (getText("UI_BurdJournals_RecipesAlreadyKnownCount") or "%d recipes already known") or (getText("UI_BurdJournals_RecipeAlreadyKnown") or "%d recipe already known")
                skipMsg = skipMsg .. BurdJournals.formatText(recipeText, recipesSkipped)
            end
            if skipMsg ~= "" then
                player:Say(skipMsg)
            end
        end

        if BurdJournals.shouldDissolve(journal, player) then
            player:getInventory():Remove(journal)
            local dissolveMsg = BurdJournals.getRandomDissolutionMessage()
            player:Say(dissolveMsg)
            if player and player.getEmitter then
                local emitter = player:getEmitter()
                if emitter and emitter.playSound then
                    emitter:playSound("PaperRip")
                end
            end
        end
    end
end

function BurdJournals.ContextMenu.onConvertToClean(player, journal)

    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j, returnContainer)
        local isFilled = BurdJournals.isFilledJournal(j)
        local remaining = BurdJournals.getRemainingRewards(j, p)

        if isFilled and remaining > 0 then

            local confirmText = getText("UI_BurdJournals_ConfirmConvert") or "This will destroy the remaining rewards. Are you sure?"
            if BurdJournals.createAdaptiveModalDialog then
                BurdJournals.createAdaptiveModalDialog({
                    player = p,
                    target = p,
                    text = confirmText,
                    yesNo = true,
                    onClick = BurdJournals.ContextMenu.onConfirmConvert,
                    param2 = j,
                    minWidth = 360,
                    maxWidth = 700,
                    minHeight = 165,
                })
            else
                local modal = ISModalDialog:new(
                    getCore():getScreenWidth() / 2 - 150,
                    getCore():getScreenHeight() / 2 - 50,
                    300, 120,
                    confirmText,
                    true,
                    p,
                    BurdJournals.ContextMenu.onConfirmConvert,
                    nil,
                    j
                )
                modal:initialise()
                finalizePromptModalForPlayer(p, modal)
            end
        else

            local action = BurdJournals.ConvertToCleanAction:new(p, j)
            ISTimedActionQueue.add(action)
        end
    end)
end

function BurdJournals.ContextMenu.onConfirmConvert(target, button, journal)
    if button.internal == "YES" then
        local action = BurdJournals.ConvertToCleanAction:new(target, journal)
        ISTimedActionQueue.add(action)
    end
end

function BurdJournals.ContextMenu.onOpenCleanJournal(player, journal)
    if not BurdJournals.ContextMenu.requireLightOrNotify(player) then
        return
    end

    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j)
        if not BurdJournals.ContextMenu.requireLightOrNotify(p) then
            return
        end
        if not BurdJournals.UI or not BurdJournals.UI.MainPanel then
            require "UI/BurdJournals_MainPanel"
        end

        if BurdJournals.UI and BurdJournals.UI.MainPanel then
            BurdJournals.UI.MainPanel.show(p, j, "view", returnContainer)
        end
    end)
end

function BurdJournals.ContextMenu.onReadCleanJournal(player, journal)

    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j, returnContainer)
        local lookupArgs = BurdJournals.buildJournalCommandLookupArgs(j, nil, false)
        sendClientCommand(
            p,
            "BurdJournals",
            "learnSkills",
            lookupArgs
        )
    end)
end

function BurdJournals.ContextMenu.onClaimAllConfirm(player, journal)
    if not BurdJournals.ContextMenu.requireLightOrNotify(player) then
        return
    end

    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j, returnContainer)
        if not BurdJournals.ContextMenu.requireLightOrNotify(p) then
            return
        end
        if not BurdJournals.UI or not BurdJournals.UI.MainPanel then
            require "UI/BurdJournals_MainPanel"
        end

        if BurdJournals.UI and BurdJournals.UI.MainPanel then

            BurdJournals.UI.MainPanel.show(p, j, "view", returnContainer)

            local panel = BurdJournals.UI.MainPanel.instance
            if panel and panel.startLearningAll then
                local journalIdentity = captureDelayedJournalIdentity(j)
                local ticksWaited = 0
                local startLearning
                startLearning = function()
                    ticksWaited = ticksWaited + 1
                    if ticksWaited >= 2 then
                        Events.OnTick.Remove(startLearning)
                        if delayedMainPanelStillTargets(panel, p, j, journalIdentity) then
                            panel:startLearningAll()
                        end
                    end
                end
                Events.OnTick.Add(startLearning)
            end
        end
    end)
end

function BurdJournals.ContextMenu.onRenameJournal(player, journal)

    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j, returnContainer)
        local currentName = j:getName() or ""
        local modal = ISTextBox:new(
            getCore():getScreenWidth() / 2 - 150,
            getCore():getScreenHeight() / 2 - 50,
            300, 100,
            getText("UI_BurdJournals_RenamePrompt") or "Enter new name:",
            currentName,
            p,
            BurdJournals.ContextMenu.onConfirmRename,
            nil,
            j
        )
        modal:initialise()
        finalizePromptModalForPlayer(p, modal)
    end)
end

function BurdJournals.ContextMenu.onConfirmRename(target, button, journal)
    if button.internal == "OK" then
        local newName = button.parent.entry:getText()
        if newName and newName ~= "" then
            local oldName = journal:getName() or ""
            local oldCustomName = journal.isCustomName and journal:isCustomName() or false
            local oldModData = journal:getModData()
            local oldBackupName = oldModData.BurdJournals and oldModData.BurdJournals.customName or nil
            -- Set name locally first for immediate feedback
            journal:setName(newName)
            -- Mark as custom name so PZ preserves it during item serialization (MP transfers)
            if journal.setCustomName then
                journal:setCustomName(true)
            end

            local modData = journal:getModData()
            if modData.BurdJournals then
                modData.BurdJournals.customName = newName
            end

            -- In multiplayer, send command to server to update the name there too
            -- This is CRITICAL for MP name persistence - the server must have the correct name
            if BurdJournals.clientShouldUseServerAuthority() then
                local player = target
                if player then
                    BurdJournals.Client._pendingJournalRenames = BurdJournals.Client._pendingJournalRenames or {}
                    if BurdJournals.Client.prunePendingJournalRenames then
                        BurdJournals.Client.prunePendingJournalRenames()
                    end
                    BurdJournals.Client._pendingJournalRenameRequestId =
                        (tonumber(BurdJournals.Client._pendingJournalRenameRequestId) or 0) + 1
                    local renameRequestId = tostring(BurdJournals.Client._pendingJournalRenameRequestId)
                    BurdJournals.Client._pendingJournalRenames[renameRequestId] = {
                        journal = journal,
                        player = player,
                        oldName = oldName,
                        oldCustomName = oldCustomName,
                        oldBackupName = oldBackupName,
                        queuedAt = (getTimestampMs and getTimestampMs()) or ((os.time() or 0) * 1000),
                    }
                    BurdJournals.Client.prunePendingJournalRenames(nil, renameRequestId)
                    local lookupArgs = BurdJournals.buildJournalCommandLookupArgs(journal, modData.BurdJournals, false)
                    lookupArgs.newName = newName
                    lookupArgs.renameRequestId = renameRequestId
                    sendClientCommand(player, "BurdJournals", "renameJournal", lookupArgs)
                end
            else
                -- Single player or listen server - just transmit locally
                if journal.transmitModData
                    and (not BurdJournals.shouldTransmitJournalItemModData
                        or BurdJournals.shouldTransmitJournalItemModData(journal, "contextMenuRenameLocal"))
                then
                    journal:transmitModData()
                end
            end
        end
    end
end

function BurdJournals.ContextMenu.onEraseJournal(player, journal)

    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j)
        local confirmText = getText("UI_BurdJournals_ConfirmErase") or "Erase all content? This cannot be undone."
        if BurdJournals.createAdaptiveModalDialog then
            BurdJournals.createAdaptiveModalDialog({
                player = p,
                target = p,
                text = confirmText,
                yesNo = true,
                onClick = BurdJournals.ContextMenu.onConfirmErase,
                param2 = j,
                minWidth = 360,
                maxWidth = 700,
                minHeight = 165,
            })
        else
            local modal = ISModalDialog:new(
                getCore():getScreenWidth() / 2 - 150,
                getCore():getScreenHeight() / 2 - 50,
                300, 120,
                confirmText,
                true,
                p,
                BurdJournals.ContextMenu.onConfirmErase,
                nil,
                j
            )
            modal:initialise()
            finalizePromptModalForPlayer(p, modal)
        end
    end)
end

function BurdJournals.ContextMenu.onConfirmErase(target, button, journal)
    if button.internal == "YES" then

        if BurdJournals.EraseJournalAction then
            ISTimedActionQueue.add(BurdJournals.EraseJournalAction:new(target, journal))
        else

            sendClientCommand(
                target,
                "BurdJournals",
                "eraseJournal",
                {journalId = journal:getID()}
            )
        end
    end
end

function BurdJournals.ContextMenu.onRecordProgress(player, journal)
    if not BurdJournals.ContextMenu.requireLightOrNotify(player) then
        return
    end

    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j)
        if not BurdJournals.ContextMenu.requireLightOrNotify(p) then
            return
        end
        if not BurdJournals.UI or not BurdJournals.UI.MainPanel then
            require "UI/BurdJournals_MainPanel"
        end

        if BurdJournals.UI and BurdJournals.UI.MainPanel then
            local mode = "log"
            local penRequired = BurdJournals.getSandboxOption("RequirePenToWrite") ~= false
            local hasPen = (not penRequired) or (BurdJournals.hasWritingTool and BurdJournals.hasWritingTool(p))
            if not hasPen then
                mode = "view"
            end
            BurdJournals.UI.MainPanel.show(p, j, mode, returnContainer)
        end
    end)
end

function BurdJournals.ContextMenu.onRecordProgressOverwrite(player, journal)

    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j)
        local confirmText = getText("UI_BurdJournals_ConfirmOverwrite") or "Overwrite existing content?"
        if BurdJournals.createAdaptiveModalDialog then
            BurdJournals.createAdaptiveModalDialog({
                player = p,
                target = p,
                text = confirmText,
                yesNo = true,
                onClick = BurdJournals.ContextMenu.onConfirmOverwrite,
                param2 = j,
                minWidth = 360,
                maxWidth = 700,
                minHeight = 165,
            })
        else
            local modal = ISModalDialog:new(
                getCore():getScreenWidth() / 2 - 150,
                getCore():getScreenHeight() / 2 - 50,
                300, 120,
                confirmText,
                true,
                p,
                BurdJournals.ContextMenu.onConfirmOverwrite,
                nil,
                j
            )
            modal:initialise()
            finalizePromptModalForPlayer(p, modal)
        end
    end)
end

function BurdJournals.ContextMenu.onConfirmOverwrite(target, button, journal)
    if button.internal == "YES" then
        if not BurdJournals.ContextMenu.requireLightOrNotify(target) then
            return
        end
        if not BurdJournals.UI or not BurdJournals.UI.MainPanel then
            require "UI/BurdJournals_MainPanel"
        end

        if BurdJournals.UI and BurdJournals.UI.MainPanel then
            BurdJournals.UI.MainPanel.show(target, journal, "log")
        end
    end
end

function BurdJournals.ContextMenu.onDisassembleJournal(player, journal)

    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j)

        local confirmText = getText("UI_BurdJournals_ConfirmDisassemble") or "Disassemble this journal?"
        confirmText = confirmText .. "\n\nYou will receive:\n2x Paper, 1x Leather Strips"

        if BurdJournals.createAdaptiveModalDialog then
            BurdJournals.createAdaptiveModalDialog({
                player = p,
                target = p,
                text = confirmText,
                yesNo = true,
                onClick = BurdJournals.ContextMenu.onConfirmDisassemble,
                param2 = j,
                minWidth = 380,
                maxWidth = 760,
                minHeight = 180,
            })
        else
            local modal = ISModalDialog:new(
                getCore():getScreenWidth() / 2 - 150,
                getCore():getScreenHeight() / 2 - 75,
                300, 150,
                confirmText,
                true,
                p,
                BurdJournals.ContextMenu.onConfirmDisassemble,
                nil,
                j
            )
            modal:initialise()
            finalizePromptModalForPlayer(p, modal)
        end
    end)
end

function BurdJournals.ContextMenu.onConfirmDisassemble(target, button, journal)
    if button.internal == "YES" then
        if BurdJournals.DisassembleJournalAction then
            ISTimedActionQueue.add(BurdJournals.DisassembleJournalAction:new(target, journal))
        end
    end
end

function BurdJournals.ContextMenu.parseRecipeString(recipeStr)
    local materials = {}
    if not recipeStr or recipeStr == "" then return materials end

    for part in recipeStr:gmatch("[^|]+") do
        part = part:match("^%s*(.-)%s*$")
        if part and part ~= "" then
            local mat = {}

            mat.keep = part:match(":keep$") ~= nil
            if mat.keep then
                part = part:gsub(":keep$", "")
            end

            local itemType, qty = part:match("^(.+):(%d+)$")
            if itemType and qty then
                mat.type = itemType
                mat.count = tonumber(qty)

                mat.name = itemType:gsub("Base%.", ""):gsub("tag:", "")
                mat.name = mat.name:gsub("(%l)(%u)", "%1 %2")
                table.insert(materials, mat)
            end
        end
    end
    return materials
end

Events.OnFillInventoryObjectContextMenu.Add(BurdJournals.ContextMenu.onFillInventoryObjectContextMenu)
