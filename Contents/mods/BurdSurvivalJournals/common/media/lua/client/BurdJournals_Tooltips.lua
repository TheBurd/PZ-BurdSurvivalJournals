--[[
    Burd's Survival Journals - Enhanced Tooltips
    Build 42 - Version 2.2

    Adds rich tooltip information for journal items showing:
    - Owner (username who owns the journal)
    - Author name (character name)
    - Skill/trait counts with XP totals
    - Journal condition (Clean/Worn/Bloody)
    - Origin info (Personal/Found/Recovered)
    - Age in days
]]

require "BurdJournals_Shared"
require "ISUI/ISToolTipInv"

BurdJournals = BurdJournals or {}
BurdJournals.Tooltips = BurdJournals.Tooltips or {}

-- ==================== HELPER FUNCTIONS ====================

-- Format age in days
local function formatAge(timestamp)
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

-- Check if player is the owner
local function isCurrentPlayerOwner(journalData)
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

-- ==================== BUILD TOOLTIP LINES ====================

function BurdJournals.Tooltips.getExtraInfo(item)
    if not item then return nil end

    local fullType = item:getFullType()
    if not fullType or not string.find(fullType, "BurdJournals") then
        return nil
    end

    local modData = item:getModData()
    local journalData = modData and modData.BurdJournals

    if not journalData then
        return nil
    end

    local lines = {}

    -- ==================== OWNERSHIP INFO ====================

    -- Owner (username) - shows who owns this journal
    if journalData.ownerUsername then
        local ownerText = journalData.ownerUsername
        if isCurrentPlayerOwner(journalData) then
            ownerText = ownerText .. " (You)"
            table.insert(lines, {text = "Owner: " .. ownerText, color = {r=0.4, g=0.8, b=1.0}})
        else
            table.insert(lines, {text = "Owner: " .. ownerText, color = {r=0.7, g=0.7, b=0.9}})
        end
    end

    -- Author (character name) - the character who wrote the journal
    if journalData.author then
        -- Only show author if different from owner display or if no owner
        local showAuthor = true
        if journalData.ownerUsername and journalData.author == journalData.ownerUsername then
            showAuthor = false  -- Don't duplicate if same
        end
        if showAuthor then
            table.insert(lines, {text = "Author: " .. journalData.author, color = {r=0.8, g=0.8, b=0.6}})
        end
    end

    -- Profession info (for found journals)
    if journalData.professionName then
        table.insert(lines, {text = "Profession: " .. journalData.professionName, color = {r=0.7, g=0.7, b=0.7}})
    end

    -- ==================== CONTENTS INFO ====================

    -- Count skills
    local skillCount = 0
    local unclaimedSkills = 0
    local totalXP = 0
    if journalData.skills then
        for skillName, skillData in pairs(journalData.skills) do
            skillCount = skillCount + 1
            if not journalData.claimedSkills or not journalData.claimedSkills[skillName] then
                unclaimedSkills = unclaimedSkills + 1
                totalXP = totalXP + (skillData.xp or 0)
            end
        end
    end

    -- Count traits
    local traitCount = 0
    local unclaimedTraits = 0
    if journalData.traits then
        for traitId, _ in pairs(journalData.traits) do
            traitCount = traitCount + 1
            if not journalData.claimedTraits or not journalData.claimedTraits[traitId] then
                unclaimedTraits = unclaimedTraits + 1
            end
        end
    end

    -- Skills line
    if skillCount > 0 then
        local skillText = "Skills: " .. unclaimedSkills .. "/" .. skillCount
        if unclaimedSkills > 0 and BurdJournals.formatXP then
            skillText = skillText .. " (" .. BurdJournals.formatXP(totalXP) .. " XP)"
            table.insert(lines, {text = skillText, color = {r=0.4, g=0.9, b=0.4}})
        elseif unclaimedSkills > 0 then
            table.insert(lines, {text = skillText, color = {r=0.4, g=0.9, b=0.4}})
        else
            table.insert(lines, {text = skillText .. " (all claimed)", color = {r=0.5, g=0.5, b=0.5}})
        end
    end

    -- Traits line
    if traitCount > 0 then
        local traitText = "Traits: " .. unclaimedTraits .. "/" .. traitCount
        if unclaimedTraits > 0 then
            table.insert(lines, {text = traitText, color = {r=0.9, g=0.7, b=0.3}})
        else
            table.insert(lines, {text = traitText .. " (all claimed)", color = {r=0.5, g=0.5, b=0.5}})
        end
    end

    -- ==================== CONDITION & ORIGIN ====================

    -- Journal condition (physical state)
    local conditionText = nil
    local conditionColor = nil

    if journalData.isBloody then
        conditionText = "Condition: Bloody"
        conditionColor = {r=0.8, g=0.2, b=0.2}
    elseif journalData.isWorn then
        conditionText = "Condition: Worn"
        conditionColor = {r=0.7, g=0.5, b=0.3}
    elseif journalData.wasRestored then
        conditionText = "Condition: Restored"
        conditionColor = {r=0.6, g=0.7, b=0.5}
    else
        conditionText = "Condition: Clean"
        conditionColor = {r=0.5, g=0.8, b=0.5}
    end

    if conditionText then
        table.insert(lines, {text = conditionText, color = conditionColor})
    end

    -- Origin info (where did this journal come from)
    local originText = nil
    local originColor = {r=0.6, g=0.6, b=0.6}

    if journalData.wasFromBloody or journalData.sourceType == "zombie" then
        originText = "Origin: Recovered from zombie"
        originColor = {r=0.6, g=0.4, b=0.3}
    elseif journalData.sourceType == "world" then
        originText = "Origin: Found in world"
        originColor = {r=0.5, g=0.5, b=0.6}
    elseif journalData.sourceType == "crafted" then
        originText = "Origin: Crafted"
        originColor = {r=0.5, g=0.6, b=0.5}
    elseif not journalData.ownerUsername and journalData.author then
        -- Legacy journal or found journal
        originText = "Origin: Found"
        originColor = {r=0.5, g=0.5, b=0.6}
    elseif isCurrentPlayerOwner(journalData) then
        originText = "Origin: Personal"
        originColor = {r=0.3, g=0.6, b=0.8}
    end

    if originText then
        table.insert(lines, {text = originText, color = originColor})
    end

    -- ==================== AGE INFO ====================

    -- Age (how long ago was this created)
    if journalData.timestamp then
        local ageText = formatAge(journalData.timestamp)
        if ageText then
            table.insert(lines, {text = "Created: " .. ageText, color = {r=0.6, g=0.6, b=0.6}})
        end
    elseif journalData.lastUpdated then
        local ageText = formatAge(journalData.lastUpdated)
        if ageText then
            table.insert(lines, {text = "Last Updated: " .. ageText, color = {r=0.6, g=0.6, b=0.6}})
        end
    end

    return lines
