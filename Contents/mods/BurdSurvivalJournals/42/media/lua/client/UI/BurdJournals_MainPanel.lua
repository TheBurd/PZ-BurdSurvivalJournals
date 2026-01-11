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

    -- Helper to create cache entry
    local function createCacheEntry(def)
        local defLabel = def:getLabel() or ""
        local defType = def:getType()
        local defName = ""
        if defType then
            pcall(function()
                defName = defType:getName() or tostring(defType)
            end)
        end
        local cached = {
            def = def,
            label = defLabel,
            name = defName,
            type = defType
        }
        pcall(function()
            if def.getTexture then
                cached.texture = def:getTexture()
            end
        end)
        traitDefCache[traitId] = cached
        return cached
    end

    -- Search CharacterTraitDefinition with priority matching
    -- Pass 1: Look for exact or case-insensitive match first (most reliable)
    -- Pass 2: Look for normalized match (no spaces)
    -- Pass 3: Partial match as last resort (can be unreliable)
    if CharacterTraitDefinition and CharacterTraitDefinition.getTraits then
        local allTraits = CharacterTraitDefinition.getTraits()

        -- Pass 1: Exact and case-insensitive matches
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

            -- Exact match (case-sensitive or case-insensitive)
            if (defLabel == traitId) or (defName == traitId) or
               (defLabelLower == traitIdLower) or (defNameLower == traitIdLower) then
                return createCacheEntry(def)
            end
        end

        -- Pass 2: Normalized matches (ignore spaces)
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

            local defLabelNorm = string.lower(defLabel):gsub("%s", "")
            local defNameNorm = string.lower(defName):gsub("%s", "")

            if (defLabelNorm == traitIdNorm) or (defNameNorm == traitIdNorm) then
                return createCacheEntry(def)
            end
        end

        -- Pass 3: Partial match (last resort - can match wrong trait)
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

            -- Only partial match if the search term is fully contained
            if defLabelLower:find(traitIdLower, 1, true) or defNameLower:find(traitIdLower, 1, true) then
                return createCacheEntry(def)
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

-- Cache for isTraitPositive results (separate from getTraitDefinition cache)
local traitPositiveCache = {}

-- Check if a trait is positive (beneficial) or negative (detrimental)
-- In PZ's trait system, getCost() returns:
--   - POSITIVE value for beneficial traits (they cost points to take, e.g., Keen Cook = +3)
--   - NEGATIVE value for detrimental traits (they give points back, e.g., Agoraphobic = -4)
-- Returns: true = positive/beneficial (green), false = negative/detrimental (red), nil = unknown/neutral
local function isTraitPositive(traitId)
    if not traitId then return nil end

    -- Check cache first (stores true/false/nil results)
    if traitPositiveCache[traitId] ~= nil then
        local cached = traitPositiveCache[traitId]
        if cached == "nil" then return nil end
        return cached
    end

    local result = nil

    -- Try TraitFactory FIRST - it uses exact trait ID matching and is most reliable
    if TraitFactory and TraitFactory.getTrait then
        local traitObj = TraitFactory.getTrait(traitId)
        if traitObj and traitObj.getCost then
            local ok, cost = pcall(function() return traitObj:getCost() end)
            if ok and cost then
                if cost > 0 then
                    result = true   -- Positive cost = beneficial trait (green) - costs points to take
                elseif cost < 0 then
                    result = false  -- Negative cost = detrimental trait (red) - gives points back
                else
                    result = nil    -- Zero cost = neutral trait (default theme)
                end
                -- Cache and return
                traitPositiveCache[traitId] = (result == nil) and "nil" or result
                return result
            end
        end
    end

    -- Fallback: Try CharacterTraitDefinition (B42) - uses fuzzy matching, less reliable
    -- Note: getTraitDefinition() returns a cached object with .def being the actual trait definition
    local traitCache = getTraitDefinition(traitId)
    if traitCache and traitCache.def then
        local traitDef = traitCache.def
        if traitDef.getCost then
            local ok, cost = pcall(function() return traitDef:getCost() end)
            if ok and cost then
                if cost > 0 then
                    result = true   -- Positive cost = beneficial trait (green)
                elseif cost < 0 then
                    result = false  -- Negative cost = detrimental trait (red)
                else
                    result = nil    -- Zero cost = neutral trait (default theme)
                end
            end
        end
    end

    -- Cache and return
    traitPositiveCache[traitId] = (result == nil) and "nil" or result
    return result
end

-- ==================== LEVEL SQUARES DISPLAY HELPERS ====================

