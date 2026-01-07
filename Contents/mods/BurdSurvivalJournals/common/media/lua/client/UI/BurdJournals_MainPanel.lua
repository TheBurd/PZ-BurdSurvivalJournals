--[[
    Burd's Survival Journals - Main Panel UI
    Build 42 - Version 2.0

    Features:
    - Visual hierarchy with themed styling
    - XP bars and progress indicators
    - Timed learning with queue system
    - Support for Worn, Bloody, and Player journals
]]

require "BurdJournals_Shared"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISScrollingListBox"

BurdJournals = BurdJournals or {}
BurdJournals.UI = BurdJournals.UI or {}

-- ==================== SOUND PRESETS (defined early for use in UI) ====================
-- Using UI sounds for immediate feedback, world sounds for character actions
-- NOTE: Some world sounds (Sewing, RummageInInventory) are looping sounds and should NOT
-- be used as one-shot sounds from UI - they will loop forever. Only use UI sounds for those.
BurdJournals.Sounds = {
    -- UI sounds (instant feedback)
    PAGE_TURN = {ui = "UISelectListItem", world = "PageFlipBook"},
    LEARN_COMPLETE = {ui = "UIActivateButton", world = "CloseBook"},
    OPEN_JOURNAL = {ui = "UIActivateTab", world = "OpenBook"},
    QUEUE_ADD = {ui = "UISelectListItem", world = "PageFlipMagazine"},
    -- World-only sounds
    DISSOLVE = {world = "BreakWoodItem"},
    ERASE = {world = "RummageInInventory"},
    -- RECORD: "Sewing" is a LOOPING sound - only use UI sound to avoid infinite loop
    RECORD = {ui = "UIActivateButton"},
}

-- ==================== HELPER FUNCTIONS ====================

-- Cache for trait definitions (label, icon, etc.)
local traitDefCache = {}

-- Get trait definition from CharacterTraitDefinition by traitId
local function getTraitDefinition(traitId)
    if not traitId then return nil end
    
    -- Check cache first
    if traitDefCache[traitId] then
        return traitDefCache[traitId]
    end
    
    local traitIdLower = string.lower(traitId)
    local traitIdNorm = traitIdLower:gsub("%s", "")
    
    -- Search CharacterTraitDefinition
    if CharacterTraitDefinition and CharacterTraitDefinition.getTraits then
        local allTraits = CharacterTraitDefinition.getTraits()
        for i = 0, allTraits:size() - 1 do
            local def = allTraits:get(i)
            local defLabel = def:getLabel() or ""
            local defType = def:getType()
            local defName = ""
            
            if defType then
                pcall(function()
                    defName = defType:getName() or tostring(defType)
                end)
            end
            
            local defLabelLower = string.lower(defLabel)
            local defNameLower = string.lower(defName)
            local defLabelNorm = defLabelLower:gsub("%s", "")
            local defNameNorm = defNameLower:gsub("%s", "")
            
            -- Match by: exact, case-insensitive, normalized (no spaces), or partial
            local exactMatch = (defLabel == traitId) or (defName == traitId)
            local lowerMatch = (defLabelLower == traitIdLower) or (defNameLower == traitIdLower)
            local normalizedMatch = (defLabelNorm == traitIdNorm) or (defNameNorm == traitIdNorm)
            local partialMatch = defLabelLower:find(traitIdLower, 1, true) or traitIdLower:find(defLabelLower, 1, true)
            
            if exactMatch or lowerMatch or normalizedMatch or partialMatch then
                local cached = {
                    def = def,
                    label = defLabel,
                    name = defName,
                    type = defType
                }
                -- Try to get icon texture
                pcall(function()
                    if def.getTexture then
                        cached.texture = def:getTexture()
                    end
                end)
                traitDefCache[traitId] = cached
                return cached
            end
        end
    end
    
    return nil
end

-- Safely get trait display name
local function safeGetTraitName(traitId)
    if not traitId then return "Unknown Trait" end

    -- Try CharacterTraitDefinition first (B42)
    local traitDef = getTraitDefinition(traitId)
    if traitDef and traitDef.label then
        return traitDef.label
    end

    -- Fallback: Try TraitFactory
    if TraitFactory and TraitFactory.getTrait then
        local traitObj = TraitFactory.getTrait(traitId)
        if traitObj and traitObj.getLabel then
            return traitObj:getLabel()
        end
    end

    -- Final fallback: make traitId more readable (insert spaces before capitals)
    return traitId:gsub("(%l)(%u)", "%1 %2")
end

-- Get trait icon texture
local function getTraitTexture(traitId)
    if not traitId then return nil end
    
    local traitDef = getTraitDefinition(traitId)
    if traitDef and traitDef.texture then
        return traitDef.texture
    end
    
    return nil
end

-- ==================== MAIN PANEL CLASS ====================

BurdJournals.UI.MainPanel = ISPanel:derive("BurdJournals.UI.MainPanel")
BurdJournals.UI.MainPanel.instance = nil

function BurdJournals.UI.MainPanel:new(x, y, width, height, player, journal, mode)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.player = player
    o.playerNum = player and player:getPlayerNum() or 0  -- Store player number for refreshing
    o.journal = journal
    o.mode = mode or "view"
    o.backgroundColor = {r=0.1, g=0.1, b=0.1, a=0.95}
    o.borderColor = {r=0.3, g=0.3, b=0.3, a=1}
    o.moveWithMouse = true
    
    -- Learning state for timed absorption
    o.learningState = {
        active = false,
        skillName = nil,       -- Current skill being learned (nil for absorb all)
        traitId = nil,         -- Current trait being learned (nil for skills/absorb all)
        isAbsorbAll = false,   -- True if learning all at once
        progress = 0,          -- 0.0 to 1.0
        totalTime = 0,         -- Total seconds needed
        startTime = 0,         -- When learning started (getTimestampMs)
        pendingRewards = {},   -- List of {type="skill"|"trait", name=..., xp=...}
        currentIndex = 0,      -- Current reward being processed in absorb all
        queue = {},            -- Queue of rewards to learn after current one
    }
    o.learningCompleted = false  -- Flag to skip close confirmation after successful learning
    o.processingQueue = false    -- Flag to skip close confirmation during queue processing
    o.confirmDialog = nil        -- Reference to close confirmation dialog
    
    return o
end

function BurdJournals.UI.MainPanel:initialise()
    ISPanel.initialise(self)
end

function BurdJournals.UI.MainPanel:createChildren()
    ISPanel.createChildren(self)

    -- Play open journal sound
    self:playSound(BurdJournals.Sounds.OPEN_JOURNAL)

    -- Create UI based on mode
    if self.mode == "absorb" then
        self:createAbsorptionUI()
    elseif self.mode == "log" then
        self:createLogUI()
    else
        self:createViewUI()
    end
end

-- Refresh player reference (helps avoid stale references)
function BurdJournals.UI.MainPanel:refreshPlayer()
    -- Always get a fresh player reference using stored player number
    local freshPlayer = getSpecificPlayer(self.playerNum)
    if freshPlayer then
        self.player = freshPlayer
    end
end

-- ==================== ABSORPTION UI (Worn/Bloody Journals) ====================
-- Redesigned with better visual hierarchy, XP bars, and themed styling

function BurdJournals.UI.MainPanel:createAbsorptionUI()
    -- Refresh player reference to ensure it's valid at UI creation
    self:refreshPlayer()

    local padding = 16
    local y = 0
    local btnHeight = 32

    -- Determine journal type for styling
    local isBloody = BurdJournals.isBloody(self.journal)
    local hasBloodyOrigin = BurdJournals.hasBloodyOrigin(self.journal)
    local journalData = BurdJournals.getJournalData(self.journal)

    -- Store for rendering
    self.isBloody = isBloody
    self.hasBloodyOrigin = hasBloodyOrigin

    -- ============ HEADER STYLING ============
    local headerHeight = 52
    if isBloody then
        self.headerColor = {r=0.45, g=0.08, b=0.08}
        self.headerAccent = {r=0.7, g=0.15, b=0.15}
        self.typeText = "BLOODY JOURNAL"
        self.rarityText = "RARE"
        self.flavorText = "Found on a fallen survivor..."
    elseif hasBloodyOrigin then
        self.headerColor = {r=0.30, g=0.22, b=0.12}
        self.headerAccent = {r=0.5, g=0.35, b=0.2}
        self.typeText = "WORN JOURNAL"
        self.rarityText = "UNCOMMON"
        self.flavorText = "Recovered from the wasteland..."
    else
        self.headerColor = {r=0.22, g=0.20, b=0.15}
        self.headerAccent = {r=0.4, g=0.35, b=0.25}
        self.typeText = "WORN JOURNAL"
        self.rarityText = nil
        self.flavorText = "An old survivor's notes..."
    end
    self.headerHeight = headerHeight
    y = headerHeight + 6

    -- ============ AUTHOR INFO BOX ============
    local authorName = journalData and journalData.author or "Unknown Survivor"
    self.authorName = authorName
    self.authorBoxY = y
    self.authorBoxHeight = 44
    y = y + self.authorBoxHeight + 10

    -- ============ COUNT SKILLS AND TRAITS ============
    local skillCount = 0
    local totalSkillCount = 0
    local traitCount = 0
    local totalTraitCount = 0
    local totalXP = 0

    if journalData and journalData.skills then
        for skillName, skillData in pairs(journalData.skills) do
            totalSkillCount = totalSkillCount + 1
            if not BurdJournals.isSkillClaimed(self.journal, skillName) then
                skillCount = skillCount + 1
                totalXP = totalXP + (skillData.xp or 0)
            end
        end
    end
    if hasBloodyOrigin and journalData and journalData.traits then
        for traitId, _ in pairs(journalData.traits) do
            totalTraitCount = totalTraitCount + 1
            if not BurdJournals.isTraitClaimed(self.journal, traitId) then
                traitCount = traitCount + 1
            end
        end
    end

    self.skillCount = skillCount
    self.traitCount = traitCount
    self.totalXP = totalXP

    -- ============ SKILL LIST ============
    local footerHeight = 85
    local listHeight = self.height - y - footerHeight - padding

    self.skillList = ISScrollingListBox:new(padding, y, self.width - padding * 2, listHeight)
    self.skillList:initialise()
    self.skillList:instantiate()
    self.skillList.drawBorder = false
    self.skillList.backgroundColor = {r=0, g=0, b=0, a=0}
    self.skillList:setFont(UIFont.Small, 2)
    self.skillList.itemheight = 52
    self.skillList.doDrawItem = BurdJournals.UI.MainPanel.doDrawAbsorptionItem
    self.skillList.mainPanel = self

    -- Click handling
    self.skillList.onMouseUp = function(listbox, x, y)
        if listbox.vscroll then
            listbox.vscroll.scrolling = false
        end
        local ok, err = pcall(function()
            local row = listbox:rowAt(x, y)
            if row and row >= 1 and row <= #listbox.items then
                local item = listbox.items[row] and listbox.items[row].item
                if item and not item.isHeader and not item.isEmpty and not item.isClaimed then
                    local btnAreaStart = listbox:getWidth() - 80
                    if x >= btnAreaStart or item.isTrait then
                        if item.isSkill then
                            listbox.mainPanel:absorbSkill(item.skillName, item.xp)
                        elseif item.isTrait and not item.alreadyKnown then
                            listbox.mainPanel:absorbTrait(item.traitId)
                        end
                    end
                end
            end
        end)
        if not ok then
            print("[BurdJournals] UI Click error: " .. tostring(err))
        end
        return true
    end
    self:addChild(self.skillList)
    y = y + listHeight

    -- ============ FOOTER ============
    self.footerY = y + 4
    self.footerHeight = footerHeight

    -- Feedback label
    self.feedbackLabel = ISLabel:new(padding, self.footerY + 4, 18, "", 0.7, 0.9, 0.7, 1, UIFont.Small, true)
    self:addChild(self.feedbackLabel)
    self.feedbackLabel:setVisible(false)
    self.feedbackTicks = 0

    -- Footer buttons
    local btnWidth = 110
    local btnSpacing = 12
    local totalBtnWidth = btnWidth * 2 + btnSpacing
    local btnStartX = (self.width - totalBtnWidth) / 2
    local btnY = self.footerY + 32

    -- Absorb All button
    self.absorbAllBtn = ISButton:new(btnStartX, btnY, btnWidth, btnHeight, "Absorb All", self, BurdJournals.UI.MainPanel.onAbsorbAll)
    self.absorbAllBtn:initialise()
    self.absorbAllBtn:instantiate()
    if isBloody then
        self.absorbAllBtn.borderColor = {r=0.6, g=0.2, b=0.2, a=1}
        self.absorbAllBtn.backgroundColor = {r=0.35, g=0.1, b=0.1, a=0.8}
    else
        self.absorbAllBtn.borderColor = {r=0.4, g=0.5, b=0.3, a=1}
        self.absorbAllBtn.backgroundColor = {r=0.2, g=0.25, b=0.15, a=0.8}
    end
    self.absorbAllBtn.textColor = {r=1, g=1, b=1, a=1}
    self:addChild(self.absorbAllBtn)

    -- Close button
    self.closeBottomBtn = ISButton:new(btnStartX + btnWidth + btnSpacing, btnY, btnWidth, btnHeight, "Close", self, BurdJournals.UI.MainPanel.onClose)
    self.closeBottomBtn:initialise()
    self.closeBottomBtn:instantiate()
    self.closeBottomBtn.borderColor = {r=0.4, g=0.35, b=0.3, a=1}
    self.closeBottomBtn.backgroundColor = {r=0.15, g=0.13, b=0.12, a=0.8}
    self.closeBottomBtn.textColor = {r=0.9, g=0.85, b=0.8, a=1}
    self:addChild(self.closeBottomBtn)

    -- Populate the list
    self:populateAbsorptionList()
end

-- Absorb All button handler
function BurdJournals.UI.MainPanel:onAbsorbAll()
    -- Start learning all rewards with combined timer
    if not self:startLearningAll() then
        self:showFeedback("Already reading...", {r=0.9, g=0.7, b=0.3})
    end
end

-- ==================== CUSTOM RENDER FOR HEADER/FOOTER ====================

function BurdJournals.UI.MainPanel:prerender()
    ISPanel.prerender(self)

    -- Handle different modes
    if self.mode == "absorb" or self.mode == "view" or self.mode == "log" then
        self:prerenderJournalUI()
    end
end

