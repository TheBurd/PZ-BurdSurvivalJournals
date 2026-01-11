--[[
    Burd's Survival Journals - Timed Actions
    Build 42 - Version 2.0

    Timed actions for journal operations:
    - ConvertToCleanAction: Convert worn journal to clean blank (tailoring)

    Note: Bloody journal cleaning is now done via the crafting menu only
    (CleanBloodyFilledToClean recipe) to prevent Bloodyâ†’Worn exploit.
]]

require "TimedActions/ISBaseTimedAction"
require "BurdJournals_Shared"

BurdJournals = BurdJournals or {}

-- ==================== CONVERT TO CLEAN ACTION ====================
-- Converts a worn journal to a clean blank journal using tailoring materials

BurdJournals.ConvertToCleanAction = ISBaseTimedAction:derive("BurdJournals_ConvertToCleanAction")

function BurdJournals.ConvertToCleanAction:new(character, journal)
    local o = ISBaseTimedAction.new(self, character)
    
    o.journal = journal
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true
    
    -- Use sandbox option for convert time (default 15 seconds = 500 ticks at ~33 ticks/sec)
    local convertTime = BurdJournals.getSandboxOption("ConvertTime") or 15.0
    o.maxTime = math.floor(convertTime * 33)
    
    return o
end

function BurdJournals.ConvertToCleanAction:isValid()
    local player = self.character
    if not player then return false end
    
    -- Check if journal is still in inventory
    local journal = BurdJournals.findItemById(player, self.journal:getID())
    if not journal then return false end
    
    -- Check if still worn
    if not BurdJournals.isWorn(journal) then return false end
    
    -- Check materials and skill
    return BurdJournals.canConvertToClean(player)
end

function BurdJournals.ConvertToCleanAction:update()
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function BurdJournals.ConvertToCleanAction:start()
    self:setActionAnim("Loot")
    self.character:reportEvent("EventCrafting")
    -- Play sewing sound (looped)
    self.sound = self.character:getEmitter():playSound("Sewing")
end

function BurdJournals.ConvertToCleanAction:stop()
    -- Stop the sewing sound
    if self.sound and self.sound ~= 0 then
        self.character:getEmitter():stopSound(self.sound)
    end
    ISBaseTimedAction.stop(self)
end

function BurdJournals.ConvertToCleanAction:perform()
    -- Stop the sewing sound
    if self.sound and self.sound ~= 0 then
        self.character:getEmitter():stopSound(self.sound)
    end
    
    local player = self.character

    -- In single player, handle directly
    -- In multiplayer, send to server (server handles material consumption)
    if isClient() and not isServer() then
        -- Multiplayer - server will validate and consume materials
        sendClientCommand(
            player,
            "BurdJournals",
            "convertToClean",
            {journalId = self.journal:getID()}
        )
    else
        -- Single player - handle directly here
        local inventory = player:getInventory()

        -- Consume leather strips
        local leather = BurdJournals.findRepairItem(player, "leather")
        if leather then
            inventory:Remove(leather)
        end

        -- Consume thread (drainable)
        local thread = BurdJournals.findRepairItem(player, "thread")
        if thread then
            BurdJournals.consumeItemUses(thread, 1, player)
        end

        -- Needle is a tool - wear it slightly
        local needle = BurdJournals.findRepairItem(player, "needle")
        if needle then
            BurdJournals.consumeItemUses(needle, 1, player)
        end

        -- Replace worn journal with clean blank
        local journal = BurdJournals.findItemById(player, self.journal:getID())
        if journal then
            inventory:Remove(journal)
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
            end
            player:Say(getText("UI_BurdJournals_JournalRestored") or "Journal restored!")
        end
    end

    ISBaseTimedAction.perform(self)
end

-- ==================== ERASE JOURNAL ACTION ====================
-- Erases all content from a journal, returning it to blank state

BurdJournals.EraseJournalAction = ISBaseTimedAction:derive("BurdJournals_EraseJournalAction")

function BurdJournals.EraseJournalAction:new(character, journal)
    local o = ISBaseTimedAction.new(self, character)
    
    o.journal = journal
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true
    
    -- Use sandbox option for erase time (default 10 seconds = 330 ticks at ~33 ticks/sec)
    local eraseTime = BurdJournals.getSandboxOption("EraseTime") or 10.0
    o.maxTime = math.floor(eraseTime * 33)
    
    return o