-- Get XP required for a specific level (0-10) for a skill
-- Uses PZ's built-in getTotalXpForLevel method
local function getXPForLevel(skillName, level)
    if level <= 0 then return 0 end
    if level > 10 then level = 10 end

    local perk = BurdJournals.getPerkByName(skillName)
    if perk and perk.getTotalXpForLevel then
        return perk:getTotalXpForLevel(level)
    end

    -- Fallback XP table (approximation based on PZ's formula)
    -- Each level requires progressively more XP
    local xpTable = {0, 75, 225, 500, 900, 1425, 2075, 2850, 3750, 4775, 5925}
    return xpTable[level + 1] or 0
end

-- Calculate level progress from total XP for a skill
-- Returns: currentLevel (0-10), progressToNext (0.0-1.0), xpInCurrentLevel, xpNeededForNext
local function calculateLevelProgress(skillName, totalXP)
    local currentLevel = 0
    local xpForCurrentLevel = 0
    local xpForNextLevel = getXPForLevel(skillName, 1)

    -- Find current level
    for level = 1, 10 do
        local xpNeeded = getXPForLevel(skillName, level)
        if totalXP >= xpNeeded then
            currentLevel = level
            xpForCurrentLevel = xpNeeded
            xpForNextLevel = getXPForLevel(skillName, level + 1)
        else
            break
        end
    end

    -- Calculate progress to next level
    local progressToNext = 0
    if currentLevel < 10 then
        local xpInThisLevel = totalXP - xpForCurrentLevel
        local xpRangeForLevel = xpForNextLevel - xpForCurrentLevel
        if xpRangeForLevel > 0 then
            progressToNext = math.min(1, math.max(0, xpInThisLevel / xpRangeForLevel))
        end
    else
        progressToNext = 1  -- Level 10 is full
    end

    return currentLevel, progressToNext, totalXP - xpForCurrentLevel, xpForNextLevel - xpForCurrentLevel
end

-- Draw the 10-square level display (like vanilla skills UI)
-- Parameters:
--   self: the drawing context (listbox)
--   x, y: top-left position of the squares
--   level: current level (0-10)
--   progress: progress to next level (0.0-1.0)
--   squareSize: size of each square (default 12)
--   spacing: gap between squares (default 2)
--   filledColor: color table for filled squares {r, g, b}
--   emptyColor: color table for empty squares {r, g, b}
--   progressColor: color table for progress fill {r, g, b}
local function drawLevelSquares(self, x, y, level, progress, squareSize, spacing, filledColor, emptyColor, progressColor)
    squareSize = squareSize or 12
    spacing = spacing or 2
    filledColor = filledColor or {r=0.85, g=0.75, b=0.2}  -- Golden yellow (like vanilla)
    emptyColor = emptyColor or {r=0.15, g=0.15, b=0.15}   -- Dark gray
    progressColor = progressColor or {r=0.5, g=0.45, b=0.15}  -- Dimmer yellow for progress

    for i = 1, 10 do
        local sqX = x + (i - 1) * (squareSize + spacing)

        if i <= level then
            -- Fully filled square
            self:drawRect(sqX, y, squareSize, squareSize, 0.9, filledColor.r, filledColor.g, filledColor.b)
        elseif i == level + 1 and progress > 0 then
            -- Progress square - show partial fill
            self:drawRect(sqX, y, squareSize, squareSize, 0.6, emptyColor.r, emptyColor.g, emptyColor.b)
            -- Fill from bottom up (progress indicator)
            local fillHeight = squareSize * progress
            self:drawRect(sqX, y + squareSize - fillHeight, squareSize, fillHeight, 0.8, progressColor.r, progressColor.g, progressColor.b)
        else
            -- Empty square
            self:drawRect(sqX, y, squareSize, squareSize, 0.5, emptyColor.r, emptyColor.g, emptyColor.b)
        end

        -- Border
        self:drawRectBorder(sqX, y, squareSize, squareSize, 0.3, 0.3, 0.3, 0.3)
    end

    -- Return total width for positioning other elements
    return 10 * squareSize + 9 * spacing
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

-- ==================== TABBED UI SYSTEM ====================

-- Create tab buttons for the journal UI
-- tabs: array of {id="skills", label="Skills", count=5}
-- Returns the Y position after the tabs
function BurdJournals.UI.MainPanel:createTabs(tabs, startY, themeColors)
    local padding = 16
    local tabHeight = 28
    local tabSpacing = 4
    local tabY = startY

    -- Store tab info
    self.tabs = tabs
    self.currentTab = tabs[1] and tabs[1].id or "skills"
    self.tabButtons = {}

    -- Calculate tab widths (equal width, fill available space)
    local totalWidth = self.width - padding * 2
    local tabCount = #tabs
    local tabWidth = math.floor((totalWidth - (tabSpacing * (tabCount - 1))) / tabCount)

    -- Create tab buttons
    local tabX = padding
    for i, tab in ipairs(tabs) do
        local isActive = (tab.id == self.currentTab)

        local btn = ISButton:new(tabX, tabY, tabWidth, tabHeight, tab.label, self, BurdJournals.UI.MainPanel.onTabClick)
        btn:initialise()
        btn:instantiate()
        btn.internal = tab.id
        btn.tabIndex = i

        -- Style based on active state and theme
        if isActive then
            btn.backgroundColor = {r=themeColors.active.r, g=themeColors.active.g, b=themeColors.active.b, a=0.9}
            btn.borderColor = {r=themeColors.accent.r, g=themeColors.accent.g, b=themeColors.accent.b, a=1}
            btn.textColor = {r=1, g=1, b=1, a=1}
        else
            btn.backgroundColor = {r=themeColors.inactive.r, g=themeColors.inactive.g, b=themeColors.inactive.b, a=0.6}
            btn.borderColor = {r=0.3, g=0.3, b=0.3, a=0.8}
            btn.textColor = {r=0.7, g=0.7, b=0.7, a=1}
        end

        self:addChild(btn)
        self.tabButtons[tab.id] = btn

        tabX = tabX + tabWidth + tabSpacing
    end

    return tabY + tabHeight + 8  -- Return Y position after tabs
end

-- Tab click handler
function BurdJournals.UI.MainPanel:onTabClick(button)
    local tabId = button.internal
    if tabId == self.currentTab then return end  -- Already on this tab

    self.currentTab = tabId

    -- Clear search when switching tabs
    self:clearSearch()

    -- Update tab button styles
    self:updateTabStyles()

    -- Refresh the list for the new tab
    self:refreshCurrentList()
end

-- Update tab button visual styles based on current selection
function BurdJournals.UI.MainPanel:updateTabStyles()
    if not self.tabButtons or not self.tabThemeColors then return end

    local themeColors = self.tabThemeColors
    for tabId, btn in pairs(self.tabButtons) do
        local isActive = (tabId == self.currentTab)
        if isActive then
            btn.backgroundColor = {r=themeColors.active.r, g=themeColors.active.g, b=themeColors.active.b, a=0.9}
            btn.borderColor = {r=themeColors.accent.r, g=themeColors.accent.g, b=themeColors.accent.b, a=1}
            btn.textColor = {r=1, g=1, b=1, a=1}
        else
            btn.backgroundColor = {r=themeColors.inactive.r, g=themeColors.inactive.g, b=themeColors.inactive.b, a=0.6}
            btn.borderColor = {r=0.3, g=0.3, b=0.3, a=0.8}
            btn.textColor = {r=0.7, g=0.7, b=0.7, a=1}
        end
    end
end

-- Create search bar for filtering list items
-- Returns the Y position after the search bar (or same Y if hidden)
function BurdJournals.UI.MainPanel:createSearchBar(startY, themeColors, itemCount)
    local padding = 16
    local searchHeight = 24
    local minItemsForSearch = 5
    local clearButtonSize = 16

    -- Initialize search state
    self.searchQuery = ""

    -- Only show search bar if there are enough items
    if itemCount < minItemsForSearch then
        self.searchEntry = nil
        self.searchBarY = nil
        self.searchClearBtn = nil
        return startY
    end

    self.searchBarY = startY

    -- Create the search text entry (leave space for clear button)
    local entryWidth = self.width - padding * 2 - clearButtonSize - 4
    self.searchEntry = ISTextEntryBox:new("", padding, startY, entryWidth, searchHeight)
    self.searchEntry.font = UIFont.Small
    self.searchEntry:initialise()
    self.searchEntry:instantiate()
    self.searchEntry.backgroundColor = {r=0.08, g=0.08, b=0.1, a=0.9}
    self.searchEntry.borderColor = {r=themeColors.accent.r * 0.7, g=themeColors.accent.g * 0.7, b=themeColors.accent.b * 0.7, a=0.8}

    -- Store reference to main panel for callback
    self.searchEntry.mainPanel = self

    -- Set placeholder text (shown when empty)
    local placeholder = getText("UI_BurdJournals_SearchPlaceholder") or "Search..."
    self.searchEntry:setTooltip(placeholder)

    -- Track last search to detect actual changes
    self.searchEntry.lastSearchText = ""

    -- Flag to trigger deferred search refresh (fixes "one step behind" issue)
    -- onTextChange fires BEFORE the text buffer is updated, so we defer to prerender
    self.searchPendingRefresh = false

    -- On text change callback - mark for deferred refresh
    self.searchEntry.onTextChange = function()
        local entry = self.searchEntry
        if entry and entry.mainPanel then
            entry.mainPanel.searchPendingRefresh = true
        end
    end

    -- Override onOtherKey to also mark for deferred refresh (catches backspace, delete, etc.)
    local origOnOtherKey = self.searchEntry.onOtherKey
    self.searchEntry.onOtherKey = function(entry, key)
        if origOnOtherKey then
            origOnOtherKey(entry, key)
        end
        if entry.mainPanel then
            entry.mainPanel.searchPendingRefresh = true
        end
    end

    self:addChild(self.searchEntry)

    -- Create clear button (X)
    local clearBtnX = padding + entryWidth + 2
    local clearBtnY = startY + (searchHeight - clearButtonSize) / 2
    self.searchClearBtn = ISButton:new(clearBtnX, clearBtnY, clearButtonSize, clearButtonSize, "X", self, BurdJournals.UI.MainPanel.onSearchClearClick)
    self.searchClearBtn:initialise()
    self.searchClearBtn:instantiate()
    self.searchClearBtn.backgroundColor = {r=0.15, g=0.15, b=0.18, a=0.9}
    self.searchClearBtn.backgroundColorMouseOver = {r=0.5, g=0.2, b=0.2, a=0.9}
    self.searchClearBtn.borderColor = {r=0.4, g=0.4, b=0.45, a=0.8}
    self.searchClearBtn.textColor = {r=0.7, g=0.7, b=0.7, a=1}
    self.searchClearBtn:setTooltip(getText("UI_BurdJournals_ClearSearch") or "Clear search")
    self:addChild(self.searchClearBtn)

    return startY + searchHeight + 6
end

-- Clear search button click handler
function BurdJournals.UI.MainPanel:onSearchClearClick()
    self:clearSearch()
    self:refreshCurrentList()
    -- Re-focus the search entry for convenience
    if self.searchEntry then
        self.searchEntry:focus()
    end
end

-- Clear search and optionally hide the search bar
function BurdJournals.UI.MainPanel:clearSearch()
    self.searchQuery = ""
    if self.searchEntry then
        self.searchEntry:setText("")
        self.searchEntry.lastSearchText = ""
    end
end

-- Check if an item matches the current search query
function BurdJournals.UI.MainPanel:matchesSearch(displayName)
    if not self.searchQuery or self.searchQuery == "" then
        return true
    end
    local query = string.lower(self.searchQuery)
    local name = string.lower(displayName or "")
    return string.find(name, query, 1, true) ~= nil
end

-- Refresh the current list based on mode and tab
function BurdJournals.UI.MainPanel:refreshCurrentList()
    if self.mode == "log" then
        self:populateRecordList()
    elseif self.mode == "view" then
        self:populateViewList()
    elseif self.mode == "absorb" then
        self:populateAbsorptionList()
    end
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

-- Refresh journal data and check for pending journal updates
function BurdJournals.UI.MainPanel:refreshJournalData()
    -- Refresh player first
    self:refreshPlayer()

    -- Check if we have a pending new journal ID (from blank->filled conversion)
    if self.pendingNewJournalId then
        print("[BurdJournals] refreshJournalData: Checking for pending journal ID " .. tostring(self.pendingNewJournalId))
        local newJournal = BurdJournals.findItemById(self.player, self.pendingNewJournalId)
        if newJournal then
            print("[BurdJournals] refreshJournalData: Found pending journal! Updating reference.")
            self.journal = newJournal
            self.pendingNewJournalId = nil
        else
            print("[BurdJournals] refreshJournalData: Pending journal still not found")
        end
    end

    -- Ensure journal reference is still valid
    if not self.journal or not self.journal:getContainer() then
        print("[BurdJournals] refreshJournalData: Journal invalid, trying to find by ID")
        -- Try to find the journal again if we have an ID stored
        if self.pendingNewJournalId then
            local journal = BurdJournals.findItemById(self.player, self.pendingNewJournalId)
            if journal then
                self.journal = journal
                self.pendingNewJournalId = nil
            end
        end
    end

    -- Refresh the lists based on current mode
    if self.mode == "log" then
        -- Log mode uses skillList for recording
        if self.skillList then
            pcall(function() self:populateRecordList() end)
        end
    elseif self.mode == "view" then
        -- View mode (player journals) uses skillList for claiming
        if self.skillList then
            pcall(function() self:populateViewList() end)
        end
    elseif self.mode == "absorb" then
        -- Absorb mode (worn/bloody journals) uses absorbList
        if self.absorbList then
            pcall(function() self:refreshAbsorptionList() end)
        end
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
        self.typeText = getText("UI_BurdJournals_BloodyJournalHeader")
        self.rarityText = getText("UI_BurdJournals_RarityRare")
        self.flavorText = getText("UI_BurdJournals_BloodyFlavor")
    elseif hasBloodyOrigin then
        self.headerColor = {r=0.30, g=0.22, b=0.12}
        self.headerAccent = {r=0.5, g=0.35, b=0.2}
        self.typeText = getText("UI_BurdJournals_WornJournalHeader")
        self.rarityText = getText("UI_BurdJournals_RarityUncommon")
        self.flavorText = getText("UI_BurdJournals_WornBloodyFlavor")
    else
        self.headerColor = {r=0.22, g=0.20, b=0.15}
        self.headerAccent = {r=0.4, g=0.35, b=0.25}
        self.typeText = getText("UI_BurdJournals_WornJournalHeader")
        self.rarityText = nil
        self.flavorText = getText("UI_BurdJournals_WornFlavor")
    end
    self.headerHeight = headerHeight
    y = headerHeight + 6

    -- ============ AUTHOR INFO BOX ============
    local authorName = journalData and journalData.author or getText("UI_BurdJournals_UnknownSurvivor")
    self.authorName = authorName
    self.authorBoxY = y
    self.authorBoxHeight = 44
    y = y + self.authorBoxHeight + 10

    -- ============ COUNT SKILLS, TRAITS, AND RECIPES ============
    local skillCount = 0
    local totalSkillCount = 0
    local traitCount = 0
    local totalTraitCount = 0
    local recipeCount = 0
    local totalRecipeCount = 0
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
    if journalData and journalData.recipes then
        for recipeName, _ in pairs(journalData.recipes) do
            totalRecipeCount = totalRecipeCount + 1
            if not BurdJournals.isRecipeClaimed(self.journal, recipeName) then
                recipeCount = recipeCount + 1
            end
        end
    end

    self.skillCount = skillCount
    self.traitCount = traitCount
    self.recipeCount = recipeCount
    self.totalXP = totalXP

    -- ============ TAB BUTTONS ============
    -- Worn/Bloody journals: Skills, Traits, and Recipes tabs
    local tabs = {{id = "skills", label = getText("UI_BurdJournals_TabSkills")}}
    if hasBloodyOrigin and totalTraitCount > 0 then
        table.insert(tabs, {id = "traits", label = getText("UI_BurdJournals_TabTraits")})
    end
    if totalRecipeCount > 0 then
        table.insert(tabs, {id = "recipes", label = getText("UI_BurdJournals_TabRecipes")})
    end

    -- Theme colors for tabs
    local tabThemeColors
    if isBloody then
        tabThemeColors = {
            active = {r=0.5, g=0.15, b=0.15},
            inactive = {r=0.2, g=0.1, b=0.1},
            accent = {r=0.7, g=0.2, b=0.2}
        }
    else
        tabThemeColors = {
            active = {r=0.35, g=0.28, b=0.18},
            inactive = {r=0.18, g=0.15, b=0.12},
            accent = {r=0.5, g=0.4, b=0.25}
        }
    end
    self.tabThemeColors = tabThemeColors

    -- Only create tabs if there's more than one
    if #tabs > 1 then
        y = self:createTabs(tabs, y, tabThemeColors)
    end

    -- ============ SEARCH BAR ============
    -- Use max item count across tabs to determine if search bar should show
    local maxItemCount = math.max(totalSkillCount, totalTraitCount, totalRecipeCount)
    y = self:createSearchBar(y, tabThemeColors, maxItemCount)

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
                    if x >= btnAreaStart or item.isTrait or item.isRecipe then
                        if item.isSkill then
                            listbox.mainPanel:absorbSkill(item.skillName, item.xp)
                        elseif item.isTrait and not item.alreadyKnown then
                            listbox.mainPanel:absorbTrait(item.traitId)
                        elseif item.isRecipe and not item.alreadyKnown then
                            listbox.mainPanel:absorbRecipe(item.recipeName)
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
    local btnSpacing = 8
    local totalBtnWidth = btnWidth * 3 + btnSpacing * 2
    local btnStartX = (self.width - totalBtnWidth) / 2
    local btnY = self.footerY + 32

    -- Absorb Tab button (tab-specific)
    local tabName = self:getTabDisplayName(self.currentTab or "skills")
    local absorbTabText = string.format(getText("UI_BurdJournals_BtnAbsorbTab") or "Absorb %s", tabName)
    self.absorbTabBtn = ISButton:new(btnStartX, btnY, btnWidth, btnHeight, absorbTabText, self, BurdJournals.UI.MainPanel.onAbsorbTab)
    self.absorbTabBtn:initialise()
    self.absorbTabBtn:instantiate()
    if isBloody then
        self.absorbTabBtn.borderColor = {r=0.5, g=0.2, b=0.2, a=1}
        self.absorbTabBtn.backgroundColor = {r=0.3, g=0.1, b=0.1, a=0.8}
    else
        self.absorbTabBtn.borderColor = {r=0.35, g=0.45, b=0.3, a=1}
        self.absorbTabBtn.backgroundColor = {r=0.18, g=0.22, b=0.14, a=0.8}
    end
    self.absorbTabBtn.textColor = {r=1, g=1, b=1, a=1}
    self:addChild(self.absorbTabBtn)

    -- Absorb All button
    self.absorbAllBtn = ISButton:new(btnStartX + btnWidth + btnSpacing, btnY, btnWidth, btnHeight, getText("UI_BurdJournals_BtnAbsorbAll"), self, BurdJournals.UI.MainPanel.onAbsorbAll)
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
    self.closeBottomBtn = ISButton:new(btnStartX + (btnWidth + btnSpacing) * 2, btnY, btnWidth, btnHeight, getText("UI_BurdJournals_BtnClose"), self, BurdJournals.UI.MainPanel.onClose)
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
        self:showFeedback(getText("UI_BurdJournals_AlreadyReading"), {r=0.9, g=0.7, b=0.3})
    end
end

-- Absorb Tab button handler (tab-specific)
function BurdJournals.UI.MainPanel:onAbsorbTab()
    -- Start learning only rewards from the current tab
    if not self:startLearningTab(self.currentTab or "skills") then
        self:showFeedback(getText("UI_BurdJournals_AlreadyReading"), {r=0.9, g=0.7, b=0.3})
    end
end

-- ==================== CUSTOM RENDER FOR HEADER/FOOTER ====================

function BurdJournals.UI.MainPanel:prerender()
    ISPanel.prerender(self)

    -- Handle deferred search refresh (fixes "one step behind" issue)
    -- onTextChange fires BEFORE text buffer updates, so we check here after it's updated
    if self.searchPendingRefresh and self.searchEntry then
        self.searchPendingRefresh = false
        local currentText = self.searchEntry:getText() or ""
        if currentText ~= self.searchEntry.lastSearchText then
            self.searchEntry.lastSearchText = currentText
            self.searchQuery = currentText
            self:refreshCurrentList()
        end
    end

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
    if self.absorbTabBtn then
        self.absorbTabBtn:setY(targetBtnY)
    end
    if self.absorbAllBtn then
        self.absorbAllBtn:setY(targetBtnY)
    end
    if self.recordTabBtn then
        self.recordTabBtn:setY(targetBtnY)
    end
    if self.recordAllBtn then
        self.recordAllBtn:setY(targetBtnY)
    end
    if self.closeBottomBtn then
        self.closeBottomBtn:setY(targetBtnY)
    end

    -- Update button states based on learning/recording
    if self.mode == "absorb" or self.mode == "view" then
        local isLearning = self.learningState and self.learningState.active

        -- Update tab-specific button
        if self.absorbTabBtn then
            self.absorbTabBtn:setEnable(not isLearning)
            local tabName = self:getTabDisplayName(self.currentTab or "skills")
            if isLearning then
                self.absorbTabBtn.title = getText("UI_BurdJournals_StateReading")
            else
                local btnTextKey = (self.mode == "view") and "UI_BurdJournals_BtnClaimTab" or "UI_BurdJournals_BtnAbsorbTab"
                self.absorbTabBtn.title = string.format(getText(btnTextKey) or "%s Tab", tabName)
            end
        end

        -- Update all button
        if self.absorbAllBtn then
            self.absorbAllBtn:setEnable(not isLearning)
            if isLearning then
                self.absorbAllBtn.title = getText("UI_BurdJournals_StateReading")
            else
                self.absorbAllBtn.title = (self.mode == "view") and getText("UI_BurdJournals_BtnClaimAll") or getText("UI_BurdJournals_BtnAbsorbAll")
            end
        end
    elseif self.mode == "log" then
        local isRecording = self.recordingState and self.recordingState.active

        -- Update tab-specific button
        if self.recordTabBtn then
            self.recordTabBtn:setEnable(not isRecording)
            local tabName = self:getTabDisplayName(self.currentTab or "skills")
            if isRecording then
                self.recordTabBtn.title = getText("UI_BurdJournals_StateRecording")
            else
                self.recordTabBtn.title = string.format(getText("UI_BurdJournals_BtnRecordTab") or "Record %s", tabName)
            end
        end

        -- Update all button
        if self.recordAllBtn then
            self.recordAllBtn:setEnable(not isRecording)
            if isRecording then
                self.recordAllBtn.title = getText("UI_BurdJournals_StateRecording")
            else
                self.recordAllBtn.title = getText("UI_BurdJournals_BtnRecordAll")
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
        local authorNameDisplay = self.authorName or getText("UI_BurdJournals_Unknown")
        if self.mode == "log" then
            authorText = string.format(getText("UI_BurdJournals_RecordingFor"), authorNameDisplay)
        else
            authorText = string.format(getText("UI_BurdJournals_FromNotesOf"), authorNameDisplay)
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
    -- Account for scroll bar width (13px) to prevent content cutoff
    local scrollBarWidth = 13
    local w = self:getWidth() - scrollBarWidth
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

    -- Card background - tint based on trait type (positive/negative)
    local bgColor = cardBg
    local borderColor = cardBorder
    local accent = accentColor
    if data.isTrait and not data.isClaimed then
        if data.isPositive == true then
            -- Green tint for positive traits (more saturated)
            bgColor = {r=0.08, g=0.20, b=0.10}
            borderColor = {r=0.2, g=0.5, b=0.25}
            accent = {r=0.3, g=0.8, b=0.35}
        elseif data.isPositive == false then
            -- Red tint for negative traits (more saturated)
            bgColor = {r=0.22, g=0.08, b=0.08}
            borderColor = {r=0.5, g=0.2, b=0.2}
            accent = {r=0.8, g=0.3, b=0.3}
        end
        -- If isPositive is nil, keep default amber/gold theme
    end

    if data.isClaimed then
        self:drawRect(cardX, cardY, cardW, cardH, 0.3, 0.1, 0.1, 0.1)
    else
        self:drawRect(cardX, cardY, cardW, cardH, 0.7, bgColor.r, bgColor.g, bgColor.b)
    end

    -- Card border
    self:drawRectBorder(cardX, cardY, cardW, cardH, 0.6, borderColor.r, borderColor.g, borderColor.b)

    -- Left accent bar
    self:drawRect(cardX, cardY, 4, cardH, 0.9, accent.r, accent.g, accent.b)

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

        -- Line 1: Skill name
        local displayName = data.displayName or data.skillName or "Unknown Skill"
        self:drawText(displayName, textX, cardY + 6, textColor.r, textColor.g, textColor.b, 1, UIFont.Small)

        -- Line 2: Level squares + XP info OR learning progress
        if isLearningThis then
            -- Show learning progress bar
            local progressText = string.format("Reading... %d%%", math.floor(learningState.progress * 100))
            self:drawText(progressText, textX, cardY + 24, 0.9, 0.8, 0.3, 1, UIFont.Small)

            local barX = textX + 90
            local barY = cardY + 27
            local barW = cardW - 120 - padding
            local barH = 10
            self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)
            self:drawRect(barX, barY, barW * learningState.progress, barH, 0.9, 0.3, 0.7, 0.4)
            self:drawRectBorder(barX, barY, barW, barH, 0.7, 0.4, 0.8, 0.5)

        elseif isQueued then
            -- Show level squares with queue indicator
            local squaresX = textX
            local squaresY = cardY + 26
            local squareSize = 10
            local squareSpacing = 2
            local level, progress = calculateLevelProgress(data.skillName, data.xp or 0)

            drawLevelSquares(self, squaresX, squaresY, level, progress, squareSize, squareSpacing,
                {r=0.4, g=0.5, b=0.6},     -- Bluish (queued)
                {r=0.1, g=0.1, b=0.1},     -- Dark empty
                {r=0.25, g=0.3, b=0.4}     -- Dimmer blue for progress
            )
            local squaresWidth = 10 * squareSize + 9 * squareSpacing
            self:drawText("+" .. BurdJournals.formatXP(data.xp) .. " XP  #" .. queuePosition, squaresX + squaresWidth + 8, squaresY, 0.6, 0.75, 0.9, 1, UIFont.Small)

        elseif isQueuedInAbsorbAll then
            -- Show level squares (Absorb All mode)
            local squaresX = textX
            local squaresY = cardY + 26
            local squareSize = 10
            local squareSpacing = 2
            local level, progress = calculateLevelProgress(data.skillName, data.xp or 0)

            drawLevelSquares(self, squaresX, squaresY, level, progress, squareSize, squareSpacing,
                {r=0.45, g=0.55, b=0.35},  -- Greenish (absorb all queued)
                {r=0.1, g=0.1, b=0.1},     -- Dark empty
                {r=0.3, g=0.38, b=0.22}    -- Dimmer green
            )
            local squaresWidth = 10 * squareSize + 9 * squareSpacing
            self:drawText("+" .. BurdJournals.formatXP(data.xp) .. " XP  Queued", squaresX + squaresWidth + 8, squaresY, 0.5, 0.6, 0.4, 1, UIFont.Small)

        elseif data.xp and not data.isClaimed then
            -- Show level squares + XP reward
            local squaresX = textX
            local squaresY = cardY + 26
            local squareSize = 10
            local squareSpacing = 2
            local level, progress = calculateLevelProgress(data.skillName, data.xp or 0)

            -- Choose theme colors based on journal type
            local filledColor, progressColor
            if isBloody then
                filledColor = {r=0.65, g=0.25, b=0.25}   -- Red for bloody
                progressColor = {r=0.45, g=0.18, b=0.18}
            else
                filledColor = {r=0.5, g=0.6, b=0.4}     -- Green/olive for worn
                progressColor = {r=0.35, g=0.42, b=0.28}
            end

            drawLevelSquares(self, squaresX, squaresY, level, progress, squareSize, squareSpacing,
                filledColor,
                {r=0.1, g=0.1, b=0.1},     -- Dark empty
                progressColor
            )
            local squaresWidth = 10 * squareSize + 9 * squareSpacing
            self:drawText("+" .. BurdJournals.formatXP(data.xp) .. " XP", squaresX + squaresWidth + 8, squaresY, 0.6, 0.8, 0.5, 1, UIFont.Small)

        elseif data.isClaimed then
            -- Show dimmed level squares for claimed
            local squaresX = textX
            local squaresY = cardY + 26
            local squareSize = 10
            local squareSpacing = 2
            local level, progress = calculateLevelProgress(data.skillName, data.xp or 0)

            drawLevelSquares(self, squaresX, squaresY, level, progress, squareSize, squareSpacing,
                {r=0.2, g=0.2, b=0.2},     -- Dark gray (claimed)
                {r=0.08, g=0.08, b=0.08},  -- Very dark empty
                {r=0.15, g=0.15, b=0.15}   -- Dimmer for progress
            )
            local squaresWidth = 10 * squareSize + 9 * squareSpacing
            self:drawText("Claimed", squaresX + squaresWidth + 8, squaresY, 0.35, 0.35, 0.35, 1, UIFont.Small)
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
                local btnText = getText("UI_BurdJournals_BtnQueue")
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.9, 0.95, 1, 1, UIFont.Small)
            elseif not learningState.active then
                -- Show "ABSORB" button (normal state)
            self:drawRect(btnX, btnY, btnW, btnH, 0.7, accentColor.r * 0.6, accentColor.g * 0.6, accentColor.b * 0.6)
            self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, accentColor.r, accentColor.g, accentColor.b)
            local btnText = getText("UI_BurdJournals_Absorb")
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

        -- Trait name with color based on positive/negative type
        local traitColor
        if data.isClaimed then
            traitColor = {r=0.4, g=0.4, b=0.4}  -- Grayed out when claimed
        elseif data.isPositive == true then
            traitColor = {r=0.5, g=0.9, b=0.5}  -- Green for positive traits
        elseif data.isPositive == false then
            traitColor = {r=0.9, g=0.5, b=0.5}  -- Red for negative traits
        else
            traitColor = {r=0.9, g=0.75, b=0.5}  -- Original amber for unknown
        end
        self:drawText(traitName, traitTextX, cardY + 6, traitColor.r, traitColor.g, traitColor.b, 1, UIFont.Small)

        -- Show learning progress bar if this trait is being learned
        if isLearningThis then
            local progressText = string.format("Absorbing... %d%%", math.floor(learningState.progress * 100))
            self:drawText(progressText, traitTextX, cardY + 22, 0.9, 0.7, 0.3, 1, UIFont.Small)

            -- Learning progress bar (shorter width to account for icon offset)
            local barX = traitTextX + 100
            local barY = cardY + 25
            local barW = cardW - barX - 20  -- Dynamic width based on actual start position
            local barH = 10

            -- Bar background
            self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)
            -- Bar fill (gold/amber for traits)
            self:drawRect(barX, barY, barW * learningState.progress, barH, 0.9, 0.8, 0.6, 0.2)
            -- Bar border
            self:drawRectBorder(barX, barY, barW, barH, 0.7, 0.9, 0.7, 0.3)
        
        elseif isQueued then
            -- Show as queued with position - different text for positive vs negative traits
            if data.isPositive == false then
                local queueText = string.format(getText("UI_BurdJournals_NegativeTraitQueued") or "Cursed trait - Queued #%d", queuePosition)
                self:drawText(queueText, traitTextX, cardY + 22, 0.7, 0.4, 0.4, 1, UIFont.Small)
            else
                local queueText = string.format(getText("UI_BurdJournals_RareTraitQueued") or "Rare trait - Queued #%d", queuePosition)
                self:drawText(queueText, traitTextX, cardY + 22, 0.6, 0.75, 0.9, 1, UIFont.Small)
            end
            
        elseif isQueuedInAbsorbAll then
            -- Show different flavor text for positive vs negative traits
            if data.isPositive == false then
                local curseText = getText("UI_BurdJournals_NegativeTraitCurseQueued") or "Cursed knowledge... - Queued"
                self:drawText(curseText, traitTextX, cardY + 22, 0.5, 0.35, 0.35, 1, UIFont.Small)
            else
                local bonusText = getText("UI_BurdJournals_RareTraitBonusQueued") or "Rare trait bonus! - Queued"
                self:drawText(bonusText, traitTextX, cardY + 22, 0.5, 0.45, 0.25, 1, UIFont.Small)
            end

        elseif data.isClaimed then
            self:drawText(getText("UI_BurdJournals_StatusClaimed") or "Claimed", traitTextX, cardY + 22, 0.35, 0.35, 0.35, 1, UIFont.Small)
        elseif data.alreadyKnown then
            self:drawText(getText("UI_BurdJournals_StatusAlreadyKnown") or "Already known", traitTextX, cardY + 22, 0.5, 0.4, 0.3, 1, UIFont.Small)
        else
            -- Show different flavor text for positive vs negative traits
            if data.isPositive == false then
                local curseText = getText("UI_BurdJournals_NegativeTraitCurse") or "Cursed knowledge..."
                self:drawText(curseText, traitTextX, cardY + 22, 0.7, 0.4, 0.4, 1, UIFont.Small)
            else
                local bonusText = getText("UI_BurdJournals_RareTraitBonus") or "Rare trait bonus!"
                self:drawText(bonusText, traitTextX, cardY + 22, 0.7, 0.55, 0.3, 1, UIFont.Small)
            end
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
                local btnText = getText("UI_BurdJournals_BtnQueue")
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 1, 0.95, 0.85, 1, UIFont.Small)
            elseif not learningState.active then
                -- Show "CLAIM" button (normal state)
            self:drawRect(btnX, btnY, btnW, btnH, 0.7, 0.5, 0.35, 0.15)
            self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.7, 0.5, 0.25)
            local btnText = getText("UI_BurdJournals_BtnClaim")
            local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
            self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 1, 0.95, 0.85, 1, UIFont.Small)
            end
        end
    end

    -- ============ RECIPE ROW ============
    if data.isRecipe then
        -- Check if this recipe is currently being learned
        local learningState = mainPanel.learningState
        local isLearningThis = learningState.active and not learningState.isAbsorbAll
                              and learningState.recipeName == data.recipeName
        local isQueuedInAbsorbAll = learningState.active and learningState.isAbsorbAll
                                   and not data.isClaimed and not data.alreadyKnown

        -- Check if this recipe is in the manual queue
        local queuePosition = mainPanel:getQueuePosition(data.recipeName)
        local isQueued = queuePosition ~= nil

        local recipeName = data.displayName or data.recipeName or "Unknown Recipe"
        local recipeTextX = textX

        -- Recipe name with teal/cyan color theme
        local recipeColor
        if data.isClaimed then
            recipeColor = {r=0.4, g=0.4, b=0.4}  -- Grayed out when claimed
        elseif data.alreadyKnown then
            recipeColor = {r=0.5, g=0.5, b=0.45}  -- Dimmed when already known
        else
            recipeColor = {r=0.5, g=0.85, b=0.9}  -- Teal/cyan for available recipes
        end
        self:drawText(recipeName, recipeTextX, cardY + 6, recipeColor.r, recipeColor.g, recipeColor.b, 1, UIFont.Small)

        -- Show learning progress bar if this recipe is being learned
        if isLearningThis then
            local progressText = string.format("Learning... %d%%", math.floor(learningState.progress * 100))
            self:drawText(progressText, recipeTextX, cardY + 22, 0.5, 0.8, 0.9, 1, UIFont.Small)

            -- Learning progress bar
            local barX = recipeTextX + 100
            local barY = cardY + 25
            local barW = cardW - barX - 20
            local barH = 10

            -- Bar background
            self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)
            -- Bar fill (teal for recipes)
            self:drawRect(barX, barY, barW * learningState.progress, barH, 0.9, 0.3, 0.7, 0.8)
            -- Bar border
            self:drawRectBorder(barX, barY, barW, barH, 0.7, 0.4, 0.8, 0.9)

        elseif isQueued then
            -- Show as queued with position
            local queueText = string.format("Recipe knowledge - Queued #%d", queuePosition)
            self:drawText(queueText, recipeTextX, cardY + 22, 0.6, 0.75, 0.9, 1, UIFont.Small)

        elseif isQueuedInAbsorbAll then
            -- Show queued state for Absorb All
            local bonusText = "Recipe knowledge - Queued"
            self:drawText(bonusText, recipeTextX, cardY + 22, 0.4, 0.6, 0.65, 1, UIFont.Small)

        elseif data.isClaimed then
            self:drawText(getText("UI_BurdJournals_RecipeClaimed") or "Claimed", recipeTextX, cardY + 22, 0.35, 0.35, 0.35, 1, UIFont.Small)
        elseif data.alreadyKnown then
            self:drawText(getText("UI_BurdJournals_RecipeAlreadyKnown") or "Already known", recipeTextX, cardY + 22, 0.5, 0.4, 0.3, 1, UIFont.Small)
        else
            -- Show magazine source if available
            local sourceText = "Recipe knowledge"
            if data.magazineSource then
                local magazineName = BurdJournals.getMagazineDisplayName(data.magazineSource)
                sourceText = string.format(getText("UI_BurdJournals_RecipeFromMagazine") or "From: %s", magazineName)
            end
            self:drawText(sourceText, recipeTextX, cardY + 22, 0.5, 0.7, 0.75, 1, UIFont.Small)
        end

        -- Button for recipes (not already known or claimed)
        if not data.isClaimed and not data.alreadyKnown and not isLearningThis then
            local btnW = 60
            local btnH = 24
            local btnX = cardX + cardW - btnW - 10
            local btnY = cardY + (cardH - btnH) / 2

            if isQueued then
                -- Show "QUEUED" indicator
                self:drawRect(btnX, btnY, btnW, btnH, 0.5, 0.3, 0.5, 0.55)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.6, 0.4, 0.6, 0.7)
                local btnText = "#" .. queuePosition
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.8, 0.9, 1, 1, UIFont.Small)
            elseif learningState.active and not learningState.isAbsorbAll then
                -- Show "QUEUE" button
                self:drawRect(btnX, btnY, btnW, btnH, 0.6, 0.25, 0.45, 0.5)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.35, 0.6, 0.7)
                local btnText = getText("UI_BurdJournals_BtnQueue")
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.9, 0.95, 1, 1, UIFont.Small)
            elseif not learningState.active then
                -- Show "CLAIM" button (normal state) - teal theme
                self:drawRect(btnX, btnY, btnW, btnH, 0.7, 0.2, 0.45, 0.5)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.3, 0.6, 0.7)
                local btnText = getText("UI_BurdJournals_BtnClaim")
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.9, 1, 1, 1, UIFont.Small)
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
    local currentTab = self.currentTab or "skills"

    -- ============ SKILLS TAB ============
    if currentTab == "skills" then
        -- Count skills
        local skillCount = 0
        if journalData and journalData.skills then
            for skillName, _ in pairs(journalData.skills) do
                if not BurdJournals.isSkillClaimed(self.journal, skillName) then
                    skillCount = skillCount + 1
                end
            end
        end

        -- Add skill rows (no header needed with tabs)
        if journalData and journalData.skills then
            local hasSkills = false
            local matchCount = 0
            for skillName, skillData in pairs(journalData.skills) do
                hasSkills = true
                local isClaimed = BurdJournals.isSkillClaimed(self.journal, skillName)
                local displayName = BurdJournals.getPerkDisplayName(skillName)
                -- Apply search filter
                if self:matchesSearch(displayName) then
                    matchCount = matchCount + 1
                    self.skillList:addItem(skillName, {
                        isSkill = true,
                        skillName = skillName,
                        displayName = displayName,
                        xp = skillData.xp or 0,
                        level = skillData.level or 0,
                        isClaimed = isClaimed
                    })
                end
            end
            if not hasSkills then
                self.skillList:addItem("empty", {isEmpty = true, text = getText("UI_BurdJournals_NoSkillsRecorded")})
            elseif matchCount == 0 and self.searchQuery and self.searchQuery ~= "" then
                self.skillList:addItem("no_results", {isEmpty = true, text = getText("UI_BurdJournals_NoSearchResults") or "No results found"})
            end
        else
            self.skillList:addItem("empty", {isEmpty = true, text = getText("UI_BurdJournals_NoSkillsRecorded")})
        end

    -- ============ TRAITS TAB ============
    elseif currentTab == "traits" then
        if hasBloodyOrigin and journalData and journalData.traits then
            local hasTraits = false
            local matchCount = 0
            for traitId, traitData in pairs(journalData.traits) do
                hasTraits = true
                local isClaimed = BurdJournals.isTraitClaimed(self.journal, traitId)
                local alreadyKnown = BurdJournals.playerHasTrait(self.player, traitId)
                local traitName = safeGetTraitName(traitId)
                local traitTexture = getTraitTexture(traitId)
                local isPositive = isTraitPositive(traitId)
                -- Apply search filter
                if self:matchesSearch(traitName) then
                    matchCount = matchCount + 1
                    self.skillList:addItem(traitId, {
                        isTrait = true,
                        traitId = traitId,
                        traitName = traitName,
                        traitTexture = traitTexture,
                        isClaimed = isClaimed,
                        alreadyKnown = alreadyKnown,
                        isPositive = isPositive  -- true = positive (green), false = negative (red), nil = unknown
                    })
                end
            end
            if not hasTraits then
                self.skillList:addItem("empty_traits", {isEmpty = true, text = "No rare traits found"})
            elseif matchCount == 0 and self.searchQuery and self.searchQuery ~= "" then
                self.skillList:addItem("no_results", {isEmpty = true, text = getText("UI_BurdJournals_NoSearchResults") or "No results found"})
            end
        else
            self.skillList:addItem("empty_traits", {isEmpty = true, text = getText("UI_BurdJournals_NoTraitsAvailable")})
        end

    -- ============ RECIPES TAB ============
    elseif currentTab == "recipes" then
        if journalData and journalData.recipes then
            local hasRecipes = false
            local matchCount = 0
            for recipeName, recipeData in pairs(journalData.recipes) do
                hasRecipes = true
                local isClaimed = BurdJournals.isRecipeClaimed(self.journal, recipeName)
                local alreadyKnown = BurdJournals.playerKnowsRecipe(self.player, recipeName)
                local displayName = BurdJournals.getRecipeDisplayName(recipeName)
                local magazineSource = recipeData.source or BurdJournals.getMagazineForRecipe(recipeName)
                -- Apply search filter
                if self:matchesSearch(displayName) then
                    matchCount = matchCount + 1
                    self.skillList:addItem(recipeName, {
                        isRecipe = true,
                        recipeName = recipeName,
                        displayName = displayName,
                        magazineSource = magazineSource,
                        isClaimed = isClaimed,
                        alreadyKnown = alreadyKnown
                    })
                end
            end
            if not hasRecipes then
                self.skillList:addItem("empty_recipes", {isEmpty = true, text = getText("UI_BurdJournals_NoRecipesRecorded")})
            elseif matchCount == 0 and self.searchQuery and self.searchQuery ~= "" then
                self.skillList:addItem("no_results", {isEmpty = true, text = getText("UI_BurdJournals_NoSearchResults") or "No results found"})
            end
        else
            self.skillList:addItem("empty_recipes", {isEmpty = true, text = getText("UI_BurdJournals_NoRecipesAvailable")})
        end
    end
