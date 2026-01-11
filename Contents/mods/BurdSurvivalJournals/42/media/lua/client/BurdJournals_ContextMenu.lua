--[[
    Burd's Survival Journals - Context Menu
    Build 42 - Version 2.0

    Right-click context menu options for journals

    BLOODY JOURNALS (rare, from zombie corpses):
    - Open Journal... â†’ absorption UI (better XP + rare traits)
    - Absorb All â†’ quick absorb all remaining (with confirmation)
    - Convert to Personal Journal â†’ via crafting menu (destroys rewards)
    Note: Bloody journals can be read directly without cleaning.

    WORN JOURNALS (common, from world containers):
    - Open Journal... â†’ absorption UI (light XP rewards)
    - Absorb All â†’ quick absorb all remaining (with confirmation)
    - Convert to Personal Journal â†’ Tailoring Lv1 â†’ Clean Blank

    CLEAN JOURNALS (player-created, reusable):
    - Open Journal... â†’ view/set XP
    - Read â†’ apply XP (SET mode)
    - Erase â†’ convert to blank
    - Record Progress â†’ log skills
]]

require "BurdJournals_Shared"
require "BurdJournals_TimedActions"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISInventoryTransferAction"

BurdJournals = BurdJournals or {}
BurdJournals.ContextMenu = BurdJournals.ContextMenu or {}

-- ==================== HELPER: PICK UP ITEM FIRST IF NEEDED ====================

-- Check if item is in player's MAIN inventory (not in equipped bags/containers)
function BurdJournals.ContextMenu.isInPlayerMainInventory(player, item)
    if not player or not item then return false end
    local mainInventory = player:getInventory()
    if not mainInventory then return false end
    
    -- Check if the item's container IS the main inventory (not a sub-container)
    local itemContainer = item:getContainer()
    return itemContainer == mainInventory
end

-- Check if item is in any of the player's containers (main inventory or equipped bags)
function BurdJournals.ContextMenu.isInPlayerContainers(player, item)
    if not player or not item then return false end
    
    local itemContainer = item:getContainer()
    if not itemContainer then return false end
    
    -- Check main inventory
    if itemContainer == player:getInventory() then
        return true
    end
    
    -- Check equipped containers (backpacks, fanny packs, etc.)
    -- These are containers attached to worn items
    local wornItems = player:getWornItems()
    if wornItems then
        -- PZ uses 1-based loop with 0-based get()
        for i = 1, wornItems:size() do
            local wornItem = wornItems:get(i - 1)  -- WornItem wrapper
            if wornItem then
                local actualItem = wornItem:getItem()  -- Get the actual InventoryItem
                if actualItem and actualItem:IsInventoryContainer() then
                    local bagContainer = actualItem:getItemContainer()
                    if bagContainer and itemContainer == bagContainer then
                        return true  -- Item is in an equipped bag
                    end
                end
            end
        end
    end
    
    return false
end

-- Transfer item to player's main inventory, then execute callback
-- callback receives (player, item) after transfer completes
function BurdJournals.ContextMenu.pickUpThenDo(player, item, callback)
    if not player or not item or not callback then return end
    
    -- If already in main inventory, just do the callback immediately
    if BurdJournals.ContextMenu.isInPlayerMainInventory(player, item) then
        callback(player, item)
        return
    end
    
    -- Get the source container
    local sourceContainer = item:getContainer()
    if not sourceContainer then
        -- Item might be on the ground, try to get it
        -- Debug removed
        callback(player, item)
        return
    end
    
    local destContainer = player:getInventory()
    
    -- Check if item is in an equipped bag (worn container) - quick transfer, no walking
    local isInEquippedBag = BurdJournals.ContextMenu.isInPlayerContainers(player, item) and 
                            not BurdJournals.ContextMenu.isInPlayerMainInventory(player, item)
    
    if isInEquippedBag then
        -- Item is in a worn bag - can transfer instantly without walking
        -- Still use timed action for consistency, but it should be quick
        ISTimedActionQueue.add(ISInventoryTransferAction:new(player, item, sourceContainer, destContainer))
    else
        -- Item is in world container or on ground - needs walking
        ISTimedActionQueue.add(ISInventoryTransferAction:new(player, item, sourceContainer, destContainer))
    end
    
    -- After transfer, execute the callback
    -- We use a tick-based delay to wait for the transfer to complete
    local checkTicks = 0
    local maxTicks = 300  -- ~5 seconds max wait
    local checkTransfer
    checkTransfer = function()
        checkTicks = checkTicks + 1
        
        -- Check if item is now in player's main inventory
        if BurdJournals.ContextMenu.isInPlayerMainInventory(player, item) then
            Events.OnTick.Remove(checkTransfer)
            callback(player, item)
            return
        end
        
        -- Timeout
        if checkTicks >= maxTicks then
            Events.OnTick.Remove(checkTransfer)
            -- Debug removed
            return
        end
    end
    Events.OnTick.Add(checkTransfer)
end

-- ==================== CONTEXT MENU HANDLER ====================