end

-- ==================== TOOLTIP HOOK ====================
-- Hook into ISToolTipInv to add extra lines for journal items
-- Note: ISToolTipInv uses self:drawRect/self:drawText, not self.tooltip

local originalRender = ISToolTipInv.render

ISToolTipInv.render = function(self)
    -- Call original render first
    originalRender(self)

    -- Check if we have a journal item
    if not self.item then return end

    local fullType = self.item:getFullType()
    if not fullType or not string.find(fullType, "BurdJournals") then
        return
    end

    -- Get extra tooltip info
    local extraLines = BurdJournals.Tooltips.getExtraInfo(self.item)
    if not extraLines or #extraLines == 0 then
        return
    end

    -- Get font and line height
    local font = UIFont.Small
    local lineHeight = getTextManager():getFontHeight(font) + 2

    -- Calculate starting Y position (after the existing tooltip content)
    local startY = self:getHeight() + 5

    -- Draw a separator line
    self:drawRect(10, startY - 3, self:getWidth() - 20, 1, 0.3, 0.6, 0.6, 0.6)

    -- Draw each extra line
    for i, lineData in ipairs(extraLines) do
        local y = startY + (i - 1) * lineHeight
        self:drawText(lineData.text, 12, y, lineData.color.r, lineData.color.g, lineData.color.b, 1.0, font)
    end

    -- Expand tooltip height to fit new content
    local extraHeight = (#extraLines * lineHeight) + 10
    self:setHeight(self:getHeight() + extraHeight)
end

print("[BurdJournals] Tooltip hook installed")