end

function BurdJournals.EraseJournalAction:isValid()
    local player = self.character
    if not player then return false end
    
    -- Check if journal is still in inventory
    local journal = BurdJournals.findItemById(player, self.journal:getID())
    if not journal then return false end
    
    -- Check if player still has an eraser
    return BurdJournals.hasEraser(player)
end

function BurdJournals.EraseJournalAction:update()
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function BurdJournals.EraseJournalAction:start()
    self:setActionAnim("Loot")
    self.character:reportEvent("EventCrafting")
    -- Play erasing sound (looped)
    self.sound = self.character:getEmitter():playSound("RummageInInventory")
end

function BurdJournals.EraseJournalAction:stop()
    -- Stop the erasing sound
    if self.sound and self.sound ~= 0 then
        self.character:getEmitter():stopSound(self.sound)
    end
    ISBaseTimedAction.stop(self)
end

function BurdJournals.EraseJournalAction:perform()
    -- Stop the erasing sound
    if self.sound and self.sound ~= 0 then
        self.character:getEmitter():stopSound(self.sound)
    end
    
    local player = self.character
    local journal = BurdJournals.findItemById(player, self.journal:getID())
    
    if not journal then
        ISBaseTimedAction.perform(self)
        return
    end
    
    -- Send erase command to server (or handle locally in SP)
    if isClient() and not isServer() then
        sendClientCommand(
            player,
            "BurdJournals",
            "eraseJournal",
            {journalId = journal:getID()}
        )
    else
        -- Single player - handle directly
        local inventory = player:getInventory()
        local journalType = journal:getFullType()
        
        -- Remove the old journal
        inventory:Remove(journal)
        
        -- Add a new blank journal
        local blankJournal = inventory:AddItem("BurdJournals.BlankSurvivalJournal")
        if blankJournal then
            local modData = blankJournal:getModData()
            modData.BurdJournals = {
                isWorn = false,
                isBloody = false,
                wasFromBloody = false,
                isPlayerCreated = true,
            }
            BurdJournals.updateJournalName(blankJournal)
            BurdJournals.updateJournalIcon(blankJournal)
        end
        
        player:Say(getText("UI_BurdJournals_JournalErased") or "Journal erased...")
    end

    ISBaseTimedAction.perform(self)
end

-- ==================== BIND JOURNAL ACTION ====================
-- Binds a vanilla Journal or Notebook into a Survival Journal using context menu crafting
-- Respects sandbox-configurable JSON recipe requirements

BurdJournals.BindJournalAction = ISBaseTimedAction:derive("BurdJournals_BindJournalAction")

function BurdJournals.BindJournalAction:new(character, sourceItem, actionType)
    local o = ISBaseTimedAction.new(self, character)

    o.sourceItem = sourceItem
    o.actionType = actionType or "BindJournal"
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true

    -- Get config from dynamic recipe system (default 120 seconds = ~4000 ticks at ~33 ticks/sec)
    local config = BurdJournals.ContextMenu and BurdJournals.ContextMenu.getCraftingConfig and
                   BurdJournals.ContextMenu.getCraftingConfig(o.actionType)
    local bindTime = config and config.time or 120
    o.maxTime = math.floor(bindTime * 33)
    o.xpAward = config and config.xpAward or 0

    return o
end

function BurdJournals.BindJournalAction:isValid()
    local player = self.character
    if not player then return false end

    -- Check if source item is still in inventory
    local inventory = player:getInventory()
    if not inventory:contains(self.sourceItem) then return false end

    -- Check if player still has required materials
    if BurdJournals.ContextMenu and BurdJournals.ContextMenu.hasRequiredMaterials then
        local hasMaterials = BurdJournals.ContextMenu.hasRequiredMaterials(player, self.actionType)
        if not hasMaterials then return false end
    end

    -- Check tailoring level
    local config = BurdJournals.ContextMenu and BurdJournals.ContextMenu.getCraftingConfig and
                   BurdJournals.ContextMenu.getCraftingConfig(self.actionType)
    if config and config.tailoringRequired > 0 then
        if not BurdJournals.ContextMenu.hasTailoringLevel(player, config.tailoringRequired) then
            return false
        end
    end

    return true