function BurdJournals.ContextMenu.onFillInventoryObjectContextMenu(playerNum, context, items)
    -- Debug: Always log entry
    
    if not BurdJournals.isEnabled() then 
        -- Debug removed
        return 
    end
    
    local player = getSpecificPlayer(playerNum)
    if not player then 
        -- Debug removed
        return 
    end
    
    -- Build item list - handle both single items and item stacks
    local itemList = {}
    for i, v in ipairs(items) do
        if instanceof(v, "InventoryItem") then
            -- Direct item reference
            table.insert(itemList, v)
        elseif type(v) == "table" and v.items then
            -- Item stack - v.items might be a Java ArrayList or Lua table
            local stackItems = v.items
            if stackItems.size then
                -- Java ArrayList
                for j = 0, stackItems:size() - 1 do
                    local item = stackItems:get(j)
                    table.insert(itemList, item)
                end
            else
                -- Lua table
                for j, item in ipairs(stackItems) do
                    table.insert(itemList, item)
                end
            end
        end
    end
    
    -- Debug removed
    
    for _, item in ipairs(itemList) do
        local fullType = item:getFullType()
        local isJournal = BurdJournals.isAnyJournal(item)
        
        if isJournal then
            BurdJournals.ContextMenu.addJournalOptions(context, player, item)
            break
        end
    end
end

-- ==================== ADD JOURNAL OPTIONS ====================

-- Remove vanilla book/literature read options that shouldn't apply to our journals
function BurdJournals.ContextMenu.removeVanillaReadOptions(context)
    -- Find and remove vanilla "Read" options that got added by mistake
    local vanillaReadTexts = {
        getText("ContextMenu_Read") or "Read",
        getText("ContextMenu_ReRead") or "Re-read",
        getText("ContextMenu_Look_at_picture") or "Look at picture",
        getText("ContextMenu_Look_at_pictures") or "Look at pictures",
        getText("ContextMenu_ReLook_at_picture") or "Re-look at picture",
        getText("ContextMenu_ReLook_at_pictures") or "Re-look at pictures",
    }

    -- Iterate through context options and mark vanilla read options for removal
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

    -- Remove options in reverse order to preserve indices
    for i = #optionsToRemove, 1, -1 do
        table.remove(context.options, optionsToRemove[i])
    end
end

function BurdJournals.ContextMenu.addJournalOptions(context, player, journal)
    -- Debug removed

    local ok, err = pcall(function()
        -- First, remove any vanilla read options that shouldn't apply to our journals
        BurdJournals.ContextMenu.removeVanillaReadOptions(context)

        -- Block illiterate players from using journals entirely
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
            tooltip.description = getText("Tooltip_BurdJournals_IlliterateDesc") or "You cannot read or write. Journals are useless to you."
            illiterateOption.toolTip = tooltip
            return  -- Don't add any other options
        end

        local isBloody = BurdJournals.isBloody(journal)
        local isWorn = BurdJournals.isWorn(journal)
        local isClean = BurdJournals.isClean(journal)
        local isBlank = BurdJournals.isBlankJournal(journal)
        local isFilled = BurdJournals.isFilledJournal(journal)

        if isBloody then
            -- Debug removed
            BurdJournals.ContextMenu.addBloodyJournalOptions(context, player, journal, isBlank)
        elseif isWorn then
            -- Debug removed
            BurdJournals.ContextMenu.addWornJournalOptions(context, player, journal, isBlank)
        elseif isClean then
            -- Debug removed
            if isFilled then
                BurdJournals.ContextMenu.addCleanFilledJournalOptions(context, player, journal)
            else
                BurdJournals.ContextMenu.addCleanBlankJournalOptions(context, player, journal)
            end
        else
        end
    end)
    
    if not ok then
        print("[BurdJournals] ERROR in addJournalOptions: " .. tostring(err))
    end
end

-- ==================== BLOODY JOURNAL OPTIONS ====================

