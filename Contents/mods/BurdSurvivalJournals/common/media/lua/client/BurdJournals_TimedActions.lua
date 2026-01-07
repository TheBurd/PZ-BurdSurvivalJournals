--[[
    Burd's Survival Journals - Timed Actions
    Build 41 - Version 2.0

    Timed actions for journal operations:
    - ConvertToCleanAction: Convert worn journal to clean blank (tailoring)

    Note: Bloody journal cleaning is now done via the crafting menu only
    (CleanBloodyFilledToClean recipe) to prevent BloodyÃ¢â€ â€™Worn exploit.
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