-- Shared prerender for all journal UI modes
function BurdJournals.UI.MainPanel:prerenderJournalUI()
    local padding = 16

    -- Check if any progress bar is active (Absorb All, Claim All, or Record All)
    local isProgressActive = false
    if self.mode == "log" then
        isProgressActive = self.recordingState and self.recordingState.active and self.recordingState.isRecordAll
    else
        isProgressActive = self.learningState and self.learningState.active and self.learningState.isAbsorbAll
    end

    -- Dynamically reposition buttons when progress bar is showing
    -- Progress bar + tooltip takes up ~45 pixels, so push buttons down
    local normalBtnY = self.footerY + 32
    local progressBtnY = self.footerY + 48  -- Move buttons down when progress bar is visible

    local targetBtnY = isProgressActive and progressBtnY or normalBtnY

    -- Update button positions
    if self.absorbAllBtn then
        self.absorbAllBtn:setY(targetBtnY)
    end
    if self.recordAllBtn then
        self.recordAllBtn:setY(targetBtnY)
    end
    if self.closeBottomBtn then
        self.closeBottomBtn:setY(targetBtnY)
    end

    -- Update button states based on learning/recording
    if self.mode == "absorb" or self.mode == "view" then
        if self.absorbAllBtn then
            local isLearning = self.learningState and self.learningState.active
            self.absorbAllBtn:setEnable(not isLearning)
            if isLearning then
                self.absorbAllBtn.title = "Reading..."
            else
                self.absorbAllBtn.title = (self.mode == "view") and "Claim All" or "Absorb All"
            end
        end
    elseif self.mode == "log" then
        if self.recordAllBtn then
            local isRecording = self.recordingState and self.recordingState.active
            self.recordAllBtn:setEnable(not isRecording)
            if isRecording then
                self.recordAllBtn.title = "Recording..."
            else
                self.recordAllBtn.title = "Record All"
            end
        end
    end

    -- ============ DRAW HEADER ============
    if self.headerColor then
        -- Header background
        self:drawRect(0, 0, self.width, self.headerHeight, 0.95, self.headerColor.r, self.headerColor.g, self.headerColor.b)

        -- Header accent line
        if self.headerAccent then
            self:drawRect(0, self.headerHeight - 3, self.width, 3, 1, self.headerAccent.r, self.headerAccent.g, self.headerAccent.b)
        end

        -- Journal type text
        if self.typeText then
            self:drawText(self.typeText, padding, 12, 1, 0.9, 0.85, 1, UIFont.Medium)
        end

        -- Rarity badge (only for absorb mode)
        if self.rarityText and self.mode == "absorb" then
            local rarityX = self.width - padding - getTextManager():MeasureStringX(UIFont.Small, self.rarityText) - 12
            if self.isBloody then
                self:drawRect(rarityX - 6, 10, getTextManager():MeasureStringX(UIFont.Small, self.rarityText) + 12, 20, 0.8, 0.6, 0.15, 0.15)
            else
                self:drawRect(rarityX - 6, 10, getTextManager():MeasureStringX(UIFont.Small, self.rarityText) + 12, 20, 0.8, 0.5, 0.4, 0.2)
            end
            self:drawText(self.rarityText, rarityX, 12, 1, 0.95, 0.85, 1, UIFont.Small)
        end
    end

    -- ============ DRAW AUTHOR BOX ============
    if self.authorBoxY then
        -- Author box background (blue tint for personal journals)
        local boxBg = (self.mode == "log" or self.mode == "view") 
            and {r=0.10, g=0.14, b=0.18} 
            or {r=0.12, g=0.11, b=0.10}
        local boxBorder = (self.mode == "log" or self.mode == "view")
            and {r=0.20, g=0.30, b=0.38}
            or {r=0.30, g=0.28, b=0.25}
        
        self:drawRect(padding, self.authorBoxY, self.width - padding * 2, self.authorBoxHeight, 0.6, boxBg.r, boxBg.g, boxBg.b)
        self:drawRectBorder(padding, self.authorBoxY, self.width - padding * 2, self.authorBoxHeight, 0.5, boxBorder.r, boxBorder.g, boxBorder.b)

        -- Author name (different text for log mode)
        local authorText
        if self.mode == "log" then
            authorText = "Recording progress for " .. (self.authorName or "Unknown")
        else
            authorText = "From the notes of " .. (self.authorName or "Unknown")
        end
        self:drawText(authorText, padding + 10, self.authorBoxY + 8, 0.8, 0.85, 0.9, 1, UIFont.Small)

        -- Flavor text
        if self.flavorText then
            self:drawText(self.flavorText, padding + 10, self.authorBoxY + 24, 0.5, 0.55, 0.6, 1, UIFont.Small)
        end
    end

    -- ============ DRAW FOOTER ============
    if self.footerY then
        -- Footer separator
        self:drawRect(padding, self.footerY, self.width - padding * 2, 1, 0.3, 0.25, 0.35, 0.45)

        -- Handle progress bars for different modes
        if self.mode == "log" then
            -- Recording mode progress bar
            if self.recordingState and self.recordingState.active and self.recordingState.isRecordAll then
                local barX = padding
                local barY = self.footerY + 8
                local barW = self.width - padding * 2
                local barH = 16
                local progress = self.recordingState.progress
                local totalRecords = #self.recordingState.pendingRecords
                
                local elapsed = (getTimestampMs() - self.recordingState.startTime) / 1000.0
                local remaining = math.max(0, self.recordingState.totalTime - elapsed)
                local remainingText = string.format("%.1fs", remaining)
                
                self:drawRect(barX, barY, barW, barH, 0.7, 0.12, 0.12, 0.12)
                self:drawRect(barX, barY, barW * progress, barH, 0.85, 0.25, 0.55, 0.45)
                self:drawRectBorder(barX, barY, barW, barH, 0.8, 0.4, 0.6, 0.7)
                
                local progressText = string.format("Recording All: %d%% (%s remaining)", 
                                                  math.floor(progress * 100), remainingText)
                local textWidth = getTextManager():MeasureStringX(UIFont.Small, progressText)
                self:drawText(progressText, (self.width - textWidth) / 2, barY + 1, 1, 1, 1, 1, UIFont.Small)
                
                local countText = string.format("%d item%s", totalRecords, totalRecords > 1 and "s" or "")
                local countWidth = getTextManager():MeasureStringX(UIFont.Small, countText)
                self:drawText(countText, (self.width - countWidth) / 2, barY + barH + 4, 0.6, 0.7, 0.75, 1, UIFont.Small)
            end
        elseif self.learningState and self.learningState.active and self.learningState.isAbsorbAll then
            -- Absorb/Claim All progress bar
            local barX = padding
            local barY = self.footerY + 8
            local barW = self.width - padding * 2
            local barH = 16
            local progress = self.learningState.progress
            local totalRewards = #self.learningState.pendingRewards
            
            local elapsed = (getTimestampMs() - self.learningState.startTime) / 1000.0
            local remaining = math.max(0, self.learningState.totalTime - elapsed)
            local remainingText = string.format("%.1fs", remaining)
            
            self:drawRect(barX, barY, barW, barH, 0.7, 0.12, 0.12, 0.12)
            local fillW = barW * progress
            if self.isBloody then
                self:drawRect(barX, barY, fillW, barH, 0.85, 0.6, 0.2, 0.15)
            elseif self.mode == "view" then
                self:drawRect(barX, barY, fillW, barH, 0.85, 0.25, 0.50, 0.60)
            else
                self:drawRect(barX, barY, fillW, barH, 0.85, 0.35, 0.55, 0.25)
            end
            self:drawRectBorder(barX, barY, barW, barH, 0.8, 0.5, 0.5, 0.5)
            
            local actionText = (self.mode == "view") and "Claiming All" or "Absorbing All"
            local progressText = string.format("%s: %d%% (%s remaining)", actionText,
                                              math.floor(progress * 100), remainingText)
            local textWidth = getTextManager():MeasureStringX(UIFont.Small, progressText)
            self:drawText(progressText, (self.width - textWidth) / 2, barY + 1, 1, 1, 1, 1, UIFont.Small)
            
            local countText = string.format("%d reward%s queued", totalRewards, totalRewards > 1 and "s" or "")
            local countWidth = getTextManager():MeasureStringX(UIFont.Small, countText)
            self:drawText(countText, (self.width - countWidth) / 2, barY + barH + 4, 0.6, 0.6, 0.55, 1, UIFont.Small)
        else
            -- Normal summary text (for absorb/view modes)
            if self.mode == "absorb" or self.mode == "view" then
        local summaryText = ""
        if self.totalXP and self.totalXP > 0 then
            summaryText = "Total: +" .. BurdJournals.formatXP(self.totalXP) .. " XP"
        end
        if self.traitCount and self.traitCount > 0 then
            if summaryText ~= "" then summaryText = summaryText .. "  |  " end
            summaryText = summaryText .. self.traitCount .. " trait" .. (self.traitCount > 1 and "s" or "")
        end
        if summaryText ~= "" then
            local textWidth = getTextManager():MeasureStringX(UIFont.Small, summaryText)
                    self:drawText(summaryText, (self.width - textWidth) / 2, self.footerY + 10, 0.7, 0.75, 0.8, 1, UIFont.Small)
                end
            end
        end
    end
end

-- ==================== DRAW ITEM FUNCTIONS ====================

function BurdJournals.UI.MainPanel.doDrawAbsorptionItem(self, y, item, alt)
    local mainPanel = self.mainPanel
    if not mainPanel then return y + self.itemheight end

    -- IMPORTANT: In ISScrollingListBox, the data passed to addItem() is stored in item.item
    local data = item.item or {}

    local x = 0
    local w = self:getWidth()
    local h = self.itemheight
    local padding = 12

    -- Get theme colors
    local isBloody = mainPanel.isBloody
    local cardBg, cardBorder, accentColor
    if isBloody then
        cardBg = {r=0.18, g=0.12, b=0.12}
        cardBorder = {r=0.4, g=0.2, b=0.2}
        accentColor = {r=0.7, g=0.25, b=0.25}
    else
        cardBg = {r=0.14, g=0.13, b=0.11}
        cardBorder = {r=0.35, g=0.32, b=0.28}
        accentColor = {r=0.5, g=0.6, b=0.4}
    end

    -- ============ HEADER ROW ============
    if data.isHeader then
        self:drawRect(x, y + 2, w, h - 4, 0.4, 0.15, 0.14, 0.12)
        self:drawText(data.text or "SKILLS", x + padding, y + (h - 18) / 2, 0.9, 0.8, 0.6, 1, UIFont.Medium)
        if data.count then
            local countText = "(" .. data.count .. " available)"
            local countWidth = getTextManager():MeasureStringX(UIFont.Small, countText)
            self:drawText(countText, w - padding - countWidth, y + (h - 14) / 2, 0.5, 0.5, 0.45, 1, UIFont.Small)
        end
        return y + h
    end

    -- ============ EMPTY ROW ============
    if data.isEmpty then
        self:drawText(data.text or "No rewards available", x + padding, y + (h - 14) / 2, 0.4, 0.4, 0.4, 1, UIFont.Small)
        return y + h
    end

    -- ============ SKILL/TRAIT CARD ============
    local cardMargin = 4
    local cardX = x + cardMargin
    local cardY = y + cardMargin
    local cardW = w - cardMargin * 2
    local cardH = h - cardMargin * 2

    -- Card background
    if data.isClaimed then
        self:drawRect(cardX, cardY, cardW, cardH, 0.3, 0.1, 0.1, 0.1)
    else
        self:drawRect(cardX, cardY, cardW, cardH, 0.7, cardBg.r, cardBg.g, cardBg.b)
    end

    -- Card border
    self:drawRectBorder(cardX, cardY, cardW, cardH, 0.6, cardBorder.r, cardBorder.g, cardBorder.b)

    -- Left accent bar
    self:drawRect(cardX, cardY, 4, cardH, 0.9, accentColor.r, accentColor.g, accentColor.b)

    local textX = cardX + padding + 4
    local textColor = data.isClaimed and {r=0.4, g=0.4, b=0.4} or {r=0.95, g=0.9, b=0.85}

    -- ============ SKILL ROW ============
    if data.isSkill then
        -- Check if this skill is currently being learned
        local learningState = mainPanel.learningState
        local isLearningThis = learningState.active and not learningState.isAbsorbAll 
                              and learningState.skillName == data.skillName
        local isQueuedInAbsorbAll = learningState.active and learningState.isAbsorbAll
                                   and not data.isClaimed
        
        -- Check if this skill is in the manual queue
        local queuePosition = mainPanel:getQueuePosition(data.skillName)
        local isQueued = queuePosition ~= nil
        
        -- Skill name
        local displayName = data.displayName or data.skillName or "Unknown Skill"
        self:drawText(displayName, textX, cardY + 6, textColor.r, textColor.g, textColor.b, 1, UIFont.Small)

        -- Show learning progress bar if this skill is being learned
        if isLearningThis then
            local progressText = string.format("Reading... %d%%", math.floor(learningState.progress * 100))
            self:drawText(progressText, textX, cardY + 22, 0.9, 0.8, 0.3, 1, UIFont.Small)

            -- Learning progress bar (replaces XP bar)
            local barX = textX + 90
            local barY = cardY + 25
            local barW = cardW - 120 - padding
            local barH = 10

            -- Bar background
            self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)
            -- Bar fill (animated)
            self:drawRect(barX, barY, barW * learningState.progress, barH, 0.9, 0.3, 0.7, 0.4)
            -- Bar border
            self:drawRectBorder(barX, barY, barW, barH, 0.7, 0.4, 0.8, 0.5)
        
        elseif isQueued then
            -- Show as queued with position
            local xpText = "+" .. BurdJournals.formatXP(data.xp) .. " XP - Queued #" .. queuePosition
            self:drawText(xpText, textX, cardY + 22, 0.6, 0.75, 0.9, 1, UIFont.Small)
            
        elseif isQueuedInAbsorbAll then
            -- Show as queued (Absorb All mode)
            local xpText = "+" .. BurdJournals.formatXP(data.xp) .. " XP - Queued"
            self:drawText(xpText, textX, cardY + 22, 0.5, 0.6, 0.4, 1, UIFont.Small)
            
        elseif data.xp and not data.isClaimed then
            local xpText = "+" .. BurdJournals.formatXP(data.xp) .. " XP"
            self:drawText(xpText, textX, cardY + 22, 0.6, 0.8, 0.5, 1, UIFont.Small)

            -- XP progress bar
            local barX = textX + 80
            local barY = cardY + 25
            local barW = 100
            local barH = 8
            local maxXP = 1000  -- Approximate max for visual scaling
            local fillRatio = math.min(data.xp / maxXP, 1)

            -- Bar background
            self:drawRect(barX, barY, barW, barH, 0.5, 0.1, 0.1, 0.1)
            -- Bar fill
            self:drawRect(barX, barY, barW * fillRatio, barH, 0.8, accentColor.r, accentColor.g, accentColor.b)
            -- Bar border
            self:drawRectBorder(barX, barY, barW, barH, 0.4, 0.3, 0.3, 0.3)
        elseif data.isClaimed then
            self:drawText("Claimed", textX, cardY + 22, 0.35, 0.35, 0.35, 1, UIFont.Small)
        end

        -- Button (right side)
        if not data.isClaimed and not isLearningThis then
            local btnW = 65
            local btnH = 24
            local btnX = cardX + cardW - btnW - 10
            local btnY = cardY + (cardH - btnH) / 2
            
            if isQueued then
                -- Show "QUEUED" indicator (not clickable style)
                self:drawRect(btnX, btnY, btnW, btnH, 0.5, 0.3, 0.4, 0.5)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.6, 0.4, 0.5, 0.6)
                local btnText = "#" .. queuePosition
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.8, 0.9, 1, 1, UIFont.Small)
            elseif learningState.active and not learningState.isAbsorbAll then
                -- Show "QUEUE" button
                self:drawRect(btnX, btnY, btnW, btnH, 0.6, 0.25, 0.35, 0.5)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.4, 0.55, 0.7)
                local btnText = "QUEUE"
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.9, 0.95, 1, 1, UIFont.Small)
            elseif not learningState.active then
                -- Show "ABSORB" button (normal state)
            self:drawRect(btnX, btnY, btnW, btnH, 0.7, accentColor.r * 0.6, accentColor.g * 0.6, accentColor.b * 0.6)
            self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, accentColor.r, accentColor.g, accentColor.b)
            local btnText = "ABSORB"
            local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
            self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 1, 1, 1, 1, UIFont.Small)
            end
        end
    end

    -- ============ TRAIT ROW ============
    if data.isTrait then
        -- Check if this trait is currently being learned
        local learningState = mainPanel.learningState
        local isLearningThis = learningState.active and not learningState.isAbsorbAll 
                              and learningState.traitId == data.traitId
        local isQueuedInAbsorbAll = learningState.active and learningState.isAbsorbAll
                                   and not data.isClaimed and not data.alreadyKnown
        
        -- Check if this trait is in the manual queue
        local queuePosition = mainPanel:getQueuePosition(data.traitId)
        local isQueued = queuePosition ~= nil
        
        local traitName = data.traitName or data.traitId or "Unknown Trait"
        local traitTextX = textX

        -- Draw trait icon if available
        if data.traitTexture then
            local iconSize = 24
            local iconX = textX
            local iconY = cardY + (cardH - iconSize) / 2
            local iconAlpha = data.isClaimed and 0.4 or 1.0
            self:drawTextureScaledAspect(data.traitTexture, iconX, iconY, iconSize, iconSize, iconAlpha, 1, 1, 1)
            traitTextX = textX + iconSize + 6  -- Offset text after icon
        end

        -- Trait name with special color
        local traitColor = data.isClaimed and {r=0.4, g=0.4, b=0.4} or {r=0.9, g=0.75, b=0.5}
        self:drawText(traitName, traitTextX, cardY + 6, traitColor.r, traitColor.g, traitColor.b, 1, UIFont.Small)

        -- Show learning progress bar if this trait is being learned
        if isLearningThis then
            local progressText = string.format("Absorbing... %d%%", math.floor(learningState.progress * 100))
            self:drawText(progressText, traitTextX, cardY + 22, 0.9, 0.7, 0.3, 1, UIFont.Small)

            -- Learning progress bar
            local barX = traitTextX + 100
            local barY = cardY + 25
            local barW = cardW - 130 - padding
            local barH = 10

            -- Bar background
            self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)
            -- Bar fill (gold/amber for traits)
            self:drawRect(barX, barY, barW * learningState.progress, barH, 0.9, 0.8, 0.6, 0.2)
            -- Bar border
            self:drawRectBorder(barX, barY, barW, barH, 0.7, 0.9, 0.7, 0.3)
        
        elseif isQueued then
            -- Show as queued with position
            self:drawText("Rare trait - Queued #" .. queuePosition, traitTextX, cardY + 22, 0.6, 0.75, 0.9, 1, UIFont.Small)
            
        elseif isQueuedInAbsorbAll then
            self:drawText("Rare trait bonus! - Queued", traitTextX, cardY + 22, 0.5, 0.45, 0.25, 1, UIFont.Small)
            
        elseif data.isClaimed then
            self:drawText("Claimed", traitTextX, cardY + 22, 0.35, 0.35, 0.35, 1, UIFont.Small)
        elseif data.alreadyKnown then
            self:drawText("Already known", traitTextX, cardY + 22, 0.5, 0.4, 0.3, 1, UIFont.Small)
        else
            self:drawText("Rare trait bonus!", traitTextX, cardY + 22, 0.7, 0.55, 0.3, 1, UIFont.Small)
        end

        -- Button for traits (not already known or claimed)
        if not data.isClaimed and not data.alreadyKnown and not isLearningThis then
            local btnW = 60
            local btnH = 24
            local btnX = cardX + cardW - btnW - 10
            local btnY = cardY + (cardH - btnH) / 2
            
            if isQueued then
                -- Show "QUEUED" indicator
                self:drawRect(btnX, btnY, btnW, btnH, 0.5, 0.4, 0.35, 0.5)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.6, 0.5, 0.45, 0.6)
                local btnText = "#" .. queuePosition
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.9, 0.85, 0.7, 1, UIFont.Small)
            elseif learningState.active and not learningState.isAbsorbAll then
                -- Show "QUEUE" button
                self:drawRect(btnX, btnY, btnW, btnH, 0.6, 0.4, 0.35, 0.25)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.6, 0.5, 0.35)
                local btnText = "QUEUE"
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 1, 0.95, 0.85, 1, UIFont.Small)
            elseif not learningState.active then
                -- Show "CLAIM" button (normal state)
            self:drawRect(btnX, btnY, btnW, btnH, 0.7, 0.5, 0.35, 0.15)
            self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.7, 0.5, 0.25)
            local btnText = "CLAIM"
            local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
            self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 1, 0.95, 0.85, 1, UIFont.Small)
            end
        end
    end

    return y + h