end

function BurdJournals.BindJournalAction:update()
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function BurdJournals.BindJournalAction:start()
    self:setActionAnim("Loot")
    self.character:reportEvent("EventCrafting")
    -- Play sewing sound (looped)
    self.sound = self.character:getEmitter():playSound("Sewing")
end

function BurdJournals.BindJournalAction:stop()
    -- Stop the sewing sound
    if self.sound and self.sound ~= 0 then
        self.character:getEmitter():stopSound(self.sound)
    end
    ISBaseTimedAction.stop(self)
end

function BurdJournals.BindJournalAction:perform()
    -- Stop the sewing sound
    if self.sound and self.sound ~= 0 then
        self.character:getEmitter():stopSound(self.sound)
    end

    local player = self.character
    local inventory = player:getInventory()

    -- Get material configuration from dynamic recipe system
    local config = BurdJournals.ContextMenu and BurdJournals.ContextMenu.getCraftingConfig and
                   BurdJournals.ContextMenu.getCraftingConfig(self.actionType)
    if not config then
        print("[BurdJournals] ERROR: Invalid action type in BindJournalAction: " .. tostring(self.actionType))
        ISBaseTimedAction.perform(self)
        return
    end

    -- Consume materials (if any - empty recipe = free crafting)
    for _, mat in ipairs(config.materials) do
        for i = 1, mat.count do
            local item = BurdJournals.ContextMenu.findItemByTypeOrTag(player, mat)
            if item then
                if mat.keep then
                    -- Tool - just degrade it slightly
                    if item:getCondition() then
                        item:setCondition(item:getCondition() - 1)
                    end
                else
                    -- Consumable - remove it
                    inventory:Remove(item)
                end
            end
        end
    end

    -- Remove the source journal/notebook
    inventory:Remove(self.sourceItem)

    -- Create the survival journal
    local newJournal = inventory:AddItem("BurdJournals.BlankSurvivalJournal")
    if newJournal then
        local modData = newJournal:getModData()
        modData.BurdJournals = {
            isWorn = false,
            isBloody = false,
            wasFromBloody = false,
            isPlayerCreated = true,
            sourceType = "crafted",
        }
        BurdJournals.updateJournalName(newJournal)
        BurdJournals.updateJournalIcon(newJournal)
    end

    -- Award Tailoring XP (if enabled in sandbox)
    if config.xpAward and config.xpAward > 0 then
        player:getXp():AddXP(Perks.Tailoring, config.xpAward)
    end

    -- Feedback
    local boundMsg = getText("UI_BurdJournals_JournalBound") or "Journal bound!"
    if HaloTextHelper and HaloTextHelper.addTextWithArrow then
        HaloTextHelper.addTextWithArrow(player, boundMsg, true, HaloTextHelper.getColorGreen())
    else
        player:Say(boundMsg)
    end

    ISBaseTimedAction.perform(self)
end

-- ==================== DISASSEMBLE JOURNAL ACTION ====================
-- Disassembles a Blank Survival Journal into component materials
-- Output materials are configurable via sandbox options

BurdJournals.DisassembleJournalAction = ISBaseTimedAction:derive("BurdJournals_DisassembleJournalAction")

function BurdJournals.DisassembleJournalAction:new(character, journal)
    local o = ISBaseTimedAction.new(self, character)

    o.journal = journal
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true

    -- Use sandbox option for disassemble time (default 30 seconds, ~1000 ticks at ~33 ticks/sec)
    local disassembleTime = BurdJournals.getSandboxOption("CraftingTime_DisassembleJournal") or 30.0
    o.maxTime = math.floor(disassembleTime * 33)

    return o
end

function BurdJournals.DisassembleJournalAction:isValid()
    local player = self.character
    if not player then return false end

    -- Check if journal is still in inventory
    local journal = BurdJournals.findItemById(player, self.journal:getID())
    if not journal then return false end

    -- Must be a blank survival journal
    return BurdJournals.isBlankJournal(journal)
end

function BurdJournals.DisassembleJournalAction:update()
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function BurdJournals.DisassembleJournalAction:start()
    self:setActionAnim("Loot")
    self.character:reportEvent("EventCrafting")
    -- Play paper ripping sound
    self.sound = self.character:getEmitter():playSound("PaperRip")