end

-- ==================== REFRESH THE LIST ====================

function BurdJournals.UI.MainPanel:refreshAbsorptionList()
    print("[BurdJournals] UI: refreshAbsorptionList called")
    -- Re-count totals
    local journalData = BurdJournals.getJournalData(self.journal)
    local hasBloodyOrigin = BurdJournals.hasBloodyOrigin(self.journal)
    -- Debug: show claimed count
    local claimedCount = journalData and journalData.claimedSkills and BurdJournals.countTable(journalData.claimedSkills) or 0
    print("[BurdJournals] UI: refreshAbsorptionList sees claimedSkills count: " .. tostring(claimedCount))

    local skillCount = 0
    local traitCount = 0
    local recipeCount = 0
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
    if journalData and journalData.recipes then
        for recipeName, _ in pairs(journalData.recipes) do
            if not BurdJournals.isRecipeClaimed(self.journal, recipeName) then
                recipeCount = recipeCount + 1
            end
        end
    end

    self.skillCount = skillCount
    self.traitCount = traitCount
    self.recipeCount = recipeCount
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

-- Get display name for current tab (used in tab-specific buttons)
function BurdJournals.UI.MainPanel:getTabDisplayName(tabId)
    local tabNames = {
        skills = getText("UI_BurdJournals_TabSkills") or "Skills",
        traits = getText("UI_BurdJournals_TabTraits") or "Traits",
        recipes = getText("UI_BurdJournals_TabRecipes") or "Recipes",
        stats = getText("UI_BurdJournals_TabStats") or "Stats",
        charinfo = getText("UI_BurdJournals_TabStats") or "Stats",  -- charinfo is stats in view mode
    }
    return tabNames[tabId] or "Items"
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

-- Start learning a single skill (uses ISTimedActionQueue)
function BurdJournals.UI.MainPanel:startLearningSkill(skillName, xp)
    if self.learningState.active then
        -- Already learning something
        return false
    end

    -- Build rewards array
    local rewards = {{type = "skill", name = skillName, xp = xp}}

    -- Queue the timed action (respects game pause)
    if BurdJournals.queueLearnAction then
        return BurdJournals.queueLearnAction(self.player, self.journal, rewards, false, self)
    end

    -- Fallback to old system if timed actions not loaded
    self.learningState = {
        active = true,
        skillName = skillName,
        traitId = nil,
        isAbsorbAll = false,
        progress = 0,
        totalTime = self:getSkillLearningTime(),
        startTime = getTimestampMs(),
        pendingRewards = rewards,
        currentIndex = 1,
        queue = {},
    }

    -- Register tick handler
    Events.OnTick.Add(BurdJournals.UI.MainPanel.onLearningTickStatic)

    -- Play page turn sound
    self:playSound(BurdJournals.Sounds.PAGE_TURN)

    return true
end

-- Start learning a single trait (uses ISTimedActionQueue)
function BurdJournals.UI.MainPanel:startLearningTrait(traitId)
    if self.learningState.active then
        return false
    end

    -- Build rewards array
    local rewards = {{type = "trait", name = traitId}}

    -- Queue the timed action (respects game pause)
    if BurdJournals.queueLearnAction then
        return BurdJournals.queueLearnAction(self.player, self.journal, rewards, false, self)
    end

    -- Fallback to old system if timed actions not loaded
    self.learningState = {
        active = true,
        skillName = nil,
        traitId = traitId,
        isAbsorbAll = false,
        progress = 0,
        totalTime = self:getTraitLearningTime(),
        startTime = getTimestampMs(),
        pendingRewards = rewards,
        currentIndex = 1,
        queue = {},
    }

    Events.OnTick.Add(BurdJournals.UI.MainPanel.onLearningTickStatic)

    -- Play page turn sound
    self:playSound(BurdJournals.Sounds.PAGE_TURN)

    return true
end

function BurdJournals.UI.MainPanel:startLearningRecipe(recipeName)
    if self.learningState.active then
        return false
    end

    -- Build rewards array
    local rewards = {{type = "recipe", name = recipeName}}

    -- Queue the timed action (respects game pause)
    if BurdJournals.queueLearnAction then
        return BurdJournals.queueLearnAction(self.player, self.journal, rewards, false, self)
    end

    -- Fallback to old system if timed actions not loaded
    self.learningState = {
        active = true,
        skillName = nil,
        traitId = nil,
        recipeName = recipeName,
        isAbsorbAll = false,
        progress = 0,
        totalTime = self:getRecipeLearningTime(),
        startTime = getTimestampMs(),
        pendingRewards = rewards,
        currentIndex = 1,
        queue = {},
    }

    Events.OnTick.Add(BurdJournals.UI.MainPanel.onLearningTickStatic)

    -- Play page turn sound
    self:playSound(BurdJournals.Sounds.PAGE_TURN)

    return true
end

-- Get learning time for a recipe (in seconds)
function BurdJournals.UI.MainPanel:getRecipeLearningTime()
    local baseTime = BurdJournals.getSandboxOption("LearningTimePerRecipe") or 2.0
    local multiplier = BurdJournals.getSandboxOption("LearningTimeMultiplier") or 1.0
    local readingMultiplier = self:getReadingSpeedMultiplier()
    return baseTime * multiplier * readingMultiplier
end

-- Start learning all available rewards (Absorb All) - uses ISTimedActionQueue
function BurdJournals.UI.MainPanel:startLearningAll()
    if self.learningState.active then
        return false
    end

    local journalData = BurdJournals.getJournalData(self.journal)
    if not journalData then return false end

    local isPlayerJournal = self.isPlayerJournal or self.mode == "view"
    local hasBloodyOrigin = BurdJournals.hasBloodyOrigin(self.journal)
    local pendingRewards = {}

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
            end
        end
    end

    if #pendingRewards == 0 then
        self:showFeedback(getText("UI_BurdJournals_NoNewRewards"), {r=0.7, g=0.7, b=0.5})
        return false
    end

    -- Queue the timed action (respects game pause)
    if BurdJournals.queueLearnAction then
        return BurdJournals.queueLearnAction(self.player, self.journal, pendingRewards, true, self)
    end

    -- Fallback to old system if timed actions not loaded
    local totalTime = 0
    for _, reward in ipairs(pendingRewards) do
        if reward.type == "skill" then
            totalTime = totalTime + self:getSkillLearningTime()
        else
            totalTime = totalTime + self:getTraitLearningTime()
        end
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