end

-- ==================== POPULATE ABSORPTION LIST ====================

function BurdJournals.UI.MainPanel:populateAbsorptionList()
    self.skillList:clear()

    local journalData = BurdJournals.getJournalData(self.journal)
    local hasBloodyOrigin = BurdJournals.hasBloodyOrigin(self.journal)

    -- Count skills
    local skillCount = 0
    if journalData and journalData.skills then
        for skillName, _ in pairs(journalData.skills) do
            if not BurdJournals.isSkillClaimed(self.journal, skillName) then
                skillCount = skillCount + 1
            end
        end
    end

    -- Add skills header
    self.skillList:addItem("SKILLS", {isHeader = true, text = "SKILLS", count = skillCount})

    -- Add skill rows
    if journalData and journalData.skills then
        local hasSkills = false
        for skillName, skillData in pairs(journalData.skills) do
            hasSkills = true
            local isClaimed = BurdJournals.isSkillClaimed(self.journal, skillName)
            local displayName = BurdJournals.getPerkDisplayName(skillName)
            self.skillList:addItem(skillName, {
                isSkill = true,
                skillName = skillName,
                displayName = displayName,
                xp = skillData.xp or 0,
                level = skillData.level or 0,
                isClaimed = isClaimed
            })
        end
        if not hasSkills then
            self.skillList:addItem("empty", {isEmpty = true, text = "No skills recorded"})
        end
    else
        self.skillList:addItem("empty", {isEmpty = true, text = "No skills recorded"})
    end

    -- Add traits section for bloody journals
    if hasBloodyOrigin and journalData and journalData.traits then
        local traitCount = 0
        for traitId, _ in pairs(journalData.traits) do
            if not BurdJournals.isTraitClaimed(self.journal, traitId) then
                traitCount = traitCount + 1
            end
        end

        self.skillList:addItem("TRAITS", {isHeader = true, text = "TRAITS", count = traitCount})

        local hasTraits = false
        for traitId, traitData in pairs(journalData.traits) do
            hasTraits = true
            local isClaimed = BurdJournals.isTraitClaimed(self.journal, traitId)
            local alreadyKnown = BurdJournals.playerHasTrait(self.player, traitId)
            local traitName = safeGetTraitName(traitId)
            local traitTexture = getTraitTexture(traitId)
            self.skillList:addItem(traitId, {
                isTrait = true,
                traitId = traitId,
                traitName = traitName,
                traitTexture = traitTexture,
                isClaimed = isClaimed,
                alreadyKnown = alreadyKnown
            })
        end
        if not hasTraits then
            self.skillList:addItem("empty_traits", {isEmpty = true, text = "No rare traits found"})
        end
    end
end

-- ==================== REFRESH THE LIST ====================

function BurdJournals.UI.MainPanel:refreshAbsorptionList()
    -- Re-count totals
    local journalData = BurdJournals.getJournalData(self.journal)
    local hasBloodyOrigin = BurdJournals.hasBloodyOrigin(self.journal)

    local skillCount = 0
    local traitCount = 0
    local totalXP = 0

    if journalData and journalData.skills then
        for skillName, skillData in pairs(journalData.skills) do
            if not BurdJournals.isSkillClaimed(self.journal, skillName) then
                skillCount = skillCount + 1
                totalXP = totalXP + (skillData.xp or 0)
            end
        end
    end
    if hasBloodyOrigin and journalData and journalData.traits then
        for traitId, _ in pairs(journalData.traits) do
            if not BurdJournals.isTraitClaimed(self.journal, traitId) then
                traitCount = traitCount + 1
            end
        end
    end

    self.skillCount = skillCount
    self.traitCount = traitCount
    self.totalXP = totalXP

    -- Repopulate list based on mode
    if self.mode == "view" then
        self:populateViewList()
    else
        self:populateAbsorptionList()
    end
end

-- ==================== ABSORPTION HANDLERS ====================

-- ==================== LEARNING TIMER SYSTEM ====================

-- Get reading skill speed bonus (reduces learning time)
function BurdJournals.UI.MainPanel:getReadingSpeedMultiplier()
    if not BurdJournals.getSandboxOption("ReadingSkillAffectsSpeed") then
        return 1.0
    end
    
    local bonusPerLevel = BurdJournals.getSandboxOption("ReadingSpeedBonus") or 0.1
    local readingLevel = 0
    
    -- Get player's reading skill level (if the method exists)
    if self.player then
        pcall(function()
            -- Try to get reading level - this method exists in vanilla PZ
            if self.player.getReadingLevel then
                readingLevel = self.player:getReadingLevel() or 0
            end
        end)
    end
    
    -- Calculate speed bonus (higher reading = faster = lower multiplier)
    -- Each level gives bonusPerLevel (e.g., 0.1 = 10%) faster
    -- Max 10 levels = up to 100% faster (0.0 multiplier, capped at 0.1)
    local speedBonus = readingLevel * bonusPerLevel
    local speedMultiplier = math.max(0.1, 1.0 - speedBonus)
    
    return speedMultiplier
end

-- Get learning time for a skill (in seconds)
function BurdJournals.UI.MainPanel:getSkillLearningTime()
    local baseTime = BurdJournals.getSandboxOption("LearningTimePerSkill") or 3.0
    local multiplier = BurdJournals.getSandboxOption("LearningTimeMultiplier") or 1.0
    local readingMultiplier = self:getReadingSpeedMultiplier()
    return baseTime * multiplier * readingMultiplier
end

-- Get learning time for a trait (in seconds)
function BurdJournals.UI.MainPanel:getTraitLearningTime()
    local baseTime = BurdJournals.getSandboxOption("LearningTimePerTrait") or 5.0
    local multiplier = BurdJournals.getSandboxOption("LearningTimeMultiplier") or 1.0
    local readingMultiplier = self:getReadingSpeedMultiplier()
    return baseTime * multiplier * readingMultiplier
end

-- Start learning a single skill
function BurdJournals.UI.MainPanel:startLearningSkill(skillName, xp)
    if self.learningState.active then
        -- Already learning something
        return false
    end
    
    self.learningState = {
        active = true,
        skillName = skillName,
        traitId = nil,
        isAbsorbAll = false,
        progress = 0,
        totalTime = self:getSkillLearningTime(),
        startTime = getTimestampMs(),
        pendingRewards = {{type = "skill", name = skillName, xp = xp}},
        currentIndex = 1,
        queue = {},
    }
    
    -- Register tick handler
    Events.OnTick.Add(BurdJournals.UI.MainPanel.onLearningTickStatic)
    
    -- Play page turn sound
    self:playSound(BurdJournals.Sounds.PAGE_TURN)
    
    return true
end

-- Start learning a single trait
function BurdJournals.UI.MainPanel:startLearningTrait(traitId)
    if self.learningState.active then
        return false
    end
    
    self.learningState = {
        active = true,
        skillName = nil,
        traitId = traitId,
        isAbsorbAll = false,
        progress = 0,
        totalTime = self:getTraitLearningTime(),
        startTime = getTimestampMs(),
        pendingRewards = {{type = "trait", name = traitId}},
        currentIndex = 1,
        queue = {},
    }
    
    Events.OnTick.Add(BurdJournals.UI.MainPanel.onLearningTickStatic)
    
    -- Play page turn sound
    self:playSound(BurdJournals.Sounds.PAGE_TURN)
    
    return true
end

-- Start learning all available rewards (Absorb All)
function BurdJournals.UI.MainPanel:startLearningAll()
    if self.learningState.active then
        return false
    end
    
    local journalData = BurdJournals.getJournalData(self.journal)
    if not journalData then return false end
    
    local isPlayerJournal = self.isPlayerJournal or self.mode == "view"
    local hasBloodyOrigin = BurdJournals.hasBloodyOrigin(self.journal)
    local pendingRewards = {}
    local totalTime = 0
    
    -- Collect all unclaimed/claimable skills
    if journalData.skills then
        for skillName, skillData in pairs(journalData.skills) do
            local shouldInclude = false
            
            if isPlayerJournal then
                -- SET mode: Only include if player's XP is below recorded
                local perk = BurdJournals.getPerkByName(skillName)
                if perk then
                    local playerXP = self.player:getXp():getXP(perk)
                    if playerXP < (skillData.xp or 0) then
                        shouldInclude = true
                    end
                end
            else
                -- ADD mode: Include if not claimed
                if not BurdJournals.isSkillClaimed(self.journal, skillName) then
                    shouldInclude = true
                end
            end
            
            if shouldInclude then
                table.insert(pendingRewards, {type = "skill", name = skillName, xp = skillData.xp})
                totalTime = totalTime + self:getSkillLearningTime()
            end
        end
    end
    
    -- Collect all unclaimed traits
    local hasTraits = (isPlayerJournal and journalData.traits) or (hasBloodyOrigin and journalData.traits)
    if hasTraits then
        for traitId, _ in pairs(journalData.traits) do
            local shouldInclude = false
            
            if isPlayerJournal then
                -- Player journals: Include if player doesn't have the trait
                if not BurdJournals.playerHasTrait(self.player, traitId) then
                    shouldInclude = true
                end
            else
                -- Worn/bloody: Include if not claimed
                if not BurdJournals.isTraitClaimed(self.journal, traitId) then
                    shouldInclude = true
                end
            end
            
            if shouldInclude then
                table.insert(pendingRewards, {type = "trait", name = traitId})
                totalTime = totalTime + self:getTraitLearningTime()
            end
        end
    end
    
    if #pendingRewards == 0 then
        self:showFeedback("No new rewards to claim", {r=0.7, g=0.7, b=0.5})
        return false
    end
    
    self.learningState = {
        active = true,
        skillName = nil,
        traitId = nil,
        isAbsorbAll = true,
        progress = 0,
        totalTime = totalTime,
        startTime = getTimestampMs(),
        pendingRewards = pendingRewards,
        currentIndex = 1,
        queue = {},  -- Not used in Absorb All mode
    }
    
    Events.OnTick.Add(BurdJournals.UI.MainPanel.onLearningTickStatic)
    
    -- Play page turn sound
    self:playSound(BurdJournals.Sounds.PAGE_TURN)
    
    return true
end

-- Cancel learning (called when closing mid-learning)
function BurdJournals.UI.MainPanel:cancelLearning()
    if self.learningState.active then
        self.learningState.active = false
        Events.OnTick.Remove(BurdJournals.UI.MainPanel.onLearningTickStatic)
    end
    self.learningState = {
        active = false,
        skillName = nil,
        traitId = nil,
        isAbsorbAll = false,
        progress = 0,
        totalTime = 0,
        startTime = 0,
        pendingRewards = {},
        currentIndex = 0,
        queue = {},
    }
    self.learningCompleted = false
    self.processingQueue = false
end

-- ==================== RECORDING SYSTEM (For Player Journals) ====================

-- Get recording time for a skill (shorter than learning)
function BurdJournals.UI.MainPanel:getSkillRecordingTime()
    local baseTime = (BurdJournals.getSandboxOption("LearningTimePerSkill") or 3.0) * 0.5  -- Half the learning time
    local multiplier = BurdJournals.getSandboxOption("LearningTimeMultiplier") or 1.0
    return baseTime * multiplier