function BurdJournals.ContextMenu.addBloodyJournalOptions(context, player, journal, isBlank)
    local journalData = BurdJournals.getJournalData(journal)
    local isFilled = BurdJournals.isFilledJournal(journal)

    if isFilled and journalData then
        -- Count skills and traits separately for detailed display
        local skillCount = 0
        local totalSkills = 0
        local traitCount = 0
        local totalTraits = 0

        if journalData.skills then
            for skillName, _ in pairs(journalData.skills) do
                totalSkills = totalSkills + 1
                if not BurdJournals.isSkillClaimed(journal, skillName) then
                    skillCount = skillCount + 1
                end
            end
        end
        if journalData.traits then
            for traitId, _ in pairs(journalData.traits) do
                totalTraits = totalTraits + 1
                if not BurdJournals.isTraitClaimed(journal, traitId) then
                    traitCount = traitCount + 1
                end
            end
        end

        local remaining = skillCount + traitCount

        -- Open Journal... (absorption UI) - same as worn but with rare rewards
        local openOption = context:addOption(
            getText("ContextMenu_BurdJournals_OpenJournal") or "Open Journal...",
            player,
            BurdJournals.ContextMenu.onOpenBloodyJournal,
            journal
        )
        local tooltip = ISToolTip:new()
        tooltip:initialise()
        tooltip:setVisible(false)
        tooltip:setName(getText("Tooltip_BurdJournals_BloodyJournal") or "Bloody Journal")

        -- Build detailed tooltip showing skills and traits separately
        local tooltipDesc = ""
        if totalSkills > 0 then
            tooltipDesc = tooltipDesc .. (getText("Tooltip_BurdJournals_SkillsAvailable") or "Skills: %d/%d available"):gsub("%%d/%%d", skillCount .. "/" .. totalSkills) .. "\n"
        end
        if totalTraits > 0 then
            tooltipDesc = tooltipDesc .. (getText("Tooltip_BurdJournals_TraitsAvailable") or "Traits: %d/%d available"):gsub("%%d/%%d", traitCount .. "/" .. totalTraits) .. "\n"
        end
        if tooltipDesc == "" then
            tooltipDesc = (getText("Tooltip_BurdJournals_NoRewardsFound") or "No rewards found") .. "\n"
        end
        tooltipDesc = tooltipDesc .. "\n" .. (getText("Tooltip_BurdJournals_BloodyDesc") or "Rare find! May contain valuable traits.")
        tooltip.description = tooltipDesc
        openOption.toolTip = tooltip

        -- Absorb All (quick action)
        if remaining > 0 then
            local absorbLabel = getText("Tooltip_BurdJournals_AbsorbAllRewards") or "Absorb All Rewards"
            if traitCount > 0 then
                absorbLabel = string.format(getText("Tooltip_BurdJournals_AbsorbAllSkillsTraits") or "Absorb All (%d skills, %d traits)", skillCount, traitCount)
            elseif skillCount > 0 then
                absorbLabel = string.format(getText("Tooltip_BurdJournals_AbsorbAllSkills") or "Absorb All (%d skills)", skillCount)
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
            tooltip2.description = getText("Tooltip_BurdJournals_AbsorbAllDesc") or "Opens the journal and begins reading all rewards.\nRequires time to absorb each skill and trait.\nMaxed skills and known traits will be skipped."
            absorbAllOption.toolTip = tooltip2
        end
    else
        -- Bloody blank journal - just show info
        local infoOption = context:addOption(
            getText("ContextMenu_BurdJournals_BloodyBlank") or "Bloody Blank Journal",
            nil, nil
        )
        infoOption.notAvailable = true
    end

    -- Info about conversion to personal journal (via crafting)
    local craftOption = context:addOption(
        getText("ContextMenu_BurdJournals_ConvertViaCrafting") or "Convert to Personal Journal...",
        nil, nil
    )
    craftOption.notAvailable = true
    local tooltip3 = ISToolTip:new()
    tooltip3:initialise()
    tooltip3:setVisible(false)
    tooltip3:setName(getText("Tooltip_BurdJournals_CraftingRequired") or "Crafting Required")
    tooltip3.description = getText("Tooltip_BurdJournals_ConvertBloodyDesc") or "Open the crafting menu (B) to find 'Clean and Convert Bloody Journal'.\nRequires: Soap, Cloth, Leather, Thread, Needle, Tailoring Lv1.\nWARNING: Destroys any remaining rewards!"
    craftOption.toolTip = tooltip3
end

-- ==================== WORN JOURNAL OPTIONS ====================

function BurdJournals.ContextMenu.addWornJournalOptions(context, player, journal, isBlank)
    -- Debug removed
    
    local ok, err = pcall(function()
        local journalData = BurdJournals.getJournalData(journal)
        local isFilled = BurdJournals.isFilledJournal(journal)
        
        if isFilled and journalData then
            -- Debug removed
            
            -- Count skills and traits separately for detailed display
            local skillCount = 0
            local totalSkills = 0
            local traitCount = 0
            local totalTraits = 0

            if journalData.skills then
                for skillName, _ in pairs(journalData.skills) do
                    totalSkills = totalSkills + 1
                    if not BurdJournals.isSkillClaimed(journal, skillName) then
                        skillCount = skillCount + 1
                    end
                end
            end
            if journalData.traits then
                for traitId, _ in pairs(journalData.traits) do
                    totalTraits = totalTraits + 1
                    if not BurdJournals.isTraitClaimed(journal, traitId) then
                        traitCount = traitCount + 1
                    end
                end
            end

            local remaining = skillCount + traitCount

            -- Open Journal... (absorption UI)
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

        -- Build detailed tooltip showing skills available
        local tooltipDesc = ""
        if totalSkills > 0 then
            tooltipDesc = (getText("Tooltip_BurdJournals_SkillsAvailable") or "Skills: %d/%d available"):gsub("%%d/%%d", skillCount .. "/" .. totalSkills)
        end
        if tooltipDesc == "" then
            tooltipDesc = getText("Tooltip_BurdJournals_NoRewardsFound") or "No rewards found"
        end
        tooltip.description = tooltipDesc
        openOption.toolTip = tooltip

        -- Absorb All (quick action)
        if remaining > 0 then
            local absorbLabel = getText("Tooltip_BurdJournals_AbsorbAllRewards") or "Absorb All Rewards"
            if traitCount > 0 then
                absorbLabel = string.format(getText("Tooltip_BurdJournals_AbsorbAllSkillsTraits") or "Absorb All (%d skills, %d traits)", skillCount, traitCount)
            elseif skillCount > 0 then
                absorbLabel = string.format(getText("Tooltip_BurdJournals_AbsorbAllSkills") or "Absorb All (%d skills)", skillCount)
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
            tooltip2.description = getText("Tooltip_BurdJournals_AbsorbAllDesc") or "Opens the journal and begins reading all rewards.\nRequires time to absorb each skill and trait.\nMaxed skills and known traits will be skipped."
            absorbAllOption.toolTip = tooltip2
        end
    else
        -- Empty worn journal - just show info
        local infoOption = context:addOption(
            getText("ContextMenu_BurdJournals_WornBlank") or "Worn Blank Journal",
            nil, nil
        )
        infoOption.notAvailable = true
    end
    
    -- Convert to Personal Journal (Tailoring)
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
        tooltip3.description = getText("Tooltip_BurdJournals_NeedsConvertMaterials") or "Requires: Leather + Thread + Needle + Tailoring Lv1"
        convertOption.toolTip = tooltip3
    else
        local tooltip3 = ISToolTip:new()
        tooltip3:initialise()
        tooltip3:setVisible(false)
        tooltip3:setName(getText("Tooltip_BurdJournals_ConvertToClean") or "Convert to Personal Journal")
        tooltip3.description = getText("Tooltip_BurdJournals_ConvertToCleanDesc") or "Restore this worn journal to a clean blank journal for personal use."
        convertOption.toolTip = tooltip3
    end
    
    end) -- end pcall
    
    if not ok then
        print("[BurdJournals] ERROR in addWornJournalOptions: " .. tostring(err))
    end
