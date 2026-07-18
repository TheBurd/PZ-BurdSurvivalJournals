-- ============================================================================
-- BurdJournals_DebugPanel.lua
-- Debug Center UI for testing and development
-- Uses custom tab system (not ISTabPanel) for reliable rendering
-- ============================================================================

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTickBox"
require "ISUI/ISComboBox"
require "ISUI/ISModalDialog"

BurdJournals = BurdJournals or {}
BurdJournals.UI = BurdJournals.UI or {}

-- ============================================================================
-- Debug Panel Class
-- ============================================================================

BurdJournals.UI.DebugPanel = ISPanel:derive("BurdJournals_DebugPanel")

-- Singleton instance
BurdJournals.UI.DebugPanel.instance = nil

-- Panel dimensions (runtime is clamped to screen)
BurdJournals.UI.DebugPanel.DEFAULT_WIDTH = 860
BurdJournals.UI.DebugPanel.DEFAULT_HEIGHT = 760
BurdJournals.UI.DebugPanel.MIN_WIDTH = 760
BurdJournals.UI.DebugPanel.MIN_HEIGHT = 680
BurdJournals.UI.DebugPanel.SCREEN_MARGIN = 24

-- Scrollbar offset for right-aligned elements in lists
BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH = 15

-- ============================================================================
-- Constructor
-- ============================================================================

function BurdJournals.UI.DebugPanel:new(x, y, player)
    local width, height = BurdJournals.UI.DebugPanel.getPanelDimensions()
    
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    
    o.player = player
    o.backgroundColor = {r=0.1, g=0.1, b=0.12, a=0.98}
    o.borderColor = {r=0.3, g=0.5, b=0.7, a=1}
    o.moveWithMouse = true
    
    -- Drag state
    o.dragging = false
    o.dragOffsetX = 0
    o.dragOffsetY = 0
    
    -- Tab management
    o.currentTab = "spawn"
    o.tabPanels = {}
    o.tabButtons = {}
    
    -- Status message
    o.statusMessage = nil
    o.statusColor = {r=1, g=1, b=1}
    o.statusTime = 0
    o.sharedTargetUsername = player and player.getUsername and player:getUsername() or nil
    o.suppressTargetSync = false
    
    return o
end

-- ============================================================================
-- Utility Functions
-- ============================================================================

-- Safe localized text lookup for debug UI labels that must also survive B41.
local function debugText(key, fallback)
    if BurdJournals and BurdJournals.safeGetText then
        return BurdJournals.safeGetText(key, fallback)
    end
    if getText then
        local ok, value = pcall(getText, key)
        if ok and value and value ~= key then
            return value
        end
    end
    return fallback
end

local function debugFormatText(key, fallback, ...)
    local template = debugText(key, fallback)
    if BurdJournals and BurdJournals.formatText then
        return BurdJournals.formatText(template, ...)
    end
    local ok, value = pcall(string.format, template, ...)
    if ok and value then
        return value
    end
    return template
end

local DEBUG_TEXT_KEY_BY_ENGLISH = {
    ["Add XP"] = "UI_BurdJournals_DebugAddXP",
    ["Advanced"] = "UI_BurdJournals_DebugTabAdvanced",
    ["All"] = "UI_BurdJournals_DebugFilterAll",
    ["Apply Snapshot"] = "UI_BurdJournals_BaselineSnapshotApply",
    ["Auto (Type Default)"] = "UI_BurdJournals_DebugSpawnOriginAuto",
    ["Available"] = "UI_BurdJournals_DebugAvailable",
    ["Baseline draft cleared. Save to apply."] = "UI_BurdJournals_DebugBaselineDraftClearedSave",
    ["Baseline draft is already empty."] = "UI_BurdJournals_DebugBaselineDraftAlreadyEmpty",
    ["Baseline draft save unavailable"] = "UI_BurdJournals_DebugBaselineDraftSaveUnavailable",
    ["Baseline dumped to console"] = "UI_BurdJournals_DebugBaselineDumped",
    ["Baseline editing is disabled in this sandbox."] = "UI_BurdJournals_DebugBaselineEditingDisabled",
    ["Baseline skill draft already matches current skills."] = "UI_BurdJournals_DebugBaselineSkillsAlreadyMatch",
    ["Blank"] = "UI_BurdJournals_DebugJournalTypeBlank",
    ["Bloody"] = "UI_BurdJournals_DebugJournalTypeBloody",
    ["Clear All"] = "UI_BurdJournals_DebugClearAll",
    ["Clear All Baseline"] = "UI_BurdJournals_DebugClearAllBaseline",
    ["Click skill row to select"] = "UI_BurdJournals_DebugClickSkillRowToSelect",
    ["Clean"] = "UI_BurdJournals_DebugFilledStateClean",
    ["Copy Current Recipes"] = "UI_BurdJournals_DebugCopyCurrentRecipes",
    ["Copy Current Traits"] = "UI_BurdJournals_DebugCopyCurrentTraits",
    ["Could not build baseline draft payload"] = "UI_BurdJournals_DebugBaselineBuildDraftFailed",
    ["Cursed"] = "UI_BurdJournals_DebugJournalTypeCursed",
    ["Debug (Legacy)"] = "UI_BurdJournals_DebugSpawnProfileDebug",
    ["Debug Profile"] = "UI_BurdJournals_DebugSummaryDebugProfile",
    ["Delete Snapshot"] = "UI_BurdJournals_BaselineSnapshotDelete",
    ["Display refreshed (baseline unchanged)"] = "UI_BurdJournals_DebugDisplayRefreshedBaselineUnchanged",
    ["Dump Spawn Readiness"] = "UI_BurdJournals_DebugDumpSpawnReadiness",
    ["Dump to Console"] = "UI_BurdJournals_DebugDumpToConsole",
    ["Enter a positive XP amount to add"] = "UI_BurdJournals_DebugEnterPositiveXP",
    ["Failed to spawn journal"] = "UI_BurdJournals_DebugSpawnFailed",
    ["Filled"] = "UI_BurdJournals_DebugJournalTypeFilled",
    ["Found"] = "UI_BurdJournals_DebugSpawnOriginFound",
    ["Found in World"] = "UI_BurdJournals_DebugSpawnOriginWorld",
    ["Import JSON"] = "UI_BurdJournals_DebugJournalImportJSON",
    ["Journal Editor"] = "UI_BurdJournals_DebugTabJournalEditor",
    ["Known"] = "UI_BurdJournals_DebugKnown",
    ["Lore Mode:"] = "UI_BurdJournals_DebugSpawnLoreMode",
    ["Migrate Journals"] = "UI_BurdJournals_DebugMigrateJournals",
    ["No skill selected - click a skill row first"] = "UI_BurdJournals_DebugNoSkillSelected",
    ["Normal (Natural)"] = "UI_BurdJournals_DebugSpawnProfileNormal",
    ["Normal Profile"] = "UI_BurdJournals_DebugSummaryNormalProfile",
    ["Owned"] = "UI_BurdJournals_DebugOwned",
    ["Passive"] = "UI_BurdJournals_DebugPassive",
    ["Passive skill traits cannot be modified"] = "UI_BurdJournals_DebugPassiveTraitsLocked",
    ["Passive skills are disabled for loot journals in sandbox settings"] = "UI_BurdJournals_DebugPassiveSkillsDisabledLoot",
    ["Personal"] = "UI_BurdJournals_DebugSpawnOriginPersonal",
    ["Player"] = "UI_BurdJournals_DebugTabPlayer",
    ["Ready"] = "UI_BurdJournals_DebugReady",
    ["Recipes"] = "UI_BurdJournals_DebugWhitelistRecipes",
    ["Recipe baseline draft already matches current known recipes."] = "UI_BurdJournals_DebugBaselineRecipesAlreadyMatch",
    ["Recovered from Zombie"] = "UI_BurdJournals_DebugSpawnOriginZombie",
    ["Refresh"] = "UI_BurdJournals_DebugRefresh",
    ["Requested baseline snapshots..."] = "UI_BurdJournals_DebugSnapshotsRequested",
    ["Restored"] = "UI_BurdJournals_DebugFilledStateRestored",
    ["Save Snapshot"] = "UI_BurdJournals_BaselineSnapshotSave",
    ["Saving baseline snapshot..."] = "UI_BurdJournals_DebugSnapshotSaving",
    ["Selected"] = "UI_BurdJournals_DebugSelected",
    ["Selected Player:"] = "UI_BurdJournals_DebugSelectedPlayer",
    ["Select a snapshot first"] = "UI_BurdJournals_DebugSelectSnapshotFirst",
    ["Selections cleared"] = "UI_BurdJournals_DebugSelectionsCleared",
    ["Set to Current Skills"] = "UI_BurdJournals_DebugSetToCurrentSkills",
    ["Skills"] = "UI_BurdJournals_DebugWhitelistSkills",
    ["Skills dumped to console"] = "UI_BurdJournals_DebugSkillsDumped",
    ["Snapshot save unavailable"] = "UI_BurdJournals_DebugSnapshotSaveUnavailable",
    ["Spawn"] = "UI_BurdJournals_DebugTabSpawn",
    ["Spawn function not available"] = "UI_BurdJournals_DebugSpawnFunctionUnavailable",
    ["Spawn readiness dump unavailable"] = "UI_BurdJournals_DebugSpawnReadinessDumpUnavailable",
    ["Spawn readiness dumped to console"] = "UI_BurdJournals_DebugSpawnReadinessDumped",
    ["Starting"] = "UI_BurdJournals_DebugStarting",
    ["Starting Data"] = "UI_BurdJournals_DebugTabStartingData",
    ["Target player unavailable"] = "UI_BurdJournals_DebugTargetPlayerUnavailable",
    ["Trait baseline draft already matches current traits."] = "UI_BurdJournals_DebugBaselineTraitsAlreadyMatch",
    ["Traits"] = "UI_BurdJournals_DebugWhitelistTraits",
    ["Unknown"] = "UI_BurdJournals_DebugUnknown",
    ["Unknown Recipe"] = "UI_BurdJournals_DebugUnknownRecipe",
    ["Whitelist"] = "UI_BurdJournals_DebugTabWhitelist",
    ["Worn"] = "UI_BurdJournals_DebugJournalTypeWorn",
    ["Yuletide"] = "UI_BurdJournals_DebugJournalTypeYuletide",
}

local function debugTextFromEnglish(value)
    if type(value) ~= "string" then
        return value
    end
    local key = DEBUG_TEXT_KEY_BY_ENGLISH[value]
    if key then
        return debugText(key, value)
    end
    return value
end

local function getDebugTextWidth(text, font)
    local value = tostring(text or "")
    local textManager = getTextManager and getTextManager() or nil
    if textManager then
        if textManager.MeasureStringX then
            local ok, width = pcall(function()
                return textManager:MeasureStringX(font or UIFont.Small, value)
            end)
            if ok and type(width) == "number" then
                return width
            end
        end
        if textManager.measureStringX then
            local ok, width = pcall(function()
                return textManager:measureStringX(font or UIFont.Small, value)
            end)
            if ok and type(width) == "number" then
                return width
            end
        end
    end
    return string.len(value) * 7
end

local function fitDebugButtonWidth(title, font, minWidth, maxWidth, padding)
    local desired = math.ceil(getDebugTextWidth(title, font or UIFont.Small)) + (padding or 18)
    if maxWidth then
        desired = math.min(maxWidth, desired)
    end
    return math.max(minWidth or 0, desired)
end

-- Passive skill traits that need to be removed before setting skill level
-- These traits are auto-granted by PZ based on skill level, but having them
-- while trying to set a different level can cause conflicts (skill bounces back)
BurdJournals.UI.DebugPanel.PASSIVE_SKILL_TRAITS = {
    Strength = {"puny", "weak", "feeble", "stout", "strong"},
    Fitness = {"unfit", "outofshape", "fit", "athletic"}
}

-- Remove all passive skill traits for a specific skill before setting its level
-- This prevents the trait system from bouncing the skill back (e.g., Feeble trait
-- forcing Strength to stay at level 2-4 when trying to set to 0)
function BurdJournals.UI.DebugPanel.removePassiveSkillTraits(targetPlayer, skillName)
    local traits = BurdJournals.UI.DebugPanel.PASSIVE_SKILL_TRAITS[skillName]
    if not traits then return end
    
    BurdJournals.debugPrint("[BurdJournals] DEBUG (SP): Removing passive skill traits for " .. skillName)
    
    for _, traitId in ipairs(traits) do
        local removed = false
        
        -- Try safeRemoveTrait if available
        if BurdJournals.safeRemoveTrait then
            removed = BurdJournals.safeRemoveTrait(targetPlayer, traitId) == true
            if removed then
                BurdJournals.debugPrint("[BurdJournals] DEBUG (SP): Removed trait '" .. traitId .. "' via safeRemoveTrait")
            end
        end
        
        -- Direct trait removal fallback
        if not removed and targetPlayer and targetPlayer.getCharacterTraits then
            local charTraits = targetPlayer:getCharacterTraits()
            if charTraits and charTraits.size and charTraits.get then
                for i = charTraits:size() - 1, 0, -1 do
                    local traitObj = charTraits:get(i)
                    if traitObj then
                        local traitName = ""
                        if traitObj.getName then
                            traitName = traitObj:getName() or ""
                        else
                            traitName = tostring(traitObj)
                        end
                        if string.lower(traitName) == string.lower(traitId) then
                            if charTraits.remove then
                                charTraits:remove(traitObj)
                            end
                            if charTraits.set then
                                charTraits:set(traitObj, false)
                            end
                            local stillHas = targetPlayer.hasTrait and targetPlayer:hasTrait(traitObj) or false
                            if not stillHas then
                                removed = true
                                if BurdJournals.applyTraitLifecycleSideEffects then
                                    BurdJournals.applyTraitLifecycleSideEffects(targetPlayer, traitId, "trait_removed", {
                                        traitObj = traitObj,
                                        source = "DebugPanel.removePassiveSkillTraits_direct_fallback",
                                    })
                                end
                                BurdJournals.debugPrint("[BurdJournals] DEBUG (SP): Removed trait '" .. traitId .. "' via direct removal")
                                break
                            end
                        end
                    end
                end
            end
        end
    end
end

function BurdJournals.UI.DebugPanel.isAdminPlayer(player)
    if not player then return false end
    if player.isAccessLevel and player:isAccessLevel("admin") then
        return true
    end
    local accessLevel = player.getAccessLevel and player:getAccessLevel() or nil
    local normalized = tostring(accessLevel or ""):lower()
    return accessLevel ~= nil and normalized ~= "" and normalized ~= "none"
end

function BurdJournals.UI.DebugPanel:canTargetOtherPlayers()
    if not (isClient and isClient()) then
        return false
    end
    return BurdJournals.UI.DebugPanel.isAdminPlayer(self.player)
end

local function getDebugTargetPlayerName(player)
    if player and player.getUsername then
        local username = player:getUsername()
        if type(username) == "string" and username ~= "" then
            return username
        end
    end
    return "You"
end

local function collectDebugTargetablePlayers(panelSelf)
    local players = {}
    local seenNames = {}

    local function addPlayer(playerObj)
        if not playerObj then
            return
        end
        local username = getDebugTargetPlayerName(playerObj)
        if username == "" or seenNames[username] then
            return
        end
        seenNames[username] = true
        players[#players + 1] = playerObj
    end

    addPlayer(panelSelf.player)

    if panelSelf:canTargetOtherPlayers() then
        local onlinePlayers = getOnlinePlayers and getOnlinePlayers()
        if onlinePlayers then
            for i = 0, onlinePlayers:size() - 1 do
                addPlayer(onlinePlayers:get(i))
            end
        end
    end

    return players
end

local function findDebugPlayerByName(panelSelf, username)
    local wanted = tostring(username or "")
    if wanted == "" then
        return panelSelf.player
    end

    local targetablePlayers = collectDebugTargetablePlayers(panelSelf)
    for _, playerObj in ipairs(targetablePlayers) do
        if getDebugTargetPlayerName(playerObj) == wanted then
            return playerObj
        end
    end

    return panelSelf.player
end

local function setComboSelectedCompat(combo, index)
    if not combo then
        return
    end
    if combo.setSelected then
        combo:setSelected(index)
    else
        combo.selected = index
    end
end

local function applyDebugXPCompat(targetPlayer, perk, amount, options)
    if BurdJournals.applyXPDeltaCompat then
        local ok = BurdJournals.applyXPDeltaCompat(targetPlayer, perk, amount)
        return ok == true
    end

    local xpAmount = tonumber(amount) or 0
    if not targetPlayer or not perk or xpAmount == 0 then
        return xpAmount == 0
    end

    local xpObj = targetPlayer.getXp and targetPlayer:getXp() or nil
    if not (xpObj and xpObj.AddXP) then
        return false
    end

    local safePcallFn = BurdJournals.safePcall or pcall
    local ok = safePcallFn(function()
        xpObj:AddXP(perk, xpAmount)
    end)
    return ok == true
end

function BurdJournals.UI.DebugPanel:getSharedTargetPlayer()
    return findDebugPlayerByName(self, self.sharedTargetUsername)
end

function BurdJournals.UI.DebugPanel:updateSharedTargetSummary()
    if not self.sharedTargetHintLabel then
        return
    end

    local targetPlayer = self:getSharedTargetPlayer()
    local targetName = getDebugTargetPlayerName(targetPlayer)
    local hintText
    if self:canTargetOtherPlayers() then
        hintText = BurdJournals.formatText(getText("UI_BurdJournals_DebugViewingSharedTarget"), targetName)
    else
        hintText = getText("UI_BurdJournals_DebugViewingSharedSelf")
    end
    self.sharedTargetHintLabel:setName(hintText)
end

function BurdJournals.UI.DebugPanel:populateSharedTargetCombo()
    if not self.sharedTargetCombo then
        return
    end

    local combo = self.sharedTargetCombo
    local selectedPlayer = self:getSharedTargetPlayer()
    local selectedName = getDebugTargetPlayerName(selectedPlayer)

    combo:clear()
    local targetablePlayers = collectDebugTargetablePlayers(self)
    for _, playerObj in ipairs(targetablePlayers) do
        combo:addOptionWithData(getDebugTargetPlayerName(playerObj), playerObj)
    end

    if combo.select then
        combo:select(selectedName)
    else
        combo.selected = 1
    end

    self:updateSharedTargetSummary()
end

function BurdJournals.UI.DebugPanel:syncTargetCombos()
    local previousSuppress = self.suppressTargetSync
    self.suppressTargetSync = true

    if self.populateSharedTargetCombo then
        self:populateSharedTargetCombo()
    end
    if self.populateCharacterPlayerList then
        self:populateCharacterPlayerList()
    end
    if self.populateBaselinePlayerList then
        self:populateBaselinePlayerList()
    end
    if self.populateSnapshotPlayerList then
        self:populateSnapshotPlayerList()
    end

    self.suppressTargetSync = previousSuppress
end

function BurdJournals.UI.DebugPanel:getCharacterTargetUsername()
    local panel = self.charPanel
    local targetPlayer = panel and panel.targetPlayer or self.player
    return targetPlayer and targetPlayer.getUsername and targetPlayer:getUsername() or nil
end

function BurdJournals.UI.DebugPanel:isCharacterTargetLocal()
    local targetUsername = self:getCharacterTargetUsername()
    local localUsername = self.player and self.player.getUsername and self.player:getUsername() or nil
    return targetUsername == nil or localUsername == nil or tostring(targetUsername) == tostring(localUsername)
end

function BurdJournals.UI.DebugPanel:requestAuthoritativeCharacterData(reason)
    if not (BurdJournals.clientShouldUseServerAuthority()) then
        return false
    end
    if self:isCharacterTargetLocal() then
        return false
    end
    local targetUsername = self:getCharacterTargetUsername()
    if not targetUsername or targetUsername == "" then
        return false
    end
    if BurdJournals.Client and BurdJournals.Client.sendToServer then
        return BurdJournals.Client.sendToServer("debugRequestCharacterData", {
            targetUsername = targetUsername,
            reason = reason or "refresh",
        }, self.player) == true
    end
    sendClientCommand(self.player, "BurdJournals", "debugRequestCharacterData", {
        targetUsername = targetUsername,
        reason = reason or "refresh",
    })
    return true
end

function BurdJournals.UI.DebugPanel:applyAuthoritativeCharacterData(args)
    if type(args) ~= "table" then
        return
    end
    self.authoritativeCharacterData = self.authoritativeCharacterData or {}
    local username = tostring(args.targetUsername or "")
    if username == "" then
        return
    end
    self.authoritativeCharacterData[username] = args
    if self.charPanel and self:getCharacterTargetUsername() == username and self.refreshCharacterData then
        self:refreshCharacterData(true)
    end
end

function BurdJournals.UI.DebugPanel:getBaselineTargetUsername()
    local panel = self.baselinePanel
    local targetPlayer = panel and panel.targetPlayer or self.player
    return targetPlayer and targetPlayer.getUsername and targetPlayer:getUsername() or nil
end

function BurdJournals.UI.DebugPanel:isBaselineTargetLocal()
    local targetUsername = self:getBaselineTargetUsername()
    local localUsername = self.player and self.player.getUsername and self.player:getUsername() or nil
    return targetUsername == nil or localUsername == nil or tostring(targetUsername) == tostring(localUsername)
end

function BurdJournals.UI.DebugPanel:requestAuthoritativeBaselineData(reason)
    if not (BurdJournals.clientShouldUseServerAuthority()) then
        return false
    end
    if self:isBaselineTargetLocal() then
        return false
    end
    local targetUsername = self:getBaselineTargetUsername()
    if not targetUsername or targetUsername == "" then
        return false
    end
    if BurdJournals.Client and BurdJournals.Client.Debug and BurdJournals.Client.Debug.getTargetBaselinePayload then
        return BurdJournals.Client.Debug.getTargetBaselinePayload({
            targetUsername = targetUsername,
            reason = reason or "baselineRefresh",
        }, self.player) == true
    end
    return false
end

function BurdJournals.UI.DebugPanel:applyAuthoritativeBaselineData(args)
    if type(args) ~= "table" then
        return
    end
    local username = tostring(args.targetUsername or "")
    if username == "" then
        return
    end
    self.authoritativeBaselineData = self.authoritativeBaselineData or {}
    self.authoritativeBaselineData[username] = args
    if self.baselinePanel and self:getBaselineTargetUsername() == username and self.refreshBaselineData then
        self:refreshBaselineData(true)
    end
end

local function getDebugComboSelectedData(combo)
    if not combo then
        return nil
    end

    local options = type(combo.options) == "table" and combo.options or {}
    local optionCount = #options
    local candidates = {}

    if combo.getSelectedIndex then
        local ok, selectedIndex = pcall(function()
            return combo:getSelectedIndex()
        end)
        if ok and selectedIndex ~= nil then
            local index = tonumber(selectedIndex)
            if index then
                candidates[#candidates + 1] = index + 1
                candidates[#candidates + 1] = index
            end
        end
    end

    if combo.selected ~= nil then
        local selected = tonumber(combo.selected)
        if selected then
            candidates[#candidates + 1] = selected
            candidates[#candidates + 1] = selected + 1
        end
    end

    for _, index in ipairs(candidates) do
        if index and index >= 1 and index <= optionCount then
            local option = options[index]
            if option ~= nil then
                return option.data ~= nil and option.data or option
            end
        end
    end

    if combo.getOptionData and combo.selected ~= nil then
        local ok, data = pcall(function()
            return combo:getOptionData(combo.selected)
        end)
        if ok and data ~= nil then
            return data
        end
    end

    return nil
end

function BurdJournals.UI.DebugPanel:applySharedTargetPlayer(targetPlayer, options)
    options = options or {}
    local resolvedPlayer = targetPlayer or self.player

    if resolvedPlayer ~= self.player and not self:canTargetOtherPlayers() then
        self:syncTargetCombos()
        self:setStatus(getText("UI_BurdJournals_AdminOnly") or "This command requires admin access.", {r=1, g=0.6, b=0.3})
        return false
    end

    local baselinePanel = self.baselinePanel
    local previousBaselineTarget = baselinePanel and (baselinePanel.targetPlayer or self.player) or nil

    local function revertSelections()
        self:syncTargetCombos()
        if self.updateJournalTargetSummary then
            self:updateJournalTargetSummary()
        end
        BurdJournals.UI.DebugPanel.updateJournalDiminishingLabel(self)
    end

    local function applySelection()
        self.sharedTargetUsername = getDebugTargetPlayerName(resolvedPlayer)

        if self.charPanel then
            self.charPanel.targetPlayer = resolvedPlayer
        end
        if self.baselinePanel then
            self.baselinePanel.targetPlayer = resolvedPlayer
        end
        if self.snapshotPanel then
            self.snapshotPanel.targetPlayer = resolvedPlayer
        end

        self:syncTargetCombos()

        if self.refreshCharacterData then
            self:refreshCharacterData()
        end
        if self.refreshBaselineData then
            self:refreshBaselineData()
        end
        if self.refreshSnapshotPanelData then
            self:refreshSnapshotPanelData()
        end
        if self.updateJournalTargetSummary then
            self:updateJournalTargetSummary()
        end
        BurdJournals.UI.DebugPanel.updateJournalDiminishingLabel(self)

        local statusText = options.statusText
            or BurdJournals.formatText(getText("UI_BurdJournals_DebugViewingPlayer"), getDebugTargetPlayerName(resolvedPlayer))
        self:setStatus(statusText, {r=0.5, g=0.8, b=1})
    end

    if baselinePanel
        and previousBaselineTarget
        and previousBaselineTarget ~= resolvedPlayer
        and self:hasUnsavedBaselineDraft()
    then
        self:confirmDiscardBaselineDraft(
            getText("UI_BurdJournals_BaselineDraftActionChangeTarget") or "change selected player",
            applySelection,
            revertSelections
        )
        return false
    end

    applySelection()
    return true
end

local function closePlayerInventoryPanelsForController(player)
    if not player then
        return
    end

    local playerNum = player.getPlayerNum and player:getPlayerNum() or 0
    local joypadActive = false
    if BurdJournals and BurdJournals.isJoypadActiveForPlayer then
        joypadActive = BurdJournals.isJoypadActiveForPlayer(playerNum)
    elseif getJoypadData then
        local joypadData = getJoypadData(playerNum)
        if joypadData and (not joypadData.isConnected or joypadData:isConnected()) and joypadData.id ~= -1 then
            joypadActive = true
        end
    end

    if not joypadActive then
        return
    end

    local function closePanel(panel)
        if not panel then
            return
        end
        if panel.close then
            panel:close()
            return
        end
        if panel.setVisible then
            panel:setVisible(false)
        end
    end

    if getPlayerInventory then
        closePanel(getPlayerInventory(playerNum))
    end
    if getPlayerLoot then
        closePanel(getPlayerLoot(playerNum))
    end
end

-- ============================================================================
-- Initialization
-- ============================================================================

function BurdJournals.UI.DebugPanel:initialise()
    ISPanel.initialise(self)
end

function BurdJournals.UI.DebugPanel:prerender()
    ISPanel.prerender(self)

    -- Handle deferred journal refresh (from MainPanel erase operations)
    -- This prevents refresh during render cycle which can cause draw crashes
    if self.needsJournalRefresh then
        self.needsJournalRefresh = false
        if self.refreshJournalEditorData then
            self:refreshJournalEditorData()
        end
    end

    -- Handle deferred text entry updates (fixes "one step behind" issue)
    if self.spawnPanel then
        if self.spawnPanel.extraXPPendingUpdate then
            self.spawnPanel.extraXPPendingUpdate = false
            BurdJournals.UI.DebugPanel.onExtraXPChange(self)
        end
    end
end

function BurdJournals.UI.DebugPanel:createChildren()
    ISPanel.createChildren(self)
    
    local padding = 10
    local labelHeight = 18
    
    -- Title bar with drag support
    self.titleBar = ISPanel:new(0, 0, self.width, 30)
    self.titleBar:initialise()
    self.titleBar:instantiate()
    self.titleBar.backgroundColor = {r=0.15, g=0.25, b=0.35, a=1}
    self.titleBar.parentPanel = self  -- Reference to parent for drag handling
    
    -- Override title bar mouse handlers for reliable drag support
    self.titleBar.onMouseDown = function(titleBar, x, y)
        if not titleBar.parentPanel then return true end
        -- Start dragging the parent panel
        titleBar.parentPanel.dragging = true
        titleBar.parentPanel.dragOffsetX = titleBar:getAbsoluteX() + x
        titleBar.parentPanel.dragOffsetY = titleBar:getAbsoluteY() + y
        return true
    end
    
    self.titleBar.onMouseUp = function(titleBar, x, y)
        if titleBar.parentPanel then
            titleBar.parentPanel.dragging = false
        end
        return true
    end
    
    self.titleBar.onMouseMove = function(titleBar, dx, dy)
        if titleBar.parentPanel and titleBar.parentPanel.dragging then
            local newX = titleBar.parentPanel:getX() + dx
            local newY = titleBar.parentPanel:getY() + dy
            titleBar.parentPanel:setX(newX)
            titleBar.parentPanel:setY(newY)
        end
        return true
    end
    
    self.titleBar.onMouseMoveOutside = function(titleBar, dx, dy)
        if titleBar.parentPanel and titleBar.parentPanel.dragging then
            local newX = titleBar.parentPanel:getX() + dx
            local newY = titleBar.parentPanel:getY() + dy
            titleBar.parentPanel:setX(newX)
            titleBar.parentPanel:setY(newY)
        end
        return true
    end
    
    self.titleBar.onMouseUpOutside = function(titleBar, x, y)
        if titleBar.parentPanel then
            titleBar.parentPanel.dragging = false
        end
        return true
    end
    
    self:addChild(self.titleBar)
    
    -- Title text
    self.titleLabel = ISLabel:new(padding, 6, labelHeight, debugText("UI_BurdJournals_DebugTitle", "BSJ Debug Center"), 1, 1, 1, 1, UIFont.Medium, true)
    self.titleLabel:initialise()
    self.titleLabel:instantiate()
    self.titleBar:addChild(self.titleLabel)
    
    -- Close button
    self.closeBtn = ISButton:new(self.width - 30, 3, 24, 24, "X", self, BurdJournals.UI.DebugPanel.onClose)
    self.closeBtn:initialise()
    self.closeBtn:instantiate()
    self.closeBtn.font = UIFont.Small
    self.closeBtn.textColor = {r=1, g=1, b=1, a=1}
    self.closeBtn.borderColor = {r=0.7, g=0.3, b=0.3, a=1}
    self.closeBtn.backgroundColor = {r=0.5, g=0.15, b=0.15, a=0.8}
    self.titleBar:addChild(self.closeBtn)
    
    -- Shared player target strip for admin-friendly inspection.
    local targetStripY = 34
    local targetLabel = ISLabel:new(padding, targetStripY + 4, labelHeight, debugText("UI_BurdJournals_DebugViewingPlayerLabel", "Viewing Player:"), 0.86, 0.9, 1, 1, UIFont.Small, true)
    targetLabel:initialise()
    targetLabel:instantiate()
    self:addChild(targetLabel)

    self.sharedTargetCombo = ISComboBox:new(padding + 95, targetStripY, 210, 22, self, BurdJournals.UI.DebugPanel.onSharedTargetPlayerChange)
    self.sharedTargetCombo:initialise()
    self.sharedTargetCombo:instantiate()
    self.sharedTargetCombo.font = UIFont.Small
    self:addChild(self.sharedTargetCombo)

    local refreshPlayersTitle = debugText("UI_BurdJournals_DebugRefreshPlayers", "Refresh Players")
    local refreshPlayersWidth = fitDebugButtonWidth(refreshPlayersTitle, UIFont.Small, 88, 160, 18)
    local refreshPlayersBtn = ISButton:new(padding + 310, targetStripY, refreshPlayersWidth, 22, refreshPlayersTitle, self, BurdJournals.UI.DebugPanel.onSharedTargetRefresh)
    refreshPlayersBtn:initialise()
    refreshPlayersBtn:instantiate()
    refreshPlayersBtn.font = UIFont.Small
    refreshPlayersBtn.textColor = {r=1, g=1, b=1, a=1}
    refreshPlayersBtn.borderColor = {r=0.4, g=0.5, b=0.6, a=1}
    refreshPlayersBtn.backgroundColor = {r=0.2, g=0.25, b=0.3, a=1}
    self:addChild(refreshPlayersBtn)

    self.sharedTargetHintLabel = ISLabel:new(padding + 317 + refreshPlayersWidth, targetStripY + 4, labelHeight, "", 0.62, 0.74, 0.88, 1, UIFont.Small, true)
    self.sharedTargetHintLabel:initialise()
    self.sharedTargetHintLabel:instantiate()
    self:addChild(self.sharedTargetHintLabel)

    self:populateSharedTargetCombo()

    -- Tab bar (custom buttons instead of ISTabPanel)
    local tabY = 60
    local tabBtnHeight = 25
    local tabs = {
        {id = "spawn", label = debugText("UI_BurdJournals_DebugTabSpawn", "Spawn")},
        {id = "character", label = debugText("UI_BurdJournals_DebugTabPlayer", "Player")},
        {id = "baseline", label = debugText("UI_BurdJournals_DebugTabStartingData", "Starting Data")},
        {id = "snapshots", label = getText("UI_BurdJournals_DebugTabSnapshots") or "Saved Snapshots"},
        {id = "journal", label = debugText("UI_BurdJournals_DebugTabJournalEditor", "Journal Editor")},
        {id = "whitelist", label = debugText("UI_BurdJournals_DebugTabWhitelist", "Whitelist")},
        {id = "diagnostics", label = debugText("UI_BurdJournals_DebugTabAdvanced", "Advanced")},
    }
    local tabX = 5
    local availableW = math.max(420, self.width - 10)
    local minTabW = 72
    local spacing = 2
    local tabWidths = {}
    local tabWidthTotal = 0
    local spacingTotal = (#tabs - 1) * spacing
    for i, tab in ipairs(tabs) do
        local tabW = fitDebugButtonWidth(tab.label, UIFont.Small, minTabW, 158, 20)
        tabWidths[i] = tabW
        tabWidthTotal = tabWidthTotal + tabW
    end
    if tabWidthTotal + spacingTotal > availableW then
        local scale = math.max(0.1, (availableW - spacingTotal) / math.max(1, tabWidthTotal))
        local scaledTotal = 0
        for i, tabW in ipairs(tabWidths) do
            tabWidths[i] = math.max(minTabW, math.floor(tabW * scale))
            scaledTotal = scaledTotal + tabWidths[i]
        end
        if scaledTotal + spacingTotal > availableW then
            local equalW = math.max(50, math.floor((availableW - spacingTotal) / #tabs))
            for i = 1, #tabWidths do
                tabWidths[i] = equalW
            end
        end
    end
    
    for i, tab in ipairs(tabs) do
        local tabBtnWidth = tabWidths[i] or minTabW
        local btn = ISButton:new(tabX, tabY, tabBtnWidth, tabBtnHeight, tab.label, self, BurdJournals.UI.DebugPanel.onTabClick)
        btn:initialise()
        btn:instantiate()
        btn.font = UIFont.Small
        btn.internal = tab.id
        btn.textColor = {r=1, g=1, b=1, a=1}
        btn.borderColor = {r=0.4, g=0.5, b=0.6, a=1}
        btn.backgroundColor = {r=0.15, g=0.15, b=0.2, a=1}
        self:addChild(btn)
        self.tabButtons[tab.id] = btn
        tabX = tabX + tabBtnWidth + spacing
    end
    
    -- Content area
    local contentY = tabY + tabBtnHeight + 5
    local contentHeight = self.height - contentY - 35  -- Room for status bar
    
    -- Clear trait caches before populating panels to ensure fresh discovery
    BurdJournals.UI.DebugPanel.clearTraitCaches()
    
    -- Build only the initially visible tab. Other tabs can contain thousands
    -- of modded traits/recipes, so constructing them eagerly causes a large
    -- hitch before the user has opened them.
    self._debugContentY = contentY
    self._debugContentHeight = contentHeight
    self:createDebugTab("spawn")
    
    -- Status bar
    self.statusBar = ISPanel:new(0, self.height - 30, self.width, 30)
    self.statusBar:initialise()
    self.statusBar:instantiate()
    self.statusBar.backgroundColor = {r=0.08, g=0.08, b=0.1, a=1}
    self:addChild(self.statusBar)
    
    self.statusLabel = ISLabel:new(padding, 6, labelHeight, debugText("UI_BurdJournals_DebugReady", "Ready"), 0.6, 0.7, 0.8, 1, UIFont.Small, true)
    self.statusLabel:initialise()
    self.statusLabel:instantiate()
    self.statusBar:addChild(self.statusLabel)
    
    -- Show initial tab
    self:showTab("spawn")
end

-- ============================================================================
-- Tab Switching
-- ============================================================================

function BurdJournals.UI.DebugPanel:onTabClick(button)
    local tabId = button.internal
    self:showTab(tabId)
end

-- Forward declaration so earlier callbacks resolve the local helper.
local isAffirmativeDialogButton

function BurdJournals.UI.DebugPanel:hasUnsavedBaselineDraft()
    local panel = self.baselinePanel
    return panel and panel.baselineDraftDirty == true
end

function BurdJournals.UI.DebugPanel:resetBaselineDraftState()
    local panel = self.baselinePanel
    if not panel then
        return
    end
    panel.baselineDraftDirty = false
    panel.baselineDraftSkills = {}
    panel.baselineDraftTraits = {}
    panel.baselineDraftRecipes = {}
    if self.updateBaselineDraftButtons then
        self:updateBaselineDraftButtons()
    end
end

function BurdJournals.UI.DebugPanel:confirmDiscardBaselineDraft(actionText, onConfirm, onCancel)
    if not self:hasUnsavedBaselineDraft() then
        if onConfirm then
            onConfirm()
        end
        return true
    end

    if self.baselineDraftPromptOpen then
        return false
    end

    local actionLabel = tostring(actionText or "continue")
    local promptTemplate = getText("UI_BurdJournals_BaselineDraftUnsavedPrompt")
        or "You have unsaved changes that could be lost. Are you sure you want to %s?"
    local promptText = BurdJournals.formatText(promptTemplate, actionLabel)

    if ISModalDialog then
        self.baselineDraftPromptOpen = true
        local selfRef = self
        local callback = function(_target, buttonObj)
            selfRef.baselineDraftPromptOpen = false
            if isAffirmativeDialogButton(buttonObj) then
                selfRef:resetBaselineDraftState()
                if onConfirm then
                    onConfirm()
                end
            else
                if onCancel then
                    onCancel()
                end
                selfRef:setStatus(
                    getText("UI_BurdJournals_BaselineDraftUnsavedCancelled") or "Unsaved baseline changes kept.",
                    {r=0.95, g=0.78, b=0.45}
                )
            end
        end
        if BurdJournals.createAdaptiveModalDialog then
            BurdJournals.createAdaptiveModalDialog({
                player = self.player,
                text = promptText,
                yesNo = true,
                onClick = callback,
                minWidth = 420,
                maxWidth = 820,
                minHeight = 175,
            })
        else
            local w, h = 520, 180
            local x = (getCore():getScreenWidth() - w) / 2
            local y = (getCore():getScreenHeight() - h) / 2
            local modal = ISModalDialog:new(x, y, w, h, promptText, true, nil, callback)
            modal:initialise()
            modal:addToUIManager()
        end
        return false
    end

    self:resetBaselineDraftState()
    if onConfirm then
        onConfirm()
    end
    return true
end

function BurdJournals.UI.DebugPanel:createDebugTab(tabId)
    if self.tabPanels and self.tabPanels[tabId] then
        return self.tabPanels[tabId]
    end
    local y = self._debugContentY
    local height = self._debugContentHeight
    if not y or not height then return nil end
    if tabId == "spawn" then
        self:createSpawnPanel(y, height)
    elseif tabId == "character" then
        self:createCharacterPanel(y, height)
    elseif tabId == "baseline" then
        self:createBaselinePanel(y, height)
    elseif tabId == "snapshots" then
        self:createSnapshotsPanel(y, height)
    elseif tabId == "journal" then
        self:createJournalPanel(y, height)
    elseif tabId == "whitelist" then
        self:createWhitelistPanel(y, height)
    elseif tabId == "diagnostics" then
        self:createDiagnosticsPanel(y, height)
    end
    local panel = self.tabPanels and self.tabPanels[tabId] or nil
    local sharedTarget = self.getSharedTargetPlayer and self:getSharedTargetPlayer() or nil
    if panel and sharedTarget and sharedTarget ~= self.player then
        panel.targetPlayer = sharedTarget
        if tabId == "character" and self.refreshCharacterData then
            self:refreshCharacterData()
        elseif tabId == "baseline" and self.refreshBaselineData then
            self:refreshBaselineData()
        end
    end
    return panel
end

function BurdJournals.UI.DebugPanel:showTab(tabId, skipBaselineDraftConfirm)
    if not skipBaselineDraftConfirm
        and self.currentTab == "baseline"
        and tabId ~= "baseline"
        and self:hasUnsavedBaselineDraft()
    then
        self:confirmDiscardBaselineDraft(
            getText("UI_BurdJournals_BaselineDraftActionSwitchTabs") or "switch tabs",
            function()
                self:showTab(tabId, true)
            end
        )
        return
    end

    self:createDebugTab(tabId)
    self.currentTab = tabId
    
    -- Hide all panels, show selected
    for id, panel in pairs(self.tabPanels) do
        panel:setVisible(id == tabId)
    end
    
    -- Update button styles
    for id, btn in pairs(self.tabButtons) do
        if id == tabId then
            btn.backgroundColor = {r=0.3, g=0.4, b=0.5, a=1}
            btn.borderColor = {r=0.5, g=0.7, b=0.9, a=1}
        else
            btn.backgroundColor = {r=0.15, g=0.15, b=0.2, a=1}
            btn.borderColor = {r=0.4, g=0.5, b=0.6, a=1}
        end
    end

    if tabId == "journal" and self.refreshJournalPickerList then
        self:refreshJournalPickerList(true)
        if self.onJournalRefreshServerIndex then
            self:onJournalRefreshServerIndex()
        end
    elseif tabId == "baseline" then
        if self.populateBaselinePlayerList then
            self:populateBaselinePlayerList()
        end
        if self.refreshBaselineData then
            self:refreshBaselineData()
        end
    elseif tabId == "snapshots" then
        if self.populateSnapshotPlayerList then
            self:populateSnapshotPlayerList()
        end
        if self.refreshSnapshotPanelData then
            self:refreshSnapshotPanelData()
        end
    elseif tabId == "whitelist" then
        if self.requestAdminPolicy then
            self:requestAdminPolicy()
        end
        if self.refreshWhitelistData then
            self:refreshWhitelistData()
        end
    end

    if self.updateSharedTargetSummary then
        self:updateSharedTargetSummary()
    end
    if self.updateJournalTargetSummary then
        self:updateJournalTargetSummary()
    end
    BurdJournals.UI.DebugPanel.updateJournalDiminishingLabel(self)
end

function BurdJournals.UI.DebugPanel:onSharedTargetPlayerChange(combo)
    if self.suppressTargetSync then
        return
    end

    local selectedPlayer = getDebugComboSelectedData(combo) or self.player
    self:applySharedTargetPlayer(selectedPlayer, {
        statusText = BurdJournals.formatText(getText("UI_BurdJournals_DebugViewingPlayer"), getDebugTargetPlayerName(selectedPlayer)),
    })
end

function BurdJournals.UI.DebugPanel:onSharedTargetRefresh()
    self:syncTargetCombos()
    if self.refreshCharacterData then
        self:refreshCharacterData()
    end
    if self.refreshBaselineData and not self:hasUnsavedBaselineDraft() then
        self:refreshBaselineData()
    end
    if self.refreshSnapshotPanelData then
        self:refreshSnapshotPanelData()
    end
    if self.updateJournalTargetSummary then
        self:updateJournalTargetSummary()
    end
    BurdJournals.UI.DebugPanel.updateJournalDiminishingLabel(self)
    if self:hasUnsavedBaselineDraft() then
        self:setStatus(debugText("UI_BurdJournals_DebugPlayerListsRefreshedDraftKept", "Player lists refreshed. Starting Data draft kept."), {r=0.5, g=0.8, b=1})
    else
        self:setStatus(debugText("UI_BurdJournals_DebugPlayerListsRefreshed", "Player lists refreshed"), {r=0.5, g=0.8, b=1})
    end
end

local function normalizeDebugSearchText(value)
    local text = string.lower(tostring(value or ""))
    if text == "" then
        return ""
    end

    -- Strip common rich-text style tags and normalize punctuation/spacing.
    text = string.gsub(text, "%[img=[^%]]-%]", " ")
    text = string.gsub(text, "%[col=[^%]]-%]", " ")
    text = string.gsub(text, "%[/col%]", " ")
    text = string.gsub(text, "[%p_]+", " ")
    text = string.gsub(text, "%s+", " ")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

isAffirmativeDialogButton = function(button)
    if not button then
        return false
    end
    local internal = string.upper(tostring(button.internal or ""))
    if internal == "YES" or internal == "OK" or internal == "TRUE" or internal == "1" then
        return true
    end
    local title = string.upper(tostring(button.title or button.name or ""))
    if title == "YES" or title == "OK" then
        return true
    end
    return false
end

local function debugSearchMatches(query, ...)
    local normalizedQuery = normalizeDebugSearchText(query)
    if normalizedQuery == "" then
        return true
    end

    local compactQuery = string.gsub(normalizedQuery, "%s+", "")
    for i = 1, select("#", ...) do
        local haystack = normalizeDebugSearchText(select(i, ...))
        if haystack ~= "" then
            if string.find(haystack, normalizedQuery, 1, true) then
                return true
            end
            if compactQuery ~= "" then
                local compactHaystack = string.gsub(haystack, "%s+", "")
                if string.find(compactHaystack, compactQuery, 1, true) then
                    return true
                end
            end
        end
    end

    return false
end

local debugTraitTextureCache = {}
local debugTraitTextureIndex = nil
local debugRecipeTextureCache = nil
local debugRecipeCatalogCache = nil
local debugRecipeMembershipIndexCache = setmetatable({}, { __mode = "k" })
local debugMagazineTextureCache = {}
local debugItemTextureCache = {}

local function resolveDebugTexture(...)
    if not getTexture then
        return nil
    end
    for i = 1, select("#", ...) do
        local candidate = select(i, ...)
        if candidate and tostring(candidate) ~= "" then
            local texture = getTexture(tostring(candidate))
            if texture then
                return texture
            end
        end
    end
    return nil
end

local function resolveDebugTraitTexture(rawTexture)
    if not rawTexture then
        return nil
    end
    if type(rawTexture) ~= "string" then
        return rawTexture
    end
    return resolveDebugTexture(
        rawTexture,
        "media/ui/" .. rawTexture,
        "media/ui/" .. rawTexture .. ".png",
        "media/ui/Traits/" .. rawTexture,
        "media/ui/Traits/" .. rawTexture .. ".png"
    )
end

local function getDebugTraitTextureIndex()
    if debugTraitTextureIndex ~= nil then
        return debugTraitTextureIndex
    end
    local index = {}
    local function addIndexKey(value, texture)
        if value == nil or texture == nil then return end
        local key = string.lower(tostring(value))
        if key ~= "" then
            index[key] = texture
            index[string.gsub(key, "%s+", "")] = texture
        end
    end
    if CharacterTraitDefinition and CharacterTraitDefinition.getTraits then
        local allTraits = CharacterTraitDefinition.getTraits()
        if allTraits and allTraits.size and allTraits.get then
            for i = 0, allTraits:size() - 1 do
                local def = allTraits:get(i)
                if def then
                    local rawType = def.getType and def:getType() or nil
                    local typeName = rawType and rawType.getName and rawType:getName() or rawType
                    local rawTexture = def.getTexture and def:getTexture() or def.texture
                    local texture = resolveDebugTraitTexture(rawTexture)
                    addIndexKey(typeName, texture)
                    addIndexKey(def.getLabel and def:getLabel() or nil, texture)
                end
            end
        end
    end
    debugTraitTextureIndex = index
    return index
end

local function getDebugTraitTexture(traitId)
    if not traitId then
        return nil
    end
    local cacheKey = string.lower(tostring(traitId))
    if debugTraitTextureCache[cacheKey] ~= nil then
        return debugTraitTextureCache[cacheKey] or nil
    end

    local indexedTexture = getDebugTraitTextureIndex()[cacheKey]
        or getDebugTraitTextureIndex()[string.gsub(cacheKey, "%s+", "")]
    if indexedTexture then
        debugTraitTextureCache[cacheKey] = indexedTexture
        return indexedTexture
    end

    local normalizedId = string.gsub(cacheKey, "%s+", "")
    local texture = nil

    local function captureTexture(def)
        if not def then
            return nil
        end
        local rawTexture = nil
        if def.getTexture then
            rawTexture = def:getTexture()
        elseif def.texture ~= nil then
            rawTexture = def.texture
        end
        return resolveDebugTraitTexture(rawTexture)
    end

    if CharacterTraitDefinition and CharacterTraitDefinition.getTraits then
        local allTraits = CharacterTraitDefinition.getTraits()
        if allTraits and allTraits.size and allTraits.get then
            for i = 0, allTraits:size() - 1 do
                local def = allTraits:get(i)
                if def then
                    local label = def.getLabel and tostring(def:getLabel() or "") or ""
                    local rawType = def.getType and def:getType() or nil
                    local typeName = ""
                    if rawType and rawType.getName then
                        typeName = tostring(rawType:getName() or "")
                    elseif rawType then
                        typeName = tostring(rawType or "")
                    end
                    local compareId = string.lower(typeName)
                    local compareLabel = string.lower(label)
                    local compareIdCompact = string.gsub(compareId, "%s+", "")
                    local compareLabelCompact = string.gsub(compareLabel, "%s+", "")
                    if compareId == cacheKey
                        or compareLabel == cacheKey
                        or compareIdCompact == normalizedId
                        or compareLabelCompact == normalizedId
                    then
                        texture = captureTexture(def)
                        if texture then
                            break
                        end
                    end
                end
            end
        end
    end

    if not texture and TraitFactory and TraitFactory.getTrait then
        local traitObj = TraitFactory.getTrait(traitId)
            or TraitFactory.getTrait(string.gsub(tostring(traitId), "^base:", ""))
        if traitObj then
            texture = captureTexture(traitObj)
        end
    end

    debugTraitTextureCache[cacheKey] = texture or false
    return texture
end

local function getDebugMagazineTexture(magazineSource)
    if not magazineSource then
        return nil
    end
    local cacheKey = tostring(magazineSource)
    if debugMagazineTextureCache[cacheKey] ~= nil then
        return debugMagazineTextureCache[cacheKey] or nil
    end
    if not getScriptManager then
        debugMagazineTextureCache[cacheKey] = false
        return nil
    end
    local scriptMgr = getScriptManager()
    if not scriptMgr or not scriptMgr.getItem then
        debugMagazineTextureCache[cacheKey] = false
        return nil
    end
    local script = scriptMgr:getItem(magazineSource)
    if not script or not script.getIcon then
        debugMagazineTextureCache[cacheKey] = false
        return nil
    end
    local iconName = script:getIcon()
    if not iconName or iconName == "" then
        debugMagazineTextureCache[cacheKey] = false
        return nil
    end
    local texture = resolveDebugTexture(
        "Item_" .. iconName,
        "media/textures/Item_" .. iconName .. ".png",
        "media/ui/" .. iconName,
        "media/ui/" .. iconName .. ".png"
    )
    debugMagazineTextureCache[cacheKey] = texture or false
    return texture
end

local function getDebugRecipeTexture()
    if debugRecipeTextureCache ~= nil then
        return debugRecipeTextureCache or nil
    end
    debugRecipeTextureCache = resolveDebugTexture(
        "media/ui/inventoryPanes/craft.png",
        "media/ui/Icon_RecipeGroup_Open_48x48.png",
        "media/ui/Icon_RecipeGroup_Closed_48x48.png",
        "media/ui/craftingMenus/BuildProperty_Book_16.png",
        "media/ui/craftingMenus/BuildProperty_Book.png"
    ) or false
    return debugRecipeTextureCache ~= false and debugRecipeTextureCache or nil
end

local function getDebugItemTexture(iconName)
    if not iconName then
        return nil
    end

    local cacheKey = tostring(iconName)
    if debugItemTextureCache[cacheKey] ~= nil then
        return debugItemTextureCache[cacheKey] or nil
    end

    local texture = resolveDebugTexture(
        "Item_" .. cacheKey,
        "media/textures/Item_" .. cacheKey .. ".png"
    )
    debugItemTextureCache[cacheKey] = texture or false
    return texture
end

local function getDebugJournalTypeIconName(journalType)
    local jType = string.lower(tostring(journalType or ""))
    local debugType = BurdJournals.getDebugJournalType and BurdJournals.getDebugJournalType(jType) or nil
    if type(debugType) == "table" and debugType.iconName then
        return tostring(debugType.iconName)
    end
    if jType == "blank" then
        return "BlankJournalClean"
    elseif jType == "filled" then
        return "FilledJournalClean"
    elseif jType == "worn" then
        return "FilledJournalWorn"
    elseif jType == "bloody" then
        return "FilledJournalBloody"
    elseif jType == "cursed" then
        return "CursedJournal"
    elseif jType == "yuletide" then
        return (BurdJournals.getYuletideWrappedIconName and BurdJournals.getYuletideWrappedIconName(nil))
            or "YuletideJournalWrapped_1"
    end
    return nil
end

local function getDebugJournalTypeTexture(journalType)
    return getDebugItemTexture(getDebugJournalTypeIconName(journalType))
end

local DEBUG_BUILTIN_JOURNAL_TYPES = {
    blank = true,
    filled = true,
    worn = true,
    bloody = true,
    cursed = true,
    yuletide = true,
}

local function isDebugSpawnJournalTypeAllowed(journalType)
    local value = tostring(journalType or "")
    if DEBUG_BUILTIN_JOURNAL_TYPES[value] == true then
        return true
    end
    return BurdJournals.isDebugJournalTypeRegistered
        and BurdJournals.isDebugJournalTypeRegistered(value) == true
end

function BurdJournals.UI.DebugPanel.getDebugSpawnJournalTypeDefs()
    local out = {
        {id = "blank", label = debugText("UI_BurdJournals_DebugJournalTypeBlank", "Blank"), sortOrder = 10},
        {id = "filled", label = debugText("UI_BurdJournals_DebugJournalTypeFilled", "Filled"), sortOrder = 20},
        {id = "worn", label = debugText("UI_BurdJournals_DebugJournalTypeWorn", "Worn"), sortOrder = 30},
        {id = "bloody", label = debugText("UI_BurdJournals_DebugJournalTypeBloody", "Bloody"), sortOrder = 40},
        {id = "cursed", label = debugText("UI_BurdJournals_DebugJournalTypeCursed", "Cursed"), sortOrder = 50},
        {id = "yuletide", label = debugText("UI_BurdJournals_DebugJournalTypeYuletide", "Yuletide"), sortOrder = 60},
    }
    if BurdJournals.getDebugJournalTypes then
        for _, def in ipairs(BurdJournals.getDebugJournalTypes() or {}) do
            if type(def) == "table" and def.id and not DEBUG_BUILTIN_JOURNAL_TYPES[tostring(def.id)] then
                out[#out + 1] = def
            end
        end
    end
    table.sort(out, function(a, b)
        local ao = tonumber(a.sortOrder) or 1000
        local bo = tonumber(b.sortOrder) or 1000
        if ao ~= bo then return ao < bo end
        return tostring(a.label or a.id or "") < tostring(b.label or b.id or "")
    end)
    return out
end

local function getDebugYuletideTextureForState(stateValue, wrappedVariant)
    local wrappedState = BurdJournals.YULETIDE_STATE_WRAPPED or "wrapped"
    local unwrappedState = BurdJournals.YULETIDE_STATE_UNWRAPPED or "unwrapped"
    local state = tostring(stateValue or wrappedState)
    if state == unwrappedState then
        return getDebugItemTexture("YuletideJournalUnwrapped")
    end

    local variant = wrappedVariant
    if BurdJournals.normalizeYuletideWrappedVariant then
        variant = BurdJournals.normalizeYuletideWrappedVariant(variant)
    else
        variant = tostring(variant or "1")
    end
    return getDebugItemTexture("YuletideJournalWrapped_" .. tostring(variant))
end

local function getSelectedComboOptionData(combo)
    if not combo or not combo.selected or combo.selected < 1 then
        return nil
    end
    return combo:getOptionData(combo.selected) or combo.options[combo.selected]
end

local function getSelectedYuletideWrappedVariant(panel)
    local variant = getSelectedComboOptionData(panel and panel.yuletideWrappedVariantCombo)
    if BurdJournals.normalizeYuletideWrappedVariant then
        return BurdJournals.normalizeYuletideWrappedVariant(variant)
    end
    return tostring(variant or "1")
end

local function drawDebugListIcon(listbox, texture, x, y, h, alpha, sizeOverride)
    if not (listbox and texture) then
        return 0
    end
    local rowHeight = tonumber(h) or 24
    local iconSize = math.max(10, math.min(rowHeight - 6, tonumber(sizeOverride) or 14))
    local iconY = y + (rowHeight - iconSize) / 2
    listbox:drawTextureScaledAspect(texture, x, iconY, iconSize, iconSize, alpha or 1, 1, 1, 1)
    return iconSize
end

local function drawDebugIconComboPopupItem(popup, y, item, alt)
    local combo = popup and popup.parentCombo or nil
    if not combo then
        return y
    end
    if combo:hasFilterText() then
        if not item.text:lower():contains(combo:getFilterText():lower()) then
            return y
        end
    end
    if item.height == 0 then
        item.height = popup.itemheight
    end
    if y + popup:getYScroll() + item.height < 0 or y + popup:getYScroll() >= popup.height then
        return y + item.height
    end

    local highlight = (popup:isMouseOver() and not popup:isMouseOverScrollBar()) and popup.mouseoverselected or popup.selected
    if combo.joypadFocused then
        highlight = popup.selected
    end
    if highlight == item.index then
        local selectColor = combo.backgroundColorMouseOver
        popup:drawRect(0, y, popup:getWidth(), item.height - 1, selectColor.a, selectColor.r, selectColor.g, selectColor.b)
        local mouseOver = popup:isMouseOver() and not popup:isMouseOverScrollBar()
        if combo.joypadFocused then
            mouseOver = true
        end
        if mouseOver then
            local textWid = getTextManager():MeasureStringX(popup.font, item.text)
            local scrollBarWid = popup:isVScrollBarVisible() and 13 or 0
            if 10 + textWid > popup.width - scrollBarWid then
                popup.tooWide = item
                popup.tooWideY = y
            end
        end
    end

    local textX = 10
    local iconTexture = combo.getDebugOptionTexture and combo:getDebugOptionTexture(item.index) or nil
    if iconTexture then
        local iconSize = math.max(12, math.min(item.height - 6, combo.debugOptionIconSize or 14))
        local iconY = y + math.floor((item.height - iconSize) / 2)
        popup:drawTextureScaledAspect(iconTexture, textX, iconY, iconSize, iconSize, 1, 1, 1, 1)
        textX = textX + iconSize + 6
    end

    local itemPadY = popup.itemPadY or (item.height - popup.fontHgt) / 2
    popup:drawText(item.text, textX, y + itemPadY, combo.textColor.r, combo.textColor.g, combo.textColor.b, combo.textColor.a, popup.font)
    return y + item.height
end

local function renderDebugIconCombo(combo)
    if not combo.disabled then
        combo.fade:setFadeIn(combo.joypadFocused or combo:isMouseOver())
        combo.fade:update()
    end

    combo:drawRect(0, 0, combo.width, combo.height, combo.backgroundColor.a, combo.backgroundColor.r, combo.backgroundColor.g, combo.backgroundColor.b)

    if combo.expanded then
    elseif not combo.joypadFocused then
        combo:drawRect(
            0,
            0,
            combo.width,
            combo.height,
            combo.backgroundColorMouseOver.a * 0.5 * combo.fade:fraction(),
            combo.backgroundColorMouseOver.r,
            combo.backgroundColorMouseOver.g,
            combo.backgroundColorMouseOver.b
        )
    else
        combo:drawRect(0, 0, combo.width, combo.height, combo.backgroundColorMouseOver.a, combo.backgroundColorMouseOver.r, combo.backgroundColorMouseOver.g, combo.backgroundColorMouseOver.b)
    end

    local alpha = math.min(combo.borderColor.a + 0.2 * combo.fade:fraction(), 1.0)
    if not combo.disabled then
        combo:drawRectBorder(0, 0, combo.width, combo.height, alpha, combo.borderColor.r, combo.borderColor.g, combo.borderColor.b)
    else
        combo:drawRectBorder(0, 0, combo.width, combo.height, alpha, 0.5, 0.5, 0.5)
    end

    local fontHgt = getTextManager():getFontHeight(combo.font)
    local textY = (combo.height - fontHgt) / 2
    local optionText = nil
    local iconTexture = nil
    if not (combo:isEditable() and combo.editor and combo.editor:isReallyVisible()) then
        if combo.options[combo.selected] then
            optionText = combo:getOptionText(combo.selected)
            iconTexture = combo.getDebugOptionTexture and combo:getDebugOptionTexture(combo.selected) or nil
        elseif combo.noSelectionText then
            optionText = combo.noSelectionText
        end
    end

    if optionText then
        local textX = 10
        if iconTexture then
            local iconSize = math.max(12, math.min(combo.height - 6, combo.debugOptionIconSize or 14))
            local iconY = math.floor((combo.height - iconSize) / 2)
            combo:drawTextureScaledAspect(iconTexture, textX, iconY, iconSize, iconSize, combo.disabled and 0.6 or 1, 1, 1, 1)
            textX = textX + iconSize + 6
        end

        local availableWidth = math.max(0, combo.width - combo.image:getWidthOrig() - 6 - textX)
        local stencilX, stencilY, stencilW, stencilH = combo:clampStencilRectToParent(textX, 0, availableWidth, combo.height)
        if not combo.disabled then
            combo:drawText(optionText, textX, textY, combo.textColor.r, combo.textColor.g, combo.textColor.b, combo.textColor.a, combo.font)
        else
            combo:drawText(optionText, textX, textY, 0.6, 0.6, 0.6, 1, combo.font)
        end
        combo:clearStencilRect()
        if combo.doRepaintStencil then
            combo:repaintStencilRect(stencilX, stencilY, stencilW, stencilH)
        end
    end

    if combo:isMouseOver() and not combo.expanded and combo:getOptionTooltip(combo.selected) then
        local tooltipText = combo:getOptionTooltip(combo.selected)
        if not combo.tooltipUI then
            combo.tooltipUI = ISToolTip:new()
            combo.tooltipUI:setOwner(combo)
            combo.tooltipUI:setVisible(false)
            combo.tooltipUI:setAlwaysOnTop(true)
        end
        if not combo.tooltipUI:getIsVisible() then
            if string.contains(tooltipText, "\n") then
                combo.tooltipUI.maxLineWidth = 1000
            else
                combo.tooltipUI.maxLineWidth = 300
            end
            combo.tooltipUI:addToUIManager()
            combo.tooltipUI:setVisible(true)
        end
        combo.tooltipUI.description = tooltipText
        combo.tooltipUI:setX(combo:getMouseX() + 23)
        combo.tooltipUI:setY(combo:getMouseY() + 23)
    else
        if combo.tooltipUI and combo.tooltipUI:getIsVisible() then
            combo.tooltipUI:setVisible(false)
            combo.tooltipUI:removeFromUIManager()
        end
    end

    if not combo.disabled then
        combo:drawTexture(combo.image, combo.width - combo.image:getWidthOrig() - 3, (combo.baseHeight / 2) - (combo.image:getHeight() / 2), 1, 1, 1, 1)
    else
        combo:drawTexture(combo.image, combo.width - combo.image:getWidthOrig() - 3, (combo.baseHeight / 2) - (combo.image:getHeight() / 2), 1, 0.5, 0.5, 0.5)
    end
end

local function installDebugIconCombo(combo, iconResolver)
    if not combo or type(iconResolver) ~= "function" then
        return
    end

    combo.debugOptionIconSize = 14
    combo.getDebugOptionTexture = function(selfRef, optionIndex)
        if not optionIndex or optionIndex < 1 then
            return nil
        end
        local optionText = selfRef.getOptionText and selfRef:getOptionText(optionIndex) or nil
        local optionData = selfRef.getOptionData and selfRef:getOptionData(optionIndex) or nil
        return iconResolver(selfRef, optionIndex, optionText, optionData)
    end

    local popup = ISComboBoxPopup:new(0, 0, 100, 50)
    popup:initialise()
    popup:instantiate()
    popup:setFont(combo.font, 4)
    popup:setAlwaysOnTop(true)
    popup.drawBorder = true
    popup:setCapture(true)
    popup.doDrawItem = drawDebugIconComboPopupItem
    combo.popup = popup
    combo.render = function(selfRef)
        renderDebugIconCombo(selfRef)
    end
end

local function createDebugButton(parent, x, y, w, h, title, owner, callback, internal, borderColor, backgroundColor, tooltip)
    title = debugTextFromEnglish(title)
    tooltip = debugTextFromEnglish(tooltip)
    local btn = ISButton:new(x, y, w, h, title, owner, callback)
    btn:initialise()
    btn:instantiate()
    btn.font = UIFont.Small
    btn.textColor = {r=1, g=1, b=1, a=1}
    btn.borderColor = borderColor or {r=0.4, g=0.5, b=0.6, a=1}
    btn.backgroundColor = backgroundColor or {r=0.2, g=0.25, b=0.3, a=1}
    if internal then
        btn.internal = internal
    end
    if tooltip and btn.setTooltip then
        btn:setTooltip(tooltip)
    end
    parent:addChild(btn)
    return btn
end

local function createDebugBulkTick(parent, x, y, w, h, label, owner, callback, tooltip)
    label = debugTextFromEnglish(label or "All")
    tooltip = debugTextFromEnglish(tooltip)
    local tick = ISTickBox:new(x, y, w, h, "", owner, callback)
    tick:initialise()
    tick:instantiate()
    tick.font = UIFont.Small
    tick:addOption(label)
    if tick.setSelected then
        tick:setSelected(1, false)
    else
        tick.selected[1] = false
    end
    tick.choicesColor = {r=0.82, g=0.86, b=0.92, a=1}
    tick.borderColor = {r=0.45, g=0.58, b=0.68, a=0.85}
    if tooltip then
        tick.tooltip = tooltip
    end
    parent:addChild(tick)
    return tick
end

local function setDebugBulkTickSelected(tick, selected)
    if not tick then
        return
    end
    if tick.setSelected then
        tick:setSelected(1, selected == true)
    else
        tick.selected = tick.selected or {}
        tick.selected[1] = selected == true
    end
end

local function isDebugVisibleBulkRow(row)
    return row ~= nil and row.hidden ~= true and row.hiddenBySandbox ~= true
end

local function refreshDebugBulkTickState(tick, list, canToggleRow, isRowSelected)
    if not tick then
        return
    end

    local anyVisible = false
    local allVisibleSelected = true
    if list and type(list.items) == "table" then
        for _, itemData in ipairs(list.items) do
            local row = itemData and itemData.item or nil
            if isDebugVisibleBulkRow(row) and (canToggleRow == nil or canToggleRow(row) ~= false) then
                anyVisible = true
                if not (isRowSelected and isRowSelected(row) == true) then
                    allVisibleSelected = false
                end
            end
        end
    end

    tick.enable = anyVisible
    setDebugBulkTickSelected(tick, anyVisible and allVisibleSelected)
end

local function attachDebugButtonIconCompat(button, texture)
    if not (button and texture and button.drawTextureScaledAspect) then
        return button
    end

    button.debugIconTexture = texture
    button.render = function(selfRef)
        local iconTexture = selfRef.debugIconTexture
        if not iconTexture then
            ISButton.render(selfRef)
            return
        end

        local savedTitle = selfRef.title
        selfRef.title = ""
        ISButton.render(selfRef)
        selfRef.title = savedTitle

        local iconSize = math.max(12, math.min((selfRef.height or 22) - 6, 16))
        local iconX = 6
        local iconY = math.floor(((selfRef.height or 22) - iconSize) / 2)
        local alpha = (selfRef.enable == false) and 0.6 or 1
        selfRef:drawTextureScaledAspect(iconTexture, iconX, iconY, iconSize, iconSize, alpha, 1, 1, 1)

        local titleText = tostring(savedTitle or "")
        if titleText ~= "" then
            local font = selfRef.font or UIFont.Small
            local textColor = selfRef.textColor or { r = 1, g = 1, b = 1, a = 1 }
            local textAlpha = (selfRef.enable == false) and 0.6 or (textColor.a or 1)
            local fontHgt = getTextManager and getTextManager():getFontHeight(font) or 14
            local textY = math.floor(((selfRef.height or 22) - fontHgt) / 2)
            local textLeft = iconX + iconSize + 6
            local textWidth = math.max(0, (selfRef.width or 0) - textLeft - 4)
            selfRef:drawTextCentre(titleText, textLeft + (textWidth / 2), textY, textColor.r or 1, textColor.g or 1, textColor.b or 1, textAlpha, font)
        end
    end

    return button
end

local function createDebugSectionPanel(parent, x, y, w, h)
    local panel = ISPanel:new(x, y, w, h)
    panel:initialise()
    panel:instantiate()
    panel.backgroundColor = {r=0.09, g=0.09, b=0.11, a=0}
    panel.borderColor = {r=0.2, g=0.24, b=0.3, a=0}
    parent:addChild(panel)
    return panel
end

BurdJournals.UI = BurdJournals.UI or {}
BurdJournals.UI.DebugPanel = BurdJournals.UI.DebugPanel or {}
BurdJournals.UI.DebugPanel.createDebugButton = createDebugButton
BurdJournals.UI.DebugPanel.createDebugSectionPanel = createDebugSectionPanel

function BurdJournals.UI.DebugPanel.shouldAllowTraitReconciliation(panel)
    local charPanel = panel and panel.charPanel or nil
    local tickBox = charPanel and charPanel.traitReconcileTick or nil
    return tickBox and tickBox.selected and tickBox.selected[1] == true or false
end

function BurdJournals.UI.DebugPanel.buildDebugTraitAddOptions(panel, baseOpts)
    local opts = {}
    if type(baseOpts) == "table" then
        for key, value in pairs(baseOpts) do
            opts[key] = value
        end
    end

    if not BurdJournals.UI.DebugPanel.shouldAllowTraitReconciliation(panel) then
        opts.skipTraitReconciliation = true
    end

    return opts
end

local function measureDebugTextWidth(font, text, fallback)
    if getTextManager and getTextManager().MeasureStringX then
        return getTextManager():MeasureStringX(font or UIFont.Small, tostring(text or ""))
    end
    return tonumber(fallback) or (#tostring(text or "") * 6)
end

local function normalizeDebugSourceId(sourceId)
    if BurdJournals and BurdJournals.normalizeFilterSourceId then
        return BurdJournals.normalizeFilterSourceId(sourceId)
    end
    local normalized = string.lower(tostring(sourceId or "modded"))
    normalized = normalized:gsub("[^%w]+", "")
    if normalized == "" then
        normalized = "modded"
    end
    return normalized
end

local function getDebugRowSourceMeta(row)
    local source = type(row) == "table" and row.source or nil
    local sourceId = type(row) == "table" and row.sourceId or nil

    if type(row) == "table" then
        if source == nil then
            if row.isVanilla ~= nil then
                source = row.isVanilla and "Vanilla" or "Modded"
            elseif row.isModded ~= nil then
                source = row.isModded and "Modded" or "Vanilla"
            end
        end
        if sourceId == nil then
            if row.isVanilla ~= nil then
                sourceId = row.isVanilla and "vanilla" or "modded"
            elseif row.isModded ~= nil then
                sourceId = row.isModded and "modded" or "vanilla"
            elseif source then
                sourceId = source
            end
        end
    end

    local normalizedId = normalizeDebugSourceId(sourceId or source or "modded")
    local label = tostring(source or "Modded")
    if normalizedId == "vanilla" then
        label = "Vanilla"
    elseif normalizedId == "modded" and (label == "" or label == "Unknown" or label == "Runtime") then
        label = "Modded"
    end
    return label, normalizedId
end

local function debugRowMatchesSourceFilter(row, selectedSourceId)
    local normalizedFilter = normalizeDebugSourceId(selectedSourceId or "all")
    if normalizedFilter == "all" then
        return true
    end
    local _, rowSourceId = getDebugRowSourceMeta(row)
    if normalizedFilter == "modded" then
        return rowSourceId ~= "vanilla"
    end
    return rowSourceId == normalizedFilter
end

local function getDebugTraitPolarityId(row)
    if type(row) ~= "table" then
        return "neutral"
    end
    if row.isPositive == true then
        return "positive"
    end
    if row.isPositive == false then
        return "negative"
    end
    local traitId = row.id or row.name or row.traitId
    if traitId and BurdJournals and BurdJournals.UI and BurdJournals.UI.DebugPanel then
        local bucket = BurdJournals.UI.DebugPanel.getBulkTraitBucket
            and BurdJournals.UI.DebugPanel.getBulkTraitBucket(traitId)
            or nil
        if bucket == "positive" or bucket == "negative" or bucket == "neutral" then
            return bucket
        end
    end
    return "neutral"
end

local function debugRowMatchesTraitPolarityFilter(row, selectedPolarity)
    local filter = tostring(selectedPolarity or "all")
    if filter == "all" then
        return true
    end
    return getDebugTraitPolarityId(row) == filter
end

local function onDebugTraitPolarityFilterChanged(owner, combo)
    if owner and combo and combo.filterCallback then
        combo.filterCallback(owner)
    end
end

local function createDebugTraitPolarityFilter(parent, x, y, ownerRef, onChanged, tooltip)
    local combo = ISComboBox:new(x, y, 86, 20, ownerRef, onDebugTraitPolarityFilterChanged)
    combo:initialise()
    combo:instantiate()
    combo:addOptionWithData(debugText("UI_BurdJournals_DebugPolarityAll", "All +/-"), "all")
    combo:addOptionWithData(debugText("UI_BurdJournals_DebugPolarityPositive", "+ Only"), "positive")
    combo:addOptionWithData(debugText("UI_BurdJournals_DebugPolarityNegative", "- Only"), "negative")
    combo:addOptionWithData(debugText("UI_BurdJournals_DebugPolarityOther", "? Other"), "neutral")
    combo.selected = 1
    combo.filterCallback = onChanged
    if tooltip and combo.setTooltip then
        combo:setTooltip(tooltip)
    end
    parent:addChild(combo)
    return combo
end

local function getDebugTraitPolarityFilterValue(combo)
    if not combo then
        return "all"
    end
    if combo.getOptionData then
        return combo:getOptionData(combo.selected or 1) or "all"
    end
    return "all"
end

local function getDebugListRowHeight(list, item, fallbackHeight)
    local rowHeight = tonumber(item and item.height)
    if rowHeight ~= nil and rowHeight >= 0 then
        return rowHeight
    end
    return tonumber(list and list.itemheight) or tonumber(fallbackHeight) or 24
end

local function getDebugListRowAt(list, x, y)
    if not (list and type(list.items) == "table") then
        return -1
    end

    local clickY = tonumber(y)
    if clickY == nil then
        return -1
    end

    if list.rowAt then
        local resolved = tonumber(list:rowAt(tonumber(x) or 0, clickY)) or -1
        if resolved > 0 then
            return resolved
        end
    end

    local rowTop = 0
    for index, itemData in ipairs(list.items) do
        local rowHeight = tonumber(itemData and itemData.height) or getDebugListRowHeight(list, itemData, list.itemheight)
        if rowHeight > 0 then
            if clickY >= rowTop and clickY < (rowTop + rowHeight) then
                return index
            end
            rowTop = rowTop + rowHeight
        end
    end

    return -1
end

local function applyDebugRowFilter(list, matcher, signature)
    if not (list and type(list.items) == "table") then
        return
    end

    if signature and list._debugFilterSignature == signature and list._debugFilterItemCount == #list.items then
        return
    end

    local defaultHeight = tonumber(list.itemheight) or 0
    local firstVisible = nil
    for index, itemData in ipairs(list.items) do
        local row = itemData and itemData.item or nil
        local visible = true
        if row then
            visible = matcher == nil or matcher(row, itemData, index) ~= false
            row.hidden = not visible
        end
        if itemData then
            itemData.height = visible and defaultHeight or 0
        end
        if visible and not firstVisible then
            firstVisible = index
        end
    end

    local selected = tonumber(list.selected) or -1
    if selected > 0 and list.items[selected] and (tonumber(list.items[selected].height) or 0) <= 0 then
        list.selected = firstVisible or -1
    end

    if list.updateScrollBars then
        list:updateScrollBars()
    elseif list.updateScrollbars then
        list:updateScrollbars()
    end
    list._debugFilterSignature = signature
    list._debugFilterItemCount = #list.items
end

local function collectDebugSourceFilterOptions(items)
    local options = {
        { label = debugText("UI_BurdJournals_DebugFilterAll", "All"), sourceId = "all" }
    }
    local vanillaCount = 0
    local moddedCount = 0
    local explicitSources = {}

    for _, entry in ipairs(items or {}) do
        local row = entry and entry.item or entry
        if row and not row.isEmpty then
            local label, sourceId = getDebugRowSourceMeta(row)
            if sourceId == "vanilla" then
                vanillaCount = vanillaCount + 1
            else
                moddedCount = moddedCount + 1
                if sourceId ~= "modded" then
                    local bucket = explicitSources[sourceId]
                    if not bucket then
                        bucket = { label = label, sourceId = sourceId, count = 0 }
                        explicitSources[sourceId] = bucket
                    end
                    bucket.count = bucket.count + 1
                end
            end
        end
    end

    if vanillaCount > 0 then
        options[#options + 1] = { label = debugText("UI_BurdJournals_DebugFilterVanilla", "Vanilla"), sourceId = "vanilla", count = vanillaCount }
    end
    if moddedCount > 0 then
        options[#options + 1] = { label = debugText("UI_BurdJournals_DebugFilterModded", "Modded"), sourceId = "modded", count = moddedCount }
    end

    local explicitList = {}
    for _, bucket in pairs(explicitSources) do
        explicitList[#explicitList + 1] = bucket
    end
    table.sort(explicitList, function(a, b)
        return string.lower(tostring(a.label or "")) < string.lower(tostring(b.label or ""))
    end)
    for _, bucket in ipairs(explicitList) do
        options[#options + 1] = bucket
    end

    return options
end

local function updateDebugSourceFilterButtonStyles(filterState)
    for _, button in ipairs(filterState.buttons or {}) do
        local selected = normalizeDebugSourceId(button.sourceId or "all") == normalizeDebugSourceId(filterState.selectedSourceId or "all")
        button.backgroundColor = selected and {r=0.28, g=0.38, b=0.46, a=1} or {r=0.14, g=0.16, b=0.19, a=1}
        button.borderColor = selected and {r=0.5, g=0.7, b=0.9, a=1} or {r=0.32, g=0.4, b=0.48, a=1}
        button.textColor = selected and {r=1, g=1, b=1, a=1} or {r=0.82, g=0.86, b=0.92, a=1}
    end
end

local function layoutDebugSourceFilterStrip(filterState)
    if not (filterState and filterState.viewport) then
        return
    end
    local viewportWidth = tonumber(filterState.viewport.width) or 0
    local maxOffset = math.max(0, (tonumber(filterState.contentWidth) or 0) - viewportWidth)
    filterState.scrollOffset = math.max(0, math.min(tonumber(filterState.scrollOffset) or 0, maxOffset))

    local x = 0
    for _, button in ipairs(filterState.buttons or {}) do
        local btnWidth = tonumber(button.width) or 44
        if button.setX then button:setX(x - filterState.scrollOffset) end
        if button.setY then button:setY(1) end
        if button.setVisible then
            local visible = (x + btnWidth - filterState.scrollOffset) > 0 and (x - filterState.scrollOffset) < viewportWidth
            button:setVisible(visible)
        end
        x = x + btnWidth + 4
    end
    filterState.contentWidth = math.max(0, x - 4)

    local leftEnabled = filterState.scrollOffset > 0
    local rightEnabled = filterState.scrollOffset < math.max(0, filterState.contentWidth - viewportWidth)
    if filterState.leftButton then
        filterState.leftButton.enable = leftEnabled
        filterState.leftButton.textColor = leftEnabled and {r=1, g=1, b=1, a=1} or {r=0.55, g=0.55, b=0.55, a=1}
    end
    if filterState.rightButton then
        filterState.rightButton.enable = rightEnabled
        filterState.rightButton.textColor = rightEnabled and {r=1, g=1, b=1, a=1} or {r=0.55, g=0.55, b=0.55, a=1}
    end
    updateDebugSourceFilterButtonStyles(filterState)
end

local function onDebugSourceFilterChip(owner, button)
    local filterState = button and button.filterState or nil
    if not filterState then
        return
    end
    filterState.selectedSourceId = button.sourceId or "all"
    layoutDebugSourceFilterStrip(filterState)
    if filterState.onChanged then
        filterState.onChanged(filterState.ownerRef)
    end
end

local function onDebugSourceFilterScroll(owner, button)
    local filterState = button and button.filterState or nil
    if not filterState then
        return
    end
    local delta = tonumber(button and button.scrollDelta) or 0
    filterState.scrollOffset = math.max(0, (tonumber(filterState.scrollOffset) or 0) + delta)
    layoutDebugSourceFilterStrip(filterState)
end

local function createDebugSourceFilterStrip(parent, x, y, width, ownerRef, onChanged, tooltip)
    local stripWidth = math.max(76, tonumber(width) or 0)
    local container = ISPanel:new(x, y, stripWidth, 20)
    container:initialise()
    container:instantiate()
    container.backgroundColor = {r=0, g=0, b=0, a=0}
    container.borderColor = {r=0, g=0, b=0, a=0}
    parent:addChild(container)

    local viewport = ISPanel:new(22, 0, math.max(12, stripWidth - 44), 20)
    viewport:initialise()
    viewport:instantiate()
    viewport.backgroundColor = {r=0, g=0, b=0, a=0}
    viewport.borderColor = {r=0, g=0, b=0, a=0}
    container:addChild(viewport)

    local filterState = {
        container = container,
        viewport = viewport,
        ownerRef = ownerRef,
        onChanged = onChanged,
        tooltip = tooltip or debugText("UI_BurdJournals_DebugFilterSourceRows", "Filter rows by content source."),
        selectedSourceId = "all",
        scrollOffset = 0,
        buttons = {},
        contentWidth = 0,
    }

    local leftButton = createDebugButton(container, 0, 0, 20, 20, "<", ownerRef, onDebugSourceFilterScroll, nil, {r=0.3, g=0.38, b=0.46, a=1}, {r=0.14, g=0.16, b=0.19, a=1}, tooltip or debugText("UI_BurdJournals_DebugFilterSourceScroll", "Scroll source filters."))
    leftButton.filterState = filterState
    leftButton.scrollDelta = -84
    filterState.leftButton = leftButton

    local rightButton = createDebugButton(container, stripWidth - 20, 0, 20, 20, ">", ownerRef, onDebugSourceFilterScroll, nil, {r=0.3, g=0.38, b=0.46, a=1}, {r=0.14, g=0.16, b=0.19, a=1}, tooltip or debugText("UI_BurdJournals_DebugFilterSourceScroll", "Scroll source filters."))
    rightButton.filterState = filterState
    rightButton.scrollDelta = 84
    filterState.rightButton = rightButton

    return filterState
end

local function refreshDebugSourceFilterStrip(filterState, items)
    if not (filterState and filterState.viewport) then
        return
    end

    for _, button in ipairs(filterState.buttons or {}) do
        if button.setVisible then
            button:setVisible(false)
        end
        if filterState.viewport.removeChild then
            filterState.viewport:removeChild(button)
        end
    end
    filterState.buttons = {}

    local options = collectDebugSourceFilterOptions(items)
    filterState.options = options

    local signatureParts = {}
    for _, option in ipairs(options) do
        signatureParts[#signatureParts + 1] = tostring(option.sourceId or "all") .. "\31" .. tostring(option.label or "")
    end
    local signature = table.concat(signatureParts, "\30")
    if filterState.signature == signature then
        updateDebugSourceFilterButtonStyles(filterState)
        return
    end
    filterState.signature = signature

    local selectedStillExists = false
    for _, option in ipairs(options) do
        if normalizeDebugSourceId(option.sourceId or "all") == normalizeDebugSourceId(filterState.selectedSourceId or "all") then
            selectedStillExists = true
            break
        end
    end
    if not selectedStillExists then
        filterState.selectedSourceId = "all"
    end

    local x = 0
    for _, option in ipairs(options) do
        local label = tostring(option.label or debugText("UI_BurdJournals_DebugFilterAll", "All"))
        local btnWidth = math.max(42, math.min(140, measureDebugTextWidth(UIFont.Small, label, 48) + 16))
        local button = createDebugButton(filterState.viewport, x, 1, btnWidth, 18, label, filterState.ownerRef, onDebugSourceFilterChip, nil, {r=0.32, g=0.4, b=0.48, a=1}, {r=0.14, g=0.16, b=0.19, a=1}, filterState.tooltip)
        button.filterState = filterState
        button.sourceId = option.sourceId or "all"
        filterState.buttons[#filterState.buttons + 1] = button
        x = x + btnWidth + 4
    end
    filterState.contentWidth = math.max(0, x - 4)
    layoutDebugSourceFilterStrip(filterState)
end

local function createSectionSourceFilterStrip(parent, ownerRef, labelText, searchX, y, sectionPadding, onChanged, tooltip, labelX)
    local filterX = (tonumber(labelX) or sectionPadding) + measureDebugTextWidth(UIFont.Small, labelText, 150) + 14
    local filterWidth = math.max(0, tonumber(searchX or 0) - filterX - 8)
    if filterWidth < 76 then
        return nil
    end
    return createDebugSourceFilterStrip(parent, filterX, y, filterWidth, ownerRef, onChanged, tooltip)
end

local function setDebugSubTabState(tabState, activeId)
    if type(tabState) ~= "table" then
        return
    end
    tabState.current = activeId
    for id, panel in pairs(tabState.panels or {}) do
        if panel and panel.setVisible then
            panel:setVisible(id == activeId)
        end
    end
    for id, btn in pairs(tabState.buttons or {}) do
        if btn then
            if id == activeId then
                btn.backgroundColor = {r=0.28, g=0.38, b=0.46, a=1}
                btn.borderColor = {r=0.5, g=0.7, b=0.9, a=1}
            else
                btn.backgroundColor = {r=0.15, g=0.17, b=0.2, a=1}
                btn.borderColor = {r=0.36, g=0.44, b=0.54, a=1}
            end
        end
    end
end

local function trimDebugText(value, maxChars)
    local text = tostring(value or "")
    local limit = math.max(4, tonumber(maxChars) or 18)
    if #text <= limit then
        return text
    end
    return string.sub(text, 1, limit - 3) .. "..."
end

local function getDebugRecipeSourceText(row, maxChars)
    local limit = tonumber(maxChars) or 22
    if type(row) ~= "table" then
        return "Runtime"
    end
    if row.magazineDisplayName and tostring(row.magazineDisplayName) ~= "" then
        return BurdJournals.formatText("From: %s", trimDebugText(row.magazineDisplayName, limit))
    end
    local source = tostring(row.source or "Runtime")
    if source == "" or source == "Unknown" then
        source = "Runtime"
    end
    return trimDebugText(source, limit)
end

local function sortDebugRecipeRows(rows)
    table.sort(rows, function(a, b)
        local left = string.lower(tostring((a and a.displayName) or (a and a.name) or ""))
        local right = string.lower(tostring((b and b.displayName) or (b and b.name) or ""))
        if left == right then
            return string.lower(tostring((a and a.name) or "")) < string.lower(tostring((b and b.name) or ""))
        end
        return left < right
    end)
end

local function getDebugRecipeCatalog(recipeCache)
    if debugRecipeCatalogCache then
        return debugRecipeCatalogCache
    end

    local catalog = {}
    for recipeName, _ in pairs(recipeCache or {}) do
        if recipeName and tostring(recipeName) ~= "" then
            local resolvedName = BurdJournals.getRecipeCanonicalName and BurdJournals.getRecipeCanonicalName(recipeName) or recipeName
            catalog[tostring(resolvedName or recipeName)] = true
        end
    end

    local recipes = getAllRecipes and getAllRecipes() or nil
    if recipes and recipes.size and recipes.get then
        for i = 0, recipes:size() - 1 do
            local recipe = recipes:get(i)
            local recipeName = recipe and BurdJournals.getRecipeCanonicalName and BurdJournals.getRecipeCanonicalName(recipe) or nil
            recipeName = recipeName or (recipe and recipe.getName and recipe:getName() or nil)
            if recipeName and tostring(recipeName) ~= "" then
                catalog[tostring(recipeName)] = true
            end
        end
    end
    debugRecipeCatalogCache = catalog
    return catalog
end

local function appendDebugDiscoveredRecipeNames(recipeNames, recipeCache)
    if type(recipeNames) ~= "table" then
        return
    end

    for recipeName, _ in pairs(getDebugRecipeCatalog(recipeCache)) do
        recipeNames[recipeName] = true
    end
end

local function addDebugRecipeName(recipeNames, recipeName)
    if type(recipeNames) ~= "table" or recipeName == nil then
        return
    end
    local canonicalName = BurdJournals.getRecipeCanonicalName and BurdJournals.getRecipeCanonicalName(recipeName) or nil
    local resolvedName = canonicalName or (BurdJournals.validateRecipeName and BurdJournals.validateRecipeName(recipeName)) or recipeName
    if resolvedName and tostring(resolvedName) ~= "" then
        recipeNames[tostring(resolvedName)] = true
    end
end

local function buildDebugRecipeMembershipIndex(recipeTable)
    local index = {}
    if type(recipeTable) ~= "table" then return index end
    local enabledCount = 0
    for recipeName, enabled in pairs(recipeTable) do
        if enabled == true and type(recipeName) == "string" and recipeName ~= "" then
            enabledCount = enabledCount + 1
        end
    end
    local cached = debugRecipeMembershipIndexCache[recipeTable]
    if cached and cached.enabledCount == enabledCount and cached.index then
        return cached.index
    end
    for recipeName, enabled in pairs(recipeTable) do
        if enabled == true and type(recipeName) == "string" and recipeName ~= "" then
            index[recipeName] = true
            index[string.lower(recipeName)] = true
            if BurdJournals.getRecipeNameAliases then
                for _, alias in ipairs(BurdJournals.getRecipeNameAliases(recipeName) or {}) do
                    if type(alias) == "string" and alias ~= "" then
                        index[alias] = true
                        index[string.lower(alias)] = true
                    end
                end
            end
        end
    end
    debugRecipeMembershipIndexCache[recipeTable] = {
        enabledCount = enabledCount,
        index = index,
    }
    return index
end

local function buildDebugRecipeRows(player, includeTransferableCatalog, includeBaselineEntries)
    local rows = {}
    local recipeNames = {}
    local knownRecipes = BurdJournals.getAuthoritativeKnownRecipeSet and BurdJournals.getAuthoritativeKnownRecipeSet(player) or {}
    local baselineRecipes = includeBaselineEntries and BurdJournals.getRecipeBaseline and BurdJournals.getRecipeBaseline(player) or {}
    local recipeCache = BurdJournals.buildMagazineRecipeCache and BurdJournals.buildMagazineRecipeCache() or {}
    local knownRecipeIndex = buildDebugRecipeMembershipIndex(knownRecipes)
    local baselineRecipeIndex = buildDebugRecipeMembershipIndex(baselineRecipes)

    for recipeName, isKnown in pairs(knownRecipes or {}) do
        if isKnown == true then
            addDebugRecipeName(recipeNames, recipeName)
        end
    end
    if includeBaselineEntries then
        for recipeName, isBaseline in pairs(baselineRecipes or {}) do
            if isBaseline == true then
                addDebugRecipeName(recipeNames, recipeName)
            end
        end
    end
    if includeTransferableCatalog then
        appendDebugDiscoveredRecipeNames(recipeNames, recipeCache)
    end

    for recipeName, _ in pairs(recipeNames) do
        local magazineSource = recipeCache[recipeName]
            or (BurdJournals.getMagazineForRecipe and BurdJournals.getMagazineForRecipe(recipeName))
            or nil
        local recipeLower = string.lower(tostring(recipeName))
        rows[#rows + 1] = {
            name = recipeName,
            displayName = BurdJournals.getRecipeDisplayName and BurdJournals.getRecipeDisplayName(recipeName) or tostring(recipeName),
            source = BurdJournals.getRecipeModSource and BurdJournals.getRecipeModSource(recipeName, magazineSource) or "Unknown",
            sourceId = BurdJournals.getRecipeModId and BurdJournals.getRecipeModId(recipeName, magazineSource) or nil,
            magazineSource = magazineSource,
            magazineDisplayName = magazineSource and BurdJournals.getMagazineDisplayName and BurdJournals.getMagazineDisplayName(magazineSource) or nil,
            isKnown = knownRecipeIndex[recipeName] == true or knownRecipeIndex[recipeLower] == true,
            isBaseline = baselineRecipeIndex[recipeName] == true or baselineRecipeIndex[recipeLower] == true,
            hasMagazine = magazineSource ~= nil and tostring(magazineSource) ~= "",
        }
    end

    sortDebugRecipeRows(rows)
    return rows
end

local function buildDebugSpawnSkillRows()
    local rows = {}
    local seen = {}
    local skillMetadata = BurdJournals and BurdJournals.discoverSkillMetadata and BurdJournals.discoverSkillMetadata() or nil

    if type(skillMetadata) == "table" then
        for perkId, skillData in pairs(skillMetadata) do
            local skillName = tostring((skillData and skillData.id) or perkId or "")
            if skillName ~= "" then
                local lower = string.lower(skillName)
                if not seen[lower] then
                    seen[lower] = true
                    local isPassive = (skillData and skillData.isPassive) == true
                        or (BurdJournals and BurdJournals.isPassiveSkill and BurdJournals.isPassiveSkill(skillName))
                        or skillName == "Fitness"
                        or skillName == "Strength"
                    local isVanilla = true
                    if skillData and skillData.isVanilla ~= nil then
                        isVanilla = skillData.isVanilla == true
                    end
                    rows[#rows + 1] = {
                        name = skillName,
                        displayName = (skillData and skillData.displayName) or BurdJournals.UI.DebugPanel.getSkillDisplayName(skillName),
                        category = (skillData and skillData.category) or (isPassive and "Passive" or "Other"),
                        isPassive = isPassive,
                        isVanilla = isVanilla,
                        source = BurdJournals.getSkillModSource and BurdJournals.getSkillModSource(skillName) or (isVanilla and "Vanilla" or "Modded"),
                        sourceId = BurdJournals.getSkillModId and BurdJournals.getSkillModId(skillName) or (isVanilla and "vanilla" or "modded"),
                    }
                end
            end
        end
    end

    if #rows == 0 then
        for _, skillName in ipairs(BurdJournals.UI.DebugPanel.getAvailableSkills() or {}) do
            local lower = string.lower(tostring(skillName))
            if not seen[lower] then
                seen[lower] = true
                local isPassive = (BurdJournals and BurdJournals.isPassiveSkill and BurdJournals.isPassiveSkill(skillName))
                    or skillName == "Fitness"
                    or skillName == "Strength"
                rows[#rows + 1] = {
                    name = skillName,
                    displayName = BurdJournals.UI.DebugPanel.getSkillDisplayName(skillName),
                    category = isPassive and "Passive" or "Other",
                    isPassive = isPassive,
                    isVanilla = true,
                    source = BurdJournals.getSkillModSource and BurdJournals.getSkillModSource(skillName) or "Vanilla",
                    sourceId = BurdJournals.getSkillModId and BurdJournals.getSkillModId(skillName) or "vanilla",
                }
            end
        end
    end

    table.sort(rows, function(a, b)
        local leftCategory = string.lower(tostring((a and a.category) or "zzz"))
        local rightCategory = string.lower(tostring((b and b.category) or "zzz"))
        if leftCategory ~= rightCategory then
            return leftCategory < rightCategory
        end
        local left = string.lower(tostring((a and a.displayName) or (a and a.name) or ""))
        local right = string.lower(tostring((b and b.displayName) or (b and b.name) or ""))
        if left == right then
            return string.lower(tostring((a and a.name) or "")) < string.lower(tostring((b and b.name) or ""))
        end
        return left < right
    end)

    return rows
end

local function buildDebugSpawnTraitRows()
    local rows = {}
    local seenDisplayNames = {}
    local traitMetadata = BurdJournals and BurdJournals.discoverTraitMetadata and BurdJournals.discoverTraitMetadata() or nil
    local discoveredTraits = BurdJournals.UI.DebugPanel.getAvailableTraits() or {}
    local grantableSet = {}
    local traitCostLookup = BurdJournals.UI.DebugPanel.buildTraitCostLookup()

    for _, traitId in ipairs(discoveredTraits) do
        local normalized = string.lower(tostring(traitId or ""))
        if normalized ~= "" then
            grantableSet[normalized] = true
        end
    end

    if type(traitMetadata) == "table" then
        for traitId, traitData in pairs(traitMetadata) do
            local traitName = tostring(traitId or "")
            local lower = string.lower(traitName)
            if traitName ~= "" and grantableSet[lower] then
                local displayName = (traitData and traitData.displayName) or BurdJournals.UI.DebugPanel.getTraitDisplayName(traitName)
                local displayLower = string.lower(displayName)
                if not seenDisplayNames[displayLower] then
                    seenDisplayNames[displayLower] = true
                    local source = (traitData and traitData.source) or (BurdJournals.getTraitModSource and BurdJournals.getTraitModSource(traitName) or "Vanilla")
                    local sourceId = (traitData and traitData.sourceId) or (BurdJournals.getTraitModId and BurdJournals.getTraitModId(traitName) or source)
                    rows[#rows + 1] = {
                        id = traitName,
                        displayName = displayName,
                        isPositive = BurdJournals.UI.DebugPanel.resolveTraitIsPositive(traitName, traitData, traitCostLookup),
                        isPassiveSkillTrait = BurdJournals.isPassiveSkillTrait and BurdJournals.isPassiveSkillTrait(traitName) or false,
                        source = source,
                        sourceId = sourceId,
                        traitTexture = getDebugTraitTexture(traitName),
                    }
                end
            end
        end
    end

    if #rows == 0 then
        for _, traitId in ipairs(discoveredTraits) do
            local traitName = tostring(traitId or "")
            if traitName ~= "" then
                local displayName = BurdJournals.UI.DebugPanel.getTraitDisplayName(traitName)
                local displayLower = string.lower(displayName)
                if not seenDisplayNames[displayLower] then
                    seenDisplayNames[displayLower] = true
                    local source = BurdJournals.getTraitModSource and BurdJournals.getTraitModSource(traitName) or "Vanilla"
                    rows[#rows + 1] = {
                        id = traitName,
                        displayName = displayName,
                        isPositive = BurdJournals.UI.DebugPanel.resolveTraitIsPositive(traitName, nil, traitCostLookup),
                        isPassiveSkillTrait = BurdJournals.isPassiveSkillTrait and BurdJournals.isPassiveSkillTrait(traitName) or false,
                        source = source,
                        sourceId = BurdJournals.getTraitModId and BurdJournals.getTraitModId(traitName) or source,
                        traitTexture = getDebugTraitTexture(traitName),
                    }
                end
            end
        end
    end

    table.sort(rows, function(a, b)
        local left = string.lower(tostring((a and a.displayName) or (a and a.id) or ""))
        local right = string.lower(tostring((b and b.displayName) or (b and b.id) or ""))
        if left == right then
            return string.lower(tostring((a and a.id) or "")) < string.lower(tostring((b and b.id) or ""))
        end
        return left < right
    end)

    return rows
end

-- Clear trait discovery caches to force fresh lookup
function BurdJournals.UI.DebugPanel.clearTraitCaches()
    if BurdJournals then
        BurdJournals._cachedAllTraits = nil
        BurdJournals._cachedGrantableTraits = nil
        BurdJournals._cachedPositiveTraits = nil
        BurdJournals._cachedNegativeTraits = nil
        BurdJournals.debugPrint("[BSJ DebugPanel] Cleared trait caches for fresh discovery")
    end
end

-- ============================================================================
-- Tab 1: Spawn Panel
-- ============================================================================

-- Dynamically discover skills from the game (includes modded skills)
function BurdJournals.UI.DebugPanel.getAvailableSkills()
    local skills = nil
    
    -- Use the mod's discovery function if available
    if BurdJournals and BurdJournals.discoverAllSkills then
        local result = BurdJournals.discoverAllSkills()
        if result and type(result) == "table" and #result > 0 then
            skills = result
        end
    end
    
    -- Fallback: try PerkFactory directly
    if not skills or #skills == 0 then
        skills = {}
        if PerkFactory and PerkFactory.PerkList then
            local perkList = PerkFactory.PerkList
            if perkList and perkList.size then
                for i = 0, perkList:size() - 1 do
                    local perk = perkList:get(i)
                    if perk then
                        -- Only include trainable skills (not categories)
                        local parent = perk.getParent and perk:getParent() or nil
                        if parent then
                            local parentId = parent.getId and parent:getId() or nil
                            if parentId ~= "None" then
                                local perkName = (perk.getId and perk:getId()) or tostring(perk)
                                if perkName then
                                    table.insert(skills, perkName)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Final fallback: hardcoded list
    if not skills or #skills == 0 then
        skills = {
            "Fitness", "Strength", "Cooking", "Farming", "FirstAid", "Fishing", 
            "PlantScavenging", "Woodwork", "Mechanics", "Electricity", "Metalworking", 
            "Tailoring", "Aiming", "Reloading", "Axe", "Blunt", "SmallBlunt", 
            "LongBlade", "ShortBlade", "Spear", "Maintenance", "Sprinting", 
            "Lightfooted", "Nimble", "Sneaking", "Trapping"
        }
    end
    
    return skills
end

-- Dynamically discover traits from the game (includes modded traits)
function BurdJournals.UI.DebugPanel.getAvailableTraits()
    local traits = {}
    local addedTraitsLower = {}  -- For case-insensitive deduplication
    
    -- Helper to add trait with deduplication
    local function addTrait(traitId)
        if traitId and type(traitId) == "string" then
            local lower = string.lower(traitId)
            if not addedTraitsLower[lower] then
                addedTraitsLower[lower] = true
                table.insert(traits, traitId)
            end
        end
    end
    
    -- Use the mod's discovery function if available (include negative traits for debug)
    if BurdJournals and BurdJournals.discoverGrantableTraits then
        local result = BurdJournals.discoverGrantableTraits(true)  -- true = include negative
        if result and type(result) == "table" then
            for _, traitId in ipairs(result) do
                addTrait(traitId)
            end
        end
    end
    
    -- Fallback: try TraitFactory directly (with deduplication)
    if #traits == 0 then
        if TraitFactory and TraitFactory.getTraits then
            local traitList = TraitFactory.getTraits()
            if traitList and traitList.size then
                for i = 0, traitList:size() - 1 do
                    local trait = traitList:get(i)
                    if trait then
                        local traitType = trait.getType and trait:getType() or nil
                        if traitType then
                            addTrait(traitType)
                        end
                    end
                end
            end
        end
    end
    
    -- Final fallback: hardcoded list
    if #traits == 0 then
        local fallback = {
            "Athletic", "Strong", "Brave", "Lucky", "FastLearner", "Dextrous", 
            "Graceful", "LightEater", "Organized", "Outdoorsman", "ThickSkinned", 
            "Inconspicuous", "Conspicuous", "Clumsy", "SlowLearner", "Cowardly", 
            "Weak", "Obese", "Overweight", "Underweight", "Pacifist"
        }
        for _, t in ipairs(fallback) do
            addTrait(t)
        end
    end
    
    return traits
end

-- Get display name for a skill
function BurdJournals.UI.DebugPanel.getSkillDisplayName(skillName)
    if BurdJournals.getPerkDisplayName then
        local display = BurdJournals.getPerkDisplayName(skillName)
        if display then return display end
    end
    -- Fallback: convert camelCase to Title Case
    return skillName:gsub("(%l)(%u)", "%1 %2")
end

-- Get display name for a trait
function BurdJournals.UI.DebugPanel.getTraitDisplayName(traitName)
    if BurdJournals.getTraitDisplayName then
        local display = BurdJournals.getTraitDisplayName(traitName)
        if display then return display end
    end
    -- Try TraitFactory
    if TraitFactory and TraitFactory.getTrait then
        local trait = TraitFactory.getTrait(traitName)
        if trait and trait.getLabel then
            return trait:getLabel()
        end
    end
    -- Fallback: convert camelCase to Title Case
    return traitName:gsub("(%l)(%u)", "%1 %2")
end

local function sortDebugDiscoveryRows(rows)
    table.sort(rows, function(a, b)
        local left = string.lower(tostring((a and a.displayName) or (a and a.name) or ""))
        local right = string.lower(tostring((b and b.displayName) or (b and b.name) or ""))
        if left == right then
            return string.lower(tostring((a and a.name) or "")) < string.lower(tostring((b and b.name) or ""))
        end
        return left < right
    end)
end

local function setDebugWidgetTooltipCompat(widget, text)
    if not widget then
        return
    end
    if widget.setTooltip then
        widget:setTooltip(text or "")
    else
        widget.tooltip = text or ""
    end
end

local function getSpawnLoreMode(panel)
    if not panel or not panel.loreModeCombo then
        return "dynamic"
    end
    local selected = tonumber(panel.loreModeCombo.selected) or 0
    if selected <= 0 then
        return "dynamic"
    end
    local value = panel.loreModeCombo:getOptionData(selected)
        or panel.loreModeCombo.options[selected]
    local mode = tostring(value or "dynamic")
    if mode == "custom" then
        return "manual"
    end
    if mode ~= "manual" then
        return "dynamic"
    end
    return mode
end

local function getSelectedLoreTemplateKey(panel)
    if not panel or not panel.loreTemplateCombo then
        return nil
    end
    local selected = tonumber(panel.loreTemplateCombo.selected) or 0
    if selected <= 0 then
        return nil
    end
    local value = panel.loreTemplateCombo:getOptionData(selected)
        or panel.loreTemplateCombo.options[selected]
    value = tostring(value or "")
    if value == "" or value == "random" then
        return nil
    end
    return value
end

function BurdJournals.UI.DebugPanel.applyLoreTemplateOptions(panel, args)
    panel = panel or BurdJournals.UI.DebugPanel.instance
    if panel and not panel.loreTemplateCombo and panel.spawnPanel then
        panel = panel.spawnPanel
    end
    if not panel or not panel.loreTemplateCombo then
        return
    end
    local selectedKey = getSelectedLoreTemplateKey(panel)
    panel.loreTemplateCombo:clear()
    panel.loreTemplateCombo:addOptionWithData(getText("UI_BurdJournals_DebugSpawnLoreTemplateRandom") or "Random template", "random")
    for _, option in ipairs((args and args.templates) or {}) do
        local key = tostring(option.key or "")
        if key ~= "" then
            local label = tostring(option.label or key)
            panel.loreTemplateCombo:addOptionWithData(label, key)
            if selectedKey and selectedKey == key then
                panel.loreTemplateCombo.selected = #panel.loreTemplateCombo.options
            end
        end
    end
    if not panel.loreTemplateCombo.selected or panel.loreTemplateCombo.selected <= 0 then
        setComboSelectedCompat(panel.loreTemplateCombo, 1)
    end
end

local function getSelectedDebugSpawnJournalType(panel)
    if not panel then
        return "filled"
    end
    local combo = panel.journalTypeCombo
    if combo then
        local selected = tonumber(combo.selected) or 1
        local value = combo:getOptionData(selected) or combo.options[selected]
        value = tostring(value or "")
        if isDebugSpawnJournalTypeAllowed(value) then
            return value
        end
    end
    local selectedType = tostring(panel.selectedType or "")
    if isDebugSpawnJournalTypeAllowed(selectedType) then
        return selectedType
    end
    return "filled"
end

function BurdJournals.UI.DebugPanel.requestLoreTemplateOptionsForPanel(panel)
    panel = panel or BurdJournals.UI.DebugPanel.instance
    if panel and not panel.journalTypeCombo and panel.spawnPanel then
        panel = panel.spawnPanel
    end
    if not panel then
        return
    end
    local journalType = getSelectedDebugSpawnJournalType(panel)
    local family = journalType
    if family == "filled" or family == "blank" then
        family = "worn"
    end
    if BurdJournals.Server and BurdJournals.Server.getDebugLoreTemplateOptions then
        local ok, result = pcall(BurdJournals.Server.getDebugLoreTemplateOptions, family)
        if ok and type(result) == "table" then
            result.family = family
            BurdJournals.UI.DebugPanel.applyLoreTemplateOptions(panel, result)
        end
    end
    local player = getPlayer and getPlayer() or nil
    if player and sendClientCommand then
        sendClientCommand(player, "BurdJournals", "debugRequestLoreTemplateOptions", {family = family})
    end
end

local function buildLoreTagHelperRows()
    return {
        {
            tag = getText("UI_BurdJournals_DebugLoreTagHelper_SectionTags") or "Dynamic Tags",
            description = getText("UI_BurdJournals_DebugLoreTagHelper_SectionTagsDesc")
                or "These tokens are replaced when the journal is first generated. Existing save items keep their old notes.",
            isSection = true,
        },
        {
            tag = "{{openerName}}",
            description = getText("UI_BurdJournals_DebugLoreTagHelper_OpenerName")
                or "Uses the first player who opens or unseals the journal. Best for direct mentions and regrets.",
        },
        {
            tag = "{{authorName}}",
            description = getText("UI_BurdJournals_DebugLoreTagHelper_AuthorName")
                or "Uses the journal author's name when available. Best for signatures or remembered conversations.",
        },
        {
            tag = "{{professionName}}",
            description = getText("UI_BurdJournals_DebugLoreTagHelper_ProfessionName")
                or "Uses the profession carried on the journal profile. Best for trade-specific observations.",
        },
        {
            tag = "{{survivorName}}",
            description = getText("UI_BurdJournals_DebugLoreTagHelper_SurvivorName")
                or "Uses another survivor-style name. Good for stash partners, debtors, or people the writer mentions.",
        },
        {
            tag = "{{skillName}} / {{skillNameA}} / {{skillNameB}}",
            description = getText("UI_BurdJournals_DebugLoreTagHelper_SkillName")
                or "Pulls from runtime-discovered skill names. Use the A/B suffixes when you want distinct skills in one note.",
        },
        {
            tag = "{{traitName}} / {{traitNameA}} / {{traitNameB}}",
            description = getText("UI_BurdJournals_DebugLoreTagHelper_TraitName")
                or "Pulls from runtime-discovered trait names. Keep these in lore-sensitive spots instead of generic noun slots.",
        },
        {
            tag = "{{recipeName}} / {{recipeNameA}} / {{recipeNameB}}",
            description = getText("UI_BurdJournals_DebugLoreTagHelper_RecipeName")
                or "Pulls from runtime-discovered journal recipes. Best for practical notes about magazines, plans, or workbenches.",
        },
        {
            tag = "{{stashNoun}} / {{dangerNoun}} / {{supplyNoun}} / {{omenNoun}}",
            description = getText("UI_BurdJournals_DebugLoreTagHelper_Pools")
                or "Uses themed filler pools. These are good when you want variety without tying the note to journal contents.",
        },
        {
            tag = getText("UI_BurdJournals_DebugLoreTagHelper_SectionTips") or "Best Practices",
            description = getText("UI_BurdJournals_DebugLoreTagHelper_SectionTipsDesc")
                or "Short, grounded notes read best. Keep them easy to parse in the journal UI.",
            isSection = true,
        },
        {
            tag = getText("UI_BurdJournals_DebugLoreTagHelper_TipSentencesLabel") or "1-3 sentences",
            description = getText("UI_BurdJournals_DebugLoreTagHelper_TipSentences")
                or "Keep notes to three sentences at most. One or two short sentences usually reads best.",
            isTip = true,
        },
        {
            tag = getText("UI_BurdJournals_DebugLoreTagHelper_TipDistinctLabel") or "Distinct inserts",
            description = getText("UI_BurdJournals_DebugLoreTagHelper_TipDistinct")
                or "Use {{skillNameA}} and {{skillNameB}} when you want different values, not accidental repeats.",
            isTip = true,
        },
        {
            tag = getText("UI_BurdJournals_DebugLoreTagHelper_TipToneLabel") or "Match the journal",
            description = getText("UI_BurdJournals_DebugLoreTagHelper_TipTone")
                or "Worn journals should feel grounded, bloody journals tense, Yuletide warm, and cursed notes accusatory or ominous.",
            isTip = true,
        },
        {
            tag = getText("UI_BurdJournals_DebugLoreTagHelper_TipDynamicLabel") or "New spawns only",
            description = getText("UI_BurdJournals_DebugLoreTagHelper_TipDynamic")
                or "The new Mad Lib note system only applies to journals spawned after this update. Existing save items stay untouched.",
            isTip = true,
        },
    }
end

function BurdJournals.UI.DebugPanel.drawLoreTagHelperItem(self, y, item, alt)
    local h = tonumber(self.itemheight) or 38
    y = tonumber(y) or 0
    if y ~= y then y = 0 end
    if not item or not item.item then return y + h end

    local data = item.item
    local w = tonumber(self.width) or 520
    local scrollOffset = BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH or 15

    if item.index and self.mouseoverselected == item.index then
        self:drawRect(0, y, w, h, 0.15, 0.2, 0.15, 0.4)
    end

    if data.isSection then
        self:drawRect(0, y, w, h, 0.12, 0.18, 0.24, 0.35)
        self:drawText(tostring(data.tag or ""), 8, y + 4, 0.88, 0.92, 1, 1, UIFont.Small)
        self:drawText(tostring(data.description or ""), 8, y + 18, 0.7, 0.78, 0.86, 0.9, UIFont.Small)
        return y + h
    end

    local labelColor = data.isTip and {0.7, 0.85, 1, 1} or {0.95, 0.95, 0.95, 1}
    local detailColor = data.isTip and {0.68, 0.8, 0.95, 0.9} or {0.7, 0.76, 0.84, 0.92}
    self:drawText(tostring(data.tag or ""), 8, y + 4, labelColor[1], labelColor[2], labelColor[3], labelColor[4], UIFont.Small)
    self:drawText(tostring(data.description or ""), 8, y + 18, detailColor[1], detailColor[2], detailColor[3], detailColor[4], UIFont.Small)
    if data.isTip then
        self:drawTextRight(getText("UI_BurdJournals_DebugLoreTagHelper_BadgeTips") or "TIP", w - 8 - scrollOffset, y + 4, 0.62, 0.84, 1, 0.9, UIFont.Small)
    end

    return y + h
end

function BurdJournals.UI.DebugPanel:openLoreTagHelper()
    if self.loreTagHelperPopup and self.loreTagHelperPopup.close then
        self.loreTagHelperPopup:close()
        self.loreTagHelperPopup = nil
    end

    local popupWidth = 640
    local popupHeight = 470
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local popupX = (screenW - popupWidth) / 2
    local popupY = (screenH - popupHeight) / 2

    local popup = ISPanel:new(popupX, popupY, popupWidth, popupHeight)
    popup:initialise()
    popup:instantiate()
    popup.backgroundColor = {r=0.1, g=0.1, b=0.12, a=0.98}
    popup.borderColor = {r=0.4, g=0.5, b=0.6, a=1}
    popup:setAlwaysOnTop(true)
    popup:addToUIManager()
    popup.parentPanel = self

    local padding = 10
    local y = padding

    local titleLabel = ISLabel:new(
        padding,
        y,
        20,
        getText("UI_BurdJournals_DebugLoreTagHelper_Title") or "Dynamic Lore Tags",
        1,
        1,
        1,
        1,
        UIFont.Medium,
        true
    )
    titleLabel:initialise()
    titleLabel:instantiate()
    popup:addChild(titleLabel)

    local closeBtn = ISButton:new(popupWidth - 30, 5, 22, 22, "X", self, function()
        if popup and popup.close then
            popup:close()
        end
    end)
    closeBtn:initialise()
    closeBtn:instantiate()
    closeBtn.borderColor = {r=0.8, g=0.3, b=0.3, a=1}
    closeBtn.backgroundColor = {r=0.2, g=0.1, b=0.1, a=1}
    closeBtn.parent = popup
    popup:addChild(closeBtn)

    y = y + 26
    local introLabel = ISLabel:new(
        padding,
        y,
        18,
        getText("UI_BurdJournals_DebugLoreTagHelper_Subtitle")
            or "Use these tags in custom debug notes. They resolve when the spawned loot journal first generates its lore.",
        0.75,
        0.82,
        0.9,
        1,
        UIFont.Small,
        true
    )
    introLabel:initialise()
    introLabel:instantiate()
    popup:addChild(introLabel)

    y = y + 24
    popup.loreTagList = ISScrollingListBox:new(padding, y, popupWidth - padding * 2, popupHeight - y - padding)
    popup.loreTagList:initialise()
    popup.loreTagList:instantiate()
    popup.loreTagList.itemheight = 40
    popup.loreTagList.backgroundColor = {r=0.06, g=0.06, b=0.08, a=1}
    popup.loreTagList.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    popup.loreTagList.doDrawItem = BurdJournals.UI.DebugPanel.drawLoreTagHelperItem
    popup:addChild(popup.loreTagList)

    for _, row in ipairs(buildLoreTagHelperRows()) do
        popup.loreTagList:addItem(row.tag, row)
    end

    popup.close = function(selfRef)
        selfRef:setVisible(false)
        selfRef:removeFromUIManager()
    end
    self.loreTagHelperPopup = popup
end

function BurdJournals.UI.DebugPanel:onLoreTagHelperClick()
    self:openLoreTagHelper()
end

function BurdJournals.UI.DebugPanel.buildDiscoveryBrowserPayload(kind)
    local rows = {}
    local title = debugText("UI_BurdJournals_DebugDiscoveryBrowser", "Discovery Browser")
    local discoveryMethod = debugText("UI_BurdJournals_DebugUnknown", "Unknown")
    local discoveryTooltip = debugText("UI_BurdJournals_DebugDiscoveryRuntimeTip", "Shows what the mod can currently discover in this runtime.")
    local emptyMessage = debugText("UI_BurdJournals_DebugNoEntriesFound", "No entries found.")

    if kind == "skills" then
        title = debugText("UI_BurdJournals_DebugAvailableSkills", "Available Skills")
        discoveryMethod = debugText("UI_BurdJournals_DebugDiscoveryHardcodedFallback", "Hardcoded fallback")
        discoveryTooltip = debugText("UI_BurdJournals_DebugDiscoverySkillsHardcodedTip", "Shows skills the mod can currently discover. Source method: hardcoded fallback list.")
        emptyMessage = debugText("UI_BurdJournals_DebugNoSkillsFound", "No skills found.")

        local skills = nil
        if BurdJournals and BurdJournals.discoverAllSkills then
            local result = BurdJournals.discoverAllSkills()
            if result and type(result) == "table" and #result > 0 then
                skills = result
            discoveryMethod = debugText("UI_BurdJournals_DebugDiscoverySkillsDynamic", "Dynamic via BurdJournals.discoverAllSkills()")
            discoveryTooltip = debugText("UI_BurdJournals_DebugDiscoverySkillsDynamicTip", "Shows skills the mod can currently discover. Source method: dynamic discovery via BurdJournals.discoverAllSkills().")
            end
        end

        if not skills or #skills == 0 then
            skills = {}
            if PerkFactory and PerkFactory.PerkList then
                local perkList = PerkFactory.PerkList
                if perkList and perkList.size then
                    for i = 0, perkList:size() - 1 do
                        local perk = perkList:get(i)
                        if perk then
                            local parent = perk.getParent and perk:getParent() or nil
                            local parentId = parent and parent.getId and parent:getId() or nil
                            if parent and parentId ~= "None" then
                                local perkName = (perk.getId and perk:getId()) or tostring(perk)
                                if perkName then
                                    table.insert(skills, perkName)
                                end
                            end
                        end
                    end
                end
            end
            if #skills > 0 then
            discoveryMethod = debugText("UI_BurdJournals_DebugDiscoverySkillsRuntimeFallback", "Runtime fallback via PerkFactory.PerkList")
            discoveryTooltip = debugText("UI_BurdJournals_DebugDiscoverySkillsRuntimeFallbackTip", "Shows skills the mod can currently discover. Source method: runtime fallback via PerkFactory.PerkList.")
            else
                skills = BurdJournals.UI.DebugPanel.getAvailableSkills()
            end
        end

        for _, skillName in ipairs(skills or {}) do
            rows[#rows + 1] = {
                name = skillName,
                displayName = BurdJournals.UI.DebugPanel.getSkillDisplayName(skillName),
                source = BurdJournals.getSkillModSource and BurdJournals.getSkillModSource(skillName) or "Unknown",
            }
        end
    elseif kind == "traits" then
        title = debugText("UI_BurdJournals_DebugAvailableTraits", "Available Traits")
        discoveryMethod = debugText("UI_BurdJournals_DebugDiscoveryHardcodedFallback", "Hardcoded fallback")
        discoveryTooltip = debugText("UI_BurdJournals_DebugDiscoveryTraitsHardcodedTip", "Shows traits the mod can currently discover. Source method: hardcoded fallback list.")
        emptyMessage = debugText("UI_BurdJournals_DebugNoTraitsFound", "No traits found.")

        local traitMetadata = BurdJournals and BurdJournals.discoverTraitMetadata and BurdJournals.discoverTraitMetadata() or nil
        local traits = {}
        if BurdJournals and BurdJournals.discoverGrantableTraits then
            local result = BurdJournals.discoverGrantableTraits(true)
            if result and type(result) == "table" and #result > 0 then
                traits = result
            end
        end

        if traitMetadata and BurdJournals.hasAnyEntries and BurdJournals.hasAnyEntries(traitMetadata) and #traits > 0 then
            local grantableSet = {}
            for _, traitId in ipairs(traits) do
                grantableSet[string.lower(tostring(traitId))] = true
            end

            for traitId, traitData in pairs(traitMetadata) do
                if grantableSet[string.lower(tostring(traitId))] then
                    rows[#rows + 1] = {
                        name = traitId,
                        rawId = traitId,
                        displayName = (traitData and traitData.displayName) or BurdJournals.UI.DebugPanel.getTraitDisplayName(traitId),
                        source = (traitData and traitData.source) or (BurdJournals.getTraitModSource and BurdJournals.getTraitModSource(traitId) or "Unknown"),
                    }
                end
            end

            if #rows > 0 then
            discoveryMethod = debugText("UI_BurdJournals_DebugDiscoveryTraitsDynamic", "Dynamic via BurdJournals.discoverTraitMetadata() + discoverGrantableTraits(true)")
            discoveryTooltip = debugText("UI_BurdJournals_DebugDiscoveryTraitsDynamicTip", "Shows traits the mod can currently discover. Source method: runtime discovery via BurdJournals.discoverTraitMetadata(), filtered through BurdJournals.discoverGrantableTraits(true).")
            end
        end

        if #rows == 0 and #traits == 0 then
            if TraitFactory and TraitFactory.getTraits then
                local traitList = TraitFactory.getTraits()
                if traitList and traitList.size then
                    for i = 0, traitList:size() - 1 do
                        local trait = traitList:get(i)
                        local traitType = trait and trait.getType and trait:getType() or nil
                        if traitType then
                            rows[#rows + 1] = {
                                name = tostring(traitType),
                                rawId = tostring(traitType),
                                displayName = BurdJournals.UI.DebugPanel.getTraitDisplayName(tostring(traitType)),
                                source = BurdJournals.getTraitModSource and BurdJournals.getTraitModSource(tostring(traitType)) or "Unknown",
                            }
                        end
                    end
                end
            end
            if #rows > 0 then
            discoveryMethod = debugText("UI_BurdJournals_DebugDiscoveryTraitsRuntimeFallback", "Runtime fallback via TraitFactory.getTraits()")
            discoveryTooltip = debugText("UI_BurdJournals_DebugDiscoveryTraitsRuntimeFallbackTip", "Shows traits the mod can currently discover. Source method: runtime fallback via TraitFactory.getTraits().")
            else
                traits = BurdJournals.UI.DebugPanel.getAvailableTraits()
            end
        end

        if #rows == 0 then
            for _, traitName in ipairs(traits or {}) do
                rows[#rows + 1] = {
                    name = traitName,
                    rawId = traitName,
                    displayName = BurdJournals.UI.DebugPanel.getTraitDisplayName(traitName),
                    source = BurdJournals.getTraitModSource and BurdJournals.getTraitModSource(traitName) or "Unknown",
                }
            end
        end
    elseif kind == "recipes" then
        title = debugText("UI_BurdJournals_DebugAvailableRecipes", "Available Recipes")
        discoveryMethod = debugText("UI_BurdJournals_DebugDiscoveryRecipesDynamic", "Dynamic via runtime recipe catalog + BurdJournals.buildMagazineRecipeCache()")
        discoveryTooltip = debugText("UI_BurdJournals_DebugDiscoveryRecipesDynamicTip", "Shows recipes the mod can currently discover from the live runtime recipe list, plus any journal-transfer mappings from the magazine recipe cache.")
        emptyMessage = debugText("UI_BurdJournals_DebugNoRecipesFound", "No recipes found in the current runtime recipe catalog.")

        local recipeCache = BurdJournals.buildMagazineRecipeCache and BurdJournals.buildMagazineRecipeCache() or {}
        local recipeNames = {}
        appendDebugDiscoveredRecipeNames(recipeNames, recipeCache)
        for recipeName, _ in pairs(recipeNames) do
            local magazineSource = recipeCache[recipeName]
            rows[#rows + 1] = {
                name = recipeName,
                displayName = BurdJournals.getRecipeDisplayName and BurdJournals.getRecipeDisplayName(recipeName) or tostring(recipeName),
                source = BurdJournals.getRecipeModSource and BurdJournals.getRecipeModSource(recipeName, magazineSource) or tostring(magazineSource or "Unknown"),
                magazineSource = magazineSource,
                magazineDisplayName = magazineSource and BurdJournals.getMagazineDisplayName and BurdJournals.getMagazineDisplayName(magazineSource) or nil,
            }
        end
    end

    sortDebugDiscoveryRows(rows)

    return {
        kind = kind,
        title = title,
        discoveryMethod = discoveryMethod,
        discoveryTooltip = discoveryTooltip,
        emptyMessage = emptyMessage,
        rows = rows,
    }
end

function BurdJournals.UI.DebugPanel.populateDiscoveryBrowserList(popup)
    if not popup or not popup.discoveryList then
        return
    end

    local searchText = popup.discoverySearchEntry and popup.discoverySearchEntry:getText() or ""
    popup.discoveryList:clear()

    local added = 0
    for _, row in ipairs(popup.discoveryRows or {}) do
        local matches = searchText == ""
        if not matches then
            matches = debugSearchMatches(searchText, row.displayName, row.name, row.source, row.magazineSource)
        end
        if matches then
            popup.discoveryList:addItem(row.displayName, row)
            added = added + 1
        end
    end

    if added == 0 then
        popup.discoveryList:addItem(popup.discoveryEmptyMessage or debugText("UI_BurdJournals_DebugNoEntriesFound", "No entries found."), {
            isEmpty = true,
            text = popup.discoveryEmptyMessage or debugText("UI_BurdJournals_DebugNoEntriesFound", "No entries found."),
        })
    end
end

function BurdJournals.UI.DebugPanel.drawDiscoveryBrowserItem(self, y, item, alt)
    local h = tonumber(self.itemheight) or 32
    y = tonumber(y) or 0
    if y ~= y then y = 0 end
    if not item or not item.item then return y + h end

    local data = item.item
    local w = tonumber(self.width) or 500
    local scrollOffset = BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH or 15

    if item.index and self.mouseoverselected == item.index then
        self:drawRect(0, y, w, h, 0.15, 0.2, 0.15, 0.4)
    end

    if data.isEmpty then
        self:drawText(tostring(data.text or debugText("UI_BurdJournals_DebugNoEntriesFound", "No entries found.")), 8, y + 8, 0.8, 0.8, 0.8, 0.8, UIFont.Small)
        return y + h
    end

    local displayName = tostring(data.displayName or data.name or debugText("UI_BurdJournals_DebugUnknown", "Unknown"))
    local detail = debugFormatText("UI_BurdJournals_DebugDiscoveryIdFormat", "ID: %1", tostring(data.rawId or data.name or "?"))
    if data.source then
        detail = detail .. debugFormatText("UI_BurdJournals_DebugDiscoverySourceSuffix", " | Source: %1", tostring(data.source))
    end
    if data.magazineSource then
        detail = detail .. debugFormatText("UI_BurdJournals_DebugDiscoveryMagazineSuffix", " | Magazine: %1", tostring(data.magazineSource))
    end

    local textX = 8
    if data.rawId then
        local traitTexture = getDebugTraitTexture(data.rawId)
        local traitSize = drawDebugListIcon(self, traitTexture, textX, y, h, 0.95, 14)
        if traitSize > 0 then
            textX = textX + traitSize + 6
        end
    end
    if data.magazineSource or (data.name and BurdJournals.getMagazineForRecipe and BurdJournals.getMagazineForRecipe(data.name)) then
        local recipeSize = drawDebugListIcon(self, getDebugRecipeTexture(), textX, y, h, 0.95, 14)
        if recipeSize > 0 then
            textX = textX + recipeSize + 4
        end
        local magazineTexture = getDebugMagazineTexture(data.magazineSource or (BurdJournals.getMagazineForRecipe and BurdJournals.getMagazineForRecipe(data.name)))
        local magazineSize = drawDebugListIcon(self, magazineTexture, textX, y, h, 0.9, 14)
        if magazineSize > 0 then
            textX = textX + magazineSize + 6
        end
    end

    self:drawText(displayName, textX, y + 3, 0.95, 0.95, 0.95, 1, UIFont.Small)
    self:drawText(detail, textX, y + 16, 0.65, 0.72, 0.8, 0.9, UIFont.Small)

    local badgeText = tostring(data.source or "")
    if badgeText ~= "" then
        self:drawTextRight(badgeText, w - 8 - scrollOffset, y + 3, 0.7, 0.85, 1, 0.85, UIFont.Small)
    end

    return y + h
end

function BurdJournals.UI.DebugPanel:openDiscoveryBrowser(kind)
    if self.discoveryPopup and self.discoveryPopup.close then
        self.discoveryPopup:close()
        self.discoveryPopup = nil
    end

    local payload = BurdJournals.UI.DebugPanel.buildDiscoveryBrowserPayload(kind)
    if not payload then
        self:setStatus(debugText("UI_BurdJournals_DebugDiscoveryUnavailable", "Discovery browser unavailable"), {r=1, g=0.6, b=0.3})
        return
    end

    local popupWidth = 620
    local popupHeight = 460
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local popupX = (screenW - popupWidth) / 2
    local popupY = (screenH - popupHeight) / 2

    local popup = ISPanel:new(popupX, popupY, popupWidth, popupHeight)
    popup:initialise()
    popup:instantiate()
    popup.backgroundColor = {r=0.1, g=0.1, b=0.12, a=0.98}
    popup.borderColor = {r=0.4, g=0.5, b=0.6, a=1}
    popup:setAlwaysOnTop(true)
    popup:addToUIManager()
    popup.parentPanel = self
    popup.discoveryRows = payload.rows or {}
    popup.discoveryEmptyMessage = payload.emptyMessage

    local padding = 10
    local y = padding

    local titleLabel = ISLabel:new(padding, y, 22, payload.title or debugText("UI_BurdJournals_DebugDiscoveryBrowser", "Discovery Browser"), 0.9, 0.8, 0.6, 1, UIFont.Medium, true)
    titleLabel:initialise()
    titleLabel:instantiate()
    popup:addChild(titleLabel)

    local closeBtn = ISButton:new(popupWidth - 30, 5, 22, 22, "X", self, function()
        if popup and popup.close then
            popup:close()
        end
    end)
    closeBtn:initialise()
    closeBtn:instantiate()
    closeBtn.font = UIFont.Small
    closeBtn.textColor = {r=1, g=0.5, b=0.5, a=1}
    closeBtn.borderColor = {r=0.5, g=0.3, b=0.3, a=1}
    closeBtn.backgroundColor = {r=0.3, g=0.1, b=0.1, a=0.8}
    closeBtn.parent = popup
    popup:addChild(closeBtn)
    y = y + 28

    local sourceLabel = ISLabel:new(padding, y, 18, debugFormatText("UI_BurdJournals_DebugDiscoveryMethodFormat", "Discovery: %1", tostring(payload.discoveryMethod or debugText("UI_BurdJournals_DebugUnknown", "Unknown"))), 0.7, 0.82, 1, 1, UIFont.Small, true)
    sourceLabel:initialise()
    sourceLabel:instantiate()
    setDebugWidgetTooltipCompat(sourceLabel, payload.discoveryTooltip or "")
    popup:addChild(sourceLabel)
    y = y + 22

    local searchLabel = ISLabel:new(padding, y, 18, debugText("UI_BurdJournals_DebugSearchLabel", "Search:"), 0.7, 0.7, 0.7, 1, UIFont.Small, true)
    searchLabel:initialise()
    searchLabel:instantiate()
    popup:addChild(searchLabel)

    popup.discoverySearchEntry = ISTextEntryBox:new("", padding + 50, y - 2, popupWidth - padding * 2 - 50, 20)
    popup.discoverySearchEntry:initialise()
    popup.discoverySearchEntry:instantiate()
    popup.discoverySearchEntry.font = UIFont.Small
    setDebugWidgetTooltipCompat(popup.discoverySearchEntry, payload.discoveryTooltip or debugText("UI_BurdJournals_DebugDiscoverySearchTip", "Type to filter the discovery list."))
    popup.discoverySearchEntry.onTextChange = function()
        BurdJournals.UI.DebugPanel.populateDiscoveryBrowserList(popup)
    end
    popup:addChild(popup.discoverySearchEntry)
    y = y + 28

    local listHeight = popupHeight - y - 12
    popup.discoveryList = ISScrollingListBox:new(padding, y, popupWidth - padding * 2, listHeight)
    popup.discoveryList:initialise()
    popup.discoveryList:instantiate()
    popup.discoveryList.itemheight = 34
    popup.discoveryList.backgroundColor = {r=0.06, g=0.06, b=0.08, a=1}
    popup.discoveryList.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    popup.discoveryList.doDrawItem = BurdJournals.UI.DebugPanel.drawDiscoveryBrowserItem
    popup.discoveryList.parentPanel = self
    setDebugWidgetTooltipCompat(popup.discoveryList, payload.discoveryTooltip or "")
    popup:addChild(popup.discoveryList)

    popup.close = function(selfRef)
        selfRef:setVisible(false)
        selfRef:removeFromUIManager()
    end

    BurdJournals.UI.DebugPanel.populateDiscoveryBrowserList(popup)
    self.discoveryPopup = popup
end

function BurdJournals.UI.DebugPanel:createSpawnPanel(startY, height)
    local panel = ISPanel:new(5, startY, self.width - 10, height)
    panel:initialise()
    panel:instantiate()
    panel.backgroundColor = {r=0.12, g=0.12, b=0.15, a=1}
    panel.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    self:addChild(panel)
    self.tabPanels["spawn"] = panel
    
    local padding = 10
    local y = padding
    local fullWidth = panel.width - padding * 2
    
    -- Journal Type section
    local typeLabel = ISLabel:new(padding, y, 20, debugText("UI_BurdJournals_DebugJournalTypeLabel", "Journal Type:"), 1, 1, 1, 1, UIFont.Small, true)
    typeLabel:initialise()
    typeLabel:instantiate()
    panel:addChild(typeLabel)
    y = y + 22
    
    -- Type buttons
    local typeX = padding
    local btnWidth = 76
    local types = BurdJournals.UI.DebugPanel.getDebugSpawnJournalTypeDefs()
    panel.typeButtons = {}
    panel.selectedType = "filled"
    
    for _, typeInfo in ipairs(types) do
        local btn = ISButton:new(typeX, y, btnWidth, 22, typeInfo.label, self, BurdJournals.UI.DebugPanel.onTypeSelect)
        btn:initialise()
        btn:instantiate()
        btn.font = UIFont.Small
        btn.internal = typeInfo.id
        btn.textColor = {r=1, g=1, b=1, a=1}
        btn.borderColor = {r=0.4, g=0.5, b=0.6, a=1}
        btn.backgroundColor = {r=0.2, g=0.25, b=0.3, a=1}
        if typeInfo.tooltip and btn.setTooltip then
            btn:setTooltip(tostring(typeInfo.tooltip))
        end
        attachDebugButtonIconCompat(btn, getDebugJournalTypeTexture(btn.internal))
        panel:addChild(btn)
        panel.typeButtons[typeInfo.id] = btn
        typeX = typeX + btnWidth + 3
    end

    panel.spawnImportBtn = ISButton:new(typeX + 5, y, 104, 22, debugText("UI_BurdJournals_DebugJournalImportJSON", "Import JSON"), self, BurdJournals.UI.DebugPanel.onSpawnImportJSON)
    panel.spawnImportBtn:initialise()
    panel.spawnImportBtn:instantiate()
    panel.spawnImportBtn.font = UIFont.Small
    panel.spawnImportBtn.textColor = {r=0.85, g=0.95, b=1, a=1}
    panel.spawnImportBtn.borderColor = {r=0.35, g=0.5, b=0.65, a=1}
    panel.spawnImportBtn.backgroundColor = {r=0.12, g=0.22, b=0.3, a=1}
    panel.spawnImportBtn:setTooltip(debugText("UI_BurdJournals_DebugJournalImportSpawnTip", "Import a journal JSON export as a newly spawned journal."))
    panel:addChild(panel.spawnImportBtn)

    self:updateTypeButtons(panel)
    y = y + 30

    -- Spawn profile: normal (natural behavior) vs debug (legacy debug flags)
    panel.spawnProfile = "normal"

    panel.spawnProfileLabel = ISLabel:new(
        padding,
        y,
        18,
        BurdJournals.safeGetText and BurdJournals.safeGetText("UI_BurdJournals_DebugSpawnProfile", "Spawn Profile:")
            or "Spawn Profile:",
        0.9, 0.9, 0.7, 1,
        UIFont.Small,
        true
    )
    panel.spawnProfileLabel:initialise()
    panel.spawnProfileLabel:instantiate()
    panel:addChild(panel.spawnProfileLabel)

    panel.spawnProfileCombo = ISComboBox:new(padding + 95, y - 2, 215, 22, self, BurdJournals.UI.DebugPanel.onSpawnProfileChange)
    panel.spawnProfileCombo:initialise()
    panel.spawnProfileCombo:instantiate()
    panel.spawnProfileCombo.font = UIFont.Small
    panel.spawnProfileCombo:addOptionWithData(
        BurdJournals.safeGetText and BurdJournals.safeGetText("UI_BurdJournals_DebugSpawnProfileNormal", "Normal (Natural)")
            or "Normal (Natural)",
        "normal"
    )
    panel.spawnProfileCombo:addOptionWithData(
        BurdJournals.safeGetText and BurdJournals.safeGetText("UI_BurdJournals_DebugSpawnProfileDebug", "Debug (Legacy)")
            or "Debug (Legacy)",
        "debug"
    )
    setComboSelectedCompat(panel.spawnProfileCombo, 1)
    panel:addChild(panel.spawnProfileCombo)
    y = y + 24

    panel.spawnOriginMode = "auto"
    panel.spawnOriginLabel = ISLabel:new(
        padding,
        y,
        18,
        BurdJournals.safeGetText and BurdJournals.safeGetText("UI_BurdJournals_DebugSpawnOrigin", "Origin:") or "Origin:",
        0.9, 0.9, 0.7, 1,
        UIFont.Small,
        true
    )
    panel.spawnOriginLabel:initialise()
    panel.spawnOriginLabel:instantiate()
    panel:addChild(panel.spawnOriginLabel)

    panel.spawnOriginCombo = ISComboBox:new(padding + 95, y - 2, 215, 22, self, BurdJournals.UI.DebugPanel.onSpawnOriginChange)
    panel.spawnOriginCombo:initialise()
    panel.spawnOriginCombo:instantiate()
    panel.spawnOriginCombo.font = UIFont.Small
    panel.spawnOriginCombo:addOptionWithData(
        BurdJournals.safeGetText and BurdJournals.safeGetText("UI_BurdJournals_DebugSpawnOriginAuto", "Auto (Type Default)")
            or "Auto (Type Default)",
        "auto"
    )
    panel.spawnOriginCombo:addOptionWithData(
        BurdJournals.safeGetText and BurdJournals.safeGetText("UI_BurdJournals_DebugSpawnOriginPersonal", "Personal")
            or "Personal",
        "personal"
    )
    panel.spawnOriginCombo:addOptionWithData(
        BurdJournals.safeGetText and BurdJournals.safeGetText("UI_BurdJournals_DebugSpawnOriginFound", "Found")
            or "Found",
        "found"
    )
    panel.spawnOriginCombo:addOptionWithData(
        BurdJournals.safeGetText and BurdJournals.safeGetText("UI_BurdJournals_DebugSpawnOriginWorld", "Found in World")
            or "Found in World",
        "world"
    )
    panel.spawnOriginCombo:addOptionWithData(
        BurdJournals.safeGetText and BurdJournals.safeGetText("UI_BurdJournals_DebugSpawnOriginZombie", "Recovered from Zombie")
            or "Recovered from Zombie",
        "zombie"
    )
    setComboSelectedCompat(panel.spawnOriginCombo, 1)
    panel:addChild(panel.spawnOriginCombo)
    y = y + 24

    panel.ownerSectionY = y

    panel.filledStateLabel = ISLabel:new(padding, y, 18, debugText("UI_BurdJournals_DebugFilledState", "Filled State:"), 0.9, 0.9, 0.7, 1, UIFont.Small, true)
    panel.filledStateLabel:initialise()
    panel.filledStateLabel:instantiate()
    panel:addChild(panel.filledStateLabel)

    panel.filledStateCombo = ISComboBox:new(padding + 95, y - 2, 215, 22, self, BurdJournals.UI.DebugPanel.onFilledStateChange)
    panel.filledStateCombo:initialise()
    panel.filledStateCombo:instantiate()
    panel.filledStateCombo.font = UIFont.Small
    panel.filledStateCombo:addOptionWithData(debugText("UI_BurdJournals_DebugFilledStateClean", "Clean"), "clean")
    panel.filledStateCombo:addOptionWithData(debugText("UI_BurdJournals_DebugFilledStateRestored", "Restored"), "restored")
    setComboSelectedCompat(panel.filledStateCombo, 1)
    panel:addChild(panel.filledStateCombo)
    y = y + 24
    
    -- ====== Owner/Assignment Section ======
    -- This section changes based on journal type:
    -- - Blank: Hidden (no owner needed)
    -- - Filled: Player dropdown + Custom option (for editable journals)
    -- - Worn/Bloody: Name field for RP/lore purposes
    
    panel.ownerLabel = ISLabel:new(
        padding, y, 18,
        (BurdJournals.safeGetText and BurdJournals.safeGetText("UI_BurdJournals_DebugSpawnOwnerAssign", "Assign to Player:")) or "Assign to Player:",
        0.9, 0.9, 0.7, 1, UIFont.Small, true
    )
    panel.ownerLabel:initialise()
    panel.ownerLabel:instantiate()
    panel:addChild(panel.ownerLabel)
    
    -- Player dropdown (includes "Custom..." option at the end)
    panel.ownerCombo = ISComboBox:new(padding + 110, y - 2, 200, 22, self, BurdJournals.UI.DebugPanel.onOwnerComboChange)
    panel.ownerCombo:initialise()
    panel.ownerCombo:instantiate()
    panel.ownerCombo.font = UIFont.Small
    panel:addChild(panel.ownerCombo)
    
    -- Populate with online players + "Custom..." option
    self:populateOwnerCombo(panel)
    self:applySpawnOwnerDefault(panel, panel.selectedType or "filled")
    y = y + 24
    
    -- Custom name entry (shown when "Custom..." is selected)
    panel.customNameLabel = ISLabel:new(padding, y, 18, debugText("UI_BurdJournals_DebugCustomName", "Custom Name:"), 0.8, 0.8, 0.8, 1, UIFont.Small, true)
    panel.customNameLabel:initialise()
    panel.customNameLabel:instantiate()
    panel.customNameLabel:setVisible(false)
    panel:addChild(panel.customNameLabel)
    
    panel.customNameEntry = ISTextEntryBox:new(debugText("UI_BurdJournals_DebugUnknownSurvivor", "Unknown Survivor"), padding + 85, y - 2, 225, 20)
    panel.customNameEntry:initialise()
    panel.customNameEntry:instantiate()
    panel.customNameEntry.font = UIFont.Small
    panel.customNameEntry:setTooltip(debugText("UI_BurdJournals_DebugCustomNameTip", "Enter a custom owner name for the journal"))
    panel.customNameEntry:setVisible(false)
    panel:addChild(panel.customNameEntry)
    y = y + 24
    
    -- ====== Profession Section (for Worn/Bloody journals) ======
    panel.professionLabel = ISLabel:new(padding, y, 18, debugText("UI_BurdJournals_DebugProfession", "Profession:"), 0.8, 0.8, 0.8, 1, UIFont.Small, true)
    panel.professionLabel:initialise()
    panel.professionLabel:instantiate()
    panel:addChild(panel.professionLabel)
    
    panel.professionCombo = ISComboBox:new(padding + 75, y - 2, 235, 22, self, BurdJournals.UI.DebugPanel.onProfessionComboChange)
    panel.professionCombo:initialise()
    panel.professionCombo:instantiate()
    panel.professionCombo.font = UIFont.Small
    panel:addChild(panel.professionCombo)
    
    -- Populate profession dropdown
    panel.professionCombo:addOption(debugText("UI_BurdJournals_DebugRandomOption", "(Random)"))  -- Index 1
    panel.professionCombo:addOption(debugText("UI_BurdJournals_DebugNoneOption", "(None)"))    -- Index 2
    panel.professionCombo:addOption(debugText("UI_BurdJournals_DebugSpawnOwnerCustom", "Custom..."))  -- Index 3
    if BurdJournals.PROFESSIONS then
        for _, prof in ipairs(BurdJournals.PROFESSIONS) do
            local displayName = prof.nameKey and getText(prof.nameKey) or prof.name
            panel.professionCombo:addOption(displayName)  -- Index 4+
        end
    end
    setComboSelectedCompat(panel.professionCombo, 1)  -- Default to (Random)
    
    panel.professionSectionY = y
    y = y + 24
    
    -- Custom profession entry (shown when "Custom..." is selected)
    panel.customProfLabel = ISLabel:new(padding, y, 18, debugText("UI_BurdJournals_DebugCustomProfession", "Custom Prof:"), 0.8, 0.8, 0.8, 1, UIFont.Small, true)
    panel.customProfLabel:initialise()
    panel.customProfLabel:instantiate()
    panel.customProfLabel:setVisible(false)
    panel:addChild(panel.customProfLabel)
    
    panel.customProfEntry = ISTextEntryBox:new(debugText("UI_BurdJournals_DebugFormerSurvivor", "Former Survivor"), padding + 85, y - 2, 225, 20)
    panel.customProfEntry:initialise()
    panel.customProfEntry:instantiate()
    panel.customProfEntry.font = UIFont.Small
    panel.customProfEntry:setTooltip(debugText("UI_BurdJournals_DebugCustomProfessionTip", "Enter custom profession (e.g., 'Former Teacher', 'Ex-Mechanic')"))
    panel.customProfEntry:setVisible(false)
    panel:addChild(panel.customProfEntry)
    
    panel.customProfSectionY = y
    y = y + 26
    
    -- ====== Flavor Text Section (custom subtitle) ======
    panel.flavorLabel = ISLabel:new(padding, y, 18, debugText("UI_BurdJournals_DebugFlavorText", "Flavor Text:"), 0.8, 0.8, 0.8, 1, UIFont.Small, true)
    panel.flavorLabel:initialise()
    panel.flavorLabel:instantiate()
    panel:addChild(panel.flavorLabel)
    
    panel.flavorEntry = ISTextEntryBox:new("", padding + 75, y - 2, 235, 20)
    panel.flavorEntry:initialise()
    panel.flavorEntry:instantiate()
    panel.flavorEntry.font = UIFont.Small
    panel.flavorEntry:setTooltip(debugText("UI_BurdJournals_DebugFlavorTextTip", "Custom flavor text (leave empty for profession default)"))
    panel:addChild(panel.flavorEntry)
    
    panel.flavorSectionY = y
    y = y + 24

    panel.loreModeLabel = ISLabel:new(padding, y, 18, getText("UI_BurdJournals_DebugSpawnLoreMode") or "Lore Mode:", 0.8, 0.8, 0.8, 1, UIFont.Small, true)
    panel.loreModeLabel:initialise()
    panel.loreModeLabel:instantiate()
    panel.loreModeLabel:setVisible(false)
    panel:addChild(panel.loreModeLabel)

    panel.loreModeCombo = ISComboBox:new(padding + 75, y - 2, 120, 22, self, BurdJournals.UI.DebugPanel.onLoreModeComboChange)
    panel.loreModeCombo:initialise()
    panel.loreModeCombo:instantiate()
    panel.loreModeCombo.font = UIFont.Small
    panel.loreModeCombo:addOptionWithData(getText("UI_BurdJournals_DebugSpawnLoreModeRandom") or "Random", "dynamic")
    panel.loreModeCombo:addOptionWithData(getText("UI_BurdJournals_DebugSpawnLoreModeManual") or "Manual", "manual")
    setComboSelectedCompat(panel.loreModeCombo, 1)
    panel.loreModeCombo:setVisible(false)
    setDebugWidgetTooltipCompat(
        panel.loreModeCombo,
        getText("UI_BurdJournals_DebugSpawnLoreModeTip")
            or "Random uses normal procedural selection. Manual lets you pick a shipped or custom template key."
    )
    panel:addChild(panel.loreModeCombo)

    panel.loreModeSectionY = y
    y = y + 24

    panel.loreNoteLabel = ISLabel:new(padding, y, 18, getText("UI_BurdJournals_DebugSpawnLoreTemplate") or "Template:", 0.8, 0.8, 0.8, 1, UIFont.Small, true)
    panel.loreNoteLabel:initialise()
    panel.loreNoteLabel:instantiate()
    panel.loreNoteLabel:setVisible(false)
    panel:addChild(panel.loreNoteLabel)

    panel.loreTemplateCombo = ISComboBox:new(padding + 75, y - 2, 235, 22, self, nil)
    panel.loreTemplateCombo:initialise()
    panel.loreTemplateCombo:instantiate()
    panel.loreTemplateCombo.font = UIFont.Small
    panel.loreTemplateCombo:addOptionWithData(getText("UI_BurdJournals_DebugSpawnLoreTemplateRandom") or "Random template", "random")
    setComboSelectedCompat(panel.loreTemplateCombo, 1)
    panel.loreTemplateCombo:setVisible(false)
    setDebugWidgetTooltipCompat(
        panel.loreTemplateCombo,
        getText("UI_BurdJournals_DebugSpawnLoreTemplateTip")
            or "Choose a specific shipped or custom procedural lore template for this spawned loot journal."
    )
    panel:addChild(panel.loreTemplateCombo)

    panel.loreNoteSectionY = y
    y = y + 28

    -- ====== Spawn Metadata Section ======
    panel.ageLabel = ISLabel:new(padding, y, 18, debugText("UI_BurdJournals_DebugAgeHoursAgo", "Age (hours ago):"), 0.8, 0.8, 0.8, 1, UIFont.Small, true)
    panel.ageLabel:initialise()
    panel.ageLabel:instantiate()
    panel:addChild(panel.ageLabel)

    panel.ageEntry = ISTextEntryBox:new("72", padding + 95, y - 2, 70, 20)
    panel.ageEntry:initialise()
    panel.ageEntry:instantiate()
    panel.ageEntry.font = UIFont.Small
    panel.ageEntry:setOnlyNumbers(true)
    panel.ageEntry:setTooltip(debugText("UI_BurdJournals_DebugAgeHoursAgoTip", "How many in-game hours old this journal should appear"))
    panel:addChild(panel.ageEntry)
    y = y + 24

    panel.yuletideStateLabel = ISLabel:new(padding, y, 18, debugText("UI_BurdJournals_DebugYuletideState", "Yuletide State:"), 0.8, 0.8, 0.8, 1, UIFont.Small, true)
    panel.yuletideStateLabel:initialise()
    panel.yuletideStateLabel:instantiate()
    panel:addChild(panel.yuletideStateLabel)

    panel.yuletideStateCombo = ISComboBox:new(padding + 95, y - 2, 215, 22, self, nil)
    panel.yuletideStateCombo:initialise()
    panel.yuletideStateCombo:instantiate()
    panel.yuletideStateCombo.font = UIFont.Small
    panel.yuletideStateCombo:addOptionWithData(debugText("UI_BurdJournals_DebugYuletideWrapped", "Wrapped"), BurdJournals.YULETIDE_STATE_WRAPPED or "wrapped")
    panel.yuletideStateCombo:addOptionWithData(debugText("UI_BurdJournals_DebugYuletideUnwrapped", "Unwrapped"), BurdJournals.YULETIDE_STATE_UNWRAPPED or "unwrapped")
    panel.yuletideStateCombo.parentPanel = panel
    installDebugIconCombo(panel.yuletideStateCombo, function(combo, optionIndex, optionText, optionData)
        local stateValue = optionData or optionText
        local variant = getSelectedYuletideWrappedVariant(combo.parentPanel)
        return getDebugYuletideTextureForState(stateValue, variant)
    end)
    setComboSelectedCompat(panel.yuletideStateCombo, 1)
    panel:addChild(panel.yuletideStateCombo)
    y = y + 24

    panel.yuletideWrappedVariantLabel = ISLabel:new(padding, y, 18, debugText("UI_BurdJournals_DebugWrappedVariant", "Wrapped Variant:"), 0.8, 0.8, 0.8, 1, UIFont.Small, true)
    panel.yuletideWrappedVariantLabel:initialise()
    panel.yuletideWrappedVariantLabel:instantiate()
    panel:addChild(panel.yuletideWrappedVariantLabel)

    panel.yuletideWrappedVariantCombo = ISComboBox:new(padding + 95, y - 2, 215, 22, self, nil)
    panel.yuletideWrappedVariantCombo:initialise()
    panel.yuletideWrappedVariantCombo:instantiate()
    panel.yuletideWrappedVariantCombo.font = UIFont.Small
    local yuletideVariants = (BurdJournals.getYuletideWrappedVariants and BurdJournals.getYuletideWrappedVariants())
        or BurdJournals.YULETIDE_WRAPPED_VARIANTS
        or {"1"}
    for _, variant in ipairs(yuletideVariants) do
        panel.yuletideWrappedVariantCombo:addOptionWithData(debugFormatText("UI_BurdJournals_DebugVariantFormat", "Variant %1", tostring(variant)), tostring(variant))
    end
    panel.yuletideWrappedVariantCombo.parentPanel = panel
    installDebugIconCombo(panel.yuletideWrappedVariantCombo, function(combo, optionIndex, optionText, optionData)
        local variant = optionData or optionText
        return getDebugYuletideTextureForState(BurdJournals.YULETIDE_STATE_WRAPPED or "wrapped", variant)
    end)
    setComboSelectedCompat(panel.yuletideWrappedVariantCombo, 1)
    panel:addChild(panel.yuletideWrappedVariantCombo)
    y = y + 24

    panel.yuletideRewardTierLabel = ISLabel:new(padding, y, 18, debugText("UI_BurdJournals_DebugYuletideRewardTier", "Reward Tier:"), 0.8, 0.8, 0.8, 1, UIFont.Small, true)
    panel.yuletideRewardTierLabel:initialise()
    panel.yuletideRewardTierLabel:instantiate()
    panel:addChild(panel.yuletideRewardTierLabel)

    panel.yuletideRewardTierCombo = ISComboBox:new(padding + 95, y - 2, 215, 22, self, nil)
    panel.yuletideRewardTierCombo:initialise()
    panel.yuletideRewardTierCombo:instantiate()
    panel.yuletideRewardTierCombo.font = UIFont.Small
    panel.yuletideRewardTierCombo:addOptionWithData(debugText("UI_BurdJournals_DebugYuletideTierRandom", "Random"), "random")
    panel.yuletideRewardTierCombo:addOptionWithData(debugText("UI_BurdJournals_DebugYuletideTierPractical", "Practical"), "practical")
    panel.yuletideRewardTierCombo:addOptionWithData(debugText("UI_BurdJournals_DebugYuletideTierRare", "Rare"), "rare")
    panel.yuletideRewardTierCombo:addOptionWithData(debugText("UI_BurdJournals_DebugYuletideTierJackpot", "Jackpot"), "jackpot")
    setComboSelectedCompat(panel.yuletideRewardTierCombo, 1)
    panel:addChild(panel.yuletideRewardTierCombo)
    y = y + 24

    -- Cursed controls (shown only for cursed type)
    panel.cursedStateLabel = ISLabel:new(padding, y, 18, (getText("UI_BurdJournals_DebugCursedState") or "Cursed State:"), 0.8, 0.75, 0.9, 1, UIFont.Small, true)
    panel.cursedStateLabel:initialise()
    panel.cursedStateLabel:instantiate()
    panel:addChild(panel.cursedStateLabel)

    panel.cursedStateCombo = ISComboBox:new(padding + 95, y - 2, 215, 22, self, nil)
    panel.cursedStateCombo:initialise()
    panel.cursedStateCombo:instantiate()
    panel.cursedStateCombo.font = UIFont.Small
    panel.cursedStateCombo:addOption(getText("UI_BurdJournals_DebugCursedDormant") or "Dormant (Cursed Item)")
    panel.cursedStateCombo:addOption(getText("UI_BurdJournals_DebugCursedHidden") or "Hidden (Disguised Bloody)")
    panel.cursedStateCombo:addOption(getText("UI_BurdJournals_DebugCursedUnleashed") or "Unleashed (Bloody Reward)")
    setComboSelectedCompat(panel.cursedStateCombo, 1)
    panel:addChild(panel.cursedStateCombo)
    y = y + 24

    panel.forceCurseLabel = ISLabel:new(padding, y, 18, (getText("UI_BurdJournals_DebugForceCurse") or "Force Curse:"), 0.8, 0.75, 0.9, 1, UIFont.Small, true)
    panel.forceCurseLabel:initialise()
    panel.forceCurseLabel:instantiate()
    panel:addChild(panel.forceCurseLabel)

    local forceComboX = padding + 95
    local forceComboTotalW = math.max(220, panel.width - forceComboX - padding)
    local forceComboPrimaryW = math.max(120, math.floor((forceComboTotalW - 6) * 0.5))
    local forceComboTargetW = math.max(95, forceComboTotalW - forceComboPrimaryW - 6)

    panel.forceCurseCombo = ISComboBox:new(forceComboX, y - 2, forceComboPrimaryW, 22, self, BurdJournals.UI.DebugPanel.onForceCurseComboChange)
    panel.forceCurseCombo:initialise()
    panel.forceCurseCombo:instantiate()
    panel.forceCurseCombo.font = UIFont.Small
    panel.forceCurseCombo:addOptionWithData(getText("UI_BurdJournals_DebugCurseRandom") or "Random", "random")
    panel.forceCurseCombo:addOptionWithData(getText("UI_BurdJournals_DebugCurseBarbedSeal") or "Barbed Seal (Hand Laceration)", "barbed_seal")
    panel.forceCurseCombo:addOptionWithData(getText("UI_BurdJournals_DebugCurseJammedBreath") or "Jammed Breath (Endurance Hit)", "jammed_breath")
    panel.forceCurseCombo:addOptionWithData(getText("UI_BurdJournals_DebugCurseHexedTooling") or "Hexed Tooling (Item Condition Loss)", "hexed_tooling")
    panel.forceCurseCombo:addOptionWithData(getText("UI_BurdJournals_DebugCurseTornGear") or "Torn Gear (3-5 Holes)", "torn_gear")
    panel.forceCurseCombo:addOptionWithData(getText("UI_BurdJournals_DebugCurseSeasonalWave") or "Seasonal Wave (Heat/Cold Spike)", "seasonal_wave")
    panel.forceCurseCombo:addOptionWithData(getText("UI_BurdJournals_DebugCursePantsed") or "Pants'd (Unequip Bottoms)", "pantsed")
    panel.forceCurseCombo:addOptionWithData(getText("UI_BurdJournals_DebugCurseGainNegative") or "Gain Negative Trait", "gain_negative_trait")
    panel.forceCurseCombo:addOptionWithData(getText("UI_BurdJournals_DebugCurseLosePositive") or "Lose Positive Trait", "lose_positive_trait")
    panel.forceCurseCombo:addOptionWithData(getText("UI_BurdJournals_DebugCurseLoseSkill") or "Lose Skill Level", "lose_skill_level")
    panel.forceCurseCombo:addOptionWithData(getText("UI_BurdJournals_DebugCurseAmbush") or "Ambush (Panic + Horde)", "panic")
    setComboSelectedCompat(panel.forceCurseCombo, 1)
    panel:addChild(panel.forceCurseCombo)

    panel.forceCurseTargetCombo = ISComboBox:new(forceComboX + forceComboPrimaryW + 6, y - 2, forceComboTargetW, 22, self, nil)
    panel.forceCurseTargetCombo:initialise()
    panel.forceCurseTargetCombo:instantiate()
    panel.forceCurseTargetCombo.font = UIFont.Small
    panel.forceCurseTargetCombo:setVisible(false)
    if panel.forceCurseTargetCombo.setTooltip then
        panel.forceCurseTargetCombo:setTooltip(getText("UI_BurdJournals_DebugForceCurseTargetTip")
            or "Optional specific target used by the selected curse type.")
    end
    panel:addChild(panel.forceCurseTargetCombo)

    panel.forceCurseTargetType = nil
    y = y + 24

    panel.forgetSlotTick = ISTickBox:new(padding, y - 2, panel.width - (padding * 2), 20, "", self, nil)
    panel.forgetSlotTick:initialise()
    panel.forgetSlotTick:instantiate()
    panel.forgetSlotTick:addOption(getText("UI_BurdJournals_DebugForgetSlot") or "Include forget slot")
    if panel.forgetSlotTick.setSelected then
        panel.forgetSlotTick:setSelected(1, false)
    else
        panel.forgetSlotTick.selected[1] = false
    end
    panel:addChild(panel.forgetSlotTick)
    y = y + 24

    panel.debugExtensionControls = {}
    for _, typeInfo in ipairs(types or {}) do
        local typeId = tostring(typeInfo and typeInfo.id or "")
        if typeId ~= "" and DEBUG_BUILTIN_JOURNAL_TYPES[typeId] ~= true and type(typeInfo.buildControls) == "function" then
            local section = typeInfo.buildControls(panel, y, {
                owner = self,
                padding = padding,
                fullWidth = fullWidth,
                rowHeight = 24,
                setTooltip = setDebugWidgetTooltipCompat,
            })
            if type(section) == "table" then
                section.widgets = type(section.widgets) == "table" and section.widgets or {}
                panel.debugExtensionControls[typeId] = section
                for _, widget in ipairs(section.widgets) do
                    if widget and widget.setVisible then
                        widget:setVisible(false)
                    end
                end
                if section.panel and section.panel.setVisible then
                    section.panel:setVisible(false)
                end
            end
        end
    end

    -- ====== Content Section (Skills / Traits / Recipes) ======
    panel.contentSeparatorY = y
    y = y + 5
    panel.contentStartY = y
    panel.selectedSkills = {}  -- {skillName = {level = X, extraXP = Y}}
    panel.selectedTraits = {}  -- {traitName = true}
    panel.selectedRecipes = {} -- {recipeName = true}
    panel.focusedSkill = nil   -- Currently focused skill for level editing
    panel.defaultLevel = 10
    panel.defaultExtraXP = 0
    panel.spawnTabState = {buttons = {}, panels = {}, current = "skills"}

    local tabX = padding
    local tabWidth = 84
    local tabHeight = 22
    local tabSpacing = 6
    panel.spawnTabState.buttons.skills = createDebugButton(panel, tabX, y, tabWidth, tabHeight, debugText("UI_BurdJournals_DebugWhitelistSkills", "Skills"), self, BurdJournals.UI.DebugPanel.onSpawnSubTab, "skills")
    tabX = tabX + tabWidth + tabSpacing
    panel.spawnTabState.buttons.traits = createDebugButton(panel, tabX, y, tabWidth, tabHeight, debugText("UI_BurdJournals_DebugWhitelistTraits", "Traits"), self, BurdJournals.UI.DebugPanel.onSpawnSubTab, "traits")
    tabX = tabX + tabWidth + tabSpacing
    panel.spawnTabState.buttons.recipes = createDebugButton(panel, tabX, y, tabWidth, tabHeight, debugText("UI_BurdJournals_DebugWhitelistRecipes", "Recipes"), self, BurdJournals.UI.DebugPanel.onSpawnSubTab, "recipes")
    y = y + tabHeight + 8

    local sectionPadding = 8
    local contentWidth = fullWidth - sectionPadding * 2
    local sectionHeight = 188
    local searchWidth = 150

    local skillsSection = createDebugSectionPanel(panel, padding, y, fullWidth, sectionHeight)
    panel.spawnTabState.panels.skills = skillsSection
    local sy = sectionPadding
    local skillLabelText = (BurdJournals.safeGetText and BurdJournals.safeGetText("UI_BurdJournals_DebugSpawnSkillsGrant", "Skills to grant:")) or "Skills to grant:"
    local spawnSkillLabelX = sectionPadding + 58
    panel.spawnSkillBulkTick = createDebugBulkTick(skillsSection, sectionPadding, sy - 1, 52, 20, debugText("UI_BurdJournals_DebugFilterAll", "All"), self, BurdJournals.UI.DebugPanel.onSpawnSkillBulkToggle, debugText("UI_BurdJournals_DebugToggleAllSpawnSkills", "Toggle all visible spawn skills."))
    panel.spawnSkillSectionLabel = ISLabel:new(spawnSkillLabelX, sy + 2, 18, skillLabelText, 0.9, 0.9, 0.7, 1, UIFont.Small, true)
    panel.spawnSkillSectionLabel:initialise()
    panel.spawnSkillSectionLabel:instantiate()
    skillsSection:addChild(panel.spawnSkillSectionLabel)
    local spawnSkillSearchX = math.max(220, contentWidth - (searchWidth + 6))
    panel.spawnSkillSearch = ISTextEntryBox:new("", spawnSkillSearchX, sy, searchWidth, 20)
    panel.spawnSkillSearch:initialise()
    panel.spawnSkillSearch:instantiate()
    panel.spawnSkillSearch.font = UIFont.Small
    panel.spawnSkillSearch:setTooltip(debugText("UI_BurdJournals_DebugFilterSkills", "Filter skills..."))
    panel.spawnSkillSearch.onTextChange = function()
        BurdJournals.UI.DebugPanel.filterSpawnSkillList(self)
    end
    skillsSection:addChild(panel.spawnSkillSearch)
    panel.spawnSkillSourceFilter = createSectionSourceFilterStrip(skillsSection, self, skillLabelText, spawnSkillSearchX, sy, sectionPadding, BurdJournals.UI.DebugPanel.filterSpawnSkillList, debugText("UI_BurdJournals_DebugFilterSpawnSkillsSource", "Filter spawn skills by source."), spawnSkillLabelX)
    sy = sy + 24
    panel.skillList = ISScrollingListBox:new(sectionPadding, sy, contentWidth, 96)
    panel.skillList:initialise()
    panel.skillList:instantiate()
    panel.skillList.itemheight = 30
    panel.skillList.backgroundColor = {r=0.1, g=0.1, b=0.12, a=1}
    panel.skillList.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    panel.skillList.doDrawItem = BurdJournals.UI.DebugPanel.drawSkillItem
    panel.skillList.onMouseDown = BurdJournals.UI.DebugPanel.onSkillListClick
    panel.skillList.parentPanel = self
    skillsSection:addChild(panel.skillList)

    panel.levelLabel = ISLabel:new(sectionPadding, sy + 102, 18, debugText("UI_BurdJournals_DebugLevelDefault", "Level (default):"), 0.8, 0.8, 0.8, 1, UIFont.Small, true)
    panel.levelLabel:initialise()
    panel.levelLabel:instantiate()
    skillsSection:addChild(panel.levelLabel)

    panel.levelButtons = {}
    local lvlX = sectionPadding + 80
    for lvl = 0, 10 do
        local btn = ISButton:new(lvlX, sy + 100, 22, 20, tostring(lvl), self, BurdJournals.UI.DebugPanel.onLevelSelect)
        btn:initialise()
        btn:instantiate()
        btn.font = UIFont.Small
        btn.internal = lvl
        btn.textColor = {r=1, g=1, b=1, a=1}
        btn.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
        btn.backgroundColor = lvl == 10 and {r=0.3, g=0.5, b=0.4, a=1} or {r=0.2, g=0.2, b=0.25, a=1}
        skillsSection:addChild(btn)
        panel.levelButtons[lvl] = btn
        lvlX = lvlX + 24
    end

    panel.extraXPLabel = ISLabel:new(sectionPadding, sy + 126, 18, debugText("UI_BurdJournals_DebugExtraXP", "Extra XP:"), 0.8, 0.8, 0.8, 1, UIFont.Small, true)
    panel.extraXPLabel:initialise()
    panel.extraXPLabel:instantiate()
    skillsSection:addChild(panel.extraXPLabel)

    panel.extraXPEntry = ISTextEntryBox:new("0", sectionPadding + 60, sy + 124, 60, 20)
    panel.extraXPEntry:initialise()
    panel.extraXPEntry:instantiate()
    panel.extraXPEntry.font = UIFont.Small
    panel.extraXPEntry:setOnlyNumbers(true)
    panel.extraXPEntry.backgroundColor = {r=0.15, g=0.15, b=0.18, a=1}
    panel.extraXPEntry.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    panel.extraXPEntry.onTextChange = function()
        panel.extraXPPendingUpdate = true
    end
    skillsSection:addChild(panel.extraXPEntry)

    panel.extraXPRange = ISLabel:new(sectionPadding + 125, sy + 126, 18, "(0-149)", 0.6, 0.7, 0.6, 1, UIFont.Small, true)
    panel.extraXPRange:initialise()
    panel.extraXPRange:instantiate()
    skillsSection:addChild(panel.extraXPRange)

    local traitsSection = createDebugSectionPanel(panel, padding, y, fullWidth, sectionHeight)
    panel.spawnTabState.panels.traits = traitsSection
    local ty = sectionPadding
    local traitLabelText = (BurdJournals.safeGetText and BurdJournals.safeGetText("UI_BurdJournals_DebugSpawnTraitsGrant", "Traits to grant:")) or "Traits to grant:"
    local spawnTraitLabelX = sectionPadding + 58
    panel.spawnTraitBulkTick = createDebugBulkTick(traitsSection, sectionPadding, ty - 1, 52, 20, debugText("UI_BurdJournals_DebugFilterAll", "All"), self, BurdJournals.UI.DebugPanel.onSpawnTraitBulkToggle, debugText("UI_BurdJournals_DebugToggleAllSpawnTraits", "Toggle all visible spawn traits."))
    panel.spawnTraitSectionLabel = ISLabel:new(spawnTraitLabelX, ty + 2, 18, traitLabelText, 0.9, 0.9, 0.7, 1, UIFont.Small, true)
    panel.spawnTraitSectionLabel:initialise()
    panel.spawnTraitSectionLabel:instantiate()
    traitsSection:addChild(panel.spawnTraitSectionLabel)
    local spawnTraitSearchX = math.max(220, contentWidth - (searchWidth + 6))
    panel.spawnTraitSearch = ISTextEntryBox:new("", spawnTraitSearchX, ty, searchWidth, 20)
    panel.spawnTraitSearch:initialise()
    panel.spawnTraitSearch:instantiate()
    panel.spawnTraitSearch.font = UIFont.Small
    panel.spawnTraitSearch:setTooltip(debugText("UI_BurdJournals_DebugFilterTraits", "Filter traits..."))
    panel.spawnTraitSearch.onTextChange = function()
        BurdJournals.UI.DebugPanel.filterSpawnTraitList(self)
    end
    traitsSection:addChild(panel.spawnTraitSearch)
    panel.spawnTraitPolarityFilter = createDebugTraitPolarityFilter(traitsSection, math.max(sectionPadding, spawnTraitSearchX - 92), ty, self, BurdJournals.UI.DebugPanel.filterSpawnTraitList, debugText("UI_BurdJournals_DebugFilterSpawnTraitsPolarity", "Filter spawn traits by positive/negative polarity."))
    panel.spawnTraitSourceFilter = createSectionSourceFilterStrip(traitsSection, self, traitLabelText, spawnTraitSearchX, ty, sectionPadding, BurdJournals.UI.DebugPanel.filterSpawnTraitList, debugText("UI_BurdJournals_DebugFilterSpawnTraitsSource", "Filter spawn traits by source."), spawnTraitLabelX)
    ty = ty + 24
    panel.traitList = ISScrollingListBox:new(sectionPadding, ty, contentWidth, 132)
    panel.traitList:initialise()
    panel.traitList:instantiate()
    panel.traitList.itemheight = 30
    panel.traitList.backgroundColor = {r=0.1, g=0.1, b=0.12, a=1}
    panel.traitList.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    panel.traitList.doDrawItem = BurdJournals.UI.DebugPanel.drawTraitItem
    panel.traitList.onMouseDown = BurdJournals.UI.DebugPanel.onTraitListClick
    panel.traitList.parentPanel = self
    traitsSection:addChild(panel.traitList)

    local recipesSection = createDebugSectionPanel(panel, padding, y, fullWidth, sectionHeight)
    panel.spawnTabState.panels.recipes = recipesSection
    local ry = sectionPadding
    local recipeLabelText = (BurdJournals.safeGetText and BurdJournals.safeGetText("UI_BurdJournals_DebugSpawnRecipesGrant", "Recipes to grant:")) or "Recipes to grant:"
    local spawnRecipeLabelX = sectionPadding + 58
    panel.spawnRecipeBulkTick = createDebugBulkTick(recipesSection, sectionPadding, ry - 1, 52, 20, debugText("UI_BurdJournals_DebugFilterAll", "All"), self, BurdJournals.UI.DebugPanel.onSpawnRecipeBulkToggle, debugText("UI_BurdJournals_DebugToggleAllSpawnRecipes", "Toggle all visible spawn recipes."))
    panel.spawnRecipeSectionLabel = ISLabel:new(spawnRecipeLabelX, ry + 2, 18, recipeLabelText, 0.9, 0.9, 0.7, 1, UIFont.Small, true)
    panel.spawnRecipeSectionLabel:initialise()
    panel.spawnRecipeSectionLabel:instantiate()
    recipesSection:addChild(panel.spawnRecipeSectionLabel)
    local spawnRecipeSearchX = math.max(220, contentWidth - (searchWidth + 6))
    panel.spawnRecipeSearch = ISTextEntryBox:new("", spawnRecipeSearchX, ry, searchWidth, 20)
    panel.spawnRecipeSearch:initialise()
    panel.spawnRecipeSearch:instantiate()
    panel.spawnRecipeSearch.font = UIFont.Small
    panel.spawnRecipeSearch:setTooltip(debugText("UI_BurdJournals_DebugFilterRecipes", "Filter recipes..."))
    panel.spawnRecipeSearch.onTextChange = function()
        BurdJournals.UI.DebugPanel.filterSpawnRecipeList(self)
    end
    recipesSection:addChild(panel.spawnRecipeSearch)
    panel.spawnRecipeSourceFilter = createSectionSourceFilterStrip(recipesSection, self, recipeLabelText, spawnRecipeSearchX, ry, sectionPadding, BurdJournals.UI.DebugPanel.filterSpawnRecipeList, debugText("UI_BurdJournals_DebugFilterSpawnRecipesSource", "Filter spawn recipes by source."), spawnRecipeLabelX)
    ry = ry + 24
    panel.recipeList = ISScrollingListBox:new(sectionPadding, ry, contentWidth, 132)
    panel.recipeList:initialise()
    panel.recipeList:instantiate()
    panel.recipeList.itemheight = 30
    panel.recipeList.backgroundColor = {r=0.1, g=0.1, b=0.12, a=1}
    panel.recipeList.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    panel.recipeList.doDrawItem = BurdJournals.UI.DebugPanel.drawSpawnRecipeItem
    panel.recipeList.onMouseDown = BurdJournals.UI.DebugPanel.onSpawnRecipeListClick
    panel.recipeList.parentPanel = self
    recipesSection:addChild(panel.recipeList)

    for _, row in ipairs(buildDebugSpawnSkillRows()) do
        panel.skillList:addItem(row.displayName, {
            name = row.name,
            displayName = row.displayName,
            category = row.category,
            isPassive = row.isPassive,
            isVanilla = row.isVanilla,
            source = row.source,
            sourceId = row.sourceId,
            selected = false,
            level = panel.defaultLevel,
            extraXP = 0,
        })
    end

    for _, row in ipairs(buildDebugSpawnTraitRows()) do
        panel.traitList:addItem(row.displayName, {
            id = row.id,
            name = row.id,
            displayName = row.displayName,
            isPositive = row.isPositive,
            isPassiveSkillTrait = row.isPassiveSkillTrait,
            source = row.source,
            sourceId = row.sourceId,
            traitTexture = row.traitTexture,
            selected = false,
        })
    end

    local spawnRecipeRows = buildDebugRecipeRows(self.player, true, false)
    for _, row in ipairs(spawnRecipeRows) do
        row.recipeTexture = getDebugRecipeTexture()
        row.magazineTexture = getDebugMagazineTexture(row.magazineSource)
        row.magazineDisplayName = row.magazineDisplayName or (row.magazineSource and BurdJournals.getMagazineDisplayName and BurdJournals.getMagazineDisplayName(row.magazineSource) or nil)
        row.selected = false
        panel.recipeList:addItem(row.displayName, row)
    end

    refreshDebugSourceFilterStrip(panel.spawnSkillSourceFilter, panel.skillList and panel.skillList.items or nil)
    refreshDebugSourceFilterStrip(panel.spawnTraitSourceFilter, panel.traitList and panel.traitList.items or nil)
    refreshDebugSourceFilterStrip(panel.spawnRecipeSourceFilter, panel.recipeList and panel.recipeList.items or nil)
    setDebugSubTabState(panel.spawnTabState, "skills")

    y = y + sectionHeight + 8
    
    -- Selected summary
    local summaryLabel = ISLabel:new(padding, y, 18, debugText("UI_BurdJournals_DebugSelectedLabel", "Selected:"), 0.7, 0.8, 0.9, 1, UIFont.Small, true)
    summaryLabel:initialise()
    summaryLabel:instantiate()
    panel:addChild(summaryLabel)
    panel.summaryLabelRef = summaryLabel
    y = y + 18
    
    panel.summaryText = ISLabel:new(padding, y, 18, debugText("UI_BurdJournals_DebugNoItemsSelected", "No items selected"), 0.6, 0.7, 0.6, 1, UIFont.Small, true)
    panel.summaryText:initialise()
    panel.summaryText:instantiate()
    panel:addChild(panel.summaryText)
    y = y + 25
    
    -- Clear selections button
    panel.clearBtn = ISButton:new(padding, y, 100, 22, debugText("UI_BurdJournals_DebugClearAll", "Clear All"), self, BurdJournals.UI.DebugPanel.onClearSelections)
    panel.clearBtn:initialise()
    panel.clearBtn:instantiate()
    panel.clearBtn.font = UIFont.Small
    panel.clearBtn.textColor = {r=1, g=0.8, b=0.8, a=1}
    panel.clearBtn.borderColor = {r=0.5, g=0.3, b=0.3, a=1}
    panel.clearBtn.backgroundColor = {r=0.3, g=0.15, b=0.15, a=1}
    panel:addChild(panel.clearBtn)
    
    -- Quick preset buttons
    local presetX = padding + 110
    panel.presetButtons = {}
    local presets = {
        {name = debugText("UI_BurdJournals_DebugPresetMaxPassive", "Max Passive"), preset = "maxpassive"},
        {name = debugText("UI_BurdJournals_DebugPresetAllPositiveTraits", "All + Traits"), preset = "allpositive"},
        {name = debugText("UI_BurdJournals_DebugPresetAllNegativeTraits", "All - Traits"), preset = "allnegative"},
    }
    for _, presetDef in ipairs(presets) do
        local btn = ISButton:new(presetX, y, 95, 22, presetDef.name, self, BurdJournals.UI.DebugPanel.onPresetClick)
        btn:initialise()
        btn:instantiate()
        btn.font = UIFont.Small
        btn.internal = presetDef.preset
        btn.textColor = {r=1, g=1, b=1, a=1}
        btn.borderColor = {r=0.5, g=0.4, b=0.2, a=1}
        btn.backgroundColor = {r=0.3, g=0.25, b=0.15, a=1}
        panel:addChild(btn)
        table.insert(panel.presetButtons, btn)
        presetX = presetX + 100
    end

    y = y + 35
    
    panel.contentEndY = y
    
    -- ====== Spawn Button ======
    local spawnBtn = ISButton:new(padding, y, fullWidth, 30, debugText("UI_BurdJournals_DebugSpawnJournal", "SPAWN JOURNAL"), self, BurdJournals.UI.DebugPanel.onSpawnClick)
    spawnBtn:initialise()
    spawnBtn:instantiate()
    spawnBtn.font = UIFont.Medium
    spawnBtn.textColor = {r=1, g=1, b=1, a=1}
    spawnBtn.borderColor = {r=0.3, g=0.7, b=0.4, a=1}
    spawnBtn.backgroundColor = {r=0.15, g=0.4, b=0.2, a=1}
    panel:addChild(spawnBtn)
    panel.spawnBtn = spawnBtn
    panel.contentEndY = y
    
    self.spawnPanel = panel
    
    -- Initial visibility update based on default type
    self:updateSpawnPanelVisibility()
end

-- Populate the owner dropdown with online players + "Custom..." option
local function findOwnerOptionIndex(panel, predicate)
    if not panel or not panel.ownerCombo or not predicate then
        return nil
    end
    local optionCount = #panel.ownerCombo.options
    for i = 1, optionCount do
        local data = panel.ownerCombo:getOptionData(i)
        if predicate(data, i) then
            return i
        end
    end
    return nil
end

function BurdJournals.UI.DebugPanel:applySpawnOwnerDefault(panel, journalType)
    if not panel or not panel.ownerCombo then
        return
    end
    local jType = tostring(journalType or panel.selectedType or "filled")
    local isFilled = jType == "filled"
    local selectedIndex = panel.ownerCombo.selected or 1
    local selectedData = panel.ownerCombo:getOptionData(selectedIndex)

    if isFilled then
        if selectedData and selectedData.isPlayer then
            return
        end
        local playerIndex = findOwnerOptionIndex(panel, function(data)
            return type(data) == "table" and data.isPlayer == true
        end)
        local noneIndex = findOwnerOptionIndex(panel, function(data)
            return type(data) == "table" and data.isNone == true
        end)
        panel.ownerCombo.selected = playerIndex or noneIndex or 1
        return
    end

    if selectedData and selectedData.isNone then
        return
    end
    local noneIndex = findOwnerOptionIndex(panel, function(data)
        return type(data) == "table" and data.isNone == true
    end)
    if noneIndex then
        panel.ownerCombo.selected = noneIndex
    end
end

function BurdJournals.UI.DebugPanel:populateOwnerCombo(panel)
    panel.ownerCombo:clear()

    local noneLabel = (BurdJournals.safeGetText and BurdJournals.safeGetText("UI_BurdJournals_DebugSpawnOwnerNone", "None")) or "None"
    panel.ownerCombo:addOptionWithData(noneLabel, {
        isNone = true
    })

    local addedCount = 0
    
    -- Add online players
    local onlinePlayers = getOnlinePlayers()
    if onlinePlayers then
        for i = 0, onlinePlayers:size() - 1 do
            local p = onlinePlayers:get(i)
            if p then
                local username = p:getUsername()
                local charName = p:getDescriptor():getForename() .. " " .. p:getDescriptor():getSurname()
                local displayText = charName .. " (" .. username .. ")"
                panel.ownerCombo:addOptionWithData(displayText, {
                    isPlayer = true,
                    username = username,
                    steamId = BurdJournals.getPlayerSteamId(p),
                    characterName = charName,
                    player = p
                })
                addedCount = addedCount + 1
            end
        end
    end
    
    -- Add single player if no online players (SP mode)
    if addedCount == 0 then
        local p = getPlayer()
        if p then
            local charName = p:getDescriptor():getForename() .. " " .. p:getDescriptor():getSurname()
            local username = p:getUsername()
            if not username then username = "Player" end
            panel.ownerCombo:addOptionWithData(charName, {
                isPlayer = true,
                username = username,
                steamId = BurdJournals.getPlayerSteamId(p),
                characterName = charName,
                player = p
            })
        end
    end
    
    -- Add "Custom..." option at the end
    panel.ownerCombo:addOptionWithData(
        (BurdJournals.safeGetText and BurdJournals.safeGetText("UI_BurdJournals_DebugSpawnOwnerCustom", "Custom...")) or "Custom...",
        {
        isCustom = true
    })

    panel.ownerCombo.selected = 1
end

-- Handle owner combo box change
function BurdJournals.UI.DebugPanel.onOwnerComboChange(self)
    -- Trigger full visibility/layout update
    self:updateSpawnPanelVisibility()
end

-- Handle profession combo box change
function BurdJournals.UI.DebugPanel.onProfessionComboChange(self)
    -- Trigger full visibility/layout update
    self:updateSpawnPanelVisibility()
end

function BurdJournals.UI.DebugPanel:requestLoreTemplateOptions()
    BurdJournals.UI.DebugPanel.requestLoreTemplateOptionsForPanel(self.spawnPanel or self)
end

function BurdJournals.UI.DebugPanel.onLoreModeComboChange(self)
    if self and self.requestLoreTemplateOptions then
        self:requestLoreTemplateOptions()
    else
        BurdJournals.UI.DebugPanel.requestLoreTemplateOptionsForPanel(self)
    end
    self:updateSpawnPanelVisibility()
end

local function buildPositiveTraitDebugTargets()
    local targets = {}
    local seen = {}
    local allTraits = BurdJournals.getPositiveTraits and BurdJournals.getPositiveTraits(true) or BurdJournals.UI.DebugPanel.getAvailableTraits()
    for _, traitId in ipairs(allTraits or {}) do
        local id = tostring(traitId or "")
        local lower = string.lower(id)
        if BurdJournals.UI.DebugPanel.getBulkTraitBucket(id) == "positive" and not seen[lower] then
            seen[lower] = true
            targets[#targets + 1] = {
                id = id,
                label = BurdJournals.UI.DebugPanel.getTraitDisplayName(id)
            }
        end
    end
    table.sort(targets, function(a, b)
        return string.lower(a.label) < string.lower(b.label)
    end)
    return targets
end

local function buildNegativeTraitDebugTargets()
    local targets = {}
    local seen = {}
    local allTraits = BurdJournals.getNegativeTraits and BurdJournals.getNegativeTraits(true) or BurdJournals.REMOVABLE_TRAITS or {}
    for _, traitId in ipairs(allTraits) do
        local id = tostring(traitId or "")
        local lower = string.lower(id)
        if id ~= "" and BurdJournals.UI.DebugPanel.getBulkTraitBucket(id) == "negative" and not seen[lower] then
            seen[lower] = true
            targets[#targets + 1] = {
                id = id,
                label = BurdJournals.UI.DebugPanel.getTraitDisplayName(id)
            }
        end
    end
    table.sort(targets, function(a, b)
        return string.lower(a.label) < string.lower(b.label)
    end)
    return targets
end

local function buildSkillDebugTargets()
    local targets = {}
    local seen = {}
    local skills = BurdJournals.getAllowedSkills and BurdJournals.getAllowedSkills() or {}
    for _, skillName in ipairs(skills) do
        local id = tostring(skillName or "")
        local lower = string.lower(id)
        if id ~= "" and not seen[lower] then
            seen[lower] = true
            targets[#targets + 1] = {
                id = id,
                label = BurdJournals.UI.DebugPanel.getSkillDisplayName(id)
            }
        end
    end
    table.sort(targets, function(a, b)
        return string.lower(a.label) < string.lower(b.label)
    end)
    return targets
end

function BurdJournals.UI.DebugPanel.refreshForceCurseTargetCombo(panel)
    if not panel or not panel.forceCurseCombo or not panel.forceCurseTargetCombo then
        return
    end

    local curseType = panel.forceCurseCombo:getOptionData(panel.forceCurseCombo.selected)
        or panel.forceCurseCombo.options[panel.forceCurseCombo.selected]
    local targetCombo = panel.forceCurseTargetCombo
    targetCombo:clear()
    panel.forceCurseTargetType = nil

    if curseType == "gain_negative_trait" then
        panel.forceCurseTargetType = "trait"
        targetCombo:addOptionWithData("Contextual (Negative Trait)", nil)
        for _, entry in ipairs(buildNegativeTraitDebugTargets()) do
            targetCombo:addOptionWithData(entry.label, entry.id)
        end
    elseif curseType == "lose_positive_trait" then
        panel.forceCurseTargetType = "trait"
        targetCombo:addOptionWithData("Contextual (Positive Trait)", nil)
        for _, entry in ipairs(buildPositiveTraitDebugTargets()) do
            targetCombo:addOptionWithData(entry.label, entry.id)
        end
    elseif curseType == "lose_skill_level" then
        panel.forceCurseTargetType = "skill"
        targetCombo:addOptionWithData("Contextual (Skill)", nil)
        for _, entry in ipairs(buildSkillDebugTargets()) do
            targetCombo:addOptionWithData(entry.label, entry.id)
        end
    end

    if panel.forceCurseTargetType then
        setComboSelectedCompat(targetCombo, 1)
        targetCombo:setVisible(true)
    else
        targetCombo:setVisible(false)
    end
end

function BurdJournals.UI.DebugPanel.onForceCurseComboChange(self)
    BurdJournals.UI.DebugPanel.refreshForceCurseTargetCombo(self.spawnPanel)
end

local function isSpawnSkillAllowedForType(journalType, skillName)
    if not skillName then
        return false
    end
    local isPassive = BurdJournals.isPassiveSkill and BurdJournals.isPassiveSkill(skillName) or (skillName == "Fitness" or skillName == "Strength")
    if not isPassive then
        return true
    end
    if not BurdJournals.isSkillEnabledForJournal then
        return true
    end
    local context = {isPlayerCreated = (journalType == "filled")}
    return BurdJournals.isSkillEnabledForJournal(context, skillName)
end

local function sanitizeSpawnSkillSelections(panel, journalType)
    if not panel or not panel.skillList then
        return
    end
    local focusedStillValid = false
    for _, itemData in ipairs(panel.skillList.items) do
        local data = itemData and itemData.item
        if data and data.name then
            local allowed = isSpawnSkillAllowedForType(journalType, data.name)
            if not allowed then
                data.selected = false
                data.hiddenBySandbox = true
                panel.selectedSkills[data.name] = nil
                if panel.focusedSkill == data.name then
                    panel.focusedSkill = nil
                end
            else
                data.hiddenBySandbox = false
                if panel.focusedSkill == data.name and data.selected then
                    focusedStillValid = true
                end
            end
        end
    end
    if panel.focusedSkill and not focusedStillValid then
        panel.focusedSkill = nil
    end
end

local function normalizeDebugOriginMode(mode)
    local value = tostring(mode or "auto")
    if value == "personal" or value == "found" or value == "world" or value == "zombie" then
        return value
    end
    return "auto"
end

local function getDefaultDebugOriginModeForType(journalType)
    local t = tostring(journalType or "filled")
    if t == "worn" then
        return "found"
    end
    if t == "bloody" or t == "cursed" then
        return "zombie"
    end
    return "personal"
end

local function resolveSpawnOriginMode(panel, journalType)
    local selected = normalizeDebugOriginMode(panel and panel.spawnOriginMode or "auto")
    if selected == "auto" then
        return getDefaultDebugOriginModeForType(journalType or (panel and panel.selectedType))
    end
    return selected
end

local function getOriginModeLabel(mode)
    local value = normalizeDebugOriginMode(mode)
    if value == "personal" then
        return getText("Tooltip_BurdJournals_OriginPersonal") or "Origin: Personal"
    elseif value == "zombie" then
        return getText("Tooltip_BurdJournals_OriginZombie") or "Origin: Recovered from zombie"
    elseif value == "world" then
        return getText("Tooltip_BurdJournals_OriginWorld") or "Origin: Found in world"
    elseif value == "found" then
        return getText("Tooltip_BurdJournals_OriginFound") or "Origin: Found"
    end
    return getText("Tooltip_BurdJournals_OriginFound") or "Origin: Found"
end

local function inferJournalOriginMode(journalData)
    if type(journalData) ~= "table" then
        return "found"
    end
    local sourceType = type(journalData.sourceType) == "string" and string.lower(journalData.sourceType) or ""
    if sourceType == "personal" then
        return "personal"
    elseif sourceType == "zombie" then
        return "zombie"
    elseif sourceType == "world" then
        return "world"
    elseif sourceType == "found" then
        return "found"
    end
    if journalData.isPlayerCreated == true then
        return "personal"
    end
    if journalData.wasFromBloody == true or journalData.hasBloodyOrigin == true then
        return "zombie"
    end
    return "found"
end

local function applyOriginModeToJournalData(journalData, originMode)
    if type(journalData) ~= "table" then
        return
    end
    local mode = normalizeDebugOriginMode(originMode)
    if mode == "auto" then
        mode = "found"
    end
    journalData.originMode = mode
    if mode == "personal" then
        journalData.isPlayerCreated = true
        journalData.sourceType = "personal"
    elseif mode == "zombie" then
        journalData.isPlayerCreated = false
        journalData.sourceType = "zombie"
    elseif mode == "world" then
        journalData.isPlayerCreated = false
        journalData.sourceType = "world"
    else
        journalData.isPlayerCreated = false
        journalData.sourceType = "found"
    end
end

local function setDebugWidgetY(widget, y)
    if not widget then
        return
    end
    if widget.setY then
        widget:setY(y)
    else
        widget.y = y
    end
end

local function setDebugWidgetHeight(widget, height)
    if not widget then
        return
    end
    if widget.setHeight then
        widget:setHeight(height)
    else
        widget.height = height
    end
end

local function setDebugExtensionControlsVisible(panel, activeType)
    if not panel or type(panel.debugExtensionControls) ~= "table" then
        return
    end
    for typeId, section in pairs(panel.debugExtensionControls) do
        local visible = tostring(typeId) == tostring(activeType)
        if type(section) == "table" then
            for _, widget in ipairs(section.widgets or {}) do
                if widget and widget.setVisible then
                    widget:setVisible(visible)
                end
            end
            if section.panel and section.panel.setVisible then
                section.panel:setVisible(visible)
            end
        end
    end
end

local function layoutDebugExtensionControls(panel, journalType, startY)
    if not panel or type(panel.debugExtensionControls) ~= "table" then
        return startY
    end
    setDebugExtensionControlsVisible(panel, journalType)
    local section = panel.debugExtensionControls[tostring(journalType or "")]
    if type(section) ~= "table" then
        return startY
    end
    local def = BurdJournals.getDebugJournalType and BurdJournals.getDebugJournalType(journalType) or nil
    if type(def) == "table" and type(def.layoutControls) == "function" then
        local result = def.layoutControls(panel, section, startY, {
            journalType = journalType,
            setY = setDebugWidgetY,
            setHeight = setDebugWidgetHeight,
        })
        return tonumber(result) or (startY + (tonumber(section.height) or 0))
    end
    if section.panel then
        setDebugWidgetY(section.panel, startY)
    end
    return startY + (tonumber(section.height) or 0)
end

local function setSpawnContentVisibility(panel, visible)
    if not panel then
        return
    end

    if panel.spawnTabState then
        for _, button in pairs(panel.spawnTabState.buttons or {}) do
            if button then
                button:setVisible(visible)
            end
        end
        for id, subPanel in pairs(panel.spawnTabState.panels or {}) do
            if subPanel and subPanel.setVisible then
                subPanel:setVisible(visible and id == (panel.spawnTabState.current or "skills"))
            end
        end
    end

    if panel.summaryLabelRef then panel.summaryLabelRef:setVisible(visible) end
    if panel.summaryText then panel.summaryText:setVisible(visible) end
    if panel.clearBtn then panel.clearBtn:setVisible(visible) end
    if panel.presetButtons then
        for _, btn in ipairs(panel.presetButtons) do
            if btn then btn:setVisible(visible) end
        end
    end
end

local function layoutSpawnContentPanels(panel, startY)
    if not (panel and panel.spawnTabState) then
        return startY
    end

    local padding = 10
    local fullWidth = panel.width - padding * 2
    local tabWidth = 84
    local tabHeight = 22
    local tabSpacing = 6
    local sectionPadding = 8
    local contentWidth = fullWidth - sectionPadding * 2
    local bottomReserve = 152
    local availableSectionHeight = math.floor(panel.height - startY - bottomReserve)
    local sectionHeight = math.max(88, math.min(220, availableSectionHeight))
    panel.spawnContentSectionHeight = sectionHeight
    panel.contentStartY = startY

    local tabX = padding
    setDebugWidgetY(panel.spawnTabState.buttons.skills, startY)
    if panel.spawnTabState.buttons.skills then panel.spawnTabState.buttons.skills:setX(tabX) end
    tabX = tabX + tabWidth + tabSpacing
    setDebugWidgetY(panel.spawnTabState.buttons.traits, startY)
    if panel.spawnTabState.buttons.traits then panel.spawnTabState.buttons.traits:setX(tabX) end
    tabX = tabX + tabWidth + tabSpacing
    setDebugWidgetY(panel.spawnTabState.buttons.recipes, startY)
    if panel.spawnTabState.buttons.recipes then panel.spawnTabState.buttons.recipes:setX(tabX) end

    local sectionY = startY + tabHeight + 8
    for _, subPanel in pairs(panel.spawnTabState.panels or {}) do
        if subPanel then
            if subPanel.setX then subPanel:setX(padding) end
            setDebugWidgetY(subPanel, sectionY)
            if subPanel.setWidth then subPanel:setWidth(fullWidth) end
            setDebugWidgetHeight(subPanel, sectionHeight)
        end
    end

    local skillListY = sectionPadding + 24
    local skillListHeight = math.max(42, sectionHeight - 92)
    if panel.skillList then
        setDebugWidgetY(panel.skillList, skillListY)
        if panel.skillList.setWidth then panel.skillList:setWidth(contentWidth) end
        setDebugWidgetHeight(panel.skillList, skillListHeight)
    end
    local skillControlsY = skillListY + skillListHeight + 6
    if panel.levelLabel then setDebugWidgetY(panel.levelLabel, skillControlsY + 2) end
    if panel.levelButtons then
        local lvlX = sectionPadding + 80
        for lvl = 0, 10 do
            local btn = panel.levelButtons[lvl]
            if btn then
                if btn.setX then btn:setX(lvlX) end
                setDebugWidgetY(btn, skillControlsY)
            end
            lvlX = lvlX + 24
        end
    end
    local extraXPY = skillControlsY + 24
    if panel.extraXPLabel then setDebugWidgetY(panel.extraXPLabel, extraXPY + 2) end
    if panel.extraXPEntry then setDebugWidgetY(panel.extraXPEntry, extraXPY) end
    if panel.extraXPRange then setDebugWidgetY(panel.extraXPRange, extraXPY + 2) end

    local genericListHeight = math.max(52, sectionHeight - 40)
    if panel.traitList then
        setDebugWidgetY(panel.traitList, skillListY)
        if panel.traitList.setWidth then panel.traitList:setWidth(contentWidth) end
        setDebugWidgetHeight(panel.traitList, genericListHeight)
    end
    if panel.recipeList then
        setDebugWidgetY(panel.recipeList, skillListY)
        if panel.recipeList.setWidth then panel.recipeList:setWidth(contentWidth) end
        setDebugWidgetHeight(panel.recipeList, genericListHeight)
    end

    return sectionY + sectionHeight + 8
end

-- Update spawn panel visibility based on selected journal type
function BurdJournals.UI.DebugPanel:updateSpawnPanelVisibility()
    local panel = self.spawnPanel
    if not panel then return end
    
    -- Ensure all required elements exist before proceeding
    if not panel.ownerLabel or not panel.ownerCombo or not panel.customNameEntry then
        return  -- Panel not fully initialized yet
    end
    
    local journalType = panel.selectedType or "blank"
    local debugTypeDef = BurdJournals.getDebugJournalType and BurdJournals.getDebugJournalType(journalType) or nil
    local isExtensionType = type(debugTypeDef) == "table" and DEBUG_BUILTIN_JOURNAL_TYPES[journalType] ~= true
    local isBlank = (journalType == "blank")
    local isFilled = (journalType == "filled")
    local isCursed = (journalType == "cursed")
    local isYuletide = (journalType == "yuletide")
    local isWornOrBloody = (journalType == "worn" or journalType == "bloody")
    local supportsGeneratedLore = (isWornOrBloody == true or isCursed == true or isYuletide == true)
        or (isExtensionType and debugTypeDef.supportsGeneratedLore == true)
    
    -- Check combo selections (with nil safety)
    local selectedData = nil
    if panel.ownerCombo and panel.ownerCombo.selected and panel.ownerCombo.selected > 0 then
        selectedData = panel.ownerCombo:getOptionData(panel.ownerCombo.selected)
    end
    local isCustomOwner = (selectedData ~= nil and selectedData.isCustom == true)
    local profSelected = 1
    if panel.professionCombo and panel.professionCombo.selected then
        profSelected = panel.professionCombo.selected
    end
    local isCustomProf = (profSelected == 3)  -- Index 3 is "Custom..."
    
    -- Determine visibility for each section (explicitly boolean)
    local showOrigin = (isBlank == false and (not isExtensionType or debugTypeDef.showOrigin ~= false))
    local showFilledState = (isFilled == true)
    local showOwner = (isFilled == true) or (isExtensionType and debugTypeDef.showOwner == true)
    local showCustomName = (showOwner == true and isCustomOwner == true)
    local showProfession = (isWornOrBloody == true) or (isExtensionType and debugTypeDef.showProfession == true)
    local showCustomProf = (isWornOrBloody == true and isCustomProf == true)
    local showFlavor = (isBlank == false and (not isExtensionType or debugTypeDef.showFlavor ~= false))
    local loreMode = getSpawnLoreMode(panel)
    local showLoreMode = (supportsGeneratedLore == true)
    local showCustomLore = (showLoreMode == true and loreMode == "manual")
    local showSpawnMeta = (isBlank == false and (not isExtensionType or debugTypeDef.showAge ~= false))
    local showYuletideControls = (isYuletide == true)
    local showCursedControls = (isCursed == true)
    if showCursedControls then
        BurdJournals.UI.DebugPanel.refreshForceCurseTargetCombo(panel)
    end
    local showForceCurseTarget = showCursedControls and panel.forceCurseTargetType ~= nil
    local showForgetSlotToggle = (isBlank == false and (isWornOrBloody == true or isCursed == true or isYuletide == true))
        or (isExtensionType and debugTypeDef.showForgetSlotToggle == true)
    local showContent = (isBlank == false and (not isExtensionType or debugTypeDef.showContent ~= false))
    
    -- Set visibility (with nil guards)
    if panel.spawnOriginLabel then panel.spawnOriginLabel:setVisible(showOrigin) end
    if panel.spawnOriginCombo then panel.spawnOriginCombo:setVisible(showOrigin) end
    if panel.filledStateLabel then panel.filledStateLabel:setVisible(showFilledState) end
    if panel.filledStateCombo then panel.filledStateCombo:setVisible(showFilledState) end
    if panel.ownerLabel then panel.ownerLabel:setVisible(showOwner) end
    if panel.ownerCombo then panel.ownerCombo:setVisible(showOwner) end
    if panel.customNameLabel then panel.customNameLabel:setVisible(showCustomName) end
    if panel.customNameEntry then panel.customNameEntry:setVisible(showCustomName) end
    if panel.professionLabel then panel.professionLabel:setVisible(showProfession) end
    if panel.professionCombo then panel.professionCombo:setVisible(showProfession) end
    if panel.customProfLabel then panel.customProfLabel:setVisible(showCustomProf) end
    if panel.customProfEntry then panel.customProfEntry:setVisible(showCustomProf) end
    if panel.flavorLabel then panel.flavorLabel:setVisible(showFlavor) end
    if panel.flavorEntry then panel.flavorEntry:setVisible(showFlavor) end
    if panel.loreModeLabel then panel.loreModeLabel:setVisible(showLoreMode) end
    if panel.loreModeCombo then panel.loreModeCombo:setVisible(showLoreMode) end
    if panel.loreNoteLabel then panel.loreNoteLabel:setVisible(showCustomLore) end
    if panel.loreTemplateCombo then panel.loreTemplateCombo:setVisible(showCustomLore) end
    if panel.ageLabel then panel.ageLabel:setVisible(showSpawnMeta) end
    if panel.ageEntry then panel.ageEntry:setVisible(showSpawnMeta) end
    if panel.yuletideStateLabel then panel.yuletideStateLabel:setVisible(showYuletideControls) end
    if panel.yuletideStateCombo then panel.yuletideStateCombo:setVisible(showYuletideControls) end
    if panel.yuletideWrappedVariantLabel then panel.yuletideWrappedVariantLabel:setVisible(showYuletideControls) end
    if panel.yuletideWrappedVariantCombo then panel.yuletideWrappedVariantCombo:setVisible(showYuletideControls) end
    if panel.yuletideRewardTierLabel then panel.yuletideRewardTierLabel:setVisible(showYuletideControls) end
    if panel.yuletideRewardTierCombo then panel.yuletideRewardTierCombo:setVisible(showYuletideControls) end
    if panel.cursedStateLabel then panel.cursedStateLabel:setVisible(showCursedControls) end
    if panel.cursedStateCombo then panel.cursedStateCombo:setVisible(showCursedControls) end
    if panel.forceCurseLabel then panel.forceCurseLabel:setVisible(showCursedControls) end
    if panel.forceCurseCombo then panel.forceCurseCombo:setVisible(showCursedControls) end
    if panel.forceCurseTargetCombo then panel.forceCurseTargetCombo:setVisible(showForceCurseTarget) end
    if panel.forgetSlotTick then panel.forgetSlotTick:setVisible(showForgetSlotToggle) end
    
    -- Update owner label text
    if panel.ownerLabel then
        panel.ownerLabel:setName((BurdJournals.safeGetText and BurdJournals.safeGetText("UI_BurdJournals_DebugSpawnOwnerAssign", "Assign to Player:")) or "Assign to Player:")
    end
    
    -- Dynamic Y repositioning based on visibility
    local padding = 10
    local rowHeight = 24
    local y = panel.ownerSectionY or 100  -- Start from owner section base (fallback to 100 if not set)

    if showFilledState then
        if panel.filledStateLabel then panel.filledStateLabel:setY(y) end
        if panel.filledStateCombo then panel.filledStateCombo:setY(y - 2) end
        y = y + rowHeight
    end
    
    -- Owner row
    if showOwner then
        panel.ownerLabel:setY(y)
        panel.ownerCombo:setY(y - 2)
        y = y + rowHeight
    end
    
    -- Custom name row (conditional)
    if showCustomName then
        panel.customNameLabel:setY(y)
        panel.customNameEntry:setY(y - 2)
        y = y + rowHeight
    end
    
    -- Profession row (conditional)
    if showProfession then
        panel.professionLabel:setY(y)
        panel.professionCombo:setY(y - 2)
        y = y + rowHeight
    end
    
    -- Custom profession row (conditional)
    if showCustomProf then
        panel.customProfLabel:setY(y)
        panel.customProfEntry:setY(y - 2)
        y = y + rowHeight
    end
    
    -- Flavor text row
    if showFlavor then
        panel.flavorLabel:setY(y)
        panel.flavorEntry:setY(y - 2)
        y = y + rowHeight
    end

    if showLoreMode then
        if panel.loreModeLabel then panel.loreModeLabel:setY(y) end
        if panel.loreModeCombo then panel.loreModeCombo:setY(y - 2) end
        y = y + rowHeight
    end

    if showCustomLore then
        if panel.loreNoteLabel then panel.loreNoteLabel:setY(y) end
        if panel.loreTemplateCombo then panel.loreTemplateCombo:setY(y - 2) end
        y = y + rowHeight
    end

    if showSpawnMeta then
        if panel.ageLabel then panel.ageLabel:setY(y) end
        if panel.ageEntry then panel.ageEntry:setY(y - 2) end
        y = y + rowHeight
    end

    if showYuletideControls then
        if panel.yuletideStateLabel then panel.yuletideStateLabel:setY(y) end
        if panel.yuletideStateCombo then panel.yuletideStateCombo:setY(y - 2) end
        y = y + rowHeight

        if panel.yuletideWrappedVariantLabel then panel.yuletideWrappedVariantLabel:setY(y) end
        if panel.yuletideWrappedVariantCombo then panel.yuletideWrappedVariantCombo:setY(y - 2) end
        y = y + rowHeight

        if panel.yuletideRewardTierLabel then panel.yuletideRewardTierLabel:setY(y) end
        if panel.yuletideRewardTierCombo then panel.yuletideRewardTierCombo:setY(y - 2) end
        y = y + rowHeight
    end

    if showCursedControls then
        if panel.cursedStateLabel then panel.cursedStateLabel:setY(y) end
        if panel.cursedStateCombo then panel.cursedStateCombo:setY(y - 2) end
        y = y + rowHeight

        if panel.forceCurseLabel then panel.forceCurseLabel:setY(y) end
        if panel.forceCurseCombo then panel.forceCurseCombo:setY(y - 2) end
        if panel.forceCurseTargetCombo then panel.forceCurseTargetCombo:setY(y - 2) end
        y = y + rowHeight

    end

    if showForgetSlotToggle then
        if panel.forgetSlotTick then panel.forgetSlotTick:setY(y - 2) end
        y = y + rowHeight
    end

    y = layoutDebugExtensionControls(panel, journalType, y)
    
    -- Content section (skills / traits / recipes)
    y = y + rowHeight + 4
    setSpawnContentVisibility(panel, showContent)

    if showContent then
        if panel.spawnTabState then
            setDebugSubTabState(panel.spawnTabState, panel.spawnTabState.current or "skills")
        end
        y = layoutSpawnContentPanels(panel, y)

        if panel.summaryLabelRef then panel.summaryLabelRef:setY(y) end
        y = y + 18
        if panel.summaryText then panel.summaryText:setY(y) end
        y = y + 22

        if panel.clearBtn then panel.clearBtn:setY(y) end
        if panel.presetButtons then
            for _, btn in ipairs(panel.presetButtons) do
                if btn then btn:setY(y) end
            end
        end
        y = y + 35
        panel.contentEndY = y
        panel.spawnBtn:setY(y)
    else
        panel.contentEndY = y
        panel.spawnBtn:setY(y + 10)
    end

    if showContent then
        sanitizeSpawnSkillSelections(panel, journalType)
        BurdJournals.UI.DebugPanel.filterSpawnSkillList(self)
        BurdJournals.UI.DebugPanel.filterSpawnTraitList(self)
        BurdJournals.UI.DebugPanel.filterSpawnRecipeList(self)
        BurdJournals.UI.DebugPanel.updateLevelButtons(self)
        BurdJournals.UI.DebugPanel.updateSpawnSummary(self)
    end
    BurdJournals.UI.DebugPanel.updateSpawnSummary(self)
    
    -- Update spawn button text
    if isBlank then
        panel.spawnBtn:setTitle(debugText("UI_BurdJournals_DebugSpawnBlankJournal", "SPAWN BLANK JOURNAL"))
    elseif isCursed and panel.cursedStateCombo then
        if panel.cursedStateCombo.selected == 3 then
            panel.spawnBtn:setTitle(debugText("UI_BurdJournals_DebugSpawnCursedReward", "SPAWN CURSED REWARD"))
        elseif panel.cursedStateCombo.selected == 2 then
            panel.spawnBtn:setTitle(debugText("UI_BurdJournals_DebugSpawnHiddenCursedJournal", "SPAWN HIDDEN CURSED JOURNAL"))
        else
            panel.spawnBtn:setTitle(debugFormatText("UI_BurdJournals_DebugSpawnTypeJournal", "SPAWN %1 JOURNAL", string.upper(journalType)))
        end
    elseif isExtensionType and debugTypeDef and debugTypeDef.spawnButtonLabel then
        panel.spawnBtn:setTitle(tostring(debugTypeDef.spawnButtonLabel))
    else
        panel.spawnBtn:setTitle(debugFormatText("UI_BurdJournals_DebugSpawnTypeJournal", "SPAWN %1 JOURNAL", string.upper(journalType)))
    end
end

function BurdJournals.UI.DebugPanel.refreshSpawnBulkToggles(self)
    local panel = self and self.spawnPanel or nil
    if not panel then
        return
    end
    refreshDebugBulkTickState(panel.spawnSkillBulkTick, panel.skillList, nil, function(row) return row.selected == true end)
    refreshDebugBulkTickState(panel.spawnTraitBulkTick, panel.traitList, nil, function(row) return row.selected == true end)
    refreshDebugBulkTickState(panel.spawnRecipeBulkTick, panel.recipeList, nil, function(row) return row.selected == true end)
end

function BurdJournals.UI.DebugPanel.onSpawnSkillBulkToggle(self, _index, selected)
    local panel = self and self.spawnPanel or nil
    if not (panel and panel.skillList and panel.selectedSkills) then
        return
    end

    local count = 0
    if selected == true then
        for _, itemData in ipairs(panel.skillList.items or {}) do
            local row = itemData and itemData.item or nil
            if isDebugVisibleBulkRow(row) and row.name then
                row.selected = true
                row.level = panel.defaultLevel
                row.extraXP = panel.defaultExtraXP or 0
                panel.selectedSkills[row.name] = {level = row.level, extraXP = row.extraXP}
                panel.focusedSkill = panel.focusedSkill or row.name
                count = count + 1
            end
        end
        self:setStatus(debugFormatText("UI_BurdJournals_DebugSelectedVisibleSpawnSkills", "Selected %1 visible spawn skill(s)", tostring(count)), {r=0.5, g=0.8, b=1})
    else
        for _, itemData in ipairs(panel.skillList.items or {}) do
            local row = itemData and itemData.item or nil
            if row and row.name then
                row.selected = false
                panel.selectedSkills[row.name] = nil
                if panel.focusedSkill == row.name then
                    panel.focusedSkill = nil
                end
                count = count + 1
            end
        end
        self:setStatus(debugFormatText("UI_BurdJournals_DebugClearedSpawnSkills", "Cleared %1 spawn skill(s)", tostring(count)), {r=0.8, g=0.8, b=0.5})
    end

    self:updateLevelButtons()
    self:updateSpawnSummary()
    BurdJournals.UI.DebugPanel.refreshSpawnBulkToggles(self)
end

function BurdJournals.UI.DebugPanel.onSpawnTraitBulkToggle(self, _index, selected)
    local panel = self and self.spawnPanel or nil
    if not (panel and panel.traitList and panel.selectedTraits) then
        return
    end

    local count = 0
    for _, itemData in ipairs(panel.traitList.items or {}) do
        local row = itemData and itemData.item or nil
        if row and row.name and (selected == true and isDebugVisibleBulkRow(row) or selected ~= true) then
            row.selected = selected == true
            if selected == true then
                panel.selectedTraits[row.name] = true
            else
                panel.selectedTraits[row.name] = nil
            end
            count = count + 1
        end
    end

    self:updateSpawnSummary()
    BurdJournals.UI.DebugPanel.refreshSpawnBulkToggles(self)
    self:setStatus(
        selected and debugFormatText("UI_BurdJournals_DebugSelectedVisibleSpawnTraits", "Selected %1 visible spawn trait(s)", tostring(count))
            or debugFormatText("UI_BurdJournals_DebugClearedSpawnTraits", "Cleared %1 spawn trait(s)", tostring(count)),
        {r=0.5, g=0.8, b=1}
    )
end

function BurdJournals.UI.DebugPanel.onSpawnRecipeBulkToggle(self, _index, selected)
    local panel = self and self.spawnPanel or nil
    if not (panel and panel.recipeList and panel.selectedRecipes) then
        return
    end

    local count = 0
    for _, itemData in ipairs(panel.recipeList.items or {}) do
        local row = itemData and itemData.item or nil
        if row and row.name and (selected == true and isDebugVisibleBulkRow(row) or selected ~= true) then
            row.selected = selected == true
            if selected == true then
                panel.selectedRecipes[tostring(row.name)] = true
            else
                panel.selectedRecipes[tostring(row.name)] = nil
            end
            count = count + 1
        end
    end

    self:updateSpawnSummary()
    BurdJournals.UI.DebugPanel.refreshSpawnBulkToggles(self)
    self:setStatus(
        selected and debugFormatText("UI_BurdJournals_DebugSelectedVisibleSpawnRecipes", "Selected %1 visible spawn recipe(s)", tostring(count))
            or debugFormatText("UI_BurdJournals_DebugClearedSpawnRecipes", "Cleared %1 spawn recipe(s)", tostring(count)),
        {r=0.5, g=0.8, b=1}
    )
end

-- Filter functions for Spawn tab
function BurdJournals.UI.DebugPanel.filterSpawnSkillList(self)
    local panel = self.spawnPanel
    if not panel or not panel.skillList then return end
    local journalType = panel.selectedType or "blank"
    
    local searchText = ""
    if panel.spawnSkillSearch and panel.spawnSkillSearch.getText then
        searchText = panel.spawnSkillSearch:getText()
    end
    local selectedSourceId = panel.spawnSkillSourceFilter and panel.spawnSkillSourceFilter.selectedSourceId or "all"
    
    applyDebugRowFilter(panel.skillList, function(row)
        local skillName = row and row.name or nil
        local isAllowed = isSpawnSkillAllowedForType(journalType, skillName)
        row.hiddenBySandbox = not isAllowed
        local matchesSearch = searchText == "" or debugSearchMatches(searchText, row.displayName, row.name, row.category, row.source)
        local matchesSource = debugRowMatchesSourceFilter(row, selectedSourceId)
        return isAllowed and matchesSearch and matchesSource
    end)
    BurdJournals.UI.DebugPanel.refreshSpawnBulkToggles(self)
end

function BurdJournals.UI.DebugPanel.filterSpawnTraitList(self)
    local panel = self.spawnPanel
    if not panel or not panel.traitList then return end
    
    local searchText = ""
    if panel.spawnTraitSearch and panel.spawnTraitSearch.getText then
        searchText = panel.spawnTraitSearch:getText()
    end
    local selectedSourceId = panel.spawnTraitSourceFilter and panel.spawnTraitSourceFilter.selectedSourceId or "all"
    local selectedPolarity = getDebugTraitPolarityFilterValue(panel.spawnTraitPolarityFilter)
    
    applyDebugRowFilter(panel.traitList, function(row)
        local matchesSearch = searchText == "" or debugSearchMatches(searchText, row.displayName, row.name, row.source)
        local matchesSource = debugRowMatchesSourceFilter(row, selectedSourceId)
        local matchesPolarity = debugRowMatchesTraitPolarityFilter(row, selectedPolarity)
        return matchesSearch and matchesSource and matchesPolarity
    end)
    BurdJournals.UI.DebugPanel.refreshSpawnBulkToggles(self)
end

function BurdJournals.UI.DebugPanel.filterSpawnRecipeList(self)
    local panel = self.spawnPanel
    if not panel or not panel.recipeList then return end

    local searchText = ""
    if panel.spawnRecipeSearch and panel.spawnRecipeSearch.getText then
        searchText = panel.spawnRecipeSearch:getText()
    end
    local selectedSourceId = panel.spawnRecipeSourceFilter and panel.spawnRecipeSourceFilter.selectedSourceId or "all"

    applyDebugRowFilter(panel.recipeList, function(row)
        local matchesSearch = searchText == "" or debugSearchMatches(searchText, row.displayName, row.name, row.magazineSource, row.magazineDisplayName, row.source)
        local matchesSource = debugRowMatchesSourceFilter(row, selectedSourceId)
        return matchesSearch and matchesSource
    end)
    BurdJournals.UI.DebugPanel.refreshSpawnBulkToggles(self)
end

-- Custom draw function for skill list items
function BurdJournals.UI.DebugPanel.drawSkillItem(self, y, item, alt)
    local h = getDebugListRowHeight(self, item, 30)
    local data = item.item
    
    -- Skip hidden items (filtered by search)
    if data.hidden then return y + h end
    
    local isFocused = self.parentPanel and self.parentPanel.spawnPanel and 
                      self.parentPanel.spawnPanel.focusedSkill == data.name
    local w = self.width or 300
    local scrollOffset = BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH or 15
    
    -- Background - highlight focused item more prominently
    if isFocused and data.selected then
        self:drawRect(0, y, w, h, 0.4, 0.3, 0.6, 0.5)
    elseif data.selected then
        self:drawRect(0, y, w, h, 0.25, 0.2, 0.4, 0.3)
    elseif self.mouseoverselected == item.index then
        self:drawRect(0, y, w, h, 0.2, 0.2, 0.3, 0.3)
    elseif data.isPassive then
        self:drawRect(0, y, w, h, 0.1, 0.15, 0.2, 0.18)
    end
    
    -- Checkbox
    local checkX = 5
    if data.selected then
        self:drawText("[X]", checkX, y + 2, 0.3, 0.8, 0.3, 1, UIFont.Small)
    else
        self:drawText("[ ]", checkX, y + 2, 0.5, 0.5, 0.5, 1, UIFont.Small)
    end
    
    -- Skill name (use display name if available)
    local textX = 30
    local displayText = data.displayName or data.name
    local color = isFocused and {1, 1, 0.7} or (data.selected and {0.9, 1, 0.9} or {0.7, 0.7, 0.7})
    self:drawText(displayText, textX, y + 2, color[1], color[2], color[3], 1, UIFont.Small)

    local detailParts = {}
    if data.category and data.category ~= "" then
        detailParts[#detailParts + 1] = tostring(data.category)
    end
    if data.source and data.source ~= "" then
        detailParts[#detailParts + 1] = tostring(data.source)
    end
    if data.isPassive then
        detailParts[#detailParts + 1] = debugText("UI_BurdJournals_DebugPassive", "Passive")
    end
    if #detailParts > 0 then
        self:drawText(table.concat(detailParts, " | "), textX, y + 15, 0.55, 0.65, 0.78, 0.9, UIFont.Small)
    end
    
    -- Show level and extra XP for selected skills
    if data.selected then
        local lvlColor = isFocused and {1, 1, 0.5} or {0.5, 0.8, 1}
        local extraXP = data.extraXP or 0
        local lvlText = BurdJournals.formatText(getText("UI_BurdJournals_LevelFormat"), data.level or 0)
        if extraXP > 0 then
            lvlText = lvlText .. "+" .. extraXP
        end
        local textWidth = getTextManager():MeasureStringX(UIFont.Small, lvlText)
        self:drawText(lvlText, w - textWidth - 5 - scrollOffset, y + 2, lvlColor[1], lvlColor[2], lvlColor[3], 1, UIFont.Small)
        self:drawText(debugText("UI_BurdJournals_DebugSelected", "Selected"), w - 54 - scrollOffset, y + 15, 0.55, 0.82, 0.55, 0.9, UIFont.Small)
    end
    
    return y + h
end

-- Custom draw function for trait list items
function BurdJournals.UI.DebugPanel.drawTraitItem(self, y, item, alt)
    local h = getDebugListRowHeight(self, item, 30)
    local data = item.item
    
    -- Skip hidden items (filtered by search)
    if data.hidden then return y + h end
    local w = self.width or 300
    local scrollOffset = BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH or 15
    
    -- Background
    if data.selected then
        self:drawRect(0, y, w, h, 0.3, 0.3, 0.5, 0.2)
    elseif self.mouseoverselected == item.index then
        self:drawRect(0, y, w, h, 0.2, 0.2, 0.3, 0.3)
    end
    
    -- Checkbox
    local checkX = 5
    if data.selected then
        self:drawText("[X]", checkX, y + 2, 0.3, 0.8, 0.3, 1, UIFont.Small)
    else
        self:drawText("[ ]", checkX, y + 2, 0.5, 0.5, 0.5, 1, UIFont.Small)
    end
    
    local iconSize = drawDebugListIcon(self, data.traitTexture or getDebugTraitTexture(data.id or data.name), 28, y, h, 0.95, 13)
    local textX = 28 + math.max(iconSize, 13) + 6
    local displayText = BurdJournals.UI.DebugPanel.getTraitPolarityPrefix(data) .. " " .. tostring(data.displayName or data.name or debugText("UI_BurdJournals_DebugUnknown", "Unknown"))
    local color = BurdJournals.UI.DebugPanel.getTraitPolarityColor(data)
    if data.selected then
        color = {
            math.min(1, color[1] + 0.15),
            math.min(1, color[2] + 0.15),
            math.min(1, color[3] + 0.15),
        }
    end
    self:drawText(displayText, textX, y + 2, color[1], color[2], color[3], 1, UIFont.Small)
    local sourceText = BurdJournals.UI.DebugPanel.getTraitSourceLine(data)
    if sourceText ~= "" then
        self:drawText(sourceText, textX, y + 15, color[1], color[2], color[3], 0.85, UIFont.Small)
    end
    if data.selected then
        self:drawText(debugText("UI_BurdJournals_DebugSelected", "Selected"), w - 54 - scrollOffset, y + 2, 0.55, 0.82, 0.55, 1, UIFont.Small)
    end
    
    return y + h
end

-- Skill list click handler
function BurdJournals.UI.DebugPanel.onSkillListClick(self, x, y)
    local row = BurdJournals.UI.DebugPanel.safeListMouseDown(self, x, y)
    if row > 0 and row <= #self.items then
        local item = self.items[row]
        local data = item.item
        if not data or data.hidden or data.hiddenBySandbox then
            return
        end
        local panel = self.parentPanel.spawnPanel
        
        -- Check if clicking on checkbox area (left 25 pixels) or text area
        local isCheckboxClick = x < 25
        
        if data.selected and not isCheckboxClick then
            -- Already selected, just focus it (don't toggle)
            panel.focusedSkill = data.name
            self.parentPanel:setStatus(debugFormatText("UI_BurdJournals_DebugEditingLevelFor", "Editing level for %1", data.name), {r=1, g=1, b=0.6})
        else
            -- Toggle selection (checkbox click or clicking unselected item)
            data.selected = not data.selected
            
            if data.selected then
                -- New selection: set to default level/extraXP and focus it
                data.level = panel.defaultLevel
                data.extraXP = panel.defaultExtraXP or 0
                panel.selectedSkills[data.name] = {level = data.level, extraXP = data.extraXP}
                panel.focusedSkill = data.name
            else
                -- Deselected: remove from selections and clear focus if it was focused
                panel.selectedSkills[data.name] = nil
                if panel.focusedSkill == data.name then
                    panel.focusedSkill = nil
                end
            end
        end
        
        -- Update level buttons to show focused skill's level
        self.parentPanel:updateLevelButtons()
        self.parentPanel:updateSpawnSummary()
        BurdJournals.UI.DebugPanel.refreshSpawnBulkToggles(self.parentPanel)
    end
end

-- Trait list click handler
function BurdJournals.UI.DebugPanel.onTraitListClick(self, x, y)
    local row = BurdJournals.UI.DebugPanel.safeListMouseDown(self, x, y)
    if row > 0 and row <= #self.items then
        local item = self.items[row]
        local data = item.item
        if not data or data.hidden then
            return
        end
        data.selected = not data.selected
        
        -- Update parent panel's selected traits
        local panel = self.parentPanel.spawnPanel
        if data.selected then
            panel.selectedTraits[data.name] = true
        else
            panel.selectedTraits[data.name] = nil
        end
        self.parentPanel:updateSpawnSummary()
        BurdJournals.UI.DebugPanel.refreshSpawnBulkToggles(self.parentPanel)
    end
end

function BurdJournals.UI.DebugPanel.drawSpawnRecipeItem(self, y, item, alt)
    local h = getDebugListRowHeight(self, item, 30)
    if not item or not item.item then return y + h end
    local data = item.item
    if not data or data.hidden then return y + h end

    local w = self.width or 300
    local scrollOffset = BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH or 15

    if data.selected then
        self:drawRect(0, y, w, h, 0.12, 0.2, 0.12, 0.28)
    elseif self.mouseoverselected == item.index then
        self:drawRect(0, y, w, h, 0.2, 0.2, 0.3, 0.3)
    end

    if data.selected then
        self:drawText("[X]", 8, y + 2, 0.4, 0.7, 0.4, 1, UIFont.Small)
    else
        self:drawText("[ ]", 8, y + 2, 0.5, 0.5, 0.5, 1, UIFont.Small)
    end

    local iconX = 28
    local recipeIcon = data.recipeTexture or getDebugRecipeTexture()
    local recipeSize = drawDebugListIcon(self, recipeIcon, iconX, y, h, 0.95, 13)
    local textX = iconX + math.max(recipeSize, 13) + 6
    if data.magazineSource then
        local magSize = drawDebugListIcon(self, data.magazineTexture or getDebugMagazineTexture(data.magazineSource), textX, y, h, 0.9, 13)
        if magSize > 0 then
            textX = textX + magSize + 6
        end
    end

    self:drawText(tostring(data.displayName or data.name or debugText("UI_BurdJournals_DebugUnknownRecipe", "Unknown Recipe")), textX, y + 2, data.selected and 0.82 or 0.74, data.selected and 1 or 0.74, data.selected and 0.82 or 0.74, 1, UIFont.Small)
    local sourceText = getDebugRecipeSourceText(data, 22)
    local sourceColor = data.magazineDisplayName and {0.5, 0.7, 0.75}
        or ((data.source and data.source ~= "Vanilla" and data.source ~= "Runtime" and data.source ~= "Unknown")
            and {0.82, 0.72, 0.5}
            or {0.55, 0.65, 0.78})
    self:drawText(sourceText, textX, y + 15, sourceColor[1], sourceColor[2], sourceColor[3], 0.9, UIFont.Small)
    if data.selected then
        self:drawText(debugText("UI_BurdJournals_DebugSelected", "Selected"), w - 54 - scrollOffset, y + 2, 0.55, 0.82, 0.55, 1, UIFont.Small)
    elseif data.hasMagazine then
        self:drawText(debugText("UI_BurdJournals_DebugAvailable", "Available"), w - 56 - scrollOffset, y + 2, 0.68, 0.82, 0.95, 0.9, UIFont.Small)
    end
    return y + h
end

function BurdJournals.UI.DebugPanel.onSpawnRecipeListClick(self, x, y)
    local row = BurdJournals.UI.DebugPanel.safeListMouseDown(self, x, y)
    if row <= 0 or row > #self.items then return end

    local item = self.items[row]
    local data = item and item.item or nil
    if not (data and self.parentPanel and self.parentPanel.spawnPanel) then return end
    if data.hidden then
        return
    end

    data.selected = not data.selected
    local panel = self.parentPanel.spawnPanel
    if data.selected then
        panel.selectedRecipes[tostring(data.name)] = true
    else
        panel.selectedRecipes[tostring(data.name)] = nil
    end
    self.parentPanel:updateSpawnSummary()
    BurdJournals.UI.DebugPanel.refreshSpawnBulkToggles(self.parentPanel)
end

-- Level selector click - only affects focused skill, or sets default for new selections
function BurdJournals.UI.DebugPanel:onLevelSelect(button)
    local panel = self.spawnPanel
    local level = button.internal
    
    -- If a skill is focused, update only that skill's level
    if panel.focusedSkill then
        for _, itemData in ipairs(panel.skillList.items) do
            if itemData.item.name == panel.focusedSkill and itemData.item.selected then
                itemData.item.level = level
                
                -- Get valid range for new level and clamp extraXP if needed
                local range = BurdJournals.Client.Debug.getXPRangeForLevel and 
                              BurdJournals.Client.Debug.getXPRangeForLevel(itemData.item.name, level) or
                              {maxExtra = 999999}
                local currentExtraXP = itemData.item.extraXP or 0
                if currentExtraXP > range.maxExtra then
                    itemData.item.extraXP = range.maxExtra
                end
                
                panel.selectedSkills[itemData.item.name] = {level = level, extraXP = itemData.item.extraXP or 0}
                self:setStatus("Set " .. panel.focusedSkill .. " to level " .. level, {r=0.5, g=0.8, b=1})
                break
            end
        end
    else
        -- No skill focused - update default level for new selections
        panel.defaultLevel = level
        -- Reset default extraXP to 0 when level changes (to avoid exceeding new max)
        panel.defaultExtraXP = 0
        self:setStatus("Default level set to " .. level, {r=0.6, g=0.7, b=0.8})
    end
    
    self:updateLevelButtons()
    self:updateSpawnSummary()
end

-- Update level button visuals based on focused skill or default
function BurdJournals.UI.DebugPanel:updateLevelButtons()
    local panel = self.spawnPanel
    if not panel or not panel.levelButtons then return end
    
    -- Determine which level and extraXP to highlight
    local highlightLevel = panel.defaultLevel
    local currentExtraXP = panel.defaultExtraXP or 0
    local focusedSkillName = nil
    
    if panel.focusedSkill then
        -- Find the focused skill's level and extraXP
        for _, itemData in ipairs(panel.skillList.items) do
            if itemData.item.name == panel.focusedSkill and itemData.item.selected then
                highlightLevel = itemData.item.level
                currentExtraXP = itemData.item.extraXP or 0
                focusedSkillName = itemData.item.name
                break
            end
        end
    end
    
    -- Update label text
    if panel.levelLabel then
        if panel.focusedSkill then
            -- Find display name for focused skill
            local displayName = panel.focusedSkill
            for _, itemData in ipairs(panel.skillList.items) do
                if itemData.item.name == panel.focusedSkill then
                    displayName = itemData.item.displayName or panel.focusedSkill
                    break
                end
            end
            panel.levelLabel:setName("Level for " .. displayName .. ":")
            panel.levelLabel.r = 1
            panel.levelLabel.g = 1
            panel.levelLabel.b = 0.6
        else
            panel.levelLabel:setName("Level (default):")
            panel.levelLabel.r = 0.8
            panel.levelLabel.g = 0.8
            panel.levelLabel.b = 0.8
        end
    end
    
    -- Update extra XP entry and range
    if panel.extraXPEntry and panel.extraXPRange then
        -- Get XP range for current skill/level
        local skillName = focusedSkillName or "Carpentry"  -- Default skill for range calc
        local range = BurdJournals.Client.Debug.getXPRangeForLevel and 
                      BurdJournals.Client.Debug.getXPRangeForLevel(skillName, highlightLevel) or
                      {min = 0, max = 149, maxExtra = 149}
        
        -- Update extra XP entry to show current value
        panel.extraXPEntry:setText(tostring(currentExtraXP))
        
        -- Update range label
        panel.extraXPRange:setName("(0-" .. tostring(range.maxExtra) .. ")")
        
        -- Color coding based on focus state
        if panel.focusedSkill then
            panel.extraXPLabel.r = 1
            panel.extraXPLabel.g = 1
            panel.extraXPLabel.b = 0.6
        else
            panel.extraXPLabel.r = 0.8
            panel.extraXPLabel.g = 0.8
            panel.extraXPLabel.b = 0.8
        end
    end
    
    -- Update button visuals
    for lvl, btn in pairs(panel.levelButtons) do
        if lvl == highlightLevel then
            if panel.focusedSkill then
                -- Focused skill - yellow highlight
                btn.backgroundColor = {r=0.5, g=0.5, b=0.2, a=1}
                btn.borderColor = {r=0.7, g=0.7, b=0.3, a=1}
            else
                -- Default level - green highlight
                btn.backgroundColor = {r=0.3, g=0.5, b=0.4, a=1}
                btn.borderColor = {r=0.4, g=0.7, b=0.5, a=1}
            end
        else
            btn.backgroundColor = {r=0.2, g=0.2, b=0.25, a=1}
            btn.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
        end
    end
end

-- Handle extra XP input change
function BurdJournals.UI.DebugPanel.onExtraXPChange(self)
    local panel = self.spawnPanel
    if not panel or not panel.extraXPEntry then return end
    
    local inputText = panel.extraXPEntry:getText() or "0"
    local extraXP = tonumber(inputText) or 0
    
    -- Get current level to validate against
    local currentLevel = panel.defaultLevel
    local focusedSkillName = nil
    
    if panel.focusedSkill then
        for _, itemData in ipairs(panel.skillList.items) do
            if itemData.item.name == panel.focusedSkill and itemData.item.selected then
                currentLevel = itemData.item.level
                focusedSkillName = itemData.item.name
                break
            end
        end
    end
    
    -- Get valid range
    local skillName = focusedSkillName or "Carpentry"
    local range = BurdJournals.Client.Debug.getXPRangeForLevel and 
                  BurdJournals.Client.Debug.getXPRangeForLevel(skillName, currentLevel) or
                  {min = 0, max = 149, maxExtra = 149}
    
    -- Clamp to valid range
    extraXP = math.max(0, math.min(extraXP, range.maxExtra))
    
    -- Update focused skill's extraXP or default
    if panel.focusedSkill then
        for _, itemData in ipairs(panel.skillList.items) do
            if itemData.item.name == panel.focusedSkill and itemData.item.selected then
                itemData.item.extraXP = extraXP
                panel.selectedSkills[itemData.item.name] = {level = itemData.item.level, extraXP = extraXP}
                break
            end
        end
        self:setStatus("Set " .. panel.focusedSkill .. " extra XP to " .. extraXP, {r=0.5, g=0.8, b=1})
    else
        panel.defaultExtraXP = extraXP
        self:setStatus("Default extra XP set to " .. extraXP, {r=0.6, g=0.7, b=0.8})
    end
    
    self:updateSpawnSummary()
end

-- Clear all selections
function BurdJournals.UI.DebugPanel:onClearSelections()
    local panel = self.spawnPanel
    
    -- Clear skills
    for _, itemData in ipairs(panel.skillList.items) do
        itemData.item.selected = false
        itemData.item.extraXP = 0
    end
    panel.selectedSkills = {}
    panel.focusedSkill = nil
    panel.defaultExtraXP = 0
    
    -- Clear traits
    for _, itemData in ipairs(panel.traitList.items) do
        itemData.item.selected = false
    end
    panel.selectedTraits = {}

    -- Clear recipes
    if panel.recipeList and panel.recipeList.items then
        for _, itemData in ipairs(panel.recipeList.items) do
            itemData.item.selected = false
        end
    end
    panel.selectedRecipes = {}
    
    self:updateLevelButtons()
    self:updateSpawnSummary()
    BurdJournals.UI.DebugPanel.refreshSpawnBulkToggles(self)
    self:setStatus("Selections cleared", {r=0.8, g=0.8, b=0.5})
end

-- Update summary text
function BurdJournals.UI.DebugPanel:updateSpawnSummary()
    local panel = self.spawnPanel
    if not panel or not panel.summaryText then
        return
    end
    local parts = {}
    local profile = (panel and panel.spawnProfile == "debug") and "Debug Profile" or "Normal Profile"
    table.insert(parts, profile)

    local journalType = panel.selectedType or "filled"
    if journalType == "filled" and panel.filledStateCombo then
        local filledState = panel.filledStateCombo:getOptionData(panel.filledStateCombo.selected)
            or panel.filledStateCombo.options[panel.filledStateCombo.selected]
            or "clean"
        table.insert(parts, tostring(filledState) == "restored" and "Restored" or "Clean")
    end
    if journalType ~= "blank" then
        local selectedOriginMode = normalizeDebugOriginMode(panel.spawnOriginMode)
        local resolvedOriginMode = resolveSpawnOriginMode(panel, journalType)
        local originText = getOriginModeLabel(resolvedOriginMode)
        if selectedOriginMode == "auto" then
            originText = originText .. " (Auto)"
        end
        table.insert(parts, originText)
    end
    
    local skillCount = 0
    for name, level in pairs(panel.selectedSkills) do
        skillCount = skillCount + 1
    end
    if skillCount > 0 then
        table.insert(parts, skillCount .. " skill(s)")
    end
    
    local traitCount = 0
    for name, _ in pairs(panel.selectedTraits) do
        traitCount = traitCount + 1
    end
    if traitCount > 0 then
        table.insert(parts, traitCount .. " trait(s)")
    end

    local recipeCount = 0
    for name, _ in pairs(panel.selectedRecipes or {}) do
        recipeCount = recipeCount + 1
    end
    if recipeCount > 0 then
        table.insert(parts, recipeCount .. " recipe(s)")
    end
    
    panel.summaryText:setName(table.concat(parts, ", "))
end

function BurdJournals.UI.DebugPanel:updateTypeButtons(panel)
    if not panel or not panel.typeButtons then return end
    for typeName, btn in pairs(panel.typeButtons) do
        if string.lower(typeName) == panel.selectedType then
            btn.backgroundColor = {r=0.3, g=0.5, b=0.4, a=1}
            btn.borderColor = {r=0.4, g=0.8, b=0.5, a=1}
        else
            btn.backgroundColor = {r=0.2, g=0.25, b=0.3, a=1}
            btn.borderColor = {r=0.4, g=0.5, b=0.6, a=1}
        end
    end
end

function BurdJournals.UI.DebugPanel:onTypeSelect(button)
    local panel = self.spawnPanel
    panel.selectedType = button.internal
    self:applySpawnOwnerDefault(panel, panel.selectedType)
    self:updateTypeButtons(panel)
    self:requestLoreTemplateOptions()
    self:updateSpawnPanelVisibility()
end

function BurdJournals.UI.DebugPanel:onPresetClick(button)
    local preset = button.internal
    local panel = self.spawnPanel
    
    -- Clear current selections
    for _, itemData in ipairs(panel.skillList.items) do
        itemData.item.selected = false
        itemData.item.extraXP = 0
    end
    panel.selectedSkills = {}
    for _, itemData in ipairs(panel.traitList.items) do
        itemData.item.selected = false
    end
    panel.selectedTraits = {}
    
    if preset == "maxpassive" then
        panel.selectedType = "worn"
        if not isSpawnSkillAllowedForType(panel.selectedType, "Fitness") then
            self:updateTypeButtons(panel)
            self:updateSpawnPanelVisibility()
            self:setStatus("Passive skills are disabled for loot journals in sandbox settings", {r=1, g=0.7, b=0.3})
            return
        end
        -- Select all passive skills (Fitness, Strength, etc.) at level 10
        local passiveSkills = BurdJournals.getPassiveSkills and BurdJournals.getPassiveSkills() or {"Fitness", "Strength"}
        for _, itemData in ipairs(panel.skillList.items) do
            for _, passiveSkill in ipairs(passiveSkills) do
                if (itemData.item.name == passiveSkill or BurdJournals.isPassiveSkill(itemData.item.name))
                    and isSpawnSkillAllowedForType(panel.selectedType, itemData.item.name) then
                    itemData.item.selected = true
                    itemData.item.level = 10
                    itemData.item.extraXP = 0
                    panel.selectedSkills[itemData.item.name] = {level = 10, extraXP = 0}
                    break
                end
            end
        end
    elseif preset == "allpositive" then
        -- Select ALL positive traits from the list using the shared polarity resolver.
        for _, itemData in ipairs(panel.traitList.items) do
            local traitName = itemData.item.name
            if BurdJournals.UI.DebugPanel.matchesBulkTraitAction("addallpositivetraits", traitName) then
                itemData.item.selected = true
                panel.selectedTraits[traitName] = true
            end
        end
        panel.selectedType = "bloody"
    elseif preset == "allnegative" then
        -- Select ALL negative traits from the list using the shared polarity resolver.
        for _, itemData in ipairs(panel.traitList.items) do
            local traitName = itemData.item.name
            if BurdJournals.UI.DebugPanel.matchesBulkTraitAction("addallnegativetraits", traitName) then
                itemData.item.selected = true
                panel.selectedTraits[traitName] = true
            end
        end
        panel.selectedType = "bloody"
    end
    
    self:updateTypeButtons(panel)
    self:updateSpawnPanelVisibility()
    self:updateSpawnSummary()
    self:setStatus("Preset loaded: " .. preset, {r=0.5, g=0.8, b=1})
end

function BurdJournals.UI.DebugPanel:onSpawnClick()
    local panel = self.spawnPanel
    local journalType = panel.selectedType
    local debugTypeDef = BurdJournals.getDebugJournalType and BurdJournals.getDebugJournalType(journalType) or nil
    
    -- Build params from selections
    local params = {
        journalType = journalType,
        skills = {},
        traits = {},
        recipes = {},
        stats = {},
        manualRewards = true,
        debugBackupEnabled = journalType ~= "blank",
        owner = nil,
        ownerMode = "none",
        forceCurseType = nil,
        forceCurseTraitId = nil,
        forceCurseSkillName = nil,
        cursedSpawnState = "dormant",
        cursedUnleashed = false,
        forgetSlot = false,
        spawnProfile = (panel.spawnProfile or "normal"),
        originMode = resolveSpawnOriginMode(panel, journalType),
    }
    
    -- Handle owner/assignment based on journal type
    if journalType ~= "blank" then
        if journalType == "filled" then
            if panel.filledStateCombo then
                params.filledJournalState = panel.filledStateCombo:getOptionData(panel.filledStateCombo.selected)
                    or panel.filledStateCombo.options[panel.filledStateCombo.selected]
                    or "clean"
            end
            if tostring(params.filledJournalState or "clean") ~= "restored" then
                params.filledJournalState = "clean"
            end

            local selectedData = panel.ownerCombo:getOptionData(panel.ownerCombo.selected)
            if selectedData and selectedData.isNone then
                params.ownerMode = "none"
                params.owner = nil
            elseif selectedData and selectedData.isCustom then
                -- Custom name - display only.
                local customName = panel.customNameEntry:getText()
                if customName and customName ~= "" then
                    params.ownerMode = "custom"
                    params.owner = customName
                    params.isCustomOwner = true
                else
                    params.ownerMode = "none"
                    params.owner = nil
                end
            elseif selectedData and selectedData.isPlayer then
                -- Assign to a specific player (true ownership assignment).
                params.ownerMode = "player_assignment"
                params.owner = selectedData.characterName
                params.ownerSteamId = selectedData.steamId
                params.ownerUsername = selectedData.username
                params.ownerCharacterName = selectedData.characterName
                params.assignedPlayer = selectedData.player
                params.isPlayerCreated = true
            else
                params.ownerMode = "none"
                params.owner = nil
            end
        else
            -- Loot journal types always spawn without ownership metadata.
            params.ownerMode = "none"
            params.owner = nil
            params.ownerSteamId = nil
            params.ownerUsername = nil
            params.ownerCharacterName = nil
            params.assignedPlayer = nil
            params.isPlayerCreated = nil
        end

        -- Handle profession selection (for worn/bloody journals)
        if journalType == "worn" or journalType == "bloody" then
            local profSelected = panel.professionCombo.selected or 1
            if profSelected == 1 then
                -- (Random) - let spawn function pick random profession
                params.randomProfession = true
            elseif profSelected == 2 then
                -- (None) - no profession
                params.noProfession = true
            elseif profSelected == 3 then
                -- Custom profession - use the text entry value
                local customProf = panel.customProfEntry:getText()
                if customProf and customProf ~= "" then
                    params.profession = "custom"
                    params.professionName = customProf
                    params.isCustomProfession = true
                    -- No flavor key for custom - user can set flavor text separately
                else
                    -- Fallback to random if custom field is empty
                    params.randomProfession = true
                end
            elseif profSelected >= 4 and BurdJournals.PROFESSIONS then
                -- Specific profession selected (index 4+ maps to PROFESSIONS[index-3])
                local profIndex = profSelected - 3
                local prof = BurdJournals.PROFESSIONS[profIndex]
                if prof then
                    params.profession = prof.id
                    params.professionName = prof.nameKey and getText(prof.nameKey) or prof.name
                    params.professionFlavorKey = prof.flavorKey
                end
            end
        end

        -- Handle custom flavor text (for all non-blank journals)
        local flavorText = panel.flavorEntry:getText()
        if flavorText and flavorText ~= "" then
            params.flavorText = flavorText
        end

        local supportsGeneratedLore = (journalType == "worn" or journalType == "bloody" or journalType == "cursed" or journalType == "yuletide")
            or (type(debugTypeDef) == "table" and debugTypeDef.supportsGeneratedLore == true)
        if supportsGeneratedLore then
            params.loreMode = getSpawnLoreMode(panel)
            if params.loreMode == "manual" then
                local templateKey = getSelectedLoreTemplateKey(panel)
                if not templateKey then
                    self:setStatus(
                        getText("UI_BurdJournals_DebugSpawnLoreTemplateRequired")
                            or "Choose a lore template or switch Lore Text back to Random.",
                        {r=1, g=0.55, b=0.35}
                    )
                    return
                end
                params.loreTemplateKey = templateKey
            end
        end

        -- Spawn metadata
        if panel.ageEntry and panel.ageEntry.getText then
            local ageHours = tonumber(panel.ageEntry:getText() or "0") or 0
            params.ageHours = math.max(0, ageHours)
        end

        if panel.forgetSlotTick and panel.forgetSlotTick.selected then
            params.forgetSlot = panel.forgetSlotTick.selected[1] == true
        end
        if journalType == "yuletide" then
            if panel.yuletideStateCombo and panel.yuletideStateCombo.selected and panel.yuletideStateCombo.selected > 0 then
                params.yuletideState = panel.yuletideStateCombo:getOptionData(panel.yuletideStateCombo.selected)
                    or panel.yuletideStateCombo.options[panel.yuletideStateCombo.selected]
            end
            if panel.yuletideWrappedVariantCombo and panel.yuletideWrappedVariantCombo.selected and panel.yuletideWrappedVariantCombo.selected > 0 then
                params.yuletideWrappedVariant = panel.yuletideWrappedVariantCombo:getOptionData(panel.yuletideWrappedVariantCombo.selected)
                    or panel.yuletideWrappedVariantCombo.options[panel.yuletideWrappedVariantCombo.selected]
            end
            if panel.yuletideRewardTierCombo and panel.yuletideRewardTierCombo.selected and panel.yuletideRewardTierCombo.selected > 0 then
                local tier = panel.yuletideRewardTierCombo:getOptionData(panel.yuletideRewardTierCombo.selected)
                    or panel.yuletideRewardTierCombo.options[panel.yuletideRewardTierCombo.selected]
                tier = tostring(tier or "random")
                if tier ~= "random" then
                    params.yuletideGiftTier = tier
                end
            end
        end
        if journalType == "cursed" then
            local cursedSpawnState = "dormant"
            if panel.cursedStateCombo then
                if panel.cursedStateCombo.selected == 3 then
                    cursedSpawnState = "unleashed"
                elseif panel.cursedStateCombo.selected == 2 then
                    cursedSpawnState = "hidden"
                end
            end
            params.cursedSpawnState = cursedSpawnState
            params.cursedUnleashed = (cursedSpawnState == "unleashed")
            if panel.forceCurseCombo and panel.forceCurseCombo.selected and panel.forceCurseCombo.selected > 0 then
                params.forceCurseType = panel.forceCurseCombo:getOptionData(panel.forceCurseCombo.selected)
                    or panel.forceCurseCombo.options[panel.forceCurseCombo.selected]
            end
            if panel.forceCurseTargetCombo and panel.forceCurseTargetCombo.selected and panel.forceCurseTargetCombo.selected > 0 then
                local targetValue = panel.forceCurseTargetCombo:getOptionData(panel.forceCurseTargetCombo.selected)
                if panel.forceCurseTargetType == "trait" then
                    params.forceCurseTraitId = targetValue
                elseif panel.forceCurseTargetType == "skill" then
                    params.forceCurseSkillName = targetValue
                end
            end
        end

        if type(debugTypeDef) == "table" and type(debugTypeDef.collectOptions) == "function" then
            local extensionOptions = debugTypeDef.collectOptions(panel, params, self)
            if extensionOptions == false then
                return
            end
            if type(extensionOptions) == "table" then
                params.debugTypeOptions = extensionOptions
            end
        end
    end
    
    -- Add selected skills (only for non-blank journals)
    if journalType ~= "blank" then
        -- Read extra XP directly from the text entry field
        local extraXPFromField = 0
        local extraXPFieldText = ""
        if panel.extraXPEntry and panel.extraXPEntry.getText then
            extraXPFieldText = panel.extraXPEntry:getText() or ""
            extraXPFromField = tonumber(extraXPFieldText) or 0
        end
        
        BurdJournals.debugPrint("[BurdJournals] DEBUG SPAWN: Extra XP field text = '" .. tostring(extraXPFieldText) .. "' -> number = " .. tostring(extraXPFromField))
        BurdJournals.debugPrint("[BurdJournals] DEBUG SPAWN: Focused skill = " .. tostring(panel.focusedSkill))
        
        for skillName, skillData in pairs(panel.selectedSkills) do
            if isSpawnSkillAllowedForType(journalType, skillName) then
                -- skillData is now {level = X, extraXP = Y}
                local level = skillData.level or skillData  -- Backward compat: might be just a number
                local storedExtraXP = skillData.extraXP or 0
                local extraXP = storedExtraXP
                
                BurdJournals.debugPrint("[BurdJournals] DEBUG SPAWN: Skill '" .. skillName .. "' stored extraXP = " .. tostring(storedExtraXP))
                
                -- For the focused skill, use the value directly from the text field
                -- This ensures we capture the latest typed value even if onTextChange didn't fire
                if panel.focusedSkill == skillName then
                    extraXP = extraXPFromField
                    BurdJournals.debugPrint("[BurdJournals] DEBUG SPAWN: Using field value " .. tostring(extraXPFromField) .. " for focused skill")
                end
                
                -- Also get extraXP from the item data directly as a fallback
                for _, itemData in ipairs(panel.skillList.items) do
                    if itemData.item.name == skillName and itemData.item.selected then
                        local itemExtraXP = itemData.item.extraXP or 0
                        BurdJournals.debugPrint("[BurdJournals] DEBUG SPAWN: Item data extraXP = " .. tostring(itemExtraXP))
                        -- If this is the focused skill, use field value; otherwise use stored value
                        if panel.focusedSkill == skillName then
                            extraXP = extraXPFromField
                        elseif itemExtraXP > 0 then
                            extraXP = itemExtraXP
                        end
                        break
                    end
                end
                
                BurdJournals.debugPrint("[BurdJournals] DEBUG SPAWN: Final - skill=" .. skillName .. " level=" .. tostring(level) .. " extraXP=" .. tostring(extraXP))
                table.insert(params.skills, {name = skillName, level = level, extraXP = extraXP})
            else
                BurdJournals.debugPrint("[BurdJournals] DEBUG SPAWN: Skipping disabled passive skill " .. tostring(skillName))
            end
        end
        
        -- Add selected traits
        for traitName, _ in pairs(panel.selectedTraits) do
            table.insert(params.traits, traitName)
        end

        -- Add selected recipes
        for recipeName, _ in pairs(panel.selectedRecipes or {}) do
            table.insert(params.recipes, recipeName)
        end
    end
    
    BurdJournals.debugPrint("[BurdJournals] DEBUG UI: Spawning " .. journalType .. " journal" ..
          (journalType ~= "blank" and (" with " .. #params.skills .. " skills, " .. #params.traits .. " traits, " .. #params.recipes .. " recipes") or ""))
    BurdJournals.debugPrint("[BurdJournals] DEBUG UI: Spawn profile = " .. tostring(params.spawnProfile))
    BurdJournals.debugPrint("[BurdJournals] DEBUG UI: Origin mode = " .. tostring(params.originMode))
    
    if params.ownerSteamId then
        BurdJournals.debugPrint("[BurdJournals] DEBUG UI: Assigned to player: " .. tostring(params.ownerCharacterName) .. " (SteamID: " .. tostring(params.ownerSteamId) .. ")")
    elseif params.ownerMode == "none" then
        BurdJournals.debugPrint("[BurdJournals] DEBUG UI: Journal author set to None")
    elseif params.isCustomOwner then
        BurdJournals.debugPrint("[BurdJournals] DEBUG UI: Custom owner name: " .. tostring(params.owner))
    elseif params.ownerMode == "player_author" then
        BurdJournals.debugPrint("[BurdJournals] DEBUG UI: Lore author set from player: " .. tostring(params.owner))
    end
    
    -- Spawn
    if BurdJournals.Client and BurdJournals.Client.Debug and BurdJournals.Client.Debug.spawnJournal then
        local success, item = BurdJournals.Client.Debug.spawnJournal(self.player, params)
        if success then
            local ownerInfo = ""
            if params.ownerSteamId then
                ownerInfo = " (assigned to " .. params.ownerCharacterName .. ")"
            elseif params.isCustomOwner then
                ownerInfo = " (author: " .. params.owner .. ")"
            elseif params.ownerMode == "player_author" and params.owner and params.owner ~= "" then
                ownerInfo = " (author: " .. params.owner .. ")"
            end
            local profileSuffix = (params.spawnProfile == "debug") and " [Debug]" or " [Normal]"
            local originSuffix = ""
            if journalType ~= "blank" then
                originSuffix = " [" .. tostring(getOriginModeLabel(params.originMode)) .. "]"
            end
            self:setStatus("Spawned " .. journalType .. " journal!" .. profileSuffix .. originSuffix .. ownerInfo, {r=0.3, g=1, b=0.5})
        else
            self:setStatus("Failed to spawn journal", {r=1, g=0.3, b=0.3})
        end
    else
        self:setStatus("Spawn function not available", {r=1, g=0.5, b=0.3})
    end
end

-- ============================================================================
-- Tab 2: Character Panel (Enhanced with interactive skill/trait management)
-- ============================================================================

function BurdJournals.UI.DebugPanel:createCharacterPanel(startY, height)
    local panel = ISPanel:new(5, startY, self.width - 10, height)
    panel:initialise()
    panel:instantiate()
    panel.backgroundColor = {r=0.12, g=0.12, b=0.15, a=1}
    panel.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    self:addChild(panel)
    self.tabPanels["character"] = panel
    
    local padding = 10
    local y = padding
    local fullWidth = panel.width - padding * 2
    local btnHeight = 24
    local sectionPadding = 8
    
    -- Player selector (for admins to select other players)
    local playerLabel = ISLabel:new(padding, y, 18, "Selected Player:", 1, 1, 1, 1, UIFont.Small, true)
    playerLabel:initialise()
    playerLabel:instantiate()
    panel:addChild(playerLabel)
    
    panel.targetPlayerCombo = ISComboBox:new(padding + 90, y - 2, 200, 22, self, BurdJournals.UI.DebugPanel.onCharacterTargetPlayerChange)
    panel.targetPlayerCombo:initialise()
    panel.targetPlayerCombo:instantiate()
    panel.targetPlayerCombo.font = UIFont.Small
    panel:addChild(panel.targetPlayerCombo)
    
    local refreshBtn = ISButton:new(padding + 295, y - 2, 70, 22, "Refresh", self, BurdJournals.UI.DebugPanel.onCharacterRefresh)
    refreshBtn:initialise()
    refreshBtn:instantiate()
    refreshBtn.font = UIFont.Small
    refreshBtn.textColor = {r=1, g=1, b=1, a=1}
    refreshBtn.borderColor = {r=0.4, g=0.5, b=0.6, a=1}
    refreshBtn.backgroundColor = {r=0.2, g=0.25, b=0.3, a=1}
    panel:addChild(refreshBtn)
    y = y + 28

    panel.characterSummaryLabel = ISLabel:new(padding, y, 18, "", 0.82, 0.88, 0.98, 1, UIFont.Small, true)
    panel.characterSummaryLabel:initialise()
    panel.characterSummaryLabel:instantiate()
    panel:addChild(panel.characterSummaryLabel)
    y = y + 18

    panel.characterHelpLabel = ISLabel:new(padding, y, 18, "", 0.62, 0.74, 0.86, 1, UIFont.Small, true)
    panel.characterHelpLabel:initialise()
    panel.characterHelpLabel:instantiate()
    panel:addChild(panel.characterHelpLabel)
    y = y + 22

    panel.characterTabState = {buttons = {}, panels = {}, current = "skills"}
    local makeDebugButton = type(createDebugButton) == "function"
        and createDebugButton
        or BurdJournals.UI.DebugPanel.createDebugButton
        or function(parentRef, x, y, w, h, title, owner, callback, internal, borderColor, backgroundColor, tooltip)
            local btn = ISButton:new(x, y, w, h, title, owner, callback)
            btn:initialise()
            btn:instantiate()
            btn.font = UIFont.Small
            btn.textColor = {r=1, g=1, b=1, a=1}
            btn.borderColor = borderColor or {r=0.4, g=0.5, b=0.6, a=1}
            btn.backgroundColor = backgroundColor or {r=0.2, g=0.25, b=0.3, a=1}
            if internal then
                btn.internal = internal
            end
            if tooltip and btn.setTooltip then
                btn:setTooltip(tooltip)
            end
            parentRef:addChild(btn)
            return btn
        end
    local makeDebugSectionPanel = type(createDebugSectionPanel) == "function"
        and createDebugSectionPanel
        or BurdJournals.UI.DebugPanel.createDebugSectionPanel
        or function(parentRef, x, y, w, h)
            local childPanel = ISPanel:new(x, y, w, h)
            childPanel:initialise()
            childPanel:instantiate()
            childPanel.backgroundColor = {r=0.09, g=0.09, b=0.11, a=0}
            childPanel.borderColor = {r=0.2, g=0.24, b=0.3, a=0}
            parentRef:addChild(childPanel)
            return childPanel
        end
    local tabX = padding
    local tabWidth = 84
    local tabHeight = 22
    local tabSpacing = 6
    panel.characterTabState.buttons.skills = makeDebugButton(panel, tabX, y, tabWidth, tabHeight, "Skills", self, BurdJournals.UI.DebugPanel.onCharacterSubTab, "skills")
    tabX = tabX + tabWidth + tabSpacing
    panel.characterTabState.buttons.traits = makeDebugButton(panel, tabX, y, tabWidth, tabHeight, "Traits", self, BurdJournals.UI.DebugPanel.onCharacterSubTab, "traits")
    tabX = tabX + tabWidth + tabSpacing
    panel.characterTabState.buttons.recipes = makeDebugButton(panel, tabX, y, tabWidth, tabHeight, "Recipes", self, BurdJournals.UI.DebugPanel.onCharacterSubTab, "recipes")
    y = y + tabHeight + 8

    local sectionHeight = math.max(220, panel.height - y - padding)
    local sectionWidth = fullWidth

    local skillsSection = makeDebugSectionPanel(panel, padding, y, sectionWidth, sectionHeight)
    panel.characterTabState.panels.skills = skillsSection
    local sy = sectionPadding
    local contentWidth = skillsSection.width - sectionPadding * 2
    local skillLabelText = getText("UI_BurdJournals_DebugSkillsChangeLevel")
    local skillLabel = ISLabel:new(sectionPadding, sy + 2, 18, skillLabelText, 0.9, 0.9, 0.7, 1, UIFont.Small, true)
    skillLabel:initialise()
    skillLabel:instantiate()
    skillsSection:addChild(skillLabel)
    local skillSearchX = math.max(210, contentWidth - 160)
    panel.skillSearchEntry = ISTextEntryBox:new("", skillSearchX, sy, 150, 20)
    panel.skillSearchEntry:initialise()
    panel.skillSearchEntry:instantiate()
    panel.skillSearchEntry.font = UIFont.Small
    panel.skillSearchEntry:setTooltip("Type to filter skills...")
    panel.skillSearchEntry.onTextChange = function()
        BurdJournals.UI.DebugPanel.filterCharacterSkillList(self)
    end
    skillsSection:addChild(panel.skillSearchEntry)
    panel.skillSourceFilter = createSectionSourceFilterStrip(skillsSection, self, skillLabelText, skillSearchX, sy, sectionPadding, BurdJournals.UI.DebugPanel.filterCharacterSkillList, "Filter skill rows by source.")
    sy = sy + 24
    local skillListHeight = math.max(120, sectionHeight - 98)
    panel.charSkillList = ISScrollingListBox:new(sectionPadding, sy, contentWidth, skillListHeight)
    panel.charSkillList:initialise()
    panel.charSkillList:instantiate()
    panel.charSkillList.itemheight = 24
    panel.charSkillList.backgroundColor = {r=0.08, g=0.08, b=0.1, a=1}
    panel.charSkillList.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    panel.charSkillList.doDrawItem = BurdJournals.UI.DebugPanel.drawCharacterSkillItem
    panel.charSkillList.onMouseDown = BurdJournals.UI.DebugPanel.onCharacterSkillListClick
    panel.charSkillList.parentPanel = self
    skillsSection:addChild(panel.charSkillList)
    sy = sy + skillListHeight + 6
    panel.focusedSkill = nil
    panel.xpLabel = ISLabel:new(sectionPadding, sy + 2, 18, "Add XP:", 0.8, 0.8, 0.8, 1, UIFont.Small, true)
    panel.xpLabel:initialise()
    panel.xpLabel:instantiate()
    skillsSection:addChild(panel.xpLabel)
    panel.xpEntry = ISTextEntryBox:new("100", sectionPadding + 48, sy, 60, 20)
    panel.xpEntry:initialise()
    panel.xpEntry:instantiate()
    panel.xpEntry.font = UIFont.Small
    panel.xpEntry:setOnlyNumbers(true)
    panel.xpEntry.backgroundColor = {r=0.15, g=0.15, b=0.18, a=1}
    panel.xpEntry.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    skillsSection:addChild(panel.xpEntry)
    panel.xpSkillLabel = ISLabel:new(sectionPadding + 114, sy + 2, 18, "Click skill row to select", 0.5, 0.6, 0.7, 1, UIFont.Small, true)
    panel.xpSkillLabel:initialise()
    panel.xpSkillLabel:instantiate()
    skillsSection:addChild(panel.xpSkillLabel)
    local addXpBtn = createDebugButton(skillsSection, contentWidth - 60 + sectionPadding, sy, 60, 20, "+Add", self, BurdJournals.UI.DebugPanel.onCharacterAddXP, nil, {r=0.3, g=0.5, b=0.4, a=1}, {r=0.2, g=0.3, b=0.25, a=1})
    panel.addXpBtn = addXpBtn
    sy = sy + 28
    createDebugButton(skillsSection, sectionPadding, sy, 104, btnHeight, "All Skills Max", self, BurdJournals.UI.DebugPanel.onCharCmd, "setallmax", {r=0.3, g=0.6, b=0.3, a=1}, {r=0.15, g=0.3, b=0.15, a=1})
    createDebugButton(skillsSection, sectionPadding + 110, sy, 108, btnHeight, "All Skills Zero", self, BurdJournals.UI.DebugPanel.onCharCmd, "setallzero", {r=0.6, g=0.4, b=0.3, a=1}, {r=0.35, g=0.2, b=0.15, a=1})
    createDebugButton(skillsSection, sectionPadding + 224, sy, 96, btnHeight, "Dump Skills", self, BurdJournals.UI.DebugPanel.onCharCmd, "dumpskills")

    local traitsSection = createDebugSectionPanel(panel, padding, y, sectionWidth, sectionHeight)
    panel.characterTabState.panels.traits = traitsSection
    local ty = sectionPadding
    local traitLabelText = getText("UI_BurdJournals_DebugTraitsAddRemove")
    local charTraitLabelX = sectionPadding + 58
    panel.charTraitBulkTick = createDebugBulkTick(traitsSection, sectionPadding, ty - 1, 52, 20, "All", self, BurdJournals.UI.DebugPanel.onCharacterTraitBulkToggle, "Add or remove all visible non-passive traits.")
    local traitLabel = ISLabel:new(charTraitLabelX, ty + 2, 18, traitLabelText, 0.9, 0.9, 0.7, 1, UIFont.Small, true)
    traitLabel:initialise()
    traitLabel:instantiate()
    traitsSection:addChild(traitLabel)
    local traitSearchX = math.max(210, contentWidth - 160)
    panel.traitSearchEntry = ISTextEntryBox:new("", traitSearchX, ty, 150, 20)
    panel.traitSearchEntry:initialise()
    panel.traitSearchEntry:instantiate()
    panel.traitSearchEntry.font = UIFont.Small
    panel.traitSearchEntry:setTooltip("Type to filter traits...")
    panel.traitSearchEntry.onTextChange = function()
        BurdJournals.UI.DebugPanel.filterCharacterTraitList(self)
    end
    traitsSection:addChild(panel.traitSearchEntry)
    panel.traitPolarityFilter = createDebugTraitPolarityFilter(traitsSection, math.max(sectionPadding, traitSearchX - 92), ty, self, BurdJournals.UI.DebugPanel.filterCharacterTraitList, "Filter player traits by positive/negative polarity.")
    panel.traitSourceFilter = createSectionSourceFilterStrip(traitsSection, self, traitLabelText, traitSearchX, ty, sectionPadding, BurdJournals.UI.DebugPanel.filterCharacterTraitList, "Filter trait rows by source.", charTraitLabelX)
    ty = ty + 24
    local traitListHeight = math.max(96, sectionHeight - 122)
    panel.charTraitList = ISScrollingListBox:new(sectionPadding, ty, contentWidth, traitListHeight)
    panel.charTraitList:initialise()
    panel.charTraitList:instantiate()
    panel.charTraitList.itemheight = 24
    panel.charTraitList.backgroundColor = {r=0.08, g=0.08, b=0.1, a=1}
    panel.charTraitList.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    panel.charTraitList.doDrawItem = BurdJournals.UI.DebugPanel.drawCharacterTraitItem
    panel.charTraitList.onMouseDown = BurdJournals.UI.DebugPanel.onCharacterTraitListClick
    panel.charTraitList.parentPanel = self
    traitsSection:addChild(panel.charTraitList)
    ty = ty + traitListHeight + 6
    panel.traitReconcileTick = ISTickBox:new(sectionPadding, ty - 2, contentWidth, 20, "", self, nil)
    panel.traitReconcileTick:initialise()
    panel.traitReconcileTick:instantiate()
    panel.traitReconcileTick:addOption(getText("UI_BurdJournals_DebugAllowTraitReconciliation") or "Allow Trait Reconciliation")
    panel.traitReconcileTick.selected[1] = false
    if panel.traitReconcileTick.setTooltip then
        panel.traitReconcileTick:setTooltip(getText("UI_BurdJournals_DebugAllowTraitReconciliationTip") or "When enabled, debug trait adds run BSJ trait XP reconciliation after the trait is applied.")
    end
    traitsSection:addChild(panel.traitReconcileTick)
    ty = ty + 24
    createDebugButton(traitsSection, sectionPadding, ty, 122, btnHeight, getText("UI_BurdJournals_DebugAddAllTraits") or "Add All Traits", self, BurdJournals.UI.DebugPanel.onCharCmd, "addalltraits", {r=0.3, g=0.55, b=0.32, a=1}, {r=0.15, g=0.3, b=0.17, a=1})
    createDebugButton(traitsSection, sectionPadding + 128, ty, 118, btnHeight, getText("UI_BurdJournals_DebugAddAllPositiveTraits") or "+ All Positive", self, BurdJournals.UI.DebugPanel.onCharCmd, "addallpositivetraits", {r=0.28, g=0.52, b=0.34, a=1}, {r=0.14, g=0.28, b=0.18, a=1})
    createDebugButton(traitsSection, sectionPadding + 252, ty, 118, btnHeight, getText("UI_BurdJournals_DebugAddAllNegativeTraits") or "+ All Negative", self, BurdJournals.UI.DebugPanel.onCharCmd, "addallnegativetraits", {r=0.55, g=0.42, b=0.22, a=1}, {r=0.3, g=0.22, b=0.12, a=1})
    createDebugButton(traitsSection, sectionPadding + 376, ty, 96, btnHeight, "Dump Traits", self, BurdJournals.UI.DebugPanel.onCharCmd, "dumptraits")
    ty = ty + btnHeight + 6
    createDebugButton(traitsSection, sectionPadding, ty, 122, btnHeight, getText("UI_BurdJournals_DebugRemoveAllTraits") or "Remove All Traits", self, BurdJournals.UI.DebugPanel.onCharCmd, "removealltraits", {r=0.6, g=0.3, b=0.3, a=1}, {r=0.4, g=0.15, b=0.15, a=1})
    createDebugButton(traitsSection, sectionPadding + 128, ty, 118, btnHeight, getText("UI_BurdJournals_DebugRemoveAllPositiveTraits") or "- All Positive", self, BurdJournals.UI.DebugPanel.onCharCmd, "removeallpositivetraits", {r=0.58, g=0.34, b=0.28, a=1}, {r=0.34, g=0.18, b=0.14, a=1})
    createDebugButton(traitsSection, sectionPadding + 252, ty, 118, btnHeight, getText("UI_BurdJournals_DebugRemoveAllNegativeTraits") or "- All Negative", self, BurdJournals.UI.DebugPanel.onCharCmd, "removeallnegativetraits", {r=0.62, g=0.28, b=0.24, a=1}, {r=0.36, g=0.14, b=0.12, a=1})

    local recipesSection = createDebugSectionPanel(panel, padding, y, sectionWidth, sectionHeight)
    panel.characterTabState.panels.recipes = recipesSection
    local ry = sectionPadding
    panel.charRecipeSummaryLabel = ISLabel:new(sectionPadding, ry + 2, 18, "Known recipes for the selected player.", 0.78, 0.82, 0.9, 1, UIFont.Small, true)
    panel.charRecipeSummaryLabel:initialise()
    panel.charRecipeSummaryLabel:instantiate()
    recipesSection:addChild(panel.charRecipeSummaryLabel)
    ry = ry + 20
    local recipeLabelText = getText("UI_BurdJournals_DebugRecipesViewSources")
    local charRecipeLabelX = sectionPadding + 58
    panel.charRecipeBulkTick = createDebugBulkTick(recipesSection, sectionPadding, ry - 1, 52, 20, "All", self, BurdJournals.UI.DebugPanel.onCharacterRecipeBulkToggle, "Learn or forget all visible recipes.")
    local recipeLabel = ISLabel:new(charRecipeLabelX, ry + 2, 18, recipeLabelText, 0.9, 0.9, 0.7, 1, UIFont.Small, true)
    recipeLabel:initialise()
    recipeLabel:instantiate()
    recipesSection:addChild(recipeLabel)
    local recipeSearchX = math.max(210, contentWidth - 160)
    panel.recipeSearchEntry = ISTextEntryBox:new("", recipeSearchX, ry, 150, 20)
    panel.recipeSearchEntry:initialise()
    panel.recipeSearchEntry:instantiate()
    panel.recipeSearchEntry.font = UIFont.Small
    panel.recipeSearchEntry:setTooltip("Type to filter recipes...")
    panel.recipeSearchEntry.onTextChange = function()
        BurdJournals.UI.DebugPanel.filterCharacterRecipeList(self)
    end
    recipesSection:addChild(panel.recipeSearchEntry)
    panel.recipeSourceFilter = createSectionSourceFilterStrip(recipesSection, self, recipeLabelText, recipeSearchX, ry, sectionPadding, BurdJournals.UI.DebugPanel.filterCharacterRecipeList, "Filter recipe rows by source.", charRecipeLabelX)
    ry = ry + 24
    local recipeListHeight = math.max(120, sectionHeight - 88)
    panel.charRecipeList = ISScrollingListBox:new(sectionPadding, ry, contentWidth, recipeListHeight)
    panel.charRecipeList:initialise()
    panel.charRecipeList:instantiate()
    panel.charRecipeList.itemheight = 30
    panel.charRecipeList.backgroundColor = {r=0.08, g=0.08, b=0.1, a=1}
    panel.charRecipeList.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    panel.charRecipeList.doDrawItem = BurdJournals.UI.DebugPanel.drawCharacterRecipeItem
    panel.charRecipeList.onMouseDown = BurdJournals.UI.DebugPanel.onCharacterRecipeListClick
    panel.charRecipeList.parentPanel = self
    recipesSection:addChild(panel.charRecipeList)
    ry = ry + recipeListHeight + 6
    createDebugButton(recipesSection, sectionPadding, ry, 104, btnHeight, "Dump Recipes", self, BurdJournals.UI.DebugPanel.onCharCmd, "dumprecipes")

    setDebugSubTabState(panel.characterTabState, "skills")

    -- Store reference
    self.charPanel = panel
    panel.targetPlayer = self.player  -- Default to current player
    
    -- Initial population
    self:populateCharacterPlayerList()
    self:refreshCharacterData()
end

function BurdJournals.UI.DebugPanel:onCharacterSubTab(button)
    local panel = self.charPanel
    if not (panel and panel.characterTabState and button and button.internal) then
        return
    end
    setDebugSubTabState(panel.characterTabState, tostring(button.internal))
end

-- Populate player dropdown with online players
function BurdJournals.UI.DebugPanel:populateCharacterPlayerList()
    local panel = self.charPanel
    if not panel or not panel.targetPlayerCombo then return end

    local selectedPlayer = panel.targetPlayer or self:getSharedTargetPlayer() or self.player
    local selectedName = getDebugTargetPlayerName(selectedPlayer)

    panel.targetPlayerCombo:clear()

    local targetablePlayers = collectDebugTargetablePlayers(self)
    for _, playerObj in ipairs(targetablePlayers) do
        panel.targetPlayerCombo:addOptionWithData(getDebugTargetPlayerName(playerObj), playerObj)
    end

    if panel.targetPlayerCombo.select then
        panel.targetPlayerCombo:select(selectedName)
    else
        panel.targetPlayerCombo.selected = 1
    end
    panel.targetPlayer = selectedPlayer
end

-- Handle player selection change
function BurdJournals.UI.DebugPanel:onCharacterTargetPlayerChange(combo)
    if self.suppressTargetSync then
        return
    end

    local panel = self.charPanel
    if not panel then return end
    
    local selectedPlayer = getDebugComboSelectedData(combo)
    if selectedPlayer then
        self:applySharedTargetPlayer(selectedPlayer, {
            statusText = BurdJournals.formatText(getText("UI_BurdJournals_DebugViewingPlayer"), getDebugTargetPlayerName(selectedPlayer)),
        })
    end
end

-- Refresh button handler
function BurdJournals.UI.DebugPanel:onCharacterRefresh()
    self:populateCharacterPlayerList()
    self:refreshCharacterData()
    self:setStatus("Character data refreshed", {r=0.5, g=0.8, b=1})
end

function BurdJournals.UI.DebugPanel:updateCharacterSummary()
    local panel = self.charPanel
    if not panel then
        return
    end

    local targetPlayer = panel.targetPlayer or self:getSharedTargetPlayer() or self.player
    local targetName = getDebugTargetPlayerName(targetPlayer)

    if panel.characterSummaryLabel then
        panel.characterSummaryLabel:setName("Viewing " .. targetName .. ". Skill and trait changes on this tab apply to that player.")
    end

    if panel.characterHelpLabel then
        local helpText
        if not BurdJournals.UI.DebugPanel.isDiminishingEnabled() then
            helpText = getText("UI_BurdJournals_DebugReclaimHistoryDisabled")
                or "Journal reclaim reduction is disabled. Turn on diminished XP recovery to inspect reclaim history."
        else
            local journalName = self.editingJournal and self.editingJournal.getName and self.editingJournal:getName() or nil
            if journalName and journalName ~= "" then
                helpText = BurdJournals.formatText(
                    getText("UI_BurdJournals_DebugReclaimPreviewReady")
                        or "Journal reclaim preview is ready for %s. Open Journal Editor and select a skill to inspect the next reclaim values.",
                    targetName
                )
            else
                helpText = BurdJournals.formatText(
                    getText("UI_BurdJournals_DebugReclaimJournalBased")
                        or "Journal reclaim reduction is journal-based. Open Journal Editor, load a journal, and pick a skill to inspect the next reclaim values for %s.",
                    targetName
                )
            end
        end
        panel.characterHelpLabel:setName(helpText)
    end
end

-- Refresh character skill/trait data
function BurdJournals.UI.DebugPanel:refreshCharacterData(authoritativeRefresh)
    local panel = self.charPanel
    if not panel then return end
    
    local targetPlayer = panel.targetPlayer or self.player
    if not targetPlayer then 
        -- No player yet, skip population
        return 
    end
    panel.targetPlayer = targetPlayer
    self:updateCharacterSummary()
    local targetUsername = targetPlayer and targetPlayer.getUsername and targetPlayer:getUsername() or nil
    local authoritativeData = nil
    if targetUsername and self.authoritativeCharacterData then
        authoritativeData = self.authoritativeCharacterData[tostring(targetUsername)]
    end
    if BurdJournals.clientShouldUseServerAuthority()
        and not self:isCharacterTargetLocal()
        and authoritativeRefresh ~= true
    then
        self:requestAuthoritativeCharacterData("refresh")
        if type(authoritativeData) ~= "table" and self.setStatus then
            self:setStatus("Requesting authoritative target data...", {r=0.5, g=0.8, b=1})
        end
        return
    end

    -- Clear existing lists safely
    if panel.charSkillList and panel.charSkillList.clear then 
        panel.charSkillList:clear()
        panel.charSkillList._debugFilterSignature = nil
        panel.charSkillList._debugFilterItemCount = nil
    end
    if panel.charTraitList and panel.charTraitList.clear then 
        panel.charTraitList:clear()
        panel.charTraitList._debugFilterSignature = nil
        panel.charTraitList._debugFilterItemCount = nil
    end
    if panel.charRecipeList and panel.charRecipeList.clear then
        panel.charRecipeList:clear()
        panel.charRecipeList._debugFilterSignature = nil
        panel.charRecipeList._debugFilterItemCount = nil
    end
    
    -- Populate skills using dynamic discovery
    local skillMetadata = {}
    if BurdJournals.discoverSkillMetadata then
        skillMetadata = BurdJournals.discoverSkillMetadata(true) or {}
    end
    
    -- Get player's XP object safely
    local xpObj = nil
    if targetPlayer and targetPlayer.getXp then
        xpObj = targetPlayer:getXp()
    end
    
    -- If we still don't have xpObj, try refreshing targetPlayer reference
    if not xpObj and targetPlayer and targetPlayer.getUsername then
        -- Re-fetch player reference (in case it went stale)
        local username = targetPlayer:getUsername()
        if username then
            local onlinePlayers = getOnlinePlayers and getOnlinePlayers()
            if onlinePlayers then
                for i = 0, onlinePlayers:size() - 1 do
                    local p = onlinePlayers:get(i)
                    if p and p.getUsername and p:getUsername() == username then
                        targetPlayer = p
                        panel.targetPlayer = p
                        if p.getXp then
                            xpObj = p:getXp()
                        end
                        break
                    end
                end
            end
        end
    end
    
    -- Sort skills by category then name
    local sortedSkills = {}
    for skillName, metadata in pairs(skillMetadata) do
        table.insert(sortedSkills, {
            name = skillName,
            displayName = metadata.displayName or skillName,
            category = metadata.category or "Other",
            isVanilla = metadata.isVanilla,
            isPassive = metadata.isPassive,
            perkId = metadata.id
        })
    end
    table.sort(sortedSkills, function(a, b)
        if a.category ~= b.category then
            return a.category < b.category
        end
        return a.displayName < b.displayName
    end)
    
    -- Add skills to list
    for _, skill in ipairs(sortedSkills) do
        local level = 0
        local currentXP = 0
        
        -- Get perk object
        local perk = nil
        if BurdJournals.getPerkByName then
            perk = BurdJournals.getPerkByName(skill.name)
        end
        
        -- Fallback: try Perks directly
        if not perk and Perks then
            local perkId = skill.perkId or skill.name
            if Perks[perkId] then perk = Perks[perkId] end
        end
        
        if perk and targetPlayer then
            -- Method 1: getPerkLevel (most reliable)
            if targetPlayer.getPerkLevel then
                local result = targetPlayer:getPerkLevel(perk)
                if type(result) == "number" then
                    level = result
                end
            end
            
            -- Method 2: Get XP and calculate level (fallback)
            if level == 0 and xpObj and xpObj.getXP then
                local xp = BurdJournals.getPlayerSkillTotalXP and BurdJournals.getPlayerSkillTotalXP(targetPlayer, perk, skill.name) or xpObj:getXP(perk)
                if type(xp) == "number" and xp > 0 then
                    currentXP = xp
                    -- Calculate level from XP using corrected helper
                    if BurdJournals.Client.Debug.getLevelFromXP then
                        level = BurdJournals.Client.Debug.getLevelFromXP(skill.name, xp)
                    elseif perk.getTotalXpForLevel then
                        -- Fallback: getTotalXpForLevel(N) = XP to COMPLETE level N
                        -- So level N requires XP >= getTotalXpForLevel(N-1)
                        for l = 10, 1, -1 do
                            local threshold = perk:getTotalXpForLevel(l - 1) or 0
                            if xp >= threshold then
                                level = l
                                break
                            end
                        end
                    end
                end
            end
            
            -- Get current XP if we didn't already
            if currentXP == 0 and xpObj and xpObj.getXP then
                local xp = BurdJournals.getPlayerSkillTotalXP and BurdJournals.getPlayerSkillTotalXP(targetPlayer, perk, skill.name) or xpObj:getXP(perk)
                if type(xp) == "number" then
                    currentXP = xp
                end
            end
        end
        local remoteSkill = authoritativeData
            and type(authoritativeData.skills) == "table"
            and authoritativeData.skills[skill.name]
            or nil
        if type(remoteSkill) == "table" then
            level = tonumber(remoteSkill.level) or level
            currentXP = tonumber(remoteSkill.xp) or currentXP
        end
        
        local prefix = skill.isVanilla == false and "[MOD] " or ""
        local itemText = prefix .. skill.displayName
        local source = BurdJournals.getSkillModSource and BurdJournals.getSkillModSource(skill.name) or (skill.isVanilla == false and "Modded" or "Vanilla")
        local sourceId = BurdJournals.getSkillModId and BurdJournals.getSkillModId(skill.name) or (skill.isVanilla == false and "modded" or "vanilla")
        
        if panel.charSkillList then
            panel.charSkillList:addItem(itemText, {
                name = skill.name,
                displayName = skill.displayName,
                category = skill.category,
                level = level,
                currentXP = currentXP,
                isPassive = skill.isPassive,
                isVanilla = skill.isVanilla,
                source = source,
                sourceId = sourceId,
            })
        end
    end
    
    -- Populate traits using the comprehensive discovery (same as Spawn panel)
    local allTraits = {}
    local addedTraits = {}  -- For deduplication
    
    -- Use discoverGrantableTraits (includes negative traits for debug panel)
    -- This discovers ALL traits including modded ones and neutral/profession traits
    local discoveredTraits = {}
    if BurdJournals and BurdJournals.discoverGrantableTraits then
        local result = BurdJournals.discoverGrantableTraits(true)  -- true = include negative
        if result and type(result) == "table" then
            discoveredTraits = result
        end
    end
    
    -- Fallback to older methods if discovery failed
    if #discoveredTraits == 0 then
        local positiveTraits = BurdJournals.getPositiveTraits and BurdJournals.getPositiveTraits() or {}
        local negativeTraits = BurdJournals.getNegativeTraits and BurdJournals.getNegativeTraits() or {}
        for _, t in ipairs(positiveTraits) do table.insert(discoveredTraits, t) end
        for _, t in ipairs(negativeTraits) do table.insert(discoveredTraits, t) end
    end
    
    local traitCostLookup = BurdJournals.UI.DebugPanel.buildTraitCostLookup()

    -- Determine trait polarity from the shared resolver and deduplicate by display name.
    -- This keeps the DebugPanel aligned even when trait definitions expose aliases.
    local addedDisplayNames = {}  -- Track display names to prevent visual duplicates
    for _, traitId in ipairs(discoveredTraits) do
        local lowerTraitId = string.lower(traitId)
        if not addedTraits[lowerTraitId] then
            -- Get display name first to check for duplicates
            local displayName = traitId
            if BurdJournals.getTraitDisplayName then
                displayName = BurdJournals.getTraitDisplayName(traitId) or traitId
            end
            local displayNameLower = string.lower(displayName)
            
            -- Skip if we already have a trait with this display name (B42 variant handling)
            if not addedDisplayNames[displayNameLower] then
                addedTraits[lowerTraitId] = true
                addedDisplayNames[displayNameLower] = traitId
                local traitSource = BurdJournals.getTraitModSource and BurdJournals.getTraitModSource(traitId) or "Vanilla"
                local traitSourceId = BurdJournals.getTraitModId and BurdJournals.getTraitModId(traitId) or traitSource
                
                local isPositive = BurdJournals.UI.DebugPanel.resolveTraitIsPositive(traitId, nil, traitCostLookup)
                
                table.insert(allTraits, {
                    id = traitId,
                    isPositive = isPositive,
                    source = traitSource,
                    sourceId = traitSourceId,
                    isModded = traitSource ~= "Vanilla",
                })
            end
        end
    end
    
    -- Sort traits alphabetically
    table.sort(allTraits, function(a, b)
        return a.id < b.id
    end)
    
    -- Count how many times player has each trait
    -- Use multiple detection methods for reliability
    local playerTraitCounts = {}
    
    if authoritativeData and type(authoritativeData.traits) == "table" then
        for traitId, count in pairs(authoritativeData.traits) do
            playerTraitCounts[string.lower(tostring(traitId))] = tonumber(count) or 1
            playerTraitCounts[tostring(traitId)] = tonumber(count) or 1
        end
    elseif targetPlayer then
        -- Method 1: player:getTraits() - runtime trait list (may have duplicates from debug)
        if targetPlayer.getTraits then
            local playerTraits = targetPlayer:getTraits()
            if playerTraits and playerTraits.size then
                for i = 0, playerTraits:size() - 1 do
                    local traitId = playerTraits:get(i)
                    if traitId then
                        local lower = string.lower(tostring(traitId))
                        playerTraitCounts[lower] = (playerTraitCounts[lower] or 0) + 1
                        playerTraitCounts[traitId] = (playerTraitCounts[traitId] or 0) + 1
                    end
                end
            end
        end
    end
    
    -- Store reference to target player for HasTrait checks below
    local traitCheckPlayer = authoritativeData and nil or targetPlayer
    
    -- Add traits to list
    for _, trait in ipairs(allTraits) do
        local displayName = trait.id
        if BurdJournals.getTraitDisplayName then
            displayName = BurdJournals.getTraitDisplayName(trait.id) or trait.id
        end
        
        -- Check if player has this trait (and how many)
        local count = playerTraitCounts[string.lower(trait.id)] or playerTraitCounts[trait.id] or 0
        
        -- Fallback: use the comprehensive BurdJournals.playerHasTrait function
        -- This properly checks hasTrait with trait object, HasTrait with string, etc.
        if count == 0 and traitCheckPlayer and BurdJournals.playerHasTrait then
            if BurdJournals.playerHasTrait(traitCheckPlayer, trait.id) then
                count = 1
            end
        end
        
        if panel.charTraitList then
            panel.charTraitList:addItem(displayName, {
                id = trait.id,
                displayName = displayName,
                isPositive = trait.isPositive,
                hasCount = count,
                isPassiveSkillTrait = BurdJournals.isPassiveSkillTrait and BurdJournals.isPassiveSkillTrait(trait.id),
                traitTexture = getDebugTraitTexture(trait.id),
                source = trait.source,
                sourceId = trait.sourceId,
                isModded = trait.isModded,
            })
        end
    end

    local recipeRows = buildDebugRecipeRows(targetPlayer, true, false)
    if authoritativeData and type(authoritativeData.recipes) == "table" then
        local knownRecipes = authoritativeData.recipes
        local seen = {}
        for _, row in ipairs(recipeRows) do
            local known = knownRecipes[row.name] == true
            row.isKnown = known
            seen[row.name] = true
        end
        for recipeName, known in pairs(knownRecipes) do
            if known == true and not seen[recipeName] then
                local magazineSource = BurdJournals.getMagazineForRecipe and BurdJournals.getMagazineForRecipe(recipeName) or nil
                recipeRows[#recipeRows + 1] = {
                    name = recipeName,
                    displayName = BurdJournals.getRecipeDisplayName and BurdJournals.getRecipeDisplayName(recipeName) or tostring(recipeName),
                    source = BurdJournals.getRecipeModSource and BurdJournals.getRecipeModSource(recipeName, magazineSource) or "Unknown",
                    sourceId = BurdJournals.getRecipeModId and BurdJournals.getRecipeModId(recipeName, magazineSource) or nil,
                    magazineSource = magazineSource,
                    magazineDisplayName = magazineSource and BurdJournals.getMagazineDisplayName and BurdJournals.getMagazineDisplayName(magazineSource) or nil,
                    isKnown = true,
                    isBaseline = false,
                    hasMagazine = magazineSource ~= nil and tostring(magazineSource) ~= "",
                }
            end
        end
        sortDebugRecipeRows(recipeRows)
    end
    for _, row in ipairs(recipeRows) do
        row.recipeTexture = getDebugRecipeTexture()
        row.magazineTexture = getDebugMagazineTexture(row.magazineSource)
        row.magazineDisplayName = row.magazineDisplayName or (row.magazineSource and BurdJournals.getMagazineDisplayName and BurdJournals.getMagazineDisplayName(row.magazineSource) or nil)
        if panel.charRecipeList then
            panel.charRecipeList:addItem(row.displayName, row)
        end
    end
    if panel.charRecipeSummaryLabel then
        panel.charRecipeSummaryLabel:setName(BurdJournals.formatText("Runtime recipes for selected player: %d", #recipeRows))
    end
    refreshDebugSourceFilterStrip(panel.skillSourceFilter, panel.charSkillList and panel.charSkillList.items or nil)
    refreshDebugSourceFilterStrip(panel.traitSourceFilter, panel.charTraitList and panel.charTraitList.items or nil)
    refreshDebugSourceFilterStrip(panel.recipeSourceFilter, panel.charRecipeList and panel.charRecipeList.items or nil)

    BurdJournals.UI.DebugPanel.filterCharacterSkillList(self)
    BurdJournals.UI.DebugPanel.filterCharacterTraitList(self)
    BurdJournals.UI.DebugPanel.filterCharacterRecipeList(self)
end

-- Draw function for character skill items with interactive level visualizer
function BurdJournals.UI.DebugPanel.drawCharacterSkillItem(self, y, item, alt)
    -- Safety checks for required values
    local h = getDebugListRowHeight(self, item, 24)
    
    -- CRITICAL: Must always return y + h for ISScrollingListBox
    if not item or not item.item then return y + h end
    local data = item.item
    if not data then return y + h end
    
    -- Skip hidden items (filtered by search)
    if data.hidden then return y + h end
    
    -- Ensure we have valid dimensions
    local w = self.width or 300
    local scrollOffset = BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH
    
    -- Check if this skill is selected for XP addition
    local parentPanel = self.parentPanel
    local charPanel = parentPanel and parentPanel.charPanel
    local isSelected = charPanel and charPanel.focusedSkill == data.name
    
    -- Background - highlight if selected
    if isSelected then
        self:drawRect(0, y, w, h, 0.3, 0.2, 0.4, 0.3)
    elseif self.mouseoverselected == item.index then
        self:drawRect(0, y, w, h, 0.2, 0.2, 0.3, 0.3)
    elseif data.isPassive then
        self:drawRect(0, y, w, h, 0.1, 0.15, 0.2, 0.2)
    end
    
    -- Skill name (with category in dim text)
    local nameX = 8
    local nameColor = data.isVanilla == false and {0.6, 0.8, 1} or {1, 1, 1}
    if isSelected then nameColor = {1, 1, 0.6} end  -- Yellow when selected
    self:drawText(data.displayName, nameX, y + 4, nameColor[1], nameColor[2], nameColor[3], 1, UIFont.Small)
    
    -- Level text
    local levelText = BurdJournals.formatText(getText("UI_BurdJournals_LevelFormat"), tonumber(data.level) or 0)
    local levelX = 140
    self:drawText(levelText, levelX, y + 4, 0.8, 0.8, 0.5, 1, UIFont.Small)
    
    -- Interactive level squares (0-10) with progress visualization
    local squaresX = 185
    local squareSize = 12
    local squareSpacing = 2
    local currentLevel = data.level or 0
    local currentXP = data.currentXP or 0
    
    -- Calculate progress within current level (0-1)
    local progress = 0
    if currentLevel < 10 then
        local perk = BurdJournals.getPerkByName and BurdJournals.getPerkByName(data.name)
        if perk and perk.getTotalXpForLevel then
            -- XP needed to BE at current level (threshold for current level)
            local levelStartXP = currentLevel > 0 and (perk:getTotalXpForLevel(currentLevel - 1) or 0) or 0
            -- XP needed to reach next level
            local levelEndXP = perk:getTotalXpForLevel(currentLevel) or (levelStartXP + 150)
            local xpRange = levelEndXP - levelStartXP
            if xpRange > 0 then
                progress = math.max(0, math.min(1, (currentXP - levelStartXP) / xpRange))
            end
        end
    end
    
    for i = 1, 10 do
        local sqX = squaresX + (i - 1) * (squareSize + squareSpacing)
        local sqY = y + (h - squareSize) / 2
        
        if i <= currentLevel then
            -- Filled square (has this level)
            self:drawRect(sqX, sqY, squareSize, squareSize, 0.9, 0.4, 0.7, 0.4)
        elseif i == currentLevel + 1 and progress > 0 then
            -- Partial progress square - show fill from bottom
            self:drawRect(sqX, sqY, squareSize, squareSize, 0.6, 0.15, 0.15, 0.2)
            local fillHeight = squareSize * progress
            self:drawRect(sqX, sqY + squareSize - fillHeight, squareSize, fillHeight, 0.8, 0.3, 0.5, 0.35)
        else
            -- Empty square
            self:drawRect(sqX, sqY, squareSize, squareSize, 0.5, 0.15, 0.15, 0.2)
        end
        -- Border
        self:drawRectBorder(sqX, sqY, squareSize, squareSize, 0.8, 0.4, 0.5, 0.6)
    end
    
    -- XP display (simple text after squares)
    local squaresEndX = squaresX + 10 * (squareSize + squareSpacing)
    local xpDisplayX = squaresEndX + 8
    local currentXP = data.currentXP or 0
    
    -- Format XP display
    local xpText = tostring(math.floor(currentXP)) .. " XP"
    local xpColor = isSelected and {1, 1, 0.6} or {0.6, 0.8, 0.6}
    self:drawText(xpText, xpDisplayX, y + 4, xpColor[1], xpColor[2], xpColor[3], 1, UIFont.Small)
    
    -- Passive indicator (moved to accommodate XP display, account for scrollbar)
    if data.isPassive then
        local scrollOffset = BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH
        self:drawText("[P]", w - 25 - scrollOffset, y + 4, 0.5, 0.7, 0.9, 0.7, UIFont.Small)
    end
    
    -- CRITICAL: Must return y + h for ISScrollingListBox
    return y + h
end

-- Click handler for character skill list (set skill level)
function BurdJournals.UI.DebugPanel.onCharacterSkillListClick(self, x, y)
    local row = BurdJournals.UI.DebugPanel.safeListMouseDown(self, x, y)
    
    -- Safety checks
    if not self.items then return end
    if not row or row <= 0 or row > #self.items then return end
    
    local item = self.items[row]
    if not item or not item.item then return end
    local data = item.item
    if not data then return end
    
    local parentPanel = self.parentPanel
    if not parentPanel then return end
    local charPanel = parentPanel.charPanel
    local targetPlayer = charPanel and charPanel.targetPlayer or parentPanel.player
    if not targetPlayer then return end
    
    -- Check if click is in the squares area
    local squaresX = 185
    local squareSize = 12
    local squareSpacing = 2
    local squaresEndX = squaresX + 10 * (squareSize + squareSpacing)
    
    if x >= squaresX and x <= squaresEndX then
        -- Calculate which level was clicked
        local relX = x - squaresX
        local clickedLevel = math.floor(relX / (squareSize + squareSpacing)) + 1
        clickedLevel = math.max(0, math.min(10, clickedLevel))
        
        -- If clicking on current level, set to 0 (toggle off)
        if clickedLevel == data.level then
            clickedLevel = 0
        end
        
        -- Set the skill level - update UI immediately (optimistic)
        data.level = clickedLevel
        parentPanel:setStatus("Set " .. data.displayName .. " to level " .. clickedLevel, {r=0.3, g=1, b=0.5})
        
        if BurdJournals.clientShouldUseServerAuthority() then
            -- Multiplayer: send to server
            sendClientCommand("BurdJournals", "debugSetSkill", {
                skillName = data.name,
                level = clickedLevel,
                targetUsername = targetPlayer:getUsername()
            })
        else
            -- Singleplayer: apply directly
            local perk = BurdJournals.getPerkByName and BurdJournals.getPerkByName(data.name)
            if perk and targetPlayer then
                local perkName = tostring(perk)
                local isPassive = (perkName == "Fitness" or perkName == "Strength")
                
                -- For passive skills, remove existing passive traits FIRST
                -- This prevents the trait system from bouncing the skill back
                if isPassive then
                    BurdJournals.UI.DebugPanel.removePassiveSkillTraits(targetPlayer, perkName)
                end
                
                if isPassive then
                    -- For passive skills, use setPerkLevelDebug which directly sets level
                    -- This bypasses XP scaling issues that affect Strength specifically
                    targetPlayer:setPerkLevelDebug(perk, clickedLevel)
                else
                    local targetXP = 0
                    if clickedLevel > 0 then
                        targetXP = (BurdJournals.getXPThresholdForLevel and BurdJournals.getXPThresholdForLevel(data.name, clickedLevel))
                            or (perk.getTotalXpForLevel and perk:getTotalXpForLevel(clickedLevel))
                            or 0
                    end
                    if BurdJournals.setSkillTotalXPCompat then
                        BurdJournals.setSkillTotalXPCompat(targetPlayer, perk, targetXP, data.name)
                    end
                end
            end
        end
    end
    
    -- Always select this skill for XP addition (clicking anywhere on the row)
    charPanel.focusedSkill = data.name
    BurdJournals.UI.DebugPanel.updateCharacterXPLabel(parentPanel)
end

-- Update skill name label when a skill is selected
function BurdJournals.UI.DebugPanel.updateCharacterXPLabel(self)
    local panel = self.charPanel
    if not panel then return end
    
    local focusedSkillName = panel.focusedSkill
    local focusedData = nil
    
    -- Find the focused skill data
    if focusedSkillName and panel.charSkillList then
        for _, itemData in ipairs(panel.charSkillList.items) do
            if itemData.item and itemData.item.name == focusedSkillName then
                focusedData = itemData.item
                break
            end
        end
    end
    
    if focusedData then
        -- Update skill name label to show selected skill
        if panel.xpSkillLabel then
            panel.xpSkillLabel:setName(focusedData.displayName .. " (" .. math.floor(focusedData.currentXP or 0) .. " XP)")
            panel.xpSkillLabel.r = 1
            panel.xpSkillLabel.g = 1
            panel.xpSkillLabel.b = 0.6
        end
    else
        -- No skill focused
        if panel.xpSkillLabel then
            panel.xpSkillLabel:setName("Click skill row to select")
            panel.xpSkillLabel.r = 0.5
            panel.xpSkillLabel.g = 0.6
            panel.xpSkillLabel.b = 0.7
        end
    end
end

-- Add XP to focused skill (simple addition to current XP)
function BurdJournals.UI.DebugPanel:onCharacterAddXP()
    local panel = self.charPanel
    if not panel then return end
    
    local focusedSkillName = panel.focusedSkill
    if not focusedSkillName then
        self:setStatus("No skill selected - click a skill row first", {r=1, g=0.5, b=0.5})
        return
    end
    
    local targetPlayer = panel.targetPlayer or self.player
    if not targetPlayer then return end
    
    -- Get XP amount to add from input
    local xpText = panel.xpEntry and panel.xpEntry:getText() or "0"
    local xpToAdd = tonumber(xpText) or 0
    xpToAdd = math.max(0, math.floor(xpToAdd))
    
    if xpToAdd <= 0 then
        self:setStatus("Enter a positive XP amount to add", {r=1, g=0.5, b=0.5})
        return
    end
    
    -- Find the focused skill data to update
    local focusedData = nil
    if panel.charSkillList then
        for _, itemData in ipairs(panel.charSkillList.items) do
            if itemData.item and itemData.item.name == focusedSkillName then
                focusedData = itemData.item
                break
            end
        end
    end
    
    if not focusedData then
        self:setStatus("Skill not found: " .. focusedSkillName, {r=1, g=0.5, b=0.5})
        return
    end
    
    -- Calculate new XP total
    local currentXP = focusedData.currentXP or 0
    local newXP = currentXP + xpToAdd
    
    -- Update local data optimistically
    focusedData.currentXP = newXP
    
    -- Get perk for level calculation and game API
    local perk = BurdJournals.getPerkByName and BurdJournals.getPerkByName(focusedSkillName)
    
    self:setStatus("Added " .. xpToAdd .. " XP to " .. focusedData.displayName .. " (now " .. math.floor(newXP) .. " XP)", {r=0.3, g=1, b=0.5})
    
    -- Apply to game
    if BurdJournals.clientShouldUseServerAuthority() then
        -- Multiplayer: send to server to add XP
        sendClientCommand("BurdJournals", "debugAddSkillXP", {
            skillName = focusedSkillName,
            xpToAdd = xpToAdd,
            targetUsername = targetPlayer:getUsername()
        })
    else
        -- Singleplayer: apply directly using AddXP
        if perk and targetPlayer then
            applyDebugXPCompat(targetPlayer, perk, xpToAdd, {
                skillName = focusedSkillName,
                useMultipliers = false,
                isPassive = false,
            })
        end
    end
    
    -- Schedule a UI refresh after a short delay to show updated values
    local selfRef = self
    local skillName = focusedSkillName
    if Events and Events.OnTick then
        local tickCount = 0
        local refreshHandler = nil
        refreshHandler = function()
            tickCount = tickCount + 1
            if tickCount >= 10 then  -- ~166ms delay at 60 FPS
                Events.OnTick.Remove(refreshHandler)
                if selfRef and selfRef.refreshCharacterData then
                    selfRef:refreshCharacterData()
                    -- Re-select the skill and update label
                    if selfRef.charPanel then
                        selfRef.charPanel.focusedSkill = skillName
                        BurdJournals.UI.DebugPanel.updateCharacterXPLabel(selfRef)
                    end
                end
            end
        end
        Events.OnTick.Add(refreshHandler)
    end
end

-- Draw function for character trait items with journal-editor style checkboxes
function BurdJournals.UI.DebugPanel.drawCharacterTraitItem(self, y, item, alt)
    -- Safety checks for required values
    local h = getDebugListRowHeight(self, item, 24)
    
    -- CRITICAL: Must always return y + h for ISScrollingListBox
    if not item or not item.item then return y + h end
    local data = item.item
    if not data then return y + h end
    
    -- Skip hidden items (filtered by search)
    if data.hidden then return y + h end
    
    -- Ensure we have valid dimensions
    local w = self.width or 300
    
    -- Ensure hasCount is a number
    data.hasCount = data.hasCount or 0
    
    -- Background based on trait type and ownership
    if data.isPassiveSkillTrait then
        self:drawRect(0, y, w, h, 0.15, 0.15, 0.15, 0.15)
    elseif data.hasCount > 0 then
        self:drawRect(0, y, w, h, 0.12, 0.2, 0.12, 0.3)
    elseif self.mouseoverselected == item.index then
        self:drawRect(0, y, w, h, 0.2, 0.2, 0.3, 0.3)
    end
    
    local checkX = 8
    if data.hasCount > 0 then
        self:drawText("[X]", checkX, y + 4, 0.45, 0.85, 0.45, 1, UIFont.Small)
    else
        self:drawText("[ ]", checkX, y + 4, data.isPassiveSkillTrait and 0.35 or 0.58, data.isPassiveSkillTrait and 0.35 or 0.58, data.isPassiveSkillTrait and 0.35 or 0.58, 1, UIFont.Small)
    end

    local iconX = 30
    local iconSize = drawDebugListIcon(self, data.traitTexture or getDebugTraitTexture(data.id), iconX, y, h, 0.95, 14)
    local textX = iconX + math.max(iconSize, 14) + 6

    -- Trait name
    local nameColor = BurdJournals.UI.DebugPanel.getTraitPolarityColor(data)
    self:drawText(BurdJournals.UI.DebugPanel.getTraitPolarityPrefix(data) .. " " .. tostring(data.displayName or data.id or "Unknown"), textX, y + 4, nameColor[1], nameColor[2], nameColor[3], 1, UIFont.Small)

    local scrollOffset = BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH or 15
    local statusX = w - 108 - scrollOffset
    if data.isPassiveSkillTrait then
        self:drawText("Passive", statusX, y + 4, 0.4, 0.4, 0.4, 0.85, UIFont.Small)
    elseif data.hasCount > 1 then
        self:drawText("Owned x" .. tostring(data.hasCount), statusX, y + 4, 0.52, 0.82, 0.52, 1, UIFont.Small)
    elseif data.hasCount > 0 then
        self:drawText("Owned", statusX, y + 4, 0.52, 0.82, 0.52, 1, UIFont.Small)
    else
        self:drawText(BurdJournals.UI.DebugPanel.getTraitPolarityText(data), statusX, y + 4, nameColor[1], nameColor[2], nameColor[3], 0.95, UIFont.Small)
    end

    -- CRITICAL: Must return y + h for ISScrollingListBox
    return y + h
end

-- Click handler for character trait list (checkbox row toggle)
function BurdJournals.UI.DebugPanel.onCharacterTraitListClick(self, x, y)
    local row = BurdJournals.UI.DebugPanel.safeListMouseDown(self, x, y)
    
    -- Safety checks
    if not self.items then return end
    if not row or row <= 0 or row > #self.items then return end
    
    local item = self.items[row]
    if not item or not item.item then return end
    local data = item.item
    if not data then return end
    
    local parentPanel = self.parentPanel
    if not parentPanel then return end
    local charPanel = parentPanel.charPanel
    local targetPlayer = charPanel and charPanel.targetPlayer or parentPanel.player
    if not targetPlayer then return end
    
    -- Don't allow modifying passive skill traits
    if data.isPassiveSkillTrait then
        parentPanel:setStatus("Passive skill traits cannot be modified", {r=1, g=0.6, b=0.3})
        return
    end
    
    if (tonumber(data.hasCount) or 0) <= 0 then
        data.hasCount = (data.hasCount or 0) + 1
        parentPanel:setStatus("Added trait: " .. data.displayName, {r=0.3, g=1, b=0.5})
        local addOpts = BurdJournals.UI.DebugPanel.buildDebugTraitAddOptions(parentPanel)
        
        if BurdJournals.clientShouldUseServerAuthority() then
            -- Multiplayer: send to server
            sendClientCommand("BurdJournals", "debugAddTrait", {
                traitId = data.id,
                allowTraitReconciliation = not (addOpts and addOpts.skipTraitReconciliation == true),
                targetUsername = targetPlayer:getUsername()
            })
        else
            -- Singleplayer: apply directly
            if BurdJournals.safeAddTrait then
                local added = BurdJournals.safeAddTrait(targetPlayer, data.id, addOpts)
                if added
                    and not (addOpts and addOpts.skipTraitReconciliation == true)
                    and BurdJournals.Server
                    and BurdJournals.Server.resolveAndRemoveTraitConflicts then
                    BurdJournals.Server.resolveAndRemoveTraitConflicts(targetPlayer, data.id)
                end
            end
        end
        BurdJournals.UI.DebugPanel.refreshCharacterBulkToggles(parentPanel)

    else
        -- Update UI immediately (optimistic)
        data.hasCount = 0
        parentPanel:setStatus("Removed: " .. data.displayName, {r=0.3, g=1, b=0.5})
        
        if BurdJournals.clientShouldUseServerAuthority() then
            -- Multiplayer: send to server
            sendClientCommand("BurdJournals", "debugRemoveTrait", {
                traitId = data.id,
                removeAll = true,
                targetUsername = targetPlayer:getUsername()
            })
        else
            -- Singleplayer: remove all instances using safeRemoveTrait if available
            if BurdJournals.safeRemoveTrait then
                BurdJournals.safeRemoveTrait(targetPlayer, data.id)
            elseif targetPlayer and targetPlayer.getTraits then
                local traits = targetPlayer:getTraits()
                if traits and traits.size then
                    local toRemove = {}
                    for i = 0, traits:size() - 1 do
                        local t = traits:get(i)
                        if t then
                            local tNorm = BurdJournals.UI.DebugPanel.normalizeTraitId(t) or t
                            local idNorm = BurdJournals.UI.DebugPanel.normalizeTraitId(data.id) or data.id
                            if (BurdJournals.traitIdsMatch and BurdJournals.traitIdsMatch(tNorm, idNorm))
                                or string.lower(tostring(tNorm)) == string.lower(tostring(idNorm)) then
                                table.insert(toRemove, t)
                            end
                        end
                    end
                    for _, t in ipairs(toRemove) do
                        if traits.remove then
                            traits:remove(t)
                        end
                    end
                end
            end
        end
        BurdJournals.UI.DebugPanel.refreshCharacterBulkToggles(parentPanel)
    end
end

-- Filter skill list based on search text
function BurdJournals.UI.DebugPanel.filterCharacterSkillList(self)
    local panel = self.charPanel
    if not panel or not panel.charSkillList then return end
    
    local searchText = ""
    if panel.skillSearchEntry and panel.skillSearchEntry.getText then
        searchText = panel.skillSearchEntry:getText()
    end
    local selectedSourceId = panel.skillSourceFilter and panel.skillSourceFilter.selectedSourceId or "all"
    
    local signature = "skill|" .. tostring(searchText) .. "|" .. tostring(selectedSourceId)
    applyDebugRowFilter(panel.charSkillList, function(row)
        local matchesSearch = searchText == "" or debugSearchMatches(searchText, row.displayName, row.name, row.category, row.source)
        local matchesSource = debugRowMatchesSourceFilter(row, selectedSourceId)
        return matchesSearch and matchesSource
    end, signature)
end

-- Filter trait list based on search text
function BurdJournals.UI.DebugPanel.filterCharacterTraitList(self)
    local panel = self.charPanel
    if not panel or not panel.charTraitList then return end
    
    local searchText = ""
    if panel.traitSearchEntry and panel.traitSearchEntry.getText then
        searchText = panel.traitSearchEntry:getText()
    end
    local selectedSourceId = panel.traitSourceFilter and panel.traitSourceFilter.selectedSourceId or "all"
    local selectedPolarity = getDebugTraitPolarityFilterValue(panel.traitPolarityFilter)
    
    local signature = "trait|" .. tostring(searchText) .. "|" .. tostring(selectedSourceId) .. "|" .. tostring(selectedPolarity)
    applyDebugRowFilter(panel.charTraitList, function(row)
        local matchesSearch = searchText == "" or debugSearchMatches(searchText, row.displayName, row.id, row.source)
        local matchesSource = debugRowMatchesSourceFilter(row, selectedSourceId)
        local matchesPolarity = debugRowMatchesTraitPolarityFilter(row, selectedPolarity)
        return matchesSearch and matchesSource and matchesPolarity
    end, signature)
    BurdJournals.UI.DebugPanel.refreshCharacterBulkToggles(self)
end

function BurdJournals.UI.DebugPanel.filterCharacterRecipeList(self)
    local panel = self.charPanel
    if not panel or not panel.charRecipeList then return end

    local searchText = ""
    if panel.recipeSearchEntry and panel.recipeSearchEntry.getText then
        searchText = panel.recipeSearchEntry:getText()
    end
    local selectedSourceId = panel.recipeSourceFilter and panel.recipeSourceFilter.selectedSourceId or "all"

    local signature = "recipe|" .. tostring(searchText) .. "|" .. tostring(selectedSourceId)
    applyDebugRowFilter(panel.charRecipeList, function(row)
        local matchesSearch = searchText == "" or debugSearchMatches(searchText, row.displayName, row.name, row.magazineSource, row.magazineDisplayName, row.source)
        local matchesSource = debugRowMatchesSourceFilter(row, selectedSourceId)
        return matchesSearch and matchesSource
    end, signature)
    BurdJournals.UI.DebugPanel.refreshCharacterBulkToggles(self)
end

function BurdJournals.UI.DebugPanel.drawCharacterRecipeItem(self, y, item, alt)
    local h = getDebugListRowHeight(self, item, 30)
    if not item or not item.item then return y + h end
    local data = item.item
    if not data or data.hidden then return y + h end

    local w = self.width or 300
    local scrollOffset = BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH

    if data.isKnown then
        self:drawRect(0, y, w, h, 0.12, 0.18, 0.12, 0.25)
    elseif self.mouseoverselected == item.index then
        self:drawRect(0, y, w, h, 0.2, 0.2, 0.3, 0.3)
    end

    if data.isKnown then
        self:drawText("[X]", 8, y + 2, 0.45, 0.85, 0.45, 1, UIFont.Small)
    else
        self:drawText("[ ]", 8, y + 2, 0.58, 0.58, 0.58, 1, UIFont.Small)
    end

    local iconX = 30
    local recipeIcon = data.recipeTexture or getDebugRecipeTexture()
    local recipeIconSize = drawDebugListIcon(self, recipeIcon, iconX, y, h, 0.95, 14)
    local textX = iconX + math.max(recipeIconSize, 14) + 6
    if data.magazineSource then
        local magazineIcon = data.magazineTexture or getDebugMagazineTexture(data.magazineSource)
        local magSize = drawDebugListIcon(self, magazineIcon, textX, y, h, 0.9, 14)
        if magSize > 0 then
            textX = textX + magSize + 6
        end
    end

    self:drawText(tostring(data.displayName or data.name or "Unknown Recipe"), textX, y + 2, 0.92, 0.92, 0.92, 1, UIFont.Small)
    local sourceText = getDebugRecipeSourceText(data, 22)
    local sourceColor = data.magazineDisplayName and {0.5, 0.7, 0.75}
        or ((data.source and data.source ~= "Vanilla" and data.source ~= "Runtime" and data.source ~= "Unknown")
            and {0.82, 0.72, 0.5}
            or {0.55, 0.65, 0.78})
    self:drawText(sourceText, textX, y + 15, sourceColor[1], sourceColor[2], sourceColor[3], 0.9, UIFont.Small)
    local rightLabel = data.isKnown and "Known" or (data.hasMagazine and "Available" or "Piped")
    self:drawText(rightLabel, w - 108 - scrollOffset, y + 2, 0.68, 0.82, 0.95, 0.9, UIFont.Small)
    return y + h
end

function BurdJournals.UI.DebugPanel.onCharacterRecipeListClick(self, x, y)
    local row = BurdJournals.UI.DebugPanel.safeListMouseDown(self, x, y)

    if not self.items then return end
    if not row or row <= 0 or row > #self.items then return end

    local item = self.items[row]
    if not item or not item.item then return end
    local data = item.item
    if not data or not data.name then return end

    local parentPanel = self.parentPanel
    if not parentPanel then return end
    local charPanel = parentPanel.charPanel
    local targetPlayer = charPanel and charPanel.targetPlayer or parentPanel.player
    if not targetPlayer then return end

    if data.isKnown ~= true then
        data.isKnown = true
        parentPanel:setStatus("Learned recipe: " .. tostring(data.displayName or data.name), {r=0.3, g=1, b=0.5})

        if BurdJournals.clientShouldUseServerAuthority() then
            sendClientCommand("BurdJournals", "debugAddRecipe", {
                recipeName = data.name,
                targetUsername = targetPlayer:getUsername()
            })
        else
            local learned = BurdJournals.learnRecipeWithVerification and BurdJournals.learnRecipeWithVerification(targetPlayer, data.name, "[BSJ Debug Recipes]")
            if not learned then
                data.isKnown = false
                parentPanel:setStatus("Failed to learn recipe: " .. tostring(data.displayName or data.name), {r=1, g=0.5, b=0.3})
            end
        end
        BurdJournals.UI.DebugPanel.refreshCharacterBulkToggles(parentPanel)
    else
        data.isKnown = false
        parentPanel:setStatus("Removed recipe: " .. tostring(data.displayName or data.name), {r=0.3, g=1, b=0.5})

        if BurdJournals.clientShouldUseServerAuthority() then
            sendClientCommand("BurdJournals", "debugRemoveRecipe", {
                recipeName = data.name,
                targetUsername = targetPlayer:getUsername()
            })
        else
            local removed = BurdJournals.forgetRecipeWithVerification and BurdJournals.forgetRecipeWithVerification(targetPlayer, data.name, "[BSJ Debug Recipes]")
            if not removed then
                data.isKnown = true
                parentPanel:setStatus("Failed to remove recipe: " .. tostring(data.displayName or data.name), {r=1, g=0.5, b=0.3})
            end
        end
        BurdJournals.UI.DebugPanel.refreshCharacterBulkToggles(parentPanel)
    end
end

function BurdJournals.UI.DebugPanel:syncCharacterTraitRows(traitIds, hasCount)
    local panel = self.charPanel
    local list = panel and panel.charTraitList or nil
    if not (list and list.items and traitIds) then
        return
    end

    local targetIds = {}
    local function addTargetId(traitId)
        if not traitId then
            return
        end
        local normalized = BurdJournals.UI.DebugPanel.normalizeTraitId(traitId) or traitId
        targetIds[string.lower(tostring(normalized))] = true
        targetIds[string.lower(tostring(traitId))] = true
    end

    if type(traitIds) == "table" then
        for _, traitId in ipairs(traitIds) do
            addTargetId(traitId)
        end
    else
        addTargetId(traitIds)
    end

    for _, itemData in ipairs(list.items) do
        local row = itemData and itemData.item or nil
        if row and row.id then
            local normalized = BurdJournals.UI.DebugPanel.normalizeTraitId(row.id) or row.id
            if targetIds[string.lower(tostring(normalized))] or targetIds[string.lower(tostring(row.id))] then
                row.hasCount = hasCount
            end
        end
    end

    BurdJournals.UI.DebugPanel.refreshCharacterBulkToggles(self)
end

function BurdJournals.UI.DebugPanel:syncCharacterRecipeRows(recipeNames, isKnown)
    local panel = self.charPanel
    local list = panel and panel.charRecipeList or nil
    if not (list and list.items and recipeNames) then
        return
    end

    local targetNames = {}
    local function addTargetName(recipeName)
        if not recipeName then
            return
        end
        targetNames[tostring(recipeName)] = true
        targetNames[string.lower(tostring(recipeName))] = true
    end

    if type(recipeNames) == "table" then
        for _, recipeName in ipairs(recipeNames) do
            addTargetName(recipeName)
        end
    else
        addTargetName(recipeNames)
    end

    for _, itemData in ipairs(list.items) do
        local row = itemData and itemData.item or nil
        if row and row.name and (targetNames[tostring(row.name)] or targetNames[string.lower(tostring(row.name))]) then
            row.isKnown = isKnown == true
        end
    end

    BurdJournals.UI.DebugPanel.refreshCharacterBulkToggles(self)
end

function BurdJournals.UI.DebugPanel.refreshCharacterBulkToggles(self)
    local panel = self and self.charPanel or nil
    if not panel then
        return
    end

    refreshDebugBulkTickState(panel.charTraitBulkTick, panel.charTraitList, function(row)
        return row.isPassiveSkillTrait ~= true
    end, function(row)
        return (tonumber(row.hasCount) or 0) > 0
    end)
    refreshDebugBulkTickState(panel.charRecipeBulkTick, panel.charRecipeList, nil, function(row)
        return row.isKnown == true
    end)
end

function BurdJournals.UI.DebugPanel.onCharacterTraitBulkToggle(self, _index, selected)
    local panel = self and self.charPanel or nil
    local targetPlayer = panel and (panel.targetPlayer or self.player) or nil
    if not (panel and panel.charTraitList and targetPlayer) then
        return
    end

    local addOpts = BurdJournals.UI.DebugPanel.buildDebugTraitAddOptions(self)
    local bulkAction = "removealltraits"
    local count = 0
    for _, itemData in ipairs(panel.charTraitList.items or {}) do
        local row = itemData and itemData.item or nil
        if row and row.id and row.isPassiveSkillTrait ~= true and (selected == true and isDebugVisibleBulkRow(row) or selected ~= true) then
            if selected == true and (tonumber(row.hasCount) or 0) <= 0 then
                row.hasCount = 1
                count = count + 1
                if BurdJournals.clientShouldUseServerAuthority() then
                    sendClientCommand("BurdJournals", "debugAddTrait", {
                        traitId = row.id,
                        allowTraitReconciliation = not (addOpts and addOpts.skipTraitReconciliation == true),
                        targetUsername = targetPlayer:getUsername()
                    })
                elseif BurdJournals.safeAddTrait then
                    local added = BurdJournals.safeAddTrait(targetPlayer, row.id, addOpts)
                    if added
                        and not (addOpts and addOpts.skipTraitReconciliation == true)
                        and BurdJournals.Server
                        and BurdJournals.Server.resolveAndRemoveTraitConflicts then
                        BurdJournals.Server.resolveAndRemoveTraitConflicts(targetPlayer, row.id)
                    end
                end
            elseif selected ~= true and (tonumber(row.hasCount) or 0) > 0 then
                row.hasCount = 0
                count = count + 1
            end
        end
    end

    if selected ~= true and count > 0 then
        if BurdJournals.clientShouldUseServerAuthority() then
            sendClientCommand("BurdJournals", "debugBulkTraits", {
                action = bulkAction,
                allowTraitReconciliation = false,
                targetUsername = targetPlayer:getUsername()
            })
        else
            BurdJournals.UI.DebugPanel.applyBulkTraitActionLocally(targetPlayer, bulkAction, addOpts)
        end
    end

    BurdJournals.UI.DebugPanel.refreshCharacterBulkToggles(self)
    self:setStatus((selected and "Added " or "Cleared ") .. tostring(count) .. (selected and " visible" or "") .. " player trait(s)", {r=0.5, g=0.8, b=1})
    if not (BurdJournals.clientShouldUseServerAuthority()) and self.refreshCharacterData then
        self:refreshCharacterData()
    end
end

function BurdJournals.UI.DebugPanel.onCharacterRecipeBulkToggle(self, _index, selected)
    local panel = self and self.charPanel or nil
    local targetPlayer = panel and (panel.targetPlayer or self.player) or nil
    if not (panel and panel.charRecipeList and targetPlayer) then
        return
    end

    local count = 0
    local bulkRecipeNames = {}
    for _, itemData in ipairs(panel.charRecipeList.items or {}) do
        local row = itemData and itemData.item or nil
        if row and row.name and (selected == true and isDebugVisibleBulkRow(row) or selected ~= true) then
            if selected == true and row.isKnown ~= true then
                row.isKnown = true
                count = count + 1
                if BurdJournals.clientShouldUseServerAuthority() then
                    bulkRecipeNames[#bulkRecipeNames + 1] = row.name
                else
                    local learned = BurdJournals.learnRecipeWithVerification and BurdJournals.learnRecipeWithVerification(targetPlayer, row.name, "[BSJ Debug Recipes]")
                    if not learned then
                        row.isKnown = false
                    end
                end
            elseif selected ~= true and row.isKnown == true then
                row.isKnown = false
                count = count + 1
                if BurdJournals.clientShouldUseServerAuthority() then
                    bulkRecipeNames[#bulkRecipeNames + 1] = row.name
                else
                    local removed = BurdJournals.forgetRecipeWithVerification and BurdJournals.forgetRecipeWithVerification(targetPlayer, row.name, "[BSJ Debug Recipes]")
                    if not removed then
                        row.isKnown = true
                    end
                end
            end
        end
    end

    if BurdJournals.clientShouldUseServerAuthority() and #bulkRecipeNames > 0 then
        sendClientCommand("BurdJournals", "debugBulkRecipes", {
            action = selected == true and "add" or "remove",
            recipeNames = bulkRecipeNames,
            targetUsername = targetPlayer:getUsername()
        })
    end

    BurdJournals.UI.DebugPanel.refreshCharacterBulkToggles(self)
    self:setStatus((selected and "Learned " or "Cleared ") .. tostring(count) .. (selected and " visible" or "") .. " player recipe(s)", {r=0.5, g=0.8, b=1})
    if not (BurdJournals.clientShouldUseServerAuthority()) and self.refreshCharacterData then
        self:refreshCharacterData()
    end
end

-- Character command handler
function BurdJournals.UI.DebugPanel:onCharCmd(button)
    local cmd = button.internal
    local charPanel = self.charPanel
    local targetPlayer = charPanel and charPanel.targetPlayer or self.player
    
    if cmd == "setallmax" then
        self:setStatus("Setting all skills to max...", {r=0.5, g=0.8, b=1})
        if targetPlayer then
            if BurdJournals.clientShouldUseServerAuthority() then
                -- Multiplayer: send to server, UI refresh will happen on server response
                sendClientCommand("BurdJournals", "debugSetAllSkills", {
                    level = 10,
                    targetUsername = targetPlayer:getUsername()
                })
                -- Optimistically update the list display while waiting for server
                if self.charPanel and self.charPanel.charSkillList then
                    for _, item in ipairs(self.charPanel.charSkillList.items) do
                        if item.item then
                            item.item.level = 10
                        end
                    end
                end
            else
                -- Singleplayer: apply directly
                local xpObj = targetPlayer:getXp()
                local count = 0
                
                -- Remove ALL passive skill traits FIRST to prevent bouncing
                BurdJournals.UI.DebugPanel.removePassiveSkillTraits(targetPlayer, "Strength")
                BurdJournals.UI.DebugPanel.removePassiveSkillTraits(targetPlayer, "Fitness")
                
                -- For passive skills, use setPerkLevelDebug which directly sets level
                -- This bypasses XP scaling issues that affect Strength specifically
                local strengthPerk = Perks.Strength
                local fitnessPerk = Perks.Fitness
                
                if strengthPerk then
                    targetPlayer:setPerkLevelDebug(strengthPerk, 10)
                    count = count + 1
                end
                
                if fitnessPerk then
                    targetPlayer:setPerkLevelDebug(fitnessPerk, 10)
                    count = count + 1
                end
                
                -- For all other skills, use XP-based approach
                for i = 0, Perks.getMaxIndex() - 1 do
                    local perk = Perks.fromIndex(i)
                    if perk and perk:getParent() ~= Perks.None then
                        local perkName = tostring(perk)
                        -- Skip passive skills - already handled above
                        if perkName ~= "Fitness" and perkName ~= "Strength" then
                            local targetXP = (BurdJournals.getXPThresholdForLevel and BurdJournals.getXPThresholdForLevel(perkName, 10))
                                or (perk.getTotalXpForLevel and perk:getTotalXpForLevel(10))
                                or 0
                            if BurdJournals.setSkillTotalXPCompat then
                                BurdJournals.setSkillTotalXPCompat(targetPlayer, perk, targetXP, perkName)
                            end
                            count = count + 1
                        end
                    end
                end
                self:setStatus("All " .. count .. " skills set to level 10!", {r=0.3, g=1, b=0.5})
                self:refreshCharacterData()
            end
        end
        
    elseif cmd == "setallzero" then
        -- Optimistically update the UI immediately
        if self.charPanel and self.charPanel.charSkillList then
            for _, item in ipairs(self.charPanel.charSkillList.items) do
                if item.item then
                    item.item.level = 0
                end
            end
        end
        self:setStatus("All skills set to level 0!", {r=1, g=0.8, b=0.3})
        
        if targetPlayer then
            if BurdJournals.clientShouldUseServerAuthority() then
                -- Multiplayer: send to server
                sendClientCommand("BurdJournals", "debugSetAllSkills", {
                    level = 0,
                    targetUsername = targetPlayer:getUsername()
                })
            else
                -- Singleplayer: set all to 0
                local xpObj = targetPlayer:getXp()
                local count = 0
                
                -- Remove ALL passive skill traits FIRST to prevent bouncing
                -- (e.g., Feeble trait forcing Strength to stay at level 2)
                BurdJournals.UI.DebugPanel.removePassiveSkillTraits(targetPlayer, "Strength")
                BurdJournals.UI.DebugPanel.removePassiveSkillTraits(targetPlayer, "Fitness")
                
                -- For passive skills, use setPerkLevelDebug which directly sets level
                -- This bypasses XP scaling issues that affect Strength specifically
                local strengthPerk = Perks.Strength
                local fitnessPerk = Perks.Fitness
                
                if strengthPerk then
                    targetPlayer:setPerkLevelDebug(strengthPerk, 0)
                    -- Also reset XP directly and remove traits again
                    -- PZ auto-applies "Weak" trait which bounces Strength back up
                    applyDebugXPCompat(targetPlayer, strengthPerk, -xpObj:getXP(strengthPerk), {
                        skillName = "Strength",
                        useMultipliers = false,
                        isPassive = true,
                    })
                    BurdJournals.UI.DebugPanel.removePassiveSkillTraits(targetPlayer, "Strength")
                    targetPlayer:setPerkLevelDebug(strengthPerk, 0)
                    count = count + 1
                end
                
                if fitnessPerk then
                    targetPlayer:setPerkLevelDebug(fitnessPerk, 0)
                    -- Same treatment for Fitness just in case
                    applyDebugXPCompat(targetPlayer, fitnessPerk, -xpObj:getXP(fitnessPerk), {
                        skillName = "Fitness",
                        useMultipliers = false,
                        isPassive = true,
                    })
                    BurdJournals.UI.DebugPanel.removePassiveSkillTraits(targetPlayer, "Fitness")
                    targetPlayer:setPerkLevelDebug(fitnessPerk, 0)
                    count = count + 1
                end
                
                -- For all other skills, set to 0 XP
                for i = 0, Perks.getMaxIndex() - 1 do
                    local perk = Perks.fromIndex(i)
                    if perk and perk:getParent() ~= Perks.None then
                        local perkName = tostring(perk)
                        -- Skip passive skills - already handled above
                        if perkName ~= "Fitness" and perkName ~= "Strength" then
                            if BurdJournals.setSkillTotalXPCompat then
                                BurdJournals.setSkillTotalXPCompat(targetPlayer, perk, 0, perkName)
                            end
                            count = count + 1
                        end
                    end
                end
                self:setStatus("All " .. count .. " skills set to level 0!", {r=0.3, g=1, b=0.5})
                self:refreshCharacterData()
            end
        end
        
    elseif BurdJournals.UI.DebugPanel.getDebugBulkTraitActionSpec(cmd) then
        local actionSpec = BurdJournals.UI.DebugPanel.getDebugBulkTraitActionSpec(cmd)
        local addOpts = actionSpec.isAdd and BurdJournals.UI.DebugPanel.buildDebugTraitAddOptions(self) or nil
        if self.charPanel and self.charPanel.charTraitList then
            for _, item in ipairs(self.charPanel.charTraitList.items) do
                local traitData = item and item.item or nil
                if traitData
                    and not traitData.isPassiveSkillTrait
                    and BurdJournals.UI.DebugPanel.matchesBulkTraitAction(cmd, traitData.id or traitData.displayName) then
                    if actionSpec.isAdd then
                        traitData.hasCount = math.max(1, tonumber(traitData.hasCount) or 0)
                    else
                        traitData.hasCount = 0
                    end
                end
            end
        end
        self:setStatus(actionSpec.pendingMessage, {r=1, g=0.8, b=0.3})

        if targetPlayer then
            if BurdJournals.clientShouldUseServerAuthority() then
                sendClientCommand("BurdJournals", "debugBulkTraits", {
                    action = cmd,
                    allowTraitReconciliation = actionSpec.isAdd and not (addOpts and addOpts.skipTraitReconciliation == true) or false,
                    targetUsername = targetPlayer:getUsername()
                })
            else
                local appliedCount, skippedCount, failedCount = BurdJournals.UI.DebugPanel.applyBulkTraitActionLocally(targetPlayer, cmd, addOpts)
                self:setStatus(BurdJournals.UI.DebugPanel.formatBulkTraitActionMessage(cmd, appliedCount, skippedCount, failedCount), {r=0.3, g=1, b=0.5})
                self:refreshCharacterData()
            end
        end
        
    elseif cmd == "dumpskills" then
        BurdJournals.debugPrint("[BSJ DEBUG] Player Skills for: " .. (targetPlayer:getUsername() or "Unknown"))
        if targetPlayer then
            local xp = targetPlayer:getXp()
            for i = 0, Perks.getMaxIndex() - 1 do
                local perk = Perks.fromIndex(i)
                if perk and perk:getParent() ~= Perks.None then
                    local level = targetPlayer:getPerkLevel(perk)
                    local xpVal = BurdJournals.getPlayerSkillTotalXP and BurdJournals.getPlayerSkillTotalXP(targetPlayer, perk, tostring(perk)) or xp:getXP(perk)
                    BurdJournals.debugPrint(BurdJournals.formatText("  %s: Level %d (XP: %.0f)", tostring(perk), level, xpVal))
                end
            end
        end
        self:setStatus("Skills dumped to console", {r=0.5, g=0.8, b=1})
        
    elseif cmd == "dumptraits" then
        BurdJournals.debugPrint("[BSJ DEBUG] Player Traits for: " .. (targetPlayer:getUsername() or "Unknown"))
        if targetPlayer then
            local traitCounts = {}
            local totalCount = 0
            
            -- Build 42 approach: iterate through CharacterTraitDefinition and check which ones player has
            local CharacterTraitDefinition = CharacterTraitDefinition
            if CharacterTraitDefinition and CharacterTraitDefinition.getTraits then
                local allDefs = CharacterTraitDefinition.getTraits()
                if allDefs then
                    for i = 0, allDefs:size() - 1 do
                        local def = allDefs:get(i)
                        if def and def.getTrait then
                            local traitObj = def:getTrait()
                            if traitObj and targetPlayer.hasTrait and targetPlayer:hasTrait(traitObj) then
                                local traitId = "unknown"
                                if traitObj.getResourceLocation then
                                    local loc = traitObj:getResourceLocation()
                                    if loc then traitId = tostring(loc) end
                                end
                                -- Also try to get display name
                                local displayName = traitId
                                if def.getLabel then displayName = def:getLabel() or traitId end
                                traitCounts[traitId] = (traitCounts[traitId] or 0) + 1
                                totalCount = totalCount + 1
                            end
                        end
                    end
                end
            end
            
            -- Fallback: try old API if no traits found
            if totalCount == 0 and targetPlayer.getTraits then
                local traits = targetPlayer:getTraits()
                if traits and traits.size then
                    for i = 0, traits:size() - 1 do
                        local t = tostring(traits:get(i))
                        traitCounts[t] = (traitCounts[t] or 0) + 1
                        totalCount = totalCount + 1
                    end
                end
            end
            
            -- Print results
            if totalCount > 0 then
                for traitId, count in pairs(traitCounts) do
                    if count > 1 then
                        BurdJournals.debugPrint("  " .. traitId .. " (x" .. count .. ")")
                    else
                        BurdJournals.debugPrint("  " .. traitId)
                    end
                end
            else
                BurdJournals.debugPrint("  (no traits found)")
            end
            BurdJournals.debugPrint("[BSJ DEBUG] Total: " .. totalCount .. " traits")
        end
        self:setStatus("Traits dumped to console", {r=0.5, g=0.8, b=1})
    elseif cmd == "dumprecipes" then
        BurdJournals.debugPrint("[BSJ DEBUG] Player Recipes for: " .. (targetPlayer and targetPlayer:getUsername() or "Unknown"))
        if targetPlayer then
        local rows = buildDebugRecipeRows(targetPlayer, true, false)
            if #rows == 0 then
                BurdJournals.debugPrint("  (no known recipes found)")
            else
                for _, row in ipairs(rows) do
                    local suffix = row.magazineSource and (" | Magazine: " .. tostring(row.magazineSource)) or ""
                    BurdJournals.debugPrint("  " .. tostring(row.name) .. " -> " .. tostring(row.displayName) .. suffix)
                end
            end
            BurdJournals.debugPrint("[BSJ DEBUG] Total: " .. tostring(#rows) .. " recipes")
        end
        self:setStatus("Recipes dumped to console", {r=0.5, g=0.8, b=1})
    end
end

-- ============================================================================
-- Tab 3: Baseline Manager Panel
-- ============================================================================

function BurdJournals.UI.DebugPanel:createBaselinePanel(startY, height)
    local panel = ISPanel:new(5, startY, self.width - 10, height)
    panel:initialise()
    panel:instantiate()
    panel.backgroundColor = {r=0.12, g=0.12, b=0.15, a=1}
    panel.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    self:addChild(panel)
    self.tabPanels["baseline"] = panel
    
    local padding = 10
    local y = padding
    local fullWidth = panel.width - padding * 2
    local halfWidth = (fullWidth - padding) / 2
    local btnHeight = 24
    
    -- Check if baseline restriction is enabled
    local baselineEnabled = BurdJournals.isBaselineRestrictionEnabled and BurdJournals.isBaselineRestrictionEnabled()
    panel.baselineEnabled = baselineEnabled
    panel.baselineDraftDirty = false
    panel.baselineDraftSkills = {}
    panel.baselineDraftTraits = {}
    panel.baselineDraftRecipes = {}
    
    -- Status indicator for baseline setting
    local statusText = baselineEnabled and "Baseline Restriction: ENABLED" or "Baseline Restriction: DISABLED"
    local statusColor = baselineEnabled and {0.5, 0.8, 0.5} or {0.8, 0.6, 0.3}
    local statusLabel = ISLabel:new(padding, y, 18, statusText, statusColor[1], statusColor[2], statusColor[3], 1, UIFont.Small, true)
    statusLabel:initialise()
    statusLabel:instantiate()
    panel:addChild(statusLabel)
    panel.statusLabel = statusLabel
    y = y + 22

    -- Server-authoritative baseline note
    local authLabel = ISLabel:new(padding, y, 16, "Baseline is stored from server state (authoritative).", 0.6, 0.7, 0.9, 1, UIFont.Small, true)
    authLabel:initialise()
    authLabel:instantiate()
    panel:addChild(authLabel)
    y = y + 18
    
    -- If baseline is disabled, show explanation and limited controls
    if not baselineEnabled then
        local infoLabel1 = ISLabel:new(padding, y, 16, "The sandbox setting 'Only Record Earned Progress' is OFF.", 0.7, 0.7, 0.7, 1, UIFont.Small, true)
        infoLabel1:initialise()
        infoLabel1:instantiate()
        panel:addChild(infoLabel1)
        y = y + 18
        
        local infoLabel2 = ISLabel:new(padding, y, 16, "Players can record ALL progress, not just earned XP.", 0.7, 0.7, 0.7, 1, UIFont.Small, true)
        infoLabel2:initialise()
        infoLabel2:instantiate()
        panel:addChild(infoLabel2)
        y = y + 18
        
        local infoLabel3 = ISLabel:new(padding, y, 16, "Baseline management is not needed for this save.", 0.6, 0.6, 0.6, 1, UIFont.Small, true)
        infoLabel3:initialise()
        infoLabel3:instantiate()
        panel:addChild(infoLabel3)
        y = y + 30
        
        -- Still show view-only info
        local viewLabel = ISLabel:new(padding, y, 18, "Player Stats (View Only):", 0.9, 0.9, 0.7, 1, UIFont.Small, true)
        viewLabel:initialise()
        viewLabel:instantiate()
        panel:addChild(viewLabel)
        y = y + 22
        
        -- Simplified skill view list (read-only)
        local skillListHeight = 200
        panel.baselineSkillList = ISScrollingListBox:new(padding, y, fullWidth, skillListHeight)
        panel.baselineSkillList:initialise()
        panel.baselineSkillList:instantiate()
        panel.baselineSkillList.itemheight = 24
        panel.baselineSkillList.backgroundColor = {r=0.08, g=0.08, b=0.1, a=1}
        panel.baselineSkillList.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
        panel.baselineSkillList.doDrawItem = BurdJournals.UI.DebugPanel.drawBaselineSkillItemReadOnly
        panel.baselineSkillList.parentPanel = self
        panel:addChild(panel.baselineSkillList)
        y = y + skillListHeight + 10
        
        -- Dump buttons
        local dumpBtn = ISButton:new(padding, y, 150, btnHeight, "Dump Stats to Console", self, BurdJournals.UI.DebugPanel.onBaselineCmd)
        dumpBtn:initialise()
        dumpBtn:instantiate()
        dumpBtn.font = UIFont.Small
        dumpBtn.internal = "dumpbaseline"
        dumpBtn.textColor = {r=1, g=1, b=1, a=1}
        dumpBtn.borderColor = {r=0.4, g=0.5, b=0.6, a=1}
        dumpBtn.backgroundColor = {r=0.2, g=0.25, b=0.3, a=1}
        panel:addChild(dumpBtn)

        local spawnDumpBtn = ISButton:new(padding + 160, y, 200, btnHeight, "Dump Spawn Readiness", self, BurdJournals.UI.DebugPanel.onBaselineCmd)
        spawnDumpBtn:initialise()
        spawnDumpBtn:instantiate()
        spawnDumpBtn.font = UIFont.Small
        spawnDumpBtn.internal = "dumpspawnstate"
        spawnDumpBtn.textColor = {r=1, g=1, b=1, a=1}
        spawnDumpBtn.borderColor = {r=0.35, g=0.55, b=0.65, a=1}
        spawnDumpBtn.backgroundColor = {r=0.16, g=0.28, b=0.34, a=1}
        panel:addChild(spawnDumpBtn)
        
        -- Store reference and populate
        self.baselinePanel = panel
        panel.targetPlayer = self.player
        self:refreshBaselineData()
        return
    end
    
    -- Full baseline management UI (when enabled)
    -- Player selector (for admins to select other players)
    local playerLabel = ISLabel:new(padding, y, 18, "Selected Player:", 1, 1, 1, 1, UIFont.Small, true)
    playerLabel:initialise()
    playerLabel:instantiate()
    panel:addChild(playerLabel)
    
    panel.targetPlayerCombo = ISComboBox:new(padding + 90, y - 2, 200, 22, self, BurdJournals.UI.DebugPanel.onBaselineTargetPlayerChange)
    panel.targetPlayerCombo:initialise()
    panel.targetPlayerCombo:instantiate()
    panel.targetPlayerCombo.font = UIFont.Small
    panel:addChild(panel.targetPlayerCombo)
    
    local refreshBtn = ISButton:new(padding + 295, y - 2, 70, 22, "Refresh", self, BurdJournals.UI.DebugPanel.onBaselineRefresh)
    refreshBtn:initialise()
    refreshBtn:instantiate()
    refreshBtn.font = UIFont.Small
    refreshBtn.textColor = {r=1, g=1, b=1, a=1}
    refreshBtn.borderColor = {r=0.4, g=0.5, b=0.6, a=1}
    refreshBtn.backgroundColor = {r=0.2, g=0.25, b=0.3, a=1}
    panel:addChild(refreshBtn)
    y = y + 28
    
    -- Skills section header with search
    local skillsLabel = ISLabel:new(padding, y, 18, "Skills (Click squares to set baseline):", 0.9, 0.9, 0.7, 1, UIFont.Small, true)
    skillsLabel:initialise()
    skillsLabel:instantiate()
    panel:addChild(skillsLabel)
    
    -- Skill search field + quick draft actions
    local skillSearchX = padding + 230
    local skillSearchWidth = 145
    panel.baselineSkillSearch = ISTextEntryBox:new("", skillSearchX, y - 2, skillSearchWidth, 20)
    panel.baselineSkillSearch:initialise()
    panel.baselineSkillSearch:instantiate()
    panel.baselineSkillSearch.font = UIFont.Small
    panel.baselineSkillSearch:setTooltip("Filter skills...")
    panel.baselineSkillSearch.onTextChange = function()
        BurdJournals.UI.DebugPanel.filterBaselineSkillList(self)
    end
    panel:addChild(panel.baselineSkillSearch)

    local topActionSpacing = 6
    local saveDraftWidth = 158
    local discardDraftWidth = 88
    local openSnapshotsWidth = 96
    local topActionTotalWidth = saveDraftWidth + discardDraftWidth + openSnapshotsWidth + (topActionSpacing * 2)
    local topActionX = padding + fullWidth - topActionTotalWidth
    local minTopActionX = skillSearchX + skillSearchWidth + 8
    if topActionX < minTopActionX then
        topActionX = minTopActionX
    end

    local saveDraftBtn = ISButton:new(topActionX, y - 2, saveDraftWidth, btnHeight, getText("UI_BurdJournals_SaveBaselineSnapshot") or "Save Baseline Snapshot", self, BurdJournals.UI.DebugPanel.onBaselineCmd)
    saveDraftBtn:initialise()
    saveDraftBtn:instantiate()
    saveDraftBtn.font = UIFont.Small
    saveDraftBtn.internal = "savebaselinechanges"
    saveDraftBtn.textColor = {r=1, g=1, b=1, a=1}
    saveDraftBtn.borderColor = {r=0.45, g=0.72, b=0.5, a=1}
    saveDraftBtn.backgroundColor = {r=0.2, g=0.35, b=0.24, a=1}
    panel:addChild(saveDraftBtn)
    panel.saveBaselineChangesBtn = saveDraftBtn

    local discardDraftBtn = ISButton:new(topActionX + saveDraftWidth + topActionSpacing, y - 2, discardDraftWidth, btnHeight, getText("UI_BurdJournals_DiscardBaselineDraftShort") or "Discard", self, BurdJournals.UI.DebugPanel.onBaselineCmd)
    discardDraftBtn:initialise()
    discardDraftBtn:instantiate()
    discardDraftBtn.font = UIFont.Small
    discardDraftBtn.internal = "discardbaselinechanges"
    discardDraftBtn.textColor = {r=1, g=1, b=1, a=1}
    discardDraftBtn.borderColor = {r=0.68, g=0.5, b=0.4, a=1}
    discardDraftBtn.backgroundColor = {r=0.34, g=0.24, b=0.18, a=1}
    panel:addChild(discardDraftBtn)
    panel.discardBaselineChangesBtn = discardDraftBtn

    local openSnapshotsBtn = ISButton:new(topActionX + saveDraftWidth + discardDraftWidth + (topActionSpacing * 2), y - 2, openSnapshotsWidth, btnHeight, getText("UI_BurdJournals_OpenSnapshotsTabShort") or "Snapshots", self, BurdJournals.UI.DebugPanel.onBaselineCmd)
    openSnapshotsBtn:initialise()
    openSnapshotsBtn:instantiate()
    openSnapshotsBtn.font = UIFont.Small
    openSnapshotsBtn.internal = "opensnapshots"
    openSnapshotsBtn.textColor = {r=1, g=1, b=1, a=1}
    openSnapshotsBtn.borderColor = {r=0.55, g=0.5, b=0.75, a=1}
    openSnapshotsBtn.backgroundColor = {r=0.24, g=0.2, b=0.34, a=1}
    panel:addChild(openSnapshotsBtn)
    y = y + 24

    panel.baselineTabState = {buttons = {}, panels = {}, current = "skills"}
    local tabX = padding
    local tabWidth = 84
    local tabHeight = 22
    local tabSpacing = 6
    panel.baselineTabState.buttons.skills = createDebugButton(panel, tabX, y, tabWidth, tabHeight, "Skills", self, BurdJournals.UI.DebugPanel.onBaselineSubTab, "skills")
    tabX = tabX + tabWidth + tabSpacing
    panel.baselineTabState.buttons.traits = createDebugButton(panel, tabX, y, tabWidth, tabHeight, "Traits", self, BurdJournals.UI.DebugPanel.onBaselineSubTab, "traits")
    tabX = tabX + tabWidth + tabSpacing
    panel.baselineTabState.buttons.recipes = createDebugButton(panel, tabX, y, tabWidth, tabHeight, "Recipes", self, BurdJournals.UI.DebugPanel.onBaselineSubTab, "recipes")
    y = y + tabHeight + 8

    local utilityY = panel.height - padding - btnHeight
    local sectionHeight = math.max(220, utilityY - y - 8)
    local sectionPadding = 8
    local contentWidth = fullWidth - sectionPadding * 2

    local skillsSection = createDebugSectionPanel(panel, padding, y, fullWidth, sectionHeight)
    panel.baselineTabState.panels.skills = skillsSection
    local sy = sectionPadding
    local baselineSkillLabelText = getText("UI_BurdJournals_DebugSkillsSetBaseline")
    local skillsLabel = ISLabel:new(sectionPadding, sy + 2, 18, baselineSkillLabelText, 0.9, 0.9, 0.7, 1, UIFont.Small, true)
    skillsLabel:initialise()
    skillsLabel:instantiate()
    skillsSection:addChild(skillsLabel)
    local baselineSkillSearchX = math.max(220, contentWidth - 156)
    panel.baselineSkillSearch = ISTextEntryBox:new("", baselineSkillSearchX, sy, 150, 20)
    panel.baselineSkillSearch:initialise()
    panel.baselineSkillSearch:instantiate()
    panel.baselineSkillSearch.font = UIFont.Small
    panel.baselineSkillSearch:setTooltip("Filter skills...")
    panel.baselineSkillSearch.onTextChange = function()
        BurdJournals.UI.DebugPanel.filterBaselineSkillList(self)
    end
    skillsSection:addChild(panel.baselineSkillSearch)
    panel.baselineSkillSourceFilter = createSectionSourceFilterStrip(skillsSection, self, baselineSkillLabelText, baselineSkillSearchX, sy, sectionPadding, BurdJournals.UI.DebugPanel.filterBaselineSkillList, "Filter baseline skills by source.")
    sy = sy + 24
    local skillListHeight = math.max(120, sectionHeight - 62)
    panel.baselineSkillList = ISScrollingListBox:new(sectionPadding, sy, contentWidth, skillListHeight)
    panel.baselineSkillList:initialise()
    panel.baselineSkillList:instantiate()
    panel.baselineSkillList.itemheight = 24
    panel.baselineSkillList.backgroundColor = {r=0.08, g=0.08, b=0.1, a=1}
    panel.baselineSkillList.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    panel.baselineSkillList.doDrawItem = BurdJournals.UI.DebugPanel.drawBaselineSkillItem
    panel.baselineSkillList.onMouseDown = BurdJournals.UI.DebugPanel.onBaselineSkillListClick
    panel.baselineSkillList.parentPanel = self
    skillsSection:addChild(panel.baselineSkillList)
    sy = sy + skillListHeight + 6
    createDebugButton(skillsSection, sectionPadding, sy, 140, btnHeight, "Set to Current Skills", self, BurdJournals.UI.DebugPanel.onBaselineCmd, "recalculate", {r=0.5, g=0.6, b=0.3, a=1}, {r=0.25, g=0.35, b=0.15, a=1})

    local traitsSection = createDebugSectionPanel(panel, padding, y, fullWidth, sectionHeight)
    panel.baselineTabState.panels.traits = traitsSection
    local ty = sectionPadding
    local baselineTraitLabelText = getText("UI_BurdJournals_DebugTraitsBaseline")
    local baselineTraitLabelX = sectionPadding + 58
    panel.baselineTraitBulkTick = createDebugBulkTick(traitsSection, sectionPadding, ty - 1, 52, 20, "All", self, BurdJournals.UI.DebugPanel.onBaselineTraitBulkToggle, "Set or clear all visible baseline traits.")
    local traitsLabel = ISLabel:new(baselineTraitLabelX, ty + 2, 18, baselineTraitLabelText, 0.9, 0.9, 0.7, 1, UIFont.Small, true)
    traitsLabel:initialise()
    traitsLabel:instantiate()
    traitsSection:addChild(traitsLabel)
    local baselineTraitSearchX = math.max(220, contentWidth - 156)
    panel.baselineTraitSearch = ISTextEntryBox:new("", baselineTraitSearchX, ty, 150, 20)
    panel.baselineTraitSearch:initialise()
    panel.baselineTraitSearch:instantiate()
    panel.baselineTraitSearch.font = UIFont.Small
    panel.baselineTraitSearch:setTooltip("Filter traits...")
    panel.baselineTraitSearch.onTextChange = function()
        BurdJournals.UI.DebugPanel.filterBaselineTraitList(self)
    end
    traitsSection:addChild(panel.baselineTraitSearch)
    panel.baselineTraitPolarityFilter = createDebugTraitPolarityFilter(traitsSection, math.max(sectionPadding, baselineTraitSearchX - 92), ty, self, BurdJournals.UI.DebugPanel.filterBaselineTraitList, "Filter baseline traits by positive/negative polarity.")
    panel.baselineTraitSourceFilter = createSectionSourceFilterStrip(traitsSection, self, baselineTraitLabelText, baselineTraitSearchX, ty, sectionPadding, BurdJournals.UI.DebugPanel.filterBaselineTraitList, "Filter baseline traits by source.", baselineTraitLabelX)
    ty = ty + 24
    local traitListHeight = math.max(120, sectionHeight - 62)
    panel.baselineTraitList = ISScrollingListBox:new(sectionPadding, ty, contentWidth, traitListHeight)
    panel.baselineTraitList:initialise()
    panel.baselineTraitList:instantiate()
    panel.baselineTraitList.itemheight = 22
    panel.baselineTraitList.backgroundColor = {r=0.08, g=0.08, b=0.1, a=1}
    panel.baselineTraitList.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    panel.baselineTraitList.doDrawItem = BurdJournals.UI.DebugPanel.drawBaselineTraitItem
    panel.baselineTraitList.onMouseDown = BurdJournals.UI.DebugPanel.onBaselineTraitListClick
    panel.baselineTraitList.parentPanel = self
    traitsSection:addChild(panel.baselineTraitList)
    ty = ty + traitListHeight + 6
    createDebugButton(traitsSection, sectionPadding + 60, ty, 134, btnHeight, "Copy Current Traits", self, BurdJournals.UI.DebugPanel.onBaselineCmd, "copycurrenttraits", {r=0.45, g=0.58, b=0.38, a=1}, {r=0.2, g=0.3, b=0.2, a=1})

    local recipesSection = createDebugSectionPanel(panel, padding, y, fullWidth, sectionHeight)
    panel.baselineTabState.panels.recipes = recipesSection
    local ry = sectionPadding
    local baselineRecipeLabelText = getText("UI_BurdJournals_DebugRecipesBaseline")
    local recipesLabel = ISLabel:new(sectionPadding, ry + 2, 18, baselineRecipeLabelText, 0.9, 0.9, 0.7, 1, UIFont.Small, true)
    recipesLabel:initialise()
    recipesLabel:instantiate()
    recipesSection:addChild(recipesLabel)
    local baselineRecipeSearchX = math.max(220, contentWidth - 156)
    panel.baselineRecipeSearch = ISTextEntryBox:new("", baselineRecipeSearchX, ry, 150, 20)
    panel.baselineRecipeSearch:initialise()
    panel.baselineRecipeSearch:instantiate()
    panel.baselineRecipeSearch.font = UIFont.Small
    panel.baselineRecipeSearch:setTooltip("Filter recipes...")
    panel.baselineRecipeSearch.onTextChange = function()
        BurdJournals.UI.DebugPanel.filterBaselineRecipeList(self)
    end
    recipesSection:addChild(panel.baselineRecipeSearch)
    panel.baselineRecipeSourceFilter = createSectionSourceFilterStrip(recipesSection, self, baselineRecipeLabelText, baselineRecipeSearchX, ry, sectionPadding, BurdJournals.UI.DebugPanel.filterBaselineRecipeList, "Filter baseline recipes by source.")
    ry = ry + 24
    local recipeListHeight = math.max(120, sectionHeight - 62)
    panel.baselineRecipeList = ISScrollingListBox:new(sectionPadding, ry, contentWidth, recipeListHeight)
    panel.baselineRecipeList:initialise()
    panel.baselineRecipeList:instantiate()
    panel.baselineRecipeList.itemheight = 30
    panel.baselineRecipeList.backgroundColor = {r=0.08, g=0.08, b=0.1, a=1}
    panel.baselineRecipeList.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    panel.baselineRecipeList.doDrawItem = BurdJournals.UI.DebugPanel.drawBaselineRecipeItem
    panel.baselineRecipeList.onMouseDown = BurdJournals.UI.DebugPanel.onBaselineRecipeListClick
    panel.baselineRecipeList.parentPanel = self
    recipesSection:addChild(panel.baselineRecipeList)
    ry = ry + recipeListHeight + 6
    panel.baselineRecipeBulkTick = createDebugBulkTick(recipesSection, sectionPadding, ry - 1, 52, 20, "All", self, BurdJournals.UI.DebugPanel.onBaselineRecipeBulkToggle, "Set or clear all visible baseline recipes.")
    createDebugButton(recipesSection, sectionPadding + 60, ry, 146, btnHeight, "Copy Current Recipes", self, BurdJournals.UI.DebugPanel.onBaselineCmd, "copycurrentrecipes", {r=0.45, g=0.58, b=0.38, a=1}, {r=0.2, g=0.3, b=0.2, a=1})

    local btnWidth = 136
    local btnSpacing = 8
    local btnX = padding
    createDebugButton(panel, btnX, utilityY, btnWidth, btnHeight, "Clear All Baseline", self, BurdJournals.UI.DebugPanel.onBaselineCmd, "clearall", {r=0.6, g=0.4, b=0.3, a=1}, {r=0.4, g=0.2, b=0.15, a=1})
    btnX = btnX + btnWidth + btnSpacing
    createDebugButton(panel, btnX, utilityY, btnWidth, btnHeight, "Dump to Console", self, BurdJournals.UI.DebugPanel.onBaselineCmd, "dumpbaseline")
    btnX = btnX + btnWidth + btnSpacing
    createDebugButton(panel, btnX, utilityY, btnWidth, btnHeight, "Migrate Journals", self, BurdJournals.UI.DebugPanel.onBaselineCmd, "migratejournals", {r=0.35, g=0.55, b=0.65, a=1}, {r=0.16, g=0.26, b=0.32, a=1})
    btnX = btnX + btnWidth + btnSpacing
    createDebugButton(panel, btnX, utilityY, 170, btnHeight, "Dump Spawn Readiness", self, BurdJournals.UI.DebugPanel.onBaselineCmd, "dumpspawnstate", {r=0.35, g=0.55, b=0.65, a=1}, {r=0.16, g=0.28, b=0.34, a=1})

    setDebugSubTabState(panel.baselineTabState, "skills")

    -- Store reference
    self.baselinePanel = panel
    panel.targetPlayer = self.player  -- Default to current player
    
    -- Initial population
    self:populateBaselinePlayerList()
    self:refreshBaselineData()
end

function BurdJournals.UI.DebugPanel:onBaselineSubTab(button)
    local panel = self.baselinePanel
    if not (panel and panel.baselineTabState and button and button.internal) then
        return
    end
    setDebugSubTabState(panel.baselineTabState, tostring(button.internal))
end

function BurdJournals.UI.DebugPanel:onJournalSubTab(button)
    local panel = self.journalPanel
    if not (panel and panel.journalTabState and button and button.internal) then
        return
    end
    setDebugSubTabState(panel.journalTabState, tostring(button.internal))
end

function BurdJournals.UI.DebugPanel:onSpawnSubTab(button)
    local panel = self.spawnPanel
    if not (panel and panel.spawnTabState and button and button.internal) then
        return
    end
    setDebugSubTabState(panel.spawnTabState, tostring(button.internal))
end

function BurdJournals.UI.DebugPanel.onSpawnProfileChange(self)
    local panel = self.spawnPanel
    if not panel or not panel.spawnProfileCombo then
        return
    end
    local value = panel.spawnProfileCombo:getOptionData(panel.spawnProfileCombo.selected)
        or panel.spawnProfileCombo.options[panel.spawnProfileCombo.selected]
        or "normal"
    value = tostring(value or "normal")
    if value ~= "debug" then
        value = "normal"
    end
    panel.spawnProfile = value
    self:updateSpawnSummary()
end

function BurdJournals.UI.DebugPanel.onSpawnOriginChange(self)
    local panel = self.spawnPanel
    if not panel or not panel.spawnOriginCombo then
        return
    end
    local value = panel.spawnOriginCombo:getOptionData(panel.spawnOriginCombo.selected)
        or panel.spawnOriginCombo.options[panel.spawnOriginCombo.selected]
        or "auto"
    panel.spawnOriginMode = normalizeDebugOriginMode(value)
    self:updateSpawnSummary()
end

function BurdJournals.UI.DebugPanel.onFilledStateChange(self)
    self:updateSpawnSummary()
end

function BurdJournals.UI.DebugPanel:createSnapshotsPanel(startY, height)
    local panel = ISPanel:new(5, startY, self.width - 10, height)
    panel:initialise()
    panel:instantiate()
    panel.backgroundColor = {r=0.12, g=0.12, b=0.15, a=1}
    panel.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    self:addChild(panel)
    self.tabPanels["snapshots"] = panel

    local padding = 10
    local y = padding
    local fullWidth = panel.width - padding * 2

    local heading = ISLabel:new(
        padding,
        y,
        18,
        getText("UI_BurdJournals_BaselineSnapshotManagerTitle") or "Baseline Backup Manager",
        0.88,
        0.84,
        0.96,
        1,
        UIFont.Small,
        true
    )
    heading:initialise()
    heading:instantiate()
    panel:addChild(heading)
    y = y + 22

    local targetLabel = ISLabel:new(
        padding,
        y + 2,
        16,
        getText("UI_BurdJournals_SnapshotTargetPlayer") or "Selected Player:",
        1,
        1,
        1,
        1,
        UIFont.Small,
        true
    )
    targetLabel:initialise()
    targetLabel:instantiate()
    panel:addChild(targetLabel)

    panel.snapshotTargetCombo = ISComboBox:new(padding + 90, y - 2, math.max(190, math.min(260, math.floor(fullWidth * 0.34))), 22, self, BurdJournals.UI.DebugPanel.onSnapshotTargetPlayerChange)
    panel.snapshotTargetCombo:initialise()
    panel.snapshotTargetCombo:instantiate()
    panel.snapshotTargetCombo.font = UIFont.Small
    panel:addChild(panel.snapshotTargetCombo)

    y = y + 28

    local searchLabel = ISLabel:new(
        padding,
        y + 2,
        16,
        getText("UI_BurdJournals_BaselineSnapshotSearch") or "Search:",
        0.8,
        0.8,
        0.9,
        1,
        UIFont.Small,
        true
    )
    searchLabel:initialise()
    searchLabel:instantiate()
    panel:addChild(searchLabel)

    local searchW = math.max(150, math.min(270, math.floor(fullWidth * 0.30)))
    panel.snapshotSearch = ISTextEntryBox:new("", padding + 52, y - 1, searchW, 20)
    panel.snapshotSearch:initialise()
    panel.snapshotSearch:instantiate()
    panel.snapshotSearch.font = UIFont.Small
    panel.snapshotSearch.onTextChange = function()
        if BurdJournals.UI.DebugPanel.instance and BurdJournals.UI.DebugPanel.instance.requestBaselineSnapshots then
            BurdJournals.UI.DebugPanel.instance:requestBaselineSnapshots()
        end
    end
    panel:addChild(panel.snapshotSearch)

    local filterX = panel.snapshotSearch:getX() + panel.snapshotSearch:getWidth() + 10
    if filterX + 210 > (padding + fullWidth) then
        y = y + 24
        filterX = padding
    end

    local filterLabel = ISLabel:new(
        filterX,
        y + 2,
        16,
        getText("UI_BurdJournals_BaselineSnapshotFilter") or "Filter:",
        0.8,
        0.8,
        0.9,
        1,
        UIFont.Small,
        true
    )
    filterLabel:initialise()
    filterLabel:instantiate()
    panel:addChild(filterLabel)

    panel.snapshotFilterCombo = ISComboBox:new(filterX + 38, y - 2, 130, 22, self, BurdJournals.UI.DebugPanel.onBaselineSnapshotFilterChanged)
    panel.snapshotFilterCombo:initialise()
    panel.snapshotFilterCombo:instantiate()
    panel.snapshotFilterCombo.font = UIFont.Small
    panel.snapshotFilterCombo:addOptionWithData(getText("UI_BurdJournals_BaselineSnapshotFilterCurrentTarget") or "Current Target", "target")
    panel.snapshotFilterCombo:addOptionWithData(getText("UI_BurdJournals_BaselineSnapshotFilterSteamId") or "SteamID", "steam")
    panel.snapshotFilterCombo:addOptionWithData(getText("UI_BurdJournals_BaselineSnapshotFilterCharacterId") or "Character ID", "character")
    panel.snapshotFilterCombo.selected = 1
    panel:addChild(panel.snapshotFilterCombo)

    local refreshX = panel.snapshotFilterCombo:getX() + panel.snapshotFilterCombo:getWidth() + 6
    local topRefreshBtn = ISButton:new(
        refreshX,
        y - 2,
        76,
        22,
        getText("UI_BurdJournals_BaselineSnapshotRefresh") or "Refresh",
        self,
        BurdJournals.UI.DebugPanel.onSnapshotCmd
    )
    topRefreshBtn:initialise()
    topRefreshBtn:instantiate()
    topRefreshBtn.font = UIFont.Small
    topRefreshBtn.internal = "baselinesnapshot_refresh"
    topRefreshBtn.textColor = {r=1, g=1, b=1, a=1}
    topRefreshBtn.borderColor = {r=0.4, g=0.5, b=0.6, a=1}
    topRefreshBtn.backgroundColor = {r=0.2, g=0.25, b=0.3, a=1}
    panel:addChild(topRefreshBtn)
    y = y + 26

    panel.snapshotListSummaryLabel = ISLabel:new(
        padding,
        y + 1,
        16,
        "Snapshots: 0",
        0.72,
        0.8,
        0.92,
        1,
        UIFont.Small,
        true
    )
    panel.snapshotListSummaryLabel:initialise()
    panel.snapshotListSummaryLabel:instantiate()
    panel:addChild(panel.snapshotListSummaryLabel)
    y = y + 18

    local contentBottom = panel.height - 56
    local contentHeight = math.max(220, contentBottom - y)
    local splitWide = fullWidth >= 800
    local gap = 8

    if splitWide then
        panel.snapshotListX = padding
        panel.snapshotListY = y
        panel.snapshotListW = math.max(260, math.floor(fullWidth * 0.42))
        panel.snapshotListH = contentHeight
        panel.snapshotPreviewX = panel.snapshotListX + panel.snapshotListW + gap
        panel.snapshotPreviewY = y
        panel.snapshotPreviewW = fullWidth - panel.snapshotListW - gap
        panel.snapshotPreviewH = contentHeight
    else
        panel.snapshotListX = padding
        panel.snapshotListY = y
        panel.snapshotListW = fullWidth
        panel.snapshotListH = math.max(120, math.floor(contentHeight * 0.34))
        panel.snapshotPreviewX = padding
        panel.snapshotPreviewY = panel.snapshotListY + panel.snapshotListH + gap
        panel.snapshotPreviewW = fullWidth
        panel.snapshotPreviewH = contentHeight - panel.snapshotListH - gap
    end

    panel.snapshotList = ISScrollingListBox:new(panel.snapshotListX, panel.snapshotListY, panel.snapshotListW, panel.snapshotListH)
    panel.snapshotList:initialise()
    panel.snapshotList:instantiate()
    panel.snapshotList.itemheight = 36
    panel.snapshotList.backgroundColor = {r=0.08, g=0.08, b=0.1, a=1}
    panel.snapshotList.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    panel.snapshotList.parentPanel = self
    panel.snapshotList.doDrawItem = BurdJournals.UI.DebugPanel.drawBaselineSnapshotItem
    panel.snapshotList.onMouseDown = BurdJournals.UI.DebugPanel.onBaselineSnapshotListClick
    panel:addChild(panel.snapshotList)

    local px = panel.snapshotPreviewX
    local py = panel.snapshotPreviewY
    local pw = panel.snapshotPreviewW
    local ph = panel.snapshotPreviewH

    panel.snapshotDetailLabel = ISLabel:new(
        px,
        py,
        16,
        getText("UI_BurdJournals_BaselineSnapshotDetailNone") or "Select a snapshot to preview details.",
        0.7,
        0.75,
        0.85,
        1,
        UIFont.Small,
        true
    )
    panel.snapshotDetailLabel:initialise()
    panel.snapshotDetailLabel:instantiate()
    panel:addChild(panel.snapshotDetailLabel)
    py = py + 18

    panel.snapshotDetailMetaLabel = ISLabel:new(
        px,
        py,
        16,
        "",
        0.72,
        0.78,
        0.88,
        1,
        UIFont.Small,
        true
    )
    panel.snapshotDetailMetaLabel:initialise()
    panel.snapshotDetailMetaLabel:instantiate()
    panel:addChild(panel.snapshotDetailMetaLabel)
    py = py + 16

    panel.snapshotCurrentLabel = ISLabel:new(
        px,
        py,
        16,
        getText("UI_BurdJournals_SnapshotCurrentBaselineLabel") or "Current baseline comparison: waiting for server...",
        0.62,
        0.78,
        0.92,
        1,
        UIFont.Small,
        true
    )
    panel.snapshotCurrentLabel:initialise()
    panel.snapshotCurrentLabel:instantiate()
    panel:addChild(panel.snapshotCurrentLabel)
    py = py + 18

    local skillH = math.max(90, math.floor(ph * 0.55))
    local remainingH = ph - (py - panel.snapshotPreviewY) - skillH - 8
    if remainingH < 66 then
        skillH = math.max(76, skillH + remainingH - 66)
        remainingH = 66
    end

    panel.snapshotSkillPreviewList = ISScrollingListBox:new(px, py, pw, skillH)
    panel.snapshotSkillPreviewList:initialise()
    panel.snapshotSkillPreviewList:instantiate()
    panel.snapshotSkillPreviewList.itemheight = 32
    panel.snapshotSkillPreviewList.backgroundColor = {r=0.08, g=0.08, b=0.1, a=1}
    panel.snapshotSkillPreviewList.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    panel.snapshotSkillPreviewList.parentPanel = self
    panel.snapshotSkillPreviewList.doDrawItem = BurdJournals.UI.DebugPanel.drawSnapshotSkillPreviewItem
    panel:addChild(panel.snapshotSkillPreviewList)
    py = py + skillH + 8

    local diffGap = 6
    local diffW = math.floor((pw - (diffGap * 2)) / 3)
    panel.snapshotTraitDiffList = ISScrollingListBox:new(px, py, diffW, remainingH)
    panel.snapshotTraitDiffList:initialise()
    panel.snapshotTraitDiffList:instantiate()
    panel.snapshotTraitDiffList.itemheight = 18
    panel.snapshotTraitDiffList.backgroundColor = {r=0.08, g=0.08, b=0.1, a=1}
    panel.snapshotTraitDiffList.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    panel.snapshotTraitDiffList.parentPanel = self
    panel.snapshotTraitDiffList.doDrawItem = BurdJournals.UI.DebugPanel.drawSnapshotDiffItem
    panel:addChild(panel.snapshotTraitDiffList)

    panel.snapshotRecipeDiffList = ISScrollingListBox:new(px + diffW + diffGap, py, diffW, remainingH)
    panel.snapshotRecipeDiffList:initialise()
    panel.snapshotRecipeDiffList:instantiate()
    panel.snapshotRecipeDiffList.itemheight = 18
    panel.snapshotRecipeDiffList.backgroundColor = {r=0.08, g=0.08, b=0.1, a=1}
    panel.snapshotRecipeDiffList.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    panel.snapshotRecipeDiffList.parentPanel = self
    panel.snapshotRecipeDiffList.doDrawItem = BurdJournals.UI.DebugPanel.drawSnapshotDiffItem
    panel:addChild(panel.snapshotRecipeDiffList)

    panel.snapshotMediaDiffList = ISScrollingListBox:new(px + ((diffW + diffGap) * 2), py, diffW, remainingH)
    panel.snapshotMediaDiffList:initialise()
    panel.snapshotMediaDiffList:instantiate()
    panel.snapshotMediaDiffList.itemheight = 18
    panel.snapshotMediaDiffList.backgroundColor = {r=0.08, g=0.08, b=0.1, a=1}
    panel.snapshotMediaDiffList.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    panel.snapshotMediaDiffList.parentPanel = self
    panel.snapshotMediaDiffList.doDrawItem = BurdJournals.UI.DebugPanel.drawSnapshotDiffItem
    panel:addChild(panel.snapshotMediaDiffList)

    local btnY = panel.height - 32
    local btnGap = 6
    local btnW = math.max(120, math.floor((fullWidth - (btnGap * 2)) / 3))
    local btnX = padding
    local function makeSnapshotButton(labelKey, fallback, internal, border, bg)
        local btn = ISButton:new(
            btnX,
            btnY,
            btnW,
            22,
            getText(labelKey) or fallback,
            self,
            BurdJournals.UI.DebugPanel.onSnapshotCmd
        )
        btn:initialise()
        btn:instantiate()
        btn.font = UIFont.Small
        btn.internal = internal
        btn.textColor = {r=1, g=1, b=1, a=1}
        btn.borderColor = border
        btn.backgroundColor = bg
        panel:addChild(btn)
        btnX = btnX + btnW + btnGap
        return btn
    end

    makeSnapshotButton("UI_BurdJournals_BaselineSnapshotSave", "Save Snapshot", "baselinesnapshot_save", {r=0.35, g=0.55, b=0.4, a=1}, {r=0.18, g=0.3, b=0.22, a=1})
    makeSnapshotButton("UI_BurdJournals_BaselineSnapshotApply", "Apply Snapshot", "baselinesnapshot_apply", {r=0.55, g=0.52, b=0.75, a=1}, {r=0.22, g=0.18, b=0.32, a=1})
    makeSnapshotButton("UI_BurdJournals_BaselineSnapshotDelete", "Delete Snapshot", "baselinesnapshot_delete", {r=0.65, g=0.38, b=0.38, a=1}, {r=0.35, g=0.16, b=0.16, a=1})

    panel.snapshotItems = {}
    panel.snapshotSelectedId = nil
    panel.snapshotSelectedData = nil
    panel.snapshotCurrentPage = 1
    panel.snapshotPageSize = 20
    panel.snapshotLiveBaselinePayload = nil
    panel.snapshotPreviewRows = {}
    panel.snapshotTraitDiffRows = {}
    panel.snapshotRecipeDiffRows = {}
    panel.snapshotMediaDiffRows = {}

    self.snapshotPanel = panel
    panel.targetPlayer = self.player
    self:populateSnapshotPlayerList()
    self:refreshSnapshotPanelData()
end

-- Populate player dropdown with online players
function BurdJournals.UI.DebugPanel:populateBaselinePlayerList()
    local panel = self.baselinePanel
    if not panel or not panel.targetPlayerCombo then return end

    local selectedPlayer = panel.targetPlayer or self:getSharedTargetPlayer() or self.player
    local selectedName = getDebugTargetPlayerName(selectedPlayer)
    panel.targetPlayerCombo:clear()

    local targetablePlayers = collectDebugTargetablePlayers(self)
    for _, playerObj in ipairs(targetablePlayers) do
        panel.targetPlayerCombo:addOptionWithData(getDebugTargetPlayerName(playerObj), playerObj)
    end
    
    if selectedName and selectedName ~= "" then
        panel.targetPlayerCombo:select(selectedName)
    else
        panel.targetPlayerCombo:select(getDebugTargetPlayerName(self.player))
    end
    panel.targetPlayer = selectedPlayer
end

-- Handler for player selection change
function BurdJournals.UI.DebugPanel:onBaselineTargetPlayerChange(combo)
    if self.suppressTargetSync then
        return
    end

    local panel = self.baselinePanel
    if not panel then return end
    
    local selectedPlayer = getDebugComboSelectedData(combo)
    if selectedPlayer then
        self:applySharedTargetPlayer(selectedPlayer, {
            statusText = BurdJournals.formatText(getText("UI_BurdJournals_DebugViewingStartingData"), getDebugTargetPlayerName(selectedPlayer)),
        })
    end
end

-- Refresh button handler (non-destructive - just refreshes display without modifying baseline)
function BurdJournals.UI.DebugPanel:onBaselineRefresh()
    local function doRefresh()
        -- Don't clear skill cache - that's for full rediscovery
        -- Just refresh the player list and current baseline data display
        self:populateBaselinePlayerList()
        self:refreshBaselineData()
        self:setStatus("Display refreshed (baseline unchanged)", {r=0.5, g=0.8, b=1})
    end

    if self:hasUnsavedBaselineDraft() then
        self:confirmDiscardBaselineDraft(
            getText("UI_BurdJournals_BaselineDraftActionRefresh") or "refresh baseline data",
            doRefresh
        )
        return
    end

    doRefresh()
end

-- Refresh baseline data for the target player
function BurdJournals.UI.DebugPanel:refreshBaselineData(authoritativeRefresh)
    local panel = self.baselinePanel
    if not panel then return end
    panel.baselineDraftDirty = false
    panel.baselineDraftSkills = {}
    panel.baselineDraftTraits = {}
    if self.updateBaselineDraftButtons then
        self:updateBaselineDraftButtons()
    end

    local targetPlayer = panel.targetPlayer or self.player
    if not targetPlayer then 
        -- No player yet, skip population
        return 
    end
    local targetUsername = targetPlayer and targetPlayer.getUsername and targetPlayer:getUsername() or nil
    local authoritativeBaselineArgs = nil
    local authoritativeBaseline = nil
    if targetUsername and self.authoritativeBaselineData then
        authoritativeBaselineArgs = self.authoritativeBaselineData[tostring(targetUsername)]
        authoritativeBaseline = authoritativeBaselineArgs and authoritativeBaselineArgs.baselinePayload or nil
    end

    local localPlayer = getPlayer and getPlayer() or self.player
    local isLocalTarget = targetPlayer == localPlayer
    if not isLocalTarget and targetPlayer and localPlayer then
        local targetName = targetPlayer.getUsername and targetPlayer:getUsername() or nil
        local localName = localPlayer.getUsername and localPlayer:getUsername() or nil
        if targetName and localName and targetName == localName then
            isLocalTarget = true
        end
    end
    if BurdJournals.clientShouldUseServerAuthority()
        and not isLocalTarget
        and authoritativeRefresh ~= true
    then
        self:requestAuthoritativeBaselineData("baselineRefresh")
        if type(authoritativeBaseline) ~= "table" and self.setStatus then
            self:setStatus("Requesting authoritative target baseline...", {r=0.5, g=0.8, b=1})
        end
        return
    end

    local bootstrapPlayer = isLocalTarget and localPlayer or targetPlayer
    if isLocalTarget
        and bootstrapPlayer
        and BurdJournals
        and BurdJournals.Client
        and BurdJournals.Client.tryBootstrapPendingNewCharacterBaseline then
        BurdJournals.Client.tryBootstrapPendingNewCharacterBaseline(bootstrapPlayer, "debug_panel_refresh", true)
    end
    
    -- Get player's XP object safely (same logic as Character tab)
    local xpObj = nil
    if targetPlayer and targetPlayer.getXp then
        xpObj = targetPlayer:getXp()
    end
    
    -- If we still don't have xpObj, try refreshing targetPlayer reference
    if not xpObj and targetPlayer and targetPlayer.getUsername then
        local username = targetPlayer:getUsername()
        if username then
            local onlinePlayers = getOnlinePlayers and getOnlinePlayers()
            if onlinePlayers then
                for i = 0, onlinePlayers:size() - 1 do
                    local p = onlinePlayers:get(i)
                    if p and p.getUsername and p:getUsername() == username then
                        targetPlayer = p
                        panel.targetPlayer = p  -- Update panel reference too
                        if p.getXp then
                            xpObj = p:getXp()
                        end
                        break
                    end
                end
            end
        end
    end

    -- Refresh skills list using enhanced metadata discovery
    if panel.baselineSkillList and panel.baselineSkillList.clear then
        panel.baselineSkillList:clear()
        
        -- Use enhanced skill metadata (includes modded skills with full info)
        local skillMetadata = nil
        if BurdJournals and BurdJournals.discoverSkillMetadata then
            skillMetadata = BurdJournals.discoverSkillMetadata()
        end
        
        -- Fallback to simple discovery if metadata not available
        if not skillMetadata then
            skillMetadata = {}
            local skills = {}
            if BurdJournals and BurdJournals.getAllowedSkills then
                local result = BurdJournals.getAllowedSkills()
                if result then skills = result end
            end
            for _, skillName in ipairs(skills) do
                skillMetadata[skillName] = {
                    id = skillName,
                    displayName = skillName,
                    category = "Unknown",
                    isVanilla = true,
                    isPassive = (skillName == "Fitness" or skillName == "Strength")
                }
            end
        end
        
        -- Sort skills by category then by display name
        local sortedSkills = {}
        for perkId, data in pairs(skillMetadata) do
            table.insert(sortedSkills, data)
        end
        table.sort(sortedSkills, function(a, b)
            -- Sort by category first, then by display name
            if a.category ~= b.category then
                return (a.category or "ZZZ") < (b.category or "ZZZ")
            end
            return (a.displayName or a.id) < (b.displayName or b.id)
        end)

        for _, skillData in ipairs(sortedSkills) do
            local skillName = skillData.id
            local currentLevel = 0
            local baselineLevel = 0
            local displayName = skillData.displayName or skillName
            local isPassive = skillData.isPassive or false
            local category = skillData.category or "Other"
            local isModded = not skillData.isVanilla
            
            -- Get perk object with fallbacks
            local perk = nil
            if BurdJournals and BurdJournals.getPerkByName then
                perk = BurdJournals.getPerkByName(skillName)
            end
            -- Fallback: try Perks directly
            if not perk and Perks then
                local perkId = skillData.perkId or skillName
                if Perks[perkId] then perk = Perks[perkId] end
            end
            
            -- Get current level and XP with multiple methods
            local currentXP = 0
            if perk and targetPlayer then
                -- Method 1: getPerkLevel (most reliable)
                if targetPlayer.getPerkLevel then
                    local result = targetPlayer:getPerkLevel(perk)
                    if type(result) == "number" then
                        currentLevel = result
                    end
                end
                
                -- Get current XP
                if xpObj and xpObj.getXP then
                    local xp = BurdJournals.getPlayerSkillTotalXP and BurdJournals.getPlayerSkillTotalXP(targetPlayer, perk, skillName) or xpObj:getXP(perk)
                    if type(xp) == "number" then
                        currentXP = xp
                    end
                end
                
                -- Method 2: Calculate level from XP if getPerkLevel didn't work
                if currentLevel == 0 and currentXP > 0 then
                    -- Calculate level from XP using corrected helper
                    if BurdJournals.Client.Debug.getLevelFromXP then
                        currentLevel = BurdJournals.Client.Debug.getLevelFromXP(skillName, currentXP)
                    elseif perk.getTotalXpForLevel then
                        -- Fallback: getTotalXpForLevel(N) = XP to COMPLETE level N
                        -- So level N requires XP >= getTotalXpForLevel(N-1)
                        for l = 10, 1, -1 do
                            local threshold = perk:getTotalXpForLevel(l - 1) or 0
                            if currentXP >= threshold then
                                currentLevel = l
                                break
                            end
                        end
                    end
                end
            end
            
            -- Get baseline level
            if type(authoritativeBaseline) == "table"
                and type(authoritativeBaseline.skillBaseline) == "table"
                and authoritativeBaseline.skillBaseline[skillName] ~= nil then
                local baselineXPValue = tonumber(authoritativeBaseline.skillBaseline[skillName]) or 0
                baselineLevel = BurdJournals.Client.Debug.getLevelFromXP
                    and BurdJournals.Client.Debug.getLevelFromXP(skillName, baselineXPValue)
                    or baselineLevel
            elseif BurdJournals and BurdJournals.getSkillBaselineLevel then
                local lvl = BurdJournals.getSkillBaselineLevel(targetPlayer, skillName)
                if lvl and type(lvl) == "number" then 
                    baselineLevel = lvl 
                end
            end

            -- Calculate baseline XP from baseline level
            -- Use our verified threshold tables for consistent values
            local baselineXP = 0
            if type(authoritativeBaseline) == "table"
                and type(authoritativeBaseline.skillBaseline) == "table"
                and authoritativeBaseline.skillBaseline[skillName] ~= nil then
                baselineXP = math.max(0, tonumber(authoritativeBaseline.skillBaseline[skillName]) or 0)
            elseif baselineLevel > 0 then
                if isPassive then
                    baselineXP = BurdJournals.PASSIVE_XP_THRESHOLDS and BurdJournals.PASSIVE_XP_THRESHOLDS[baselineLevel] or 0
                else
                    baselineXP = BurdJournals.STANDARD_XP_THRESHOLDS and BurdJournals.STANDARD_XP_THRESHOLDS[baselineLevel] or 0
                end
            end

            -- Format display: add [MOD] prefix for modded skills
            local itemLabel = displayName
            if isModded then
                itemLabel = "[MOD] " .. displayName
            end

            panel.baselineSkillList:addItem(itemLabel, {
                name = skillName,
                displayName = displayName,
                currentLevel = currentLevel,
                currentXP = currentXP,
                baselineLevel = baselineLevel,
                baselineXP = baselineXP,
                isPassive = isPassive,
                category = category,
                isModded = isModded,
                source = BurdJournals.getSkillModSource and BurdJournals.getSkillModSource(skillName) or (isModded and "Modded" or "Vanilla"),
                sourceId = BurdJournals.getSkillModId and BurdJournals.getSkillModId(skillName) or (isModded and "modded" or "vanilla"),
            })
        end
    end

    -- Refresh traits list - show ALL traits for baseline management
    -- Uses comprehensive discovery (same as Spawn panel - includes modded and neutral traits)
    if panel.baselineTraitList and panel.baselineTraitList.clear then
        panel.baselineTraitList:clear()
        
        -- Use discoverGrantableTraits (includes negative traits for debug/baseline panel)
        -- This discovers ALL traits including modded ones and neutral/profession traits
        local discoveredTraits = {}
        if BurdJournals and BurdJournals.discoverGrantableTraits then
            local result = BurdJournals.discoverGrantableTraits(true)  -- true = include negative
            if result and type(result) == "table" then
                discoveredTraits = result
            end
        end
        
        -- Fallback to older methods if discovery failed
        if #discoveredTraits == 0 then
            local posTraits = BurdJournals.getPositiveTraits and BurdJournals.getPositiveTraits() or {}
            local negTraits = BurdJournals.getNegativeTraits and BurdJournals.getNegativeTraits() or {}
            for _, t in ipairs(posTraits) do table.insert(discoveredTraits, t) end
            for _, t in ipairs(negTraits) do table.insert(discoveredTraits, t) end
        end
        
        -- Get trait baseline data for the target player (case-insensitive lookup)
        local traitBaseline = {}
        local traitBaselineLower = {}  -- For case-insensitive lookup
        if type(authoritativeBaseline) == "table" and type(authoritativeBaseline.traitBaseline) == "table" then
            traitBaseline = authoritativeBaseline.traitBaseline
            for traitId, isBaseline in pairs(traitBaseline) do
                if isBaseline then
                    traitBaselineLower[string.lower(tostring(traitId))] = true
                end
            end
        elseif BurdJournals and BurdJournals.getTraitBaseline then
            local result = BurdJournals.getTraitBaseline(targetPlayer)
            if result then 
                traitBaseline = result
            end
            -- Build lowercase lookup table
            for traitId, isBaseline in pairs(traitBaseline) do
                if isBaseline then
                    traitBaselineLower[string.lower(traitId)] = true
                end
            end
        end
        
        -- Build combined list of all traits with deduplication and polarity detection
        local sortedTraits = {}
        local addedTraits = {}  -- lowercase keys for deduplication
        
        -- Build a cost lookup for polarity detection
        local traitCostLookup = BurdJournals.UI.DebugPanel.buildTraitCostLookup()
        
        -- Add all discovered traits, deduplicating by DISPLAY NAME (not just ID)
        -- This handles B42's trait variants (e.g., AdrenalineJunkie and adrenalinejunkie2 both show "Adrenaline Junkie")
        local addedDisplayNames = {}  -- Track display names to prevent visual duplicates
        for _, traitId in ipairs(discoveredTraits) do
            local traitIdLower = string.lower(traitId)
            if not addedTraits[traitIdLower] then
                local displayName = traitId
                if BurdJournals and BurdJournals.getTraitDisplayName then
                    local name = BurdJournals.getTraitDisplayName(traitId)
                    if name then displayName = name end
                end
                
                -- Skip if we already have a trait with this display name (B42 variant handling)
                local displayNameLower = string.lower(displayName)
                if addedDisplayNames[displayNameLower] then
                    -- Skip this variant - we already have one with the same display name
                    -- Prefer non-"2" variants (e.g., prefer AdrenalineJunkie over adrenalinejunkie2)
                else
                    -- Determine polarity from cost
                    local isPositive = BurdJournals.UI.DebugPanel.resolveTraitIsPositive(traitId, nil, traitCostLookup)
                    local traitSource = BurdJournals.getTraitModSource and BurdJournals.getTraitModSource(traitId) or "Vanilla"
                    local traitSourceId = BurdJournals.getTraitModId and BurdJournals.getTraitModId(traitId) or traitSource
                    
                    table.insert(sortedTraits, {
                        id = traitId,
                        displayName = displayName,
                        isPositive = isPositive,
                        isModded = traitSource ~= "Vanilla",
                        source = traitSource,
                        sourceId = traitSourceId,
                    })
                    addedTraits[traitIdLower] = true
                    addedDisplayNames[displayNameLower] = traitId  -- Track by display name
                end
            end
        end
        
        -- Sort: positive first, then by display name
        table.sort(sortedTraits, function(a, b)
            if a.isPositive ~= b.isPositive then
                return a.isPositive  -- Positive traits first
            end
            return (a.displayName or a.id) < (b.displayName or b.id)
        end)
        
        BurdJournals.debugPrint("[BSJ DebugPanel] Showing " .. #sortedTraits .. " traits for baseline management")
        
        -- Add all traits to list
        for _, traitData in ipairs(sortedTraits) do
            local traitId = traitData.id
            local displayName = traitData.displayName or traitId
            local isPassiveSkillTrait = false
            
            -- Check if passive skill trait
            if BurdJournals and BurdJournals.isPassiveSkillTrait then
                isPassiveSkillTrait = BurdJournals.isPassiveSkillTrait(traitId) == true
            end
            
            -- Format display: add markers for negative traits
            local itemLabel = displayName
            if not traitData.isPositive then
                itemLabel = itemLabel .. " (-)"
            end
            
            -- Check if this trait is in baseline (case-insensitive)
            local isInBaseline = traitBaseline[traitId] or traitBaselineLower[string.lower(traitId)] or false
            local hasTrait = BurdJournals.playerHasTrait and BurdJournals.playerHasTrait(targetPlayer, traitId) or false
            
            panel.baselineTraitList:addItem(itemLabel, {
                id = traitId,
                displayName = displayName,
                isBaseline = isInBaseline,
                isPassiveSkillTrait = isPassiveSkillTrait,
                isPositive = traitData.isPositive,
                isModded = traitData.isModded or false,
                hasTrait = hasTrait,
                traitTexture = getDebugTraitTexture(traitId),
                source = traitData.source,
                sourceId = traitData.sourceId,
            })
        end
    end

    if panel.baselineRecipeList and panel.baselineRecipeList.clear then
        panel.baselineRecipeList:clear()
        local recipeRows = buildDebugRecipeRows(targetPlayer, true, true)
        if type(authoritativeBaseline) == "table" and type(authoritativeBaseline.recipeBaseline) == "table" then
            local recipeBaseline = authoritativeBaseline.recipeBaseline
            local seen = {}
            for _, row in ipairs(recipeRows) do
                row.isBaseline = recipeBaseline[row.name] == true
                seen[row.name] = true
            end
            for recipeName, isBaseline in pairs(recipeBaseline) do
                if isBaseline == true and not seen[recipeName] then
                    local magazineSource = BurdJournals.getMagazineForRecipe and BurdJournals.getMagazineForRecipe(recipeName) or nil
                    recipeRows[#recipeRows + 1] = {
                        name = recipeName,
                        displayName = BurdJournals.getRecipeDisplayName and BurdJournals.getRecipeDisplayName(recipeName) or tostring(recipeName),
                        source = BurdJournals.getRecipeModSource and BurdJournals.getRecipeModSource(recipeName, magazineSource) or "Unknown",
                        sourceId = BurdJournals.getRecipeModId and BurdJournals.getRecipeModId(recipeName, magazineSource) or nil,
                        magazineSource = magazineSource,
                        magazineDisplayName = magazineSource and BurdJournals.getMagazineDisplayName and BurdJournals.getMagazineDisplayName(magazineSource) or nil,
                        isKnown = false,
                        isBaseline = true,
                        hasMagazine = magazineSource ~= nil and tostring(magazineSource) ~= "",
                    }
                end
            end
            sortDebugRecipeRows(recipeRows)
        end
        for _, row in ipairs(recipeRows) do
            row.recipeTexture = getDebugRecipeTexture()
            row.magazineTexture = getDebugMagazineTexture(row.magazineSource)
            row.magazineDisplayName = row.magazineDisplayName or (row.magazineSource and BurdJournals.getMagazineDisplayName and BurdJournals.getMagazineDisplayName(row.magazineSource) or nil)
            panel.baselineRecipeList:addItem(row.displayName, row)
        end
    end
    refreshDebugSourceFilterStrip(panel.baselineSkillSourceFilter, panel.baselineSkillList and panel.baselineSkillList.items or nil)
    refreshDebugSourceFilterStrip(panel.baselineTraitSourceFilter, panel.baselineTraitList and panel.baselineTraitList.items or nil)
    refreshDebugSourceFilterStrip(panel.baselineRecipeSourceFilter, panel.baselineRecipeList and panel.baselineRecipeList.items or nil)

    BurdJournals.UI.DebugPanel.filterBaselineSkillList(self)
    BurdJournals.UI.DebugPanel.filterBaselineTraitList(self)
    BurdJournals.UI.DebugPanel.filterBaselineRecipeList(self)

end

function BurdJournals.UI.DebugPanel:updateBaselineDraftButtons()
    local panel = self.baselinePanel
    if not panel then
        return
    end
    local dirty = panel.baselineDraftDirty == true
    if panel.saveBaselineChangesBtn then
        panel.saveBaselineChangesBtn.enable = dirty
        panel.saveBaselineChangesBtn.textColor = dirty and {r=1, g=1, b=1, a=1} or {r=0.65, g=0.65, b=0.65, a=1}
    end
    if panel.discardBaselineChangesBtn then
        panel.discardBaselineChangesBtn.enable = dirty
        panel.discardBaselineChangesBtn.textColor = dirty and {r=1, g=1, b=1, a=1} or {r=0.65, g=0.65, b=0.65, a=1}
    end
end

function BurdJournals.UI.DebugPanel:markBaselineDraftDirty(message)
    local panel = self.baselinePanel
    if not panel then
        return
    end
    panel.baselineDraftDirty = true
    self:updateBaselineDraftButtons()
    self:setStatus(message or (getText("UI_BurdJournals_BaselineDraftPending") or "Baseline draft pending. Save to apply."), {r=0.95, g=0.8, b=0.4})
end

function BurdJournals.UI.DebugPanel:buildBaselineDraftPayload()
    local panel = self.baselinePanel
    if not panel then
        return nil
    end

    local skillBaseline = {}
    if panel.baselineSkillList and panel.baselineSkillList.items then
        for _, row in ipairs(panel.baselineSkillList.items) do
            local data = row and row.item
            if data and data.name then
                skillBaseline[tostring(data.name)] = math.max(0, math.floor(tonumber(data.baselineXP) or 0))
            end
        end
    end

    local traitBaseline = {}
    if panel.baselineTraitList and panel.baselineTraitList.items then
        for _, row in ipairs(panel.baselineTraitList.items) do
            local data = row and row.item
            if data and data.id and data.isBaseline then
                local aliases = BurdJournals.getTraitAliases and BurdJournals.getTraitAliases(data.id) or {data.id, string.lower(tostring(data.id))}
                for _, alias in ipairs(aliases) do
                    if alias and alias ~= "" then
                        traitBaseline[tostring(alias)] = true
                    end
                end
            end
        end
    end

    local recipeBaseline = {}
    if panel.baselineRecipeList and panel.baselineRecipeList.items then
        for _, row in ipairs(panel.baselineRecipeList.items) do
            local data = row and row.item
            if data and data.name and data.isBaseline then
                recipeBaseline[tostring(data.name)] = true
            end
        end
    end

    return {
        skillBaseline = skillBaseline,
        traitBaseline = traitBaseline,
        recipeBaseline = recipeBaseline,
    }
end

function BurdJournals.UI.DebugPanel.getPanelDimensions()
    local core = getCore and getCore() or nil
    local screenW = core and core.getScreenWidth and core:getScreenWidth() or BurdJournals.UI.DebugPanel.DEFAULT_WIDTH
    local screenH = core and core.getScreenHeight and core:getScreenHeight() or BurdJournals.UI.DebugPanel.DEFAULT_HEIGHT
    local margin = tonumber(BurdJournals.UI.DebugPanel.SCREEN_MARGIN) or 24

    local maxW = math.max(420, screenW - (margin * 2))
    local maxH = math.max(420, screenH - (margin * 2))
    local minW = math.max(420, tonumber(BurdJournals.UI.DebugPanel.MIN_WIDTH) or 760)
    local minH = math.max(420, tonumber(BurdJournals.UI.DebugPanel.MIN_HEIGHT) or 680)
    local defaultW = math.max(minW, tonumber(BurdJournals.UI.DebugPanel.DEFAULT_WIDTH) or 860)
    local defaultH = math.max(minH, tonumber(BurdJournals.UI.DebugPanel.DEFAULT_HEIGHT) or 760)

    local width = math.floor(math.max(minW, math.min(maxW, defaultW)))
    local height = math.floor(math.max(minH, math.min(maxH, defaultH)))
    return width, height
end

-- Draw function for skill items (read-only mode when baseline is disabled)
function BurdJournals.UI.DebugPanel.drawBaselineSkillItemReadOnly(self, y, item, alt)
    local h = getDebugListRowHeight(self, item, self.itemheight or 24)
    local data = item.item
    
    -- Skip hidden items (filtered by search)
    if data.hidden then return y + h end
    
    -- Background
    if self.mouseoverselected == item.index then
        self:drawRect(0, y, self.width, h, 0.2, 0.2, 0.3, 0.3)
    end
    
    -- Skill name
    local textX = 8
    self:drawText(data.displayName, textX, y + 4, 0.9, 0.9, 0.9, 1, UIFont.Small)
    
    -- Current level
    local levelText = BurdJournals.formatText(getText("UI_BurdJournals_LevelFormat"), tonumber(data.currentLevel) or 0)
    self:drawText(levelText, 150, y + 4, 0.5, 0.8, 0.6, 1, UIFont.Small)
    
    -- Squares showing current level + partial progress
    local squaresX = 230
    local squareSize = 14
    local squareSpacing = 2
    local currentLevel = tonumber(data.currentLevel) or 0
    local currentXP = tonumber(data.currentXP) or 0

    local progress = 0
    if currentLevel < 10 then
        local perk = BurdJournals.getPerkByName and BurdJournals.getPerkByName(data.name)
        if perk and perk.getTotalXpForLevel then
            local levelStartXP = currentLevel > 0 and (perk:getTotalXpForLevel(currentLevel - 1) or 0) or 0
            local levelEndXP = perk:getTotalXpForLevel(currentLevel) or (levelStartXP + 150)
            local xpRange = levelEndXP - levelStartXP
            if xpRange > 0 then
                progress = math.max(0, math.min(1, (currentXP - levelStartXP) / xpRange))
            end
        end
    end
    
    for lvl = 1, 10 do
        local sqX = squaresX + (lvl - 1) * (squareSize + squareSpacing)
        local sqY = y + (h - squareSize) / 2
        
        if lvl <= currentLevel then
            -- Current level (filled)
            self:drawRect(sqX, sqY, squareSize, squareSize, 0.9, 0.3, 0.6, 0.5)
        elseif lvl == currentLevel + 1 and progress > 0 then
            self:drawRect(sqX, sqY, squareSize, squareSize, 0.5, 0.1, 0.1, 0.12)
            local fillHeight = squareSize * progress
            self:drawRect(sqX, sqY + squareSize - fillHeight, squareSize, fillHeight, 0.8, 0.2, 0.4, 0.35)
        else
            -- Empty
            self:drawRect(sqX, sqY, squareSize, squareSize, 0.5, 0.1, 0.1, 0.12)
        end
        self:drawRectBorder(sqX, sqY, squareSize, squareSize, 0.4, 0.3, 0.35, 0.4)
    end
    
    return y + h
end

-- Filter functions for Baseline tab
function BurdJournals.UI.DebugPanel.filterBaselineSkillList(self)
    local panel = self.baselinePanel
    if not panel or not panel.baselineSkillList then return end
    
    local searchText = ""
    if panel.baselineSkillSearch and panel.baselineSkillSearch.getText then
        searchText = panel.baselineSkillSearch:getText()
    end
    local selectedSourceId = panel.baselineSkillSourceFilter and panel.baselineSkillSourceFilter.selectedSourceId or "all"
    
    applyDebugRowFilter(panel.baselineSkillList, function(row)
        local matchesSearch = searchText == "" or debugSearchMatches(searchText, row.displayName, row.name, row.category, row.source)
        local matchesSource = debugRowMatchesSourceFilter(row, selectedSourceId)
        return matchesSearch and matchesSource
    end)
end

function BurdJournals.UI.DebugPanel.filterBaselineTraitList(self)
    local panel = self.baselinePanel
    if not panel or not panel.baselineTraitList then return end
    
    local searchText = ""
    if panel.baselineTraitSearch and panel.baselineTraitSearch.getText then
        searchText = panel.baselineTraitSearch:getText()
    end
    local selectedSourceId = panel.baselineTraitSourceFilter and panel.baselineTraitSourceFilter.selectedSourceId or "all"
    local selectedPolarity = getDebugTraitPolarityFilterValue(panel.baselineTraitPolarityFilter)
    
    applyDebugRowFilter(panel.baselineTraitList, function(row)
        local matchesSearch = searchText == "" or debugSearchMatches(searchText, row.displayName, row.id, row.source)
        local matchesSource = debugRowMatchesSourceFilter(row, selectedSourceId)
        local matchesPolarity = debugRowMatchesTraitPolarityFilter(row, selectedPolarity)
        return matchesSearch and matchesSource and matchesPolarity
    end)
    BurdJournals.UI.DebugPanel.refreshBaselineBulkToggles(self)
end

function BurdJournals.UI.DebugPanel.filterBaselineRecipeList(self)
    local panel = self.baselinePanel
    if not panel or not panel.baselineRecipeList then return end

    local searchText = ""
    if panel.baselineRecipeSearch and panel.baselineRecipeSearch.getText then
        searchText = panel.baselineRecipeSearch:getText()
    end
    local selectedSourceId = panel.baselineRecipeSourceFilter and panel.baselineRecipeSourceFilter.selectedSourceId or "all"

    applyDebugRowFilter(panel.baselineRecipeList, function(row)
        local matchesSearch = searchText == "" or debugSearchMatches(searchText, row.displayName, row.name, row.magazineSource, row.magazineDisplayName, row.source)
        local matchesSource = debugRowMatchesSourceFilter(row, selectedSourceId)
        return matchesSearch and matchesSource
    end)
    BurdJournals.UI.DebugPanel.refreshBaselineBulkToggles(self)
end

function BurdJournals.UI.DebugPanel.refreshBaselineBulkToggles(self)
    local panel = self and self.baselinePanel or nil
    if not panel then
        return
    end

    refreshDebugBulkTickState(panel.baselineTraitBulkTick, panel.baselineTraitList, function(row)
        return row.isPassiveSkillTrait ~= true
    end, function(row)
        return row.isBaseline == true
    end)
    refreshDebugBulkTickState(panel.baselineRecipeBulkTick, panel.baselineRecipeList, nil, function(row)
        return row.isBaseline == true
    end)
end

function BurdJournals.UI.DebugPanel.onBaselineTraitBulkToggle(self, _index, selected)
    local panel = self and self.baselinePanel or nil
    if not (panel and panel.baselineTraitList) then
        return
    end
    if panel.baselineEnabled == false then
        self:setStatus("Baseline editing is disabled in this sandbox.", {r=1, g=0.6, b=0.3})
        BurdJournals.UI.DebugPanel.refreshBaselineBulkToggles(self)
        return
    end

    panel.baselineDraftTraits = panel.baselineDraftTraits or {}
    local count = 0
    for _, itemData in ipairs(panel.baselineTraitList.items or {}) do
        local row = itemData and itemData.item or nil
        if row and row.id and row.isPassiveSkillTrait ~= true and (selected == true and isDebugVisibleBulkRow(row) or selected ~= true) then
            local newStatus = selected == true
            if row.isBaseline ~= newStatus then
                row.isBaseline = newStatus
                panel.baselineDraftTraits[row.id] = newStatus
                count = count + 1
            end
        end
    end

    BurdJournals.UI.DebugPanel.refreshBaselineBulkToggles(self)
    if self.markBaselineDraftDirty then
        local actionText = selected == true and "added to" or "removed from"
        self:markBaselineDraftDirty("Draft: " .. tostring(count) .. " trait(s) " .. actionText .. " baseline. Save to apply.")
    end
end

function BurdJournals.UI.DebugPanel.onBaselineRecipeBulkToggle(self, _index, selected)
    local panel = self and self.baselinePanel or nil
    if not (panel and panel.baselineRecipeList) then
        return
    end
    if panel.baselineEnabled == false then
        self:setStatus("Baseline editing is disabled in this sandbox.", {r=1, g=0.6, b=0.3})
        BurdJournals.UI.DebugPanel.refreshBaselineBulkToggles(self)
        return
    end

    panel.baselineDraftRecipes = panel.baselineDraftRecipes or {}
    local count = 0
    for _, itemData in ipairs(panel.baselineRecipeList.items or {}) do
        local row = itemData and itemData.item or nil
        if row and row.name and (selected == true and isDebugVisibleBulkRow(row) or selected ~= true) then
            local newStatus = selected == true
            if row.isBaseline ~= newStatus then
                row.isBaseline = newStatus
                local recipeName = BurdJournals.getRecipeCanonicalName and BurdJournals.getRecipeCanonicalName(row.name) or row.name
                panel.baselineDraftRecipes[tostring(recipeName)] = newStatus
                count = count + 1
            end
        end
    end

    BurdJournals.UI.DebugPanel.refreshBaselineBulkToggles(self)
    if self.markBaselineDraftDirty then
        local actionText = selected == true and "added to" or "removed from"
        self:markBaselineDraftDirty("Draft: " .. tostring(count) .. " recipe(s) " .. actionText .. " baseline. Save to apply.")
    end
end

-- Draw function for baseline skill items with interactive squares
function BurdJournals.UI.DebugPanel.drawBaselineSkillItem(self, y, item, alt)
    local h = getDebugListRowHeight(self, item, self.itemheight or 24)
    local data = item.item
    
    -- Skip hidden items (filtered by search)
    if data.hidden then return y + h end
    
    local parentPanel = self.parentPanel
    local baselinePanel = parentPanel and parentPanel.baselinePanel
    
    -- Background
    if data.isPassive then
        self:drawRect(0, y, self.width, h, 0.15, 0.25, 0.2, 0.25)
    elseif self.mouseoverselected == item.index then
        self:drawRect(0, y, self.width, h, 0.2, 0.2, 0.3, 0.3)
    end
    
    -- Skill name
    local textX = 8
    local nameColor = data.isPassive and {0.7, 0.9, 0.8} or {0.9, 0.9, 0.9}
    self:drawText(data.displayName, textX, y + 4, nameColor[1], nameColor[2], nameColor[3], 1, UIFont.Small)
    
    -- Current level indicator
    local currentText = BurdJournals.formatText(getText("UI_BurdJournals_LevelFormat"), tonumber(data.currentLevel) or 0)
    self:drawText(currentText, 130, y + 4, 0.5, 0.7, 0.9, 1, UIFont.Small)
    
    -- Interactive squares for baseline (10 squares) with progress visualization
    local squaresX = 175
    local squareSize = 14
    local squareSpacing = 2
    
    -- Calculate progress within current level (0-1) for baseline
    -- Use our verified threshold tables for consistent values
    local baselineProgress = 0
    local baselineLevel = data.baselineLevel or 0
    local baselineXP = data.baselineXP or 0
    local isPassive = data.isPassive or (data.name == "Fitness" or data.name == "Strength")
    local thresholds = isPassive and BurdJournals.PASSIVE_XP_THRESHOLDS or BurdJournals.STANDARD_XP_THRESHOLDS
    
    if baselineLevel < 10 and thresholds then
        local levelStartXP = thresholds[baselineLevel] or 0
        local levelEndXP = thresholds[baselineLevel + 1] or (levelStartXP + 150)
        local xpRange = levelEndXP - levelStartXP
        if xpRange > 0 then
            baselineProgress = math.max(0, math.min(1, (baselineXP - levelStartXP) / xpRange))
        end
    end
    
    -- Calculate progress for current (earned) level
    local currentProgress = 0
    local currentLevel = data.currentLevel or 0
    local currentXP = data.currentXP or 0
    
    if currentLevel < 10 and thresholds then
        local levelStartXP = thresholds[currentLevel] or 0
        local levelEndXP = thresholds[currentLevel + 1] or (levelStartXP + 150)
        local xpRange = levelEndXP - levelStartXP
        if xpRange > 0 then
            currentProgress = math.max(0, math.min(1, (currentXP - levelStartXP) / xpRange))
        end
    end
    
    for lvl = 1, 10 do
        local sqX = squaresX + (lvl - 1) * (squareSize + squareSpacing)
        local sqY = y + (h - squareSize) / 2
        
        -- Determine square color based on level relationships
        if lvl <= baselineLevel then
            -- Baseline level (filled, darker tone)
            self:drawRect(sqX, sqY, squareSize, squareSize, 0.9, 0.4, 0.3, 0.25)
        elseif lvl == baselineLevel + 1 and baselineProgress > 0 and lvl > currentLevel then
            -- Baseline has partial progress in this square but no earned XP beyond it
            self:drawRect(sqX, sqY, squareSize, squareSize, 0.5, 0.1, 0.1, 0.12)
            local fillHeight = squareSize * baselineProgress
            self:drawRect(sqX, sqY + squareSize - fillHeight, squareSize, fillHeight, 0.6, 0.35, 0.28, 0.22)
        elseif lvl == baselineLevel + 1 and lvl <= currentLevel then
            -- Transition square: baseline progress + earned portion
            if baselineProgress > 0 then
                local baselineFillHeight = squareSize * baselineProgress
                self:drawRect(sqX, sqY + squareSize - baselineFillHeight, squareSize, baselineFillHeight, 0.6, 0.35, 0.28, 0.22)
            end
            local earnedPortion = 1.0 - baselineProgress
            if earnedPortion > 0 then
                local earnedFillHeight = squareSize * earnedPortion
                self:drawRect(sqX, sqY, squareSize, earnedFillHeight, 0.9, 0.3, 0.6, 0.5)
            end
        elseif lvl <= currentLevel then
            -- Earned level beyond baseline (bright)
            self:drawRect(sqX, sqY, squareSize, squareSize, 0.9, 0.3, 0.6, 0.5)
        elseif lvl == currentLevel + 1 and currentProgress > 0 then
            -- Partial progress on current earned level
            self:drawRect(sqX, sqY, squareSize, squareSize, 0.5, 0.1, 0.1, 0.12)
            local fillHeight = squareSize * currentProgress
            self:drawRect(sqX, sqY + squareSize - fillHeight, squareSize, fillHeight, 0.8, 0.2, 0.4, 0.35)
        else
            -- Empty (not reached)
            self:drawRect(sqX, sqY, squareSize, squareSize, 0.5, 0.1, 0.1, 0.12)
        end
        
        -- Border - highlight baseline square
        if lvl == baselineLevel and baselineLevel > 0 then
            self:drawRectBorder(sqX, sqY, squareSize, squareSize, 0.9, 0.9, 0.7, 0.4)
        else
            self:drawRectBorder(sqX, sqY, squareSize, squareSize, 0.4, 0.3, 0.35, 0.4)
        end
    end
    
    -- XP display (simple text after squares)
    local squaresEndX = squaresX + 10 * (squareSize + squareSpacing)
    local xpDisplayX = squaresEndX + 8
    local baselineXP = data.baselineXP or 0
    
    -- Format XP display
    local xpText = tostring(math.floor(baselineXP)) .. " XP"
    self:drawText(xpText, xpDisplayX, y + 4, 0.6, 0.5, 0.4, 1, UIFont.Small)
    
    return y + h
end

-- Click handler for baseline skill list (detects square clicks)
function BurdJournals.UI.DebugPanel.onBaselineSkillListClick(self, x, y)
    local row = BurdJournals.UI.DebugPanel.safeListMouseDown(self, x, y)
    if row <= 0 or row > #self.items then return end
    
    local item = self.items[row]
    local data = item.item
    local parentPanel = self.parentPanel
    local baselinePanel = parentPanel and parentPanel.baselinePanel
    local targetPlayer = baselinePanel and baselinePanel.targetPlayer or parentPanel.player
    
    -- Check if click is in the squares area
    local squaresX = 175
    local squareSize = 14
    local squareSpacing = 2
    local squaresEndX = squaresX + 10 * (squareSize + squareSpacing)
    
    if x >= squaresX and x < squaresEndX then
        -- Calculate which square was clicked
        local relX = x - squaresX
        local clickedLevel = math.floor(relX / (squareSize + squareSpacing)) + 1
        clickedLevel = math.max(0, math.min(10, clickedLevel))
        
        -- Handle click on same level = set to 0 (toggle off)
        if clickedLevel == data.baselineLevel then
            clickedLevel = 0
        end
        
        data.baselineLevel = clickedLevel

        local baselineXP = 0
        if clickedLevel > 0 then
            local isPassive = (data.name == "Fitness" or data.name == "Strength")
            if isPassive then
                baselineXP = BurdJournals.PASSIVE_XP_THRESHOLDS and BurdJournals.PASSIVE_XP_THRESHOLDS[clickedLevel] or 0
            else
                baselineXP = BurdJournals.STANDARD_XP_THRESHOLDS and BurdJournals.STANDARD_XP_THRESHOLDS[clickedLevel] or 0
            end
        end
        data.baselineXP = baselineXP

        if baselinePanel then
            baselinePanel.baselineDraftSkills = baselinePanel.baselineDraftSkills or {}
            baselinePanel.baselineDraftSkills[data.name] = baselineXP
        end
        if parentPanel.markBaselineDraftDirty then
            parentPanel:markBaselineDraftDirty("Draft: " .. data.displayName .. " baseline set to level " .. clickedLevel .. ". Save to apply.")
        end
    end
end

-- Draw function for baseline trait items with checkbox
function BurdJournals.UI.DebugPanel.drawBaselineTraitItem(self, y, item, alt)
    local h = getDebugListRowHeight(self, item, self.itemheight or 22)
    local data = item.item
    
    -- Skip hidden items (filtered by search)
    if data.hidden then return y + h end
    
    -- Background for passive skill traits (can't be toggled)
    if data.isPassiveSkillTrait then
        self:drawRect(0, y, self.width, h, 0.15, 0.2, 0.15, 0.15)
    elseif self.mouseoverselected == item.index then
        self:drawRect(0, y, self.width, h, 0.2, 0.2, 0.3, 0.3)
    end
    
    local checkX = 8
    local parentPanel = self.parentPanel
    local baselinePanel = parentPanel and parentPanel.baselinePanel
    local isReadOnly = baselinePanel and baselinePanel.baselineEnabled == false
    if data.isPassiveSkillTrait then
        self:drawText("[~]", checkX, y + 2, 0.4, 0.4, 0.4, 1, UIFont.Small)
    elseif data.isBaseline then
        self:drawText("[X]", checkX, y + 2, 0.4, 0.7, 0.4, 1, UIFont.Small)
    else
        self:drawText("[ ]", checkX, y + 2, 0.5, 0.5, 0.5, 1, UIFont.Small)
    end

    local iconSize = drawDebugListIcon(self, data.traitTexture or getDebugTraitTexture(data.id), 28, y, h, 0.95, 13)
    local textX = 28 + math.max(iconSize, 13) + 6
    local nameColor = BurdJournals.UI.DebugPanel.getTraitPolarityColor(data)
    if data.isBaseline then
        nameColor = {0.8, 1, 0.8}
    end
    self:drawText(BurdJournals.UI.DebugPanel.getTraitPolarityPrefix(data) .. " " .. tostring(data.displayName or data.id or "Unknown"), textX, y + 2, nameColor[1], nameColor[2], nameColor[3], 1, UIFont.Small)
    
    -- Status indicator (account for scrollbar)
    local scrollOffset = BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH
    if data.isPassiveSkillTrait then
        self:drawText("(auto)", self.width - 50 - scrollOffset, y + 2, 0.4, 0.4, 0.4, 1, UIFont.Small)
    elseif data.isBaseline then
        self:drawText("Starting", self.width - 55 - scrollOffset, y + 2, 0.5, 0.65, 0.5, 1, UIFont.Small)
    elseif data.hasTrait then
        self:drawText(isReadOnly and "Current" or "Owned", self.width - 55 - scrollOffset, y + 2, 0.55, 0.65, 0.82, 1, UIFont.Small)
    else
        self:drawText(BurdJournals.UI.DebugPanel.getTraitPolarityText(data), self.width - 62 - scrollOffset, y + 2, nameColor[1], nameColor[2], nameColor[3], 0.95, UIFont.Small)
    end
    
    return y + h
end

-- Click handler for baseline trait list
function BurdJournals.UI.DebugPanel.onBaselineTraitListClick(self, x, y)
    local row = BurdJournals.UI.DebugPanel.safeListMouseDown(self, x, y)
    if row <= 0 or row > #self.items then return end
    
    local item = self.items[row]
    local data = item.item
    local parentPanel = self.parentPanel
    local baselinePanel = parentPanel and parentPanel.baselinePanel
    local targetPlayer = baselinePanel and baselinePanel.targetPlayer or parentPanel.player
    
    -- Don't allow toggling passive skill traits
    if data.isPassiveSkillTrait then
        parentPanel:setStatus("Passive skill traits cannot be modified", {r=1, g=0.6, b=0.3})
        return
    end
    if baselinePanel and baselinePanel.baselineEnabled == false then
        parentPanel:setStatus("Baseline editing is disabled in this sandbox.", {r=1, g=0.6, b=0.3})
        return
    end
    
    -- Toggle baseline status
    local newStatus = not data.isBaseline
    
    data.isBaseline = newStatus
    if baselinePanel then
        baselinePanel.baselineDraftTraits = baselinePanel.baselineDraftTraits or {}
        baselinePanel.baselineDraftTraits[data.id] = newStatus == true
    end
    if parentPanel.markBaselineDraftDirty then
        local statusText = newStatus and "added to" or "removed from"
        parentPanel:markBaselineDraftDirty("Draft: " .. data.displayName .. " " .. statusText .. " baseline. Save to apply.")
    end
    BurdJournals.UI.DebugPanel.refreshBaselineBulkToggles(parentPanel)
end

function BurdJournals.UI.DebugPanel.drawBaselineRecipeItem(self, y, item, alt)
    local h = getDebugListRowHeight(self, item, 30)
    if not item or not item.item then return y + h end
    local data = item.item
    if not data or data.hidden then return y + h end

    local w = self.width or 300
    local scrollOffset = BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH
    local parentPanel = self.parentPanel
    local baselinePanel = parentPanel and parentPanel.baselinePanel
    local isReadOnly = baselinePanel and baselinePanel.baselineEnabled == false

    if data.isBaseline then
        self:drawRect(0, y, w, h, 0.12, 0.2, 0.12, 0.28)
    elseif self.mouseoverselected == item.index then
        self:drawRect(0, y, w, h, 0.2, 0.2, 0.3, 0.3)
    end

    if data.isBaseline then
        self:drawText("[X]", 8, y + 2, 0.4, 0.7, 0.4, 1, UIFont.Small)
    else
        self:drawText("[ ]", 8, y + 2, 0.5, 0.5, 0.5, 1, UIFont.Small)
    end

    local iconX = 28
    local recipeIcon = data.recipeTexture or getDebugRecipeTexture()
    local recipeSize = drawDebugListIcon(self, recipeIcon, iconX, y, h, 0.95, 13)
    local textX = iconX + math.max(recipeSize, 13) + 6
    if data.magazineSource then
        local magSize = drawDebugListIcon(self, data.magazineTexture or getDebugMagazineTexture(data.magazineSource), textX, y, h, 0.9, 13)
        if magSize > 0 then
            textX = textX + magSize + 6
        end
    end

    self:drawText(tostring(data.displayName or data.name or "Unknown Recipe"), textX, y + 2, data.isBaseline and 0.82 or 0.74, data.isBaseline and 1 or 0.74, data.isBaseline and 0.82 or 0.74, 1, UIFont.Small)
    local sourceText = getDebugRecipeSourceText(data, 22)
    local sourceColor = data.magazineDisplayName and {0.5, 0.7, 0.75}
        or ((data.source and data.source ~= "Vanilla" and data.source ~= "Runtime" and data.source ~= "Unknown")
            and {0.82, 0.72, 0.5}
            or {0.55, 0.65, 0.78})
    self:drawText(sourceText, textX, y + 15, sourceColor[1], sourceColor[2], sourceColor[3], 0.9, UIFont.Small)
    local rightText = data.isBaseline and "Starting" or (data.isKnown and (isReadOnly and "Current" or "Known") or "")
    if rightText ~= "" then
        self:drawText(rightText, w - 56 - scrollOffset, y + 2, 0.55, 0.68, 0.82, 1, UIFont.Small)
    end
    return y + h
end

function BurdJournals.UI.DebugPanel.onBaselineRecipeListClick(self, x, y)
    local row = BurdJournals.UI.DebugPanel.safeListMouseDown(self, x, y)
    if row <= 0 or row > #self.items then return end

    local item = self.items[row]
    local data = item and item.item or nil
    local parentPanel = self.parentPanel
    local baselinePanel = parentPanel and parentPanel.baselinePanel
    if not (data and parentPanel and baselinePanel) then return end
    if baselinePanel.baselineEnabled == false then
        parentPanel:setStatus("Baseline editing is disabled in this sandbox.", {r=1, g=0.6, b=0.3})
        return
    end

    data.isBaseline = not data.isBaseline
    baselinePanel.baselineDraftRecipes = baselinePanel.baselineDraftRecipes or {}
    local recipeName = BurdJournals.getRecipeCanonicalName and BurdJournals.getRecipeCanonicalName(data.name) or data.name
    baselinePanel.baselineDraftRecipes[tostring(recipeName)] = data.isBaseline == true
    local statusText = data.isBaseline and "added to" or "removed from"
    if parentPanel.markBaselineDraftDirty then
        parentPanel:markBaselineDraftDirty("Draft: " .. tostring(data.displayName or data.name) .. " " .. statusText .. " baseline recipes. Save to apply.")
    end
    BurdJournals.UI.DebugPanel.refreshBaselineBulkToggles(parentPanel)
end

function BurdJournals.UI.DebugPanel.onBaselineSnapshotFilterChanged(self)
    if self and self.requestBaselineSnapshots then
        self:requestBaselineSnapshots()
    end
    if self and self.requestSnapshotLiveBaselinePayload then
        self:requestSnapshotLiveBaselinePayload()
    end
end

local function snapshotFormatEpochMsForUI(epochMs)
    local ms = tonumber(epochMs)
    if not ms or ms <= 0 or not (os and os.date) then
        return nil
    end
    local ok, value = pcall(os.date, "%Y-%m-%d %H:%M:%S", math.floor(ms / 1000))
    if ok and value and value ~= "" then
        return tostring(value)
    end
    return nil
end

local function snapshotGetRealStamp(snapshot, prefix)
    local key = tostring(prefix or "captured")
    local localField = tostring(key .. "AtLocal")
    local isoField = tostring(key .. "AtIsoUtc")
    local epochField = tostring(key .. "AtEpochMs")
    local localStamp = snapshot and snapshot[localField] or nil
    if localStamp and tostring(localStamp) ~= "" then
        return tostring(localStamp)
    end
    local isoStamp = snapshot and snapshot[isoField] or nil
    if isoStamp and tostring(isoStamp) ~= "" then
        return tostring(isoStamp)
    end
    return snapshotFormatEpochMsForUI(snapshot and snapshot[epochField] or nil)
end

local function formatSnapshotSummaryLine(snapshot)
    local counts = snapshot and snapshot.counts or {}
    local skills = tonumber(counts and counts.skills) or 0
    local media = tonumber(counts and counts.mediaSkills) or 0
    local traits = tonumber(counts and counts.traits) or 0
    local recipes = tonumber(counts and counts.recipes) or 0
    local source = tostring(snapshot and snapshot.source or "?")
    local who = tostring(snapshot and (snapshot.characterName or snapshot.username or snapshot.characterId) or "Unknown")
    local captured = tonumber(snapshot and snapshot.capturedAtHours) or 0
    local stamp = BurdJournals.formatText("%.1fh", captured)
    local realStamp = snapshotGetRealStamp(snapshot, "captured")
    if snapshot and snapshot.endedReason and snapshot.endedReason ~= "" then
        source = source .. "/" .. tostring(snapshot.endedReason)
    end
    if realStamp and realStamp ~= "" then
        return BurdJournals.formatText("[%s] %s @ %s | RL %s (%dS %dM %dT %dR)", source, who, stamp, realStamp, skills, media, traits, recipes)
    end
    return BurdJournals.formatText("[%s] %s @ %s (%dS %dM %dT %dR)", source, who, stamp, skills, media, traits, recipes)
end

local function trimSnapshotText(text, maxChars)
    local value = tostring(text or "")
    local limit = math.max(8, tonumber(maxChars) or 64)
    if #value <= limit then
        return value
    end
    return string.sub(value, 1, limit - 3) .. "..."
end

local function getSnapshotPanel(self)
    if self and self.snapshotPanel and self.snapshotPanel.snapshotList then
        return self.snapshotPanel
    end
    if self and self.baselinePanel and self.baselinePanel.snapshotList then
        return self.baselinePanel
    end
    return nil
end

function BurdJournals.UI.DebugPanel:populateSnapshotPlayerList()
    local panel = getSnapshotPanel(self)
    if not panel or not panel.snapshotTargetCombo then
        return
    end

    local selectedPlayer = panel.targetPlayer or self:getSharedTargetPlayer() or self.player
    local selectedName = getDebugTargetPlayerName(selectedPlayer)
    panel.snapshotTargetCombo:clear()
    local targetablePlayers = collectDebugTargetablePlayers(self)
    for _, playerObj in ipairs(targetablePlayers) do
        panel.snapshotTargetCombo:addOptionWithData(getDebugTargetPlayerName(playerObj), playerObj)
    end

    if selectedName and selectedName ~= "" then
        panel.snapshotTargetCombo:select(selectedName)
    else
        panel.snapshotTargetCombo:select(getDebugTargetPlayerName(self.player))
    end
    panel.targetPlayer = selectedPlayer
end

function BurdJournals.UI.DebugPanel:onSnapshotTargetPlayerChange(combo)
    if self.suppressTargetSync then
        return
    end

    local panel = getSnapshotPanel(self)
    if not panel then
        return
    end

    local selectedPlayer = getDebugComboSelectedData(combo)
    if selectedPlayer then
        self:applySharedTargetPlayer(selectedPlayer, {
            statusText = BurdJournals.formatText(getText("UI_BurdJournals_DebugViewingSnapshots"), getDebugTargetPlayerName(selectedPlayer)),
        })
    end
end

function BurdJournals.UI.DebugPanel:refreshSnapshotPanelData()
    local panel = getSnapshotPanel(self)
    if not panel then
        return
    end
    if not panel.targetPlayer then
        panel.targetPlayer = self.player
    end
    if self.requestBaselineSnapshots then
        self:requestBaselineSnapshots()
    end
    if self.requestSnapshotLiveBaselinePayload then
        self:requestSnapshotLiveBaselinePayload()
    end
end

function BurdJournals.UI.DebugPanel.drawBaselineSnapshotItem(self, y, item, alt)
    local h = self.itemheight
    local data = item.item
    if not data then
        return y + h
    end

    local isSelected = self.selected == item.index
    if isSelected then
        self:drawRect(0, y, self.width, h, 0.38, 0.28, 0.5, 0.34)
        self:drawRectBorder(0, y, self.width, h, 0.75, 0.62, 0.9, 0.6)
    elseif self.mouseoverselected == item.index then
        self:drawRect(0, y, self.width, h, 0.25, 0.22, 0.3, 0.38)
    elseif item.index % 2 == 0 then
        self:drawRect(0, y, self.width, h, 0.08, 0.08, 0.1, 0.35)
    end

    local source = tostring(data.source or "?")
    local who = tostring(data.characterName or data.username or data.characterId or "Unknown")
    local captured = tonumber(data.capturedAtHours) or 0
    local counts = data.counts or {}
    local mode = data.isProtected and "protected" or "unlocked"
    local ended = data.endedReason and (" | ended:" .. tostring(data.endedReason)) or ""
    local realStamp = snapshotGetRealStamp(data, "captured")
    local line1 = BurdJournals.formatText("[%s] %s @ %.1fh", source, who, captured)
    local line2 = BurdJournals.formatText(
        "%dS %dM %dT %dR | %s%s",
        tonumber(counts.skills) or 0,
        tonumber(counts.mediaSkills) or 0,
        tonumber(counts.traits) or 0,
        tonumber(counts.recipes) or 0,
        mode,
        ended
    )
    if realStamp and realStamp ~= "" then
        line2 = line2 .. " | RL " .. tostring(realStamp)
    end
    local charsPerLine = math.max(34, math.floor((self.width - 14) / 6))
    self:drawText(trimSnapshotText(line1, charsPerLine), 6, y + 3, 0.92, 0.92, 0.97, 1, UIFont.Small)
    self:drawText(trimSnapshotText(line2, charsPerLine + 6), 6, y + 18, 0.72, 0.8, 0.92, 1, UIFont.Small)
    return y + h
end

function BurdJournals.UI.DebugPanel.onBaselineSnapshotListClick(self, x, y)
    BurdJournals.UI.DebugPanel.safeListMouseDown(self, x, y)
    local parentPanel = self.parentPanel
    if not parentPanel then
        return
    end
    local panel = getSnapshotPanel(parentPanel)
    if not panel then
        return
    end
    local selected = self.items and self.items[self.selected]
    local selectedData = selected and selected.item or nil
    if not selectedData then
        return
    end
    panel.snapshotSelectedId = selectedData.snapshotId
    panel.snapshotSelectedData = selectedData
    if parentPanel.refreshBaselineSnapshotDetail then
        parentPanel:refreshBaselineSnapshotDetail()
    end
    if BurdJournals.Client and BurdJournals.Client.Debug and BurdJournals.Client.Debug.getBaselineSnapshot then
        BurdJournals.Client.Debug.getBaselineSnapshot(selectedData.snapshotId, parentPanel.player)
    end
    if parentPanel.requestSnapshotLiveBaselinePayload then
        parentPanel:requestSnapshotLiveBaselinePayload()
    end
end

function BurdJournals.UI.DebugPanel:getBaselineSnapshotFilterPayload()
    local panel = getSnapshotPanel(self)
    if not panel then
        return nil
    end
    local payload = {
        includeDead = true,
        page = panel.snapshotCurrentPage or 1,
        pageSize = panel.snapshotPageSize or 20,
    }

    local query = panel.snapshotSearch and panel.snapshotSearch.getText and panel.snapshotSearch:getText() or ""
    if query and query ~= "" then
        payload.query = query
    end

    local filterMode = "target"
    if panel.snapshotFilterCombo and panel.snapshotFilterCombo.options and panel.snapshotFilterCombo.selected > 0 then
        local option = panel.snapshotFilterCombo.options[panel.snapshotFilterCombo.selected]
        if option and option.data then
            filterMode = tostring(option.data)
        end
    end

    local targetPlayer = panel.targetPlayer or self.player
    if filterMode == "steam" then
        local steamId = targetPlayer and BurdJournals.getPlayerSteamId and BurdJournals.getPlayerSteamId(targetPlayer) or nil
        if steamId and steamId ~= "" then
            payload.steamId = tostring(steamId)
        else
            payload.targetUsername = targetPlayer and targetPlayer.getUsername and targetPlayer:getUsername() or nil
        end
    elseif filterMode == "character" then
        payload.useTargetCharacterId = true
        local characterId = targetPlayer and BurdJournals.getPlayerCharacterId and BurdJournals.getPlayerCharacterId(targetPlayer) or nil
        if characterId and characterId ~= "" then
            payload.characterId = tostring(characterId)
        else
            payload.targetUsername = targetPlayer and targetPlayer.getUsername and targetPlayer:getUsername() or nil
        end
    else
        local steamId = targetPlayer and BurdJournals.getPlayerSteamId and BurdJournals.getPlayerSteamId(targetPlayer) or nil
        if steamId and steamId ~= "" then
            payload.steamId = tostring(steamId)
        else
            payload.targetUsername = targetPlayer and targetPlayer.getUsername and targetPlayer:getUsername() or nil
        end
    end
    return payload
end

function BurdJournals.UI.DebugPanel:requestBaselineSnapshots()
    local payload = self:getBaselineSnapshotFilterPayload()
    if not payload then
        return
    end
    if BurdJournals.Client and BurdJournals.Client.Debug and BurdJournals.Client.Debug.listBaselineSnapshots then
        BurdJournals.Client.Debug.listBaselineSnapshots(payload, self.player)
    elseif sendClientCommand then
        sendClientCommand("BurdJournals", "debugListBaselineSnapshots", payload)
    end
end

function BurdJournals.UI.DebugPanel:requestSnapshotLiveBaselinePayload()
    local panel = getSnapshotPanel(self)
    if not panel then
        return
    end
    local targetPlayer = panel.targetPlayer or self.player
    local targetUsername = targetPlayer and targetPlayer.getUsername and targetPlayer:getUsername() or nil
    if BurdJournals.Client and BurdJournals.Client.Debug and BurdJournals.Client.Debug.getTargetBaselinePayload then
        BurdJournals.Client.Debug.getTargetBaselinePayload({
            targetUsername = targetUsername
        }, self.player)
    elseif sendClientCommand then
        sendClientCommand("BurdJournals", "debugGetTargetBaselinePayload", {
            targetUsername = targetUsername
        })
    end
end

local function snapshotGetSkillDisplayName(skillName)
    if BurdJournals and BurdJournals.getSkillDisplayName then
        local displayName = BurdJournals.getSkillDisplayName(skillName)
        if displayName and displayName ~= "" then
            return displayName
        end
    end
    return tostring(skillName or "Unknown")
end

local function snapshotGetThresholds(skillName)
    local isPassive = skillName == "Fitness" or skillName == "Strength"
    return isPassive and BurdJournals.PASSIVE_XP_THRESHOLDS or BurdJournals.STANDARD_XP_THRESHOLDS
end

local function snapshotLevelProgressFromXP(skillName, xp)
    local value = math.max(0, tonumber(xp) or 0)
    local thresholds = snapshotGetThresholds(skillName) or {}
    local level = 0
    for l = 10, 1, -1 do
        local threshold = tonumber(thresholds[l]) or 0
        if value >= threshold then
            level = l
            break
        end
    end
    local progress = 0
    if level < 10 then
        local levelStart = tonumber(thresholds[level]) or 0
        local levelEnd = tonumber(thresholds[level + 1]) or (levelStart + 150)
        local range = levelEnd - levelStart
        if range > 0 then
            progress = math.max(0, math.min(1, (value - levelStart) / range))
        end
    end
    return level, progress
end

local function snapshotBuildBooleanDiffRows(liveData, snapshotData, labelFn)
    local rows = {}
    local seen = {}
    local keys = {}

    liveData = type(liveData) == "table" and liveData or {}
    snapshotData = type(snapshotData) == "table" and snapshotData or {}

    for key, value in pairs(liveData) do
        if value == true then
            local id = tostring(key)
            if not seen[id] then
                seen[id] = true
                keys[#keys + 1] = id
            end
        end
    end
    for key, value in pairs(snapshotData) do
        if value == true then
            local id = tostring(key)
            if not seen[id] then
                seen[id] = true
                keys[#keys + 1] = id
            end
        end
    end

    table.sort(keys)
    for _, key in ipairs(keys) do
        local inLive = liveData[key] == true
        local inSnapshot = snapshotData[key] == true
        if inSnapshot and (not inLive) then
            rows[#rows + 1] = {kind = "added", text = (labelFn and labelFn(key) or key)}
        elseif inLive and (not inSnapshot) then
            rows[#rows + 1] = {kind = "removed", text = (labelFn and labelFn(key) or key)}
        end
    end
    return rows
end

local function snapshotBuildMediaDiffRows(liveData, snapshotData, labelFn)
    local rows = {}
    local seen = {}
    local keys = {}

    liveData = type(liveData) == "table" and liveData or {}
    snapshotData = type(snapshotData) == "table" and snapshotData or {}

    for key in pairs(liveData) do
        local id = tostring(key)
        if not seen[id] then
            seen[id] = true
            keys[#keys + 1] = id
        end
    end
    for key in pairs(snapshotData) do
        local id = tostring(key)
        if not seen[id] then
            seen[id] = true
            keys[#keys + 1] = id
        end
    end

    table.sort(keys)
    for _, key in ipairs(keys) do
        local liveXP = tonumber(liveData[key]) or 0
        local newXP = tonumber(snapshotData[key]) or 0
        local hasLive = liveData[key] ~= nil and liveXP > 0
        local hasNew = snapshotData[key] ~= nil and newXP > 0
        local label = (labelFn and labelFn(key) or key)
        if hasNew and (not hasLive) then
            rows[#rows + 1] = {kind = "added", text = BurdJournals.formatText("%s (+%d XP)", label, newXP)}
        elseif hasLive and (not hasNew) then
            rows[#rows + 1] = {kind = "removed", text = BurdJournals.formatText("%s (-%d XP)", label, liveXP)}
        elseif hasLive and hasNew and liveXP ~= newXP then
            local delta = newXP - liveXP
            rows[#rows + 1] = {kind = "changed", text = BurdJournals.formatText("%s (%+d XP)", label, delta)}
        end
    end
    return rows
end

local function snapshotBuildSkillRows(liveSkills, snapshotSkills)
    local rows = {}
    local keys = {}
    local seen = {}

    liveSkills = type(liveSkills) == "table" and liveSkills or {}
    snapshotSkills = type(snapshotSkills) == "table" and snapshotSkills or {}

    for key in pairs(liveSkills) do
        local id = tostring(key)
        if not seen[id] then
            seen[id] = true
            keys[#keys + 1] = id
        end
    end
    for key in pairs(snapshotSkills) do
        local id = tostring(key)
        if not seen[id] then
            seen[id] = true
            keys[#keys + 1] = id
        end
    end

    table.sort(keys, function(a, b)
        return snapshotGetSkillDisplayName(a) < snapshotGetSkillDisplayName(b)
    end)

    for _, skillName in ipairs(keys) do
        local liveXP = tonumber(liveSkills[skillName]) or 0
        local newXP = tonumber(snapshotSkills[skillName]) or 0
        local liveLevel, liveProgress = snapshotLevelProgressFromXP(skillName, liveXP)
        local newLevel, newProgress = snapshotLevelProgressFromXP(skillName, newXP)
        rows[#rows + 1] = {
            name = skillName,
            displayName = snapshotGetSkillDisplayName(skillName),
            isPassive = (skillName == "Fitness" or skillName == "Strength"),
            liveXP = liveXP,
            snapshotXP = newXP,
            liveLevel = liveLevel,
            snapshotLevel = newLevel,
            liveProgress = liveProgress,
            snapshotProgress = newProgress,
            deltaXP = newXP - liveXP,
            deltaLevel = newLevel - liveLevel,
        }
    end
    return rows
end

function BurdJournals.UI.DebugPanel:refreshBaselineSnapshotPreview()
    local panel = getSnapshotPanel(self)
    if not panel then
        return
    end

    local snapshot = panel.snapshotSelectedData
    local livePayload = panel.snapshotLiveBaselinePayload or {}
    local snapshotPayload = snapshot or {}

    local liveSkills = type(livePayload.skillBaseline) == "table" and livePayload.skillBaseline or {}
    local newSkills = type(snapshotPayload.skillBaseline) == "table" and snapshotPayload.skillBaseline or {}
    local liveTraits = type(livePayload.traitBaseline) == "table" and livePayload.traitBaseline or {}
    local newTraits = type(snapshotPayload.traitBaseline) == "table" and snapshotPayload.traitBaseline or {}
    local liveRecipes = type(livePayload.recipeBaseline) == "table" and livePayload.recipeBaseline or {}
    local newRecipes = type(snapshotPayload.recipeBaseline) == "table" and snapshotPayload.recipeBaseline or {}
    local liveMedia = type(livePayload.mediaSkillBaseline) == "table" and livePayload.mediaSkillBaseline or {}
    local newMedia = type(snapshotPayload.mediaSkillBaseline) == "table" and snapshotPayload.mediaSkillBaseline or {}

    panel.snapshotPreviewRows = snapshotBuildSkillRows(liveSkills, newSkills)
    panel.snapshotTraitDiffRows = snapshotBuildBooleanDiffRows(liveTraits, newTraits, function(id) return BurdJournals.getTraitDisplayName and BurdJournals.getTraitDisplayName(id) or id end)
    panel.snapshotRecipeDiffRows = snapshotBuildBooleanDiffRows(liveRecipes, newRecipes, function(id) return id end)
    panel.snapshotMediaDiffRows = snapshotBuildMediaDiffRows(liveMedia, newMedia, snapshotGetSkillDisplayName)

    if panel.snapshotSkillPreviewList then
        panel.snapshotSkillPreviewList:clear()
        if #panel.snapshotPreviewRows == 0 then
            panel.snapshotSkillPreviewList:addItem(getText("UI_BurdJournals_SnapshotPreviewNoSkills") or "No skill baseline differences.", {isHeader = true, text = getText("UI_BurdJournals_SnapshotPreviewNoSkills") or "No skill baseline differences."})
        else
            for _, row in ipairs(panel.snapshotPreviewRows) do
                panel.snapshotSkillPreviewList:addItem(row.displayName, row)
            end
        end
    end

    if panel.snapshotTraitDiffList then
        panel.snapshotTraitDiffList:clear()
        panel.snapshotTraitDiffList:addItem(getText("UI_BurdJournals_SnapshotPreviewTraitsTitle") or "Traits", {isHeader = true, text = getText("UI_BurdJournals_SnapshotPreviewTraitsTitle") or "Traits"})
        if #panel.snapshotTraitDiffRows == 0 then
            panel.snapshotTraitDiffList:addItem(getText("UI_BurdJournals_SnapshotPreviewNoTraitDiff") or "No trait changes", {kind = "neutral", text = getText("UI_BurdJournals_SnapshotPreviewNoTraitDiff") or "No trait changes"})
        else
            for _, row in ipairs(panel.snapshotTraitDiffRows) do
                panel.snapshotTraitDiffList:addItem(row.text, row)
            end
        end
    end

    if panel.snapshotRecipeDiffList then
        panel.snapshotRecipeDiffList:clear()
        panel.snapshotRecipeDiffList:addItem(getText("UI_BurdJournals_SnapshotPreviewRecipesTitle") or "Recipes", {isHeader = true, text = getText("UI_BurdJournals_SnapshotPreviewRecipesTitle") or "Recipes"})
        if #panel.snapshotRecipeDiffRows == 0 then
            panel.snapshotRecipeDiffList:addItem(getText("UI_BurdJournals_SnapshotPreviewNoRecipeDiff") or "No recipe changes", {kind = "neutral", text = getText("UI_BurdJournals_SnapshotPreviewNoRecipeDiff") or "No recipe changes"})
        else
            for _, row in ipairs(panel.snapshotRecipeDiffRows) do
                panel.snapshotRecipeDiffList:addItem(row.text, row)
            end
        end
    end

    if panel.snapshotMediaDiffList then
        panel.snapshotMediaDiffList:clear()
        panel.snapshotMediaDiffList:addItem(getText("UI_BurdJournals_SnapshotPreviewMediaTitle") or "Media Skills", {isHeader = true, text = getText("UI_BurdJournals_SnapshotPreviewMediaTitle") or "Media Skills"})
        if #panel.snapshotMediaDiffRows == 0 then
            panel.snapshotMediaDiffList:addItem(getText("UI_BurdJournals_SnapshotPreviewNoMediaDiff") or "No media changes", {kind = "neutral", text = getText("UI_BurdJournals_SnapshotPreviewNoMediaDiff") or "No media changes"})
        else
            for _, row in ipairs(panel.snapshotMediaDiffRows) do
                panel.snapshotMediaDiffList:addItem(row.text, row)
            end
        end
    end
end

function BurdJournals.UI.DebugPanel:applySnapshotLiveBaselinePayload(payloadArgs)
    local panel = getSnapshotPanel(self)
    if not panel then
        return
    end

    local payload = payloadArgs and payloadArgs.baselinePayload or nil
    panel.snapshotLiveBaselinePayload = type(payload) == "table" and payload or nil

    local counts = payloadArgs and payloadArgs.counts or {}
    local currentLabel = getText("UI_BurdJournals_SnapshotCurrentBaselineLabel") or "Current baseline comparison: server payload loaded."
    if panel.snapshotLiveBaselinePayload then
        currentLabel = BurdJournals.formatText(
            "%s %dS %dM %dT %dR",
            getText("UI_BurdJournals_SnapshotCurrentBaselineLoaded") or "Current baseline:",
            tonumber(counts.skills) or 0,
            tonumber(counts.mediaSkills) or 0,
            tonumber(counts.traits) or 0,
            tonumber(counts.recipes) or 0
        )
    else
        currentLabel = getText("UI_BurdJournals_SnapshotCurrentBaselineMissing") or "No authoritative baseline payload available for target."
    end
    if panel.snapshotCurrentLabel then
        panel.snapshotCurrentLabel:setName(currentLabel)
    end
    self:refreshBaselineSnapshotPreview()
end

function BurdJournals.UI.DebugPanel.drawSnapshotSkillPreviewItem(self, y, item, alt)
    local h = self.itemheight
    local data = item.item
    if not data then
        return y + h
    end
    if data.isHeader then
        self:drawText(tostring(data.text or ""), 6, y + 8, 0.7, 0.75, 0.85, 1, UIFont.Small)
        return y + h
    end

    if self.mouseoverselected == item.index then
        self:drawRect(0, y, self.width, h, 0.2, 0.2, 0.3, 0.3)
    elseif item.index % 2 == 0 then
        self:drawRect(0, y, self.width, h, 0.08, 0.08, 0.1, 0.35)
    end

    local name = tostring(data.displayName or data.name or "Unknown")
    local deltaXP = tonumber(data.deltaXP) or 0
    local liveLevel = tonumber(data.liveLevel) or 0
    local newLevel = tonumber(data.snapshotLevel) or 0
    local deltaColor = {0.75, 0.75, 0.8}
    if deltaXP > 0 then
        deltaColor = {0.4, 0.95, 0.5}
    elseif deltaXP < 0 then
        deltaColor = {0.95, 0.45, 0.45}
    end

    self:drawText(name, 6, y + 3, 0.9, 0.9, 0.95, 1, UIFont.Small)
    self:drawText(BurdJournals.formatText("Now Lv %d -> After Lv %d | XP %+d", liveLevel, newLevel, deltaXP), 6, y + 16, deltaColor[1], deltaColor[2], deltaColor[3], 1, UIFont.Small)

    local squareSize = 10
    local squareGap = 2
    local scrollOffset = tonumber(BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH) or 15
    local squaresX = self.width - ((squareSize + squareGap) * 10) - scrollOffset - 6
    local squaresY = y + 5
    local newProgress = tonumber(data.snapshotProgress) or 0
    local liveProgress = tonumber(data.liveProgress) or 0

    for lvl = 1, 10 do
        local sx = squaresX + (lvl - 1) * (squareSize + squareGap)
        local sy = squaresY
        self:drawRect(sx, sy, squareSize, squareSize, 0.5, 0.1, 0.1, 0.12)

        if lvl <= newLevel then
            self:drawRect(sx, sy, squareSize, squareSize, 0.62, 0.34, 0.78, 0.55)
        elseif lvl == (newLevel + 1) and newProgress > 0 then
            local fillH = squareSize * newProgress
            self:drawRect(sx, sy + squareSize - fillH, squareSize, fillH, 0.62, 0.34, 0.78, 0.55)
        end

        if lvl <= liveLevel then
            self:drawRectBorder(sx + 1, sy + 1, squareSize - 2, squareSize - 2, 0.6, 0.82, 0.9, 0.45)
        elseif lvl == (liveLevel + 1) and liveProgress > 0 then
            local liveFill = math.max(1, math.floor(squareSize * liveProgress))
            self:drawRect(sx + 1, sy + 1, math.max(1, squareSize - 2), math.min(squareSize - 2, liveFill), 0.5, 0.8, 0.9, 0.4)
        end

        self:drawRectBorder(sx, sy, squareSize, squareSize, 0.42, 0.34, 0.46, 0.6)
    end
    return y + h
end

function BurdJournals.UI.DebugPanel.drawSnapshotDiffItem(self, y, item, alt)
    local h = self.itemheight
    local data = item.item
    if not data then
        return y + h
    end

    if data.isHeader then
        self:drawRect(0, y, self.width, h, 0.25, 0.22, 0.32, 0.45)
        self:drawText(tostring(data.text or ""), 6, y + 2, 0.92, 0.9, 0.98, 1, UIFont.Small)
        return y + h
    end

    local r, g, b = 0.82, 0.82, 0.86
    local prefix = "* "
    if data.kind == "added" then
        r, g, b = 0.45, 0.95, 0.55
        prefix = "+ "
    elseif data.kind == "removed" then
        r, g, b = 0.95, 0.45, 0.45
        prefix = "- "
    elseif data.kind == "changed" then
        r, g, b = 0.85, 0.75, 0.98
        prefix = "~ "
    end

    if self.mouseoverselected == item.index then
        self:drawRect(0, y, self.width, h, 0.2, 0.2, 0.3, 0.25)
    end
    self:drawText(prefix .. tostring(data.text or ""), 6, y + 2, r, g, b, 1, UIFont.Small)
    return y + h
end

function BurdJournals.UI.DebugPanel:refreshBaselineSnapshotDetail()
    local panel = getSnapshotPanel(self)
    if not panel or not panel.snapshotDetailLabel then
        return
    end
    local data = panel.snapshotSelectedData
    if not data then
        panel.snapshotDetailLabel:setName(getText("UI_BurdJournals_BaselineSnapshotDetailNone") or "Select a snapshot to preview details.")
        if panel.snapshotDetailMetaLabel then
            panel.snapshotDetailMetaLabel:setName("")
        end
        return
    end

    local counts = data.counts or {}
    local snapshotId = tostring(data.snapshotId or "?")
    local source = tostring(data.source or "?")
    local who = tostring(data.characterName or data.username or data.characterId or "Unknown")
    local mode = data.isProtected and "protected" or "unlocked"
    local ended = data.endedReason and (" | ended:" .. tostring(data.endedReason)) or ""
    local realCaptured = snapshotGetRealStamp(data, "captured")
    local realEnded = snapshotGetRealStamp(data, "ended")
    local compactId = snapshotId
    if #compactId > 48 then
        compactId = string.sub(compactId, 1, 20) .. "..." .. string.sub(compactId, -16)
    end
    local header = BurdJournals.formatText("%s | %s | %s", compactId, source, who)
    local detail = BurdJournals.formatText(
        "%dS %dM %dT %dR | %s%s",
        tonumber(counts.skills) or 0,
        tonumber(counts.mediaSkills) or 0,
        tonumber(counts.traits) or 0,
        tonumber(counts.recipes) or 0,
        mode,
        ended
    )
    if realCaptured and realCaptured ~= "" then
        detail = detail .. " | RL " .. tostring(realCaptured)
    end
    if realEnded and realEnded ~= "" then
        detail = detail .. " -> " .. tostring(realEnded)
    end
    panel.snapshotDetailLabel:setName(header)
    if panel.snapshotDetailMetaLabel then
        panel.snapshotDetailMetaLabel:setName(detail)
    end
    self:refreshBaselineSnapshotPreview()
end

function BurdJournals.UI.DebugPanel:applyBaselineSnapshotList(payload)
    local panel = getSnapshotPanel(self)
    if not panel or not panel.snapshotList then
        return
    end

    local previousSelection = panel.snapshotSelectedId
    panel.snapshotItems = type(payload and payload.items) == "table" and payload.items or {}
    if panel.snapshotListSummaryLabel then
        local shown = #panel.snapshotItems
        local total = tonumber(payload and payload.total) or shown
        if total > shown then
            panel.snapshotListSummaryLabel:setName(BurdJournals.formatText("Snapshots: %d/%d", shown, total))
        else
            panel.snapshotListSummaryLabel:setName(BurdJournals.formatText("Snapshots: %d", shown))
        end
    end
    panel.snapshotList:clear()

    for _, entry in ipairs(panel.snapshotItems) do
        entry.label = formatSnapshotSummaryLine(entry)
        panel.snapshotList:addItem(entry.label, entry)
    end

    panel.snapshotSelectedData = nil
    panel.snapshotSelectedId = nil
    if previousSelection then
        for i = 1, #panel.snapshotList.items do
            local row = panel.snapshotList.items[i]
            if row and row.item and row.item.snapshotId == previousSelection then
                panel.snapshotList.selected = i
                panel.snapshotSelectedId = previousSelection
                panel.snapshotSelectedData = row.item
                break
            end
        end
    end

    if (not panel.snapshotSelectedData) and #panel.snapshotList.items > 0 then
        panel.snapshotList.selected = 1
        panel.snapshotSelectedData = panel.snapshotList.items[1].item
        panel.snapshotSelectedId = panel.snapshotSelectedData and panel.snapshotSelectedData.snapshotId or nil
    end

    if #panel.snapshotList.items == 0 then
        panel.snapshotDetailLabel:setName(getText("UI_BurdJournals_BaselineSnapshotNoResults") or "No snapshots found.")
        if panel.snapshotDetailMetaLabel then
            panel.snapshotDetailMetaLabel:setName("")
        end
        if self.refreshBaselineSnapshotPreview then
            self:refreshBaselineSnapshotPreview()
        end
    else
        self:refreshBaselineSnapshotDetail()
        if panel.snapshotSelectedId and BurdJournals.Client and BurdJournals.Client.Debug and BurdJournals.Client.Debug.getBaselineSnapshot then
            BurdJournals.Client.Debug.getBaselineSnapshot(panel.snapshotSelectedId, self.player)
        end
    end
end

function BurdJournals.UI.DebugPanel:applyBaselineSnapshotDetail(snapshot)
    local panel = getSnapshotPanel(self)
    if not panel then
        return
    end
    if type(snapshot) ~= "table" then
        return
    end
    if panel.snapshotSelectedId and snapshot.snapshotId and panel.snapshotSelectedId ~= snapshot.snapshotId then
        return
    end
    panel.snapshotSelectedData = snapshot
    panel.snapshotSelectedId = snapshot.snapshotId
    self:refreshBaselineSnapshotDetail()
end

function BurdJournals.UI.DebugPanel:runSnapshotCommand(cmd)
    local panel = getSnapshotPanel(self)
    local targetPlayer = panel and panel.targetPlayer or self.player

    if cmd == "baselinesnapshot_refresh" then
        self:refreshSnapshotPanelData()
        self:setStatus("Requested baseline snapshots...", {r=0.5, g=0.8, b=1})
        return true
    elseif cmd == "baselinesnapshot_save" then
        if targetPlayer and BurdJournals.Client and BurdJournals.Client.Debug and BurdJournals.Client.Debug.saveBaselineSnapshot then
            BurdJournals.Client.Debug.saveBaselineSnapshot({
                targetUsername = targetPlayer:getUsername(),
                source = "debug_panel",
            }, self.player)
            self:setStatus("Saving baseline snapshot...", {r=0.5, g=0.8, b=1})
        else
            self:setStatus("Snapshot save unavailable", {r=1, g=0.5, b=0.3})
        end
        return true
    elseif cmd == "baselinesnapshot_apply" then
        local selectedSnapshot = panel and panel.snapshotSelectedData or nil
        if not selectedSnapshot or not selectedSnapshot.snapshotId then
            self:setStatus("Select a snapshot first", {r=1, g=0.6, b=0.3})
            return true
        end
        if not targetPlayer then
            self:setStatus("Target player unavailable", {r=1, g=0.6, b=0.3})
            return true
        end

        local snapshotId = tostring(selectedSnapshot.snapshotId)
        local targetName = targetPlayer:getUsername() or "Unknown"
        local promptFormat = getText("UI_BurdJournals_BaselineSnapshotConfirmApply")
            or "Apply snapshot %s to %s? Protected restore keeps debug lock until manually unlocked."
        local promptText = BurdJournals.formatText(promptFormat, snapshotId, targetName)
        if ISModalDialog then
            local selfRef = self
            local callback = function(_target, buttonObj)
                if isAffirmativeDialogButton(buttonObj) and selfRef
                    and BurdJournals.Client and BurdJournals.Client.Debug
                    and BurdJournals.Client.Debug.applyBaselineSnapshot
                then
                    BurdJournals.Client.Debug.applyBaselineSnapshot({
                        targetUsername = targetName,
                        snapshotId = snapshotId,
                        restoreMode = BurdJournals.getDefaultBaselineRestoreMode
                            and BurdJournals.getDefaultBaselineRestoreMode()
                            or BurdJournals.BASELINE_SNAPSHOT_RESTORE_UNLOCKED,
                    }, selfRef.player)
                    selfRef:setStatus("Applying snapshot " .. snapshotId .. "...", {r=0.5, g=0.8, b=1})
                end
            end
            if BurdJournals.createAdaptiveModalDialog then
                BurdJournals.createAdaptiveModalDialog({
                    player = self.player,
                    text = promptText,
                    yesNo = true,
                    onClick = callback,
                    minWidth = 420,
                    maxWidth = 840,
                    minHeight = 180,
                })
            else
                local w, h = 520, 180
                local x = (getCore():getScreenWidth() - w) / 2
                local y = (getCore():getScreenHeight() - h) / 2
                local modal = ISModalDialog:new(x, y, w, h, promptText, true, nil, callback)
                modal:initialise()
                modal:addToUIManager()
            end
        elseif BurdJournals.Client and BurdJournals.Client.Debug and BurdJournals.Client.Debug.applyBaselineSnapshot then
            BurdJournals.Client.Debug.applyBaselineSnapshot({
                targetUsername = targetName,
                snapshotId = snapshotId,
                restoreMode = BurdJournals.getDefaultBaselineRestoreMode
                    and BurdJournals.getDefaultBaselineRestoreMode()
                    or BurdJournals.BASELINE_SNAPSHOT_RESTORE_UNLOCKED,
            }, self.player)
            self:setStatus("Applying snapshot " .. snapshotId .. "...", {r=0.5, g=0.8, b=1})
        end
        return true
    elseif cmd == "baselinesnapshot_delete" then
        local selectedSnapshot = panel and panel.snapshotSelectedData or nil
        if not selectedSnapshot or not selectedSnapshot.snapshotId then
            self:setStatus("Select a snapshot first", {r=1, g=0.6, b=0.3})
            return true
        end
        local snapshotId = tostring(selectedSnapshot.snapshotId)
        local promptFormat = getText("UI_BurdJournals_BaselineSnapshotConfirmDelete")
            or "Delete snapshot %s permanently?"
        local promptText = BurdJournals.formatText(promptFormat, snapshotId)
        if ISModalDialog then
            local selfRef = self
            local callback = function(_target, buttonObj)
                if isAffirmativeDialogButton(buttonObj) and selfRef
                    and BurdJournals.Client and BurdJournals.Client.Debug
                    and BurdJournals.Client.Debug.deleteBaselineSnapshot
                then
                    BurdJournals.Client.Debug.deleteBaselineSnapshot(snapshotId, selfRef.player)
                    selfRef:setStatus("Deleting snapshot " .. snapshotId .. "...", {r=0.5, g=0.8, b=1})
                end
            end
            if BurdJournals.createAdaptiveModalDialog then
                BurdJournals.createAdaptiveModalDialog({
                    player = self.player,
                    text = promptText,
                    yesNo = true,
                    onClick = callback,
                    minWidth = 400,
                    maxWidth = 760,
                    minHeight = 170,
                })
            else
                local w, h = 460, 170
                local x = (getCore():getScreenWidth() - w) / 2
                local y = (getCore():getScreenHeight() - h) / 2
                local modal = ISModalDialog:new(x, y, w, h, promptText, true, nil, callback)
                modal:initialise()
                modal:addToUIManager()
            end
        elseif BurdJournals.Client and BurdJournals.Client.Debug and BurdJournals.Client.Debug.deleteBaselineSnapshot then
            BurdJournals.Client.Debug.deleteBaselineSnapshot(snapshotId, self.player)
            self:setStatus("Deleting snapshot " .. snapshotId .. "...", {r=0.5, g=0.8, b=1})
        end
        return true
    end
    return false
end

function BurdJournals.UI.DebugPanel:onSnapshotCmd(button)
    local cmd = button and button.internal or nil
    if not cmd then
        return
    end
    self:runSnapshotCommand(cmd)
end

-- Baseline command handler (for utility buttons)
function BurdJournals.UI.DebugPanel:onBaselineCmd(button)
    local cmd = button.internal
    local panel = self.baselinePanel
    local targetPlayer = panel and panel.targetPlayer or self.player
    
    if cmd == "dumpbaseline" then
        BurdJournals.debugPrint("[BSJ DEBUG] Player Baseline for: " .. (targetPlayer and targetPlayer:getUsername() or "Unknown"))
        local modData = targetPlayer and targetPlayer:getModData() or {}
        local skillBaseline = modData.BurdJournals and modData.BurdJournals.skillBaseline or {}
        local traitBaseline = modData.BurdJournals and modData.BurdJournals.traitBaseline or {}
        local recipeBaseline = modData.BurdJournals and modData.BurdJournals.recipeBaseline or {}
        BurdJournals.debugPrint("  Skills (XP):")
        for k, v in pairs(skillBaseline) do
            local level = BurdJournals.getSkillBaselineLevel and BurdJournals.getSkillBaselineLevel(targetPlayer, k) or "?"
            BurdJournals.debugPrint("    " .. k .. ": " .. tostring(v) .. " XP (Level " .. tostring(level) .. ")")
        end
        BurdJournals.debugPrint("  Traits:")
        for k, v in pairs(traitBaseline) do
            BurdJournals.debugPrint("    " .. k .. ": " .. tostring(v))
        end
        BurdJournals.debugPrint("  Recipes:")
        for k, v in pairs(recipeBaseline) do
            BurdJournals.debugPrint("    " .. k .. ": " .. tostring(v))
        end
        BurdJournals.debugPrint("  Debug Modified: " .. tostring(modData.BurdJournals and modData.BurdJournals.debugModified or false))
        self:setStatus("Baseline dumped to console", {r=0.5, g=0.8, b=1})
    elseif cmd == "dumpspawnstate" then
        if BurdJournals and BurdJournals.Client and BurdJournals.Client.dumpBaselineSpawnState then
            BurdJournals.Client.dumpBaselineSpawnState(targetPlayer, "DebugPanel")
            self:setStatus("Spawn readiness dumped to console", {r=0.5, g=0.8, b=1})
        else
            self:setStatus("Spawn readiness dump unavailable", {r=1, g=0.5, b=0.3})
        end
    elseif cmd == "savebaselinechanges" then
        if not panel or panel.baselineDraftDirty ~= true then
            self:setStatus(getText("UI_BurdJournals_BaselineDraftNoChanges") or "No pending baseline changes to save.", {r=0.9, g=0.75, b=0.4})
            return
        end
        local payload = self.buildBaselineDraftPayload and self:buildBaselineDraftPayload() or nil
        if not payload then
            self:setStatus("Could not build baseline draft payload", {r=1, g=0.5, b=0.3})
            return
        end
        if targetPlayer and BurdJournals.Client and BurdJournals.Client.Debug and BurdJournals.Client.Debug.saveBaselineDraft then
            BurdJournals.Client.Debug.saveBaselineDraft({
                targetUsername = targetPlayer:getUsername(),
                skillBaseline = payload.skillBaseline,
                traitBaseline = payload.traitBaseline,
                recipeBaseline = payload.recipeBaseline,
            }, self.player)
            self:setStatus(getText("UI_BurdJournals_BaselineDraftSaving") or "Saving baseline snapshot...", {r=0.5, g=0.8, b=1})
        else
            self:setStatus("Baseline draft save unavailable", {r=1, g=0.5, b=0.3})
        end
    elseif cmd == "discardbaselinechanges" then
        if not panel or panel.baselineDraftDirty ~= true then
            self:setStatus(getText("UI_BurdJournals_BaselineDraftNoChanges") or "No pending baseline changes to discard.", {r=0.9, g=0.75, b=0.4})
            return
        end
        self:refreshBaselineData()
        self:setStatus(getText("UI_BurdJournals_BaselineDraftDiscarded") or "Discarded baseline draft changes.", {r=0.95, g=0.78, b=0.45})
    elseif cmd == "opensnapshots" then
        self:showTab("snapshots")
    elseif cmd == "baselinesnapshot_refresh"
        or cmd == "baselinesnapshot_save"
        or cmd == "baselinesnapshot_apply"
        or cmd == "baselinesnapshot_delete"
    then
        self:runSnapshotCommand(cmd)
    elseif cmd == "clearall" then
        if panel then
            local changedSkillCount = 0
            local changedTraitCount = 0
            local changedRecipeCount = 0
            local changedAny = false

            panel.baselineDraftSkills = panel.baselineDraftSkills or {}
            panel.baselineDraftTraits = panel.baselineDraftTraits or {}
            panel.baselineDraftRecipes = panel.baselineDraftRecipes or {}

            if panel.baselineSkillList and panel.baselineSkillList.items then
                for _, row in ipairs(panel.baselineSkillList.items) do
                    local data = row and row.item
                    if data and data.name then
                        local oldXP = tonumber(data.baselineXP) or 0
                        local oldLevel = tonumber(data.baselineLevel) or 0
                        if oldXP > 0 or oldLevel > 0 then
                            changedAny = true
                            changedSkillCount = changedSkillCount + 1
                        end
                        data.baselineLevel = 0
                        data.baselineXP = 0
                        panel.baselineDraftSkills[tostring(data.name)] = 0
                    end
                end
            end

            if panel.baselineTraitList and panel.baselineTraitList.items then
                for _, row in ipairs(panel.baselineTraitList.items) do
                    local data = row and row.item
                    if data and data.id then
                        if data.isBaseline == true then
                            changedAny = true
                            changedTraitCount = changedTraitCount + 1
                        end
                        data.isBaseline = false
                        panel.baselineDraftTraits[tostring(data.id)] = false
                    end
                end
            end

            if panel.baselineRecipeList and panel.baselineRecipeList.items then
                for _, row in ipairs(panel.baselineRecipeList.items) do
                    local data = row and row.item
                    if data and data.name then
                        if data.isBaseline == true then
                            changedAny = true
                            changedRecipeCount = changedRecipeCount + 1
                        end
                        data.isBaseline = false
                        local recipeName = BurdJournals.getRecipeCanonicalName and BurdJournals.getRecipeCanonicalName(data.name) or data.name
                        panel.baselineDraftRecipes[tostring(recipeName)] = false
                    end
                end
            end

            if changedAny then
                if self.markBaselineDraftDirty then
                    self:markBaselineDraftDirty(
                        BurdJournals.formatText(
                            "Draft cleared: %d skills, %d traits, %d recipes reset. Save to apply.",
                            changedSkillCount,
                            changedTraitCount,
                            changedRecipeCount
                        )
                    )
                else
                    self:setStatus("Baseline draft cleared. Save to apply.", {r=0.95, g=0.8, b=0.4})
                end
            else
                self:setStatus("Baseline draft is already empty.", {r=0.9, g=0.75, b=0.4})
            end
        end
    elseif cmd == "recalculate" then
        if panel and panel.baselineSkillList and panel.baselineSkillList.items then
            panel.baselineDraftSkills = panel.baselineDraftSkills or {}
            local changedCount = 0
            local changedAny = false

            for _, row in ipairs(panel.baselineSkillList.items) do
                local data = row and row.item
                if data and data.name then
                    local targetXP = math.max(0, math.floor(tonumber(data.currentXP) or 0))
                    local currentLevel = math.max(0, math.min(10, math.floor(tonumber(data.currentLevel) or 0)))
                    if targetXP <= 0 and currentLevel > 0 then
                        local isPassive = data.isPassive or data.name == "Fitness" or data.name == "Strength"
                        if isPassive then
                            targetXP = BurdJournals.PASSIVE_XP_THRESHOLDS and BurdJournals.PASSIVE_XP_THRESHOLDS[currentLevel] or 0
                        else
                            targetXP = BurdJournals.STANDARD_XP_THRESHOLDS and BurdJournals.STANDARD_XP_THRESHOLDS[currentLevel] or 0
                        end
                        targetXP = math.max(0, math.floor(tonumber(targetXP) or 0))
                    end

                    local oldXP = math.max(0, math.floor(tonumber(data.baselineXP) or 0))
                    if oldXP ~= targetXP then
                        changedAny = true
                        changedCount = changedCount + 1
                    end

                    data.baselineXP = targetXP
                    if BurdJournals.Client and BurdJournals.Client.Debug and BurdJournals.Client.Debug.getLevelFromXP then
                        data.baselineLevel = BurdJournals.Client.Debug.getLevelFromXP(data.name, targetXP)
                    else
                        data.baselineLevel = currentLevel
                    end
                    panel.baselineDraftSkills[tostring(data.name)] = targetXP
                end
            end

            if changedAny then
                if self.markBaselineDraftDirty then
                    self:markBaselineDraftDirty(
                        BurdJournals.formatText(
                            "Draft set to current skills: %d skill baselines updated. Save to apply.",
                            changedCount
                        )
                    )
                else
                    self:setStatus("Draft set to current skills. Save to apply.", {r=0.95, g=0.8, b=0.4})
                end
            else
                self:setStatus("Baseline skill draft already matches current skills.", {r=0.9, g=0.75, b=0.4})
            end
        end
    elseif cmd == "copycurrenttraits" then
        if panel and panel.baselineTraitList and panel.baselineTraitList.items then
            panel.baselineDraftTraits = panel.baselineDraftTraits or {}
            local changedCount = 0
            local changedAny = false
            for _, row in ipairs(panel.baselineTraitList.items) do
                local data = row and row.item
                if data and data.id and not data.isPassiveSkillTrait then
                    local newStatus = data.hasTrait == true
                    if data.isBaseline ~= newStatus then
                        changedAny = true
                        changedCount = changedCount + 1
                    end
                    data.isBaseline = newStatus
                    panel.baselineDraftTraits[tostring(data.id)] = newStatus
                end
            end
            if changedAny then
                self:markBaselineDraftDirty(BurdJournals.formatText("Draft set to current traits: %d entries updated. Save to apply.", changedCount))
            else
                self:setStatus("Trait baseline draft already matches current traits.", {r=0.9, g=0.75, b=0.4})
            end
        end
    elseif cmd == "copycurrentrecipes" then
        if panel and panel.baselineRecipeList and panel.baselineRecipeList.items then
            panel.baselineDraftRecipes = panel.baselineDraftRecipes or {}
            local changedCount = 0
            local changedAny = false
            for _, row in ipairs(panel.baselineRecipeList.items) do
                local data = row and row.item
                if data and data.name then
                    local newStatus = data.isKnown == true
                    if data.isBaseline ~= newStatus then
                        changedAny = true
                        changedCount = changedCount + 1
                    end
                    data.isBaseline = newStatus
                    local recipeName = BurdJournals.getRecipeCanonicalName and BurdJournals.getRecipeCanonicalName(data.name) or data.name
                    panel.baselineDraftRecipes[tostring(recipeName)] = newStatus
                end
            end
            if changedAny then
                self:markBaselineDraftDirty(BurdJournals.formatText("Draft set to current recipes: %d entries updated. Save to apply.", changedCount))
            else
                self:setStatus("Recipe baseline draft already matches current known recipes.", {r=0.9, g=0.75, b=0.4})
            end
        end
    elseif cmd == "migratejournals" then
        if sendClientCommand then
            sendClientCommand("BurdJournals", "debugMigrateOnlineJournals", {})
            self:setStatus("Requested online journal migration on server...", {r=0.5, g=0.8, b=1})
        else
            self:setStatus("Migration command unavailable in this context", {r=1, g=0.5, b=0.3})
        end
    end
end

-- ============================================================================
-- Tab 4: Journal Editor Panel
-- Allows editing skills and traits of a selected journal
-- ============================================================================

local function normalizeJournalEditProfile(profileValue)
    local value = tostring(profileValue or "normal")
    if value == "debug" then
        return "debug"
    end
    return "normal"
end

local function getJournalProfileFromCombo(panel)
    if not panel or not panel.journalProfileCombo then
        return "normal"
    end
    local selected = panel.journalProfileCombo.selected or 1
    local value = panel.journalProfileCombo:getOptionData(selected)
        or panel.journalProfileCombo.options[selected]
    return normalizeJournalEditProfile(value)
end

local function updateJournalProfileConvertButtons(panel, profileValue)
    if not panel then
        return
    end
    local profile = normalizeJournalEditProfile(profileValue or getJournalProfileFromCombo(panel))
    if panel.journalConvertNormalBtn then
        panel.journalConvertNormalBtn:setVisible(profile == "debug")
    end
    if panel.journalConvertDebugBtn then
        panel.journalConvertDebugBtn:setVisible(profile ~= "debug")
    end
end

local function setJournalProfileCombo(panel, profileValue)
    if not panel or not panel.journalProfileCombo then
        return
    end
    local profile = normalizeJournalEditProfile(profileValue)
    local selected = (profile == "debug") and 2 or 1
    panel.journalProfileCombo.selected = selected
    panel.journalProfile = profile
    updateJournalProfileConvertButtons(panel, profile)
end

local function resolveJournalEditProfileForItem(journal, explicitProfile)
    if explicitProfile ~= nil then
        return normalizeJournalEditProfile(explicitProfile)
    end

    local instance = BurdJournals.UI and BurdJournals.UI.DebugPanel and BurdJournals.UI.DebugPanel.instance
    local panel = instance and instance.journalPanel or nil
    if panel and instance.editingJournal == journal then
        return getJournalProfileFromCombo(panel)
    end

    local modData = journal and journal.getModData and journal:getModData() or nil
    local data = modData and modData.BurdJournals or nil
    if type(data) == "table" and data.isDebugSpawned == true then
        return "debug"
    end
    return "normal"
end

local function normalizeJournalOriginMode(originValue)
    local value = tostring(originValue or "found")
    if value == "personal" or value == "found" or value == "world" or value == "zombie" then
        return value
    end
    return "found"
end

local function getJournalOriginFromCombo(panel)
    if not panel or not panel.journalOriginCombo then
        return "found"
    end
    local selected = panel.journalOriginCombo.selected or 1
    local value = panel.journalOriginCombo:getOptionData(selected)
        or panel.journalOriginCombo.options[selected]
    return normalizeJournalOriginMode(value)
end

local function setJournalOriginCombo(panel, originValue)
    if not panel or not panel.journalOriginCombo then
        return
    end
    local originMode = normalizeJournalOriginMode(originValue)
    local selectedIndex = 2
    if originMode == "personal" then
        selectedIndex = 1
    elseif originMode == "found" then
        selectedIndex = 2
    elseif originMode == "world" then
        selectedIndex = 3
    elseif originMode == "zombie" then
        selectedIndex = 4
    end
    panel.journalOriginCombo.selected = selectedIndex
    panel.journalOriginMode = originMode
end

local function normalizeJournalEditType(typeValue)
    local value = tostring(typeValue or "filled")
    if value == "blank" or value == "filled" or value == "worn" or value == "bloody" or value == "cursed" then
        return value
    end
    return "filled"
end

local function getJournalEditTypeFromCombo(panel)
    if not panel or not panel.journalTypeCombo then
        return "filled"
    end
    local selected = panel.journalTypeCombo.selected or 1
    local value = panel.journalTypeCombo:getOptionData(selected)
        or panel.journalTypeCombo.options[selected]
    return normalizeJournalEditType(value)
end

local function setJournalEditTypeCombo(panel, typeValue)
    if not panel or not panel.journalTypeCombo then
        return
    end
    local selectedType = normalizeJournalEditType(typeValue)
    local selected = 2
    if selectedType == "blank" then
        selected = 1
    elseif selectedType == "filled" then
        selected = 2
    elseif selectedType == "worn" then
        selected = 3
    elseif selectedType == "bloody" then
        selected = 4
    elseif selectedType == "cursed" then
        selected = 5
    end
    panel.journalTypeCombo.selected = selected
    panel.journalEditType = selectedType
end

local function inferJournalEditTypeFromItem(journal, journalData)
    local fullType = journal and journal.getFullType and journal:getFullType() or ""
    local cursedItemType = BurdJournals.CURSED_ITEM_TYPE or "BurdJournals.CursedJournal"

    if type(fullType) == "string" and string.find(fullType, "BlankSurvivalJournal", 1, true) then
        return "blank"
    end
    if fullType == cursedItemType then
        return "cursed"
    end
    if type(fullType) == "string" and string.find(fullType, "_Worn", 1, true) then
        return "worn"
    end
    if type(fullType) == "string" and string.find(fullType, "_Bloody", 1, true) then
        return "bloody"
    end

    if type(journalData) == "table" then
        if journalData.isCursedJournal == true and journalData.cursedState ~= "unleashed" then
            return "cursed"
        end
        if journalData.isWorn == true or journalData.wasFromWorn == true then
            return "worn"
        end
        if journalData.isBloody == true or journalData.wasFromBloody == true or journalData.isCursedReward == true then
            return "bloody"
        end
    end
    return "filled"
end

local function getEditorItemTypeForJournalType(typeValue)
    local selectedType = normalizeJournalEditType(typeValue)
    if selectedType == "blank" then
        return "BurdJournals.BlankSurvivalJournal"
    elseif selectedType == "worn" then
        return "BurdJournals.FilledSurvivalJournal_Worn"
    elseif selectedType == "bloody" then
        return "BurdJournals.FilledSurvivalJournal_Bloody"
    elseif selectedType == "cursed" then
        return BurdJournals.CURSED_ITEM_TYPE or "BurdJournals.CursedJournal"
    end
    return "BurdJournals.FilledSurvivalJournal"
end

local function findOwnerOptionIndexByCombo(ownerCombo, predicate)
    if not ownerCombo or not predicate then
        return nil
    end
    local optionCount = #ownerCombo.options
    for i = 1, optionCount do
        local data = ownerCombo:getOptionData(i)
        if predicate(data, i) then
            return i
        end
    end
    return nil
end

function BurdJournals.UI.DebugPanel:createJournalPanel(startY, height)
    local panel = ISPanel:new(5, startY, self.width - 10, height)
    panel:initialise()
    panel:instantiate()
    panel.backgroundColor = {r=0.12, g=0.12, b=0.15, a=1}
    panel.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    self:addChild(panel)
    self.tabPanels["journal"] = panel
    
    local padding = 10
    local y = padding
    local fullWidth = panel.width - padding * 2
    local halfWidth = (fullWidth - padding) / 2
    local btnHeight = 24
    
    -- Header - Journal name display
    panel.journalHeaderLabel = ISLabel:new(padding, y, 20, "No journal selected", 0.9, 0.7, 0.5, 1, UIFont.Medium, true)
    panel.journalHeaderLabel:initialise()
    panel.journalHeaderLabel:instantiate()
    panel:addChild(panel.journalHeaderLabel)
    
    -- Select Journal button (for when no journal is selected via context menu)
    local selectBtn = ISButton:new(fullWidth - 100, y - 2, 110, 22, "Pick from Inv", self, BurdJournals.UI.DebugPanel.onJournalSelectFromInventory)
    selectBtn:initialise()
    selectBtn:instantiate()
    selectBtn.font = UIFont.Small
    selectBtn.textColor = {r=1, g=1, b=1, a=1}
    selectBtn.borderColor = {r=0.4, g=0.5, b=0.6, a=1}
    selectBtn.backgroundColor = {r=0.2, g=0.25, b=0.3, a=1}
    panel:addChild(selectBtn)
    y = y + 28

    -- Journal picker dropdown: Name | Author | UUID
    local pickerLabel = ISLabel:new(padding, y + 2, 16, "Nearby:", 0.8, 0.8, 0.9, 1, UIFont.Small, true)
    pickerLabel:initialise()
    pickerLabel:instantiate()
    panel:addChild(pickerLabel)

    local pickerX = padding + 52
    local pickerWidth = math.max(240, fullWidth - 185)
    panel.journalSelectCombo = ISComboBox:new(pickerX, y - 2, pickerWidth, 22, self, BurdJournals.UI.DebugPanel.onJournalPickerChanged)
    panel.journalSelectCombo:initialise()
    panel.journalSelectCombo:instantiate()
    panel.journalSelectCombo.font = UIFont.Small
    panel.journalSelectCombo.borderColor = {r=0.35, g=0.45, b=0.55, a=1}
    panel:addChild(panel.journalSelectCombo)

    local pickerBtnX = pickerX + pickerWidth + 5
    local refreshListBtn = ISButton:new(pickerBtnX, y - 2, 56, 22, "Reload", self, BurdJournals.UI.DebugPanel.onJournalRefreshList)
    refreshListBtn:initialise()
    refreshListBtn:instantiate()
    refreshListBtn.font = UIFont.Small
    refreshListBtn.textColor = {r=1, g=1, b=1, a=1}
    refreshListBtn.borderColor = {r=0.4, g=0.5, b=0.6, a=1}
    refreshListBtn.backgroundColor = {r=0.2, g=0.25, b=0.3, a=1}
    panel:addChild(refreshListBtn)

    local useSelectedBtn = ISButton:new(pickerBtnX + 60, y - 2, 52, 22, "Open", self, BurdJournals.UI.DebugPanel.onJournalUseDropdownSelection)
    useSelectedBtn:initialise()
    useSelectedBtn:instantiate()
    useSelectedBtn.font = UIFont.Small
    useSelectedBtn.textColor = {r=1, g=1, b=1, a=1}
    useSelectedBtn.borderColor = {r=0.35, g=0.55, b=0.4, a=1}
    useSelectedBtn.backgroundColor = {r=0.2, g=0.3, b=0.25, a=1}
    panel:addChild(useSelectedBtn)
    y = y + 26

    -- Server index picker (can include journals not currently nearby/open)
    local serverPickerLabel = ISLabel:new(padding, y + 2, 16, "Server:", 0.8, 0.8, 0.9, 1, UIFont.Small, true)
    serverPickerLabel:initialise()
    serverPickerLabel:instantiate()
    panel:addChild(serverPickerLabel)

    local serverPickerX = padding + 52
    local serverPickerWidth = math.max(240, fullWidth - 185)
    panel.journalServerIndexCombo = ISComboBox:new(serverPickerX, y - 2, serverPickerWidth, 22, self, BurdJournals.UI.DebugPanel.onJournalServerIndexChanged)
    panel.journalServerIndexCombo:initialise()
    panel.journalServerIndexCombo:instantiate()
    panel.journalServerIndexCombo.font = UIFont.Small
    panel.journalServerIndexCombo.borderColor = {r=0.35, g=0.45, b=0.55, a=1}
    panel:addChild(panel.journalServerIndexCombo)

    local serverBtnX = serverPickerX + serverPickerWidth + 5
    local refreshServerListBtn = ISButton:new(serverBtnX, y - 2, 56, 22, "Load", self, BurdJournals.UI.DebugPanel.onJournalRefreshServerIndex)
    refreshServerListBtn:initialise()
    refreshServerListBtn:instantiate()
    refreshServerListBtn.font = UIFont.Small
    refreshServerListBtn.textColor = {r=1, g=1, b=1, a=1}
    refreshServerListBtn.borderColor = {r=0.4, g=0.5, b=0.6, a=1}
    refreshServerListBtn.backgroundColor = {r=0.2, g=0.25, b=0.3, a=1}
    panel:addChild(refreshServerListBtn)

    local useServerSelectedBtn = ISButton:new(serverBtnX + 60, y - 2, 52, 22, "Open", self, BurdJournals.UI.DebugPanel.onJournalUseServerIndexSelection)
    useServerSelectedBtn:initialise()
    useServerSelectedBtn:instantiate()
    useServerSelectedBtn.font = UIFont.Small
    useServerSelectedBtn.textColor = {r=1, g=1, b=1, a=1}
    useServerSelectedBtn.borderColor = {r=0.35, g=0.55, b=0.4, a=1}
    useServerSelectedBtn.backgroundColor = {r=0.2, g=0.3, b=0.25, a=1}
    panel:addChild(useServerSelectedBtn)
    y = y + 26
    
    -- Journal info line
    panel.journalInfoLabel = ISLabel:new(padding, y, 16, "", 0.6, 0.6, 0.7, 1, UIFont.Small, true)
    panel.journalInfoLabel:initialise()
    panel.journalInfoLabel:instantiate()
    panel:addChild(panel.journalInfoLabel)
    y = y + 20

    panel.journalTargetSummaryLabel = ISLabel:new(padding, y, 16, "", 0.82, 0.88, 0.98, 1, UIFont.Small, true)
    panel.journalTargetSummaryLabel:initialise()
    panel.journalTargetSummaryLabel:instantiate()
    panel:addChild(panel.journalTargetSummaryLabel)
    y = y + 18

    panel.journalTargetHelpLabel = ISLabel:new(padding, y, 16, "", 0.62, 0.74, 0.86, 1, UIFont.Small, true)
    panel.journalTargetHelpLabel:initialise()
    panel.journalTargetHelpLabel:instantiate()
    panel:addChild(panel.journalTargetHelpLabel)
    y = y + 22

    -- Metadata controls (type/profile/origin + author/flavor/age) in a compact block.
    panel.journalMetaLabel = ISLabel:new(padding, y, 16, "Journal Metadata", 0.75, 0.82, 0.95, 1, UIFont.Small, true)
    panel.journalMetaLabel:initialise()
    panel.journalMetaLabel:instantiate()
    panel:addChild(panel.journalMetaLabel)
    y = y + 18

    local row1Y = y
    panel.journalTypeLabel = ISLabel:new(padding, row1Y + 2, 16, "Type:", 0.8, 0.8, 0.9, 1, UIFont.Small, true)
    panel.journalTypeLabel:initialise()
    panel.journalTypeLabel:instantiate()
    panel:addChild(panel.journalTypeLabel)

    panel.journalTypeCombo = ISComboBox:new(padding + 46, row1Y - 2, 122, 22, self, BurdJournals.UI.DebugPanel.onJournalTypeChange)
    panel.journalTypeCombo:initialise()
    panel.journalTypeCombo:instantiate()
    panel.journalTypeCombo.font = UIFont.Small
    panel.journalTypeCombo:addOptionWithData("Blank", "blank")
    panel.journalTypeCombo:addOptionWithData("Filled", "filled")
    panel.journalTypeCombo:addOptionWithData("Worn", "worn")
    panel.journalTypeCombo:addOptionWithData("Bloody", "bloody")
    panel.journalTypeCombo:addOptionWithData("Cursed", "cursed")
    setComboSelectedCompat(panel.journalTypeCombo, 2)
    panel:addChild(panel.journalTypeCombo)
    panel.journalEditType = "filled"

    panel.journalProfileLabel = ISLabel:new(
        padding + 176,
        row1Y + 2,
        16,
        (BurdJournals.safeGetText and BurdJournals.safeGetText("UI_BurdJournals_DebugSpawnProfile", "Spawn Profile:"))
            or "Spawn Profile:",
        0.8, 0.8, 0.9, 1,
        UIFont.Small,
        true
    )
    panel.journalProfileLabel:initialise()
    panel.journalProfileLabel:instantiate()
    panel:addChild(panel.journalProfileLabel)

    panel.journalProfileCombo = ISComboBox:new(padding + 266, row1Y - 2, 170, 22, self, BurdJournals.UI.DebugPanel.onJournalProfileChange)
    panel.journalProfileCombo:initialise()
    panel.journalProfileCombo:instantiate()
    panel.journalProfileCombo.font = UIFont.Small
    panel.journalProfileCombo:addOptionWithData(
        (BurdJournals.safeGetText and BurdJournals.safeGetText("UI_BurdJournals_DebugSpawnProfileNormal", "Normal (Natural)"))
            or "Normal (Natural)",
        "normal"
    )
    panel.journalProfileCombo:addOptionWithData(
        (BurdJournals.safeGetText and BurdJournals.safeGetText("UI_BurdJournals_DebugSpawnProfileDebug", "Debug (Legacy)"))
            or "Debug (Legacy)",
        "debug"
    )
    setComboSelectedCompat(panel.journalProfileCombo, 1)
    panel:addChild(panel.journalProfileCombo)
    panel.journalProfile = "normal"

    panel.journalOriginLabel = ISLabel:new(
        padding + 444,
        row1Y + 2,
        16,
        BurdJournals.safeGetText and BurdJournals.safeGetText("UI_BurdJournals_DebugSpawnOrigin", "Origin:") or "Origin:",
        0.8, 0.8, 0.9, 1,
        UIFont.Small,
        true
    )
    panel.journalOriginLabel:initialise()
    panel.journalOriginLabel:instantiate()
    panel:addChild(panel.journalOriginLabel)

    panel.journalOriginCombo = ISComboBox:new(padding + 498, row1Y - 2, 180, 22, self, BurdJournals.UI.DebugPanel.onJournalOriginChange)
    panel.journalOriginCombo:initialise()
    panel.journalOriginCombo:instantiate()
    panel.journalOriginCombo.font = UIFont.Small
    panel.journalOriginCombo:addOptionWithData(
        BurdJournals.safeGetText and BurdJournals.safeGetText("UI_BurdJournals_DebugSpawnOriginPersonal", "Personal")
            or "Personal",
        "personal"
    )
    panel.journalOriginCombo:addOptionWithData(
        BurdJournals.safeGetText and BurdJournals.safeGetText("UI_BurdJournals_DebugSpawnOriginFound", "Found")
            or "Found",
        "found"
    )
    panel.journalOriginCombo:addOptionWithData(
        BurdJournals.safeGetText and BurdJournals.safeGetText("UI_BurdJournals_DebugSpawnOriginWorld", "Found in World")
            or "Found in World",
        "world"
    )
    panel.journalOriginCombo:addOptionWithData(
        BurdJournals.safeGetText and BurdJournals.safeGetText("UI_BurdJournals_DebugSpawnOriginZombie", "Recovered from Zombie")
            or "Recovered from Zombie",
        "zombie"
    )
    setComboSelectedCompat(panel.journalOriginCombo, 2)
    panel:addChild(panel.journalOriginCombo)
    panel.journalOriginMode = "found"
    y = row1Y + 26

    local row2Y = y
    panel.journalOwnerLabel = ISLabel:new(
        padding,
        row2Y + 2,
        16,
        (BurdJournals.safeGetText and BurdJournals.safeGetText("UI_BurdJournals_DebugSpawnOwnerAssign", "Assign to Player:"))
            or "Assign to Player:",
        0.8, 0.8, 0.9, 1,
        UIFont.Small,
        true
    )
    panel.journalOwnerLabel:initialise()
    panel.journalOwnerLabel:instantiate()
    panel:addChild(panel.journalOwnerLabel)

    panel.journalOwnerCombo = ISComboBox:new(padding + 92, row2Y - 2, 190, 22, self, BurdJournals.UI.DebugPanel.onJournalOwnerChange)
    panel.journalOwnerCombo:initialise()
    panel.journalOwnerCombo:instantiate()
    panel.journalOwnerCombo.font = UIFont.Small
    panel:addChild(panel.journalOwnerCombo)

    panel.journalOwnerCustomEntry = ISTextEntryBox:new("", padding + 92, row2Y - 2, 190, 20)
    panel.journalOwnerCustomEntry:initialise()
    panel.journalOwnerCustomEntry:instantiate()
    panel.journalOwnerCustomEntry.font = UIFont.Small
    panel.journalOwnerCustomEntry:setTooltip("Custom author name")
    panel:addChild(panel.journalOwnerCustomEntry)

    panel.journalFlavorLabel = ISLabel:new(padding + 288, row2Y + 2, 16, "Flavor:", 0.8, 0.8, 0.9, 1, UIFont.Small, true)
    panel.journalFlavorLabel:initialise()
    panel.journalFlavorLabel:instantiate()
    panel:addChild(panel.journalFlavorLabel)

    panel.journalFlavorEntry = ISTextEntryBox:new("", padding + 336, row2Y - 2, 170, 20)
    panel.journalFlavorEntry:initialise()
    panel.journalFlavorEntry:instantiate()
    panel.journalFlavorEntry.font = UIFont.Small
    panel.journalFlavorEntry:setTooltip("Custom flavor text (leave empty for profession/default flavor)")
    panel:addChild(panel.journalFlavorEntry)

    panel.journalAgeLabel = ISLabel:new(padding + 512, row2Y + 2, 16, "Age h:", 0.8, 0.8, 0.9, 1, UIFont.Small, true)
    panel.journalAgeLabel:initialise()
    panel.journalAgeLabel:instantiate()
    panel:addChild(panel.journalAgeLabel)

    panel.journalAgeEntry = ISTextEntryBox:new("0", padding + 556, row2Y - 2, 64, 20)
    panel.journalAgeEntry:initialise()
    panel.journalAgeEntry:instantiate()
    panel.journalAgeEntry.font = UIFont.Small
    panel.journalAgeEntry:setOnlyNumbers(true)
    panel.journalAgeEntry:setTooltip("How many world-hours old the journal appears")
    panel:addChild(panel.journalAgeEntry)

    panel.journalApplyMetaBtn = ISButton:new(padding + 626, row2Y - 2, 138, 22, "Apply Metadata", self, BurdJournals.UI.DebugPanel.onJournalApplyMetadata)
    panel.journalApplyMetaBtn:initialise()
    panel.journalApplyMetaBtn:instantiate()
    panel.journalApplyMetaBtn.font = UIFont.Small
    panel.journalApplyMetaBtn.textColor = {r=1, g=1, b=1, a=1}
    panel.journalApplyMetaBtn.borderColor = {r=0.35, g=0.5, b=0.65, a=1}
    panel.journalApplyMetaBtn.backgroundColor = {r=0.2, g=0.27, b=0.35, a=1}
    panel.journalApplyMetaBtn:setTooltip("Apply type/origin/author/flavor/age/profile changes.")
    panel:addChild(panel.journalApplyMetaBtn)

    self:populateOwnerCombo({ownerCombo = panel.journalOwnerCombo})
    setJournalEditTypeCombo(panel, "filled")
    updateJournalProfileConvertButtons(panel, "normal")
    y = row2Y + 26

    -- UUID tools (target stale/exploited journals directly)
    local uuidLabel = ISLabel:new(padding, y, 16, "UUID:", 0.8, 0.8, 0.9, 1, UIFont.Small, true)
    uuidLabel:initialise()
    uuidLabel:instantiate()
    panel:addChild(uuidLabel)

    local uuidFieldX = padding + 42
    local findUuidW, repairUuidW, restoreUuidW = 56, 62, 92
    local uuidBtnGap = 4
    local uuidButtonsTotal = findUuidW + repairUuidW + restoreUuidW + (uuidBtnGap * 2)
    local uuidRowRight = padding + fullWidth
    local uuidBtnX = uuidRowRight - uuidButtonsTotal
    local uuidEntryWidth = math.max(150, uuidBtnX - uuidFieldX - 5)
    panel.journalUUIDEntry = ISTextEntryBox:new("", uuidFieldX, y - 2, uuidEntryWidth, 20)
    panel.journalUUIDEntry:initialise()
    panel.journalUUIDEntry:instantiate()
    panel.journalUUIDEntry.font = UIFont.Small
    panel.journalUUIDEntry:setTooltip("Paste a journal UUID to locate or repair it.")
    panel:addChild(panel.journalUUIDEntry)

    local findUuidBtn = ISButton:new(uuidBtnX, y - 2, findUuidW, 20, "Find", self, BurdJournals.UI.DebugPanel.onJournalFindByUUID)
    findUuidBtn:initialise()
    findUuidBtn:instantiate()
    findUuidBtn.font = UIFont.Small
    findUuidBtn.textColor = {r=1, g=1, b=1, a=1}
    findUuidBtn.borderColor = {r=0.35, g=0.5, b=0.65, a=1}
    findUuidBtn.backgroundColor = {r=0.18, g=0.27, b=0.35, a=1}
    panel:addChild(findUuidBtn)

    local repairUuidBtnX = uuidBtnX + findUuidW + uuidBtnGap
    local repairUuidBtn = ISButton:new(repairUuidBtnX, y - 2, repairUuidW, 20, "Repair", self, BurdJournals.UI.DebugPanel.onJournalRepairByUUID)
    repairUuidBtn:initialise()
    repairUuidBtn:instantiate()
    repairUuidBtn.font = UIFont.Small
    repairUuidBtn.textColor = {r=1, g=1, b=1, a=1}
    repairUuidBtn.borderColor = {r=0.35, g=0.55, b=0.4, a=1}
    repairUuidBtn.backgroundColor = {r=0.16, g=0.32, b=0.22, a=1}
    panel:addChild(repairUuidBtn)

    local restoreUuidBtnX = repairUuidBtnX + repairUuidW + uuidBtnGap
    local restoreUuidBtn = ISButton:new(restoreUuidBtnX, y - 2, restoreUuidW, 20, "Mark Restored", self, BurdJournals.UI.DebugPanel.onJournalMarkRestoredByUUID)
    restoreUuidBtn:initialise()
    restoreUuidBtn:instantiate()
    restoreUuidBtn.font = UIFont.Small
    restoreUuidBtn.textColor = {r=1, g=1, b=1, a=1}
    restoreUuidBtn.borderColor = {r=0.55, g=0.45, b=0.3, a=1}
    restoreUuidBtn.backgroundColor = {r=0.32, g=0.24, b=0.15, a=1}
    panel:addChild(restoreUuidBtn)

    local uuidSecondRowY = y + 22
    local deleteUuidW = 70
    local normalizeUuidW = 92
    local deleteUuidX = padding + fullWidth - deleteUuidW
    local normalizeUuidX = deleteUuidX - uuidBtnGap - normalizeUuidW

    local normalizeUuidBtn = ISButton:new(normalizeUuidX, uuidSecondRowY, normalizeUuidW, 20, "Normalize XP", self, BurdJournals.UI.DebugPanel.onJournalNormalizeXPModeByUUID)
    normalizeUuidBtn:initialise()
    normalizeUuidBtn:instantiate()
    normalizeUuidBtn.font = UIFont.Small
    normalizeUuidBtn.textColor = {r=1, g=1, b=1, a=1}
    normalizeUuidBtn.borderColor = {r=0.35, g=0.45, b=0.6, a=1}
    normalizeUuidBtn.backgroundColor = {r=0.2, g=0.24, b=0.35, a=1}
    normalizeUuidBtn:setTooltip("Normalize journal XP mode by UUID (auto-detect absolute vs baseline mode).")
    panel:addChild(normalizeUuidBtn)

    local deleteUuidBtn = ISButton:new(deleteUuidX, uuidSecondRowY, deleteUuidW, 20, "Delete", self, BurdJournals.UI.DebugPanel.onJournalDeleteByUUIDPrompt)
    deleteUuidBtn:initialise()
    deleteUuidBtn:instantiate()
    deleteUuidBtn.font = UIFont.Small
    deleteUuidBtn.textColor = {r=1, g=1, b=1, a=1}
    deleteUuidBtn.borderColor = {r=0.7, g=0.35, b=0.35, a=1}
    deleteUuidBtn.backgroundColor = {r=0.38, g=0.16, b=0.16, a=1}
    deleteUuidBtn:setTooltip("Delete live journal item by UUID and purge debug/index cache records.")
    panel:addChild(deleteUuidBtn)
    y = y + 48

    panel.journalFocusedSkill = nil
    panel.journalTabState = {buttons = {}, panels = {}, current = "skills"}

    local journalTabWidth = 84
    local journalTabHeight = 22
    local journalTabSpacing = 6
    local journalTabX = padding
    panel.journalTabState.buttons.skills = createDebugButton(panel, journalTabX, y, journalTabWidth, journalTabHeight, getText("UI_BurdJournals_TabSkills") or "Skills", self, BurdJournals.UI.DebugPanel.onJournalSubTab, "skills")
    journalTabX = journalTabX + journalTabWidth + journalTabSpacing
    panel.journalTabState.buttons.traits = createDebugButton(panel, journalTabX, y, journalTabWidth, journalTabHeight, getText("UI_BurdJournals_TabTraits") or "Traits", self, BurdJournals.UI.DebugPanel.onJournalSubTab, "traits")
    journalTabX = journalTabX + journalTabWidth + journalTabSpacing
    panel.journalTabState.buttons.recipes = createDebugButton(panel, journalTabX, y, journalTabWidth, journalTabHeight, getText("UI_BurdJournals_TabRecipes") or "Recipes", self, BurdJournals.UI.DebugPanel.onJournalSubTab, "recipes")
    y = y + journalTabHeight + 8

    local utilityY = panel.height - padding - btnHeight
    local sectionHeight = math.max(220, utilityY - y - 8)
    local sectionPadding = 8
    local contentWidth = fullWidth - sectionPadding * 2
    local searchWidth = 150

    local skillsSection = createDebugSectionPanel(panel, padding, y, fullWidth, sectionHeight)
    panel.journalTabState.panels.skills = skillsSection
    local sy = sectionPadding
    local journalSkillsLabelText = (getText("UI_BurdJournals_TabSkills") or "Skills") .. " (Click squares to set level):"
    local skillsLabel = ISLabel:new(sectionPadding, sy + 2, 18, journalSkillsLabelText, 0.9, 0.9, 0.7, 1, UIFont.Small, true)
    skillsLabel:initialise()
    skillsLabel:instantiate()
    skillsSection:addChild(skillsLabel)

    local addSkillWidth = 76
    local searchGap = 6
    local journalSkillSearchX = math.max(300, contentWidth - (searchWidth + addSkillWidth + searchGap))
    panel.journalSkillSearchEntry = ISTextEntryBox:new("", journalSkillSearchX, sy, searchWidth, 20)
    panel.journalSkillSearchEntry:initialise()
    panel.journalSkillSearchEntry:instantiate()
    panel.journalSkillSearchEntry.font = UIFont.Small
    panel.journalSkillSearchEntry:setTooltip("Type to filter skills...")
    panel.journalSkillSearchEntry.onTextChange = function()
        BurdJournals.UI.DebugPanel.filterJournalSkillList(self)
    end
    skillsSection:addChild(panel.journalSkillSearchEntry)

    local addSkillBtn = createDebugButton(skillsSection, journalSkillSearchX + searchWidth + searchGap, sy, addSkillWidth, 20, "+ Add", self, BurdJournals.UI.DebugPanel.onJournalAddSkillPopup, nil, {r=0.3, g=0.5, b=0.4, a=1}, {r=0.2, g=0.35, b=0.25, a=1}, "Add a new skill to the selected journal.")
    addSkillBtn.font = UIFont.Small
    panel.journalSkillSourceFilter = createSectionSourceFilterStrip(skillsSection, self, journalSkillsLabelText, journalSkillSearchX, sy, sectionPadding, BurdJournals.UI.DebugPanel.filterJournalSkillList, "Filter journal skills by source.")
    sy = sy + 24

    local skillListHeight = math.max(96, sectionHeight - 116)
    panel.journalSkillList = ISScrollingListBox:new(sectionPadding, sy, contentWidth, skillListHeight)
    panel.journalSkillList:initialise()
    panel.journalSkillList:instantiate()
    panel.journalSkillList.itemheight = 24
    panel.journalSkillList.backgroundColor = {r=0.08, g=0.08, b=0.1, a=1}
    panel.journalSkillList.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    panel.journalSkillList.doDrawItem = BurdJournals.UI.DebugPanel.drawJournalSkillItem
    panel.journalSkillList.onMouseDown = BurdJournals.UI.DebugPanel.onJournalSkillListClick
    panel.journalSkillList.parentPanel = self
    skillsSection:addChild(panel.journalSkillList)
    sy = sy + skillListHeight + 6

    panel.journalXPLabel = ISLabel:new(sectionPadding, sy, 18, "Set XP:", 0.8, 0.8, 0.8, 1, UIFont.Small, true)
    panel.journalXPLabel:initialise()
    panel.journalXPLabel:instantiate()
    skillsSection:addChild(panel.journalXPLabel)

    panel.journalXPEntry = ISTextEntryBox:new("0", sectionPadding + 50, sy - 2, 70, 20)
    panel.journalXPEntry:initialise()
    panel.journalXPEntry:instantiate()
    panel.journalXPEntry.font = UIFont.Small
    panel.journalXPEntry:setOnlyNumbers(true)
    panel.journalXPEntry.backgroundColor = {r=0.15, g=0.15, b=0.18, a=1}
    panel.journalXPEntry.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    skillsSection:addChild(panel.journalXPEntry)

    panel.journalSkillNameLabel = ISLabel:new(sectionPadding + 125, sy, 18, "Select a skill below", 0.5, 0.6, 0.7, 1, UIFont.Small, true)
    panel.journalSkillNameLabel:initialise()
    panel.journalSkillNameLabel:instantiate()
    skillsSection:addChild(panel.journalSkillNameLabel)

    panel.journalDRLabel = ISLabel:new(sectionPadding + 125, sy + 12, 16, "Recovery: --", 0.55, 0.62, 0.72, 1, UIFont.Small, true)
    panel.journalDRLabel:initialise()
    panel.journalDRLabel:instantiate()
    skillsSection:addChild(panel.journalDRLabel)

    local skillActionSpacing = 6
    local setXPBtnWidth = 50
    local removeSkillBtnWidth = 55
    local skillActionX = contentWidth - (setXPBtnWidth + removeSkillBtnWidth + skillActionSpacing)

    local setXPBtn = ISButton:new(skillActionX, sy - 2, setXPBtnWidth, 20, "Set", self, BurdJournals.UI.DebugPanel.onJournalSetXP)
    setXPBtn:initialise()
    setXPBtn:instantiate()
    setXPBtn.font = UIFont.Small
    setXPBtn.textColor = {r=1, g=1, b=1, a=1}
    setXPBtn.borderColor = {r=0.3, g=0.5, b=0.4, a=1}
    setXPBtn.backgroundColor = {r=0.2, g=0.3, b=0.25, a=1}
    skillsSection:addChild(setXPBtn)

    local removeSkillBtn = ISButton:new(skillActionX + setXPBtnWidth + skillActionSpacing, sy - 2, removeSkillBtnWidth, 20, "Remove", self, BurdJournals.UI.DebugPanel.onJournalRemoveSkill)
    removeSkillBtn:initialise()
    removeSkillBtn:instantiate()
    removeSkillBtn.font = UIFont.Small
    removeSkillBtn.textColor = {r=1, g=1, b=1, a=1}
    removeSkillBtn.borderColor = {r=0.5, g=0.3, b=0.3, a=1}
    removeSkillBtn.backgroundColor = {r=0.35, g=0.15, b=0.15, a=1}
    skillsSection:addChild(removeSkillBtn)
    sy = sy + 28

    panel.journalDRStepLabel = ISLabel:new(sectionPadding, sy, 16, "Times Reclaimed:", 0.75, 0.8, 0.9, 1, UIFont.Small, true)
    panel.journalDRStepLabel:initialise()
    panel.journalDRStepLabel:instantiate()
    skillsSection:addChild(panel.journalDRStepLabel)

    panel.journalDRStepEntry = ISTextEntryBox:new("0", sectionPadding + 96, sy - 2, 60, 20)
    panel.journalDRStepEntry:initialise()
    panel.journalDRStepEntry:instantiate()
    panel.journalDRStepEntry.font = UIFont.Small
    panel.journalDRStepEntry:setOnlyNumbers(true)
    panel.journalDRStepEntry.backgroundColor = {r=0.15, g=0.15, b=0.18, a=1}
    panel.journalDRStepEntry.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    skillsSection:addChild(panel.journalDRStepEntry)

    local setDRStepBtn = ISButton:new(sectionPadding + 160, sy - 2, 52, 20, "Apply", self, BurdJournals.UI.DebugPanel.onJournalSetDRStep)
    setDRStepBtn:initialise()
    setDRStepBtn:instantiate()
    setDRStepBtn.font = UIFont.Small
    setDRStepBtn.textColor = {r=1, g=1, b=1, a=1}
    setDRStepBtn.borderColor = {r=0.3, g=0.5, b=0.4, a=1}
    setDRStepBtn.backgroundColor = {r=0.2, g=0.3, b=0.25, a=1}
    skillsSection:addChild(setDRStepBtn)
    panel.journalDRSetBtn = setDRStepBtn

    local decDRBtn = ISButton:new(sectionPadding + 216, sy - 2, 36, 20, "-1", self, BurdJournals.UI.DebugPanel.onJournalDecrementDRStep)
    decDRBtn:initialise()
    decDRBtn:instantiate()
    decDRBtn.font = UIFont.Small
    decDRBtn.textColor = {r=1, g=1, b=1, a=1}
    decDRBtn.borderColor = {r=0.55, g=0.42, b=0.35, a=1}
    decDRBtn.backgroundColor = {r=0.34, g=0.23, b=0.2, a=1}
    skillsSection:addChild(decDRBtn)
    panel.journalDRDecBtn = decDRBtn

    local incDRBtn = ISButton:new(sectionPadding + 256, sy - 2, 36, 20, "+1", self, BurdJournals.UI.DebugPanel.onJournalIncrementDRStep)
    incDRBtn:initialise()
    incDRBtn:instantiate()
    incDRBtn.font = UIFont.Small
    incDRBtn.textColor = {r=1, g=1, b=1, a=1}
    incDRBtn.borderColor = {r=0.35, g=0.45, b=0.55, a=1}
    incDRBtn.backgroundColor = {r=0.2, g=0.26, b=0.34, a=1}
    skillsSection:addChild(incDRBtn)
    panel.journalDRIncBtn = incDRBtn

    local resetDRBtn = ISButton:new(sectionPadding + 296, sy - 2, 88, 20, "Reset History", self, BurdJournals.UI.DebugPanel.onJournalResetDR)
    resetDRBtn:initialise()
    resetDRBtn:instantiate()
    resetDRBtn.font = UIFont.Small
    resetDRBtn.textColor = {r=1, g=1, b=1, a=1}
    resetDRBtn.borderColor = {r=0.5, g=0.35, b=0.25, a=1}
    resetDRBtn.backgroundColor = {r=0.3, g=0.2, b=0.12, a=1}
    skillsSection:addChild(resetDRBtn)
    panel.journalDRResetBtn = resetDRBtn

    panel.journalDRHintLabel = ISLabel:new(sectionPadding + 390, sy, 16, "", 0.55, 0.62, 0.72, 1, UIFont.Small, true)
    panel.journalDRHintLabel:initialise()
    panel.journalDRHintLabel:instantiate()
    skillsSection:addChild(panel.journalDRHintLabel)
    sy = sy + 26

    panel.journalDRPreviewLabel = ISLabel:new(sectionPadding + 125, sy - 2, 16, getText("UI_BurdJournals_DebugReclaimPreviewEmpty"), 0.65, 0.75, 0.85, 1, UIFont.Small, true)
    panel.journalDRPreviewLabel:initialise()
    panel.journalDRPreviewLabel:instantiate()
    skillsSection:addChild(panel.journalDRPreviewLabel)

    local traitsSection = createDebugSectionPanel(panel, padding, y, fullWidth, sectionHeight)
    panel.journalTabState.panels.traits = traitsSection
    local ty = sectionPadding
    local journalTraitsLabelText = getText("UI_BurdJournals_TabTraits") or "Traits"
    local journalTraitLabelX = sectionPadding + 58
    panel.journalTraitBulkTick = createDebugBulkTick(traitsSection, sectionPadding, ty - 1, 52, 20, "All", self, BurdJournals.UI.DebugPanel.onJournalTraitBulkToggle, "Store or remove all visible non-passive traits.")
    local traitsLabel = ISLabel:new(journalTraitLabelX, ty + 2, 18, journalTraitsLabelText, 0.9, 0.9, 0.7, 1, UIFont.Small, true)
    traitsLabel:initialise()
    traitsLabel:instantiate()
    traitsSection:addChild(traitsLabel)

    local journalTraitSearchX = math.max(220, contentWidth - 156)
    panel.journalTraitSearchEntry = ISTextEntryBox:new("", journalTraitSearchX, ty, 150, 20)
    panel.journalTraitSearchEntry:initialise()
    panel.journalTraitSearchEntry:instantiate()
    panel.journalTraitSearchEntry.font = UIFont.Small
    panel.journalTraitSearchEntry:setTooltip("Filter traits...")
    panel.journalTraitSearchEntry.onTextChange = function()
        BurdJournals.UI.DebugPanel.filterJournalTraitList(self)
    end
    traitsSection:addChild(panel.journalTraitSearchEntry)
    panel.journalTraitPolarityFilter = createDebugTraitPolarityFilter(traitsSection, math.max(sectionPadding, journalTraitSearchX - 92), ty, self, BurdJournals.UI.DebugPanel.filterJournalTraitList, "Filter journal traits by positive/negative polarity.")
    panel.journalTraitSourceFilter = createSectionSourceFilterStrip(traitsSection, self, journalTraitsLabelText, journalTraitSearchX, ty, sectionPadding, BurdJournals.UI.DebugPanel.filterJournalTraitList, "Filter journal traits by source.", journalTraitLabelX)
    ty = ty + 24

    local traitListHeight = math.max(120, sectionHeight - 32)
    panel.journalTraitList = ISScrollingListBox:new(sectionPadding, ty, contentWidth, traitListHeight)
    panel.journalTraitList:initialise()
    panel.journalTraitList:instantiate()
    panel.journalTraitList.itemheight = 24
    panel.journalTraitList.backgroundColor = {r=0.08, g=0.08, b=0.1, a=1}
    panel.journalTraitList.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    panel.journalTraitList.doDrawItem = BurdJournals.UI.DebugPanel.drawJournalTraitItem
    panel.journalTraitList.onMouseDown = BurdJournals.UI.DebugPanel.onJournalTraitListClick
    panel.journalTraitList.parentPanel = self
    traitsSection:addChild(panel.journalTraitList)

    local recipesSection = createDebugSectionPanel(panel, padding, y, fullWidth, sectionHeight)
    panel.journalTabState.panels.recipes = recipesSection
    local ry = sectionPadding
    local journalRecipesLabelText = getText("UI_BurdJournals_TabRecipes") or "Recipes"
    local journalRecipeLabelX = sectionPadding + 58
    panel.journalRecipeBulkTick = createDebugBulkTick(recipesSection, sectionPadding, ry - 1, 52, 20, "All", self, BurdJournals.UI.DebugPanel.onJournalRecipeBulkToggle, "Store or remove all visible recipes.")
    local recipesLabel = ISLabel:new(journalRecipeLabelX, ry + 2, 18, journalRecipesLabelText, 0.9, 0.9, 0.7, 1, UIFont.Small, true)
    recipesLabel:initialise()
    recipesLabel:instantiate()
    recipesSection:addChild(recipesLabel)

    local journalRecipeSearchX = math.max(220, contentWidth - 156)
    panel.journalRecipeSearchEntry = ISTextEntryBox:new("", journalRecipeSearchX, ry, 150, 20)
    panel.journalRecipeSearchEntry:initialise()
    panel.journalRecipeSearchEntry:instantiate()
    panel.journalRecipeSearchEntry.font = UIFont.Small
    panel.journalRecipeSearchEntry:setTooltip("Filter recipes...")
    panel.journalRecipeSearchEntry.onTextChange = function()
        BurdJournals.UI.DebugPanel.filterJournalRecipeList(self)
    end
    recipesSection:addChild(panel.journalRecipeSearchEntry)
    panel.journalRecipeSourceFilter = createSectionSourceFilterStrip(recipesSection, self, journalRecipesLabelText, journalRecipeSearchX, ry, sectionPadding, BurdJournals.UI.DebugPanel.filterJournalRecipeList, "Filter journal recipes by source.", journalRecipeLabelX)
    ry = ry + 24

    local recipeListHeight = math.max(120, sectionHeight - 32)
    panel.journalRecipeList = ISScrollingListBox:new(sectionPadding, ry, contentWidth, recipeListHeight)
    panel.journalRecipeList:initialise()
    panel.journalRecipeList:instantiate()
    panel.journalRecipeList.itemheight = 30
    panel.journalRecipeList.backgroundColor = {r=0.08, g=0.08, b=0.1, a=1}
    panel.journalRecipeList.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    panel.journalRecipeList.doDrawItem = BurdJournals.UI.DebugPanel.drawJournalRecipeItem
    panel.journalRecipeList.onMouseDown = BurdJournals.UI.DebugPanel.onJournalRecipeListClick
    panel.journalRecipeList.parentPanel = self
    recipesSection:addChild(panel.journalRecipeList)

    local editorBtnWidth = 112
    local editorBtnSpacing = 6
    local editorBtnX = padding
    createDebugButton(panel, editorBtnX, utilityY, editorBtnWidth, btnHeight, "Clear " .. (getText("UI_BurdJournals_TabSkills") or "Skills"), self, BurdJournals.UI.DebugPanel.onJournalCmd, "clearskills", {r=0.5, g=0.3, b=0.3, a=1}, {r=0.35, g=0.15, b=0.15, a=1})
    editorBtnX = editorBtnX + editorBtnWidth + editorBtnSpacing
    createDebugButton(panel, editorBtnX, utilityY, editorBtnWidth, btnHeight, "Clear " .. (getText("UI_BurdJournals_TabTraits") or "Traits"), self, BurdJournals.UI.DebugPanel.onJournalCmd, "cleartraits", {r=0.5, g=0.3, b=0.3, a=1}, {r=0.35, g=0.15, b=0.15, a=1})
    editorBtnX = editorBtnX + editorBtnWidth + editorBtnSpacing
    createDebugButton(panel, editorBtnX, utilityY, editorBtnWidth, btnHeight, "Clear " .. (getText("UI_BurdJournals_TabRecipes") or "Recipes"), self, BurdJournals.UI.DebugPanel.onJournalCmd, "clearrecipes", {r=0.5, g=0.3, b=0.3, a=1}, {r=0.35, g=0.15, b=0.15, a=1})
    editorBtnX = editorBtnX + editorBtnWidth + editorBtnSpacing
    createDebugButton(panel, editorBtnX, utilityY, 74, btnHeight, "Refresh", self, BurdJournals.UI.DebugPanel.onJournalRefresh)
    editorBtnX = editorBtnX + 74 + editorBtnSpacing
    createDebugButton(panel, editorBtnX, utilityY, 88, btnHeight, debugText("UI_BurdJournals_DebugJournalExportJSON", "Export JSON"), self, BurdJournals.UI.DebugPanel.onJournalExportJSON, nil, {r=0.35, g=0.5, b=0.65, a=1}, {r=0.14, g=0.24, b=0.32, a=1}, debugText("UI_BurdJournals_DebugJournalExportTooltip", "Export the selected journal as portable JSON."))
    editorBtnX = editorBtnX + 88 + editorBtnSpacing
    createDebugButton(panel, editorBtnX, utilityY, 88, btnHeight, debugText("UI_BurdJournals_DebugJournalImportJSON", "Import JSON"), self, BurdJournals.UI.DebugPanel.onJournalImportJSON, nil, {r=0.35, g=0.55, b=0.45, a=1}, {r=0.14, g=0.28, b=0.2, a=1}, debugText("UI_BurdJournals_DebugJournalImportTooltip", "Import JSON into the selected journal, or spawn one if none is selected."))

    setDebugSubTabState(panel.journalTabState, "skills")

    -- Store reference
    self.journalPanel = panel
    self:updateJournalEditorMetaVisibility()
    self:updateJournalTargetSummary()
end

local function getSelectedJournalOwnerData(panel)
    if not panel or not panel.journalOwnerCombo then
        return nil
    end
    local selected = panel.journalOwnerCombo.selected or 1
    return panel.journalOwnerCombo:getOptionData(selected)
end

local function trimJournalEditorText(value)
    local text = tostring(value or "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

function BurdJournals.UI.DebugPanel:updateJournalEditorMetaVisibility()
    local panel = self.journalPanel
    if not panel then
        return
    end

    local selectedType = getJournalEditTypeFromCombo(panel)
    local isFilled = selectedType == "filled"
    local ownerSelection = getSelectedJournalOwnerData(panel)
    local useCustomAuthor = (not isFilled) or (ownerSelection and ownerSelection.isCustom == true)

    if panel.journalOwnerLabel then
        local labelText = isFilled
            and ((BurdJournals.safeGetText and BurdJournals.safeGetText("UI_BurdJournals_DebugSpawnOwnerAssign", "Assign to Player:")) or "Assign to Player:")
            or "Author:"
        panel.journalOwnerLabel:setName(labelText)
    end
    if panel.journalOwnerCombo then
        panel.journalOwnerCombo:setVisible(isFilled)
    end
    if panel.journalOwnerCustomEntry then
        panel.journalOwnerCustomEntry:setVisible(useCustomAuthor)
    end
end

function BurdJournals.UI.DebugPanel:onJournalTypeChange(combo)
    local panel = self.journalPanel
    if not panel then
        return
    end
    local selectedType = getJournalEditTypeFromCombo(panel)
    panel.journalEditType = selectedType
    self:updateJournalEditorMetaVisibility()
    self:setStatus("Journal type set to " .. tostring(selectedType) .. " (pending apply)", {r=0.88, g=0.78, b=0.42})
end

function BurdJournals.UI.DebugPanel:onJournalOwnerChange(combo)
    self:updateJournalEditorMetaVisibility()
end

function BurdJournals.UI.DebugPanel:onJournalProfileChange(combo)
    local panel = self.journalPanel
    if not panel then
        return
    end
    local profile = getJournalProfileFromCombo(panel)
    panel.journalProfile = profile
    local label = (profile == "debug") and "Debug" or "Normal"
    self:setStatus("Journal profile set to " .. label .. " (pending apply)", {r=0.88, g=0.78, b=0.42})
end

function BurdJournals.UI.DebugPanel:onJournalOriginChange(combo)
    local panel = self.journalPanel
    if not panel then
        return
    end
    local originMode = getJournalOriginFromCombo(panel)
    panel.journalOriginMode = originMode
    self:setStatus("Journal origin set to " .. getOriginModeLabel(originMode) .. " (pending apply)", {r=0.88, g=0.78, b=0.42})
end

function BurdJournals.UI.DebugPanel:onJournalApplyMetadata()
    local panel = self.journalPanel
    local journal = self.editingJournal
    if not panel or not journal then
        self:setStatus("No journal selected", {r=1, g=0.6, b=0.3})
        return
    end

    local selectedType = getJournalEditTypeFromCombo(panel)
    local profile = getJournalProfileFromCombo(panel)
    local originMode = getJournalOriginFromCombo(panel)
    local desiredItemType = getEditorItemTypeForJournalType(selectedType)
    local currentItemType = journal.getFullType and journal:getFullType() or nil
    local shouldConvertItemType = desiredItemType ~= nil and currentItemType ~= nil and desiredItemType ~= currentItemType
    local useDebugProfile = profile == "debug"

    if journal.__bsjServerProxy and shouldConvertItemType then
        self:setStatus("Type conversion requires a live journal item (not server snapshot).", {r=1, g=0.6, b=0.3})
        return
    end

    local modData = journal:getModData()
    modData.BurdJournals = modData.BurdJournals or {}
    local data = modData.BurdJournals

    data.isDebugSpawned = useDebugProfile
    data.isDebugEdited = useDebugProfile and true or nil
    applyOriginModeToJournalData(data, originMode)

    local preservedCursedReward = data.isCursedReward == true
    local preservedCursedEffectType = data.cursedEffectType
    local preservedCursedByCharacter = data.cursedUnleashedByCharacterId
    local preservedCursedByUsername = data.cursedUnleashedByUsername
    local preservedCursedAtHours = data.cursedUnleashedAtHours

    -- Normalize type markers before applying selected journal type.
    data.isWorn = nil
    data.isBloody = nil
    data.wasFromWorn = nil
    data.wasFromBloody = nil
    data.isCursedJournal = nil
    data.isCursedReward = nil
    data.cursedEffectType = nil
    data.cursedUnleashedByCharacterId = nil
    data.cursedUnleashedByUsername = nil
    data.cursedUnleashedAtHours = nil
    data.cursedPendingRewards = nil

    if selectedType == "worn" then
        data.isWorn = true
        data.wasFromWorn = true
    elseif selectedType == "bloody" then
        data.isBloody = true
        data.wasFromBloody = true
        if preservedCursedReward then
            data.isCursedReward = true
            data.cursedState = "unleashed"
            data.cursedEffectType = preservedCursedEffectType
            data.cursedUnleashedByCharacterId = preservedCursedByCharacter
            data.cursedUnleashedByUsername = preservedCursedByUsername
            data.cursedUnleashedAtHours = preservedCursedAtHours
        end
    elseif selectedType == "cursed" then
        data.isCursedJournal = true
        data.isCursedReward = false
        data.cursedState = (data.cursedState == "unleashed") and "unleashed" or "dormant"
    else
        if selectedType ~= "blank" then
            data.cursedState = nil
            data.cursedEffectType = nil
        end
    end

    if selectedType == "blank" then
        data.isWritten = nil
    else
        data.isWritten = true
    end

    -- Owner/author assignment is type-aware.
    data.ownerMode = "none"
    data.ownerSteamId = nil
    data.ownerUsername = nil
    data.ownerCharacterName = nil
    data.author = nil

    if selectedType == "filled" then
        local ownerData = getSelectedJournalOwnerData(panel)
        if ownerData and ownerData.isPlayer then
            data.ownerMode = "player_assignment"
            data.ownerSteamId = ownerData.steamId
            data.ownerUsername = ownerData.username
            data.ownerCharacterName = ownerData.characterName
            data.author = ownerData.characterName
        elseif ownerData and ownerData.isCustom then
            local customAuthor = trimJournalEditorText(panel.journalOwnerCustomEntry and panel.journalOwnerCustomEntry:getText() or "")
            if customAuthor ~= "" then
                data.ownerMode = "custom"
                data.ownerCharacterName = customAuthor
                data.author = customAuthor
            end
        end
    else
        local authorText = trimJournalEditorText(panel.journalOwnerCustomEntry and panel.journalOwnerCustomEntry:getText() or "")
        if authorText ~= "" then
            data.ownerMode = "player_author"
            data.ownerCharacterName = authorText
            data.author = authorText
        end
    end

    local flavorText = trimJournalEditorText(panel.journalFlavorEntry and panel.journalFlavorEntry:getText() or "")
    data.flavorText = (flavorText ~= "") and flavorText or nil

    if panel.journalAgeEntry and panel.journalAgeEntry.getText then
        local ageHours = math.max(0, tonumber(panel.journalAgeEntry:getText() or "0") or 0)
        local worldAge = (getGameTime and getGameTime() and getGameTime():getWorldAgeHours()) or 0
        data.timestamp = math.max(0, tonumber(worldAge) - ageHours)
    end

    local extraPayload = nil
    if shouldConvertItemType then
        extraPayload = {
            desiredJournalType = selectedType,
            desiredItemType = desiredItemType
        }
    end

    BurdJournals.UI.DebugPanel.finalizeJournalEdit(journal, {
        profile = profile,
        originMode = originMode,
        extraPayload = extraPayload
    })

    -- Rebind to live item by UUID in case server replaced item type.
    self:refreshJournalPickerList(true)
    if panel.journalSelectCombo and (panel.journalSelectCombo.selected or 0) > 1 then
        self:onJournalUseDropdownSelection()
    end
    self:refreshJournalEditorData()

    self:setStatus(
        "Applied metadata: "
            .. tostring(selectedType)
            .. " | "
            .. ((profile == "debug") and "Debug" or "Normal")
            .. " | "
            .. getOriginModeLabel(originMode),
        {r=0.3, g=1, b=0.5}
    )
end

function BurdJournals.UI.DebugPanel:onJournalApplyProfile()
    self:onJournalApplyMetadata()
end

function BurdJournals.UI.DebugPanel:onJournalConvertToNormal()
    local panel = self.journalPanel
    if not panel or not panel.journalProfileCombo then
        self:setStatus("Profile controls unavailable", {r=1, g=0.6, b=0.3})
        return
    end
    setJournalProfileCombo(panel, "normal")
    self:onJournalApplyMetadata()
end

function BurdJournals.UI.DebugPanel:onJournalConvertToDebug()
    local panel = self.journalPanel
    if not panel or not panel.journalProfileCombo then
        self:setStatus("Profile controls unavailable", {r=1, g=0.6, b=0.3})
        return
    end
    setJournalProfileCombo(panel, "debug")
    self:onJournalApplyMetadata()
end

-- Filter journal skill list by search text
function BurdJournals.UI.DebugPanel.filterJournalSkillList(self)
    local panel = self.journalPanel
    if not panel or not panel.journalSkillSearchEntry or not panel.journalSkillList then return end
    
    local searchText = panel.journalSkillSearchEntry:getText() or ""
    local selectedSourceId = panel.journalSkillSourceFilter and panel.journalSkillSourceFilter.selectedSourceId or "all"
    
    applyDebugRowFilter(panel.journalSkillList, function(row)
        local matchesSearch = searchText == "" or debugSearchMatches(searchText, row.displayName, row.name, row.category, row.source)
        local matchesSource = debugRowMatchesSourceFilter(row, selectedSourceId)
        return matchesSearch and matchesSource
    end)
end

function BurdJournals.UI.DebugPanel.filterJournalTraitList(self)
    local panel = self.journalPanel
    if not panel or not panel.journalTraitSearchEntry or not panel.journalTraitList then return end
    
    local searchText = panel.journalTraitSearchEntry:getText() or ""
    local selectedSourceId = panel.journalTraitSourceFilter and panel.journalTraitSourceFilter.selectedSourceId or "all"
    local selectedPolarity = getDebugTraitPolarityFilterValue(panel.journalTraitPolarityFilter)
    
    applyDebugRowFilter(panel.journalTraitList, function(row)
        local matchesSearch = searchText == "" or debugSearchMatches(searchText, row.displayName, row.id, row.source)
        local matchesSource = debugRowMatchesSourceFilter(row, selectedSourceId)
        local matchesPolarity = debugRowMatchesTraitPolarityFilter(row, selectedPolarity)
        return matchesSearch and matchesSource and matchesPolarity
    end)
    BurdJournals.UI.DebugPanel.refreshJournalBulkToggles(self)
end

function BurdJournals.UI.DebugPanel.filterJournalRecipeList(self)
    local panel = self.journalPanel
    if not panel or not panel.journalRecipeSearchEntry or not panel.journalRecipeList then return end
    
    local searchText = panel.journalRecipeSearchEntry:getText() or ""
    local selectedSourceId = panel.journalRecipeSourceFilter and panel.journalRecipeSourceFilter.selectedSourceId or "all"
    
    applyDebugRowFilter(panel.journalRecipeList, function(row)
        local matchesSearch = searchText == "" or debugSearchMatches(searchText, row.displayName, row.name, row.magazineSource, row.magazineDisplayName, row.source)
        local matchesSource = debugRowMatchesSourceFilter(row, selectedSourceId)
        return matchesSearch and matchesSource
    end)
    BurdJournals.UI.DebugPanel.refreshJournalBulkToggles(self)
end

local function getJournalAuthorForPicker(journalData)
    if not journalData or type(journalData) ~= "table" then
        return "Unknown"
    end
    return tostring(
        journalData.ownerCharacterName
        or journalData.author
        or journalData.ownerUsername
        or journalData.restoredBy
        or "Unknown"
    )
end

local function addJournalPickerEntry(entries, seenKeys, item)
    if not item or not item.getFullType then return end

    local fullType = item:getFullType()
    if not fullType then return end
    if not (
        string.find(fullType, "SurvivalJournal")
        or string.find(fullType, "BloodyJournal")
        or string.find(fullType, "WornJournal")
    ) then
        return
    end

    local journalData = BurdJournals.getJournalData and BurdJournals.getJournalData(item) or nil
    if type(journalData) ~= "table" then
        return
    end

    local uuid = tostring(journalData.uuid or "")
    local key
    if uuid ~= "" then
        key = "uuid:" .. uuid
    elseif item.getID then
        key = "id:" .. tostring(item:getID())
    else
        key = "item:" .. tostring(item)
    end
    if seenKeys[key] then
        return
    end
    seenKeys[key] = true

    local journalName = tostring((item.getName and item:getName()) or "Journal")
    local author = getJournalAuthorForPicker(journalData)
    local uuidDisplay = (uuid ~= "" and uuid) or "No UUID"
    local display = journalName .. " | " .. author .. " | " .. uuidDisplay

    table.insert(entries, {
        journal = item,
        uuid = uuid,
        name = journalName,
        author = author,
        display = display
    })
end

local function collectJournalsFromContainer(container, entries, seenKeys)
    if not container then return end
    local items = container.getItems and container:getItems() or nil
    if not items then return end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            addJournalPickerEntry(entries, seenKeys, item)
            if item.getInventory then
                local childInventory = item:getInventory()
                if childInventory then
                    collectJournalsFromContainer(childInventory, entries, seenKeys)
                end
            end
        end
    end
end

function BurdJournals.UI.DebugPanel.collectSelectableJournals(player)
    local entries = {}
    local seenKeys = {}
    if not player then
        return entries
    end

    local inventory = player:getInventory()
    if inventory then
        collectJournalsFromContainer(inventory, entries, seenKeys)
    end

    if getPlayerLoot and not isServer() then
        local playerNum = player:getPlayerNum()
        if playerNum then
            local lootPanel = getPlayerLoot(playerNum)
            if lootPanel and lootPanel.inventoryPane and lootPanel.inventoryPane.inventories then
                for i = 1, #lootPanel.inventoryPane.inventories do
                    local containerInfo = lootPanel.inventoryPane.inventories[i]
                    if containerInfo and containerInfo.inventory then
                        collectJournalsFromContainer(containerInfo.inventory, entries, seenKeys)
                    end
                end
            end
        end
    end

    local square = player:getCurrentSquare()
    if square and getCell then
        for dx = -1, 1 do
            for dy = -1, 1 do
                local nearSquare = getCell():getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ())
                if nearSquare then
                    local objects = nearSquare:getObjects()
                    if objects then
                        for i = 0, objects:size() - 1 do
                            local obj = objects:get(i)
                            if obj and obj.getContainer then
                                local container = obj:getContainer()
                                if container then
                                    collectJournalsFromContainer(container, entries, seenKeys)
                                end
                            end
                            if obj and obj.getInventory then
                                local inv = obj:getInventory()
                                if inv then
                                    collectJournalsFromContainer(inv, entries, seenKeys)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(entries, function(a, b)
        return string.lower(a.display) < string.lower(b.display)
    end)
    return entries
end

function BurdJournals.UI.DebugPanel:refreshJournalPickerList(keepSelection)
    local panel = self.journalPanel
    if not panel or not panel.journalSelectCombo then return end

    local selectedUuid = nil
    if keepSelection and panel.journalSelectCombo.selected and panel.journalSelectCombo.selected > 1 then
        local selectedData = panel.journalSelectCombo:getOptionData(panel.journalSelectCombo.selected)
        selectedUuid = selectedData and selectedData.uuid or nil
    end
    if (not selectedUuid or selectedUuid == "") and self.editingJournal and BurdJournals.getJournalData then
        local currentData = BurdJournals.getJournalData(self.editingJournal)
        if currentData and currentData.uuid then
            selectedUuid = tostring(currentData.uuid)
        end
    end

    local entries = BurdJournals.UI.DebugPanel.collectSelectableJournals(self.player)
    panel.journalPickerEntries = entries

    panel.journalSelectCombo:clear()
    panel.journalSelectCombo:addOptionWithData("Select journal...", nil)

    local selectedIndex = 1
    for i, entry in ipairs(entries) do
        panel.journalSelectCombo:addOptionWithData(entry.display, entry)
        if selectedUuid and selectedUuid ~= "" and entry.uuid == selectedUuid then
            selectedIndex = i + 1
        end
    end
    panel.journalSelectCombo.selected = selectedIndex

    if panel.journalSelectCombo.selected and panel.journalSelectCombo.selected > 1 then
        BurdJournals.UI.DebugPanel.onJournalPickerChanged(self, panel.journalSelectCombo)
    end
end

function BurdJournals.UI.DebugPanel:onJournalRefreshList()
    self:refreshJournalPickerList(true)
    local panel = self.journalPanel
    local count = panel and panel.journalPickerEntries and #panel.journalPickerEntries or 0
    self:setStatus("Journal list refreshed (" .. tostring(count) .. " found)", {r=0.5, g=0.8, b=1})
end

function BurdJournals.UI.DebugPanel:onJournalPickerChanged(combo)
    local panel = self.journalPanel
    if not panel or not panel.journalUUIDEntry or not combo then return end
    local selectedData = combo.selected and combo.selected > 1 and combo:getOptionData(combo.selected) or nil
    panel.journalUUIDEntry:setText(selectedData and tostring(selectedData.uuid or "") or "")
end

function BurdJournals.UI.DebugPanel:onJournalUseDropdownSelection()
    local panel = self.journalPanel
    if not panel or not panel.journalSelectCombo then return end

    local selectedIndex = panel.journalSelectCombo.selected or 0
    if selectedIndex <= 1 then
        self:setStatus("Select a journal from the dropdown first", {r=1, g=0.6, b=0.3})
        return
    end

    local selectedData = panel.journalSelectCombo:getOptionData(selectedIndex)
    if not selectedData then
        self:setStatus("Selected journal entry is unavailable", {r=1, g=0.6, b=0.3})
        return
    end

    if selectedData.journal then
        self.editingJournal = selectedData.journal
        self:refreshJournalEditorData()
        self:setStatus("Selected: " .. tostring(selectedData.name or "Journal"), {r=0.3, g=1, b=0.5})
        return
    end

    if selectedData.uuid and selectedData.uuid ~= "" then
        panel.journalUUIDEntry:setText(selectedData.uuid)
        self:onJournalFindByUUID()
        return
    end

    self:setStatus("Selected entry cannot be resolved", {r=1, g=0.6, b=0.3})
end

local function getServerIndexDisplayName(entry)
    local itemName = entry and entry.itemName
    if type(itemName) == "string" and itemName ~= "" then
        return itemName
    end

    local itemType = tostring(entry and entry.itemType or "")
    if itemType:find("_Bloody") or entry.wasFromBloody then
        return getText("Tooltip_BurdJournals_BloodyJournal")
    end
    if itemType:find("_Worn") or entry.wasFromWorn then
        return getText("Tooltip_BurdJournals_WornJournal")
    end
    if entry and entry.isPlayerCreated == true then
        return getText("Tooltip_BurdJournals_PersonalJournal")
    end
    if itemType ~= "" then
        local short = itemType:match("^.+%.(.+)$")
        if short and short ~= "" then
            return short
        end
    end
    return getText("UI_BurdJournals_DebugJournalTypeGeneric")
end

local function getServerIndexDisplayText(entry)
    local name = getServerIndexDisplayName(entry)
    local author = tostring((entry and (entry.ownerCharacterName or entry.ownerUsername)) or "Unknown")
    local uuid = tostring((entry and entry.uuid) or "No UUID")
    return name .. " | " .. author .. " | " .. uuid
end

function BurdJournals.UI.DebugPanel:applyServerJournalIndexList(entries, meta)
    local panel = self.journalPanel
    if not panel or not panel.journalServerIndexCombo then return end

    local selectedUuid = nil
    if panel.journalServerIndexCombo.selected and panel.journalServerIndexCombo.selected > 1 then
        local selectedData = panel.journalServerIndexCombo:getOptionData(panel.journalServerIndexCombo.selected)
        selectedUuid = selectedData and selectedData.uuid or nil
    end
    if (not selectedUuid or selectedUuid == "") and panel.journalUUIDEntry then
        selectedUuid = tostring(panel.journalUUIDEntry:getText() or "")
    end

    local normalizedEntries = entries
    if type(normalizedEntries) ~= "table" and BurdJournals.normalizeTable then
        normalizedEntries = BurdJournals.normalizeTable(normalizedEntries)
    end
    if type(normalizedEntries) ~= "table" then
        normalizedEntries = {}
    end

    panel.journalServerIndexEntries = {}
    for _, entry in pairs(normalizedEntries) do
        if type(entry) == "table" and entry.uuid then
            entry.display = getServerIndexDisplayText(entry)
            table.insert(panel.journalServerIndexEntries, entry)
        end
    end

    table.sort(panel.journalServerIndexEntries, function(a, b)
        local ats = tonumber(a.lastSeenTs) or 0
        local bts = tonumber(b.lastSeenTs) or 0
        if ats ~= bts then return ats > bts end
        return tostring(a.uuid or "") < tostring(b.uuid or "")
    end)

    panel.journalServerIndexCombo:clear()
    panel.journalServerIndexCombo:addOptionWithData("Server index...", nil)

    local selectedIndex = 1
    for i, entry in ipairs(panel.journalServerIndexEntries) do
        panel.journalServerIndexCombo:addOptionWithData(entry.display, entry)
        if selectedUuid and selectedUuid ~= "" and tostring(entry.uuid) == tostring(selectedUuid) then
            selectedIndex = i + 1
        end
    end
    panel.journalServerIndexCombo.selected = selectedIndex

    if meta then
        local count = tonumber(meta.count) or #panel.journalServerIndexEntries
        local total = tonumber(meta.total) or count
        if meta.truncated then
            self:setStatus("Server index loaded " .. tostring(count) .. "/" .. tostring(total) .. " (truncated)", {r=0.95, g=0.8, b=0.35})
        else
            self:setStatus("Server index loaded (" .. tostring(count) .. " entries)", {r=0.5, g=0.8, b=1})
        end
    end
end

function BurdJournals.UI.DebugPanel:onJournalRefreshServerIndex()
    if sendClientCommand and isClient and isClient() then
        sendClientCommand("BurdJournals", "debugListJournalUUIDIndex", {maxEntries = 500})
        self:setStatus("Fetching server journal index...", {r=0.5, g=0.8, b=1})
        return
    end

    local cache = ModData.getOrCreate and ModData.getOrCreate("BurdJournals_JournalUUIDIndex") or nil
    local journals = cache and cache.journals or {}
    if type(journals) ~= "table" and BurdJournals.normalizeTable then
        journals = BurdJournals.normalizeTable(journals) or {}
    end

    local entries = {}
    for uuid, entry in pairs(journals or {}) do
        if type(entry) == "table" then
            local normalized = {}
            for k, v in pairs(entry) do normalized[k] = v end
            normalized.uuid = normalized.uuid or uuid
            table.insert(entries, normalized)
        end
    end
    self:applyServerJournalIndexList(entries, {count = #entries, total = #entries, truncated = false})
end

function BurdJournals.UI.DebugPanel:onJournalServerIndexChanged(combo)
    local panel = self.journalPanel
    if not panel or not panel.journalUUIDEntry or not combo then return end
    local selectedData = combo.selected and combo.selected > 1 and combo:getOptionData(combo.selected) or nil
    panel.journalUUIDEntry:setText(selectedData and tostring(selectedData.uuid or "") or "")
end

local function getCachedDebugBackupByUUID(uuid)
    local trimmed = tostring(uuid or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then
        return nil
    end

    local cache = ModData.getOrCreate and ModData.getOrCreate("BurdJournals_DebugJournalCache") or nil
    local journals = cache and cache.journals or nil
    if type(journals) ~= "table" and BurdJournals.normalizeTable then
        journals = BurdJournals.normalizeTable(journals)
    end
    if type(journals) ~= "table" then
        return nil
    end

    local direct = journals[trimmed]
    if type(direct) == "table" then
        return direct
    end

    for key, entry in pairs(journals) do
        if type(entry) == "table" then
            local entryUUID = tostring(entry.uuid or key or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if entryUUID == trimmed then
                return entry
            end
        end
    end

    return nil
end

function BurdJournals.UI.DebugPanel:onJournalUseServerIndexSelection()
    local panel = self.journalPanel
    if not panel or not panel.journalServerIndexCombo then return end
    local selectedIndex = panel.journalServerIndexCombo.selected or 0
    if selectedIndex <= 1 then
        self:setStatus("Select a server-index journal first", {r=1, g=0.6, b=0.3})
        return
    end

    local selectedData = panel.journalServerIndexCombo:getOptionData(selectedIndex)
    local uuid = selectedData and tostring(selectedData.uuid or "") or ""
    if uuid == "" then
        self:setStatus("Selected server-index entry has no UUID", {r=1, g=0.6, b=0.3})
        return
    end

    panel.journalUUIDEntry:setText(uuid)
    local localJournal = BurdJournals.findJournalByUUID and BurdJournals.findJournalByUUID(self.player, uuid) or nil
    if localJournal then
        self.editingJournal = localJournal
        self:refreshJournalEditorData()
        self:setStatus("Selected from server index", {r=0.3, g=1, b=0.5})
        return
    end

    if BurdJournals.UI and BurdJournals.UI.DebugPanel and BurdJournals.UI.DebugPanel.createServerJournalProxy then
        local cachedBackup = getCachedDebugBackupByUUID(uuid)
        local proxy = BurdJournals.UI.DebugPanel.createServerJournalProxy(uuid, selectedData, cachedBackup)
        if proxy then
            self.editingJournal = proxy
            self:refreshJournalEditorData()
            self:setStatus("Loaded server-index snapshot; checking for live item...", {r=0.95, g=0.8, b=0.35})
        end
    end

    self:onJournalFindByUUID()
end

function BurdJournals.UI.DebugPanel.createServerJournalProxy(uuid, indexEntry, backupData)
    local resolvedUUID = tostring(uuid or "")
    if resolvedUUID == "" then
        return nil
    end

    local normalized = BurdJournals.normalizeJournalData and BurdJournals.normalizeJournalData(backupData) or backupData
    if type(normalized) ~= "table" then
        normalized = {}
    end

    normalized.skills = normalized.skills or {}
    normalized.traits = normalized.traits or {}
    normalized.recipes = normalized.recipes or {}
    normalized.stats = normalized.stats or {}
    normalized.skillReadCounts = normalized.skillReadCounts or {}

    normalized.uuid = normalized.uuid or resolvedUUID
    normalized.isDebugSpawned = normalized.isDebugSpawned == true
    normalized.isDebugEdited = normalized.isDebugSpawned and (normalized.isDebugEdited == true) or nil
    local normalizedItemType = normalized.itemType or (type(indexEntry) == "table" and indexEntry.itemType) or ""
    local isWornType = type(normalizedItemType) == "string" and string.find(normalizedItemType, "_Worn", 1, true) ~= nil
    local isBloodyType = type(normalizedItemType) == "string" and string.find(normalizedItemType, "_Bloody", 1, true) ~= nil
    local isCursedType = normalizedItemType == (BurdJournals.CURSED_ITEM_TYPE or "BurdJournals.CursedJournal")
    local isFoundJournal = normalized.isWorn == true
        or normalized.isBloody == true
        or normalized.isCursedJournal == true
        or normalized.isCursedReward == true
        or isWornType
        or isBloodyType
        or isCursedType
        or (type(indexEntry) == "table" and indexEntry.isPlayerCreated == false)
    if isFoundJournal then
        normalized.isPlayerCreated = false
    elseif normalized.isPlayerCreated == nil then
        normalized.isPlayerCreated = true
    end
    normalized.sanitizedVersion = normalized.sanitizedVersion or (BurdJournals.SANITIZE_VERSION or 1)
    normalized.isWritten = true

    if indexEntry and type(indexEntry) == "table" then
        normalized.itemType = normalized.itemType or indexEntry.itemType
        normalized.itemName = normalized.itemName or indexEntry.itemName
        normalized.ownerUsername = normalized.ownerUsername or indexEntry.ownerUsername
        normalized.ownerSteamId = normalized.ownerSteamId or indexEntry.ownerSteamId
        normalized.ownerCharacterName = normalized.ownerCharacterName or indexEntry.ownerCharacterName
        normalized.wasFromWorn = normalized.wasFromWorn == true or indexEntry.wasFromWorn == true
        normalized.wasFromBloody = normalized.wasFromBloody == true or indexEntry.wasFromBloody == true
        normalized.wasRestored = normalized.wasRestored == true or indexEntry.wasRestored == true
    end

    local itemType = normalized.itemType or "BurdJournals.FilledSurvivalJournal"
    local itemName = normalized.itemName or "Server Journal"
    local itemId = tonumber(indexEntry and indexEntry.itemId) or -1

    local proxy = {
        __bsjServerProxy = true,
        __bsjUUID = resolvedUUID,
        __bsjIndexEntry = indexEntry,
        __bsjmodData = {BurdJournals = normalized},
        __bsjItemType = itemType,
        __bsjItemName = itemName,
        __bsjItemId = itemId,
        __bsjDirty = false,
    }

    function proxy:getModData()
        return self.__bsjmodData
    end

    function proxy:getID()
        return self.__bsjItemId
    end

    function proxy:getFullType()
        return self.__bsjItemType
    end

    function proxy:getName()
        return self.__bsjItemName
    end

    function proxy:transmitModData()
        return
    end

    return proxy
end

-- Select a journal from the dropdown list (fallback picks first match)
function BurdJournals.UI.DebugPanel:onJournalSelectFromInventory()
    self:refreshJournalPickerList(true)
    local panel = self.journalPanel
    if not panel or not panel.journalPickerEntries or #panel.journalPickerEntries == 0 then
        self:setStatus("No journals found nearby or in inventory", {r=1, g=0.5, b=0.5})
        return
    end

    if not panel.journalSelectCombo.selected or panel.journalSelectCombo.selected <= 1 then
        panel.journalSelectCombo.selected = 2
    end
    self:onJournalUseDropdownSelection()
end

local function getJournalUUIDInput(panel)
    if not panel or not panel.journalPanel or not panel.journalPanel.journalUUIDEntry then
        return nil
    end
    local raw = panel.journalPanel.journalUUIDEntry:getText()
    if not raw then return nil end
    local uuid = tostring(raw):gsub("^%s+", ""):gsub("%s+$", "")
    if uuid == "" then
        return nil
    end
    return uuid
end

local function getDebugXPModeLabel(mode)
    if mode == true then
        return "baseline"
    end
    if mode == false then
        return "absolute"
    end
    return "auto"
end

local function normalizeDebugJournalXPMode(data, player)
    if type(data) ~= "table" then
        return nil, nil, false, false
    end

    local modeBefore = data.recordedWithBaseline
    local modeAfter = BurdJournals.getJournalSkillRecordingMode
        and BurdJournals.getJournalSkillRecordingMode(data, player)
        or (modeBefore == true)
    local autoRepaired = false

    if modeAfter and data.recordedWithBaseline == true and type(data.skills) == "table" and player and player.getXp then
        local sampledSkills = 0
        local suspiciousAbsoluteSkills = 0
        for skillName, storedData in pairs(data.skills) do
            local storedXP = tonumber(type(storedData) == "table" and storedData.xp or storedData)
            if storedXP and storedXP > 0 then
                local perk = BurdJournals.getPerkByName and BurdJournals.getPerkByName(skillName)
                if perk then
                    sampledSkills = sampledSkills + 1
                    local actualXP = BurdJournals.getPlayerSkillTotalXP and BurdJournals.getPlayerSkillTotalXP(player, perk, skillName) or player:getXp():getXP(perk)
                    local baselineXP = math.max(0, tonumber(BurdJournals.getSkillBaseline and BurdJournals.getSkillBaseline(player, skillName) or 0) or 0)
                    local earnedXP = math.max(0, actualXP - baselineXP)
                    if storedXP > (earnedXP + 0.001) and storedXP <= (actualXP + 0.001) then
                        suspiciousAbsoluteSkills = suspiciousAbsoluteSkills + 1
                    end
                end
            end
        end
        if sampledSkills > 0 and suspiciousAbsoluteSkills >= math.max(1, math.floor(sampledSkills * 0.5)) then
            modeAfter = false
            autoRepaired = true
        end
    end

    if data.recordedWithBaseline ~= modeAfter then
        data.recordedWithBaseline = modeAfter
        return modeBefore, modeAfter, true, autoRepaired
    end

    return modeBefore, modeAfter, false, autoRepaired
end

function BurdJournals.UI.DebugPanel:onJournalFindByUUID()
    local uuid = getJournalUUIDInput(self)
    if not uuid then
        self:setStatus("Enter a journal UUID first", {r=1, g=0.6, b=0.3})
        return
    end

    local panel = self.journalPanel
    if panel and panel.journalServerIndexCombo and panel.journalServerIndexEntries then
        for i, entry in ipairs(panel.journalServerIndexEntries) do
            if tostring(entry.uuid or "") == tostring(uuid) then
                panel.journalServerIndexCombo.selected = i + 1
                break
            end
        end
    end

    if sendClientCommand and isClient and isClient() then
        sendClientCommand("BurdJournals", "debugLookupJournalByUUID", {uuid = uuid})
        self:setStatus("Looking up UUID on server...", {r=0.5, g=0.8, b=1})
        return
    end

    -- SP/local fallback
    local journal = BurdJournals.findJournalByUUID and BurdJournals.findJournalByUUID(self.player, uuid)
    if not journal then
        self:setStatus("UUID not found locally. Move closer to the container and retry.", {r=1, g=0.6, b=0.3})
        return
    end

    self.editingJournal = journal
    self:refreshJournalEditorData()
    self:setStatus("Selected journal by UUID", {r=0.3, g=1, b=0.5})
end

function BurdJournals.UI.DebugPanel:onJournalRepairByUUID()
    local uuid = getJournalUUIDInput(self)
    if not uuid then
        self:setStatus("Enter a journal UUID first", {r=1, g=0.6, b=0.3})
        return
    end

    if sendClientCommand and isClient and isClient() then
        sendClientCommand("BurdJournals", "debugRepairJournalByUUID", {uuid = uuid})
        self:setStatus("Repair request sent for UUID...", {r=0.5, g=0.8, b=1})
        return
    end

    -- SP/local fallback
    local journal = BurdJournals.findJournalByUUID and BurdJournals.findJournalByUUID(self.player, uuid)
    if not journal then
        self:setStatus("UUID not found locally. Move closer and retry.", {r=1, g=0.6, b=0.3})
        return
    end

    if BurdJournals.migrateJournalIfNeeded then
        BurdJournals.migrateJournalIfNeeded(journal, self.player)
    end
    if BurdJournals.sanitizeJournalData then
        BurdJournals.sanitizeJournalData(journal, self.player)
    end
    if BurdJournals.compactJournalData then
        BurdJournals.compactJournalData(journal)
    end
    if BurdJournals.UI and BurdJournals.UI.DebugPanel and BurdJournals.UI.DebugPanel.finalizeJournalEdit then
        BurdJournals.UI.DebugPanel.finalizeJournalEdit(journal)
    elseif journal.transmitModData then
        journal:transmitModData()
    end

    self.editingJournal = journal
    self:refreshJournalEditorData()
    self:setStatus("Local UUID repair complete", {r=0.3, g=1, b=0.5})
end

function BurdJournals.UI.DebugPanel:onJournalNormalizeXPModeByUUID()
    local uuid = getJournalUUIDInput(self)
    if not uuid then
        self:setStatus("Enter a journal UUID first", {r=1, g=0.6, b=0.3})
        return
    end

    if sendClientCommand and isClient and isClient() then
        sendClientCommand("BurdJournals", "debugRepairJournalByUUID", {uuid = uuid, normalizeXPMode = true})
        self:setStatus("Normalize-XP request sent...", {r=0.5, g=0.8, b=1})
        return
    end

    -- SP/local fallback
    local journal = BurdJournals.findJournalByUUID and BurdJournals.findJournalByUUID(self.player, uuid)
    if not journal then
        self:setStatus("UUID not found locally. Move closer and retry.", {r=1, g=0.6, b=0.3})
        return
    end

    local modData = journal:getModData()
    modData.BurdJournals = modData.BurdJournals or {}
    local data = modData.BurdJournals
    local modeBefore, modeAfter, modeChanged, autoRepaired = normalizeDebugJournalXPMode(data, self.player)

    if BurdJournals.UI and BurdJournals.UI.DebugPanel and BurdJournals.UI.DebugPanel.finalizeJournalEdit then
        BurdJournals.UI.DebugPanel.finalizeJournalEdit(journal)
    elseif journal.transmitModData then
        journal:transmitModData()
    end

    self.editingJournal = journal
    self:refreshJournalEditorData()

    local message = BurdJournals.formatText(BurdJournals.safeGetText("UI_BurdJournals_DebugXPModeAlreadyNormalized", "XP mode already normalized (%s)"), getDebugXPModeLabel(modeAfter))
    if modeChanged then
        message = BurdJournals.formatText(BurdJournals.safeGetText("UI_BurdJournals_DebugXPModeNormalized", "Normalized XP mode: %s -> %s"), getDebugXPModeLabel(modeBefore), getDebugXPModeLabel(modeAfter))
    end
    if autoRepaired then
        message = message .. " [legacy mismatch repaired]"
    end
    self:setStatus(message, {r=0.3, g=1, b=0.5})
end

function BurdJournals.UI.DebugPanel:onJournalMarkRestoredByUUID()
    local uuid = getJournalUUIDInput(self)
    if not uuid then
        self:setStatus("Enter a journal UUID first", {r=1, g=0.6, b=0.3})
        return
    end

    if sendClientCommand and isClient and isClient() then
        sendClientCommand("BurdJournals", "debugRepairJournalByUUID", {uuid = uuid, markRestored = true})
        self:setStatus("Mark-restored request sent...", {r=0.5, g=0.8, b=1})
        return
    end

    -- SP/local fallback
    local journal = BurdJournals.findJournalByUUID and BurdJournals.findJournalByUUID(self.player, uuid)
    if not journal then
        self:setStatus("UUID not found locally. Move closer and retry.", {r=1, g=0.6, b=0.3})
        return
    end

    local modData = journal:getModData()
    modData.BurdJournals = modData.BurdJournals or {}
    local data = modData.BurdJournals
    data.isPlayerCreated = true
    data.wasRestored = true
    if data.wasFromWorn ~= true and data.wasFromBloody ~= true then
        data.wasFromWorn = true
    end
    data.restoredBy = data.restoredBy or (self.player and self.player:getUsername()) or "Admin"
    data.isWorn = false
    data.isBloody = false

    if BurdJournals.UI and BurdJournals.UI.DebugPanel and BurdJournals.UI.DebugPanel.finalizeJournalEdit then
        BurdJournals.UI.DebugPanel.finalizeJournalEdit(journal)
    elseif journal.transmitModData then
        journal:transmitModData()
    end

    self.editingJournal = journal
    self:refreshJournalEditorData()
    self:setStatus("Marked journal as restored", {r=0.3, g=1, b=0.5})
end

function BurdJournals.UI.DebugPanel:onJournalDeleteByUUID()
    local uuid = getJournalUUIDInput(self)
    if not uuid then
        self:setStatus("Enter a journal UUID first", {r=1, g=0.6, b=0.3})
        return
    end

    if sendClientCommand and isClient and isClient() then
        sendClientCommand("BurdJournals", "debugDeleteJournalByUUID", {uuid = uuid})
        self:setStatus("Delete request sent for UUID...", {r=0.95, g=0.8, b=0.35})
        return
    end

    local removedLive = false
    local journal = BurdJournals.findJournalByUUID and BurdJournals.findJournalByUUID(self.player, uuid)
    if journal then
        local container = journal.getContainer and journal:getContainer() or nil
        if container then
            container:Remove(journal)
            removedLive = true
        end
    end

    local removedIndexEntries = 0
    local indexCache = ModData.getOrCreate and ModData.getOrCreate("BurdJournals_JournalUUIDIndex") or nil
    local indexTable = indexCache and indexCache.journals or nil
    if type(indexTable) ~= "table" and BurdJournals.normalizeTable then
        indexTable = BurdJournals.normalizeTable(indexTable)
        if indexCache then indexCache.journals = indexTable end
    end
    if type(indexTable) == "table" then
        for key, entry in pairs(indexTable) do
            local entryUUID = tostring((type(entry) == "table" and entry.uuid) or key or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if entryUUID == uuid then
                indexTable[key] = nil
                removedIndexEntries = removedIndexEntries + 1
            end
        end
    end

    local removedBackupEntries = 0
    local backupCache = ModData.getOrCreate and ModData.getOrCreate("BurdJournals_DebugJournalCache") or nil
    local backupTable = backupCache and backupCache.journals or nil
    if type(backupTable) ~= "table" and BurdJournals.normalizeTable then
        backupTable = BurdJournals.normalizeTable(backupTable)
        if backupCache then backupCache.journals = backupTable end
    end
    if type(backupTable) == "table" then
        for key, entry in pairs(backupTable) do
            local entryUUID = tostring((type(entry) == "table" and entry.uuid) or key or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if entryUUID == uuid then
                backupTable[key] = nil
                removedBackupEntries = removedBackupEntries + 1
            end
        end
    end

    if ModData.transmit then
        ModData.transmit("BurdJournals_JournalUUIDIndex")
        ModData.transmit("BurdJournals_DebugJournalCache")
    end

    self.editingJournal = nil
    self:refreshJournalEditorData()
    self:refreshJournalPickerList(true)
    self:onJournalRefreshServerIndex()

    if removedLive or removedIndexEntries > 0 or removedBackupEntries > 0 then
        self:setStatus("Deleted UUID data (live=" .. tostring(removedLive) .. ", index=" .. tostring(removedIndexEntries) .. ", backup=" .. tostring(removedBackupEntries) .. ")", {r=0.3, g=1, b=0.5})
    else
        self:setStatus("No live/cached journal data found for UUID", {r=1, g=0.6, b=0.3})
    end
end

function BurdJournals.UI.DebugPanel:onJournalDeleteByUUIDPrompt()
    local uuid = getJournalUUIDInput(self)
    if not uuid then
        self:setStatus("Enter a journal UUID first", {r=1, g=0.6, b=0.3})
        return
    end

    if not ISModalDialog then
        self:onJournalDeleteByUUID()
        return
    end

    local text = BurdJournals.formatText(getText("UI_BurdJournals_DebugDeleteJournalUUID"), tostring(uuid))

    local panel = self
    local callback = function(_target, button)
        if isAffirmativeDialogButton(button) and panel and panel.onJournalDeleteByUUID then
            panel:onJournalDeleteByUUID()
        end
    end
    if BurdJournals.createAdaptiveModalDialog then
        BurdJournals.createAdaptiveModalDialog({
            player = self.player,
            text = text,
            yesNo = true,
            onClick = callback,
            minWidth = 430,
            maxWidth = 860,
            minHeight = 190,
        })
    else
        local w = 520
        local h = 190
        local x = (getCore():getScreenWidth() - w) / 2
        local y = (getCore():getScreenHeight() - h) / 2
        local modal = ISModalDialog:new(x, y, w, h, text, true, nil, callback)
        modal:initialise()
        modal:addToUIManager()
    end
end

-- Helper: normalize trait IDs for consistent comparisons (strip base prefixes)
function BurdJournals.UI.DebugPanel.normalizeTraitId(traitId)
    if BurdJournals.normalizeTraitId then
        return BurdJournals.normalizeTraitId(traitId)
    end
    return traitId
end

-- Helper: build a lookup of trait IDs (including aliases) from a traits table
function BurdJournals.UI.DebugPanel.buildTraitLookup(traitsTable)
    if BurdJournals.buildTraitLookup then
        return BurdJournals.buildTraitLookup(traitsTable)
    end
    return {}
end

-- Helper: check if a trait is already present in lookup (including aliases)
function BurdJournals.UI.DebugPanel.isTraitInLookup(lookup, traitId)
    if BurdJournals.isTraitInLookup then
        return BurdJournals.isTraitInLookup(lookup, traitId)
    end
    return false
end

-- Helper: remove a trait from table, including aliases and case variants
function BurdJournals.UI.DebugPanel.removeTraitFromTable(traitsTable, traitId)
    if BurdJournals.removeTraitFromTable then
        return BurdJournals.removeTraitFromTable(traitsTable, traitId)
    end
    return false
end

-- Helper: resolve the actual key used in a skills table (handles case/alias mismatches)
function BurdJournals.UI.DebugPanel.resolveSkillKey(skillsTable, skillName)
    if BurdJournals.resolveSkillKey then
        return BurdJournals.resolveSkillKey(skillsTable, skillName)
    end
    return skillName
end

function BurdJournals.UI.DebugPanel.resolveRecipeKey(recipesTable, recipeName)
    if BurdJournals.resolveRecipeKey then
        local resolved = BurdJournals.resolveRecipeKey(recipesTable, recipeName)
        if resolved ~= nil then
            return resolved
        end
    end

    local wanted = string.lower(tostring(recipeName or ""))
    if wanted == "" then
        return nil
    end

    if type(recipesTable) == "table" then
        for key, _ in pairs(recipesTable) do
            if string.lower(tostring(key or "")) == wanted then
                return key
            end
        end
    end

    if BurdJournals.normalizeTable then
        local normalized = BurdJournals.normalizeTable(recipesTable)
        if type(normalized) == "table" then
            for key, _ in pairs(normalized) do
                if string.lower(tostring(key or "")) == wanted then
                    return key
                end
            end
        end
    end

    return nil
end

-- Helper: safely call base list mouse down without pcall
function BurdJournals.UI.DebugPanel.safeListMouseDown(self, x, y)
    local resolvedRow = getDebugListRowAt(self, x, y)
    if ISScrollingListBox and ISScrollingListBox.onMouseDown then
        ISScrollingListBox.onMouseDown(self, x, y)
    end
    if resolvedRow > 0 and self.items and self.items[resolvedRow] then
        self.selected = resolvedRow
    end
    return resolvedRow
end

-- Helper: build lookup of trait costs (positive/negative/neutral)
function BurdJournals.UI.DebugPanel.buildTraitCostLookup()
    if BurdJournals.buildTraitCostLookup then
        return BurdJournals.buildTraitCostLookup()
    end
    return {}
end

local function getDebugTraitLookupCost(traitId, costLookup)
    local normalized = BurdJournals.UI.DebugPanel.normalizeTraitId(traitId) or traitId
    normalized = string.gsub(tostring(normalized or ""), "^base:", "")
    if normalized == "" then
        return nil, normalized
    end

    local lookup = costLookup or BurdJournals.UI.DebugPanel.buildTraitCostLookup()
    return tonumber(lookup[string.lower(normalized)]), normalized
end

local function resolveDebugTraitBucket(traitId, costLookup)
    local traitData = BurdJournals and BurdJournals.getTraitMetadata and BurdJournals.getTraitMetadata(traitId) or nil
    if traitData and traitData.isPositive ~= nil then
        return traitData.isPositive and "positive" or "negative"
    end

    local cost, normalized = getDebugTraitLookupCost(traitId, costLookup)
    if normalized == "" then
        return nil
    end

    if cost ~= nil and cost > 0 then
        return "positive"
    end
    if cost ~= nil and cost < 0 then
        return "negative"
    end

    if BurdJournals and BurdJournals.buildKnownTraitSets then
        BurdJournals.buildKnownTraitSets()
    end

    local positiveSet = BurdJournals and BurdJournals._knownPositiveTraitsSet or nil
    local negativeSet = BurdJournals and BurdJournals._knownNegativeTraitsSet or nil
    local lower = string.lower(normalized)

    if positiveSet and positiveSet[lower] then
        return "positive"
    end
    if negativeSet and negativeSet[lower] then
        return "negative"
    end

    local aliases = BurdJournals and BurdJournals.getTraitAliases and BurdJournals.getTraitAliases(normalized) or {}
    for _, alias in ipairs(aliases) do
        local aliasLower = string.lower(tostring(alias or ""))
        if positiveSet and positiveSet[aliasLower] then
            return "positive"
        end
        if negativeSet and negativeSet[aliasLower] then
            return "negative"
        end
    end

    if BurdJournals and BurdJournals.determineTraitPolarity then
        local polarity = BurdJournals.determineTraitPolarity(normalized, cost)
        if polarity == false then
            return "negative"
        end
        if polarity == true then
            return "positive"
        end
    end

    return "neutral"
end

function BurdJournals.UI.DebugPanel.resolveTraitIsPositive(traitId, traitData, costLookup)
    if traitData and traitData.isPositive ~= nil then
        return traitData.isPositive
    end

    return resolveDebugTraitBucket(traitId, costLookup) ~= "negative"
end

function BurdJournals.UI.DebugPanel.getDebugBulkTraitActionSpec(action)
    local specs = {
        addalltraits = {
            isAdd = true,
            pendingMessage = BurdJournals.safeGetText("UI_BurdJournals_DebugAddAllTraits", "Add All Traits") .. "...",
            resultLabel = "traits",
        },
        addallpositivetraits = {
            isAdd = true,
            pendingMessage = BurdJournals.safeGetText("UI_BurdJournals_DebugAddAllPositiveTraits", "Add Positive") .. "...",
            resultLabel = "positive traits",
        },
        addallnegativetraits = {
            isAdd = true,
            pendingMessage = BurdJournals.safeGetText("UI_BurdJournals_DebugAddAllNegativeTraits", "Add Negative") .. "...",
            resultLabel = "negative traits",
        },
        removealltraits = {
            isAdd = false,
            pendingMessage = BurdJournals.safeGetText("UI_BurdJournals_DebugRemoveAllTraits", "Remove All Traits") .. "...",
            resultLabel = "traits",
        },
        removeallpositivetraits = {
            isAdd = false,
            pendingMessage = BurdJournals.safeGetText("UI_BurdJournals_DebugRemoveAllPositiveTraits", "Remove Positive") .. "...",
            resultLabel = "positive traits",
        },
        removeallnegativetraits = {
            isAdd = false,
            pendingMessage = BurdJournals.safeGetText("UI_BurdJournals_DebugRemoveAllNegativeTraits", "Remove Negative") .. "...",
            resultLabel = "negative traits",
        },
    }

    return specs[string.lower(tostring(action or ""))]
end

function BurdJournals.UI.DebugPanel.getBulkTraitBucket(traitId)
    return resolveDebugTraitBucket(traitId)
end

function BurdJournals.UI.DebugPanel.matchesBulkTraitAction(action, traitId)
    local spec = BurdJournals.UI.DebugPanel.getDebugBulkTraitActionSpec(action)
    if not spec then
        return false
    end

    if spec.resultLabel == "traits" then
        return true
    end

    local normalized = BurdJournals.UI.DebugPanel.normalizeTraitId(traitId) or traitId
    normalized = string.gsub(tostring(normalized or ""), "^base:", "")
    if normalized == "" then
        return false
    end

    local bucket = BurdJournals.UI.DebugPanel.getBulkTraitBucket(normalized)

    if spec.resultLabel == "positive traits" then
        return bucket == "positive"
    end

    if spec.resultLabel == "negative traits" then
        return bucket == "negative"
    end

    return false
end

function BurdJournals.UI.DebugPanel.collectAvailableTraitIdsForBulkAction(action)
    local out = {}
    local seen = {}
    local seenDisplay = {}
    local availableTraits = BurdJournals.UI.DebugPanel.getAvailableTraits and BurdJournals.UI.DebugPanel.getAvailableTraits() or {}
    if type(availableTraits) ~= "table" then
        availableTraits = {}
    end

    for _, rawTraitId in ipairs(availableTraits) do
        local traitId = BurdJournals.UI.DebugPanel.normalizeTraitId(rawTraitId) or rawTraitId
        traitId = string.gsub(tostring(traitId or ""), "^base:", "")
        if traitId ~= ""
            and not (BurdJournals.isPassiveSkillTrait and BurdJournals.isPassiveSkillTrait(traitId))
            and BurdJournals.UI.DebugPanel.matchesBulkTraitAction(action, traitId) then
            local key = string.lower(traitId)
            local displayName = BurdJournals.getTraitDisplayName and BurdJournals.getTraitDisplayName(traitId) or traitId
            local displayKey = string.lower(tostring(displayName or traitId)):gsub("%s+", ""):gsub("_", "")
            if not seen[key] and not seenDisplay[displayKey] then
                seen[key] = true
                seenDisplay[displayKey] = true
                if BurdJournals.getTraitAliases then
                    for _, alias in ipairs(BurdJournals.getTraitAliases(traitId)) do
                        local aliasNorm = BurdJournals.UI.DebugPanel.normalizeTraitId(alias) or alias
                        seen[string.lower(tostring(aliasNorm or ""))] = true
                    end
                end
                out[#out + 1] = traitId
            end
        end
    end

    table.sort(out)
    return out
end

function BurdJournals.UI.DebugPanel.collectOwnedTraitIdsForBulkAction(targetPlayer, action)
    local traitsToApply = {}
    local seenTraitIds = {}

    local function extractTraitId(candidate)
        if candidate == nil then
            return nil
        end
        if type(candidate) == "string" then
            return candidate
        end
        if candidate.getResourceLocation then
            local location = candidate:getResourceLocation()
            if location ~= nil and tostring(location) ~= "" then
                return tostring(location)
            end
        end
        if candidate.getName then
            local name = candidate:getName()
            if name ~= nil and tostring(name) ~= "" then
                return tostring(name)
            end
        end
        return nil
    end

    local function queueTraitId(rawTraitId)
        local traitId = BurdJournals.UI.DebugPanel.normalizeTraitId(rawTraitId) or rawTraitId
        traitId = string.gsub(tostring(traitId or ""), "^base:", "")
        if traitId == "" then
            return
        end
        if BurdJournals.isPassiveSkillTrait and BurdJournals.isPassiveSkillTrait(traitId) then
            return
        end
        if not BurdJournals.UI.DebugPanel.matchesBulkTraitAction(action, traitId) then
            return
        end

        local seenKey = string.lower(traitId)
        if seenTraitIds[seenKey] then
            return
        end

        seenTraitIds[seenKey] = true
        traitsToApply[#traitsToApply + 1] = traitId
    end

    if targetPlayer and BurdJournals.collectPlayerTraits then
        local collectedTraits = BurdJournals.collectPlayerTraits(targetPlayer, false) or {}
        for key, value in pairs(collectedTraits) do
            if type(key) == "string" then
                queueTraitId(key)
            elseif type(value) == "string" then
                queueTraitId(value)
            elseif type(value) == "table" then
                queueTraitId(value.id or value.type or value.name)
            end
        end
    end

    if targetPlayer then
        local function queueTraitLike(traitLike)
            local traitId = extractTraitId(traitLike)
            if not traitId and traitLike and traitLike.getType then
                traitId = extractTraitId(traitLike:getType())
            end
            if not traitId and traitLike and traitLike.getTrait then
                traitId = extractTraitId(traitLike:getTrait())
            end
            if traitId then
                queueTraitId(traitId)
            end
        end

        if targetPlayer.getTraits then
            local traits = targetPlayer:getTraits()
            if traits and traits.size and traits.get then
                for i = 0, traits:size() - 1 do
                    queueTraitLike(traits:get(i))
                end
            end
        end

        if targetPlayer.getCharacterTraits then
            local charTraits = targetPlayer:getCharacterTraits()
            if charTraits and charTraits.size and charTraits.get then
                for i = 0, charTraits:size() - 1 do
                    queueTraitLike(charTraits:get(i))
                end
            end
        end

        if CharacterTraitDefinition and CharacterTraitDefinition.getTraits and targetPlayer.hasTrait then
            local allDefs = CharacterTraitDefinition.getTraits()
            if allDefs then
                for i = 0, allDefs:size() - 1 do
                    local def = allDefs:get(i)
                    if def then
                        local probeTrait = (def.getType and def:getType())
                            or (def.getTrait and def:getTrait())
                            or nil
                        if probeTrait and targetPlayer:hasTrait(probeTrait) then
                            queueTraitLike(probeTrait)
                        end
                    end
                end
            end
        end
    end

    table.sort(traitsToApply)
    return traitsToApply
end

local function removeDebugTraitCompletelyLocally(targetPlayer, traitId)
    if not targetPlayer or not traitId then
        return 0, false
    end

    local removedCount = 0
    local remainingPasses = 32
    local traitIdsToTry = {}
    local seenTraitIds = {}
    local function addTraitId(id)
        if id == nil then return end
        id = tostring(id)
        if id == "" then return end
        local key = string.lower(id)
        if seenTraitIds[key] then return end
        seenTraitIds[key] = true
        traitIdsToTry[#traitIdsToTry + 1] = id
    end
    addTraitId(traitId)
    addTraitId(string.lower(tostring(traitId)))
    if BurdJournals.getTraitAliases then
        for _, alias in ipairs(BurdJournals.getTraitAliases(tostring(traitId))) do
            addTraitId(alias)
        end
    end

    while remainingPasses > 0 do
        local activeTraitId = nil
        for _, candidateTraitId in ipairs(traitIdsToTry) do
            if BurdJournals.playerHasTrait and BurdJournals.playerHasTrait(targetPlayer, candidateTraitId) == true then
                activeTraitId = candidateTraitId
                break
            end
        end
        if not activeTraitId then
            break
        end

        local okRemove, removed = pcall(function()
            return BurdJournals.safeRemoveTrait and BurdJournals.safeRemoveTrait(targetPlayer, activeTraitId, { skipSyncXp = true }) == true
        end)
        if not okRemove then
            return removedCount, false, tostring(removed)
        end
        if not removed then
            break
        end

        removedCount = removedCount + 1
        remainingPasses = remainingPasses - 1
    end

    local stillHas = false
    if BurdJournals.playerHasTrait then
        for _, candidateTraitId in ipairs(traitIdsToTry) do
            if BurdJournals.playerHasTrait(targetPlayer, candidateTraitId) == true then
                stillHas = true
                break
            end
        end
    end
    return removedCount, not stillHas, stillHas and "trait still present after bulk removal" or nil
end

function BurdJournals.UI.DebugPanel.applyBulkTraitActionLocally(targetPlayer, action, addOpts)
    local actionSpec = BurdJournals.UI.DebugPanel.getDebugBulkTraitActionSpec(action)
    if not actionSpec or not targetPlayer then
        return 0, 0, 0
    end

    local appliedCount = 0
    local skippedCount = 0
    local failedCount = 0
    local traitIds = actionSpec.isAdd
        and BurdJournals.UI.DebugPanel.collectAvailableTraitIdsForBulkAction(action)
        or BurdJournals.UI.DebugPanel.collectOwnedTraitIdsForBulkAction(targetPlayer, action)

    for _, traitId in ipairs(traitIds) do
        if actionSpec.isAdd then
            local hadBefore = BurdJournals.playerHasTrait and BurdJournals.playerHasTrait(targetPlayer, traitId) == true
            if hadBefore then
                skippedCount = skippedCount + 1
            else
                local okAdd, added = pcall(function()
                    local traitAddOpts = BurdJournals.UI.DebugPanel.buildDebugTraitAddOptions(
                        BurdJournals.UI.DebugPanel.instance,
                        addOpts or { skipSyncXp = true }
                    )
                    traitAddOpts.skipSyncXp = true
                    local traitAdded = BurdJournals.safeAddTrait and BurdJournals.safeAddTrait(targetPlayer, traitId, traitAddOpts) or false
                    if traitAdded
                        and not (traitAddOpts and traitAddOpts.skipTraitReconciliation == true)
                        and BurdJournals.Server
                        and BurdJournals.Server.resolveAndRemoveTraitConflicts then
                        BurdJournals.Server.resolveAndRemoveTraitConflicts(targetPlayer, traitId, { skipSyncXp = true })
                    end
                    return traitAdded
                end)
                if okAdd then
                    local hasAfter = BurdJournals.playerHasTrait and BurdJournals.playerHasTrait(targetPlayer, traitId) == true
                    if added or hasAfter then
                        appliedCount = appliedCount + 1
                    else
                        failedCount = failedCount + 1
                    end
                else
                    failedCount = failedCount + 1
                    if BurdJournals.writeLogLine then
                        BurdJournals.writeLogLine("[BurdJournals] DebugPanel.applyBulkTraitActionLocally: add failed for '" .. tostring(traitId) .. "' during '" .. tostring(action) .. "': " .. tostring(added))
                    end
                end
            end
        else
            local failedSeen = {}
            for _, pendingTraitId in ipairs(traitIds) do
                local removedPasses, cleared, removeErr = removeDebugTraitCompletelyLocally(targetPlayer, pendingTraitId)
                if removedPasses > 0 and cleared then
                    appliedCount = appliedCount + removedPasses
                else
                    local failKey = string.lower(tostring(pendingTraitId or ""))
                    if failKey ~= "" and not failedSeen[failKey] then
                        failedSeen[failKey] = true
                        failedCount = failedCount + 1
                        if BurdJournals.writeLogLine then
                            BurdJournals.writeLogLine("[BurdJournals] DebugPanel.applyBulkTraitActionLocally: remove failed for '" .. tostring(pendingTraitId) .. "' during '" .. tostring(action) .. "': " .. tostring(removeErr))
                        end
                    end
                end
            end
            break
        end
    end

    if appliedCount > 0 and SyncXp then
        pcall(function()
            SyncXp(targetPlayer)
        end)
    end

    return appliedCount, skippedCount, failedCount
end

function BurdJournals.UI.DebugPanel.formatBulkTraitActionMessage(action, count, skippedCount, failedCount)
    local spec = BurdJournals.UI.DebugPanel.getDebugBulkTraitActionSpec(action)
    if not spec then
        return getText("UI_BurdJournals_DebugTraitsUpdated") or "Traits updated."
    end

    count = tonumber(count) or 0
    skippedCount = tonumber(skippedCount) or 0
    failedCount = tonumber(failedCount) or 0

    local parts = {}
    local verb = spec.isAdd and "Added " or "Removed "
    if count > 0 or skippedCount > 0 or failedCount > 0 then
        parts[#parts + 1] = verb .. tostring(count) .. " " .. spec.resultLabel
    else
        parts[#parts + 1] = "No matching " .. spec.resultLabel .. " found."
    end
    if skippedCount > 0 then
        parts[#parts + 1] = tostring(skippedCount) .. " already present"
    end
    if failedCount > 0 then
        parts[#parts + 1] = tostring(failedCount) .. " failed"
    end

    return table.concat(parts, " | ")
end

function BurdJournals.UI.DebugPanel.getTraitPolarityPrefix(data)
    if data and data.isPassiveSkillTrait then
        return "[~]"
    end
    if data and data.isPositive == false then
        return "[-]"
    end
    return "[+]"
end

function BurdJournals.UI.DebugPanel.getTraitPolarityText(data)
    if data and data.isPassiveSkillTrait then
        return "Passive"
    end
    if data and data.isPositive == false then
        return "Negative"
    end
    return "Positive"
end

function BurdJournals.UI.DebugPanel.getTraitPolarityColor(data)
    if data and data.isPassiveSkillTrait then
        return {0.5, 0.5, 0.5}
    end
    if data and data.isPositive == false then
        return {0.8, 0.5, 0.5}
    end
    return {0.5, 0.8, 0.5}
end

function BurdJournals.UI.DebugPanel.getTraitSourceLine(data)
    local polarity = BurdJournals.UI.DebugPanel.getTraitPolarityText(data)
    local source = data and tostring(data.source or "") or ""
    if source ~= "" then
        return polarity .. " Trait | " .. source
    end
    return polarity .. " Trait"
end

-- Refresh journal editor data
function BurdJournals.UI.DebugPanel:refreshJournalEditorData()
    local panel = self.journalPanel
    if not panel then return end
    if self.updateCharacterSummary then
        self:updateCharacterSummary()
    end
    if self.updateJournalTargetSummary then
        self:updateJournalTargetSummary()
    end
    local previousFocusedSkill = panel.journalFocusedSkill and tostring(panel.journalFocusedSkill) or nil

    -- Clear existing lists safely (ensure borderColor stays valid during clear)
    local function safeClearList(list)
        if not list then return end
        -- Ensure borderColor is valid before clear to prevent render crashes
        if not list.borderColor or type(list.borderColor) ~= "table" then
            list.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
        end
        if list.borderColor.b == nil then list.borderColor.b = 0.5 end
        if list.borderColor.r == nil then list.borderColor.r = 0.3 end
        if list.borderColor.g == nil then list.borderColor.g = 0.4 end
        if list.borderColor.a == nil then list.borderColor.a = 1 end
        list:clear()
    end

    safeClearList(panel.journalSkillList)
    safeClearList(panel.journalTraitList)
    safeClearList(panel.journalRecipeList)
    
    local journal = self.editingJournal
    if not journal then
        panel.journalHeaderLabel:setName("No journal selected")
        panel.journalInfoLabel:setName("Right-click a filled journal and select 'Edit Journal'")
        setJournalEditTypeCombo(panel, "filled")
        setJournalProfileCombo(panel, "normal")
        setJournalOriginCombo(panel, "found")
        if panel.journalOwnerCustomEntry then panel.journalOwnerCustomEntry:setText("") end
        if panel.journalFlavorEntry then panel.journalFlavorEntry:setText("") end
        if panel.journalAgeEntry then panel.journalAgeEntry:setText("0") end
        self:updateJournalEditorMetaVisibility()
        panel.journalFocusedSkill = nil
        refreshDebugSourceFilterStrip(panel.journalSkillSourceFilter, panel.journalSkillList and panel.journalSkillList.items or nil)
        refreshDebugSourceFilterStrip(panel.journalTraitSourceFilter, panel.journalTraitList and panel.journalTraitList.items or nil)
        refreshDebugSourceFilterStrip(panel.journalRecipeSourceFilter, panel.journalRecipeList and panel.journalRecipeList.items or nil)
        BurdJournals.UI.DebugPanel.updateJournalSkillLabel(self)
        BurdJournals.UI.DebugPanel.refreshJournalBulkToggles(self)
        return
    end

    -- Update header with journal name
    local journalName = journal:getName() or "Unknown Journal"
    if journal.__bsjServerProxy then
        journalName = journalName .. " [Server Snapshot]"
    end
    panel.journalHeaderLabel:setName(journalName)

    -- Get journal data
    local journalData = BurdJournals.getJournalData(journal)
    if not journalData then
        panel.journalInfoLabel:setName("No data in journal")
        setJournalEditTypeCombo(panel, inferJournalEditTypeFromItem(journal, nil))
        setJournalProfileCombo(panel, "normal")
        setJournalOriginCombo(panel, "found")
        if panel.journalOwnerCustomEntry then panel.journalOwnerCustomEntry:setText("") end
        if panel.journalFlavorEntry then panel.journalFlavorEntry:setText("") end
        if panel.journalAgeEntry then panel.journalAgeEntry:setText("0") end
        self:updateJournalEditorMetaVisibility()
        panel.journalFocusedSkill = nil
        refreshDebugSourceFilterStrip(panel.journalSkillSourceFilter, panel.journalSkillList and panel.journalSkillList.items or nil)
        refreshDebugSourceFilterStrip(panel.journalTraitSourceFilter, panel.journalTraitList and panel.journalTraitList.items or nil)
        refreshDebugSourceFilterStrip(panel.journalRecipeSourceFilter, panel.journalRecipeList and panel.journalRecipeList.items or nil)
        BurdJournals.UI.DebugPanel.updateJournalSkillLabel(self)
        BurdJournals.UI.DebugPanel.refreshJournalBulkToggles(self)
        return
    end
    if panel.journalUUIDEntry then
        panel.journalUUIDEntry:setText(tostring(journalData.uuid or ""))
    end
    if panel.journalSelectCombo and panel.journalPickerEntries then
        local selectedIndex = panel.journalSelectCombo.selected or 1
        local targetUuid = tostring(journalData.uuid or "")
        for i, entry in ipairs(panel.journalPickerEntries) do
            if (entry.journal and entry.journal == journal) or (targetUuid ~= "" and entry.uuid == targetUuid) then
                selectedIndex = i + 1
                break
            end
        end
        panel.journalSelectCombo.selected = selectedIndex
    end
    if panel.journalServerIndexCombo and panel.journalServerIndexEntries then
        local selectedIndex = panel.journalServerIndexCombo.selected or 1
        local targetUuid = tostring(journalData.uuid or "")
        for i, entry in ipairs(panel.journalServerIndexEntries) do
            if targetUuid ~= "" and tostring(entry.uuid or "") == targetUuid then
                selectedIndex = i + 1
                break
            end
        end
        panel.journalServerIndexCombo.selected = selectedIndex
    end

    local journalProfile = (journalData.isDebugSpawned == true) and "debug" or "normal"
    setJournalProfileCombo(panel, journalProfile)
    local journalOriginMode = inferJournalOriginMode(journalData)
    setJournalOriginCombo(panel, journalOriginMode)
    local journalEditType = inferJournalEditTypeFromItem(journal, journalData)
    setJournalEditTypeCombo(panel, journalEditType)

    if panel.journalOwnerCombo then
        self:populateOwnerCombo({ownerCombo = panel.journalOwnerCombo})
    end
    local ownerAuthorText = trimJournalEditorText(journalData.ownerCharacterName or journalData.author or "")
    if panel.journalOwnerCustomEntry then
        panel.journalOwnerCustomEntry:setText(ownerAuthorText)
    end
    if panel.journalOwnerCombo then
        local noneIndex = findOwnerOptionIndexByCombo(panel.journalOwnerCombo, function(optionData)
            return type(optionData) == "table" and optionData.isNone == true
        end) or 1
        local customIndex = findOwnerOptionIndexByCombo(panel.journalOwnerCombo, function(optionData)
            return type(optionData) == "table" and optionData.isCustom == true
        end)

        local selectedOwnerIndex = noneIndex
        if journalEditType == "filled" then
            selectedOwnerIndex = findOwnerOptionIndexByCombo(panel.journalOwnerCombo, function(optionData)
                if type(optionData) ~= "table" or optionData.isPlayer ~= true then
                    return false
                end
                local optionSteam = tostring(optionData.steamId or "")
                local dataSteam = tostring(journalData.ownerSteamId or "")
                if optionSteam ~= "" and dataSteam ~= "" and optionSteam == dataSteam then
                    return true
                end
                local optionUser = tostring(optionData.username or "")
                local dataUser = tostring(journalData.ownerUsername or "")
                return optionUser ~= "" and dataUser ~= "" and optionUser == dataUser
            end)
            if not selectedOwnerIndex and ownerAuthorText ~= "" and customIndex then
                selectedOwnerIndex = customIndex
            end
            if not selectedOwnerIndex then
                selectedOwnerIndex = noneIndex
            end
        end
        panel.journalOwnerCombo.selected = selectedOwnerIndex
    end

    if panel.journalFlavorEntry then
        panel.journalFlavorEntry:setText(tostring(journalData.flavorText or ""))
    end
    if panel.journalAgeEntry then
        local nowHours = (getGameTime and getGameTime() and getGameTime():getWorldAgeHours()) or 0
        local tsHours = tonumber(journalData.timestamp) or tonumber(journalData.createdAtHours) or tonumber(nowHours) or 0
        local ageHours = math.max(0, math.floor((tonumber(nowHours) or 0) - tsHours))
        panel.journalAgeEntry:setText(tostring(ageHours))
    end
    self:updateJournalEditorMetaVisibility()
    
    -- Update info line
    local skillCount = journalData.skills and BurdJournals.countTable(journalData.skills) or 0
    local traitCount = journalData.traits and BurdJournals.countTable(journalData.traits) or 0
    local recipeCount = journalData.recipes and BurdJournals.countTable(journalData.recipes) or 0
    local infoText = BurdJournals.formatText("%s %d | %s %d | %s %d", getText("UI_BurdJournals_TabSkills"), skillCount, getText("UI_BurdJournals_TabTraits"), traitCount, getText("UI_BurdJournals_TabRecipes"), recipeCount)
    if journalData.isPlayerCreated then
        infoText = infoText .. " [Player Journal]"
    end
    infoText = infoText .. " [Type: " .. tostring(journalEditType) .. "]"
    infoText = infoText .. ((journalProfile == "debug") and " [Profile: Debug]" or " [Profile: Normal]")
    infoText = infoText .. " [" .. getOriginModeLabel(journalOriginMode) .. "]"
    if journalData.forgetSlot == true then
        infoText = infoText .. " [Forget Slot]"
    end
    if journalData.isCursedJournal == true then
        infoText = infoText .. " [Cursed:" .. tostring(journalData.cursedState or "dormant") .. "]"
    elseif journalData.isCursedReward == true then
        infoText = infoText .. " [Cursed Reward]"
    end
    if journalData.cursedEffectType and journalData.cursedEffectType ~= "" then
        infoText = infoText .. " [Curse=" .. tostring(journalData.cursedEffectType) .. "]"
    end
    if journal.__bsjServerProxy then
        infoText = infoText .. " [No live item]"
    end

    -- Compatibility status note for Adaptive Traits filtering on player journals.
    if journalData.isPlayerCreated
        and BurdJournals.isAdaptiveTraitsModActive
        and BurdJournals.isAdaptiveTraitsModActive() then
        local adaptiveAllowed = BurdJournals.isAdaptiveTraitsManagedTraitRecordingEnabled
            and BurdJournals.isAdaptiveTraitsManagedTraitRecordingEnabled()
        if adaptiveAllowed then
            infoText = infoText .. " [AdaptiveTraits: Allowed]"
        else
            local filteredCount = 0
            if type(journalData.traits) == "table" and BurdJournals.isAdaptiveManagedTrait then
                for traitId, _ in pairs(journalData.traits) do
                    if BurdJournals.isAdaptiveManagedTrait(traitId) then
                        filteredCount = filteredCount + 1
                    end
                end
            end
            if filteredCount > 0 then
                infoText = infoText .. " [AdaptiveTraits: Filtered " .. tostring(filteredCount) .. "]"
            else
                infoText = infoText .. " [AdaptiveTraits: Filtered]"
            end
        end
    end

    panel.journalInfoLabel:setName(infoText)
    
    -- Populate skills from journal (normalized for Java-backed ModData safety)
    local normalized = BurdJournals.normalizeJournalData(journalData) or journalData
    local skillTable = normalized.skills or {}
    local focusedSkillFound = false
    local journalSkillCount = 0
    if skillTable then
        local sortedSkills = {}
        for skillName, skillData in pairs(skillTable) do
            local enabledForJournal = not BurdJournals.isSkillEnabledForJournal or BurdJournals.isSkillEnabledForJournal(journalData, skillName)
            if skillName ~= nil and enabledForJournal then
                local displayName = BurdJournals.getPerkDisplayName and BurdJournals.getPerkDisplayName(skillName) or tostring(skillName)
                local isPassive = BurdJournals.isPassiveSkill and BurdJournals.isPassiveSkill(skillName) or false
                local xp = (type(skillData) == "table" and tonumber(skillData.xp)) or 0
                local level = (type(skillData) == "table" and tonumber(skillData.level)) or 0
                local skillSource = BurdJournals.getSkillModSource and BurdJournals.getSkillModSource(skillName) or (isPassive and "Vanilla" or "Unknown")

                table.insert(sortedSkills, {
                    name = skillName,
                    displayName = displayName,
                    xp = xp,
                    level = level,
                    isPassive = isPassive,
                    source = skillSource,
                    sourceId = BurdJournals.getSkillModId and BurdJournals.getSkillModId(skillName) or skillSource,
                })
            end
        end
        
        -- Sort by display name
        table.sort(sortedSkills, function(a, b)
            return a.displayName < b.displayName
        end)
        
        for _, skill in ipairs(sortedSkills) do
            panel.journalSkillList:addItem(skill.displayName, skill)
            journalSkillCount = journalSkillCount + 1
            if previousFocusedSkill and string.lower(tostring(skill.name)) == string.lower(previousFocusedSkill) then
                panel.journalFocusedSkill = skill.name
                focusedSkillFound = true
            end
        end
    end
    
    -- Build journal trait rows with add/remove controls and source metadata.
    local journalTraits = normalized.traits or {}
    local journalTraitLookup = BurdJournals.UI.DebugPanel.buildTraitLookup(journalTraits)
    local traitCostLookup = BurdJournals.UI.DebugPanel.buildTraitCostLookup()
    local allTraits = BurdJournals.UI.DebugPanel.getAvailableTraits()
    local combinedTraits = {}
    local addedTraitDisplayNames = {}

    for _, traitId in ipairs(allTraits) do
        local displayName = BurdJournals.getTraitDisplayName and BurdJournals.getTraitDisplayName(traitId) or tostring(traitId)
        local displayNameLower = string.lower(displayName)
        if not addedTraitDisplayNames[displayNameLower] then
            local traitSource = BurdJournals.getTraitModSource and BurdJournals.getTraitModSource(traitId) or "Vanilla"
            combinedTraits[#combinedTraits + 1] = {
                id = traitId,
                displayName = displayName,
                inJournal = BurdJournals.UI.DebugPanel.isTraitInLookup(journalTraitLookup, traitId),
                isPositive = BurdJournals.UI.DebugPanel.resolveTraitIsPositive(traitId, nil, traitCostLookup),
                isPassiveSkillTrait = BurdJournals.isPassiveSkillTrait and BurdJournals.isPassiveSkillTrait(traitId) or false,
                traitTexture = getDebugTraitTexture(traitId),
                source = traitSource,
                sourceId = BurdJournals.getTraitModId and BurdJournals.getTraitModId(traitId) or traitSource,
            }
            addedTraitDisplayNames[displayNameLower] = true
        end
    end

    for traitId, _ in pairs(journalTraits) do
        local normalizedId = BurdJournals.UI.DebugPanel.normalizeTraitId(traitId) or traitId
        local displayName = BurdJournals.getTraitDisplayName and BurdJournals.getTraitDisplayName(normalizedId) or tostring(normalizedId)
        local displayNameLower = string.lower(displayName)
        if not addedTraitDisplayNames[displayNameLower] then
            local traitSource = BurdJournals.getTraitModSource and BurdJournals.getTraitModSource(normalizedId) or "Unknown"
            combinedTraits[#combinedTraits + 1] = {
                id = normalizedId,
                displayName = displayName,
                inJournal = true,
                isPositive = BurdJournals.UI.DebugPanel.resolveTraitIsPositive(normalizedId, nil, traitCostLookup),
                isPassiveSkillTrait = BurdJournals.isPassiveSkillTrait and BurdJournals.isPassiveSkillTrait(normalizedId) or false,
                traitTexture = getDebugTraitTexture(normalizedId),
                source = traitSource,
                sourceId = BurdJournals.getTraitModId and BurdJournals.getTraitModId(normalizedId) or traitSource,
            }
            addedTraitDisplayNames[displayNameLower] = true
        end
    end

    table.sort(combinedTraits, function(a, b)
        local left = string.lower(tostring((a and a.displayName) or (a and a.id) or ""))
        local right = string.lower(tostring((b and b.displayName) or (b and b.id) or ""))
        if left == right then
            return string.lower(tostring((a and a.id) or "")) < string.lower(tostring((b and b.id) or ""))
        end
        return left < right
    end)

    for _, trait in ipairs(combinedTraits) do
        panel.journalTraitList:addItem(trait.displayName, trait)
    end

    -- Build journal recipe rows using the same runtime catalog as the other editors,
    -- while preserving any recipe names already stored in this journal.
    local targetPlayer = self.getSharedTargetPlayer and self:getSharedTargetPlayer() or self.player
    local journalRecipes = normalized.recipes or {}
    local recipeRows = buildDebugRecipeRows(targetPlayer, true, false)
    local recipeRowLookup = {}
    for _, row in ipairs(recipeRows) do
        local key = string.lower(tostring(row.name or ""))
        local storedRecipeKey = BurdJournals.UI.DebugPanel.resolveRecipeKey(journalRecipes, row.name)
        row.inJournal = storedRecipeKey ~= nil and journalRecipes[storedRecipeKey] == true
        row.recipeTexture = getDebugRecipeTexture()
        row.magazineTexture = getDebugMagazineTexture(row.magazineSource)
        row.magazineDisplayName = row.magazineDisplayName or (row.magazineSource and BurdJournals.getMagazineDisplayName and BurdJournals.getMagazineDisplayName(row.magazineSource) or nil)
        recipeRowLookup[key] = row
    end

    for recipeName, isStored in pairs(journalRecipes) do
        local normalizedRecipeName = tostring(recipeName or "")
        local key = string.lower(normalizedRecipeName)
        if isStored == true and not recipeRowLookup[key] then
            local magazineSource = BurdJournals.getMagazineForRecipe and BurdJournals.getMagazineForRecipe(normalizedRecipeName) or nil
            recipeRows[#recipeRows + 1] = {
                name = normalizedRecipeName,
                displayName = BurdJournals.getRecipeDisplayName and BurdJournals.getRecipeDisplayName(normalizedRecipeName) or normalizedRecipeName,
                source = BurdJournals.getRecipeModSource and BurdJournals.getRecipeModSource(normalizedRecipeName, magazineSource) or tostring(magazineSource or "Unknown"),
                sourceId = BurdJournals.getRecipeModId and BurdJournals.getRecipeModId(normalizedRecipeName, magazineSource) or tostring(magazineSource or "unknown"),
                magazineSource = magazineSource,
                magazineDisplayName = magazineSource and BurdJournals.getMagazineDisplayName and BurdJournals.getMagazineDisplayName(magazineSource) or nil,
                isKnown = false,
                hasMagazine = magazineSource ~= nil and tostring(magazineSource) ~= "",
                inJournal = true,
                recipeTexture = getDebugRecipeTexture(),
                magazineTexture = getDebugMagazineTexture(magazineSource),
            }
        elseif recipeRowLookup[key] then
            recipeRowLookup[key].inJournal = true
        end
    end

    sortDebugRecipeRows(recipeRows)
    for _, row in ipairs(recipeRows) do
        panel.journalRecipeList:addItem(row.displayName, row)
    end

    refreshDebugSourceFilterStrip(panel.journalSkillSourceFilter, panel.journalSkillList and panel.journalSkillList.items or nil)
    refreshDebugSourceFilterStrip(panel.journalTraitSourceFilter, panel.journalTraitList and panel.journalTraitList.items or nil)
    refreshDebugSourceFilterStrip(panel.journalRecipeSourceFilter, panel.journalRecipeList and panel.journalRecipeList.items or nil)
    BurdJournals.UI.DebugPanel.filterJournalSkillList(self)
    BurdJournals.UI.DebugPanel.filterJournalTraitList(self)
    BurdJournals.UI.DebugPanel.filterJournalRecipeList(self)
    
    if not focusedSkillFound then
        panel.journalFocusedSkill = nil
    end
    BurdJournals.UI.DebugPanel.updateJournalSkillLabel(self)
end

local function getDebugSkillDisplayLevel(skillName, storedLevel, xp)
    local currentXP = math.max(0, tonumber(xp) or 0)
    local normalizedStoredLevel = math.max(0, math.min(10, math.floor(tonumber(storedLevel) or 0)))
    local derivedLevel = normalizedStoredLevel

    if BurdJournals.getSkillLevelFromXP then
        local computed = BurdJournals.getSkillLevelFromXP(currentXP, skillName)
        if tonumber(computed) then
            derivedLevel = math.max(0, math.min(10, math.floor(tonumber(computed) or 0)))
        end
    end

    -- For baseline-recorded passive skills, stored level can be intentionally higher than
    -- XP-derived level (XP is delta, level is absolute). Preserve stored level in UI.
    if normalizedStoredLevel > derivedLevel then
        return normalizedStoredLevel, true
    end
    return derivedLevel, false
end

-- Draw function for journal skill items
function BurdJournals.UI.DebugPanel.drawJournalSkillItem(self, y, item, alt)
    local h = getDebugListRowHeight(self, item, 24)

    -- CRITICAL: y must be a valid number for ISScrollingListBox to work correctly
    -- Return y + h (not just h) to maintain proper list positioning
    y = tonumber(y) or 0
    if y ~= y then y = 0 end  -- NaN check

    -- Item validation - return valid y + h even for invalid items
    if not item or not item.item then return y + h end
    local data = item.item
    if not data then return y + h end
    if data.hidden then return y + h end

    local w = tonumber(self.width) or 300
    if w <= 0 then w = 300 end
    local parentPanel = self.parentPanel
    local journalPanel = parentPanel and parentPanel.journalPanel
    local isSelected = journalPanel and journalPanel.journalFocusedSkill == data.name
    
    -- Resolve display level from XP, but preserve stored level when it is intentionally higher
    -- (e.g., passive skills recorded in baseline mode).
    local currentXP = math.max(0, tonumber(data.xp) or 0)
    local currentLevel, usedStoredOverride = getDebugSkillDisplayLevel(data.name, data.level, currentXP)
    local displayName = tostring(data.displayName or data.name or "Unknown")
    
    -- Background (check item.index exists)
    if isSelected then
        self:drawRect(0, y, w, h, 0.3, 0.2, 0.4, 0.3)
    elseif item.index and self.mouseoverselected == item.index then
        self:drawRect(0, y, w, h, 0.2, 0.2, 0.3, 0.3)
    elseif data.isPassive then
        self:drawRect(0, y, w, h, 0.1, 0.15, 0.2, 0.2)
    end

    -- Skill name
    local nameColor = isSelected and {1, 1, 0.6} or {1, 1, 1}
    self:drawText(displayName, 8, y + 4, nameColor[1], nameColor[2], nameColor[3], 1, UIFont.Small)

    -- Level text
    local levelText = BurdJournals.formatText(getText("UI_BurdJournals_LevelFormat"), tonumber(currentLevel) or 0)
    self:drawText(levelText, 140, y + 4, 0.8, 0.8, 0.5, 1, UIFont.Small)

    -- Level squares (0-10) - show current level + partial progress
    -- Use shared threshold helpers so editor math matches set/get XP behavior.
    local squaresX = 185
    local squareSize = 12
    local squareSpacing = 2
    local progress = 0
    if currentLevel < 10 and not usedStoredOverride then
        local levelStartXP = 0
        local levelEndXP = 0
        if BurdJournals.getXPThresholdForLevel then
            levelStartXP = tonumber(BurdJournals.getXPThresholdForLevel(data.name, currentLevel)) or 0
            levelEndXP = tonumber(BurdJournals.getXPThresholdForLevel(data.name, currentLevel + 1)) or levelStartXP
        end
        if levelEndXP < levelStartXP then
            levelEndXP = levelStartXP
        end
        local xpRange = levelEndXP - levelStartXP
        if xpRange > 0 then
            progress = math.max(0, math.min(1, (currentXP - levelStartXP) / xpRange))
        elseif currentXP > levelStartXP then
            progress = 1
        end
    end

    for i = 1, 10 do
        local sqX = squaresX + (i - 1) * (squareSize + squareSpacing)
        local sqY = y + (h - squareSize) / 2

        if i <= currentLevel then
            -- Filled square
            self:drawRect(sqX, sqY, squareSize, squareSize, 0.9, 0.4, 0.7, 0.4)
        elseif i == currentLevel + 1 and progress > 0 then
            self:drawRect(sqX, sqY, squareSize, squareSize, 0.5, 0.15, 0.15, 0.2)
            local fillHeight = squareSize * progress
            self:drawRect(sqX, sqY + squareSize - fillHeight, squareSize, fillHeight, 0.8, 0.3, 0.5, 0.35)
        else
            -- Empty square
            self:drawRect(sqX, sqY, squareSize, squareSize, 0.5, 0.15, 0.15, 0.2)
        end
        self:drawRectBorder(sqX, sqY, squareSize, squareSize, 0.8, 0.4, 0.5, 0.6)
    end

    -- XP display
    local squaresEndX = squaresX + 10 * (squareSize + squareSpacing)
    local xpText = tostring(math.floor(currentXP)) .. " XP"
    local xpColor = isSelected and {1, 1, 0.6} or {0.6, 0.8, 0.6}
    self:drawText(xpText, squaresEndX + 8, y + 4, xpColor[1], xpColor[2], xpColor[3], 1, UIFont.Small)

    -- Remove button
    local scrollOffset = BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH or 15
    local removeBtnW = 50
    local removeBtnH = h - 4
    local removeBtnX = w - removeBtnW - 5 - scrollOffset
    local removeBtnY = y + 2

    -- Store button coords for click detection
    item.removeBtnX = removeBtnX
    item.removeBtnW = removeBtnW

    -- Draw remove button with hover effect (check item.index exists)
    local isHover = item.index and self.mouseoverselected == item.index
    if removeBtnX > 0 and removeBtnW > 0 and removeBtnH > 0 then
        if isHover then
            self:drawRect(removeBtnX, removeBtnY, removeBtnW, removeBtnH, 0.6, 0.6, 0.2, 0.2)
        else
            self:drawRect(removeBtnX, removeBtnY, removeBtnW, removeBtnH, 0.4, 0.4, 0.15, 0.15)
        end
        self:drawRectBorder(removeBtnX, removeBtnY, removeBtnW, removeBtnH, 0.7, 0.5, 0.3, 0.3)

        local removeText = getText("UI_BurdJournals_BtnErase")
        local removeTextW = getTextManager():MeasureStringX(UIFont.Small, removeText)
        self:drawText(removeText, removeBtnX + (removeBtnW - removeTextW) / 2, y + 4, 1, 0.5, 0.5, 0.9, UIFont.Small)

        -- Passive indicator (moved left to make room for Remove button)
        if data.isPassive then
            self:drawText("[P]", removeBtnX - 25, y + 4, 0.5, 0.7, 0.9, 0.7, UIFont.Small)
        end
    end
    
    return y + h
end

-- Click handler for journal skill list
function BurdJournals.UI.DebugPanel.onJournalSkillListClick(self, x, y)
    local row = BurdJournals.UI.DebugPanel.safeListMouseDown(self, x, y)
    
    if not self.items then return end
    if not row or row <= 0 or row > #self.items then return end
    
    local item = self.items[row]
    if not item or not item.item then return end
    local data = item.item
    if not data then return end
    
    local parentPanel = self.parentPanel
    if not parentPanel then return end
    local journalPanel = parentPanel.journalPanel
    local journal = parentPanel.editingJournal
    if not journal then return end
    
    -- Check if click is on the Remove button
    local removeBtnX = item.removeBtnX
    local removeBtnW = item.removeBtnW or 50
    if removeBtnX and x >= removeBtnX and x <= removeBtnX + removeBtnW then
        -- Mark as debug-edited for persistence
        BurdJournals.UI.DebugPanel.markJournalAsDebugEdited(journal)
        
        -- Remove skill from journal
        local modData = journal:getModData()
        if modData and modData.BurdJournals and modData.BurdJournals.skills then
            if BurdJournals.normalizeTable then
                modData.BurdJournals.skills = BurdJournals.normalizeTable(modData.BurdJournals.skills) or modData.BurdJournals.skills
            end
            local skillsTable = modData.BurdJournals.skills
            local skillKey = BurdJournals.UI.DebugPanel.resolveSkillKey(skillsTable, data.name)
            if skillKey then
                skillsTable[skillKey] = nil
            end
            -- Remove case-variant duplicates if present
            local nameLower = string.lower(tostring(data.name))
            local tableToScan = skillsTable
            if BurdJournals.normalizeTable then
                tableToScan = BurdJournals.normalizeTable(skillsTable) or skillsTable
            end
            for key, _ in pairs(tableToScan) do
                if string.lower(tostring(key)) == nameLower then
                    skillsTable[key] = nil
                end
            end
            if journal.transmitModData then
                journal:transmitModData()
            end
            -- Finalize edit: transmit and backup to global cache
            BurdJournals.UI.DebugPanel.finalizeJournalEdit(journal)
            parentPanel:refreshJournalEditorData()
            parentPanel:setStatus("Removed " .. data.displayName .. " from journal", {r=1, g=0.6, b=0.3})
        end
        return
    end
    
    -- Check if click is in the squares area
    local squaresX = 185
    local squareSize = 12
    local squareSpacing = 2
    local squaresEndX = squaresX + 10 * (squareSize + squareSpacing)
    
    if x >= squaresX and x <= squaresEndX then
        -- Calculate which level was clicked
        local relX = x - squaresX
        local clickedLevel = math.floor(relX / (squareSize + squareSpacing)) + 1
        clickedLevel = math.max(0, math.min(10, clickedLevel))
        
        local currentDisplayLevel = select(1, getDebugSkillDisplayLevel(data.name, data.level, data.xp))
        -- Toggle off if clicking current displayed level
        if clickedLevel == currentDisplayLevel then
            clickedLevel = 0
        end
        
        -- Update journal data
        BurdJournals.UI.DebugPanel.setJournalSkillLevel(parentPanel, data.name, clickedLevel)
        parentPanel:setStatus("Set " .. data.displayName .. " to level " .. clickedLevel, {r=0.3, g=1, b=0.5})
    end
    
    -- Select this skill for XP modification
    journalPanel.journalFocusedSkill = data.name
    
    -- Update XP entry with current XP
    if journalPanel.journalXPEntry then
        journalPanel.journalXPEntry:setText(tostring(math.floor(data.xp or 0)))
    end
    
    BurdJournals.UI.DebugPanel.updateJournalSkillLabel(parentPanel)
end

-- Update skill label when a skill is selected
function BurdJournals.UI.DebugPanel.updateJournalSkillLabel(self)
    local panel = self.journalPanel
    if not panel then return end
    
    local focusedSkill = panel.journalFocusedSkill
    if focusedSkill and panel.journalSkillList then
        for _, itemData in ipairs(panel.journalSkillList.items) do
            if itemData.item and itemData.item.name == focusedSkill then
                panel.journalSkillNameLabel:setName(itemData.item.displayName)
                panel.journalSkillNameLabel.r = 1
                panel.journalSkillNameLabel.g = 1
                panel.journalSkillNameLabel.b = 0.6
                BurdJournals.UI.DebugPanel.updateJournalDiminishingLabel(self)
                return
            end
        end
    end
    
    panel.journalSkillNameLabel:setName("Select a skill below")
    panel.journalSkillNameLabel.r = 0.5
    panel.journalSkillNameLabel.g = 0.6
    panel.journalSkillNameLabel.b = 0.7
    BurdJournals.UI.DebugPanel.updateJournalDiminishingLabel(self)
end

function BurdJournals.UI.DebugPanel:updateJournalTargetSummary()
    local panel = self.journalPanel
    if not panel then
        return
    end

    local targetPlayer = self:getSharedTargetPlayer() or self.player
    local targetName = getDebugTargetPlayerName(targetPlayer)
    local journalName = self.editingJournal and self.editingJournal.getName and self.editingJournal:getName() or nil

    if panel.journalTargetSummaryLabel then
        if journalName and journalName ~= "" then
            panel.journalTargetSummaryLabel:setName(BurdJournals.formatText(getText("UI_BurdJournals_DebugReclaimPreviewForJournal"), targetName, journalName))
        else
            panel.journalTargetSummaryLabel:setName(BurdJournals.formatText(getText("UI_BurdJournals_DebugReclaimPreviewFor"), targetName))
        end
    end

    if panel.journalTargetHelpLabel then
        local helpText
        if not BurdJournals.UI.DebugPanel.isDiminishingEnabled() then
            helpText = getText("UI_BurdJournals_DebugReclaimHelpDisabled")
        else
            helpText = getText("UI_BurdJournals_DebugReclaimHelpSelect")
        end
        panel.journalTargetHelpLabel:setName(helpText)
    end
end

function BurdJournals.UI.DebugPanel.getDiminishingModeName()
    local mode = BurdJournals.getDiminishingTrackingMode and BurdJournals.getDiminishingTrackingMode() or 3
    if mode == 1 then
        return getText("Sandbox_BurdJournals_DiminishingTrackingMode_option1")
    elseif mode == 2 then
        return getText("Sandbox_BurdJournals_DiminishingTrackingMode_option2")
    end
    return getText("Sandbox_BurdJournals_DiminishingTrackingMode_option3")
end

function BurdJournals.UI.DebugPanel.isDiminishingEnabled()
    return BurdJournals.getXPRecoveryMode and BurdJournals.getXPRecoveryMode() == 2
end

function BurdJournals.UI.DebugPanel.updateJournalDiminishingControlsVisibility(self, visible)
    local panel = self and self.journalPanel
    if not panel then return end

    local controls = {
        panel.journalDRStepLabel,
        panel.journalDRStepEntry,
        panel.journalDRSetBtn,
        panel.journalDRDecBtn,
        panel.journalDRIncBtn,
        panel.journalDRResetBtn,
        panel.journalDRHintLabel,
        panel.journalDRPreviewLabel,
    }
    for _, control in ipairs(controls) do
        if control and control.setVisible then
            control:setVisible(visible == true)
        end
    end
end

function BurdJournals.UI.DebugPanel.getJournalDRPreviewPercents(journalData, focusedSkill, player)
    if not journalData or not BurdJournals.getJournalClaimMultiplier then
        return nil
    end

    local percents = {}
    for readOffset = 0, 2 do
        local multiplier = BurdJournals.getJournalClaimMultiplier(journalData, readOffset, focusedSkill, nil, player)
        local percent = math.floor((math.max(0, tonumber(multiplier) or 0) * 100) + 0.5)
        percents[#percents + 1] = percent
    end

    return percents
end

function BurdJournals.UI.DebugPanel.updateJournalDiminishingLabel(self)
    local panel = self and self.journalPanel
    if not panel or not panel.journalDRLabel then return end
    if self and self.updateJournalTargetSummary then
        self:updateJournalTargetSummary()
    end

    local drEnabled = BurdJournals.UI.DebugPanel.isDiminishingEnabled()
    BurdJournals.UI.DebugPanel.updateJournalDiminishingControlsVisibility(self, drEnabled)
    if not drEnabled then
        panel.journalDRLabel:setName(BurdJournals.formatText(getText("UI_BurdJournals_DebugRecoveryLabel"), tostring(getText("Sandbox_BurdJournals_XPRecoveryMode_option1"))))
        panel.journalDRLabel.r = 0.55
        panel.journalDRLabel.g = 0.62
        panel.journalDRLabel.b = 0.72
        if panel.journalDRPreviewLabel then
            panel.journalDRPreviewLabel:setName(getText("UI_BurdJournals_DebugReclaimPreviewEmpty"))
        end
        return
    end

    local modeName = BurdJournals.UI.DebugPanel.getDiminishingModeName()
    local mode = BurdJournals.getDiminishingTrackingMode and BurdJournals.getDiminishingTrackingMode() or 3
    local journal = self and self.editingJournal
    local journalData = journal and BurdJournals.getJournalData and BurdJournals.getJournalData(journal) or nil
    local focusedSkill = panel.journalFocusedSkill
    local previewPlayer = self and self.getSharedTargetPlayer and self:getSharedTargetPlayer() or nil

    local suffix = "--"
    local previewText = getText("UI_BurdJournals_DebugReclaimPreviewEmpty")
    local stepValue = 0
    local stepHint = getText("UI_BurdJournals_DebugReclaimStepAllReads")
    if mode == 1 then
        stepHint = getText("UI_BurdJournals_DebugReclaimStepAllReads")
        stepValue = tonumber(journalData and journalData.readCount) or 0
    elseif mode == 2 then
        stepHint = getText("UI_BurdJournals_DebugReclaimStepSessions")
        stepValue = tonumber(journalData and journalData.readSessionCount) or 0
    else
        stepHint = getText("UI_BurdJournals_DebugReclaimStepSkillReads")
        stepValue = 0
        local skillReadCounts = journalData and journalData.skillReadCounts
        if type(skillReadCounts) ~= "table" and BurdJournals.normalizeTable then
            skillReadCounts = BurdJournals.normalizeTable(skillReadCounts)
        end
        if focusedSkill and type(skillReadCounts) == "table" then
            local resolvedKey = BurdJournals.resolveSkillKey and BurdJournals.resolveSkillKey(skillReadCounts, focusedSkill) or focusedSkill
            stepValue = tonumber(skillReadCounts[resolvedKey or focusedSkill]) or 0
        end
    end

    if panel.journalDRStepEntry then
        panel.journalDRStepEntry:setText(tostring(math.max(0, math.floor(stepValue))))
    end
    if panel.journalDRHintLabel then
        panel.journalDRHintLabel:setName(stepHint)
    end

    if mode == 3 and not focusedSkill then
        suffix = getText("UI_BurdJournals_DebugReclaimSelectSkill")
    end

    local claimPercent = nil
    local canPreview = journalData and BurdJournals.getJournalClaimMultiplier and (mode ~= 3 or focusedSkill ~= nil)
    if canPreview then
        local previewPercents = BurdJournals.UI.DebugPanel.getJournalDRPreviewPercents(journalData, focusedSkill, previewPlayer)
        if previewPercents and #previewPercents >= 3 then
            claimPercent = previewPercents[1]
            previewText = BurdJournals.formatText(getText("UI_BurdJournals_DebugReclaimPreviewFormat"), previewPercents[1], previewPercents[2], previewPercents[3])
        end
        claimPercent = claimPercent or 0
        suffix = tostring(claimPercent) .. "%"
        if mode == 1 then
            local readCount = tonumber(journalData.readCount) or 0
            suffix = BurdJournals.formatText(getText("UI_BurdJournals_DebugReclaimReadsSuffix"), suffix, readCount)
        elseif mode == 2 then
            local sessionCount = tonumber(journalData.readSessionCount) or 0
            suffix = BurdJournals.formatText(getText("UI_BurdJournals_DebugReclaimSessionSuffix"), suffix, sessionCount + 1)
        else
            local skillReads = 0
            local skillReadCounts = journalData and journalData.skillReadCounts
            if type(skillReadCounts) ~= "table" and BurdJournals.normalizeTable then
                skillReadCounts = BurdJournals.normalizeTable(skillReadCounts)
            end
            if type(skillReadCounts) == "table" then
                local resolvedKey = BurdJournals.resolveSkillKey and BurdJournals.resolveSkillKey(skillReadCounts, focusedSkill) or focusedSkill
                skillReads = tonumber(skillReadCounts[resolvedKey or focusedSkill]) or 0
            end
            suffix = BurdJournals.formatText(getText("UI_BurdJournals_DebugReclaimSkillReadsSuffix"), suffix, skillReads)
        end
    elseif not journalData then
        suffix = "--"
    end

    if panel.journalDRPreviewLabel then
        panel.journalDRPreviewLabel:setName(previewText)
    end

    panel.journalDRLabel:setName("Recovery: " .. modeName .. " | Next reclaim: " .. suffix)
    if claimPercent and claimPercent < 100 then
        panel.journalDRLabel.r = 1
        panel.journalDRLabel.g = 0.85
        panel.journalDRLabel.b = 0.55
    else
        panel.journalDRLabel.r = 0.55
        panel.journalDRLabel.g = 0.62
        panel.journalDRLabel.b = 0.72
    end
end

-- Mark journal as debug-edited for persistence across restarts and mod updates.
-- Keeps worn/bloody journals in found-journal claim mode; only clean journals
-- are forced into player-journal mode.
function BurdJournals.UI.DebugPanel.markJournalAsDebugEdited(journal)
    if not journal then return end
    local modData = journal:getModData()
    if not modData.BurdJournals then modData.BurdJournals = {} end
    local desiredProfile = resolveJournalEditProfileForItem(journal)
    local useDebugProfile = desiredProfile == "debug"

    local needsTransmit = false

    if not modData.BurdJournals.uuid then
        local generatedUUID = (BurdJournals.generateUUID and BurdJournals.generateUUID())
            or ("debug-" .. tostring(getTimestampMs and getTimestampMs() or os.time()) .. "-" .. tostring(journal:getID()))
        modData.BurdJournals.uuid = generatedUUID
        needsTransmit = true
        BurdJournals.debugPrint("[BurdJournals] Assigned UUID to debug-edited journal: " .. tostring(generatedUUID))
    end

    if useDebugProfile and not modData.BurdJournals.isDebugSpawned then
        modData.BurdJournals.isDebugSpawned = true
        modData.BurdJournals.isDebugEdited = true
        needsTransmit = true
        BurdJournals.debugPrint("[BurdJournals] Marked journal as debug-edited for persistence")
    elseif not useDebugProfile and modData.BurdJournals.isDebugSpawned then
        modData.BurdJournals.isDebugSpawned = false
        modData.BurdJournals.isDebugEdited = nil
        needsTransmit = true
        BurdJournals.debugPrint("[BurdJournals] Journal profile set to normal (debug flags cleared)")
    end

    local fullType = journal.getFullType and journal:getFullType() or ""
    local isWornType = type(fullType) == "string" and string.find(fullType, "_Worn", 1, true) ~= nil
    local isBloodyType = type(fullType) == "string" and string.find(fullType, "_Bloody", 1, true) ~= nil
    local isCursedType = fullType == (BurdJournals.CURSED_ITEM_TYPE or "BurdJournals.CursedJournal")
    local isFoundJournal = isWornType or isBloodyType or isCursedType

    -- Keep type/origin flags on found journals so per-character claims remain correct.
    if isWornType and modData.BurdJournals.isWorn ~= true then
        modData.BurdJournals.isWorn = true
        modData.BurdJournals.wasFromWorn = true
        needsTransmit = true
    end
    if isBloodyType and modData.BurdJournals.isBloody ~= true then
        modData.BurdJournals.isBloody = true
        modData.BurdJournals.wasFromBloody = true
        needsTransmit = true
    end

    if isFoundJournal then
        if modData.BurdJournals.isPlayerCreated ~= false then
            modData.BurdJournals.isPlayerCreated = false
            needsTransmit = true
            BurdJournals.debugPrint("[BurdJournals] Preserved found-journal claim mode (isPlayerCreated=false)")
        end
    elseif modData.BurdJournals.isPlayerCreated ~= true then
        modData.BurdJournals.isPlayerCreated = true
        needsTransmit = true
        BurdJournals.debugPrint("[BurdJournals] Ensured clean journal uses player-journal claim mode")
    end

    -- Update sanitized version to current to prevent data removal
    local currentVersion = BurdJournals.SANITIZE_VERSION or 1
    if modData.BurdJournals.sanitizedVersion ~= currentVersion then
        modData.BurdJournals.sanitizedVersion = currentVersion
        needsTransmit = true
    end

    -- Transmit changes to server for MP sync and persistence
    if needsTransmit and journal.transmitModData then
        journal:transmitModData()
    end

    -- Cache pre-edit state only when this journal is intentionally in Debug profile.
    if useDebugProfile then
        BurdJournals.UI.DebugPanel.backupJournalToGlobalCache(journal)
    end
end

-- Finalize debug journal edit - transmit and backup after data modification
-- Call this AFTER modifying journal data to ensure persistence
function BurdJournals.UI.DebugPanel.finalizeJournalEdit(journal, options)
    if not journal then return end
    options = options or {}
    local isServerProxy = journal.__bsjServerProxy == true
    local desiredProfile = resolveJournalEditProfileForItem(journal, options.profile)
    local useDebugProfile = desiredProfile == "debug"

    -- Ensure critical flags are set before transmitting
    local modData = journal:getModData()
    local journalUUID = nil
    if modData and modData.BurdJournals then
        if not modData.BurdJournals.uuid then
            modData.BurdJournals.uuid = (BurdJournals.generateUUID and BurdJournals.generateUUID())
                or ("debug-" .. tostring(getTimestampMs and getTimestampMs() or os.time()) .. "-" .. tostring(journal:getID()))
        end
        journalUUID = modData.BurdJournals.uuid

        -- Always ensure these flags are set for proper behavior.
        -- Preserve found-journal claim semantics for worn/bloody item types.
        local fullType = journal.getFullType and journal:getFullType() or ""
        local isWornType = type(fullType) == "string" and string.find(fullType, "_Worn", 1, true) ~= nil
        local isBloodyType = type(fullType) == "string" and string.find(fullType, "_Bloody", 1, true) ~= nil
        local isCursedType = fullType == (BurdJournals.CURSED_ITEM_TYPE or "BurdJournals.CursedJournal")
        modData.BurdJournals.isDebugSpawned = useDebugProfile
        modData.BurdJournals.isDebugEdited = useDebugProfile and true or nil
        if isWornType then
            modData.BurdJournals.isWorn = true
            modData.BurdJournals.wasFromWorn = true
        end
        if isBloodyType then
            modData.BurdJournals.isBloody = true
            modData.BurdJournals.wasFromBloody = true
        end
        if isWornType or isBloodyType or isCursedType then
            modData.BurdJournals.isPlayerCreated = false
        else
            modData.BurdJournals.isPlayerCreated = true
        end
        modData.BurdJournals.sanitizedVersion = BurdJournals.SANITIZE_VERSION or 1

        -- Mark as written so it's recognized as a valid filled journal
        modData.BurdJournals.isWritten = true
    end

    -- Transmit the item's ModData to server (critical for MP persistence)
    if journal.transmitModData and not isServerProxy then
        journal:transmitModData()
        BurdJournals.debugPrint("[BurdJournals] Transmitted journal ModData to server")
    end

    local journalKey = journalUUID or tostring((journal and journal.getID and journal:getID()) or "")
    local payloadData = BurdJournals.normalizeJournalData and BurdJournals.normalizeJournalData(modData and modData.BurdJournals) or (modData and modData.BurdJournals)

    -- Backup to global cache only for explicit Debug profile journals.
    if useDebugProfile then
        local cachedKey, backupData = BurdJournals.UI.DebugPanel.backupJournalToGlobalCache(journal)
        if cachedKey then
            journalKey = cachedKey
        end
        if backupData then
            payloadData = backupData
        end
    end

    -- MP authoritative persist: push edited journal payload to server-side item modData.
    -- For server proxies, this queues deferred apply immediately (pendingApply=true on server)
    -- when the live journal is not currently loaded.
    local player = getPlayer()
    if player and payloadData and isClient and isClient() then
        local payload = {
            journalUUID = journalUUID,
            journalKey = journalKey,
            journalData = payloadData
        }
        if type(options.extraPayload) == "table" then
            for key, value in pairs(options.extraPayload) do
                payload[key] = value
            end
        end
        if not isServerProxy then
            payload.journalId = journal:getID()
        end

        if not (BurdJournals.Client and BurdJournals.Client.Debug and BurdJournals.Client.Debug.sendServer
            and BurdJournals.Client.Debug.sendServer("debugApplyJournalEdits", payload, player)) then
            sendClientCommand(player, "BurdJournals", "debugApplyJournalEdits", payload)
        end
        if isServerProxy then
            journal.__bsjDirty = true
        end
    elseif isServerProxy then
        journal.__bsjDirty = true
    end
end

local function getDebugPanelJournalIdentity(panel)
    local journal = panel and panel.editingJournal or nil
    local identity = {}
    if journal and journal.getID and not journal.__bsjServerProxy then
        identity.journalId = journal:getID()
    end
    if journal and journal.getModData then
        local modData = journal:getModData()
        local data = modData and modData.BurdJournals or nil
        if type(data) == "table" then
            identity.journalUUID = data.uuid
            identity.journalKey = data.uuid
        end
    end
    if (not identity.journalUUID or identity.journalUUID == "") and panel and panel.journalPanel and panel.journalPanel.journalUUIDEntry then
        local text = panel.journalPanel.journalUUIDEntry:getText()
        if text and text ~= "" then
            identity.journalUUID = text
            identity.journalKey = text
        end
    end
    return identity
end

local function getJournalImportClaimModeFromModal(modal)
    if modal and modal.claimModeCombo and modal.claimModeCombo.selected and modal.claimModeCombo.selected > 0 then
        return modal.claimModeCombo:getOptionData(modal.claimModeCombo.selected)
            or modal.claimModeCombo.options[modal.claimModeCombo.selected]
    end
    return "preserve"
end

local function getImportItemTypeForClient(data, source)
    data = type(data) == "table" and data or {}
    source = type(source) == "table" and source or {}
    local itemType = tostring(source.itemType or data.fullType or data.itemType or "")
    local allowed = {
        ["BurdJournals.BlankSurvivalJournal"] = true,
        ["BurdJournals.FilledSurvivalJournal"] = true,
        ["BurdJournals.FilledSurvivalJournal_Worn"] = true,
        ["BurdJournals.FilledSurvivalJournal_Bloody"] = true,
        [BurdJournals.CURSED_ITEM_TYPE or "BurdJournals.CursedJournal"] = true,
        [BurdJournals.YULETIDE_ITEM_TYPE or "BurdJournals.YuletideJournal"] = true,
    }
    if allowed[itemType] then
        return itemType
    end
    if data.isYuletideJournal == true then
        return BurdJournals.YULETIDE_ITEM_TYPE or "BurdJournals.YuletideJournal"
    end
    if data.isCursedJournal == true then
        return BurdJournals.CURSED_ITEM_TYPE or "BurdJournals.CursedJournal"
    end
    if data.isBloody == true or data.wasFromBloody == true then
        return "BurdJournals.FilledSurvivalJournal_Bloody"
    end
    if data.isWorn == true or data.wasFromWorn == true then
        return "BurdJournals.FilledSurvivalJournal_Worn"
    end
    return "BurdJournals.FilledSurvivalJournal"
end

function BurdJournals.UI.DebugPanel:applyJournalImportLocally(jsonText, claimMode, mode)
    local envelope, parseErr = BurdJournals.parseJournalExportPayload and BurdJournals.parseJournalExportPayload(jsonText)
    if not envelope then
        self:setStatus(parseErr or debugText("UI_BurdJournals_DebugJournalImportInvalidJSON", "Invalid journal JSON"), {r=1, g=0.45, b=0.35})
        return false
    end
    local importedData, meta = BurdJournals.normalizeImportedJournalPayload(envelope, {claimMode = claimMode})
    if type(importedData) ~= "table" then
        self:setStatus(tostring(meta or debugText("UI_BurdJournals_DebugJournalImportInvalidData", "Invalid imported journal data")), {r=1, g=0.45, b=0.35})
        return false
    end

    local target = (mode ~= "spawn") and self.editingJournal or nil
    local action = "overwrite"
    if not target then
        action = "spawn"
        local inventory = self.player and self.player.getInventory and self.player:getInventory() or nil
        if not inventory then
            self:setStatus(debugText("UI_BurdJournals_DebugJournalImportNoInventory", "No inventory available for imported journal"), {r=1, g=0.45, b=0.35})
            return false
        end
        target = inventory:AddItem(getImportItemTypeForClient(importedData, envelope.source))
        if not target then
            self:setStatus(debugText("UI_BurdJournals_DebugJournalImportCreateFailed", "Failed to create imported journal"), {r=1, g=0.45, b=0.35})
            return false
        end
    end

    local modData = target:getModData()
    modData.BurdJournals = importedData
    importedData.wasImportedFromJSON = true
    importedData.importClaimMode = claimMode
    importedData.importedBy = self.player and self.player.getUsername and self.player:getUsername() or nil
    if BurdJournals.updateJournalName then
        BurdJournals.updateJournalName(target, true)
    end
    if BurdJournals.updateJournalIcon then
        BurdJournals.updateJournalIcon(target)
    end
    if target.transmitModData then
        target:transmitModData()
    end
    self.editingJournal = (mode == "spawn") and self.editingJournal or target
    if action == "overwrite" then
        self:refreshJournalEditorData()
    end
    self:refreshJournalPickerList(true)
    self:setStatus(
        (action == "spawn") and debugText("UI_BurdJournals_DebugJournalImportSpawned", "Imported journal created in inventory") or debugText("UI_BurdJournals_DebugJournalImportApplied", "Imported journal applied to selected journal"),
        {r=0.3, g=1, b=0.5}
    )
    return true
end

function BurdJournals.UI.DebugPanel:copyTextToClipboard(text, successMessage, unavailablePrefix)
    text = tostring(text or "")
    if text == "" then
        self:setStatus(debugText("UI_BurdJournals_DebugJournalCopyMissing", "No JSON available to copy"), {r=1, g=0.6, b=0.3})
        return false
    end

    local copied = false
    if Clipboard and Clipboard.setClipboard then
        Clipboard.setClipboard(text)
        copied = true
    end

    if not copied then
        local core = getCore and getCore() or nil
        if core and core.setClipboard then
            core:setClipboard(text)
            copied = true
        end
    end

    if copied then
        self:setStatus(successMessage or debugText("UI_BurdJournals_DebugJournalCopySuccess", "JSON copied to clipboard"), {r=0.3, g=1, b=0.5})
    else
        self:setStatus(unavailablePrefix or debugText("UI_BurdJournals_DebugJournalCopyUnavailable", "Clipboard unavailable; select and copy the JSON manually."), {r=1, g=0.75, b=0.35})
    end
    return copied
end

function BurdJournals.UI.DebugPanel:showJournalExportModal(jsonText, payload)
    local width = 720
    local height = 360
    local x = (getCore():getScreenWidth() - width) / 2
    local y = (getCore():getScreenHeight() - height) / 2
    local modal = ISPanel:new(x, y, width, height)
    modal:initialise()
    modal:instantiate()
    modal.backgroundColor = {r=0.08, g=0.09, b=0.11, a=0.98}
    modal.borderColor = {r=0.35, g=0.5, b=0.65, a=1}
    modal.parentDebugPanel = self
    modal.jsonText = jsonText or ""

    local padding = 12
    local title = ISLabel:new(padding, padding, 20, debugText("UI_BurdJournals_DebugJournalExportTitle", "Journal JSON Export"), 0.9, 0.95, 1, 1, UIFont.Medium, true)
    title:initialise()
    title:instantiate()
    modal:addChild(title)

    local counts = payload and payload.counts or {}
    local summary = BurdJournals.formatText(
        debugText("UI_BurdJournals_DebugJournalSummaryFormat", "UI_BurdJournals_DebugJournalSummaryFormat"),
        tonumber(counts.skills) or 0,
        tonumber(counts.traits) or 0,
        tonumber(counts.recipes) or 0,
        tonumber(counts.stats) or 0,
        tonumber(counts.claims) or 0
    )
    local summaryLabel = ISLabel:new(padding, 38, 16, summary, 0.7, 0.8, 0.9, 1, UIFont.Small, true)
    summaryLabel:initialise()
    summaryLabel:instantiate()
    modal:addChild(summaryLabel)

    modal.jsonList = ISScrollingListBox:new(padding, 62, width - padding * 2, 210)
    modal.jsonList:initialise()
    modal.jsonList:instantiate()
    modal.jsonList.font = UIFont.Small
    modal.jsonList.itemheight = 14
    modal.jsonList.backgroundColor = {r=0.03, g=0.035, b=0.045, a=1}
    modal.jsonList.borderColor = {r=0.55, g=0.6, b=0.68, a=1}
    modal.jsonList.doDrawItem = function(list, yPos, item, alt)
        local line = tostring(item and item.text or "")
        list:drawRect(0, yPos, list:getWidth(), list.itemheight, 0.0, 0, 0, 0)
        list:drawText(line, 6, yPos + 1, 0.92, 0.92, 0.92, 1, UIFont.Small)
        return yPos + list.itemheight
    end
    for line in string.gmatch(modal.jsonText .. "\n", "([^\n]*)\n") do
        modal.jsonList:addItem(line, line)
    end
    modal:addChild(modal.jsonList)

    local copyBtn = ISButton:new(padding, 286, 112, 24, debugText("UI_BurdJournals_DebugJournalCopyJSON", "Copy JSON"), modal, function(buttonTarget)
        local p = buttonTarget.parentDebugPanel
        if p then
            p:copyTextToClipboard(buttonTarget.jsonText or "", debugText("UI_BurdJournals_DebugJournalCopyJSONSuccess", "Journal JSON copied to clipboard"))
        end
    end)
    copyBtn:initialise()
    copyBtn:instantiate()
    copyBtn.font = UIFont.Small
    modal:addChild(copyBtn)

    local closeBtn = ISButton:new(width - padding - 82, height - padding - 24, 82, 24, debugText("UI_BurdJournals_Close", "Close"), modal, function(buttonTarget)
        buttonTarget:setVisible(false)
        buttonTarget:removeFromUIManager()
    end)
    closeBtn:initialise()
    closeBtn:instantiate()
    closeBtn.font = UIFont.Small
    modal:addChild(closeBtn)

    modal:addToUIManager()
    self.journalExportModal = modal
end

function BurdJournals.UI.DebugPanel:showJournalImportModal(options)
    options = type(options) == "table" and options or {}
    local width = 720
    local height = 390
    local x = (getCore():getScreenWidth() - width) / 2
    local y = (getCore():getScreenHeight() - height) / 2
    local modal = ISPanel:new(x, y, width, height)
    modal:initialise()
    modal:instantiate()
    modal.backgroundColor = {r=0.08, g=0.1, b=0.09, a=0.98}
    modal.borderColor = {r=0.35, g=0.55, b=0.45, a=1}
    modal.parentDebugPanel = self
    modal.importMode = options.mode or "auto"

    local padding = 12
    local titleText = (modal.importMode == "spawn") and debugText("UI_BurdJournals_DebugJournalImportSpawnerTitle", "Import Journal JSON to Spawner") or debugText("UI_BurdJournals_DebugJournalImportTitle", "Import Journal JSON")
    local title = ISLabel:new(padding, padding, 20, titleText, 0.9, 1, 0.92, 1, UIFont.Medium, true)
    title:initialise()
    title:instantiate()
    modal:addChild(title)

    local help = ISLabel:new(padding, 38, 16, debugText("UI_BurdJournals_DebugJournalImportHelp", "Paste a BSJ journal export JSON payload below. Imports always receive a new UUID."), 0.7, 0.84, 0.74, 1, UIFont.Small, true)
    help:initialise()
    help:instantiate()
    modal:addChild(help)

    modal.textEntry = ISTextEntryBox:new(options.jsonText or "", padding, 62, width - padding * 2, 220)
    modal.textEntry:initialise()
    modal.textEntry:instantiate()
    modal.textEntry.font = UIFont.Small
    modal.textEntry:setText(options.jsonText or "")
    modal:addChild(modal.textEntry)

    local claimLabel = ISLabel:new(padding, 296, 16, debugText("UI_BurdJournals_DebugJournalClaims", "Claims:"), 0.8, 0.85, 0.8, 1, UIFont.Small, true)
    claimLabel:initialise()
    claimLabel:instantiate()
    modal:addChild(claimLabel)

    modal.claimModeCombo = ISComboBox:new(padding + 52, 292, 150, 22, self, nil)
    modal.claimModeCombo:initialise()
    modal.claimModeCombo:instantiate()
    modal.claimModeCombo.font = UIFont.Small
    modal.claimModeCombo:addOptionWithData(debugText("UI_BurdJournals_DebugJournalClaimsPreserve", "Preserve"), "preserve")
    modal.claimModeCombo:addOptionWithData(debugText("UI_BurdJournals_DebugJournalClaimsClear", "Clear"), "clear")
    setComboSelectedCompat(modal.claimModeCombo, 1)
    modal:addChild(modal.claimModeCombo)

    local importBtn = ISButton:new(width - padding - 190, height - padding - 24, 104, 24, debugText("UI_BurdJournals_DebugJournalImport", "Import"), modal, function(buttonTarget)
        local p = buttonTarget.parentDebugPanel
        if p then
            p:confirmJournalImportFromModal(buttonTarget)
        end
    end)
    importBtn:initialise()
    importBtn:instantiate()
    importBtn.font = UIFont.Small
    modal:addChild(importBtn)

    local closeBtn = ISButton:new(width - padding - 80, height - padding - 24, 80, 24, debugText("UI_BurdJournals_Close", "Close"), modal, function(buttonTarget)
        buttonTarget:setVisible(false)
        buttonTarget:removeFromUIManager()
    end)
    closeBtn:initialise()
    closeBtn:instantiate()
    closeBtn.font = UIFont.Small
    modal:addChild(closeBtn)

    modal:addToUIManager()
    self.journalImportModal = modal
end

function BurdJournals.UI.DebugPanel:onJournalExportJSON()
    local journal = self.editingJournal
    if not journal then
        self:setStatus(debugText("UI_BurdJournals_DebugJournalExportNoSelection", "No journal selected for export"), {r=1, g=0.6, b=0.3})
        return
    end
    if isClient and isClient() and not journal.__bsjServerProxy then
        local payload = getDebugPanelJournalIdentity(self)
        if not (BurdJournals.Client and BurdJournals.Client.Debug and BurdJournals.Client.Debug.sendServer
            and BurdJournals.Client.Debug.sendServer("debugExportJournalJSON", payload, self.player)) then
            sendClientCommand(self.player, "BurdJournals", "debugExportJournalJSON", payload)
        end
        self:setStatus(debugText("UI_BurdJournals_DebugJournalExportRequested", "Journal export requested"), {r=0.5, g=0.8, b=1})
        return
    end
    local modData = journal:getModData()
    local data = modData and modData.BurdJournals or nil
    local payload, err = BurdJournals.buildJournalExportPayload(data, {
        itemType = journal.getFullType and journal:getFullType() or nil,
        itemName = journal.getName and journal:getName() or nil,
    }, {
        exportedBy = self.player and self.player.getUsername and self.player:getUsername() or nil
    })
    if not payload then
        self:setStatus(err or debugText("UI_BurdJournals_DebugJournalExportBuildFailed", "Failed to export journal"), {r=1, g=0.45, b=0.35})
        return
    end
    local jsonText, jsonErr = BurdJournals.encodeJournalExportJSON(payload, {pretty = true})
    if not jsonText then
        self:setStatus(jsonErr or debugText("UI_BurdJournals_DebugJournalExportEncodeFailed", "Failed to encode journal JSON"), {r=1, g=0.45, b=0.35})
        return
    end
    self:showJournalExportModal(jsonText, payload)
end

function BurdJournals.UI.DebugPanel:onJournalImportJSON()
    self:showJournalImportModal({mode = "auto"})
end

function BurdJournals.UI.DebugPanel:onSpawnImportJSON()
    self:showJournalImportModal({mode = "spawn"})
end

function BurdJournals.UI.DebugPanel:confirmJournalImportFromModal(modal)
    local jsonText = modal and modal.textEntry and modal.textEntry:getText() or ""
    local claimMode = getJournalImportClaimModeFromModal(modal)
    local importMode = modal and modal.importMode or "auto"
    if not jsonText or jsonText == "" then
        self:setStatus(debugText("UI_BurdJournals_DebugJournalImportPasteRequired", "Paste journal JSON before importing"), {r=1, g=0.6, b=0.3})
        return
    end
    if isClient and isClient() then
        local payload = getDebugPanelJournalIdentity(self)
        payload.jsonText = jsonText
        payload.claimMode = claimMode
        payload.mode = importMode
        if not (BurdJournals.Client and BurdJournals.Client.Debug and BurdJournals.Client.Debug.sendServer
            and BurdJournals.Client.Debug.sendServer("debugImportJournalJSON", payload, self.player)) then
            sendClientCommand(self.player, "BurdJournals", "debugImportJournalJSON", payload)
        end
        self:setStatus(debugText("UI_BurdJournals_DebugJournalImportRequested", "Journal import requested"), {r=0.5, g=0.8, b=1})
    else
        self:applyJournalImportLocally(jsonText, claimMode, importMode)
    end
end

function BurdJournals.UI.DebugPanel:handleJournalExportJSONResponse(args)
    if not args or args.success ~= true then
        self:setStatus((args and args.message) or debugText("UI_BurdJournals_DebugJournalExportFailed", "Journal export failed"), {r=1, g=0.45, b=0.35})
        return
    end
    self:showJournalExportModal(args.jsonText or "", args.payload or {counts = args.counts, source = args.source})
    self:setStatus(debugText("UI_BurdJournals_DebugJournalExportReady", "Journal export ready"), {r=0.3, g=1, b=0.5})
end

function BurdJournals.UI.DebugPanel:handleJournalImportResult(args)
    if not args or args.success ~= true then
        self:setStatus((args and args.message) or debugText("UI_BurdJournals_DebugJournalImportFailed", "Journal import failed"), {r=1, g=0.45, b=0.35})
        return
    end
    self:setStatus(args.message or debugText("UI_BurdJournals_DebugJournalImportComplete", "Journal import complete"), {r=0.3, g=1, b=0.5})
    self:refreshJournalPickerList(true)
    if args.action == "spawn" and args.requestMode ~= "spawn" and args.journalId and BurdJournals.findItemByIdInPlayerInventory then
        local journal = BurdJournals.findItemByIdInPlayerInventory(self.player, args.journalId)
        if journal then
            self.editingJournal = journal
        end
    end
    if args.action ~= "spawn" and self.refreshJournalEditorData then
        self:refreshJournalEditorData()
    elseif args.action == "spawn" and args.requestMode ~= "spawn" and self.refreshJournalEditorData then
        self:refreshJournalEditorData()
    end
end

-- Backup debug-edited journal data to global ModData for persistence
-- This mirrors the baseline system approach - global ModData survives better than item ModData
-- IMPORTANT: On dedicated MP servers, client-side ModData.transmit() doesn't persist!
-- So we also send the data to the server via sendClientCommand for proper server-side storage
function BurdJournals.UI.DebugPanel.backupJournalToGlobalCache(journal)
    if not journal then return end

    local modData = journal:getModData()
    if not modData.BurdJournals then return end
    if not (modData.BurdJournals.isDebugSpawned == true or modData.BurdJournals.debugBackupEnabled == true) then return end

    if not modData.BurdJournals.uuid then
        modData.BurdJournals.uuid = (BurdJournals.generateUUID and BurdJournals.generateUUID())
            or ("debug-" .. tostring(getTimestampMs and getTimestampMs() or os.time()) .. "-" .. tostring(journal:getID()))
    end

    -- Get or create global cache (similar to baseline cache)
    local cache = ModData.getOrCreate("BurdJournals_DebugJournalCache")
    if not cache.journals then cache.journals = {} end

    -- Use journal UUID as key for stable persistence across reconnects.
    local journalKey = modData.BurdJournals.uuid or tostring(journal:getID())
    local normalized = BurdJournals.normalizeJournalData(modData.BurdJournals) or modData.BurdJournals

    -- Build the backup data structure
    local backupData = {
        skills = {},
        traits = {},
        recipes = {},
        stats = {},
        claims = {},
        claimedSkills = {},
        claimedTraits = {},
        claimedRecipes = {},
        claimedStats = {},
        claimedForgetSlot = {},
        skillReadCounts = {},
        forgetSlot = normalized.forgetSlot == true,
        isCursedJournal = normalized.isCursedJournal == true,
        cursedState = normalized.cursedState,
        isCursedReward = normalized.isCursedReward == true,
        cursedEffectType = normalized.cursedEffectType,
        cursedUnleashedByCharacterId = normalized.cursedUnleashedByCharacterId,
        cursedUnleashedByUsername = normalized.cursedUnleashedByUsername,
        cursedUnleashedAtHours = tonumber(normalized.cursedUnleashedAtHours) or nil,
        cursedSealSoundEvent = normalized.cursedSealSoundEvent,
        cursedForcedEffectType = normalized.cursedForcedEffectType,
        cursedForcedTraitId = normalized.cursedForcedTraitId,
        cursedForcedSkillName = normalized.cursedForcedSkillName,
        cursedPendingRewards = nil,
        isDebugSpawned = normalized.isDebugSpawned == true,
        isDebugEdited = modData.BurdJournals.isDebugEdited,
        debugBackupEnabled = normalized.debugBackupEnabled == true,
        isPlayerCreated = modData.BurdJournals.isPlayerCreated,
        isWorn = modData.BurdJournals.isWorn,
        isBloody = modData.BurdJournals.isBloody,
        wasFromWorn = modData.BurdJournals.wasFromWorn,
        wasFromBloody = modData.BurdJournals.wasFromBloody,
        wasRestored = modData.BurdJournals.wasRestored,
        restoredBy = modData.BurdJournals.restoredBy,
        sanitizedVersion = modData.BurdJournals.sanitizedVersion,
        uuid = modData.BurdJournals.uuid,
        readCount = tonumber(modData.BurdJournals.readCount) or 0,
        readSessionCount = tonumber(modData.BurdJournals.readSessionCount) or 0,
        currentSessionId = modData.BurdJournals.currentSessionId,
        currentSessionReadCount = tonumber(modData.BurdJournals.currentSessionReadCount) or 0,
        timestamp = getTimestampMs and getTimestampMs() or os.time(),
        -- Store item info for restoration
        itemType = journal:getFullType(),
        itemID = journal:getID(),
    }

    -- Copy skills
    local skillsTable = normalized.skills or {}
    for skillName, skillData in pairs(skillsTable) do
        if skillName and skillData then
            backupData.skills[skillName] = {
                xp = skillData.xp,
                level = skillData.level
            }
        end
    end

    -- Copy traits
    local traitsTable = normalized.traits or {}
    for traitId, value in pairs(traitsTable) do
        if traitId then
            backupData.traits[traitId] = value
        end
    end

    -- Copy recipes
    local recipesTable = normalized.recipes or {}
    for recipeName, value in pairs(recipesTable) do
        if recipeName then
            backupData.recipes[recipeName] = value
        end
    end

    -- Copy stats
    local statsTable = normalized.stats or {}
    for statId, statData in pairs(statsTable) do
        if statId then
            backupData.stats[statId] = statData
        end
    end

    -- Copy claims and legacy claim maps
    local claimsTable = normalized.claims or {}
    for characterId, claimData in pairs(claimsTable) do
        if characterId then
            backupData.claims[characterId] = claimData
        end
    end

    local claimedSkillsTable = normalized.claimedSkills or {}
    for skillName, value in pairs(claimedSkillsTable) do
        if skillName then
            backupData.claimedSkills[skillName] = value
        end
    end

    local claimedTraitsTable = normalized.claimedTraits or {}
    for traitId, value in pairs(claimedTraitsTable) do
        if traitId then
            backupData.claimedTraits[traitId] = value
        end
    end

    local claimedRecipesTable = normalized.claimedRecipes or {}
    for recipeName, value in pairs(claimedRecipesTable) do
        if recipeName then
            backupData.claimedRecipes[recipeName] = value
        end
    end

    local claimedStatsTable = normalized.claimedStats or {}
    for statId, value in pairs(claimedStatsTable) do
        if statId then
            backupData.claimedStats[statId] = value
        end
    end

    local claimedForgetTable = normalized.claimedForgetSlot or {}
    for characterId, value in pairs(claimedForgetTable) do
        if characterId then
            backupData.claimedForgetSlot[characterId] = value
        end
    end

    if type(normalized.cursedPendingRewards) == "table" then
        backupData.cursedPendingRewards = BurdJournals.normalizeJournalData(normalized.cursedPendingRewards)
            or normalized.cursedPendingRewards
    end

    -- Copy diminishing-returns per-skill tracking.
    local skillReadCounts = normalized.skillReadCounts
    if type(skillReadCounts) ~= "table" and BurdJournals.normalizeTable then
        skillReadCounts = BurdJournals.normalizeTable(skillReadCounts)
    end
    if type(skillReadCounts) == "table" then
        for skillName, count in pairs(skillReadCounts) do
            if skillName then
                backupData.skillReadCounts[skillName] = tonumber(count) or 0
            end
        end
    end

    -- Keep DR counters in sync with normalized values when present.
    backupData.readCount = tonumber(normalized.readCount) or backupData.readCount
    backupData.readSessionCount = tonumber(normalized.readSessionCount) or backupData.readSessionCount
    backupData.currentSessionId = normalized.currentSessionId or backupData.currentSessionId
    backupData.currentSessionReadCount = tonumber(normalized.currentSessionReadCount) or backupData.currentSessionReadCount

    -- Store in local cache (works for SP and host player)
    cache.journals[journalKey] = backupData

    -- Transmit global cache (works for SP and host, but NOT for clients on dedicated servers)
    ModData.transmit("BurdJournals_DebugJournalCache")

    -- CRITICAL: On dedicated MP servers, also send to server via command for proper persistence
    -- This ensures the server stores the backup in its own global ModData
    local player = getPlayer()
    if player and isClient and isClient() then
        sendClientCommand(player, "BurdJournals", "saveDebugJournalBackup", {
            journalKey = journalKey,
            journalData = backupData
        })
        BurdJournals.debugPrint("[BurdJournals] Sent debug journal backup to server: " .. journalKey)
    end

    BurdJournals.debugPrint("[BurdJournals] Backed up debug journal to global cache: " .. journalKey)
    return journalKey, backupData
end

-- Restore journal data from global cache if item data was lost
-- Called during getJournalData or when opening a debug-spawned journal
-- On MP dedicated servers, will request backup from server if local cache is empty
function BurdJournals.UI.DebugPanel.restoreJournalFromGlobalCache(journal)
    if not journal then return false end

    local modData = journal:getModData()
    if not modData then return false end

    -- Initialize BurdJournals table if needed
    if not modData.BurdJournals then modData.BurdJournals = {} end

    local function hasCoreData(data)
        if not data then return false end
        if BurdJournals.hasAnyEntries(data.skills) then return true end
        if BurdJournals.hasAnyEntries(data.traits) then return true end
        if BurdJournals.hasAnyEntries(data.recipes) then return true end
        if BurdJournals.hasAnyEntries(data.stats) then return true end
        if data.forgetSlot == true then return true end
        if BurdJournals.hasAnyEntries(data.claims) then return true end
        if BurdJournals.hasAnyEntries(data.claimedForgetSlot) then return true end
        if data.isCursedJournal == true or data.isCursedReward == true then return true end
        if BurdJournals.hasAnyEntries(data.cursedPendingRewards) then return true end
        return false
    end

    local function hasDRData(data)
        if not data then return false end
        if (tonumber(data.readCount) or 0) > 0 then return true end
        if (tonumber(data.readSessionCount) or 0) > 0 then return true end
        if (tonumber(data.currentSessionReadCount) or 0) > 0 then return true end
        if data.currentSessionId then return true end
        if BurdJournals.hasAnyEntries(data.skillReadCounts) then return true end
        return false
    end

    -- Determine journal key for cache lookup
    local journalKey = modData.BurdJournals.uuid
    if not journalKey then
        journalKey = tostring(journal:getID())
    end

    -- Get global cache
    local cache = ModData.getOrCreate("BurdJournals_DebugJournalCache")
    if not cache.journals then cache.journals = {} end

    -- Check if we have a local backup
    local backup = cache.journals[journalKey]

    if not backup then
        -- No local backup found - on MP, request from server
        if isClient and isClient() then
            BurdJournals.debugPrint("[BurdJournals] No local cache for debug journal key=" .. tostring(journalKey) .. " - requesting from server")
            if BurdJournals.Client and BurdJournals.Client.requestDebugJournalBackup then
                BurdJournals.Client.requestDebugJournalBackup(journal, journalKey)
            end
        end
        return false
    end

    local normalizedBackup = BurdJournals.normalizeJournalData(backup) or backup

    local existingCore = hasCoreData(modData.BurdJournals)
    local existingDR = hasDRData(modData.BurdJournals)
    local backupCore = hasCoreData(normalizedBackup)
    local backupDR = hasDRData(normalizedBackup)
    local shouldRestoreCore = (not existingCore) and backupCore
    local shouldRestoreDR = (not existingDR) and backupDR

    if not shouldRestoreCore and not shouldRestoreDR then
        return false
    end

    BurdJournals.debugPrint("[BurdJournals] Restoring debug journal from global cache: " .. tostring(journalKey))

    local fullType = journal.getFullType and journal:getFullType() or ""
    local isWornType = type(fullType) == "string" and string.find(fullType, "_Worn", 1, true) ~= nil
    local isBloodyType = type(fullType) == "string" and string.find(fullType, "_Bloody", 1, true) ~= nil
    local isCursedType = fullType == (BurdJournals.CURSED_ITEM_TYPE or "BurdJournals.CursedJournal")
    local isFoundJournal = isWornType
        or isBloodyType
        or isCursedType
        or normalizedBackup.isWorn == true
        or normalizedBackup.isBloody == true
        or normalizedBackup.isCursedJournal == true
        or normalizedBackup.isCursedReward == true

    -- Restore flags
    modData.BurdJournals.isDebugSpawned = normalizedBackup.isDebugSpawned == true
    modData.BurdJournals.isDebugEdited = modData.BurdJournals.isDebugSpawned and (normalizedBackup.isDebugEdited == true) or nil
    modData.BurdJournals.debugBackupEnabled = normalizedBackup.debugBackupEnabled == true
    if isFoundJournal then
        modData.BurdJournals.isPlayerCreated = false
    elseif normalizedBackup.isPlayerCreated ~= nil then
        modData.BurdJournals.isPlayerCreated = normalizedBackup.isPlayerCreated == true
    else
        modData.BurdJournals.isPlayerCreated = true
    end
    modData.BurdJournals.sanitizedVersion = normalizedBackup.sanitizedVersion or (BurdJournals.SANITIZE_VERSION or 1)
    modData.BurdJournals.uuid = normalizedBackup.uuid
    modData.BurdJournals.wasRestored = normalizedBackup.wasRestored == true
    modData.BurdJournals.restoredBy = normalizedBackup.restoredBy
    modData.BurdJournals.forgetSlot = normalizedBackup.forgetSlot == true
    modData.BurdJournals.claimedForgetSlot = BurdJournals.normalizeTable(normalizedBackup.claimedForgetSlot) or {}
    modData.BurdJournals.isCursedJournal = normalizedBackup.isCursedJournal == true
    modData.BurdJournals.cursedState = normalizedBackup.cursedState
    modData.BurdJournals.isCursedReward = normalizedBackup.isCursedReward == true
    modData.BurdJournals.cursedEffectType = normalizedBackup.cursedEffectType
    modData.BurdJournals.cursedUnleashedByCharacterId = normalizedBackup.cursedUnleashedByCharacterId
    modData.BurdJournals.cursedUnleashedByUsername = normalizedBackup.cursedUnleashedByUsername
    modData.BurdJournals.cursedUnleashedAtHours = tonumber(normalizedBackup.cursedUnleashedAtHours) or nil
    modData.BurdJournals.cursedSealSoundEvent = normalizedBackup.cursedSealSoundEvent
    modData.BurdJournals.cursedForcedEffectType = normalizedBackup.cursedForcedEffectType
    modData.BurdJournals.cursedForcedTraitId = normalizedBackup.cursedForcedTraitId
    modData.BurdJournals.cursedForcedSkillName = normalizedBackup.cursedForcedSkillName
    modData.BurdJournals.cursedPendingRewards = BurdJournals.normalizeTable(normalizedBackup.cursedPendingRewards)

    if shouldRestoreCore then
        -- Restore skills
        modData.BurdJournals.skills = modData.BurdJournals.skills or {}
        for skillName, skillData in pairs(normalizedBackup.skills or {}) do
            modData.BurdJournals.skills[skillName] = {
                xp = skillData.xp,
                level = skillData.level
            }
        end

        -- Restore traits
        modData.BurdJournals.traits = modData.BurdJournals.traits or {}
        for traitId, value in pairs(normalizedBackup.traits or {}) do
            modData.BurdJournals.traits[traitId] = value
        end

        -- Restore recipes
        modData.BurdJournals.recipes = modData.BurdJournals.recipes or {}
        for recipeName, value in pairs(normalizedBackup.recipes or {}) do
            modData.BurdJournals.recipes[recipeName] = value
        end

        -- Restore stats
        modData.BurdJournals.stats = modData.BurdJournals.stats or {}
        for statId, statData in pairs(normalizedBackup.stats or {}) do
            modData.BurdJournals.stats[statId] = statData
        end

        modData.BurdJournals.claims = BurdJournals.normalizeTable(normalizedBackup.claims) or {}
        modData.BurdJournals.claimedSkills = BurdJournals.normalizeTable(normalizedBackup.claimedSkills) or {}
        modData.BurdJournals.claimedTraits = BurdJournals.normalizeTable(normalizedBackup.claimedTraits) or {}
        modData.BurdJournals.claimedRecipes = BurdJournals.normalizeTable(normalizedBackup.claimedRecipes) or {}
        modData.BurdJournals.claimedStats = BurdJournals.normalizeTable(normalizedBackup.claimedStats) or {}
    end

    if shouldRestoreDR then
        modData.BurdJournals.readCount = tonumber(normalizedBackup.readCount) or 0
        modData.BurdJournals.readSessionCount = tonumber(normalizedBackup.readSessionCount) or 0
        modData.BurdJournals.currentSessionId = normalizedBackup.currentSessionId
        modData.BurdJournals.currentSessionReadCount = tonumber(normalizedBackup.currentSessionReadCount) or 0

        local backupSkillReadCounts = normalizedBackup.skillReadCounts
        if type(backupSkillReadCounts) ~= "table" and BurdJournals.normalizeTable then
            backupSkillReadCounts = BurdJournals.normalizeTable(backupSkillReadCounts)
        end
        modData.BurdJournals.skillReadCounts = {}
        if type(backupSkillReadCounts) == "table" then
            for skillName, count in pairs(backupSkillReadCounts) do
                if skillName then
                    modData.BurdJournals.skillReadCounts[skillName] = tonumber(count) or 0
                end
            end
        end
    end

    -- Transmit restored data back to server
    if journal.transmitModData then
        journal:transmitModData()
    end

    BurdJournals.debugPrint("[BurdJournals] Successfully restored debug journal data from global cache")
    return true
end

-- Set skill level in journal
function BurdJournals.UI.DebugPanel.setJournalSkillLevel(self, skillName, level)
    local journal = self.editingJournal
    if not journal then return end
    
    -- Mark as debug-edited for persistence
    BurdJournals.UI.DebugPanel.markJournalAsDebugEdited(journal)
    
    local modData = journal:getModData()
    if not modData.BurdJournals then modData.BurdJournals = {} end
    if not modData.BurdJournals.skills then modData.BurdJournals.skills = {} end
    if BurdJournals.normalizeTable then
        modData.BurdJournals.skills = BurdJournals.normalizeTable(modData.BurdJournals.skills) or modData.BurdJournals.skills
    end
    local skillsTable = modData.BurdJournals.skills
    local skillKey = BurdJournals.UI.DebugPanel.resolveSkillKey(skillsTable, skillName)
    
    local targetLevel = math.floor(tonumber(level) or 0)
    if targetLevel < 0 then targetLevel = 0 end
    if targetLevel > 10 then targetLevel = 10 end

    -- Calculate XP for level using shared thresholds
    local xp = 0
    if targetLevel > 0 then
        if BurdJournals.getXPThresholdForLevel then
            xp = tonumber(BurdJournals.getXPThresholdForLevel(skillKey, targetLevel)) or 0
        else
            local isPassive = BurdJournals.isPassiveSkill and BurdJournals.isPassiveSkill(skillKey) or false
            if isPassive then
                xp = BurdJournals.PASSIVE_XP_THRESHOLDS and BurdJournals.PASSIVE_XP_THRESHOLDS[targetLevel] or (targetLevel * 7500)
            else
                xp = BurdJournals.STANDARD_XP_THRESHOLDS and BurdJournals.STANDARD_XP_THRESHOLDS[targetLevel] or (targetLevel * 150)
            end
        end
    end
    
    -- Keep skill at level 0 with 0 XP (don't auto-remove)
    skillsTable[skillKey] = {
        xp = math.max(0, tonumber(xp) or 0),
        level = targetLevel
    }

    -- Finalize edit: transmit and backup to global cache
    BurdJournals.UI.DebugPanel.finalizeJournalEdit(journal)

    -- Refresh display
    self:refreshJournalEditorData()
end

-- Set skill XP directly in journal
function BurdJournals.UI.DebugPanel:onJournalSetXP()
    local panel = self.journalPanel
    if not panel then return end
    
    local focusedSkill = panel.journalFocusedSkill
    if not focusedSkill then
        self:setStatus("No skill selected", {r=1, g=0.5, b=0.5})
        return
    end
    
    local journal = self.editingJournal
    if not journal then
        self:setStatus("No journal selected", {r=1, g=0.5, b=0.5})
        return
    end
    
    -- Mark as debug-edited for persistence
    BurdJournals.UI.DebugPanel.markJournalAsDebugEdited(journal)
    
    local xpText = panel.journalXPEntry:getText() or "0"
    local xp = math.max(0, tonumber(xpText) or 0)
    
    local modData = journal:getModData()
    if not modData.BurdJournals then modData.BurdJournals = {} end
    if not modData.BurdJournals.skills then modData.BurdJournals.skills = {} end
    if BurdJournals.normalizeTable then
        modData.BurdJournals.skills = BurdJournals.normalizeTable(modData.BurdJournals.skills) or modData.BurdJournals.skills
    end
    local skillsTable = modData.BurdJournals.skills
    local skillKey = BurdJournals.UI.DebugPanel.resolveSkillKey(skillsTable, focusedSkill)
    
    -- Calculate level from XP using shared helper
    local level = 0
    if BurdJournals.getSkillLevelFromXP then
        level = tonumber(BurdJournals.getSkillLevelFromXP(xp, skillKey)) or 0
    else
        local isPassive = BurdJournals.isPassiveSkill and BurdJournals.isPassiveSkill(skillKey) or false
        if isPassive then
            local thresholds = BurdJournals.PASSIVE_XP_THRESHOLDS or {}
            for l = 10, 1, -1 do
                if xp >= (thresholds[l] or (l * 7500)) then
                    level = l
                    break
                end
            end
        else
            local thresholds = BurdJournals.STANDARD_XP_THRESHOLDS or {}
            for l = 10, 1, -1 do
                if xp >= (thresholds[l] or (l * 150)) then
                    level = l
                    break
                end
            end
        end
    end
    level = math.max(0, math.min(10, math.floor(tonumber(level) or 0)))
    
    -- Keep skill even at 0 XP (don't auto-remove, use Remove button instead)
    skillsTable[skillKey] = {
        xp = xp,
        level = level
    }

    -- Finalize edit: transmit and backup to global cache
    BurdJournals.UI.DebugPanel.finalizeJournalEdit(journal)

    self:refreshJournalEditorData()
    self:setStatus("Set " .. tostring(focusedSkill) .. " to " .. xp .. " XP (Lv." .. level .. ")", {r=0.3, g=1, b=0.5})
end

function BurdJournals.UI.DebugPanel:onJournalSetDRStep()
    local panel = self.journalPanel
    if not panel or not panel.journalDRStepEntry then return end
    if not BurdJournals.UI.DebugPanel.isDiminishingEnabled() then return end

    local journal = self.editingJournal
    if not journal then
        self:setStatus("No journal selected", {r=1, g=0.5, b=0.5})
        return
    end

    local rawStep = tonumber(panel.journalDRStepEntry:getText() or "")
    if not rawStep then
        self:setStatus("Invalid DR step", {r=1, g=0.5, b=0.5})
        return
    end
    local stepValue = math.max(0, math.floor(rawStep))

    local mode = BurdJournals.getDiminishingTrackingMode and BurdJournals.getDiminishingTrackingMode() or 3
    local focusedSkill = panel.journalFocusedSkill
    if mode == 3 and not focusedSkill then
        self:setStatus("Select a skill first", {r=1, g=0.6, b=0.4})
        return
    end

    BurdJournals.UI.DebugPanel.markJournalAsDebugEdited(journal)
    local modData = journal:getModData()
    if not modData.BurdJournals then modData.BurdJournals = {} end
    local data = modData.BurdJournals

    if mode == 1 then
        data.readCount = stepValue
    elseif mode == 2 then
        data.readSessionCount = stepValue
        data.currentSessionId = nil
        data.currentSessionReadCount = 0
    else
        local skillReadCounts = data.skillReadCounts
        if type(skillReadCounts) ~= "table" and BurdJournals.normalizeTable then
            skillReadCounts = BurdJournals.normalizeTable(skillReadCounts)
        end
        if type(skillReadCounts) ~= "table" then
            skillReadCounts = {}
        end
        data.skillReadCounts = skillReadCounts
        local resolvedKey = BurdJournals.resolveSkillKey and BurdJournals.resolveSkillKey(skillReadCounts, focusedSkill) or nil
        skillReadCounts[resolvedKey or focusedSkill] = stepValue
    end

    BurdJournals.UI.DebugPanel.finalizeJournalEdit(journal)
    self:refreshJournalEditorData()
    self:setStatus("Updated DR step to " .. tostring(stepValue), {r=0.4, g=0.9, b=0.75})
end

function BurdJournals.UI.DebugPanel:onJournalDecrementDRStep()
    local panel = self.journalPanel
    if not panel or not panel.journalDRStepEntry then return end
    if not BurdJournals.UI.DebugPanel.isDiminishingEnabled() then return end

    local currentStep = math.max(0, math.floor(tonumber(panel.journalDRStepEntry:getText() or "") or 0))
    if currentStep <= 0 then
        self:setStatus("Already at DR step 0", {r=0.9, g=0.75, b=0.5})
        BurdJournals.UI.DebugPanel.updateJournalDiminishingLabel(self)
        return
    end

    panel.journalDRStepEntry:setText(tostring(currentStep - 1))
    self:onJournalSetDRStep()
end

function BurdJournals.UI.DebugPanel:onJournalIncrementDRStep()
    local panel = self.journalPanel
    if not panel or not panel.journalDRStepEntry then return end
    if not BurdJournals.UI.DebugPanel.isDiminishingEnabled() then return end

    local currentStep = tonumber(panel.journalDRStepEntry:getText() or "") or 0
    local nextStep = math.max(0, math.floor(currentStep)) + 1
    panel.journalDRStepEntry:setText(tostring(nextStep))

    self:onJournalSetDRStep()
end

function BurdJournals.UI.DebugPanel:onJournalPreviewDRClaims()
    local panel = self.journalPanel
    if not panel then return end
    if not BurdJournals.UI.DebugPanel.isDiminishingEnabled() then return end

    local journal = self.editingJournal
    if not journal then
        self:setStatus("No journal selected", {r=1, g=0.5, b=0.5})
        return
    end

    local mode = BurdJournals.getDiminishingTrackingMode and BurdJournals.getDiminishingTrackingMode() or 3
    local focusedSkill = panel.journalFocusedSkill
    if mode == 3 and not focusedSkill then
        self:setStatus("Select a skill first", {r=1, g=0.6, b=0.4})
        BurdJournals.UI.DebugPanel.updateJournalDiminishingLabel(self)
        return
    end

    local journalData = BurdJournals.getJournalData and BurdJournals.getJournalData(journal) or nil
    local previewPlayer = self.getSharedTargetPlayer and self:getSharedTargetPlayer() or nil
    local previewPercents = BurdJournals.UI.DebugPanel.getJournalDRPreviewPercents(journalData, focusedSkill, previewPlayer)
    BurdJournals.UI.DebugPanel.updateJournalDiminishingLabel(self)

    if not previewPercents or #previewPercents < 3 then
        self:setStatus("No DR data to preview", {r=0.9, g=0.75, b=0.5})
        return
    end

    self:setStatus(
        "Next claims: " .. tostring(previewPercents[1]) .. "% / " .. tostring(previewPercents[2]) .. "% / " .. tostring(previewPercents[3]) .. "%",
        {r=0.65, g=0.85, b=1}
    )
end

function BurdJournals.UI.DebugPanel:onJournalResetDR()
    if not BurdJournals.UI.DebugPanel.isDiminishingEnabled() then return end
    local journal = self.editingJournal
    if not journal then
        self:setStatus("No journal selected", {r=1, g=0.5, b=0.5})
        return
    end

    BurdJournals.UI.DebugPanel.markJournalAsDebugEdited(journal)
    local modData = journal:getModData()
    if not modData.BurdJournals then modData.BurdJournals = {} end
    local data = modData.BurdJournals

    data.readCount = 0
    data.readSessionCount = 0
    data.currentSessionId = nil
    data.currentSessionReadCount = 0
    data.skillReadCounts = {}

    BurdJournals.UI.DebugPanel.finalizeJournalEdit(journal)
    self:refreshJournalEditorData()
    self:setStatus("Reset journal DR tracking", {r=0.8, g=0.85, b=1})
end

-- Remove focused skill from journal
function BurdJournals.UI.DebugPanel:onJournalRemoveSkill()
    local panel = self.journalPanel
    if not panel then return end

    local focusedSkill = panel.journalFocusedSkill
    if not focusedSkill then
        self:setStatus("No skill selected", {r=1, g=0.5, b=0.5})
        return
    end

    local journal = self.editingJournal
    if not journal then
        self:setStatus("No journal selected", {r=1, g=0.5, b=0.5})
        return
    end

    -- Mark as debug-edited for persistence
    BurdJournals.UI.DebugPanel.markJournalAsDebugEdited(journal)

    local modData = journal:getModData()
    if modData.BurdJournals and modData.BurdJournals.skills then
        if BurdJournals.normalizeTable then
            modData.BurdJournals.skills = BurdJournals.normalizeTable(modData.BurdJournals.skills) or modData.BurdJournals.skills
        end
        local skillsTable = modData.BurdJournals.skills
        local skillKey = BurdJournals.UI.DebugPanel.resolveSkillKey(skillsTable, focusedSkill)
        if skillKey then
            skillsTable[skillKey] = nil
        end
        local focusedLower = string.lower(tostring(focusedSkill))
        local tableToScan = skillsTable
        if BurdJournals.normalizeTable then
            tableToScan = BurdJournals.normalizeTable(skillsTable) or skillsTable
        end
        for key, _ in pairs(tableToScan) do
            if string.lower(tostring(key)) == focusedLower then
                skillsTable[key] = nil
            end
        end
    end

    -- Finalize edit: transmit and backup to global cache
    BurdJournals.UI.DebugPanel.finalizeJournalEdit(journal)

    panel.journalFocusedSkill = nil
    self:refreshJournalEditorData()
    self:setStatus("Removed " .. focusedSkill .. " from journal", {r=1, g=0.7, b=0.3})
end

function BurdJournals.UI.DebugPanel.refreshJournalBulkToggles(self)
    local panel = self and self.journalPanel or nil
    if not panel then
        return
    end

    refreshDebugBulkTickState(panel.journalTraitBulkTick, panel.journalTraitList, function(row)
        return row.isPassiveSkillTrait ~= true
    end, function(row)
        return row.inJournal == true
    end)
    refreshDebugBulkTickState(panel.journalRecipeBulkTick, panel.journalRecipeList, nil, function(row)
        return row.inJournal == true
    end)
end

function BurdJournals.UI.DebugPanel.onJournalTraitBulkToggle(self, _index, selected)
    local panel = self and self.journalPanel or nil
    local journal = self and self.editingJournal or nil
    if not (panel and panel.journalTraitList and journal) then
        return
    end

    BurdJournals.UI.DebugPanel.markJournalAsDebugEdited(journal)
    local modData = journal:getModData()
    modData.BurdJournals = modData.BurdJournals or {}
    modData.BurdJournals.traits = modData.BurdJournals.traits or {}
    local traitsTable = modData.BurdJournals.traits
    local count = 0

    for _, itemData in ipairs(panel.journalTraitList.items or {}) do
        local row = itemData and itemData.item or nil
        if row and row.id and row.isPassiveSkillTrait ~= true and (selected == true and isDebugVisibleBulkRow(row) or selected ~= true) then
            if selected == true and row.inJournal ~= true then
                traitsTable[tostring(row.id)] = true
                row.inJournal = true
                count = count + 1
            elseif selected ~= true and row.inJournal == true then
                BurdJournals.UI.DebugPanel.removeTraitFromTable(traitsTable, row.id)
                row.inJournal = false
                count = count + 1
            end
        end
    end

    BurdJournals.UI.DebugPanel.finalizeJournalEdit(journal)
    self:refreshJournalEditorData()
    self:setStatus((selected and "Stored " or "Cleared ") .. tostring(count) .. (selected and " visible" or "") .. " journal trait(s)", {r=0.5, g=0.8, b=1})
end

function BurdJournals.UI.DebugPanel.onJournalRecipeBulkToggle(self, _index, selected)
    local panel = self and self.journalPanel or nil
    local journal = self and self.editingJournal or nil
    if not (panel and panel.journalRecipeList and journal) then
        return
    end

    BurdJournals.UI.DebugPanel.markJournalAsDebugEdited(journal)
    local modData = journal:getModData()
    modData.BurdJournals = modData.BurdJournals or {}
    modData.BurdJournals.recipes = modData.BurdJournals.recipes or {}
    local recipesTable = modData.BurdJournals.recipes
    local count = 0

    for _, itemData in ipairs(panel.journalRecipeList.items or {}) do
        local row = itemData and itemData.item or nil
        if row and row.name and (selected == true and isDebugVisibleBulkRow(row) or selected ~= true) then
            if selected == true and row.inJournal ~= true then
                local recipeName = BurdJournals.getRecipeCanonicalName and BurdJournals.getRecipeCanonicalName(row.name) or row.name
                recipesTable[tostring(recipeName)] = true
                row.inJournal = true
                count = count + 1
            elseif selected ~= true and row.inJournal == true then
                local recipeKey = BurdJournals.UI.DebugPanel.resolveRecipeKey(recipesTable, row.name)
                if recipeKey then
                    recipesTable[recipeKey] = nil
                end
                row.inJournal = false
                count = count + 1
            end
        end
    end

    BurdJournals.UI.DebugPanel.finalizeJournalEdit(journal)
    self:refreshJournalEditorData()
    self:setStatus((selected and "Stored " or "Cleared ") .. tostring(count) .. (selected and " visible" or "") .. " journal recipe(s)", {r=0.5, g=0.8, b=1})
end

function BurdJournals.UI.DebugPanel.drawJournalTraitItem(self, y, item, alt)
    local h = getDebugListRowHeight(self, item, 24)
    if not item or not item.item then return y + h end
    local data = item.item
    if not data or data.hidden then return y + h end

    local w = self.width or 300
    local scrollOffset = BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH or 15

    if data.isPassiveSkillTrait then
        self:drawRect(0, y, w, h, 0.15, 0.15, 0.15, 0.16)
    elseif data.inJournal then
        self:drawRect(0, y, w, h, 0.12, 0.2, 0.12, 0.3)
    elseif self.mouseoverselected == item.index then
        self:drawRect(0, y, w, h, 0.2, 0.2, 0.3, 0.3)
    end

    if data.inJournal then
        self:drawText("[X]", 8, y + 4, 0.45, 0.85, 0.45, 1, UIFont.Small)
    else
        self:drawText("[ ]", 8, y + 4, 0.58, 0.58, 0.58, 1, UIFont.Small)
    end

    local iconX = 32
    local iconSize = drawDebugListIcon(self, data.traitTexture or getDebugTraitTexture(data.id), iconX, y, h, 0.95, 14)
    local textX = iconX + math.max(iconSize, 14) + 6

    local nameColor = BurdJournals.UI.DebugPanel.getTraitPolarityColor(data)
    if data.inJournal then
        nameColor = {0.9, 1, 0.9}
    end
    self:drawText(BurdJournals.UI.DebugPanel.getTraitPolarityPrefix(data) .. " " .. tostring(data.displayName or data.id or "Unknown"), textX, y + 4, nameColor[1], nameColor[2], nameColor[3], 1, UIFont.Small)

    local statusX = w - 104 - scrollOffset
    if data.isPassiveSkillTrait then
        self:drawText("Passive", statusX, y + 4, 0.45, 0.45, 0.45, 0.85, UIFont.Small)
    elseif data.inJournal then
        self:drawText("Stored", statusX, y + 4, 0.52, 0.82, 0.52, 1, UIFont.Small)
    else
        self:drawText(BurdJournals.UI.DebugPanel.getTraitPolarityText(data), statusX, y + 4, nameColor[1], nameColor[2], nameColor[3], 0.95, UIFont.Small)
    end
    return y + h
end

function BurdJournals.UI.DebugPanel.onJournalTraitListClick(self, x, y)
    local row = BurdJournals.UI.DebugPanel.safeListMouseDown(self, x, y)

    if not self.items then return end
    if not row or row <= 0 or row > #self.items then return end

    local item = self.items[row]
    local data = item and item.item or nil
    local parentPanel = self.parentPanel
    local journal = parentPanel and parentPanel.editingJournal or nil
    if not (data and parentPanel and journal) then return end

    if data.isPassiveSkillTrait then
        parentPanel:setStatus("Passive skill traits cannot be modified in journals", {r=1, g=0.6, b=0.3})
        return
    end

    BurdJournals.UI.DebugPanel.markJournalAsDebugEdited(journal)
    local modData = journal:getModData()
    modData.BurdJournals = modData.BurdJournals or {}
    modData.BurdJournals.traits = modData.BurdJournals.traits or {}
    local traitsTable = modData.BurdJournals.traits

    if data.inJournal then
        BurdJournals.UI.DebugPanel.removeTraitFromTable(traitsTable, data.id)
        data.inJournal = false
        BurdJournals.UI.DebugPanel.finalizeJournalEdit(journal)
        parentPanel:refreshJournalEditorData()
        BurdJournals.UI.DebugPanel.refreshJournalBulkToggles(parentPanel)
        parentPanel:setStatus("Removed trait: " .. tostring(data.displayName or data.id), {r=1, g=0.7, b=0.3})
    else
        traitsTable[tostring(data.id)] = true
        data.inJournal = true
        BurdJournals.UI.DebugPanel.finalizeJournalEdit(journal)
        parentPanel:refreshJournalEditorData()
        BurdJournals.UI.DebugPanel.refreshJournalBulkToggles(parentPanel)
        parentPanel:setStatus("Added trait: " .. tostring(data.displayName or data.id), {r=0.3, g=1, b=0.5})
    end
end

function BurdJournals.UI.DebugPanel.drawJournalRecipeItem(self, y, item, alt)
    local h = getDebugListRowHeight(self, item, 30)
    if not item or not item.item then return y + h end
    local data = item.item
    if not data or data.hidden then return y + h end

    local w = self.width or 300
    local scrollOffset = BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH or 15

    if data.inJournal then
        self:drawRect(0, y, w, h, 0.12, 0.2, 0.12, 0.28)
    elseif self.mouseoverselected == item.index then
        self:drawRect(0, y, w, h, 0.2, 0.2, 0.3, 0.3)
    end

    if data.inJournal then
        self:drawText("[X]", 8, y + 2, 0.45, 0.85, 0.45, 1, UIFont.Small)
    else
        self:drawText("[ ]", 8, y + 2, 0.58, 0.58, 0.58, 1, UIFont.Small)
    end

    local iconX = 32
    local recipeIcon = data.recipeTexture or getDebugRecipeTexture()
    local recipeIconSize = drawDebugListIcon(self, recipeIcon, iconX, y, h, 0.95, 14)
    local textX = iconX + math.max(recipeIconSize, 14) + 6
    if data.magazineSource then
        local magazineIcon = data.magazineTexture or getDebugMagazineTexture(data.magazineSource)
        local magSize = drawDebugListIcon(self, magazineIcon, textX, y, h, 0.9, 14)
        if magSize > 0 then
            textX = textX + magSize + 6
        end
    end

    self:drawText(tostring(data.displayName or data.name or "Unknown Recipe"), textX, y + 2, data.inJournal and 0.82 or 0.92, data.inJournal and 1 or 0.92, data.inJournal and 0.82 or 0.92, 1, UIFont.Small)
    local sourceText = getDebugRecipeSourceText(data, 22)
    local sourceColor = data.magazineDisplayName and {0.5, 0.7, 0.75}
        or ((data.source and data.source ~= "Vanilla" and data.source ~= "Runtime" and data.source ~= "Unknown")
            and {0.82, 0.72, 0.5}
            or {0.55, 0.65, 0.78})
    self:drawText(sourceText, textX, y + 15, sourceColor[1], sourceColor[2], sourceColor[3], 0.9, UIFont.Small)

    local rightLabel = data.inJournal and "Stored" or (data.isKnown and "Known" or (data.hasMagazine and "Available" or "Piped"))
    self:drawText(rightLabel, w - 104 - scrollOffset, y + 2, 0.68, 0.82, 0.95, 0.9, UIFont.Small)
    return y + h
end

function BurdJournals.UI.DebugPanel.onJournalRecipeListClick(self, x, y)
    local row = BurdJournals.UI.DebugPanel.safeListMouseDown(self, x, y)

    if not self.items then return end
    if not row or row <= 0 or row > #self.items then return end

    local item = self.items[row]
    local data = item and item.item or nil
    local parentPanel = self.parentPanel
    local journal = parentPanel and parentPanel.editingJournal or nil
    if not (data and parentPanel and journal and data.name) then return end

    BurdJournals.UI.DebugPanel.markJournalAsDebugEdited(journal)
    local modData = journal:getModData()
    modData.BurdJournals = modData.BurdJournals or {}
    modData.BurdJournals.recipes = modData.BurdJournals.recipes or {}
    local recipesTable = modData.BurdJournals.recipes

    if data.inJournal then
        local recipeKey = BurdJournals.UI.DebugPanel.resolveRecipeKey(recipesTable, data.name)
        if recipeKey then
            recipesTable[recipeKey] = nil
        end
        data.inJournal = false
        BurdJournals.UI.DebugPanel.finalizeJournalEdit(journal)
        parentPanel:refreshJournalEditorData()
        BurdJournals.UI.DebugPanel.refreshJournalBulkToggles(parentPanel)
        parentPanel:setStatus("Removed recipe: " .. tostring(data.displayName or data.name), {r=1, g=0.7, b=0.3})
    else
        local recipeName = BurdJournals.getRecipeCanonicalName and BurdJournals.getRecipeCanonicalName(data.name) or data.name
        recipesTable[tostring(recipeName)] = true
        data.inJournal = true
        BurdJournals.UI.DebugPanel.finalizeJournalEdit(journal)
        parentPanel:refreshJournalEditorData()
        BurdJournals.UI.DebugPanel.refreshJournalBulkToggles(parentPanel)
        parentPanel:setStatus("Added recipe: " .. tostring(data.displayName or data.name), {r=0.3, g=1, b=0.5})
    end
end

-- Draw function for AVAILABLE traits (left column - traits to add)
function BurdJournals.UI.DebugPanel.drawJournalAvailTraitItem(self, y, item, alt)
    local h = getDebugListRowHeight(self, item, 22)

    -- CRITICAL: y must be a valid number for ISScrollingListBox to work correctly
    -- Return y + h (not just h) to maintain proper list positioning
    y = tonumber(y) or 0
    if y ~= y then y = 0 end  -- NaN check

    -- Item validation - return valid y + h even for invalid items
    if not item or not item.item then return y + h end
    local data = item.item
    if not data then return y + h end
    if data.hidden then return y + h end

    local w = tonumber(self.width) or 200
    if w <= 0 then w = 200 end
    local scrollOffset = tonumber(BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH) or 15
    local displayName = BurdJournals.UI.DebugPanel.getTraitPolarityPrefix(data) .. " " .. tostring(data.displayName or data.id or "Unknown")

    -- Background on hover (check item.index exists)
    local itemIndex = tonumber(item.index)
    if itemIndex and self.mouseoverselected == itemIndex then
        self:drawRect(0, y, w, h, 0.15, 0.2, 0.15, 0.3)
    end

    -- Trait name
    local nameColor = BurdJournals.UI.DebugPanel.getTraitPolarityColor(data)
    self:drawText(displayName, 6, y + 3, nameColor[1], nameColor[2], nameColor[3], 1, UIFont.Small)

    -- Add button
    local btnX = w - 40 - scrollOffset
    local btnW = 35
    local btnY = y + 2
    local btnH = h - 4

    if btnX > 0 and btnW > 0 and btnH > 0 then
        self:drawRect(btnX, btnY, btnW, btnH, 0.5, 0.2, 0.4, 0.2)
        self:drawRectBorder(btnX, btnY, btnW, btnH, 0.5, 0.7, 0.5, 0.8)
        self:drawTextCentre("+", btnX + btnW / 2, y + 3, 0.4, 0.9, 0.4, 1, UIFont.Small)
    end

    return y + h
end

-- Draw function for IN JOURNAL traits (right column - traits to remove)
function BurdJournals.UI.DebugPanel.drawJournalInTraitItem(self, y, item, alt)
    local h = getDebugListRowHeight(self, item, 22)

    -- CRITICAL: y must be a valid number for ISScrollingListBox to work correctly
    -- Return y + h (not just h) to maintain proper list positioning
    y = tonumber(y) or 0
    if y ~= y then y = 0 end  -- NaN check

    -- Item validation - return valid y + h even for invalid items
    if not item or not item.item then return y + h end
    local data = item.item
    if not data then return y + h end
    if data.hidden then return y + h end

    local w = tonumber(self.width) or 200
    if w <= 0 then w = 200 end
    local scrollOffset = tonumber(BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH) or 15
    local displayName = BurdJournals.UI.DebugPanel.getTraitPolarityPrefix(data) .. " " .. tostring(data.displayName or data.id or "Unknown")

    -- Green background to show it's in journal
    self:drawRect(0, y, w, h, 0.1, 0.2, 0.1, 0.4)

    -- Hover highlight (check item.index exists)
    local itemIndex = tonumber(item.index)
    if itemIndex and self.mouseoverselected == itemIndex then
        self:drawRect(0, y, w, h, 0.2, 0.15, 0.15, 0.3)
    end

    -- Trait name
    local nameColor = data.isPositive == false and {1, 0.82, 0.82} or {0.9, 1, 0.9}
    self:drawText(displayName, 6, y + 3, nameColor[1], nameColor[2], nameColor[3], 1, UIFont.Small)

    -- Remove button
    local btnX = w - 40 - scrollOffset
    local btnW = 35
    local btnY = y + 2
    local btnH = h - 4

    if btnX > 0 and btnW > 0 and btnH > 0 then
        self:drawRect(btnX, btnY, btnW, btnH, 0.7, 0.3, 0.2, 0.3)
        self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.4, 0.3, 0.8)
        self:drawTextCentre("-", btnX + btnW / 2, y + 3, 1, 0.5, 0.4, 1, UIFont.Small)
    end

    return y + h
end

-- Click handler for AVAILABLE traits list (add trait to journal)
function BurdJournals.UI.DebugPanel.onJournalAvailTraitListClick(self, x, y)
    local row = BurdJournals.UI.DebugPanel.safeListMouseDown(self, x, y)
    
    if not self.items then return end
    if not row or row <= 0 or row > #self.items then return end
    
    local item = self.items[row]
    if not item or not item.item then return end
    local data = item.item
    if not data then return end
    
    local parentPanel = self.parentPanel
    if not parentPanel then return end
    local journal = parentPanel.editingJournal
    if not journal then return end
    
    -- Check if click is in button area
    local w = self.width or 200
    local scrollOffset = BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH or 15
    local btnX = w - 40 - scrollOffset
    
    if x >= btnX then
        -- Mark as debug-edited for persistence
        BurdJournals.UI.DebugPanel.markJournalAsDebugEdited(journal)

        local modData = journal:getModData()
        if not modData.BurdJournals then modData.BurdJournals = {} end
        if not modData.BurdJournals.traits then modData.BurdJournals.traits = {} end
        if BurdJournals.normalizeTable then
            modData.BurdJournals.traits = BurdJournals.normalizeTable(modData.BurdJournals.traits) or modData.BurdJournals.traits
        end

        local traitId = data.id or data.key or data.displayName
        if not traitId then return end
        traitId = BurdJournals.UI.DebugPanel.normalizeTraitId(traitId) or traitId

        -- Prevent adding duplicate trait (including aliases)
        local lookup = BurdJournals.UI.DebugPanel.buildTraitLookup(modData.BurdJournals.traits)
        if BurdJournals.UI.DebugPanel.isTraitInLookup(lookup, traitId) then
            parentPanel:setStatus("Trait already in journal: " .. (data.displayName or tostring(traitId)), {r=1, g=0.7, b=0.3})
            return
        end

        -- Add trait to journal
        modData.BurdJournals.traits[traitId] = true
        parentPanel:setStatus("Added trait: " .. (data.displayName or tostring(traitId)), {r=0.3, g=1, b=0.5})

        -- Finalize edit: transmit and backup to global cache
        BurdJournals.UI.DebugPanel.finalizeJournalEdit(journal)

        parentPanel:refreshJournalEditorData()
    end
end

-- Click handler for IN JOURNAL traits list (remove trait from journal)
function BurdJournals.UI.DebugPanel.onJournalInTraitListClick(self, x, y)
    local row = BurdJournals.UI.DebugPanel.safeListMouseDown(self, x, y)
    
    if not self.items then return end
    if not row or row <= 0 or row > #self.items then return end
    
    local item = self.items[row]
    if not item or not item.item then return end
    local data = item.item
    if not data then return end
    
    local parentPanel = self.parentPanel
    if not parentPanel then return end
    local journal = parentPanel.editingJournal
    if not journal then return end
    
    -- Check if click is in button area
    local w = self.width or 200
    local scrollOffset = BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH or 15
    local btnX = w - 40 - scrollOffset
    
    if x >= btnX then
        -- Mark as debug-edited for persistence
        BurdJournals.UI.DebugPanel.markJournalAsDebugEdited(journal)

        local modData = journal:getModData()
        if modData.BurdJournals and modData.BurdJournals.traits then
            if BurdJournals.normalizeTable then
                modData.BurdJournals.traits = BurdJournals.normalizeTable(modData.BurdJournals.traits) or modData.BurdJournals.traits
            end
            local traitId = data.id or data.key or data.displayName
            if not traitId then return end
            traitId = BurdJournals.UI.DebugPanel.normalizeTraitId(traitId) or traitId

            -- Remove trait from journal (including aliases)
            BurdJournals.UI.DebugPanel.removeTraitFromTable(modData.BurdJournals.traits, traitId)
            parentPanel:setStatus("Removed trait: " .. (data.displayName or tostring(traitId)), {r=1, g=0.7, b=0.3})

            -- Finalize edit: transmit and backup to global cache
            BurdJournals.UI.DebugPanel.finalizeJournalEdit(journal)

            parentPanel:refreshJournalEditorData()
        end
    end
end

-- Journal command handler (clear skills, clear traits)
function BurdJournals.UI.DebugPanel:onJournalCmd(button)
    local cmd = button.internal
    local journal = self.editingJournal
    
    if not journal then
        self:setStatus("No journal selected", {r=1, g=0.5, b=0.5})
        return
    end
    
    -- Mark as debug-edited for persistence
    BurdJournals.UI.DebugPanel.markJournalAsDebugEdited(journal)
    
    local modData = journal:getModData()
    if not modData.BurdJournals then modData.BurdJournals = {} end
    
    if cmd == "clearskills" then
        modData.BurdJournals.skills = {}
        if self.journalPanel then
            self.journalPanel.journalFocusedSkill = nil
        end
        self:setStatus("Cleared all skills from journal", {r=1, g=0.7, b=0.3})
    elseif cmd == "cleartraits" then
        modData.BurdJournals.traits = {}
        self:setStatus("Cleared all traits from journal", {r=1, g=0.7, b=0.3})
    elseif cmd == "clearrecipes" then
        modData.BurdJournals.recipes = {}
        self:setStatus("Cleared all recipes from journal", {r=1, g=0.7, b=0.3})
    end

    -- Finalize edit: transmit and backup to global cache
    BurdJournals.UI.DebugPanel.finalizeJournalEdit(journal)

    self:refreshJournalEditorData()
end

-- Refresh button handler
function BurdJournals.UI.DebugPanel:onJournalRefresh()
    self:refreshJournalPickerList(true)
    self:onJournalRefreshServerIndex()
    self:refreshJournalEditorData()
    self:setStatus("Journal data refreshed", {r=0.5, g=0.8, b=1})
end

-- ============================================================================
-- Add Skill Popup for Journal Editor
-- ============================================================================

-- Open the Add Skill popup
function BurdJournals.UI.DebugPanel:onJournalAddSkillPopup()
    local journal = self.editingJournal
    if not journal then
        self:setStatus("Select a journal first", {r=1, g=0.5, b=0.5})
        return
    end
    
    -- Close existing popup if open
    if self.addSkillPopup and self.addSkillPopup:isVisible() then
        self.addSkillPopup:close()
    end
    
    -- Get skills already in journal
    local journalData = BurdJournals.getJournalData(journal)
    local existingSkills = {}
    if journalData then
        local normalized = BurdJournals.normalizeJournalData(journalData) or journalData
        local skillsTable = normalized.skills or {}
        for skillName, _ in pairs(skillsTable) do
            local skillLower = string.lower(tostring(skillName))
            existingSkills[skillLower] = true
            if BurdJournals.mapPerkIdToSkillName then
                local mapped = BurdJournals.mapPerkIdToSkillName(skillName)
                if mapped then
                    existingSkills[string.lower(mapped)] = true
                end
            end
            if BurdJournals.SKILL_TO_PERK and BurdJournals.SKILL_TO_PERK[skillName] then
                existingSkills[string.lower(BurdJournals.SKILL_TO_PERK[skillName])] = true
            end
        end
    end
    
    -- Create popup panel
    local popupWidth = 300
    local popupHeight = 350
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local popupX = (screenW - popupWidth) / 2
    local popupY = (screenH - popupHeight) / 2
    
    local popup = ISPanel:new(popupX, popupY, popupWidth, popupHeight)
    popup:initialise()
    popup:instantiate()
    popup.backgroundColor = {r=0.1, g=0.1, b=0.12, a=0.98}
    popup.borderColor = {r=0.4, g=0.5, b=0.6, a=1}
    popup:setAlwaysOnTop(true)
    popup:addToUIManager()
    popup.parentPanel = self
    
    local padding = 10
    local y = padding
    
    -- Title
    local titleLabel = ISLabel:new(padding, y, 22, "Add Skill to Journal", 0.9, 0.8, 0.6, 1, UIFont.Medium, true)
    titleLabel:initialise()
    titleLabel:instantiate()
    popup:addChild(titleLabel)
    
    -- Close button (X)
    local closeBtn = ISButton:new(popupWidth - 30, 5, 22, 22, "X", self, function()
        if popup and popup.close then
            popup:close()
        end
    end)
    closeBtn:initialise()
    closeBtn:instantiate()
    closeBtn.font = UIFont.Small
    closeBtn.textColor = {r=1, g=0.5, b=0.5, a=1}
    closeBtn.borderColor = {r=0.5, g=0.3, b=0.3, a=1}
    closeBtn.backgroundColor = {r=0.3, g=0.1, b=0.1, a=0.8}
    closeBtn.parent = popup
    popup:addChild(closeBtn)
    y = y + 28
    
    -- Search field
    local searchLabel = ISLabel:new(padding, y, 18, "Search:", 0.7, 0.7, 0.7, 1, UIFont.Small, true)
    searchLabel:initialise()
    searchLabel:instantiate()
    popup:addChild(searchLabel)
    
    popup.skillSearchEntry = ISTextEntryBox:new("", padding + 50, y - 2, popupWidth - padding * 2 - 50, 20)
    popup.skillSearchEntry:initialise()
    popup.skillSearchEntry:instantiate()
    popup.skillSearchEntry.font = UIFont.Small
    popup.skillSearchEntry:setTooltip("Type to filter skills...")
    popup.skillSearchEntry.onTextChange = function()
        BurdJournals.UI.DebugPanel.filterAddSkillPopupList(self, popup)
    end
    popup:addChild(popup.skillSearchEntry)
    y = y + 26
    
    -- Skill list
    local listHeight = popupHeight - y - 50
    popup.skillList = ISScrollingListBox:new(padding, y, popupWidth - padding * 2, listHeight)
    popup.skillList:initialise()
    popup.skillList:instantiate()
    popup.skillList.itemheight = 24
    popup.skillList.backgroundColor = {r=0.06, g=0.06, b=0.08, a=1}
    popup.skillList.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    popup.skillList.doDrawItem = BurdJournals.UI.DebugPanel.drawAddSkillPopupItem
    popup.skillList.onMouseDown = BurdJournals.UI.DebugPanel.onAddSkillPopupListClick
    popup.skillList.parentPanel = self
    popup.skillList.popup = popup
    popup:addChild(popup.skillList)
    y = y + listHeight + 8
    
    -- Populate with available skills (not already in journal)
    local allSkills = BurdJournals.UI.DebugPanel.getAvailableSkills()
    for _, skillName in ipairs(allSkills) do
        local skillLower = string.lower(tostring(skillName))
        local skip = existingSkills[skillLower]
        if not skip and BurdJournals.SKILL_TO_PERK and BurdJournals.SKILL_TO_PERK[skillName] then
            skip = existingSkills[string.lower(BurdJournals.SKILL_TO_PERK[skillName])] or skip
        end
        if not skip and BurdJournals.mapPerkIdToSkillName then
            local mapped = BurdJournals.mapPerkIdToSkillName(skillName)
            if mapped then
                skip = existingSkills[string.lower(mapped)] or skip
            end
        end
        if not skip and BurdJournals.isSkillEnabledForJournal and not BurdJournals.isSkillEnabledForJournal(journalData, skillName) then
            skip = true
        end

        if not skip then
            local displayName = BurdJournals.getPerkDisplayName and BurdJournals.getPerkDisplayName(skillName) or tostring(skillName)
            local isPassive = BurdJournals.isPassiveSkill and BurdJournals.isPassiveSkill(skillName) or false

            popup.skillList:addItem(displayName, {
                name = skillName,
                displayName = displayName,
                isPassive = isPassive
            })
        end
    end
    
    -- Close function
    popup.close = function(self)
        self:setVisible(false)
        self:removeFromUIManager()
    end
    
    self.addSkillPopup = popup
end

-- Filter Add Skill popup list
function BurdJournals.UI.DebugPanel.filterAddSkillPopupList(self, popup)
    if not popup or not popup.skillSearchEntry or not popup.skillList then return end
    
    local searchText = popup.skillSearchEntry:getText() or ""
    
    applyDebugRowFilter(popup.skillList, function(row)
        return searchText == "" or debugSearchMatches(searchText, row.displayName, row.name)
    end)
end

-- Draw item for Add Skill popup
function BurdJournals.UI.DebugPanel.drawAddSkillPopupItem(self, y, item, alt)
    local h = getDebugListRowHeight(self, item, 24)

    -- Defensive checks for all parameters
    y = tonumber(y) or 0
    if y ~= y then y = 0 end  -- NaN check
    if not item then return y + h end
    if not item.item then return y + h end
    local data = item.item
    if not data then return y + h end
    if data.hidden then return y + h end
    
    local w = tonumber(self.width) or 280
    if w <= 0 then w = 280 end
    local scrollOffset = BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH or 15
    local displayName = tostring(data.displayName or data.name or "Unknown")
    
    -- Hover highlight (check item.index exists)
    if item.index and self.mouseoverselected == item.index then
        self:drawRect(0, y, w, h, 0.15, 0.2, 0.15, 0.4)
    end

    -- Skill name
    local nameColor = data.isPassive and {0.7, 0.8, 1} or {0.9, 0.9, 0.9}
    self:drawText(displayName, 8, y + 4, nameColor[1], nameColor[2], nameColor[3], 1, UIFont.Small)

    -- Passive indicator
    if data.isPassive then
        self:drawText("[P]", w - 50 - scrollOffset, y + 4, 0.5, 0.6, 0.8, 0.7, UIFont.Small)
    end

    -- Add button
    local btnX = w - 35 - scrollOffset
    local btnW = 30
    local btnY = y + 3
    local btnH = h - 6

    if btnX > 0 and btnW > 0 and btnH > 0 then
        self:drawRect(btnX, btnY, btnW, btnH, 0.2, 0.4, 0.2, 0.5)
        self:drawRectBorder(btnX, btnY, btnW, btnH, 0.4, 0.7, 0.4, 0.8)
        self:drawTextCentre("+", btnX + btnW / 2, y + 4, 0.5, 1, 0.5, 1, UIFont.Small)
    end
    
    return y + h
end

-- Click handler for Add Skill popup list
function BurdJournals.UI.DebugPanel.onAddSkillPopupListClick(self, x, y)
    local row = BurdJournals.UI.DebugPanel.safeListMouseDown(self, x, y)
    
    if not self.items then return end
    if not row or row <= 0 or row > #self.items then return end
    
    local item = self.items[row]
    if not item or not item.item then return end
    local data = item.item
    if not data then return end
    
    local parentPanel = self.parentPanel
    if not parentPanel then return end
    local popup = self.popup
    local journal = parentPanel.editingJournal
    if not journal then return end
    
    -- Check if click is in button area
    local w = self.width or 280
    local scrollOffset = BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH or 15
    local btnX = w - 35 - scrollOffset
    
    if x >= btnX then
        local journalData = BurdJournals.getJournalData(journal)
        if BurdJournals.isSkillEnabledForJournal and not BurdJournals.isSkillEnabledForJournal(journalData, data.name) then
            parentPanel:setStatus("Passive skills are disabled for this journal type", {r=1, g=0.7, b=0.3})
            return
        end
        -- Mark as debug-edited for persistence
        BurdJournals.UI.DebugPanel.markJournalAsDebugEdited(journal)
        
        local modData = journal:getModData()
        if not modData.BurdJournals then modData.BurdJournals = {} end
        if not modData.BurdJournals.skills then modData.BurdJournals.skills = {} end
        if BurdJournals.normalizeTable then
            modData.BurdJournals.skills = BurdJournals.normalizeTable(modData.BurdJournals.skills) or modData.BurdJournals.skills
        end

        local skillsTable = modData.BurdJournals.skills
        local skillKey = BurdJournals.UI.DebugPanel.resolveSkillKey(skillsTable, data.name)
        if skillsTable[skillKey] then
            parentPanel:setStatus("Skill already in journal: " .. (data.displayName or data.name), {r=1, g=0.7, b=0.3})
            return
        end

        -- Add skill to journal with level 0 and 0 XP
        skillsTable[skillKey] = {
            xp = 0,
            level = 0
        }

        parentPanel:setStatus("Added skill: " .. (data.displayName or data.name), {r=0.3, g=1, b=0.5})

        -- Finalize edit: transmit and backup to global cache
        BurdJournals.UI.DebugPanel.finalizeJournalEdit(journal)

        -- Remove from popup list and refresh main panel
        for i, listItem in ipairs(self.items) do
            if listItem.item and listItem.item.name == data.name then
                table.remove(self.items, i)
                break
            end
        end
        
        parentPanel:refreshJournalEditorData()
    end
end

-- ============================================================================
-- ============================================================================
-- Tab 6: Whitelist Panel
-- ============================================================================

local function getWhitelistPolicyLabel(policy)
    if policy == "allow" then return debugText("UI_BurdJournals_DebugWhitelistPolicyAllow", "Allow") end
    if policy == "ban" then return debugText("UI_BurdJournals_DebugWhitelistPolicyBan", "Ban") end
    return debugText("UI_BurdJournals_DebugWhitelistPolicyInherit", "Inherit")
end

local function getWhitelistKindForContent(contentType)
    if contentType == "skills" then return "skills" end
    if contentType == "traits" then return "traits" end
    if contentType == "recipes" then return "recipes" end
    return nil
end

local function getWhitelistRowId(row)
    if type(row) ~= "table" then return nil end
    return row.name or row.id
end

local function getWhitelistJournalContext(scope)
    return scope == "player"
        and { isPlayerCreated = true }
        or { isWorn = true }
end

local function getWhitelistSandboxReasonOptions(row, scope)
    local kind = getWhitelistKindForContent(row and row.kind)
    local id = getWhitelistRowId(row)
    if not (kind and id and BurdJournals.getEntrySandboxBlockReasons) then return nil end
    return BurdJournals.getEntrySandboxBlockReasons(kind, id, scope, getWhitelistJournalContext(scope))
end

local function getWhitelistSandboxOptionLabel(optionName)
    local key = "Sandbox_BurdJournals_" .. tostring(optionName or "")
    local label = getText and getText(key) or nil
    if label and label ~= key then
        return label
    end
    return tostring(optionName or "")
end

local function getWhitelistSandboxReasonText(row, scope)
    local options = getWhitelistSandboxReasonOptions(row, scope)
    if type(options) ~= "table" or #options == 0 then return nil end
    local lines = {
        debugText("UI_BurdJournals_DebugWhitelistSandboxBlocked", "Sandbox settings block this entry; change sandbox settings first."),
        debugText("UI_BurdJournals_DebugWhitelistSandboxBlockedBy", "Blocked by sandbox option(s):"),
    }
    for _, optionName in ipairs(options) do
        lines[#lines + 1] = "- " .. getWhitelistSandboxOptionLabel(optionName) .. " (" .. tostring(optionName) .. ")"
    end
    return table.concat(lines, "\n")
end

local function getWhitelistCellStatus(row, scope)
    local kind = getWhitelistKindForContent(row and row.kind)
    local id = getWhitelistRowId(row)
    if not (kind and id) then return "blocked", "Invalid" end
    local context = getWhitelistJournalContext(scope)
    if BurdJournals.isEntrySandboxBlocked and BurdJournals.isEntrySandboxBlocked(kind, id, scope, context) then
        return "sandbox", debugText("UI_BurdJournals_DebugWhitelistPolicySandbox", "Sandbox"), getWhitelistSandboxReasonText(row, scope)
    end
    local policy = BurdJournals.getAdminPolicy and BurdJournals.getAdminPolicy(kind, id, scope) or nil
    return policy or "inherit", getWhitelistPolicyLabel(policy)
end

local function getWhitelistPolicyColor(status)
    if status == "allow" then return 0.35, 0.82, 0.46 end
    if status == "ban" then return 0.95, 0.34, 0.28 end
    if status == "sandbox" then return 0.72, 0.56, 0.34 end
    return 0.58, 0.68, 0.78
end

local function addWhitelistRowsToList(list, rows, kind)
    if not list then return end
    list:clear()
    for _, row in ipairs(rows or {}) do
        row.kind = kind
        list:addItem(row.displayName or row.name or row.id or "Unknown", row)
    end
end

function BurdJournals.UI.DebugPanel:createWhitelistPanel(y, height)
    local panel = ISPanel:new(5, y, self.width - 10, height)
    panel:initialise()
    panel:instantiate()
    panel.backgroundColor = {r=0.08, g=0.08, b=0.1, a=0.85}
    panel.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    panel:setVisible(false)
    self:addChild(panel)
    self.tabPanels["whitelist"] = panel
    self.whitelistPanel = panel

    local padding = 12
    local contentWidth = panel.width - padding * 2
    local yPos = padding
    local tabW = 86
    panel.whitelistTabState = {buttons = {}, panels = {}, current = "skills"}
    panel.whitelistTabState.buttons.skills = createDebugButton(panel, padding, yPos, tabW, 22, debugText("UI_BurdJournals_DebugWhitelistSkills", "Skills"), self, BurdJournals.UI.DebugPanel.onWhitelistSubTab, "skills")
    panel.whitelistTabState.buttons.traits = createDebugButton(panel, padding + tabW + 6, yPos, tabW, 22, debugText("UI_BurdJournals_DebugWhitelistTraits", "Traits"), self, BurdJournals.UI.DebugPanel.onWhitelistSubTab, "traits")
    panel.whitelistTabState.buttons.recipes = createDebugButton(panel, padding + (tabW + 6) * 2, yPos, tabW, 22, debugText("UI_BurdJournals_DebugWhitelistRecipes", "Recipes"), self, BurdJournals.UI.DebugPanel.onWhitelistSubTab, "recipes")
    local refreshTitle = debugText("UI_BurdJournals_DebugWhitelistRefresh", "Refresh")
    local resetTitle = debugText("UI_BurdJournals_DebugWhitelistResetAll", "Reset All")
    local refreshW = fitDebugButtonWidth(refreshTitle, UIFont.Small, 84, 128, 18)
    local resetW = fitDebugButtonWidth(resetTitle, UIFont.Small, 84, 144, 18)
    local refreshX = panel.width - padding - refreshW
    local resetX = refreshX - resetW - 6
    createDebugButton(panel, refreshX, yPos, refreshW, 22, refreshTitle, self, BurdJournals.UI.DebugPanel.onWhitelistRefresh)
    createDebugButton(panel, resetX, yPos, resetW, 22, resetTitle, self, BurdJournals.UI.DebugPanel.onWhitelistResetAll, nil, {r=0.75,g=0.42,b=0.38,a=1}, {r=0.35,g=0.12,b=0.12,a=0.7})
    yPos = yPos + 30

    local function buildSection(contentType, builder)
        local section = ISPanel:new(padding, yPos, contentWidth, height - yPos - padding)
        section:initialise()
        section:instantiate()
        section.backgroundColor = {r=0, g=0, b=0, a=0}
        section.borderColor = {r=0, g=0, b=0, a=0}
        panel:addChild(section)
        panel.whitelistTabState.panels[contentType] = section

        local labelText = contentType == "skills" and debugText("UI_BurdJournals_DebugWhitelistSkills", "Skills") or (contentType == "traits" and debugText("UI_BurdJournals_DebugWhitelistTraits", "Traits") or debugText("UI_BurdJournals_DebugWhitelistRecipes", "Recipes"))
        local searchX = section.width - 210
        local label = ISLabel:new(0, 3, 18, labelText, 0.86, 0.9, 0.94, 1, UIFont.Small, true)
        label:initialise()
        label:instantiate()
        section:addChild(label)

        local search = ISTextEntryBox:new("", searchX, 0, 210, 22)
        search:initialise()
        search:instantiate()
        search:setTooltip(BurdJournals.formatText(debugText("UI_BurdJournals_DebugWhitelistSearchTooltip", "Filter %1..."), string.lower(labelText)))
        search.onTextChange = function()
            BurdJournals.UI.DebugPanel.filterWhitelistList(self)
        end
        section:addChild(search)
        panel[contentType .. "WhitelistSearch"] = search

        if contentType == "traits" then
            panel.whitelistTraitPolarityFilter = createDebugTraitPolarityFilter(section, math.max(96, searchX - 92), 0, self, BurdJournals.UI.DebugPanel.filterWhitelistList, debugText("UI_BurdJournals_DebugWhitelistFilterTraits", "Filter traits by positive/negative polarity."))
        end
        panel[contentType .. "WhitelistSourceFilter"] = createSectionSourceFilterStrip(section, self, labelText, searchX, 0, 0, BurdJournals.UI.DebugPanel.filterWhitelistList, debugText("UI_BurdJournals_DebugWhitelistFilterSource", "Filter by source."), 0)

        local headerY = 30
        local header = ISLabel:new(8, headerY, 18, debugText("UI_BurdJournals_DebugWhitelistEntry", "Entry"), 0.55, 0.7, 0.82, 1, UIFont.Small, true)
        header:initialise()
        header:instantiate()
        section:addChild(header)
        local pHeader = ISLabel:new(section.width - 170, headerY, 18, debugText("UI_BurdJournals_DebugWhitelistPlayer", "Player"), 0.55, 0.7, 0.82, 1, UIFont.Small, true)
        pHeader:initialise()
        pHeader:instantiate()
        section:addChild(pHeader)
        local lHeader = ISLabel:new(section.width - 88, headerY, 18, debugText("UI_BurdJournals_DebugWhitelistLoot", "Loot"), 0.55, 0.7, 0.82, 1, UIFont.Small, true)
        lHeader:initialise()
        lHeader:instantiate()
        section:addChild(lHeader)

        local list = ISScrollingListBox:new(0, headerY + 20, section.width, section.height - headerY - 76)
        list:initialise()
        list:instantiate()
        list.itemheight = 34
        list.font = UIFont.Small
        list.parentPanel = self
        list.doDrawItem = BurdJournals.UI.DebugPanel.drawWhitelistItem
        list.onMouseDown = BurdJournals.UI.DebugPanel.onWhitelistListClick
        list.onMouseMove = BurdJournals.UI.DebugPanel.onWhitelistListMouseMove
        list.onMouseMoveOutside = BurdJournals.UI.DebugPanel.onWhitelistListMouseMoveOutside
        section:addChild(list)
        panel[contentType .. "WhitelistList"] = list
        panel[contentType .. "WhitelistRows"] = builder()
        addWhitelistRowsToList(list, panel[contentType .. "WhitelistRows"], contentType)

        local bulkY = section.height - 48
        local bulkButtons = {
            {label = debugText("UI_BurdJournals_DebugWhitelistPlayerAllow", "P Allow"), internal = {scope="player", policy="allow"}},
            {label = debugText("UI_BurdJournals_DebugWhitelistPlayerBan", "P Ban"), internal = {scope="player", policy="ban"}},
            {label = debugText("UI_BurdJournals_DebugWhitelistPlayerInherit", "P Inherit"), internal = {scope="player", policy="inherit"}},
            {label = debugText("UI_BurdJournals_DebugWhitelistLootAllow", "L Allow"), internal = {scope="loot", policy="allow"}},
            {label = debugText("UI_BurdJournals_DebugWhitelistLootBan", "L Ban"), internal = {scope="loot", policy="ban"}},
            {label = debugText("UI_BurdJournals_DebugWhitelistLootInherit", "L Inherit"), internal = {scope="loot", policy="inherit"}},
        }
        local bulkGap = 4
        local bulkTotal = 0
        for _, def in ipairs(bulkButtons) do
            def.width = fitDebugButtonWidth(def.label, UIFont.Small, 58, 132, 16)
            bulkTotal = bulkTotal + def.width
        end
        bulkTotal = bulkTotal + ((#bulkButtons - 1) * bulkGap)
        if bulkTotal > section.width then
            local scale = math.max(0.1, (section.width - ((#bulkButtons - 1) * bulkGap)) / math.max(1, bulkTotal - ((#bulkButtons - 1) * bulkGap)))
            for _, def in ipairs(bulkButtons) do
                def.width = math.max(52, math.floor(def.width * scale))
            end
        end
        local bulkX = 0
        for _, def in ipairs(bulkButtons) do
            createDebugButton(section, bulkX, bulkY, def.width, 22, def.label, self, BurdJournals.UI.DebugPanel.onWhitelistBulk, def.internal)
            bulkX = bulkX + def.width + bulkGap
        end

        local summary = ISLabel:new(0, section.height - 20, 18, "", 0.58, 0.72, 0.86, 1, UIFont.Small, true)
        summary:initialise()
        summary:instantiate()
        section:addChild(summary)
        panel[contentType .. "WhitelistSummary"] = summary
    end

    buildSection("skills", buildDebugSpawnSkillRows)
    buildSection("traits", buildDebugSpawnTraitRows)
    buildSection("recipes", function() return buildDebugRecipeRows(self.player, true, false) end)
    setDebugSubTabState(panel.whitelistTabState, "skills")
    self:refreshWhitelistData()
end

function BurdJournals.UI.DebugPanel.onWhitelistSubTab(self, button)
    local panel = self and self.whitelistPanel or nil
    if not (panel and button and button.internal) then return end
    setDebugSubTabState(panel.whitelistTabState, button.internal)
    BurdJournals.UI.DebugPanel.filterWhitelistList(self)
end

function BurdJournals.UI.DebugPanel:requestAdminPolicy()
    if BurdJournals.clientShouldUseServerAuthority() then
        sendClientCommand("BurdJournals", "debugRequestAdminPolicy", {})
    end
end

function BurdJournals.UI.DebugPanel.onWhitelistRefresh(self)
    if self and self.requestAdminPolicy then
        self:requestAdminPolicy()
    end
    if self and self.refreshWhitelistData then
        self:refreshWhitelistData(true)
    end
end

function BurdJournals.UI.DebugPanel.onWhitelistResetAll(self)
    if BurdJournals.clientShouldUseServerAuthority() then
        sendClientCommand("BurdJournals", "debugResetAdminPolicy", {})
    else
        BurdJournals.setAdminPolicy({skills = {}, traits = {}, recipes = {}})
        if self and self.refreshWhitelistData then self:refreshWhitelistData() end
    end
end

function BurdJournals.UI.DebugPanel:refreshWhitelistData(rebuildRows)
    local panel = self.whitelistPanel
    if not panel then return end
    if rebuildRows == true then
        panel.skillsWhitelistRows = buildDebugSpawnSkillRows()
        panel.traitsWhitelistRows = buildDebugSpawnTraitRows()
        panel.recipesWhitelistRows = buildDebugRecipeRows(self.player, true, false)
    end
    addWhitelistRowsToList(panel.skillsWhitelistList, panel.skillsWhitelistRows, "skills")
    addWhitelistRowsToList(panel.traitsWhitelistList, panel.traitsWhitelistRows, "traits")
    addWhitelistRowsToList(panel.recipesWhitelistList, panel.recipesWhitelistRows, "recipes")
    refreshDebugSourceFilterStrip(panel.skillsWhitelistSourceFilter, panel.skillsWhitelistList and panel.skillsWhitelistList.items or nil)
    refreshDebugSourceFilterStrip(panel.traitsWhitelistSourceFilter, panel.traitsWhitelistList and panel.traitsWhitelistList.items or nil)
    refreshDebugSourceFilterStrip(panel.recipesWhitelistSourceFilter, panel.recipesWhitelistList and panel.recipesWhitelistList.items or nil)
    BurdJournals.UI.DebugPanel.filterWhitelistList(self)
end

function BurdJournals.UI.DebugPanel.filterWhitelistList(self)
    local panel = self and self.whitelistPanel or nil
    if not panel then return end
    local active = panel.whitelistTabState and panel.whitelistTabState.current or "skills"
    local list = panel[active .. "WhitelistList"]
    if not list then return end
    local searchBox = panel[active .. "WhitelistSearch"]
    local searchText = searchBox and searchBox.getText and searchBox:getText() or ""
    local sourceFilter = panel[active .. "WhitelistSourceFilter"]
    local selectedSourceId = sourceFilter and sourceFilter.selectedSourceId or "all"
    local selectedPolarity = active == "traits" and getDebugTraitPolarityFilterValue(panel.whitelistTraitPolarityFilter) or "all"
    applyDebugRowFilter(list, function(row)
        local matchesSearch = searchText == "" or debugSearchMatches(searchText, row.displayName, row.name, row.id, row.category, row.source, row.magazineSource)
        local matchesSource = debugRowMatchesSourceFilter(row, selectedSourceId)
        local matchesPolarity = active ~= "traits" or debugRowMatchesTraitPolarityFilter(row, selectedPolarity)
        return matchesSearch and matchesSource and matchesPolarity
    end)
    BurdJournals.UI.DebugPanel.updateWhitelistSummary(self)
end

function BurdJournals.UI.DebugPanel.updateWhitelistSummary(self)
    local panel = self and self.whitelistPanel or nil
    if not panel then return end
    local active = panel.whitelistTabState and panel.whitelistTabState.current or "skills"
    local list = panel[active .. "WhitelistList"]
    local summary = panel[active .. "WhitelistSummary"]
    if not (list and summary) then return end
    local visible, allow, ban, sandbox = 0, 0, 0, 0
    for _, itemData in ipairs(list.items or {}) do
        local row = itemData and itemData.item or nil
        if isDebugVisibleBulkRow(row) then
            visible = visible + 1
            for _, scope in ipairs({"player", "loot"}) do
                local status = getWhitelistCellStatus(row, scope)
                if status == "allow" then allow = allow + 1
                elseif status == "ban" then ban = ban + 1
                elseif status == "sandbox" then sandbox = sandbox + 1 end
            end
        end
    end
    summary:setName(BurdJournals.formatText(debugText("UI_BurdJournals_DebugWhitelistSummaryFormat", "Visible: %1 | Allowed: %2 | Banned: %3 | Sandbox: %4"), visible, allow, ban, sandbox))
end

function BurdJournals.UI.DebugPanel.drawWhitelistItem(self, y, item, alt)
    local h = getDebugListRowHeight(self, item, self.itemheight or 34)
    local data = item and item.item or nil
    if not data or data.hidden then return y + h end
    local w = self.width or 300
    if self.mouseoverselected == item.index then
        self:drawRect(0, y, w, h, 0.18, 0.23, 0.29, 0.45)
    elseif alt then
        self:drawRect(0, y, w, h, 0.08, 0.08, 0.1, 0.25)
    end
    local iconSize = 0
    if data.kind == "traits" then
        iconSize = drawDebugListIcon(self, data.traitTexture or getDebugTraitTexture(data.id), 6, y, h, 0.95, 14)
    elseif data.kind == "recipes" then
        iconSize = drawDebugListIcon(self, data.recipeTexture or getDebugRecipeTexture(), 6, y, h, 0.95, 14)
    end
    local textX = 8 + math.max(iconSize, 0)
    if iconSize > 0 then textX = textX + 6 end
    self:drawText(tostring(data.displayName or data.name or data.id or "Unknown"), textX, y + 3, 0.86, 0.9, 0.94, 1, UIFont.Small)
    local meta = tostring(data.source or data.category or data.name or data.id or "")
    if data.kind == "recipes" then
        meta = getDebugRecipeSourceText(data, 32)
    end
    self:drawText(trimDebugText(meta, 38), textX, y + 18, 0.52, 0.64, 0.72, 0.9, UIFont.Small)

    local playerStatus, playerLabel = getWhitelistCellStatus(data, "player")
    local lootStatus, lootLabel = getWhitelistCellStatus(data, "loot")
    local playerX = w - 176 - BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH
    local lootX = w - 92 - BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH
    local cellW = 76
    for _, cell in ipairs({
        {x=playerX, status=playerStatus, label=playerLabel},
        {x=lootX, status=lootStatus, label=lootLabel},
    }) do
        local r, g, b = getWhitelistPolicyColor(cell.status)
        self:drawRect(cell.x, y + 6, cellW, h - 12, 0.18, r, g, b)
        self:drawRectBorder(cell.x, y + 6, cellW, h - 12, 0.85, r, g, b)
        self:drawTextCentre(cell.label, cell.x + cellW / 2, y + 10, r, g, b, 1, UIFont.Small)
    end
    return y + h
end

function BurdJournals.UI.DebugPanel.onWhitelistListClick(self, x, y)
    local rowIndex = BurdJournals.UI.DebugPanel.safeListMouseDown(self, x, y)
    if rowIndex <= 0 or rowIndex > #self.items then return end
    local data = self.items[rowIndex] and self.items[rowIndex].item or nil
    local parentPanel = self.parentPanel
    if not (data and parentPanel) then return end
    local w = self.width or 300
    local playerX = w - 176 - BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH
    local lootX = w - 92 - BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH
    local scope = nil
    if x >= playerX and x <= playerX + 76 then scope = "player"
    elseif x >= lootX and x <= lootX + 76 then scope = "loot" end
    if not scope then return end
    local status, _, reasonText = getWhitelistCellStatus(data, scope)
    if status == "sandbox" then
        parentPanel:setStatus(reasonText or debugText("UI_BurdJournals_DebugWhitelistSandboxBlocked", "Sandbox settings block this entry; change sandbox settings first."), {r=1, g=0.7, b=0.35})
        return
    end
    local nextPolicy = status == "inherit" and "allow" or (status == "allow" and "ban" or "inherit")
    parentPanel:sendWhitelistPolicy(data, scope, nextPolicy)
end

function BurdJournals.UI.DebugPanel.onWhitelistListMouseMove(self, dx, dy)
    if ISScrollingListBox and ISScrollingListBox.onMouseMove then
        ISScrollingListBox.onMouseMove(self, dx, dy)
    end
    local rowIndex = getDebugListRowAt(self, self:getMouseX(), self:getMouseY())
    local data = rowIndex > 0 and self.items and self.items[rowIndex] and self.items[rowIndex].item or nil
    local w = self.width or 300
    local playerX = w - 176 - BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH
    local lootX = w - 92 - BurdJournals.UI.DebugPanel.SCROLLBAR_WIDTH
    local mouseX = self:getMouseX()
    local scope = nil
    if mouseX >= playerX and mouseX <= playerX + 76 then scope = "player"
    elseif mouseX >= lootX and mouseX <= lootX + 76 then scope = "loot" end
    local tooltipText = scope and data and getWhitelistSandboxReasonText(data, scope) or nil
    if tooltipText and tooltipText ~= "" then
        if not self.whitelistTooltipUI then
            self.whitelistTooltipUI = ISToolTip:new()
            self.whitelistTooltipUI:setOwner(self)
            self.whitelistTooltipUI:setVisible(false)
            self.whitelistTooltipUI:setAlwaysOnTop(true)
            self.whitelistTooltipUI.maxLineWidth = 520
        end
        if not self.whitelistTooltipUI:getIsVisible() then
            self.whitelistTooltipUI:addToUIManager()
            self.whitelistTooltipUI:setVisible(true)
        end
        self.whitelistTooltipUI.description = tooltipText
        self.whitelistTooltipUI:setX(self:getMouseX() + 23)
        self.whitelistTooltipUI:setY(self:getMouseY() + 23)
    elseif self.whitelistTooltipUI and self.whitelistTooltipUI:getIsVisible() then
        self.whitelistTooltipUI:setVisible(false)
        self.whitelistTooltipUI:removeFromUIManager()
    end
end

function BurdJournals.UI.DebugPanel.onWhitelistListMouseMoveOutside(self, dx, dy)
    if ISScrollingListBox and ISScrollingListBox.onMouseMoveOutside then
        ISScrollingListBox.onMouseMoveOutside(self, dx, dy)
    end
    if self.whitelistTooltipUI and self.whitelistTooltipUI:getIsVisible() then
        self.whitelistTooltipUI:setVisible(false)
        self.whitelistTooltipUI:removeFromUIManager()
    end
end

function BurdJournals.UI.DebugPanel:sendWhitelistPolicy(row, scope, policy)
    local kind = getWhitelistKindForContent(row and row.kind)
    local id = getWhitelistRowId(row)
    if not (kind and id and scope) then return end
    if BurdJournals.clientShouldUseServerAuthority() then
        sendClientCommand("BurdJournals", "debugSetAdminPolicy", {kind=kind, id=id, scope=scope, policy=policy})
    else
        BurdJournals.AdminPolicy = BurdJournals.AdminPolicy or {skills={}, traits={}, recipes={}}
        BurdJournals.AdminPolicy[kind] = BurdJournals.AdminPolicy[kind] or {}
        BurdJournals.AdminPolicy[kind][id] = BurdJournals.AdminPolicy[kind][id] or {}
        BurdJournals.AdminPolicy[kind][id][scope] = BurdJournals.normalizeAdminPolicyValue(policy)
        if BurdJournals.AdminPolicy[kind][id].player == nil and BurdJournals.AdminPolicy[kind][id].loot == nil then
            BurdJournals.AdminPolicy[kind][id] = nil
        end
        self:refreshWhitelistData()
    end
end

function BurdJournals.UI.DebugPanel.onWhitelistBulk(self, button)
    local panel = self and self.whitelistPanel or nil
    local internal = button and button.internal or nil
    local active = panel and panel.whitelistTabState and panel.whitelistTabState.current or nil
    local list = active and panel[active .. "WhitelistList"] or nil
    if not (panel and internal and list) then return end
    local kind = getWhitelistKindForContent(active)
    local ids = {}
    for _, itemData in ipairs(list.items or {}) do
        local row = itemData and itemData.item or nil
        local id = getWhitelistRowId(row)
        local status = row and getWhitelistCellStatus(row, internal.scope) or "sandbox"
        if row and id and isDebugVisibleBulkRow(row) and status ~= "sandbox" then
            ids[#ids + 1] = id
        end
    end
    if BurdJournals.clientShouldUseServerAuthority() then
        sendClientCommand("BurdJournals", "debugBulkSetAdminPolicy", {
            kind = kind,
            ids = ids,
            scope = internal.scope,
            policy = internal.policy,
        })
    else
        for _, id in ipairs(ids) do
            self:sendWhitelistPolicy({kind=kind, name=id, id=id}, internal.scope, internal.policy)
        end
    end
    self:setStatus(BurdJournals.formatText(debugText("UI_BurdJournals_DebugWhitelistBulkQueued", "Whitelist bulk queued: %1 entrie(s)"), #ids), {r=0.5, g=0.8, b=1})
end

-- ============================================================================
-- Tab 7: Diagnostics Panel
-- ============================================================================

function BurdJournals.UI.DebugPanel:addAdvancedExtensionSections(panel, y, padding)
    if not (panel and BurdJournals.getDebugAdvancedSections) then
        return y
    end

    local sections = BurdJournals.getDebugAdvancedSections() or {}
    if #sections < 1 then
        return y
    end

    local fullWidth = panel.width - (padding * 2)
    local label = ISLabel:new(padding, y, 20, "Add-on Debug Options:", 1, 1, 1, 1, UIFont.Small, true)
    label:initialise()
    label:instantiate()
    panel:addChild(label)
    y = y + 24

    panel.advancedExtensionSections = panel.advancedExtensionSections or {}
    for _, def in ipairs(sections) do
        if type(def) == "table" and type(def.build) == "function" then
            local result = def.build(panel, y, {
                owner = self,
                padding = padding,
                fullWidth = fullWidth,
                rowHeight = 24,
            })
            if type(result) == "table" then
                result.id = result.id or def.id
                panel.advancedExtensionSections[#panel.advancedExtensionSections + 1] = result
                y = y + (tonumber(result.height) or 0)
            end
        end
    end

    return y + 10
end

function BurdJournals.UI.DebugPanel:createDiagnosticsPanel(startY, height)
    local panel = ISPanel:new(5, startY, self.width - 10, height)
    panel:initialise()
    panel:instantiate()
    panel.backgroundColor = {r=0.12, g=0.12, b=0.15, a=1}
    panel.borderColor = {r=0.3, g=0.4, b=0.5, a=1}
    self:addChild(panel)
    self.tabPanels["diagnostics"] = panel
    
    local padding = 10
    local y = padding
    local btnWidth = 200
    local btnHeight = 28
    
    -- Diagnostic commands
    local diagLabel = ISLabel:new(padding, y, 20, "Diagnostic Commands:", 1, 1, 1, 1, UIFont.Small, true)
    diagLabel:initialise()
    diagLabel:instantiate()
    panel:addChild(diagLabel)
    y = y + 25
    
    local diagBtns = {
        {name = "Run Full Diagnostics", cmd = "fulldiag"},
        {name = "Run Self Tests", cmd = "runselftests"},
        {name = "Scan Inventory for Journals", cmd = "scanjournals"},
        {name = "Audit Unknown Mod Sources", cmd = "auditunknownsources"},
        {name = "Check Selected Journal Persistence", cmd = "journalpersist"},
        {name = "Check Sandbox Options", cmd = "checksandbox"},
        {name = "Check Mod State", cmd = "checkmodstate"},
    }
    
    for _, btnDef in ipairs(diagBtns) do
        local btn = ISButton:new(padding, y, btnWidth, btnHeight, btnDef.name, self, BurdJournals.UI.DebugPanel.onDiagCmd)
        btn:initialise()
        btn:instantiate()
        btn.font = UIFont.Small
        btn.internal = btnDef.cmd
        btn.textColor = {r=1, g=1, b=1, a=1}
        btn.borderColor = {r=0.4, g=0.5, b=0.6, a=1}
        btn.backgroundColor = {r=0.2, g=0.25, b=0.3, a=1}
        panel:addChild(btn)
        y = y + btnHeight + 5
    end

    y = y + 8

    local browseLabel = ISLabel:new(padding, y, 20, "Browse Discoverable Data:", 1, 1, 1, 1, UIFont.Small, true)
    browseLabel:initialise()
    browseLabel:instantiate()
    panel:addChild(browseLabel)
    y = y + 25

    local browseDefs = {
        {name = "Browse Skills", cmd = "browseskills", tooltip = "Lists every skill the mod can currently discover and shows whether it came from dynamic runtime data, a runtime fallback, or a hardcoded fallback."},
        {name = "Browse Traits", cmd = "browsetraits", tooltip = "Lists every trait the mod can currently discover and shows whether it came from dynamic runtime data, a runtime fallback, or a hardcoded fallback."},
        {name = "Browse Recipes", cmd = "browserecipes", tooltip = "Lists every recipe the mod can currently discover from the journal recipe cache and shows the source it was derived from."},
    }
    local browseBtnWidth = 150
    local browseX = padding
    for _, btnDef in ipairs(browseDefs) do
        local btn = ISButton:new(browseX, y, browseBtnWidth, btnHeight, btnDef.name, self, BurdJournals.UI.DebugPanel.onDiagCmd)
        btn:initialise()
        btn:instantiate()
        btn.font = UIFont.Small
        btn.internal = btnDef.cmd
        btn.textColor = {r=1, g=1, b=1, a=1}
        btn.borderColor = {r=0.35, g=0.5, b=0.7, a=1}
        btn.backgroundColor = {r=0.16, g=0.24, b=0.34, a=1}
        if btn.setTooltip then
            btn:setTooltip(btnDef.tooltip)
        else
            btn.tooltip = btnDef.tooltip
        end
        panel:addChild(btn)
        browseX = browseX + browseBtnWidth + 6
    end

    y = y + btnHeight + 20
    
    -- Verbose logging toggle
    local verboseLabel = ISLabel:new(padding, y, 20, "Verbose Logging:", 1, 1, 1, 1, UIFont.Small, true)
    verboseLabel:initialise()
    verboseLabel:instantiate()
    panel:addChild(verboseLabel)
    y = y + 25
    
    local verboseOnBtn = ISButton:new(padding, y, 100, btnHeight, "Enable", self, BurdJournals.UI.DebugPanel.onVerboseOn)
    verboseOnBtn:initialise()
    verboseOnBtn:instantiate()
    verboseOnBtn.font = UIFont.Small
    verboseOnBtn.textColor = {r=1, g=1, b=1, a=1}
    verboseOnBtn.borderColor = {r=0.3, g=0.6, b=0.4, a=1}
    verboseOnBtn.backgroundColor = {r=0.15, g=0.35, b=0.2, a=1}
    panel:addChild(verboseOnBtn)
    
    local verboseOffBtn = ISButton:new(padding + 105, y, 100, btnHeight, "Disable", self, BurdJournals.UI.DebugPanel.onVerboseOff)
    verboseOffBtn:initialise()
    verboseOffBtn:instantiate()
    verboseOffBtn.font = UIFont.Small
    verboseOffBtn.textColor = {r=1, g=1, b=1, a=1}
    verboseOffBtn.borderColor = {r=0.6, g=0.4, b=0.3, a=1}
    verboseOffBtn.backgroundColor = {r=0.35, g=0.2, b=0.15, a=1}
    panel:addChild(verboseOffBtn)

    local openLogsBtn = ISButton:new(padding + 225, y, 180, btnHeight, "Open BSJ Log Folder", self, BurdJournals.UI.DebugPanel.onDiagCmd)
    openLogsBtn:initialise()
    openLogsBtn:instantiate()
    openLogsBtn.font = UIFont.Small
    openLogsBtn.internal = "openlogs"
    openLogsBtn.textColor = {r=1, g=1, b=1, a=1}
    openLogsBtn.borderColor = {r=0.35, g=0.5, b=0.7, a=1}
    openLogsBtn.backgroundColor = {r=0.16, g=0.24, b=0.34, a=1}
    if openLogsBtn.setTooltip then
        openLogsBtn:setTooltip("Opens the Project Zomboid Logs folder where writeLog('BurdJournals', ...) entries are stored. If opening is blocked, the path is copied/logged for manual navigation.")
    else
        openLogsBtn.tooltip = "Opens the Project Zomboid Logs folder where writeLog('BurdJournals', ...) entries are stored. If opening is blocked, the path is copied/logged for manual navigation."
    end
    panel:addChild(openLogsBtn)

    y = y + btnHeight + 12

    y = BurdJournals.UI.DebugPanel.addAdvancedExtensionSections(self, panel, y, padding)

    local unknownLabel = ISLabel:new(padding, y, 20, "Unknown Source Results:", 1, 1, 1, 1, UIFont.Small, true)
    unknownLabel:initialise()
    unknownLabel:instantiate()
    panel:addChild(unknownLabel)
    y = y + 20

    local listHeight = math.max(120, panel.height - y - 10)
    panel.unknownSourceList = ISScrollingListBox:new(padding, y, panel.width - padding * 2, listHeight)
    panel.unknownSourceList:initialise()
    panel.unknownSourceList:instantiate()
    panel.unknownSourceList.itemheight = 20
    panel.unknownSourceList.font = UIFont.Small
    panel.unknownSourceList.backgroundColor = {r=0.08, g=0.08, b=0.1, a=0.9}
    panel.unknownSourceList.borderColor = {r=0.35, g=0.42, b=0.5, a=0.9}
    panel:addChild(panel.unknownSourceList)
    panel.unknownSourceList:addItem("Run 'Audit Unknown Mod Sources' to populate results.", nil)
    
    self.diagPanel = panel
end

local function appendUnknownSourceDiagnostics(rows, category, name, context)
    if not BurdJournals or not BurdJournals.diagnoseModSource then
        return
    end
    local diag = BurdJournals.diagnoseModSource(category, name, context)
    if not diag or diag.source ~= "Modded" then
        return
    end

    local detailParts = {}
    if diag.details then
        for k, v in pairs(diag.details) do
            table.insert(detailParts, tostring(k) .. "=" .. tostring(v))
        end
    end
    table.sort(detailParts)

    local suffix = (#detailParts > 0) and (" | " .. table.concat(detailParts, ", ")) or ""
    table.insert(rows, "[" .. category .. "] " .. tostring(name) .. " -> reason=" .. tostring(diag.reason) .. suffix)
end

local function updateUnknownSourceDiagnosticsList(self, rows)
    local panel = self and self.diagPanel
    local list = panel and panel.unknownSourceList
    if not list then
        return
    end

    list:clear()

    if not rows or #rows == 0 then
        list:addItem("No unknown-source entries found.", nil)
        return
    end

    list:addItem("Unknown-source entries: " .. tostring(#rows), nil)
    for _, row in ipairs(rows) do
        list:addItem(row, nil)
    end
end

function BurdJournals.UI.DebugPanel.getPathSeparatorFor(root)
    root = tostring(root or "")
    if string.find(root, "/", 1, true) and not string.find(root, "\\", 1, true) then
        return "/"
    end
    return "\\"
end

function BurdJournals.UI.DebugPanel.appendPathPart(root, part)
    if type(root) ~= "string" or root == "" then
        return nil
    end
    local sep = BurdJournals.UI.DebugPanel.getPathSeparatorFor(root)
    if string.sub(root, -1) == "\\" or string.sub(root, -1) == "/" then
        return root .. tostring(part or "")
    end
    return root .. sep .. tostring(part or "")
end

function BurdJournals.UI.DebugPanel.addUniquePath(paths, seen, path)
    if type(path) ~= "string" or path == "" then
        return
    end
    local key = string.lower(path)
    if seen[key] then
        return
    end
    seen[key] = true
    paths[#paths + 1] = path
end

function BurdJournals.UI.DebugPanel.getBSJLogFolderCandidates()
    local paths = {}
    local seen = {}

    local function addRoot(root)
        if type(root) ~= "string" or root == "" then
            return
        end
        local normalizedRoot = string.lower(string.gsub(root, "\\", "/"))
        local isZomboidRoot = string.sub(normalizedRoot, -8) == "/zomboid" or normalizedRoot == "zomboid"
        if isZomboidRoot then
            BurdJournals.UI.DebugPanel.addUniquePath(paths, seen, BurdJournals.UI.DebugPanel.appendPathPart(root, "Logs"))
            BurdJournals.UI.DebugPanel.addUniquePath(paths, seen, BurdJournals.UI.DebugPanel.appendPathPart(BurdJournals.UI.DebugPanel.appendPathPart(root, "Zomboid"), "Logs"))
        else
            BurdJournals.UI.DebugPanel.addUniquePath(paths, seen, BurdJournals.UI.DebugPanel.appendPathPart(BurdJournals.UI.DebugPanel.appendPathPart(root, "Zomboid"), "Logs"))
            BurdJournals.UI.DebugPanel.addUniquePath(paths, seen, BurdJournals.UI.DebugPanel.appendPathPart(root, "Logs"))
        end
    end

    if getMyDocumentFolder then
        local ok, root = pcall(getMyDocumentFolder)
        if ok then
            addRoot(root)
        end
    end
    if getCacheDir then
        local ok, root = pcall(getCacheDir)
        if ok then
            addRoot(root)
        end
    end
    if os and os.getenv then
        addRoot(os.getenv("USERPROFILE"))
        addRoot(os.getenv("HOME"))
    end

    return paths
end

function BurdJournals.UI.DebugPanel.pathToFileUrl(path)
    path = tostring(path or "")
    path = string.gsub(path, "\\", "/")
    path = string.gsub(path, " ", "%%20")
    if string.sub(path, 1, 1) == "/" then
        return "file://" .. path
    end
    return "file:///" .. path
end

function BurdJournals.UI.DebugPanel.copyTextToClipboardCompat(text)
    if Clipboard and Clipboard.setClipboard then
        local ok = pcall(function()
            Clipboard:setClipboard(text)
        end)
        if ok then
            return true
        end
        ok = pcall(function()
            Clipboard.setClipboard(text)
        end)
        if ok then
            return true
        end
    end
    if getClipboard then
        local okClipboard, clipboard = pcall(getClipboard)
        if okClipboard and clipboard and clipboard.setClipboard then
            local ok = pcall(function()
                clipboard:setClipboard(text)
            end)
            if ok then
                return true
            end
        end
    end
    return false
end

function BurdJournals.UI.DebugPanel.tryOpenFolderPath(path)
    if type(path) ~= "string" or path == "" then
        return false
    end
    if openUrl then
        local ok = pcall(function()
            openUrl(BurdJournals.UI.DebugPanel.pathToFileUrl(path))
        end)
        if ok then
            return true
        end
    end
    if openURL then
        local ok = pcall(function()
            openURL(BurdJournals.UI.DebugPanel.pathToFileUrl(path))
        end)
        if ok then
            return true
        end
    end
    if luajava and luajava.bindClass then
        local ok = pcall(function()
            local File = luajava.bindClass("java.io.File")
            local Desktop = luajava.bindClass("java.awt.Desktop")
            Desktop:getDesktop():open(File:new(path))
        end)
        if ok then
            return true
        end
    end
    return false
end

function BurdJournals.UI.DebugPanel:onDiagCmd(button)
    local cmd = button.internal

    if cmd == "browseskills" then
        self:openDiscoveryBrowser("skills")
        self:setStatus("Opened skill discovery browser", {r=0.5, g=0.8, b=1})
    elseif cmd == "browsetraits" then
        self:openDiscoveryBrowser("traits")
        self:setStatus("Opened trait discovery browser", {r=0.5, g=0.8, b=1})
    elseif cmd == "browserecipes" then
        self:openDiscoveryBrowser("recipes")
        self:setStatus("Opened recipe discovery browser", {r=0.5, g=0.8, b=1})
    elseif cmd == "openlogs" then
        local candidates = BurdJournals.UI.DebugPanel.getBSJLogFolderCandidates()
        local openedPath = nil
        for _, path in ipairs(candidates) do
            if BurdJournals.UI.DebugPanel.tryOpenFolderPath(path) then
                openedPath = path
                break
            end
        end
        local fallbackPath = openedPath or candidates[1] or "Zomboid/Logs"
        BurdJournals.writeLogLine("[BurdJournals] Log folder requested from Debug Center. Logger='BurdJournals', folder='" .. tostring(fallbackPath) .. "'.")
        if openedPath then
            self:setStatus("Opened log folder: " .. tostring(openedPath), {r=0.5, g=0.8, b=1})
        else
            self:setStatus("Could not open folder; path logged: " .. tostring(fallbackPath), {r=1, g=0.7, b=0.3})
        end
    elseif cmd == "fulldiag" then
        BurdJournals.debugPrint("[BSJ DEBUG] === FULL DIAGNOSTICS ===")
        BurdJournals.debugPrint("--- Environment ---")
        BurdJournals.debugPrint("  Player: " .. (self.player and self.player:getUsername() or "nil"))
        BurdJournals.debugPrint("  Is Client: " .. tostring(isClient()))
        BurdJournals.debugPrint("  Is Server: " .. tostring(isServer()))
        BurdJournals.debugPrint("  Game Mode: " .. (isServer() and isClient() and "Listen Server" or (isServer() and "Dedicated Server" or (isClient() and "MP Client" or "Singleplayer"))))
        
        BurdJournals.debugPrint("--- Mod Status ---")
        BurdJournals.debugPrint("  BurdJournals loaded: " .. tostring(BurdJournals ~= nil))
        BurdJournals.debugPrint("  BurdJournals.Client loaded: " .. tostring(BurdJournals.Client ~= nil))
        BurdJournals.debugPrint("  BurdJournals.Server loaded: " .. tostring(BurdJournals.Server ~= nil))
        BurdJournals.debugPrint("  Verbose Logging: " .. tostring(BurdJournals.verboseLogging or false))
        
        if self.player then
            BurdJournals.debugPrint("--- Player Baseline ---")
            local modData = self.player:getModData()
            local bj = modData.BurdJournals or {}
            BurdJournals.debugPrint("  Baseline Captured: " .. tostring(bj.baselineCaptured or false))
            BurdJournals.debugPrint("  Debug Modified: " .. tostring(bj.debugModified or false))
            BurdJournals.debugPrint("  Baseline Bypassed: " .. tostring(bj.baselineBypassed or false))
            BurdJournals.debugPrint("  Baseline Version: " .. tostring(bj.baselineVersion or "none"))
            local skillCount = 0
            for _ in pairs(bj.skillBaseline or {}) do skillCount = skillCount + 1 end
            local traitCount = 0
            for _ in pairs(bj.traitBaseline or {}) do traitCount = traitCount + 1 end
            local recipeCount = 0
            for _ in pairs(bj.recipeBaseline or {}) do recipeCount = recipeCount + 1 end
            BurdJournals.debugPrint("  Skill Baselines: " .. skillCount)
            BurdJournals.debugPrint("  Trait Baselines: " .. traitCount)
            BurdJournals.debugPrint("  Recipe Baselines: " .. recipeCount)
        end
        
        BurdJournals.debugPrint("=================================")
        self:setStatus("Diagnostics output to console", {r=0.5, g=0.8, b=1})
    elseif cmd == "runselftests" then
        if BurdJournals and BurdJournals.runSelfTests then
            local result = BurdJournals.runSelfTests()
            if result and result.failed == 0 then
                self:setStatus("Self-tests passed", {r=0.3, g=1, b=0.5})
            else
                local failCount = result and result.failed or "?"
                self:setStatus("Self-tests failed (" .. tostring(failCount) .. ")", {r=1, g=0.45, b=0.45})
            end
        else
            BurdJournals.debugPrint("[BSJ DEBUG] runSelfTests() is not available")
            self:setStatus("Self-tests unavailable", {r=1, g=0.6, b=0.3})
        end
    elseif cmd == "scanjournals" then
        BurdJournals.debugPrint("[BSJ DEBUG] === INVENTORY JOURNAL SCAN ===")
        if self.player then
            local inv = self.player:getInventory()
            local items = inv:getItems()
            local journalCount = 0
            for i = 0, items:size() - 1 do
                local item = items:get(i)
                local fullType = item:getFullType()
                if fullType and string.find(fullType, "BurdJournals") then
                    journalCount = journalCount + 1
                    BurdJournals.debugPrint("  Found: " .. fullType)
                    local modData = item:getModData()
                    if modData and modData.BurdJournals then
                        BurdJournals.debugPrint("    Has ModData: yes")
                        BurdJournals.debugPrint("    Skills: " .. tostring(BurdJournals.countTable and BurdJournals.countTable(modData.BurdJournals.skills or {}) or "?"))
                        BurdJournals.debugPrint("    Traits: " .. tostring(BurdJournals.countTable and BurdJournals.countTable(modData.BurdJournals.traits or {}) or "?"))
                        BurdJournals.debugPrint("    Recipes: " .. tostring(BurdJournals.countTable and BurdJournals.countTable(modData.BurdJournals.recipes or {}) or "?"))
                        if modData.BurdJournals.ownerName then
                            BurdJournals.debugPrint("    Owner: " .. modData.BurdJournals.ownerName)
                        end
                        if modData.BurdJournals.profession then
                            BurdJournals.debugPrint("    Profession: " .. tostring(modData.BurdJournals.professionName or modData.BurdJournals.profession))
                        end
                    end
                end
            end
            BurdJournals.debugPrint("Total journals found: " .. journalCount)
        end
        BurdJournals.debugPrint("=========================================")
        self:setStatus("Journal scan complete", {r=0.5, g=0.8, b=1})
    elseif cmd == "auditunknownsources" then
        local rows = {}

        -- Inspect selected journal payload first.
        local journal = self.editingJournal
        local journalData = journal and BurdJournals.getJournalData and BurdJournals.getJournalData(journal) or nil
        if journalData then
            for skillName, _ in pairs(journalData.skills or {}) do
                appendUnknownSourceDiagnostics(rows, "skills", skillName)
            end
            for traitId, _ in pairs(journalData.traits or {}) do
                appendUnknownSourceDiagnostics(rows, "traits", traitId)
            end
            for recipeName, recipeData in pairs(journalData.recipes or {}) do
                local magazineSource = (type(recipeData) == "table" and recipeData.source) or (BurdJournals.getMagazineForRecipe and BurdJournals.getMagazineForRecipe(recipeName))
                appendUnknownSourceDiagnostics(rows, "recipes", recipeName, {magazineSource = magazineSource})
            end
        end

        -- Inspect player's currently known/active data for unknown classification.
        if self.player then
            local allowedSkills = BurdJournals.getAllowedSkills and BurdJournals.getAllowedSkills() or {}
            for _, skillName in ipairs(allowedSkills) do
                local perk = BurdJournals.getPerkByName and BurdJournals.getPerkByName(skillName)
                if perk then
                    local xpObj = self.player.getXp and self.player:getXp() or nil
                    local currentXP = (BurdJournals.getPlayerSkillTotalXP and BurdJournals.getPlayerSkillTotalXP(self.player, perk, skillName))
                        or ((xpObj and xpObj.getXP and xpObj:getXP(perk)) or 0)
                    local currentLevel = (self.player.getPerkLevel and self.player:getPerkLevel(perk)) or 0
                    if currentXP > 0 or currentLevel > 0 then
                        appendUnknownSourceDiagnostics(rows, "skills", skillName)
                    end
                end
            end

            local playerTraits = BurdJournals.collectPlayerTraits and BurdJournals.collectPlayerTraits(self.player, false) or {}
            for traitId, _ in pairs(playerTraits or {}) do
                appendUnknownSourceDiagnostics(rows, "traits", traitId)
            end

            local playerRecipes = BurdJournals.collectPlayerMagazineRecipes and BurdJournals.collectPlayerMagazineRecipes(self.player) or {}
            for recipeName, recipeData in pairs(playerRecipes or {}) do
                local magazineSource = (type(recipeData) == "table" and recipeData.source) or (BurdJournals.getMagazineForRecipe and BurdJournals.getMagazineForRecipe(recipeName))
                appendUnknownSourceDiagnostics(rows, "recipes", recipeName, {magazineSource = magazineSource})
            end
        end

        local dedup = {}
        local uniqueRows = {}
        BurdJournals.debugPrint("[BSJ DEBUG] === UNKNOWN SOURCE DIAGNOSTICS ===")
        for _, row in ipairs(rows) do
            if not dedup[row] then
                dedup[row] = true
                table.insert(uniqueRows, row)
                BurdJournals.debugPrint("  " .. row)
            end
        end
        local count = #uniqueRows
        BurdJournals.debugPrint("Total unknown-source entries: " .. tostring(count))
        BurdJournals.debugPrint("========================================")
        updateUnknownSourceDiagnosticsList(self, uniqueRows)

        if count > 0 then
            self:setStatus("Unknown-source diagnostics dumped (" .. tostring(count) .. ")", {r=0.9, g=0.8, b=0.4})
        else
            self:setStatus("No unknown-source entries found", {r=0.3, g=1, b=0.5})
        end
    elseif cmd == "journalpersist" then
        local journal = self.editingJournal
        if not journal then
            self:setStatus("No journal selected in Journal tab", {r=1, g=0.6, b=0.3})
            BurdJournals.debugPrint("[BSJ DEBUG] Journal persistence check: no selected journal")
            return
        end

        local modData = journal.getModData and journal:getModData() or nil
        local data = modData and modData.BurdJournals or nil
        local journalId = journal.getID and journal:getID() or "nil"
        local fullType = journal.getFullType and journal:getFullType() or "unknown"

        BurdJournals.debugPrint("[BSJ DEBUG] === SELECTED JOURNAL PERSISTENCE ===")
        BurdJournals.debugPrint("  Journal ID: " .. tostring(journalId))
        BurdJournals.debugPrint("  Item Type: " .. tostring(fullType))
        BurdJournals.debugPrint("  Has ModData.BurdJournals: " .. tostring(data ~= nil))

        if data then
            local skillsCount = BurdJournals.countTable and BurdJournals.countTable(data.skills) or 0
            local traitsCount = BurdJournals.countTable and BurdJournals.countTable(data.traits) or 0
            local recipesCount = BurdJournals.countTable and BurdJournals.countTable(data.recipes) or 0
            local statsCount = BurdJournals.countTable and BurdJournals.countTable(data.stats) or 0
            local hasAnyData = (BurdJournals.hasAnyEntries and (
                BurdJournals.hasAnyEntries(data.skills) or
                BurdJournals.hasAnyEntries(data.traits) or
                BurdJournals.hasAnyEntries(data.recipes) or
                BurdJournals.hasAnyEntries(data.stats)
            )) or false

            BurdJournals.debugPrint("  UUID: " .. tostring(data.uuid))
            BurdJournals.debugPrint("  journalVersion: " .. tostring(data.journalVersion))
            BurdJournals.debugPrint("  sanitizedVersion: " .. tostring(data.sanitizedVersion))
            BurdJournals.debugPrint("  compactVersion: " .. tostring(data.compactVersion))
            BurdJournals.debugPrint("  isDebugSpawned: " .. tostring(data.isDebugSpawned))
            BurdJournals.debugPrint("  isDebugEdited: " .. tostring(data.isDebugEdited))
            BurdJournals.debugPrint("  isPlayerCreated: " .. tostring(data.isPlayerCreated))
            BurdJournals.debugPrint("  isWritten: " .. tostring(data.isWritten))
            BurdJournals.debugPrint("  skills count: " .. tostring(skillsCount))
            BurdJournals.debugPrint("  traits count: " .. tostring(traitsCount))
            BurdJournals.debugPrint("  recipes count: " .. tostring(recipesCount))
            BurdJournals.debugPrint("  stats count: " .. tostring(statsCount))
            BurdJournals.debugPrint("  hasAnyEntries: " .. tostring(hasAnyData))

            local journalKey = data.uuid or tostring(journalId)
            local cache = ModData.getOrCreate("BurdJournals_DebugJournalCache")
            local hasLocalCache = cache and cache.journals and cache.journals[journalKey] ~= nil
            BurdJournals.debugPrint("  backup key: " .. tostring(journalKey))
            BurdJournals.debugPrint("  local backup cache entry: " .. tostring(hasLocalCache))

            if BurdJournals.clientShouldUseServerAuthority() then
                BurdJournals.debugPrint("  mode: MP client (requesting server backup check)")
                if BurdJournals.Client and BurdJournals.Client.requestDebugJournalBackup then
                    BurdJournals.Client.requestDebugJournalBackup(journal, journalKey)
                end
            else
                BurdJournals.debugPrint("  mode: SP/host/server")
            end

            self:setStatus("Journal persistence dumped (key: " .. tostring(journalKey) .. ")", {r=0.5, g=0.8, b=1})
        else
            self:setStatus("Selected item has no BurdJournals data", {r=1, g=0.6, b=0.3})
        end
        BurdJournals.debugPrint("=========================================")
    elseif cmd == "checksandbox" then
        BurdJournals.debugPrint("[BSJ DEBUG] === SANDBOX OPTIONS ===")
        BurdJournals.debugPrint("--- Core Settings ---")
        local coreOptions = {
            "EnableJournals",
            "EnablePlayerJournals",
            "EnablePlayerJournalCrafting",
            "EnableBaselineRestriction",
            "AllowDebugCommands",
        }
        for _, opt in ipairs(coreOptions) do
            local value = BurdJournals.getSandboxOption and BurdJournals.getSandboxOption(opt)
            BurdJournals.debugPrint("  " .. opt .. ": " .. tostring(value))
        end
        BurdJournals.debugPrint("--- Recording Settings ---")
        local recordOptions = {
            "EnableTraitRecordingPlayer",
            "EnableRecipeRecordingPlayer",
            "EnableStatRecording",
        }
        for _, opt in ipairs(recordOptions) do
            local value = BurdJournals.getSandboxOption and BurdJournals.getSandboxOption(opt)
            BurdJournals.debugPrint("  " .. opt .. ": " .. tostring(value))
        end
        BurdJournals.debugPrint("--- World Spawns ---")
        local spawnOptions = {
            "EnableWornJournalSpawns",
            "EnableBloodyJournalSpawns",
            "EnableCursedJournalSpawns",
            "WornJournalForgetChance",
            "BloodyJournalForgetChance",
            "CursedJournalForgetChance",
            "EnableWornJournalForgetSlot",
            "EnableBloodyJournalForgetSlot",
            "EnableCursedJournalForgetSlot",
            "CursedJournalMinSkills",
            "CursedJournalMaxSkills",
            "CursedJournalMinXP",
            "CursedJournalMaxXP",
            "EnableCursedJournalTraits",
            "CursedJournalTraitChance",
            "CursedJournalMinTraits",
            "CursedJournalMaxTraits",
            "EnableCursedJournalRecipes",
            "CursedJournalRecipeChance",
            "CursedJournalMaxRecipes",
            "CursedJournalSpawnChance",
        }
        for _, opt in ipairs(spawnOptions) do
            local value = BurdJournals.getSandboxOption and BurdJournals.getSandboxOption(opt)
            BurdJournals.debugPrint("  " .. opt .. ": " .. tostring(value))
        end
        BurdJournals.debugPrint("--- Permissions ---")
        local permOptions = {
            "AllowOthersToOpenJournals",
            "AllowOthersToClaimFromJournals",
            "AllowNegativeTraits",
            "AllowPlayerJournalDissolution",
        }
        for _, opt in ipairs(permOptions) do
            local value = BurdJournals.getSandboxOption and BurdJournals.getSandboxOption(opt)
            BurdJournals.debugPrint("  " .. opt .. ": " .. tostring(value))
        end
        BurdJournals.debugPrint("==================================")
        self:setStatus("Sandbox options dumped", {r=0.5, g=0.8, b=1})
    elseif cmd == "checkmodstate" then
        BurdJournals.debugPrint("[BSJ DEBUG] === MOD STATE ===")
        BurdJournals.debugPrint("--- Core Modules ---")
        BurdJournals.debugPrint("  BurdJournals: " .. tostring(BurdJournals ~= nil))
        BurdJournals.debugPrint("  BurdJournals.Client: " .. tostring(BurdJournals.Client ~= nil))
        BurdJournals.debugPrint("  BurdJournals.Server: " .. tostring(BurdJournals.Server ~= nil))
        BurdJournals.debugPrint("  BurdJournals.UI: " .. tostring(BurdJournals.UI ~= nil))
        BurdJournals.debugPrint("--- Key Functions ---")
        BurdJournals.debugPrint("  getJournalData: " .. tostring(BurdJournals.getJournalData ~= nil))
        BurdJournals.debugPrint("  getSkillBaselineLevel: " .. tostring(BurdJournals.getSkillBaselineLevel ~= nil))
        BurdJournals.debugPrint("  getSkillLevelFromXP: " .. tostring(BurdJournals.getSkillLevelFromXP ~= nil))
        BurdJournals.debugPrint("  isBaselineRestrictionEnabled: " .. tostring(BurdJournals.isBaselineRestrictionEnabled ~= nil))
        BurdJournals.debugPrint("  calculateProfessionBaseline: " .. tostring(BurdJournals.Client and BurdJournals.Client.calculateProfessionBaseline ~= nil))
        BurdJournals.debugPrint("--- Debug Functions ---")
        BurdJournals.debugPrint("  Client.Debug: " .. tostring(BurdJournals.Client and BurdJournals.Client.Debug ~= nil))
        BurdJournals.debugPrint("  Client.Debug.getXPForLevel: " .. tostring(BurdJournals.Client and BurdJournals.Client.Debug and BurdJournals.Client.Debug.getXPForLevel ~= nil))
        BurdJournals.debugPrint("=============================")
        self:setStatus("Mod state dumped", {r=0.5, g=0.8, b=1})
    end
end

function BurdJournals.UI.DebugPanel:onVerboseOn()
    BurdJournals.verboseLogging = true
    self:setStatus("Verbose logging enabled", {r=0.3, g=1, b=0.5})
    BurdJournals.UI.DebugPanel.sendVerboseLoggingToServer(true)
end

function BurdJournals.UI.DebugPanel:onVerboseOff()
    BurdJournals.verboseLogging = false
    self:setStatus("Verbose logging disabled", {r=1, g=0.7, b=0.3})
    BurdJournals.UI.DebugPanel.sendVerboseLoggingToServer(false)
end

-- In MP the server keeps its own verbose flag (used by server-side shouldDebugLog
-- and debug_* payload stripping). Propagate the toggle so both sides stay in sync.
-- Server validates admin access before honoring the request.
function BurdJournals.UI.DebugPanel.sendVerboseLoggingToServer(enabled)
    if not (isClient and isClient()) then
        return
    end
    local player = getPlayer and getPlayer()
    if not player then
        return
    end
    sendClientCommand(player, "BurdJournals", "setVerboseLogging", { enabled = enabled == true })
end

-- ============================================================================
-- Status and Close
-- ============================================================================

function BurdJournals.UI.DebugPanel:setStatus(message, color)
    message = debugTextFromEnglish(message)
    if self.statusLabel then
        self.statusLabel:setName(message)
        if color then
            self.statusLabel:setColor(color.r, color.g, color.b)
        end
    end
    self.statusTime = getTimestampMs and getTimestampMs() or os.time() * 1000
end

-- Safety handlers to ensure dragging state is always cleaned up
function BurdJournals.UI.DebugPanel:onMouseUp(x, y)
    self.dragging = false
    return ISPanel.onMouseUp(self, x, y)
end

function BurdJournals.UI.DebugPanel:onMouseUpOutside(x, y)
    self.dragging = false
    return ISPanel.onMouseUpOutside(self, x, y)
end

function BurdJournals.UI.DebugPanel:onClose(skipBaselineDraftConfirm)
    if not skipBaselineDraftConfirm and self:hasUnsavedBaselineDraft() then
        self:confirmDiscardBaselineDraft(
            getText("UI_BurdJournals_BaselineDraftActionCloseDebug") or "close the debug panel",
            function()
                self:onClose(true)
            end
        )
        return
    end

    self.dragging = false
    self:setVisible(false)
    self:removeFromUIManager()
    BurdJournals.UI.DebugPanel.instance = nil
end

function BurdJournals.UI.DebugPanel:close()
    self:onClose()
end

-- ============================================================================
-- Static: Open the debug panel
-- ============================================================================

function BurdJournals.UI.DebugPanel.Open(player)
    if BurdJournals.UI.DebugPanel.instance then
        local activePlayer = player or BurdJournals.UI.DebugPanel.instance.player or getPlayer()
        closePlayerInventoryPanelsForController(activePlayer)
        BurdJournals.UI.DebugPanel.instance:setVisible(true)
        return BurdJournals.UI.DebugPanel.instance
    end
    
    player = player or getPlayer()
    if not player then return nil end
    closePlayerInventoryPanelsForController(player)
    
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local panelW, panelH = BurdJournals.UI.DebugPanel.getPanelDimensions()
    local x = (screenW - panelW) / 2
    local y = (screenH - panelH) / 2
    
    local panel = BurdJournals.UI.DebugPanel:new(x, y, player)
    panel:initialise()
    panel:instantiate()
    panel:addToUIManager()
    panel:setVisible(true)
    
    BurdJournals.UI.DebugPanel.instance = panel
    return panel
end