end

-- Get recording time for a trait
function BurdJournals.UI.MainPanel:getTraitRecordingTime()
    local baseTime = (BurdJournals.getSandboxOption("LearningTimePerTrait") or 5.0) * 0.5
    local multiplier = BurdJournals.getSandboxOption("LearningTimeMultiplier") or 1.0
    return baseTime * multiplier
end

-- Start recording a single skill
function BurdJournals.UI.MainPanel:startRecordingSkill(skillName, xp, level)
    if self.recordingState and self.recordingState.active then
        return false
    end
    
    if not self.recordingState then
        self.recordingState = {}
    end
    
    self.recordingState = {
        active = true,
        skillName = skillName,
        traitId = nil,
        isRecordAll = false,
        progress = 0,
        totalTime = self:getSkillRecordingTime(),
        startTime = getTimestampMs(),
        pendingRecords = {{type = "skill", name = skillName, xp = xp, level = level}},
        currentIndex = 1,
        queue = {},
    }
    
    Events.OnTick.Add(BurdJournals.UI.MainPanel.onRecordingTickStatic)
    return true
end

-- Start recording a single trait
function BurdJournals.UI.MainPanel:startRecordingTrait(traitId)
    if self.recordingState and self.recordingState.active then
        return false
    end
    
    if not self.recordingState then
        self.recordingState = {}
    end
    
    self.recordingState = {
        active = true,
        skillName = nil,
        traitId = traitId,
        isRecordAll = false,
        progress = 0,
        totalTime = self:getTraitRecordingTime(),
        startTime = getTimestampMs(),
        pendingRecords = {{type = "trait", name = traitId}},
        currentIndex = 1,
        queue = {},
    }
    
    Events.OnTick.Add(BurdJournals.UI.MainPanel.onRecordingTickStatic)
    return true
end

-- Start recording all skills and traits
function BurdJournals.UI.MainPanel:startRecordingAll()
    if self.recordingState and self.recordingState.active then
        return false
    end
    
    if not self.recordingState then
        self.recordingState = {}
    end
    
    local pendingRecords = {}
    local totalTime = 0
    
    local allowedSkills = BurdJournals.getAllowedSkills()
    local recordedSkills = self.recordedSkills or {}
    local recordedTraits = self.recordedTraits or {}
    
    -- Collect all recordable skills
    for _, skillName in ipairs(allowedSkills) do
        local perk = BurdJournals.getPerkByName(skillName)
        if perk then
            local currentXP = self.player:getXp():getXP(perk)
            local currentLevel = self.player:getPerkLevel(perk)
            local recordedData = recordedSkills[skillName]
            local recordedXP = recordedData and recordedData.xp or 0
            
            if (currentXP > 0 or currentLevel > 0) and currentXP > recordedXP then
                table.insert(pendingRecords, {type = "skill", name = skillName, xp = currentXP, level = currentLevel})
                totalTime = totalTime + self:getSkillRecordingTime()
            end
        end
    end
    
    -- Collect all recordable traits
    local playerTraits = BurdJournals.collectPlayerTraits(self.player)
    for traitId, _ in pairs(playerTraits) do
        if (BurdJournals.tableContains(BurdJournals.GRANTABLE_TRAITS, traitId) or
            BurdJournals.tableContains(BurdJournals.GRANTABLE_TRAITS, string.lower(traitId))) and
           not recordedTraits[traitId] then
            table.insert(pendingRecords, {type = "trait", name = traitId})
            totalTime = totalTime + self:getTraitRecordingTime()
        end
    end
    
    if #pendingRecords == 0 then
        self:showFeedback("Nothing new to record", {r=0.7, g=0.7, b=0.5})
        return false
    end
    
    self.recordingState = {
        active = true,
        skillName = nil,
        traitId = nil,
        isRecordAll = true,
        progress = 0,
        totalTime = totalTime,
        startTime = getTimestampMs(),
        pendingRecords = pendingRecords,
        currentIndex = 1,
        queue = {},
    }
    
    Events.OnTick.Add(BurdJournals.UI.MainPanel.onRecordingTickStatic)
    return true
end

-- Cancel recording
function BurdJournals.UI.MainPanel:cancelRecording()
    if self.recordingState and self.recordingState.active then
        self.recordingState.active = false
        Events.OnTick.Remove(BurdJournals.UI.MainPanel.onRecordingTickStatic)
    end
    if self.recordingState then
        self.recordingState = {
            active = false,
            skillName = nil,
            traitId = nil,
            isRecordAll = false,
            progress = 0,
            totalTime = 0,
            startTime = 0,
            pendingRecords = {},
            currentIndex = 0,
            queue = {},
        }
    end
    self.recordingCompleted = false
    self.processingRecordQueue = false
end

-- Static tick handler for recording
function BurdJournals.UI.MainPanel.onRecordingTickStatic()
    local instance = BurdJournals.UI.MainPanel.instance
    if instance and instance.recordingState and instance.recordingState.active then
        instance:onRecordingTick()
    else
        Events.OnTick.Remove(BurdJournals.UI.MainPanel.onRecordingTickStatic)
    end
end

-- Static tick handler for waiting on pending journal (after blank->filled conversion)
function BurdJournals.UI.MainPanel.onPendingJournalRetryStatic()
    local instance = BurdJournals.UI.MainPanel.instance
    if not instance or not instance.pendingNewJournalId then
        Events.OnTick.Remove(BurdJournals.UI.MainPanel.onPendingJournalRetryStatic)
        return
    end

    -- Try to find the pending journal
    local newJournal = BurdJournals.findItemById(instance.player, instance.pendingNewJournalId)
    if newJournal then
        print("[BurdJournals] onPendingJournalRetryStatic: Found pending journal!")
        instance.journal = newJournal
        instance.pendingNewJournalId = nil
        instance.pendingRecordingRetryCount = 0
        Events.OnTick.Remove(BurdJournals.UI.MainPanel.onPendingJournalRetryStatic)

        -- Resume the recording that was waiting
        if instance.pendingRecordingData then
            instance.recordingState = {
                active = false,
                pendingRecords = instance.pendingRecordingData.pendingRecords,
                queue = instance.pendingRecordingData.queue,
                isRecordAll = instance.pendingRecordingData.isRecordAll
            }
            instance.pendingRecordingData = nil
            instance:completeRecording()
        end
    else
        -- Increment retry counter in static handler
        instance.pendingRecordingRetryCount = (instance.pendingRecordingRetryCount or 0) + 1
        if instance.pendingRecordingRetryCount >= 20 then
            print("[BurdJournals] onPendingJournalRetryStatic: Max retries, giving up")
            Events.OnTick.Remove(BurdJournals.UI.MainPanel.onPendingJournalRetryStatic)
            instance.pendingRecordingRetryCount = 0
            instance.pendingNewJournalId = nil
            -- Show error to user
            if instance.showFeedback then
                instance:showFeedback("Error: Journal sync failed", {r=0.8, g=0.3, b=0.3})
            end
        end
    end
end

-- Instance tick handler for recording
function BurdJournals.UI.MainPanel:onRecordingTick()
    if not self.recordingState or not self.recordingState.active then
        Events.OnTick.Remove(BurdJournals.UI.MainPanel.onRecordingTickStatic)
        return
    end
    
    local now = getTimestampMs()
    local elapsed = (now - self.recordingState.startTime) / 1000.0
    self.recordingState.progress = math.min(1.0, elapsed / self.recordingState.totalTime)
    
    if self.recordingState.progress >= 1.0 then
        self:completeRecording()
    end
end