end

-- ==================== CLEAN FILLED JOURNAL OPTIONS ====================

function BurdJournals.ContextMenu.addCleanFilledJournalOptions(context, player, journal)
    local journalData = BurdJournals.getJournalData(journal)
    local hasPen = BurdJournals.hasWritingTool(player)
    local hasEraser = BurdJournals.hasEraser(player)

    -- Check permissions for viewing/claiming
    local canOpen, openReason = BurdJournals.canPlayerOpenJournal(player, journal)
    local canClaim, claimReason = BurdJournals.canPlayerClaimFromJournal(player, journal)
    local isOwner = BurdJournals.isJournalOwner(player, journal)
    
    -- Count claimable skills and traits
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
    
    -- Open Journal... (view/claiming UI)
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
        tooltip.description = openReason or "You don't have permission to open this journal."
        openOption.toolTip = tooltip
    elseif journalData then
        local tooltip = ISToolTip:new()
        tooltip:initialise()
        tooltip:setVisible(false)
        tooltip:setName(getText("Tooltip_BurdJournals_PersonalJournal") or "Personal Survival Journal")
        local author = journalData.author or (getText("UI_BurdJournals_Unknown") or "Unknown")
        local desc = (getText("Tooltip_BurdJournals_WrittenBy") or "Written by: %s"):gsub("%%s", author) .. "\n"
        local itemText = totalRecorded > 1 and (getText("Tooltip_BurdJournals_RecordedItems") or "Contains %d recorded items") or (getText("Tooltip_BurdJournals_RecordedItem") or "Contains %d recorded item")
        desc = desc .. string.format(itemText, totalRecorded) .. "\n\n"
        if claimableSkills > 0 or claimableTraits > 0 then
            if canClaim then
                desc = desc .. (getText("Tooltip_BurdJournals_ClaimableRewards") or "Claimable rewards:") .. "\n"
                if claimableSkills > 0 then
                    local skillText = claimableSkills > 1 and (getText("Tooltip_BurdJournals_SkillsCount") or "  - %d skills") or (getText("Tooltip_BurdJournals_SkillCount") or "  - %d skill")
                    desc = desc .. string.format(skillText, claimableSkills) .. "\n"
                end
                if claimableTraits > 0 then
                    local traitText = claimableTraits > 1 and (getText("Tooltip_BurdJournals_TraitsCount") or "  - %d traits") or (getText("Tooltip_BurdJournals_TraitCount") or "  - %d trait")
                    desc = desc .. string.format(traitText, claimableTraits) .. "\n"
                end
            else
                desc = desc .. (getText("Tooltip_BurdJournals_ViewOnly") or "View only") .. " - " .. (claimReason or (getText("Tooltip_BurdJournals_CannotClaimDefault") or "Cannot claim from this journal.")) .. "\n"
            end
        else
            desc = desc .. (getText("Tooltip_BurdJournals_NoNewRewards") or "No new rewards available.") .. "\n"
        end
        desc = desc .. "\n" .. (getText("Tooltip_BurdJournals_ClaimingInfo") or "Claiming sets your XP to the recorded level (if higher).")
        tooltip.description = desc
        openOption.toolTip = tooltip
    end
    
    -- Update Records (adds/updates current skills to journal) - Owner only
    if hasPen and isOwner then
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
        tooltip.description = getText("Tooltip_BurdJournals_UpdateRecordsDesc") or "Opens journal to update your recorded skills.\nRecorded values are only updated if your current level is higher."
        recordOption.toolTip = tooltip
    end
    
    -- Claim All (with timed learning UI)
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
            tooltip.description = claimReason or (getText("Tooltip_BurdJournals_NoPermissionClaim") or "You don't have permission to claim from this journal.")
            claimAllOption.toolTip = tooltip
        else
            local tooltip = ISToolTip:new()
            tooltip:initialise()
            tooltip:setVisible(false)
            tooltip:setName(getText("Tooltip_BurdJournals_ClaimAll") or "Claim All Skills")
            local desc = (getText("Tooltip_BurdJournals_ClaimAllDesc") or "Opens journal and claims all available skills.") .. "\n\n"
            local skillText = claimableSkills > 1 and (getText("Tooltip_BurdJournals_AvailableSkills") or "Available: %d skills") or (getText("Tooltip_BurdJournals_AvailableSkill") or "Available: %d skill")
            desc = desc .. string.format(skillText, claimableSkills)
            if claimableTraits > 0 then
                local traitText = claimableTraits > 1 and (getText("Tooltip_BurdJournals_AndTraits") or ", %d traits") or (getText("Tooltip_BurdJournals_AndTrait") or ", %d trait")
                desc = desc .. string.format(traitText, claimableTraits)
            end
            desc = desc .. "\n\n" .. (getText("Tooltip_BurdJournals_ReadingSpeedNote") or "This will take time based on your reading speed.")
            tooltip.description = desc
            claimAllOption.toolTip = tooltip
        end
    end
    
    -- Rename - Owner only
    if isOwner then
        context:addOption(
            getText("ContextMenu_BurdJournals_Rename") or "Rename",
            player,
            BurdJournals.ContextMenu.onRenameJournal,
            journal
        )
    end

    -- Erase Journal (resets to blank) - Owner only
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
        tooltip.description = getText("Tooltip_BurdJournals_EraseContentsDesc") or "Erases all recorded data, returning the journal to a blank state.\nRequires an eraser."
        eraseOption.toolTip = tooltip
    end