end

function BurdJournals.DisassembleJournalAction:stop()
    if self.sound and self.sound ~= 0 then
        self.character:getEmitter():stopSound(self.sound)
    end
    ISBaseTimedAction.stop(self)
end

function BurdJournals.DisassembleJournalAction:perform()
    if self.sound and self.sound ~= 0 then
        self.character:getEmitter():stopSound(self.sound)
    end

    local player = self.character
    local inventory = player:getInventory()
    local journal = BurdJournals.findItemById(player, self.journal:getID())

    if not journal then
        ISBaseTimedAction.perform(self)
        return
    end

    -- Remove the journal
    inventory:Remove(journal)

    -- Get output materials from sandbox
    local outputStr = BurdJournals.getSandboxOption("Recipe_DisassembleOutput") or "Base.SheetPaper2:2|Base.LeatherStrips:1"
    local outputs = BurdJournals.ContextMenu and BurdJournals.ContextMenu.parseRecipeString and
                    BurdJournals.ContextMenu.parseRecipeString(outputStr) or {}

    -- Give output items to player
    local itemsGiven = {}
    for _, mat in ipairs(outputs) do
        -- Only process direct item types (not tags) for output
        if mat.type and not mat.type:match("^tag:") then
            for i = 1, mat.count do
                inventory:AddItem(mat.type)
            end
            table.insert(itemsGiven, mat.count .. "x " .. mat.name)
        end
    end

    -- Feedback
    if #itemsGiven > 0 then
        local msg = string.format(getText("UI_BurdJournals_Salvaged") or "Salvaged: %s", table.concat(itemsGiven, ", "))
        if HaloTextHelper and HaloTextHelper.addTextWithArrow then
            HaloTextHelper.addTextWithArrow(player, msg, true, HaloTextHelper.getColorGreen())
        else
            player:Say(msg)
        end
    else
        player:Say(getText("UI_BurdJournals_JournalDisassembled") or "Journal disassembled.")
    end

    ISBaseTimedAction.perform(self)
end


-- ==================== LEARN FROM JOURNAL ACTION ====================
-- Timed action for learning skills/traits from journals
-- Uses ISTimedActionQueue so progress respects game pause

BurdJournals.LearnFromJournalAction = ISBaseTimedAction:derive("BurdJournals_LearnFromJournalAction")

function BurdJournals.LearnFromJournalAction:new(character, journal, rewards, isAbsorbAll, mainPanel, queuedRewards)
    local o = ISBaseTimedAction.new(self, character)

    o.journal = journal
    o.rewards = rewards or {}  -- Array of {type="skill"|"trait", name=..., xp=...}
    o.isAbsorbAll = isAbsorbAll or false
    o.mainPanel = mainPanel  -- Reference to UI panel for progress updates
    o.queuedRewards = queuedRewards or {}  -- Queue stored in action object, not just panel state
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true

    -- Calculate total time based on rewards
    local totalTime = 0
    for _, reward in ipairs(rewards) do
        if reward.type == "skill" then
            totalTime = totalTime + (mainPanel and mainPanel:getSkillLearningTime() or 3.0)
        elseif reward.type == "trait" then
            totalTime = totalTime + (mainPanel and mainPanel:getTraitLearningTime() or 5.0)
        end
    end

    -- Minimum time of 1 second for feedback
    totalTime = math.max(1.0, totalTime)
    o.totalTimeSeconds = totalTime
    o.maxTime = math.floor(totalTime * 33)  -- Convert seconds to ticks (~33 ticks/sec)

    return o
end

function BurdJournals.LearnFromJournalAction:isValid()
    local player = self.character
    if not player then return false end

    -- Check if journal is still in inventory
    local journal = BurdJournals.findItemById(player, self.journal:getID())
    if not journal then return false end

    -- Check if main panel is still open
    if self.mainPanel and not self.mainPanel:isVisible() then
        return false
    end

    return true
end

function BurdJournals.LearnFromJournalAction:update()
    self.character:setMetabolicTarget(Metabolics.LightWork)

    -- Update progress in the UI panel
    if self.mainPanel and self.mainPanel.learningState then
        local progress = self:getJobDelta()
        self.mainPanel.learningState.progress = progress
    end
end