-- Complete recording - send records to server (MP-safe)
function BurdJournals.UI.MainPanel:completeRecording()
    Events.OnTick.Remove(BurdJournals.UI.MainPanel.onRecordingTickStatic)

    self.processingRecordQueue = true

    -- CRITICAL: Check if we have a pending journal ID from a previous blank->filled conversion
    -- This can happen when recording multiple skills in sequence
    if self.pendingNewJournalId then
        print("[BurdJournals] completeRecording: Checking for pending journal ID " .. tostring(self.pendingNewJournalId))
        local newJournal = BurdJournals.findItemById(self.player, self.pendingNewJournalId)
        if newJournal then
            print("[BurdJournals] completeRecording: Found pending journal, updating reference")
            self.journal = newJournal
            self.pendingNewJournalId = nil
        else
            -- Journal still not in inventory - wait and retry
            print("[BurdJournals] completeRecording: Pending journal not found yet, scheduling retry...")
            self.pendingRecordingRetryCount = (self.pendingRecordingRetryCount or 0) + 1
            if self.pendingRecordingRetryCount < 20 then -- Max 20 retries (~1 second)
                -- Schedule a retry in 50ms
                self.pendingRecordingData = {
                    pendingRecords = self.recordingState.pendingRecords,
                    queue = self.recordingState.queue,
                    isRecordAll = self.recordingState.isRecordAll
                }
                Events.OnTick.Add(BurdJournals.UI.MainPanel.onPendingJournalRetryStatic)
                return
            else
                print("[BurdJournals] completeRecording: Max retries reached, proceeding anyway")
                self.pendingRecordingRetryCount = 0
            end
        end
    end

    -- Collect skills and traits to send to server
    local skillsToRecord = {}
    local traitsToRecord = {}
    local skillCount = 0
    local traitCount = 0

    for _, record in ipairs(self.recordingState.pendingRecords) do
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
        end
    end

    -- Store pending counts for feedback after server response
    self.pendingRecordFeedback = {
        skills = skillCount,
        traits = traitCount
    }

    -- Send to server - server handles modData update and journal conversion
    sendClientCommand(self.player, "BurdJournals", "recordProgress", {
        journalId = self.journal:getID(),
        skills = skillsToRecord,
        traits = traitsToRecord
    })

    -- Show pending feedback (will be updated when server responds)
    self:showFeedback("Saving progress...", {r=0.7, g=0.7, b=0.7})
    
    -- Save the queue before resetting (Record All doesn't use queue)
    local savedQueue = {}
    if not self.recordingState.isRecordAll then
        savedQueue = self.recordingState.queue or {}
    end
    
    -- Check if there are queued items to record next
    if #savedQueue > 0 then
        local nextRecord = table.remove(savedQueue, 1)
        
        -- Start recording the next queued item
        if nextRecord.type == "skill" then
            self.recordingState = {
                active = true,
                skillName = nextRecord.name,
                traitId = nil,
                isRecordAll = false,
                progress = 0,
                totalTime = self:getSkillRecordingTime(),
                startTime = getTimestampMs(),
                pendingRecords = {{type = "skill", name = nextRecord.name, xp = nextRecord.xp, level = nextRecord.level}},
                currentIndex = 1,
                queue = savedQueue,
            }
        else
            self.recordingState = {
                active = true,
                skillName = nil,
                traitId = nextRecord.name,
                isRecordAll = false,
                progress = 0,
                totalTime = self:getTraitRecordingTime(),
                startTime = getTimestampMs(),
                pendingRecords = {{type = "trait", name = nextRecord.name}},
                currentIndex = 1,
                queue = savedQueue,
            }
        end
        
        -- Re-register tick handler for next item (remove first to avoid duplicates)
        Events.OnTick.Remove(BurdJournals.UI.MainPanel.onRecordingTickStatic)
        Events.OnTick.Add(BurdJournals.UI.MainPanel.onRecordingTickStatic)

        -- Refresh list to show updated state
        if self.skillList then
            pcall(function()
                self:populateRecordList()
            end)
        end

        -- Clear processing flag now that next item has started
        self.processingRecordQueue = false
        return
    end

    -- No more queued items - fully complete
    self.recordingCompleted = true
    self.processingRecordQueue = false

    -- Play completion sound (only once at the end)
    self:playSound(BurdJournals.Sounds.RECORD)
    
    self.recordingState = {
        active = false,
        skillName = nil,
        traitId = nil,
        isRecordAll = false,
        progress = 0,
        totalTime = 0,
        startTime = 0,
        pendingRecords = {},
        currentIndex = 0,
        queue = {},
    }
    
    -- Refresh list
    if self.skillList then
        self:populateRecordList()
    end
    
    -- Sync modData in multiplayer
    if isClient() and not isServer() then
        sendClientCommand(self.player, "BurdJournals", "syncJournalData", {
            journalId = self.journal:getID()
        })
    end
end

-- Record a skill (starts timed recording)
function BurdJournals.UI.MainPanel:recordSkill(skillName, xp, level)
    -- If already recording, add to queue
    if self.recordingState and self.recordingState.active and not self.recordingState.isRecordAll then
        if self:addToRecordQueue("skill", skillName, xp, level) then
            local displayName = BurdJournals.getPerkDisplayName(skillName) or skillName
            self:showFeedback("Queued: " .. displayName, {r=0.5, g=0.7, b=0.8})
        else
            self:showFeedback("Already queued", {r=0.9, g=0.7, b=0.3})
        end
        return
    end
    
    if not self:startRecordingSkill(skillName, xp, level) then
        self:showFeedback("Cannot record", {r=0.9, g=0.5, b=0.3})
    end
end

-- Record a trait (starts timed recording)
function BurdJournals.UI.MainPanel:recordTrait(traitId)
    -- If already recording, add to queue
    if self.recordingState and self.recordingState.active and not self.recordingState.isRecordAll then
        if self:addToRecordQueue("trait", traitId) then
            local traitName = safeGetTraitName(traitId)
            self:showFeedback("Queued: " .. traitName, {r=0.5, g=0.7, b=0.8})
        else
            self:showFeedback("Already queued", {r=0.9, g=0.7, b=0.3})
        end
        return
    end
    
    if not self:startRecordingTrait(traitId) then
        self:showFeedback("Cannot record", {r=0.9, g=0.5, b=0.3})
    end
end

-- Static tick handler (calls instance method)
function BurdJournals.UI.MainPanel.onLearningTickStatic()
    local instance = BurdJournals.UI.MainPanel.instance
    if instance and instance.learningState and instance.learningState.active then
        instance:onLearningTick()
    else
        -- No active instance, remove the handler
        Events.OnTick.Remove(BurdJournals.UI.MainPanel.onLearningTickStatic)
    end
end

-- Instance tick handler - updates progress and completes learning
function BurdJournals.UI.MainPanel:onLearningTick()
    if not self.learningState.active then
        Events.OnTick.Remove(BurdJournals.UI.MainPanel.onLearningTickStatic)
        return
    end
    
    local now = getTimestampMs()
    local elapsed = (now - self.learningState.startTime) / 1000.0  -- Convert to seconds
    self.learningState.progress = math.min(1.0, elapsed / self.learningState.totalTime)
    
    -- Check if complete
    if self.learningState.progress >= 1.0 then
        self:completeLearning()
    end
end

-- Complete learning - apply all pending rewards
function BurdJournals.UI.MainPanel:completeLearning()
    Events.OnTick.Remove(BurdJournals.UI.MainPanel.onLearningTickStatic)
    
    -- Mark that we're processing the queue (skip confirmation dialog during this)
    self.processingQueue = true
    
    -- If confirmation dialog is open, close it immediately
    if self.confirmDialog then
        pcall(function()
            self.confirmDialog:setVisible(false)
            self.confirmDialog:removeFromUIManager()
        end)
        self.confirmDialog = nil
    end
    
    -- Apply all pending rewards (current learning item(s))
    -- Use different commands based on journal type: absorb (ADD) vs claim (SET)
    local isPlayerJournal = self.isPlayerJournal or self.mode == "view"
    
    for _, reward in ipairs(self.learningState.pendingRewards) do
        if reward.type == "skill" then
            if isPlayerJournal then
                self:sendClaimSkill(reward.name, reward.xp)
            else
                self:sendAbsorbSkill(reward.name, reward.xp)
            end
        elseif reward.type == "trait" then
            if isPlayerJournal then
                self:sendClaimTrait(reward.name)
            else
                self:sendAbsorbTrait(reward.name)
            end
        end
    end
    
    -- Save the queue before resetting (Absorb All doesn't use queue)
    local savedQueue = {}
    if not self.learningState.isAbsorbAll then
        savedQueue = self.learningState.queue or {}
    end
    
    -- Check if there are queued items to learn next
    if #savedQueue > 0 then
        local nextReward = table.remove(savedQueue, 1)
        
        -- Start learning the next queued item
        if nextReward.type == "skill" then
            self.learningState = {
                active = true,
                skillName = nextReward.name,
                traitId = nil,
                isAbsorbAll = false,
                progress = 0,
                totalTime = self:getSkillLearningTime(),
                startTime = getTimestampMs(),
                pendingRewards = {{type = "skill", name = nextReward.name, xp = nextReward.xp}},
                currentIndex = 1,
                queue = savedQueue,
            }
        else
            self.learningState = {
                active = true,
                skillName = nil,
                traitId = nextReward.name,
                isAbsorbAll = false,
                progress = 0,
                totalTime = self:getTraitLearningTime(),
                startTime = getTimestampMs(),
                pendingRewards = {{type = "trait", name = nextReward.name}},
                currentIndex = 1,
                queue = savedQueue,
            }
        end
        
        -- Re-register tick handler for next item (remove first to avoid duplicates)
        Events.OnTick.Remove(BurdJournals.UI.MainPanel.onLearningTickStatic)
        Events.OnTick.Add(BurdJournals.UI.MainPanel.onLearningTickStatic)

        -- Refresh list to show updated state
        if self.skillList and self.journal then
            pcall(function()
                self:populateAbsorptionList()
            end)
        end

        -- Clear processing flag now that next item has started
        self.processingQueue = false
        return
    end

    -- No more queued items - fully complete
    self.learningCompleted = true
    self.processingQueue = false

    -- Play completion sound (only once at the end)
    self:playSound(BurdJournals.Sounds.LEARN_COMPLETE)
    
    -- Reset state
    self.learningState = {
        active = false,
        skillName = nil,
        traitId = nil,
        isAbsorbAll = false,
        progress = 0,
        totalTime = 0,
        startTime = 0,
        pendingRewards = {},
        currentIndex = 0,
        queue = {},
    }
    
    -- Refresh list to show claimed items (if panel still exists and journal not dissolved)
    if self.skillList and self.journal then
        pcall(function()
            -- Refresh player reference to get fresh XP values
            self:refreshPlayer()
            
            -- Use appropriate populate function based on mode
            if self.mode == "view" or self.isPlayerJournal then
                self:populateViewList()
            else
                self:populateAbsorptionList()
            end
        end)
    end
end

-- Send skill absorption command to server (actual application)
function BurdJournals.UI.MainPanel:sendAbsorbSkill(skillName, xp)
    local journalId = self.journal:getID()
    if isClient() and not isServer() then
        sendClientCommand(self.player, "BurdJournals", "absorbSkill", {
            journalId = journalId,
            skillName = skillName
        })
    else
        self:applySkillXPDirectly(skillName, xp)
    end
end

-- Send trait absorption command to server (actual application)
function BurdJournals.UI.MainPanel:sendAbsorbTrait(traitId)
    local journalId = self.journal:getID()
    if isClient() and not isServer() then
        sendClientCommand(self.player, "BurdJournals", "absorbTrait", {
            journalId = journalId,
            traitId = traitId
        })
    else
        self:applyTraitDirectly(traitId)
    end
end

-- ==================== CLAIM FUNCTIONS (for Player Journals - SET mode) ====================

-- Send skill claim command to server (SET mode - for player journals)
function BurdJournals.UI.MainPanel:sendClaimSkill(skillName, recordedXP)
    local journalId = self.journal:getID()

    -- Track as pending claim for immediate UI feedback
    if not self.pendingClaims then self.pendingClaims = {skills = {}, traits = {}} end
    self.pendingClaims.skills[skillName] = true

    if isClient() and not isServer() then
        sendClientCommand(self.player, "BurdJournals", "claimSkill", {
            journalId = journalId,
            skillName = skillName
        })
    else
        self:applySkillXPSetMode(skillName, recordedXP)
    end
end

-- Send trait claim command to server (for player journals)
function BurdJournals.UI.MainPanel:sendClaimTrait(traitId)
    local journalId = self.journal:getID()

    -- Track as pending claim for immediate UI feedback
    if not self.pendingClaims then self.pendingClaims = {skills = {}, traits = {}} end
    self.pendingClaims.traits[traitId] = true

    if isClient() and not isServer() then
        sendClientCommand(self.player, "BurdJournals", "claimTrait", {
            journalId = journalId,
            traitId = traitId
        })
    else
        self:applyTraitDirectly(traitId)
    end
end

-- Apply skill XP in SET mode (single player fallback)
function BurdJournals.UI.MainPanel:applySkillXPSetMode(skillName, recordedXP)
    local perk = BurdJournals.getPerkByName(skillName)
    if not perk then
        return
    end
    
    local playerXP = self.player:getXp():getXP(perk)
    if recordedXP > playerXP then
        -- SET mode: Set to recorded XP level
        local xpDiff = recordedXP - playerXP
        
        -- Use sendAddXp for authoritative XP application
        if sendAddXp then
            sendAddXp(self.player, perk, xpDiff, true)
        else
            self.player:getXp():AddXP(perk, xpDiff, true, true)
        end
        
        local displayName = BurdJournals.getPerkDisplayName(skillName)
        self:showFeedback("Set " .. displayName .. " to recorded level", {r=0.5, g=0.8, b=0.9})
    else
        self:showFeedback("Already at or above this level", {r=0.7, g=0.7, b=0.5})
    end
end

-- ==================== PUBLIC ABSORB FUNCTIONS (now start learning) ====================

function BurdJournals.UI.MainPanel:absorbSkill(skillName, xp)
    -- If already learning (but not Absorb All), add to queue
    if self.learningState.active and not self.learningState.isAbsorbAll then
        if self:addToQueue("skill", skillName, xp) then
            self:showFeedback("Queued: " .. (BurdJournals.getPerkDisplayName(skillName) or skillName), {r=0.7, g=0.8, b=0.9})
        else
            self:showFeedback("Already queued", {r=0.9, g=0.7, b=0.3})
        end
        return
    end
    
    -- Start learning instead of immediate absorption
    if not self:startLearningSkill(skillName, xp) then
        self:showFeedback("Already reading...", {r=0.9, g=0.7, b=0.3})
    end
end

function BurdJournals.UI.MainPanel:absorbTrait(traitId)
    -- If already learning (but not Absorb All), add to queue
    if self.learningState.active and not self.learningState.isAbsorbAll then
        if self:addToQueue("trait", traitId) then
            local traitName = safeGetTraitName(traitId)
            self:showFeedback("Queued: " .. traitName, {r=0.9, g=0.8, b=0.6})
        else
            self:showFeedback("Already queued", {r=0.9, g=0.7, b=0.3})
        end
        return
    end
    
    -- Start learning instead of immediate absorption
    if not self:startLearningTrait(traitId) then
        self:showFeedback("Already reading...", {r=0.9, g=0.7, b=0.3})
    end
end

-- Add a reward to the queue
function BurdJournals.UI.MainPanel:addToQueue(rewardType, name, xp)
    -- Check if already in queue or currently learning
    if self.learningState.skillName == name or self.learningState.traitId == name then
        return false  -- Already learning this one
    end
    
    for _, queued in ipairs(self.learningState.queue) do
        if queued.name == name then
            return false  -- Already in queue
        end
    end
    
    -- Add to queue
    table.insert(self.learningState.queue, {
        type = rewardType,
        name = name,
        xp = xp
    })
    
    -- Play queue sound
    self:playSound(BurdJournals.Sounds.QUEUE_ADD)
    
    return true
end

-- Check if a reward is in the queue (returns position or nil)
function BurdJournals.UI.MainPanel:getQueuePosition(name)
    for i, queued in ipairs(self.learningState.queue) do
        if queued.name == name then
            return i
        end
    end
    return nil
end

-- Remove from queue
function BurdJournals.UI.MainPanel:removeFromQueue(name)
    for i, queued in ipairs(self.learningState.queue) do
        if queued.name == name then
            table.remove(self.learningState.queue, i)
            return true
        end
    end
    return false
end

-- ==================== RECORDING QUEUE FUNCTIONS ====================

-- Add to recording queue
function BurdJournals.UI.MainPanel:addToRecordQueue(recordType, name, xp, level)
    if not self.recordingState then return false end
    if not self.recordingState.queue then
        self.recordingState.queue = {}
    end
    
    -- Check if already recording this one
    if self.recordingState.skillName == name or self.recordingState.traitId == name then
        return false
    end
    
    -- Check if already in queue
    for _, queued in ipairs(self.recordingState.queue) do
        if queued.name == name then
            return false
        end
    end
    
    -- Add to queue
    table.insert(self.recordingState.queue, {
        type = recordType,
        name = name,
        xp = xp,
        level = level
    })
    
    -- Play queue sound
    self:playSound(BurdJournals.Sounds.QUEUE_ADD)
    
    return true
end

-- Check if a record is in the queue (returns position or nil)
function BurdJournals.UI.MainPanel:getRecordQueuePosition(name)
    if not self.recordingState or not self.recordingState.queue then return nil end
    for i, queued in ipairs(self.recordingState.queue) do
        if queued.name == name then
            return i
        end
    end
    return nil
end

function BurdJournals.UI.MainPanel:applySkillXPDirectly(skillName, xp)
    -- Refresh player reference
    self:refreshPlayer()

    local perk = BurdJournals.getPerkByName(skillName)
    if perk and xp and xp > 0 then
        local journalMultiplier = BurdJournals.getSandboxOption("JournalXPMultiplier") or 1.0
        local xpToApply = xp * journalMultiplier

        -- Check if this is a passive skill (Fitness/Strength) - they need MUCH more XP
        local isPassiveSkill = (skillName == "Fitness" or skillName == "Strength")
        if isPassiveSkill then
            -- Passive skills need ~10x more XP per level than regular skills
            -- Scale up the XP to make journal rewards meaningful
            xpToApply = xpToApply * 5
        end

        local xpObj = self.player:getXp()
        local beforeXP = xpObj:getXP(perk)

        -- Use sendAddXp if available (proper game function), otherwise fall back to AddXP
        if sendAddXp then
            sendAddXp(self.player, perk, xpToApply, true)
        else
        xpObj:AddXP(perk, xpToApply, true, true)
        end

        local afterXP = xpObj:getXP(perk)
        local actualGain = afterXP - beforeXP

        -- Debug output for passive skills
        if isPassiveSkill then
        end

        if actualGain > 0 then
            BurdJournals.claimSkill(self.journal, skillName)
            self:showFeedback("+" .. BurdJournals.formatXP(actualGain) .. " " .. BurdJournals.getPerkDisplayName(skillName), {r=0.5, g=0.8, b=0.5})
        else
            self:showFeedback("Skill already maxed!", {r=0.7, g=0.5, b=0.3})
        end

        self:refreshAbsorptionList()
        self:checkDissolution()
    end
end

function BurdJournals.UI.MainPanel:applyTraitDirectly(traitId)
    -- Use the stored player reference
    local player = self.player

    if not player then
        self:showFeedback("No player!", {r=0.8, g=0.3, b=0.3})
        return
    end

    -- Check if already has the trait (uses safe B42 method)
    if BurdJournals.playerHasTrait(player, traitId) then
        self:showFeedback("Trait already known!", {r=0.7, g=0.5, b=0.3})
        return
    end

    -- Use the new safe B42-compatible trait addition
    if BurdJournals.safeAddTrait(player, traitId) then
        BurdJournals.claimTrait(self.journal, traitId)
        local traitName = safeGetTraitName(traitId)
        self:showFeedback("Gained trait: " .. traitName, {r=0.9, g=0.75, b=0.5})
    else
        self:showFeedback("Failed to add trait!", {r=0.8, g=0.3, b=0.3})
    end

    self:refreshAbsorptionList()
    self:checkDissolution()
end

function BurdJournals.UI.MainPanel:showFeedback(text, color)
    if self.feedbackLabel then
        self.feedbackLabel:setName(text)
        self.feedbackLabel:setColor(color.r, color.g, color.b)
        self.feedbackLabel:setVisible(true)
        self.feedbackTicks = 120
    end
end

-- ==================== SOUND EFFECTS ====================

-- Play a sound effect (uses vanilla PZ sounds)
-- soundData can be a string (legacy) or a table with {ui=..., world=...}
function BurdJournals.UI.MainPanel:playSound(soundData)
    if not soundData then return end
    
    -- Handle legacy string format
    local uiSound, worldSound
    if type(soundData) == "string" then
        worldSound = soundData
    elseif type(soundData) == "table" then
        uiSound = soundData.ui
        worldSound = soundData.world
    else
        return
    end
    
    -- Play UI sound first (instant, guaranteed to work in UI context)
    if uiSound and getSoundManager then
        pcall(function()
            getSoundManager():playUISound(uiSound)
        end)
    end
    
    -- Also play world sound if player exists (for immersion)
    if worldSound and self.player then
        pcall(function()
            self.player:playSound(worldSound)
        end)
    end
end

function BurdJournals.UI.MainPanel:checkDissolution()
    if BurdJournals.shouldDissolve(self.journal) then
        local container = self.journal:getContainer()
        if container then container:Remove(self.journal) end
        self.player:getInventory():Remove(self.journal)

        local dissolveMsg = BurdJournals.getRandomDissolutionMessage()
        pcall(function()
            -- Show as player speech (character says the message)
            self.player:Say(dissolveMsg)
        end)
        
        -- Play dissolution sound
        self:playSound(BurdJournals.Sounds.DISSOLVE)
        
        self:onClose()
    end
end

-- ==================== UPDATE (for feedback timer) ====================

function BurdJournals.UI.MainPanel:update()
    ISPanel.update(self)

    if self.feedbackTicks and self.feedbackTicks > 0 then
        self.feedbackTicks = self.feedbackTicks - 1
        if self.feedbackTicks <= 0 and self.feedbackLabel then
            self.feedbackLabel:setVisible(false)
        end
    end
end

-- ==================== CLOSE ====================

function BurdJournals.UI.MainPanel:onClose()
    -- Skip confirmation if learning just completed successfully
    if self.learningCompleted then
        self:doClose()
        return
    end
    
    -- Skip confirmation if we're in the middle of processing the queue
    if self.processingQueue then
        self:doClose()
        return
    end
    
    -- Check if learning is active
    if self.learningState and self.learningState.active then
        -- Show confirmation dialog
        self:showCloseConfirmDialog()
        return
    end
    
    self:doClose()
end

-- Actually close the panel
function BurdJournals.UI.MainPanel:doClose()
    -- Cancel any active learning
    if self.learningState and self.learningState.active then
        self:cancelLearning()
    end
    
    -- Close any open confirmation dialog
    if self.confirmDialog then
        pcall(function()
            self.confirmDialog:setVisible(false)
            self.confirmDialog:removeFromUIManager()
        end)
        self.confirmDialog = nil
    end
    
    self:setVisible(false)
    self:removeFromUIManager()
    BurdJournals.UI.MainPanel.instance = nil
end

-- Show confirmation dialog when closing mid-learning
function BurdJournals.UI.MainPanel:showCloseConfirmDialog()
    -- If dialog already open, don't create another
    if self.confirmDialog then
        return
    end
    
    -- Create a simple modal dialog
    local dialogW = 280
    local dialogH = 120
    local dialogX = (getCore():getScreenWidth() - dialogW) / 2
    local dialogY = (getCore():getScreenHeight() - dialogH) / 2
    
    local dialog = ISPanel:new(dialogX, dialogY, dialogW, dialogH)
    dialog:initialise()
    dialog:instantiate()
    dialog.backgroundColor = {r=0.15, g=0.15, b=0.15, a=0.98}
    dialog.borderColor = {r=0.6, g=0.5, b=0.3, a=1}
    dialog.moveWithMouse = true
    dialog.mainPanel = self
    
    -- Store reference so we can close it if learning completes
    self.confirmDialog = dialog
    
    -- Warning text
    local warningLabel = ISLabel:new(dialogW/2, 20, 20, "You are still reading!", 1, 0.9, 0.7, 1, UIFont.Medium, true)
    dialog:addChild(warningLabel)
    
    local subLabel = ISLabel:new(dialogW/2, 44, 16, "Cancel learning and close?", 0.8, 0.75, 0.65, 1, UIFont.Small, true)
    dialog:addChild(subLabel)
    
    -- Keep Reading button
    local btnW = 100
    local btnH = 28
    local btnSpacing = 20
    local btnStartX = (dialogW - btnW * 2 - btnSpacing) / 2
    local btnY = 75
    
    -- Store references for button callbacks
    local dialogRef = dialog
    local mainPanelRef = self
    
    local keepBtn = ISButton:new(btnStartX, btnY, btnW, btnH, "Keep Reading", dialog, function(btn)
        -- Close the dialog, keep reading
        if mainPanelRef then
            mainPanelRef.confirmDialog = nil
        end
        if dialogRef then
            dialogRef:setVisible(false)
            dialogRef:removeFromUIManager()
        end
    end)
    keepBtn:initialise()
    keepBtn:instantiate()
    keepBtn.borderColor = {r=0.4, g=0.6, b=0.4, a=1}
    keepBtn.backgroundColor = {r=0.2, g=0.3, b=0.2, a=0.9}
    keepBtn.textColor = {r=0.9, g=1, b=0.9, a=1}
    dialog:addChild(keepBtn)
    
    -- Cancel & Close button
    local closeBtn = ISButton:new(btnStartX + btnW + btnSpacing, btnY, btnW, btnH, "Cancel & Close", dialog, function(btn)
        -- Clear reference first
        if mainPanelRef then
            mainPanelRef.confirmDialog = nil
        end
        -- Close the dialog
        if dialogRef then
            dialogRef:setVisible(false)
            dialogRef:removeFromUIManager()
        end
        -- Then close the main panel
        if mainPanelRef then
            mainPanelRef:doClose()
        end
    end)
    closeBtn:initialise()
    closeBtn:instantiate()
    closeBtn.borderColor = {r=0.6, g=0.3, b=0.3, a=1}
    closeBtn.backgroundColor = {r=0.35, g=0.15, b=0.15, a=0.9}
    closeBtn.textColor = {r=1, g=0.85, b=0.85, a=1}
    dialog:addChild(closeBtn)
    
    dialog:addToUIManager()
    dialog:bringToTop()
end

-- ==================== STATIC SHOW FUNCTION ====================

function BurdJournals.UI.MainPanel.show(player, journal, mode)
    if BurdJournals.UI.MainPanel.instance then
        BurdJournals.UI.MainPanel.instance:onClose()
    end

    local width = 360
    
    -- Calculate dynamic height based on content
    local baseHeight = 180  -- Header + author + footer
    local itemHeight = 52   -- Height per skill/trait row
    local headerRowHeight = 52  -- Height for section headers
    local minHeight = 420   -- Show about 4-5 items
    local maxHeight = 550   -- Cap the max height to prevent it from getting too tall
    
    -- Count items for height calculation
    local journalData = BurdJournals.getJournalData(journal)
    local hasBloodyOrigin = BurdJournals.hasBloodyOrigin(journal)
    local skillCount = 0
    local traitCount = 0
    
    -- For log mode (recording), count player's skills instead
    if mode == "log" then
        local allowedSkills = BurdJournals.getAllowedSkills()
        if allowedSkills then
            for _, skillName in ipairs(allowedSkills) do
                local perk = BurdJournals.getPerkByName(skillName)
                if perk then
                    local currentXP = player:getXp():getXP(perk)
                    local currentLevel = player:getPerkLevel(perk)
                    if currentXP > 0 or currentLevel > 0 then
                        skillCount = skillCount + 1
                    end
                end
            end
        end
    else
        if journalData and journalData.skills then
            for _ in pairs(journalData.skills) do
                skillCount = skillCount + 1
            end
        end
    end
    
    if hasBloodyOrigin and journalData and journalData.traits then
        for _ in pairs(journalData.traits) do
            traitCount = traitCount + 1
        end
    end
    
    -- Calculate ideal height: base + skills header + skills + traits header (if any) + traits
    local contentHeight = baseHeight
    contentHeight = contentHeight + headerRowHeight  -- Skills header
    contentHeight = contentHeight + (skillCount * itemHeight)
    if traitCount > 0 then
        contentHeight = contentHeight + headerRowHeight  -- Traits header
        contentHeight = contentHeight + (traitCount * itemHeight)
    end
    
    -- Clamp to min/max
    local height = math.max(minHeight, math.min(maxHeight, contentHeight))
    
    local x = (getCore():getScreenWidth() - width) / 2
    local y = (getCore():getScreenHeight() - height) / 2

    local panel = BurdJournals.UI.MainPanel:new(x, y, width, height, player, journal, mode)
    panel:initialise()
    panel:addToUIManager()
    BurdJournals.UI.MainPanel.instance = panel

    return panel
end

-- ==================== LOG UI (Recording Progress) ====================

function BurdJournals.UI.MainPanel:createLogUI()
    self:refreshPlayer()
    
    local padding = 16
    local y = 0
    local btnHeight = 32
    
    -- Recording state (similar to learning state)
    self.recordingState = {
        active = false,
        skillName = nil,
        traitId = nil,
        isRecordAll = false,
        progress = 0,
        totalTime = 0,
        startTime = 0,
        pendingRecords = {},
        currentIndex = 0,
        queue = {},
    }
    self.recordingCompleted = false
    self.processingRecordQueue = false
    
    -- Get journal data
    local journalData = BurdJournals.getJournalData(self.journal) or {}
    local recordedSkills = journalData.skills or {}
    local recordedTraits = journalData.traits or {}
    
    -- Store for rendering
    self.isRecordMode = true
    self.recordedSkills = recordedSkills
    self.recordedTraits = recordedTraits
    
    -- ============ HEADER STYLING (Blue/Teal for personal journals) ============
    local headerHeight = 52
    self.headerColor = {r=0.12, g=0.25, b=0.35}
    self.headerAccent = {r=0.2, g=0.45, b=0.55}
    self.typeText = "RECORD PROGRESS"
    self.rarityText = nil
    self.flavorText = "Document your survival skills..."
    self.headerHeight = headerHeight
    y = headerHeight + 6
    
    -- ============ AUTHOR INFO BOX ============
    local playerName = self.player:getDescriptor():getForename() .. " " .. self.player:getDescriptor():getSurname()
    self.authorName = playerName
    self.authorBoxY = y
    self.authorBoxHeight = 44
    y = y + self.authorBoxHeight + 10
    
    -- ============ SKILL LIST ============
    local footerHeight = 85
    local listHeight = self.height - y - footerHeight - padding
    
    self.skillList = ISScrollingListBox:new(padding, y, self.width - padding * 2, listHeight)
    self.skillList:initialise()
    self.skillList:instantiate()
    self.skillList.drawBorder = false
    self.skillList.backgroundColor = {r=0, g=0, b=0, a=0}
    self.skillList:setFont(UIFont.Small, 2)
    self.skillList.itemheight = 52
    self.skillList.doDrawItem = BurdJournals.UI.MainPanel.doDrawRecordItem
    self.skillList.mainPanel = self
    
    -- Click handling for RECORD buttons
    self.skillList.onMouseUp = function(listbox, x, y)
        if listbox.vscroll then
            listbox.vscroll.scrolling = false
        end
        local ok, err = pcall(function()
            local row = listbox:rowAt(x, y)
            if row and row >= 1 and row <= #listbox.items then
                local item = listbox.items[row] and listbox.items[row].item
                if item and not item.isHeader and not item.isEmpty then
                    local btnAreaStart = listbox:getWidth() - 80
                    if x >= btnAreaStart then
                        if item.isSkill then
                            listbox.mainPanel:recordSkill(item.skillName, item.xp, item.level)
                        elseif item.isTrait then
                            listbox.mainPanel:recordTrait(item.traitId)
                        end
                    end
                end
            end
        end)
        if not ok then
            print("[BurdJournals] Record UI Click error: " .. tostring(err))
        end
        return true
    end
    self:addChild(self.skillList)
    y = y + listHeight
    
    -- ============ FOOTER ============
    self.footerY = y + 4
    self.footerHeight = footerHeight
    
    -- Feedback label
    self.feedbackLabel = ISLabel:new(padding, self.footerY + 4, 18, "", 0.7, 0.9, 0.7, 1, UIFont.Small, true)
    self:addChild(self.feedbackLabel)
    self.feedbackLabel:setVisible(false)
    self.feedbackTicks = 0
    
    -- Footer buttons
    local btnWidth = 110
    local btnSpacing = 12
    local totalBtnWidth = btnWidth * 2 + btnSpacing
    local btnStartX = (self.width - totalBtnWidth) / 2
    local btnY = self.footerY + 32
    
    -- Record All button
    self.recordAllBtn = ISButton:new(btnStartX, btnY, btnWidth, btnHeight, "Record All", self, BurdJournals.UI.MainPanel.onRecordAll)
    self.recordAllBtn:initialise()
    self.recordAllBtn:instantiate()
    self.recordAllBtn.borderColor = {r=0.3, g=0.5, b=0.6, a=1}
    self.recordAllBtn.backgroundColor = {r=0.15, g=0.28, b=0.35, a=0.8}
    self.recordAllBtn.textColor = {r=1, g=1, b=1, a=1}
    self:addChild(self.recordAllBtn)
    
    -- Close button
    self.closeBottomBtn = ISButton:new(btnStartX + btnWidth + btnSpacing, btnY, btnWidth, btnHeight, "Close", self, BurdJournals.UI.MainPanel.onClose)
    self.closeBottomBtn:initialise()
    self.closeBottomBtn:instantiate()
    self.closeBottomBtn.borderColor = {r=0.4, g=0.35, b=0.3, a=1}
    self.closeBottomBtn.backgroundColor = {r=0.15, g=0.13, b=0.12, a=0.8}
    self.closeBottomBtn.textColor = {r=0.9, g=0.85, b=0.8, a=1}
    self:addChild(self.closeBottomBtn)
    
    -- Populate the list
    self:populateRecordList()
end

-- Populate the record list with player's current skills and traits
function BurdJournals.UI.MainPanel:populateRecordList()
    self.skillList:clear()

    -- CRITICAL: Re-read journal data to get latest recorded skills/traits
    -- This ensures the UI reflects server-synced data after recording
    local journalData = BurdJournals.getJournalData(self.journal) or {}
    self.recordedSkills = journalData.skills or {}
    self.recordedTraits = journalData.traits or {}

    local allowedSkills = BurdJournals.getAllowedSkills()
    local recordedSkills = self.recordedSkills
    local recordedTraits = self.recordedTraits
    
    -- Count recordable skills
    local recordableCount = 0
    for _, skillName in ipairs(allowedSkills) do
        local perk = BurdJournals.getPerkByName(skillName)
        if perk then
            local currentXP = self.player:getXp():getXP(perk)
            local currentLevel = self.player:getPerkLevel(perk)
            local recordedData = recordedSkills[skillName]
            local recordedXP = recordedData and recordedData.xp or 0
            
            -- Count if player has progress OR if player's is higher than recorded
            if currentXP > 0 or currentLevel > 0 then
                if currentXP > recordedXP then
                    recordableCount = recordableCount + 1
                end
            end
        end
    end
    
    -- Add skills header
    self.skillList:addItem("SKILLS", {isHeader = true, text = "YOUR SKILLS", count = recordableCount})
    
    -- Add skill rows
    local hasSkills = false
    for _, skillName in ipairs(allowedSkills) do
        local perk = BurdJournals.getPerkByName(skillName)
        if perk then
            local currentXP = self.player:getXp():getXP(perk)
            local currentLevel = self.player:getPerkLevel(perk)
            
            -- Only show skills where player has some progress
            if currentXP > 0 or currentLevel > 0 then
                hasSkills = true
                local displayName = BurdJournals.getPerkDisplayName(skillName)
                local recordedData = recordedSkills[skillName]
                local recordedXP = recordedData and recordedData.xp or 0
                local recordedLevel = recordedData and recordedData.level or 0
                local canRecord = currentXP > recordedXP
                
                self.skillList:addItem(skillName, {
                    isSkill = true,
                    skillName = skillName,
                    displayName = displayName,
                    xp = currentXP,
                    level = currentLevel,
                    recordedXP = recordedXP,
                    recordedLevel = recordedLevel,
                    isRecorded = recordedXP > 0,
                    canRecord = canRecord,
                })
            end
        end
    end
    
    if not hasSkills then
        self.skillList:addItem("empty", {isEmpty = true, text = "No skills to record yet"})
    end
    
    -- Add traits section
    local playerTraits = BurdJournals.collectPlayerTraits(self.player)
    local positiveTraits = {}
    for traitId, traitData in pairs(playerTraits) do
        -- Only show positive traits (those that can be granted)
        if BurdJournals.tableContains(BurdJournals.GRANTABLE_TRAITS, traitId) or
           BurdJournals.tableContains(BurdJournals.GRANTABLE_TRAITS, string.lower(traitId)) then
            positiveTraits[traitId] = traitData
        end
    end
    
    local traitCount = BurdJournals.countTable(positiveTraits)
    if traitCount > 0 then
        -- Count recordable traits
        local recordableTraitCount = 0
        for traitId, _ in pairs(positiveTraits) do
            if not recordedTraits[traitId] then
                recordableTraitCount = recordableTraitCount + 1
            end
        end
        
        self.skillList:addItem("TRAITS", {isHeader = true, text = "YOUR TRAITS", count = recordableTraitCount})
        
        for traitId, traitData in pairs(positiveTraits) do
            local traitName = safeGetTraitName(traitId)
            local traitTexture = getTraitTexture(traitId)
            local isRecorded = recordedTraits[traitId] ~= nil
            
            self.skillList:addItem(traitId, {
                isTrait = true,
                traitId = traitId,
                traitName = traitName,
                traitTexture = traitTexture,
                isRecorded = isRecorded,
                canRecord = not isRecorded,
            })
        end
    end
end

-- Draw function for record items
function BurdJournals.UI.MainPanel.doDrawRecordItem(self, y, item, alt)
    local mainPanel = self.mainPanel
    if not mainPanel then return y + self.itemheight end
    
    local data = item.item or {}
    local x = 0
    local w = self:getWidth()
    local h = self.itemheight
    local padding = 12
    
    -- Blue/teal theme for recording
    local cardBg = {r=0.12, g=0.16, b=0.20}
    local cardBorder = {r=0.25, g=0.38, b=0.45}
    local accentColor = {r=0.3, g=0.55, b=0.65}
    
    -- ============ HEADER ROW ============
    if data.isHeader then
        self:drawRect(x, y + 2, w, h - 4, 0.4, 0.12, 0.18, 0.22)
        self:drawText(data.text or "YOUR SKILLS", x + padding, y + (h - 18) / 2, 0.7, 0.9, 1.0, 1, UIFont.Medium)
        if data.count then
            local countText = "(" .. data.count .. " recordable)"
            local countWidth = getTextManager():MeasureStringX(UIFont.Small, countText)
            self:drawText(countText, w - padding - countWidth, y + (h - 14) / 2, 0.4, 0.6, 0.7, 1, UIFont.Small)
        end
        return y + h
    end
    
    -- ============ EMPTY ROW ============
    if data.isEmpty then
        self:drawText(data.text or "Nothing to record", x + padding, y + (h - 14) / 2, 0.4, 0.5, 0.55, 1, UIFont.Small)
        return y + h
    end
    
    -- ============ SKILL/TRAIT CARD ============
    local cardMargin = 4
    local cardX = x + cardMargin
    local cardY = y + cardMargin
    local cardW = w - cardMargin * 2
    local cardH = h - cardMargin * 2
    
    -- Card background
    if data.isRecorded and not data.canRecord then
        self:drawRect(cardX, cardY, cardW, cardH, 0.4, 0.12, 0.15, 0.12)
    else
        self:drawRect(cardX, cardY, cardW, cardH, 0.7, cardBg.r, cardBg.g, cardBg.b)
    end
    
    -- Card border
    self:drawRectBorder(cardX, cardY, cardW, cardH, 0.6, cardBorder.r, cardBorder.g, cardBorder.b)
    
    -- Left accent bar (green if can record, gray if already recorded at max)
    if data.canRecord then
        self:drawRect(cardX, cardY, 4, cardH, 0.9, 0.3, 0.7, 0.4)
    else
        self:drawRect(cardX, cardY, 4, cardH, 0.5, 0.3, 0.35, 0.3)
    end
    
    local textX = cardX + padding + 4
    local textColor = data.canRecord and {r=0.95, g=0.95, b=1.0} or {r=0.5, g=0.55, b=0.5}
    
    -- ============ SKILL ROW ============
    if data.isSkill then
        -- Check if recording this skill
        local recordingState = mainPanel.recordingState
        local isRecordingThis = recordingState and recordingState.active and not recordingState.isRecordAll
                               and recordingState.skillName == data.skillName
        
        -- Skill name
        local displayName = data.displayName or data.skillName or "Unknown Skill"
        self:drawText(displayName .. " (Lv." .. data.level .. ")", textX, cardY + 6, textColor.r, textColor.g, textColor.b, 1, UIFont.Small)
        
        -- Show recording progress or status
        if isRecordingThis then
            local progressText = string.format("Recording... %d%%", math.floor(recordingState.progress * 100))
            self:drawText(progressText, textX, cardY + 22, 0.3, 0.8, 0.5, 1, UIFont.Small)
            
            -- Progress bar
            local barX = textX + 100
            local barY = cardY + 25
            local barW = cardW - 130 - padding
            local barH = 10
            self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)
            self:drawRect(barX, barY, barW * recordingState.progress, barH, 0.9, 0.3, 0.7, 0.4)
            self:drawRectBorder(barX, barY, barW, barH, 0.7, 0.4, 0.8, 0.5)
        else
            -- Show XP info
            local xpText = BurdJournals.formatXP(data.xp) .. " XP"
            if data.isRecorded then
                if data.canRecord then
                    xpText = xpText .. " (was " .. BurdJournals.formatXP(data.recordedXP) .. ")"
                    self:drawText(xpText, textX, cardY + 22, 0.5, 0.8, 0.5, 1, UIFont.Small)
                else
                    xpText = "Recorded: " .. BurdJournals.formatXP(data.recordedXP) .. " XP"
                    self:drawText(xpText, textX, cardY + 22, 0.4, 0.5, 0.4, 1, UIFont.Small)
                end
            else
                self:drawText(xpText, textX, cardY + 22, 0.5, 0.7, 0.8, 1, UIFont.Small)
            end
            
            -- XP progress bar
            local barX = textX + 120
            local barY = cardY + 25
            local barW = 80
            local barH = 8
            local maxXP = 1000
            local fillRatio = math.min(data.xp / maxXP, 1)
            self:drawRect(barX, barY, barW, barH, 0.5, 0.1, 0.1, 0.1)
            self:drawRect(barX, barY, barW * fillRatio, barH, 0.8, accentColor.r, accentColor.g, accentColor.b)
            self:drawRectBorder(barX, barY, barW, barH, 0.4, 0.3, 0.3, 0.3)
        end
        
        -- RECORD/QUEUE button
        if data.canRecord and not isRecordingThis then
            local btnW = 65
            local btnH = 24
            local btnX = cardX + cardW - btnW - 10
            local btnY = cardY + (cardH - btnH) / 2
            
            -- Check if in queue
            local queuePosition = mainPanel:getRecordQueuePosition(data.skillName)
            local isQueued = queuePosition ~= nil
            
            if isQueued then
                -- Show queue position indicator
                self:drawRect(btnX, btnY, btnW, btnH, 0.5, 0.3, 0.4, 0.5)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.6, 0.4, 0.5, 0.6)
                local btnText = "#" .. queuePosition
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.8, 0.9, 1, 1, UIFont.Small)
            elseif recordingState and recordingState.active and not recordingState.isRecordAll then
                -- Show QUEUE button when another item is recording
                self:drawRect(btnX, btnY, btnW, btnH, 0.6, 0.25, 0.35, 0.5)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.4, 0.55, 0.7)
                local btnText = "QUEUE"
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.9, 0.95, 1, 1, UIFont.Small)
            else
                -- Normal RECORD button
                self:drawRect(btnX, btnY, btnW, btnH, 0.7, 0.2, 0.45, 0.35)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.3, 0.6, 0.5)
                local btnText = "RECORD"
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 1, 1, 1, 1, UIFont.Small)
            end
        end
    end
    
    -- ============ TRAIT ROW ============
    if data.isTrait then
        local recordingState = mainPanel.recordingState
        local isRecordingThis = recordingState and recordingState.active and not recordingState.isRecordAll
                               and recordingState.traitId == data.traitId
        
        local traitName = data.traitName or data.traitId or "Unknown Trait"
        local traitTextX = textX
        
        -- Draw trait icon if available
        if data.traitTexture then
            local iconSize = 24
            local iconX = textX
            local iconY = cardY + (cardH - iconSize) / 2
            local iconAlpha = data.canRecord and 1.0 or 0.5
            self:drawTextureScaledAspect(data.traitTexture, iconX, iconY, iconSize, iconSize, iconAlpha, 1, 1, 1)
            traitTextX = textX + iconSize + 6
        end
        
        -- Trait name
        local traitColor = data.canRecord and {r=0.8, g=0.9, b=1.0} or {r=0.5, g=0.55, b=0.5}
        self:drawText(traitName, traitTextX, cardY + 6, traitColor.r, traitColor.g, traitColor.b, 1, UIFont.Small)
        
        -- Check if in queue
        local queuePosition = mainPanel:getRecordQueuePosition(data.traitId)
        local isQueued = queuePosition ~= nil
        
        -- Status text
        if isRecordingThis then
            local progressText = string.format("Recording... %d%%", math.floor(recordingState.progress * 100))
            self:drawText(progressText, traitTextX, cardY + 22, 0.3, 0.8, 0.5, 1, UIFont.Small)
        elseif isQueued then
            self:drawText("Queued #" .. queuePosition, traitTextX, cardY + 22, 0.6, 0.75, 0.9, 1, UIFont.Small)
        elseif data.isRecorded then
            self:drawText("Already recorded", traitTextX, cardY + 22, 0.4, 0.5, 0.4, 1, UIFont.Small)
        else
            self:drawText("Your trait", traitTextX, cardY + 22, 0.5, 0.7, 0.8, 1, UIFont.Small)
        end
        
        -- RECORD/QUEUE button
        if data.canRecord and not isRecordingThis then
            local btnW = 65
            local btnH = 24
            local btnX = cardX + cardW - btnW - 10
            local btnY = cardY + (cardH - btnH) / 2
            
            if isQueued then
                -- Show queue position indicator
                self:drawRect(btnX, btnY, btnW, btnH, 0.5, 0.4, 0.35, 0.5)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.6, 0.5, 0.45, 0.6)
                local btnText = "#" .. queuePosition
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.9, 0.85, 0.7, 1, UIFont.Small)
            elseif recordingState and recordingState.active and not recordingState.isRecordAll then
                -- Show QUEUE button when another item is recording
                self:drawRect(btnX, btnY, btnW, btnH, 0.6, 0.4, 0.35, 0.25)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.6, 0.5, 0.35)
                local btnText = "QUEUE"
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 1, 0.95, 0.85, 1, UIFont.Small)
            else
                -- Normal RECORD button
                self:drawRect(btnX, btnY, btnW, btnH, 0.7, 0.35, 0.45, 0.25)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.5, 0.6, 0.4)
                local btnText = "RECORD"
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 1, 1, 0.9, 1, UIFont.Small)
            end
        end
    end
    
    return y + h