end

-- ==================== CLEAN BLANK JOURNAL OPTIONS ====================

function BurdJournals.ContextMenu.addCleanBlankJournalOptions(context, player, journal)
    local hasPen = BurdJournals.hasWritingTool(player)

    -- Open Journal... (for blank journals, opens in log/record mode)
    local openOption = context:addOption(
        getText("ContextMenu_BurdJournals_OpenJournal") or "Open Journal...",
        player,
        BurdJournals.ContextMenu.onRecordProgress,
        journal
    )
    local tooltip = ISToolTip:new()
    tooltip:initialise()
    tooltip:setVisible(false)
    tooltip:setName(getText("Tooltip_BurdJournals_BlankJournal") or "Blank Survival Journal")
    tooltip.description = getText("Tooltip_BurdJournals_BlankJournalDesc") or "Opens the journal to record your survival progress.\nRequires a writing tool."
    openOption.toolTip = tooltip
    if not hasPen then
        openOption.notAvailable = true
    end

    -- Rename
    context:addOption(
        getText("ContextMenu_BurdJournals_Rename") or "Rename",
        player,
        BurdJournals.ContextMenu.onRenameJournal,
        journal
    )

    -- Disassemble Journal (get materials back)
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
    tooltip2.description = getText("Tooltip_BurdJournals_DisassembleDesc") or "Tear apart this journal for materials.\n\nYou will receive:\n  2x Paper\n  1x Leather Strips"
    disassembleOption.toolTip = tooltip2
end

-- ==================== ACTION CALLBACKS ====================

-- Show confirmation dialog before Absorb All
function BurdJournals.ContextMenu.onAbsorbAllConfirm(player, journal)
    local journalData = BurdJournals.getJournalData(journal)

    -- Count skills and traits
    local skillCount = 0
    local traitCount = 0
    if journalData and journalData.skills then
        for skillName, _ in pairs(journalData.skills) do
            if not BurdJournals.isSkillClaimed(journal, skillName) then
                skillCount = skillCount + 1
            end
        end
    end
    if journalData and journalData.traits then
        for traitId, _ in pairs(journalData.traits) do
            if not BurdJournals.isTraitClaimed(journal, traitId) then
                traitCount = traitCount + 1
            end
        end
    end

    local confirmText = (getText("UI_BurdJournals_ConfirmAbsorbAll") or "Absorb all remaining rewards?") .. "\n\n"
    if skillCount > 0 then
        local skillText = skillCount > 1 and (getText("UI_BurdJournals_SkillsCount") or "%d skills") or (getText("UI_BurdJournals_SkillCount") or "%d skill")
        confirmText = confirmText .. string.format(skillText, skillCount) .. "\n"
    end
    if traitCount > 0 then
        local traitText = traitCount > 1 and (getText("UI_BurdJournals_RareTraitsCount") or "%d rare traits") or (getText("UI_BurdJournals_RareTraitCount") or "%d rare trait")
        confirmText = confirmText .. string.format(traitText, traitCount) .. "\n"
    end
    confirmText = confirmText .. "\n" .. (getText("UI_BurdJournals_MaxedSkillsSkipped") or "Maxed skills and known traits will be skipped.")

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
    modal:addToUIManager()
end

