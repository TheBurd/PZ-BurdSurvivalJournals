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
        return getText("Tooltip_BurdJournals_AgeToday") or "Today"
    elseif ageDays == 1 then
        return getText("Tooltip_BurdJournals_Age1Day") or "1 day ago"
    else
        return string.format(getText("Tooltip_BurdJournals_AgeDays") or "%d days ago", ageDays)
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
            ownerText = ownerText .. " " .. (getText("Tooltip_BurdJournals_OwnerYou") or "(You)")
            local ownerLine = string.format(getText("Tooltip_BurdJournals_Owner") or "Owner: %s", ownerText)
            table.insert(lines, {text = ownerLine, color = {r=0.4, g=0.8, b=1.0}})
        else
            local ownerLine = string.format(getText("Tooltip_BurdJournals_Owner") or "Owner: %s", ownerText)
            table.insert(lines, {text = ownerLine, color = {r=0.7, g=0.7, b=0.9}})
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
            local authorLine = string.format(getText("Tooltip_BurdJournals_Author") or "Author: %s", journalData.author)
            table.insert(lines, {text = authorLine, color = {r=0.8, g=0.8, b=0.6}})
        end
    end

    -- Profession info (for found journals)
    if journalData.professionName then
        local profLine = string.format(getText("Tooltip_BurdJournals_Profession") or "Profession: %s", journalData.professionName)
        table.insert(lines, {text = profLine, color = {r=0.7, g=0.7, b=0.7}})
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
        local skillText
        if unclaimedSkills > 0 and BurdJournals.formatXP then
            skillText = string.format(getText("Tooltip_BurdJournals_SkillsLineXP") or "Skills: %d/%d (%s XP)", unclaimedSkills, skillCount, BurdJournals.formatXP(totalXP))
            table.insert(lines, {text = skillText, color = {r=0.4, g=0.9, b=0.4}})
        elseif unclaimedSkills > 0 then
            skillText = string.format(getText("Tooltip_BurdJournals_SkillsLine") or "Skills: %d/%d", unclaimedSkills, skillCount)
            table.insert(lines, {text = skillText, color = {r=0.4, g=0.9, b=0.4}})
        else
            skillText = string.format(getText("Tooltip_BurdJournals_SkillsLine") or "Skills: %d/%d", unclaimedSkills, skillCount)
            skillText = skillText .. " " .. (getText("Tooltip_BurdJournals_AllClaimed") or "(all claimed)")
            table.insert(lines, {text = skillText, color = {r=0.5, g=0.5, b=0.5}})
        end
    end

    -- Traits line
    if traitCount > 0 then
        local traitText = string.format(getText("Tooltip_BurdJournals_TraitsLine") or "Traits: %d/%d", unclaimedTraits, traitCount)
        if unclaimedTraits > 0 then
            table.insert(lines, {text = traitText, color = {r=0.9, g=0.7, b=0.3}})
        else
            traitText = traitText .. " " .. (getText("Tooltip_BurdJournals_AllClaimed") or "(all claimed)")
            table.insert(lines, {text = traitText, color = {r=0.5, g=0.5, b=0.5}})
        end
    end

    -- ==================== CONDITION & ORIGIN ====================

    -- Journal condition (physical state)
    local conditionText = nil
    local conditionColor = nil

    if journalData.isBloody then
        conditionText = getText("Tooltip_BurdJournals_ConditionBloody") or "Condition: Bloody"
        conditionColor = {r=0.8, g=0.2, b=0.2}
    elseif journalData.isWorn then
        conditionText = getText("Tooltip_BurdJournals_ConditionWorn") or "Condition: Worn"
        conditionColor = {r=0.7, g=0.5, b=0.3}
    elseif journalData.wasRestored then
        conditionText = getText("Tooltip_BurdJournals_ConditionRestored") or "Condition: Restored"
        conditionColor = {r=0.6, g=0.7, b=0.5}
    else
        conditionText = getText("Tooltip_BurdJournals_ConditionClean") or "Condition: Clean"
        conditionColor = {r=0.5, g=0.8, b=0.5}
    end

    if conditionText then
        table.insert(lines, {text = conditionText, color = conditionColor})
    end

    -- Origin info (where did this journal come from)
    local originText = nil
    local originColor = {r=0.6, g=0.6, b=0.6}

    if journalData.wasFromBloody or journalData.sourceType == "zombie" then
        originText = getText("Tooltip_BurdJournals_OriginZombie") or "Origin: Recovered from zombie"
        originColor = {r=0.6, g=0.4, b=0.3}
    elseif journalData.sourceType == "world" then
        originText = getText("Tooltip_BurdJournals_OriginWorld") or "Origin: Found in world"
        originColor = {r=0.5, g=0.5, b=0.6}
    elseif journalData.sourceType == "crafted" then
        originText = getText("Tooltip_BurdJournals_OriginCrafted") or "Origin: Crafted"
        originColor = {r=0.5, g=0.6, b=0.5}
    elseif not journalData.ownerUsername and journalData.author then
        -- Legacy journal or found journal
        originText = getText("Tooltip_BurdJournals_OriginFound") or "Origin: Found"
        originColor = {r=0.5, g=0.5, b=0.6}
    elseif isCurrentPlayerOwner(journalData) then
        originText = getText("Tooltip_BurdJournals_OriginPersonal") or "Origin: Personal"
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
            local createdLine = string.format(getText("Tooltip_BurdJournals_Created") or "Created: %s", ageText)
            table.insert(lines, {text = createdLine, color = {r=0.6, g=0.6, b=0.6}})
        end
    elseif journalData.lastUpdated then
        local ageText = formatAge(journalData.lastUpdated)
        if ageText then
            local updatedLine = string.format(getText("Tooltip_BurdJournals_LastUpdated") or "Last Updated: %s", ageText)
            table.insert(lines, {text = updatedLine, color = {r=0.6, g=0.6, b=0.6}})
        end
    end

    return lines