end

-- Record All button handler
function BurdJournals.UI.MainPanel:onRecordAll()
    if not self:startRecordingAll() then
        self:showFeedback("Already recording...", {r=0.9, g=0.7, b=0.3})
    end
end

-- ==================== VIEW UI (Viewing/Claiming from Player Journal) ====================

function BurdJournals.UI.MainPanel:createViewUI()
    -- For player journals, we use a modified absorption UI
    -- The main difference is SET mode instead of ADD mode, and no dissolution
    self:refreshPlayer()
    
    local padding = 16
    local y = 0
    local btnHeight = 32
    
    local journalData = BurdJournals.getJournalData(self.journal)

    -- Store for rendering
    self.isPlayerJournal = true
    self.isSetMode = true  -- SET mode for player journals

    -- Track pending claims for immediate UI feedback (before async XP applies)
    -- This allows the UI to show "claimed" immediately while XP is being applied
    self.pendingClaims = self.pendingClaims or {skills = {}, traits = {}}

    -- ============ HEADER STYLING (Blue/Teal for personal journals) ============
    local headerHeight = 52
    self.headerColor = {r=0.12, g=0.25, b=0.35}
    self.headerAccent = {r=0.2, g=0.45, b=0.55}
    self.typeText = "PERSONAL JOURNAL"
    self.rarityText = nil
    self.flavorText = "Your documented survival knowledge..."
    self.headerHeight = headerHeight
    y = headerHeight + 6
    
    -- ============ AUTHOR INFO BOX ============
    local authorName = journalData and journalData.author or "Unknown"
    self.authorName = authorName
    self.authorBoxY = y
    self.authorBoxHeight = 44
    y = y + self.authorBoxHeight + 10
    
    -- ============ COUNT SKILLS AND TRAITS ============
    local skillCount = 0
    local totalSkillCount = 0
    local traitCount = 0
    local totalTraitCount = 0
    local totalXP = 0
    
    if journalData and journalData.skills then
        for skillName, skillData in pairs(journalData.skills) do
            totalSkillCount = totalSkillCount + 1
            -- For SET mode, check if player's XP is below recorded
            local perk = BurdJournals.getPerkByName(skillName)
            local playerXP = 0
            if perk then
                playerXP = self.player:getXp():getXP(perk)
            end
            if playerXP < (skillData.xp or 0) then
                skillCount = skillCount + 1
                totalXP = totalXP + ((skillData.xp or 0) - playerXP)
            end
        end
    end
    if journalData and journalData.traits then
        for traitId, _ in pairs(journalData.traits) do
            totalTraitCount = totalTraitCount + 1
            if not BurdJournals.playerHasTrait(self.player, traitId) then
                traitCount = traitCount + 1
            end
        end
    end
    
    self.skillCount = skillCount
    self.traitCount = traitCount
    self.totalXP = totalXP
    
    -- ============ SKILL LIST ============
    local footerHeight = 85
    local listHeight = self.height - y - footerHeight - padding
    
    self.skillList = ISScrollingListBox:new(padding, y, self.width - padding * 2, listHeight)
    self.skillList:initialise()
    self.skillList:instantiate()
    self.skillList.drawBorder = false
    self.skillList.backgroundColor = {r=0, g=0, b=0, a=0}
    self.skillList:setFont(UIFont.Small, 2)
    self.skillList.itemheight = 52
    self.skillList.doDrawItem = BurdJournals.UI.MainPanel.doDrawViewItem
    self.skillList.mainPanel = self
    
    -- Click handling
    self.skillList.onMouseUp = function(listbox, x, y)
        if listbox.vscroll then
            listbox.vscroll.scrolling = false
        end
        local ok, err = pcall(function()
            local row = listbox:rowAt(x, y)
            if row and row >= 1 and row <= #listbox.items then
                local item = listbox.items[row] and listbox.items[row].item
                if item and not item.isHeader and not item.isEmpty then
                    local btnAreaStart = listbox:getWidth() - 80
                    if x >= btnAreaStart then
                        if item.isSkill and item.canClaim then
                            listbox.mainPanel:claimSkill(item.skillName, item.xp)
                        elseif item.isTrait and not item.alreadyKnown then
                            listbox.mainPanel:claimTrait(item.traitId)
                        end
                    end
                end
            end
        end)
        if not ok then
            print("[BurdJournals] View UI Click error: " .. tostring(err))
        end
        return true
    end
    self:addChild(self.skillList)
    y = y + listHeight
    
    -- ============ FOOTER ============
    self.footerY = y + 4
    self.footerHeight = footerHeight
    
    -- Feedback label
    self.feedbackLabel = ISLabel:new(padding, self.footerY + 4, 18, "", 0.7, 0.9, 0.7, 1, UIFont.Small, true)
    self:addChild(self.feedbackLabel)
    self.feedbackLabel:setVisible(false)
    self.feedbackTicks = 0
    
    -- Footer buttons
    local btnWidth = 110
    local btnSpacing = 12
    local totalBtnWidth = btnWidth * 2 + btnSpacing
    local btnStartX = (self.width - totalBtnWidth) / 2
    local btnY = self.footerY + 32
    
    -- Claim All button
    self.absorbAllBtn = ISButton:new(btnStartX, btnY, btnWidth, btnHeight, "Claim All", self, BurdJournals.UI.MainPanel.onClaimAll)
    self.absorbAllBtn:initialise()
    self.absorbAllBtn:instantiate()
    self.absorbAllBtn.borderColor = {r=0.3, g=0.5, b=0.6, a=1}
    self.absorbAllBtn.backgroundColor = {r=0.15, g=0.28, b=0.35, a=0.8}
    self.absorbAllBtn.textColor = {r=1, g=1, b=1, a=1}
    self:addChild(self.absorbAllBtn)
    
    -- Close button
    self.closeBottomBtn = ISButton:new(btnStartX + btnWidth + btnSpacing, btnY, btnWidth, btnHeight, "Close", self, BurdJournals.UI.MainPanel.onClose)
    self.closeBottomBtn:initialise()
    self.closeBottomBtn:instantiate()
    self.closeBottomBtn.borderColor = {r=0.4, g=0.35, b=0.3, a=1}
    self.closeBottomBtn.backgroundColor = {r=0.15, g=0.13, b=0.12, a=0.8}
    self.closeBottomBtn.textColor = {r=0.9, g=0.85, b=0.8, a=1}
    self:addChild(self.closeBottomBtn)
    
    -- Populate the list
    self:populateViewList()