function BurdJournals.ContextMenu.onConfirmAbsorbAll(target, button, journal)
    if button.internal == "YES" then
        -- Pick up the journal first if it's not in inventory, then open and start learning
        BurdJournals.ContextMenu.pickUpThenDo(target, journal, function(player, j)
            if not BurdJournals.UI then
                require "UI/BurdJournals_MainPanel"
            end
            
            if BurdJournals.UI and BurdJournals.UI.MainPanel then
                -- Show the panel first
                BurdJournals.UI.MainPanel.show(player, j, "absorb")
                
                -- Then immediately trigger the learning process
                local ticksWaited = 0
                local startLearning
                startLearning = function()
                    ticksWaited = ticksWaited + 1
                    if ticksWaited >= 2 then
                        Events.OnTick.Remove(startLearning)
                        if BurdJournals.UI.MainPanel.instance then
                            BurdJournals.UI.MainPanel.instance:startLearningAll()
                        end
                    end
                end
                Events.OnTick.Add(startLearning)
            end
        end)
    end
end

-- Open worn journal (absorption UI)
function BurdJournals.ContextMenu.onOpenWornJournal(player, journal)
    -- Pick up the journal first if it's not in inventory
    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j)
        if not BurdJournals.UI then
            require "UI/BurdJournals_MainPanel"
        end

        if BurdJournals.UI and BurdJournals.UI.MainPanel then
            BurdJournals.UI.MainPanel.show(p, j, "absorb")
        end
    end)
end

-- Open bloody journal (absorption UI - same as worn but with rare rewards)
function BurdJournals.ContextMenu.onOpenBloodyJournal(player, journal)
    -- Pick up the journal first if it's not in inventory
    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j)
        if not BurdJournals.UI then
            require "UI/BurdJournals_MainPanel"
        end

        if BurdJournals.UI and BurdJournals.UI.MainPanel then
            BurdJournals.UI.MainPanel.show(p, j, "absorb")
        end
    end)
end

-- Absorb all from worn/bloody journal (handles single player directly)
-- Only claims rewards that are actually absorbed (not maxed skills or already-known traits)
function BurdJournals.ContextMenu.onAbsorbAllFromJournal(player, journal)
    -- Refresh player reference to avoid stale data from context menu callback
    local playerNum = player and player:getPlayerNum() or 0
    player = getSpecificPlayer(playerNum) or getSpecificPlayer(0)
    if not player then
        -- Debug removed
        return
    end

    local totalXP = 0
    local skillsAbsorbed = 0
    local skillsSkipped = 0
    local traitsAbsorbed = 0
    local traitsSkipped = 0

    -- Get all unclaimed skills
    local unclaimed = BurdJournals.getUnclaimedSkills(journal)
    local journalData = BurdJournals.getJournalData(journal)

    -- In single player, apply directly; in multiplayer, use server commands
    if isClient() and not isServer() then
        -- Multiplayer - use server commands
        for skillName, _ in pairs(unclaimed) do
            sendClientCommand(player, "BurdJournals", "absorbSkill",
                {journalId = journal:getID(), skillName = skillName})
        end
        local unclaimedTraits = BurdJournals.getUnclaimedTraits(journal)
        for traitId, _ in pairs(unclaimedTraits) do
            sendClientCommand(player, "BurdJournals", "absorbTrait",
                {journalId = journal:getID(), traitId = traitId})
        end
    else
        -- Single player - apply XP directly, only claim what's actually absorbed
        -- Get journal XP multiplier from sandbox (default 1.0)
        local journalMultiplier = BurdJournals.getSandboxOption("JournalXPMultiplier") or 1.0

        for skillName, _ in pairs(unclaimed) do
            local skillData = journalData and journalData.skills and journalData.skills[skillName]
            local xp = skillData and skillData.xp or 0

            -- Use getPerkByName for proper skill name mapping (e.g., Foraging -> PlantScavenging)
            local perk = BurdJournals.getPerkByName(skillName)
            if perk and xp > 0 then
                local xpObj = player:getXp()
                local beforeXP = xpObj:getXP(perk)

                -- Apply journal multiplier
                local xpToApply = xp * journalMultiplier

                -- Passive skills (Fitness/Strength) need more XP - scale up
                local isPassiveSkill = (skillName == "Fitness" or skillName == "Strength")
                if isPassiveSkill then
                    xpToApply = xpToApply * 5
                end

                -- Use sendAddXp if available, otherwise fall back to AddXP
                if sendAddXp then
                    sendAddXp(player, perk, xpToApply, true)
                else
                    xpObj:AddXP(perk, xpToApply, true, true)
                end

                local afterXP = xpObj:getXP(perk)
                local actualGain = afterXP - beforeXP

                if actualGain > 0 then
                    -- XP was gained - mark as claimed
                    BurdJournals.claimSkill(journal, skillName)
                    totalXP = totalXP + actualGain
                    skillsAbsorbed = skillsAbsorbed + 1
                else
                    -- Skill maxed - don't claim
                    skillsSkipped = skillsSkipped + 1
                end
            end
        end

        -- Apply traits - only claim those successfully granted
        local unclaimedTraits = BurdJournals.getUnclaimedTraits(journal)
        for traitId, _ in pairs(unclaimedTraits) do
            if BurdJournals.playerHasTrait(player, traitId) then
                -- Already has trait - don't claim
                traitsSkipped = traitsSkipped + 1
            else
                -- Try to grant trait
                local success = pcall(function()
                    player:getTraits():add(traitId)
                end)
                if success then
                    BurdJournals.claimTrait(journal, traitId)
                    traitsAbsorbed = traitsAbsorbed + 1
                else
                    traitsSkipped = traitsSkipped + 1
                end
            end
        end

        -- Show combined feedback via halo text
        if totalXP > 0 or traitsAbsorbed > 0 then
            local message = "+" .. BurdJournals.formatXP(totalXP) .. " XP"
            if traitsAbsorbed > 0 then
                local traitText = traitsAbsorbed > 1 and (getText("UI_BurdJournals_PlusTraits") or ", +%d traits") or (getText("UI_BurdJournals_PlusTrait") or ", +%d trait")
                message = message .. string.format(traitText, traitsAbsorbed)
            end
            if HaloTextHelper and HaloTextHelper.addTextWithArrow then
                HaloTextHelper.addTextWithArrow(player, message, true, HaloTextHelper.getColorGreen())
            else
                player:Say(message)
            end
        end

        -- Show what was skipped (if any)
        if skillsSkipped > 0 or traitsSkipped > 0 then
            local skipMsg = ""
            if skillsSkipped > 0 then
                local skillText = skillsSkipped > 1 and (getText("UI_BurdJournals_SkillsAlreadyMaxed") or "%d skills already maxed") or (getText("UI_BurdJournals_SkillAlreadyMaxed") or "%d skill already maxed")
                skipMsg = string.format(skillText, skillsSkipped)
            end
            if traitsSkipped > 0 then
                if skipMsg ~= "" then skipMsg = skipMsg .. ", " end
                local traitText = traitsSkipped > 1 and (getText("UI_BurdJournals_TraitsAlreadyKnown") or "%d traits already known") or (getText("UI_BurdJournals_TraitAlreadyKnown") or "%d trait already known")
                skipMsg = skipMsg .. string.format(traitText, traitsSkipped)
        end
        player:Say(skipMsg)
        end

        -- Only dissolve if ALL rewards have been claimed (nothing left)
        if BurdJournals.shouldDissolve(journal) then
            player:getInventory():Remove(journal)
            local dissolveMsg = BurdJournals.getRandomDissolutionMessage()
            player:Say(dissolveMsg)
            pcall(function() player:getEmitter():playSound("PaperRip") end)
        end
    end