function BurdJournals.LearnFromJournalAction:start()
    -- Set up reading animation with book in hand
    self:setAnimVariable("ReadType", "book")
    self:setActionAnim(CharacterActionAnims.Read)
    self:setOverrideHandModels(nil, self.journal)
    self.character:setReading(true)
    self.character:reportEvent("EventRead")

    -- Play book open sound
    self.character:playSound("OpenBook")

    -- Initialize learning state in UI if panel exists
    if self.mainPanel then
        local firstReward = self.rewards[1]
        self.mainPanel.learningState = {
            active = true,
            skillName = firstReward and firstReward.type == "skill" and firstReward.name or nil,
            traitId = firstReward and firstReward.type == "trait" and firstReward.name or nil,
            recipeName = firstReward and firstReward.type == "recipe" and firstReward.name or nil,
            isAbsorbAll = self.isAbsorbAll,
            progress = 0,
            totalTime = self.totalTimeSeconds,
            startTime = getTimestampMs(),  -- For backwards compatibility with UI display
            pendingRewards = self.rewards,
            currentIndex = 1,
            queue = self.queuedRewards,  -- Use queue from action object
            timedAction = self,  -- Reference to this action
        }
    end
end

function BurdJournals.LearnFromJournalAction:stop()
    -- Reset reading state and play close sound
    self.character:setReading(false)
    self.character:playSound("CloseBook")

    -- Reset UI state if cancelled
    if self.mainPanel then
        self.mainPanel.learningState = {
            active = false,
            skillName = nil,
            traitId = nil,
            recipeName = nil,
            isAbsorbAll = false,
            progress = 0,
            totalTime = 0,
            startTime = 0,
            pendingRewards = {},
            currentIndex = 0,
            queue = {},
        }
        -- Refresh UI to show cancelled state
        if self.mainPanel.refreshCurrentList then
            pcall(function() self.mainPanel:refreshCurrentList() end)
        end
    end

    ISBaseTimedAction.stop(self)
end