end

-- Populate the view list with recorded skills and traits
function BurdJournals.UI.MainPanel:populateViewList()
    self.skillList:clear()

    local journalData = BurdJournals.getJournalData(self.journal)

    -- Ensure pendingClaims exists
    if not self.pendingClaims then self.pendingClaims = {skills = {}, traits = {}} end

    -- Count claimable skills
    -- For player journals (view mode): skill is claimable if player XP < recorded XP
    -- AND not pending (waiting for async XP to apply)
    local claimableCount = 0
    if journalData and journalData.skills then
        for skillName, skillData in pairs(journalData.skills) do
            local perk = BurdJournals.getPerkByName(skillName)
            if perk then
                local playerXP = self.player:getXp():getXP(perk)
                local recordedXP = skillData.xp or 0
                local isPending = self.pendingClaims.skills[skillName]

                -- Clear pending flag if XP has been applied
                if isPending and playerXP >= recordedXP then
                    self.pendingClaims.skills[skillName] = nil
                    isPending = false
                end

                -- Claimable if player XP is below recorded AND not pending
                if playerXP < recordedXP and not isPending then
                    claimableCount = claimableCount + 1
                end
            end
        end
    end

    -- Add skills header
    self.skillList:addItem("SKILLS", {isHeader = true, text = "RECORDED SKILLS", count = claimableCount})

    -- Add skill rows
    if journalData and journalData.skills then
        local hasSkills = false
        for skillName, skillData in pairs(journalData.skills) do
            hasSkills = true
            local displayName = BurdJournals.getPerkDisplayName(skillName)
            local perk = BurdJournals.getPerkByName(skillName)
            local playerXP = 0
            local playerLevel = 0
            if perk then
                playerXP = self.player:getXp():getXP(perk)
                playerLevel = self.player:getPerkLevel(perk)
            end

            local recordedXP = skillData.xp or 0
            local isPending = self.pendingClaims.skills[skillName]

            -- Clear pending flag if XP has been applied
            if isPending and playerXP >= recordedXP then
                self.pendingClaims.skills[skillName] = nil
                isPending = false
            end

            -- For player journals: canClaim if player XP < recorded AND not pending
            -- isPending means we just claimed it and are waiting for async XP
            local canClaim = playerXP < recordedXP and not isPending

            self.skillList:addItem(skillName, {
                isSkill = true,
                skillName = skillName,
                displayName = displayName,
                xp = skillData.xp or 0,
                level = skillData.level or 0,
                playerXP = playerXP,
                playerLevel = playerLevel,
                canClaim = canClaim,
                isPending = isPending,  -- For UI to show "claimed" state
            })
        end
        if not hasSkills then
            self.skillList:addItem("empty", {isEmpty = true, text = "No skills recorded"})
        end
    else
        self.skillList:addItem("empty", {isEmpty = true, text = "No skills recorded"})
    end

    -- Add traits section
    -- For player journals: trait is claimable if player doesn't already have it AND not pending
    if journalData and journalData.traits then
        local traitCount = 0
        for traitId, _ in pairs(journalData.traits) do
            local alreadyKnown = BurdJournals.playerHasTrait(self.player, traitId)
            local isPending = self.pendingClaims.traits[traitId]

            -- Clear pending flag if trait has been applied
            if isPending and alreadyKnown then
                self.pendingClaims.traits[traitId] = nil
                isPending = false
            end

            if not alreadyKnown and not isPending then
                traitCount = traitCount + 1
            end
        end

        if BurdJournals.countTable(journalData.traits) > 0 then
            self.skillList:addItem("TRAITS", {isHeader = true, text = "RECORDED TRAITS", count = traitCount})

            for traitId, traitData in pairs(journalData.traits) do
                local traitName = safeGetTraitName(traitId)
                local traitTexture = getTraitTexture(traitId)
                local alreadyKnown = BurdJournals.playerHasTrait(self.player, traitId)
                local isPending = self.pendingClaims.traits[traitId]

                -- Clear pending flag if trait has been applied
                if isPending and alreadyKnown then
                    self.pendingClaims.traits[traitId] = nil
                    isPending = false
                end

                self.skillList:addItem(traitId, {
                    isTrait = true,
                    traitId = traitId,
                    traitName = traitName,
                    traitTexture = traitTexture,
                    alreadyKnown = alreadyKnown,
                    isPending = isPending,  -- For UI to show "claimed" state
                })
            end
        end
    end
