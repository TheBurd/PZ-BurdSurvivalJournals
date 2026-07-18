-- Build 41 admin item list compatibility:
-- vanilla `ISItemsListTable` only tries `getTexture("Item_" .. iconName)`, which can miss
-- mod item textures even though the normal inventory icon resolves correctly.

local function resolveAdminListTexture(scriptItem)
    if not scriptItem then
        return nil
    end

    if scriptItem.getNormalTexture then
        local normalTexture = scriptItem:getNormalTexture()
        if normalTexture then
            return normalTexture
        end
    end

    local iconName = nil
    local icons = scriptItem.getIconsForTexture and scriptItem:getIconsForTexture() or nil
    if icons and icons.isEmpty and not icons:isEmpty() and icons.get then
        iconName = icons:get(0)
    end
    if (not iconName or tostring(iconName) == "") and scriptItem.getIcon then
        iconName = scriptItem:getIcon()
    end
    if not iconName or tostring(iconName) == "" then
        return nil
    end

    local iconId = tostring(iconName)
    local candidates = {
        "Item_" .. iconId,
        iconId,
        "media/textures/Item_" .. iconId .. ".png",
        "media/textures/" .. iconId .. ".png",
    }

    for i = 1, #candidates do
        local texture = getTexture(candidates[i])
        if texture then
            return texture
        end
    end

    return nil
end

local function patchAdminItemList()
    require "ISUI/AdminPanel/ISItemsListTable"
    if not ISItemsListTable or ISItemsListTable._bsjIconCompatPatched then
        return
    end

    local function getScriptText(scriptItem, primaryMethod, fallbackMethod, fallbackValue)
        if not scriptItem then
            return fallbackValue or ""
        end

        local value = nil
        if primaryMethod and scriptItem[primaryMethod] then
            value = scriptItem[primaryMethod](scriptItem)
        end
        if (value == nil or tostring(value) == "") and fallbackMethod and scriptItem[fallbackMethod] then
            value = scriptItem[fallbackMethod](scriptItem)
        end
        if value == nil or tostring(value) == "" then
            value = fallbackValue or ""
        end
        return tostring(value)
    end

    function ISItemsListTable:drawDatas(y, item, alt)
        if y + self:getYScroll() + self.itemheight < 0 or y + self:getYScroll() >= self.height then
            return y + self.itemheight
        end

        local a = 0.9

        if self.selected == item.index then
            self:drawRect(0, y, self:getWidth(), self.itemheight, 0.3, 0.7, 0.35, 0.15)
        end

        if alt then
            self:drawRect(0, y, self:getWidth(), self.itemheight, 0.3, 0.6, 0.5, 0.5)
        end

        self:drawRectBorder(0, y, self:getWidth(), self.itemheight, a, self.borderColor.r, self.borderColor.g, self.borderColor.b)

        local fontHeight = getTextManager():getFontHeight(UIFont.Small)
        local iconX = 4
        local iconSize = fontHeight
        local xoffset = 10

        local clipX = self.columns[1].size
        local clipX2 = self.columns[2].size
        local clipY = math.max(0, y + self:getYScroll())
        local clipY2 = math.min(self.height, y + self:getYScroll() + self.itemheight)
        local scriptItem = item and item.item or nil
        local itemName = getScriptText(scriptItem, "getName", nil, "Unknown Item")
        local displayName = getScriptText(scriptItem, "getDisplayName", "getName", itemName)
        local typeString = getScriptText(scriptItem, "getTypeString", "getFullName", "Unknown Type")

        self:setStencilRect(clipX, clipY, clipX2 - clipX, clipY2 - clipY)
        self:drawText(itemName, xoffset, y + 4, 1, 1, 1, a, self.font)
        self:clearStencilRect()

        clipX = self.columns[2].size
        clipX2 = self.columns[3].size
        self:setStencilRect(clipX, clipY, clipX2 - clipX, clipY2 - clipY)
        self:drawText(displayName, self.columns[2].size + iconX + iconSize + 4, y + 4, 1, 1, 1, a, self.font)
        self:clearStencilRect()

        clipX = self.columns[3].size
        clipX2 = self.columns[4].size
        self:setStencilRect(clipX, clipY, clipX2 - clipX, clipY2 - clipY)
        self:drawText(typeString, self.columns[3].size + xoffset, y + 4, 1, 1, 1, a, self.font)
        self:clearStencilRect()

        local displayCategory = scriptItem and scriptItem.getDisplayCategory and scriptItem:getDisplayCategory() or nil
        if displayCategory ~= nil and tostring(displayCategory) ~= "" then
            self:drawText(getText("IGUI_ItemCat_" .. tostring(displayCategory)), self.columns[4].size + xoffset, y + 4, 1, 1, 1, a, self.font)
        else
            self:drawText("Error: No category set", self.columns[4].size + xoffset, y + 4, 1, 1, 1, a, self.font)
        end

        self:repaintStencilRect(0, clipY, self.width, clipY2 - clipY)

        local texture = resolveAdminListTexture(scriptItem)
        if texture then
            self:drawTextureScaledAspect2(texture, self.columns[2].size + iconX, y + (self.itemheight - iconSize) / 2, iconSize, iconSize, 1, 1, 1, 1)
        end

        return y + self.itemheight
    end

    ISItemsListTable._bsjIconCompatPatched = true
end

patchAdminItemList()
if Events and Events.OnGameStart then
    Events.OnGameStart.Add(patchAdminItemList)
end