end

-- Convert worn to clean
function BurdJournals.ContextMenu.onConvertToClean(player, journal)
    -- Pick up the journal first if it's not in inventory
    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j)
        local isFilled = BurdJournals.isFilledJournal(j)
        local remaining = BurdJournals.getRemainingRewards(j)
        
        if isFilled and remaining > 0 then
            -- Show confirmation dialog
            local modal = ISModalDialog:new(
                getCore():getScreenWidth() / 2 - 150,
                getCore():getScreenHeight() / 2 - 50,
                300, 120,
                getText("UI_BurdJournals_ConfirmConvert") or "This will destroy the remaining rewards. Are you sure?",
                true,
                p,
                BurdJournals.ContextMenu.onConfirmConvert,
                nil,
                j
            )
            modal:initialise()
            modal:addToUIManager()
        else
            -- No remaining rewards, just convert
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

-- Open clean journal
function BurdJournals.ContextMenu.onOpenCleanJournal(player, journal)
    -- Pick up the journal first if it's not in inventory
    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j)
        if not BurdJournals.UI then
            require "UI/BurdJournals_MainPanel"
        end
        
        if BurdJournals.UI and BurdJournals.UI.MainPanel then
            BurdJournals.UI.MainPanel.show(p, j, "view")
        end
    end)
end

-- Read clean journal (SET mode) - DEPRECATED, use UI-based claiming instead
function BurdJournals.ContextMenu.onReadCleanJournal(player, journal)
    -- Pick up the journal first if it's not in inventory
    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j)
        sendClientCommand(
            p,
            "BurdJournals",
            "learnSkills",
            {journalId = j:getID()}
        )
    end)
end

-- Claim All from clean journal (opens UI and starts timed claiming)
function BurdJournals.ContextMenu.onClaimAllConfirm(player, journal)
    -- Pick up the journal first if it's not in inventory
    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j)
        if not BurdJournals.UI then
            require "UI/BurdJournals_MainPanel"
        end
        
        if BurdJournals.UI and BurdJournals.UI.MainPanel then
            -- Show the panel in view mode
            BurdJournals.UI.MainPanel.show(p, j, "view")
            
            -- Start learning all after a small delay
            local panel = BurdJournals.UI.MainPanel.instance
            if panel and panel.startLearningAll then
                local ticksWaited = 0
                local startLearning
                startLearning = function()
                    ticksWaited = ticksWaited + 1
                    if ticksWaited >= 2 then
                        Events.OnTick.Remove(startLearning)
                        if BurdJournals.UI.MainPanel.instance then
                            BurdJournals.UI.MainPanel.instance:startLearningAll()
                        end
                    end
                end
                Events.OnTick.Add(startLearning)
            end
        end
    end)