function BurdJournals.LearnFromJournalAction:perform()
    -- Reset reading state and play close sound
    self.character:setReading(false)
    self.character:playSound("CloseBook")

    local player = self.character
    local panel = self.mainPanel

    if not panel then
        ISBaseTimedAction.perform(self)
        return
    end

    -- Apply all rewards
    local isPlayerJournal = panel.isPlayerJournal or panel.mode == "view"

    for _, reward in ipairs(self.rewards) do
        if reward.type == "skill" then
            if isPlayerJournal then
                panel:sendClaimSkill(reward.name, reward.xp, true)
            else
                panel:sendAbsorbSkill(reward.name, reward.xp, true)
            end
        elseif reward.type == "trait" then
            if isPlayerJournal then
                panel:sendClaimTrait(reward.name, true)
            else
                panel:sendAbsorbTrait(reward.name, true)
            end
        end
    end

    -- Check if journal was dissolved during reward application (single player path)
    -- In SP, applyTraitDirectly calls checkDissolution which may have already closed the panel
    if not panel:isVisible() or not panel.journal then
        -- Panel was closed (journal dissolved) - don't continue queue processing
        ISBaseTimedAction.perform(self)
        return
    end

    -- Refresh UI
    panel:refreshPlayer()
    if isPlayerJournal then
        if panel.refreshJournalData then
            panel:refreshJournalData()
        end
    else
        if panel.refreshAbsorptionList then
            panel:refreshAbsorptionList()
        end
    end

    -- Get queue - merge action's queue with any items added to panel during this action
    -- Items queued during action go to panel.learningState.queue, items from previous actions are in self.queuedRewards
    local savedQueue = {}
    if not self.isAbsorbAll then
        -- First add items from action's queue (from previous action)
        for _, item in ipairs(self.queuedRewards or {}) do
            table.insert(savedQueue, item)
        end
        -- Then add any items added to panel during this action
        if panel.learningState and panel.learningState.queue then
            for _, item in ipairs(panel.learningState.queue) do
                -- Avoid duplicates
                local isDupe = false
                for _, existing in ipairs(savedQueue) do
                    if existing.name == item.name then
                        isDupe = true
                        break
                    end
                end
                if not isDupe then
                    table.insert(savedQueue, item)
                end
            end
        end
    end

    -- Check if there are queued items to learn next
    if #savedQueue > 0 then
        local nextReward = table.remove(savedQueue, 1)

        -- Update state for UI (show next item being learned)
        panel.learningState = {
            active = true,
            skillName = nextReward.type == "skill" and nextReward.name or nil,
            traitId = nextReward.type == "trait" and nextReward.name or nil,
            recipeName = nextReward.type == "recipe" and nextReward.name or nil,
            isAbsorbAll = false,
            progress = 0,
            totalTime = 0,
            startTime = 0,
            pendingRewards = {nextReward},
            currentIndex = 1,
            queue = savedQueue,
        }

        -- Refresh list to show updated state
        if panel.skillList and panel.journal then
            pcall(function()
                panel:refreshPlayer()
                if panel.mode == "view" or panel.isPlayerJournal then
                    panel:populateViewList()
                else
                    panel:populateAbsorptionList()
                end
            end)
        end

        -- Queue the next timed action for the next reward, passing remaining queue
        local nextRewards = {nextReward}
        local action = BurdJournals.LearnFromJournalAction:new(player, self.journal, nextRewards, false, panel, savedQueue)
        ISTimedActionQueue.add(action)

        ISBaseTimedAction.perform(self)
        return
    end

    -- No more queued items - fully complete
    panel.learningCompleted = true
    panel.learningState = {
        active = false,
        skillName = nil,
        traitId = nil,
        recipeName = nil,
        isAbsorbAll = false,
        progress = 0,
        totalTime = 0,
        startTime = 0,
        pendingRewards = {},
        currentIndex = 0,
        queue = {},
    }

    -- Play completion sound (only once at the end)
    if panel.playSound and BurdJournals.Sounds then
        panel:playSound(BurdJournals.Sounds.LEARN_COMPLETE)
    end

    -- Refresh list
    if panel.skillList and panel.journal then
        pcall(function()
            panel:refreshPlayer()
            if panel.mode == "view" or panel.isPlayerJournal then
                panel:populateViewList()
            else
                panel:populateAbsorptionList()
            end
        end)
    end

    -- Check dissolution only after queue is fully complete
    -- (Worn/Bloody journals dissolve when all rewards are claimed)
    -- Refresh journal reference first to ensure we have latest claimed data
    if panel.refreshJournalData then
        panel:refreshJournalData()
    end
    if panel.checkDissolution then
        panel:checkDissolution()
    end

    ISBaseTimedAction.perform(self)
end


-- ==================== RECORD TO JOURNAL ACTION ====================
-- Timed action for recording skills/traits/stats to journals
-- Uses ISTimedActionQueue so progress respects game pause

BurdJournals.RecordToJournalAction = ISBaseTimedAction:derive("BurdJournals_RecordToJournalAction")

function BurdJournals.RecordToJournalAction:new(character, journal, records, isRecordAll, mainPanel, queuedRecords)
    local o = ISBaseTimedAction.new(self, character)

    o.journal = journal
    o.records = records or {}  -- Array of {type="skill"|"trait"|"stat", name=..., xp=..., level=..., value=...}
    o.isRecordAll = isRecordAll or false
    o.mainPanel = mainPanel  -- Reference to UI panel for progress updates
    o.queuedRecords = queuedRecords or {}  -- Queue stored in action object, not just panel state
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true

    -- Calculate total time based on records
    local totalTime = 0
    for _, record in ipairs(records) do
        if record.type == "skill" then
            totalTime = totalTime + (mainPanel and mainPanel:getSkillRecordingTime() or 3.0)
        elseif record.type == "trait" then
            totalTime = totalTime + (mainPanel and mainPanel:getTraitRecordingTime() or 5.0)
        elseif record.type == "stat" then
            totalTime = totalTime + (mainPanel and mainPanel:getStatRecordingTime() or 2.0)
        end
    end

    -- Minimum time of 1 second for feedback
    totalTime = math.max(1.0, totalTime)
    o.totalTimeSeconds = totalTime
    o.maxTime = math.floor(totalTime * 33)  -- Convert seconds to ticks (~33 ticks/sec)

    return o
end