-- Start learning only rewards from a specific tab (Absorb Tab / Claim Tab)
function BurdJournals.UI.MainPanel:startLearningTab(tabId)
    if self.learningState.active then
        return false
    end

    local journalData = BurdJournals.getJournalData(self.journal)
    if not journalData then return false end

    local isPlayerJournal = self.isPlayerJournal or self.mode == "view"
    local hasBloodyOrigin = BurdJournals.hasBloodyOrigin(self.journal)
    local pendingRewards = {}

    -- Filter rewards based on the tab type
    if tabId == "skills" then
        -- Collect skills
        if journalData.skills then
            for skillName, skillData in pairs(journalData.skills) do
                local shouldInclude = false

                if isPlayerJournal then
                    local perk = BurdJournals.getPerkByName(skillName)
                    if perk then
                        local playerXP = self.player:getXp():getXP(perk)
                        if playerXP < (skillData.xp or 0) then
                            shouldInclude = true
                        end
                    end
                else
                    if not BurdJournals.isSkillClaimed(self.journal, skillName) then
                        shouldInclude = true
                    end
                end

                if shouldInclude then
                    table.insert(pendingRewards, {type = "skill", name = skillName, xp = skillData.xp})
                end
            end
        end

    elseif tabId == "traits" then
        -- Collect traits
        local hasTraits = (isPlayerJournal and journalData.traits) or (hasBloodyOrigin and journalData.traits)
        if hasTraits then
            for traitId, _ in pairs(journalData.traits) do
                local shouldInclude = false

                if isPlayerJournal then
                    if not BurdJournals.playerHasTrait(self.player, traitId) then
                        shouldInclude = true
                    end
                else
                    if not BurdJournals.isTraitClaimed(self.journal, traitId) then
                        shouldInclude = true
                    end
                end

                if shouldInclude then
                    table.insert(pendingRewards, {type = "trait", name = traitId})
                end
            end
        end

    elseif tabId == "recipes" then
        -- Collect recipes
        if journalData.recipes then
            for recipeName, _ in pairs(journalData.recipes) do
                local shouldInclude = false

                if isPlayerJournal then
                    -- For player journals, check if player doesn't know the recipe
                    if not BurdJournals.playerKnowsRecipe(self.player, recipeName) then
                        shouldInclude = true
                    end
                else
                    -- For worn/bloody, check if not claimed
                    if not BurdJournals.isRecipeClaimed(self.journal, recipeName) then
                        shouldInclude = true
                    end
                end

                if shouldInclude then
                    table.insert(pendingRewards, {type = "recipe", name = recipeName})
                end
            end
        end
    end

    if #pendingRewards == 0 then
        local tabName = self:getTabDisplayName(tabId)
        self:showFeedback(getText("UI_BurdJournals_NoNewRewards") or "No new rewards", {r=0.7, g=0.7, b=0.5})
        return false
    end

    -- Queue the timed action (respects game pause)
    if BurdJournals.queueLearnAction then
        return BurdJournals.queueLearnAction(self.player, self.journal, pendingRewards, true, self)
    end

    -- Fallback to old system if timed actions not loaded
    local totalTime = 0
    for _, reward in ipairs(pendingRewards) do
        if reward.type == "skill" then
            totalTime = totalTime + self:getSkillLearningTime()
        elseif reward.type == "trait" then
            totalTime = totalTime + self:getTraitLearningTime()
        elseif reward.type == "recipe" then
            totalTime = totalTime + self:getRecipeLearningTime()
        end
    end

    self.learningState = {
        active = true,
        skillName = nil,
        traitId = nil,
        recipeName = nil,
        isAbsorbAll = true,  -- Use the same progress bar behavior as Absorb All
        progress = 0,
        totalTime = totalTime,
        startTime = getTimestampMs(),
        pendingRewards = pendingRewards,
        currentIndex = 1,
        queue = {},
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

        -- Cancel timed action if using new system
        if self.learningState.timedAction and ISTimedActionQueue then
            ISTimedActionQueue.clear(self.player)
        end
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

-- Start recording a single skill (uses ISTimedActionQueue)
function BurdJournals.UI.MainPanel:startRecordingSkill(skillName, xp, level)
    if self.recordingState and self.recordingState.active then
        return false
    end

    if not self.recordingState then
        self.recordingState = {}
    end

    -- Build records array
    local records = {{type = "skill", name = skillName, xp = xp, level = level}}

    -- Queue the timed action (respects game pause)
    if BurdJournals.queueRecordAction then
        return BurdJournals.queueRecordAction(self.player, self.journal, records, false, self)
    end

    -- Fallback to old system if timed actions not loaded
    self.recordingState = {
        active = true,
        skillName = skillName,
        traitId = nil,
        isRecordAll = false,
        progress = 0,
        totalTime = self:getSkillRecordingTime(),
        startTime = getTimestampMs(),
        pendingRecords = records,
        currentIndex = 1,
        queue = {},
    }

    Events.OnTick.Add(BurdJournals.UI.MainPanel.onRecordingTickStatic)
    return true
end

-- Start recording a single trait (uses ISTimedActionQueue)
function BurdJournals.UI.MainPanel:startRecordingTrait(traitId)
    if self.recordingState and self.recordingState.active then
        return false
    end

    if not self.recordingState then
        self.recordingState = {}
    end

    -- Build records array
    local records = {{type = "trait", name = traitId}}

    -- Queue the timed action (respects game pause)
    if BurdJournals.queueRecordAction then
        return BurdJournals.queueRecordAction(self.player, self.journal, records, false, self)
    end

    -- Fallback to old system if timed actions not loaded
    self.recordingState = {
        active = true,
        skillName = nil,
        traitId = traitId,
        isRecordAll = false,
        progress = 0,
        totalTime = self:getTraitRecordingTime(),
        startTime = getTimestampMs(),
        pendingRecords = records,
        currentIndex = 1,
        queue = {},
    }

    Events.OnTick.Add(BurdJournals.UI.MainPanel.onRecordingTickStatic)
    return true
end

-- Start recording a single stat (uses ISTimedActionQueue)
function BurdJournals.UI.MainPanel:startRecordingStat(statId, value)
    if self.recordingState and self.recordingState.active then
        return false
    end

    if not self.recordingState then
        self.recordingState = {}
    end

    -- Build records array
    local records = {{type = "stat", name = statId, value = value}}

    -- Queue the timed action (respects game pause)
    if BurdJournals.queueRecordAction then
        return BurdJournals.queueRecordAction(self.player, self.journal, records, false, self)
    end

    -- Fallback to old system if timed actions not loaded
    self.recordingState = {
        active = true,
        skillName = nil,
        traitId = nil,
        statId = statId,
        isRecordAll = false,
        progress = 0,
        totalTime = self:getStatRecordingTime(),
        startTime = getTimestampMs(),
        pendingRecords = records,
        currentIndex = 1,
        queue = {},
    }

    Events.OnTick.Add(BurdJournals.UI.MainPanel.onRecordingTickStatic)
    return true
end

-- Get recording time for stats (uses skill time as base)
function BurdJournals.UI.MainPanel:getStatRecordingTime()
    return self:getSkillRecordingTime()
end

-- Get recording time for recipes (half of learning time, like skills/traits)
function BurdJournals.UI.MainPanel:getRecipeRecordingTime()
    local baseTime = (BurdJournals.getSandboxOption("LearningTimePerRecipe") or 5.0) * 0.5
    local multiplier = BurdJournals.getSandboxOption("LearningTimeMultiplier") or 1.0
    return baseTime * multiplier
end

-- Start recording a single recipe (uses ISTimedActionQueue)
function BurdJournals.UI.MainPanel:startRecordingRecipe(recipeName)
    if self.recordingState and self.recordingState.active then
        return false
    end

    if not self.recordingState then
        self.recordingState = {}
    end

    -- Build records array
    local records = {{type = "recipe", name = recipeName}}

    -- Queue the timed action (respects game pause)
    if BurdJournals.queueRecordAction then
        return BurdJournals.queueRecordAction(self.player, self.journal, records, false, self)
    end

    -- Fallback to old system if timed actions not loaded
    self.recordingState = {
        active = true,
        skillName = nil,
        traitId = nil,
        statId = nil,
        recipeName = recipeName,
        isRecordAll = false,
        progress = 0,
        totalTime = self:getRecipeRecordingTime(),
        startTime = getTimestampMs(),
        pendingRecords = records,
        currentIndex = 1,
        queue = {},
    }

    Events.OnTick.Add(BurdJournals.UI.MainPanel.onRecordingTickStatic)
    return true
end

-- Start recording all skills, traits, and stats (uses ISTimedActionQueue)
function BurdJournals.UI.MainPanel:startRecordingAll()
    if self.recordingState and self.recordingState.active then
        return false
    end

    if not self.recordingState then
        self.recordingState = {}
    end

    local pendingRecords = {}

    local allowedSkills = BurdJournals.getAllowedSkills()
    local recordedSkills = self.recordedSkills or {}
    local recordedTraits = self.recordedTraits or {}

    -- Collect all recordable skills (respecting baseline restriction)
    local useBaseline = BurdJournals.isBaselineRestrictionEnabled()
    for _, skillName in ipairs(allowedSkills) do
        local perk = BurdJournals.getPerkByName(skillName)
        if perk then
            local currentXP = self.player:getXp():getXP(perk)
            local currentLevel = self.player:getPerkLevel(perk)
            local recordedData = recordedSkills[skillName]
            local recordedXP = recordedData and recordedData.xp or 0

            -- Get baseline XP (what player spawned with)
            local baselineXP = 0
            if useBaseline then
                baselineXP = BurdJournals.getSkillBaseline(self.player, skillName)
            end

            -- Calculate earned XP (current - baseline)
            local earnedXP = math.max(0, currentXP - baselineXP)

            -- Can only record if player has earned XP above baseline AND it's higher than recorded
            if earnedXP > 0 and earnedXP > recordedXP then
                table.insert(pendingRecords, {type = "skill", name = skillName, xp = earnedXP, level = currentLevel})
            end
        end
    end

    -- Collect all recordable traits (excluding starting traits)
    local playerTraits = BurdJournals.collectPlayerTraits(self.player)
    local traitBaseline = BurdJournals.getTraitBaseline(self.player) or {}
    local grantableTraits = (BurdJournals.getGrantableTraits and BurdJournals.getGrantableTraits()) or BurdJournals.GRANTABLE_TRAITS or {}
    for traitId, _ in pairs(playerTraits) do
        -- Check if this is a grantable trait (handles profession variants like soto:slaughterer2)
        local isGrantable = BurdJournals.isTraitGrantable(traitId, grantableTraits)
        -- Check if player started with this trait (baseline)
        local isStartingTrait = traitBaseline[traitId] or traitBaseline[string.lower(traitId)]
        -- Check if already recorded
        local isRecorded = recordedTraits[traitId]

        if isGrantable and not isStartingTrait and not isRecorded then
            table.insert(pendingRecords, {type = "trait", name = traitId})
        end
    end

    -- Collect all recordable stats (only if enabled)
    if BurdJournals.getSandboxOption("EnableStatRecording") then
        for _, stat in ipairs(BurdJournals.RECORDABLE_STATS) do
            if BurdJournals.isStatEnabled(stat.id) then
                local canUpdate, currentVal, _ = BurdJournals.canUpdateStat(self.journal, stat.id, self.player)
                if canUpdate then
                    table.insert(pendingRecords, {type = "stat", name = stat.id, value = currentVal})
                end
            end
        end
    end

    -- Collect all recordable recipes (only if enabled)
    if BurdJournals.getSandboxOption("EnableRecipeRecording") then
        local recordedRecipes = self.recordedRecipes or {}
        local playerRecipes = BurdJournals.collectPlayerMagazineRecipes(self.player)
        for recipeName, recipeData in pairs(playerRecipes) do
            if not recordedRecipes[recipeName] then
                table.insert(pendingRecords, {type = "recipe", name = recipeName})
            end
        end
    end

    if #pendingRecords == 0 then
        self:showFeedback(getText("UI_BurdJournals_NothingNewToRecord") or "Nothing new to record", {r=0.7, g=0.7, b=0.5})
        return false
    end

    -- Queue the timed action (respects game pause)
    if BurdJournals.queueRecordAction then
        return BurdJournals.queueRecordAction(self.player, self.journal, pendingRecords, true, self)
    end

    -- Fallback to old system if timed actions not loaded
    local totalTime = 0
    for _, record in ipairs(pendingRecords) do
        if record.type == "skill" then
            totalTime = totalTime + self:getSkillRecordingTime()
        elseif record.type == "trait" then
            totalTime = totalTime + self:getTraitRecordingTime()
        elseif record.type == "recipe" then
            totalTime = totalTime + self:getRecipeRecordingTime()
        else
            totalTime = totalTime + self:getStatRecordingTime()
        end
    end

    self.recordingState = {
        active = true,
        skillName = nil,
        traitId = nil,
        recipeName = nil,
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

-- Start recording only items from a specific tab (Record Tab)
function BurdJournals.UI.MainPanel:startRecordingTab(tabId)
    if self.recordingState and self.recordingState.active then
        return false
    end

    if not self.recordingState then
        self.recordingState = {}
    end

    local pendingRecords = {}

    local recordedSkills = self.recordedSkills or {}
    local recordedTraits = self.recordedTraits or {}

    -- Filter records based on the tab type
    if tabId == "skills" then
        -- Collect recordable skills
        local allowedSkills = BurdJournals.getAllowedSkills()
        local useBaseline = BurdJournals.isBaselineRestrictionEnabled()
        for _, skillName in ipairs(allowedSkills) do
            local perk = BurdJournals.getPerkByName(skillName)
            if perk then
                local currentXP = self.player:getXp():getXP(perk)
                local currentLevel = self.player:getPerkLevel(perk)
                local recordedData = recordedSkills[skillName]
                local recordedXP = recordedData and recordedData.xp or 0

                local baselineXP = 0
                if useBaseline then
                    baselineXP = BurdJournals.getSkillBaseline(self.player, skillName)
                end

                local earnedXP = math.max(0, currentXP - baselineXP)

                if earnedXP > 0 and earnedXP > recordedXP then
                    table.insert(pendingRecords, {type = "skill", name = skillName, xp = earnedXP, level = currentLevel})
                end
            end
        end

    elseif tabId == "traits" then
        -- Collect recordable traits
        local playerTraits = BurdJournals.collectPlayerTraits(self.player)
        local traitBaseline = BurdJournals.getTraitBaseline(self.player) or {}
        local grantableTraits = (BurdJournals.getGrantableTraits and BurdJournals.getGrantableTraits()) or BurdJournals.GRANTABLE_TRAITS or {}
        for traitId, _ in pairs(playerTraits) do
            -- Use isTraitGrantable which handles profession variants (e.g., soto:slaughterer2)
            local isGrantable = BurdJournals.isTraitGrantable(traitId, grantableTraits)
            local isStartingTrait = traitBaseline[traitId] or traitBaseline[string.lower(traitId)]
            local isRecorded = recordedTraits[traitId]

            if isGrantable and not isStartingTrait and not isRecorded then
                table.insert(pendingRecords, {type = "trait", name = traitId})
            end
        end

    elseif tabId == "recipes" then
        -- Collect recordable recipes
        if BurdJournals.getSandboxOption("EnableRecipeRecording") then
            local recordedRecipes = self.recordedRecipes or {}
            local playerRecipes = BurdJournals.collectPlayerMagazineRecipes(self.player)
            for recipeName, recipeData in pairs(playerRecipes) do
                if not recordedRecipes[recipeName] then
                    table.insert(pendingRecords, {type = "recipe", name = recipeName})
                end
            end
        end

    elseif tabId == "stats" then
        -- Collect recordable stats
        if BurdJournals.getSandboxOption("EnableStatRecording") then
            for _, stat in ipairs(BurdJournals.RECORDABLE_STATS) do
                if BurdJournals.isStatEnabled(stat.id) then
                    local canUpdate, currentVal, _ = BurdJournals.canUpdateStat(self.journal, stat.id, self.player)
                    if canUpdate then
                        table.insert(pendingRecords, {type = "stat", name = stat.id, value = currentVal})
                    end
                end
            end
        end
    end

    if #pendingRecords == 0 then
        self:showFeedback(getText("UI_BurdJournals_NothingNewToRecord") or "Nothing new to record", {r=0.7, g=0.7, b=0.5})
        return false
    end

    -- Queue the timed action (respects game pause)
    if BurdJournals.queueRecordAction then
        return BurdJournals.queueRecordAction(self.player, self.journal, pendingRecords, true, self)
    end

    -- Fallback to old system if timed actions not loaded
    local totalTime = 0
    for _, record in ipairs(pendingRecords) do
        if record.type == "skill" then
            totalTime = totalTime + self:getSkillRecordingTime()
        elseif record.type == "trait" then
            totalTime = totalTime + self:getTraitRecordingTime()
        elseif record.type == "recipe" then
            totalTime = totalTime + self:getRecipeRecordingTime()
        else
            totalTime = totalTime + self:getStatRecordingTime()
        end
    end

    self.recordingState = {
        active = true,
        skillName = nil,
        traitId = nil,
        recipeName = nil,
        isRecordAll = true,  -- Use same progress bar behavior
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

        -- Cancel timed action if using new system
        if self.recordingState.timedAction and ISTimedActionQueue then
            ISTimedActionQueue.clear(self.player)
        end
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
                instance:showFeedback(getText("UI_BurdJournals_JournalSyncFailed") or "Error: Journal sync failed", {r=0.8, g=0.3, b=0.3})
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

    -- Collect skills, traits, and stats to send to server
    local skillsToRecord = {}
    local traitsToRecord = {}
    local statsToRecord = {}
    local skillCount = 0
    local traitCount = 0
    local statCount = 0

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
        elseif record.type == "stat" then
            statsToRecord[record.name] = {
                value = record.value
            }
            statCount = statCount + 1
        end
    end

    -- Store pending counts for feedback after server response
    self.pendingRecordFeedback = {
        skills = skillCount,
        traits = traitCount,
        stats = statCount
    }

    -- Send to server - server handles modData update and journal conversion
    -- In SP, the server's sendToClient defers the client handler to next tick
    -- In MP, the server response comes back asynchronously via OnServerCommand
    -- Either way, handleRecordSuccess will be called to update UI with authoritative data
    sendClientCommand(self.player, "BurdJournals", "recordProgress", {
        journalId = self.journal:getID(),
        skills = skillsToRecord,
        traits = traitsToRecord,
        stats = statsToRecord
    })

    -- Show pending feedback (will be updated when server responds via handleRecordSuccess)
    self:showFeedback(getText("UI_BurdJournals_SavingProgress") or "Saving progress...", {r=0.7, g=0.7, b=0.7})

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
                statId = nil,
                recipeName = nil,
                isRecordAll = false,
                progress = 0,
                totalTime = self:getSkillRecordingTime(),
                startTime = getTimestampMs(),
                pendingRecords = {{type = "skill", name = nextRecord.name, xp = nextRecord.xp, level = nextRecord.level}},
                currentIndex = 1,
                queue = savedQueue,
            }
        elseif nextRecord.type == "trait" then
            self.recordingState = {
                active = true,
                skillName = nil,
                traitId = nextRecord.name,
                statId = nil,
                recipeName = nil,
                isRecordAll = false,
                progress = 0,
                totalTime = self:getTraitRecordingTime(),
                startTime = getTimestampMs(),
                pendingRecords = {{type = "trait", name = nextRecord.name}},
                currentIndex = 1,
                queue = savedQueue,
            }
        elseif nextRecord.type == "stat" then
            self.recordingState = {
                active = true,
                skillName = nil,
                traitId = nil,
                statId = nextRecord.name,
                recipeName = nil,
                isRecordAll = false,
                progress = 0,
                totalTime = self:getStatRecordingTime(),
                startTime = getTimestampMs(),
                pendingRecords = {{type = "stat", name = nextRecord.name, value = nextRecord.value or nextRecord.xp}},
                currentIndex = 1,
                queue = savedQueue,
            }
        elseif nextRecord.type == "recipe" then
            self.recordingState = {
                active = true,
                skillName = nil,
                traitId = nil,
                statId = nil,
                recipeName = nextRecord.name,
                isRecordAll = false,
                progress = 0,
                totalTime = self:getRecipeRecordingTime(),
                startTime = getTimestampMs(),
                pendingRecords = {{type = "recipe", name = nextRecord.name}},
                currentIndex = 1,
                queue = savedQueue,
            }
        end
        
        -- Re-register tick handler for next item (remove first to avoid duplicates)
        Events.OnTick.Remove(BurdJournals.UI.MainPanel.onRecordingTickStatic)
        Events.OnTick.Add(BurdJournals.UI.MainPanel.onRecordingTickStatic)

        -- Note: Don't refresh list here - handleRecordSuccess already refreshed with
        -- authoritative data from server. The UI will update via onRecordingTick.

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

    -- Note: Don't refresh list here - handleRecordSuccess will be called by the server
    -- response (synchronously in SP, asynchronously in MP) and will refresh with the
    -- authoritative data. Refreshing here would use potentially stale modData in SP.
    -- The server's recordSuccess response includes journalData which bypasses timing issues.
end

-- Record a skill (starts timed recording)
function BurdJournals.UI.MainPanel:recordSkill(skillName, xp, level)
    -- If already recording, add to queue
    if self.recordingState and self.recordingState.active and not self.recordingState.isRecordAll then
        if self:addToRecordQueue("skill", skillName, xp, level) then
            local displayName = BurdJournals.getPerkDisplayName(skillName) or skillName
            self:showFeedback(string.format(getText("UI_BurdJournals_Queued") or "Queued: %s", displayName), {r=0.5, g=0.7, b=0.8})
        else
            self:showFeedback(getText("UI_BurdJournals_AlreadyQueued") or "Already queued", {r=0.9, g=0.7, b=0.3})
        end
        return
    end

    if not self:startRecordingSkill(skillName, xp, level) then
        self:showFeedback(getText("UI_BurdJournals_CannotRecord") or "Cannot record", {r=0.9, g=0.5, b=0.3})
    end
end

-- Record a trait (starts timed recording)
function BurdJournals.UI.MainPanel:recordTrait(traitId)
    -- If already recording, add to queue
    if self.recordingState and self.recordingState.active and not self.recordingState.isRecordAll then
        if self:addToRecordQueue("trait", traitId) then
            local traitName = safeGetTraitName(traitId)
            self:showFeedback(string.format(getText("UI_BurdJournals_Queued") or "Queued: %s", traitName), {r=0.5, g=0.7, b=0.8})
        else
            self:showFeedback(getText("UI_BurdJournals_AlreadyQueued") or "Already queued", {r=0.9, g=0.7, b=0.3})
        end
        return
    end

    if not self:startRecordingTrait(traitId) then
        self:showFeedback(getText("UI_BurdJournals_CannotRecord") or "Cannot record", {r=0.9, g=0.5, b=0.3})
    end
end

-- Record a stat (starts timed recording)
function BurdJournals.UI.MainPanel:recordStat(statId, value)
    -- If already recording, add to queue
    if self.recordingState and self.recordingState.active and not self.recordingState.isRecordAll then
        if self:addToRecordQueue("stat", statId, value) then
            local stat = BurdJournals.getStatById(statId)
            local statName = stat and stat.name or statId
            self:showFeedback(string.format(getText("UI_BurdJournals_Queued") or "Queued: %s", statName), {r=0.5, g=0.7, b=0.8})
        else
            self:showFeedback(getText("UI_BurdJournals_AlreadyQueued") or "Already queued", {r=0.9, g=0.7, b=0.3})
        end
        return
    end

    if not self:startRecordingStat(statId, value) then
        self:showFeedback(getText("UI_BurdJournals_CannotRecord") or "Cannot record", {r=0.9, g=0.5, b=0.3})
    end
end

-- Record a recipe (starts timed recording)
function BurdJournals.UI.MainPanel:recordRecipe(recipeName)
    -- If already recording, add to queue
    if self.recordingState and self.recordingState.active and not self.recordingState.isRecordAll then
        if self:addToRecordQueue("recipe", recipeName) then
            local displayName = BurdJournals.getRecipeDisplayName(recipeName) or recipeName
            self:showFeedback(string.format(getText("UI_BurdJournals_Queued") or "Queued: %s", displayName), {r=0.5, g=0.7, b=0.8})
        else
            self:showFeedback(getText("UI_BurdJournals_AlreadyQueued") or "Already queued", {r=0.9, g=0.7, b=0.3})
        end
        return
    end

    if not self:startRecordingRecipe(recipeName) then
        self:showFeedback(getText("UI_BurdJournals_CannotRecord") or "Cannot record", {r=0.9, g=0.5, b=0.3})
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

    -- Skip individual refreshes during batch processing - we'll do one refresh at the end
    local skipRefresh = true

    for _, reward in ipairs(self.learningState.pendingRewards) do
        if reward.type == "skill" then
            if isPlayerJournal then
                self:sendClaimSkill(reward.name, reward.xp, skipRefresh)
            else
                self:sendAbsorbSkill(reward.name, reward.xp, skipRefresh)
            end
        elseif reward.type == "trait" then
            if isPlayerJournal then
                self:sendClaimTrait(reward.name, skipRefresh)
            else
                self:sendAbsorbTrait(reward.name, skipRefresh)
            end
        elseif reward.type == "recipe" then
            if isPlayerJournal then
                self:sendClaimRecipe(reward.name, skipRefresh)
            else
                self:sendAbsorbRecipe(reward.name, skipRefresh)
            end
        end
    end

    -- Do a single refresh after all claims are processed
    -- The claim status is updated synchronously (via BurdJournals.claimSkill/claimTrait),
    -- so the UI will correctly show items as claimed immediately.
    -- Note: sendAddXp is async, but the UI shows claim status, not XP values, so this is fine.
    self:refreshPlayer()
    if isPlayerJournal then
        if self.refreshJournalData then
            self:refreshJournalData()
        end
    else
        if self.refreshAbsorptionList then
            self:refreshAbsorptionList()
        end
    end

    -- Check if journal should dissolve (all items claimed)
    if self.checkDissolution then
        self:checkDissolution()
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
                recipeName = nil,
                isAbsorbAll = false,
                progress = 0,
                totalTime = self:getSkillLearningTime(),
                startTime = getTimestampMs(),
                pendingRewards = {{type = "skill", name = nextReward.name, xp = nextReward.xp}},
                currentIndex = 1,
                queue = savedQueue,
            }
        elseif nextReward.type == "trait" then
            self.learningState = {
                active = true,
                skillName = nil,
                traitId = nextReward.name,
                recipeName = nil,
                isAbsorbAll = false,
                progress = 0,
                totalTime = self:getTraitLearningTime(),
                startTime = getTimestampMs(),
                pendingRewards = {{type = "trait", name = nextReward.name}},
                currentIndex = 1,
                queue = savedQueue,
            }
        elseif nextReward.type == "recipe" then
            self.learningState = {
                active = true,
                skillName = nil,
                traitId = nil,
                recipeName = nextReward.name,
                isAbsorbAll = false,
                progress = 0,
                totalTime = self:getRecipeLearningTime(),
                startTime = getTimestampMs(),
                pendingRewards = {{type = "recipe", name = nextReward.name}},
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
        recipeName = nil,
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
-- In single player, apply XP directly like Skill Recovery Journal does
-- skipRefresh: optional, if true, don't refresh UI (used for batch operations)
function BurdJournals.UI.MainPanel:sendAbsorbSkill(skillName, xp)
    local journalId = self.journal:getID()
    -- In MP (isClient and not isServer), send command to server
    -- In SP (isClient and isServer), fall through to direct application
    if isClient() and not isServer() then
        sendClientCommand(self.player, "BurdJournals", "absorbSkill", {
            journalId = journalId,
            skillName = skillName
        })
    else
        -- Single player: apply directly using the existing function
        self:applySkillXPDirectly(skillName, xp)
    end
end

-- Send trait absorption command to server (actual application)
function BurdJournals.UI.MainPanel:sendAbsorbTrait(traitId)
    local journalId = self.journal:getID()
    -- In MP (isClient and not isServer), send command to server
    -- In SP (isClient and isServer), fall through to direct application
    if isClient() and not isServer() then
        sendClientCommand(self.player, "BurdJournals", "absorbTrait", {
            journalId = journalId,
            traitId = traitId
        })
    else
        -- Single player: apply directly using the existing function
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

    -- In MP (isClient and not isServer), send command to server
    -- In SP (isClient and isServer), fall through to direct application
    if isClient() and not isServer() then
        sendClientCommand(self.player, "BurdJournals", "claimSkill", {
            journalId = journalId,
            skillName = skillName
        })
    else
        -- Single player: apply directly using the existing function
        self:applySkillXPSetMode(skillName, recordedXP)
    end
end

-- Send trait claim command to server (for player journals)
function BurdJournals.UI.MainPanel:sendClaimTrait(traitId)
    local journalId = self.journal:getID()

    -- Track as pending claim for immediate UI feedback
    if not self.pendingClaims then self.pendingClaims = {skills = {}, traits = {}} end
    self.pendingClaims.traits[traitId] = true

    -- In MP (isClient and not isServer), send command to server
    -- In SP (isClient and isServer), fall through to direct application
    if isClient() and not isServer() then
        sendClientCommand(self.player, "BurdJournals", "claimTrait", {
            journalId = journalId,
            traitId = traitId
        })
    else
        -- Single player: apply directly using the existing function
        self:applyTraitDirectly(traitId)
    end
end

-- Send recipe absorption command to server (for worn/bloody journals)
function BurdJournals.UI.MainPanel:sendAbsorbRecipe(recipeName)
    local journalId = self.journal:getID()
    -- In MP (isClient and not isServer), send command to server
    -- In SP (isClient and isServer), fall through to direct application
    if isClient() and not isServer() then
        sendClientCommand(self.player, "BurdJournals", "absorbRecipe", {
            journalId = journalId,
            recipeName = recipeName
        })
    else
        -- Single player: apply directly
        self:applyRecipeDirectly(recipeName)
    end
end

-- Send recipe claim command to server (for player journals)
function BurdJournals.UI.MainPanel:sendClaimRecipe(recipeName)
    local journalId = self.journal:getID()

    -- Track as pending claim for immediate UI feedback
    if not self.pendingClaims then self.pendingClaims = {skills = {}, traits = {}, recipes = {}} end
    if not self.pendingClaims.recipes then self.pendingClaims.recipes = {} end
    self.pendingClaims.recipes[recipeName] = true

    -- In MP (isClient and not isServer), send command to server
    -- In SP (isClient and isServer), fall through to direct application
    if isClient() and not isServer() then
        sendClientCommand(self.player, "BurdJournals", "claimRecipe", {
            journalId = journalId,
            recipeName = recipeName
        })
    else
        -- Single player: apply directly
        self:applyRecipeDirectly(recipeName)
        -- Mark as claimed in journal modData
        BurdJournals.claimRecipe(self.journal, recipeName)
    end
end

-- Apply recipe directly (single player fallback)
function BurdJournals.UI.MainPanel:applyRecipeDirectly(recipeName)
    if not self.player or not recipeName then return end

    -- Check if player already knows the recipe
    if BurdJournals.playerKnowsRecipe(self.player, recipeName) then
        self:showFeedback(string.format(getText("UI_BurdJournals_AlreadyKnowRecipe") or "Already know: %s", recipeName), {r=0.7, g=0.7, b=0.5})
        return
    end

    -- Learn the recipe
    local recipeWasLearned = false
    pcall(function()
        self.player:learnRecipe(recipeName)
        recipeWasLearned = true
    end)

    if recipeWasLearned then
        local displayName = BurdJournals.getRecipeDisplayName(recipeName) or recipeName
        self:showFeedback(string.format(getText("UI_BurdJournals_LearnedRecipe") or "Learned: %s", displayName), {r=0.5, g=0.9, b=0.95})

        -- Show halo text for recipe learned
        BurdJournals.Client.showHaloMessage(self.player, "+" .. displayName, BurdJournals.Client.HaloColors.RECIPE_GAIN)
    else
        self:showFeedback("Failed to learn recipe", {r=0.9, g=0.5, b=0.5})
    end
end

-- Apply skill XP in SET mode (single player fallback for player journals)
function BurdJournals.UI.MainPanel:applySkillXPSetMode(skillName, recordedXP)
    -- Refresh player reference first
    self:refreshPlayer()

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

        -- Mark as claimed in journal modData
        BurdJournals.claimSkill(self.journal, skillName)

        local displayName = BurdJournals.getPerkDisplayName(skillName)
        self:showFeedback(string.format(getText("UI_BurdJournals_SetSkillToLevel") or "Set %s to recorded level", displayName), {r=0.5, g=0.8, b=0.9})
    else
        self:showFeedback(getText("UI_BurdJournals_AlreadyAtLevel") or "Already at or above this level", {r=0.7, g=0.7, b=0.5})
    end

    -- Refresh list and check if journal should dissolve
    self:refreshJournalData()
    self:checkDissolution()
end

-- ==================== PUBLIC ABSORB FUNCTIONS (now start learning) ====================

function BurdJournals.UI.MainPanel:absorbSkill(skillName, xp)
    -- If already learning (but not Absorb All), add to queue
    if self.learningState.active and not self.learningState.isAbsorbAll then
        if self:addToQueue("skill", skillName, xp) then
            self:showFeedback(string.format(getText("UI_BurdJournals_Queued") or "Queued: %s", BurdJournals.getPerkDisplayName(skillName) or skillName), {r=0.7, g=0.8, b=0.9})
        else
            self:showFeedback(getText("UI_BurdJournals_AlreadyQueued") or "Already queued", {r=0.9, g=0.7, b=0.3})
        end
        return
    end

    -- Start learning instead of immediate absorption
    if not self:startLearningSkill(skillName, xp) then
        self:showFeedback(getText("UI_BurdJournals_AlreadyReading") or "Already reading...", {r=0.9, g=0.7, b=0.3})
    end
end

function BurdJournals.UI.MainPanel:absorbTrait(traitId)
    -- If already learning (but not Absorb All), add to queue
    if self.learningState.active and not self.learningState.isAbsorbAll then
        if self:addToQueue("trait", traitId) then
            local traitName = safeGetTraitName(traitId)
            self:showFeedback(string.format(getText("UI_BurdJournals_Queued") or "Queued: %s", traitName), {r=0.9, g=0.8, b=0.6})
        else
            self:showFeedback(getText("UI_BurdJournals_AlreadyQueued") or "Already queued", {r=0.9, g=0.7, b=0.3})
        end
        return
    end

    -- Start learning instead of immediate absorption
    if not self:startLearningTrait(traitId) then
        self:showFeedback(getText("UI_BurdJournals_AlreadyReading") or "Already reading...", {r=0.9, g=0.7, b=0.3})
    end
end

function BurdJournals.UI.MainPanel:absorbRecipe(recipeName)
    -- If already learning (but not Absorb All), add to queue
    if self.learningState.active and not self.learningState.isAbsorbAll then
        if self:addToQueue("recipe", recipeName) then
            local displayName = BurdJournals.getRecipeDisplayName(recipeName)
            self:showFeedback(string.format(getText("UI_BurdJournals_Queued") or "Queued: %s", displayName), {r=0.5, g=0.85, b=0.9})
        else
            self:showFeedback(getText("UI_BurdJournals_AlreadyQueued") or "Already queued", {r=0.9, g=0.7, b=0.3})
        end
        return
    end

    -- Start learning the recipe
    if not self:startLearningRecipe(recipeName) then
        self:showFeedback(getText("UI_BurdJournals_AlreadyReading") or "Already reading...", {r=0.9, g=0.7, b=0.3})
    end
end

-- Add a reward to the queue
function BurdJournals.UI.MainPanel:addToQueue(rewardType, name, xp)
    -- Check if already in queue or currently learning
    if self.learningState.skillName == name or self.learningState.traitId == name or self.learningState.recipeName == name then
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
-- For stats, 'xp' parameter is used as 'value'
function BurdJournals.UI.MainPanel:addToRecordQueue(recordType, name, xp, level)
    if not self.recordingState then return false end
    if not self.recordingState.queue then
        self.recordingState.queue = {}
    end

    -- Check if already recording this one
    if self.recordingState.skillName == name or self.recordingState.traitId == name or self.recordingState.statId == name or self.recordingState.recipeName == name then
        return false
    end

    -- Check if already in queue
    for _, queued in ipairs(self.recordingState.queue) do
        if queued.name == name then
            return false
        end
    end

    -- Add to queue (for stats, xp is used as the value)
    table.insert(self.recordingState.queue, {
        type = recordType,
        name = name,
        xp = xp,
        level = level,
        value = xp  -- For stats, we use xp parameter as value
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
            self:showFeedback(string.format(getText("UI_BurdJournals_GainedXP") or "+%s %s", BurdJournals.formatXP(actualGain), BurdJournals.getPerkDisplayName(skillName)), {r=0.5, g=0.8, b=0.5})
        else
            self:showFeedback(getText("UI_BurdJournals_SkillMaxed") or "Skill already maxed!", {r=0.7, g=0.5, b=0.3})
        end

        self:refreshAbsorptionList()
        self:checkDissolution()
    end
end

function BurdJournals.UI.MainPanel:applyTraitDirectly(traitId)
    -- Use the stored player reference
    local player = self.player

    if not player then
        self:showFeedback(getText("UI_BurdJournals_NoPlayer") or "No player!", {r=0.8, g=0.3, b=0.3})
        return
    end

    -- Check if already has the trait (uses safe B42 method)
    if BurdJournals.playerHasTrait(player, traitId) then
        self:showFeedback(getText("UI_BurdJournals_TraitAlreadyKnownFeedback") or "Trait already known!", {r=0.7, g=0.5, b=0.3})
        return
    end

    -- Use the new safe B42-compatible trait addition
    if BurdJournals.safeAddTrait(player, traitId) then
        BurdJournals.claimTrait(self.journal, traitId)
        local traitName = safeGetTraitName(traitId)
        self:showFeedback(string.format(getText("UI_BurdJournals_GainedTrait") or "Gained trait: %s", traitName), {r=0.9, g=0.75, b=0.5})
    else
        self:showFeedback(getText("UI_BurdJournals_FailedToAddTrait") or "Failed to add trait!", {r=0.8, g=0.3, b=0.3})
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

    -- Check for pending journal update (from blank->filled conversion)
    -- This runs every update tick until the new journal is found
    if self.pendingNewJournalId then
        -- Throttle the check to avoid excessive searching
        self.pendingJournalCheckCounter = (self.pendingJournalCheckCounter or 0) + 1
        if self.pendingJournalCheckCounter >= 30 then  -- Check every ~30 ticks
            self.pendingJournalCheckCounter = 0
            local newJournal = BurdJournals.findItemById(self.player, self.pendingNewJournalId)
            if newJournal then
                print("[BurdJournals] update: Found pending new journal! Updating reference.")
                self.journal = newJournal
                self.pendingNewJournalId = nil
                -- Refresh the UI with new journal data
                self:refreshJournalData()
            end
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

    local width = 410  -- Extended from 360 to prevent progress bars from squishing content

    -- Calculate dynamic height based on content
    local baseHeight = 180  -- Header + author + footer
    local itemHeight = 52   -- Height per skill/trait/stat row
    local headerRowHeight = 52  -- Height for section headers
    local minHeight = 420   -- Show about 4-5 items
    local maxHeight = 650   -- Increased max height to accommodate stats section

    -- Count items for height calculation
    local journalData = BurdJournals.getJournalData(journal)
    local hasBloodyOrigin = BurdJournals.hasBloodyOrigin(journal)
    local skillCount = 0
    local traitCount = 0
    local statCount = 0

    -- For log mode (recording), count player's skills and stats
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

        -- Count enabled stats
        if BurdJournals.RECORDABLE_STATS then
            for _, stat in ipairs(BurdJournals.RECORDABLE_STATS) do
                if BurdJournals.isStatEnabled(stat.id) then
                    statCount = statCount + 1
                end
            end
        end
    else
        -- For view/absorb modes, count from journal data
        if journalData and journalData.skills then
            for _ in pairs(journalData.skills) do
                skillCount = skillCount + 1
            end
        end
        -- Count traits for view mode (player journals can have recorded traits)
        -- OR for absorb mode with bloody origin journals
        if journalData and journalData.traits then
            for _ in pairs(journalData.traits) do
                traitCount = traitCount + 1
            end
        end
    end

    -- Calculate ideal height: base + skills header + skills + traits header (if any) + traits + stats header (if any) + stats
    local contentHeight = baseHeight
    contentHeight = contentHeight + headerRowHeight  -- Skills header
    contentHeight = contentHeight + (skillCount * itemHeight)
    if traitCount > 0 then
        contentHeight = contentHeight + headerRowHeight  -- Traits header
        contentHeight = contentHeight + (traitCount * itemHeight)
    end
    if statCount > 0 then
        contentHeight = contentHeight + headerRowHeight  -- Stats header
        contentHeight = contentHeight + (statCount * itemHeight)
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
    self.typeText = getText("UI_BurdJournals_RecordProgressHeader")
    self.rarityText = nil
    self.flavorText = getText("UI_BurdJournals_RecordFlavor")
    self.headerHeight = headerHeight
    y = headerHeight + 6
    
    -- ============ AUTHOR INFO BOX ============
    local playerName = self.player:getDescriptor():getForename() .. " " .. self.player:getDescriptor():getSurname()
    self.authorName = playerName
    self.authorBoxY = y
    self.authorBoxHeight = 44
    y = y + self.authorBoxHeight + 10

    -- ============ TAB BUTTONS ============
    -- Player journals in Log mode: Skills, Traits, Recipes, and CharInfo (stats) tabs
    local tabs = {
        {id = "skills", label = getText("UI_BurdJournals_TabSkills")},
        {id = "traits", label = getText("UI_BurdJournals_TabTraits")},
    }
    -- Only add Recipes tab if recipe recording is enabled
    if BurdJournals.getSandboxOption("EnableRecipeRecording") then
        table.insert(tabs, {id = "recipes", label = getText("UI_BurdJournals_TabRecipes")})
    end
    -- Only add CharInfo tab if stat recording is enabled
    if BurdJournals.getSandboxOption("EnableStatRecording") then
        table.insert(tabs, {id = "charinfo", label = getText("UI_BurdJournals_TabStats")})
    end

    -- Blue/teal theme for recording
    local tabThemeColors = {
        active = {r=0.18, g=0.32, b=0.42},
        inactive = {r=0.1, g=0.15, b=0.18},
        accent = {r=0.3, g=0.55, b=0.65}
    }
    self.tabThemeColors = tabThemeColors

    y = self:createTabs(tabs, y, tabThemeColors)

    -- ============ SEARCH BAR ============
    -- Skills tab always has 24+ items, so search bar will show for that tab
    -- For other tabs, we estimate based on player traits/recipes
    local skillItemCount = 24  -- PZ has 24+ skills
    y = self:createSearchBar(y, tabThemeColors, skillItemCount)

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
                        -- Only allow recording if canRecord is true
                        if not item.canRecord then
                            -- Show feedback for non-recordable items
                            if item.isAtBaseline then
                                listbox.mainPanel:showFeedback(getText("UI_BurdJournals_CantRecordStartingSkills") or "Can't record starting skills", {r=0.7, g=0.5, b=0.3})
                            elseif item.isStartingTrait then
                                listbox.mainPanel:showFeedback(getText("UI_BurdJournals_CantRecordStartingTraits") or "Can't record starting traits", {r=0.7, g=0.5, b=0.3})
                            end
                            return
                        end
                        if item.isSkill then
                            listbox.mainPanel:recordSkill(item.skillName, item.xp, item.level)
                        elseif item.isTrait then
                            listbox.mainPanel:recordTrait(item.traitId)
                        elseif item.isStat then
                            listbox.mainPanel:recordStat(item.statId, item.currentValue)
                        elseif item.isRecipe then
                            listbox.mainPanel:recordRecipe(item.recipeName)
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
    
    -- Footer buttons (3 buttons: Record Tab, Record All, Close)
    local btnWidth = 100
    local btnSpacing = 8
    local totalBtnWidth = btnWidth * 3 + btnSpacing * 2
    local btnStartX = (self.width - totalBtnWidth) / 2
    local btnY = self.footerY + 32

    -- Record Tab button (tab-specific)
    local tabName = self:getTabDisplayName(self.currentTab or "skills")
    local recordTabText = string.format(getText("UI_BurdJournals_BtnRecordTab") or "Record %s", tabName)
    self.recordTabBtn = ISButton:new(btnStartX, btnY, btnWidth, btnHeight, recordTabText, self, BurdJournals.UI.MainPanel.onRecordTab)
    self.recordTabBtn:initialise()
    self.recordTabBtn:instantiate()
    self.recordTabBtn.borderColor = {r=0.25, g=0.45, b=0.55, a=1}
    self.recordTabBtn.backgroundColor = {r=0.12, g=0.24, b=0.30, a=0.8}
    self.recordTabBtn.textColor = {r=1, g=1, b=1, a=1}
    self:addChild(self.recordTabBtn)

    -- Record All button
    self.recordAllBtn = ISButton:new(btnStartX + btnWidth + btnSpacing, btnY, btnWidth, btnHeight, getText("UI_BurdJournals_BtnRecordAll"), self, BurdJournals.UI.MainPanel.onRecordAll)
    self.recordAllBtn:initialise()
    self.recordAllBtn:instantiate()
    self.recordAllBtn.borderColor = {r=0.3, g=0.5, b=0.6, a=1}
    self.recordAllBtn.backgroundColor = {r=0.15, g=0.28, b=0.35, a=0.8}
    self.recordAllBtn.textColor = {r=1, g=1, b=1, a=1}
    self:addChild(self.recordAllBtn)

    -- Close button
    self.closeBottomBtn = ISButton:new(btnStartX + (btnWidth + btnSpacing) * 2, btnY, btnWidth, btnHeight, getText("UI_BurdJournals_BtnClose"), self, BurdJournals.UI.MainPanel.onClose)
    self.closeBottomBtn:initialise()
    self.closeBottomBtn:instantiate()
    self.closeBottomBtn.borderColor = {r=0.4, g=0.35, b=0.3, a=1}
    self.closeBottomBtn.backgroundColor = {r=0.15, g=0.13, b=0.12, a=0.8}
    self.closeBottomBtn.textColor = {r=0.9, g=0.85, b=0.8, a=1}
    self:addChild(self.closeBottomBtn)

    -- Debug button (only visible in debug mode)
    if BurdJournals.isDebug and BurdJournals.isDebug() then
        local debugBtnWidth = 140
        local debugBtnX = (self.width - debugBtnWidth) / 2
        local debugBtnY = btnY - 28  -- Above the main buttons

        self.debugResetBtn = ISButton:new(debugBtnX, debugBtnY, debugBtnWidth, 22, "[DEBUG] Reset Baseline", self, BurdJournals.UI.MainPanel.onDebugResetBaseline)
        self.debugResetBtn:initialise()
        self.debugResetBtn:instantiate()
        self.debugResetBtn.borderColor = {r=0.8, g=0.4, b=0.1, a=1}
        self.debugResetBtn.backgroundColor = {r=0.4, g=0.2, b=0.05, a=0.9}
        self.debugResetBtn.textColor = {r=1, g=0.8, b=0.3, a=1}
        self.debugResetBtn.tooltip = "Recalculates skill/trait baseline from profession and traits. Use if 'Starting skill' shows incorrectly."
        self:addChild(self.debugResetBtn)
    end

    -- Populate the list
    self:populateRecordList()
end

-- Debug handler: Reset baseline and refresh UI
function BurdJournals.UI.MainPanel:onDebugResetBaseline()
    if not self.player then return end

    print("[BurdJournals] DEBUG: Resetting baseline for player...")

    -- Clear the baseline data
    local modData = self.player:getModData()
    if modData.BurdJournals then
        -- Store old values for comparison
        local oldSkillBaseline = modData.BurdJournals.skillBaseline or {}
        local oldTraitBaseline = modData.BurdJournals.traitBaseline or {}

        -- Clear baseline flags
        modData.BurdJournals.baselineCaptured = nil
        modData.BurdJournals.skillBaseline = nil
        modData.BurdJournals.traitBaseline = nil

        print("[BurdJournals] DEBUG: Old baseline had " .. BurdJournals.countTable(oldSkillBaseline) .. " skills, " .. BurdJournals.countTable(oldTraitBaseline) .. " traits")
    end

    -- Recapture baseline from profession/traits
    if BurdJournals.Client and BurdJournals.Client.captureBaseline then
        BurdJournals.Client.captureBaseline(self.player, false)
    end

    -- Log new baseline
    local newModData = self.player:getModData()
    if newModData.BurdJournals then
        local newSkillBaseline = newModData.BurdJournals.skillBaseline or {}
        local newTraitBaseline = newModData.BurdJournals.traitBaseline or {}
        print("[BurdJournals] DEBUG: New baseline has " .. BurdJournals.countTable(newSkillBaseline) .. " skills, " .. BurdJournals.countTable(newTraitBaseline) .. " traits")

        -- Log individual skills
        for skillName, xp in pairs(newSkillBaseline) do
            print("[BurdJournals] DEBUG:   Skill baseline: " .. skillName .. " = " .. tostring(xp) .. " XP")
        end
    end

    -- Refresh the UI to reflect changes
    self:populateRecordList()

    -- Show feedback
    self:showFeedback(getText("UI_BurdJournals_BaselineReset") or "Baseline reset! Check console for details.", {r=1, g=0.8, b=0.3})

    print("[BurdJournals] DEBUG: Baseline reset complete, UI refreshed")
end

-- Populate the record list with player's current skills and traits
function BurdJournals.UI.MainPanel:populateRecordList(overrideData)
    self.skillList:clear()

    -- CRITICAL: Re-read journal data to get latest recorded skills/traits
    -- This ensures the UI reflects server-synced data after recording
    -- In SP, server response may set overrideData to bypass getModData() timing issues
    local journalData
    if overrideData then
        journalData = overrideData
        print("[BurdJournals] populateRecordList: Using override data from server response")
    else
        journalData = BurdJournals.getJournalData(self.journal) or {}
    end
    self.recordedSkills = journalData.skills or {}
    self.recordedTraits = journalData.traits or {}

    local allowedSkills = BurdJournals.getAllowedSkills()
    local recordedSkills = self.recordedSkills
    local recordedTraits = self.recordedTraits
    local currentTab = self.currentTab or "skills"

    -- ============ SKILLS TAB ============
    if currentTab == "skills" then
        -- Add skill rows (no header with tabs)
        local matchCount = 0
        local totalSkills = 0
        local useBaseline = BurdJournals.isBaselineRestrictionEnabled()

        for _, skillName in ipairs(allowedSkills) do
            local perk = BurdJournals.getPerkByName(skillName)
            if perk then
                local currentXP = self.player:getXp():getXP(perk)
                local currentLevel = self.player:getPerkLevel(perk)

                -- Only show skills where player has some progress
                if currentXP > 0 or currentLevel > 0 then
                    totalSkills = totalSkills + 1
                    local displayName = BurdJournals.getPerkDisplayName(skillName)

                    -- Apply search filter
                    if self:matchesSearch(displayName) then
                        matchCount = matchCount + 1
                        local recordedData = recordedSkills[skillName]
                        local recordedXP = recordedData and recordedData.xp or 0
                        local recordedLevel = recordedData and recordedData.level or 0

                        -- Get baseline XP (what player spawned with)
                        local baselineXP = 0
                        if useBaseline then
                            baselineXP = BurdJournals.getSkillBaseline(self.player, skillName)
                        end

                        -- Calculate earned XP (current - baseline)
                        local earnedXP = math.max(0, currentXP - baselineXP)

                        -- Can only record if:
                        -- 1. Player has earned XP above baseline, AND
                        -- 2. Earned XP is higher than what's already recorded
                        local canRecord = earnedXP > recordedXP

                        -- Check if this skill is entirely at baseline (no earned progress)
                        local isAtBaseline = useBaseline and earnedXP == 0 and baselineXP > 0

                        self.skillList:addItem(skillName, {
                            isSkill = true,
                            skillName = skillName,
                            displayName = displayName,
                            xp = earnedXP,  -- Use earned XP (above baseline) for recording
                            currentXP = currentXP,  -- Store full XP for display if needed
                            level = currentLevel,
                            recordedXP = recordedXP,
                            recordedLevel = recordedLevel,
                            isRecorded = recordedXP > 0,
                            canRecord = canRecord,
                            baselineXP = baselineXP,
                            earnedXP = earnedXP,
                            isAtBaseline = isAtBaseline,
                        })
                    end
                end
            end
        end

        if matchCount == 0 then
            if totalSkills == 0 then
                self.skillList:addItem("empty", {isEmpty = true, text = getText("UI_BurdJournals_NoSkillsToRecord") or "No skills to record yet"})
            else
                self.skillList:addItem("empty", {isEmpty = true, text = getText("UI_BurdJournals_NoSearchResults") or "No results found"})
            end
        end

    -- ============ TRAITS TAB ============
    elseif currentTab == "traits" then
        -- Get player's positive traits
        local playerTraits = BurdJournals.collectPlayerTraits(self.player, false)
        local grantableTraitList = (BurdJournals.getGrantableTraits and BurdJournals.getGrantableTraits()) or BurdJournals.GRANTABLE_TRAITS or {}
        local positiveTraits = {}
        for traitId, traitData in pairs(playerTraits) do
            -- Use isTraitGrantable which handles profession variants (e.g., soto:slaughterer2 -> soto:slaughterer)
            if BurdJournals.isTraitGrantable(traitId, grantableTraitList) then
                positiveTraits[traitId] = traitData
            end
        end

        local matchCount = 0
        local totalTraits = 0
        for traitId, traitData in pairs(positiveTraits) do
            totalTraits = totalTraits + 1
            local traitName = safeGetTraitName(traitId)

            -- Apply search filter
            if self:matchesSearch(traitName) then
                matchCount = matchCount + 1
                local traitTexture = getTraitTexture(traitId)
                local isRecorded = recordedTraits[traitId] ~= nil
                local isStartingTrait = BurdJournals.isStartingTrait(self.player, traitId)
                local isPositive = isTraitPositive(traitId)

                self.skillList:addItem(traitId, {
                    isTrait = true,
                    traitId = traitId,
                    traitName = traitName,
                    traitTexture = traitTexture,
                    isRecorded = isRecorded,
                    isStartingTrait = isStartingTrait,
                    canRecord = not isRecorded and not isStartingTrait,
                    isPositive = isPositive,
                })
            end
        end

        if matchCount == 0 then
            if totalTraits == 0 then
                self.skillList:addItem("empty", {isEmpty = true, text = getText("UI_BurdJournals_NoTraitsToRecord") or "No traits to record"})
            else
                self.skillList:addItem("empty", {isEmpty = true, text = getText("UI_BurdJournals_NoSearchResults") or "No results found"})
            end
        end

    -- ============ CHARINFO (STATS) TAB ============
    elseif currentTab == "charinfo" then
        if BurdJournals.getSandboxOption("EnableStatRecording") then
            local recordedStats = journalData.stats or {}
            local matchCount = 0
            local totalStats = 0

            for _, stat in ipairs(BurdJournals.RECORDABLE_STATS) do
                if BurdJournals.isStatEnabled(stat.id) then
                    totalStats = totalStats + 1

                    -- Apply search filter
                    if self:matchesSearch(stat.name) then
                        matchCount = matchCount + 1
                        local currentValue = BurdJournals.getStatValue(self.player, stat.id)
                        local recorded = recordedStats[stat.id]
                        local recordedValue = recorded and recorded.value or nil
                        local canUpdate, _, _ = BurdJournals.canUpdateStat(self.journal, stat.id, self.player)

                        local currentFormatted = BurdJournals.formatStatValue(stat.id, currentValue)
                        local recordedFormatted = recordedValue and BurdJournals.formatStatValue(stat.id, recordedValue) or nil

                        self.skillList:addItem(stat.id, {
                            isStat = true,
                            statId = stat.id,
                            statName = stat.name,
                            statCategory = stat.category,
                            statDescription = stat.description,
                            currentValue = currentValue,
                            currentFormatted = currentFormatted,
                            recordedValue = recordedValue,
                            recordedFormatted = recordedFormatted,
                            isRecorded = recordedValue ~= nil,
                            canRecord = canUpdate,
                            isText = stat.isText,
                        })
                    end
                end
            end

            if matchCount == 0 then
                if totalStats == 0 then
                    self.skillList:addItem("empty", {isEmpty = true, text = "No stats enabled"})
                else
                    self.skillList:addItem("empty", {isEmpty = true, text = getText("UI_BurdJournals_NoSearchResults") or "No results found"})
                end
            end
        else
            self.skillList:addItem("empty", {isEmpty = true, text = "Stat recording is disabled"})
        end

    -- ============ RECIPES TAB ============
    elseif currentTab == "recipes" then
        if BurdJournals.getSandboxOption("EnableRecipeRecording") then
            local recordedRecipes = journalData.recipes or {}
            -- Get player's magazine-learned recipes
            local playerRecipes = BurdJournals.collectPlayerMagazineRecipes(self.player)
            local matchCount = 0
            local totalRecipes = 0

            for recipeName, recipeData in pairs(playerRecipes) do
                totalRecipes = totalRecipes + 1
                local displayName = BurdJournals.getRecipeDisplayName(recipeName)

                -- Apply search filter
                if self:matchesSearch(displayName) then
                    matchCount = matchCount + 1
                    local magazineSource = recipeData.source or BurdJournals.getMagazineForRecipe(recipeName)
                    local isRecorded = recordedRecipes[recipeName] ~= nil

                    self.skillList:addItem(recipeName, {
                        isRecipe = true,
                        recipeName = recipeName,
                        displayName = displayName,
                        magazineSource = magazineSource,
                        isRecorded = isRecorded,
                        canRecord = not isRecorded,
                    })
                end
            end

            if matchCount == 0 then
                if totalRecipes == 0 then
                    self.skillList:addItem("empty", {isEmpty = true, text = getText("UI_BurdJournals_NoRecipesToRecord") or "No magazine recipes learned"})
                else
                    self.skillList:addItem("empty", {isEmpty = true, text = getText("UI_BurdJournals_NoSearchResults") or "No results found"})
                end
            end
        else
            self.skillList:addItem("empty", {isEmpty = true, text = "Recipe recording is disabled"})
        end
    end
end

-- Draw function for record items
function BurdJournals.UI.MainPanel.doDrawRecordItem(self, y, item, alt)
    local mainPanel = self.mainPanel
    if not mainPanel then return y + self.itemheight end

    local data = item.item or {}
    local x = 0
    -- Account for scroll bar width (13px) to prevent content cutoff
    local scrollBarWidth = 13
    local w = self:getWidth() - scrollBarWidth
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
    
    -- Card background - tint based on trait type (positive/negative)
    local bgColor = cardBg
    local borderColor = cardBorder
    local accentGreen = {r=0.3, g=0.7, b=0.4}
    if data.isTrait then
        if data.isPositive == true then
            -- Green tint for positive traits (more saturated)
            bgColor = {r=0.08, g=0.20, b=0.10}
            borderColor = {r=0.2, g=0.5, b=0.25}
            accentGreen = {r=0.3, g=0.8, b=0.35}
        elseif data.isPositive == false then
            -- Red tint for negative traits (more saturated)
            bgColor = {r=0.22, g=0.08, b=0.08}
            borderColor = {r=0.5, g=0.2, b=0.2}
            accentGreen = {r=0.8, g=0.3, b=0.3}
        end
        -- If isPositive is nil, keep default blue/teal theme
    end

    if data.isRecorded and not data.canRecord then
        self:drawRect(cardX, cardY, cardW, cardH, 0.4, 0.12, 0.15, 0.12)
    else
        self:drawRect(cardX, cardY, cardW, cardH, 0.7, bgColor.r, bgColor.g, bgColor.b)
    end

    -- Card border
    self:drawRectBorder(cardX, cardY, cardW, cardH, 0.6, borderColor.r, borderColor.g, borderColor.b)

    -- Left accent bar (green if can record, gray if already recorded at max)
    if data.canRecord then
        self:drawRect(cardX, cardY, 4, cardH, 0.9, accentGreen.r, accentGreen.g, accentGreen.b)
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

        -- Pre-calculated baseline data from populateRecordList
        local baselineXP = data.baselineXP or 0
        local earnedXP = data.earnedXP or data.xp
        local isStartingSkill = data.isAtBaseline or (baselineXP > 0 and earnedXP == 0)

        -- Line 1: Skill name + level
        local displayName = data.displayName or data.skillName or "Unknown Skill"
        self:drawText(displayName .. " (Lv." .. data.level .. ")", textX, cardY + 6, textColor.r, textColor.g, textColor.b, 1, UIFont.Small)

        -- Line 2: Level squares + XP info OR recording progress
        if isRecordingThis then
            -- Show recording progress bar
            local progressText = string.format("Recording... %d%%", math.floor(recordingState.progress * 100))
            self:drawText(progressText, textX, cardY + 24, 0.3, 0.8, 0.5, 1, UIFont.Small)

            local barX = textX + 100
            local barY = cardY + 27
            local barW = cardW - 130 - padding
            local barH = 10
            self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)
            self:drawRect(barX, barY, barW * recordingState.progress, barH, 0.9, 0.3, 0.7, 0.4)
            self:drawRectBorder(barX, barY, barW, barH, 0.7, 0.4, 0.8, 0.5)
        elseif isStartingSkill then
            -- Starting skill - show dimmed squares and baseline XP info
            local squaresX = textX
            local squaresY = cardY + 26
            local squareSize = 10
            local squareSpacing = 2
            local level, progress = calculateLevelProgress(data.skillName, data.currentXP or data.xp or 0)

            -- Draw dimmed squares for starting skills
            drawLevelSquares(self, squaresX, squaresY, level, progress, squareSize, squareSpacing,
                {r=0.35, g=0.28, b=0.22},  -- Brownish/muted (starting skill)
                {r=0.1, g=0.1, b=0.1},     -- Dark empty
                {r=0.25, g=0.2, b=0.15}    -- Dimmer brown for progress
            )

            -- Status text after squares - show baseline XP so user understands what's blocked
            local squaresWidth = 10 * squareSize + 9 * squareSpacing
            local baselineText = string.format(getText("UI_BurdJournals_StartingXP"), BurdJournals.formatXP(baselineXP))
            self:drawText(baselineText, squaresX + squaresWidth + 8, squaresY, 0.5, 0.4, 0.35, 1, UIFont.Small)
        else
            -- Normal skill - show level squares + XP
            local squaresX = textX
            local squaresY = cardY + 26
            local squareSize = 10
            local squareSpacing = 2
            local level, progress = calculateLevelProgress(data.skillName, data.xp or 0)

            -- Choose colors based on state
            local filledColor, emptyColor, progressColor
            if data.isRecorded and not data.canRecord then
                -- Already recorded at max - show muted green
                filledColor = {r=0.25, g=0.4, b=0.3}
                emptyColor = {r=0.1, g=0.1, b=0.1}
                progressColor = {r=0.2, g=0.3, b=0.25}
            else
                -- Can record - show bright teal
                filledColor = {r=0.3, g=0.65, b=0.55}
                emptyColor = {r=0.12, g=0.12, b=0.12}
                progressColor = {r=0.2, g=0.4, b=0.35}
            end

            drawLevelSquares(self, squaresX, squaresY, level, progress, squareSize, squareSpacing,
                filledColor, emptyColor, progressColor
            )

            -- XP text after squares
            local squaresWidth = 10 * squareSize + 9 * squareSpacing
            local xpText
            local xpColor

            if data.isRecorded and not data.canRecord then
                -- Already recorded at this level
                xpText = string.format(getText("UI_BurdJournals_RecordedXP") or "Recorded: %s XP", BurdJournals.formatXP(data.recordedXP))
                xpColor = {r=0.4, g=0.5, b=0.45}
            elseif data.isRecorded and data.canRecord then
                -- Can update recording - show earned XP with baseline info if applicable
                if baselineXP > 0 then
                    xpText = string.format(getText("UI_BurdJournals_XPWithBaseline"),
                        BurdJournals.formatXP(earnedXP), BurdJournals.formatXP(baselineXP))
                    xpText = xpText .. " (was " .. BurdJournals.formatXP(data.recordedXP) .. ")"
                else
                    xpText = string.format(getText("UI_BurdJournals_RecordedWas") or "%s XP (was %s)", BurdJournals.formatXP(earnedXP), BurdJournals.formatXP(data.recordedXP))
                end
                xpColor = {r=0.5, g=0.8, b=0.6}
            else
                -- New recording - show earned XP with baseline info if applicable
                if baselineXP > 0 then
                    xpText = string.format(getText("UI_BurdJournals_XPWithBaseline"),
                        BurdJournals.formatXP(earnedXP), BurdJournals.formatXP(baselineXP))
                else
                    xpText = BurdJournals.formatXP(earnedXP) .. " XP"
                end
                xpColor = {r=0.5, g=0.75, b=0.7}
            end

            self:drawText(xpText, squaresX + squaresWidth + 8, squaresY, xpColor.r, xpColor.g, xpColor.b, 1, UIFont.Small)
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
                local btnText = getText("UI_BurdJournals_BtnQueue")
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.9, 0.95, 1, 1, UIFont.Small)
            else
                -- Normal RECORD button
                self:drawRect(btnX, btnY, btnW, btnH, 0.7, 0.2, 0.45, 0.35)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.3, 0.6, 0.5)
                local btnText = getText("UI_BurdJournals_BtnRecord")
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
        
        -- Trait name with color based on positive/negative type
        local traitColor
        if not data.canRecord then
            traitColor = {r=0.5, g=0.55, b=0.5}  -- Grayed out when can't record
        elseif data.isPositive == true then
            traitColor = {r=0.5, g=0.9, b=0.5}  -- Green for positive traits
        elseif data.isPositive == false then
            traitColor = {r=0.9, g=0.5, b=0.5}  -- Red for negative traits
        else
            traitColor = {r=0.8, g=0.9, b=1.0}  -- Original light blue for unknown
        end
        self:drawText(traitName, traitTextX, cardY + 6, traitColor.r, traitColor.g, traitColor.b, 1, UIFont.Small)
        
        -- Check if in queue
        local queuePosition = mainPanel:getRecordQueuePosition(data.traitId)
        local isQueued = queuePosition ~= nil
        
        -- Status text
        if isRecordingThis then
            local progressText = string.format("Recording... %d%%", math.floor(recordingState.progress * 100))
            self:drawText(progressText, traitTextX, cardY + 22, 0.3, 0.8, 0.5, 1, UIFont.Small)

            -- Progress bar for traits (shorter width to account for icon offset)
            local barX = traitTextX + 100
            local barY = cardY + 25
            local barW = cardW - barX - 20  -- Dynamic width based on actual start position
            local barH = 10

            -- Bar background
            self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)
            -- Bar fill (teal/cyan for recording)
            self:drawRect(barX, barY, barW * recordingState.progress, barH, 0.9, 0.2, 0.6, 0.5)
            -- Bar border
            self:drawRectBorder(barX, barY, barW, barH, 0.7, 0.3, 0.7, 0.6)
        elseif isQueued then
            local queuedText = string.format(getText("UI_BurdJournals_QueuedNumber") or "Queued #%d", queuePosition)
            self:drawText(queuedText, traitTextX, cardY + 22, 0.6, 0.75, 0.9, 1, UIFont.Small)
        elseif data.isStartingTrait then
            -- Show "Spawned with" for traits the player started with
            self:drawText(getText("UI_BurdJournals_SpawnedWith") or "Spawned with", traitTextX, cardY + 22, 0.5, 0.45, 0.4, 1, UIFont.Small)
        elseif data.isRecorded then
            self:drawText(getText("UI_BurdJournals_StatusAlreadyRecorded") or "Already recorded", traitTextX, cardY + 22, 0.4, 0.5, 0.4, 1, UIFont.Small)
        else
            self:drawText(getText("UI_BurdJournals_YourTrait") or "Your trait", traitTextX, cardY + 22, 0.5, 0.7, 0.8, 1, UIFont.Small)
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
                local btnText = getText("UI_BurdJournals_BtnQueue")
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 1, 0.95, 0.85, 1, UIFont.Small)
            else
                -- Normal RECORD button
                self:drawRect(btnX, btnY, btnW, btnH, 0.7, 0.35, 0.45, 0.25)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.5, 0.6, 0.4)
                local btnText = getText("UI_BurdJournals_BtnRecord")
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 1, 1, 0.9, 1, UIFont.Small)
            end
        end
    end

    -- ============ STAT ROW ============
    if data.isStat then
        local recordingState = mainPanel.recordingState
        local isRecordingThis = recordingState and recordingState.active and not recordingState.isRecordAll
                               and recordingState.statId == data.statId

        -- Stat name with category
        local statName = data.statName or data.statId or "Unknown Stat"
        self:drawText(statName, textX, cardY + 6, textColor.r, textColor.g, textColor.b, 1, UIFont.Small)

        -- Check if in queue
        local queuePosition = mainPanel:getRecordQueuePosition(data.statId)
        local isQueued = queuePosition ~= nil

        -- Value display
        if isRecordingThis then
            local progressText = string.format("Recording... %d%%", math.floor(recordingState.progress * 100))
            self:drawText(progressText, textX, cardY + 22, 0.3, 0.8, 0.5, 1, UIFont.Small)

            -- Progress bar for stats (shorter width to fit within card)
            local barX = textX + 100
            local barY = cardY + 25
            local barW = cardW - barX - 20  -- Dynamic width based on actual start position
            local barH = 10

            -- Bar background
            self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)
            -- Bar fill (teal/cyan for recording)
            self:drawRect(barX, barY, barW * recordingState.progress, barH, 0.9, 0.2, 0.6, 0.5)
            -- Bar border
            self:drawRectBorder(barX, barY, barW, barH, 0.7, 0.3, 0.7, 0.6)
        elseif isQueued then
            local valueText = string.format(getText("UI_BurdJournals_CurrentQueued") or "Current: %s - Queued #%d", data.currentFormatted or "?", queuePosition)
            self:drawText(valueText, textX, cardY + 22, 0.6, 0.75, 0.9, 1, UIFont.Small)
        elseif data.isRecorded then
            if data.canRecord then
                -- Can update (current value is higher/different)
                local valueText = string.format(getText("UI_BurdJournals_NowWas") or "Now: %s (was %s)", data.currentFormatted or "?", data.recordedFormatted or "?")
                self:drawText(valueText, textX, cardY + 22, 0.5, 0.8, 0.5, 1, UIFont.Small)
            else
                -- Already at max
                local valueText = string.format(getText("UI_BurdJournals_RecordedValue") or "Recorded: %s", data.recordedFormatted or "?")
                self:drawText(valueText, textX, cardY + 22, 0.4, 0.5, 0.4, 1, UIFont.Small)
            end
        else
            -- Not yet recorded
            local valueText = string.format(getText("UI_BurdJournals_CurrentValue") or "Current: %s", data.currentFormatted or "?")
            self:drawText(valueText, textX, cardY + 22, 0.5, 0.7, 0.8, 1, UIFont.Small)
        end

        -- RECORD/QUEUE button
        if data.canRecord and not isRecordingThis then
            local btnW = 65
            local btnH = 24
            local btnX = cardX + cardW - btnW - 10
            local btnY = cardY + (cardH - btnH) / 2

            if isQueued then
                -- Show queue position indicator
                self:drawRect(btnX, btnY, btnW, btnH, 0.5, 0.35, 0.45, 0.5)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.6, 0.45, 0.55, 0.6)
                local btnText = "#" .. queuePosition
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.8, 0.9, 1, 1, UIFont.Small)
            elseif recordingState and recordingState.active and not recordingState.isRecordAll then
                -- Show QUEUE button when another item is recording
                self:drawRect(btnX, btnY, btnW, btnH, 0.6, 0.3, 0.4, 0.5)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.45, 0.55, 0.65)
                local btnText = getText("UI_BurdJournals_BtnQueue")
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.9, 0.95, 1, 1, UIFont.Small)
            else
                -- Normal RECORD button (cyan/teal for stats)
                self:drawRect(btnX, btnY, btnW, btnH, 0.7, 0.2, 0.4, 0.45)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.35, 0.55, 0.6)
                local btnText = getText("UI_BurdJournals_BtnRecord")
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 1, 1, 1, 1, UIFont.Small)
            end
        end
    end

    -- ============ RECIPE ROW ============
    if data.isRecipe then
        local recordingState = mainPanel.recordingState
        local isRecordingThis = recordingState and recordingState.active and not recordingState.isRecordAll
                               and recordingState.recipeName == data.recipeName

        local displayName = data.displayName or data.recipeName or "Unknown Recipe"
        local recipeTextX = textX

        -- Get magazine texture if available
        local magazineTexture = nil
        if data.magazineSource then
            pcall(function()
                local script = getScriptManager():getItem(data.magazineSource)
                if script then
                    local iconName = script:getIcon()
                    if iconName then
                        magazineTexture = getTexture("Item_" .. iconName)
                    end
                end
            end)
        end

        -- Draw magazine icon if available
        if magazineTexture then
            local iconSize = 24
            local iconX = textX
            local iconY = cardY + (cardH - iconSize) / 2
            local iconAlpha = data.canRecord and 1.0 or 0.5
            self:drawTextureScaledAspect(magazineTexture, iconX, iconY, iconSize, iconSize, iconAlpha, 1, 1, 1)
            recipeTextX = textX + iconSize + 6
        end

        -- Recipe name
        self:drawText(displayName, recipeTextX, cardY + 6, textColor.r, textColor.g, textColor.b, 1, UIFont.Small)

        -- Check if in queue
        local queuePosition = mainPanel:getRecordQueuePosition(data.recipeName)
        local isQueued = queuePosition ~= nil

        -- Source/status line
        if isRecordingThis then
            local progressText = string.format("Recording... %d%%", math.floor(recordingState.progress * 100))
            self:drawText(progressText, recipeTextX, cardY + 22, 0.3, 0.8, 0.5, 1, UIFont.Small)

            -- Progress bar
            local barX = recipeTextX + 100
            local barY = cardY + 25
            local barW = cardW - barX - 20
            local barH = 10

            self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)
            self:drawRect(barX, barY, barW * recordingState.progress, barH, 0.9, 0.5, 0.85, 0.9) -- Teal progress
            self:drawRectBorder(barX, barY, barW, barH, 0.7, 0.5, 0.85, 0.9)
        elseif isQueued then
            local queuedText = string.format(getText("UI_BurdJournals_QueuedNumber") or "Queued #%d", queuePosition)
            self:drawText(queuedText, recipeTextX, cardY + 22, 0.6, 0.75, 0.9, 1, UIFont.Small)
        elseif data.isRecorded then
            self:drawText(getText("UI_BurdJournals_StatusAlreadyRecorded") or "Already recorded", recipeTextX, cardY + 22, 0.4, 0.5, 0.4, 1, UIFont.Small)
        else
            -- Show magazine source with display name
            local magazineName = data.magazineSource and BurdJournals.getMagazineDisplayName(data.magazineSource) or nil
            local sourceText = magazineName and string.format(getText("UI_BurdJournals_RecipeFromMagazine") or "From: %s", magazineName) or "Learned from magazine"
            self:drawText(sourceText, recipeTextX, cardY + 22, 0.5, 0.7, 0.8, 1, UIFont.Small)
        end

        -- RECORD/QUEUE button
        if data.canRecord and not isRecordingThis then
            local btnW = 65
            local btnH = 24
            local btnX = cardX + cardW - btnW - 10
            local btnY = cardY + (cardH - btnH) / 2

            if isQueued then
                -- Show queue position indicator
                self:drawRect(btnX, btnY, btnW, btnH, 0.5, 0.4, 0.7, 0.7)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.6, 0.5, 0.85, 0.9)
                local btnText = "#" .. queuePosition
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.9, 0.95, 1, 1, UIFont.Small)
            elseif recordingState and recordingState.active and not recordingState.isRecordAll then
                -- Show QUEUE button when another item is recording
                self:drawRect(btnX, btnY, btnW, btnH, 0.6, 0.35, 0.55, 0.6)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.5, 0.75, 0.8)
                local btnText = getText("UI_BurdJournals_BtnQueue")
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 1, 1, 1, 1, UIFont.Small)
            else
                -- Normal RECORD button (teal/cyan for recipes)
                self:drawRect(btnX, btnY, btnW, btnH, 0.7, 0.3, 0.55, 0.6)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.5, 0.75, 0.8)
                local btnText = getText("UI_BurdJournals_BtnRecord")
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 1, 1, 1, 1, UIFont.Small)
            end
        end
    end

    return y + h