end

-- Draw function for view items (claiming from player journal)
function BurdJournals.UI.MainPanel.doDrawViewItem(self, y, item, alt)
    local mainPanel = self.mainPanel
    if not mainPanel then return y + self.itemheight end
    
    local data = item.item or {}
    local x = 0
    local w = self:getWidth()
    local h = self.itemheight
    local padding = 12
    
    -- Blue/teal theme for personal journals
    local cardBg = {r=0.12, g=0.16, b=0.20}
    local cardBorder = {r=0.25, g=0.38, b=0.45}
    local accentColor = {r=0.3, g=0.55, b=0.65}
    
    -- ============ HEADER ROW ============
    if data.isHeader then
        self:drawRect(x, y + 2, w, h - 4, 0.4, 0.12, 0.18, 0.22)
        self:drawText(data.text or "SKILLS", x + padding, y + (h - 18) / 2, 0.7, 0.9, 1.0, 1, UIFont.Medium)
        if data.count then
            local countText = "(" .. data.count .. " claimable)"
            local countWidth = getTextManager():MeasureStringX(UIFont.Small, countText)
            self:drawText(countText, w - padding - countWidth, y + (h - 14) / 2, 0.4, 0.6, 0.7, 1, UIFont.Small)
        end
        return y + h
    end
    
    -- ============ EMPTY ROW ============
    if data.isEmpty then
        self:drawText(data.text or "No content", x + padding, y + (h - 14) / 2, 0.4, 0.5, 0.55, 1, UIFont.Small)
        return y + h
    end
    
    -- ============ SKILL/TRAIT CARD ============
    local cardMargin = 4
    local cardX = x + cardMargin
    local cardY = y + cardMargin
    local cardW = w - cardMargin * 2
    local cardH = h - cardMargin * 2
    
    -- Card background
    -- For player journals: canClaim is based on XP comparison (and not pending), alreadyKnown for traits
    -- isPending means we just claimed it and are waiting for async XP/trait to apply
    local canInteract = (data.isSkill and data.canClaim) or (data.isTrait and not data.alreadyKnown and not data.isPending)
    if not canInteract then
        self:drawRect(cardX, cardY, cardW, cardH, 0.4, 0.12, 0.12, 0.12)
    else
        self:drawRect(cardX, cardY, cardW, cardH, 0.7, cardBg.r, cardBg.g, cardBg.b)
    end
    
    -- Card border
    self:drawRectBorder(cardX, cardY, cardW, cardH, 0.6, cardBorder.r, cardBorder.g, cardBorder.b)
    
    -- Left accent bar
    if canInteract then
        self:drawRect(cardX, cardY, 4, cardH, 0.9, accentColor.r, accentColor.g, accentColor.b)
    else
        self:drawRect(cardX, cardY, 4, cardH, 0.5, 0.3, 0.3, 0.3)
    end
    
    local textX = cardX + padding + 4
    local textColor = canInteract and {r=0.95, g=0.95, b=1.0} or {r=0.5, g=0.5, b=0.5}
    
    -- ============ SKILL ROW ============
    if data.isSkill then
        local learningState = mainPanel.learningState
        local isLearningThis = learningState and learningState.active and not learningState.isAbsorbAll
                              and learningState.skillName == data.skillName
        
        -- Skill name
        local displayName = data.displayName or data.skillName or "Unknown Skill"
        self:drawText(displayName, textX, cardY + 6, textColor.r, textColor.g, textColor.b, 1, UIFont.Small)
        
        -- Check if in queue
        local queuePosition = mainPanel:getQueuePosition(data.skillName)
        local isQueued = queuePosition ~= nil
        
        -- Show learning progress or status
        if isLearningThis then
            local progressText = string.format("Reading... %d%%", math.floor(learningState.progress * 100))
            self:drawText(progressText, textX, cardY + 22, 0.3, 0.7, 0.9, 1, UIFont.Small)
            
            -- Progress bar
            local barX = textX + 90
            local barY = cardY + 25
            local barW = cardW - 120 - padding
            local barH = 10
            self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)
            self:drawRect(barX, barY, barW * learningState.progress, barH, 0.9, 0.3, 0.6, 0.8)
            self:drawRectBorder(barX, barY, barW, barH, 0.7, 0.4, 0.6, 0.8)
        elseif isQueued then
            self:drawText("Queued #" .. queuePosition, textX, cardY + 22, 0.6, 0.75, 0.9, 1, UIFont.Small)
        elseif data.canClaim then
            -- Show XP comparison: Recorded vs Current
            local xpText = "Recorded: " .. BurdJournals.formatXP(data.xp) .. " XP (You: " .. BurdJournals.formatXP(data.playerXP) .. ")"
            self:drawText(xpText, textX, cardY + 22, 0.5, 0.7, 0.8, 1, UIFont.Small)
        else
            -- Already at or above this level
            self:drawText("Already at this level or higher", textX, cardY + 22, 0.4, 0.45, 0.45, 1, UIFont.Small)
        end
        
        -- CLAIM/QUEUE button
        if data.canClaim and not isLearningThis then
            local btnW = 60
            local btnH = 24
            local btnX = cardX + cardW - btnW - 10
            local btnY = cardY + (cardH - btnH) / 2
            
            if isQueued then
                -- Show queue position indicator
                self:drawRect(btnX, btnY, btnW, btnH, 0.5, 0.3, 0.4, 0.5)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.6, 0.4, 0.5, 0.6)
                local btnText = "#" .. queuePosition
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.8, 0.9, 1, 1, UIFont.Small)
            elseif learningState and learningState.active and not learningState.isAbsorbAll then
                -- Show QUEUE button
                self:drawRect(btnX, btnY, btnW, btnH, 0.6, 0.25, 0.35, 0.5)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.4, 0.55, 0.7)
                local btnText = "QUEUE"
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.9, 0.95, 1, 1, UIFont.Small)
            else
                self:drawRect(btnX, btnY, btnW, btnH, 0.7, 0.2, 0.4, 0.5)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.3, 0.55, 0.65)
                local btnText = "CLAIM"
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 1, 1, 1, 1, UIFont.Small)
            end
        end
    end
    
    -- ============ TRAIT ROW ============
    if data.isTrait then
        local learningState = mainPanel.learningState
        local isLearningThis = learningState and learningState.active and not learningState.isAbsorbAll
                              and learningState.traitId == data.traitId
        
        local traitName = data.traitName or data.traitId or "Unknown Trait"
        local traitTextX = textX
        
        -- Draw trait icon if available
        if data.traitTexture then
            local iconSize = 24
            local iconX = textX
            local iconY = cardY + (cardH - iconSize) / 2
            local iconAlpha = data.alreadyKnown and 0.4 or 1.0
            self:drawTextureScaledAspect(data.traitTexture, iconX, iconY, iconSize, iconSize, iconAlpha, 1, 1, 1)
            traitTextX = textX + iconSize + 6
        end
        
        -- Check if in queue
        local queuePosition = mainPanel:getQueuePosition(data.traitId)
        local isQueued = queuePosition ~= nil
        
        -- Trait name
        local traitColor = data.alreadyKnown and {r=0.5, g=0.5, b=0.5} or {r=0.8, g=0.9, b=1.0}
        self:drawText(traitName, traitTextX, cardY + 6, traitColor.r, traitColor.g, traitColor.b, 1, UIFont.Small)
        
        -- Status text
        if isLearningThis then
            local progressText = string.format("Learning... %d%%", math.floor(learningState.progress * 100))
            self:drawText(progressText, traitTextX, cardY + 22, 0.3, 0.7, 0.9, 1, UIFont.Small)
        elseif isQueued then
            self:drawText("Queued #" .. queuePosition, traitTextX, cardY + 22, 0.6, 0.75, 0.9, 1, UIFont.Small)
        elseif data.alreadyKnown then
            self:drawText("Already known", traitTextX, cardY + 22, 0.4, 0.45, 0.45, 1, UIFont.Small)
        else
            self:drawText("Recorded trait", traitTextX, cardY + 22, 0.5, 0.7, 0.8, 1, UIFont.Small)
        end
        
        -- CLAIM/QUEUE button
        if not data.alreadyKnown and not isLearningThis then
            local btnW = 60
            local btnH = 24
            local btnX = cardX + cardW - btnW - 10
            local btnY = cardY + (cardH - btnH) / 2
            
            if isQueued then
                -- Show queue position indicator
                self:drawRect(btnX, btnY, btnW, btnH, 0.5, 0.4, 0.35, 0.5)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.6, 0.5, 0.45, 0.6)
                local btnText = "#" .. queuePosition
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.9, 0.85, 0.7, 1, UIFont.Small)
            elseif learningState and learningState.active and not learningState.isAbsorbAll then
                -- Show QUEUE button
                self:drawRect(btnX, btnY, btnW, btnH, 0.6, 0.35, 0.4, 0.5)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.5, 0.55, 0.65)
                local btnText = "QUEUE"
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 1, 0.95, 0.9, 1, UIFont.Small)
            else
                self:drawRect(btnX, btnY, btnW, btnH, 0.7, 0.35, 0.45, 0.55)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.5, 0.6, 0.7)
                local btnText = "CLAIM"
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 1, 1, 1, 1, UIFont.Small)
            end
        end
    end
    
    return y + h
end

-- Claim All button handler (for player journals)
function BurdJournals.UI.MainPanel:onClaimAll()
    if not self:startLearningAll() then
        self:showFeedback("Already reading...", {r=0.9, g=0.7, b=0.3})
    end
end

-- Claim skill (SET mode - sets XP to recorded level)
function BurdJournals.UI.MainPanel:claimSkill(skillName, recordedXP)
    -- If already learning, add to queue
    if self.learningState.active and not self.learningState.isAbsorbAll then
        if self:addToQueue("skill", skillName, recordedXP) then
            self:showFeedback("Queued: " .. (BurdJournals.getPerkDisplayName(skillName) or skillName), {r=0.7, g=0.8, b=0.9})
        else
            self:showFeedback("Already queued", {r=0.9, g=0.7, b=0.3})
        end
        return
    end
    
    -- Start learning
    if not self:startLearningSkill(skillName, recordedXP) then
        self:showFeedback("Already reading...", {r=0.9, g=0.7, b=0.3})
    end
end

-- Claim trait (same as absorb but from player journal)
function BurdJournals.UI.MainPanel:claimTrait(traitId)
    -- If already learning, add to queue
    if self.learningState.active and not self.learningState.isAbsorbAll then
        if self:addToQueue("trait", traitId) then
            local traitName = safeGetTraitName(traitId)
            self:showFeedback("Queued: " .. traitName, {r=0.7, g=0.8, b=0.9})
        else
            self:showFeedback("Already queued", {r=0.9, g=0.7, b=0.3})
        end
        return
    end
    
    -- Start learning
    if not self:startLearningTrait(traitId) then
        self:showFeedback("Already reading...", {r=0.9, g=0.7, b=0.3})
    end
end

-- Debug removed


