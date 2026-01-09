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
            player:Say("Journal restored!")
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
        
        player:Say("Journal erased...")
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
    if HaloTextHelper and HaloTextHelper.addTextWithArrow then
        HaloTextHelper.addTextWithArrow(player, "Journal bound!", true, HaloTextHelper.getColorGreen())
    else
        player:Say("Journal bound!")
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
        local msg = "Salvaged: " .. table.concat(itemsGiven, ", ")
        if HaloTextHelper and HaloTextHelper.addTextWithArrow then
            HaloTextHelper.addTextWithArrow(player, msg, true, HaloTextHelper.getColorGreen())
        else
            player:Say(msg)
        end
    else
        player:Say("Journal disassembled.")
    end

    ISBaseTimedAction.perform(self)
end