end

-- Rename journal
function BurdJournals.ContextMenu.onRenameJournal(player, journal)
    -- Pick up the journal first if it's not in inventory
    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j)
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
        modal:addToUIManager()
    end)
end

function BurdJournals.ContextMenu.onConfirmRename(target, button, journal)
    if button.internal == "OK" then
        local newName = button.parent.entry:getText()
        if newName and newName ~= "" then
            journal:setName(newName)
        end
    end
end

-- Erase journal
function BurdJournals.ContextMenu.onEraseJournal(player, journal)
    -- Pick up the journal first if it's not in inventory
    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j)
        local modal = ISModalDialog:new(
            getCore():getScreenWidth() / 2 - 150,
            getCore():getScreenHeight() / 2 - 50,
            300, 120,
            getText("UI_BurdJournals_ConfirmErase") or "Erase all content? This cannot be undone.",
            true,
            p,
            BurdJournals.ContextMenu.onConfirmErase,
            nil,
            j
        )
        modal:initialise()
        modal:addToUIManager()
    end)
end

function BurdJournals.ContextMenu.onConfirmErase(target, button, journal)
    if button.internal == "YES" then
        -- Use timed action for erasing (10 seconds)
        if BurdJournals.EraseJournalAction then
            ISTimedActionQueue.add(BurdJournals.EraseJournalAction:new(target, journal))
        else
            -- Fallback to immediate if timed action not loaded
            sendClientCommand(
                target,
                "BurdJournals",
                "eraseJournal",
                {journalId = journal:getID()}
            )
        end
    end
end

-- Record progress
function BurdJournals.ContextMenu.onRecordProgress(player, journal)
    -- Pick up the journal first if it's not in inventory
    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j)
        if not BurdJournals.UI then
            require "UI/BurdJournals_MainPanel"
        end
        
        if BurdJournals.UI and BurdJournals.UI.MainPanel then
            BurdJournals.UI.MainPanel.show(p, j, "log")
        end
    end)
end

-- Record progress (overwrite existing)
function BurdJournals.ContextMenu.onRecordProgressOverwrite(player, journal)
    -- Pick up the journal first if it's not in inventory
    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j)
        local modal = ISModalDialog:new(
            getCore():getScreenWidth() / 2 - 150,
            getCore():getScreenHeight() / 2 - 50,
            300, 120,
            getText("UI_BurdJournals_ConfirmOverwrite") or "Overwrite existing content?",
            true,
            p,
            BurdJournals.ContextMenu.onConfirmOverwrite,
            nil,
            j
        )
        modal:initialise()
        modal:addToUIManager()
    end)
end

function BurdJournals.ContextMenu.onConfirmOverwrite(target, button, journal)
    if button.internal == "YES" then
        if not BurdJournals.UI then
            require "UI/BurdJournals_MainPanel"
        end
        
        if BurdJournals.UI and BurdJournals.UI.MainPanel then
            BurdJournals.UI.MainPanel.show(target, journal, "log")
        end
    end
end

-- Disassemble journal (get materials back)
function BurdJournals.ContextMenu.onDisassembleJournal(player, journal)
    -- Pick up the journal first if it's not in inventory
    BurdJournals.ContextMenu.pickUpThenDo(player, journal, function(p, j)
        -- Show confirmation dialog
        local confirmText = getText("UI_BurdJournals_ConfirmDisassemble") or "Disassemble this journal?"
        confirmText = confirmText .. "\n\nYou will receive:\n2x Paper, 1x Leather Strips"

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
        modal:addToUIManager()
    end)
end

function BurdJournals.ContextMenu.onConfirmDisassemble(target, button, journal)
    if button.internal == "YES" then
        if BurdJournals.DisassembleJournalAction then
            ISTimedActionQueue.add(BurdJournals.DisassembleJournalAction:new(target, journal))
        end
    end
end

-- ==================== RECIPE STRING PARSER (for disassemble output) ====================

function BurdJournals.ContextMenu.parseRecipeString(recipeStr)
    local materials = {}
    if not recipeStr or recipeStr == "" then return materials end

    -- Split by pipe |
    for part in recipeStr:gmatch("[^|]+") do
        part = part:match("^%s*(.-)%s*$") -- trim whitespace
        if part and part ~= "" then
            local mat = {}
            -- Check for :keep suffix
            mat.keep = part:match(":keep$") ~= nil
            if mat.keep then
                part = part:gsub(":keep$", "")
            end

            -- Parse type:qty format
            local itemType, qty = part:match("^(.+):(%d+)$")
            if itemType and qty then
                mat.type = itemType
                mat.count = tonumber(qty)
                -- Generate display name
                mat.name = itemType:gsub("Base%.", ""):gsub("tag:", "")
                mat.name = mat.name:gsub("(%l)(%u)", "%1 %2") -- CamelCase to spaced
                table.insert(materials, mat)
            end
        end
    end
    return materials
end

-- ==================== EVENT REGISTRATION ====================

Events.OnFillInventoryObjectContextMenu.Add(BurdJournals.ContextMenu.onFillInventoryObjectContextMenu)