end

-- Record All button handler
function BurdJournals.UI.MainPanel:onRecordAll()
    if not self:startRecordingAll() then
        self:showFeedback(getText("UI_BurdJournals_AlreadyRecording") or "Already recording...", {r=0.9, g=0.7, b=0.3})
    end
end

-- Record Tab button handler (tab-specific)
function BurdJournals.UI.MainPanel:onRecordTab()
    if not self:startRecordingTab(self.currentTab or "skills") then
        self:showFeedback(getText("UI_BurdJournals_AlreadyRecording") or "Already recording...", {r=0.9, g=0.7, b=0.3})
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
    self.typeText = getText("UI_BurdJournals_PersonalJournalHeader")
    self.rarityText = nil
    self.flavorText = getText("UI_BurdJournals_PersonalFlavor")
    self.headerHeight = headerHeight
    y = headerHeight + 6

    -- ============ AUTHOR INFO BOX ============
    local authorName = journalData and journalData.author or getText("UI_BurdJournals_Unknown")
    self.authorName = authorName
    self.authorBoxY = y
    self.authorBoxHeight = 44
    y = y + self.authorBoxHeight + 10
    
    -- ============ COUNT SKILLS, TRAITS, AND STATS ============
    local skillCount = 0
    local totalSkillCount = 0
    local traitCount = 0
    local totalTraitCount = 0
    local statCount = 0
    local totalStatCount = 0
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
    if journalData and journalData.stats then
        for statId, statData in pairs(journalData.stats) do
            totalStatCount = totalStatCount + 1
            -- Check if player's current stat is below recorded
            local currentValue = BurdJournals.getStatValue(self.player, statId)
            if currentValue < (statData.value or 0) then
                statCount = statCount + 1
            end
        end
    end

    -- Count recipes
    local recipeCount = 0
    local totalRecipeCount = 0
    if journalData and journalData.recipes then
        for recipeName, _ in pairs(journalData.recipes) do
            totalRecipeCount = totalRecipeCount + 1
            -- Check if player already knows this recipe
            if not BurdJournals.playerKnowsRecipe(self.player, recipeName) then
                recipeCount = recipeCount + 1
            end
        end
    end

    self.skillCount = skillCount
    self.traitCount = traitCount
    self.statCount = statCount
    self.recipeCount = recipeCount
    self.totalXP = totalXP

    -- ============ TAB BUTTONS ============
    -- Player journals in View mode: Skills, Traits, Stats, and Recipes tabs
    local tabs = {{id = "skills", label = getText("UI_BurdJournals_TabSkills")}}
    if totalTraitCount > 0 then
        table.insert(tabs, {id = "traits", label = getText("UI_BurdJournals_TabTraits")})
    end
    if totalRecipeCount > 0 then
        table.insert(tabs, {id = "recipes", label = getText("UI_BurdJournals_TabRecipes")})
    end
    if totalStatCount > 0 then
        table.insert(tabs, {id = "stats", label = getText("UI_BurdJournals_TabStats")})
    end

    -- Blue/teal theme for player journals
    local tabThemeColors = {
        active = {r=0.15, g=0.30, b=0.40},
        inactive = {r=0.08, g=0.15, b=0.20},
        accent = {r=0.25, g=0.50, b=0.60}
    }
    self.tabThemeColors = tabThemeColors

    -- Only create tabs if there's more than one
    if #tabs > 1 then
        y = self:createTabs(tabs, y, tabThemeColors)
    end

    -- ============ SEARCH BAR ============
    -- Use max item count across tabs to determine if search bar should show
    local maxItemCount = math.max(totalSkillCount, totalTraitCount, totalRecipeCount, totalStatCount)
    y = self:createSearchBar(y, tabThemeColors, maxItemCount)

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
                    if x >= btnAreaStart or item.isTrait or item.isRecipe then
                        if item.isSkill and item.canClaim then
                            listbox.mainPanel:claimSkill(item.skillName, item.xp)
                        elseif item.isTrait and not item.alreadyKnown and not item.isClaimed then
                            listbox.mainPanel:claimTrait(item.traitId)
                        elseif item.isRecipe and not item.alreadyKnown and not item.isClaimed then
                            listbox.mainPanel:claimRecipe(item.recipeName)
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
    
    -- Footer buttons (3 buttons: Claim Tab, Claim All, Close)
    local btnWidth = 100
    local btnSpacing = 8
    local totalBtnWidth = btnWidth * 3 + btnSpacing * 2
    local btnStartX = (self.width - totalBtnWidth) / 2
    local btnY = self.footerY + 32

    -- Claim Tab button (tab-specific)
    local tabName = self:getTabDisplayName(self.currentTab or "skills")
    local claimTabText = string.format(getText("UI_BurdJournals_BtnClaimTab") or "Claim %s", tabName)
    self.absorbTabBtn = ISButton:new(btnStartX, btnY, btnWidth, btnHeight, claimTabText, self, BurdJournals.UI.MainPanel.onClaimTab)
    self.absorbTabBtn:initialise()
    self.absorbTabBtn:instantiate()
    self.absorbTabBtn.borderColor = {r=0.3, g=0.5, b=0.6, a=1}
    self.absorbTabBtn.backgroundColor = {r=0.12, g=0.22, b=0.28, a=0.8}
    self.absorbTabBtn.textColor = {r=0.9, g=0.95, b=1, a=1}
    self:addChild(self.absorbTabBtn)

    -- Claim All button
    self.absorbAllBtn = ISButton:new(btnStartX + btnWidth + btnSpacing, btnY, btnWidth, btnHeight, getText("UI_BurdJournals_BtnClaimAll"), self, BurdJournals.UI.MainPanel.onClaimAll)
    self.absorbAllBtn:initialise()
    self.absorbAllBtn:instantiate()
    self.absorbAllBtn.borderColor = {r=0.3, g=0.5, b=0.6, a=1}
    self.absorbAllBtn.backgroundColor = {r=0.15, g=0.28, b=0.35, a=0.8}
    self.absorbAllBtn.textColor = {r=1, g=1, b=1, a=1}
    self:addChild(self.absorbAllBtn)

    -- Close button
    self.closeBottomBtn = ISButton:new(btnStartX + (btnWidth + btnSpacing) * 2, btnY, btnWidth, btnHeight, getText("UI_BurdJournals_BtnClose"), self, BurdJournals.UI.MainPanel.onClose)
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
    local currentTab = self.currentTab or "skills"

    -- Ensure pendingClaims exists
    if not self.pendingClaims then self.pendingClaims = {skills = {}, traits = {}} end

    -- ============ SKILLS TAB ============
    if currentTab == "skills" then
        -- Add skill rows (no header with tabs)
        if journalData and journalData.skills then
            local hasSkills = false
            local matchCount = 0
            for skillName, skillData in pairs(journalData.skills) do
                hasSkills = true
                local displayName = BurdJournals.getPerkDisplayName(skillName)

                -- Apply search filter
                if self:matchesSearch(displayName) then
                    matchCount = matchCount + 1
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
                        isPending = isPending,
                    })
                end
            end
            if not hasSkills then
                self.skillList:addItem("empty", {isEmpty = true, text = getText("UI_BurdJournals_NoSkillsRecorded")})
            elseif matchCount == 0 and self.searchQuery and self.searchQuery ~= "" then
                self.skillList:addItem("no_results", {isEmpty = true, text = getText("UI_BurdJournals_NoSearchResults") or "No results found"})
            end
        else
            self.skillList:addItem("empty", {isEmpty = true, text = getText("UI_BurdJournals_NoSkillsRecorded")})
        end

    -- ============ TRAITS TAB ============
    elseif currentTab == "traits" then
        if journalData and journalData.traits and BurdJournals.countTable(journalData.traits) > 0 then
            local hasTraits = false
            local matchCount = 0
            for traitId, traitData in pairs(journalData.traits) do
                hasTraits = true
                local traitName = safeGetTraitName(traitId)

                -- Apply search filter
                if self:matchesSearch(traitName) then
                    matchCount = matchCount + 1
                    local traitTexture = getTraitTexture(traitId)
                    local alreadyKnown = BurdJournals.playerHasTrait(self.player, traitId)
                    local isClaimed = BurdJournals.isTraitClaimed(self.journal, traitId)
                    local isPending = self.pendingClaims.traits[traitId]
                    local isPositive = isTraitPositive(traitId)

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
                        isClaimed = isClaimed,
                        isPending = isPending,
                        isPositive = isPositive,
                    })
                end
            end
            if not hasTraits then
                self.skillList:addItem("empty", {isEmpty = true, text = "No traits recorded"})
            elseif matchCount == 0 and self.searchQuery and self.searchQuery ~= "" then
                self.skillList:addItem("no_results", {isEmpty = true, text = getText("UI_BurdJournals_NoSearchResults") or "No results found"})
            end
        else
            self.skillList:addItem("empty", {isEmpty = true, text = "No traits recorded"})
        end

    -- ============ RECIPES TAB ============
    elseif currentTab == "recipes" then
        if journalData and journalData.recipes and BurdJournals.countTable(journalData.recipes) > 0 then
            local hasRecipes = false
            local matchCount = 0
            for recipeName, recipeData in pairs(journalData.recipes) do
                hasRecipes = true
                local displayName = BurdJournals.getRecipeDisplayName(recipeName)

                -- Apply search filter
                if self:matchesSearch(displayName) then
                    matchCount = matchCount + 1
                    local alreadyKnown = BurdJournals.playerKnowsRecipe(self.player, recipeName)
                    local isClaimed = BurdJournals.isRecipeClaimed(self.journal, recipeName)
                    local magazineSource = recipeData.source or BurdJournals.getMagazineForRecipe(recipeName)
                    local isPending = self.pendingClaims.recipes and self.pendingClaims.recipes[recipeName]

                    -- Clear pending flag if recipe has been learned
                    if isPending and alreadyKnown then
                        if self.pendingClaims.recipes then
                            self.pendingClaims.recipes[recipeName] = nil
                        end
                        isPending = false
                    end

                    self.skillList:addItem(recipeName, {
                        isRecipe = true,
                        recipeName = recipeName,
                        displayName = displayName,
                        magazineSource = magazineSource,
                        alreadyKnown = alreadyKnown,
                        isClaimed = isClaimed,
                        isPending = isPending,
                    })
                end
            end
            if not hasRecipes then
                self.skillList:addItem("empty", {isEmpty = true, text = getText("UI_BurdJournals_NoRecipesRecorded")})
            elseif matchCount == 0 and self.searchQuery and self.searchQuery ~= "" then
                self.skillList:addItem("no_results", {isEmpty = true, text = getText("UI_BurdJournals_NoSearchResults") or "No results found"})
            end
        else
            self.skillList:addItem("empty", {isEmpty = true, text = getText("UI_BurdJournals_NoRecipesRecorded")})
        end

    -- ============ STATS TAB ============
    elseif currentTab == "stats" then
        if journalData and journalData.stats and BurdJournals.countTable(journalData.stats) > 0 then
            local hasStats = false
            local matchCount = 0
            for statId, statData in pairs(journalData.stats) do
                hasStats = true
                local stat = BurdJournals.getStatById(statId)
                local statName = stat and stat.name or statId

                -- Apply search filter
                if self:matchesSearch(statName) then
                    matchCount = matchCount + 1
                    local currentValue = BurdJournals.getStatValue(self.player, statId)
                    local recordedValue = statData.value or 0
                    local currentFormatted = BurdJournals.formatStatValue(statId, currentValue)
                    local recordedFormatted = BurdJournals.formatStatValue(statId, recordedValue)

                    -- Stats are view-only (informational) - can't "claim" zombie kills or hours survived
                    -- They show what you achieved on a previous character
                    local canClaim = false  -- Stats are informational only

                    self.skillList:addItem(statId, {
                        isStat = true,
                        statId = statId,
                        statName = statName,
                        currentValue = currentValue,
                        recordedValue = recordedValue,
                        currentFormatted = currentFormatted,
                        recordedFormatted = recordedFormatted,
                        canClaim = canClaim,
                    })
                end
            end
            if not hasStats then
                self.skillList:addItem("empty", {isEmpty = true, text = "No stats recorded"})
            end
        else
            self.skillList:addItem("empty", {isEmpty = true, text = "No stats recorded"})
        end
    end
