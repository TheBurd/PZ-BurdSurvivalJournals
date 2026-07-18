
require "BurdJournals_Shared"

BurdJournals = BurdJournals or {}
BurdJournals.UI = BurdJournals.UI or {}

BurdJournals.UI.Colors = {

    panelBg = {r=0.08, g=0.08, b=0.1, a=0.95},
    panelBorder = {r=0.4, g=0.35, b=0.3, a=1},

    titleText = {r=1, g=0.9, b=0.7, a=1},
    normalText = {r=0.9, g=0.9, b=0.9, a=1},
    dimText = {r=0.6, g=0.6, b=0.6, a=1},
    successText = {r=0.5, g=0.9, b=0.5, a=1},
    warningText = {r=0.9, g=0.7, b=0.3, a=1},
    errorText = {r=0.9, g=0.4, b=0.4, a=1},

    btnDefault = {r=0.4, g=0.4, b=0.4, a=1},
    btnSuccess = {r=0.3, g=0.5, b=0.3, a=1},
    btnDanger = {r=0.6, g=0.3, b=0.3, a=1},
    btnInfo = {r=0.3, g=0.4, b=0.6, a=1},
    btnWarning = {r=0.5, g=0.5, b=0.3, a=1},

    listBg = {r=0.12, g=0.12, b=0.15, a=1},
    listAltBg = {r=0.15, g=0.15, b=0.18, a=1},
    listSelected = {r=0.2, g=0.3, b=0.2, a=1},
    listHover = {r=0.18, g=0.18, b=0.22, a=1},

    checkboxBorder = {r=0.6, g=0.6, b=0.6, a=1},
    checkboxFill = {r=0.4, g=0.8, b=0.4, a=1},
}

function BurdJournals.UI.drawRoundedRect(target, x, y, w, h, radius, a, r, g, b)

    target:drawRect(x, y, w, h, a, r, g, b)
end

function BurdJournals.UI.drawProgressBar(target, x, y, w, h, progress, bgColor, fillColor)

    target:drawRect(x, y, w, h, bgColor.a or 0.8, bgColor.r, bgColor.g, bgColor.b)

    local fillWidth = math.max(0, math.min(1, progress)) * w
    if fillWidth > 0 then
        target:drawRect(x, y, fillWidth, h, fillColor.a or 1, fillColor.r, fillColor.g, fillColor.b)
    end

    target:drawRectBorder(x, y, w, h, 1, 0.5, 0.5, 0.5)
end

function BurdJournals.UI.truncateText(text, maxWidth, font)
    if not text then return "" end

    local textWidth = getTextManager():MeasureStringX(font or UIFont.Small, text)
    if textWidth <= maxWidth then
        return text
    end

    local ellipsis = "..."
    local ellipsisWidth = getTextManager():MeasureStringX(font or UIFont.Small, ellipsis)
    local targetWidth = maxWidth - ellipsisWidth

    local truncated = text
    while getTextManager():MeasureStringX(font or UIFont.Small, truncated) > targetWidth and #truncated > 0 do
        truncated = string.sub(truncated, 1, -2)
    end

    return truncated .. ellipsis
end

function BurdJournals.UI.getFontHeight(font, fallback)
    local manager = getTextManager and getTextManager() or nil
    if manager and manager.getFontHeight then
        local ok, height = pcall(manager.getFontHeight, manager, font or UIFont.Small)
        if ok and tonumber(height) and tonumber(height) > 0 then
            return math.ceil(tonumber(height))
        end
    end
    if manager and manager.MeasureStringY then
        local ok, height = pcall(manager.MeasureStringY, manager, font or UIFont.Small, "Ag")
        if ok and tonumber(height) and tonumber(height) > 0 then
            return math.ceil(tonumber(height))
        end
    end
    return fallback or 14
end

function BurdJournals.UI.measureText(font, text)
    local manager = getTextManager and getTextManager() or nil
    if manager and manager.MeasureStringX then
        return manager:MeasureStringX(font or UIFont.Small, tostring(text or ""))
    end
    return string.len(tostring(text or "")) * 7