function BurdJournals.RecordToJournalAction:isValid()
    local player = self.character
    if not player then return false end

    -- Check if journal is still in inventory
    local journal = BurdJournals.findItemById(player, self.journal:getID())
    if not journal then return false end

    -- Check if main panel is still open
    if self.mainPanel and not self.mainPanel:isVisible() then
        return false
    end

    -- Check if pen is required and available
    local requirePen = BurdJournals.getSandboxOption("RequirePenToWrite")
    if requirePen ~= false then  -- default true
        if not BurdJournals.hasWritingTool(player) then
            return false
        end
    end

    return true
end

function BurdJournals.RecordToJournalAction:update()
    self.character:setMetabolicTarget(Metabolics.LightWork)

    -- Update progress in the UI panel
    if self.mainPanel and self.mainPanel.recordingState then
        local progress = self:getJobDelta()
        self.mainPanel.recordingState.progress = progress
    end
end

function BurdJournals.RecordToJournalAction:start()
    -- Set up writing animation with book in hand
    self:setAnimVariable("ReadType", "book")
    self:setActionAnim(CharacterActionAnims.Read)
    self:setOverrideHandModels(nil, self.journal)
    self.character:setReading(true)
    self.character:reportEvent("EventRead")

    -- Play book open sound
    self.character:playSound("OpenBook")

    -- Initialize recording state in UI if panel exists
    if self.mainPanel then
        local firstRecord = self.records[1]
        self.mainPanel.recordingState = {
            active = true,
            skillName = firstRecord and firstRecord.type == "skill" and firstRecord.name or nil,
            traitId = firstRecord and firstRecord.type == "trait" and firstRecord.name or nil,
            statId = firstRecord and firstRecord.type == "stat" and firstRecord.name or nil,
            recipeName = firstRecord and firstRecord.type == "recipe" and firstRecord.name or nil,
            isRecordAll = self.isRecordAll,
            progress = 0,
            totalTime = self.totalTimeSeconds,
            startTime = getTimestampMs(),  -- For backwards compatibility with UI display
            pendingRecords = self.records,
            currentIndex = 1,
            queue = self.queuedRecords,  -- Use queue from action object
            timedAction = self,  -- Reference to this action
        }
    end
end

function BurdJournals.RecordToJournalAction:stop()
    -- Reset reading state and play close sound
    self.character:setReading(false)
    self.character:playSound("CloseBook")

    -- Reset UI state if cancelled
    if self.mainPanel then
        self.mainPanel.recordingState = {
            active = false,
            skillName = nil,
            traitId = nil,
            statId = nil,
            recipeName = nil,
            isRecordAll = false,
            progress = 0,
            totalTime = 0,
            startTime = 0,
            pendingRecords = {},
            currentIndex = 0,
            queue = {},
        }
        -- Refresh UI to show cancelled state
        if self.mainPanel.refreshCurrentList then
            pcall(function() self.mainPanel:refreshCurrentList() end)
        end
    end

    ISBaseTimedAction.stop(self)
end