end

-- Draw function for view items (claiming from player journal)
function BurdJournals.UI.MainPanel.doDrawViewItem(self, y, item, alt)
    local mainPanel = self.mainPanel
    if not mainPanel then return y + self.itemheight end

    local data = item.item or {}
    local x = 0
    -- Account for scroll bar width (13px) to prevent content cutoff
    local scrollBarWidth = 13
    local w = self:getWidth() - scrollBarWidth
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

    -- Tint based on trait type (positive/negative)
    local bgColor = cardBg
    local borderColor = cardBorder
    local accent = accentColor
    if data.isTrait then
        if data.isPositive == true then
            -- Green tint for positive traits (more saturated)
            bgColor = {r=0.08, g=0.20, b=0.10}
            borderColor = {r=0.2, g=0.5, b=0.25}
            accent = {r=0.3, g=0.8, b=0.35}
        elseif data.isPositive == false then
            -- Red tint for negative traits (more saturated)
            bgColor = {r=0.22, g=0.08, b=0.08}
            borderColor = {r=0.5, g=0.2, b=0.2}
            accent = {r=0.8, g=0.3, b=0.3}
        end
        -- If isPositive is nil, keep default theme
    end

    if not canInteract then
        self:drawRect(cardX, cardY, cardW, cardH, 0.4, 0.12, 0.12, 0.12)
    else
        self:drawRect(cardX, cardY, cardW, cardH, 0.7, bgColor.r, bgColor.g, bgColor.b)
    end

    -- Card border
    self:drawRectBorder(cardX, cardY, cardW, cardH, 0.6, borderColor.r, borderColor.g, borderColor.b)

    -- Left accent bar
    if canInteract then
        self:drawRect(cardX, cardY, 4, cardH, 0.9, accent.r, accent.g, accent.b)
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

        -- Line 1: Skill name
        local displayName = data.displayName or data.skillName or "Unknown Skill"
        self:drawText(displayName, textX, cardY + 6, textColor.r, textColor.g, textColor.b, 1, UIFont.Small)

        -- Check if in queue
        local queuePosition = mainPanel:getQueuePosition(data.skillName)
        local isQueued = queuePosition ~= nil

        -- Line 2: Level squares + XP info OR learning progress
        if isLearningThis then
            -- Show learning progress bar
            local progressText = string.format("Reading... %d%%", math.floor(learningState.progress * 100))
            self:drawText(progressText, textX, cardY + 24, 0.3, 0.7, 0.9, 1, UIFont.Small)

            local barX = textX + 90
            local barY = cardY + 27
            local barW = cardW - 120 - padding
            local barH = 10
            self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)
            self:drawRect(barX, barY, barW * learningState.progress, barH, 0.9, 0.3, 0.6, 0.8)
            self:drawRectBorder(barX, barY, barW, barH, 0.7, 0.4, 0.6, 0.8)
        elseif isQueued then
            -- Show queue position with level squares
            local squaresX = textX
            local squaresY = cardY + 26
            local squareSize = 10
            local squareSpacing = 2
            local level, progress = calculateLevelProgress(data.skillName, data.xp)
            drawLevelSquares(self, squaresX, squaresY, level, progress, squareSize, squareSpacing,
                {r=0.4, g=0.5, b=0.6},     -- Bluish (queued)
                {r=0.12, g=0.12, b=0.12},  -- Dark empty
                {r=0.25, g=0.3, b=0.4}     -- Dimmer blue for progress
            )
            local squaresWidth = 10 * squareSize + 9 * squareSpacing
            self:drawText("Queued #" .. queuePosition, squaresX + squaresWidth + 8, squaresY, 0.6, 0.75, 0.9, 1, UIFont.Small)
        elseif data.canClaim then
            -- Show level squares + XP
            local squaresX = textX
            local squaresY = cardY + 26
            local squareSize = 10
            local squareSpacing = 2
            local level, progress = calculateLevelProgress(data.skillName, data.xp)
            drawLevelSquares(self, squaresX, squaresY, level, progress, squareSize, squareSpacing,
                {r=0.3, g=0.55, b=0.65},   -- Teal filled
                {r=0.12, g=0.12, b=0.12},  -- Dark empty
                {r=0.2, g=0.35, b=0.4}     -- Dimmer teal for progress
            )
            local squaresWidth = 10 * squareSize + 9 * squareSpacing
            self:drawText(BurdJournals.formatXP(data.xp) .. " XP", squaresX + squaresWidth + 8, squaresY, 0.5, 0.75, 0.7, 1, UIFont.Small)
        else
            -- Already at or above this level - show dimmed squares
            local squaresX = textX
            local squaresY = cardY + 26
            local squareSize = 10
            local squareSpacing = 2
            local level, progress = calculateLevelProgress(data.skillName, data.xp)
            drawLevelSquares(self, squaresX, squaresY, level, progress, squareSize, squareSpacing,
                {r=0.25, g=0.3, b=0.3},    -- Muted (already claimed)
                {r=0.1, g=0.1, b=0.1},     -- Dark empty
                {r=0.18, g=0.22, b=0.22}   -- Dimmer for progress
            )
            local squaresWidth = 10 * squareSize + 9 * squareSpacing
            self:drawText("Already claimed", squaresX + squaresWidth + 8, squaresY, 0.4, 0.45, 0.45, 1, UIFont.Small)
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
                local btnText = getText("UI_BurdJournals_BtnQueue")
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.9, 0.95, 1, 1, UIFont.Small)
            else
                self:drawRect(btnX, btnY, btnW, btnH, 0.7, 0.2, 0.4, 0.5)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.3, 0.55, 0.65)
                local btnText = getText("UI_BurdJournals_BtnClaim")
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
        
        -- Trait name with color based on positive/negative type
        local traitColor
        if data.alreadyKnown then
            traitColor = {r=0.5, g=0.5, b=0.5}  -- Grayed out when already known
        elseif data.isPositive == true then
            traitColor = {r=0.5, g=0.9, b=0.5}  -- Green for positive traits
        elseif data.isPositive == false then
            traitColor = {r=0.9, g=0.5, b=0.5}  -- Red for negative traits
        else
            traitColor = {r=0.8, g=0.9, b=1.0}  -- Original light blue for unknown
        end
        self:drawText(traitName, traitTextX, cardY + 6, traitColor.r, traitColor.g, traitColor.b, 1, UIFont.Small)
        
        -- Status text
        if isLearningThis then
            local progressText = string.format("Learning... %d%%", math.floor(learningState.progress * 100))
            self:drawText(progressText, traitTextX, cardY + 22, 0.3, 0.7, 0.9, 1, UIFont.Small)

            -- Progress bar for traits (shorter width to account for icon offset)
            local barX = traitTextX + 100
            local barY = cardY + 25
            local barW = cardW - barX - 20  -- Dynamic width based on actual start position
            local barH = 10

            -- Bar background
            self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)
            -- Bar fill (blue/teal for claiming from player journal)
            self:drawRect(barX, barY, barW * learningState.progress, barH, 0.9, 0.25, 0.5, 0.7)
            -- Bar border
            self:drawRectBorder(barX, barY, barW, barH, 0.7, 0.35, 0.6, 0.8)
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
                local btnText = getText("UI_BurdJournals_BtnQueue")
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 1, 0.95, 0.9, 1, UIFont.Small)
            else
                self:drawRect(btnX, btnY, btnW, btnH, 0.7, 0.35, 0.45, 0.55)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.5, 0.6, 0.7)
                local btnText = getText("UI_BurdJournals_BtnClaim")
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 1, 1, 1, 1, UIFont.Small)
            end
        end
    end

    -- ============ RECIPE ROW ============
    if data.isRecipe then
        local learningState = mainPanel.learningState
        local isLearningThis = learningState and learningState.active and not learningState.isAbsorbAll
                              and learningState.recipeName == data.recipeName

        local recipeName = data.displayName or data.recipeName or "Unknown Recipe"
        local recipeTextX = textX

        -- Get magazine texture if available
        local magazineTexture = nil
        if data.magazineSource then
            pcall(function()
                local script = getScriptManager():getItem(data.magazineSource)
                if script then
                    local iconName = script:getIcon()
                    if iconName then
                        magazineTexture = getTexture("Item_" .. iconName)
                    end
                end
            end)
        end

        -- Draw magazine icon if available
        if magazineTexture then
            local iconSize = 24
            local iconX = textX
            local iconY = cardY + (cardH - iconSize) / 2
            local iconAlpha = data.alreadyKnown and 0.4 or 1.0
            self:drawTextureScaledAspect(magazineTexture, iconX, iconY, iconSize, iconSize, iconAlpha, 1, 1, 1)
            recipeTextX = textX + iconSize + 6
        end

        -- Check if in queue
        local queuePosition = mainPanel:getQueuePosition(data.recipeName)
        local isQueued = queuePosition ~= nil

        -- Recipe name with teal color theme
        local recipeColor
        if data.alreadyKnown then
            recipeColor = {r=0.5, g=0.5, b=0.5}  -- Grayed out when already known
        else
            recipeColor = {r=0.5, g=0.9, b=0.95}  -- Teal/cyan for available recipes
        end
        self:drawText(recipeName, recipeTextX, cardY + 6, recipeColor.r, recipeColor.g, recipeColor.b, 1, UIFont.Small)

        -- Status text
        if isLearningThis then
            local progressText = string.format("Learning... %d%%", math.floor(learningState.progress * 100))
            self:drawText(progressText, recipeTextX, cardY + 22, 0.3, 0.8, 0.85, 1, UIFont.Small)

            -- Progress bar for recipes
            local barX = recipeTextX + 100
            local barY = cardY + 25
            local barW = cardW - barX - 20
            local barH = 10

            -- Bar background
            self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)
            -- Bar fill (teal for recipes)
            self:drawRect(barX, barY, barW * learningState.progress, barH, 0.9, 0.25, 0.65, 0.75)
            -- Bar border
            self:drawRectBorder(barX, barY, barW, barH, 0.7, 0.35, 0.75, 0.85)
        elseif isQueued then
            self:drawText("Queued #" .. queuePosition, recipeTextX, cardY + 22, 0.5, 0.8, 0.9, 1, UIFont.Small)
        elseif data.alreadyKnown then
            self:drawText(getText("UI_BurdJournals_RecipeAlreadyKnown") or "Already known", recipeTextX, cardY + 22, 0.4, 0.45, 0.45, 1, UIFont.Small)
        else
            -- Show magazine source if available
            local sourceText = "Recorded recipe"
            if data.magazineSource then
                local magazineName = BurdJournals.getMagazineDisplayName(data.magazineSource)
                sourceText = string.format(getText("UI_BurdJournals_RecipeFromMagazine") or "From: %s", magazineName)
            end
            self:drawText(sourceText, recipeTextX, cardY + 22, 0.4, 0.65, 0.7, 1, UIFont.Small)
        end

        -- CLAIM/QUEUE button
        if not data.alreadyKnown and not isLearningThis then
            local btnW = 60
            local btnH = 24
            local btnX = cardX + cardW - btnW - 10
            local btnY = cardY + (cardH - btnH) / 2

            if isQueued then
                -- Show queue position indicator
                self:drawRect(btnX, btnY, btnW, btnH, 0.5, 0.3, 0.5, 0.55)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.6, 0.4, 0.6, 0.7)
                local btnText = "#" .. queuePosition
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.8, 0.95, 1, 1, UIFont.Small)
            elseif learningState and learningState.active and not learningState.isAbsorbAll then
                -- Show QUEUE button
                self:drawRect(btnX, btnY, btnW, btnH, 0.6, 0.25, 0.45, 0.55)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.35, 0.6, 0.7)
                local btnText = getText("UI_BurdJournals_BtnQueue")
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.9, 1, 1, 1, UIFont.Small)
            else
                -- Show CLAIM button (teal theme)
                self:drawRect(btnX, btnY, btnW, btnH, 0.7, 0.2, 0.45, 0.55)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.3, 0.6, 0.7)
                local btnText = getText("UI_BurdJournals_BtnClaim")
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.9, 1, 1, 1, UIFont.Small)
            end
        end
    end

    -- ============ STAT ROW ============
    if data.isStat then
        -- Stat name
        local statName = data.statName or data.statId or "Unknown Stat"
        self:drawText(statName, textX, cardY + 6, textColor.r, textColor.g, textColor.b, 1, UIFont.Small)

        -- Value display - show recorded value vs current
        if data.currentValue >= data.recordedValue then
            -- Player has surpassed or matched the recorded stat
            local achievedText = string.format(getText("UI_BurdJournals_RecordedAchieved") or "Recorded: %s (achieved!)", data.recordedFormatted or "?")
            self:drawText(achievedText, textX, cardY + 22, 0.4, 0.6, 0.4, 1, UIFont.Small)
        else
            -- Player is below the recorded stat
            local vsText = string.format(getText("UI_BurdJournals_RecordedVsCurrent") or "Recorded: %s | Current: %s", data.recordedFormatted or "?", data.currentFormatted or "?")
            self:drawText(vsText, textX, cardY + 22, 0.5, 0.6, 0.7, 1, UIFont.Small)
        end

        -- No button for stats - they're informational only
    end

    return y + h