end

function BurdJournals.UI.getLayoutMetrics()
    local smallFont = UIFont.Small
    local mediumFont = UIFont.Medium
    local smallH = BurdJournals.UI.getFontHeight(smallFont, 14)
    local mediumH = BurdJournals.UI.getFontHeight(mediumFont, math.max(18, smallH + 4))
    local lineGap = math.max(2, math.floor(smallH * 0.18))
    local buttonPadY = math.max(6, math.floor(smallH * 0.38))
    local buttonHeight = math.max(24, smallH + buttonPadY)
    local rowPaddingY = math.max(6, math.floor(smallH * 0.45))
    local rowButtonWidth = math.max(70, BurdJournals.UI.measureText(smallFont, getText and getText("UI_BurdJournals_BtnRecord") or "Record") + 16)
    rowButtonWidth = math.max(rowButtonWidth, BurdJournals.UI.measureText(smallFont, getText and getText("UI_BurdJournals_Absorb") or "Absorb") + 16)
    local actionColumnWidth = rowButtonWidth + 22
    local rowHeight = math.max(58, (rowPaddingY * 2) + (smallH * 2) + lineGap + 4, buttonHeight + 14)

    return {
        smallFont = smallFont,
        bodyFont = smallFont,
        buttonFont = smallFont,
        headerFont = mediumFont,
        smallHeight = smallH,
        bodyHeight = smallH,
        headerHeight = mediumH,
        lineGap = lineGap,
        rowPaddingY = rowPaddingY,
        rowTitleY = rowPaddingY,
        rowStatusY = rowPaddingY + smallH + lineGap,
        rowHeight = rowHeight,
        cardMargin = 4,
        iconSize = math.max(24, smallH + 8),
        buttonHeight = buttonHeight,
        rowButtonWidth = rowButtonWidth,
        actionColumnWidth = actionColumnWidth,
        actionColumnGap = 12,
        buttonGap = 4,
        searchHeight = math.max(24, smallH + 10),
        clearButtonSize = math.max(16, smallH + 4),
        tabHeight = math.max(28, smallH + 12),
        filterHeight = math.max(22, smallH + 8),
        paginationHeight = math.max(26, buttonHeight + 2),
        footerHeight = math.max(85, buttonHeight + smallH + 42),
        textEntryHeight = math.max(20, smallH + 8),
    }
end

function BurdJournals.UI.centerTextY(y, height, font)
    local fontHeight = BurdJournals.UI.getFontHeight(font or UIFont.Small, 14)
    return y + math.floor((height - fontHeight) / 2)
end

BurdJournals.UI.SkillIcons = {

    Passive = "media/ui/Moodles/Moodle_Icon_Endurance.png",
    Combat = "media/ui/Moodles/Moodle_Icon_Combat.png",
    Crafting = "media/ui/Moodles/Moodle_Icon_Unhappy.png",
    Survival = "media/ui/Moodles/Moodle_Icon_Hungry.png",
    Agility = "media/ui/Moodles/Moodle_Icon_Panic.png",
}

function BurdJournals.UI.getSkillCategory(skillName)
    for category, skills in pairs(BurdJournals.SKILL_CATEGORIES) do
        for _, skill in ipairs(skills) do
            if skill == skillName then
                return category
            end
        end
    end
    local fallback = "Other"
    local localized = getText and getText("UI_BurdJournals_OtherCategory")
    if localized and localized ~= "UI_BurdJournals_OtherCategory" then
        return localized
    end
    return fallback
end

function BurdJournals.UI.showNotification(player, message, color)
    if player and player.Say then
        player:Say(message)
    end
end

function BurdJournals.UI.showSuccess(player, message)
    BurdJournals.UI.showNotification(player, message, BurdJournals.UI.Colors.successText)
end

function BurdJournals.UI.showError(player, message)
    BurdJournals.UI.showNotification(player, message, BurdJournals.UI.Colors.errorText)
end

function BurdJournals.UI.showWarning(player, message)
    BurdJournals.UI.showNotification(player, message, BurdJournals.UI.Colors.warningText)
end