function BurdJournals.RecordToJournalAction:perform()
    -- Reset reading state and play close sound
    self.character:setReading(false)
    self.character:playSound("CloseBook")

    local player = self.character
    local panel = self.mainPanel

    if not panel then
        ISBaseTimedAction.perform(self)
        return
    end

    -- Collect records by type for server command
    local skillsToRecord = {}
    local traitsToRecord = {}
    local statsToRecord = {}
    local recipesToRecord = {}
    local skillCount = 0
    local traitCount = 0
    local statCount = 0
    local recipeCount = 0

    for _, record in ipairs(self.records) do
        if record.type == "skill" then
            skillsToRecord[record.name] = {
                xp = record.xp,
                level = record.level
            }
            skillCount = skillCount + 1
        elseif record.type == "trait" then
            traitsToRecord[record.name] = {
                name = record.name,
                isPositive = true
            }
            traitCount = traitCount + 1
        elseif record.type == "stat" then
            statsToRecord[record.name] = {
                value = record.value
            }
            statCount = statCount + 1
        elseif record.type == "recipe" then
            -- Get the magazine source for this recipe
            local magazineType = BurdJournals.getMagazineForRecipe and BurdJournals.getMagazineForRecipe(record.name) or nil
            recipesToRecord[record.name] = {
                name = record.name,
                source = magazineType
            }
            recipeCount = recipeCount + 1
        end
    end

    -- Store pending counts for feedback
    panel.pendingRecordFeedback = {
        skills = skillCount,
        traits = traitCount,
        stats = statCount,
        recipes = recipeCount
    }

    -- Consume pen durability if required
    local requirePen = BurdJournals.getSandboxOption("RequirePenToWrite")
    if requirePen ~= false then
        local penUses = BurdJournals.getSandboxOption("PenUsesPerLog") or 1
        local totalUses = penUses * (skillCount + traitCount + statCount + recipeCount)
        local pen = BurdJournals.findWritingTool(player)
        if pen and totalUses > 0 then
            BurdJournals.consumeItemUses(pen, totalUses, player)
        end
    end

    -- Send to server
    sendClientCommand(player, "BurdJournals", "recordProgress", {
        journalId = self.journal:getID(),
        skills = skillsToRecord,
        traits = traitsToRecord,
        stats = statsToRecord,
        recipes = recipesToRecord
    })

    -- Get queue - merge action's queue with any items added to panel during this action
    -- Items queued during action go to panel.recordingState.queue, items from previous actions are in self.queuedRecords
    local savedQueue = {}
    if not self.isRecordAll then
        -- First add items from action's queue (from previous action)
        for _, item in ipairs(self.queuedRecords or {}) do
            table.insert(savedQueue, item)
        end
        -- Then add any items added to panel during this action
        if panel.recordingState and panel.recordingState.queue then
            for _, item in ipairs(panel.recordingState.queue) do
                -- Avoid duplicates
                local isDupe = false
                for _, existing in ipairs(savedQueue) do
                    if existing.name == item.name then
                        isDupe = true
                        break
                    end
                end
                if not isDupe then
                    table.insert(savedQueue, item)
                end
            end
        end
    end

    -- Check if there are queued items to record next
    if #savedQueue > 0 then
        local nextRecord = table.remove(savedQueue, 1)

        -- Update state for UI (show next item being recorded)
        panel.recordingState = {
            active = true,
            skillName = nextRecord.type == "skill" and nextRecord.name or nil,
            traitId = nextRecord.type == "trait" and nextRecord.name or nil,
            statId = nextRecord.type == "stat" and nextRecord.name or nil,
            recipeName = nextRecord.type == "recipe" and nextRecord.name or nil,
            isRecordAll = false,
            progress = 0,
            totalTime = 0,
            startTime = 0,
            pendingRecords = {nextRecord},
            currentIndex = 1,
            queue = savedQueue,
        }

        -- Refresh list to show updated state
        if panel.skillList and panel.journal then
            pcall(function()
                panel:refreshCurrentList()
            end)
        end

        -- Queue the next timed action for the next record, passing remaining queue
        local nextRecords = {nextRecord}
        local action = BurdJournals.RecordToJournalAction:new(player, self.journal, nextRecords, false, panel, savedQueue)
        ISTimedActionQueue.add(action)

        ISBaseTimedAction.perform(self)
        return
    end

    -- No more queued items - fully complete
    panel.processingRecordQueue = false
    panel.recordingCompleted = true

    -- Reset recording state
    panel.recordingState = {
        active = false,
        skillName = nil,
        traitId = nil,
        statId = nil,
        recipeName = nil,
        isRecordAll = false,
        progress = 0,
        totalTime = 0,
        startTime = 0,
        pendingRecords = {},
        currentIndex = 0,
        queue = {},
    }

    ISBaseTimedAction.perform(self)
end


-- ==================== HELPER: Queue Learn Action ====================
-- Helper function to queue a learn action via ISTimedActionQueue
function BurdJournals.queueLearnAction(player, journal, rewards, isAbsorbAll, mainPanel)
    if not player or not journal then return false end
    if not rewards or #rewards == 0 then return false end

    local action = BurdJournals.LearnFromJournalAction:new(player, journal, rewards, isAbsorbAll, mainPanel)
    ISTimedActionQueue.add(action)
    return true
end


-- ==================== HELPER: Queue Record Action ====================
-- Helper function to queue a record action via ISTimedActionQueue
function BurdJournals.queueRecordAction(player, journal, records, isRecordAll, mainPanel)
    if not player or not journal then return false end
    if not records or #records == 0 then return false end

    local action = BurdJournals.RecordToJournalAction:new(player, journal, records, isRecordAll, mainPanel)
    ISTimedActionQueue.add(action)
    return true
end