end

-- Claim All button handler (for player journals)
function BurdJournals.UI.MainPanel:onClaimAll()
    if not self:startLearningAll() then
        self:showFeedback(getText("UI_BurdJournals_AlreadyReading") or "Already reading...", {r=0.9, g=0.7, b=0.3})
    end
end

-- Claim Tab button handler (tab-specific for player journals)
function BurdJournals.UI.MainPanel:onClaimTab()
    if not self:startLearningTab(self.currentTab or "skills") then
        self:showFeedback(getText("UI_BurdJournals_AlreadyReading") or "Already reading...", {r=0.9, g=0.7, b=0.3})
    end
end

-- Claim skill (SET mode - sets XP to recorded level)
function BurdJournals.UI.MainPanel:claimSkill(skillName, recordedXP)
    -- If already learning, add to queue
    if self.learningState.active and not self.learningState.isAbsorbAll then
        if self:addToQueue("skill", skillName, recordedXP) then
            self:showFeedback(string.format(getText("UI_BurdJournals_Queued") or "Queued: %s", BurdJournals.getPerkDisplayName(skillName) or skillName), {r=0.7, g=0.8, b=0.9})
        else
            self:showFeedback(getText("UI_BurdJournals_AlreadyQueued") or "Already queued", {r=0.9, g=0.7, b=0.3})
        end
        return
    end

    -- Start learning
    if not self:startLearningSkill(skillName, recordedXP) then
        self:showFeedback(getText("UI_BurdJournals_AlreadyReading") or "Already reading...", {r=0.9, g=0.7, b=0.3})
    end
