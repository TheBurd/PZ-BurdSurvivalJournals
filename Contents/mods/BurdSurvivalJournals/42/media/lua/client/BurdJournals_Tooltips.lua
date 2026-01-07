--[[
    Burd's Survival Journals - Tooltips Module
    Build 42 - Version 2.5

    This module provides tooltip helper functions for journal items.
    Enhanced hover tooltips are available in the dev version.
]]

require "BurdJournals_Shared"

BurdJournals = BurdJournals or {}
BurdJournals.Tooltips = BurdJournals.Tooltips or {}

-- ==================== HELPER FUNCTIONS ====================

-- Format age in days (used by context menu and main panel)
function BurdJournals.Tooltips.formatAge(timestamp)
    if not timestamp then return nil end

    local currentTime = getGameTime():getWorldAgeHours()
    local ageHours = currentTime - timestamp

    if ageHours < 0 then ageHours = 0 end

    local ageDays = math.floor(ageHours / 24)

    if ageDays == 0 then
        return "Today"
    elseif ageDays == 1 then
        return "1 day ago"
    else
        return ageDays .. " days ago"
    end
end

-- Check if player is the owner (used by context menu)
function BurdJournals.Tooltips.isCurrentPlayerOwner(journalData)
    local player = getPlayer()
    if not player then return false end

    local playerUsername = player:getUsername()
    if not playerUsername then return false end

    -- Check ownerUsername field first (new format)
    if journalData.ownerUsername then
        return journalData.ownerUsername == playerUsername
    end

    -- Fallback: Check author against username or character name
    if journalData.author then
        if journalData.author == playerUsername then
            return true
        end
        local playerFullName = player:getDescriptor():getForename() .. " " .. player:getDescriptor():getSurname()
        if journalData.author == playerFullName then
            return true
        end
    end

    return false
end

-- Get journal condition string
function BurdJournals.Tooltips.getCondition(journalData)
    if journalData.isBloody then
        return "Bloody", {r=0.8, g=0.2, b=0.2}
    elseif journalData.isWorn then
        return "Worn", {r=0.7, g=0.5, b=0.3}
    elseif journalData.wasRestored then
        return "Restored", {r=0.6, g=0.7, b=0.5}
    else
        return "Clean", {r=0.5, g=0.8, b=0.5}
    end
end

-- Get journal origin string
function BurdJournals.Tooltips.getOrigin(journalData)
    if journalData.wasFromBloody or journalData.sourceType == "zombie" then
        return "Recovered from zombie", {r=0.6, g=0.4, b=0.3}
    elseif journalData.sourceType == "world" then
        return "Found in world", {r=0.5, g=0.5, b=0.6}
    elseif journalData.sourceType == "crafted" then
        return "Crafted", {r=0.5, g=0.6, b=0.5}
    elseif not journalData.ownerUsername and journalData.author then
        return "Found", {r=0.5, g=0.5, b=0.6}
    elseif BurdJournals.Tooltips.isCurrentPlayerOwner(journalData) then
        return "Personal", {r=0.3, g=0.6, b=0.8}
    end
    return nil, nil
end

print("[BurdJournals] Tooltips module loaded (production)")