end

-- ==================== TOOLTIP HOOK ====================
-- Hook into ISToolTipInv to add extra lines for journal items
-- ISToolTipInv.render() sets self.height from ObjectTooltip dimensions THEN draws background.
-- We need to draw our own background extension after the original render completes.

local originalRender = ISToolTipInv.render

ISToolTipInv.render = function(self)
    -- Call original render first (this draws the base tooltip)
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

    -- Calculate extra height needed
    local extraHeight = (#extraLines * lineHeight) + 12

    -- The original tooltip height (what was just rendered)
    local originalHeight = self:getHeight()

    -- Draw background extension for our extra content
    -- Use same colors as the original tooltip background
    local bgColor = self.backgroundColor
    local borderColor = self.borderColor

    -- Draw background extension (starting where original ended)
    self:drawRect(0, originalHeight, self:getWidth(), extraHeight, bgColor.a, bgColor.r, bgColor.g, bgColor.b)

    -- Draw border on the sides and bottom of our extension
    -- Left border
    self:drawRect(0, originalHeight, 1, extraHeight, borderColor.a, borderColor.r, borderColor.g, borderColor.b)
    -- Right border
    self:drawRect(self:getWidth() - 1, originalHeight, 1, extraHeight, borderColor.a, borderColor.r, borderColor.g, borderColor.b)
    -- Bottom border
    self:drawRect(0, originalHeight + extraHeight - 1, self:getWidth(), 1, borderColor.a, borderColor.r, borderColor.g, borderColor.b)

    -- Remove the original bottom border (draw over it with background color)
    self:drawRect(1, originalHeight - 1, self:getWidth() - 2, 1, bgColor.a, bgColor.r, bgColor.g, bgColor.b)

    -- Draw separator line
    local startY = originalHeight + 5
    self:drawRect(10, startY - 3, self:getWidth() - 20, 1, 0.5, 0.6, 0.6, 0.6)

    -- Draw each extra line
    for i, lineData in ipairs(extraLines) do
        local y = startY + (i - 1) * lineHeight
        self:drawText(lineData.text, 12, y, lineData.color.r, lineData.color.g, lineData.color.b, 1.0, font)
    end

    -- Update the panel height so mouse detection works correctly
    self:setHeight(originalHeight + extraHeight)
end

print("[BurdJournals] Tooltip hook installed")