end

-- Claim trait (same as absorb but from player journal)
function BurdJournals.UI.MainPanel:claimTrait(traitId)
    -- If already learning, add to queue
    if self.learningState.active and not self.learningState.isAbsorbAll then
        if self:addToQueue("trait", traitId) then
            local traitName = safeGetTraitName(traitId)
            self:showFeedback(string.format(getText("UI_BurdJournals_Queued") or "Queued: %s", traitName), {r=0.7, g=0.8, b=0.9})
        else
            self:showFeedback(getText("UI_BurdJournals_AlreadyQueued") or "Already queued", {r=0.9, g=0.7, b=0.3})
        end
        return
    end

    -- Start learning
    if not self:startLearningTrait(traitId) then
        self:showFeedback(getText("UI_BurdJournals_AlreadyReading") or "Already reading...", {r=0.9, g=0.7, b=0.3})
    end
end

-- Claim recipe (same as absorb but from player journal)
function BurdJournals.UI.MainPanel:claimRecipe(recipeName)
    -- If already learning, add to queue
    if self.learningState.active and not self.learningState.isAbsorbAll then
        if self:addToQueue("recipe", recipeName) then
            local displayName = BurdJournals.getRecipeDisplayName(recipeName) or recipeName
            self:showFeedback(string.format(getText("UI_BurdJournals_Queued") or "Queued: %s", displayName), {r=0.5, g=0.85, b=0.9})
        else
            self:showFeedback(getText("UI_BurdJournals_AlreadyQueued") or "Already queued", {r=0.9, g=0.7, b=0.3})
        end
        return
    end

    -- Start learning
    if not self:startLearningRecipe(recipeName) then
        self:showFeedback(getText("UI_BurdJournals_AlreadyReading") or "Already reading...", {r=0.9, g=0.7, b=0.3})
    end
end

-- Debug removed


