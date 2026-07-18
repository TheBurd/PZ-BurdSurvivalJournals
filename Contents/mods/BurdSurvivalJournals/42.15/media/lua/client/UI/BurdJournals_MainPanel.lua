
require "BurdJournals_Shared"
require "ISUI/ISPanelJoypad"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISModalDialog"
require "ISUI/ISTextEntryBox"
require "UI/BurdJournals_UIShared"
if getCore and getCore():getGameVersion() and tostring(getCore():getGameVersion()):match("^42") then
    require "TimedActions/ISInventoryTransferUtil"
end

BurdJournals = BurdJournals or {}
BurdJournals.UI = BurdJournals.UI or {}
BurdJournals.UI.LIST_PAGINATION_THRESHOLD = BurdJournals.UI.LIST_PAGINATION_THRESHOLD or 50
BurdJournals.UI.LIST_PAGINATION_PAGE_SIZE = BurdJournals.UI.LIST_PAGINATION_PAGE_SIZE or 50
BurdJournals.UI.LIST_PAGINATION_HEIGHT = BurdJournals.UI.LIST_PAGINATION_HEIGHT or 26

if not getUILayoutMetrics then
    function getUILayoutMetrics()
        return {
            rowHeight = 52,
            smallHeight = 14,
            bodyFont = UIFont and UIFont.Small or nil,
        }
    end
end

local bsjFallbackPrint = print

local function bsjWriteLogLine(msg)
    local line = tostring(msg or "")
    -- Log gating: always emit warnings/errors; gate informational lines behind the
    -- verbose toggle (or MP perf logging) so mod-heavy production servers aren't
    -- spammed with per-claim/per-backup diagnostics.
    local upper = line:upper()
    local important = upper:find("WARN", 1, true) ~= nil
        or upper:find("ERROR", 1, true) ~= nil
        or upper:find("FATAL", 1, true) ~= nil
    if not important then
        local verbose = BurdJournals and BurdJournals.shouldDebugLog and BurdJournals.shouldDebugLog()
        local mpPerf = BurdJournals and BurdJournals.shouldLogMPPerf and BurdJournals.shouldLogMPPerf()
        if not verbose and not mpPerf then
            return
        end
    end
    if BurdJournals and BurdJournals.writeLogLine then
        BurdJournals.writeLogLine(line)
    elseif bsjFallbackPrint then
        bsjFallbackPrint(line)
    end
end

local function bsjFormatEntryStoreCounts(counts)
    if type(counts) ~= "table" then
        return "nil"
    end
    return "skills=" .. tostring(tonumber(counts.skills) or 0)
        .. ",traits=" .. tostring(tonumber(counts.traits) or 0)
        .. ",stats=" .. tostring(tonumber(counts.stats) or 0)
        .. ",recipes=" .. tostring(tonumber(counts.recipes) or 0)
end

BurdJournals.Sounds = {

    PAGE_TURN = {ui = "UISelectListItem", world = "PageFlipBook"},
    LEARN_COMPLETE = {ui = "UIActivateButton", world = "CloseBook"},
    OPEN_JOURNAL = {ui = "UIActivateTab", world = "OpenBook"},
    QUEUE_ADD = {ui = "UISelectListItem", world = "PageFlipMagazine"},

    DISSOLVE = {world = "BreakWoodItem"},
    ERASE = {world = "RummageInInventory"},

    RECORD = {ui = "UIActivateButton"},
}

local traitDefCache = {}

-- Centralized reward theme palettes. Rendering code uses self.palette.fieldName
-- instead of if/elseif branching. To add a new journal type, define a new entry
-- here ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â all downstream rendering picks it up automatically via paletteColor().
-- The "worn" palette is the universal fallback; other palettes only need to
-- override fields that differ from worn.
local REWARD_PALETTES = {}

REWARD_PALETTES.worn = {
    -- Animated backdrop (only used when a theme opts into panel animation)
    panelBg          = nil,
    stripePrimary    = nil,
    stripeSecondary  = nil,
    panelBorder      = nil,

    -- Header
    headerColor      = {r=0.22, g=0.20, b=0.15},
    headerAccent     = {r=0.4, g=0.35, b=0.25},
    headerTypeText   = {r=1, g=0.9, b=0.85},

    -- Tabs
    tabActive        = {r=0.35, g=0.28, b=0.18},
    tabInactive      = {r=0.18, g=0.15, b=0.12},
    tabAccent        = {r=0.5, g=0.4, b=0.25},
    forgetTab        = {
        active       = {r=0.52, g=0.20, b=0.56},
        inactive     = {r=0.22, g=0.10, b=0.26},
        accent       = {r=0.93, g=0.60, b=0.28},
        textInactive = {r=0.88, g=0.72, b=0.84},
    },

    -- Rarity badge
    rarityBadgeBg    = {r=0.5, g=0.4, b=0.2, a=0.8},

    -- Author box
    authorBoxBg      = {r=0.12, g=0.11, b=0.10},
    authorBoxBorder  = {r=0.30, g=0.28, b=0.25},
    authorText       = {r=0.80, g=0.85, b=0.90},
    flavorText       = {r=0.5, g=0.55, b=0.6},
    claimsText       = {r=0.82, g=0.84, b=0.66},
    summaryText      = {r=0.7, g=0.75, b=0.8},
    itemHeaderBg     = {r=0.15, g=0.14, b=0.12, a=0.4},
    itemHeaderText   = {r=0.9, g=0.8, b=0.6},
    itemHeaderCount  = {r=0.5, g=0.5, b=0.45},
    cardText         = {r=0.95, g=0.9, b=0.85},

    -- Cards
    cardBg           = {r=0.14, g=0.13, b=0.11},
    cardBorder       = {r=0.35, g=0.32, b=0.28},
    cardAccent       = {r=0.5, g=0.6, b=0.4},

    -- Level squares (normal unclaimed)
    levelFilled      = {r=0.5, g=0.6, b=0.4},
    levelProgress    = {r=0.35, g=0.42, b=0.28},
    levelEmpty       = {r=0.1, g=0.1, b=0.1},
    -- Level squares (queued single)
    levelQueuedFilled   = {r=0.4, g=0.5, b=0.6},
    levelQueuedProgress = {r=0.25, g=0.3, b=0.4},
    levelQueuedEmpty    = {r=0.1, g=0.1, b=0.1},
    -- Level squares (absorb-all)
    levelAbsorbFilled   = {r=0.45, g=0.55, b=0.35},
    levelAbsorbProgress = {r=0.3, g=0.38, b=0.22},
    levelAbsorbEmpty    = {r=0.1, g=0.1, b=0.1},

    -- Progress bar
    progressBarFill  = {r=0.35, g=0.55, b=0.25, a=0.85},

    -- Footer
    footerDivider    = {r=0.25, g=0.35, b=0.45, a=0.3},

    -- Buttons
    dissolveBtnBg     = {r=0.4, g=0.15, b=0.15, a=0.8},
    dissolveBtnBorder = {r=0.6, g=0.3, b=0.3, a=1},
    dissolveBtnText   = {r=1, g=0.9, b=0.9, a=1},
    closeBtnBg        = {r=0.15, g=0.13, b=0.12, a=0.8},
    closeBtnBorder    = {r=0.4, g=0.35, b=0.3, a=1},
    closeBtnText      = {r=0.9, g=0.85, b=0.8, a=1},
    absorbTabBtnBg     = {r=0.18, g=0.22, b=0.14, a=0.8},
    absorbTabBtnBorder = {r=0.35, g=0.45, b=0.3, a=1},
    absorbAllBtnBg     = {r=0.2, g=0.25, b=0.15, a=0.8},
    absorbAllBtnBorder = {r=0.4, g=0.5, b=0.3, a=1},
    feedbackInfo      = {r=0.5, g=0.7, b=0.8},
    feedbackWarn      = {r=0.9, g=0.7, b=0.3},
    feedbackSuccess   = {r=0.6, g=0.8, b=0.5},
    feedbackMuted     = {r=0.7, g=0.7, b=0.5},
    feedbackError     = {r=0.9, g=0.4, b=0.4},
}

REWARD_PALETTES.worn_bloody = {
    headerColor      = {r=0.30, g=0.22, b=0.12},
    headerAccent     = {r=0.5, g=0.35, b=0.2},
    headerTypeText   = {r=1, g=0.9, b=0.85},
}

REWARD_PALETTES.bloody = {
    headerColor      = {r=0.45, g=0.08, b=0.08},
    headerAccent     = {r=0.7, g=0.15, b=0.15},
    headerTypeText   = {r=1, g=0.9, b=0.85},

    tabActive        = {r=0.5, g=0.15, b=0.15},
    tabInactive      = {r=0.2, g=0.1, b=0.1},
    tabAccent        = {r=0.7, g=0.2, b=0.2},

    rarityBadgeBg    = {r=0.6, g=0.15, b=0.15, a=0.8},

    cardBg           = {r=0.18, g=0.12, b=0.12},
    cardBorder       = {r=0.4, g=0.2, b=0.2},
    cardAccent       = {r=0.7, g=0.25, b=0.25},

    levelFilled      = {r=0.65, g=0.25, b=0.25},
    levelProgress    = {r=0.45, g=0.18, b=0.18},

    progressBarFill  = {r=0.6, g=0.2, b=0.15, a=0.85},

    absorbTabBtnBg     = {r=0.3, g=0.1, b=0.1, a=0.8},
    absorbTabBtnBorder = {r=0.5, g=0.2, b=0.2, a=1},
    absorbAllBtnBg     = {r=0.35, g=0.1, b=0.1, a=0.8},
    absorbAllBtnBorder = {r=0.6, g=0.2, b=0.2, a=1},
}

REWARD_PALETTES.cursed = {
    panelBg          = {r=0.09, g=0.06, b=0.05, a=0.78},
    panelBorder      = {r=0.62, g=0.22, b=0.15, a=0.42},
    smokePrimary     = {r=0.30, g=0.09, b=0.08, a=0.14},
    smokeSecondary   = {r=0.16, g=0.08, b=0.06, a=0.10},
    emberPrimary     = {r=0.90, g=0.42, b=0.18, a=0.18},
    emberSecondary   = {r=0.78, g=0.20, b=0.16, a=0.12},
    sigil            = {r=0.88, g=0.45, b=0.23, a=0.14},
    scrollSpeed      = 10,

    headerColor      = {r=0.20, g=0.10, b=0.09},
    headerAccent     = {r=0.72, g=0.24, b=0.16},
    headerTypeText   = {r=0.95, g=0.89, b=0.82},

    tabActive        = {r=0.35, g=0.14, b=0.10},
    tabInactive      = {r=0.15, g=0.09, b=0.08},
    tabAccent        = {r=0.72, g=0.24, b=0.16},
    forgetTab        = {
        active       = {r=0.34, g=0.20, b=0.08},
        inactive     = {r=0.18, g=0.11, b=0.08},
        accent       = {r=0.88, g=0.62, b=0.22},
        textInactive = {r=0.95, g=0.84, b=0.62},
    },

    rarityBadgeBg    = {r=0.46, g=0.18, b=0.12, a=0.84},

    authorBoxBg      = {r=0.13, g=0.08, b=0.07},
    authorBoxBorder  = {r=0.40, g=0.18, b=0.13},
    authorText       = {r=0.92, g=0.86, b=0.82},
    flavorText       = {r=0.82, g=0.58, b=0.46},
    claimsText       = {r=0.94, g=0.74, b=0.42},
    summaryText      = {r=0.84, g=0.68, b=0.54},
    itemHeaderBg     = {r=0.16, g=0.09, b=0.08, a=0.46},
    itemHeaderText   = {r=0.96, g=0.90, b=0.84},
    itemHeaderCount  = {r=0.92, g=0.70, b=0.40},
    cardText         = {r=0.95, g=0.89, b=0.84},

    cardBg           = {r=0.15, g=0.09, b=0.08},
    cardBorder       = {r=0.46, g=0.20, b=0.14},
    cardAccent       = {r=0.74, g=0.28, b=0.18},

    levelFilled      = {r=0.84, g=0.52, b=0.24},
    levelProgress    = {r=0.52, g=0.24, b=0.16},
    levelEmpty       = {r=0.08, g=0.08, b=0.08},
    levelQueuedFilled   = {r=0.82, g=0.58, b=0.28},
    levelQueuedProgress = {r=0.48, g=0.26, b=0.16},
    levelQueuedEmpty    = {r=0.08, g=0.08, b=0.08},
    levelAbsorbFilled   = {r=0.88, g=0.66, b=0.30},
    levelAbsorbProgress = {r=0.56, g=0.28, b=0.18},
    levelAbsorbEmpty    = {r=0.08, g=0.08, b=0.08},

    progressBarFill  = {r=0.72, g=0.28, b=0.16, a=0.88},

    absorbTabBtnBg     = {r=0.24, g=0.11, b=0.09, a=0.88},
    absorbTabBtnBorder = {r=0.60, g=0.24, b=0.16, a=1},
    absorbAllBtnBg     = {r=0.34, g=0.14, b=0.10, a=0.88},
    absorbAllBtnBorder = {r=0.74, g=0.28, b=0.18, a=1},

    dissolveBtnBg     = {r=0.45, g=0.14, b=0.12, a=0.84},
    dissolveBtnBorder = {r=0.72, g=0.28, b=0.22, a=1},
    dissolveBtnText   = {r=1, g=0.92, b=0.86, a=1},
    closeBtnBg        = {r=0.16, g=0.10, b=0.09, a=0.84},
    closeBtnBorder    = {r=0.44, g=0.20, b=0.14, a=1},
    closeBtnText      = {r=0.92, g=0.86, b=0.82, a=1},
    feedbackInfo      = {r=0.90, g=0.72, b=0.48},
    feedbackWarn      = {r=0.94, g=0.74, b=0.42},
    feedbackSuccess   = {r=0.88, g=0.62, b=0.38},
    feedbackMuted     = {r=0.70, g=0.60, b=0.52},
    feedbackError     = {r=0.96, g=0.56, b=0.38},
}

REWARD_PALETTES.yuletide = {
    -- Animated backdrop
    panelBg          = {r=0.94, g=0.95, b=0.91, a=0.74},
    stripePrimary    = {r=0.78, g=0.19, b=0.16, a=0.12},
    stripeSecondary  = {r=0.18, g=0.42, b=0.22, a=0.10},
    panelBorder      = {r=0.74, g=0.18, b=0.15, a=0.50},
    scrollSpeed      = 12,

    -- Header
    headerColor      = {r=0.90, g=0.94, b=0.89},
    headerAccent     = {r=0.74, g=0.18, b=0.15},
    headerTypeText   = {r=0.18, g=0.32, b=0.18},

    -- Tabs
    tabActive        = {r=0.20, g=0.42, b=0.22},
    tabInactive      = {r=0.86, g=0.89, b=0.84},
    tabAccent        = {r=0.74, g=0.18, b=0.15},
    forgetTab        = {
        active       = {r=0.52, g=0.14, b=0.12},
        inactive     = {r=0.26, g=0.08, b=0.08},
        accent       = {r=0.74, g=0.18, b=0.15},
        textInactive = {r=0.92, g=0.78, b=0.72},
    },

    -- Rarity badge
    rarityBadgeBg    = {r=0.74, g=0.18, b=0.15, a=0.30},

    -- Author box
    authorBoxBg      = {r=0.91, g=0.94, b=0.90},
    authorBoxBorder  = {r=0.28, g=0.50, b=0.28},
    authorText       = {r=0.22, g=0.30, b=0.22},
    flavorText       = {r=0.34, g=0.32, b=0.28},
    claimsText       = {r=0.74, g=0.18, b=0.15},
    summaryText      = {r=0.24, g=0.27, b=0.24},
    itemHeaderBg     = {r=0.20, g=0.40, b=0.22, a=0.45},
    itemHeaderText   = {r=0.98, g=0.95, b=0.90},
    itemHeaderCount  = {r=0.74, g=0.18, b=0.15},
    cardText         = {r=0.22, g=0.25, b=0.22},

    -- Cards
    cardBg           = {r=0.80, g=0.90, b=0.79, a=0.78},
    cardBorder       = {r=0.56, g=0.22, b=0.20},
    cardAccent       = {r=0.74, g=0.18, b=0.15},

    -- Level squares (normal unclaimed)
    levelFilled      = {r=0.82, g=0.78, b=0.30},
    levelProgress    = {r=0.24, g=0.48, b=0.22},
    levelEmpty       = {r=0.76, g=0.79, b=0.74},
    -- Level squares (queued single)
    levelQueuedFilled   = {r=0.82, g=0.78, b=0.30},
    levelQueuedProgress = {r=0.18, g=0.36, b=0.16},
    levelQueuedEmpty    = {r=0.76, g=0.79, b=0.74},
    -- Level squares (absorb-all)
    levelAbsorbFilled   = {r=0.48, g=0.72, b=0.32},
    levelAbsorbProgress = {r=0.18, g=0.36, b=0.16},
    levelAbsorbEmpty    = {r=0.76, g=0.79, b=0.74},

    -- Progress bar
    progressBarFill  = {r=0.72, g=0.18, b=0.14, a=0.88},

    -- Footer
    footerDivider    = {r=0.48, g=0.24, b=0.18, a=0.38},

    -- Buttons
    dissolveBtnBg     = {r=0.42, g=0.12, b=0.10, a=0.8},
    dissolveBtnBorder = {r=0.74, g=0.18, b=0.15, a=1},
    dissolveBtnText   = {r=1, g=0.9, b=0.9, a=1},
    closeBtnBg        = {r=0.28, g=0.40, b=0.26, a=0.84},
    closeBtnBorder    = {r=0.74, g=0.18, b=0.15, a=1},
    closeBtnText      = {r=0.98, g=0.95, b=0.90, a=1},
    absorbTabBtnBg     = {r=0.20, g=0.43, b=0.21, a=0.88},
    absorbTabBtnBorder = {r=0.74, g=0.18, b=0.15, a=1},
    absorbAllBtnBg     = {r=0.62, g=0.18, b=0.16, a=0.88},
    absorbAllBtnBorder = {r=0.74, g=0.18, b=0.15, a=1},
    feedbackInfo      = {r=0.24, g=0.45, b=0.24},
    feedbackWarn      = {r=0.74, g=0.18, b=0.15},
    feedbackSuccess   = {r=0.24, g=0.45, b=0.24},
    feedbackMuted     = {r=0.34, g=0.32, b=0.28},
    feedbackError     = {r=0.74, g=0.18, b=0.15},
}

-- Merge any add-on palettes registered on the base table (see
-- BurdJournals.registerRewardPalette) into the local palette set so they are
-- picked up by getRewardPalette/paletteColor exactly like the built-ins.
local function mergeRegisteredRewardPalettes()
    local registered = BurdJournals and BurdJournals.REGISTERED_REWARD_PALETTES
    if type(registered) ~= "table" then return end
    for key, palette in pairs(registered) do
        if type(palette) == "table" then
            REWARD_PALETTES[key] = palette
        end
    end
end
mergeRegisteredRewardPalettes()

local function getRewardPalette(themeKey)
    -- Late-registered add-on palettes: pick them up on demand as a safety net
    -- in case registration happened after this file loaded.
    if themeKey and not REWARD_PALETTES[themeKey] then
        local registered = BurdJournals and BurdJournals.getRegisteredRewardPalette
            and BurdJournals.getRegisteredRewardPalette(themeKey)
        if type(registered) == "table" then
            REWARD_PALETTES[themeKey] = registered
        end
    end
    return REWARD_PALETTES[themeKey] or REWARD_PALETTES.worn
end



local function paletteColor(palette, key)
    return (palette and palette[key]) or REWARD_PALETTES.worn[key]
end

local function applyPaletteToButton(btn, palette, bgKey, borderKey, textKey)
    if not btn then return end
    local bg = paletteColor(palette, bgKey)
    local bd = paletteColor(palette, borderKey)
    local tx = paletteColor(palette, textKey)
    if bg then btn.backgroundColor = {r=bg.r, g=bg.g, b=bg.b, a=bg.a or 0.8} end
    if bd then btn.borderColor = {r=bd.r, g=bd.g, b=bd.b, a=bd.a or 1} end
    if tx then btn.textColor = {r=tx.r, g=tx.g, b=tx.b, a=tx.a or 1} end
end

local isUnwrappedYuletideRewardState
local getHeaderJournalIconTexture

-- Backward-compat alias: drawAnimatedStripedJournalBackdrop reads panelBg/stripePrimary/etc.
local YULETIDE_PANEL_THEME = REWARD_PALETTES.yuletide
local CURSED_PANEL_THEME = REWARD_PALETTES.cursed

local function getAbsorptionRewardThemeState(journal, journalData)
    local isBloody = BurdJournals.isBloody and BurdJournals.isBloody(journal) or false
    local hasBloodyOrigin = BurdJournals.hasBloodyOrigin and BurdJournals.hasBloodyOrigin(journal) or false
    local isYuletideReward = isUnwrappedYuletideRewardState and isUnwrappedYuletideRewardState(journal, journalData) or false
    local isCursedReward = type(journalData) == "table" and journalData.isCursedReward == true
    -- Add-on themes (registered via BurdJournals.registerRewardTheme) take
    -- precedence when their predicate matches, so a companion mod can theme its
    -- own journal type without editing this fallback chain.
    local registeredTheme = BurdJournals.resolveRegisteredRewardTheme
        and BurdJournals.resolveRegisteredRewardTheme(journal, journalData)
        or nil
    local rewardTheme = registeredTheme
        or (isYuletideReward and "yuletide")
        or (isCursedReward and "cursed")
        or (isBloody and "bloody")
        or (hasBloodyOrigin and "worn_bloody")
        or "worn"

    return {
        isBloody = isBloody,
        hasBloodyOrigin = hasBloodyOrigin,
        isYuletideReward = isYuletideReward,
        isCursedReward = isCursedReward,
        rewardTheme = rewardTheme,
        palette = getRewardPalette(rewardTheme),
    }
end

local function getJournalFlavorDisplayText(data, fallbackKey)
    if type(data) ~= "table" then
        return getText(fallbackKey)
    end

    local flavorText = data.flavorText
    if type(flavorText) == "string" and flavorText ~= "" then
        return flavorText
    end

    if data.flavorKey then
        local translated = getText(data.flavorKey)
        if translated and translated ~= data.flavorKey then
            return translated
        end
    end

    return getText(fallbackKey)
end

local function buildWrappedTextLayout(font, text, maxWidth)
    if type(text) ~= "string" or text == "" then
        return nil
    end

    local textManager = getTextManager and getTextManager()
    if not textManager then
        return nil
    end

    local width = math.max(80, math.floor(tonumber(maxWidth) or 80))
    local lines = {}
    local normalized = tostring(text):gsub("\r\n", "\n"):gsub("\r", "\n")

    for paragraph in (normalized .. "\n"):gmatch("(.-)\n") do
        if paragraph == "" then
            if #lines == 0 or lines[#lines] ~= "" then
                table.insert(lines, "")
            end
        else
            local currentLine = ""
            for word in paragraph:gmatch("%S+") do
                local candidate = currentLine == "" and word or (currentLine .. " " .. word)
                if currentLine ~= "" and textManager:MeasureStringX(font, candidate) > width then
                    table.insert(lines, currentLine)
                    currentLine = word
                else
                    currentLine = candidate
                end
            end
            if currentLine ~= "" then
                table.insert(lines, currentLine)
            end
        end
    end

    if #lines == 0 then
        lines[1] = normalized
    end

    local lineHeight = math.max(14, textManager:MeasureStringY(font, "Ag"))
    return {
        font = font,
        lines = lines,
        lineHeight = lineHeight,
        height = lineHeight * #lines,
    }
end

local function drawWrappedTextLayout(target, layout, x, y, color)
    if not target or not layout or type(layout.lines) ~= "table" then
        return 0
    end

    local font = layout.font or UIFont.Small
    local r = (color and color.r) or 1
    local g = (color and color.g) or 1
    local b = (color and color.b) or 1
    local a = (color and color.a) or 1
    local lineY = y

    for _, line in ipairs(layout.lines) do
        target:drawText(line, x, lineY, r, g, b, a, font)
        lineY = lineY + (layout.lineHeight or 14)
    end

    return lineY - y
end

local function refreshAbsorptionAuthorBoxLayout(panel, padding)
    if not panel or panel.mode ~= "absorb" then
        return
    end

    local innerPadding = 10
    local contentWidth = math.max(80, panel.width - padding * 2 - innerPadding * 2)
    local authorNameDisplay = panel.authorName or getText("UI_BurdJournals_Unknown")
    local authorFormat = getText("UI_BurdJournals_FromNotesOf")

    panel.authorBoxInnerPadding = innerPadding
    panel.authorBoxAuthorText = BurdJournals.formatText(authorFormat, authorNameDisplay)
    panel.authorTextLayout = buildWrappedTextLayout(UIFont.Small, panel.authorBoxAuthorText, contentWidth)
    panel.flavorTextLayout = buildWrappedTextLayout(UIFont.Small, panel.flavorText, contentWidth)

    panel.claimsTextDisplay = nil
    panel.claimsTextLayout = nil
    if panel.showClaimsLeftBeforeDissolved then
        local claimsLeft = panel:getLimitedLootClaimsLeft() or 0
        panel.claimsTextDisplay = BurdJournals.formatText(
            getText("UI_BurdJournals_ClaimsLeftBeforeDissolved") or "Claims Left Before Dissolved: %d",
            claimsLeft
        )
        panel.claimsTextLayout = buildWrappedTextLayout(UIFont.Small, panel.claimsTextDisplay, contentWidth)
    end

    local boxPaddingY = 8
    local sectionSpacing = 4
    local contentHeight = boxPaddingY * 2
    if panel.authorTextLayout then
        contentHeight = contentHeight + panel.authorTextLayout.height
    end
    if panel.flavorTextLayout and panel.flavorTextLayout.height > 0 then
        contentHeight = contentHeight + sectionSpacing + panel.flavorTextLayout.height
    end
    if panel.claimsTextLayout and panel.claimsTextLayout.height > 0 then
        contentHeight = contentHeight + sectionSpacing + panel.claimsTextLayout.height
    end

    local minHeight = panel.showClaimsLeftBeforeDissolved and 60 or 44
    panel.authorBoxHeight = math.max(minHeight, contentHeight)
end

local function applyAbsorptionPresentationState(panel)
    if not panel or not panel.journal then
        return nil
    end

    local journalData = BurdJournals.getJournalData and BurdJournals.getJournalData(panel.journal) or nil
    local state = getAbsorptionRewardThemeState(panel.journal, journalData)

    panel.isBloody = state.isBloody
    panel.hasBloodyOrigin = state.hasBloodyOrigin
    panel.isYuletideReward = state.isYuletideReward
    panel.isCursedReward = state.isCursedReward
    panel.rewardTheme = state.rewardTheme
    panel.palette = state.palette
    panel.headerColor = paletteColor(state.palette, "headerColor")
    panel.headerAccent = paletteColor(state.palette, "headerAccent")

    -- Registered add-on theme header (checked first so companion mods present
    -- their own header/rarity/flavor without a hardcoded branch here).
    local themeHeader = BurdJournals.REWARD_THEME_HEADERS
        and state.rewardTheme
        and BurdJournals.REWARD_THEME_HEADERS[state.rewardTheme]
        or nil
    if themeHeader then
        panel.typeText = themeHeader.typeKey and getText(themeHeader.typeKey) or nil
        panel.rarityText = themeHeader.rarityKey and getText(themeHeader.rarityKey) or nil
        panel.flavorText = getJournalFlavorDisplayText(journalData, themeHeader.flavorKey)
    elseif state.isYuletideReward then
        panel.typeText = getText("UI_BurdJournals_YuletideJournalUnwrapped") or "Yuletide Journal"
        panel.rarityText = getText("UI_BurdJournals_YuletideRarity") or "Seasonal Gift"
        panel.flavorText = getJournalFlavorDisplayText(journalData, "UI_BurdJournals_YuletideFlavor")

        panel.typeText = getText("UI_BurdJournals_CursedJournalHeader")
        panel.rarityText = getText("UI_BurdJournals_RarityCursed")
        panel.flavorText = getJournalFlavorDisplayText(journalData, "UI_BurdJournals_CursedFlavor")
    elseif state.isBloody then
        panel.typeText = getText("UI_BurdJournals_BloodyJournalHeader")
        panel.rarityText = getText("UI_BurdJournals_RarityRare")
        panel.flavorText = getJournalFlavorDisplayText(journalData, "UI_BurdJournals_BloodyFlavor")
    elseif state.hasBloodyOrigin then
        panel.typeText = getText("UI_BurdJournals_WornJournalHeader")
        panel.rarityText = getText("UI_BurdJournals_RarityUncommon")
        panel.flavorText = getJournalFlavorDisplayText(journalData, "UI_BurdJournals_WornBloodyFlavor")
    else
        panel.typeText = getText("UI_BurdJournals_WornJournalHeader")
        panel.rarityText = nil
        panel.flavorText = getJournalFlavorDisplayText(journalData, "UI_BurdJournals_WornFlavor")
    end

    panel.authorName = (BurdJournals.getJournalDisplayAuthor and BurdJournals.getJournalDisplayAuthor(journalData))
        or getText("UI_BurdJournals_UnknownSurvivor")
    panel.headerIconTexture = getHeaderJournalIconTexture("absorb", panel.journal, journalData, state.isBloody)
    panel.headerIconSize = 20

    return journalData
end

local function shouldExposeLootNotesTab(journalData)
    return BurdJournals.hasJournalNotes and BurdJournals.hasJournalNotes(journalData) == true
end

local function drawAnimatedStripedJournalBackdrop(target, x, y, width, height, theme, effectKey)
    if not target or not theme then
        return
    end
    if BurdJournals.shouldRenderAnimatedJournalVisuals
        and not BurdJournals.shouldRenderAnimatedJournalVisuals(effectKey or "journal_panel_backdrop") then
        return
    end

    local drawX = math.floor(tonumber(x) or 0)
    local drawY = math.floor(tonumber(y) or 0)
    local drawW = math.floor(tonumber(width) or 0)
    local drawH = math.floor(tonumber(height) or 0)
    if drawW <= 0 or drawH <= 0 then
        return
    end

    target:drawRect(drawX, drawY, drawW, drawH, theme.panelBg.a or 0.9, theme.panelBg.r, theme.panelBg.g, theme.panelBg.b)

    local useStencil = target.setStencilRect and target.clearStencilRect
    if useStencil then
        target:setStencilRect(drawX, drawY, drawW, drawH)
    end

    local stripeWidth = 26
    local stripeSpacing = 60
    local patternSpan = stripeSpacing * 2
    local segmentHeight = 14
    local slopeStep = 12
    local nowMs = (getTimestampMs and getTimestampMs()) or 0
    local scrollSpeed = tonumber(theme.scrollSpeed) or 18
    local offset = math.floor(((nowMs / 1000) * scrollSpeed) % patternSpan)
    local startX = drawX - drawH - patternSpan + offset
    local maxX = drawX + drawW + drawH + patternSpan
    local bandIndex = 0

    for bandX = startX, maxX, stripeSpacing do
        local bandColor = (bandIndex % 2 == 0) and theme.stripePrimary or theme.stripeSecondary
        local bandAlpha = math.max(0, math.min(1, bandColor.a or 0))
        if bandAlpha > 0 then
            local rowY = drawY
            local rowX = bandX
            local maxY = drawY + drawH
            while rowY < maxY do
                local drawSegmentH = math.min(segmentHeight, maxY - rowY)
                target:drawRect(math.floor(rowX), rowY, stripeWidth, drawSegmentH, bandAlpha, bandColor.r, bandColor.g, bandColor.b)
                rowX = rowX + slopeStep
                rowY = rowY + drawSegmentH
            end
        end
        bandIndex = bandIndex + 1
    end

    if useStencil then
        target:clearStencilRect()
    end

    if theme.border then
        target:drawRectBorder(drawX, drawY, drawW, drawH, theme.border.a or 0.5, theme.border.r, theme.border.g, theme.border.b)
    end
end

local function getTraitDefinition(traitId)
    if not traitId then return nil end

    if traitDefCache[traitId] then
        return traitDefCache[traitId]
    end

    local traitIdLower = string.lower(traitId)
    local traitIdNorm = traitIdLower:gsub("%s", "")

    local function resolveTraitTexture(rawTexture)
        if not rawTexture then
            return nil
        end
        if type(rawTexture) ~= "string" then
            return rawTexture
        end
        if not getTexture then
            return nil
        end
        return getTexture(rawTexture)
            or getTexture("media/ui/" .. rawTexture)
            or getTexture("media/ui/" .. rawTexture .. ".png")
            or getTexture("media/ui/Traits/" .. rawTexture)
            or getTexture("media/ui/Traits/" .. rawTexture .. ".png")
    end

    local function createCacheEntry(def)
        local defLabel = (def.getLabel and def:getLabel()) or ""
        local defType = def.getType and def:getType() or nil
        local defName = ""
        if defType then
            if defType.getName then
                defName = defType:getName() or tostring(defType)
            else
                defName = tostring(defType)
            end
        elseif def.getName then
            defName = def:getName() or ""
            defType = defName
        end
        local cached = {
            def = def,
            label = defLabel,
            name = defName,
            type = defType
        }
        local rawTexture = nil
        if def.getTexture then
            rawTexture = def:getTexture()
        elseif def.texture ~= nil then
            rawTexture = def.texture
        end
        cached.texture = resolveTraitTexture(rawTexture)
        traitDefCache[traitId] = cached
        return cached
    end

    if CharacterTraitDefinition and CharacterTraitDefinition.getTraits then
        local allTraits = CharacterTraitDefinition.getTraits()

        for i = 0, allTraits:size() - 1 do
            local def = allTraits:get(i)
            local defLabel = def:getLabel() or ""
            local defType = def:getType()
            local defName = ""
            if defType then
                if defType.getName then
                    defName = defType:getName() or tostring(defType)
                else
                    defName = tostring(defType)
                end
            end

            local defLabelLower = string.lower(defLabel)
            local defNameLower = string.lower(defName)

            if (defLabel == traitId) or (defName == traitId) or
               (defLabelLower == traitIdLower) or (defNameLower == traitIdLower) then
                return createCacheEntry(def)
            end
        end

        for i = 0, allTraits:size() - 1 do
            local def = allTraits:get(i)
            local defLabel = def:getLabel() or ""
            local defType = def:getType()
            local defName = ""
            if defType then
                if defType.getName then
                    defName = defType:getName() or tostring(defType)
                else
                    defName = tostring(defType)
                end
            end

            local defLabelNorm = string.lower(defLabel):gsub("%s", "")
            local defNameNorm = string.lower(defName):gsub("%s", "")

            if (defLabelNorm == traitIdNorm) or (defNameNorm == traitIdNorm) then
                return createCacheEntry(def)
            end
        end

        for i = 0, allTraits:size() - 1 do
            local def = allTraits:get(i)
            local defLabel = def:getLabel() or ""
            local defType = def:getType()
            local defName = ""
            if defType then
                if defType.getName then
                    defName = defType:getName() or tostring(defType)
                else
                    defName = tostring(defType)
                end
            end

            local defLabelLower = string.lower(defLabel)
            local defNameLower = string.lower(defName)

            if defLabelLower:find(traitIdLower, 1, true) or defNameLower:find(traitIdLower, 1, true) then
                return createCacheEntry(def)
            end
        end
    end

    if TraitFactory and TraitFactory.getTrait then
        local direct = TraitFactory.getTrait(traitId)
            or TraitFactory.getTrait(string.gsub(traitId, "^base:", ""))
        if direct then
            return createCacheEntry(direct)
        end

        local allTraits = TraitFactory.getTraits and TraitFactory.getTraits() or nil
        if allTraits and allTraits.size and allTraits.get then
            for i = 0, allTraits:size() - 1 do
                local trait = allTraits:get(i)
                local traitLabel = (trait and trait.getLabel and trait:getLabel()) or ""
                local traitType = (trait and trait.getType and trait:getType()) or ""
                local traitLabelLower = string.lower(tostring(traitLabel))
                local traitTypeLower = string.lower(tostring(traitType))
                local traitLabelNorm = traitLabelLower:gsub("%s", "")
                local traitTypeNorm = traitTypeLower:gsub("%s", "")

                if traitLabelLower == traitIdLower
                    or traitTypeLower == traitIdLower
                    or traitLabelNorm == traitIdNorm
                    or traitTypeNorm == traitIdNorm
                    or traitLabelLower:find(traitIdLower, 1, true)
                    or traitTypeLower:find(traitIdLower, 1, true) then
                    return createCacheEntry(trait)
                end
            end
        end
    end

    return nil
end

local function safeGetTraitName(traitId)
    if not traitId then return getText("UI_BurdJournals_UnknownTrait") or "Unknown Trait" end

    local traitDef = getTraitDefinition(traitId)
    if traitDef and traitDef.label then
        return traitDef.label
    end

    if TraitFactory and TraitFactory.getTrait then
        local traitObj = TraitFactory.getTrait(traitId)
        if traitObj and traitObj.getLabel then
            return traitObj:getLabel()
        end
    end

    return traitId:gsub("(%l)(%u)", "%1 %2")
end

local function getTraitTexture(traitId)
    if not traitId then return nil end

    local traitDef = getTraitDefinition(traitId)
    if traitDef and traitDef.texture then
        return traitDef.texture
    end

    return nil
end

local traitPositiveCache = {}
local traitCostLookup = nil

local function getTraitCost(traitId)
    if not traitId then return nil end

    if not traitCostLookup then
        traitCostLookup = BurdJournals.buildTraitCostLookup() or {}
    end

    local cost = traitCostLookup[string.lower(traitId)]
    if cost ~= nil then
        return cost
    end

    local traitCache = getTraitDefinition(traitId)
    if traitCache and traitCache.def and traitCache.def.getCost then
        return traitCache.def:getCost()
    end

    if TraitFactory and TraitFactory.getTrait then
        local traitObj = TraitFactory.getTrait(traitId)
        if traitObj and traitObj.getCost then
            return traitObj:getCost()
        end
    end

    return nil
end

local function isTraitPositive(traitId)
    if not traitId then return nil end

    if traitPositiveCache[traitId] ~= nil then
        local cached = traitPositiveCache[traitId]
        if cached == "nil" then return nil end
        return cached
    end

    local result = nil

    local cost = getTraitCost(traitId)
    if cost ~= nil then
        if cost > 0 then
            result = true
        elseif cost < 0 then
            result = false
        else
            result = nil
        end
    end

    traitPositiveCache[traitId] = (result == nil) and "nil" or result
    return result
end

local magazineTextureCache = {}
local smallTextWidthCache = {}

local function getCachedSmallTextWidth(text)
    local label = tostring(text or "")
    local cached = smallTextWidthCache[label]
    if cached ~= nil then
        return cached
    end
    local width = getTextManager():MeasureStringX(UIFont.Small, label)
    smallTextWidthCache[label] = width
    return width
end

local function syncListBoxScrollGeometry(listbox, resetScroll)
    if not listbox then
        return
    end

    if resetScroll and listbox.setYScroll then
        listbox:setYScroll(0)
    end

    if listbox.vscroll then
        if listbox.vscroll.setHeight then
            listbox.vscroll:setHeight(listbox:getHeight())
        end
        if listbox.vscroll.setX then
            listbox.vscroll:setX(listbox:getWidth() - listbox.vscroll:getWidth())
        end
        if listbox.vscroll.setY then
            listbox.vscroll:setY(0)
        end
        listbox.vscroll.scrolling = false
        if listbox.vscroll.updatePos then
            listbox.vscroll:updatePos()
        end
    end

    if listbox.updateScrollbars then
        listbox:updateScrollbars()
    elseif listbox.updateScrollBars then
        listbox:updateScrollBars()
    end
end

local function captureListBoxScrollState(listbox)
    if not listbox then
        return nil
    end

    local yScroll = 0
    if listbox.getYScroll then
        yScroll = tonumber(listbox:getYScroll()) or 0
    elseif listbox.yScroll then
        yScroll = tonumber(listbox.yScroll) or 0
    end

    return {
        yScroll = yScroll,
        smoothScrollY = tonumber(listbox.smoothScrollY),
        smoothScrollTargetY = tonumber(listbox.smoothScrollTargetY),
        selected = tonumber(listbox.selected) or -1,
    }
end

local function restoreListBoxScrollState(listbox, state)
    if not listbox or not state then
        return
    end

    local yScroll = tonumber(state.yScroll) or 0
    if listbox.setYScroll then
        listbox:setYScroll(yScroll)
    else
        listbox.yScroll = yScroll
    end
    listbox.smoothScrollY = tonumber(state.smoothScrollY) or yScroll
    listbox.smoothScrollTargetY = tonumber(state.smoothScrollTargetY) or yScroll

    if state.selected and type(listbox.items) == "table" and #listbox.items > 0 then
        listbox.selected = math.max(-1, math.min(state.selected, #listbox.items))
    end

    syncListBoxScrollGeometry(listbox, false)
end

local function scheduleListBoxScrollRestore(panel, state)
    if not panel or not state then
        return
    end
    panel.pendingListScrollRestore = {
        state = state,
        ticks = 4,
    }
end

local function applyPendingListBoxScrollRestore(panel)
    if not panel or not panel.pendingListScrollRestore or not panel.skillList then
        return
    end
    restoreListBoxScrollState(panel.skillList, panel.pendingListScrollRestore.state)
    panel.pendingListScrollRestore.ticks = (tonumber(panel.pendingListScrollRestore.ticks) or 1) - 1
    if panel.pendingListScrollRestore.ticks <= 0 then
        panel.pendingListScrollRestore = nil
    end
end

local function buildRecipeSourceText(magazineSource, defaultText)
    if magazineSource then
        local magazineName = BurdJournals.getMagazineDisplayName(magazineSource)
        return BurdJournals.formatText(getText("UI_BurdJournals_RecipeFromMagazine") or "From: %s", magazineName)
    end
    return defaultText or getText("UI_BurdJournals_RecipeKnowledge") or "UI_BurdJournals_RecipeKnowledge"
end

local function getMagazineTexture(magazineSource)
    if not magazineSource then return nil end
    local cached = magazineTextureCache[magazineSource]
    if cached ~= nil then
        return cached ~= false and cached or nil
    end
    if not getScriptManager then
        magazineTextureCache[magazineSource] = false
        return nil
    end
    local scriptMgr = getScriptManager()
    if not scriptMgr or not scriptMgr.getItem then
        magazineTextureCache[magazineSource] = false
        return nil
    end
    local script = scriptMgr:getItem(magazineSource)
    if not script or not script.getIcon then
        magazineTextureCache[magazineSource] = false
        return nil
    end
    local iconName = script:getIcon()
    if not iconName then
        magazineTextureCache[magazineSource] = false
        return nil
    end
    local texture = getTexture("Item_" .. iconName)
    magazineTextureCache[magazineSource] = texture or false
    return texture
end

BurdJournals.getMagazineTexture = BurdJournals.getMagazineTexture or getMagazineTexture

local function showTooDarkFeedback(player)
    local message = BurdJournals.safeGetText("ContextMenu_TooDark", "Too dark to read.")

    if HaloTextHelper and HaloTextHelper.addBadText and player then
        HaloTextHelper.addBadText(player, message)
    elseif player and player.Say then
        player:Say(message)
    end
end

local function resolveHeaderIconTexture(iconName)
    if not iconName or iconName == "" then
        return nil
    end

    local lookupKeys = {
        "Item_" .. iconName,
        iconName,
        "media/textures/Item_" .. iconName .. ".png",
        "media/textures/" .. iconName .. ".png"
    }
    for _, key in ipairs(lookupKeys) do
        local texture = getTexture(key)
        if texture then
            return texture
        end
    end

    return nil
end

local function shouldDrawListRow(listbox, y, itemHeight)
    if not listbox then
        return true
    end

    local rowY = tonumber(y) or 0
    local rowH = tonumber(itemHeight) or 0
    local viewportH = listbox.getHeight and listbox:getHeight() or 0
    local margin = math.max(0, rowH)
    local yScroll = 0
    if listbox.getYScroll then
        yScroll = tonumber(listbox:getYScroll()) or 0
    elseif listbox.yScroll then
        yScroll = tonumber(listbox.yScroll) or 0
    end
    local visibleY = rowY + yScroll

    return (visibleY + rowH) >= -margin and visibleY <= (viewportH + margin)
end

local function resolveHeaderIconFromScript(fullType)
    if not fullType or fullType == "" or not getScriptManager then
        return nil
    end
    local scriptMgr = getScriptManager()
    if not scriptMgr or not scriptMgr.getItem then
        return nil
    end
    local script = scriptMgr:getItem(fullType)
    if not script or not script.getIcon then
        return nil
    end
    return resolveHeaderIconTexture(script:getIcon())
end

local function canProbeHeaderJournalItem(journal)
    if not journal then
        return false
    end
    local function safeHasMethod(methodName)
        local ok, method = pcall(function()
            return journal[methodName]
        end)
        return ok and type(method) == "function"
    end
    if BurdJournals.isValidItem then
        local ok, valid = pcall(BurdJournals.isValidItem, journal)
        if ok then
            if valid ~= true then
                return false
            end
            return safeHasMethod("getFullType") or safeHasMethod("getModData")
        end
    end
    return safeHasMethod("getFullType") or safeHasMethod("getModData")
end

local function safeGetHeaderJournalFullType(journal)
    if not canProbeHeaderJournalItem(journal) then
        return ""
    end
    local okMethod, getFullType = pcall(function()
        return journal and journal.getFullType
    end)
    if not okMethod or type(getFullType) ~= "function" then
        return ""
    end
    local ok, fullType = pcall(function()
        return getFullType(journal)
    end)
    if not ok or fullType == nil then
        return ""
    end
    return tostring(fullType)
end

local function safeProbeHeaderJournalPredicate(journal, predicate)
    if not canProbeHeaderJournalItem(journal) or type(predicate) ~= "function" then
        return false
    end
    local ok, result = pcall(predicate, journal)
    return ok and result == true or false
end

isUnwrappedYuletideRewardState = function(journal, journalData)
    if type(journalData) == "table"
        and journalData.isYuletideJournal == true
        and journalData.yuletideState == BurdJournals.YULETIDE_STATE_UNWRAPPED
    then
        return true
    end
    return journal
        and BurdJournals.isUnwrappedYuletideJournal
        and safeProbeHeaderJournalPredicate(journal, BurdJournals.isUnwrappedYuletideJournal)
        or false
end

getHeaderJournalIconTexture = function(mode, journal, journalData, isBloodyHint)
    local journalDataHasPresentationState = type(journalData) == "table"
        and (journalData.isCursedReward ~= nil
            or journalData.isCursedJournal ~= nil
            or journalData.isHiddenCursedJournal ~= nil
            or journalData.isWorn ~= nil
            or journalData.isBloody ~= nil
            or journalData.isYuletideJournal ~= nil
            or journalData.yuletideState ~= nil)
    local canProbeLiveJournal = not journalDataHasPresentationState
    local fullType = canProbeLiveJournal and safeGetHeaderJournalFullType(journal) or ""
    local isWornType = fullType ~= "" and string.find(fullType, "_Worn", 1, true) ~= nil
    local isBloodyType = fullType ~= "" and string.find(fullType, "_Bloody", 1, true) ~= nil
    local isYuletideState = isUnwrappedYuletideRewardState(canProbeLiveJournal and journal or nil, journalData)
    local isHiddenCursedState = type(journalData) == "table"
        and journalData.isHiddenCursedJournal == true
        and journalData.isCursedReward ~= true
    local isCursedState = (journalData and (journalData.isCursedReward == true or journalData.isCursedJournal == true))
        or (canProbeLiveJournal and safeProbeHeaderJournalPredicate(journal, BurdJournals.isCursedJournalItem))
    local isWornState = isWornType
        or (journalData and journalData.isWorn == true)
        or (canProbeLiveJournal and safeProbeHeaderJournalPredicate(journal, BurdJournals.isWorn))
    local isBloodyState = isBloodyHint == true
        or isBloodyType
        or isHiddenCursedState
        or (journalData and journalData.isBloody == true)
        or (canProbeLiveJournal and safeProbeHeaderJournalPredicate(journal, BurdJournals.isBloody))

    -- Registered sealed archetypes (e.g. Blessed) supply their own state-aware
    -- header icon, checked before the built-in bloody/worn/cursed fallbacks.
    local sealedIconName = BurdJournals.getSealedJournalIconName
        and BurdJournals.getSealedJournalIconName((canProbeLiveJournal and journal) or journalData)
        or nil

    local iconName = "FilledJournalClean"
    if sealedIconName then
        iconName = sealedIconName
    elseif isYuletideState then
        iconName = "YuletideJournalUnwrapped"
    elseif isCursedState then
        iconName = "CursedJournal"

    elseif isBloodyState then
        iconName = "FilledJournalBloody"
    elseif isWornState then
        iconName = "FilledJournalWorn"
    end

    local resolved = resolveHeaderIconTexture(iconName)
    if resolved then
        return resolved
    end

    resolved = resolveHeaderIconFromScript(fullType)
    if resolved then
        return resolved
    end

    return resolveHeaderIconTexture("FilledJournalClean")
end

BurdJournals.getHeaderJournalIconTexture = BurdJournals.getHeaderJournalIconTexture or getHeaderJournalIconTexture

-- Standard (non-passive) skill cumulative XP thresholds from Project Zomboid
-- These are CUMULATIVE totals to reach each level
-- Per-level increments: 50, 100, 200, 500, 1000, 2000, 3000, 4000, 5000, 6000
BurdJournals.STANDARD_XP_THRESHOLDS = BurdJournals.STANDARD_XP_THRESHOLDS or {
    [0] = 0,
    [1] = 50,
    [2] = 150,      -- 50 + 100
    [3] = 350,      -- 150 + 200
    [4] = 850,      -- 350 + 500
    [5] = 1850,     -- 850 + 1000
    [6] = 3850,     -- 1850 + 2000
    [7] = 6850,     -- 3850 + 3000
    [8] = 10850,    -- 6850 + 4000
    [9] = 15850,    -- 10850 + 5000
    [10] = 21850    -- 15850 + 6000
}

-- Exact passive skill (Fitness/Strength) cumulative XP thresholds from Project Zomboid
-- These are CUMULATIVE totals to reach each level
BurdJournals.PASSIVE_XP_THRESHOLDS = BurdJournals.PASSIVE_XP_THRESHOLDS or {
    [0] = 0,
    [1] = 1000,
    [2] = 3000,    -- 1000 + 2000
    [3] = 7000,    -- 3000 + 4000
    [4] = 13000,   -- 7000 + 6000
    [5] = 25000,   -- 13000 + 12000
    [6] = 45000,   -- 25000 + 20000
    [7] = 85000,   -- 45000 + 40000
    [8] = 145000,  -- 85000 + 60000
    [9] = 225000,  -- 145000 + 80000
    [10] = 325000  -- 225000 + 100000
}

function BurdJournals.getDisplayXPThresholdTable(skillName)
    local isPassive = skillName == "Fitness" or skillName == "Strength"
    local thresholds = isPassive and BurdJournals.PASSIVE_XP_THRESHOLDS or BurdJournals.STANDARD_XP_THRESHOLDS
    if (type(thresholds) ~= "table" or thresholds[1] == nil or thresholds[10] == nil)
        and BurdJournals.getXPThresholdForLevel
    then
        BurdJournals.getXPThresholdForLevel(skillName, 1)
        thresholds = isPassive and BurdJournals.PASSIVE_XP_THRESHOLDS or BurdJournals.STANDARD_XP_THRESHOLDS
    end
    if type(thresholds) == "table" then
        return thresholds
    end
    return isPassive and BurdJournals.PASSIVE_XP_THRESHOLDS or BurdJournals.STANDARD_XP_THRESHOLDS
end

function BurdJournals.getXPForLevel(skillName, level)
    if level <= 0 then return 0 end
    if level > 10 then level = 10 end
    local thresholds = BurdJournals.getDisplayXPThresholdTable(skillName)
    return (thresholds and thresholds[level]) or 0
end

BurdJournals.normalizeProgressPercentLabel = BurdJournals.normalizeProgressPercentLabel or function(text)
    return tostring(text or ""):gsub("%%%%", "%%")
end

-- Helper function to determine whether a player journal skill entry should have
-- its baseline added back for level/square display. Player journals recorded in
-- baseline mode store earned XP only, while loot journals and legacy absolute
-- entries must remain untouched.
function BurdJournals.shouldAddPassiveBaselineForDisplay(journalData, player)
    if type(journalData) ~= "table" or journalData.isPlayerCreated ~= true then
        return false
    end

    local useBaselineMode = BurdJournals.getJournalSkillRecordingMode
        and BurdJournals.getJournalSkillRecordingMode(journalData, player)
        or (journalData.recordedWithBaseline == true)
    if not useBaselineMode then
        return false
    end

    local playerModData = player and player.getModData and player:getModData() or nil
    if playerModData and playerModData.BurdJournals and playerModData.BurdJournals.debugModified == true then
        return false
    end

    return true
end

function BurdJournals.getXPWithBaselineForDisplay(skillName, recordedXP, journalData, player)
    local storedXP = math.max(0, tonumber(recordedXP) or 0)
    return storedXP
end

local function drawAnimatedCursedJournalBackdrop(target, x, y, width, height, theme, effectKey)
    if not target or not theme then
        return
    end
    if BurdJournals.shouldRenderAnimatedJournalVisuals
        and not BurdJournals.shouldRenderAnimatedJournalVisuals(effectKey or "journal_panel_backdrop") then
        return
    end

    local drawX = math.floor(tonumber(x) or 0)
    local drawY = math.floor(tonumber(y) or 0)
    local drawW = math.floor(tonumber(width) or 0)
    local drawH = math.floor(tonumber(height) or 0)
    if drawW <= 0 or drawH <= 0 then
        return
    end

    local nowMs = (getTimestampMs and getTimestampMs()) or 0
    local now = nowMs / 1000
    local pulse = 0.50 + (0.50 * math.sin(now * 2.0))
    local useStencil = target.setStencilRect and target.clearStencilRect

    target:drawRect(drawX, drawY, drawW, drawH, theme.panelBg.a or 0.78, theme.panelBg.r, theme.panelBg.g, theme.panelBg.b)

    if useStencil then
        target:setStencilRect(drawX, drawY, drawW, drawH)
    end

    local hazeLayers = 10
    local hazeBaseY = drawY + math.floor(drawH * 0.76)
    local hazeHeight = math.max(8, math.floor(drawH * 0.05))
    local hazeStep = math.max(5, math.floor(hazeHeight * 0.70))
    for i = 0, hazeLayers - 1 do
        local bandY = hazeBaseY + (i * hazeStep)
        if bandY < (drawY + drawH) then
            local fade = (i + 1) / hazeLayers
            local bandAlpha = (0.004 + (0.003 * pulse)) + (fade * (0.012 + (0.008 * pulse)))
            local bandColor = (i >= hazeLayers - 4) and theme.smokePrimary or theme.smokeSecondary
            local bandHeight = math.min(hazeHeight + math.floor(i * 0.6), (drawY + drawH) - bandY)
            target:drawRect(drawX, bandY, drawW, bandHeight, bandAlpha, bandColor.r, bandColor.g, bandColor.b)
        end
    end
    target:drawRect(drawX, drawY + math.floor(drawH * 0.92), drawW, math.max(10, math.floor(drawH * 0.08)), 0.022 + (0.013 * pulse), theme.smokePrimary.r, theme.smokePrimary.g, theme.smokePrimary.b)

    local emberCount = math.max(12, math.floor(drawW / 40))
    local emberLift = math.max(54, math.floor(drawH * 0.54))
    for i = 0, emberCount - 1 do
        local seed = (i * 1.61)
        local drift = math.sin((now * 1.5) + seed)
        local rise = ((now * (16 + (i % 5) * 4)) + (i * 19)) % emberLift
        local emberY = math.floor((drawY + drawH - 12) - rise)
        local emberBaseX = drawX + (((i * 43) % math.max(1, drawW - 28)) + 14)
        local emberX = math.floor(emberBaseX + (drift * (8 + (i % 4) * 5)))
        local emberSize = (i % 4 == 0) and 3 or 2
        local emberColor = (i % 2 == 0) and theme.emberPrimary or theme.emberSecondary
        local emberAlpha = math.max(0.04, math.min(0.22, (emberColor.a or 0.14) + (0.04 * pulse) - ((rise / emberLift) * 0.07)))

        if emberY >= (drawY + 8) and emberY <= (drawY + drawH - 4) then
            target:drawRect(emberX, emberY, emberSize, emberSize, emberAlpha, emberColor.r, emberColor.g, emberColor.b)
            if emberSize > 2 then
                target:drawRect(emberX - 1, emberY + 1, emberSize + 2, 1, emberAlpha * 0.30, theme.cardAccent.r, theme.cardAccent.g, theme.cardAccent.b)
            end
        end
    end

    if useStencil then
        target:clearStencilRect()
    end

    target:drawRectBorder(drawX, drawY, drawW, drawH, theme.panelBorder.a or 0.42, theme.panelBorder.r, theme.panelBorder.g, theme.panelBorder.b)
end

-- Heavenly backdrop for the Blessed archetype: a soft off-white wash, faint
-- descending god-rays, and gentle upward-drifting light motes (the same calm,
-- "lifting" sensibility as the vigil site spores). Reads palette fields
-- panelBg / emberPrimary (mote) / emberSecondary / cardAccent (ray) /
-- panelBorder. Everything is low-alpha so it glows rather than glares.
local function drawAnimatedBlessedJournalBackdrop(target, x, y, width, height, theme, effectKey)
    if not target or not theme then
        return
    end
    if BurdJournals.shouldRenderAnimatedJournalVisuals
        and not BurdJournals.shouldRenderAnimatedJournalVisuals(effectKey or "journal_panel_backdrop_blessed") then
        return
    end

    local drawX = math.floor(tonumber(x) or 0)
    local drawY = math.floor(tonumber(y) or 0)
    local drawW = math.floor(tonumber(width) or 0)
    local drawH = math.floor(tonumber(height) or 0)
    if drawW <= 0 or drawH <= 0 then
        return
    end

    -- Sensible fallbacks so the drawer is robust to a sparse palette.
    local panelBg   = theme.panelBg      or {r=0.96, g=0.95, b=0.90, a=0.70}
    local ray       = theme.cardAccent   or {r=0.92, g=0.84, b=0.58}
    local moteA     = theme.emberPrimary or {r=1.00, g=0.94, b=0.74, a=0.16}
    local moteB     = theme.emberSecondary or {r=0.96, g=0.90, b=0.70, a=0.12}
    local border    = theme.panelBorder  or {r=0.86, g=0.76, b=0.48, a=0.42}

    local nowMs = (getTimestampMs and getTimestampMs()) or 0
    local now = nowMs / 1000
    -- Slow, calm breathing (portal/vigil cadence, not a fast flicker).
    local breathe = 0.50 + (0.50 * math.sin(now * 0.9))
    local useStencil = target.setStencilRect and target.clearStencilRect

    target:drawRect(drawX, drawY, drawW, drawH, panelBg.a or 0.70, panelBg.r, panelBg.g, panelBg.b)

    if useStencil then
        target:setStencilRect(drawX, drawY, drawW, drawH)
    end

    -- Descending god-rays: a few wide, very faint slanted columns that slowly
    -- sweep. Drawn as stacked thin rects offset per row to fake a diagonal.
    local rayCount = math.max(3, math.floor(drawW / 150))
    local rayRows = math.max(10, math.floor(drawH / 14))
    local rowH = math.max(6, math.floor(drawH / rayRows))
    for r = 0, rayCount - 1 do
        local sweep = math.sin((now * 0.35) + (r * 1.7)) * (drawW * 0.06)
        local rayW = math.max(18, math.floor(drawW / (rayCount * 2)))
        local baseX = drawX + math.floor(((r + 0.5) / rayCount) * drawW) + math.floor(sweep)
        for row = 0, rayRows - 1 do
            local ry = drawY + (row * rowH)
            -- Rays fade toward the bottom and shear rightward as they descend.
            local shear = math.floor((row / rayRows) * (rowH * rayRows) * 0.18)
            local rowFade = 1.0 - (row / rayRows)
            local a = (0.010 + (0.014 * breathe)) * rowFade
            target:drawRect(baseX + shear, ry, rayW, rowH, a, ray.r, ray.g, ray.b)
        end
    end

    -- Rising light motes: slow, sine-swaying, fading in and out as they lift.
    local moteCount = math.max(10, math.floor(drawW / 44))
    local lift = math.max(60, math.floor(drawH * 0.70))
    for i = 0, moteCount - 1 do
        local seed = (i * 1.61)
        local sway = math.sin((now * 0.8) + seed)
        -- Motes rise (subtract), unlike the cursed embers' faster churn.
        local rise = ((now * (10 + (i % 4) * 3)) + (i * 23)) % lift
        local moteY = math.floor((drawY + drawH - 10) - rise)
        local moteBaseX = drawX + (((i * 47) % math.max(1, drawW - 24)) + 12)
        local moteX = math.floor(moteBaseX + (sway * (6 + (i % 3) * 4)))
        local moteSize = (i % 5 == 0) and 3 or 2
        local col = (i % 2 == 0) and moteA or moteB
        -- Fade in at birth (bottom), out near the top of the lift.
        local k = rise / lift
        local fade = math.min(1.0, k / 0.2) * (1.0 - math.max(0.0, (k - 0.6) / 0.4))
        local a = math.max(0.0, ((col.a or 0.14) + (0.05 * breathe)) * fade)
        if moteY >= (drawY + 6) and moteY <= (drawY + drawH - 4) then
            target:drawRect(moteX, moteY, moteSize, moteSize, a, col.r, col.g, col.b)
            if moteSize > 2 then
                target:drawRect(moteX - 1, moteY - 1, moteSize + 2, moteSize + 2, a * 0.35, col.r, col.g, col.b)
            end
        end
    end

    if useStencil then
        target:clearStencilRect()
    end

    -- Soft double border for a gentle gold glow around the panel edge.
    target:drawRectBorder(drawX, drawY, drawW, drawH, (border.a or 0.42) * (0.7 + 0.3 * breathe), border.r, border.g, border.b)
    target:drawRectBorder(drawX + 1, drawY + 1, drawW - 2, drawH - 2, (border.a or 0.42) * 0.35, border.r, border.g, border.b)
end

function BurdJournals.isSkillVisibleForJournal(journalData, skillName)
    if not skillName then return false end
    if not BurdJournals.isSkillEnabledForJournal then return true end
    return BurdJournals.isSkillEnabledForJournal(journalData, skillName)
end

function BurdJournals.isSkillRecordableInPlayerJournal(skillName)
    if not skillName then return false end
    if not BurdJournals.isSkillEnabledForJournal then return true end
    return BurdJournals.isSkillEnabledForJournal({isPlayerCreated = true}, skillName)
end

function BurdJournals.hasEntries(map)
    return BurdJournals.hasAnyEntries and BurdJournals.hasAnyEntries(map) or false
end

function BurdJournals.hasTraitEntriesForJournal(journalData)
    return type(journalData) == "table" and BurdJournals.hasEntries(journalData.traits)
end

function BurdJournals.hasRecipeEntriesForJournal(journalData)
    return type(journalData) == "table" and BurdJournals.hasEntries(journalData.recipes)
end

function BurdJournals.createClaimSessionId()
    local now = getTimestampMs and getTimestampMs() or 0
    local rand = ZombRand and ZombRand(1000000) or math.floor(math.random() * 1000000)
    return tostring(now) .. "-" .. tostring(rand)
end

function BurdJournals.getClaimSessionIdForPanel(panel, createIfMissing)
    if not panel then
        return nil
    end
    if panel.learningState and panel.learningState.active then
        if createIfMissing and not panel.learningState.claimSessionId then
            panel.learningState.claimSessionId = BurdJournals.createClaimSessionId()
        end
        return panel.learningState.claimSessionId
    end
    if createIfMissing then
        return BurdJournals.createClaimSessionId()
    end
    return nil
end

-- Returns preview data for the NEXT claim read (or an offset read) so UI mirrors server-side diminishing returns.
function BurdJournals.getClaimPreviewForSkill(journalData, player, skillName, recordedXP, readOffset, claimSessionId)
    local sourceXP = math.max(0, tonumber(recordedXP) or 0)
    if type(journalData) == "table" and type(journalData.skills) == "table" then
        local storedSkillKey = BurdJournals.resolveSkillKey and BurdJournals.resolveSkillKey(journalData.skills, skillName) or skillName
        local skillData = journalData.skills[storedSkillKey]
        if type(skillData) == "table" and BurdJournals.normalizeLegacySkillEntry then
            local normalizedXP = select(1, BurdJournals.normalizeLegacySkillEntry(skillName, skillData, journalData.recordedWithBaseline))
            sourceXP = math.max(0, normalizedXP or sourceXP)
        end
    end
    local claimMultiplier, readCount = 1.0, tonumber(journalData and journalData.readCount) or 0

    if BurdJournals.getJournalClaimMultiplier then
        claimMultiplier, readCount = BurdJournals.getJournalClaimMultiplier(journalData, readOffset or 0, skillName, claimSessionId)
    end

    local effectiveXP = math.max(0, math.floor(sourceXP * claimMultiplier))
    local claimPercent = math.floor((claimMultiplier * 100) + 0.5)

    local effectiveLevel = 0
    if effectiveXP > 0 and BurdJournals.getSkillLevelFromXP then
        local xpForLevelCalc = BurdJournals.getXPWithBaselineForDisplay(skillName, effectiveXP, journalData, player)
        effectiveLevel = BurdJournals.getSkillLevelFromXP(xpForLevelCalc, skillName) or 0
    end

    return {
        sourceXP = sourceXP,
        effectiveXP = effectiveXP,
        multiplier = claimMultiplier,
        percent = claimPercent,
        readCount = readCount,
        level = effectiveLevel,
    }
end

function BurdJournals.getNormalizedSkillClaimEntry(journalData, skillName, fallbackXP)
    local normalizedXP = math.max(0, tonumber(fallbackXP) or 0)
    local normalizedLevel = 0
    if type(journalData) ~= "table" or type(journalData.skills) ~= "table" then
        return normalizedXP, normalizedLevel
    end

    local storedSkillKey = BurdJournals.resolveSkillKey and BurdJournals.resolveSkillKey(journalData.skills, skillName) or skillName
    local skillData = journalData.skills[storedSkillKey]
    if type(skillData) ~= "table" then
        return normalizedXP, normalizedLevel
    end

    normalizedLevel = math.max(0, tonumber(skillData.level) or 0)
    if BurdJournals.normalizeLegacySkillEntry then
        normalizedXP, normalizedLevel = BurdJournals.normalizeLegacySkillEntry(skillName, skillData, journalData.recordedWithBaseline)
    else
        normalizedXP = math.max(0, tonumber(skillData.xp) or normalizedXP)
    end

    return normalizedXP, normalizedLevel
end

function BurdJournals.resolveJournalRecordingModeForPlayer(journalData, player)
    local useBaseline = BurdJournals.getJournalSkillRecordingMode
        and BurdJournals.getJournalSkillRecordingMode(journalData, player)
        or BurdJournals.shouldEnforceBaseline(player)
    local autoRepaired = false

    if useBaseline
        and type(journalData) == "table"
        and journalData.recordedWithBaseline == true
        and type(journalData.skills) == "table"
        and player
        and player.getXp
    then
        local sampledSkills = 0
        local suspiciousAbsoluteSkills = 0
        for skillName, storedData in pairs(journalData.skills) do
            local storedXP = tonumber(type(storedData) == "table" and storedData.xp or storedData)
            if storedXP and storedXP > 0 then
                local perk = BurdJournals.getPerkByName and BurdJournals.getPerkByName(skillName)
                if perk then
                    sampledSkills = sampledSkills + 1
                    local actualXP = BurdJournals.getPlayerSkillTotalXP and BurdJournals.getPlayerSkillTotalXP(player, perk, skillName) or player:getXp():getXP(perk)
                    local baselineXP = math.max(0, tonumber(BurdJournals.getSkillBaseline and BurdJournals.getSkillBaseline(player, skillName) or 0) or 0)
                    local earnedXP = math.max(0, actualXP - baselineXP)
                    local storedLevel = tonumber(type(storedData) == "table" and storedData.level) or 0
                    if BurdJournals.isLikelyLegacyAbsoluteSkillEntry
                        and BurdJournals.isLikelyLegacyAbsoluteSkillEntry(journalData, player, skillName, storedXP, storedLevel, actualXP, baselineXP)
                    then
                        suspiciousAbsoluteSkills = suspiciousAbsoluteSkills + 1
                    end
                end
            end
        end

        if sampledSkills > 0 and suspiciousAbsoluteSkills >= math.max(1, math.floor(sampledSkills * 0.5)) then
            useBaseline = false
            autoRepaired = true
        end
    end

    return useBaseline, autoRepaired
end

function BurdJournals.shouldForceBaselineRecordingMode(journalData, player, legacyAbsoluteDetected)
    if not legacyAbsoluteDetected then
        return false
    end
    if type(journalData) ~= "table" or journalData.isPlayerCreated ~= true then
        return false
    end
    if journalData.recordedWithBaseline ~= true then
        return false
    end
    if BurdJournals.shouldEnforceBaseline then
        return BurdJournals.shouldEnforceBaseline(player) == true
    end
    return false
end

function BurdJournals.isLikelyAbsoluteSkillEntryForBaseline(journalData, player, skillName, storedXP, currentXP, baselineXP)
    local stored = tonumber(storedXP) or 0
    if stored <= 0 then
        return false
    end
    if type(journalData) ~= "table" or journalData.isPlayerCreated ~= true then
        return false
    end
    if journalData.recordedWithBaseline ~= true then
        return false
    end
    return BurdJournals.isLikelyLegacyAbsoluteSkillEntry
        and BurdJournals.isLikelyLegacyAbsoluteSkillEntry(journalData, player, skillName, stored, nil, currentXP, baselineXP)
        or false
end

function BurdJournals.isLikelyNewCharacterForBaseline(player)
    if not player then
        return false
    end
    -- Character age is not lifecycle evidence: a young survivor can reconnect
    -- before the first in-game hour. Only the explicit OnNewGame/OnCreatePlayer
    -- capture state is allowed to establish a new baseline.
    if BurdJournals.Client and BurdJournals.Client._pendingNewCharacterBaseline then
        return true
    end

    return false
end

function BurdJournals.queueNewCharacterBaselineCapture(panel)
    if not panel or not panel.player then
        return
    end
    if not (BurdJournals.Client and BurdJournals.Client.queueNewCharacterBaselineCapture) then return false end
    local playerIndex = panel.player.getPlayerNum and panel.player:getPlayerNum() or nil
    return BurdJournals.Client.queueNewCharacterBaselineCapture(panel.player, playerIndex, "recordingPanel")
end

function BurdJournals.ensureBaselineReadyForRecording(panel, useBaseline, contextTag)
    if not useBaseline then
        return true, false
    end
    if not panel or not panel.player then
        return false, true
    end
    if BurdJournals.hasBaselineCaptured(panel.player) then
        return true, true
    end

    if BurdJournals.isLikelyNewCharacterForBaseline(panel.player) then
        BurdJournals.queueNewCharacterBaselineCapture(panel)
        if BurdJournals.Client
            and BurdJournals.Client.requestServerBaseline
            and not BurdJournals.Client.isAwaitingServerBaseline(panel.player) then
            BurdJournals.Client.requestServerBaseline(panel.player)
        end
        return false, true
    end

    BurdJournals.debugPrint("[BurdJournals] " .. tostring(contextTag)
        .. ": baseline missing for existing character; continuing without baseline enforcement until baseline is set manually")
    if BurdJournals.Client
        and BurdJournals.Client.requestServerBaseline
        and not BurdJournals.Client.isAwaitingServerBaseline(panel.player) then
        BurdJournals.Client.requestServerBaseline(panel.player)
    end
    return true, false
end

function BurdJournals.getClaimTargetXPForPlayer(journalData, player, skillName, effectiveXP)
    local targetXP = math.max(0, tonumber(effectiveXP) or 0)
    local baselineXP = 0
    local baselineSuppressed = false
    local claimUsesEarnedDeltaGrant = false
    local useBaselineForJournal = BurdJournals.resolveJournalRecordingModeForPlayer(journalData, player)

    local playerModData = player and player.getModData and player:getModData() or nil
    if playerModData and playerModData.BurdJournals and playerModData.BurdJournals.debugModified == true then
        baselineSuppressed = true
    end

    if journalData
        and journalData.isPlayerCreated
        and useBaselineForJournal
        and BurdJournals.getSkillBaseline
    then
        if not baselineSuppressed then
            baselineXP = math.max(0, tonumber(BurdJournals.getSkillBaseline(player, skillName)) or 0)
        end
        local recordedLevel = 0
        if type(journalData.skills) == "table" then
            local storedSkillKey = BurdJournals.resolveSkillKey and BurdJournals.resolveSkillKey(journalData.skills, skillName) or skillName
            if type(journalData.skills[storedSkillKey]) == "table" then
                recordedLevel = tonumber(journalData.skills[storedSkillKey].level) or 0
            end
        end
        local legacyAbsolute = BurdJournals.isLikelyLegacyAbsoluteSkillEntry
            and BurdJournals.isLikelyLegacyAbsoluteSkillEntry(journalData, player, skillName, effectiveXP, recordedLevel, nil, baselineXP)
            or false
        if not legacyAbsolute then
            local perk = BurdJournals.getPerkByName and BurdJournals.getPerkByName(skillName)
            local currentXP = 0
            if perk and player and player.getXp then
                currentXP = math.max(
                    0,
                    tonumber(BurdJournals.getPlayerSkillTotalXP and BurdJournals.getPlayerSkillTotalXP(player, perk, skillName) or player:getXp():getXP(perk)) or 0
                )
            end
            local currentLevel = 0
            if perk and player and player.getPerkLevel then
                currentLevel = math.max(0, tonumber(player:getPerkLevel(perk)) or 0)
            end
            local isPassiveSkill = (BurdJournals.isPassiveSkill and BurdJournals.isPassiveSkill(skillName))
                or (skillName == "Fitness" or skillName == "Strength")
            if recordedLevel > 0 and (currentLevel > recordedLevel or (isPassiveSkill and currentLevel >= recordedLevel)) then
                targetXP = currentXP
            else
                local currentEarnedXP = math.max(0, currentXP - baselineXP)
                local missingEarnedXP = math.max(0, targetXP - currentEarnedXP)
                targetXP = currentXP + missingEarnedXP
            end
            if BurdJournals.getActivePlayerJournalSkillClaimLock
                and BurdJournals.getActivePlayerJournalSkillClaimLock(journalData, player, skillName, effectiveXP, targetXP, currentXP, currentLevel) then
                targetXP = currentXP
            end
            claimUsesEarnedDeltaGrant = true
        end
    end

    return targetXP, baselineXP, baselineSuppressed, claimUsesEarnedDeltaGrant
end

function BurdJournals.getSkillVhsBreakdown(skillData, fallbackNetXP)
    local netXP = math.max(0, tonumber((skillData and skillData.xp) or fallbackNetXP) or 0)
    local rawXP = tonumber(skillData and skillData.rawXP)
    if rawXP == nil then
        rawXP = netXP
    else
        rawXP = math.max(netXP, rawXP)
    end
    local excludedXP = tonumber(skillData and skillData.vhsExcludedXP)
    if excludedXP == nil then
        excludedXP = math.max(0, rawXP - netXP)
    else
        excludedXP = math.max(0, excludedXP)
    end
    if excludedXP > rawXP then
        excludedXP = rawXP
    end
    if rawXP < (netXP + excludedXP) then
        rawXP = netXP + excludedXP
    end
    return netXP, rawXP, excludedXP
end

function BurdJournals.formatXPWithVhsBreakdown(netXP, rawXP, excludedXP)
    local fmtNet = BurdJournals.formatXP(math.max(0, tonumber(netXP) or 0))
    local fmtRaw = BurdJournals.formatXP(math.max(0, tonumber(rawXP) or 0))
    local fmtExcluded = BurdJournals.formatXP(math.max(0, tonumber(excludedXP) or 0))
    if (tonumber(excludedXP) or 0) > 0 and (tonumber(rawXP) or 0) > (tonumber(netXP) or 0) then
        return fmtNet .. "/" .. fmtRaw .. " XP (VHS -" .. fmtExcluded .. ")"
    end
    return fmtNet .. " XP"
end

function BurdJournals.buildSkillVhsTooltip(skillData, claimableXP, claimPercent, startingXP)
    local netXP, rawXP, excludedXP = BurdJournals.getSkillVhsBreakdown(skillData)
    local hasVhsDelta = excludedXP > 0 and rawXP > netXP
    local hasClaimDelta = claimableXP ~= nil and netXP > 0 and math.max(0, tonumber(claimableXP) or 0) < netXP
    local startingXPValue = math.max(0, tonumber(startingXP) or 0)
    local hasStartingXP = startingXPValue > 0
    if not hasVhsDelta and not hasClaimDelta and not hasStartingXP then
        return nil
    end

    local lines = {}
    if hasStartingXP then
        table.insert(lines, BurdJournals.formatText(getText("UI_BurdJournals_StartingXP") or "Starting: %s XP", BurdJournals.formatXP(startingXPValue)))
    end
    table.insert(lines, "Recorded net XP: " .. BurdJournals.formatXP(netXP))
    if hasVhsDelta then
        table.insert(lines, "Recorded raw XP: " .. BurdJournals.formatXP(rawXP))
        table.insert(lines, "VHS excluded at record: -" .. BurdJournals.formatXP(excludedXP))
    end
    if hasClaimDelta then
        local claimable = math.max(0, tonumber(claimableXP) or 0)
        local line = "Current claimable: " .. BurdJournals.formatXP(claimable)
        if claimPercent and claimPercent < 100 then
            line = line .. " (" .. tostring(claimPercent) .. "%)"
        end
        table.insert(lines, line)
    end
    return table.concat(lines, "\n")
end

local function getSkillDetailText(key, fallback)
    local text = getText and getText(key) or nil
    if not text or text == "" or text == key then
        return fallback
    end
    return text
end

local function formatCompactMediaGuid(guid)
    local text = tostring(guid or "")
    if text == "" then
        return ""
    end
    if string.len(text) <= 18 then
        return text
    end
    return string.sub(text, 1, 8) .. "..." .. string.sub(text, -6)
end

local function getSkillMediaLineLabel(guid, lineData)
    local label = nil
    if type(lineData) == "table" then
        label = lineData.displayName or lineData.name or lineData.title or lineData.category
    end
    local compactGuid = formatCompactMediaGuid(guid or (type(lineData) == "table" and lineData.lineGuid) or "")
    if label and label ~= "" and compactGuid ~= "" then
        return tostring(label) .. " (" .. compactGuid .. ")"
    end
    return compactGuid
end

local function appendSkillMediaDetail(lines, skillName, skillData)
    local lineMap = type(skillData) == "table" and (skillData.vhsMediaLines or skillData.mediaLines) or nil
    if type(lineMap) ~= "table" then
        return
    end

    local labels = {}
    for guid, lineData in pairs(lineMap) do
        local include = true
        if type(lineData) == "table" and type(lineData.skills) == "table" and type(skillName) == "string" then
            include = (tonumber(lineData.skills[skillName]) or 0) > 0
        end
        if include then
            local label = getSkillMediaLineLabel(guid, lineData)
            if label and label ~= "" then
                labels[#labels + 1] = label
            end
        end
    end
    table.sort(labels)
    if #labels <= 0 then
        return
    end

    local shown = {}
    local maxShown = 2
    for i = 1, math.min(#labels, maxShown) do
        shown[#shown + 1] = labels[i]
    end
    local suffix = ""
    if #labels > maxShown then
        suffix = BurdJournals.formatText(getSkillDetailText("UI_BurdJournals_SkillDetailMore", " +%1 more"), #labels - maxShown)
    end
    lines[#lines + 1] = BurdJournals.formatText(
        getSkillDetailText("UI_BurdJournals_SkillDetailMedia", "Media: %1"),
        table.concat(shown, ", ") .. suffix
    )
end

function BurdJournals.buildSkillDetailLines(skillName, data, journalData, player, mode)
    if type(data) ~= "table" or not data.isSkill then
        return {}
    end

    local lines = {}
    local netXP = math.max(0, tonumber(data.effectiveXP or data.earnedXP or data.xp or data.recordedXP) or 0)
    local rawXP = math.max(netXP, tonumber(data.rawXP or data.recordedRawXP) or netXP)
    local vhsExcludedXP = math.max(0, tonumber(data.vhsExcludedXP or data.recordedVhsExcludedXP) or 0)
    if rawXP < (netXP + vhsExcludedXP) then
        rawXP = netXP + vhsExcludedXP
    end

    local primaryKey = mode == "record" and "UI_BurdJournals_SkillDetailCurrent" or "UI_BurdJournals_SkillDetailRecorded"
    local primaryFallback = mode == "record" and "Current: %1 XP" or "Recorded: %1 XP"
    lines[#lines + 1] = BurdJournals.formatText(getSkillDetailText(primaryKey, primaryFallback), BurdJournals.formatXP(netXP))

    if vhsExcludedXP > 0 and rawXP > netXP then
        lines[#lines + 1] = BurdJournals.formatText(
            getSkillDetailText("UI_BurdJournals_SkillDetailRawVhs", "Raw: %1 XP | VHS excluded: %2 XP"),
            BurdJournals.formatXP(rawXP),
            BurdJournals.formatXP(vhsExcludedXP)
        )
    end

    appendSkillMediaDetail(lines, skillName, data)

    local baselineXP = math.max(0, tonumber(data.baselineXP) or 0)
    if baselineXP > 0 then
        lines[#lines + 1] = BurdJournals.formatText(getSkillDetailText("UI_BurdJournals_StartingXP", "Starting: %1 XP"), BurdJournals.formatXP(baselineXP))
    end

    local readCount = math.max(0, tonumber(data.claimReadCount) or 0)
    if readCount <= 0 and type(journalData) == "table" and type(journalData.skillReadCounts) == "table" then
        local readKey = BurdJournals.resolveSkillKey and BurdJournals.resolveSkillKey(journalData.skillReadCounts, skillName) or skillName
        readCount = math.max(0, tonumber(journalData.skillReadCounts[readKey or skillName]) or 0)
    end
    local claimPercent = tonumber(data.claimPercent)
    if readCount > 0 or (claimPercent and claimPercent < 100) then
        lines[#lines + 1] = BurdJournals.formatText(
            getSkillDetailText("UI_BurdJournals_SkillDetailDiminishing", "Diminishing: read %1 time(s), current recovery %2%"),
            readCount,
            claimPercent or 100
        )
    end

    while #lines > 4 do
        table.remove(lines)
    end
    return lines
end

function BurdJournals.getSkillDetailRowHeight(lineCount)
    local metrics = getUILayoutMetrics()
    local baseHeight = metrics.rowHeight or 52
    local count = math.max(0, math.min(4, tonumber(lineCount) or 0))
    if count <= 0 then
        return baseHeight
    end
    local lineHeight = math.max(12, (metrics.smallHeight or 14) - 1)
    return baseHeight + 8 + (count * lineHeight)
end

function BurdJournals.calculateLevelProgress(skillName, totalXP)
    local resolvedTotalXP = math.max(0, tonumber(totalXP) or 0)
    local thresholds = BurdJournals.getDisplayXPThresholdTable(skillName)
    local currentLevel = 0
    local xpForCurrentLevel = 0
    local xpForNextLevel = math.max(0, tonumber(thresholds and thresholds[1]) or 0)

    for level = 1, 10 do
        local xpNeeded = math.max(0, tonumber(thresholds and thresholds[level]) or 0)
        if resolvedTotalXP >= xpNeeded then
            currentLevel = level
            xpForCurrentLevel = xpNeeded
            local nextLevel = math.min(10, level + 1)
            xpForNextLevel = math.max(xpNeeded, tonumber(thresholds and thresholds[nextLevel]) or xpNeeded)
        else
            break
        end
    end

    local progressToNext = 0
    if currentLevel < 10 then
        local xpInThisLevel = resolvedTotalXP - xpForCurrentLevel
        local xpRangeForLevel = xpForNextLevel - xpForCurrentLevel
        if xpRangeForLevel > 0 then
            progressToNext = math.min(1, math.max(0, xpInThisLevel / xpRangeForLevel))
        end
    else
        progressToNext = 1
    end

    return currentLevel, progressToNext, resolvedTotalXP - xpForCurrentLevel, xpForNextLevel - xpForCurrentLevel
end

-- Helper to calculate level with override support (for when stored level is more accurate)
function BurdJournals.calculateLevelProgressWithOverride(skillName, totalXP, storedLevel)
    local level, progress, xpInLevel, xpRange = BurdJournals.calculateLevelProgress(skillName, totalXP)
    local isPassive = (BurdJournals.isPassiveSkill and BurdJournals.isPassiveSkill(skillName))
        or (skillName == "Fitness" or skillName == "Strength")

    if isPassive and storedLevel and storedLevel >= 0 then
        local clampedStored = math.max(0, math.min(10, tonumber(storedLevel) or 0))
        local thresholds = BurdJournals.getDisplayXPThresholdTable(skillName)
        local xpCurrentStart = math.max(0, tonumber(thresholds and thresholds[clampedStored]) or 0)
        local nextLevel = math.min(10, clampedStored + 1)
        local xpNextStart = math.max(xpCurrentStart, tonumber(thresholds and thresholds[nextLevel]) or xpCurrentStart)
        local passiveProgress = 0
        if clampedStored >= 10 then
            passiveProgress = 1
        else
            local span = xpNextStart - xpCurrentStart
            if span > 0 then
                passiveProgress = math.min(1, math.max(0, ((tonumber(totalXP) or 0) - xpCurrentStart) / span))
            end
        end
        return clampedStored, passiveProgress, math.max(0, (tonumber(totalXP) or 0) - xpCurrentStart), math.max(0, xpNextStart - xpCurrentStart)
    end

    -- If stored level is provided and higher than calculated (can happen with passive skills),
    -- use stored level but don't show phantom progress (set to 0, not 1.0)
    if storedLevel and storedLevel > 0 and storedLevel > level then
        return storedLevel, 0, 0, 0
    end
    return level, progress, xpInLevel, xpRange
end

function BurdJournals.drawLevelSquares(self, x, y, level, progress, squareSize, spacing, filledColor, emptyColor, progressColor)
    squareSize = squareSize or 12
    spacing = spacing or 2
    filledColor = filledColor or {r=0.85, g=0.75, b=0.2}
    emptyColor = emptyColor or {r=0.15, g=0.15, b=0.15}
    progressColor = progressColor or {r=0.5, g=0.45, b=0.15}

    for i = 1, 10 do
        local sqX = x + (i - 1) * (squareSize + spacing)

        if i <= level then

            self:drawRect(sqX, y, squareSize, squareSize, 0.9, filledColor.r, filledColor.g, filledColor.b)
        elseif i == level + 1 and progress > 0 then

            self:drawRect(sqX, y, squareSize, squareSize, 0.6, emptyColor.r, emptyColor.g, emptyColor.b)

            local fillHeight = squareSize * progress
            self:drawRect(sqX, y + squareSize - fillHeight, squareSize, fillHeight, 0.8, progressColor.r, progressColor.g, progressColor.b)
        else

            self:drawRect(sqX, y, squareSize, squareSize, 0.5, emptyColor.r, emptyColor.g, emptyColor.b)
        end

        self:drawRectBorder(sqX, y, squareSize, squareSize, 0.3, 0.3, 0.3, 0.3)
    end

    return 10 * squareSize + 9 * spacing
end

local function getBaselineSquareColor(filledColor, emptyColor)
    local filled = filledColor or {r=0.3, g=0.65, b=0.55}
    local empty = emptyColor or {r=0.1, g=0.1, b=0.1}
    return {
        r = math.min(1, (filled.r * 0.55) + (empty.r * 0.45)),
        g = math.min(1, (filled.g * 0.55) + (empty.g * 0.45)),
        b = math.min(1, (filled.b * 0.55) + (empty.b * 0.45)),
    }
end

-- Draw level squares with baseline distinction
-- Shows baseline levels as dimmed, earned levels as bright, giving accurate visual representation
-- Parameters:
--   baselineLevel, baselineProgress: Level/progress from baseline XP (restricted, shown dimmed)
--   totalLevel, totalProgress: Level/progress from total XP (baseline + earned)
--   baselineColor: Color for baseline portion (dimmed)
--   earnedColor: Color for earned portion (bright)
--   emptyColor: Color for empty squares
--   progressColor: Color for partial progress square
function BurdJournals.drawLevelSquaresWithBaseline(self, x, y, baselineLevel, baselineProgress, totalLevel, totalProgress, squareSize, spacing, baselineColor, earnedColor, emptyColor, progressColor)
    squareSize = squareSize or 12
    spacing = spacing or 2
    baselineColor = baselineColor or {r=0.35, g=0.28, b=0.22}
    earnedColor = earnedColor or {r=0.3, g=0.65, b=0.55}
    emptyColor = emptyColor or {r=0.1, g=0.1, b=0.1}
    progressColor = progressColor or {r=0.2, g=0.4, b=0.35}

    for i = 1, 10 do
        local sqX = x + (i - 1) * (squareSize + spacing)

        if i <= baselineLevel then
            -- Fully filled baseline level (dimmed/greyed)
            self:drawRect(sqX, y, squareSize, squareSize, 0.7, baselineColor.r, baselineColor.g, baselineColor.b)
        elseif i == baselineLevel + 1 and i <= totalLevel then
            -- This square transitions from baseline progress to earned
            -- First draw the baseline portion (bottom part, dimmed)
            if baselineProgress > 0 then
                local baselineFillHeight = squareSize * baselineProgress
                self:drawRect(sqX, y + squareSize - baselineFillHeight, squareSize, baselineFillHeight, 0.6, baselineColor.r, baselineColor.g, baselineColor.b)
            end
            -- Then draw the earned portion on top (remaining to fill the square)
            local earnedPortion = 1.0 - baselineProgress
            if earnedPortion > 0 then
                local earnedFillHeight = squareSize * earnedPortion
                self:drawRect(sqX, y, squareSize, earnedFillHeight, 0.9, earnedColor.r, earnedColor.g, earnedColor.b)
            end
        elseif i == baselineLevel + 1 and baselineProgress > 0 and i > totalLevel then
            -- Baseline has partial progress in this square but no earned XP beyond it
            self:drawRect(sqX, y, squareSize, squareSize, 0.5, emptyColor.r, emptyColor.g, emptyColor.b)
            local fillHeight = squareSize * baselineProgress
            self:drawRect(sqX, y + squareSize - fillHeight, squareSize, fillHeight, 0.6, baselineColor.r, baselineColor.g, baselineColor.b)
        elseif i <= totalLevel then
            -- Fully earned level (bright) - beyond baseline
            self:drawRect(sqX, y, squareSize, squareSize, 0.9, earnedColor.r, earnedColor.g, earnedColor.b)
        elseif i == totalLevel + 1 and totalProgress > 0 then
            -- Partial progress on current earned level
            self:drawRect(sqX, y, squareSize, squareSize, 0.5, emptyColor.r, emptyColor.g, emptyColor.b)
            local fillHeight = squareSize * totalProgress
            self:drawRect(sqX, y + squareSize - fillHeight, squareSize, fillHeight, 0.8, progressColor.r, progressColor.g, progressColor.b)
        else
            -- Empty square
            self:drawRect(sqX, y, squareSize, squareSize, 0.5, emptyColor.r, emptyColor.g, emptyColor.b)
        end

        self:drawRectBorder(sqX, y, squareSize, squareSize, 0.3, 0.3, 0.3, 0.3)
    end

    return 10 * squareSize + 9 * spacing
end

function BurdJournals.drawPlayerJournalViewSkillSquares(self, x, y, skillName, displayXP, visualXP, storedLevel, journalData, player, squareSize, spacing, colors)
    local isPassive = (BurdJournals.isPassiveSkill and BurdJournals.isPassiveSkill(skillName))
        or (skillName == "Fitness" or skillName == "Strength")
    local absoluteStoredLevel = math.max(0, tonumber(storedLevel) or 0)
    if isPassive and absoluteStoredLevel > 0 then
        local earnedXP = math.max(0, tonumber(visualXP) or 0)
        local levelBaseXP = BurdJournals.getXPThresholdForLevel and BurdJournals.getXPThresholdForLevel(skillName, absoluteStoredLevel) or 0
        local totalXP = math.max(0, tonumber(levelBaseXP) or 0) + earnedXP
        local level, progress = BurdJournals.calculateLevelProgressWithOverride(skillName, totalXP, absoluteStoredLevel)
        BurdJournals.drawLevelSquares(
            self,
            x,
            y,
            level,
            progress,
            squareSize,
            spacing,
            colors.filledColor or colors.earnedColor,
            colors.emptyColor,
            colors.progressColor
        )
        return 0
    end

    local xpForDisplay = BurdJournals.getXPWithBaselineForDisplay(skillName, visualXP, journalData, player)
    BurdJournals.drawEarnedOnlySkillSquares(
        self,
        x,
        y,
        skillName,
        xpForDisplay,
        squareSize,
        spacing,
        {
            filledColor = colors.filledColor or colors.earnedColor,
            emptyColor = colors.emptyColor,
            progressColor = colors.progressColor,
        }
    )
    return 0
end

function BurdJournals.drawEarnedOnlySkillSquares(self, x, y, skillName, visualXP, squareSize, spacing, colors)
    local level, progress = BurdJournals.calculateLevelProgress(skillName, math.max(0, tonumber(visualXP) or 0))
    BurdJournals.drawLevelSquares(
        self,
        x,
        y,
        level,
        progress,
        squareSize,
        spacing,
        colors.filledColor,
        colors.emptyColor,
        colors.progressColor
    )
end

function BurdJournals.getEarnedOnlyDisplayLevel(skillName, visualXP, fallbackLevel)
    local xp = math.max(0, tonumber(visualXP) or 0)
    if BurdJournals.getSkillLevelFromXP then
        local level = tonumber(BurdJournals.getSkillLevelFromXP(xp, skillName))
        if level ~= nil then
            return math.max(0, level)
        end
    end
    return math.max(0, tonumber(fallbackLevel) or 0)
end

-- Helper function to check if an item is in the current batch being recorded
local function isInCurrentBatch(recordingState, itemType, itemName)
    if not recordingState or not recordingState.active or not recordingState.isRecordAll then
        return false
    end
    if not recordingState.pendingRecords then
        return false
    end
    for _, record in ipairs(recordingState.pendingRecords) do
        if record.type == itemType and record.name == itemName then
            return true
        end
    end
    return false
end

-- Helper function to check if an item is in the current batch being absorbed/claimed
local function isInCurrentAbsorbBatch(learningState, itemType, itemName)
    if not learningState or not learningState.active or not learningState.isAbsorbAll then
        return false
    end
    if not learningState.pendingRewards then
        return false
    end
    for _, reward in ipairs(learningState.pendingRewards) do
        if reward.type == itemType and reward.name == itemName then
            return true
        end
    end
    return false
end

BurdJournals.isInCurrentAbsorbBatch = BurdJournals.isInCurrentAbsorbBatch or isInCurrentAbsorbBatch

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

local function isEligibleJournalReturnContainer(player, container)
    if not player or not container then return false end
    if container.getType and container:getType() == "floor" then
        return false
    end
    if container.isInCharacterInventory and container:isInCharacterInventory(player) then
        return false
    end
    return true
end

BurdJournals.UI.MainPanel = ISPanelJoypad:derive("BurdJournals.UI.MainPanel")
BurdJournals.UI.MainPanel.instance = nil
require "UI/BurdJournals_MainPanel_ViewRows"

function BurdJournals.UI.MainPanel:new(x, y, width, height, player, journal, mode)
    local o = ISPanelJoypad:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.player = player
    o.playerNum = player and player:getPlayerNum() or 0
    o.journal = journal
    o.mode = mode or "view"
    o.backgroundColor = {r=0.1, g=0.1, b=0.1, a=0.95}
    o.borderColor = {r=0.3, g=0.3, b=0.3, a=1}
    o.moveWithMouse = true

    o.learningState = {
        active = false,
        skillName = nil,
        traitId = nil,
        forgetTraitId = nil,
        recipeName = nil,
        statId = nil,
        isAbsorbAll = false,
        progress = 0,
        totalTime = 0,
        startTime = 0,
        pendingRewards = {},
        currentIndex = 0,
        queue = {},
    }
    o.learningCompleted = false
    o.processingQueue = false
    o.confirmDialog = nil
    o.borrowReturnContainer = nil
    o.prevJoypadFocus = nil
    o.controllerHintShown = false
    o.listFocusActive = false
    o.listEnterGuardUntilMs = 0
    o.listEntryConsumeA = false
    o.lastListSelectedIndex = nil
    o.lastListContextKey = nil
    o.controllerPromptsActive = false
    o.controllerPromptStyleToken = nil
    o._promptTrackedButtons = {}

    return o
end

function BurdJournals.UI.MainPanel:initialise()
    ISPanelJoypad.initialise(self)
end

function BurdJournals.UI.MainPanel:resizeToJournalData(journalData)
    if type(journalData) ~= "table" then
        return false
    end

    local layoutMetrics = getUILayoutMetrics()
    local baseHeight = 220
    local itemHeight = math.max(52, layoutMetrics.rowHeight or 52)
    local headerRowHeight = math.max(52, itemHeight)
    local minHeight = self.mode == "absorb" and 560 or 500
    local screenHeight = getCore and getCore() and getCore():getScreenHeight() or 900
    local maxHeight = math.min(820, screenHeight - 40)
    local skillCount = 0
    local traitCount = 0
    local statCount = 0
    local recipeCount = 0

    if type(journalData.skills) == "table" then
        for skillName, _ in pairs(journalData.skills) do
            if not BurdJournals.isSkillVisibleForJournal or BurdJournals.isSkillVisibleForJournal(journalData, skillName) then
                skillCount = skillCount + 1
            end
        end
    end
    if type(journalData.traits) == "table" then
        for _ in pairs(journalData.traits) do
            traitCount = traitCount + 1
        end
    end
    if type(journalData.stats) == "table" then
        for _ in pairs(journalData.stats) do
            statCount = statCount + 1
        end
    end
    if type(journalData.recipes) == "table" then
        for _ in pairs(journalData.recipes) do
            recipeCount = recipeCount + 1
        end
    end

    local contentHeight = math.max(
        baseHeight + headerRowHeight + (skillCount * itemHeight),
        baseHeight + headerRowHeight + (traitCount * itemHeight),
        baseHeight + headerRowHeight + (statCount * itemHeight),
        baseHeight + headerRowHeight + (recipeCount * itemHeight)
    )
    local targetHeight = math.max(minHeight, math.min(maxHeight, contentHeight))
    local oldHeight = tonumber(self.height) or targetHeight
    if targetHeight <= oldHeight + 4 then
        return false
    end

    local delta = targetHeight - oldHeight
    if self.setHeight then
        self:setHeight(targetHeight)
    else
        self.height = targetHeight
    end
    if self.setY and self.getY then
        self:setY(math.max(0, self:getY() - math.floor(delta / 2)))
    end

    if self.skillList and self.skillList.setHeight then
        self.skillList:setHeight(math.max(80, (tonumber(self.skillList:getHeight()) or 80) + delta))
        syncListBoxScrollGeometry(self.skillList, true)
    end
    if self.listBottomY then
        self.listBottomY = self.listBottomY + delta
    end
    if self.paginationBarY then
        self.paginationBarY = self.paginationBarY + delta
    end
    if self.footerY then
        self.footerY = self.footerY + delta
    end

    local controls = {
        self.feedbackLabel,
        self.absorbTabBtn,
        self.absorbAllBtn,
        self.dissolveBtn,
        self.closeBottomBtn,
    }
    for _, control in ipairs(controls) do
        if control and control.setY and control.getY then
            control:setY(control:getY() + delta)
        end
    end
    if self.renderPaginatedListEntries then
        self:renderPaginatedListEntries()
    end
    return true
end

function BurdJournals.UI.MainPanel:isJoypadActive()
    if BurdJournals and BurdJournals.isJoypadActiveForPlayer then
        return BurdJournals.isJoypadActiveForPlayer(self.playerNum or 0)
    end
    if not getJoypadData then
        return false, nil
    end
    local joypadData = getJoypadData(self.playerNum or 0)
    if not joypadData then
        return false, nil
    end
    if joypadData.isConnected and not joypadData:isConnected() then
        return false, joypadData
    end
    if joypadData.id ~= nil and joypadData.id == -1 then
        return false, joypadData
    end
    return true, joypadData
end

function BurdJournals.UI.MainPanel:isControlVisible(control)
    if not control then
        return false
    end
    if control.getIsVisible then
        return control:getIsVisible()
    end
    if control.isVisible then
        return control:isVisible()
    end
    return true
end

function BurdJournals.UI.MainPanel:getNowMs()
    return getTimestampMs and getTimestampMs() or 0
end

function BurdJournals.UI.MainPanel:getListSelectionContextKey()
    local tab = self.currentTab or "skills"
    local filter = "all"
    if self.filterState and self.filterState[tab] then
        filter = tostring(self.filterState[tab].current or "all")
    end
    local search = tostring(self.searchQuery or "")
    return table.concat({
        tostring(self.mode or "view"),
        tostring(tab),
        filter,
        search,
        tostring(self.paginationCurrentPage or 1),
    }, "|")
end

function BurdJournals.UI.MainPanel:isSelectableListRow(index)
    if not self.skillList or type(self.skillList.items) ~= "table" then
        return false
    end
    local row = self.skillList.items[tonumber(index) or -1]
    local item = row and row.item
    return item ~= nil and not item.isHeader and not item.isEmpty
end

function BurdJournals.UI.MainPanel:isPrimaryActionAvailableForItem(item)
    if not item then
        return false
    end

    if self.mode == "log" then
        return item.canRecord == true
    end

    if self.mode == "view" then
        if item.isSkill then
            return item.canClaim == true
        end
        if item.isTrait then
            return not item.alreadyKnown and not item.isClaimed
        end
        if item.isRecipe then
            return not item.alreadyKnown and not item.isClaimed
        end
        if item.isStat then
            return item.canClaim and not item.alreadyClaimed
        end
        return false
    end

    if self.mode == "absorb" then
        if item.isSkill then
            return not item.isClaimed
        end
        if item.isForgetSlot then
            return not item.isClaimed
        end
        if item.isTrait then
            return not item.alreadyKnown and not item.isClaimed
        end
        if item.isRecipe then
            return not item.alreadyKnown and not item.isClaimed
        end
        return false
    end

    return false
end

function BurdJournals.UI.MainPanel:findFirstSelectableListIndex(preferActionable)
    if not self.skillList or type(self.skillList.items) ~= "table" then
        return nil
    end

    local firstSelectable = nil
    for i, row in ipairs(self.skillList.items) do
        local item = row and row.item
        if item and not item.isHeader and not item.isEmpty then
            if not firstSelectable then
                firstSelectable = i
            end
            if preferActionable and self:isPrimaryActionAvailableForItem(item) then
                return i
            end
        end
    end

    return firstSelectable
end

function BurdJournals.UI.MainPanel:rememberListSelection()
    if not self.skillList then
        return
    end

    local selected = tonumber(self.skillList.selected) or -1
    if self:isSelectableListRow(selected) then
        self.lastListSelectedIndex = selected
        self.lastListContextKey = self:getListSelectionContextKey()
    end
end

function BurdJournals.UI.MainPanel:ensureListSelection(preferActionable)
    if not self.skillList or type(self.skillList.items) ~= "table" then
        return nil
    end

    local contextKey = self:getListSelectionContextKey()
    local selected = tonumber(self.skillList.selected) or -1
    if self:isSelectableListRow(selected) then
        self.lastListSelectedIndex = selected
        self.lastListContextKey = contextKey
        return selected
    end

    local targetIndex = nil
    if self.lastListContextKey == contextKey and self:isSelectableListRow(self.lastListSelectedIndex) then
        targetIndex = tonumber(self.lastListSelectedIndex)
    end
    if not targetIndex and preferActionable == true then
        targetIndex = self:findFirstSelectableListIndex(preferActionable == true)
    end

    if targetIndex and self:isSelectableListRow(targetIndex) then
        self.skillList.selected = targetIndex
        if preferActionable == true and self.skillList.ensureVisible then
            self.skillList:ensureVisible(targetIndex)
        end
        self.lastListSelectedIndex = targetIndex
        self.lastListContextKey = contextKey
        return targetIndex
    end

    return nil
end

function BurdJournals.UI.MainPanel:isListRowFocusedInPanel()
    if not self.skillList then
        return false
    end

    local focusedChild = self.getJoypadFocus and self:getJoypadFocus() or nil
    if focusedChild == self.skillList then
        return true
    end

    local rowIndex = select(1, self:findJoypadControl(self.skillList))
    if not rowIndex then
        return false
    end
    return (tonumber(self.joypadIndexY) or -1) == rowIndex
end

function BurdJournals.UI.MainPanel:isListFocusAmbiguous()
    return self.skillList ~= nil and not self.listFocusActive and self:isListRowFocusedInPanel()
end

function BurdJournals.UI.MainPanel:isListEnterGuardActive()
    return (tonumber(self.listEnterGuardUntilMs) or 0) > self:getNowMs()
end

function BurdJournals.UI.MainPanel:enterListJoypadFocus(joypadData)
    if not self.skillList or not joypadData then
        return false
    end

    self:ensureListSelection(false)
    self.listFocusActive = true
    self.listEnterGuardUntilMs = self:getNowMs() + 180
    self.listEntryConsumeA = true
    if self.skillList.setJoypadFocused then
        self.skillList:setJoypadFocused(true, joypadData)
    end
    joypadData.focus = self.skillList
    if updateJoypadFocus then
        updateJoypadFocus(joypadData)
    end
    return true
end

function BurdJournals.UI.MainPanel:exitListJoypadFocus(joypadData)
    self.listFocusActive = false
    self.listEnterGuardUntilMs = 0
    self.listEntryConsumeA = false
    self:rememberListSelection()

    local data = joypadData
    if not data and getJoypadData then
        data = getJoypadData(self.playerNum or 0)
    end

    if self.skillList and data and self.skillList.setJoypadFocused then
        self.skillList:setJoypadFocused(false, data)
    end

    local rowIndex, colIndex = self:findJoypadControl(self.skillList)
    if rowIndex then
        self.joypadIndexY = rowIndex
        self.joypadButtons = self.joypadButtonsY and self.joypadButtonsY[rowIndex] or nil
        self.joypadIndex = colIndex or 1
    end

    if data and setJoypadFocus then
        setJoypadFocus(self.playerNum, self)
        if updateJoypadFocus then
            updateJoypadFocus(data)
        end
    end

    return true
end

function BurdJournals.UI.MainPanel:addJoypadRow(controls)
    if type(controls) ~= "table" then
        return
    end
    local row = {}
    for _, control in ipairs(controls) do
        if self:isControlVisible(control) then
            table.insert(row, control)
        end
    end
    if #row > 0 then
        table.insert(self.joypadButtonsY, row)
    end
end

function BurdJournals.UI.MainPanel:findJoypadControl(control)
    if not control or type(self.joypadButtonsY) ~= "table" then
        return nil, nil
    end
    for rowIndex, row in ipairs(self.joypadButtonsY) do
        for colIndex, rowControl in ipairs(row) do
            if rowControl == control then
                return rowIndex, colIndex
            end
        end
    end
    return nil, nil
end

function BurdJournals.UI.MainPanel:getVisibleJoypadChildren(rowIndex)
    if self.getVisibleChildren then
        local visibleChildren = self:getVisibleChildren(rowIndex)
        if type(visibleChildren) == "table" then
            return visibleChildren
        end
    end

    local children = {}
    local row = type(self.joypadButtonsY) == "table" and self.joypadButtonsY[rowIndex] or nil
    if type(row) ~= "table" then
        return children
    end

    for _, child in ipairs(row) do
        if self:isControlVisible(child) then
            table.insert(children, child)
        end
    end
    return children
end

function BurdJournals.UI.MainPanel:getFirstVisibleJoypadRow()
    if self.getMinVisibleRow then
        local rowIndex = tonumber(self:getMinVisibleRow())
        if rowIndex and rowIndex >= 1 then
            return rowIndex
        end
    end

    if type(self.joypadButtonsY) ~= "table" then
        return -1
    end

    for rowIndex = 1, #self.joypadButtonsY do
        if #self:getVisibleJoypadChildren(rowIndex) > 0 then
            return rowIndex
        end
    end

    return -1
end

function BurdJournals.UI.MainPanel:rebuildJoypadRows()
    if not self.joypadButtonsY then
        self.joypadButtonsY = {}
    end

    local joypadData = getJoypadData and getJoypadData(self.playerNum or 0) or nil
    local panelHadFocus = joypadData and joypadData.focus == self
    local listHadFocus = joypadData and self.skillList and joypadData.focus == self.skillList
    self.listFocusActive = listHadFocus == true
    local preferredControl = nil
    if panelHadFocus and self.getJoypadFocus then
        preferredControl = self:getJoypadFocus()
    end

    self.joypadButtonsY = {}

    self:addJoypadRow({
        self.headerStateBadgeBtn,
        self.headerUuidBadgeBtn,
        self.headerRefreshBtn,
    })

    if self.tabs and self.tabButtons then
        local tabRow = {}
        for _, tab in ipairs(self.tabs) do
            local btn = self.tabButtons[tab.id]
            if self:isControlVisible(btn) then
                table.insert(tabRow, btn)
            end
        end
        self:addJoypadRow(tabRow)
    end

    if self.filterBarVisible then
        local filterRow = {}
        if self:isControlVisible(self.filterScrollLeftBtn) then
            table.insert(filterRow, self.filterScrollLeftBtn)
        end
        if self.filterTabButtons then
            for _, btn in ipairs(self.filterTabButtons) do
                if self:isControlVisible(btn) then
                    table.insert(filterRow, btn)
                end
            end
        end
        if self:isControlVisible(self.filterScrollRightBtn) then
            table.insert(filterRow, self.filterScrollRightBtn)
        end
        self:addJoypadRow(filterRow)
    end

    self:addJoypadRow({
        self.searchEntry,
        self.searchClearBtn,
    })

    if self:isControlVisible(self.skillList) then
        self.skillList.joypadParent = self
        self:addJoypadRow({ self.skillList })
    end

    local paginationRow = {}
    if self:isControlVisible(self.paginationPrevBtn) then
        table.insert(paginationRow, self.paginationPrevBtn)
    end
    if self:isControlVisible(self.paginationNextBtn) then
        table.insert(paginationRow, self.paginationNextBtn)
    end
    if #paginationRow > 0 then
        self:addJoypadRow(paginationRow)
    end

    local footerRow = {}
    if self.mode == "log" then
        if self:isControlVisible(self.recordTabBtn) then
            table.insert(footerRow, self.recordTabBtn)
        end
        if self:isControlVisible(self.recordAllBtn) then
            table.insert(footerRow, self.recordAllBtn)
        end
    else
        if self:isControlVisible(self.absorbTabBtn) then
            table.insert(footerRow, self.absorbTabBtn)
        end
        if self:isControlVisible(self.absorbAllBtn) then
            table.insert(footerRow, self.absorbAllBtn)
        end
    end
    if self:isControlVisible(self.dissolveBtn) then
        table.insert(footerRow, self.dissolveBtn)
    end
    if self:isControlVisible(self.closeBottomBtn) then
        table.insert(footerRow, self.closeBottomBtn)
    end
    self:addJoypadRow(footerRow)

    if #self.joypadButtonsY == 0 then
        self.joypadButtons = nil
        self.joypadIndex = 0
        self.joypadIndexY = 0
        self.listFocusActive = false
        self:refreshControllerPrompts(true)
        return
    end

    if panelHadFocus then
        local rowIndex, colIndex = self:findJoypadControl(preferredControl)
        if not rowIndex and self.joypadIndexY and self.joypadIndexY >= 1 and self.joypadIndexY <= #self.joypadButtonsY then
            local currentRow = self:getVisibleJoypadChildren(self.joypadIndexY)
            if #currentRow > 0 then
                rowIndex = self.joypadIndexY
                colIndex = math.min(math.max(self.joypadIndex or 1, 1), #currentRow)
            end
        end
        if not rowIndex then
            rowIndex = self:getFirstVisibleJoypadRow()
            if rowIndex == -1 then
                rowIndex = 1
            end
            colIndex = 1
        end

        self.joypadIndexY = rowIndex
        self.joypadButtons = self.joypadButtonsY[rowIndex]
        local visibleChildren = self:getVisibleJoypadChildren(rowIndex)
        if #visibleChildren > 0 then
            self.joypadIndex = math.min(math.max(colIndex or 1, 1), #visibleChildren)
            local child = visibleChildren[self.joypadIndex]
            if child and child ~= self.skillList then
                child:setJoypadFocused(true, joypadData)
            end
        else
            self.joypadIndex = 1
        end
    elseif listHadFocus then
        if not self:isControlVisible(self.skillList) and setJoypadFocus then
            self.listFocusActive = false
            setJoypadFocus(self.playerNum, self)
            if updateJoypadFocus and joypadData then
                updateJoypadFocus(joypadData)
            end
        else
            self:ensureListSelection(false)
        end
    else
        self.listFocusActive = false
        local firstRow = self:getFirstVisibleJoypadRow()
        if firstRow ~= -1 then
            self.joypadIndexY = firstRow
            self.joypadButtons = self.joypadButtonsY[firstRow]
            local firstChildren = self:getVisibleJoypadChildren(firstRow)
            self.joypadIndex = (#firstChildren > 0) and 1 or 0
        end
    end

    self:refreshControllerPrompts(true)
end

function BurdJournals.UI.MainPanel:wireSkillListJoypad()
    if not self.skillList then
        return
    end

    local list = self.skillList
    list.joypadParent = self
    list.mainPanel = self

    list.onJoypadDownInParent = function(listbox, button, joypadData)
        local panel = listbox.mainPanel
        if not panel or not joypadData then
            return false
        end

        if button == Joypad.AButton then
            return panel:enterListJoypadFocus(joypadData)
        end

        if button == Joypad.YButton then
            return true
        end

        if button == Joypad.LBumper then
            panel:cycleTopTab(-1)
            return true
        end

        if button == Joypad.RBumper then
            panel:cycleTopTab(1)
            return true
        end

        if button == Joypad.XButton then
            panel:showFeedback(
                getText("UI_BurdJournals_ControllerNoSecondaryAction") or "No secondary action for this entry",
                {r=0.95, g=0.75, b=0.4}
            )
            return true
        end

        return false
    end

    list.onJoypadDown = function(listbox, button, joypadData)
        local panel = listbox.mainPanel
        if not panel then
            ISScrollingListBox.onJoypadDown(listbox, button, joypadData)
            return
        end
        panel.listFocusActive = true

        if button == Joypad.BButton then
            panel:exitListJoypadFocus(joypadData)
            return
        end

        if button == Joypad.AButton then
            if panel.listEntryConsumeA then
                panel.listEntryConsumeA = false
                return
            end
            if panel:isListEnterGuardActive() then
                return
            end
            local item = panel:getSelectedListItem()
            if not item or not panel:performPrimaryListAction(item) then
                panel:showFeedback(
                    getText("UI_BurdJournals_ControllerNoPrimaryAction") or "No primary action for this entry",
                    {r=0.95, g=0.75, b=0.4}
                )
            end
            return
        end

        if button == Joypad.XButton then
            local item = panel:getSelectedListItem()
            if not item or not panel:performSecondaryListAction(item) then
                panel:showFeedback(
                    getText("UI_BurdJournals_ControllerNoSecondaryAction") or "No secondary action for this entry",
                    {r=0.95, g=0.75, b=0.4}
                )
            end
            return
        end

        if button == Joypad.YButton then
            if not panel:performTabBatchAction() then
                panel:showFeedback(
                    getText("UI_BurdJournals_ControllerNoTabAction") or "No tab action available right now",
                    {r=0.95, g=0.75, b=0.4}
                )
            end
            return
        end

        if button == Joypad.LBumper then
            panel:cycleTopTab(-1)
            return
        end

        if button == Joypad.RBumper then
            panel:cycleTopTab(1)
            return
        end

        ISScrollingListBox.onJoypadDown(listbox, button, joypadData)
        panel:rememberListSelection()
    end
end

function BurdJournals.UI.MainPanel:getSelectedListItem()
    if not self.skillList or type(self.skillList.items) ~= "table" then
        return nil
    end

    local selected = self:ensureListSelection(true)
    local maxItems = #self.skillList.items
    if not selected or selected < 1 or selected > maxItems then
        return nil
    end

    local row = self.skillList.items[selected]
    local item = row and row.item
    if not item or item.isHeader or item.isEmpty then
        return nil
    end
    self.lastListSelectedIndex = selected
    self.lastListContextKey = self:getListSelectionContextKey()
    return item
end

function BurdJournals.UI.MainPanel:performPrimaryListAction(item)
    if not item then
        return false
    end

    if self.mode == "log" then
        if not item.canRecord then
            if not self:hasRecordWritingTool() then
                self:showNeedWritingToolFeedback()
            elseif item.isAtBaseline then
                self:showFeedback(getText("UI_BurdJournals_CantRecordStartingSkills") or "Can't record starting skills", {r=0.7, g=0.5, b=0.3})
            elseif item.isStartingTrait then
                self:showFeedback(getText("UI_BurdJournals_CantRecordStartingTraits") or "Can't record starting traits", {r=0.7, g=0.5, b=0.3})
            end
            return false
        end
        if self.confirmNotesBeforeAction and self:confirmNotesBeforeAction("recordItem", item) then
            return true
        end
        if item.isSkill then
            self:recordSkill(item.skillName, item.xp, item.level, item.baselineXP)
            return true
        end
        if item.isTrait then
            self:recordTrait(item.traitId)
            return true
        end
        if item.isStat then
            self:recordStat(item.statId, item.currentValue)
            return true
        end
        if item.isRecipe then
            self:recordRecipe(item.recipeName)
            return true
        end
        return false
    end

    if self.mode == "view" then
        if item.isSkill and item.canClaim then
            self:claimSkill(item.skillName, item.xp)
            return true
        end
        if item.isTrait and not item.alreadyKnown and not item.isClaimed then
            self:claimTrait(item.traitId)
            return true
        end
        if item.isRecipe and not item.alreadyKnown and not item.isClaimed then
            self:claimRecipe(item.recipeName)
            return true
        end
        if item.isStat and item.canClaim and not item.alreadyClaimed then
            self:claimStat(item.statId, item.recordedValue)
            return true
        end
        return false
    end

    if self.mode == "absorb" then
        if item.isSkill and not item.isClaimed then
            self:absorbSkill(item.skillName, item.xp)
            return true
        end
        if item.isForgetSlot and not item.isClaimed then
            self:claimForgetTrait(item.traitId)
            return true
        end
        if item.isTrait and not item.alreadyKnown and not item.isClaimed then
            self:absorbTrait(item.traitId)
            return true
        end
        if item.isRecipe and not item.alreadyKnown and not item.isClaimed then
            self:absorbRecipe(item.recipeName)
            return true
        end
        return false
    end

    return false
end

function BurdJournals.UI.MainPanel:performSecondaryListAction(item)
    if self.mode ~= "view" or not item then
        return false
    end

    if item.isSkill then
        self:eraseSkillEntry(item.skillName)
        return true
    end
    if item.isTrait then
        self:eraseTraitEntry(item.traitId)
        return true
    end
    if item.isRecipe then
        self:eraseRecipeEntry(item.recipeName)
        return true
    end
    if item.isStat then
        self:eraseStatEntry(item.statId)
        return true
    end
    return false
end

function BurdJournals.UI.MainPanel:performTabBatchAction()
    if self.mode == "log" then
        self:onRecordTab()
        return true
    end
    if self.mode == "view" then
        self:onClaimTab()
        return true
    end
    if self.mode == "absorb" then
        self:onAbsorbTab()
        return true
    end
    return false
end

function BurdJournals.UI.MainPanel:cycleTopTab(direction)
    if not self.tabs or #self.tabs <= 1 then
        return false
    end

    local dir = tonumber(direction) or 0
    if dir == 0 then
        return false
    end

    local currentIndex = 1
    for i, tab in ipairs(self.tabs) do
        if tab.id == self.currentTab then
            currentIndex = i
            break
        end
    end

    local nextIndex = currentIndex + dir
    if nextIndex < 1 then
        nextIndex = #self.tabs
    elseif nextIndex > #self.tabs then
        nextIndex = 1
    end

    local nextTab = self.tabs[nextIndex]
    if not nextTab or not self.tabButtons then
        return false
    end

    local btn = self.tabButtons[nextTab.id]
    if not btn then
        return false
    end

    self:onTabClick(btn)
    return true
end

function BurdJournals.UI.MainPanel:getControllerPromptStyleToken()
    local core = getCore and getCore() or nil
    local style = "default"
    if core and core.getOptionControllerButtonStyle then
        style = tostring(core:getOptionControllerButtonStyle())
    end

    local textures = Joypad and Joypad.Texture or nil
    local aBtn = textures and textures.AButton or nil
    local bBtn = textures and textures.BButton or nil
    local xBtn = textures and textures.XButton or nil
    return style .. "|" .. tostring(aBtn) .. "|" .. tostring(bBtn) .. "|" .. tostring(xBtn)
end

function BurdJournals.UI.MainPanel:getPromptTextureForAction(actionKey)
    if not self.controllerPromptsActive then
        return nil
    end
    local textures = Joypad and Joypad.Texture or nil
    if not textures then
        return nil
    end
    if actionKey == "A" then
        return textures.AButton
    end
    if actionKey == "B" then
        return textures.BButton
    end
    if actionKey == "X" then
        return textures.XButton
    end
    if actionKey == "Y" then
        return textures.YButton
    end
    return nil
end

function BurdJournals.UI.MainPanel:applyJoypadPrompt(button, textureOrNil)
    if not button then
        return
    end
    if textureOrNil and button.setJoypadButton then
        button:setJoypadButton(textureOrNil)
        return
    end
    if button.clearJoypadButton then
        button:clearJoypadButton()
    elseif button.setJoypadButton then
        button:setJoypadButton(nil)
    end
end

function BurdJournals.UI.MainPanel:clearAllJoypadPrompts()
    if type(self._promptTrackedButtons) == "table" then
        for _, button in ipairs(self._promptTrackedButtons) do
            self:applyJoypadPrompt(button, nil)
        end
    end
    self._promptTrackedButtons = {}
end

function BurdJournals.UI.MainPanel:refreshControllerPrompts(force)
    local joypadActive = self:isJoypadActive()
    local styleToken = joypadActive and self:getControllerPromptStyleToken() or nil
    if not force
        and self.controllerPromptsActive == joypadActive
        and self.controllerPromptStyleToken == styleToken
    then
        return
    end

    self.controllerPromptsActive = joypadActive
    self.controllerPromptStyleToken = styleToken
    self:clearAllJoypadPrompts()

    if not joypadActive then
        return
    end

    local tracked = {}
    local function addPrompt(button, texture)
        if not button or tracked[button] then
            return
        end
        tracked[button] = true
        self:applyJoypadPrompt(button, texture)
        table.insert(self._promptTrackedButtons, button)
    end

    local yPrompt = self:getPromptTextureForAction("Y")

    addPrompt(self.recordTabBtn, yPrompt)
    addPrompt(self.absorbTabBtn, yPrompt)
end

function BurdJournals.UI.MainPanel:drawPillLabelWithPrompt(listbox, x, y, w, h, text, textColor, promptKey)
    if not listbox then
        return
    end

    local label = tostring(text or "")
    local color = textColor or {r=1, g=1, b=1, a=1}
    local font = UIFont.Small
    local textWidth = getCachedSmallTextWidth(label)
    local textY = y + 4
    local promptTexture = promptKey and self:getPromptTextureForAction(promptKey) or nil

    if not promptTexture then
        listbox:drawText(label, x + (w - textWidth) / 2, textY, color.r, color.g, color.b, color.a or 1, font)
        return
    end

    local iconSize = math.max(10, math.min(h - 6, 14))
    local gap = 3
    local totalWidth = iconSize + gap + textWidth
    if totalWidth > (w - 2) then
        listbox:drawText(label, x + (w - textWidth) / 2, textY, color.r, color.g, color.b, color.a or 1, font)
        return
    end

    local startX = x + (w - totalWidth) / 2
    listbox:drawTextureScaledAspect(promptTexture, startX, y + (h - iconSize) / 2, iconSize, iconSize, 1, 1, 1, 1)
    listbox:drawText(label, startX + iconSize + gap, textY, color.r, color.g, color.b, color.a or 1, font)
end

function BurdJournals.UI.MainPanel:getCachedSmallTextWidth(text)
    return getCachedSmallTextWidth(text)
end

function BurdJournals.UI.MainPanel:isSelectedDrawItem(listbox, item)
    if not listbox or not item or type(listbox.items) ~= "table" then
        return false
    end
    local selectedIndex = tonumber(listbox.selected) or -1
    if selectedIndex < 1 or selectedIndex > #listbox.items then
        return false
    end
    return listbox.items[selectedIndex] == item
end

function BurdJournals.UI.MainPanel:drawSelectedRowOutline(listbox, item, cardX, cardY, cardW, cardH)
    if not self:isSelectedDrawItem(listbox, item) then
        return
    end

    local joypadFocusedList = self.listFocusActive == true
    local outerA = joypadFocusedList and 0.95 or 0.75
    local innerA = joypadFocusedList and 0.85 or 0.65
    local outer = {r=0.45, g=0.78, b=0.95}
    local inner = {r=0.28, g=0.62, b=0.82}

    listbox:drawRectBorder(cardX - 1, cardY - 1, cardW + 2, cardH + 2, outerA, outer.r, outer.g, outer.b)
    listbox:drawRectBorder(cardX + 1, cardY + 1, cardW - 2, cardH - 2, innerA, inner.r, inner.g, inner.b)
end

function BurdJournals.UI.MainPanel:showControllerHintOnce()
    if self.controllerHintShown then
        return
    end
    self.controllerHintShown = true
    self:showFeedback(
        getText("UI_BurdJournals_ControllerHintHybrid") or "Controller: A Select, B Back, X Erase, Y Tab Action, LB/RB Switch Tabs",
        {r=0.62, g=0.84, b=1.0}
    )
end

function BurdJournals.UI.MainPanel:createTabs(tabs, startY, themeColors)
    local padding = 16
    local tabHeight = 28
    local tabSpacing = 4
    local tabY = startY

    self.tabs = tabs
    self.currentTab = tabs[1] and tabs[1].id or "skills"
    self.tabButtons = {}
    self.tabDefinitions = {}

    local totalWidth = self.width - padding * 2
    local tabCount = #tabs
    local tabWidth = math.floor((totalWidth - (tabSpacing * (tabCount - 1))) / tabCount)

    local tabX = padding
    for i, tab in ipairs(tabs) do
        local isActive = (tab.id == self.currentTab)
        self.tabDefinitions[tab.id] = tab

        local btn = ISButton:new(tabX, tabY, tabWidth, tabHeight, tab.label, self, BurdJournals.UI.MainPanel.onTabClick)
        btn:initialise()
        btn:instantiate()
        btn.internal = tab.id
        btn.tabIndex = i

        self:applyTabButtonStyle(btn, tab.id, isActive)

        self:addChild(btn)
        self.tabButtons[tab.id] = btn

        tabX = tabX + tabWidth + tabSpacing
    end

    self.tabBarY = tabY + tabHeight + 8
    return self.tabBarY
end

function BurdJournals.UI.MainPanel:applyTabButtonStyle(btn, tabId, isActive)
    if not btn then
        return
    end

    local baseTheme = self.tabThemeColors or {
        active = {r=0.35, g=0.28, b=0.18},
        inactive = {r=0.18, g=0.15, b=0.12},
        accent = {r=0.5, g=0.4, b=0.25},
    }
    local tabDef = self.tabDefinitions and self.tabDefinitions[tabId] or nil
    local tabTheme = (tabDef and tabDef.themeColors) or baseTheme

    local activeBg = tabTheme.active or baseTheme.active
    local inactiveBg = tabTheme.inactive or baseTheme.inactive
    local accent = tabTheme.accent or baseTheme.accent
    local activeText = tabTheme.textActive or {r=1, g=1, b=1}
    local inactiveText = tabTheme.textInactive or {r=0.7, g=0.7, b=0.7}

    if isActive then
        btn.backgroundColor = {r=activeBg.r, g=activeBg.g, b=activeBg.b, a=0.9}
        btn.borderColor = {r=accent.r, g=accent.g, b=accent.b, a=1}
        btn.textColor = {r=activeText.r, g=activeText.g, b=activeText.b, a=1}
    else
        btn.backgroundColor = {r=inactiveBg.r, g=inactiveBg.g, b=inactiveBg.b, a=0.62}
        if tabDef and tabDef.themeColors then
            btn.borderColor = {r=math.min(1, accent.r * 0.75), g=math.min(1, accent.g * 0.75), b=math.min(1, accent.b * 0.75), a=0.8}
        else
            btn.borderColor = {r=0.3, g=0.3, b=0.3, a=0.8}
        end
        btn.textColor = {r=inactiveText.r, g=inactiveText.g, b=inactiveText.b, a=1}
    end
end

function BurdJournals.UI.MainPanel:onTabClick(button)
    local tabId = button.internal
    if tabId == self.currentTab then return end

    if self.currentTab == "notes" and self.saveNotesIfDirty then
        self:saveNotesIfDirty("tab")
    end

    if self.listFocusActive then
        self:exitListJoypadFocus(nil)
    end
    if self.skillList then
        self.skillList.selected = -1
    end
    self.lastListSelectedIndex = nil
    self.lastListContextKey = nil

    self.currentTab = tabId

    self:clearSearch()

    self:updateTabStyles()

    self:rebuildFilterTabBar()

    self:refreshCurrentList()
end

function BurdJournals.UI.MainPanel:rebuildFilterTabBar()

    self:cleanupFilterTabBar()

    local filterBarY = self.filterBaseY or self.filterBarY
    if not filterBarY and self.tabBarY then
        filterBarY = self.tabBarY + 32
    elseif not filterBarY then
        filterBarY = 150
    end

    if self.tabThemeColors then
        local newY = self:createFilterTabBar(filterBarY, self.tabThemeColors)
        self:updateTopControlsLayout(newY)
    end
end

function BurdJournals.UI.MainPanel:updateTopControlsLayout(filterEndY)
    if not self.skillList then return end

    local y = filterEndY
    if not y then
        y = self.filterBaseY or self.filterBarY or self.skillList:getY()
        if self.filterBarVisible then
            local filterHeight = BurdJournals.UI.FILTER_TAB_HEIGHT or 22
            y = y + filterHeight + 4
        end
    end

    local searchHeight = 24
    if self.searchEntry then
        self.searchBarY = y
        self.searchEntry:setY(y)
        if self.searchClearBtn then
            local clearSize = self.searchClearBtn:getHeight() or 16
            self.searchClearBtn:setY(y + (searchHeight - clearSize) / 2)
        end
        y = y + searchHeight + 6
    else
        self.searchBarY = nil
    end

    local bottomY = self.listBottomY
    if not bottomY then
        bottomY = self.skillList:getY() + self.skillList:getHeight()
        self.listBottomY = bottomY
    end

    self.skillList:setY(y)
    self.skillList:setHeight(math.max(80, bottomY - y))
end

function BurdJournals.UI.MainPanel:updateTabStyles()
    if not self.tabButtons or not self.tabThemeColors then return end

    for tabId, btn in pairs(self.tabButtons) do
        local isActive = (tabId == self.currentTab)
        self:applyTabButtonStyle(btn, tabId, isActive)
    end
end

function BurdJournals.UI.MainPanel:createSearchBar(startY, themeColors, itemCount)
    local padding = 16
    local searchHeight = 24
    local minItemsForSearch = 5
    local clearButtonSize = 16

    self.searchQuery = ""

    if itemCount < minItemsForSearch then
        self.searchEntry = nil
        self.searchBarY = nil
        self.searchClearBtn = nil
        return startY
    end

    self.searchBarY = startY

    local entryWidth = self.width - padding * 2 - clearButtonSize - 4
    self.searchEntry = ISTextEntryBox:new("", padding, startY, entryWidth, searchHeight)
    self.searchEntry.font = UIFont.Small
    self.searchEntry:initialise()
    self.searchEntry:instantiate()
    self.searchEntry.backgroundColor = {r=0.08, g=0.08, b=0.1, a=0.9}
    self.searchEntry.borderColor = {r=themeColors.accent.r * 0.7, g=themeColors.accent.g * 0.7, b=themeColors.accent.b * 0.7, a=0.8}

    self.searchEntry.mainPanel = self

    local placeholder = getText("UI_BurdJournals_SearchPlaceholder") or "Search..."
    self.searchEntry:setTooltip(placeholder)

    self.searchEntry.lastSearchText = ""

    self.searchPendingRefresh = false

    self.searchEntry.onTextChange = function()
        local entry = self.searchEntry
        if entry and entry.mainPanel then
            entry.mainPanel.searchPendingRefresh = true
        end
    end

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

function BurdJournals.UI.MainPanel:onSearchClearClick()
    self:clearSearch()
    self:refreshCurrentList()

    if self.searchEntry then
        self.searchEntry:focus()
    end
end

function BurdJournals.UI.MainPanel:clearSearch()
    self.searchQuery = ""
    if self.skillList then
        self.skillList.selected = -1
    end
    self.lastListSelectedIndex = nil
    self.lastListContextKey = nil
    if self.searchEntry then
        self.searchEntry:setText("")
        self.searchEntry.lastSearchText = ""
    end
end

function BurdJournals.UI.MainPanel:getPaginationContextKey()
    local tab = self.currentTab or "skills"
    local filter = "all"
    if self.filterState and self.filterState[tab] then
        filter = tostring(self.filterState[tab].current or "all")
    end
    local search = tostring(self.searchQuery or "")
    local threshold = self:getPaginationThreshold()
    return table.concat({
        tostring(self.mode or "view"),
        tostring(tab),
        filter,
        search,
        tostring(threshold),
    }, "|")
end

function BurdJournals.UI.MainPanel:getPaginationThreshold()
    local threshold = BurdJournals.UI.LIST_PAGINATION_THRESHOLD or 50
    if BurdJournals.getSandboxOption then
        local sandboxThreshold = tonumber(BurdJournals.getSandboxOption("JournalUIPaginationThreshold"))
        if sandboxThreshold ~= nil then
            threshold = sandboxThreshold
        end
    end

    threshold = math.floor(tonumber(threshold) or 50)
    if threshold < 10 then
        threshold = 10
    elseif threshold > 200 then
        threshold = 200
    end
    return threshold
end

function BurdJournals.UI.MainPanel:appendListEntry(entries, id, data, tooltip, sortLabel, sortIndex)
    if type(entries) ~= "table" then
        return
    end

    local normalizedSortLabel = sortLabel
    if normalizedSortLabel == nil and type(data) == "table" then
        normalizedSortLabel = data.displayName or data.traitName or data.statName or data.text or id
    end
    if type(normalizedSortLabel) == "string" then
        normalizedSortLabel = string.lower(normalizedSortLabel)
    else
        normalizedSortLabel = tostring(normalizedSortLabel or id or "")
    end

    entries[#entries + 1] = {
        id = id,
        data = data,
        tooltip = tooltip,
        sortLabel = normalizedSortLabel,
        sortIndex = tonumber(sortIndex),
    }
end

function BurdJournals.UI.MainPanel:sortListEntries(entries)
    if type(entries) ~= "table" or #entries <= 1 then
        return
    end

    table.sort(entries, function(a, b)
        local aIndex = tonumber(a and a.sortIndex)
        local bIndex = tonumber(b and b.sortIndex)
        if aIndex ~= nil or bIndex ~= nil then
            aIndex = aIndex or math.huge
            bIndex = bIndex or math.huge
            if aIndex ~= bIndex then
                return aIndex < bIndex
            end
        end

        local aLabel = tostring(a and a.sortLabel or "")
        local bLabel = tostring(b and b.sortLabel or "")
        if aLabel ~= bLabel then
            return aLabel < bLabel
        end

        return tostring(a and a.id or "") < tostring(b and b.id or "")
    end)
end

function BurdJournals.UI.MainPanel:getPaginationRangeText(totalEntries, currentPage, pageSize)
    if totalEntries <= 0 then
        return ""
    end

    local startIndex = ((currentPage - 1) * pageSize) + 1
    local endIndex = math.min(totalEntries, currentPage * pageSize)
    return tostring(startIndex) .. "-" .. tostring(endIndex) .. " / " .. tostring(totalEntries)
end

function BurdJournals.UI.MainPanel:updatePaginationControls(totalEntries, totalPages, currentPage, isActive)
    if not self.paginationPrevBtn or not self.paginationNextBtn or not self.paginationLabel then
        return
    end

    if not isActive then
        self.paginationPrevBtn:setVisible(false)
        self.paginationNextBtn:setVisible(false)
        self.paginationLabel:setVisible(false)
        return
    end

    local pageSize = self:getPaginationThreshold()
    local labelText = self:getPaginationRangeText(totalEntries, currentPage, pageSize)
    local labelWidth = getTextManager():MeasureStringX(UIFont.Small, labelText)
    local barY = self.paginationBarY or (self.listBottomY or 0)
    local barHeight = self.paginationBarHeight or (BurdJournals.UI.LIST_PAGINATION_HEIGHT or 26)
    local btnW = self.paginationPrevBtn:getWidth()
    local gap = 8
    local labelX = math.floor((self.width - labelWidth) / 2)
    local btnY = barY + math.floor((barHeight - self.paginationPrevBtn:getHeight()) / 2)
    local labelY = barY + math.floor((barHeight - 18) / 2)

    self.paginationLabel:setName(labelText)
    self.paginationLabel:setX(labelX)
    self.paginationLabel:setY(labelY)
    self.paginationLabel:setVisible(true)

    self.paginationPrevBtn:setX(labelX - gap - btnW)
    self.paginationPrevBtn:setY(btnY)
    self.paginationPrevBtn:setVisible(true)
    self.paginationPrevBtn:setEnable(currentPage > 1)

    self.paginationNextBtn:setX(labelX + labelWidth + gap)
    self.paginationNextBtn:setY(btnY)
    self.paginationNextBtn:setVisible(true)
    self.paginationNextBtn:setEnable(currentPage < totalPages)
end

function BurdJournals.UI.MainPanel:clearPaginatedListBox()
    local listbox = self.skillList
    if not listbox then
        return
    end

    local preserveScroll = self.paginationPreserveScrollOnRender == true
    local scrollState = preserveScroll and captureListBoxScrollState(listbox) or nil

    if listbox.clear then
        listbox:clear()
    else
        listbox.items = {}
        listbox.count = 0
    end

    if listbox.setScrollHeight then
        listbox:setScrollHeight(0)
    end
    if listbox.vscroll then
        listbox.vscroll.scrolling = false
    end
    if preserveScroll and scrollState then
        restoreListBoxScrollState(listbox, scrollState)
    else
        listbox.smoothScrollTargetY = nil
        listbox.smoothScrollY = nil
    end
    syncListBoxScrollGeometry(listbox, not preserveScroll)
    if preserveScroll and scrollState then
        restoreListBoxScrollState(listbox, scrollState)
    end

    return scrollState
end

function BurdJournals.UI.MainPanel:addPaginatedListItem(entry)
    if not self.skillList or not entry then
        return
    end

    if type(entry) ~= "table" then
        return
    end

    local id = entry.id or entry.text or entry.name
    local data = entry.data or entry.item
    if id == nil or data == nil then
        return
    end

    local row = self.skillList:addItem(tostring(id), data)
    if entry.tooltip and type(row) == "table" then
        row.tooltip = entry.tooltip
    elseif entry.tooltip and type(self.skillList.items) == "table" then
        row = self.skillList.items[#self.skillList.items]
        if row then
            row.tooltip = entry.tooltip
        end
    end
end

function BurdJournals.UI.MainPanel:renderPaginatedListEntries()
    local scrollState = self:clearPaginatedListBox()

    local entries = self.paginationEntries or {}
    local totalEntries = #entries
    local threshold = self:getPaginationThreshold()
    local pageSize = threshold
    local isActive = totalEntries > threshold
    local totalPages = isActive and math.max(1, math.ceil(totalEntries / pageSize)) or 1
    local currentPage = tonumber(self.paginationCurrentPage) or 1
    if not isActive then
        currentPage = 1
    end
    currentPage = math.max(1, math.min(currentPage, totalPages))

    self.paginationCurrentPage = currentPage
    self.paginationActive = isActive
    self.paginationTotalEntries = totalEntries
    self.paginationTotalPages = totalPages

    if totalEntries <= 0 then
        local emptyEntry = self.paginationEmptyEntry
        if emptyEntry then
            self:addPaginatedListItem(emptyEntry)
        end
        self:updatePaginationControls(totalEntries, totalPages, currentPage, false)
        restoreListBoxScrollState(self.skillList, scrollState)
        scheduleListBoxScrollRestore(self, scrollState)
        return
    end

    local startIndex = 1
    local endIndex = totalEntries
    if isActive then
        startIndex = ((currentPage - 1) * pageSize) + 1
        endIndex = math.min(totalEntries, startIndex + pageSize - 1)
    end

    for i = startIndex, endIndex do
        local entry = entries[i]
        if entry then
            self:addPaginatedListItem(entry)
        end
    end

    self:updatePaginationControls(totalEntries, totalPages, currentPage, isActive)
    restoreListBoxScrollState(self.skillList, scrollState)
    scheduleListBoxScrollRestore(self, scrollState)
end

function BurdJournals.UI.MainPanel:setPaginatedListEntries(entries, emptyEntry)
    self.paginationEntries = entries or {}
    self.paginationEmptyEntry = emptyEntry

    local contextKey = self:getPaginationContextKey()
    local preserveScroll = self.paginationContextKey == contextKey
    if self.paginationContextKey ~= contextKey then
        self.paginationCurrentPage = 1
    end
    self.paginationContextKey = contextKey

    self:sortListEntries(self.paginationEntries)
    self.paginationPreserveScrollOnRender = preserveScroll
    self:renderPaginatedListEntries()
    self.paginationPreserveScrollOnRender = nil
end

function BurdJournals.UI.MainPanel:changePaginationPage(delta)
    if not self.paginationActive then
        return false
    end

    local targetPage = math.max(1, math.min((tonumber(self.paginationCurrentPage) or 1) + (tonumber(delta) or 0), tonumber(self.paginationTotalPages) or 1))
    if targetPage == (tonumber(self.paginationCurrentPage) or 1) then
        return false
    end

    self.paginationCurrentPage = targetPage
    if self.skillList then
        self.skillList.selected = -1
    end
    self.lastListSelectedIndex = nil
    self.lastListContextKey = nil
    self:renderPaginatedListEntries()
    self:ensureListSelection(self.listFocusActive)
    self:rebuildJoypadRows()
    self:playSound(BurdJournals.Sounds.PAGE_TURN)
    return true
end

function BurdJournals.UI.MainPanel:onPaginationPrev()
    return self:changePaginationPage(-1)
end

function BurdJournals.UI.MainPanel:onPaginationNext()
    return self:changePaginationPage(1)
end

function BurdJournals.UI.MainPanel:createPaginationControls(startY, themeColors)
    local barHeight = BurdJournals.UI.LIST_PAGINATION_HEIGHT or 26
    local btnSize = 22

    self.paginationBarY = startY
    self.paginationBarHeight = barHeight

    if not self.paginationPrevBtn then
        self.paginationPrevBtn = ISButton:new(0, startY, btnSize, btnSize, "<", self, BurdJournals.UI.MainPanel.onPaginationPrev)
        self.paginationPrevBtn:initialise()
        self.paginationPrevBtn:instantiate()
        self.paginationPrevBtn.font = UIFont.Small
        self:addChild(self.paginationPrevBtn)
    end

    if not self.paginationNextBtn then
        self.paginationNextBtn = ISButton:new(0, startY, btnSize, btnSize, ">", self, BurdJournals.UI.MainPanel.onPaginationNext)
        self.paginationNextBtn:initialise()
        self.paginationNextBtn:instantiate()
        self.paginationNextBtn.font = UIFont.Small
        self:addChild(self.paginationNextBtn)
    end

    local active = themeColors and themeColors.active or {r=0.18, g=0.22, b=0.14}
    local accent = themeColors and themeColors.accent or {r=0.35, g=0.45, b=0.30}
    local inactive = themeColors and themeColors.inactive or {r=0.10, g=0.15, b=0.18}
    for _, btn in ipairs({self.paginationPrevBtn, self.paginationNextBtn}) do
        btn.backgroundColor = {r=inactive.r, g=inactive.g, b=inactive.b, a=0.75}
        btn.backgroundColorMouseOver = {r=active.r, g=active.g, b=active.b, a=0.9}
        btn.borderColor = {r=accent.r, g=accent.g, b=accent.b, a=0.9}
        btn.textColor = {r=0.9, g=0.9, b=0.9, a=1}
        btn:setVisible(false)
    end

    if not self.paginationLabel then
        self.paginationLabel = ISLabel:new(0, startY, 18, "", 0.8, 0.82, 0.88, 1, UIFont.Small, true)
        self:addChild(self.paginationLabel)
    end
    self.paginationLabel:setVisible(false)

    return startY + barHeight
end

function BurdJournals.UI.MainPanel:matchesSearch(displayName)
    if not self.searchQuery or self.searchQuery == "" then
        return true
    end
    local query = string.lower(self.searchQuery)
    local name = string.lower(displayName or "")
    return string.find(name, query, 1, true) ~= nil
end

function BurdJournals.UI.MainPanel:initFilterState()
    if not self.filterState then
        self.filterState = {
            skills = {current = "all", sources = {}},
            traits = {current = "all", sources = {}},
            forget = {current = "all", sources = {}},
            recipes = {current = "all", sources = {}},
            stats = {current = "all", sources = {}},
            charinfo = {current = "all", sources = {}},
        }
    end
    self.filterTabButtons = {}
    self.filterScrollOffset = 0
    self.filterBarVisible = false
end

function BurdJournals.UI.MainPanel:createFilterTabBar(startY, themeColors)
    local padding = 16
    local filterHeight = BurdJournals.UI.FILTER_TAB_HEIGHT or 22
    local filterSpacing = BurdJournals.UI.FILTER_TAB_SPACING or 2
    local filterPadding = BurdJournals.UI.FILTER_TAB_PADDING or 8
    local arrowWidth = BurdJournals.UI.FILTER_ARROW_WIDTH or 20

    self:initFilterState()

    local journalData = BurdJournals.getJournalData(self.journal)
    local currentTab = self.currentTab or "skills"
    self.filterState[currentTab] = self.filterState[currentTab] or {current = "all", sources = {}}
    local sources = BurdJournals.collectModSources(currentTab, journalData, self.player, self.mode)
    if type(sources) ~= "table" then
        sources = {}
    end

    self.filterState[currentTab].sources = sources

    if #sources <= 2 then

        self.filterBarVisible = false
        self.filterTotalTabWidth = 0
        self.filterAvailableWidth = 0
        self.filterScrollMax = 0
        self:cleanupFilterTabBar()
        return startY
    end

    self.filterBarVisible = true
    self.filterBarY = startY

    local availableWidth = self.width - padding * 2 - arrowWidth * 2

    local tabX = padding + arrowWidth
    local totalTabWidth = 0

    for _, sourceData in ipairs(sources) do
        local label = sourceData.source
        if sourceData.source ~= "All" then
            label = sourceData.source .. " (" .. sourceData.count .. ")"
        end
        local textWidth = getTextManager():MeasureStringX(UIFont.Small, label)
        totalTabWidth = totalTabWidth + textWidth + filterPadding * 2 + filterSpacing
    end
    totalTabWidth = totalTabWidth - filterSpacing

    local needsScrolling = totalTabWidth > availableWidth
    self.filterNeedsScrolling = needsScrolling
    self.filterTotalTabWidth = totalTabWidth
    self.filterAvailableWidth = availableWidth
    self.filterScrollMax = math.max(0, totalTabWidth - availableWidth)
    self.filterScrollOffset = math.max(0, math.min(tonumber(self.filterScrollOffset) or 0, self.filterScrollMax))

    if needsScrolling then

        if not self.filterScrollLeftBtn then
            self.filterScrollLeftBtn = ISButton:new(padding, startY, arrowWidth, filterHeight, "<", self, BurdJournals.UI.MainPanel.onFilterScrollLeft)
            self.filterScrollLeftBtn:initialise()
            self.filterScrollLeftBtn:instantiate()
            self.filterScrollLeftBtn.backgroundColor = {r=0.15, g=0.15, b=0.18, a=0.8}
            self.filterScrollLeftBtn.borderColor = {r=0.3, g=0.3, b=0.35, a=0.8}
            self.filterScrollLeftBtn.textColor = {r=0.7, g=0.7, b=0.7, a=1}
            self:addChild(self.filterScrollLeftBtn)
        else
            self.filterScrollLeftBtn:setVisible(true)
            self.filterScrollLeftBtn:setY(startY)
        end

        if not self.filterScrollRightBtn then
            self.filterScrollRightBtn = ISButton:new(self.width - padding - arrowWidth, startY, arrowWidth, filterHeight, ">", self, BurdJournals.UI.MainPanel.onFilterScrollRight)
            self.filterScrollRightBtn:initialise()
            self.filterScrollRightBtn:instantiate()
            self.filterScrollRightBtn.backgroundColor = {r=0.15, g=0.15, b=0.18, a=0.8}
            self.filterScrollRightBtn.borderColor = {r=0.3, g=0.3, b=0.35, a=0.8}
            self.filterScrollRightBtn.textColor = {r=0.7, g=0.7, b=0.7, a=1}
            self:addChild(self.filterScrollRightBtn)
        else
            self.filterScrollRightBtn:setVisible(true)
            self.filterScrollRightBtn:setY(startY)
        end
    else

        if self.filterScrollLeftBtn then
            self.filterScrollLeftBtn:setVisible(false)
        end
        if self.filterScrollRightBtn then
            self.filterScrollRightBtn:setVisible(false)
        end

        tabX = padding + (self.width - padding * 2 - totalTabWidth) / 2
    end

    local currentFilter = self.filterState[currentTab].current or "all"
    local filterExists = (currentFilter == "all")
    if not filterExists then
        for _, sourceData in ipairs(sources) do
            local sourceId = sourceData.sourceId or string.lower(sourceData.source or "")
            if sourceId == currentFilter then
                filterExists = true
                break
            end
        end
    end
    if not filterExists then
        currentFilter = "all"
        self.filterState[currentTab].current = "all"
    end
    local btnX = tabX - self.filterScrollOffset

    for i, sourceData in ipairs(sources) do
        local label = sourceData.source
        if sourceData.source ~= "All" then
            label = sourceData.source .. " (" .. sourceData.count .. ")"
        end
        local textWidth = getTextManager():MeasureStringX(UIFont.Small, label)
        local btnWidth = textWidth + filterPadding * 2

        local sourceId = sourceData.sourceId or string.lower(sourceData.source or "")
        local isActive = sourceId == currentFilter

        local btn = ISButton:new(btnX, startY, btnWidth, filterHeight, label, self, BurdJournals.UI.MainPanel.onFilterTabClick)
        btn:initialise()
        btn:instantiate()
        btn.internal = sourceId
        btn.filterIndex = i
        btn.font = UIFont.Small

        if isActive then
            btn.backgroundColor = {r=themeColors.active.r, g=themeColors.active.g, b=themeColors.active.b, a=0.85}
            btn.borderColor = {r=themeColors.accent.r, g=themeColors.accent.g, b=themeColors.accent.b, a=1}
            btn.textColor = {r=1, g=1, b=1, a=1}
        else
            btn.backgroundColor = {r=themeColors.inactive.r, g=themeColors.inactive.g, b=themeColors.inactive.b, a=0.5}
            btn.borderColor = {r=0.25, g=0.25, b=0.25, a=0.6}
            btn.textColor = {r=0.6, g=0.6, b=0.6, a=1}
        end

        self:addChild(btn)
        table.insert(self.filterTabButtons, btn)

        btnX = btnX + btnWidth + filterSpacing
    end

    self:updateFilterTabPositions()
    return startY + filterHeight + 4
end

function BurdJournals.UI.MainPanel:onFilterTabClick(button)
    local filterId = button.internal
    local currentTab = self.currentTab or "skills"

    if filterId == self.filterState[currentTab].current then
        return
    end

    if self.skillList then
        self.skillList.selected = -1
    end
    self.lastListSelectedIndex = nil
    self.lastListContextKey = nil

    self.filterState[currentTab].current = filterId

    self:updateFilterTabStyles()

    self:refreshCurrentList()
end

function BurdJournals.UI.MainPanel:updateFilterTabStyles()
    if not self.filterTabButtons or not self.tabThemeColors then return end

    local themeColors = self.tabThemeColors
    local currentTab = self.currentTab or "skills"
    local currentFilter = self.filterState[currentTab].current or "all"

    for _, btn in ipairs(self.filterTabButtons) do
        local isActive = btn.internal == currentFilter
        if isActive then
            btn.backgroundColor = {r=themeColors.active.r, g=themeColors.active.g, b=themeColors.active.b, a=0.85}
            btn.borderColor = {r=themeColors.accent.r, g=themeColors.accent.g, b=themeColors.accent.b, a=1}
            btn.textColor = {r=1, g=1, b=1, a=1}
        else
            btn.backgroundColor = {r=themeColors.inactive.r, g=themeColors.inactive.g, b=themeColors.inactive.b, a=0.5}
            btn.borderColor = {r=0.25, g=0.25, b=0.25, a=0.6}
            btn.textColor = {r=0.6, g=0.6, b=0.6, a=1}
        end
    end
end

function BurdJournals.UI.MainPanel:onFilterScrollLeft()
    local maxOffset = math.max(0, tonumber(self.filterScrollMax) or 0)
    self.filterScrollOffset = math.max(0, math.min(maxOffset, (tonumber(self.filterScrollOffset) or 0) - 50))
    self:updateFilterTabPositions()
    self:rebuildJoypadRows()
end

function BurdJournals.UI.MainPanel:onFilterScrollRight()
    local maxOffset = math.max(0, tonumber(self.filterScrollMax) or 0)
    self.filterScrollOffset = math.max(0, math.min(maxOffset, (tonumber(self.filterScrollOffset) or 0) + 50))
    self:updateFilterTabPositions()
    self:rebuildJoypadRows()
end

function BurdJournals.UI.MainPanel:updateFilterTabPositions()
    if not self.filterTabButtons then return end

    local padding = 16
    local arrowWidth = BurdJournals.UI.FILTER_ARROW_WIDTH or 20
    local filterSpacing = BurdJournals.UI.FILTER_TAB_SPACING or 2

    local needsScrolling = self.filterNeedsScrolling == true
    local leftEdge = padding + (needsScrolling and arrowWidth or 0)
    local rightEdge = self.width - padding - (needsScrolling and arrowWidth or 0)
    local tabX = leftEdge - (tonumber(self.filterScrollOffset) or 0)

    for _, btn in ipairs(self.filterTabButtons) do
        btn:setX(tabX)
        if needsScrolling then
            local btnRight = tabX + btn:getWidth()
            -- Hide partially-clipped tabs so they never overlap nav arrows.
            btn:setVisible(tabX >= leftEdge and btnRight <= rightEdge)
        else
            btn:setVisible(true)
        end
        tabX = tabX + btn:getWidth() + filterSpacing
    end

    local maxOffset = math.max(0, tonumber(self.filterScrollMax) or 0)
    self.filterScrollOffset = math.max(0, math.min(maxOffset, tonumber(self.filterScrollOffset) or 0))
end

function BurdJournals.UI.MainPanel:cleanupFilterTabBar()
    if self.filterTabButtons then
        for _, btn in ipairs(self.filterTabButtons) do
            self:removeChild(btn)
        end
        self.filterTabButtons = {}
    end

    if self.filterScrollLeftBtn then
        self.filterScrollLeftBtn:setVisible(false)
    end
    if self.filterScrollRightBtn then
        self.filterScrollRightBtn:setVisible(false)
    end

    self.filterScrollOffset = 0
end

function BurdJournals.UI.MainPanel:passesFilter(modSource)
    local currentTab = self.currentTab or "skills"
    if not self.filterState or not self.filterState[currentTab] then
        return true
    end

    local currentFilter = self.filterState[currentTab].current or "all"
    if currentFilter == "all" then
        return true
    end

    local normalizedSource = nil
    if BurdJournals.normalizeFilterSourceId then
        normalizedSource = BurdJournals.normalizeFilterSourceId(modSource)
    else
        normalizedSource = string.lower(modSource or "Vanilla")
    end
    return normalizedSource == currentFilter
end

function BurdJournals.UI.MainPanel:refreshCurrentList()
    self:rememberListSelection()

    if self.mode == "log" then
        self:populateRecordList(self:resolvePendingRecordJournalDataForRefresh())
    elseif self.mode == "view" then
        self:populateViewList()
    elseif self.mode == "absorb" then
        self:populateAbsorptionList()
    end

    self:ensureListSelection(self.listFocusActive)
    self:rebuildJoypadRows()
end

function BurdJournals.UI.MainPanel:getHeaderJournalUUID()
    if self.mode ~= "log" and self.mode ~= "view" and self.mode ~= "absorb" then
        return nil
    end
    if not self.journal then
        return nil
    end

    local journalData = BurdJournals.getJournalData and BurdJournals.getJournalData(self.journal) or nil
    if type(journalData) ~= "table" then
        return nil
    end

    local uuid = tostring(BurdJournals.getJournalIdentityUUID(journalData) or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if uuid == "" then
        return nil
    end
    return uuid
end

local function getLocalizedHeaderText(key, fallback)
    local value = getText and getText(key) or nil
    if not value or value == key then
        return fallback
    end
    return value
end

function BurdJournals.UI.MainPanel:updateHeaderUUIDTooltip()
    local uuid = self:getHeaderJournalUUID()
    self.headerJournalUUID = uuid

    local tooltipTemplate = getText("UI_BurdJournals_UUIDTooltip") or "Journal UUID: %s"
    local tooltip = uuid and BurdJournals.formatText(tooltipTemplate, uuid) or nil

    if self.headerUuidBadgeBtn then
        self.headerUuidBadgeBtn.tooltip = tooltip
        self.headerUuidBadgeBtn:setVisible(uuid ~= nil)
    end

    self:rebuildJoypadRows()
end

function BurdJournals.UI.MainPanel:onHeaderCopyUUID()
    local uuid = self.headerJournalUUID or self:getHeaderJournalUUID()
    if not uuid then
        self:showFeedback(getText("UI_BurdJournals_UUIDMissing") or "No journal UUID available", {r=1, g=0.6, b=0.3})
        return
    end

    local copied = false
    uuid = tostring(uuid)
    if Clipboard and Clipboard.setClipboard then
        Clipboard.setClipboard(uuid)
        copied = true
    end

    if not copied then
        local core = getCore and getCore() or nil
        if core and core.setClipboard then
            core:setClipboard(uuid)
            copied = true
        end
    end

    if copied then
        self:showFeedback(getText("UI_BurdJournals_UUIDCopied") or "Journal UUID copied", {r=0.3, g=1, b=0.5})
    else
        local fallbackTemplate = getText("UI_BurdJournals_UUIDCopyUnavailable") or "Clipboard unavailable. UUID: %s"
        self:showFeedback(BurdJournals.formatText(fallbackTemplate, uuid), {r=0.95, g=0.8, b=0.35})
    end
end

function BurdJournals.UI.MainPanel:getHeaderJournalStateInfo()
    if self.mode ~= "log" and self.mode ~= "view" then
        return nil
    end
    if not self.journal then
        return nil
    end

    local journalData = BurdJournals.getJournalData and BurdJournals.getJournalData(self.journal) or nil
    if type(journalData) ~= "table" then
        return nil
    end

    local isPlayerJournal = journalData.isPlayerCreated == true
    if not isPlayerJournal and journalData.isPlayerCreated == nil then
        local hasOwner = journalData.ownerUsername or journalData.ownerSteamId or journalData.ownerCharacterName
        if hasOwner and journalData.isWorn ~= true and journalData.isBloody ~= true then
            isPlayerJournal = true
        end
    end

    if not isPlayerJournal then
        return nil
    end

    local isRestored = BurdJournals.isRestoredJournalData and BurdJournals.isRestoredJournalData(journalData) or false
    local allowDissolution = BurdJournals.getSandboxOption and BurdJournals.getSandboxOption("AllowPlayerJournalDissolution") == true

    if isRestored then
        local tooltipKey = allowDissolution
            and "UI_BurdJournals_BadgeStateTooltipRestoredDissolveOn"
            or "UI_BurdJournals_BadgeStateTooltipRestoredDissolveOff"
        local tooltipFallback = allowDissolution
            and "Restored journal: One-time claims are enabled and this journal auto-dissolves after all rewards are claimed."
            or "Restored journal (persistent mode): 'Allow Player Journal Dissolution' is OFF, so rewards are reusable and this journal does not auto-dissolve."
        return {
            label = getLocalizedHeaderText("UI_BurdJournals_BadgeRestored", "RESTORED"),
            tooltip = getLocalizedHeaderText(tooltipKey, tooltipFallback),
            borderColor = {r=0.60, g=0.45, b=0.22, a=1},
            backgroundColor = {r=0.36, g=0.26, b=0.10, a=0.85},
            textColor = {r=1, g=0.93, b=0.78, a=1},
        }
    end

    return {
        label = getLocalizedHeaderText("UI_BurdJournals_BadgePersistent", "PERSISTENT"),
        tooltip = getLocalizedHeaderText(
            "UI_BurdJournals_BadgeStateTooltipPersistent",
            "Persistent journal: Rewards are reusable and this journal does not auto-dissolve."
        ),
        borderColor = {r=0.22, g=0.58, b=0.70, a=1},
        backgroundColor = {r=0.10, g=0.27, b=0.35, a=0.85},
        textColor = {r=0.86, g=0.98, b=1, a=1},
    }
end

function BurdJournals.UI.MainPanel:onHeaderStateBadge()
    -- Intentionally no-op: badge exists for quick status and tooltip visibility.
end

function BurdJournals.UI.MainPanel:createHeaderRefreshButton(rightMargin, y)
    local function removeControl(control)
        if not control then return end
        if self.removeChild then
            self:removeChild(control)
        end
        if control.removeFromUIManager then
            control:removeFromUIManager()
        end
    end

    removeControl(self.headerRefreshBtn)
    removeControl(self.headerCopyUuidBtn)
    removeControl(self.headerUuidBadgeBtn)
    removeControl(self.headerStateBadgeBtn)
    self.headerRefreshBtn = nil
    self.headerCopyUuidBtn = nil
    self.headerUuidBadgeBtn = nil
    self.headerStateBadgeBtn = nil

    -- Backward cleanup for any stale controls left behind by older UI builds.
    if self.children and type(self.children) == "table" then
        for i = #self.children, 1, -1 do
            local child = self.children[i]
            if child and child.bsjHeaderControl then
                removeControl(child)
            end
        end
    end

    local margin = tonumber(rightMargin) or 10
    local btnY = tonumber(y) or 15
    local refreshText = getText("UI_BurdJournals_BtnRefresh") or "Refresh"
    local refreshW = math.max(64, getTextManager():MeasureStringX(UIFont.Small, refreshText) + 14)
    local refreshH = 22
    local refreshX = self.width - margin - refreshW

    -- Derive button colors from the journal's header theme so Worn & Bloody panels
    -- get colors that match their red/brown identity instead of the default blue.
    local accent = self.headerAccent
    local btnColors
    if accent then
        -- Scale the accent color: border uses full accent, bg is darker, text is near-white tinted
        btnColors = {
            border      = {r=accent.r,           g=accent.g,           b=accent.b,           a=1},
            background  = {r=accent.r * 0.35,    g=accent.g * 0.35,    b=accent.b * 0.35,    a=0.85},
            text        = {r=0.95 + accent.r * 0.05, g=0.9 + accent.g * 0.05, b=0.9 + accent.b * 0.05, a=1},
        }
    else
        -- Default blue theme (player journals)
        btnColors = {
            border      = {r=0.35, g=0.55, b=0.7,  a=1},
            background  = {r=0.12, g=0.26, b=0.34, a=0.85},
            text        = {r=0.9,  g=0.98, b=1,    a=1},
        }
    end

    self.headerRefreshBtn = ISButton:new(refreshX, btnY, refreshW, refreshH, refreshText, self, BurdJournals.UI.MainPanel.onHeaderRefresh)
    self.headerRefreshBtn:initialise()
    self.headerRefreshBtn:instantiate()
    self.headerRefreshBtn.font = UIFont.Small
    self.headerRefreshBtn.borderColor = btnColors.border
    self.headerRefreshBtn.backgroundColor = btnColors.background
    self.headerRefreshBtn.textColor = btnColors.text
    self.headerRefreshBtn.tooltip = getText("UI_BurdJournals_RefreshTooltip") or "Refresh journal data"
    self.headerRefreshBtn.bsjHeaderControl = true
    self:addChild(self.headerRefreshBtn)

    local spacing = 6
    local cursorX = refreshX - spacing
    local consumed = refreshW + 12

    local uuid = self:getHeaderJournalUUID()
    if uuid then
        local badgeText = getText("UI_BurdJournals_UUIDBadge") or "UUID"

        local badgeW = math.max(42, getTextManager():MeasureStringX(UIFont.Small, badgeText) + 16)
        local badgeX = cursorX - badgeW
        self.headerUuidBadgeBtn = ISButton:new(badgeX, btnY, badgeW, refreshH, badgeText, self, BurdJournals.UI.MainPanel.onHeaderCopyUUID)
        self.headerUuidBadgeBtn:initialise()
        self.headerUuidBadgeBtn:instantiate()
        self.headerUuidBadgeBtn.font = UIFont.Small
        self.headerUuidBadgeBtn.borderColor = btnColors.border
        self.headerUuidBadgeBtn.backgroundColor = btnColors.background
        self.headerUuidBadgeBtn.textColor = btnColors.text
        self.headerUuidBadgeBtn.bsjHeaderControl = true
        self:addChild(self.headerUuidBadgeBtn)

        cursorX = badgeX - spacing
        consumed = consumed + badgeW + spacing
    end

    local stateInfo = self:getHeaderJournalStateInfo()
    if stateInfo and stateInfo.label then
        local stateW = math.max(78, getTextManager():MeasureStringX(UIFont.Small, stateInfo.label) + 18)
        local stateX = cursorX - stateW
        self.headerStateBadgeBtn = ISButton:new(stateX, btnY, stateW, refreshH, stateInfo.label, self, BurdJournals.UI.MainPanel.onHeaderStateBadge)
        self.headerStateBadgeBtn:initialise()
        self.headerStateBadgeBtn:instantiate()
        self.headerStateBadgeBtn.font = UIFont.Small
        self.headerStateBadgeBtn.borderColor = stateInfo.borderColor or {r=0.25, g=0.55, b=0.7, a=1}
        self.headerStateBadgeBtn.backgroundColor = stateInfo.backgroundColor or {r=0.10, g=0.26, b=0.34, a=0.85}
        self.headerStateBadgeBtn.textColor = stateInfo.textColor or {r=0.9, g=0.98, b=1, a=1}
        self.headerStateBadgeBtn.tooltip = stateInfo.tooltip
        self.headerStateBadgeBtn.bsjHeaderControl = true
        self:addChild(self.headerStateBadgeBtn)

        consumed = consumed + stateW + spacing
    end

    local inset = consumed + 8
    self.headerRightInset = inset
    self:updateHeaderUUIDTooltip()
    return margin + inset
end

function BurdJournals.UI.MainPanel:onHeaderRefresh()
    self:refreshPlayer()

    -- Match close/reopen behavior: clear transient UI session state.
    self.pendingClaims = {skills = {}, traits = {}, recipes = {}, stats = {}}
    self.sessionClaimedSkills = {}
    self.sessionClaimedSkillTargets = {}
    self.sessionClaimedTraits = {}
    self.sessionClaimedRecipes = {}
    self.sessionClaimedStats = {}
    if self.learningState then
        self.learningState.claimSessionId = nil
    end

    if self.journal then
        if BurdJournals.clientShouldUseServerAuthority() then
            if BurdJournals.Client and BurdJournals.Client.sendToServer then
                local journalData = BurdJournals.getJournalData and BurdJournals.getJournalData(self.journal) or nil
                local lookupArgs = BurdJournals.buildJournalCommandLookupArgs
                    and BurdJournals.buildJournalCommandLookupArgs(self.journal, journalData, true)
                    or { journalId = self.journal:getID(), journalUUID = nil, journalFingerprint = nil }
                if BurdJournals.Client.sendSanitizeJournalRequest then
                    BurdJournals.Client.sendSanitizeJournalRequest(self.journal, self.player)
                else
                    BurdJournals.Client.sendToServer("sanitizeJournal", {
                        journalId = lookupArgs.journalId,
                        journalUUID = lookupArgs.journalUUID,
                        journalFingerprint = lookupArgs.journalFingerprint,
                        journalData = nil,
                    })
                end
                BurdJournals.Client.sendToServer("requestXpSync", {})
            end
        else
            if BurdJournals.sanitizeJournalData then
                BurdJournals.sanitizeJournalData(self.journal, self.player)
            end
            if BurdJournals.migrateJournalIfNeeded then
                BurdJournals.migrateJournalIfNeeded(self.journal, self.player)
            end
            if BurdJournals.compactJournalData then
                BurdJournals.compactJournalData(self.journal)
            end
            if self.journal.transmitModData
                and (not BurdJournals.shouldTransmitJournalItemModData
                    or BurdJournals.shouldTransmitJournalItemModData(self.journal, "mainPanelManualRefresh"))
            then
                self.journal:transmitModData()
            end
        end
    end

    if self.refreshJournalData then
        self:refreshJournalData()
    else
        self:refreshCurrentList()
    end

    self:scheduleDeferredRefreshPasses({ singlePass = true })

    self:showFeedback(getText("UI_BurdJournals_JournalRefreshed") or "Journal refreshed", {r=0.5, g=0.8, b=1})
end

-- Force a full list rebuild by cycling tabs the same way manual tab switching does.
-- This mirrors the user-discovered "switch tabs to refresh correctly" behavior.
function BurdJournals.UI.MainPanel:forceCurrentTabRebuild()
    if not self.tabs or #self.tabs <= 1 then
        if self.refreshCurrentList then
            self:refreshCurrentList()
        end
        return
    end

    local originalTab = self.currentTab or (self.tabs[1] and self.tabs[1].id)
    if not originalTab then
        return
    end

    local altTab = nil
    for _, tab in ipairs(self.tabs) do
        if tab.id ~= originalTab then
            altTab = tab.id
            break
        end
    end

    if not altTab then
        if self.refreshCurrentList then
            self:refreshCurrentList()
        end
        return
    end

    self.currentTab = altTab
    if self.updateTabStyles then self:updateTabStyles() end
    if self.rebuildFilterTabBar then self:rebuildFilterTabBar() end
    if self.refreshCurrentList then self:refreshCurrentList() end

    self.currentTab = originalTab
    if self.updateTabStyles then self:updateTabStyles() end
    if self.rebuildFilterTabBar then self:rebuildFilterTabBar() end
    if self.refreshCurrentList then self:refreshCurrentList() end
end

function BurdJournals.UI.MainPanel:scheduleDeferredRefreshPasses(options)
    if self._headerRefreshTickHandler then
        BurdJournals.safeRemoveEvent(Events.OnTick, self._headerRefreshTickHandler)
        self._headerRefreshTickHandler = nil
    end

    options = type(options) == "table" and options or {}
    local panelRef = self
    local ticks = 0
    local nextCheckpointIndex = 1
    local checkpoints = options.singlePass == true and {6} or {6, 18}
    local function delayedRefresh()
        ticks = ticks + 1
        if not panelRef or not panelRef:getIsVisible() then
            BurdJournals.safeRemoveEvent(Events.OnTick, delayedRefresh)
            if panelRef then
                panelRef._headerRefreshTickHandler = nil
            end
            return
        end
        if ticks >= checkpoints[nextCheckpointIndex] then
            if panelRef.refreshJournalData then
                panelRef:refreshJournalData()
            else
                panelRef:refreshCurrentList()
            end
            nextCheckpointIndex = nextCheckpointIndex + 1
            if nextCheckpointIndex > #checkpoints then
                BurdJournals.safeRemoveEvent(Events.OnTick, delayedRefresh)
                panelRef._headerRefreshTickHandler = nil
            end
        end
    end

    self._headerRefreshTickHandler = delayedRefresh
    Events.OnTick.Add(delayedRefresh)
end

local function revealLootRewardsLocallyForOpenPanel(panel)
    if not (panel and panel.journal and panel.mode == "absorb") then
        return false
    end
    local journalData = nil
    if panel.journal and panel.journal.getModData then
        local modData = panel.journal:getModData()
        journalData = (BurdJournals.getJournalData and BurdJournals.getJournalData(panel.journal))
            or (modData and modData.BurdJournals)
            or nil
        if type(journalData) ~= "table" and journalData ~= nil and BurdJournals.normalizeTable then
            local normalized = BurdJournals.normalizeTable(journalData)
            if type(normalized) == "table" and modData then
                modData.BurdJournals = normalized
                journalData = normalized
            end
        end
    end
    if type(journalData) ~= "table" or journalData.isPlayerCreated == true or journalData.lootRewardsRevealed == true then
        return false
    end
    if BurdJournals.resolveJournalUUIDForRuntime then
        BurdJournals.resolveJournalUUIDForRuntime(journalData, panel.journal, false)
    end
    journalData.lootRewardsRevealed = true
    local revealName = nil
    if panel.player then
        revealName = (panel.player.getDisplayName and panel.player:getDisplayName())
            or (panel.player.getUsername and panel.player:getUsername())
            or nil
    end
    if revealName and revealName ~= "" then
        journalData.lootRewardsRevealedByName = revealName
    end
    if getGameTime and getGameTime() and getGameTime().getWorldAgeHours then
        journalData.lootRewardsRevealedAtHours = getGameTime():getWorldAgeHours()
    end
    if BurdJournals.Client and BurdJournals.Client.markLootRewardRevealedLocally then
        BurdJournals.Client.markLootRewardRevealedLocally(panel.journal, journalData)
    end
    if (not isClient() or isServer())
        and panel.journal.transmitModData
        and (not BurdJournals.shouldTransmitJournalItemModData
            or BurdJournals.shouldTransmitJournalItemModData(panel.journal, "mainPanelRevealLootRewards"))
    then
        panel.journal:transmitModData()
    end
    if BurdJournals.updateJournalName then
        BurdJournals.updateJournalName(panel.journal, true)
    end
    if BurdJournals.updateJournalIcon then
        BurdJournals.updateJournalIcon(panel.journal)
    end
    local container = panel.journal.getContainer and panel.journal:getContainer() or nil
    if container and container.setDrawDirty then
        BurdJournals.safePcall(function()
            container:setDrawDirty(true)
        end)
    end
    return true
end

local shouldHydrateOffloadedJournalOnOpen

local function safeTransmitPanelJournalModData(journal, sourceTag)
    if not (journal and journal.transmitModData) then
        return false
    end
    if BurdJournals.shouldTransmitJournalItemModData
        and not BurdJournals.shouldTransmitJournalItemModData(journal, sourceTag or "mainPanel")
    then
        return false
    end
    journal:transmitModData()
    return true
end

function BurdJournals.UI.MainPanel:createChildren()
    ISPanelJoypad.createChildren(self)
    
    -- Register this panel for baseline change notifications
    self:registerOpenPanel()

    -- In MP, request server to sanitize the journal (server-authoritative)
    -- In SP/host, sanitize directly
    if self.journal then
        revealLootRewardsLocallyForOpenPanel(self)
        if BurdJournals.clientShouldUseServerAuthority() then
            -- MP: Request server to sanitize and check dissolution
            if BurdJournals.Client and BurdJournals.Client.sendToServer then
                local journalData = BurdJournals.getJournalData and BurdJournals.getJournalData(self.journal) or nil
                local lookupArgs = BurdJournals.buildJournalCommandLookupArgs
                    and BurdJournals.buildJournalCommandLookupArgs(self.journal, journalData, true)
                    or { journalId = self.journal:getID(), journalUUID = nil, journalFingerprint = nil }
                if BurdJournals.Client.sendSanitizeJournalRequest then
                    BurdJournals.Client.sendSanitizeJournalRequest(self.journal, self.player)
                else
                    BurdJournals.Client.sendToServer("sanitizeJournal", {
                        journalId = lookupArgs.journalId,
                        journalUUID = lookupArgs.journalUUID,
                        journalFingerprint = lookupArgs.journalFingerprint,
                        journalData = nil,
                    })
                end
                -- Keep any filled-journal open in sync with deferred UUID edits and update server UUID index/cache.
                -- sanitizeJournal returns the authoritative sync payload.
            end
            -- Server will send back result if journal was dissolved
        else
            -- SP/host: Sanitize directly
            if BurdJournals.sanitizeJournalData then
                local sanitizeResult = BurdJournals.sanitizeJournalData(self.journal, self.player)
                if sanitizeResult and sanitizeResult.cleaned then
                    BurdJournals.debugPrint("[BurdJournals] MainPanel: Journal sanitized on open")
                    -- Transmit changes in SP/host
                    safeTransmitPanelJournalModData(self.journal, "mainPanelCurrentJournal")
                end
            end
        end

        -- Run migration if needed
        if BurdJournals.migrateJournalIfNeeded then
            -- In MP, migration should also go through server
            if BurdJournals.clientShouldUseServerAuthority() then
                -- Server handles migration during sanitize command
            else
                BurdJournals.migrateJournalIfNeeded(self.journal, self.player)
            end
        end

        -- SP/host patch safety: restore DR counters if item ModData lost them during update.
        if not (BurdJournals.clientShouldUseServerAuthority()) and BurdJournals.restoreJournalDRStateIfMissing then
            BurdJournals.restoreJournalDRStateIfMissing(self.journal, "mainPanelCreate", self.player)
        end
        if not (BurdJournals.clientShouldUseServerAuthority()) and BurdJournals.captureJournalDRState then
            BurdJournals.captureJournalDRState(self.journal, "mainPanelCreateSeed", self.player)
        end
    end

    self:playSound(BurdJournals.Sounds.OPEN_JOURNAL)

    if self.mode == "absorb" then
        self:createAbsorptionUI()
    elseif self.mode == "log" then
        self:createLogUI()
    else
        self:createViewUI()
    end

    -- syncSuccess starts entry chunks when the authoritative response omits them.

    if self.mode == "log" then
        if BurdJournals.clientShouldUseServerAuthority() then
            if BurdJournals.Client and BurdJournals.Client.sendToServer then
                BurdJournals.Client.sendToServer("requestXpSync", {})
            end
        end

        if self.forceCurrentTabRebuild then
            self:forceCurrentTabRebuild()
        elseif self.refreshCurrentList then
            self:refreshCurrentList()
        end

        if self.scheduleDeferredRefreshPasses then
            self:scheduleDeferredRefreshPasses()
        end
    end
end

function BurdJournals.UI.MainPanel:refreshPlayer()
    local previousPlayer = self.player
    local freshPlayer = getSpecificPlayer(self.playerNum)
    if freshPlayer then
        self.player = freshPlayer
    end
    if self.player ~= previousPlayer then
        self._hasEraserCache = nil
        self._hasEraserCacheAt = nil
        self._hasEraserCachePlayer = nil
    end
end

function BurdJournals.UI.MainPanel:hasCachedEraser()
    if not self.player then
        return false
    end

    local now = getTimestampMs and getTimestampMs() or 0
    local cacheAgeMs = 250
    if self._hasEraserCache ~= nil and self._hasEraserCachePlayer == self.player then
        local cachedAt = tonumber(self._hasEraserCacheAt) or 0
        if now == 0 or cachedAt == 0 or (now - cachedAt) <= cacheAgeMs then
            return self._hasEraserCache == true
        end
    end

    self._hasEraserCache = BurdJournals.hasEraser(self.player) == true
    self._hasEraserCacheAt = now
    self._hasEraserCachePlayer = self.player
    return self._hasEraserCache
end

function BurdJournals.UI.MainPanel:ensureDebugJournalDataRestored()
    if not self.journal then return end

    local journalData = BurdJournals.getJournalData(self.journal)
    if not journalData then return end

    local isDebugJournal = journalData.isDebugSpawned or journalData.isDebugEdited
    if not isDebugJournal then
        self._pendingDebugRestoreKey = nil
        return
    end

    local hasData = BurdJournals.hasAnyEntries(journalData.skills)
        or BurdJournals.hasAnyEntries(journalData.traits)
        or BurdJournals.hasAnyEntries(journalData.recipes)
        or BurdJournals.hasAnyEntries(journalData.stats)

    if hasData then
        self._pendingDebugRestoreKey = nil
        return
    end

    local journalKey = BurdJournals.getJournalIdentityUUID(journalData) or tostring(self.journal:getID())
    if not journalKey then return end

    if self._pendingDebugRestoreKey and BurdJournals.Client and not BurdJournals.Client._pendingDebugJournalRestore then
        self._pendingDebugRestoreKey = nil
    end
    if self._pendingDebugRestoreKey == journalKey then return end

    if BurdJournals.Client and BurdJournals.Client.requestDebugJournalBackup then
        self._pendingDebugRestoreKey = journalKey
        BurdJournals.Client.requestDebugJournalBackup(self.journal, journalKey)
        BurdJournals.debugPrint("[BurdJournals] MainPanel: requested debug journal restore for key=" .. tostring(journalKey))
    end
end

local function journalDataHasRecordedEntries(journalData)
    if type(journalData) ~= "table" then
        return false
    end
    return (BurdJournals.hasAnyEntries and BurdJournals.hasAnyEntries(journalData.skills))
        or (BurdJournals.hasAnyEntries and BurdJournals.hasAnyEntries(journalData.traits))
        or (BurdJournals.hasAnyEntries and BurdJournals.hasAnyEntries(journalData.recipes))
        or (BurdJournals.hasAnyEntries and BurdJournals.hasAnyEntries(journalData.stats))
        or false
end

local function journalDataHasStoredEntryManifest(journalData)
    if type(journalData) ~= "table" or journalData.entryStoreEnabled ~= true then
        return false
    end
    if type(journalData.entryStoreEntryCounts) ~= "table" then
        return true
    end
    for _, bucketName in ipairs(BurdJournals.ENTRY_STORE_BUCKETS or {"skills", "traits", "stats", "recipes"}) do
        if math.max(0, tonumber(journalData.entryStoreEntryCounts[bucketName]) or 0) > 0 then
            return true
        end
    end
    return false
end

local function getStoredJournalEntryCount(journalData, bucketName)
    if type(journalData) ~= "table" or type(journalData.entryStoreEntryCounts) ~= "table" then
        return 0
    end
    return math.max(0, tonumber(journalData.entryStoreEntryCounts[bucketName]) or 0)
end

shouldHydrateOffloadedJournalOnOpen = function(journalData)
    if journalDataHasRecordedEntries(journalData) then
        return false
    end
    if journalDataHasStoredEntryManifest(journalData) then
        return true
    end
    return false
end

local function isJournalAuthorityRequestPending(journal, journalData)
    return BurdJournals.Client
        and BurdJournals.Client.isJournalAuthorityRequestPending
        and BurdJournals.Client.isJournalAuthorityRequestPending(journal, journalData)
        or false
end

local function shouldWaitForAuthoritativePlayerJournalData(journalData, hasAuthoritativeData, journal)
    if hasAuthoritativeData == true
        or not (BurdJournals.clientShouldUseServerAuthority and BurdJournals.clientShouldUseServerAuthority())
    then
        return false
    end
    return type(journalData) == "table"
        and journalData.isPlayerCreated == true
        and journalData.isWritten == true
        and BurdJournals.getJournalIdentityUUID(journalData) ~= nil
        and isJournalAuthorityRequestPending(journal, journalData)
end

local function getHydratedSnapshotForEmptyLiveJournal(journal, liveData)
    if journalDataHasRecordedEntries(liveData) then
        return nil
    end
    if not (BurdJournals.Client and BurdJournals.Client.getHydratedJournalSnapshot) then
        return nil
    end
    local lookupUUID = BurdJournals.getJournalIdentityUUID(liveData)
    local snapshot = BurdJournals.Client.getHydratedJournalSnapshot(journal, lookupUUID)
    if journalDataHasRecordedEntries(snapshot) then
        return snapshot
    end
    return nil
end

local function pendingRecordSetSatisfied(liveSet, pendingSet, kind)
    if type(pendingSet) ~= "table" or not (BurdJournals.hasAnyEntries and BurdJournals.hasAnyEntries(pendingSet)) then
        return true
    end
    if type(liveSet) ~= "table" then
        return false
    end

    for key, pendingValue in pairs(pendingSet) do
        local liveValue = liveSet[key]
        if liveValue == nil and type(key) == "string" then
            liveValue = liveSet[string.lower(key)]
        end
        if liveValue == nil then
            return false
        end

        if kind == "skills" then
            local pendingXP = type(pendingValue) == "table" and tonumber(pendingValue.xp) or tonumber(pendingValue)
            local liveXP = type(liveValue) == "table" and tonumber(liveValue.xp) or tonumber(liveValue)
            if pendingXP ~= nil and (liveXP == nil or liveXP < pendingXP) then
                return false
            end

            local pendingLevel = type(pendingValue) == "table" and tonumber(pendingValue.level) or nil
            local liveLevel = type(liveValue) == "table" and tonumber(liveValue.level) or nil
            if pendingLevel ~= nil and (liveLevel == nil or liveLevel < pendingLevel) then
                return false
            end
        elseif kind == "stats" then
            local pendingStatValue = type(pendingValue) == "table" and pendingValue.value or pendingValue
            local liveStatValue = type(liveValue) == "table" and liveValue.value or liveValue
            if pendingStatValue ~= nil and liveStatValue == nil then
                return false
            end
        end
    end

    return true
end

function BurdJournals.UI.MainPanel:shouldRetainPendingRecordJournalData(journal, pendingData)
    if type(pendingData) ~= "table" then
        return false
    end

    if not journal then
        return true
    end

    local liveData = BurdJournals.getJournalData and BurdJournals.getJournalData(journal) or nil
    if type(liveData) ~= "table" then
        return true
    end

    local pendingUUID = BurdJournals.getJournalIdentityUUID(pendingData)
    local liveUUID = BurdJournals.getJournalIdentityUUID(liveData)
    if pendingUUID and liveUUID and tostring(pendingUUID) ~= tostring(liveUUID) then
        -- This is a different journal, not a delayed projection of the current
        -- one. Blank -> Filled materialization preserves UUID, so retaining a
        -- mismatched snapshot can only leak one journal's rows into another.
        return false
    end

    local pendingJournalId = self.pendingNewJournalId
    if pendingJournalId ~= nil then
        local liveJournalId = journal.getID and journal:getID() or nil
        if liveJournalId == nil or tostring(liveJournalId) ~= tostring(pendingJournalId) then return true end
    end

    if journalDataHasRecordedEntries(pendingData) and not journalDataHasRecordedEntries(liveData) then
        return true
    end
    if journalDataHasRecordedEntries(pendingData) and liveData.entryStoreEnabled == true then
        return true
    end
    if not pendingRecordSetSatisfied(liveData.skills, pendingData.skills, "skills") then
        return true
    end
    if not pendingRecordSetSatisfied(liveData.traits, pendingData.traits, "traits") then
        return true
    end
    if not pendingRecordSetSatisfied(liveData.recipes, pendingData.recipes, "recipes") then
        return true
    end
    if not pendingRecordSetSatisfied(liveData.stats, pendingData.stats, "stats") then
        return true
    end

    return false
end

function BurdJournals.UI.MainPanel:resolvePendingRecordJournalDataForRefresh()
    local pendingData = type(self.pendingRecordJournalData) == "table"
        and (BurdJournals.normalizeJournalData and BurdJournals.normalizeJournalData(self.pendingRecordJournalData) or self.pendingRecordJournalData)
        or nil

    if pendingData and self.journal and BurdJournals.getJournalData then
        local liveIdentityData = BurdJournals.getJournalData(self.journal)
        local pendingUUID = BurdJournals.getJournalIdentityUUID(pendingData)
        local liveUUID = BurdJournals.getJournalIdentityUUID(liveIdentityData)
        if pendingUUID and liveUUID and tostring(pendingUUID) ~= tostring(liveUUID) then
            self.pendingNewJournalId = nil
            self.pendingRecordJournalData = nil
            pendingData = nil
        end
    end

    if not pendingData then
        local liveData = self.journal and BurdJournals.getJournalData and BurdJournals.getJournalData(self.journal) or nil
        local liveSnapshot = getHydratedSnapshotForEmptyLiveJournal(self.journal, liveData)
        if liveSnapshot then
            self.pendingRecordJournalData = liveSnapshot
            return liveSnapshot
        end
        if shouldHydrateOffloadedJournalOnOpen(liveData)
            and BurdJournals.Client
            and BurdJournals.Client.getHydratedJournalSnapshot
        then
            local snapshot = BurdJournals.Client.getHydratedJournalSnapshot(self.journal, BurdJournals.getJournalIdentityUUID(liveData))
            if journalDataHasRecordedEntries(snapshot) then
                self.pendingRecordJournalData = snapshot
                return snapshot
            end
        end
        if self.pendingNewJournalId ~= nil and self.journal and self.journal.getID
            and tostring(self.journal:getID()) == tostring(self.pendingNewJournalId)
        then
            self.pendingNewJournalId = nil
        end
        self.pendingRecordJournalData = nil
        return nil
    end

    self.pendingRecordJournalData = pendingData

    local shouldRetain = self:shouldRetainPendingRecordJournalData(self.journal, pendingData)
    if shouldRetain
        and self.journal
        and BurdJournals.Client
        and BurdJournals.Client.projectAuthoritativeJournalDataToLocalItem
        and pendingData.entryStoreEnabled ~= true
    then
        BurdJournals.Client.projectAuthoritativeJournalDataToLocalItem(self.player, self.journal, pendingData)
        shouldRetain = self:shouldRetainPendingRecordJournalData(self.journal, pendingData)
    end

    if not shouldRetain
        and self.recordingState
        and self.recordingState.isRecordAll == true
    then
        shouldRetain = true
    end

    if not shouldRetain then
        self.pendingNewJournalId = nil
        self.pendingRecordJournalData = nil
        return nil
    end

    return pendingData
end

function BurdJournals.UI.MainPanel:findPendingNewJournalInInventory()
    if self.pendingNewJournalId == nil or not BurdJournals.findItemByIdInPlayerInventory then
        return nil
    end
    local candidate = BurdJournals.findItemByIdInPlayerInventory(self.player, self.pendingNewJournalId)
    if not candidate then return nil end

    local expectedData = type(self.pendingRecordJournalData) == "table" and self.pendingRecordJournalData
        or (self.journal and BurdJournals.getJournalData and BurdJournals.getJournalData(self.journal) or nil)
    local candidateData = BurdJournals.getJournalData and BurdJournals.getJournalData(candidate) or nil
    local expectedUUID = BurdJournals.getJournalIdentityUUID and BurdJournals.getJournalIdentityUUID(expectedData) or nil
    local candidateUUID = BurdJournals.getJournalIdentityUUID and BurdJournals.getJournalIdentityUUID(candidateData) or nil
    if expectedUUID and candidateUUID and tostring(expectedUUID) ~= tostring(candidateUUID) then
        return nil
    end
    return candidate
end

function BurdJournals.UI.MainPanel:refreshJournalData()

    self:refreshPlayer()
    self:ensureDebugJournalDataRestored()

    if self.pendingNewJournalId then
        BurdJournals.debugPrint("[BurdJournals] refreshJournalData: Checking for pending journal ID " .. tostring(self.pendingNewJournalId))
        local newJournal = self:findPendingNewJournalInInventory()
        if newJournal then
            BurdJournals.debugPrint("[BurdJournals] refreshJournalData: Found pending journal! Updating reference.")
            self.journal = newJournal
            self.pendingNewJournalId = nil
            self.pendingJournalCheckCounter = 0
        else
            BurdJournals.debugPrint("[BurdJournals] refreshJournalData: Pending journal still not found")
        end
    end

    if not self.journal or not self.journal:getContainer() then
        BurdJournals.debugPrint("[BurdJournals] refreshJournalData: Journal invalid, trying to find by ID")

        if self.pendingNewJournalId then
            local journal = self:findPendingNewJournalInInventory()
            if journal then
                self.journal = journal
            end
        end
    end

    local pendingRecordJournalData = self:resolvePendingRecordJournalDataForRefresh()
    if self.mode == "absorb" then
        applyAbsorptionPresentationState(self)
    end

    self:rememberListSelection()
    if self.mode == "log" then

        if self.skillList then
            if self.populateRecordList then
                self:populateRecordList(pendingRecordJournalData)
            end
        end
    elseif self.mode == "view" then

        if self.skillList then
            if self.populateViewList then
                self:populateViewList(pendingRecordJournalData)
            end
        end
    elseif self.mode == "absorb" then
        -- Note: the list is called skillList, not absorbList
        if self.skillList then
            if self.refreshAbsorptionList then
                self:refreshAbsorptionList()
            end
        end
    end

    self:ensureListSelection(self.listFocusActive)
    self:updateHeaderUUIDTooltip()
end

function BurdJournals.UI.MainPanel:isLimitedClaimLootJournal()
    if self.mode ~= "absorb" or not self.journal or not self.player then
        return false
    end
    return BurdJournals.isLimitedClaimLootJournalActive
        and BurdJournals.isLimitedClaimLootJournalActive(self.journal)
        or false
end

function BurdJournals.UI.MainPanel:getLimitedLootClaimsLeft()
    if not self:isLimitedClaimLootJournal() then
        return nil
    end
    return BurdJournals.getClaimsLeftBeforeDissolve
        and BurdJournals.getClaimsLeftBeforeDissolve(self.journal, self.player)
        or 0
end

function BurdJournals.UI.MainPanel:hasLimitedLootClaimAvailable()
    local claimsLeft = self:getLimitedLootClaimsLeft()
    if claimsLeft == nil then
        return true
    end
    if claimsLeft <= 0 then
        self:showFeedback(getText("UI_BurdJournals_LimitedLootClaimsSpent") or "This journal has no claims left.", "error")
        return false
    end
    return true
end

function BurdJournals.UI.MainPanel:shouldBlockLimitedLootQueue()
    if self:isLimitedClaimLootJournal() and self.learningState and self.learningState.active and not self.learningState.isAbsorbAll then
        self:showFeedback(getText("UI_BurdJournals_LimitedLootClaimsNoQueue") or "Finish the current claim before choosing another reward.", {r=0.9, g=0.72, b=0.45})
        return true
    end
    return false
end

function BurdJournals.UI.MainPanel:createAbsorptionUI()

    self:refreshPlayer()

    local padding = 16
    self.layoutPadding = padding
    local y = 0
    local btnHeight = 32

    local journalData = applyAbsorptionPresentationState(self)
    journalData = self:resolvePendingRecordJournalDataForRefresh() or journalData
    local isBloody = self.isBloody
    local hasBloodyOrigin = self.hasBloodyOrigin
    local isYuletideReward = self.isYuletideReward
    local isCursedReward = self.isCursedReward

    local headerHeight = 52
    self.headerRightInset = 0
    self.headerHeight = headerHeight
    self:createHeaderRefreshButton(10, 15)
    y = headerHeight + 6

    self.authorBoxY = y
    self.showClaimsLeftBeforeDissolved = self:isLimitedClaimLootJournal()
    refreshAbsorptionAuthorBoxLayout(self, padding)
    y = y + self.authorBoxHeight + 10

    local skillCount = 0
    local totalSkillCount = 0
    local traitCount = 0
    local totalTraitCount = 0
    local forgetCount = 0
    local totalForgetCount = 0
    local recipeCount = 0
    local totalRecipeCount = 0
    local totalXP = 0

    if journalData and journalData.skills then
        for skillName, skillData in pairs(journalData.skills) do
            if BurdJournals.isSkillVisibleForJournal(journalData, skillName) then
                totalSkillCount = totalSkillCount + 1
                if not BurdJournals.hasCharacterClaimedSkill(journalData, self.player, skillName) then
                    skillCount = skillCount + 1
                    totalXP = totalXP + (skillData.xp or 0)
                end
            end
        end
    end
    if BurdJournals.hasTraitEntriesForJournal(journalData) then
        for traitId, _ in pairs(journalData.traits) do
            totalTraitCount = totalTraitCount + 1
            if not BurdJournals.hasCharacterClaimedTrait(journalData, self.player, traitId) then
                traitCount = traitCount + 1
            end
        end
    end
    local forgetSlotCount = journalData and BurdJournals.getForgetSlotCount and BurdJournals.getForgetSlotCount(journalData) or 0
    local hasForgetSlot = forgetSlotCount > 0
        and BurdJournals.isForgetSlotEnabledForJournal
        and BurdJournals.isForgetSlotEnabledForJournal(journalData)
    local claimedForgetSlots = hasForgetSlot
        and BurdJournals.getCharacterClaimedForgetSlotCount
        and BurdJournals.getCharacterClaimedForgetSlotCount(journalData, self.player)
        or 0
    local remainingForgetSlots = hasForgetSlot and math.max(0, forgetSlotCount - claimedForgetSlots) or 0
    if remainingForgetSlots > 0 then
        local removableTraits = BurdJournals.getPlayerRemovableTraits and BurdJournals.getPlayerRemovableTraits(self.player) or {}
        totalForgetCount = math.min(#removableTraits, remainingForgetSlots)
        forgetCount = totalForgetCount
    end
    if journalData and journalData.recipes then
        for recipeName, _ in pairs(journalData.recipes) do
            totalRecipeCount = totalRecipeCount + 1
            if not BurdJournals.hasCharacterClaimedRecipe(journalData, self.player, recipeName) then
                recipeCount = recipeCount + 1
            end
        end
    end

    self.skillCount = skillCount
    self.traitCount = traitCount
    self.forgetCount = forgetCount
    self.recipeCount = recipeCount
    self.totalXP = totalXP

    local tabs = {{id = "skills", label = getText("UI_BurdJournals_TabSkills")}}
    -- Check if this is a debug-spawned journal (bypasses origin restrictions)
    if totalTraitCount > 0 then
        table.insert(tabs, {id = "traits", label = getText("UI_BurdJournals_TabTraits")})
    end
    if remainingForgetSlots > 0 then
        local forgetColors = paletteColor(self.palette, "forgetTab")
        table.insert(tabs, {
            id = "forget",
            label = getText("UI_BurdJournals_TabForget") or "Forget",
            themeColors = forgetColors,
        })
    end
    if totalRecipeCount > 0 then
        table.insert(tabs, {id = "recipes", label = getText("UI_BurdJournals_TabRecipes")})
    end
    if shouldExposeLootNotesTab(journalData) then
        table.insert(tabs, {id = "notes", label = getText("UI_BurdJournals_TabNotes") or "Notes"})
    end

    local tabThemeColors
    if isYuletideReward or isCursedReward then
        tabThemeColors = {
            active = paletteColor(self.palette, "tabActive"),
            inactive = paletteColor(self.palette, "tabInactive"),
            accent = paletteColor(self.palette, "tabAccent"),
        }
    elseif isBloody then
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

    if #tabs > 1 then
        y = self:createTabs(tabs, y, tabThemeColors)
    end

    self.filterBaseY = y
    y = self:createFilterTabBar(y, tabThemeColors)

    local maxItemCount = math.max(totalSkillCount, totalTraitCount, totalForgetCount, totalRecipeCount)
    y = self:createSearchBar(y, tabThemeColors, maxItemCount)

    local footerHeight = 85
    local paginationHeight = BurdJournals.UI.LIST_PAGINATION_HEIGHT or 26
    local listHeight = self.height - y - footerHeight - paginationHeight - padding

    self.skillList = ISScrollingListBox:new(padding, y, self.width - padding * 2, listHeight)
    self.skillList:initialise()
    self.skillList:instantiate()
    self.skillList.drawBorder = false
    self.skillList.backgroundColor = {r=0, g=0, b=0, a=0}
    self.skillList:setFont(UIFont.Small, 2)
    self.skillList.itemheight = 52
    self.skillList.doDrawItem = BurdJournals.UI.MainPanel.doDrawAbsorptionItem
    self.skillList.mainPanel = self
    self.listBottomY = self.skillList:getY() + self.skillList:getHeight()

    self.skillList.onMouseUp = function(listbox, x, y)
        if listbox.vscroll then
            listbox.vscroll.scrolling = false
        end
        local row = listbox:rowAt(x, y)
        if row and row >= 1 and row <= #listbox.items then
            local item = listbox.items[row] and listbox.items[row].item
            if item and not item.isHeader and not item.isEmpty then

                local btnW = 55
                local margin = 10
                local claimBtnStart = listbox:getWidth() - btnW - margin

                if x >= claimBtnStart and not item.isClaimed then
                    listbox.mainPanel:performPrimaryListAction(item)
                end
            end
        end
        return true
    end
    self:wireSkillListJoypad()
    self:addChild(self.skillList)
    y = y + listHeight
    y = self:createPaginationControls(y, tabThemeColors)

    self.footerY = y + 4
    self.footerHeight = footerHeight

    self.feedbackLabel = ISLabel:new(padding, self.footerY + 4, 18, "", 0.7, 0.9, 0.7, 1, UIFont.Small, true)
    self:addChild(self.feedbackLabel)
    self.feedbackLabel:setVisible(false)
    self.feedbackTicks = 0

    local tabName = self:getTabDisplayName(self.currentTab or "skills")
    local absorbTabText = BurdJournals.formatText(getText("UI_BurdJournals_BtnAbsorbTab") or "Absorb %s", tabName)
    local absorbAllText = getText("UI_BurdJournals_BtnAbsorbAll") or "Absorb All"
    local dissolveText = getText("UI_BurdJournals_BtnDissolve") or "Dissolve"
    local closeText = getText("UI_BurdJournals_BtnClose") or "Close"

    local allTabNames = {
        getText("UI_BurdJournals_TabSkills") or "Skills",
        getText("UI_BurdJournals_TabTraits") or "Traits",
        getText("UI_BurdJournals_TabForget") or "Forget",
        getText("UI_BurdJournals_TabRecipes") or "Recipes",
        getText("UI_BurdJournals_TabStats") or "Stats",
        getText("UI_BurdJournals_TabNotes") or "Notes"
    }
    local btnPrefix = getText("UI_BurdJournals_BtnAbsorbTab") or "Absorb %s"
    local maxAbsorbTabW = 90
    for _, name in ipairs(allTabNames) do
        local text = BurdJournals.formatText(btnPrefix, name)
        local w = getTextManager():MeasureStringX(UIFont.Small, text) + 20
        maxAbsorbTabW = math.max(maxAbsorbTabW, w)
    end
    local absorbAllW = getTextManager():MeasureStringX(UIFont.Small, absorbAllText) + 20
    local dissolveW = getTextManager():MeasureStringX(UIFont.Small, dissolveText) + 20
    local closeW = getTextManager():MeasureStringX(UIFont.Small, closeText) + 20
    local btnWidth = math.max(90, maxAbsorbTabW, absorbAllW, dissolveW, closeW)

    -- Show dissolve button for loot-style one-shot journals, including
    -- registered add-on reward journals.
    local showDissolveBtn = BurdJournals.shouldShowDissolveButton
        and BurdJournals.shouldShowDissolveButton(self.journal, self.player)
        or false
    local showAbsorbAllBtn = not self:isLimitedClaimLootJournal()

    local btnSpacing = 12
    local numButtons = 2
    if showAbsorbAllBtn then
        numButtons = numButtons + 1
    end
    if showDissolveBtn then
        numButtons = numButtons + 1
    end
    local totalBtnWidth = btnWidth * numButtons + btnSpacing * (numButtons - 1)
    local btnStartX = (self.width - totalBtnWidth) / 2
    local btnY = self.footerY + 32

    self.absorbTabBtn = ISButton:new(btnStartX, btnY, btnWidth, btnHeight, absorbTabText, self, BurdJournals.UI.MainPanel.onAbsorbTab)
    self.absorbTabBtn:initialise()
    self.absorbTabBtn:instantiate()
    applyPaletteToButton(self.absorbTabBtn, self.palette, "absorbTabBtnBg", "absorbTabBtnBorder", nil)
    self.absorbTabBtn.textColor = {r=1, g=1, b=1, a=1}
    self:addChild(self.absorbTabBtn)

    local nextBtnIndex = 1
    if showAbsorbAllBtn then
        self.absorbAllBtn = ISButton:new(btnStartX + (btnWidth + btnSpacing) * 1, btnY, btnWidth, btnHeight, absorbAllText, self, BurdJournals.UI.MainPanel.onAbsorbAll)
        self.absorbAllBtn:initialise()
        self.absorbAllBtn:instantiate()
        applyPaletteToButton(self.absorbAllBtn, self.palette, "absorbAllBtnBg", "absorbAllBtnBorder", nil)
        self.absorbAllBtn.textColor = {r=1, g=1, b=1, a=1}
        self:addChild(self.absorbAllBtn)
        nextBtnIndex = 2
    end

    -- Add dissolve button for worn/bloody journals
    if showDissolveBtn then
        self.dissolveBtn = ISButton:new(btnStartX + (btnWidth + btnSpacing) * nextBtnIndex, btnY, btnWidth, btnHeight, dissolveText, self, BurdJournals.UI.MainPanel.onDissolveJournal)
        self.dissolveBtn:initialise()
        self.dissolveBtn:instantiate()
        applyPaletteToButton(self.dissolveBtn, self.palette, "dissolveBtnBg", "dissolveBtnBorder", "dissolveBtnText")
        self:addChild(self.dissolveBtn)
        nextBtnIndex = nextBtnIndex + 1
    end

    self.closeBottomBtn = ISButton:new(btnStartX + (btnWidth + btnSpacing) * nextBtnIndex, btnY, btnWidth, btnHeight, closeText, self, BurdJournals.UI.MainPanel.onClose)
    self.closeBottomBtn:initialise()
    self.closeBottomBtn:instantiate()
    applyPaletteToButton(self.closeBottomBtn, self.palette, "closeBtnBg", "closeBtnBorder", "closeBtnText")
    self:addChild(self.closeBottomBtn)

    self:populateAbsorptionList()
    self:rebuildJoypadRows()
end

-- Manual dissolve button handler for worn/bloody journals
function BurdJournals.UI.MainPanel:onDissolveJournal()
    if not self.journal then return end

    -- Show confirmation dialog
    local confirmText = getText("UI_BurdJournals_ConfirmDissolve") or "Are you sure you want to dissolve this journal? This cannot be undone."
    if BurdJournals.createAdaptiveModalDialog then
        BurdJournals.createAdaptiveModalDialog({
            player = self.player,
            target = self,
            text = confirmText,
            yesNo = true,
            onClick = BurdJournals.UI.MainPanel.onDissolveConfirm,
            minWidth = 360,
            maxWidth = 700,
            minHeight = 165,
        })
    else
        local modal = ISModalDialog:new(
            getCore():getScreenWidth() / 2 - 150,
            getCore():getScreenHeight() / 2 - 50,
            300, 100,
            confirmText,
            true,
            self,
            BurdJournals.UI.MainPanel.onDissolveConfirm
        )
        modal:initialise()
        modal:addToUIManager()
        if BurdJournals.applyJoypadSupportToModal then
            BurdJournals.applyJoypadSupportToModal(modal, self.player, {
                playerNum = self.playerNum,
                prevFocus = self,
            })
        end
    end
end

function BurdJournals.UI.MainPanel:onDissolveConfirm(button)
    if button.internal ~= "YES" then return end
    if not self.journal then return end

    local player = self.player
    local journal = self.journal

    -- Remove the journal
    local message = BurdJournals.getRandomDissolutionMessage and BurdJournals.getRandomDissolutionMessage() or "The journal crumbles to dust..."

    if BurdJournals.clientShouldUseServerAuthority() then
        -- In MP, send command to server to remove
        -- Keep dissolve UX consistent for all journals, including debug-spawned.
        BurdJournals.debugPrint("[BurdJournals] Dissolving via dissolveJournal")
        local journalData = BurdJournals.getJournalData and BurdJournals.getJournalData(journal) or nil
        local lookupArgs = BurdJournals.buildJournalCommandPayload
            and BurdJournals.buildJournalCommandPayload(journal, journalData, true)
            or {
                journalId = journal and journal.getID and journal:getID() or nil,
                journalUUID = type(journalData) == "table" and journalData.uuid or nil,
                journalFingerprint = nil,
                journalData = nil,
            }
        sendClientCommand(player, "BurdJournals", "dissolveJournal", {
            journalId = lookupArgs.journalId,
            journalUUID = lookupArgs.journalUUID,
            journalFingerprint = lookupArgs.journalFingerprint,
            journalData = lookupArgs.journalData,
        })
    else
        -- In SP, remove directly and show message
        local container = journal:getContainer()
        if container then
            container:Remove(journal)
        end
        -- Show speaking bubble for SP (MP gets this from server response)
        if player and player.Say then
            player:Say(message)
        end
    end

    -- Close the panel
    self:close()
end

function BurdJournals.UI.MainPanel:onAbsorbAll()
    if self:isLimitedClaimLootJournal() then
        self:showFeedback(getText("UI_BurdJournals_LimitedLootClaimsNoBatch") or "Batch absorb is disabled for limited-claim loot journals.", "warn")
        return
    end
    self:startLearningAll()
end

function BurdJournals.UI.MainPanel:onAbsorbTab()
    if (self.currentTab or "skills") == "forget" then
        self:showFeedback(
            getText("UI_BurdJournals_ForgetTabHint") or "Choose a trait in this tab to forget.",
            {r=0.9, g=0.72, b=0.45}
        )
        return
    end
    self:startLearningTab(self.currentTab or "skills")
end

function BurdJournals.UI.MainPanel:prerender()
    applyPendingListBoxScrollRestore(self)
    self:updateSkillDetailRowHeight()

    ISPanelJoypad.prerender(self)

    if self.searchPendingRefresh and self.searchEntry then
        self.searchPendingRefresh = false
        local currentText = self.searchEntry:getText() or ""
        if currentText ~= self.searchEntry.lastSearchText then
            self.searchEntry.lastSearchText = currentText
            if self.skillList then
                self.skillList.selected = -1
            end
            self.lastListSelectedIndex = nil
            self.lastListContextKey = nil
            self.searchQuery = currentText
            self:refreshCurrentList()
        end
    end

    if self.mode == "absorb" or self.mode == "view" or self.mode == "log" then
        self:prerenderJournalUI()
    end
end

function BurdJournals.UI.MainPanel:prerenderJournalUI()
    local padding = 16
    local pal = self.palette or getRewardPalette(self.rewardTheme)

    if self.rewardTheme == "yuletide" then
        drawAnimatedStripedJournalBackdrop(self, 0, 0, self.width, self.height, YULETIDE_PANEL_THEME, "journal_panel_backdrop")
    elseif self.rewardTheme == "cursed" then
        drawAnimatedCursedJournalBackdrop(self, 0, 0, self.width, self.height, CURSED_PANEL_THEME, "journal_panel_backdrop_cursed")
    elseif self.rewardTheme == "blessed" then
        drawAnimatedBlessedJournalBackdrop(self, 0, 0, self.width, self.height, pal, "journal_panel_backdrop_blessed")
    end

    local isProgressActive = false
    if self.mode == "log" then
        isProgressActive = self.recordingState and self.recordingState.active and self.recordingState.isRecordAll
    else
        isProgressActive = self.learningState and self.learningState.active and self.learningState.isAbsorbAll
    end

    local normalBtnY = self.footerY + 32
    local progressBtnY = self.footerY + 48

    local targetBtnY = isProgressActive and progressBtnY or normalBtnY

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
    if self.dissolveBtn then
        self.dissolveBtn:setY(targetBtnY)
    end

    -- Hide feedback label when progress bar is active (they overlap at footerY + 4/8)
    if self.feedbackLabel then
        if isProgressActive then
            self.feedbackLabel:setVisible(false)
        end
        -- Note: feedbackLabel visibility is set by showFeedback() when not in progress
    end

    -- Admin buttons are now in the header, no repositioning needed

    if self.mode == "absorb" or self.mode == "view" then
        local isLearning = self.learningState and self.learningState.active
        local isNotesTab = self.currentTab == "notes"

        if self.absorbTabBtn then
            self.absorbTabBtn:setVisible(not isNotesTab)
            self.absorbTabBtn:setEnable((not isLearning) and not isNotesTab)
            local tabName = self:getTabDisplayName(self.currentTab or "skills")
            if isLearning then
                self.absorbTabBtn.title = getText("UI_BurdJournals_StateReading")
            else
                local btnTextKey = (self.mode == "view") and "UI_BurdJournals_BtnClaimTab" or "UI_BurdJournals_BtnAbsorbTab"
                self.absorbTabBtn.title = BurdJournals.formatText(getText(btnTextKey) or "%s Tab", tabName)
            end
        end

        if self.absorbAllBtn then
            self.absorbAllBtn:setVisible(not isNotesTab)
            self.absorbAllBtn:setEnable((not isLearning) and not isNotesTab)
            if isLearning then
                self.absorbAllBtn.title = getText("UI_BurdJournals_StateReading")
            else
                self.absorbAllBtn.title = (self.mode == "view") and getText("UI_BurdJournals_BtnClaimAll") or getText("UI_BurdJournals_BtnAbsorbAll")
            end
        end
    elseif self.mode == "log" then
        local isRecording = self.recordingState and self.recordingState.active

        if self.recordTabBtn then
            self.recordTabBtn:setEnable(not isRecording)
            local tabName = self:getTabDisplayName(self.currentTab or "skills")
            if isRecording then
                self.recordTabBtn.title = getText("UI_BurdJournals_StateRecording")
            elseif self.currentTab == "notes" then
                self.recordTabBtn.title = getText("UI_BurdJournals_NotesSave") or "Save Notes"
            else
                self.recordTabBtn.title = BurdJournals.formatText(getText("UI_BurdJournals_BtnRecordTab") or "Record %s", tabName)
            end
        end

        if self.recordAllBtn then
            self.recordAllBtn:setEnable((not isRecording) and self.currentTab ~= "notes")
            if isRecording then
                self.recordAllBtn.title = getText("UI_BurdJournals_StateRecording")
            else
                self.recordAllBtn.title = getText("UI_BurdJournals_BtnRecordAll")
            end
        end
    end

    if self.headerColor then

        self:drawRect(0, 0, self.width, self.headerHeight, 0.95, self.headerColor.r, self.headerColor.g, self.headerColor.b)

        if self.headerAccent then
            self:drawRect(0, self.headerHeight - 3, self.width, 3, 1, self.headerAccent.r, self.headerAccent.g, self.headerAccent.b)
        end

        local titleX = padding
        if self.headerIconTexture then
            local iconSize = self.headerIconSize or 20
            local iconY = math.floor((self.headerHeight - iconSize) / 2)
            self:drawTextureScaledAspect(self.headerIconTexture, padding, iconY, iconSize, iconSize, 1, 1, 1, 1)
            titleX = padding + iconSize + 8
        end

        local headerCenterY = math.floor(self.headerHeight / 2)
        if self.typeText then
            local typeTextH = getTextManager():MeasureStringY(UIFont.Medium, self.typeText)
            local typeTextY = math.floor(headerCenterY - (typeTextH / 2)) + 1
            local ht = paletteColor(pal, "headerTypeText")
            self:drawText(self.typeText, titleX, typeTextY, ht.r, ht.g, ht.b, ht.a or 1, UIFont.Medium)
        end

        if self.rarityText and self.mode == "absorb" then
            local reservedRight = self.headerRightInset or 0
            local rarityW = getTextManager():MeasureStringX(UIFont.Small, self.rarityText) + 12
            local rarityX = self.width - padding - reservedRight - rarityW
            local rarityTextH = getTextManager():MeasureStringY(UIFont.Small, self.rarityText)
            local rarityH = math.max(18, rarityTextH + 6)
            local rarityY = math.floor(headerCenterY - (rarityH / 2)) + 1
            local rarityTextY = math.floor(rarityY + ((rarityH - rarityTextH) / 2))
            local rb = paletteColor(self.palette, "rarityBadgeBg")
            self:drawRect(rarityX - 6, rarityY, rarityW, rarityH, rb.a or 0.8, rb.r, rb.g, rb.b)
            self:drawText(self.rarityText, rarityX, rarityTextY, 1, 0.95, 0.85, 1, UIFont.Small)
        end
    end

    if self.authorBoxY then

        local boxBg = nil
        local boxBorder = nil
        if self.mode == "log" or self.mode == "view" then
            boxBg = {r=0.10, g=0.14, b=0.18}
            boxBorder = {r=0.20, g=0.30, b=0.38}
        else
            boxBg = paletteColor(pal, "authorBoxBg")
            boxBorder = paletteColor(pal, "authorBoxBorder")
        end

        self:drawRect(padding, self.authorBoxY, self.width - padding * 2, self.authorBoxHeight, (self.mode == "absorb" and ((boxBg.a or 0.6))) or 0.6, boxBg.r, boxBg.g, boxBg.b)
        self:drawRectBorder(padding, self.authorBoxY, self.width - padding * 2, self.authorBoxHeight, 0.5, boxBorder.r, boxBorder.g, boxBorder.b)

        local authorText
        local authorNameDisplay = self.authorName or getText("UI_BurdJournals_Unknown")
        if self.mode == "log" then
            authorText = BurdJournals.formatText(getText("UI_BurdJournals_RecordingFor"), authorNameDisplay)
        else
            authorText = BurdJournals.formatText(getText("UI_BurdJournals_FromNotesOf"), authorNameDisplay)
        end
        local authorColor = (self.mode == "absorb") and paletteColor(pal, "authorText") or {r=0.8, g=0.85, b=0.9, a=1}
        local contentX = padding + (self.authorBoxInnerPadding or 10)
        local contentY = self.authorBoxY + 8

        if self.mode == "absorb" and self.authorTextLayout then
            contentY = contentY + drawWrappedTextLayout(self, self.authorTextLayout, contentX, contentY, authorColor)
        else
            self:drawText(authorText, contentX, contentY, authorColor.r, authorColor.g, authorColor.b, authorColor.a or 1, UIFont.Small)
            contentY = contentY + math.max(14, getTextManager():MeasureStringY(UIFont.Small, "Ag"))
        end

        if self.flavorText then
            local flavorColor = (self.mode == "absorb") and paletteColor(pal, "flavorText") or {r=0.5, g=0.55, b=0.6, a=1}
            contentY = contentY + 4
            if self.mode == "absorb" and self.flavorTextLayout then
                contentY = contentY + drawWrappedTextLayout(self, self.flavorTextLayout, contentX, contentY, flavorColor)
            else
                self:drawText(self.flavorText, contentX, contentY, flavorColor.r, flavorColor.g, flavorColor.b, flavorColor.a or 1, UIFont.Small)
                contentY = contentY + math.max(14, getTextManager():MeasureStringY(UIFont.Small, "Ag"))
            end
        end

        if self.showClaimsLeftBeforeDissolved then
            local claimsText = self.claimsTextDisplay
            if not claimsText then
                local claimsLeft = self:getLimitedLootClaimsLeft() or 0
                claimsText = BurdJournals.formatText(getText("UI_BurdJournals_ClaimsLeftBeforeDissolved") or "Claims Left Before Dissolved: %d", claimsLeft)
            end
            local claimsColor = (self.mode == "absorb") and paletteColor(pal, "claimsText") or {r=0.82, g=0.84, b=0.66, a=1}
            contentY = contentY + 4
            if self.mode == "absorb" and self.claimsTextLayout then
                drawWrappedTextLayout(self, self.claimsTextLayout, contentX, contentY, claimsColor)
            else
                self:drawText(claimsText, contentX, contentY, claimsColor.r, claimsColor.g, claimsColor.b, claimsColor.a or 1, UIFont.Small)
            end
        end
    end

    if self.footerY then

        local divider = (self.mode == "absorb") and paletteColor(pal, "footerDivider") or {r=0.25, g=0.35, b=0.45, a=0.3}
        self:drawRect(padding, self.footerY, self.width - padding * 2, 1, divider.a or 0.3, divider.r, divider.g, divider.b)

        if self.mode == "log" then

            if self.recordingState and self.recordingState.active and self.recordingState.isRecordAll then
                local barX = padding
                local barY = self.footerY + 8
                local barW = self.width - padding * 2
                local barH = 16
                local progress = self.recordingState.progress
                local totalRecords = #self.recordingState.pendingRecords

                local elapsed = (getTimestampMs() - self.recordingState.startTime) / 1000.0
                local remaining = math.max(0, self.recordingState.totalTime - elapsed)
                local remainingText = BurdJournals.formatText("%.1fs", remaining)

                self:drawRect(barX, barY, barW, barH, 0.7, 0.12, 0.12, 0.12)
                self:drawRect(barX, barY, barW * progress, barH, 0.85, 0.25, 0.55, 0.45)
                self:drawRectBorder(barX, barY, barW, barH, 0.8, 0.4, 0.6, 0.7)

                local progressFormat = getText("UI_BurdJournals_RecordingAllProgress") or "Recording All: %d%% (%s remaining)"
                local progressText = BurdJournals.normalizeProgressPercentLabel(BurdJournals.formatText(progressFormat, math.floor(progress * 100), remainingText))
                local textWidth = getTextManager():MeasureStringX(UIFont.Small, progressText)
                self:drawText(progressText, (self.width - textWidth) / 2, barY + 1, 1, 1, 1, 1, UIFont.Small)

                local queuedRecords = self.recordingState.queue and #self.recordingState.queue or 0
                local countText = self:formatBatchFooterCount(
                    totalRecords,
                    queuedRecords,
                    "UI_BurdJournals_ItemCount",
                    "UI_BurdJournals_ItemCountPlural",
                    "%d item",
                    "%d items"
                )
                local countWidth = getTextManager():MeasureStringX(UIFont.Small, countText)
                self:drawText(countText, (self.width - countWidth) / 2, barY + barH + 4, 0.6, 0.7, 0.75, 1, UIFont.Small)
            end
        elseif self.learningState and self.learningState.active and self.learningState.isAbsorbAll then

            local barX = padding
            local barY = self.footerY + 8
            local barW = self.width - padding * 2
            local barH = 16
            local progress = self.learningState.progress
            local totalRewards = #self.learningState.pendingRewards

            local remainingText
            if self.learningState.awaitingServerAck == true then
                local serverTotal = math.max(0, tonumber(self.learningState.serverTotal) or totalRewards)
                local serverProcessed = math.max(0, tonumber(self.learningState.serverProcessed) or 0)
                remainingText = tostring(math.max(0, serverTotal - serverProcessed))
            else
                local elapsed = (getTimestampMs() - self.learningState.startTime) / 1000.0
                local remaining = math.max(0, self.learningState.totalTime - elapsed)
                remainingText = BurdJournals.formatText("%.1fs", remaining)
            end

            self:drawRect(barX, barY, barW, barH, 0.7, 0.12, 0.12, 0.12)
            local fillW = barW * progress
            local pFill
            if self.mode == "view" then
                pFill = {r=0.25, g=0.50, b=0.60, a=0.85}
            else
                pFill = paletteColor(self.palette, "progressBarFill")
            end
            self:drawRect(barX, barY, fillW, barH, pFill.a or 0.85, pFill.r, pFill.g, pFill.b)
            self:drawRectBorder(barX, barY, barW, barH, 0.8, 0.5, 0.5, 0.5)

            local progressFormat
            if self.mode == "view" then
                progressFormat = getText("UI_BurdJournals_ClaimingAllProgress") or "Claiming All: %d%% (%s remaining)"
            else
                progressFormat = getText("UI_BurdJournals_AbsorbingAllProgress") or "Absorbing All: %d%% (%s remaining)"
            end
            local progressText = BurdJournals.normalizeProgressPercentLabel(BurdJournals.formatText(progressFormat, math.floor(progress * 100), remainingText))
            local textWidth = getTextManager():MeasureStringX(UIFont.Small, progressText)
            self:drawText(progressText, (self.width - textWidth) / 2, barY + 1, 1, 1, 1, 1, UIFont.Small)

            local queuedRewards = self.learningState.queue and #self.learningState.queue or 0
            local countText = self:formatBatchFooterCount(
                totalRewards,
                queuedRewards,
                "UI_BurdJournals_RewardQueued",
                "UI_BurdJournals_RewardsQueued",
                "%d reward queued",
                "%d rewards queued"
            )
            local countWidth = getTextManager():MeasureStringX(UIFont.Small, countText)
            self:drawText(countText, (self.width - countWidth) / 2, barY + barH + 4, 0.6, 0.6, 0.55, 1, UIFont.Small)
        else

            if self.mode == "absorb" or self.mode == "view" then
        local summaryText = ""
        if self.totalXP and self.totalXP > 0 then
            local xpFormat = getText("UI_BurdJournals_SummaryTotalXP") or "Total: +%s XP"
            summaryText = BurdJournals.formatText(xpFormat, BurdJournals.formatXP(self.totalXP))
        end
        if self.traitCount and self.traitCount > 0 then
            if summaryText ~= "" then
                summaryText = summaryText .. (getText("UI_BurdJournals_SummarySeparator") or "  |  ")
            end
            local traitFormat = self.traitCount > 1 and (getText("UI_BurdJournals_SummaryTraits") or "%d traits") or (getText("UI_BurdJournals_SummaryTrait") or "%d trait")
            summaryText = summaryText .. BurdJournals.formatText(traitFormat, self.traitCount)
        end
        if summaryText ~= "" then
            local textWidth = getTextManager():MeasureStringX(UIFont.Small, summaryText)
                    local summaryColor = (self.mode == "absorb") and paletteColor(pal, "summaryText") or {r=0.7, g=0.75, b=0.8, a=1}
                    self:drawText(summaryText, (self.width - textWidth) / 2, self.footerY + 10, summaryColor.r, summaryColor.g, summaryColor.b, summaryColor.a or 1, UIFont.Small)
                end
            end
        end
    end

    local joypadActive, joypadData = self:isJoypadActive()
    if joypadActive and joypadData then
        self.listFocusActive = (self.skillList ~= nil and joypadData.focus == self.skillList)
    else
        self.listFocusActive = false
    end
    self:refreshControllerPrompts(false)
end

local function drawAbsorptionSkillSquares(ctx, filledColor, emptyColor, progressColor, displayXP, visualXP, statusText, statusColor)
    local self = ctx.listBox
    local data = ctx.data
    local mainPanel = ctx.mainPanel
    local journalData = ctx.journalData
    local squaresX = ctx.textX
    local squaresY = ctx.cardY + 26
    local squareSize = 10
    local squareSpacing = 2
    BurdJournals.drawPlayerJournalViewSkillSquares(self, squaresX, squaresY, data.skillName, displayXP, visualXP, data.level, journalData, mainPanel.player, squareSize, squareSpacing, {
        baselineColor = getBaselineSquareColor(filledColor, emptyColor),
        earnedColor = filledColor,
        filledColor = filledColor,
        emptyColor = emptyColor,
        progressColor = progressColor,
    })
    local squaresWidth = 10 * squareSize + 9 * squareSpacing
    self:drawText(statusText, squaresX + squaresWidth + 8, squaresY, statusColor.r, statusColor.g, statusColor.b, statusColor.a or 1, UIFont.Small)
end

local function doDrawAbsorptionSkillContent(ctx)
    local self = ctx.listBox
    local mainPanel = ctx.mainPanel
    local data = ctx.data
    local pal = ctx.pal
    local accentColor = ctx.accentColor
    local learningState = mainPanel.learningState
    local isLearningThis = learningState.active and not learningState.isAbsorbAll and learningState.skillName == data.skillName
    local isQueuedInAbsorbAll = learningState.active and learningState.isAbsorbAll and not data.isClaimed
    local queuePosition = mainPanel:getQueuePosition(data.skillName)
    local isQueued = queuePosition ~= nil
    local displayName = data.displayName or data.skillName or "Unknown Skill"

    self:drawText(displayName, ctx.textX, ctx.cardY + 6, ctx.textColor.r, ctx.textColor.g, ctx.textColor.b, 1, UIFont.Small)

    if isLearningThis then
        local progressFormat = getText("UI_BurdJournals_ReadingProgress") or "Reading... %d%%"
        local progressText = BurdJournals.normalizeProgressPercentLabel(BurdJournals.formatText(progressFormat, math.floor(learningState.progress * 100)))
        local progressColor = ctx.yuletideLearningTextColor or {r=0.9, g=0.8, b=0.3}
        local barX = ctx.textX + 90
        local barY = ctx.cardY + 27
        local barW = ctx.cardW - 120 - ctx.padding
        local barH = 10
        local progressFill = paletteColor(pal, "progressBarFill")
        self:drawText(progressText, ctx.textX, ctx.cardY + 24, progressColor.r, progressColor.g, progressColor.b, 1, UIFont.Small)
        self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)
        self:drawRect(barX, barY, barW * learningState.progress, barH, progressFill.a or 0.9, progressFill.r, progressFill.g, progressFill.b)
        self:drawRectBorder(barX, barY, barW, barH, 0.7, accentColor.r, accentColor.g, accentColor.b)
    else
        local displayXP = math.max(0, tonumber(data.effectiveXP or data.xp or 0) or 0)
        local visualXP = displayXP
        local xpText = "+" .. BurdJournals.formatXP(displayXP) .. " XP"
        if data.hasBookBoost then
            xpText = xpText .. " " .. (getText("UI_BurdJournals_XPBoosted") or "(boosted)")
        end

        if isQueued then
            local filledColor = paletteColor(pal, "levelQueuedFilled")
            local emptyColor = paletteColor(pal, "levelQueuedEmpty")
            local progressColor = paletteColor(pal, "levelQueuedProgress")
            local xpColor = data.hasBookBoost and {r=1.0, g=0.85, b=0.3} or paletteColor(pal, "feedbackInfo")
            drawAbsorptionSkillSquares(ctx, filledColor, emptyColor, progressColor, displayXP, visualXP, xpText .. "  #" .. queuePosition, xpColor)
        elseif isQueuedInAbsorbAll then
            local filledColor = paletteColor(pal, "levelAbsorbFilled")
            local emptyColor = paletteColor(pal, "levelAbsorbEmpty")
            local progressColor = paletteColor(pal, "levelAbsorbProgress")
            local xpColor = data.hasBookBoost and {r=1.0, g=0.85, b=0.3} or paletteColor(pal, "feedbackInfo")
            drawAbsorptionSkillSquares(ctx, filledColor, emptyColor, progressColor, displayXP, visualXP, xpText .. "  Queued", xpColor)
        elseif data.xp and not data.isClaimed then
            local filledColor = paletteColor(pal, "levelFilled")
            local emptyColor = paletteColor(pal, "levelEmpty")
            local progressColor = paletteColor(pal, "levelProgress")
            local xpColor = data.hasBookBoost and {r=1.0, g=0.85, b=0.3} or paletteColor(pal, "feedbackSuccess")
            drawAbsorptionSkillSquares(ctx, filledColor, emptyColor, progressColor, displayXP, visualXP, xpText, xpColor)
        elseif data.isClaimed then
            drawAbsorptionSkillSquares(ctx, {r=0.2, g=0.2, b=0.2}, {r=0.08, g=0.08, b=0.08}, {r=0.15, g=0.15, b=0.15}, displayXP, visualXP, getText("UI_BurdJournals_StatusClaimed") or "Claimed", {r=0.35, g=0.35, b=0.35})
        end
    end

    if not data.isClaimed and not isLearningThis then
        local btnW = 60
        local btnH = 24
        local btnX = ctx.cardX + ctx.cardW - btnW - 10
        local btnY = ctx.cardY + (ctx.cardH - btnH) / 2
        local isInBatch = isInCurrentAbsorbBatch(learningState, "skill", data.skillName)

        if isQueued then
            local btnText = "#" .. queuePosition
            local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
            self:drawRect(btnX, btnY, btnW, btnH, 0.5, 0.3, 0.4, 0.5)
            self:drawRectBorder(btnX, btnY, btnW, btnH, 0.6, 0.4, 0.5, 0.6)
            self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.8, 0.9, 1, 1, UIFont.Small)
        elseif isInBatch then
            local btnText = getText("UI_BurdJournals_BtnBatching") or "BATCH"
            local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
            self:drawRect(btnX, btnY, btnW, btnH, 0.6, 0.45, 0.55, 0.45)
            self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.6, 0.7, 0.6)
            self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.95, 1, 0.95, 1, UIFont.Small)
        elseif learningState.active and not learningState.isAbsorbAll then
            local btnText = getText("UI_BurdJournals_BtnQueue")
            local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
            self:drawRect(btnX, btnY, btnW, btnH, 0.6, 0.25, 0.35, 0.5)
            self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.4, 0.55, 0.7)
            self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.9, 0.95, 1, 1, UIFont.Small)
        elseif not learningState.active then
            local btnText = getText("UI_BurdJournals_Absorb")
            self:drawRect(btnX, btnY, btnW, btnH, 0.7, accentColor.r * 0.6, accentColor.g * 0.6, accentColor.b * 0.6)
            self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, accentColor.r, accentColor.g, accentColor.b)
            mainPanel:drawPillLabelWithPrompt(self, btnX, btnY, btnW, btnH, btnText, {r=1, g=1, b=1, a=1}, "A")
        end
    end
end

local function doDrawAbsorptionRecipeContent(ctx)
    local self = ctx.listBox
    local mainPanel = ctx.mainPanel
    local data = ctx.data
    local pal = ctx.pal
    local learningState = mainPanel.learningState
    local isLearningThis = learningState.active and not learningState.isAbsorbAll and learningState.recipeName == data.recipeName
    local isQueuedInAbsorbAll = learningState.active and learningState.isAbsorbAll and not data.isClaimed and not data.alreadyKnown
    local queuePosition = mainPanel:getQueuePosition(data.recipeName)
    local isQueued = queuePosition ~= nil
    local recipeName = data.displayName or data.recipeName or "Unknown Recipe"
    local recipeTextX = ctx.textX
    local magazineTexture = data.magazineTexture or getMagazineTexture(data.magazineSource)

    if magazineTexture then
        local iconSize = 24
        local iconX = ctx.textX
        local iconY = ctx.cardY + (ctx.cardH - iconSize) / 2
        local iconAlpha = (data.isClaimed or data.alreadyKnown) and 0.4 or 1.0
        self:drawTextureScaledAspect(magazineTexture, iconX, iconY, iconSize, iconSize, iconAlpha, 1, 1, 1)
        recipeTextX = ctx.textX + iconSize + 6
    end

    local recipeColor
    if data.isClaimed then
        recipeColor = {r=0.4, g=0.4, b=0.4}
    elseif data.alreadyKnown then
        recipeColor = ctx.isYuletideReward and paletteColor(pal, "feedbackMuted") or {r=0.5, g=0.5, b=0.45}
    else
        recipeColor = ctx.isYuletideReward and paletteColor(pal, "feedbackInfo") or {r=0.5, g=0.85, b=0.9}
    end
    self:drawText(recipeName, recipeTextX, ctx.cardY + 6, recipeColor.r, recipeColor.g, recipeColor.b, 1, UIFont.Small)

    if isLearningThis then
        local progressText = BurdJournals.normalizeProgressPercentLabel(BurdJournals.formatText("Learning... %d%%", math.floor(learningState.progress * 100)))
        local progressColor = ctx.yuletideLearningTextColor or {r=0.5, g=0.8, b=0.9}
        local barX = recipeTextX + 100
        local barY = ctx.cardY + 25
        local barW = ctx.cardW - barX - 20
        local barH = 10
        local progressFill = ctx.isYuletideReward and paletteColor(pal, "progressBarFill") or {r=0.3, g=0.7, b=0.8, a=0.9}
        local progressBorder = ctx.isYuletideReward and ctx.accentColor or {r=0.4, g=0.8, b=0.9}
        self:drawText(progressText, recipeTextX, ctx.cardY + 22, progressColor.r, progressColor.g, progressColor.b, 1, UIFont.Small)
        self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)
        self:drawRect(barX, barY, barW * learningState.progress, barH, progressFill.a or 0.9, progressFill.r, progressFill.g, progressFill.b)
        self:drawRectBorder(barX, barY, barW, barH, 0.7, progressBorder.r, progressBorder.g, progressBorder.b)
    elseif isQueued then
        local queueText = BurdJournals.formatText(getText("UI_BurdJournals_RecipeKnowledgeQueuedNum") or "Recipe knowledge - Queued #%d", queuePosition)
        local queueColor = ctx.isYuletideReward and paletteColor(pal, "feedbackInfo") or {r=0.6, g=0.75, b=0.9}
        self:drawText(queueText, recipeTextX, ctx.cardY + 22, queueColor.r, queueColor.g, queueColor.b, 1, UIFont.Small)
    elseif isQueuedInAbsorbAll then
        local queuedText = getText("UI_BurdJournals_RecipeKnowledgeQueued") or "Recipe knowledge - Queued"
        local queuedColor = ctx.isYuletideReward and paletteColor(pal, "feedbackMuted") or {r=0.4, g=0.6, b=0.65}
        self:drawText(queuedText, recipeTextX, ctx.cardY + 22, queuedColor.r, queuedColor.g, queuedColor.b, 1, UIFont.Small)
    elseif data.isClaimed then
        self:drawText(getText("UI_BurdJournals_RecipeClaimed") or "Claimed", recipeTextX, ctx.cardY + 22, 0.35, 0.35, 0.35, 1, UIFont.Small)
    elseif data.alreadyKnown then
        local knownColor = ctx.isYuletideReward and paletteColor(pal, "feedbackMuted") or {r=0.5, g=0.4, b=0.3}
        self:drawText(getText("UI_BurdJournals_RecipeAlreadyKnown") or "Already known", recipeTextX, ctx.cardY + 22, knownColor.r, knownColor.g, knownColor.b, 1, UIFont.Small)
    else
        local sourceText = data.sourceText or buildRecipeSourceText(data.magazineSource, getText("UI_BurdJournals_RecipeKnowledge") or "Recipe knowledge")
        local sourceColor = ctx.isYuletideReward and paletteColor(pal, "feedbackMuted") or {r=0.5, g=0.7, b=0.75}
        self:drawText(sourceText, recipeTextX, ctx.cardY + 22, sourceColor.r, sourceColor.g, sourceColor.b, 1, UIFont.Small)
    end

    if not data.isClaimed and not data.alreadyKnown and not isLearningThis then
        local btnW = 55
        local btnH = 24
        local btnX = ctx.cardX + ctx.cardW - btnW - 10
        local btnY = ctx.cardY + (ctx.cardH - btnH) / 2
        local isInBatch = isInCurrentAbsorbBatch(learningState, "recipe", data.recipeName)

        if isQueued then
            local queuedBtnBg = ctx.isYuletideReward and paletteColor(pal, "itemHeaderBg") or {r=0.3, g=0.5, b=0.55}
            local queuedBtnBorder = ctx.isYuletideReward and ctx.accentColor or {r=0.4, g=0.6, b=0.7}
            local queuedBtnTextColor = ctx.isYuletideReward and paletteColor(pal, "itemHeaderText") or {r=0.8, g=0.9, b=1.0}
            local btnText = "#" .. queuePosition
            local btnTextW = mainPanel:getCachedSmallTextWidth(btnText)
            self:drawRect(btnX, btnY, btnW, btnH, 0.5, queuedBtnBg.r, queuedBtnBg.g, queuedBtnBg.b)
            self:drawRectBorder(btnX, btnY, btnW, btnH, 0.6, queuedBtnBorder.r, queuedBtnBorder.g, queuedBtnBorder.b)
            self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, queuedBtnTextColor.r, queuedBtnTextColor.g, queuedBtnTextColor.b, 1, UIFont.Small)
        elseif isInBatch then
            local batchBtnBg = ctx.isYuletideReward and paletteColor(pal, "absorbTabBtnBg") or {r=0.45, g=0.55, b=0.5}
            local batchBtnBorder = ctx.isYuletideReward and paletteColor(pal, "absorbTabBtnBorder") or {r=0.55, g=0.7, b=0.7}
            local batchBtnTextColor = ctx.isYuletideReward and paletteColor(pal, "closeBtnText") or {r=0.95, g=1.0, b=0.95}
            local btnText = getText("UI_BurdJournals_BtnBatching") or "BATCH"
            local btnTextW = mainPanel:getCachedSmallTextWidth(btnText)
            self:drawRect(btnX, btnY, btnW, btnH, 0.6, batchBtnBg.r, batchBtnBg.g, batchBtnBg.b)
            self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, batchBtnBorder.r, batchBtnBorder.g, batchBtnBorder.b)
            self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, batchBtnTextColor.r, batchBtnTextColor.g, batchBtnTextColor.b, 1, UIFont.Small)
        elseif learningState.active and not learningState.isAbsorbAll then
            local queueBtnBg = ctx.isYuletideReward and paletteColor(pal, "itemHeaderBg") or {r=0.25, g=0.45, b=0.5}
            local queueBtnBorder = ctx.isYuletideReward and ctx.accentColor or {r=0.35, g=0.6, b=0.7}
            local queueBtnTextColor = ctx.isYuletideReward and paletteColor(pal, "itemHeaderText") or {r=0.9, g=0.95, b=1.0}
            local btnText = getText("UI_BurdJournals_BtnQueue")
            local btnTextW = mainPanel:getCachedSmallTextWidth(btnText)
            self:drawRect(btnX, btnY, btnW, btnH, 0.6, queueBtnBg.r, queueBtnBg.g, queueBtnBg.b)
            self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, queueBtnBorder.r, queueBtnBorder.g, queueBtnBorder.b)
            self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, queueBtnTextColor.r, queueBtnTextColor.g, queueBtnTextColor.b, 1, UIFont.Small)
        elseif not learningState.active then
            local claimBtnBg = ctx.isYuletideReward and paletteColor(pal, "absorbTabBtnBg") or {r=0.2, g=0.45, b=0.5}
            local claimBtnBorder = ctx.isYuletideReward and ctx.accentColor or {r=0.3, g=0.6, b=0.7}
            local claimBtnTextColor = ctx.isYuletideReward and paletteColor(pal, "closeBtnText") or {r=0.9, g=1.0, b=1.0}
            local btnText = getText("UI_BurdJournals_BtnClaim")
            self:drawRect(btnX, btnY, btnW, btnH, 0.7, claimBtnBg.r, claimBtnBg.g, claimBtnBg.b)
            self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, claimBtnBorder.r, claimBtnBorder.g, claimBtnBorder.b)
            mainPanel:drawPillLabelWithPrompt(self, btnX, btnY, btnW, btnH, btnText, {r=claimBtnTextColor.r, g=claimBtnTextColor.g, b=claimBtnTextColor.b, a=1}, "A")
        end
    end
end

local function doDrawAbsorptionTraitContent(ctx)
    local self = ctx.listBox
    local mainPanel = ctx.mainPanel
    local data = ctx.data
    local learningState = mainPanel.learningState
    local isLearningThis = learningState.active and not learningState.isAbsorbAll and (
        (data.isForgetSlot and learningState.forgetTraitId == data.traitId) or
        ((not data.isForgetSlot) and learningState.traitId == data.traitId)
    )
    local isQueuedInAbsorbAll = learningState.active and learningState.isAbsorbAll and not data.isClaimed and not data.alreadyKnown and not data.isForgetSlot
    local queuePosition = mainPanel:getQueuePosition(data.traitId)
    local isQueued = queuePosition ~= nil
    local traitName = data.traitName or data.traitId or getText("UI_BurdJournals_UnknownTrait") or "Unknown Trait"
    local traitTextX = ctx.textX

    if data.traitTexture then
        local iconSize = 24
        local iconX = ctx.textX
        local iconY = ctx.cardY + (ctx.cardH - iconSize) / 2
        local iconAlpha = data.isClaimed and 0.4 or 1.0
        self:drawTextureScaledAspect(data.traitTexture, iconX, iconY, iconSize, iconSize, iconAlpha, 1, 1, 1)
        traitTextX = ctx.textX + iconSize + 6
    end

    local traitColor
    if data.isClaimed then
        traitColor = {r=0.4, g=0.4, b=0.4}
    elseif data.isForgetSlot then
        traitColor = {r=0.95, g=0.65, b=0.72}
    elseif data.isPositive == true then
        traitColor = {r=0.5, g=0.9, b=0.5}
    elseif data.isPositive == false then
        traitColor = {r=0.9, g=0.5, b=0.5}
    else
        traitColor = {r=0.9, g=0.75, b=0.5}
    end
    self:drawText(traitName, traitTextX, ctx.cardY + 6, traitColor.r, traitColor.g, traitColor.b, 1, UIFont.Small)

    if isLearningThis then
        local progressText = BurdJournals.normalizeProgressPercentLabel(BurdJournals.formatText(getText("UI_BurdJournals_AbsorbingProgress") or "Absorbing... %d%%", math.floor(learningState.progress * 100)))
        local progressColor = ctx.yuletideLearningTextColor or {r=0.9, g=0.7, b=0.3}
        local barX = traitTextX + 100
        local barY = ctx.cardY + 25
        local barW = ctx.cardW - barX - 20
        local barH = 10
        self:drawText(progressText, traitTextX, ctx.cardY + 22, progressColor.r, progressColor.g, progressColor.b, 1, UIFont.Small)
        self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)
        self:drawRect(barX, barY, barW * learningState.progress, barH, 0.9, 0.8, 0.6, 0.2)
        self:drawRectBorder(barX, barY, barW, barH, 0.7, 0.9, 0.7, 0.3)
    elseif isQueued then
        if data.isPositive == false then
            local queueText = BurdJournals.formatText(getText("UI_BurdJournals_NegativeTraitQueued") or "Cursed trait - Queued #%d", queuePosition)
            self:drawText(queueText, traitTextX, ctx.cardY + 22, 0.7, 0.4, 0.4, 1, UIFont.Small)
        else
            local queueText = BurdJournals.formatText(getText("UI_BurdJournals_RareTraitQueued") or "Rare trait - Queued #%d", queuePosition)
            self:drawText(queueText, traitTextX, ctx.cardY + 22, 0.6, 0.75, 0.9, 1, UIFont.Small)
        end
    elseif isQueuedInAbsorbAll then
        if data.isPositive == false then
            self:drawText(getText("UI_BurdJournals_NegativeTraitCurseQueued") or "Cursed knowledge... - Queued", traitTextX, ctx.cardY + 22, 0.5, 0.35, 0.35, 1, UIFont.Small)
        else
            self:drawText(getText("UI_BurdJournals_RareTraitBonusQueued") or "Rare trait bonus! - Queued", traitTextX, ctx.cardY + 22, 0.5, 0.45, 0.25, 1, UIFont.Small)
        end
    elseif data.isClaimed then
        self:drawText(getText("UI_BurdJournals_StatusClaimed") or "Claimed", traitTextX, ctx.cardY + 22, 0.35, 0.35, 0.35, 1, UIFont.Small)
    elseif data.isForgetSlot then
        self:drawText(getText("UI_BurdJournals_ForgetTraitHint") or "Remove this negative trait", traitTextX, ctx.cardY + 22, 0.8, 0.55, 0.6, 1, UIFont.Small)
    elseif data.alreadyKnown then
        self:drawText(getText("UI_BurdJournals_StatusAlreadyKnown") or "Already known", traitTextX, ctx.cardY + 22, 0.5, 0.4, 0.3, 1, UIFont.Small)
    elseif data.isPositive == false then
        self:drawText(getText("UI_BurdJournals_NegativeTraitCurse") or "Cursed knowledge...", traitTextX, ctx.cardY + 22, 0.7, 0.4, 0.4, 1, UIFont.Small)
    else
        self:drawText(getText("UI_BurdJournals_RareTraitBonus") or "Rare trait bonus!", traitTextX, ctx.cardY + 22, 0.7, 0.55, 0.3, 1, UIFont.Small)
    end

    if not data.isClaimed and not data.alreadyKnown and not isLearningThis then
        local btnW = 60
        local btnH = 24
        local btnX = ctx.cardX + ctx.cardW - btnW - 10
        local btnY = ctx.cardY + (ctx.cardH - btnH) / 2
        local batchType = data.isForgetSlot and "forget" or "trait"
        local isInBatch = isInCurrentAbsorbBatch(learningState, batchType, data.traitId)

        if isQueued then
            local btnText = "#" .. queuePosition
            local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
            self:drawRect(btnX, btnY, btnW, btnH, 0.5, 0.4, 0.35, 0.5)
            self:drawRectBorder(btnX, btnY, btnW, btnH, 0.6, 0.5, 0.45, 0.6)
            self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.9, 0.85, 0.7, 1, UIFont.Small)
        elseif isInBatch then
            local btnText = getText("UI_BurdJournals_BtnBatching") or "BATCH"
            local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
            self:drawRect(btnX, btnY, btnW, btnH, 0.6, 0.5, 0.45, 0.45)
            self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.65, 0.55, 0.6)
            self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 1, 0.95, 0.85, 1, UIFont.Small)
        elseif learningState.active and not learningState.isAbsorbAll then
            local btnText = getText("UI_BurdJournals_BtnQueue")
            local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
            self:drawRect(btnX, btnY, btnW, btnH, 0.6, 0.4, 0.35, 0.25)
            self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.6, 0.5, 0.35)
            self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 1, 0.95, 0.85, 1, UIFont.Small)
        elseif not learningState.active then
            local btnText = data.isForgetSlot and (getText("UI_BurdJournals_BtnForget") or "FORGET") or getText("UI_BurdJournals_BtnClaim")
            if data.isForgetSlot then
                self:drawRect(btnX, btnY, btnW, btnH, 0.8, 0.6, 0.2, 0.28)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.9, 0.85, 0.4, 0.45)
            else
                self:drawRect(btnX, btnY, btnW, btnH, 0.7, 0.5, 0.35, 0.15)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.7, 0.5, 0.25)
            end
            mainPanel:drawPillLabelWithPrompt(self, btnX, btnY, btnW, btnH, btnText, {r=1, g=0.95, b=0.85, a=1}, "A")
        end
    end
end

function BurdJournals.UI.MainPanel.doDrawAbsorptionItem(self, y, item, alt)
    local mainPanel = self.mainPanel
    if not mainPanel then return y + self.itemheight end

    local data = item.item or {}
    local x = 0
    local scrollBarWidth = 13
    local w = self:getWidth() - scrollBarWidth
    local h = tonumber(item.height) or self.itemheight
    if not shouldDrawListRow(self, y, h) then
        return y + h
    end
    local padding = 12
    local isYuletideReward = mainPanel.isYuletideReward
    local pal = mainPanel.palette or getRewardPalette(mainPanel.rewardTheme)
    local cardBg = paletteColor(pal, "cardBg")
    local cardBorder = paletteColor(pal, "cardBorder")
    local accentColor = paletteColor(pal, "cardAccent")

    if data.isHeader then
        local headerBg = paletteColor(pal, "itemHeaderBg")
        local headerText = paletteColor(pal, "itemHeaderText")
        local headerCount = paletteColor(pal, "itemHeaderCount")
        self:drawRect(x, y + 2, w, h - 4, headerBg.a or 0.4, headerBg.r, headerBg.g, headerBg.b)
        self:drawText(data.text or getText("UI_BurdJournals_Skills") or "SKILLS", x + padding, y + (h - 18) / 2, headerText.r, headerText.g, headerText.b, headerText.a or 1, UIFont.Medium)
        if data.count then
            local countText = BurdJournals.formatText(getText("UI_BurdJournals_Available") or "(%d available)", data.count)
            local countWidth = getTextManager():MeasureStringX(UIFont.Small, countText)
            self:drawText(countText, w - padding - countWidth, y + (h - 14) / 2, headerCount.r, headerCount.g, headerCount.b, headerCount.a or 1, UIFont.Small)
        end
        return y + h
    end

    if data.isEmpty then
        self:drawText(data.text or getText("UI_BurdJournals_NoRewardsAvailable") or "No rewards available", x + padding, y + (h - 14) / 2, 0.4, 0.4, 0.4, 1, UIFont.Small)
        return y + h
    end

    local cardMargin = 4
    local cardX = x + cardMargin
    local cardY = y + cardMargin
    local cardW = w - cardMargin * 2
    local cardH = h - cardMargin * 2

    local bgColor = cardBg
    local borderColor = cardBorder
    local accent = accentColor
    if data.isTrait and not data.isClaimed then
        if data.isForgetSlot then
            bgColor = {r=0.20, g=0.08, b=0.10}
            borderColor = {r=0.6, g=0.25, b=0.3}
            accent = {r=0.9, g=0.35, b=0.4}
        elseif data.isPositive == true then

            bgColor = {r=0.08, g=0.20, b=0.10}
            borderColor = {r=0.2, g=0.5, b=0.25}
            accent = {r=0.3, g=0.8, b=0.35}
        elseif data.isPositive == false then

            bgColor = {r=0.22, g=0.08, b=0.08}
            borderColor = {r=0.5, g=0.2, b=0.2}
            accent = {r=0.8, g=0.3, b=0.3}
        end

    end

    if data.isClaimed then
        self:drawRect(cardX, cardY, cardW, cardH, 0.3, 0.1, 0.1, 0.1)
    else
        local bodyAlpha = bgColor.a or (isYuletideReward and 0.76 or 0.7)
        self:drawRect(cardX, cardY, cardW, cardH, bodyAlpha, bgColor.r, bgColor.g, bgColor.b)
    end

    self:drawRectBorder(cardX, cardY, cardW, cardH, 0.6, borderColor.r, borderColor.g, borderColor.b)

    self:drawRect(cardX, cardY, 4, cardH, 0.9, accent.r, accent.g, accent.b)
    mainPanel:drawSelectedRowOutline(self, item, cardX, cardY, cardW, cardH)

    local textX = cardX + padding + 4
    local ctx = {
        accentColor = accentColor,
        cardH = cardH,
        cardW = cardW,
        cardX = cardX,
        cardY = cardY,
        data = data,
        h = h,
        isYuletideReward = isYuletideReward,
        journalData = (mainPanel.journal and BurdJournals.getJournalData and BurdJournals.getJournalData(mainPanel.journal)) or nil,
        listBox = self,
        mainPanel = mainPanel,
        padding = padding,
        pal = pal,
        textColor = data.isClaimed and {r=0.4, g=0.4, b=0.4} or paletteColor(pal, "cardText"),
        textX = textX,
        yuletideLearningTextColor = isYuletideReward and {r=0.82, g=0.22, b=0.22} or nil,
    }

    if data.isSkill then
        doDrawAbsorptionSkillContent(ctx)
    end

    if data.isTrait then
        doDrawAbsorptionTraitContent(ctx)
    end

    if data.isRecipe then
        doDrawAbsorptionRecipeContent(ctx)
    end

    return y + h
end

function BurdJournals.UI.MainPanel:populateAbsorptionList()
    local journalData = self:resolvePendingRecordJournalDataForRefresh() or BurdJournals.getJournalData(self.journal)
    local currentTab = self.currentTab or "skills"
    local entries = {}
    local emptyEntry = nil
    local sessionClaimedSkills = self.sessionClaimedSkills or {}
    local function isSkillClaimedForAbsorb(skillName)
        if not skillName then
            return false
        end
        if BurdJournals.hasCharacterClaimedSkill(journalData, self.player, skillName) then
            return true
        end
        return sessionClaimedSkills[skillName] == true
    end

    if currentTab == "notes" then
        if self.refreshNotesTab then
            self:refreshNotesTab(journalData)
        end
        return
    elseif self.hideNotesControls then
        self:hideNotesControls()
    end

    if currentTab == "skills" then
        local allowedSkills = BurdJournals.getAllowedSkills and BurdJournals.getAllowedSkills() or {}
        local skillSortIndex = {}
        for index, allowedSkillName in ipairs(allowedSkills) do
            skillSortIndex[allowedSkillName] = index
        end

        if journalData and journalData.skills then
            local hasSkills = false
            local matchCount = 0
            for skillName, skillData in pairs(journalData.skills) do
                if BurdJournals.isSkillVisibleForJournal(journalData, skillName) then
                    hasSkills = true
                    local isClaimed = isSkillClaimedForAbsorb(skillName)
                    local displayName = BurdJournals.getPerkDisplayName(skillName)
                    local modSource = BurdJournals.getSkillModId(skillName)

                    if self:matchesSearch(displayName) and self:passesFilter(modSource) then
                        matchCount = matchCount + 1
                        local baseXP = skillData.xp or 0
                        local effectiveXP = baseXP
                        local hasBookBoost = false
                        if not isClaimed then
                            effectiveXP, hasBookBoost = BurdJournals.getEffectiveXP(self.player, skillName, baseXP)
                        end
                        self:appendListEntry(entries, skillName, {
                            isSkill = true,
                            skillName = skillName,
                            displayName = displayName,
                            xp = baseXP,
                            effectiveXP = effectiveXP,
                            hasBookBoost = hasBookBoost,
                            level = skillData.level or 0,
                            isClaimed = isClaimed,
                            modSource = modSource
                        }, nil, displayName, skillSortIndex[skillName])
                    end
                end
            end

            if not hasSkills then
                emptyEntry = {id = "empty", data = {isEmpty = true, text = getText("UI_BurdJournals_NoSkillsRecorded")}}
            elseif matchCount == 0 then
                emptyEntry = {id = "no_results", data = {isEmpty = true, text = getText("UI_BurdJournals_NoSearchResults") or "No results found"}}
            end
        else
            emptyEntry = {id = "empty", data = {isEmpty = true, text = getText("UI_BurdJournals_NoSkillsRecorded")}}
        end

    elseif currentTab == "traits" then
        local hasTraitEntries = false
        local matchCount = 0

        if BurdJournals.hasTraitEntriesForJournal(journalData) then
            for traitId, traitData in pairs(journalData.traits) do
                hasTraitEntries = true
                local isClaimed = BurdJournals.hasCharacterClaimedTrait(journalData, self.player, traitId)
                local alreadyKnown = BurdJournals.playerHasTrait(self.player, traitId)
                local traitName = safeGetTraitName(traitId)
                local traitTexture = getTraitTexture(traitId)
                local isPositive = isTraitPositive(traitId)
                local modSource = BurdJournals.getTraitModId(traitId)

                if self:matchesSearch(traitName) and self:passesFilter(modSource) then
                    matchCount = matchCount + 1
                    self:appendListEntry(entries, traitId, {
                        isTrait = true,
                        traitId = traitId,
                        traitName = traitName,
                        traitTexture = traitTexture,
                        isClaimed = isClaimed,
                        alreadyKnown = alreadyKnown,
                        isPositive = isPositive,
                        modSource = modSource
                    }, nil, traitName)
                end
            end
        end

        if not hasTraitEntries then
            emptyEntry = {id = "empty_traits", data = {isEmpty = true, text = getText("UI_BurdJournals_NoTraitsAvailable")}}
        elseif matchCount == 0 then
            emptyEntry = {id = "no_results", data = {isEmpty = true, text = getText("UI_BurdJournals_NoSearchResults") or "No results found"}}
        end

    elseif currentTab == "forget" then
        local forgetSlotCount = journalData and BurdJournals.getForgetSlotCount and BurdJournals.getForgetSlotCount(journalData) or 0
        local hasForgetSlot = forgetSlotCount > 0
            and BurdJournals.isForgetSlotEnabledForJournal
            and BurdJournals.isForgetSlotEnabledForJournal(journalData)
        local claimedForgetSlots = hasForgetSlot
            and BurdJournals.getCharacterClaimedForgetSlotCount
            and BurdJournals.getCharacterClaimedForgetSlotCount(journalData, self.player)
            or 0
        local remainingForgetSlots = hasForgetSlot and math.max(0, forgetSlotCount - claimedForgetSlots) or 0

        if not hasForgetSlot then
            emptyEntry = {
                id = "no_forget_slot",
                data = {
                    isEmpty = true,
                    text = getText("UI_BurdJournals_NoForgetSlot") or "No trait-removal reward available",
                }
            }
        elseif remainingForgetSlots <= 0 then
            emptyEntry = {
                id = "forget_claimed",
                data = {
                    isEmpty = true,
                    text = getText("UI_BurdJournals_ForgetTraitUsed") or "Forget slot already used",
                }
            }
        else
            local removableTraits = BurdJournals.getPlayerRemovableTraits and BurdJournals.getPlayerRemovableTraits(self.player) or {}
            local matchCount = 0
            for index, removableTraitId in ipairs(removableTraits) do
                local removableName = safeGetTraitName(removableTraitId)
                local rowName = BurdJournals.formatText(getText("UI_BurdJournals_ForgetTraitPrefix") or "FORGET: %s", removableName)
                if self:matchesSearch(rowName) and self:passesFilter("vanilla") then
                    matchCount = matchCount + 1
                    self:appendListEntry(entries, "forget_" .. tostring(removableTraitId), {
                        isForgetSlot = true,
                        isTrait = true,
                        traitId = removableTraitId,
                        traitName = rowName,
                        baseTraitName = removableName,
                        isClaimed = false,
                        alreadyKnown = false,
                        isPositive = false,
                        modSource = "vanilla",
                    }, nil, rowName, index)
                end
            end

            if #removableTraits == 0 then
                emptyEntry = {
                    id = "no_forget_traits",
                    data = {
                        isEmpty = true,
                        text = getText("UI_BurdJournals_NoForgetableTraits") or "No removable traits available",
                    }
                }
            elseif matchCount == 0 then
                emptyEntry = {id = "no_results", data = {isEmpty = true, text = getText("UI_BurdJournals_NoSearchResults") or "No results found"}}
            end
        end

    elseif currentTab == "recipes" then
        if journalData and journalData.recipes then
            local hasRecipes = false
            local matchCount = 0
            for recipeName, recipeData in pairs(journalData.recipes) do
                if BurdJournals.isRecipeEnabledForJournal(journalData, recipeName) then
                    hasRecipes = true
                    local isClaimed = BurdJournals.hasCharacterClaimedRecipe(journalData, self.player, recipeName)
                    local alreadyKnown = BurdJournals.playerKnowsRecipe(self.player, recipeName)
                    local displayName = BurdJournals.getRecipeDisplayName(recipeName)
                    local magazineSource = (type(recipeData) == "table" and recipeData.source) or BurdJournals.getMagazineForRecipe(recipeName)
                    local modSource = BurdJournals.getRecipeModId(recipeName, magazineSource)

                    if self:matchesSearch(displayName) and self:passesFilter(modSource) then
                        matchCount = matchCount + 1
                        self:appendListEntry(entries, recipeName, {
                            isRecipe = true,
                            recipeName = recipeName,
                            displayName = displayName,
                            magazineSource = magazineSource,
                            magazineTexture = getMagazineTexture(magazineSource),
                            sourceText = buildRecipeSourceText(magazineSource, getText("UI_BurdJournals_RecipeKnowledge") or "Recipe knowledge"),
                            isClaimed = isClaimed,
                            alreadyKnown = alreadyKnown,
                            modSource = modSource
                        }, nil, displayName)
                    end
                end
            end

            if not hasRecipes then
                emptyEntry = {id = "empty_recipes", data = {isEmpty = true, text = getText("UI_BurdJournals_NoRecipesRecorded")}}
            elseif matchCount == 0 then
                emptyEntry = {id = "no_results", data = {isEmpty = true, text = getText("UI_BurdJournals_NoSearchResults") or "No results found"}}
            end
        else
            emptyEntry = {id = "empty_recipes", data = {isEmpty = true, text = getText("UI_BurdJournals_NoRecipesAvailable")}}
        end
    end

    self:setPaginatedListEntries(entries, emptyEntry)
end

function BurdJournals.UI.MainPanel:refreshAbsorptionList()
    BurdJournals.debugPrint("[BurdJournals] UI: refreshAbsorptionList called")
    self:rememberListSelection()

    local journalData = self:resolvePendingRecordJournalDataForRefresh() or BurdJournals.getJournalData(self.journal)
    local claimedCount = journalData and journalData.claimedSkills and BurdJournals.countTable(journalData.claimedSkills) or 0
    BurdJournals.debugPrint("[BurdJournals] UI: refreshAbsorptionList sees claimedSkills count: " .. tostring(claimedCount))

    local skillCount = 0
    local traitCount = 0
    local forgetCount = 0
    local recipeCount = 0
    local totalXP = 0
    local sessionClaimedSkills = self.sessionClaimedSkills or {}
    local function isSkillClaimedForAbsorb(skillName)
        if not skillName then
            return false
        end
        if BurdJournals.hasCharacterClaimedSkill(journalData, self.player, skillName) then
            return true
        end
        return sessionClaimedSkills[skillName] == true
    end

    if journalData and journalData.skills then
        for skillName, skillData in pairs(journalData.skills) do
            if BurdJournals.isSkillVisibleForJournal(journalData, skillName) then
                if not isSkillClaimedForAbsorb(skillName) then
                    skillCount = skillCount + 1
                    -- Calculate effective XP with skill book multiplier
                    local effectiveXP = BurdJournals.getEffectiveXP(self.player, skillName, skillData.xp or 0)
                    totalXP = totalXP + effectiveXP
                end
            end
        end
    end
    if BurdJournals.hasTraitEntriesForJournal(journalData) then
        for traitId, _ in pairs(journalData.traits) do
            if not BurdJournals.hasCharacterClaimedTrait(journalData, self.player, traitId) then
                traitCount = traitCount + 1
            end
        end
    end
    local forgetSlotCount = journalData and BurdJournals.getForgetSlotCount and BurdJournals.getForgetSlotCount(journalData) or 0
    local hasForgetSlot = forgetSlotCount > 0
        and BurdJournals.isForgetSlotEnabledForJournal
        and BurdJournals.isForgetSlotEnabledForJournal(journalData)
        and BurdJournals.getPlayerRemovableTraits
    if hasForgetSlot and BurdJournals.getCharacterClaimedForgetSlotCount then
        local claimedForgetSlots = BurdJournals.getCharacterClaimedForgetSlotCount(journalData, self.player)
        local remainingForgetSlots = math.max(0, forgetSlotCount - claimedForgetSlots)
        local removableTraits = BurdJournals.getPlayerRemovableTraits(self.player)
        forgetCount = math.min(#removableTraits, remainingForgetSlots)
    end
    if journalData and journalData.recipes then
        for recipeName, _ in pairs(journalData.recipes) do
            if not BurdJournals.hasCharacterClaimedRecipe(journalData, self.player, recipeName) then
                recipeCount = recipeCount + 1
            end
        end
    end

    self.skillCount = skillCount
    self.traitCount = traitCount
    self.forgetCount = forgetCount
    self.recipeCount = recipeCount
    self.totalXP = totalXP

    if self.mode == "view" then
        self:populateViewList()
    else
        self:populateAbsorptionList()
    end
    self:ensureListSelection(self.listFocusActive)
    self:rebuildJoypadRows()
end

function BurdJournals.UI.MainPanel:getReadingSpeedMultiplier()
    if not BurdJournals.getSandboxOption("ReadingSkillAffectsSpeed") then
        return 1.0
    end

    local bonusPerLevel = BurdJournals.getSandboxOption("ReadingSpeedBonus") or 0.1
    local readingLevel = 0

    if self.player then
        if self.player.getReadingLevel then
            readingLevel = self.player:getReadingLevel() or 0
        end
    end

    local speedBonus = readingLevel * bonusPerLevel
    local speedMultiplier = math.max(0.1, 1.0 - speedBonus)

    return speedMultiplier
end

function BurdJournals.UI.MainPanel:getTabDisplayName(tabId)
    local tabNames = {
        skills = getText("UI_BurdJournals_TabSkills") or "Skills",
        traits = getText("UI_BurdJournals_TabTraits") or "Traits",
        forget = getText("UI_BurdJournals_TabForget") or "Forget",
        recipes = getText("UI_BurdJournals_TabRecipes") or "Recipes",
        stats = getText("UI_BurdJournals_TabStats") or "Stats",
        charinfo = getText("UI_BurdJournals_TabStats") or "Stats",
        notes = getText("UI_BurdJournals_TabNotes") or "Notes",
    }
    return tabNames[tabId] or "Items"
end

function BurdJournals.UI.MainPanel:getSkillLearningTime()
    local baseTime = BurdJournals.getSandboxOption("LearningTimePerSkill") or 3.0
    local multiplier = BurdJournals.getSandboxOption("LearningTimeMultiplier") or 1.0
    local readingMultiplier = self:getReadingSpeedMultiplier()
    return baseTime * multiplier * readingMultiplier
end

function BurdJournals.UI.MainPanel:getTraitLearningTime()
    local baseTime = BurdJournals.getSandboxOption("LearningTimePerTrait") or 5.0
    local multiplier = BurdJournals.getSandboxOption("LearningTimeMultiplier") or 1.0
    local readingMultiplier = self:getReadingSpeedMultiplier()
    return baseTime * multiplier * readingMultiplier
end

function BurdJournals.UI.MainPanel:getStatLearningTime()
    -- Stats use the same timing as traits (5 seconds base)
    local baseTime = BurdJournals.getSandboxOption("LearningTimePerTrait") or 5.0
    local multiplier = BurdJournals.getSandboxOption("LearningTimeMultiplier") or 1.0
    local readingMultiplier = self:getReadingSpeedMultiplier()
    return baseTime * multiplier * readingMultiplier
end

function BurdJournals.UI.MainPanel:startLearningSkill(skillName, xp)
    if self.learningState.active then

        return false
    end

    local rewards = {{type = "skill", name = skillName, xp = xp}}

    if BurdJournals.queueLearnAction then
        return BurdJournals.queueLearnAction(self.player, self.journal, rewards, false, self)
    end

    self.learningState = {
        active = true,
        skillName = skillName,
        traitId = nil,
        isAbsorbAll = false,
        progress = 0,
        totalTime = self:getSkillLearningTime(),
        startTime = getTimestampMs and getTimestampMs() or 0,
        pendingRewards = rewards,
        currentIndex = 1,
        queue = {},
    }

    Events.OnTick.Add(BurdJournals.UI.MainPanel.onLearningTickStatic)

    self:playSound(BurdJournals.Sounds.PAGE_TURN)

    return true
end

function BurdJournals.UI.MainPanel:startLearningTrait(traitId)
    if self.learningState.active then
        return false
    end

    if BurdJournals.playerHasTrait(self.player, traitId) then
        return false
    end

    local rewards = {{type = "trait", name = traitId}}

    if BurdJournals.queueLearnAction then
        return BurdJournals.queueLearnAction(self.player, self.journal, rewards, false, self)
    end

    self.learningState = {
        active = true,
        skillName = nil,
        traitId = traitId,
        forgetTraitId = nil,
        isAbsorbAll = false,
        progress = 0,
        totalTime = self:getTraitLearningTime(),
        startTime = getTimestampMs and getTimestampMs() or 0,
        pendingRewards = rewards,
        currentIndex = 1,
        queue = {},
    }

    Events.OnTick.Add(BurdJournals.UI.MainPanel.onLearningTickStatic)

    self:playSound(BurdJournals.Sounds.PAGE_TURN)

    return true
end

function BurdJournals.UI.MainPanel:startLearningForgetTrait(traitId)
    if self.learningState.active then
        return false
    end

    if not (BurdJournals.playerHasTrait and BurdJournals.playerHasTrait(self.player, traitId)) then
        return false
    end

    local rewards = {{type = "forget", name = traitId}}

    if BurdJournals.queueLearnAction then
        return BurdJournals.queueLearnAction(self.player, self.journal, rewards, false, self)
    end

    self.learningState = {
        active = true,
        skillName = nil,
        traitId = nil,
        forgetTraitId = traitId,
        isAbsorbAll = false,
        progress = 0,
        totalTime = self:getTraitLearningTime(),
        startTime = getTimestampMs and getTimestampMs() or 0,
        pendingRewards = rewards,
        currentIndex = 1,
        queue = {},
    }

    Events.OnTick.Add(BurdJournals.UI.MainPanel.onLearningTickStatic)

    self:playSound(BurdJournals.Sounds.PAGE_TURN)

    return true
end

function BurdJournals.UI.MainPanel:startLearningRecipe(recipeName)
    if self.learningState.active then
        return false
    end

    local rewards = {{type = "recipe", name = recipeName}}

    if BurdJournals.queueLearnAction then
        return BurdJournals.queueLearnAction(self.player, self.journal, rewards, false, self)
    end

    self.learningState = {
        active = true,
        skillName = nil,
        traitId = nil,
        forgetTraitId = nil,
        recipeName = recipeName,
        isAbsorbAll = false,
        progress = 0,
        totalTime = self:getRecipeLearningTime(),
        startTime = getTimestampMs and getTimestampMs() or 0,
        pendingRewards = rewards,
        currentIndex = 1,
        queue = {},
    }

    Events.OnTick.Add(BurdJournals.UI.MainPanel.onLearningTickStatic)

    self:playSound(BurdJournals.Sounds.PAGE_TURN)

    return true
end

function BurdJournals.UI.MainPanel:startLearningStat(statId, value)
    if self.learningState.active then
        return false
    end

    -- Validate the stat can be absorbed
    local journalData = BurdJournals.getJournalData(self.journal)
    if not journalData then return false end

    local canAbsorb, recValue, curValue, reason = BurdJournals.canAbsorbStat(journalData, self.player, statId)
    if not canAbsorb then
        -- Convert reason codes to user-friendly messages
        local message = BurdJournals.safeGetText("UI_BurdJournals_CannotAbsorbStat", "Cannot absorb this stat")
        if reason == "not_absorbable" then
            message = BurdJournals.safeGetText("UI_BurdJournals_StatNotAbsorbable", "This stat cannot be absorbed")
        elseif reason == "already_claimed" then
            message = BurdJournals.safeGetText("UI_BurdJournals_StatAlreadyClaimed", "Already claimed from this journal")
        elseif reason == "no_benefit" then
            message = BurdJournals.safeGetText("UI_BurdJournals_StatNoBenefit", "Your current value is already higher or equal")
        end
        self:showFeedback(message, "warn")
        return false
    end

    local rewards = {{type = "stat", name = statId, value = value}}

    if BurdJournals.queueLearnAction then
        return BurdJournals.queueLearnAction(self.player, self.journal, rewards, false, self)
    end

    self.learningState = {
        active = true,
        skillName = nil,
        traitId = nil,
        forgetTraitId = nil,
        recipeName = nil,
        statId = statId,
        isAbsorbAll = false,
        progress = 0,
        totalTime = self:getStatLearningTime(),
        startTime = getTimestampMs and getTimestampMs() or 0,
        pendingRewards = rewards,
        currentIndex = 1,
        queue = {},
    }

    Events.OnTick.Add(BurdJournals.UI.MainPanel.onLearningTickStatic)

    self:playSound(BurdJournals.Sounds.PAGE_TURN)

    return true
end

function BurdJournals.UI.MainPanel:getRecipeLearningTime()

    local baseTime = (BurdJournals.getSandboxOption("LearningTimePerRecipe") or 2.0) * 0.35
    local multiplier = BurdJournals.getSandboxOption("LearningTimeMultiplier") or 1.0
    local readingMultiplier = self:getReadingSpeedMultiplier()
    return baseTime * multiplier * readingMultiplier
end

function BurdJournals.UI.MainPanel:startLearningAll()
    if self.learningState.active then
        if self.learningState.isAbsorbAll ~= true then
            self.pendingLearnBulkIntent = { mode = "all" }
            return true
        end
        self:showFeedback(getText("UI_BurdJournals_AlreadyReading") or "Already reading...", "warn")
        return false
    end
    if self:isLimitedClaimLootJournal() then
        self:showFeedback(getText("UI_BurdJournals_LimitedLootClaimsNoBatch") or "Batch absorb is disabled for limited-claim loot journals.", "warn")
        return false
    end

    local journalData = BurdJournals.getJournalData(self.journal)
    if not journalData then return false end

    local isPlayerJournal = self.isPlayerJournal or self.mode == "view"
    local pendingRewards = {}
    local sessionClaimedSkills = self.sessionClaimedSkills or {}
    local function isSkillClaimedForPendingReward(skillName)
        if not skillName then
            return false
        end
        if BurdJournals.hasCharacterClaimedSkill(journalData, self.player, skillName) then
            return true
        end
        return sessionClaimedSkills[skillName] == true
    end

    if journalData.skills then
        for skillName, skillData in pairs(journalData.skills) do
            if BurdJournals.isSkillVisibleForJournal(journalData, skillName) then
                local shouldInclude = false
                local recordedXP = BurdJournals.getNormalizedSkillClaimEntry(journalData, skillName, skillData.xp or 0)
                local preview = BurdJournals.getClaimPreviewForSkill(journalData, self.player, skillName, recordedXP, 0, BurdJournals.getClaimSessionIdForPanel(self, false))

                if isPlayerJournal then
                    local perk = BurdJournals.getPerkByName(skillName)
                    if perk then
                        local playerXP = BurdJournals.getPlayerSkillTotalXP and BurdJournals.getPlayerSkillTotalXP(self.player, perk, skillName) or self.player:getXp():getXP(perk)
                        local claimTargetXP = BurdJournals.getClaimTargetXPForPlayer(journalData, self.player, skillName, preview.effectiveXP)
                        shouldInclude = playerXP < claimTargetXP
                    end
                else
                    -- For non-player journals, check per-character claim status
                    if not isSkillClaimedForPendingReward(skillName) then
                        shouldInclude = true
                    end
                end

                if shouldInclude then
                    table.insert(pendingRewards, {type = "skill", name = skillName, xp = recordedXP})
                end
            end
        end
    end

    local hasTraits = BurdJournals.hasTraitEntriesForJournal(journalData)
    if hasTraits then
        for traitId, _ in pairs(journalData.traits) do
            local shouldInclude = false

            if isPlayerJournal then

                if not BurdJournals.playerHasTrait(self.player, traitId) then
                    shouldInclude = true
                end
            else

                if not BurdJournals.hasCharacterClaimedTrait(journalData, self.player, traitId) and
                   not BurdJournals.playerHasTrait(self.player, traitId) then
                    shouldInclude = true
                end
            end

            if shouldInclude then
                table.insert(pendingRewards, {type = "trait", name = traitId})
            end
        end
    end

    if journalData.recipes then
        for recipeName, _ in pairs(journalData.recipes) do
            local shouldInclude = false

            if isPlayerJournal then

                if not BurdJournals.playerKnowsRecipe(self.player, recipeName) then
                    shouldInclude = true
                end
            else

                if not BurdJournals.hasCharacterClaimedRecipe(journalData, self.player, recipeName) and
                   not BurdJournals.playerKnowsRecipe(self.player, recipeName) then
                    shouldInclude = true
                end
            end

            if shouldInclude then
                table.insert(pendingRewards, {type = "recipe", name = recipeName})
            end
        end
    end

    -- Add stats to the queue with timed action like other rewards
    if journalData.stats and BurdJournals.ABSORBABLE_STATS then
        for statId, statData in pairs(journalData.stats) do
            local canAbsorb, recValue, curValue, reason = BurdJournals.canAbsorbStat(journalData, self.player, statId)
            if canAbsorb and recValue then
                table.insert(pendingRewards, {type = "stat", name = statId, value = recValue})
            end
        end
    end

    if #pendingRewards == 0 then
        self:showFeedback(getText("UI_BurdJournals_NoNewRewards") or "No new rewards to claim", "muted")
        return false
    end

    if self:isLimitedClaimLootJournal() then
        local claimsLeft = self:getLimitedLootClaimsLeft() or 0
        if claimsLeft <= 0 then
            self:showFeedback(getText("UI_BurdJournals_LimitedLootClaimsSpent") or "This journal has no claims left.", "error")
            return false
        end
        if #pendingRewards > claimsLeft then
            self:showFeedback(getText("UI_BurdJournals_LimitedLootClaimsChooseIndividually") or "Choose rewards individually from this journal.", "warn")
            return false
        end
    end

    if BurdJournals.queueLearnAction then
        return BurdJournals.queueLearnAction(self.player, self.journal, pendingRewards, true, self)
    end
    return false
end

function BurdJournals.UI.MainPanel:startLearningTab(tabId)
    if self.learningState.active then
        if self.learningState.isAbsorbAll ~= true then
            self.pendingLearnBulkIntent = { mode = "tab", tabId = tabId }
            return true
        end
        self:showFeedback(getText("UI_BurdJournals_AlreadyReading") or "Already reading...", "warn")
        return false
    end

    local journalData = BurdJournals.getJournalData(self.journal)
    if not journalData then return false end

    local isPlayerJournal = self.isPlayerJournal or self.mode == "view"
    local pendingRewards = {}
    local sessionClaimedSkills = self.sessionClaimedSkills or {}
    local function isSkillClaimedForPendingReward(skillName)
        if not skillName then
            return false
        end
        if BurdJournals.hasCharacterClaimedSkill(journalData, self.player, skillName) then
            return true
        end
        return sessionClaimedSkills[skillName] == true
    end

    if tabId == "skills" then

        if journalData.skills then
            for skillName, skillData in pairs(journalData.skills) do
                if BurdJournals.isSkillVisibleForJournal(journalData, skillName) then
                    local shouldInclude = false
                    local recordedXP = BurdJournals.getNormalizedSkillClaimEntry(journalData, skillName, skillData.xp or 0)
                    local preview = BurdJournals.getClaimPreviewForSkill(journalData, self.player, skillName, recordedXP, 0, BurdJournals.getClaimSessionIdForPanel(self, false))

                    if isPlayerJournal then
                        local perk = BurdJournals.getPerkByName(skillName)
                        if perk then
                            local playerXP = BurdJournals.getPlayerSkillTotalXP and BurdJournals.getPlayerSkillTotalXP(self.player, perk, skillName) or self.player:getXp():getXP(perk)
                            local claimTargetXP = BurdJournals.getClaimTargetXPForPlayer(journalData, self.player, skillName, preview.effectiveXP)
                            if playerXP < claimTargetXP then
                                shouldInclude = true
                            end
                        end
                    else
                        if not isSkillClaimedForPendingReward(skillName) then
                            shouldInclude = true
                        end
                    end

                    if shouldInclude then
                        table.insert(pendingRewards, {type = "skill", name = skillName, xp = recordedXP})
                    end
                end
            end
        end

    elseif tabId == "traits" then

        local hasTraits = BurdJournals.hasTraitEntriesForJournal(journalData)
        if hasTraits then
            for traitId, _ in pairs(journalData.traits) do
                local shouldInclude = false

                if isPlayerJournal then
                    if not BurdJournals.playerHasTrait(self.player, traitId) then
                        shouldInclude = true
                    end
                else

                    if not BurdJournals.hasCharacterClaimedTrait(journalData, self.player, traitId) and
                       not BurdJournals.playerHasTrait(self.player, traitId) then
                        shouldInclude = true
                    end
                end

                if shouldInclude then
                    table.insert(pendingRewards, {type = "trait", name = traitId})
                end
            end
        end

    elseif tabId == "recipes" then

        if journalData.recipes then
            for recipeName, _ in pairs(journalData.recipes) do
                local shouldInclude = false

                if isPlayerJournal then

                    if not BurdJournals.playerKnowsRecipe(self.player, recipeName) then
                        shouldInclude = true
                    end
                else

                    if not BurdJournals.hasCharacterClaimedRecipe(journalData, self.player, recipeName) and
                       not BurdJournals.playerKnowsRecipe(self.player, recipeName) then
                        shouldInclude = true
                    end
                end

                if shouldInclude then
                    table.insert(pendingRewards, {type = "recipe", name = recipeName})
                end
            end
        end

    elseif tabId == "stats" then
        -- Stats use the timed action queue like other rewards
        if journalData.stats and BurdJournals.ABSORBABLE_STATS then
            for statId, statData in pairs(journalData.stats) do
                local canAbsorb, recValue, curValue, reason = BurdJournals.canAbsorbStat(journalData, self.player, statId)
                if canAbsorb and recValue then
                    table.insert(pendingRewards, {type = "stat", name = statId, value = recValue})
                end
            end
        end
    end

    if #pendingRewards == 0 then
        local tabName = self:getTabDisplayName(tabId)
        self:showFeedback(getText("UI_BurdJournals_NoNewRewards") or "No new rewards", "muted")
        return false
    end

    if self:isLimitedClaimLootJournal() then
        local claimsLeft = self:getLimitedLootClaimsLeft() or 0
        if claimsLeft <= 0 then
            self:showFeedback(getText("UI_BurdJournals_LimitedLootClaimsSpent") or "This journal has no claims left.", "error")
            return false
        end
        if #pendingRewards > claimsLeft then
            self:showFeedback(getText("UI_BurdJournals_LimitedLootClaimsChooseIndividually") or "Choose rewards individually from this journal.", "warn")
            return false
        end
    end

    if BurdJournals.queueLearnAction then
        return BurdJournals.queueLearnAction(self.player, self.journal, pendingRewards, true, self)
    end
    return false
end

function BurdJournals.UI.MainPanel:cancelLearning()
    self.pendingLearnAllContinuation = nil
    self.pendingLearnSingleContinuation = nil
    self.pendingLearnBulkIntent = nil
    if self.learningState.active then
        self.learningState.active = false
        Events.OnTick.Remove(BurdJournals.UI.MainPanel.onLearningTickStatic)

        if self.learningState.timedAction and ISTimedActionQueue then
            ISTimedActionQueue.clear(self.player)
        end
    end
    self.learningState = {
        active = false,
        skillName = nil,
        traitId = nil,
        forgetTraitId = nil,
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

function BurdJournals.UI.MainPanel:getSkillRecordingTime()
    local baseTime = (BurdJournals.getSandboxOption("LearningTimePerSkill") or 3.0) * 0.5
    local multiplier = BurdJournals.getSandboxOption("LearningTimeMultiplier") or 1.0
    return baseTime * multiplier
end

function BurdJournals.UI.MainPanel:getTraitRecordingTime()
    local baseTime = (BurdJournals.getSandboxOption("LearningTimePerTrait") or 5.0) * 0.5
    local multiplier = BurdJournals.getSandboxOption("LearningTimeMultiplier") or 1.0
    return baseTime * multiplier
end

function BurdJournals.UI.MainPanel:isWritingToolRequiredForRecordMode()
    if self.mode ~= "log" then
        return false
    end
    return BurdJournals.getSandboxOption("RequirePenToWrite") ~= false
end

function BurdJournals.UI.MainPanel:hasRecordWritingTool()
    if not self:isWritingToolRequiredForRecordMode() then
        return true
    end
    return (BurdJournals.hasWritingTool and BurdJournals.hasWritingTool(self.player)) or false
end

function BurdJournals.UI.MainPanel:showNeedWritingToolFeedback()
    self:showFeedback(getText("Tooltip_BurdJournals_NeedPen") or "Requires a pen or pencil to write.", {r=0.9, g=0.5, b=0.3})
end

function BurdJournals.UI.MainPanel:ensureRecordWritingTool()
    if self:hasRecordWritingTool() then
        return true
    end
    self:showNeedWritingToolFeedback()
    return false
end

function BurdJournals.UI.MainPanel:updateRecordActionAvailability()
    if self.mode ~= "log" then
        return
    end

    local canWrite = self:hasRecordWritingTool()
    if self.recordTabBtn and self.recordTabBtn.setVisible then
        self.recordTabBtn:setVisible(canWrite)
    end
    if self.recordAllBtn and self.recordAllBtn.setVisible then
        self.recordAllBtn:setVisible(canWrite)
    end
    if self._recordButtonLayout and self.closeBottomBtn and self.closeBottomBtn.setX then
        local closeX = canWrite and self._recordButtonLayout.closeX
            or math.floor((self.width - self.closeBottomBtn:getWidth()) / 2)
        self.closeBottomBtn:setX(closeX)
    end
end

function BurdJournals.UI.MainPanel:startRecordingSkill(skillName, xp, level, baselineXP)
    if self.recordingState and self.recordingState.active then
        return false
    end
    if not self:ensureRecordWritingTool() then
        return false
    end

    if not self.recordingState then
        self.recordingState = {}
    end

    local records = {{type = "skill", name = skillName, xp = xp, level = level, baselineXP = baselineXP}}

    if BurdJournals.queueRecordAction then
        return BurdJournals.queueRecordAction(self.player, self.journal, records, false, self)
    end

    self.recordingState = {
        active = true,
        skillName = skillName,
        traitId = nil,
        isRecordAll = false,
        progress = 0,
        totalTime = self:getSkillRecordingTime(),
        startTime = getTimestampMs and getTimestampMs() or 0,
        pendingRecords = records,
        currentIndex = 1,
        queue = {},
    }

    Events.OnTick.Add(BurdJournals.UI.MainPanel.onRecordingTickStatic)
    return true
end

function BurdJournals.UI.MainPanel:startRecordingTrait(traitId)
    if self.recordingState and self.recordingState.active then
        return false
    end
    if not self:ensureRecordWritingTool() then
        return false
    end

    if not self.recordingState then
        self.recordingState = {}
    end

    local records = {{type = "trait", name = traitId}}

    if BurdJournals.queueRecordAction then
        return BurdJournals.queueRecordAction(self.player, self.journal, records, false, self)
    end

    self.recordingState = {
        active = true,
        skillName = nil,
        traitId = traitId,
        isRecordAll = false,
        progress = 0,
        totalTime = self:getTraitRecordingTime(),
        startTime = getTimestampMs and getTimestampMs() or 0,
        pendingRecords = records,
        currentIndex = 1,
        queue = {},
    }

    Events.OnTick.Add(BurdJournals.UI.MainPanel.onRecordingTickStatic)
    return true
end

function BurdJournals.UI.MainPanel:startRecordingStat(statId, value)
    if self.recordingState and self.recordingState.active then
        return false
    end
    if not self:ensureRecordWritingTool() then
        return false
    end

    if not self.recordingState then
        self.recordingState = {}
    end

    local records = {{type = "stat", name = statId, value = value}}

    if BurdJournals.queueRecordAction then
        return BurdJournals.queueRecordAction(self.player, self.journal, records, false, self)
    end

    self.recordingState = {
        active = true,
        skillName = nil,
        traitId = nil,
        statId = statId,
        isRecordAll = false,
        progress = 0,
        totalTime = self:getStatRecordingTime(),
        startTime = getTimestampMs and getTimestampMs() or 0,
        pendingRecords = records,
        currentIndex = 1,
        queue = {},
    }

    Events.OnTick.Add(BurdJournals.UI.MainPanel.onRecordingTickStatic)
    return true
end

function BurdJournals.UI.MainPanel:getStatRecordingTime()
    return self:getSkillRecordingTime()
end

function BurdJournals.UI.MainPanel:getRecipeRecordingTime()
    local baseTime = (BurdJournals.getSandboxOption("LearningTimePerRecipe") or 5.0) * 0.16
    local multiplier = BurdJournals.getSandboxOption("LearningTimeMultiplier") or 1.0
    return baseTime * multiplier
end

function BurdJournals.UI.MainPanel:startRecordingRecipe(recipeName)
    if self.recordingState and self.recordingState.active then
        return false
    end
    if not self:ensureRecordWritingTool() then
        return false
    end

    if not self.recordingState then
        self.recordingState = {}
    end

    local records = {{type = "recipe", name = recipeName}}

    if BurdJournals.queueRecordAction then
        return BurdJournals.queueRecordAction(self.player, self.journal, records, false, self)
    end

    self.recordingState = {
        active = true,
        skillName = nil,
        traitId = nil,
        statId = nil,
        recipeName = recipeName,
        isRecordAll = false,
        progress = 0,
        totalTime = self:getRecipeRecordingTime(),
        startTime = getTimestampMs and getTimestampMs() or 0,
        pendingRecords = records,
        currentIndex = 1,
        queue = {},
    }

    Events.OnTick.Add(BurdJournals.UI.MainPanel.onRecordingTickStatic)
    return true
end

function BurdJournals.UI.MainPanel:checkJournalCapacity(pendingSkillCount, pendingTraitCount, pendingRecipeCount)
    local limits = BurdJournals.Limits or {}
    local warnings = {}

    local currentSkills = 0
    local currentTraits = 0
    local currentRecipes = 0

    if self.recordedSkills then
        for _ in pairs(self.recordedSkills) do currentSkills = currentSkills + 1 end
    end
    if self.recordedTraits then
        for _ in pairs(self.recordedTraits) do currentTraits = currentTraits + 1 end
    end
    if self.recordedRecipes then
        for _ in pairs(self.recordedRecipes) do currentRecipes = currentRecipes + 1 end
    end

    local maxSkills = tonumber(limits.MAX_SKILLS) or 0
    local maxTraits = tonumber(limits.MAX_TRAITS) or 0
    local maxRecipes = tonumber(limits.MAX_RECIPES) or 0
    local warnSkills = tonumber(limits.WARN_SKILLS) or 0
    local warnTraits = tonumber(limits.WARN_TRAITS) or 0
    local warnRecipes = tonumber(limits.WARN_RECIPES) or 0

    local newSkillTotal = currentSkills + (pendingSkillCount or 0)
    local newTraitTotal = currentTraits + (pendingTraitCount or 0)
    local newRecipeTotal = currentRecipes + (pendingRecipeCount or 0)

    if maxSkills > 0 and newSkillTotal > maxSkills then
        return false, BurdJournals.formatText("Too many skills! Journal limit is %d (would have %d)", maxSkills, newSkillTotal)
    end
    if maxTraits > 0 and newTraitTotal > maxTraits then
        return false, BurdJournals.formatText("Too many traits! Journal limit is %d (would have %d)", maxTraits, newTraitTotal)
    end
    if maxRecipes > 0 and newRecipeTotal > maxRecipes then
        return false, BurdJournals.formatText("Too many recipes! Journal limit is %d (would have %d)", maxRecipes, newRecipeTotal)
    end

    if maxSkills > 0 and warnSkills > 0 and newSkillTotal >= warnSkills and pendingSkillCount > 0 then
        table.insert(warnings, BurdJournals.formatText(getText("UI_BurdJournals_CapacitySkills") or "Skills: %d/%d", newSkillTotal, maxSkills))
    end
    if maxTraits > 0 and warnTraits > 0 and newTraitTotal >= warnTraits and pendingTraitCount > 0 then
        table.insert(warnings, BurdJournals.formatText(getText("UI_BurdJournals_CapacityTraits") or "Traits: %d/%d", newTraitTotal, maxTraits))
    end
    if maxRecipes > 0 and warnRecipes > 0 and newRecipeTotal >= warnRecipes and pendingRecipeCount > 0 then
        table.insert(warnings, BurdJournals.formatText(getText("UI_BurdJournals_CapacityRecipes") or "Recipes: %d/%d", newRecipeTotal, maxRecipes))
    end

    if #warnings > 0 then
        return true, BurdJournals.formatText(getText("UI_BurdJournals_ApproachingCapacity") or "Journal approaching capacity: %s", table.concat(warnings, ", "))
    end

    return true, nil
end

function BurdJournals.UI.MainPanel:getStatUpdateForRecordData(journalData, statId)
    if not self.player then
        return false, nil, nil
    end
    local stat = BurdJournals.getStatById and BurdJournals.getStatById(statId) or nil
    if not stat then
        return false, nil, nil
    end

    local currentValue = BurdJournals.getStatValue and BurdJournals.getStatValue(self.player, statId) or nil
    local recordedStats = type(journalData) == "table" and type(journalData.stats) == "table" and journalData.stats or {}
    local recorded = recordedStats[statId]
    local recordedValue = type(recorded) == "table" and recorded.value or recorded

    if stat.isText then
        return recordedValue == nil or recordedValue ~= currentValue, currentValue, recordedValue
    end
    return recordedValue == nil or (tonumber(currentValue) or 0) > (tonumber(recordedValue) or 0), currentValue, recordedValue
end

function BurdJournals.UI.MainPanel:startRecordingAll()
    if self.recordingState and self.recordingState.active then
        if self.recordingState.isRecordAll ~= true then
            self.pendingRecordBulkIntent = { mode = "all" }
            return true
        end
        BurdJournals.debugPrint("[BurdJournals] startRecordingAll: BLOCKED - recordingState.active is true")
        return false
    end
    if not self:ensureRecordWritingTool() then
        return false
    end
    BurdJournals.debugPrint("[BurdJournals] startRecordingAll: Starting...")

    local journalData = self:resolvePendingRecordJournalDataForRefresh() or BurdJournals.getJournalData(self.journal) or {}
    local useBaseline, autoRepairedMode = BurdJournals.resolveJournalRecordingModeForPlayer(journalData, self.player)
    if BurdJournals.shouldForceBaselineRecordingMode(journalData, self.player, autoRepairedMode) then
        useBaseline = true
    end
    if autoRepairedMode then
        BurdJournals.debugPrint("[BurdJournals] startRecordingAll: detected legacy absolute journal entries while baseline flag was set; forcing baseline-mode recording so entries can be repaired")
    end

    local baselineReady, normalizedUseBaseline = BurdJournals.ensureBaselineReadyForRecording(self, useBaseline, "startRecordingAll")
    useBaseline = normalizedUseBaseline
    if not baselineReady then
        self:showFeedback(getText("UI_BurdJournals_BaselineInitializing") or "Please wait - character data initializing...", {r=1, g=0.8, b=0.3})
        return false
    end

    if not self.recordingState then
        self.recordingState = {}
    end

    local pendingRecords = {}
    local playerJournalContext = {}
    if type(journalData) == "table" then
        for key, value in pairs(journalData) do
            playerJournalContext[key] = value
        end
    end
    playerJournalContext.isPlayerCreated = true

    self.recordedSkills = journalData.skills or {}
    self.recordedTraits = journalData.traits or {}
    self.recordedRecipes = journalData.recipes or {}

    local allowedSkills = BurdJournals.getAllowedSkills()
    local recordedSkills = self.recordedSkills
    local recordedTraits = self.recordedTraits

    for _, skillName in ipairs(allowedSkills) do
        if BurdJournals.isSkillRecordableInPlayerJournal(skillName) then
            local perk = BurdJournals.getPerkByName(skillName)
            if perk then
                local currentXP = BurdJournals.getPlayerSkillTotalXP and BurdJournals.getPlayerSkillTotalXP(self.player, perk, skillName) or self.player:getXp():getXP(perk)
                local currentLevel = self.player:getPerkLevel(perk)
                local recordedSkillKey = BurdJournals.resolveSkillKey and BurdJournals.resolveSkillKey(recordedSkills, skillName) or skillName
                local recordedData = recordedSkills[recordedSkillKey]
                local recordedXP = recordedData and recordedData.xp or 0

                local baselineXP = 0
                if useBaseline then
                    baselineXP = BurdJournals.getSkillBaseline(self.player, skillName)
                end

                local earnedXP = math.max(0, currentXP - baselineXP)
                local needsBaselineRepair = useBaseline
                    and BurdJournals.isLikelyAbsoluteSkillEntryForBaseline(journalData, self.player, skillName, recordedXP, currentXP, baselineXP)

                if earnedXP > 0 and (earnedXP > recordedXP or needsBaselineRepair) then
                    table.insert(pendingRecords, {type = "skill", name = skillName, xp = earnedXP, level = currentLevel, baselineXP = baselineXP})
                end
            end
        end
    end

    local playerTraits = BurdJournals.collectPlayerTraits(self.player)
    local traitBaseline = BurdJournals.buildTraitLookup and BurdJournals.buildTraitLookup(BurdJournals.getTraitBaseline(self.player) or {}) or (BurdJournals.getTraitBaseline(self.player) or {})
    local grantableTraits = (BurdJournals.getGrantableTraitsForJournal and BurdJournals.getGrantableTraitsForJournal(playerJournalContext))
        or (BurdJournals.getGrantableTraits and BurdJournals.getGrantableTraits())
        or BurdJournals.GRANTABLE_TRAITS or {}
    local recordedTraitLookup = BurdJournals.buildTraitLookup and BurdJournals.buildTraitLookup(recordedTraits) or recordedTraits
    local traitDebug = getDebug()
    for traitId, _ in pairs(playerTraits) do

        local isGrantable = BurdJournals.isTraitGrantable(traitId, grantableTraits)

        local isStartingTrait = BurdJournals.isTraitInLookup and BurdJournals.isTraitInLookup(traitBaseline, traitId) or traitBaseline[traitId] or traitBaseline[string.lower(traitId)]

        local isRecorded = BurdJournals.isTraitInLookup and BurdJournals.isTraitInLookup(recordedTraitLookup, traitId) or recordedTraits[traitId] or recordedTraits[string.lower(traitId)]

        if traitDebug then
            BurdJournals.debugPrint("[BurdJournals] Trait check: " .. traitId .. " | grantable=" .. tostring(isGrantable) ..
                  " | starting=" .. tostring(isStartingTrait) .. " | recorded=" .. tostring(isRecorded))
        end

        if isGrantable
            and (not BurdJournals.isTraitEnabledForJournal or BurdJournals.isTraitEnabledForJournal(playerJournalContext, traitId))
            and not isStartingTrait
            and not isRecorded
        then
            table.insert(pendingRecords, {type = "trait", name = traitId})
        end
    end

    if BurdJournals.getSandboxOption("EnableStatRecording") then
        for _, stat in ipairs(BurdJournals.RECORDABLE_STATS) do
            if BurdJournals.isStatEnabled(stat.id) then
                local canUpdate, currentVal, _ = self:getStatUpdateForRecordData(journalData, stat.id)
                if canUpdate then
                    table.insert(pendingRecords, {type = "stat", name = stat.id, value = currentVal})
                end
            end
        end
    end

    if BurdJournals.isRecipeRecordingEnabled() and BurdJournals.areRecipesEnabledForJournal(playerJournalContext) then
        local recordedRecipes = self.recordedRecipes or {}
        local playerRecipes = BurdJournals.collectPlayerMagazineRecipes(self.player)
        for recipeName, recipeData in pairs(playerRecipes) do
            local recordedRecipeKey = BurdJournals.resolveRecipeKey and BurdJournals.resolveRecipeKey(recordedRecipes, recipeName) or recipeName
            if not recordedRecipeKey or not recordedRecipes[recordedRecipeKey] then
                table.insert(pendingRecords, {type = "recipe", name = recipeName})
            end
        end
    end

    if #pendingRecords == 0 then
        self:showFeedback(getText("UI_BurdJournals_NothingNewToRecord") or "Nothing new to record", {r=0.7, g=0.7, b=0.5})
        return false
    end

    local pendingSkillCount, pendingTraitCount, pendingRecipeCount = 0, 0, 0
    for _, record in ipairs(pendingRecords) do
        if record.type == "skill" then pendingSkillCount = pendingSkillCount + 1
        elseif record.type == "trait" then pendingTraitCount = pendingTraitCount + 1
        elseif record.type == "recipe" then pendingRecipeCount = pendingRecipeCount + 1
        end
    end

    local canRecord, capacityMsg = self:checkJournalCapacity(pendingSkillCount, pendingTraitCount, pendingRecipeCount)
    if not canRecord then
        self:showFeedback(capacityMsg, {r=1, g=0.4, b=0.4})
        return false
    end
    if capacityMsg then

        self:showFeedback(capacityMsg, {r=1, g=0.8, b=0.3})
    end

    if BurdJournals.queueRecordAction then
        return BurdJournals.queueRecordAction(self.player, self.journal, pendingRecords, true, self)
    end

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
        startTime = getTimestampMs and getTimestampMs() or 0,
        pendingRecords = pendingRecords,
        currentIndex = 1,
        queue = {},
    }

    Events.OnTick.Add(BurdJournals.UI.MainPanel.onRecordingTickStatic)
    return true
end

function BurdJournals.UI.MainPanel:startRecordingTab(tabId)
    if self.recordingState and self.recordingState.active then
        if self.recordingState.isRecordAll ~= true then
            self.pendingRecordBulkIntent = { mode = "tab", tabId = tabId }
            return true
        end
        return false
    end
    if not self:ensureRecordWritingTool() then
        return false
    end

    local journalData = self:resolvePendingRecordJournalDataForRefresh() or BurdJournals.getJournalData(self.journal) or {}
    local useBaseline, autoRepairedMode = BurdJournals.resolveJournalRecordingModeForPlayer(journalData, self.player)
    if BurdJournals.shouldForceBaselineRecordingMode(journalData, self.player, autoRepairedMode) then
        useBaseline = true
    end
    if autoRepairedMode then
        BurdJournals.debugPrint("[BurdJournals] startRecordingTab: detected legacy absolute journal entries while baseline flag was set; forcing baseline-mode recording so entries can be repaired")
    end

    local baselineReady, normalizedUseBaseline = BurdJournals.ensureBaselineReadyForRecording(self, useBaseline, "startRecordingTab")
    useBaseline = normalizedUseBaseline
    if not baselineReady then
        self:showFeedback(getText("UI_BurdJournals_BaselineInitializing") or "Please wait - character data initializing...", {r=1, g=0.8, b=0.3})
        return false
    end

    if not self.recordingState then
        self.recordingState = {}
    end

    local pendingRecords = {}
    local playerJournalContext = {}
    if type(journalData) == "table" then
        for key, value in pairs(journalData) do
            playerJournalContext[key] = value
        end
    end
    playerJournalContext.isPlayerCreated = true

    self.recordedSkills = journalData.skills or {}
    self.recordedTraits = journalData.traits or {}
    self.recordedRecipes = journalData.recipes or {}

    local recordedSkills = self.recordedSkills
    local recordedTraits = self.recordedTraits

    if tabId == "skills" then

        local allowedSkills = BurdJournals.getAllowedSkills()
        for _, skillName in ipairs(allowedSkills) do
            if BurdJournals.isSkillRecordableInPlayerJournal(skillName) then
                local perk = BurdJournals.getPerkByName(skillName)
                if perk then
                    local currentXP = BurdJournals.getPlayerSkillTotalXP and BurdJournals.getPlayerSkillTotalXP(self.player, perk, skillName) or self.player:getXp():getXP(perk)
                    local currentLevel = self.player:getPerkLevel(perk)
                    local recordedSkillKey = BurdJournals.resolveSkillKey and BurdJournals.resolveSkillKey(recordedSkills, skillName) or skillName
                    local recordedData = recordedSkills[recordedSkillKey]
                    local recordedXP = recordedData and recordedData.xp or 0

                    local baselineXP = 0
                    if useBaseline then
                        baselineXP = BurdJournals.getSkillBaseline(self.player, skillName)
                    end

                    local earnedXP = math.max(0, currentXP - baselineXP)
                    local needsBaselineRepair = useBaseline
                        and BurdJournals.isLikelyAbsoluteSkillEntryForBaseline(journalData, self.player, skillName, recordedXP, currentXP, baselineXP)

                    if earnedXP > 0 and (earnedXP > recordedXP or needsBaselineRepair) then
                        table.insert(pendingRecords, {type = "skill", name = skillName, xp = earnedXP, level = currentLevel, baselineXP = baselineXP})
                    end
                end
            end
        end

    elseif tabId == "traits" then

        local playerTraits = BurdJournals.collectPlayerTraits(self.player)
        local traitBaseline = BurdJournals.buildTraitLookup and BurdJournals.buildTraitLookup(BurdJournals.getTraitBaseline(self.player) or {}) or (BurdJournals.getTraitBaseline(self.player) or {})
        local grantableTraits = (BurdJournals.getGrantableTraitsForJournal and BurdJournals.getGrantableTraitsForJournal(playerJournalContext))
            or (BurdJournals.getGrantableTraits and BurdJournals.getGrantableTraits())
            or BurdJournals.GRANTABLE_TRAITS or {}
        local recordedTraitLookup = BurdJournals.buildTraitLookup and BurdJournals.buildTraitLookup(recordedTraits) or recordedTraits
        for traitId, _ in pairs(playerTraits) do

            local isGrantable = BurdJournals.isTraitGrantable(traitId, grantableTraits)
            local isStartingTrait = BurdJournals.isTraitInLookup and BurdJournals.isTraitInLookup(traitBaseline, traitId) or traitBaseline[traitId] or traitBaseline[string.lower(traitId)]

            local isRecorded = BurdJournals.isTraitInLookup and BurdJournals.isTraitInLookup(recordedTraitLookup, traitId) or recordedTraits[traitId] or recordedTraits[string.lower(traitId)]

            if isGrantable
                and (not BurdJournals.isTraitEnabledForJournal or BurdJournals.isTraitEnabledForJournal(playerJournalContext, traitId))
                and not isStartingTrait
                and not isRecorded
            then
                table.insert(pendingRecords, {type = "trait", name = traitId})
            end
        end

    elseif tabId == "recipes" then

        if BurdJournals.isRecipeRecordingEnabled() and BurdJournals.areRecipesEnabledForJournal(playerJournalContext) then
            local recordedRecipes = self.recordedRecipes or {}
            local playerRecipes = BurdJournals.collectPlayerMagazineRecipes(self.player)
            for recipeName, recipeData in pairs(playerRecipes) do
                if not recordedRecipes[recipeName] then
                    table.insert(pendingRecords, {type = "recipe", name = recipeName})
                end
            end
        end

    elseif tabId == "stats" then

        if BurdJournals.getSandboxOption("EnableStatRecording") then
            for _, stat in ipairs(BurdJournals.RECORDABLE_STATS) do
                if BurdJournals.isStatEnabled(stat.id) then
                    local canUpdate, currentVal, _ = self:getStatUpdateForRecordData(journalData, stat.id)
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

    local pendingSkillCount, pendingTraitCount, pendingRecipeCount = 0, 0, 0
    for _, record in ipairs(pendingRecords) do
        if record.type == "skill" then pendingSkillCount = pendingSkillCount + 1
        elseif record.type == "trait" then pendingTraitCount = pendingTraitCount + 1
        elseif record.type == "recipe" then pendingRecipeCount = pendingRecipeCount + 1
        end
    end

    local canRecord, capacityMsg = self:checkJournalCapacity(pendingSkillCount, pendingTraitCount, pendingRecipeCount)
    if not canRecord then
        self:showFeedback(capacityMsg, {r=1, g=0.4, b=0.4})
        return false
    end
    if capacityMsg then

        self:showFeedback(capacityMsg, {r=1, g=0.8, b=0.3})
    end

    if BurdJournals.queueRecordAction then
        return BurdJournals.queueRecordAction(self.player, self.journal, pendingRecords, true, self)
    end

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
        startTime = getTimestampMs and getTimestampMs() or 0,
        pendingRecords = pendingRecords,
        currentIndex = 1,
        queue = {},
    }

    Events.OnTick.Add(BurdJournals.UI.MainPanel.onRecordingTickStatic)
    return true
end

function BurdJournals.UI.MainPanel:cancelRecording()
    self.pendingRecordBulkIntent = nil
    self.pendingRecordSingleContinuation = nil
    if self.recordingState and self.recordingState.active then
        self.recordingState.active = false
        Events.OnTick.Remove(BurdJournals.UI.MainPanel.onRecordingTickStatic)

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
    if BurdJournals.cancelRecordAllAuthoritySettle then
        BurdJournals.cancelRecordAllAuthoritySettle(self)
    end
end

function BurdJournals.UI.MainPanel.onRecordingTickStatic()
    local instance = BurdJournals.UI.MainPanel.instance
    if instance and instance.recordingState and instance.recordingState.active then
        instance:onRecordingTick()
    else
        Events.OnTick.Remove(BurdJournals.UI.MainPanel.onRecordingTickStatic)
    end
end

BurdJournals.UI.MainPanel._pendingJournalRetryActive = false

function BurdJournals.UI.MainPanel.releasePendingJournalRetryState(instance)
    if not instance then return end
    Events.OnTick.Remove(BurdJournals.UI.MainPanel.onPendingJournalRetryStatic)
    BurdJournals.UI.MainPanel._pendingJournalRetryActive = false
    instance.pendingNewJournalId = nil
    instance.pendingRecordingRetryCount = 0
    instance.pendingRecordingRetryStartedAt = nil
    instance.pendingRecordingRetryNextAt = nil
    instance.pendingRecordingData = nil
    instance.processingRecordQueue = false
    instance.recordingCompleted = false
    instance.pendingRecordAllContinuation = nil
    BurdJournals.pendingRecordAllContinuation = nil
    instance.recordingState = {
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
end

function BurdJournals.UI.MainPanel.onPendingJournalRetryStatic()
    local instance = BurdJournals.UI.MainPanel.instance
    if not instance or not instance.pendingNewJournalId then
        Events.OnTick.Remove(BurdJournals.UI.MainPanel.onPendingJournalRetryStatic)
        BurdJournals.UI.MainPanel._pendingJournalRetryActive = false
        return
    end

    local nowMs = (getTimestampMs and getTimestampMs()) or ((os.time() or 0) * 1000)
    if instance.pendingRecordingRetryNextAt and nowMs < instance.pendingRecordingRetryNextAt then return end
    instance.pendingRecordingRetryNextAt = nowMs + 150
    local newJournal = instance:findPendingNewJournalInInventory()
    if newJournal then
        BurdJournals.debugPrint("[BurdJournals] onPendingJournalRetryStatic: Found pending journal!")
        instance.journal = newJournal
        instance.pendingNewJournalId = nil
        instance.pendingRecordingRetryCount = 0
        instance.pendingRecordingRetryStartedAt = nil
        instance.pendingRecordingRetryNextAt = nil
        Events.OnTick.Remove(BurdJournals.UI.MainPanel.onPendingJournalRetryStatic)
        BurdJournals.UI.MainPanel._pendingJournalRetryActive = false

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

        local startedAt = tonumber(instance.pendingRecordingRetryStartedAt) or nowMs
        instance.pendingRecordingRetryStartedAt = startedAt
        if (nowMs - startedAt) >= 10000 then
            BurdJournals.debugPrint("[BurdJournals] onPendingJournalRetryStatic: Materialization timed out; preserving recording queue")
            Events.OnTick.Remove(BurdJournals.UI.MainPanel.onPendingJournalRetryStatic)
            BurdJournals.UI.MainPanel._pendingJournalRetryActive = false
            instance.processingRecordQueue = false
            if instance.recordingState then instance.recordingState.active = false end
            if instance.showFeedback then
                instance:showFeedback(getText("UI_BurdJournals_JournalSyncFailed") or "Error: Journal sync failed", {r=0.8, g=0.3, b=0.3})
            end
        end
    end
end

function BurdJournals.UI.MainPanel:onRecordingTick()
    if not self.recordingState or not self.recordingState.active then
        Events.OnTick.Remove(BurdJournals.UI.MainPanel.onRecordingTickStatic)
        return
    end

    if self.recordingState.timedAction then
        local action = self.recordingState.timedAction
        if action.getJobDelta then
            self.recordingState.progress = math.min(0.99, math.max(0, action:getJobDelta() or 0))
        end
        return
    end

    local now = getTimestampMs and getTimestampMs() or 0
    if now == 0 or self.recordingState.startTime == 0 then
        -- Fallback: complete immediately if no timestamp available
        self:completeRecording()
        return
    end
    local elapsed = (now - self.recordingState.startTime) / 1000.0
    self.recordingState.progress = math.min(1.0, elapsed / self.recordingState.totalTime)

    if self.recordingState.progress >= 1.0 then
        self:completeRecording()
    end
end

function BurdJournals.UI.MainPanel:completeRecording()
    Events.OnTick.Remove(BurdJournals.UI.MainPanel.onRecordingTickStatic)

    self.processingRecordQueue = true

    if self.pendingNewJournalId then
        BurdJournals.debugPrint("[BurdJournals] completeRecording: Checking for pending journal ID " .. tostring(self.pendingNewJournalId))
        local newJournal = self:findPendingNewJournalInInventory()
        if newJournal then
            BurdJournals.debugPrint("[BurdJournals] completeRecording: Found pending journal, updating reference")
            self.journal = newJournal
            self.pendingNewJournalId = nil
        else

            BurdJournals.debugPrint("[BurdJournals] completeRecording: Pending journal not found yet, scheduling retry...")
            self.pendingRecordingData = self.pendingRecordingData or {
                pendingRecords = self.recordingState.pendingRecords,
                queue = self.recordingState.queue,
                isRecordAll = self.recordingState.isRecordAll
            }
            local nowMs = (getTimestampMs and getTimestampMs()) or ((os.time() or 0) * 1000)
            self.pendingRecordingRetryStartedAt = self.pendingRecordingRetryStartedAt or nowMs
            self.pendingRecordingRetryNextAt = nowMs + 150
            if not BurdJournals.UI.MainPanel._pendingJournalRetryActive then
                BurdJournals.UI.MainPanel._pendingJournalRetryActive = true
                Events.OnTick.Add(BurdJournals.UI.MainPanel.onPendingJournalRetryStatic)
            end
            return
        end
    end

    local recordsToSend = self.recordingState.pendingRecords or {}
    local recordQueueRemaining = #(self.recordingState.queue or {})
    if self.recordingState.isRecordAll == true then
        local maxBatchSize = tonumber(BurdJournals.getSandboxOption("RecordBatchSize"))
            or tonumber(BurdJournals.RECORD_ALL_MP_BATCH_SIZE)
            or 10
        maxBatchSize = math.max(1, math.floor(maxBatchSize))

        local combinedRecords = {}
        for _, record in ipairs(recordsToSend) do
            combinedRecords[#combinedRecords + 1] = record
        end
        if type(self.recordingState.queue) == "table" then
            for _, record in ipairs(self.recordingState.queue) do
                combinedRecords[#combinedRecords + 1] = record
            end
        end

        local nextBatch = {}
        local remainingRecords = {}
        for index, record in ipairs(combinedRecords) do
            if index <= maxBatchSize then
                nextBatch[#nextBatch + 1] = record
            else
                remainingRecords[#remainingRecords + 1] = record
            end
        end

        recordsToSend = nextBatch
        self.recordingState.pendingRecords = nextBatch
        self.recordingState.queue = remainingRecords
        recordQueueRemaining = #remainingRecords

        if recordQueueRemaining > 0 then
            self.pendingRecordAllContinuation = { records = remainingRecords, remaining = remainingRecords }
            BurdJournals.pendingRecordAllContinuation = self.pendingRecordAllContinuation
        else
            self.pendingRecordAllContinuation = nil
            BurdJournals.pendingRecordAllContinuation = nil
        end
    end

    local skillsToRecord = {}
    local traitsToRecord = {}
    local statsToRecord = {}
    local recipesToRecord = {}
    local skillCount = 0
    local traitCount = 0
    local statCount = 0
    local recipeCount = 0

    for _, record in ipairs(recordsToSend) do
        if record.type == "skill" then
            skillsToRecord[record.name] = {
                xp = record.xp,
                level = record.level,
                baselineXP = record.baselineXP
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
        elseif record.type == "recipe" then
            recipesToRecord[record.name] = {
                name = record.name
            }
            recipeCount = recipeCount + 1
        end
    end

    self.pendingRecordFeedback = {
        skills = skillCount,
        traits = traitCount,
        stats = statCount,
        recipes = recipeCount
    }

    local journalData = BurdJournals.getJournalData and BurdJournals.getJournalData(self.journal) or nil
    local lookupArgs = BurdJournals.buildJournalCommandLookupArgs
        and BurdJournals.buildJournalCommandLookupArgs(self.journal, journalData, true)
        or {
            journalId = self.journal and self.journal.getID and self.journal:getID() or nil,
            journalUUID = type(journalData) == "table" and journalData.uuid or nil,
            journalFingerprint = nil,
        }
    lookupArgs.journalData = nil
    lookupArgs.itemFullType = self.journal and self.journal.getFullType and self.journal:getFullType() or lookupArgs.itemFullType
    local writingToolPayload = BurdJournals.buildWritingToolCommandPayload
        and BurdJournals.buildWritingToolCommandPayload(self.player)
        or nil

    sendClientCommand(self.player, "BurdJournals", "recordProgress", {
        journalId = lookupArgs.journalId,
        journalUUID = lookupArgs.journalUUID,
        journalFingerprint = lookupArgs.journalFingerprint,
        journalData = lookupArgs.journalData,
        itemFullType = lookupArgs.itemFullType,
        writingToolId = writingToolPayload and writingToolPayload.writingToolId or nil,
        writingToolFullType = writingToolPayload and writingToolPayload.writingToolFullType or nil,
        skills = skillsToRecord,
        traits = traitsToRecord,
        stats = statsToRecord,
        recipes = recipesToRecord,
        isRecordAll = self.recordingState and self.recordingState.isRecordAll == true,
        recordBatchSize = #recordsToSend,
        recordQueueRemaining = recordQueueRemaining
    })

    self:showFeedback(getText("UI_BurdJournals_SavingProgress") or "Saving progress...", {r=0.7, g=0.7, b=0.7})

    local savedQueue = {}
    if not self.recordingState.isRecordAll then
        savedQueue = self.recordingState.queue or {}
    end

    if #savedQueue > 0 then
        local nextRecord = table.remove(savedQueue, 1)

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
                startTime = getTimestampMs and getTimestampMs() or 0,
                pendingRecords = {{type = "skill", name = nextRecord.name, xp = nextRecord.xp, level = nextRecord.level, baselineXP = nextRecord.baselineXP}},
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
                startTime = getTimestampMs and getTimestampMs() or 0,
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
                startTime = getTimestampMs and getTimestampMs() or 0,
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
                startTime = getTimestampMs and getTimestampMs() or 0,
                pendingRecords = {{type = "recipe", name = nextRecord.name}},
                currentIndex = 1,
                queue = savedQueue,
            }
        end

        Events.OnTick.Remove(BurdJournals.UI.MainPanel.onRecordingTickStatic)
        Events.OnTick.Add(BurdJournals.UI.MainPanel.onRecordingTickStatic)

        self.processingRecordQueue = false
        return
    end

    self.recordingCompleted = true
    self.processingRecordQueue = false

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

end

function BurdJournals.UI.MainPanel:recordSkill(skillName, xp, level, baselineXP)

    if self.recordingState and self.recordingState.active and not self.recordingState.isRecordAll then
        if self:addToRecordQueue("skill", skillName, xp, level, baselineXP) then
            local displayName = BurdJournals.getPerkDisplayName(skillName) or skillName
            self:showFeedback(BurdJournals.formatText(getText("UI_BurdJournals_Queued") or "Queued: %s", displayName), {r=0.5, g=0.7, b=0.8})
        else
            self:showFeedback(getText("UI_BurdJournals_AlreadyQueued") or "Already queued", {r=0.9, g=0.7, b=0.3})
        end
        return
    end

    if not self:startRecordingSkill(skillName, xp, level, baselineXP) then
        self:showFeedback(getText("UI_BurdJournals_CannotRecord") or "Cannot record", {r=0.9, g=0.5, b=0.3})
    end
end

function BurdJournals.UI.MainPanel:recordTrait(traitId)

    if self.recordingState and self.recordingState.active and not self.recordingState.isRecordAll then
        if self:addToRecordQueue("trait", traitId) then
            local traitName = safeGetTraitName(traitId)
            self:showFeedback(BurdJournals.formatText(getText("UI_BurdJournals_Queued") or "Queued: %s", traitName), {r=0.5, g=0.7, b=0.8})
        else
            self:showFeedback(getText("UI_BurdJournals_AlreadyQueued") or "Already queued", {r=0.9, g=0.7, b=0.3})
        end
        return
    end

    if not self:startRecordingTrait(traitId) then
        self:showFeedback(getText("UI_BurdJournals_CannotRecord") or "Cannot record", {r=0.9, g=0.5, b=0.3})
    end
end

function BurdJournals.UI.MainPanel:recordStat(statId, value)

    if self.recordingState and self.recordingState.active and not self.recordingState.isRecordAll then
        if self:addToRecordQueue("stat", statId, value) then
            local stat = BurdJournals.getStatById(statId)
            local statName = stat and BurdJournals.getStatName(stat) or statId
            self:showFeedback(BurdJournals.formatText(getText("UI_BurdJournals_Queued") or "Queued: %s", statName), {r=0.5, g=0.7, b=0.8})
        else
            self:showFeedback(getText("UI_BurdJournals_AlreadyQueued") or "Already queued", {r=0.9, g=0.7, b=0.3})
        end
        return
    end

    if not self:startRecordingStat(statId, value) then
        self:showFeedback(getText("UI_BurdJournals_CannotRecord") or "Cannot record", {r=0.9, g=0.5, b=0.3})
    end
end

function BurdJournals.UI.MainPanel:recordRecipe(recipeName)

    if self.recordingState and self.recordingState.active and not self.recordingState.isRecordAll then
        if self:addToRecordQueue("recipe", recipeName) then
            local displayName = BurdJournals.getRecipeDisplayName(recipeName) or recipeName
            self:showFeedback(BurdJournals.formatText(getText("UI_BurdJournals_Queued") or "Queued: %s", displayName), {r=0.5, g=0.7, b=0.8})
        else
            self:showFeedback(getText("UI_BurdJournals_AlreadyQueued") or "Already queued", {r=0.9, g=0.7, b=0.3})
        end
        return
    end

    if not self:startRecordingRecipe(recipeName) then
        self:showFeedback(getText("UI_BurdJournals_CannotRecord") or "Cannot record", {r=0.9, g=0.5, b=0.3})
    end
end

function BurdJournals.UI.MainPanel.onLearningTickStatic()
    local instance = BurdJournals.UI.MainPanel.instance
    if instance and instance.learningState and instance.learningState.active then
        instance:onLearningTick()
    else

        Events.OnTick.Remove(BurdJournals.UI.MainPanel.onLearningTickStatic)
    end
end

function BurdJournals.UI.MainPanel:onLearningTick()
    if not self.learningState.active then
        Events.OnTick.Remove(BurdJournals.UI.MainPanel.onLearningTickStatic)
        return
    end

    local now = getTimestampMs and getTimestampMs() or 0
    if now == 0 or self.learningState.startTime == 0 then
        -- Fallback: complete immediately if no timestamp available
        self:completeLearning()
        return
    end
    local elapsed = (now - self.learningState.startTime) / 1000.0
    self.learningState.progress = math.min(1.0, elapsed / self.learningState.totalTime)

    if self.learningState.progress >= 1.0 then
        self:completeLearning()
    end
end

function BurdJournals.UI.MainPanel:buildBatchClaimRewardsPayload(rewards)
    if not self.journal or not self.player then
        return nil
    end

    local journalData = BurdJournals.getJournalData and BurdJournals.getJournalData(self.journal) or nil
    local journalUUID = type(journalData) == "table" and journalData.uuid or nil
    local lookupArgs = BurdJournals.buildJournalCommandPayload
        and BurdJournals.buildJournalCommandPayload(self.journal, journalData, true)
        or { journalId = self.journal:getID(), journalUUID = journalUUID, journalFingerprint = nil }
    local payload = {
        journalId = lookupArgs.journalId,
        journalUUID = lookupArgs.journalUUID,
        journalFingerprint = lookupArgs.journalFingerprint,
        journalData = lookupArgs.journalData,
        skills = {},
        traits = {},
        recipes = {},
        stats = {},
    }
    local total = 0

    for _, reward in ipairs(rewards or {}) do
        if reward.type == "skill" and reward.name then
            payload.skills[#payload.skills + 1] = {
                skillName = reward.name,
            }
            total = total + 1
        elseif reward.type == "trait" and reward.name then
            payload.traits[#payload.traits + 1] = reward.name
            total = total + 1
        elseif reward.type == "recipe" and reward.name then
            payload.recipes[#payload.recipes + 1] = reward.name
            total = total + 1
        elseif reward.type == "stat" and reward.name then
            payload.stats[#payload.stats + 1] = {
                statId = reward.name,
                value = reward.value,
            }
            total = total + 1
        elseif reward.type == "forget" then
            return nil
        end
    end

    if total <= 0 then
        return nil
    end

    if BurdJournals.getXPRecoveryMode and BurdJournals.getXPRecoveryMode() == 2
        and BurdJournals.getDiminishingTrackingMode and BurdJournals.getDiminishingTrackingMode() == 2 then
        payload.claimSessionId = BurdJournals.getClaimSessionIdForPanel(self, true)
    end

    return payload
end

function BurdJournals.UI.MainPanel:completeLearning()
    Events.OnTick.Remove(BurdJournals.UI.MainPanel.onLearningTickStatic)

    self.processingQueue = true

    if self.recordingState and self.recordingState.active then
        self:cancelRecording()
    end
    self.processingRecordQueue = false
    self.pendingRecordAllContinuation = nil
    BurdJournals.pendingRecordAllContinuation = nil

    if self.confirmDialog then
        if self.confirmDialog.setVisible then
            self.confirmDialog:setVisible(false)
        end
        if self.confirmDialog.removeFromUIManager then
            self.confirmDialog:removeFromUIManager()
        end
        self.confirmDialog = nil
    end

    local isPlayerJournal = self.isPlayerJournal or self.mode == "view"
    local batchClaimPayload = nil
    if isPlayerJournal
        and self.learningState
        and self.learningState.isAbsorbAll == true
        and BurdJournals.clientShouldUseServerAuthority()
        and BurdJournals.Client
        and BurdJournals.Client.sendBatchRewardRequest
        and self.buildBatchClaimRewardsPayload then
        batchClaimPayload = self:buildBatchClaimRewardsPayload(self.learningState.pendingRewards)
    end
    if batchClaimPayload then
        self.isProcessingRewards = true
        self.pendingBatchRewardMode = "claim"
        batchClaimPayload.requestId = batchClaimPayload.requestId or BurdJournals.Client.createBatchRewardRequestId()
        self.pendingBatchRewardRequestId = batchClaimPayload.requestId
        if BurdJournals.Client.sendBatchRewardRequest(self.player, "batchClaimRewards", batchClaimPayload) then
            return
        end
        self.isProcessingRewards = false
        self.pendingBatchRewardMode = nil
        self.pendingBatchRewardRequestId = nil
    end

    -- Queue rewards for tick-based pacing instead of sending all at once
    -- This prevents server rate-limiting from dropping commands in MP
    if not self.rewardProcessingQueue then
        self.rewardProcessingQueue = {}
    end

    for _, reward in ipairs(self.learningState.pendingRewards) do
        table.insert(self.rewardProcessingQueue, {
            type = reward.type,
            name = reward.name,
            xp = reward.xp,
            isPlayerJournal = isPlayerJournal
        })
    end

    -- Start tick-based processor if not already running
    if not self.isProcessingRewards and #self.rewardProcessingQueue > 0 then
        self.isProcessingRewards = true
        self:startRewardProcessor()
    elseif #self.rewardProcessingQueue == 0 then
        -- No rewards to process, continue with refresh
        self:refreshPlayer()
    else
        -- Processor already running, it will handle refresh when done
        return
    end

    -- Note: refreshPlayer moved to reward processor completion
    if #self.rewardProcessingQueue > 0 then
        return  -- Let the processor handle the rest
    end

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

    if self.checkDissolution then
        self:checkDissolution(true)
    end

    local savedQueue = {}
    if not self.learningState.isAbsorbAll then
        savedQueue = self.learningState.queue or {}
    end

    if #savedQueue > 0 then
        local nextReward = table.remove(savedQueue, 1)

        if nextReward.type == "skill" then
            self.learningState = {
                active = true,
                skillName = nextReward.name,
                traitId = nil,
                forgetTraitId = nil,
                recipeName = nil,
                statId = nil,
                isAbsorbAll = false,
                progress = 0,
                totalTime = self:getSkillLearningTime(),
                startTime = getTimestampMs and getTimestampMs() or 0,
                pendingRewards = {{type = "skill", name = nextReward.name, xp = nextReward.xp}},
                currentIndex = 1,
                queue = savedQueue,
            }
        elseif nextReward.type == "trait" then
            self.learningState = {
                active = true,
                skillName = nil,
                traitId = nextReward.name,
                forgetTraitId = nil,
                recipeName = nil,
                statId = nil,
                isAbsorbAll = false,
                progress = 0,
                totalTime = self:getTraitLearningTime(),
                startTime = getTimestampMs and getTimestampMs() or 0,
                pendingRewards = {{type = "trait", name = nextReward.name}},
                currentIndex = 1,
                queue = savedQueue,
            }
        elseif nextReward.type == "forget" then
            self.learningState = {
                active = true,
                skillName = nil,
                traitId = nil,
                forgetTraitId = nextReward.name,
                recipeName = nil,
                statId = nil,
                isAbsorbAll = false,
                progress = 0,
                totalTime = self:getTraitLearningTime(),
                startTime = getTimestampMs and getTimestampMs() or 0,
                pendingRewards = {{type = "forget", name = nextReward.name}},
                currentIndex = 1,
                queue = savedQueue,
            }
        elseif nextReward.type == "recipe" then
            self.learningState = {
                active = true,
                skillName = nil,
                traitId = nil,
                forgetTraitId = nil,
                recipeName = nextReward.name,
                statId = nil,
                isAbsorbAll = false,
                progress = 0,
                totalTime = self:getRecipeLearningTime(),
                startTime = getTimestampMs and getTimestampMs() or 0,
                pendingRewards = {{type = "recipe", name = nextReward.name}},
                currentIndex = 1,
                queue = savedQueue,
            }
        elseif nextReward.type == "stat" then
            self.learningState = {
                active = true,
                skillName = nil,
                traitId = nil,
                forgetTraitId = nil,
                recipeName = nil,
                statId = nextReward.name,
                isAbsorbAll = false,
                progress = 0,
                totalTime = self:getStatLearningTime(),
                startTime = getTimestampMs and getTimestampMs() or 0,
                pendingRewards = {{type = "stat", name = nextReward.name, value = nextReward.value}},
                currentIndex = 1,
                queue = savedQueue,
            }
        end

        Events.OnTick.Remove(BurdJournals.UI.MainPanel.onLearningTickStatic)
        Events.OnTick.Add(BurdJournals.UI.MainPanel.onLearningTickStatic)

        if self.skillList and self.journal then
            if self.populateAbsorptionList then
                self:populateAbsorptionList()
            end
        end

        self.processingQueue = false
        return
    end

    self.learningCompleted = true
    self.processingQueue = false

    self:playSound(BurdJournals.Sounds.LEARN_COMPLETE)

    self.learningState = {
        active = false,
        skillName = nil,
        traitId = nil,
        forgetTraitId = nil,
        recipeName = nil,
        statId = nil,
        isAbsorbAll = false,
        progress = 0,
        totalTime = 0,
        startTime = 0,
        pendingRewards = {},
        currentIndex = 0,
        queue = {},
    }

    if self.skillList and self.journal then
        self:refreshPlayer()
        if self.mode == "view" or self.isPlayerJournal then
            if self.populateViewList then
                self:populateViewList()
            end
        else
            if self.populateAbsorptionList then
                self:populateAbsorptionList()
            end
        end
    end
end

-- Time-gated reward processor to avoid server rate-limiting in MP
-- Server rate-limits at 100ms, so we send one command every 120ms to be safe
-- Uses index-based iteration instead of table.remove(1) to avoid O(n^2) behavior
function BurdJournals.UI.MainPanel:startRewardProcessor()
    local panel = self
    local skipRefresh = true
    local lastSendTime = 0
    local ticksSinceLastSend = 0 -- Fallback for builds without getTimestampMs
    local SEND_INTERVAL_MS = 120 -- Server rate-limits at 100ms, use 120ms to be safe
    local SEND_INTERVAL_TICKS = 4 -- ~120ms at 30 FPS as fallback
    local idx = 1 -- Use index instead of table.remove for O(1) access

    local processNextReward
    processNextReward = function()
        -- Check if panel still exists and has queue
        if not panel or not panel.rewardProcessingQueue or idx > #panel.rewardProcessingQueue then
            if panel then
                panel.isProcessingRewards = false
                panel.rewardProcessingQueue = nil -- Clear queue when done
                -- All rewards processed, now refresh
                panel:refreshPlayer()
                if panel.isPlayerJournal or panel.mode == "view" then
                    if panel.refreshJournalData then
                        panel:refreshJournalData()
                    end
                else
                    if panel.refreshAbsorptionList then
                        panel:refreshAbsorptionList()
                    end
                end
                if panel.checkDissolution then
                    panel:checkDissolution(true)
                end
            end
            Events.OnTick.Remove(processNextReward)
            return
        end

        -- Check if enough time has passed since last send (120ms minimum)
        local now = getTimestampMs and getTimestampMs() or 0
        if now > 0 and lastSendTime > 0 then
            -- Use millisecond timing when available
            if (now - lastSendTime) < SEND_INTERVAL_MS then
                return -- Wait for next tick, not enough time elapsed
            end
        else
            -- Fallback: use tick counting when getTimestampMs unavailable
            ticksSinceLastSend = ticksSinceLastSend + 1
            if ticksSinceLastSend < SEND_INTERVAL_TICKS then
                return -- Wait for more ticks
            end
            ticksSinceLastSend = 0
        end

        -- Process one reward with time-gating (O(1) index access)
        local reward = panel.rewardProcessingQueue[idx]
        BurdJournals.debugPrint("[BurdJournals BATCH] Processing reward " .. idx .. "/" .. #panel.rewardProcessingQueue .. ": " .. tostring(reward.type) .. " - " .. tostring(reward.name))
        idx = idx + 1
        lastSendTime = now

        if reward.type == "skill" then
            if reward.isPlayerJournal then
                BurdJournals.debugPrint("[BurdJournals BATCH] Calling sendClaimSkill for " .. tostring(reward.name) .. " with XP " .. tostring(reward.xp))
                panel:sendClaimSkill(reward.name, reward.xp, skipRefresh)
            else
                panel:sendAbsorbSkill(reward.name, reward.xp, skipRefresh)
            end
        elseif reward.type == "trait" then
            if reward.isPlayerJournal then
                panel:sendClaimTrait(reward.name, skipRefresh)
            else
                panel:sendAbsorbTrait(reward.name, skipRefresh)
            end
        elseif reward.type == "forget" then
            panel:sendClaimForgetSlot(reward.name)
        elseif reward.type == "recipe" then
            if reward.isPlayerJournal then
                panel:sendClaimRecipe(reward.name, skipRefresh)
            else
                panel:sendAbsorbRecipe(reward.name, skipRefresh)
            end
        elseif reward.type == "stat" then
            -- Stats use sendClaimStat for both player and non-player journals
            panel:sendClaimStat(reward.name, reward.value)
        end
    end

    Events.OnTick.Add(processNextReward)
end

local function shouldUseClientOnlyDebugJournalPath(journal, journalData)
    if not (journalData and journalData.isDebugSpawned and BurdJournals.clientShouldUseServerAuthority()) then return false end
    if journal and journal.__bsjServerProxy == true then return true end
    local journalId = journal and journal.getID and tonumber(journal:getID()) or 0
    return journalId <= 0
end

function BurdJournals.UI.MainPanel:sendAbsorbSkill(skillName, xp, skipDissolutionCheck)
    local journalId = self.journal:getID()
    local journalData = BurdJournals.getJournalData(self.journal)
    local journalUUID = journalData and journalData.uuid or nil
    local lookupArgs = BurdJournals.buildJournalCommandPayload
        and BurdJournals.buildJournalCommandPayload(self.journal, journalData, true)
        or { journalId = journalId, journalUUID = journalUUID, journalFingerprint = nil }

    -- Calculate skill book multiplier on the client (where the state is known)
    local skillBookMultiplier, hasBoost = BurdJournals.getSkillBookMultiplier(self.player, skillName)
    BurdJournals.debugPrint("[BurdJournals] Client sendAbsorbSkill: skill=" .. tostring(skillName) .. ", skillBookMultiplier=" .. tostring(skillBookMultiplier) .. ", hasBoost=" .. tostring(hasBoost))

    -- For debug-spawned journals in MP, use the debug command to add XP
    if shouldUseClientOnlyDebugJournalPath(self.journal, journalData) then
        BurdJournals.debugPrint("[BurdJournals] Debug journal (absorb) - using debug XP add for " .. skillName)
        sendClientCommand(self.player, "BurdJournals", "debugAddXP", {
            skillName = skillName,
            xp = xp or 0
        })
        -- Mark as claimed locally
        BurdJournals.markSkillClaimedByCharacter(journalData, self.player, skillName)
        safeTransmitPanelJournalModData(self.journal, "mainPanelCurrentJournal")
        return
    end

    if BurdJournals.clientShouldUseServerAuthority() then
        BurdJournals.debugPrint("[BurdJournals] Client: Sending to server with multiplier=" .. tostring(skillBookMultiplier))
        sendClientCommand(self.player, "BurdJournals", "absorbSkill", {
            journalId = lookupArgs.journalId,
            journalUUID = lookupArgs.journalUUID,
            journalFingerprint = lookupArgs.journalFingerprint,
            journalData = lookupArgs.journalData,
            skillName = skillName,
            skillBookMultiplier = skillBookMultiplier  -- Send the multiplier to the server
        })
    else
        BurdJournals.debugPrint("[BurdJournals] Client: SP/host path - applySkillXPDirectly")
        self:applySkillXPDirectly(skillName, xp, skipDissolutionCheck)
    end
end

function BurdJournals.UI.MainPanel:sendAbsorbTrait(traitId, skipDissolutionCheck)
    local journalId = self.journal:getID()
    local journalData = BurdJournals.getJournalData(self.journal)
    local journalUUID = journalData and journalData.uuid or nil
    local lookupArgs = BurdJournals.buildJournalCommandPayload
        and BurdJournals.buildJournalCommandPayload(self.journal, journalData, true)
        or { journalId = journalId, journalUUID = journalUUID, journalFingerprint = nil }

    -- For debug-spawned journals in MP, use the debug command to add trait
    if shouldUseClientOnlyDebugJournalPath(self.journal, journalData) then
        BurdJournals.debugPrint("[BurdJournals] Debug journal (absorb) - using debug trait add for " .. tostring(traitId))
        sendClientCommand(self.player, "BurdJournals", "debugAddTrait", {
            traitId = traitId
        })
        -- Mark as claimed locally
        BurdJournals.markTraitClaimedByCharacter(journalData, self.player, traitId)
        safeTransmitPanelJournalModData(self.journal, "mainPanelCurrentJournal")
        return
    end

    if BurdJournals.clientShouldUseServerAuthority() then
        sendClientCommand(self.player, "BurdJournals", "absorbTrait", {
            journalId = lookupArgs.journalId,
            journalUUID = lookupArgs.journalUUID,
            journalFingerprint = lookupArgs.journalFingerprint,
            journalData = lookupArgs.journalData,
            traitId = traitId
        })
    else
        self:applyTraitDirectly(traitId, skipDissolutionCheck)
    end
end

function BurdJournals.UI.MainPanel:sendClaimSkill(skillName, recordedXP, skipDissolutionCheck)
    local journalId = self.journal:getID()
    local journalData = BurdJournals.getJournalData(self.journal)
    local journalUUID = journalData and journalData.uuid or nil
    local lookupArgs = BurdJournals.buildJournalCommandPayload
        and BurdJournals.buildJournalCommandPayload(self.journal, journalData, true)
        or { journalId = journalId, journalUUID = journalUUID, journalFingerprint = nil }
    if not BurdJournals.isSkillVisibleForJournal(journalData, skillName) then
        self:showFeedback(getText("UI_BurdJournals_CantClaimSkill") or "That skill cannot be claimed right now", "warn")
        return
    end
    local claimSessionId = nil
    if BurdJournals.getXPRecoveryMode and BurdJournals.getXPRecoveryMode() == 2
        and BurdJournals.getDiminishingTrackingMode and BurdJournals.getDiminishingTrackingMode() == 2 then
        claimSessionId = BurdJournals.getClaimSessionIdForPanel(self, true)
    end
    local claimBaselineXP = nil
    if journalData
        and journalData.isPlayerCreated == true
        and BurdJournals.resolveJournalRecordingModeForPlayer
        and BurdJournals.resolveJournalRecordingModeForPlayer(journalData, self.player)
        and BurdJournals.getSkillBaseline then
        claimBaselineXP = math.max(0, tonumber(BurdJournals.getSkillBaseline(self.player, skillName)) or 0)
    end

    if not self.pendingClaims then self.pendingClaims = {skills = {}, traits = {}} end
    self.pendingClaims.skills[skillName] = true

    local debugLoggingEnabled = BurdJournals.shouldDebugLog and BurdJournals.shouldDebugLog() or false

    -- Get current player state for debug logging
    local perk = nil
    local playerLevelBefore = 0
    local playerXPBefore = 0
    if debugLoggingEnabled then
        perk = BurdJournals.getPerkByName(skillName)
    end
    if perk and debugLoggingEnabled then
        playerLevelBefore = self.player:getPerkLevel(perk)
        playerXPBefore = BurdJournals.getPlayerSkillTotalXP and BurdJournals.getPlayerSkillTotalXP(self.player, perk, skillName) or self.player:getXp():getXP(perk)
    end
    
    -- Get recorded level from journal
    local recordedLevel = 0
    if journalData and BurdJournals.isSkillVisibleForJournal(journalData, skillName) and journalData.skills then
        local storedSkillKey = BurdJournals.resolveSkillKey and BurdJournals.resolveSkillKey(journalData.skills, skillName) or skillName
        local skillData = journalData.skills[storedSkillKey]
        recordedLevel = skillData and skillData.level or 0
        -- Fallback: calculate level from XP if not stored
        if recordedLevel == 0 and recordedXP and recordedXP > 0 and BurdJournals.getSkillLevelFromXP then
            local xpForLevelCalc = BurdJournals.getXPWithBaselineForDisplay(skillName, recordedXP, journalData, self.player)
            recordedLevel = BurdJournals.getSkillLevelFromXP(xpForLevelCalc, skillName)
        end
    end
    
    -- Debug logging: what we expect vs current state
    if debugLoggingEnabled then
        BurdJournals.debugPrint("================================================================================")
        BurdJournals.debugPrint("[BurdJournals CLAIM DEBUG] Skill: " .. tostring(skillName))
        BurdJournals.debugPrint("[BurdJournals CLAIM DEBUG]   JOURNAL EXPECTS: Level " .. tostring(recordedLevel) .. ", XP " .. tostring(recordedXP))
        BurdJournals.debugPrint("[BurdJournals CLAIM DEBUG]   PLAYER BEFORE:   Level " .. tostring(playerLevelBefore) .. ", XP " .. tostring(playerXPBefore))
        BurdJournals.debugPrint("[BurdJournals CLAIM DEBUG]   isDebugSpawned: " .. tostring(journalData and journalData.isDebugSpawned))
        BurdJournals.debugPrint("[BurdJournals CLAIM DEBUG]   isPlayerJournal: " .. tostring(journalData and journalData.isPlayerCreated))
        BurdJournals.debugPrint("[BurdJournals CLAIM DEBUG]   skipDissolutionCheck: " .. tostring(skipDissolutionCheck))
        BurdJournals.debugPrint("[BurdJournals CLAIM DEBUG]   claimSessionId: " .. tostring(claimSessionId))
        BurdJournals.debugPrint("================================================================================")
    end

    -- For debug-spawned journals in MP, use the debug command to SET to target XP
    -- (normal claim flow fails because server can't find client-spawned items)
    -- IMPORTANT: Send the actual recorded XP, not just the level, for exact XP restoration
    if shouldUseClientOnlyDebugJournalPath(self.journal, journalData) then
        if debugLoggingEnabled then
            BurdJournals.debugPrint("[BurdJournals CLAIM DEBUG] Using debugSetSkillXP path (debug-spawned journal)")
        end
        local claimMultiplier = 1.0
        if BurdJournals.consumeJournalClaimRead
            and BurdJournals.getXPRecoveryMode and BurdJournals.getXPRecoveryMode() == 2 then
            claimMultiplier = BurdJournals.consumeJournalClaimRead(journalData, skillName, claimSessionId)
        end
        local effectiveRecordedXP = math.max(0, math.floor((tonumber(recordedXP) or 0) * claimMultiplier))
        local claimTargetXP, baselineXP = BurdJournals.getClaimTargetXPForPlayer(journalData, self.player, skillName, effectiveRecordedXP)
        local effectiveRecordedLevel = recordedLevel
        if BurdJournals.getSkillLevelFromXP then
            effectiveRecordedLevel = BurdJournals.getSkillLevelFromXP(claimTargetXP, skillName) or recordedLevel
        end
        local journalSnapshot = journalData
        if BurdJournals.normalizeJournalData then
            journalSnapshot = BurdJournals.normalizeJournalData(journalData) or journalData
        end
        if debugLoggingEnabled then
            BurdJournals.debugPrint("[BurdJournals CLAIM DEBUG]   Sending effectiveXP=" .. tostring(effectiveRecordedXP) .. ", targetXP=" .. tostring(claimTargetXP) .. ", baselineXP=" .. tostring(baselineXP) .. ", effectiveLevel=" .. tostring(effectiveRecordedLevel) .. ", claimMultiplier=" .. tostring(claimMultiplier))
        end
        sendClientCommand(self.player, "BurdJournals", "debugSetSkillXP", {
            skillName = skillName,
            targetXP = claimTargetXP,
            targetLevel = effectiveRecordedLevel,
            journalId = journalId,
            journalUUID = journalData and journalData.uuid,
            claimSessionId = claimSessionId,
            journalData = journalSnapshot
        })
        -- Mark as claimed locally since server can't access debug-spawned journal
        -- This ensures the UI updates correctly and the skill isn't double-claimed
        BurdJournals.markSkillClaimedByCharacter(journalData, self.player, skillName)
        safeTransmitPanelJournalModData(self.journal, "mainPanelCurrentJournal")
        -- Keep dedicated-server persistence in sync with debug claims.
        -- This mirrors the debug edit flow that already survives reconnects/patch updates.
        if BurdJournals.UI
            and BurdJournals.UI.DebugPanel
            and BurdJournals.UI.DebugPanel.backupJournalToGlobalCache then
            BurdJournals.UI.DebugPanel.backupJournalToGlobalCache(self.journal)
        end
        -- Don't refresh here - let the server response or batch completion handle it
        return
    end

    if BurdJournals.clientShouldUseServerAuthority() then
        if debugLoggingEnabled then
            BurdJournals.debugPrint("[BurdJournals CLAIM DEBUG] Using claimSkill server command path")
        end
        sendClientCommand(self.player, "BurdJournals", "claimSkill", {
            journalId = lookupArgs.journalId,
            journalUUID = lookupArgs.journalUUID,
            journalFingerprint = lookupArgs.journalFingerprint,
            journalData = lookupArgs.journalData,
            skillName = skillName,
            claimSessionId = claimSessionId,
            baselineXP = claimBaselineXP
        })
    else
        if debugLoggingEnabled then
            BurdJournals.debugPrint("[BurdJournals CLAIM DEBUG] Using local applySkillXPSetMode path (SP/host)")
        end
        self:applySkillXPSetMode(skillName, recordedXP, skipDissolutionCheck, claimSessionId)
    end
end

function BurdJournals.UI.MainPanel:sendClaimTrait(traitId, skipDissolutionCheck)
    local journalId = self.journal:getID()
    local numericJournalId = tonumber(journalId) or 0
    local journalData = BurdJournals.getJournalData(self.journal)
    local journalUUID = journalData and journalData.uuid or nil
    local lookupArgs = BurdJournals.buildJournalCommandPayload
        and BurdJournals.buildJournalCommandPayload(self.journal, journalData, true)
        or { journalId = journalId, journalUUID = journalUUID, journalFingerprint = nil }

    -- Debug logging
    BurdJournals.debugPrint("[BurdJournals] sendClaimTrait called for trait: " .. tostring(traitId))
    BurdJournals.debugPrint("[BurdJournals] journalData exists: " .. tostring(journalData ~= nil))
    if journalData then
        BurdJournals.debugPrint("[BurdJournals] journalData.isDebugSpawned: " .. tostring(journalData.isDebugSpawned))
    end
    BurdJournals.debugPrint("[BurdJournals] isClient(): " .. tostring(isClient()) .. ", isServer(): " .. tostring(isServer()))
    BurdJournals.debugPrint("[BurdJournals] skipDissolutionCheck: " .. tostring(skipDissolutionCheck))

    if not self.pendingClaims then self.pendingClaims = {skills = {}, traits = {}} end
    local normalizedTraitId = BurdJournals.normalizeTraitId and BurdJournals.normalizeTraitId(traitId) or traitId
    local traitSessionKey = string.lower(tostring(normalizedTraitId or traitId))
    self.pendingClaims.traits[traitId] = true
    self.pendingClaims.traits[traitSessionKey] = true

    -- For debug-spawned journals in MP, use the debug command to add trait
    -- (normal claim flow fails because server can't find client-spawned items)
    local useClientOnlyDebugPath = shouldUseClientOnlyDebugJournalPath(self.journal, journalData)

    if useClientOnlyDebugPath then
        BurdJournals.debugPrint("[BurdJournals] Debug journal detected - using debug trait add")
        sendClientCommand(self.player, "BurdJournals", "debugAddTrait", {
            traitId = traitId
        })
        -- Mark as claimed locally since server can't access debug-spawned journal
        BurdJournals.markTraitClaimedByCharacter(journalData, self.player, traitId)
        safeTransmitPanelJournalModData(self.journal, "mainPanelCurrentJournal")
        -- Don't refresh here - let the server response or batch completion handle it
        return
    end

    BurdJournals.debugPrint("[BurdJournals] Using normal claimTrait flow")
    if BurdJournals.clientShouldUseServerAuthority() then
        sendClientCommand(self.player, "BurdJournals", "claimTrait", {
            journalId = lookupArgs.journalId,
            journalUUID = lookupArgs.journalUUID,
            journalFingerprint = lookupArgs.journalFingerprint,
            journalData = lookupArgs.journalData,
            traitId = traitId
        })
    else
        self:applyTraitDirectly(traitId, skipDissolutionCheck)
    end
end

function BurdJournals.UI.MainPanel:sendAbsorbRecipe(recipeName, skipRefresh)
    local journalId = self.journal:getID()
    local journalData = BurdJournals.getJournalData(self.journal)
    local journalUUID = journalData and journalData.uuid or nil
    local lookupArgs = BurdJournals.buildJournalCommandPayload
        and BurdJournals.buildJournalCommandPayload(self.journal, journalData, true)
        or { journalId = journalId, journalUUID = journalUUID, journalFingerprint = nil }

    if BurdJournals.clientShouldUseServerAuthority() then
        sendClientCommand(self.player, "BurdJournals", "absorbRecipe", {
            journalId = lookupArgs.journalId,
            journalUUID = lookupArgs.journalUUID,
            journalFingerprint = lookupArgs.journalFingerprint,
            journalData = lookupArgs.journalData,
            recipeName = recipeName
        })
    else
        local recipeAlreadyKnown = BurdJournals.playerKnowsRecipe(self.player, recipeName)
        local recipeApplied = false
        if recipeAlreadyKnown then
            local displayName = BurdJournals.getRecipeDisplayName(recipeName) or recipeName
            self:showFeedback(BurdJournals.formatText(getText("UI_BurdJournals_AlreadyKnowRecipe") or "Already know: %s", displayName), "muted")
            recipeApplied = true
        else
            recipeApplied = self:applyRecipeDirectly(recipeName)
        end

        -- Use per-character claims for SP/host path to match server behavior
        local journalData = self.journal:getModData().BurdJournals
        if recipeApplied and journalData then
            BurdJournals.markRecipeClaimedByCharacter(journalData, self.player, recipeName)
            safeTransmitPanelJournalModData(self.journal, "mainPanelCurrentJournal")
        end

        if not skipRefresh then
            self:refreshAbsorptionList()
            self:checkDissolution(true)
        end
    end
end

function BurdJournals.UI.MainPanel:sendClaimRecipe(recipeName, skipDissolutionCheck)
    local journalId = self.journal:getID()
    local journalData = BurdJournals.getJournalData(self.journal)
    local journalUUID = journalData and journalData.uuid or nil
    local lookupArgs = BurdJournals.buildJournalCommandPayload
        and BurdJournals.buildJournalCommandPayload(self.journal, journalData, true)
        or { journalId = journalId, journalUUID = journalUUID, journalFingerprint = nil }

    if not self.pendingClaims then self.pendingClaims = {skills = {}, traits = {}, recipes = {}} end
    if not self.pendingClaims.recipes then self.pendingClaims.recipes = {} end
    self.pendingClaims.recipes[recipeName] = true

    if BurdJournals.clientShouldUseServerAuthority() then
        sendClientCommand(self.player, "BurdJournals", "claimRecipe", {
            journalId = lookupArgs.journalId,
            journalUUID = lookupArgs.journalUUID,
            journalFingerprint = lookupArgs.journalFingerprint,
            journalData = lookupArgs.journalData,
            recipeName = recipeName
        })
    else
        local recipeAlreadyKnown = BurdJournals.playerKnowsRecipe(self.player, recipeName)
        local recipeApplied = false
        if recipeAlreadyKnown then
            local displayName = BurdJournals.getRecipeDisplayName(recipeName) or recipeName
            self:showFeedback(BurdJournals.formatText(getText("UI_BurdJournals_AlreadyKnowRecipe") or "Already know: %s", displayName), "muted")
            recipeApplied = true
        else
            recipeApplied = self:applyRecipeDirectly(recipeName)
        end

        -- Use per-character claims for SP/host path to match server behavior
        local journalData = self.journal:getModData().BurdJournals
        if recipeApplied and journalData then
            BurdJournals.markRecipeClaimedByCharacter(journalData, self.player, recipeName)
            safeTransmitPanelJournalModData(self.journal, "mainPanelCurrentJournal")
        end

        -- Skip refresh/dissolution during batch operations
        if not skipDissolutionCheck then
            self:refreshAbsorptionList()
            self:checkDissolution(true)
        end
    end
end

function BurdJournals.UI.MainPanel:applyRecipeDirectly(recipeName)
    if not self.player or not recipeName then return false end

    local displayName = BurdJournals.getRecipeDisplayName(recipeName) or recipeName

    if BurdJournals.playerKnowsRecipe(self.player, recipeName) then
        self:showFeedback(BurdJournals.formatText(getText("UI_BurdJournals_AlreadyKnowRecipe") or "Already know: %s", displayName), "muted")
        return false
    end

    local learned = BurdJournals.learnRecipeWithVerification(self.player, recipeName, "[BurdJournals Client]")

    if learned then
        self:showFeedback(BurdJournals.formatText(getText("UI_BurdJournals_LearnedRecipe") or "Learned: %s", displayName), "success")
        BurdJournals.Client.showHaloMessage(self.player, "+" .. displayName, BurdJournals.Client.HaloColors.RECIPE_GAIN)
        return true
    else
        self:showFeedback(BurdJournals.formatText(getText("UI_BurdJournals_RecipeNotAvailable") or "Recipe not available: %s", displayName), "warn")
        return false
    end
end

function BurdJournals.UI.MainPanel:applySkillXPSetMode(skillName, recordedXP, skipDissolutionCheck, claimSessionId)
    local debugLoggingEnabled = BurdJournals.shouldDebugLog and BurdJournals.shouldDebugLog() or false
    if debugLoggingEnabled then
        BurdJournals.debugPrint("================================================================================")
        BurdJournals.debugPrint("[BurdJournals BATCH DEBUG] applySkillXPSetMode called")
        BurdJournals.debugPrint("[BurdJournals BATCH DEBUG]   skillName: " .. tostring(skillName))
        BurdJournals.debugPrint("[BurdJournals BATCH DEBUG]   recordedXP: " .. tostring(recordedXP) .. " (type: " .. type(recordedXP) .. ")")
        BurdJournals.debugPrint("[BurdJournals BATCH DEBUG]   skipDissolutionCheck: " .. tostring(skipDissolutionCheck))
    end

    self:refreshPlayer()

    local perk = BurdJournals.getPerkByName(skillName)
    if not perk then
        bsjWriteLogLine("[BurdJournals BATCH DEBUG]   ERROR: perk is nil for " .. tostring(skillName))
        return
    end
    if debugLoggingEnabled then
        BurdJournals.debugPrint("[BurdJournals BATCH DEBUG]   perk found: " .. tostring(perk))
    end

    -- Use per-character claims for SP/host path to match server behavior
    local journalData = self.journal:getModData().BurdJournals
    local claimMultiplier = 1.0
    if journalData and BurdJournals.consumeJournalClaimRead then
        claimMultiplier = BurdJournals.consumeJournalClaimRead(journalData, skillName, claimSessionId)
    end
    local effectiveRecordedXP = math.max(0, math.floor((tonumber(recordedXP) or 0) * claimMultiplier))
    local claimTargetXP, baselineXP = BurdJournals.getClaimTargetXPForPlayer(journalData, self.player, skillName, effectiveRecordedXP)

    local playerXP = BurdJournals.getPlayerSkillTotalXP and BurdJournals.getPlayerSkillTotalXP(self.player, perk, skillName) or self.player:getXp():getXP(perk)
    if debugLoggingEnabled then
        BurdJournals.debugPrint("[BurdJournals BATCH DEBUG]   playerXP (current): " .. tostring(playerXP))
        BurdJournals.debugPrint("[BurdJournals BATCH DEBUG]   claimMultiplier: " .. tostring(claimMultiplier))
        BurdJournals.debugPrint("[BurdJournals BATCH DEBUG]   effectiveRecordedXP: " .. tostring(effectiveRecordedXP))
        BurdJournals.debugPrint("[BurdJournals BATCH DEBUG]   baselineXP: " .. tostring(baselineXP))
        BurdJournals.debugPrint("[BurdJournals BATCH DEBUG]   claimTargetXP: " .. tostring(claimTargetXP))
        BurdJournals.debugPrint("[BurdJournals BATCH DEBUG]   Comparison: claimTargetXP (" .. tostring(claimTargetXP) .. ") > playerXP (" .. tostring(playerXP) .. ") = " .. tostring(claimTargetXP > playerXP))
    end
    
    if claimTargetXP > playerXP then

        local xpDiff = claimTargetXP - playerXP
        if debugLoggingEnabled then
            BurdJournals.debugPrint("[BurdJournals BATCH DEBUG]   XP to add: " .. tostring(xpDiff))
        end
        local useAddMode = claimTargetXP < (playerXP + effectiveRecordedXP)

        local applied, applyVia, actualGain, afterXP = false, "none", 0, playerXP
        if BurdJournals.applySkillXPCompat then
            local compatTargetXP = useAddMode and xpDiff or claimTargetXP
            local compatMode = useAddMode and "add" or "set"
            applied, applyVia, actualGain, afterXP = BurdJournals.applySkillXPCompat(self.player, perk, skillName, compatTargetXP, compatMode)
        else
            local xpObj = self.player:getXp()
            local beforeXP = BurdJournals.getPlayerSkillTotalXP and BurdJournals.getPlayerSkillTotalXP(self.player, perk, skillName) or xpObj:getXP(perk)
            if useAddMode then
                if BurdJournals.applyXPDeltaCompat then
                    BurdJournals.applyXPDeltaCompat(self.player, perk, xpDiff)
                else
                    xpObj:AddXP(perk, xpDiff)
                end
            elseif BurdJournals.setSkillTotalXPCompat then
                BurdJournals.setSkillTotalXPCompat(self.player, perk, claimTargetXP, skillName)
            elseif BurdJournals.applyXPDeltaCompat then
                BurdJournals.applyXPDeltaCompat(self.player, perk, xpDiff)
            else
                xpObj:AddXP(perk, xpDiff)
            end
            afterXP = BurdJournals.getPlayerSkillTotalXP and BurdJournals.getPlayerSkillTotalXP(self.player, perk, skillName) or xpObj:getXP(perk)
            actualGain = math.max(0, afterXP - beforeXP)
            applied = (useAddMode and actualGain > 0)
                or afterXP >= (claimTargetXP - 0.001)
                or actualGain > 0
            applyVia = useAddMode and "legacyAdd" or "legacy"
        end

        if debugLoggingEnabled then
            BurdJournals.debugPrint("[BurdJournals BATCH DEBUG]   Applied via: " .. tostring(applyVia))
            BurdJournals.debugPrint("[BurdJournals BATCH DEBUG]   XP after: " .. tostring(afterXP) .. ", gained: " .. tostring(actualGain))
        end

        if not applied then
            self:showFeedback(BurdJournals.safeGetText("UI_BurdJournals_JournalClaimFailed", "Could not apply this journal reward"), "error")
            if not skipDissolutionCheck then
                self:refreshJournalData()
            end
            return
        end

        if journalData then
            BurdJournals.markSkillClaimedByCharacter(journalData, self.player, skillName)
            safeTransmitPanelJournalModData(self.journal, "mainPanelCurrentJournal")
        end

        local displayName = BurdJournals.getPerkDisplayName(skillName)
        self:showFeedback(BurdJournals.formatText(getText("UI_BurdJournals_SetSkillToLevel") or "Set %s to recorded level", displayName), "success")
    else
        if debugLoggingEnabled then
            BurdJournals.debugPrint("[BurdJournals BATCH DEBUG]   SKIPPING XP add - already at or above level (or recordedXP is nil/0)")
        end
        -- Still mark as claimed even if already at level (allows dissolution)
        if journalData then
            BurdJournals.markSkillClaimedByCharacter(journalData, self.player, skillName)
            safeTransmitPanelJournalModData(self.journal, "mainPanelCurrentJournal")
        end
        self:showFeedback(getText("UI_BurdJournals_AlreadyAtLevel") or "Already at or above this level", "muted")
    end
    if journalData and BurdJournals.captureJournalDRState then
        BurdJournals.captureJournalDRState(self.journal, "applySkillXPSetMode", self.player)
    end
    if debugLoggingEnabled then
        BurdJournals.debugPrint("================================================================================")
    end

    -- Skip refresh/dissolution during batch operations - will be done at end of batch
    if not skipDissolutionCheck then
        self:refreshJournalData()
        self:checkDissolution(true)
    end
end

function BurdJournals.UI.MainPanel:absorbSkill(skillName, xp)
    if not self:hasLimitedLootClaimAvailable() then
        return
    end
    if self:shouldBlockLimitedLootQueue() then
        return
    end

    if self.learningState.active and not self.learningState.isAbsorbAll then
        if self:addToQueue("skill", skillName, xp) then
            self:showFeedback(BurdJournals.formatText(getText("UI_BurdJournals_Queued") or "Queued: %s", BurdJournals.getPerkDisplayName(skillName) or skillName), "info")
        else
            self:showFeedback(getText("UI_BurdJournals_AlreadyQueued") or "Already queued", "warn")
        end
        return
    end

    if not self:startLearningSkill(skillName, xp) then
        self:showFeedback(getText("UI_BurdJournals_AlreadyReading") or "Already reading...", "warn")
    end
end

function BurdJournals.UI.MainPanel:absorbTrait(traitId)
    if not self:hasLimitedLootClaimAvailable() then
        return
    end
    if self:shouldBlockLimitedLootQueue() then
        return
    end

    if BurdJournals.playerHasTrait(self.player, traitId) then
        self:showFeedback(getText("UI_BurdJournals_TraitAlreadyKnownFeedback") or "Trait already known!", "muted")
        return
    end

    if self.learningState.active and not self.learningState.isAbsorbAll then
        if self:addToQueue("trait", traitId) then
            local traitName = safeGetTraitName(traitId)
            self:showFeedback(BurdJournals.formatText(getText("UI_BurdJournals_Queued") or "Queued: %s", traitName), "info")
        else
            self:showFeedback(getText("UI_BurdJournals_AlreadyQueued") or "Already queued", "warn")
        end
        return
    end

    if not self:startLearningTrait(traitId) then
        self:showFeedback(getText("UI_BurdJournals_AlreadyReading") or "Already reading...", "warn")
    end
end

function BurdJournals.UI.MainPanel:absorbRecipe(recipeName)
    if not self:hasLimitedLootClaimAvailable() then
        return
    end
    if self:shouldBlockLimitedLootQueue() then
        return
    end

    if self.learningState.active and not self.learningState.isAbsorbAll then
        if self:addToQueue("recipe", recipeName) then
            local displayName = BurdJournals.getRecipeDisplayName(recipeName)
            self:showFeedback(BurdJournals.formatText(getText("UI_BurdJournals_Queued") or "Queued: %s", displayName), "info")
        else
            self:showFeedback(getText("UI_BurdJournals_AlreadyQueued") or "Already queued", "warn")
        end
        return
    end

    if not self:startLearningRecipe(recipeName) then
        self:showFeedback(getText("UI_BurdJournals_AlreadyReading") or "Already reading...", "warn")
    end
end

function BurdJournals.UI.MainPanel:eraseSkillEntry(skillName)
    if not self.journal or not skillName then return end

    if not BurdJournals.hasEraser(self.player) then
        self:showFeedback(getText("UI_BurdJournals_NeedEraser") or "Need eraser", "warn")
        return
    end

    -- Initialize erasingState if needed
    if not self.erasingState then
        self.erasingState = { active = false, queue = {} }
    end

    -- If already erasing something, add to queue
    if self.erasingState.active then
        self:addToEraseQueue("skill", skillName)
    else
        -- Start erasing directly
        BurdJournals.queueEraseAction(self.player, self.journal, "skill", skillName, self)
    end
end

function BurdJournals.UI.MainPanel:eraseTraitEntry(traitId)
    if not self.journal or not traitId then return end

    if not BurdJournals.hasEraser(self.player) then
        self:showFeedback(getText("UI_BurdJournals_NeedEraser") or "Need eraser", "warn")
        return
    end

    -- Initialize erasingState if needed
    if not self.erasingState then
        self.erasingState = { active = false, queue = {} }
    end

    -- If already erasing something, add to queue
    if self.erasingState.active then
        self:addToEraseQueue("trait", traitId)
    else
        -- Start erasing directly
        BurdJournals.queueEraseAction(self.player, self.journal, "trait", traitId, self)
    end
end

function BurdJournals.UI.MainPanel:eraseRecipeEntry(recipeName)
    if not self.journal or not recipeName then return end

    if not BurdJournals.hasEraser(self.player) then
        self:showFeedback(getText("UI_BurdJournals_NeedEraser") or "Need eraser", "warn")
        return
    end

    -- Initialize erasingState if needed
    if not self.erasingState then
        self.erasingState = { active = false, queue = {} }
    end

    -- If already erasing something, add to queue
    if self.erasingState.active then
        self:addToEraseQueue("recipe", recipeName)
    else
        -- Start erasing directly
        BurdJournals.queueEraseAction(self.player, self.journal, "recipe", recipeName, self)
    end
end

function BurdJournals.UI.MainPanel:eraseStatEntry(statId)
    if not self.journal or not statId then return end

    if not BurdJournals.hasEraser(self.player) then
        self:showFeedback(getText("UI_BurdJournals_NeedEraser") or "Need eraser", "warn")
        return
    end

    -- Initialize erasingState if needed
    if not self.erasingState then
        self.erasingState = { active = false, queue = {} }
    end

    -- If already erasing something, add to queue
    if self.erasingState.active then
        self:addToEraseQueue("stat", statId)
    else
        -- Start erasing directly
        BurdJournals.queueEraseAction(self.player, self.journal, "stat", statId, self)
    end
end

function BurdJournals.UI.MainPanel:eraseEntryDirectly(entryType, entryName)
    if not self.journal or not entryType or not entryName then return end

    local modData = self.journal:getModData()
    local journalData = modData.BurdJournals
    if not journalData then return end

    -- Get display name safely (wrap lookups in pcall to handle missing factories)
    local displayName = entryName
    if entryType == "skill" then
        if Perks and Perks.FromString and PerkFactory and PerkFactory.getPerkName then
            local perk = Perks.FromString(entryName)
            if perk then
                displayName = PerkFactory.getPerkName(perk) or entryName
            end
        end
    elseif entryType == "trait" then
        if TraitFactory and TraitFactory.getTrait then
            local trait = TraitFactory.getTrait(entryName)
            if trait and trait.getLabel then
                local label = trait:getLabel()
                displayName = (label and getText(label)) or entryName
            end
        end
    elseif entryType == "recipe" then
        if getScriptManager then
            local scriptMgr = getScriptManager()
            if scriptMgr and scriptMgr.getRecipe then
                local recipe = scriptMgr:getRecipe(entryName)
                if recipe and recipe.getName then
                    displayName = recipe:getName() or entryName
                end
            end
        end
    elseif entryType == "stat" then
        local statDef = BurdJournals.getStatById and BurdJournals.getStatById(entryName) or nil
        if statDef then
            displayName = BurdJournals.safeGetText(statDef.nameKey, statDef.nameFallback or entryName)
        else
            displayName = entryName
        end
    end

    local erased = false

    if entryType == "skill" then
        if journalData.skills and journalData.skills[entryName] then
            journalData.skills[entryName] = nil
            erased = true
        end
        if journalData.claimedSkills then
            journalData.claimedSkills[entryName] = nil
        end
    elseif entryType == "trait" then
        if journalData.traits and journalData.traits[entryName] then
            journalData.traits[entryName] = nil
            erased = true
        end
        if journalData.claimedTraits then
            journalData.claimedTraits[entryName] = nil
        end
    elseif entryType == "recipe" then
        if journalData.recipes and journalData.recipes[entryName] then
            journalData.recipes[entryName] = nil
            erased = true
        end
        if journalData.claimedRecipes then
            journalData.claimedRecipes[entryName] = nil
        end
    elseif entryType == "stat" then
        if journalData.stats and journalData.stats[entryName] then
            journalData.stats[entryName] = nil
            erased = true
        end
        if journalData.claimedStats then
            journalData.claimedStats[entryName] = nil
        end
    end

    if erased then

        safeTransmitPanelJournalModData(self.journal, "mainPanelCurrentJournal")

        self:showFeedback(BurdJournals.formatText(getText("UI_BurdJournals_EntryErased") or "Erased: %s", displayName), "success")

        if self.mode == "view" then
            self:refreshCurrentList()
        else
            self:refreshAbsorptionList()
        end

        self:playSound(BurdJournals.Sounds.PAGE_TURN)

        -- Notify Debug Panel to refresh if it's open and editing this journal
        -- Use deferred update to avoid refresh during render cycle which can cause draw crashes
        if BurdJournals.UI and BurdJournals.UI.DebugPanel and BurdJournals.UI.DebugPanel.instance then
            local debugPanel = BurdJournals.UI.DebugPanel.instance
            if debugPanel.editingJournal and debugPanel.editingJournal == self.journal then
                -- Mark for deferred refresh instead of immediate refresh
                debugPanel.needsJournalRefresh = true
            end
        end
    end
end

function BurdJournals.UI.MainPanel:addToQueue(rewardType, name, xpOrValue)

    if rewardType == "trait" and BurdJournals.playerHasTrait(self.player, name) then
        return false
    end

    -- Check if already being learned
    if self.learningState.skillName == name or self.learningState.traitId == name or
       self.learningState.forgetTraitId == name or self.learningState.recipeName == name or self.learningState.statId == name then
        return false
    end

    for _, queued in ipairs(self.learningState.queue) do
        if queued.name == name then
            return false
        end
    end

    local queueItem = {
        type = rewardType,
        name = name,
    }

    -- Stats use 'value' instead of 'xp'
    if rewardType == "stat" then
        queueItem.value = xpOrValue
    else
        queueItem.xp = xpOrValue
    end

    table.insert(self.learningState.queue, queueItem)

    self:playSound(BurdJournals.Sounds.QUEUE_ADD)

    return true
end

function BurdJournals.UI.MainPanel:getQueuePosition(name)
    for i, queued in ipairs(self.learningState.queue) do
        if queued.name == name then
            return i
        end
    end
    return nil
end

function BurdJournals.UI.MainPanel:removeFromQueue(name)
    for i, queued in ipairs(self.learningState.queue) do
        if queued.name == name then
            table.remove(self.learningState.queue, i)
            return true
        end
    end
    return false
end

function BurdJournals.UI.MainPanel:addToRecordQueue(recordType, name, xp, level, baselineXP)
    if not self.recordingState then return false end
    if not self.recordingState.queue then
        self.recordingState.queue = {}
    end

    if self.recordingState.skillName == name or self.recordingState.traitId == name or self.recordingState.statId == name or self.recordingState.recipeName == name then
        return false
    end

    for _, queued in ipairs(self.recordingState.queue) do
        if queued.name == name then
            return false
        end
    end

    table.insert(self.recordingState.queue, {
        type = recordType,
        name = name,
        xp = xp,
        level = level,
        baselineXP = baselineXP,
        value = xp
    })

    self:playSound(BurdJournals.Sounds.QUEUE_ADD)

    return true
end

function BurdJournals.UI.MainPanel:getRecordQueuePosition(name)
    if not self.recordingState or not self.recordingState.queue then return nil end
    for i, queued in ipairs(self.recordingState.queue) do
        if queued.name == name then
            return i
        end
    end
    return nil
end

-- Erase queue management functions
function BurdJournals.UI.MainPanel:addToEraseQueue(entryType, entryName)
    if not self.erasingState then
        self.erasingState = { active = false, queue = {} }
    end
    if not self.erasingState.queue then
        self.erasingState.queue = {}
    end

    -- Check if already being erased
    if self.erasingState.active and self.erasingState.entryName == entryName then
        return false
    end

    -- Check if already in queue
    for _, queued in ipairs(self.erasingState.queue) do
        if queued.name == entryName then
            return false
        end
    end

    table.insert(self.erasingState.queue, {
        type = entryType,
        name = entryName
    })

    self:playSound(BurdJournals.Sounds.QUEUE_ADD)
    return true
end

function BurdJournals.UI.MainPanel:getEraseQueuePosition(name)
    if not self.erasingState or not self.erasingState.queue then return nil end
    for i, queued in ipairs(self.erasingState.queue) do
        if queued.name == name then
            return i
        end
    end
    return nil
end

function BurdJournals.UI.MainPanel:removeFromEraseQueue(name)
    if not self.erasingState or not self.erasingState.queue then return false end
    for i, queued in ipairs(self.erasingState.queue) do
        if queued.name == name then
            table.remove(self.erasingState.queue, i)
            return true
        end
    end
    return false
end

function BurdJournals.UI.MainPanel:processNextEraseInQueue()
    if not self.erasingState or not self.erasingState.queue then return end
    if self.erasingState.active then return end -- Still erasing something

    if #self.erasingState.queue > 0 then
        local nextItem = table.remove(self.erasingState.queue, 1)
        if nextItem then
            BurdJournals.queueEraseAction(self.player, self.journal, nextItem.type, nextItem.name, self)
        end
    end
end

function BurdJournals.UI.MainPanel:applySkillXPDirectly(skillName, xp, skipDissolutionCheck)

    self:refreshPlayer()

    local perk = BurdJournals.getPerkByName(skillName)
    if perk and xp and xp > 0 then
        local journalMultiplier = BurdJournals.getSandboxOption("JournalXPMultiplier") or 1.0
        local skillBookMultiplier = 1.0
        if BurdJournals.shouldApplySkillBookMultiplierForJournal(self.journal) then
            skillBookMultiplier = BurdJournals.getSkillBookMultiplier(self.player, skillName)
        end
        local xpToApply = xp * journalMultiplier * skillBookMultiplier

        local isPassiveSkill = (skillName == "Fitness" or skillName == "Strength")
        if isPassiveSkill then
            xpToApply = xpToApply * 5
        end

        local applied, applyVia, actualGain = false, "none", 0
        if BurdJournals.applySkillXPCompat then
            applied, applyVia, actualGain = BurdJournals.applySkillXPCompat(self.player, perk, skillName, xpToApply, "add")
        else
            local xpObj = self.player:getXp()
            local beforeXP = BurdJournals.getPlayerSkillTotalXP and BurdJournals.getPlayerSkillTotalXP(self.player, perk, skillName) or xpObj:getXP(perk)
            if BurdJournals.applyXPDeltaCompat then
                BurdJournals.applyXPDeltaCompat(self.player, perk, xpToApply)
            else
                xpObj:AddXP(perk, xpToApply)
            end
            local afterXP = BurdJournals.getPlayerSkillTotalXP and BurdJournals.getPlayerSkillTotalXP(self.player, perk, skillName) or xpObj:getXP(perk)
            actualGain = math.max(0, afterXP - beforeXP)
            applied = actualGain > 0
            applyVia = "legacy"
        end

        -- Use per-character claims for SP/host path to match server behavior
        local journalData = self.journal:getModData().BurdJournals
        if applied and journalData then
            BurdJournals.markSkillClaimedByCharacter(journalData, self.player, skillName)
            safeTransmitPanelJournalModData(self.journal, "mainPanelCurrentJournal")
        end

        if actualGain > 0 then
            self:showFeedback(BurdJournals.formatText(getText("UI_BurdJournals_GainedXP") or "+%s %s", BurdJournals.formatXP(actualGain), BurdJournals.getPerkDisplayName(skillName)), "success")
        elseif applied then
            self:showFeedback(getText("UI_BurdJournals_SkillMaxed") or "Skill already maxed!", "muted")
        else
            BurdJournals.debugPrint("[BurdJournals] applySkillXPDirectly failed via " .. tostring(applyVia))
            self:showFeedback(BurdJournals.safeGetText("UI_BurdJournals_JournalClaimFailed", "Could not apply this journal reward"), "error")
        end

        -- Skip refresh/dissolution during batch operations
        if not skipDissolutionCheck then
            self:refreshAbsorptionList()
            self:checkDissolution(true)
        end
    end
end

function BurdJournals.UI.MainPanel:applyTraitDirectly(traitId, skipDissolutionCheck)

    local player = self.player

    if not player then
        self:showFeedback(getText("UI_BurdJournals_NoPlayer") or "No player!", "error")
        return
    end

    -- Use per-character claims for SP/host path to match server behavior
    local journalData = self.journal:getModData().BurdJournals

    if BurdJournals.playerHasTrait(player, traitId) then
        -- Still mark as claimed even if already known (allows dissolution)
        if journalData then
            BurdJournals.markTraitClaimedByCharacter(journalData, player, traitId)
            safeTransmitPanelJournalModData(self.journal, "mainPanelCurrentJournal")
        end
        self:showFeedback(getText("UI_BurdJournals_TraitAlreadyKnownFeedback") or "Trait already known!", "muted")
        -- Skip refresh/dissolution during batch operations
        if not skipDissolutionCheck then
            self:refreshAbsorptionList()
            self:checkDissolution(true)
        end
        return
    end

    if BurdJournals.safeAddTrait(player, traitId) then
        local allowCancellation = BurdJournals.getSandboxOption("AllowMutualExclusionCancellation")
        if allowCancellation == nil then allowCancellation = true end
        if allowCancellation and BurdJournals.getConflictingTraits and BurdJournals.safeRemoveTrait then
            local conflicts = BurdJournals.getConflictingTraits(player, traitId)
            for _, conflictId in ipairs(conflicts) do
                BurdJournals.safeRemoveTrait(player, conflictId)
            end
        end

        if journalData then
            BurdJournals.markTraitClaimedByCharacter(journalData, player, traitId)
            safeTransmitPanelJournalModData(self.journal, "mainPanelCurrentJournal")
        end
        local traitName = safeGetTraitName(traitId)
        self:showFeedback(BurdJournals.formatText(getText("UI_BurdJournals_GainedTrait") or "Gained trait: %s", traitName), "success")
    else
        self:showFeedback(getText("UI_BurdJournals_FailedToAddTrait") or "Failed to add trait!", "error")
    end

    -- Skip refresh/dissolution during batch operations
    if not skipDissolutionCheck then
        self:refreshAbsorptionList()
        self:checkDissolution(true)
    end
end

function BurdJournals.UI.MainPanel:showFeedback(text, color)
    local resolvedColor = color
    if type(color) == "string" and self.mode == "absorb" then
        local pal = self.palette or getRewardPalette(self.rewardTheme)
        local feedbackKeyMap = {
            info = "feedbackInfo",
            warn = "feedbackWarn",
            success = "feedbackSuccess",
            muted = "feedbackMuted",
            error = "feedbackError",
        }
        local paletteKey = feedbackKeyMap[color]
        local themed = paletteKey and paletteColor(pal, paletteKey) or nil
        if themed then
            resolvedColor = {r=themed.r, g=themed.g, b=themed.b}
        end
    end
    if type(resolvedColor) ~= "table" then
        resolvedColor = {r=0.7, g=0.9, b=0.7}
    end
    if self.feedbackLabel then
        self.feedbackLabel:setName(text)
        self.feedbackLabel:setColor(resolvedColor.r, resolvedColor.g, resolvedColor.b)
        self.feedbackLabel:setVisible(true)
        self.feedbackTicks = 120
    end
end

function BurdJournals.UI.MainPanel:playSound(soundData)
    if not soundData then return end

    local uiSound, worldSound
    if type(soundData) == "string" then
        worldSound = soundData
    elseif type(soundData) == "table" then
        uiSound = soundData.ui
        worldSound = soundData.world
    else
        return
    end

    if uiSound and getSoundManager then
        local soundMgr = getSoundManager()
        if soundMgr and soundMgr.playUISound then
            soundMgr:playUISound(uiSound)
        end
    end

    if worldSound and self.player and self.player.playSound then
        self.player:playSound(worldSound)
    end
end

function BurdJournals.UI.MainPanel:checkDissolution(forceAutoDissolve)
    if forceAutoDissolve ~= true then
        return
    end

    -- Guard against invalid/zombie journal objects
    if not self.journal or not BurdJournals.isValidItem(self.journal) then return end
    if not self.journal.getModData then return end
    self.journal:getModData()

    -- Pass player for per-character dissolution check
    if BurdJournals.shouldDissolve(self.journal, self.player) then
        local dissolveMsg = BurdJournals.getRandomDissolutionMessage()

        -- In MP, route dissolution through server to avoid desync
        -- Server response will trigger the Say message via handleJournalDissolved
        if BurdJournals.clientShouldUseServerAuthority() and BurdJournals.Client and BurdJournals.Client.sendToServer then
            local journalData = BurdJournals.getJournalData and BurdJournals.getJournalData(self.journal) or nil
            local lookupArgs = BurdJournals.buildJournalCommandPayload
                and BurdJournals.buildJournalCommandPayload(self.journal, journalData, true)
                or {
                    journalId = self.journal and self.journal.getID and self.journal:getID() or nil,
                    journalUUID = type(journalData) == "table" and journalData.uuid or nil,
                    journalFingerprint = nil,
                    journalData = nil,
                }
            BurdJournals.Client.sendToServer("dissolveJournal", {
                journalId = lookupArgs.journalId,
                journalUUID = lookupArgs.journalUUID,
                journalFingerprint = lookupArgs.journalFingerprint,
                journalData = lookupArgs.journalData,
            })
        else
            -- SP/host: Remove directly and show message
            local container = self.journal:getContainer()
            if container then container:Remove(self.journal) end
            self.player:getInventory():Remove(self.journal)
            -- Show speaking bubble for SP (MP gets this from server response)
            if self.player and self.player.Say then
                self.player:Say(dissolveMsg)
            end
        end

        self:playSound(BurdJournals.Sounds.DISSOLVE)

        self:onClose()
    end
end

function BurdJournals.UI.MainPanel:update()
    ISPanelJoypad.update(self)

    applyPendingListBoxScrollRestore(self)

    if self.feedbackTicks and self.feedbackTicks > 0 then
        self.feedbackTicks = self.feedbackTicks - 1
        if self.feedbackTicks <= 0 and self.feedbackLabel then
            self.feedbackLabel:setVisible(false)
        end
    end

    if self.pendingNewJournalId then

        self.pendingJournalCheckCounter = (self.pendingJournalCheckCounter or 0) + 1
        if self.pendingJournalCheckCounter >= 30 then
            self.pendingJournalCheckCounter = 0
            local newJournal = self:findPendingNewJournalInInventory()
            if newJournal then
                BurdJournals.debugPrint("[BurdJournals] update: Found pending new journal! Updating reference.")
                self.journal = newJournal
                self.pendingNewJournalId = nil
                self.pendingJournalCheckCounter = 0

                self:refreshJournalData()
            end
        end
    end
end

function BurdJournals.UI.MainPanel:onClose()

    if self.currentTab == "notes" and self.saveNotesIfDirty then
        self:saveNotesIfDirty("close")
    end

    if self.learningCompleted then
        self:doClose()
        return
    end

    if self.processingQueue then
        self:doClose()
        return
    end

    if self.learningState and self.learningState.active then

        self:showCloseConfirmDialog()
        return
    end

    self:doClose()
end

function BurdJournals.UI.MainPanel:isJoypadFocusWithinPanel(joypadData)
    if not joypadData then
        return false
    end
    if isJoypadFocusOnElementOrDescendant then
        return isJoypadFocusOnElementOrDescendant(self.playerNum, self) == true
    end
    local focus = joypadData.focus
    while focus do
        if focus == self then
            return true
        end
        focus = focus.parent
    end
    return false
end

function BurdJournals.UI.MainPanel:activateJoypadFocus()
    local joypadActive, joypadData = self:isJoypadActive()
    if not joypadActive or not joypadData or not setJoypadFocus then
        return
    end

    if joypadData.focus ~= self then
        self.prevJoypadFocus = joypadData.focus
    end
    setJoypadFocus(self.playerNum, self)
    if updateJoypadFocus then
        updateJoypadFocus(joypadData)
    end
end

function BurdJournals.UI.MainPanel:restoreJoypadFocusAfterClose()
    local _, joypadData = self:isJoypadActive()
    if not joypadData or not setJoypadFocus then
        self.prevJoypadFocus = nil
        return
    end

    local shouldRestore = self:isJoypadFocusWithinPanel(joypadData)
    if shouldRestore then
        local restoreFocus = self.prevJoypadFocus
        local cursor = restoreFocus
        while cursor do
            if cursor == self then
                restoreFocus = nil
                break
            end
            cursor = cursor.parent
        end

        setJoypadFocus(self.playerNum, restoreFocus)
        if updateJoypadFocus then
            updateJoypadFocus(joypadData)
        end
    end

    self.prevJoypadFocus = nil
end

function BurdJournals.UI.MainPanel:onGainJoypadFocus(joypadData)
    ISPanelJoypad.onGainJoypadFocus(self, joypadData)
    self:rebuildJoypadRows()
    self:refreshControllerPrompts(true)
end

function BurdJournals.UI.MainPanel:onLoseJoypadFocus(joypadData)
    ISPanelJoypad.onLoseJoypadFocus(self, joypadData)
    self.listFocusActive = false
    self:clearJoypadFocus(joypadData)
end

function BurdJournals.UI.MainPanel:onJoypadDown(button, joypadData)
    local focusedChild = self.getJoypadFocus and self:getJoypadFocus() or nil
    local textEntryFocused = focusedChild and focusedChild.Type == "ISTextEntryBox"
    local listPreEntry = self:isListFocusAmbiguous()

    if button == Joypad.LBumper then
        self:cycleTopTab(-1)
        return
    end

    if button == Joypad.RBumper then
        self:cycleTopTab(1)
        return
    end

    if button == Joypad.BButton then
        if self.listFocusActive and focusedChild == self.skillList then
            self:exitListJoypadFocus(joypadData)
            return
        end
        self:onClose()
        return
    end

    if button == Joypad.AButton and not textEntryFocused and listPreEntry then
        if self:enterListJoypadFocus(joypadData) then
            return
        end
    end

    if button == Joypad.YButton and not textEntryFocused then
        if listPreEntry then
            return
        end
        if not self:performTabBatchAction() then
            self:showFeedback(
                getText("UI_BurdJournals_ControllerNoTabAction") or "No tab action available right now",
                {r=0.95, g=0.75, b=0.4}
            )
        end
        return
    end

    if button == Joypad.XButton and not textEntryFocused and self.listFocusActive and focusedChild == self.skillList then
        local item = self:getSelectedListItem()
        if not item or not self:performSecondaryListAction(item) then
            self:showFeedback(
                getText("UI_BurdJournals_ControllerNoSecondaryAction") or "No secondary action for this entry",
                {r=0.95, g=0.75, b=0.4}
            )
        end
        return
    end

    ISPanelJoypad.onJoypadDown(self, button, joypadData)
end

function BurdJournals.UI.MainPanel:setBorrowReturnContainer(returnContainer)
    if isEligibleJournalReturnContainer(self.player, returnContainer) then
        self.borrowReturnContainer = returnContainer
    else
        self.borrowReturnContainer = nil
    end
end

function BurdJournals.UI.MainPanel:tryReturnBorrowedJournal()
    local returnContainer = self.borrowReturnContainer
    if not returnContainer then return end
    self.borrowReturnContainer = nil

    if self.learningState and self.learningState.active then return end
    if self.processingQueue then return end
    if self.recordingState and self.recordingState.active then return end
    if not self.player or not self.journal then return end
    if not BurdJournals.isValidItem(self.journal) then return end
    if not isEligibleJournalReturnContainer(self.player, returnContainer) then return end

    local currentContainer = self.journal:getContainer()
    if not currentContainer or currentContainer == returnContainer then return end
    if not currentContainer.isInCharacterInventory or not currentContainer:isInCharacterInventory(self.player) then
        return
    end

    if not (ISInventoryTransferUtil and ISInventoryTransferUtil.newInventoryTransferAction) then
        return
    end

    local action = ISInventoryTransferUtil.newInventoryTransferAction(
        self.player,
        self.journal,
        currentContainer,
        returnContainer,
        nil
    )
    if not action then return end
    if action.setAllowMissingItems then
        action:setAllowMissingItems(true)
    end
    ISTimedActionQueue.add(action)
end

function BurdJournals.UI.MainPanel:doClose()

    BurdJournals.safeRemoveEvent(Events.OnTick, BurdJournals.UI.MainPanel.onLearningTickStatic)
    BurdJournals.safeRemoveEvent(Events.OnTick, BurdJournals.UI.MainPanel.onRecordingTickStatic)
    BurdJournals.safeRemoveEvent(Events.OnTick, BurdJournals.UI.MainPanel.onPendingJournalRetryStatic)
    if self._headerRefreshTickHandler then
        BurdJournals.safeRemoveEvent(Events.OnTick, self._headerRefreshTickHandler)
        self._headerRefreshTickHandler = nil
    end

    if self.learningState and self.learningState.active then
        self:cancelLearning()
    end

    if (self.recordingState and self.recordingState.active) or self.recordAllAuthoritySettleTick then
        self:cancelRecording()
    end
    if (self.pendingRecordAllContinuation or self.pendingRecordSingleContinuation
        or self.pendingRecordAllReconcile or self.recordAllContinuationWatchdog)
        and BurdJournals.clearRecordContinuationState
    then
        BurdJournals.clearRecordContinuationState(self, "panelClosed")
    end

    local pendingBatchRequestId = self.pendingBatchRewardRequestId
    if pendingBatchRequestId and BurdJournals.Client and BurdJournals.Client._pendingBatchRewardRequests then
        BurdJournals.Client._pendingBatchRewardRequests[pendingBatchRequestId] = nil
        if BurdJournals.Client.stopBatchRewardRequestTickIfIdle then
            BurdJournals.Client.stopBatchRewardRequestTickIfIdle()
        end
    end
    self.pendingBatchRewardRequestId = nil
    self.pendingBatchRewardMode = nil
    self.pendingLearnAllContinuation = nil
    self.pendingLearnSingleContinuation = nil
    self.pendingLearnBulkIntent = nil
    self.isProcessingRewards = false
    self.rewardProcessingQueue = nil
    self.processingQueue = false

    if self.confirmDialog then
        if self.confirmDialog.setVisible then
            self.confirmDialog:setVisible(false)
        end
        if self.confirmDialog.removeFromUIManager then
            self.confirmDialog:removeFromUIManager()
        end
        self.confirmDialog = nil
    end
    if self.notesConfirmDialog then
        if self.notesConfirmDialog.setVisible then
            self.notesConfirmDialog:setVisible(false)
        end
        if self.notesConfirmDialog.removeFromUIManager then
            self.notesConfirmDialog:removeFromUIManager()
        end
        self.notesConfirmDialog = nil
    end

    -- Unregister from baseline change notifications
    self:unregisterOpenPanel()

    self.listFocusActive = false
    self:clearAllJoypadPrompts()
    self:tryReturnBorrowedJournal()
    self:restoreJoypadFocusAfterClose()

    self:setVisible(false)
    self:removeFromUIManager()
    BurdJournals.UI.MainPanel.instance = nil
end

function BurdJournals.UI.MainPanel:onCloseConfirmDialogResult(button)
    self.confirmDialog = nil
    if not button then
        return
    end
    if button.internal == "NO" then
        self:doClose()
    end
end

function BurdJournals.UI.MainPanel:showCloseConfirmDialog()
    if self.confirmDialog then
        if self.confirmDialog.bringToTop then
            self.confirmDialog:bringToTop()
        end
        local joypadActive, joypadData = self:isJoypadActive()
        if joypadActive and setJoypadFocus then
            setJoypadFocus(self.playerNum, self.confirmDialog)
            if updateJoypadFocus and joypadData then
                updateJoypadFocus(joypadData)
            end
        end
        return
    end

    local warningText = getText("UI_BurdJournals_StateReading") or "Reading..."
    local subText = getText("UI_BurdJournals_ConfirmCancelLearning") or "Cancel learning and close?"
    local keepText = getText("UI_BurdJournals_BtnKeepReading") or "Keep Reading"
    local closeText = getText("UI_BurdJournals_BtnCancelClose") or "Cancel & Close"
    local promptText = warningText .. "\n" .. subText

    local function configureModal(modal)
        if not modal then
            return
        end

        modal.prevFocus = self
        modal.moveWithMouse = true
        if modal.yes then
            modal.yes:setTitle(keepText)
            modal.yes.borderColor = {r=0.4, g=0.6, b=0.4, a=1}
            modal.yes.backgroundColor = {r=0.2, g=0.3, b=0.2, a=0.9}
            modal.yes.textColor = {r=0.9, g=1, b=0.9, a=1}
        end
        if modal.no then
            modal.no:setTitle(closeText)
            modal.no.borderColor = {r=0.6, g=0.3, b=0.3, a=1}
            modal.no.backgroundColor = {r=0.35, g=0.15, b=0.15, a=0.9}
            modal.no.textColor = {r=1, g=0.85, b=0.85, a=1}
        end

        -- Safe default: A/B keeps reading. Explicit close uses X.
        modal.onGainJoypadFocus = function(dialog, joypadData)
            ISModalDialog.onGainJoypadFocus(dialog, joypadData)
            if dialog.yes and dialog.no then
                dialog:setISButtonForA(dialog.yes)
                dialog:setISButtonForB(dialog.yes)
                dialog:setISButtonForX(dialog.no)
            end
        end
    end

    local dialog = nil
    if BurdJournals.createAdaptiveModalDialog then
        dialog = BurdJournals.createAdaptiveModalDialog({
            player = self.player,
            target = self,
            text = promptText,
            yesNo = true,
            onClick = BurdJournals.UI.MainPanel.onCloseConfirmDialogResult,
            minWidth = 360,
            maxWidth = 700,
            minHeight = 170,
            afterInit = configureModal,
            joypadSupport = false,
        })
    else
        local x = getCore():getScreenWidth() / 2 - 180
        local y = getCore():getScreenHeight() / 2 - 80
        dialog = ISModalDialog:new(
            x, y,
            360, 160,
            promptText,
            true,
            self,
            BurdJournals.UI.MainPanel.onCloseConfirmDialogResult,
            self.playerNum
        )
        dialog:initialise()
        configureModal(dialog)
        dialog:addToUIManager()
    end

    if not dialog then
        return
    end

    self.confirmDialog = dialog
    if dialog.bringToTop then
        dialog:bringToTop()
    end

    local joypadActive, joypadData = self:isJoypadActive()
    if joypadActive and setJoypadFocus then
        setJoypadFocus(self.playerNum, dialog)
        if updateJoypadFocus and joypadData then
            updateJoypadFocus(joypadData)
        end
    end
end

function BurdJournals.UI.MainPanel.show(player, journal, mode, returnContainer)
    if BurdJournals.canUseJournalInCurrentLight then
        local canUse = BurdJournals.canUseJournalInCurrentLight(player)
        if not canUse then
            showTooDarkFeedback(player)
            return nil
        end
    end

    local existingPanel = BurdJournals.UI.MainPanel.instance
    if existingPanel then
        existingPanel:onClose()
        if BurdJournals.UI.MainPanel.instance == existingPanel then
            return existingPanel
        end
    end

    closePlayerInventoryPanelsForController(player)

    local journalData = BurdJournals.getJournalData(journal)
    if mode ~= "log"
        and journal
        and BurdJournals.isHiddenCursedJournal
        and BurdJournals.isHiddenCursedJournal(journal)
        and sendClientCommand
    then
        local lookupArgs = BurdJournals.buildJournalCommandPayload
            and BurdJournals.buildJournalCommandPayload(journal, journalData, true)
            or {
                journalId = journal.getID and journal:getID() or nil,
                journalUUID = journalData and journalData.uuid or nil,
                journalFingerprint = nil,
                journalData = journalData,
                itemFullType = journal.getFullType and journal:getFullType() or nil,
            }
        if lookupArgs and (lookupArgs.journalId or lookupArgs.journalUUID or lookupArgs.journalFingerprint) then
            sendClientCommand(player, "BurdJournals", "openCursedJournal", {
                journalId = lookupArgs.journalId,
                journalUUID = lookupArgs.journalUUID,
                journalFingerprint = lookupArgs.journalFingerprint,
                journalData = lookupArgs.journalData,
                itemFullType = lookupArgs.itemFullType,
                confirm = false,
            })
            return nil
        end
    end
    if mode == "view"
        and BurdJournals.isUnwrappedYuletideJournal
        and BurdJournals.isUnwrappedYuletideJournal(journal)
    then
        mode = "absorb"
    end

    local baseWidth = 410
    local btnPadding = 20
    local btnSpacing = 12
    local minBtnWidth = 90

    local allTabNames = {
        getText("UI_BurdJournals_TabSkills") or "Skills",
        getText("UI_BurdJournals_TabTraits") or "Traits",
        getText("UI_BurdJournals_TabForget") or "Forget",
        getText("UI_BurdJournals_TabRecipes") or "Recipes",
        getText("UI_BurdJournals_TabStats") or "Stats",
        getText("UI_BurdJournals_TabNotes") or "Notes"
    }

    local maxBtn1W = minBtnWidth
    local btn2Text, btn3Text
    local btnPrefix
    if mode == "log" then
        btnPrefix = getText("UI_BurdJournals_BtnRecordTab") or "Record %s"
        btn2Text = getText("UI_BurdJournals_BtnRecordAll") or "Record All"
    else
        btnPrefix = getText("UI_BurdJournals_BtnAbsorbTab") or "Absorb %s"
        btn2Text = getText("UI_BurdJournals_BtnAbsorbAll") or "Absorb All"
    end
    btn3Text = getText("UI_BurdJournals_BtnClose") or "Close"

    for _, tabName in ipairs(allTabNames) do
        local btn1Text = BurdJournals.formatText(btnPrefix, tabName)
        local btn1W = getTextManager():MeasureStringX(UIFont.Small, btn1Text) + btnPadding
        maxBtn1W = math.max(maxBtn1W, btn1W)
    end

    local btn2W = math.max(minBtnWidth, getTextManager():MeasureStringX(UIFont.Small, btn2Text) + btnPadding)
    local btn3W = math.max(minBtnWidth, getTextManager():MeasureStringX(UIFont.Small, btn3Text) + btnPadding)

    -- Check if dissolve button will be shown for loot-style one-shot journals.
    local showDissolveBtn = mode ~= "log"
        and BurdJournals.shouldShowDissolveButton
        and BurdJournals.shouldShowDissolveButton(journal, player)
        or false

    local btn4Text = getText("UI_BurdJournals_BtnDissolve") or "Dissolve"
    local btn4W = math.max(minBtnWidth, getTextManager():MeasureStringX(UIFont.Small, btn4Text) + btnPadding)

    local maxBtnW = math.max(maxBtn1W, btn2W, btn3W, btn4W)
    local numButtons = showDissolveBtn and 4 or 3
    local totalBtnWidth = maxBtnW * numButtons + btnSpacing * (numButtons - 1) + 48

    local width = math.max(baseWidth, totalBtnWidth)
    if journalData and journalData.isPlayerCreated == true and (mode == "log" or mode == "view") then
        -- Widen Player Journal record/claim panels by ~1.5x erase-button width for extra row text room.
        local eraseBtnWidth = 55
        local playerJournalWidthBonus = math.floor(((eraseBtnWidth * 3) / 2) + 0.5)
        local maxAllowedWidth = math.max(baseWidth, getCore():getScreenWidth() - 40)
        width = math.min(maxAllowedWidth, width + playerJournalWidthBonus)
    end

    local baseHeight = 180
    local itemHeight = 52
    local headerRowHeight = 52
    local minHeight = 420
    -- Max height is screen-aware: leave 100px margin top/bottom
    local screenHeight = getCore():getScreenHeight()
    local maxHeight = math.min(750, screenHeight - 100)
    local skillCount = 0
    local traitCount = 0
    local statCount = 0
    local recipeCount = 0

    if mode == "log" then
        local allowedSkills = BurdJournals.getAllowedSkills()
        if allowedSkills then
            for _, skillName in ipairs(allowedSkills) do
                if BurdJournals.isSkillRecordableInPlayerJournal(skillName) then
                    local perk = BurdJournals.getPerkByName(skillName)
                    if perk then
                        local currentXP = BurdJournals.getPlayerSkillTotalXP and BurdJournals.getPlayerSkillTotalXP(player, perk, skillName) or player:getXp():getXP(perk)
                        local currentLevel = player:getPerkLevel(perk)
                        if currentXP > 0 or currentLevel > 0 then
                            skillCount = skillCount + 1
                        end
                    end
                end
            end
        end

        if BurdJournals.RECORDABLE_STATS then
            for _, stat in ipairs(BurdJournals.RECORDABLE_STATS) do
                if BurdJournals.isStatEnabled(stat.id) then
                    statCount = statCount + 1
                end
            end
        end

        -- Count recordable recipes for log mode
        if BurdJournals.isRecipeRecordingEnabled and BurdJournals.isRecipeRecordingEnabled() then
            local playerRecipes = BurdJournals.collectPlayerMagazineRecipes and BurdJournals.collectPlayerMagazineRecipes(player)
            if playerRecipes then
                for _ in pairs(playerRecipes) do
                    recipeCount = recipeCount + 1
                end
            end
        end
    else
        -- View/absorb mode - count from journal data
        if journalData and journalData.skills then
            for skillName, _ in pairs(journalData.skills) do
                if BurdJournals.isSkillVisibleForJournal(journalData, skillName) then
                    skillCount = skillCount + 1
                end
            end
        end

        if journalData and journalData.traits then
            for _ in pairs(journalData.traits) do
                traitCount = traitCount + 1
            end
        end

        if journalData and journalData.recipes then
            for _ in pairs(journalData.recipes) do
                recipeCount = recipeCount + 1
            end
        end

        if journalData and journalData.stats then
            for _ in pairs(journalData.stats) do
                statCount = statCount + 1
            end
        end
    end

    -- Calculate content height based on the largest tab's content
    -- We use the max of different tab contents since only one tab shows at a time
    local skillsTabHeight = baseHeight + headerRowHeight + (skillCount * itemHeight)
    local traitsTabHeight = baseHeight + headerRowHeight + (traitCount * itemHeight)
    local recipesTabHeight = baseHeight + headerRowHeight + (recipeCount * itemHeight)
    local statsTabHeight = baseHeight + headerRowHeight + (statCount * itemHeight)

    local contentHeight = math.max(skillsTabHeight, traitsTabHeight, recipesTabHeight, statsTabHeight)

    local height = math.max(minHeight, math.min(maxHeight, contentHeight))

    local x = (getCore():getScreenWidth() - width) / 2
    local y = (getCore():getScreenHeight() - height) / 2

    local panel = BurdJournals.UI.MainPanel:new(x, y, width, height, player, journal, mode)
    panel:setBorrowReturnContainer(returnContainer)
    panel:initialise()
    panel:addToUIManager()
    BurdJournals.UI.MainPanel.instance = panel
    panel:activateJoypadFocus()

    return panel
end

function BurdJournals.UI.MainPanel:createLogUI()
    self:refreshPlayer()

    local padding = 16
    local y = 0
    local btnHeight = 32

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

    local journalData = BurdJournals.getJournalData(self.journal) or {}
    local recordedSkills = journalData.skills or {}
    local recordedTraits = journalData.traits or {}
    local recordedRecipes = journalData.recipes or {}

    self.isRecordMode = true
    self.recordedSkills = recordedSkills
    self.recordedTraits = recordedTraits
    self.recordedRecipes = recordedRecipes

    local headerHeight = 52
    self.headerRightInset = 0
    self.headerColor = {r=0.12, g=0.25, b=0.35}
    self.headerAccent = {r=0.2, g=0.45, b=0.55}
    self.typeText = getText("UI_BurdJournals_RecordProgressHeader")
    self.headerIconTexture = getHeaderJournalIconTexture("log", self.journal, journalData, false)
    self.headerIconSize = 20
    self.rarityText = nil
    self.flavorText = getText("UI_BurdJournals_RecordFlavor")
    self.headerHeight = headerHeight
    self:createHeaderRefreshButton(10, 15)
    y = headerHeight + 6

    local playerName = self.player:getDescriptor():getForename() .. " " .. self.player:getDescriptor():getSurname()
    self.authorName = playerName
    self.authorBoxY = y
    self.authorBoxHeight = 44
    y = y + self.authorBoxHeight + 10

    local tabs = {
        {id = "skills", label = getText("UI_BurdJournals_TabSkills")},
    }

    -- Only show traits tab if enabled for player journals
    if BurdJournals.getSandboxOption("EnableTraitRecordingPlayer") ~= false then
        table.insert(tabs, {id = "traits", label = getText("UI_BurdJournals_TabTraits")})
    end

    -- Only show recipes tab if enabled for player journals
    if BurdJournals.getSandboxOption("EnableRecipeRecordingPlayer") ~= false then
        table.insert(tabs, {id = "recipes", label = getText("UI_BurdJournals_TabRecipes")})
    end

    if BurdJournals.getSandboxOption("EnableStatRecording") then
        table.insert(tabs, {id = "charinfo", label = getText("UI_BurdJournals_TabStats")})
    end

    if not BurdJournals.isPlayerJournalNotesEnabled or BurdJournals.isPlayerJournalNotesEnabled() then
        table.insert(tabs, {id = "notes", label = getText("UI_BurdJournals_TabNotes") or "Notes"})
    end

    local tabThemeColors = {
        active = {r=0.18, g=0.32, b=0.42},
        inactive = {r=0.1, g=0.15, b=0.18},
        accent = {r=0.3, g=0.55, b=0.65}
    }
    self.tabThemeColors = tabThemeColors

    y = self:createTabs(tabs, y, tabThemeColors)

    self.filterBaseY = y
    y = self:createFilterTabBar(y, tabThemeColors)

    local skillItemCount = 24
    y = self:createSearchBar(y, tabThemeColors, skillItemCount)

    local footerHeight = 85
    local paginationHeight = BurdJournals.UI.LIST_PAGINATION_HEIGHT or 26
    local listHeight = self.height - y - footerHeight - paginationHeight - padding

    self.skillList = ISScrollingListBox:new(padding, y, self.width - padding * 2, listHeight)
    self.skillList:initialise()
    self.skillList:instantiate()
    self.skillList.drawBorder = false
    self.skillList.backgroundColor = {r=0, g=0, b=0, a=0}
    self.skillList:setFont(UIFont.Small, 2)
    self.skillList.itemheight = 52
    self.skillList.doDrawItem = BurdJournals.UI.MainPanel.doDrawRecordItem
    self.skillList.mainPanel = self
    self.listBottomY = self.skillList:getY() + self.skillList:getHeight()

    self.skillList.onMouseUp = function(listbox, x, y)
        if listbox.vscroll then
            listbox.vscroll.scrolling = false
        end
        local row = listbox:rowAt(x, y)
        if row and row >= 1 and row <= #listbox.items then
            local item = listbox.items[row] and listbox.items[row].item
            if item and not item.isHeader and not item.isEmpty then

                local btnW = 55
                local margin = 10
                local mainBtnStart = listbox:getWidth() - btnW - margin

                if x >= mainBtnStart then
                    listbox.mainPanel:performPrimaryListAction(item)
                end
            end
        end
        return true
    end
    self:wireSkillListJoypad()
    self:addChild(self.skillList)
    y = y + listHeight
    y = self:createPaginationControls(y, tabThemeColors)

    self.footerY = y + 4
    self.footerHeight = footerHeight

    self.feedbackLabel = ISLabel:new(padding, self.footerY + 4, 18, "", 0.7, 0.9, 0.7, 1, UIFont.Small, true)
    self:addChild(self.feedbackLabel)
    self.feedbackLabel:setVisible(false)
    self.feedbackTicks = 0

    local tabName = self:getTabDisplayName(self.currentTab or "skills")
    local recordTabText = BurdJournals.formatText(getText("UI_BurdJournals_BtnRecordTab") or "Record %s", tabName)
    local recordAllText = getText("UI_BurdJournals_BtnRecordAll") or "Record All"
    local closeText = getText("UI_BurdJournals_BtnClose") or "Close"

    local allTabNames = {
        getText("UI_BurdJournals_TabSkills") or "Skills",
        getText("UI_BurdJournals_TabTraits") or "Traits",
        getText("UI_BurdJournals_TabForget") or "Forget",
        getText("UI_BurdJournals_TabRecipes") or "Recipes",
        getText("UI_BurdJournals_TabStats") or "Stats",
        getText("UI_BurdJournals_TabNotes") or "Notes"
    }
    local btnPrefix = getText("UI_BurdJournals_BtnRecordTab") or "Record %s"
    local maxRecordTabW = 90
    for _, name in ipairs(allTabNames) do
        local text = BurdJournals.formatText(btnPrefix, name)
        local w = getTextManager():MeasureStringX(UIFont.Small, text) + 20
        maxRecordTabW = math.max(maxRecordTabW, w)
    end
    local recordAllW = getTextManager():MeasureStringX(UIFont.Small, recordAllText) + 20
    local closeW = getTextManager():MeasureStringX(UIFont.Small, closeText) + 20
    local btnWidth = math.max(90, maxRecordTabW, recordAllW, closeW)

    local btnSpacing = 12
    local totalBtnWidth = btnWidth * 3 + btnSpacing * 2
    local btnStartX = (self.width - totalBtnWidth) / 2
    local btnY = self.footerY + 32

    self.recordTabBtn = ISButton:new(btnStartX, btnY, btnWidth, btnHeight, recordTabText, self, BurdJournals.UI.MainPanel.onRecordTab)
    self.recordTabBtn:initialise()
    self.recordTabBtn:instantiate()
    self.recordTabBtn.borderColor = {r=0.25, g=0.45, b=0.55, a=1}
    self.recordTabBtn.backgroundColor = {r=0.12, g=0.24, b=0.30, a=0.8}
    self.recordTabBtn.textColor = {r=1, g=1, b=1, a=1}
    self:addChild(self.recordTabBtn)

    self.recordAllBtn = ISButton:new(btnStartX + btnWidth + btnSpacing, btnY, btnWidth, btnHeight, recordAllText, self, BurdJournals.UI.MainPanel.onRecordAll)
    self.recordAllBtn:initialise()
    self.recordAllBtn:instantiate()
    self.recordAllBtn.borderColor = {r=0.3, g=0.5, b=0.6, a=1}
    self.recordAllBtn.backgroundColor = {r=0.15, g=0.28, b=0.35, a=0.8}
    self.recordAllBtn.textColor = {r=1, g=1, b=1, a=1}
    self:addChild(self.recordAllBtn)

    self.closeBottomBtn = ISButton:new(btnStartX + (btnWidth + btnSpacing) * 2, btnY, btnWidth, btnHeight, closeText, self, BurdJournals.UI.MainPanel.onClose)
    self.closeBottomBtn:initialise()
    self.closeBottomBtn:instantiate()
    self.closeBottomBtn.borderColor = {r=0.4, g=0.35, b=0.3, a=1}
    self.closeBottomBtn.backgroundColor = {r=0.15, g=0.13, b=0.12, a=0.8}
    self.closeBottomBtn.textColor = {r=0.9, g=0.85, b=0.8, a=1}
    self:addChild(self.closeBottomBtn)
    self._recordButtonLayout = {
        closeX = self.closeBottomBtn:getX(),
    }

    -- Legacy baseline debug buttons removed - use BSJ Debug Center (Baseline tab) instead
    self:updateRecordActionAvailability()
    self:populateRecordList()
    self:rebuildJoypadRows()
end

-- Legacy baseline debug functions removed - use BSJ Debug Center (Baseline tab) instead

function BurdJournals.UI.MainPanel:populateRecordList(overrideData)
    local authoritativeData = overrideData or self:resolvePendingRecordJournalDataForRefresh()
    local hasAuthoritativeData = type(authoritativeData) == "table"
    local journalData
    if overrideData then
        journalData = authoritativeData
        BurdJournals.debugPrint("[BurdJournals] populateRecordList: Using override data from server response")
    else
        journalData = authoritativeData or BurdJournals.getJournalData(self.journal) or {}
    end
    local liveSnapshot = getHydratedSnapshotForEmptyLiveJournal(self.journal, journalData)
    if liveSnapshot then
        self.pendingRecordJournalData = liveSnapshot
        journalData = liveSnapshot
        hasAuthoritativeData = true
    end
    if shouldHydrateOffloadedJournalOnOpen(journalData)
        and BurdJournals.Client
        and BurdJournals.Client.getHydratedJournalSnapshot
        and self.journal
    then
        local snapshot = BurdJournals.Client.getHydratedJournalSnapshot(self.journal,
            BurdJournals.getJournalIdentityUUID and BurdJournals.getJournalIdentityUUID(journalData) or nil)
        if journalDataHasRecordedEntries(snapshot) then
            self.pendingRecordJournalData = snapshot
            journalData = snapshot
            hasAuthoritativeData = true
        end
    end
    if shouldWaitForAuthoritativePlayerJournalData(journalData, hasAuthoritativeData, self.journal)
        or (shouldHydrateOffloadedJournalOnOpen(journalData)
            and not journalDataHasRecordedEntries(journalData)
            and isJournalAuthorityRequestPending(self.journal, journalData))
    then
        self:setPaginatedListEntries({}, {
            id = "entry_store_hydrating",
            data = {
                isEmpty = true,
                text = BurdJournals.safeGetText("UI_BurdJournals_JournalSyncing", "Syncing journal...")
            }
        })
        return
    end
    self:updateRecordActionAvailability()
    local hasWritingTool = self:hasRecordWritingTool()

    local useBaselineForJournal, autoRepairedMode = BurdJournals.resolveJournalRecordingModeForPlayer(journalData, self.player)
    if BurdJournals.shouldForceBaselineRecordingMode(journalData, self.player, autoRepairedMode) then
        useBaselineForJournal = true
    end
    if autoRepairedMode then
        BurdJournals.debugPrint("[BurdJournals] populateRecordList: detected legacy absolute journal entries while baseline flag was set; forcing baseline-mode display so entries can be repaired")
    end

    local baselineReady, normalizedUseBaseline = BurdJournals.ensureBaselineReadyForRecording(self, useBaselineForJournal, "populateRecordList")
    useBaselineForJournal = normalizedUseBaseline
    if not baselineReady then
        self:setPaginatedListEntries({}, {
            id = "initializing",
            data = {
                isEmpty = true,
                text = getText("UI_BurdJournals_BaselineInitializing") or "Please wait - character data initializing..."
            }
        })
        return
    end

    self.recordedSkills = journalData.skills or {}
    self.recordedTraits = journalData.traits or {}
    self.recordedRecipes = journalData.recipes or {}

    local allowedSkills = BurdJournals.getAllowedSkills()
    local recordedSkills = self.recordedSkills
    local recordedTraits = self.recordedTraits
    local currentTab = self.currentTab or "skills"
    local entries = {}
    local emptyEntry = nil

    if currentTab == "notes" then
        if self.refreshNotesTab then
            self:refreshNotesTab(journalData)
        end
        return
    elseif self.hideNotesControls then
        self:hideNotesControls()
    end

    if currentTab == "skills" then
        local matchCount = 0
        local totalSkills = 0
        local useBaseline = useBaselineForJournal

        for _, skillName in ipairs(allowedSkills) do
            if BurdJournals.isSkillRecordableInPlayerJournal(skillName) then
                local perk = BurdJournals.getPerkByName(skillName)
                if perk then
                    local currentXP = BurdJournals.getPlayerSkillTotalXP and BurdJournals.getPlayerSkillTotalXP(self.player, perk, skillName) or self.player:getXp():getXP(perk)
                    local currentLevel = self.player:getPerkLevel(perk)

                    if currentXP > 0 or currentLevel > 0 then
                        totalSkills = totalSkills + 1
                        local displayName = BurdJournals.getPerkDisplayName(skillName)
                        local modSource = BurdJournals.getSkillModId(skillName)

                        if self:matchesSearch(displayName) and self:passesFilter(modSource) then
                            matchCount = matchCount + 1
                            local recordedSkillKey = BurdJournals.resolveSkillKey and BurdJournals.resolveSkillKey(recordedSkills, skillName) or skillName
                            local recordedData = recordedSkills[recordedSkillKey]
                            local recordedXP = recordedData and recordedData.xp or 0
                            local _, recordedRawXP, recordedVhsExcludedXP = BurdJournals.getSkillVhsBreakdown(recordedData, recordedXP)
                            local recordedLevel = recordedData and recordedData.level or 0

                            local baselineXP = 0
                            if useBaseline then
                                baselineXP = BurdJournals.getSkillBaseline(self.player, skillName)
                            end

                            local earnedXP = math.max(0, currentXP - baselineXP)
                            local displayLevel = currentLevel
                            if useBaseline then
                                displayLevel = BurdJournals.getEarnedOnlyDisplayLevel(skillName, earnedXP, currentLevel)
                            end
                            local needsBaselineRepair = useBaseline
                                and BurdJournals.isLikelyAbsoluteSkillEntryForBaseline(journalData, self.player, skillName, recordedXP, currentXP, baselineXP)
                            local canRecord = hasWritingTool and (earnedXP > recordedXP or needsBaselineRepair)

                            local isPassiveSkill = (skillName == "Fitness" or skillName == "Strength")
                            local baselineLevel = BurdJournals.getSkillBaselineLevel(self.player, skillName) or 0
                            local isAtBaseline = false
                            if useBaseline and baselineXP > 0 then
                                isAtBaseline = earnedXP <= 0
                            end

                            local skillTooltip = BurdJournals.buildSkillVhsTooltip({
                                xp = recordedXP,
                                rawXP = recordedRawXP,
                                vhsExcludedXP = recordedVhsExcludedXP,
                                vhsMediaLines = recordedData and recordedData.vhsMediaLines or nil
                            }, nil, nil, baselineXP)

                            local currentVhsMediaLines = nil
                            if BurdJournals.getPlayerVhsMediaLinesForSkill then
                                currentVhsMediaLines = BurdJournals.getPlayerVhsMediaLinesForSkill(self.player, skillName, useBaseline and baselineXP or 0)
                            end
                            self:appendListEntry(entries, skillName, {
                                isSkill = true,
                                skillName = skillName,
                                displayName = displayName,
                                xp = earnedXP,
                                currentXP = currentXP,
                                level = currentLevel,
                                displayLevel = displayLevel,
                                recordedXP = recordedXP,
                                recordedRawXP = recordedRawXP,
                                recordedVhsExcludedXP = recordedVhsExcludedXP,
                                recordedVhsMediaLines = recordedData and recordedData.vhsMediaLines or nil,
                                vhsMediaLines = currentVhsMediaLines or (recordedData and recordedData.vhsMediaLines) or nil,
                                recordedLevel = recordedLevel,
                                isRecorded = recordedXP > 0,
                                canRecord = canRecord,
                                baselineXP = baselineXP,
                                baselineLevel = baselineLevel,
                                earnedXP = earnedXP,
                                needsBaselineRepair = needsBaselineRepair,
                                isAtBaseline = isAtBaseline,
                                isPassiveSkill = isPassiveSkill,
                                modSource = modSource,
                            }, skillTooltip, displayName, totalSkills)
                        end
                    end
                end
            end
        end

        if matchCount == 0 then
            if totalSkills == 0 then
                emptyEntry = {id = "empty", data = {isEmpty = true, text = getText("UI_BurdJournals_NoSkillsToRecord") or "No skills to record yet"}}
            else
                emptyEntry = {id = "empty", data = {isEmpty = true, text = getText("UI_BurdJournals_NoSearchResults") or "No results found"}}
            end
        end

    elseif currentTab == "traits" then
        local playerTraits = BurdJournals.collectPlayerTraits(self.player, false)
        local grantableTraitList = (BurdJournals.getGrantableTraitsForJournal and BurdJournals.getGrantableTraitsForJournal(journalData))
            or (BurdJournals.getGrantableTraits and BurdJournals.getGrantableTraits())
            or BurdJournals.GRANTABLE_TRAITS or {}
        local positiveTraits = {}
        for traitId, traitData in pairs(playerTraits) do
            if BurdJournals.isTraitGrantable(traitId, grantableTraitList)
                and (not BurdJournals.isTraitEnabledForJournal or BurdJournals.isTraitEnabledForJournal(journalData, traitId))
            then
                positiveTraits[traitId] = traitData
            end
        end

        local matchCount = 0
        local totalTraits = 0
        local recordedTraitLookup = BurdJournals.buildTraitLookup and BurdJournals.buildTraitLookup(recordedTraits) or recordedTraits
        for traitId, traitData in pairs(positiveTraits) do
            totalTraits = totalTraits + 1
            local traitName = safeGetTraitName(traitId)
            local modSource = BurdJournals.getTraitModId(traitId)

            if self:matchesSearch(traitName) and self:passesFilter(modSource) then
                matchCount = matchCount + 1
                local traitTexture = getTraitTexture(traitId)
                local isRecorded = BurdJournals.isTraitInLookup and BurdJournals.isTraitInLookup(recordedTraitLookup, traitId) or recordedTraits[traitId] ~= nil or recordedTraits[string.lower(traitId)] ~= nil
                local isStartingTrait = BurdJournals.isStartingTrait(self.player, traitId)
                local isPositive = isTraitPositive(traitId)

                self:appendListEntry(entries, traitId, {
                    isTrait = true,
                    traitId = traitId,
                    traitName = traitName,
                    traitTexture = traitTexture,
                    isRecorded = isRecorded,
                    isStartingTrait = isStartingTrait,
                    canRecord = hasWritingTool and not isRecorded and not isStartingTrait,
                    isPositive = isPositive,
                    modSource = modSource,
                }, nil, traitName)
            end
        end

        if matchCount == 0 then
            if totalTraits == 0 then
                emptyEntry = {id = "empty", data = {isEmpty = true, text = getText("UI_BurdJournals_NoTraitsToRecord") or "No traits to record"}}
            else
                emptyEntry = {id = "empty", data = {isEmpty = true, text = getText("UI_BurdJournals_NoSearchResults") or "No results found"}}
            end
        end

    elseif currentTab == "charinfo" then
        if BurdJournals.getSandboxOption("EnableStatRecording") then
            local recordedStats = journalData.stats or {}
            local matchCount = 0
            local totalStats = 0

            for _, stat in ipairs(BurdJournals.RECORDABLE_STATS) do
                if BurdJournals.isStatEnabled(stat.id) then
                    totalStats = totalStats + 1
                    local localizedName = BurdJournals.getStatName(stat)
                    local localizedDesc = BurdJournals.getStatDescription(stat)

                    if self:matchesSearch(localizedName) then
                        matchCount = matchCount + 1
                        local currentValue = BurdJournals.getStatValue(self.player, stat.id)
                        local recorded = recordedStats[stat.id]
                        local recordedValue = nil
                        if recorded then
                            recordedValue = type(recorded) == "table" and recorded.value or recorded
                            if type(recordedValue) ~= "number" then
                                recordedValue = nil
                            end
                        end
                        local canUpdate, _, _ = self:getStatUpdateForRecordData(journalData, stat.id)
                        local currentFormatted = BurdJournals.formatStatValue(stat.id, currentValue)
                        local recordedFormatted = recordedValue and BurdJournals.formatStatValue(stat.id, recordedValue) or nil

                        self:appendListEntry(entries, stat.id, {
                            isStat = true,
                            statId = stat.id,
                            statName = localizedName,
                            statCategory = stat.category,
                            statDescription = localizedDesc,
                            currentValue = currentValue,
                            currentFormatted = currentFormatted,
                            recordedValue = recordedValue,
                            recordedFormatted = recordedFormatted,
                            isRecorded = recordedValue ~= nil,
                            canRecord = hasWritingTool and canUpdate,
                            isText = stat.isText,
                        }, nil, localizedName, totalStats)
                    end
                end
            end

            if matchCount == 0 then
                if totalStats == 0 then
                    emptyEntry = {id = "empty", data = {isEmpty = true, text = "No stats enabled"}}
                else
                    emptyEntry = {id = "empty", data = {isEmpty = true, text = getText("UI_BurdJournals_NoSearchResults") or "No results found"}}
                end
            end
        else
            emptyEntry = {id = "empty", data = {isEmpty = true, text = "Stat recording is disabled"}}
        end

    elseif currentTab == "recipes" then
        if BurdJournals.isRecipeRecordingEnabled() and BurdJournals.areRecipesEnabledForJournal(journalData) then
            local recordedRecipes = journalData.recipes or {}
            local playerRecipes = BurdJournals.collectPlayerMagazineRecipes(self.player)
            local matchCount = 0
            local totalRecipes = 0

            for recipeName, recipeData in pairs(playerRecipes) do
                totalRecipes = totalRecipes + 1
                local displayName = BurdJournals.getRecipeDisplayName(recipeName)
                local magazineSource = (type(recipeData) == "table" and recipeData.source) or BurdJournals.getMagazineForRecipe(recipeName)
                local modSource = BurdJournals.getRecipeModId(recipeName, magazineSource)

                if self:matchesSearch(displayName) and self:passesFilter(modSource) then
                    matchCount = matchCount + 1
                    local recordedRecipeKey = BurdJournals.resolveRecipeKey and BurdJournals.resolveRecipeKey(recordedRecipes, recipeName) or recipeName
                    local isRecorded = recordedRecipeKey ~= nil and recordedRecipes[recordedRecipeKey] ~= nil

                    self:appendListEntry(entries, recipeName, {
                        isRecipe = true,
                        recipeName = recipeName,
                        displayName = displayName,
                        magazineSource = magazineSource,
                        magazineTexture = getMagazineTexture(magazineSource),
                        sourceText = buildRecipeSourceText(magazineSource, "Learned from magazine"),
                        isRecorded = isRecorded,
                        canRecord = hasWritingTool and not isRecorded,
                        modSource = modSource,
                    }, nil, displayName)
                end
            end

            if matchCount == 0 then
                if totalRecipes == 0 then
                    emptyEntry = {id = "empty", data = {isEmpty = true, text = getText("UI_BurdJournals_NoRecipesToRecord") or "No magazine recipes learned"}}
                else
                    emptyEntry = {id = "empty", data = {isEmpty = true, text = getText("UI_BurdJournals_NoSearchResults") or "No results found"}}
                end
            end
        else
            emptyEntry = {id = "empty", data = {isEmpty = true, text = "Recipe recording is disabled"}}
        end
    end

    self:setPaginatedListEntries(entries, emptyEntry)
end

function BurdJournals.UI.MainPanel.doDrawRecordItem(self, y, item, alt)
    local mainPanel = self.mainPanel
    if not mainPanel then return y + self.itemheight end

    local data = item.item or {}
    local x = 0

    local scrollBarWidth = 13
    local w = self:getWidth() - scrollBarWidth
    local h = tonumber(item.height) or self.itemheight
    if not shouldDrawListRow(self, y, h) then
        return y + h
    end
    local padding = 12

    local cardBg = {r=0.12, g=0.16, b=0.20}
    local cardBorder = {r=0.25, g=0.38, b=0.45}
    local accentColor = {r=0.3, g=0.55, b=0.65}

    if data.isHeader then
        self:drawRect(x, y + 2, w, h - 4, 0.4, 0.12, 0.18, 0.22)
        self:drawText(data.text or getText("UI_BurdJournals_YourSkills") or "YOUR SKILLS", x + padding, y + (h - 18) / 2, 0.7, 0.9, 1.0, 1, UIFont.Medium)
        if data.count then
            local countText = BurdJournals.formatText(getText("UI_BurdJournals_Recordable") or "(%d recordable)", data.count)
            local countWidth = getTextManager():MeasureStringX(UIFont.Small, countText)
            self:drawText(countText, w - padding - countWidth, y + (h - 14) / 2, 0.4, 0.6, 0.7, 1, UIFont.Small)
        end
        return y + h
    end

    if data.isEmpty then
        self:drawText(data.text or getText("UI_BurdJournals_NothingToRecord") or "Nothing to record", x + padding, y + (h - 14) / 2, 0.4, 0.5, 0.55, 1, UIFont.Small)
        return y + h
    end

    local cardMargin = 4
    local cardX = x + cardMargin
    local cardY = y + cardMargin
    local cardW = w - cardMargin * 2
    local cardH = h - cardMargin * 2

    local bgColor = cardBg
    local borderColor = cardBorder
    local accentGreen = {r=0.3, g=0.7, b=0.4}
    if data.isTrait then
        if data.isPositive == true then

            bgColor = {r=0.08, g=0.20, b=0.10}
            borderColor = {r=0.2, g=0.5, b=0.25}
            accentGreen = {r=0.3, g=0.8, b=0.35}
        elseif data.isPositive == false then

            bgColor = {r=0.22, g=0.08, b=0.08}
            borderColor = {r=0.5, g=0.2, b=0.2}
            accentGreen = {r=0.8, g=0.3, b=0.3}
        end

    end

    if data.isRecorded and not data.canRecord then
        self:drawRect(cardX, cardY, cardW, cardH, 0.4, 0.12, 0.15, 0.12)
    else
        self:drawRect(cardX, cardY, cardW, cardH, 0.7, bgColor.r, bgColor.g, bgColor.b)
    end

    self:drawRectBorder(cardX, cardY, cardW, cardH, 0.6, borderColor.r, borderColor.g, borderColor.b)

    if data.canRecord then
        self:drawRect(cardX, cardY, 4, cardH, 0.9, accentGreen.r, accentGreen.g, accentGreen.b)
    else
        self:drawRect(cardX, cardY, 4, cardH, 0.5, 0.3, 0.35, 0.3)
    end
    mainPanel:drawSelectedRowOutline(self, item, cardX, cardY, cardW, cardH)

    local textX = cardX + padding + 4
    local textColor = data.canRecord and {r=0.95, g=0.95, b=1.0} or {r=0.5, g=0.55, b=0.5}

    if data.isSkill then

        local recordingState = mainPanel.recordingState
        local isRecordingThis = recordingState and recordingState.active and not recordingState.isRecordAll
                               and recordingState.skillName == data.skillName

        local earnedXP = data.earnedXP or data.xp

        local displayName = data.displayName or data.skillName or "Unknown Skill"
        local displayLevel = data.displayLevel
        if displayLevel == nil then
            displayLevel = BurdJournals.getEarnedOnlyDisplayLevel(data.skillName, earnedXP, data.level)
        end
        local actualLevel = tonumber(data.level) or tonumber(displayLevel) or 0
        self:drawText(displayName .. " (Lv." .. tostring(actualLevel) .. ")", textX, cardY + 6, textColor.r, textColor.g, textColor.b, 1, UIFont.Small)

        if isRecordingThis then

            local progressFormat = getText("UI_BurdJournals_RecordingProgress") or "Recording... %d%%"
            local progressText = BurdJournals.normalizeProgressPercentLabel(BurdJournals.formatText(progressFormat, math.floor(recordingState.progress * 100)))
            self:drawText(progressText, textX, cardY + 24, 0.3, 0.8, 0.5, 1, UIFont.Small)

            local barX = textX + 100
            local barY = cardY + 27
            local barW = cardW - 130 - padding
            local barH = 10
            self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)
            self:drawRect(barX, barY, barW * recordingState.progress, barH, 0.9, 0.3, 0.7, 0.4)
            self:drawRectBorder(barX, barY, barW, barH, 0.7, 0.4, 0.8, 0.5)
        else

            local squaresX = textX
            local squaresY = cardY + 26
            local squareSize = 10
            local squareSpacing = 2

            local filledColor, emptyColor, progressColor
            if data.isRecorded and not data.canRecord then
                filledColor = {r=0.25, g=0.4, b=0.3}
                emptyColor = {r=0.1, g=0.1, b=0.1}
                progressColor = {r=0.2, g=0.3, b=0.25}
            else
                filledColor = {r=0.3, g=0.65, b=0.55}
                emptyColor = {r=0.12, g=0.12, b=0.12}
                progressColor = {r=0.2, g=0.4, b=0.35}
            end

            if (tonumber(data.baselineXP) or 0) > 0 then
                local totalLevel, totalProgress = BurdJournals.calculateLevelProgressWithOverride(
                    data.skillName,
                    tonumber(data.currentXP) or tonumber(data.baselineXP) or 0,
                    data.level
                )
                local baselineLevel, baselineProgress = BurdJournals.calculateLevelProgress(
                    data.skillName,
                    tonumber(data.baselineXP) or 0
                )
                BurdJournals.drawLevelSquaresWithBaseline(
                    self,
                    squaresX,
                    squaresY,
                    baselineLevel,
                    baselineProgress,
                    totalLevel,
                    totalProgress,
                    squareSize,
                    squareSpacing,
                    getBaselineSquareColor(filledColor, emptyColor),
                    filledColor,
                    emptyColor,
                    progressColor
                )
            else
                BurdJournals.drawEarnedOnlySkillSquares(self, squaresX, squaresY, data.skillName, earnedXP, squareSize, squareSpacing, {
                    filledColor = filledColor,
                    emptyColor = emptyColor,
                    progressColor = progressColor,
                })
            end

            local squaresWidth = 10 * squareSize + 9 * squareSpacing
            local xpText
            local xpColor
            local baselineXP = math.max(0, tonumber(data.baselineXP) or 0)
            local recordedSummary = BurdJournals.formatXPWithVhsBreakdown(
                data.recordedXP or 0,
                data.recordedRawXP or data.recordedXP or 0,
                data.recordedVhsExcludedXP or 0
            )

            if data.isRecorded and not data.canRecord then

                xpText = BurdJournals.formatText(getText("UI_BurdJournals_RecordedValue"), recordedSummary)
                xpColor = {r=0.4, g=0.5, b=0.45}
            elseif data.isRecorded and data.canRecord then

                if baselineXP > 0 then
                    xpText = BurdJournals.formatText(
                        getText("UI_BurdJournals_XPWithBaseline") or "%s XP (+%s starting)",
                        BurdJournals.formatXP(earnedXP),
                        BurdJournals.formatXP(baselineXP)
                    ) .. " (was " .. recordedSummary .. ")"
                else
                    xpText = BurdJournals.formatXP(earnedXP) .. " XP (was " .. recordedSummary .. ")"
                end
                xpColor = {r=0.5, g=0.8, b=0.6}
            else

                if baselineXP > 0 then
                    xpText = BurdJournals.formatText(
                        getText("UI_BurdJournals_XPWithBaseline") or "%s XP (+%s starting)",
                        BurdJournals.formatXP(earnedXP),
                        BurdJournals.formatXP(baselineXP)
                    )
                else
                    xpText = BurdJournals.formatXP(earnedXP) .. " XP"
                end
                xpColor = {r=0.5, g=0.75, b=0.7}
            end

            self:drawText(xpText, squaresX + squaresWidth + 8, squaresY, xpColor.r, xpColor.g, xpColor.b, 1, UIFont.Small)

            if mainPanel:isSelectedDrawItem(self, item) then
                local journalData = mainPanel.journal and BurdJournals.getJournalData and BurdJournals.getJournalData(mainPanel.journal) or nil
                local detailLines = BurdJournals.buildSkillDetailLines(data.skillName, data, journalData, mainPanel.player, "record")
                if type(detailLines) == "table" and #detailLines > 1 then
                    mainPanel:drawSkillDetailLines(
                        self,
                        data,
                        detailLines,
                        textX,
                        squaresY + 17,
                        math.max(40, cardX + cardW - textX - padding - 75),
                        UIFont.Small
                    )
                end
            end
        end

        local btnW = 55
        local btnH = 24

        local mainBtnX = cardX + cardW - btnW - 10
        local btnY = cardY + (cardH - btnH) / 2

        if data.canRecord and not isRecordingThis then

            local queuePosition = mainPanel:getRecordQueuePosition(data.skillName)
            local isQueued = queuePosition ~= nil

            local isInBatch = isInCurrentBatch(recordingState, "skill", data.skillName)

            if isQueued then

                self:drawRect(mainBtnX, btnY, btnW, btnH, 0.5, 0.3, 0.4, 0.5)
                self:drawRectBorder(mainBtnX, btnY, btnW, btnH, 0.6, 0.4, 0.5, 0.6)
                local btnText = "#" .. queuePosition
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, mainBtnX + (btnW - btnTextW) / 2, btnY + 4, 0.8, 0.9, 1, 1, UIFont.Small)
            elseif isInBatch then
                -- Item is part of current batch being processed
                self:drawRect(mainBtnX, btnY, btnW, btnH, 0.6, 0.45, 0.55, 0.45)
                self:drawRectBorder(mainBtnX, btnY, btnW, btnH, 0.8, 0.6, 0.7, 0.6)
                local btnText = getText("UI_BurdJournals_BtnBatching") or "BATCH"
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, mainBtnX + (btnW - btnTextW) / 2, btnY + 4, 0.95, 1, 0.95, 1, UIFont.Small)
            elseif recordingState and recordingState.active and not recordingState.isRecordAll then

                self:drawRect(mainBtnX, btnY, btnW, btnH, 0.6, 0.25, 0.35, 0.5)
                self:drawRectBorder(mainBtnX, btnY, btnW, btnH, 0.8, 0.4, 0.55, 0.7)
                local btnText = getText("UI_BurdJournals_BtnQueue")
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, mainBtnX + (btnW - btnTextW) / 2, btnY + 4, 0.9, 0.95, 1, 1, UIFont.Small)
            else

                self:drawRect(mainBtnX, btnY, btnW, btnH, 0.7, 0.2, 0.45, 0.35)
                self:drawRectBorder(mainBtnX, btnY, btnW, btnH, 0.8, 0.3, 0.6, 0.5)
                local btnText = getText("UI_BurdJournals_BtnRecord")
                mainPanel:drawPillLabelWithPrompt(self, mainBtnX, btnY, btnW, btnH, btnText, {r=1, g=1, b=1, a=1}, "A")
            end
        end
    end

    if data.isTrait then
        local recordingState = mainPanel.recordingState
        local isRecordingThis = recordingState and recordingState.active and not recordingState.isRecordAll
                               and recordingState.traitId == data.traitId

        local traitName = data.traitName or data.traitId or getText("UI_BurdJournals_UnknownTrait") or "Unknown Trait"
        local traitTextX = textX

        if data.traitTexture then
            local iconSize = 24
            local iconX = textX
            local iconY = cardY + (cardH - iconSize) / 2
            local iconAlpha = data.canRecord and 1.0 or 0.5
            self:drawTextureScaledAspect(data.traitTexture, iconX, iconY, iconSize, iconSize, iconAlpha, 1, 1, 1)
            traitTextX = textX + iconSize + 6
        end

        local traitColor
        if not data.canRecord then
            traitColor = {r=0.5, g=0.55, b=0.5}
        elseif data.isPositive == true then
            traitColor = {r=0.5, g=0.9, b=0.5}
        elseif data.isPositive == false then
            traitColor = {r=0.9, g=0.5, b=0.5}
        else
            traitColor = {r=0.8, g=0.9, b=1.0}
        end
        self:drawText(traitName, traitTextX, cardY + 6, traitColor.r, traitColor.g, traitColor.b, 1, UIFont.Small)

        local queuePosition = mainPanel:getRecordQueuePosition(data.traitId)
        local isQueued = queuePosition ~= nil

        if isRecordingThis then
            local progressFormat = getText("UI_BurdJournals_RecordingProgress") or "Recording... %d%%"
            local progressText = BurdJournals.normalizeProgressPercentLabel(BurdJournals.formatText(progressFormat, math.floor(recordingState.progress * 100)))
            self:drawText(progressText, traitTextX, cardY + 22, 0.3, 0.8, 0.5, 1, UIFont.Small)

            local barX = traitTextX + 100
            local barY = cardY + 25
            local barW = cardW - barX - 20
            local barH = 10

            self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)

            self:drawRect(barX, barY, barW * recordingState.progress, barH, 0.9, 0.2, 0.6, 0.5)

            self:drawRectBorder(barX, barY, barW, barH, 0.7, 0.3, 0.7, 0.6)
        elseif isQueued then
            local queuedText = BurdJournals.formatText(getText("UI_BurdJournals_QueuedNumber") or "Queued #%d", queuePosition)
            self:drawText(queuedText, traitTextX, cardY + 22, 0.6, 0.75, 0.9, 1, UIFont.Small)
        elseif data.isStartingTrait then

            self:drawText(getText("UI_BurdJournals_SpawnedWith") or "Spawned with", traitTextX, cardY + 22, 0.5, 0.45, 0.4, 1, UIFont.Small)
        elseif data.isRecorded then
            self:drawText(getText("UI_BurdJournals_StatusAlreadyRecorded") or "Already recorded", traitTextX, cardY + 22, 0.4, 0.5, 0.4, 1, UIFont.Small)
        else
            self:drawText(getText("UI_BurdJournals_YourTrait") or "Your trait", traitTextX, cardY + 22, 0.5, 0.7, 0.8, 1, UIFont.Small)
        end

        local btnW = 55
        local btnH = 24

        local mainBtnX = cardX + cardW - btnW - 10
        local btnY = cardY + (cardH - btnH) / 2

        if data.canRecord and not isRecordingThis then
            local isInBatch = isInCurrentBatch(recordingState, "trait", data.traitId)

            if isQueued then

                self:drawRect(mainBtnX, btnY, btnW, btnH, 0.5, 0.4, 0.35, 0.5)
                self:drawRectBorder(mainBtnX, btnY, btnW, btnH, 0.6, 0.5, 0.45, 0.6)
                local btnText = "#" .. queuePosition
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, mainBtnX + (btnW - btnTextW) / 2, btnY + 4, 0.9, 0.85, 0.7, 1, UIFont.Small)
            elseif isInBatch then
                -- Item is part of current batch being processed
                self:drawRect(mainBtnX, btnY, btnW, btnH, 0.6, 0.5, 0.45, 0.45)
                self:drawRectBorder(mainBtnX, btnY, btnW, btnH, 0.8, 0.65, 0.55, 0.6)
                local btnText = getText("UI_BurdJournals_BtnBatching") or "BATCH"
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, mainBtnX + (btnW - btnTextW) / 2, btnY + 4, 1, 0.95, 0.85, 1, UIFont.Small)
            elseif recordingState and recordingState.active and not recordingState.isRecordAll then

                self:drawRect(mainBtnX, btnY, btnW, btnH, 0.6, 0.4, 0.35, 0.25)
                self:drawRectBorder(mainBtnX, btnY, btnW, btnH, 0.8, 0.6, 0.5, 0.35)
                local btnText = getText("UI_BurdJournals_BtnQueue")
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, mainBtnX + (btnW - btnTextW) / 2, btnY + 4, 1, 0.95, 0.85, 1, UIFont.Small)
            else

                self:drawRect(mainBtnX, btnY, btnW, btnH, 0.7, 0.35, 0.45, 0.25)
                self:drawRectBorder(mainBtnX, btnY, btnW, btnH, 0.8, 0.5, 0.6, 0.4)
                local btnText = getText("UI_BurdJournals_BtnRecord")
                mainPanel:drawPillLabelWithPrompt(self, mainBtnX, btnY, btnW, btnH, btnText, {r=1, g=1, b=0.9, a=1}, "A")
            end
        end
    end

    if data.isStat then
        local recordingState = mainPanel.recordingState
        local isRecordingThis = recordingState and recordingState.active and not recordingState.isRecordAll
                               and recordingState.statId == data.statId

        local statName = data.statName or data.statId or "Unknown Stat"
        self:drawText(statName, textX, cardY + 6, textColor.r, textColor.g, textColor.b, 1, UIFont.Small)

        local queuePosition = mainPanel:getRecordQueuePosition(data.statId)
        local isQueued = queuePosition ~= nil

        if isRecordingThis then
            local progressFormat = getText("UI_BurdJournals_RecordingProgress") or "Recording... %d%%"
            local progressText = BurdJournals.normalizeProgressPercentLabel(BurdJournals.formatText(progressFormat, math.floor(recordingState.progress * 100)))
            self:drawText(progressText, textX, cardY + 22, 0.3, 0.8, 0.5, 1, UIFont.Small)

            local barX = textX + 100
            local barY = cardY + 25
            local barW = cardW - barX - 20
            local barH = 10

            self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)

            self:drawRect(barX, barY, barW * recordingState.progress, barH, 0.9, 0.2, 0.6, 0.5)

            self:drawRectBorder(barX, barY, barW, barH, 0.7, 0.3, 0.7, 0.6)
        elseif isQueued then
            local valueText = BurdJournals.formatText(getText("UI_BurdJournals_CurrentQueued") or "Current: %s - Queued #%d", data.currentFormatted or "?", queuePosition)
            self:drawText(valueText, textX, cardY + 22, 0.6, 0.75, 0.9, 1, UIFont.Small)
        elseif data.isRecorded then
            if data.canRecord then

                local valueText = BurdJournals.formatText(getText("UI_BurdJournals_NowWas") or "Now: %s (was %s)", data.currentFormatted or "?", data.recordedFormatted or "?")
                self:drawText(valueText, textX, cardY + 22, 0.5, 0.8, 0.5, 1, UIFont.Small)
            else

                local valueText = BurdJournals.formatText(getText("UI_BurdJournals_RecordedValue") or "Recorded: %s", data.recordedFormatted or "?")
                self:drawText(valueText, textX, cardY + 22, 0.4, 0.5, 0.4, 1, UIFont.Small)
            end
        else

            local valueText = BurdJournals.formatText(getText("UI_BurdJournals_CurrentValue") or "Current: %s", data.currentFormatted or "?")
            self:drawText(valueText, textX, cardY + 22, 0.5, 0.7, 0.8, 1, UIFont.Small)
        end

        if data.canRecord and not isRecordingThis then
            local btnW = 65
            local btnH = 24
            local btnX = cardX + cardW - btnW - 10
            local btnY = cardY + (cardH - btnH) / 2
            local isInBatch = isInCurrentBatch(recordingState, "stat", data.statId)

            if isQueued then

                self:drawRect(btnX, btnY, btnW, btnH, 0.5, 0.35, 0.45, 0.5)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.6, 0.45, 0.55, 0.6)
                local btnText = "#" .. queuePosition
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.8, 0.9, 1, 1, UIFont.Small)
            elseif isInBatch then
                -- Item is part of current batch being processed
                self:drawRect(btnX, btnY, btnW, btnH, 0.6, 0.4, 0.5, 0.45)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.55, 0.65, 0.6)
                local btnText = getText("UI_BurdJournals_BtnBatching") or "BATCH"
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.95, 1, 0.95, 1, UIFont.Small)
            elseif recordingState and recordingState.active and not recordingState.isRecordAll then

                self:drawRect(btnX, btnY, btnW, btnH, 0.6, 0.3, 0.4, 0.5)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.45, 0.55, 0.65)
                local btnText = getText("UI_BurdJournals_BtnQueue")
                local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.9, 0.95, 1, 1, UIFont.Small)
            else

                self:drawRect(btnX, btnY, btnW, btnH, 0.7, 0.2, 0.4, 0.45)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.35, 0.55, 0.6)
                local btnText = getText("UI_BurdJournals_BtnRecord")
                mainPanel:drawPillLabelWithPrompt(self, btnX, btnY, btnW, btnH, btnText, {r=1, g=1, b=1, a=1}, "A")
            end
        end
    end

    if data.isRecipe then
        local recordingState = mainPanel.recordingState
        local isRecordingThis = recordingState and recordingState.active and not recordingState.isRecordAll
                               and recordingState.recipeName == data.recipeName

        local displayName = data.displayName or data.recipeName or "Unknown Recipe"
        local recipeTextX = textX

        local magazineTexture = data.magazineTexture or getMagazineTexture(data.magazineSource)

        if magazineTexture then
            local iconSize = 24
            local iconX = textX
            local iconY = cardY + (cardH - iconSize) / 2
            local iconAlpha = data.canRecord and 1.0 or 0.5
            self:drawTextureScaledAspect(magazineTexture, iconX, iconY, iconSize, iconSize, iconAlpha, 1, 1, 1)
            recipeTextX = textX + iconSize + 6
        end

        self:drawText(displayName, recipeTextX, cardY + 6, textColor.r, textColor.g, textColor.b, 1, UIFont.Small)

        local queuePosition = mainPanel:getRecordQueuePosition(data.recipeName)
        local isQueued = queuePosition ~= nil

        if isRecordingThis then
            local progressFormat = getText("UI_BurdJournals_RecordingProgress") or "Recording... %d%%"
            local progressText = BurdJournals.normalizeProgressPercentLabel(BurdJournals.formatText(progressFormat, math.floor(recordingState.progress * 100)))
            self:drawText(progressText, recipeTextX, cardY + 22, 0.3, 0.8, 0.5, 1, UIFont.Small)

            local barX = recipeTextX + 100
            local barY = cardY + 25
            local barW = cardW - barX - 20
            local barH = 10

            self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)
            self:drawRect(barX, barY, barW * recordingState.progress, barH, 0.9, 0.5, 0.85, 0.9)
            self:drawRectBorder(barX, barY, barW, barH, 0.7, 0.5, 0.85, 0.9)
        elseif isQueued then
            local queuedText = BurdJournals.formatText(getText("UI_BurdJournals_QueuedNumber") or "Queued #%d", queuePosition)
            self:drawText(queuedText, recipeTextX, cardY + 22, 0.6, 0.75, 0.9, 1, UIFont.Small)
        elseif data.isRecorded then
            self:drawText(getText("UI_BurdJournals_StatusAlreadyRecorded") or "Already recorded", recipeTextX, cardY + 22, 0.4, 0.5, 0.4, 1, UIFont.Small)
        else

            local sourceText = data.sourceText or buildRecipeSourceText(data.magazineSource, "Learned from magazine")
            self:drawText(sourceText, recipeTextX, cardY + 22, 0.5, 0.7, 0.8, 1, UIFont.Small)
        end

        if data.canRecord and not isRecordingThis then
            local btnW = 65
            local btnH = 24
            local btnX = cardX + cardW - btnW - 10
            local btnY = cardY + (cardH - btnH) / 2
            local isInBatch = isInCurrentBatch(recordingState, "recipe", data.recipeName)

            if isQueued then

                self:drawRect(btnX, btnY, btnW, btnH, 0.5, 0.4, 0.7, 0.7)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.6, 0.5, 0.85, 0.9)
                local btnText = "#" .. queuePosition
                local btnTextW = mainPanel:getCachedSmallTextWidth(btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.9, 0.95, 1, 1, UIFont.Small)
            elseif isInBatch then
                -- Item is part of current batch being processed
                self:drawRect(btnX, btnY, btnW, btnH, 0.6, 0.45, 0.65, 0.6)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.6, 0.8, 0.8)
                local btnText = getText("UI_BurdJournals_BtnBatching") or "BATCH"
                local btnTextW = mainPanel:getCachedSmallTextWidth(btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 0.95, 1, 0.95, 1, UIFont.Small)
            elseif recordingState and recordingState.active and not recordingState.isRecordAll then

                self:drawRect(btnX, btnY, btnW, btnH, 0.6, 0.35, 0.55, 0.6)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.5, 0.75, 0.8)
                local btnText = getText("UI_BurdJournals_BtnQueue")
                local btnTextW = mainPanel:getCachedSmallTextWidth(btnText)
                self:drawText(btnText, btnX + (btnW - btnTextW) / 2, btnY + 4, 1, 1, 1, 1, UIFont.Small)
            else

                self:drawRect(btnX, btnY, btnW, btnH, 0.7, 0.3, 0.55, 0.6)
                self:drawRectBorder(btnX, btnY, btnW, btnH, 0.8, 0.5, 0.75, 0.8)
                local btnText = getText("UI_BurdJournals_BtnRecord")
                mainPanel:drawPillLabelWithPrompt(self, btnX, btnY, btnW, btnH, btnText, {r=1, g=1, b=1, a=1}, "A")
            end
        end
    end

    return y + h
end

function BurdJournals.UI.MainPanel:onRecordAll(skipNotesGuard)
    if self.currentTab == "notes" then
        if self.saveNotesIfDirty then
            self:saveNotesIfDirty("button", true)
        end
        return
    end
    if skipNotesGuard ~= true and self.confirmNotesBeforeAction and self:confirmNotesBeforeAction("recordAll") then
        return
    end
    if not self:startRecordingAll() then
        if self.recordingState and self.recordingState.active then
            self:showFeedback(getText("UI_BurdJournals_AlreadyRecording") or "Already recording...", {r=0.9, g=0.7, b=0.3})
        end
    end
end

function BurdJournals.UI.MainPanel:onRecordTab(skipNotesGuard, tabIdOverride)
    if self.currentTab == "notes" then
        if self.saveNotesIfDirty then
            self:saveNotesIfDirty("button", true)
        end
        return
    end
    if skipNotesGuard ~= true and self.confirmNotesBeforeAction and self:confirmNotesBeforeAction("recordTab", tabIdOverride or self.currentTab or "skills") then
        return
    end
    if not self:startRecordingTab(tabIdOverride or self.currentTab or "skills") then
        if self.recordingState and self.recordingState.active then
            self:showFeedback(getText("UI_BurdJournals_AlreadyRecording") or "Already recording...", {r=0.9, g=0.7, b=0.3})
        end
    end
end

function BurdJournals.UI.MainPanel:createViewUI()

    self:refreshPlayer()

    local padding = 16
    local y = 0
    local btnHeight = 32

    local journalData = BurdJournals.getJournalData(self.journal)

    self.isPlayerJournal = true
    self.isSetMode = true

    self.pendingClaims = self.pendingClaims or {skills = {}, traits = {}}
    self.sessionClaimedSkills = self.sessionClaimedSkills or {}
    self.sessionClaimedSkillTargets = self.sessionClaimedSkillTargets or {}
    self.sessionClaimedTraits = self.sessionClaimedTraits or {}

    local headerHeight = 52
    self.headerRightInset = 0
    local isRestored = BurdJournals.isRestoredJournal(self.journal)
    if isRestored then
        -- Restored journal (converted from worn/bloody blank)
        -- Dissolution controlled by sandbox option, but always displays as "Restored"
        self.headerColor = {r=0.35, g=0.28, b=0.12}
        self.headerAccent = {r=0.55, g=0.45, b=0.2}
        self.typeText = getText("UI_BurdJournals_RestoredJournalHeader")
        self.rarityText = nil
        self.flavorText = getText("UI_BurdJournals_RestoredFlavor")
    else
        -- Clean personal journal (crafted from fresh blank)
        self.headerColor = {r=0.12, g=0.25, b=0.35}
        self.headerAccent = {r=0.2, g=0.45, b=0.55}
        self.typeText = getText("UI_BurdJournals_PersonalJournalHeader")
        self.rarityText = nil
        self.flavorText = getText("UI_BurdJournals_PersonalFlavor")
    end
    self.headerIconTexture = getHeaderJournalIconTexture("view", self.journal, journalData, false)
    self.headerIconSize = 20
    self.headerHeight = headerHeight
    self:createHeaderRefreshButton(10, 15)
    y = headerHeight + 6

    local authorName = (BurdJournals.getJournalDisplayAuthor and BurdJournals.getJournalDisplayAuthor(journalData))
        or getText("UI_BurdJournals_Unknown")
    self.authorName = authorName
    self.authorBoxY = y
    self.authorBoxHeight = 44
    y = y + self.authorBoxHeight + 10

    local skillCount = 0
    local totalSkillCount = 0
    local traitCount = 0
    local totalTraitCount = 0
    local statCount = 0
    local totalStatCount = 0
    local totalXP = 0

    if journalData and journalData.skills then
        for skillName, skillData in pairs(journalData.skills) do
            if BurdJournals.isSkillVisibleForJournal(journalData, skillName) then
                totalSkillCount = totalSkillCount + 1

                local perk = BurdJournals.getPerkByName(skillName)
                local playerXP = 0
                if perk then
                    playerXP = BurdJournals.getPlayerSkillTotalXP and BurdJournals.getPlayerSkillTotalXP(self.player, perk, skillName) or self.player:getXp():getXP(perk)
                end
                local preview = BurdJournals.getClaimPreviewForSkill(
                    journalData,
                    self.player,
                    skillName,
                    BurdJournals.getNormalizedSkillClaimEntry(journalData, skillName, skillData.xp or 0),
                    0,
                    BurdJournals.getClaimSessionIdForPanel(self, false)
                )
                local claimTargetXP = BurdJournals.getClaimTargetXPForPlayer(journalData, self.player, skillName, preview.effectiveXP)
                if playerXP < claimTargetXP then
                    skillCount = skillCount + 1
                    totalXP = totalXP + (claimTargetXP - playerXP)
                end
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

            local currentValue = BurdJournals.getStatValue(self.player, statId)
            if currentValue < (statData.value or 0) then
                statCount = statCount + 1
            end
        end
    end
    if totalSkillCount <= 0 then
        totalSkillCount = getStoredJournalEntryCount(journalData, "skills")
    end
    if totalTraitCount <= 0 then
        totalTraitCount = getStoredJournalEntryCount(journalData, "traits")
        traitCount = math.max(traitCount, totalTraitCount)
    end
    if totalStatCount <= 0 then
        totalStatCount = getStoredJournalEntryCount(journalData, "stats")
        statCount = math.max(statCount, totalStatCount)
    end

    local recipeCount = 0
    local totalRecipeCount = 0
    if journalData and journalData.recipes then
        for recipeName, _ in pairs(journalData.recipes) do
            totalRecipeCount = totalRecipeCount + 1

            if not BurdJournals.playerKnowsRecipe(self.player, recipeName) then
                recipeCount = recipeCount + 1
            end
        end
    end
    if totalRecipeCount <= 0 then
        totalRecipeCount = getStoredJournalEntryCount(journalData, "recipes")
        recipeCount = math.max(recipeCount, totalRecipeCount)
    end

    self.skillCount = skillCount
    self.traitCount = traitCount
    self.statCount = statCount
    self.recipeCount = recipeCount
    self.totalXP = totalXP

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
    if shouldExposeLootNotesTab(journalData) then
        table.insert(tabs, {id = "notes", label = getText("UI_BurdJournals_TabNotes") or "Notes"})
    end

    local tabThemeColors = {
        active = {r=0.15, g=0.30, b=0.40},
        inactive = {r=0.08, g=0.15, b=0.20},
        accent = {r=0.25, g=0.50, b=0.60}
    }
    self.tabThemeColors = tabThemeColors

    if #tabs > 1 then
        y = self:createTabs(tabs, y, tabThemeColors)
    end

    self.filterBaseY = y
    y = self:createFilterTabBar(y, tabThemeColors)

    local maxItemCount = math.max(totalSkillCount, totalTraitCount, totalRecipeCount, totalStatCount)
    y = self:createSearchBar(y, tabThemeColors, maxItemCount)

    local footerHeight = 85
    local paginationHeight = BurdJournals.UI.LIST_PAGINATION_HEIGHT or 26
    local listHeight = self.height - y - footerHeight - paginationHeight - padding

    self.skillList = ISScrollingListBox:new(padding, y, self.width - padding * 2, listHeight)
    self.skillList:initialise()
    self.skillList:instantiate()
    self.skillList.drawBorder = false
    self.skillList.backgroundColor = {r=0, g=0, b=0, a=0}
    self.skillList:setFont(UIFont.Small, 2)
    self.skillList.itemheight = 52
    self.skillList.doDrawItem = BurdJournals.UI.MainPanel.doDrawViewItem
    self.skillList.mainPanel = self
    self.listBottomY = self.skillList:getY() + self.skillList:getHeight()

    self.skillList.onMouseUp = function(listbox, x, y)
        if listbox.vscroll then
            listbox.vscroll.scrolling = false
        end
        local row = listbox:rowAt(x, y)
        if row and row >= 1 and row <= #listbox.items then
            local item = listbox.items[row] and listbox.items[row].item
            if item and not item.isHeader and not item.isEmpty then

                local hasEraser = BurdJournals.hasEraser(listbox.mainPanel.player)
                local btnW = 55
                local btnGap = 4
                local margin = 10
                local rightmostBtnStart = listbox:getWidth() - btnW - margin

                local showClaimBtn = false
                if item.isSkill then
                    showClaimBtn = item.canClaim
                elseif item.isTrait then
                    showClaimBtn = not item.alreadyKnown and not item.isClaimed
                elseif item.isRecipe then
                    showClaimBtn = not item.alreadyKnown and not item.isClaimed
                elseif item.isStat then
                    showClaimBtn = item.canClaim and not item.alreadyClaimed
                end

                local claimBtnStart = rightmostBtnStart
                local eraseBtnStart = showClaimBtn and (rightmostBtnStart - btnW - btnGap) or rightmostBtnStart

                if x >= eraseBtnStart then
                    if hasEraser and x >= eraseBtnStart and x < eraseBtnStart + btnW then
                        listbox.mainPanel:performSecondaryListAction(item)
                    elseif showClaimBtn and x >= claimBtnStart then
                        listbox.mainPanel:performPrimaryListAction(item)
                    end
                end
            end
        end
        return true
    end
    self:wireSkillListJoypad()
    self:addChild(self.skillList)
    y = y + listHeight
    y = self:createPaginationControls(y, tabThemeColors)

    self.footerY = y + 4
    self.footerHeight = footerHeight

    self.feedbackLabel = ISLabel:new(padding, self.footerY + 4, 18, "", 0.7, 0.9, 0.7, 1, UIFont.Small, true)
    self:addChild(self.feedbackLabel)
    self.feedbackLabel:setVisible(false)
    self.feedbackTicks = 0

    local tabName = self:getTabDisplayName(self.currentTab or "skills")
    local claimTabText = BurdJournals.formatText(getText("UI_BurdJournals_BtnClaimTab") or "Claim %s", tabName)
    local claimAllText = getText("UI_BurdJournals_BtnClaimAll") or "Claim All"
    local closeText = getText("UI_BurdJournals_BtnClose") or "Close"

    local allTabNames = {
        getText("UI_BurdJournals_TabSkills") or "Skills",
        getText("UI_BurdJournals_TabTraits") or "Traits",
        getText("UI_BurdJournals_TabForget") or "Forget",
        getText("UI_BurdJournals_TabRecipes") or "Recipes",
        getText("UI_BurdJournals_TabStats") or "Stats",
        getText("UI_BurdJournals_TabNotes") or "Notes"
    }
    local btnPrefix = getText("UI_BurdJournals_BtnClaimTab") or "Claim %s"
    local maxClaimTabW = 90
    for _, name in ipairs(allTabNames) do
        local text = BurdJournals.formatText(btnPrefix, name)
        local w = getTextManager():MeasureStringX(UIFont.Small, text) + 20
        maxClaimTabW = math.max(maxClaimTabW, w)
    end
    local claimAllW = getTextManager():MeasureStringX(UIFont.Small, claimAllText) + 20
    local closeW = getTextManager():MeasureStringX(UIFont.Small, closeText) + 20
    local btnWidth = math.max(90, maxClaimTabW, claimAllW, closeW)

    local btnSpacing = 12
    local totalBtnWidth = btnWidth * 3 + btnSpacing * 2
    local btnStartX = (self.width - totalBtnWidth) / 2
    local btnY = self.footerY + 32

    self.absorbTabBtn = ISButton:new(btnStartX, btnY, btnWidth, btnHeight, claimTabText, self, BurdJournals.UI.MainPanel.onClaimTab)
    self.absorbTabBtn:initialise()
    self.absorbTabBtn:instantiate()
    self.absorbTabBtn.borderColor = {r=0.3, g=0.5, b=0.6, a=1}
    self.absorbTabBtn.backgroundColor = {r=0.12, g=0.22, b=0.28, a=0.8}
    self.absorbTabBtn.textColor = {r=0.9, g=0.95, b=1, a=1}
    self:addChild(self.absorbTabBtn)

    self.absorbAllBtn = ISButton:new(btnStartX + btnWidth + btnSpacing, btnY, btnWidth, btnHeight, claimAllText, self, BurdJournals.UI.MainPanel.onClaimAll)
    self.absorbAllBtn:initialise()
    self.absorbAllBtn:instantiate()
    self.absorbAllBtn.borderColor = {r=0.3, g=0.5, b=0.6, a=1}
    self.absorbAllBtn.backgroundColor = {r=0.15, g=0.28, b=0.35, a=0.8}
    self.absorbAllBtn.textColor = {r=1, g=1, b=1, a=1}
    self:addChild(self.absorbAllBtn)

    self.closeBottomBtn = ISButton:new(btnStartX + (btnWidth + btnSpacing) * 2, btnY, btnWidth, btnHeight, closeText, self, BurdJournals.UI.MainPanel.onClose)
    self.closeBottomBtn:initialise()
    self.closeBottomBtn:instantiate()
    self.closeBottomBtn.borderColor = {r=0.4, g=0.35, b=0.3, a=1}
    self.closeBottomBtn.backgroundColor = {r=0.15, g=0.13, b=0.12, a=0.8}
    self.closeBottomBtn.textColor = {r=0.9, g=0.85, b=0.8, a=1}
    self:addChild(self.closeBottomBtn)

    self:populateViewList(journalData)
    self:rebuildJoypadRows()
end

function BurdJournals.UI.MainPanel:isClaimActionActive(entryType, entryName)
    local state = self.learningState
    if type(state) ~= "table" or not state.active then
        return false
    end
    if state.isAbsorbAll then
        return true
    end

    if entryType == "skill" then
        return state.skillName == entryName
    elseif entryType == "trait" then
        return state.traitId == entryName
    elseif entryType == "recipe" then
        return state.recipeName == entryName
    elseif entryType == "stat" then
        return state.statId == entryName
    end

    return false
end

function BurdJournals.UI.MainPanel:populateViewList(overrideData)
    local authoritativeData = overrideData or self:resolvePendingRecordJournalDataForRefresh()
    local hasAuthoritativeData = type(authoritativeData) == "table"
    local journalData = authoritativeData or BurdJournals.getJournalData(self.journal)
    local liveSnapshot = getHydratedSnapshotForEmptyLiveJournal(self.journal, journalData)
    if liveSnapshot then
        self.pendingRecordJournalData = liveSnapshot
        journalData = liveSnapshot
        hasAuthoritativeData = true
    end
    if shouldHydrateOffloadedJournalOnOpen(journalData)
        and BurdJournals.Client
        and BurdJournals.Client.getHydratedJournalSnapshot
        and self.journal
    then
        local snapshot = BurdJournals.Client.getHydratedJournalSnapshot(self.journal,
            BurdJournals.getJournalIdentityUUID and BurdJournals.getJournalIdentityUUID(journalData) or nil)
        if journalDataHasRecordedEntries(snapshot) then
            self.pendingRecordJournalData = snapshot
            journalData = snapshot
            hasAuthoritativeData = true
        end
    end
    local currentTab = self.currentTab or "skills"
    local entries = {}
    local emptyEntry = nil
    if currentTab == "notes" then
        if self.refreshNotesTab then
            self:refreshNotesTab(journalData)
        end
        return
    elseif self.hideNotesControls then
        self:hideNotesControls()
    end
    if shouldWaitForAuthoritativePlayerJournalData(journalData, hasAuthoritativeData, self.journal)
        or (shouldHydrateOffloadedJournalOnOpen(journalData)
            and not journalDataHasRecordedEntries(journalData)
            and isJournalAuthorityRequestPending(self.journal, journalData))
    then
        emptyEntry = {
            id = "entry_store_hydrating",
            data = {
                isEmpty = true,
                text = BurdJournals.safeGetText("UI_BurdJournals_JournalSyncing", "Syncing journal...")
            }
        }
        self:setPaginatedListEntries(entries, emptyEntry)
        return
    end
    local allowedSkills = BurdJournals.getAllowedSkills and BurdJournals.getAllowedSkills() or {}
    local skillSortIndex = {}
    for index, skillName in ipairs(allowedSkills) do
        skillSortIndex[skillName] = index
    end
    local statSortIndex = {}
    for index, stat in ipairs(BurdJournals.RECORDABLE_STATS or {}) do
        statSortIndex[stat.id] = index
    end

    self.pendingClaims = self.pendingClaims or {}
    self.pendingClaims.skills = self.pendingClaims.skills or {}
    self.pendingClaims.traits = self.pendingClaims.traits or {}
    self.pendingClaims.recipes = self.pendingClaims.recipes or {}
    self.pendingClaims.stats = self.pendingClaims.stats or {}

    if currentTab == "skills" then
        if journalData and journalData.skills then
            local hasSkills = false
            local matchCount = 0
            for skillName, skillData in pairs(journalData.skills) do
                if BurdJournals.isSkillVisibleForJournal(journalData, skillName) then
                    hasSkills = true
                    local displayName = BurdJournals.getPerkDisplayName(skillName)
                    local modSource = BurdJournals.getSkillModId(skillName)

                    if self:matchesSearch(displayName) and self:passesFilter(modSource) then
                        matchCount = matchCount + 1
                        local perk = BurdJournals.getPerkByName(skillName)
                        local playerXP = 0
                        local playerLevel = 0
                        if perk then
                            playerXP = BurdJournals.getPlayerSkillTotalXP and BurdJournals.getPlayerSkillTotalXP(self.player, perk, skillName) or self.player:getXp():getXP(perk)
                            playerLevel = self.player:getPerkLevel(perk)
                        end

                        local recordedXP, recordedLevel = BurdJournals.getNormalizedSkillClaimEntry(journalData, skillName, skillData.xp or 0)
                        local _, recordedRawXP, recordedVhsExcludedXP = BurdJournals.getSkillVhsBreakdown(skillData, recordedXP)
                        local preview = BurdJournals.getClaimPreviewForSkill(journalData, self.player, skillName, recordedXP, 0, BurdJournals.getClaimSessionIdForPanel(self, false))
                        local effectiveClaimXP = preview.effectiveXP
                        local claimTargetXP = BurdJournals.getClaimTargetXPForPlayer(journalData, self.player, skillName, effectiveClaimXP)
                        local isPassiveSkill = (BurdJournals.isPassiveSkill and BurdJournals.isPassiveSkill(skillName))
                            or (skillName == "Fitness" or skillName == "Strength")
                        if recordedLevel == 0 and recordedXP > 0 and isPassiveSkill and BurdJournals.shouldAddPassiveBaselineForDisplay(journalData, self.player) then
                            local baselineXP = BurdJournals.getSkillBaseline and BurdJournals.getSkillBaseline(self.player, skillName) or 0
                            if baselineXP > 0 and BurdJournals.getSkillLevelFromXP then
                                recordedLevel = BurdJournals.getSkillLevelFromXP(math.max(0, tonumber(baselineXP) or 0) + recordedXP, skillName)
                            end
                        end
                        if recordedLevel == 0 and recordedXP > 0 and BurdJournals.getSkillLevelFromXP then
                            local xpForLevelCalc = BurdJournals.getXPWithBaselineForDisplay(skillName, recordedXP, journalData, self.player)
                            recordedLevel = BurdJournals.getSkillLevelFromXP(xpForLevelCalc, skillName)
                        end

                        local isPending = self.pendingClaims.skills[skillName]
                        local isClaimed = BurdJournals.hasCharacterClaimedSkill(journalData, self.player, skillName)
                        local claimedThisSession = self.sessionClaimedSkills and self.sessionClaimedSkills[skillName]
                        local claimedSessionTargetXP = self.sessionClaimedSkillTargets and tonumber(self.sessionClaimedSkillTargets[skillName])
                        local claimActionActive = self:isClaimActionActive("skill", skillName)
                        if claimedThisSession and claimedSessionTargetXP and claimTargetXP > claimedSessionTargetXP + 0.001 then
                            self.sessionClaimedSkills[skillName] = nil
                            self.sessionClaimedSkillTargets[skillName] = nil
                            claimedThisSession = false
                            claimedSessionTargetXP = nil
                        end
                        local alreadyAtLevel = playerXP >= claimTargetXP

                        if isPending and (alreadyAtLevel or isClaimed or not claimActionActive) then
                            self.pendingClaims.skills[skillName] = nil
                            isPending = false
                        end

                        if claimedThisSession and alreadyAtLevel then
                            self.sessionClaimedSkills[skillName] = nil
                            if self.sessionClaimedSkillTargets then
                                self.sessionClaimedSkillTargets[skillName] = nil
                            end
                            claimedThisSession = false
                            claimedSessionTargetXP = nil
                        end

                        isClaimed = isClaimed or claimedThisSession
                        local canClaim = not alreadyAtLevel and not isPending and not isClaimed
                        local skillTooltip = BurdJournals.buildSkillVhsTooltip({
                            xp = recordedXP,
                            rawXP = recordedRawXP,
                            vhsExcludedXP = recordedVhsExcludedXP,
                            vhsMediaLines = type(skillData) == "table" and skillData.vhsMediaLines or nil
                        }, effectiveClaimXP, preview.percent)

                        self:appendListEntry(entries, skillName, {
                            isSkill = true,
                            skillName = skillName,
                            displayName = displayName,
                            xp = recordedXP,
                            rawXP = recordedRawXP,
                            vhsExcludedXP = recordedVhsExcludedXP,
                            vhsMediaLines = type(skillData) == "table" and skillData.vhsMediaLines or nil,
                            effectiveXP = effectiveClaimXP,
                            claimMultiplier = preview.multiplier,
                            claimPercent = preview.percent,
                            claimReadCount = preview.readCount,
                            level = recordedLevel,
                            playerXP = playerXP,
                            playerLevel = playerLevel,
                            canClaim = canClaim,
                            isClaimed = isClaimed,
                            isPending = isPending,
                            alreadyAtLevel = alreadyAtLevel,
                            modSource = modSource,
                        }, skillTooltip, displayName, skillSortIndex[skillName])
                    end
                end
            end

            if not hasSkills then
                emptyEntry = {id = "empty", data = {isEmpty = true, text = getText("UI_BurdJournals_NoSkillsRecorded")}}
            elseif matchCount == 0 then
                emptyEntry = {id = "no_results", data = {isEmpty = true, text = getText("UI_BurdJournals_NoSearchResults") or "No results found"}}
            end
        else
            emptyEntry = {id = "empty", data = {isEmpty = true, text = getText("UI_BurdJournals_NoSkillsRecorded")}}
        end

    elseif currentTab == "traits" then
        if journalData and journalData.traits and BurdJournals.countTable(journalData.traits) > 0 then
            local hasTraits = false
            local matchCount = 0
            for traitId, traitData in pairs(journalData.traits) do
                hasTraits = true
                local traitName = safeGetTraitName(traitId)
                local modSource = BurdJournals.getTraitModId(traitId)

                if self:matchesSearch(traitName) and self:passesFilter(modSource) then
                    matchCount = matchCount + 1
                    local traitTexture = getTraitTexture(traitId)
                    local normalizedTraitId = BurdJournals.normalizeTraitId and BurdJournals.normalizeTraitId(traitId) or traitId
                    local traitSessionKey = string.lower(tostring(normalizedTraitId or traitId))
                    local alreadyKnownActual = BurdJournals.playerHasTrait(self.player, traitId)
                    local claimedThisSession = self.sessionClaimedTraits and (self.sessionClaimedTraits[traitId] or self.sessionClaimedTraits[traitSessionKey])
                    local claimActionActive = self:isClaimActionActive("trait", traitId)
                    local authoritativelyClaimed = BurdJournals.hasCharacterClaimedTrait(journalData, self.player, traitId)
                    if claimedThisSession and authoritativelyClaimed and self.sessionClaimedTraits then
                        self.sessionClaimedTraits[traitId] = nil
                        self.sessionClaimedTraits[traitSessionKey] = nil
                        claimedThisSession = false
                    end
                    local alreadyKnown = alreadyKnownActual or claimedThisSession
                    local isClaimed = authoritativelyClaimed or claimedThisSession
                    local isPending = self.pendingClaims.traits[traitId] or self.pendingClaims.traits[traitSessionKey]
                    local isPositive = isTraitPositive(traitId)

                    if isPending and (isClaimed or alreadyKnown or not claimActionActive) then
                        self.pendingClaims.traits[traitId] = nil
                        self.pendingClaims.traits[traitSessionKey] = nil
                        isPending = false
                    end

                    self:appendListEntry(entries, traitId, {
                        isTrait = true,
                        traitId = traitId,
                        traitName = traitName,
                        traitTexture = traitTexture,
                        alreadyKnown = alreadyKnown,
                        isClaimed = isClaimed,
                        isPending = isPending,
                        isPositive = isPositive,
                        modSource = modSource,
                    }, nil, traitName)
                end
            end

            if not hasTraits then
                emptyEntry = {id = "empty", data = {isEmpty = true, text = "No traits recorded"}}
            elseif matchCount == 0 then
                emptyEntry = {id = "no_results", data = {isEmpty = true, text = getText("UI_BurdJournals_NoSearchResults") or "No results found"}}
            end
        else
            emptyEntry = {id = "empty", data = {isEmpty = true, text = "No traits recorded"}}
        end

    elseif currentTab == "recipes" then
        if journalData and journalData.recipes and BurdJournals.countTable(journalData.recipes) > 0 then
            local hasRecipes = false
            local matchCount = 0
            for recipeName, recipeData in pairs(journalData.recipes) do
                if BurdJournals.isRecipeEnabledForJournal(journalData, recipeName) then
                    hasRecipes = true
                    local displayName = BurdJournals.getRecipeDisplayName(recipeName)
                    local magazineSource = (type(recipeData) == "table" and recipeData.source) or BurdJournals.getMagazineForRecipe(recipeName)
                    local modSource = BurdJournals.getRecipeModId(recipeName, magazineSource)

                    if self:matchesSearch(displayName) and self:passesFilter(modSource) then
                        matchCount = matchCount + 1
                        local claimedThisSession = self.sessionClaimedRecipes and self.sessionClaimedRecipes[recipeName] == true
                        local alreadyKnownActual = BurdJournals.playerKnowsRecipe(self.player, recipeName)
                        local claimActionActive = self:isClaimActionActive("recipe", recipeName)
                        if claimedThisSession and alreadyKnownActual and self.sessionClaimedRecipes then
                            self.sessionClaimedRecipes[recipeName] = nil
                            claimedThisSession = false
                        end
                        local alreadyKnown = alreadyKnownActual or claimedThisSession
                        local isClaimed = BurdJournals.hasCharacterClaimedRecipe(journalData, self.player, recipeName) or claimedThisSession
                        local isPending = self.pendingClaims.recipes and self.pendingClaims.recipes[recipeName]

                        if isPending and (isClaimed or alreadyKnown or not claimActionActive) then
                            if self.pendingClaims.recipes then
                                self.pendingClaims.recipes[recipeName] = nil
                            end
                            isPending = false
                        end

                        self:appendListEntry(entries, recipeName, {
                            isRecipe = true,
                            recipeName = recipeName,
                            displayName = displayName,
                            magazineSource = magazineSource,
                            magazineTexture = getMagazineTexture(magazineSource),
                            sourceText = buildRecipeSourceText(magazineSource, getText("UI_BurdJournals_RecordedRecipe") or "Recorded recipe"),
                            alreadyKnown = alreadyKnown,
                            isClaimed = isClaimed,
                            isPending = isPending,
                            modSource = modSource,
                        }, nil, displayName)
                    end
                end
            end

            if not hasRecipes then
                emptyEntry = {id = "empty", data = {isEmpty = true, text = getText("UI_BurdJournals_NoRecipesRecorded")}}
            elseif matchCount == 0 then
                emptyEntry = {id = "no_results", data = {isEmpty = true, text = getText("UI_BurdJournals_NoSearchResults") or "No results found"}}
            end
        else
            emptyEntry = {id = "empty", data = {isEmpty = true, text = getText("UI_BurdJournals_NoRecipesRecorded")}}
        end

    elseif currentTab == "stats" then
        if journalData and journalData.stats and BurdJournals.countTable(journalData.stats) > 0 then
            local hasStats = false
            local matchCount = 0
            for statId, statData in pairs(journalData.stats) do
                hasStats = true
                local stat = BurdJournals.getStatById(statId)
                local statName = stat and BurdJournals.getStatName(stat) or statId

                if self:matchesSearch(statName) then
                    matchCount = matchCount + 1
                    local currentValue = BurdJournals.getStatValue(self.player, statId)
                    local recordedValue = type(statData) == "table" and statData.value or statData
                    if type(recordedValue) ~= "number" then
                        recordedValue = 0
                    end
                    local currentFormatted = BurdJournals.formatStatValue(statId, currentValue)
                    local recordedFormatted = BurdJournals.formatStatValue(statId, recordedValue)
                    local canClaim, recVal, curVal, claimReason = false, nil, nil, nil
                    if BurdJournals.canAbsorbStat then
                        canClaim, recVal, curVal, claimReason = BurdJournals.canAbsorbStat(journalData, self.player, statId)
                    end
                    local claimedThisSession = self.sessionClaimedStats and self.sessionClaimedStats[statId] == true
                    local claimActionActive = self:isClaimActionActive("stat", statId)
                    if claimedThisSession then
                        canClaim = false
                        claimReason = "already_claimed"
                    end
                    local isAbsorbable = BurdJournals.ABSORBABLE_STATS and BurdJournals.ABSORBABLE_STATS[statId] ~= nil

                    self:appendListEntry(entries, statId, {
                        isStat = true,
                        statId = statId,
                        statName = statName,
                        currentValue = currentValue,
                        recordedValue = recordedValue,
                        currentFormatted = currentFormatted,
                        recordedFormatted = recordedFormatted,
                        canClaim = canClaim,
                        isAbsorbable = isAbsorbable,
                        claimReason = claimReason,
                    }, nil, statName, statSortIndex[statId])
                end
            end

            if not hasStats then
                emptyEntry = {id = "empty", data = {isEmpty = true, text = getText("UI_BurdJournals_NoStatsRecorded") or "No stats recorded"}}
            elseif matchCount == 0 then
                emptyEntry = {id = "no_results", data = {isEmpty = true, text = getText("UI_BurdJournals_NoSearchResults") or "No results found"}}
            end
        else
            emptyEntry = {id = "empty", data = {isEmpty = true, text = getText("UI_BurdJournals_NoStatsRecorded") or "No stats recorded"}}
        end
    end

    self:setPaginatedListEntries(entries, emptyEntry)
end

-- Helper function for drawing skill items in view mode (extracted to reduce local count)
local function doDrawViewSkillItem(self, mainPanel, item, data, textX, textColor, cardX, cardY, cardW, cardH, padding)
    local learningState = mainPanel.learningState
    local viewJournalData = (mainPanel.journal and BurdJournals.getJournalData and BurdJournals.getJournalData(mainPanel.journal)) or nil
    local isLearningThis = learningState and learningState.active and not learningState.isAbsorbAll
                          and learningState.skillName == data.skillName
    local erasingState = mainPanel.erasingState
    local isErasingThis = erasingState and erasingState.active
                          and erasingState.entryType == "skill" and erasingState.entryName == data.skillName
    local displayName = data.displayName or data.skillName or "Unknown Skill"
    local displayLevel = data.displayLevel
    if displayLevel == nil then
        local earnedXP = data.effectiveXP or data.xp or 0
        displayLevel = BurdJournals.getEarnedOnlyDisplayLevel(data.skillName, earnedXP, data.level)
    end
    self:drawText(displayName .. " (Lv." .. tostring(displayLevel or 0) .. ")", textX, cardY + 6, textColor.r, textColor.g, textColor.b, 1, UIFont.Small)
    local queuePosition = mainPanel:getQueuePosition(data.skillName)
    local isQueued = queuePosition ~= nil

    if isErasingThis then
        local progressFormat = getText("UI_BurdJournals_ErasingProgress") or "Erasing... %d%%"
        local progressText = BurdJournals.normalizeProgressPercentLabel(BurdJournals.formatText(progressFormat, math.floor((erasingState.progress or 0) * 100)))
        self:drawText(progressText, textX, cardY + 24, 0.9, 0.5, 0.5, 1, UIFont.Small)
        local barX, barY, barW, barH = textX + 90, cardY + 27, cardW - 120 - padding, 10
        self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)
        self:drawRect(barX, barY, barW * (erasingState.progress or 0), barH, 0.9, 0.7, 0.3, 0.3)
        self:drawRectBorder(barX, barY, barW, barH, 0.7, 0.6, 0.3, 0.3)
    elseif isLearningThis then
        local progressFormat = getText("UI_BurdJournals_ReadingProgress") or "Reading... %d%%"
        local progressText = BurdJournals.normalizeProgressPercentLabel(BurdJournals.formatText(progressFormat, math.floor(learningState.progress * 100)))
        self:drawText(progressText, textX, cardY + 24, 0.3, 0.7, 0.9, 1, UIFont.Small)
        local barX, barY, barW, barH = textX + 90, cardY + 27, cardW - 120 - padding, 10
        self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)
        self:drawRect(barX, barY, barW * learningState.progress, barH, 0.9, 0.3, 0.6, 0.8)
        self:drawRectBorder(barX, barY, barW, barH, 0.7, 0.4, 0.6, 0.8)
    elseif isQueued then
        local squaresX, squaresY, squareSize, squareSpacing = textX, cardY + 26, 10, 2
        local displayXP = data.effectiveXP or data.xp or 0
        BurdJournals.drawEarnedOnlySkillSquares(self, squaresX, squaresY, data.skillName, displayXP, squareSize, squareSpacing, {
            filledColor = {r=0.4, g=0.5, b=0.6},
            emptyColor = {r=0.12, g=0.12, b=0.12},
            progressColor = {r=0.25, g=0.3, b=0.4}
        })
        local squaresWidth = 10 * squareSize + 9 * squareSpacing
        local queuedText = BurdJournals.formatText(getText("UI_BurdJournals_QueuedNumber") or "Queued #%d", queuePosition)
        local sourceXP = math.max(0, tonumber(data.xp) or displayXP)
        local _, rawSourceXP, vhsExcludedXP = BurdJournals.getSkillVhsBreakdown(data, sourceXP)
        local xpText = queuedText .. "  "
        xpText = xpText .. BurdJournals.formatXP(displayXP) .. " XP"
        if data.claimPercent and data.claimPercent < 100 and sourceXP > 0 then
            local reducedXP = math.max(0, sourceXP - displayXP)
            xpText = queuedText .. "  " .. BurdJournals.formatXP(displayXP) .. "/" .. BurdJournals.formatXP(sourceXP) .. " XP (" .. tostring(data.claimPercent) .. "%, -" .. BurdJournals.formatXP(reducedXP) .. ")"
            if vhsExcludedXP > 0 and rawSourceXP > sourceXP then
                xpText = xpText .. " | VHS -" .. BurdJournals.formatXP(vhsExcludedXP)
            end
        else
            xpText = queuedText .. "  " .. BurdJournals.formatXPWithVhsBreakdown(displayXP, rawSourceXP, vhsExcludedXP)
        end
        self:drawText(xpText, squaresX + squaresWidth + 8, squaresY, 0.6, 0.75, 0.9, 1, UIFont.Small)
    elseif data.canClaim then
        local squaresX, squaresY, squareSize, squareSpacing = textX, cardY + 26, 10, 2
        local displayXP = data.effectiveXP or data.xp or 0
        BurdJournals.drawEarnedOnlySkillSquares(self, squaresX, squaresY, data.skillName, displayXP, squareSize, squareSpacing, {
            filledColor = {r=0.3, g=0.55, b=0.65},
            emptyColor = {r=0.12, g=0.12, b=0.12},
            progressColor = {r=0.2, g=0.35, b=0.4}
        })
        local squaresWidth = 10 * squareSize + 9 * squareSpacing
        local sourceXP = math.max(0, tonumber(data.xp) or displayXP)
        local _, rawSourceXP, vhsExcludedXP = BurdJournals.getSkillVhsBreakdown(data, sourceXP)
        local xpText = BurdJournals.formatXP(displayXP) .. " XP"
        if vhsExcludedXP > 0 and rawSourceXP > sourceXP then
            xpText = BurdJournals.formatXPWithVhsBreakdown(displayXP, rawSourceXP, vhsExcludedXP)
        end
        if data.claimPercent and data.claimPercent < 100 and sourceXP > 0 then
            local reducedXP = math.max(0, sourceXP - displayXP)
            xpText = BurdJournals.formatXP(displayXP) .. "/" .. BurdJournals.formatXP(sourceXP) .. " XP (" .. tostring(data.claimPercent) .. "%, -" .. BurdJournals.formatXP(reducedXP) .. ")"
            if vhsExcludedXP > 0 and rawSourceXP > sourceXP then
                xpText = xpText .. " | VHS -" .. BurdJournals.formatXP(vhsExcludedXP)
            end
        end
        self:drawText(xpText, squaresX + squaresWidth + 8, squaresY, 0.5, 0.75, 0.7, 1, UIFont.Small)
    else
        local squaresX, squaresY, squareSize, squareSpacing = textX, cardY + 26, 10, 2
        local displayXP = data.effectiveXP or data.xp or 0
        BurdJournals.drawEarnedOnlySkillSquares(self, squaresX, squaresY, data.skillName, displayXP, squareSize, squareSpacing, {
            filledColor = {r=0.25, g=0.3, b=0.3},
            emptyColor = {r=0.1, g=0.1, b=0.1},
            progressColor = {r=0.18, g=0.22, b=0.22}
        })
        local squaresWidth = 10 * squareSize + 9 * squareSpacing
        -- Show appropriate status: "Already at this level" if they have sufficient XP
        local statusText = data.alreadyAtLevel 
            and (getText("UI_BurdJournals_StatusAlreadyAtLevel") or "Already at this level")
            or (getText("UI_BurdJournals_StatusAlreadyClaimed") or "Already claimed")
        self:drawText(statusText, squaresX + squaresWidth + 8, squaresY, 0.4, 0.45, 0.45, 1, UIFont.Small)
    end

    if mainPanel:isSelectedDrawItem(self, item) then
        local detailLines = BurdJournals.buildSkillDetailLines(data.skillName, data, viewJournalData, mainPanel.player, "view")
        if type(detailLines) == "table" and #detailLines > 1 then
            mainPanel:drawSkillDetailLines(
                self,
                data,
                detailLines,
                textX,
                cardY + 41,
                math.max(40, cardX + cardW - textX - padding - 75),
                UIFont.Small
            )
        end
    end

    local btnW, btnH, btnGap = 55, 24, 4
    local hasEraser = BurdJournals.hasEraser(mainPanel.player)
    local rightmostBtnX = cardX + cardW - btnW - 10
    local btnY = cardY + (cardH - btnH) / 2
    local showClaimBtn = data.canClaim and not isLearningThis
    local eraseBtnX = showClaimBtn and (rightmostBtnX - btnW - btnGap) or rightmostBtnX

    -- Check if this item is in erase queue
    local eraseQueuePos = mainPanel:getEraseQueuePosition(data.skillName)
    local isEraseQueued = eraseQueuePos ~= nil

    if hasEraser and not isErasingThis then
        if isEraseQueued then
            -- Show queued state with position number
            self:drawRect(eraseBtnX, btnY, btnW, btnH, 0.5, 0.4, 0.25, 0.25)
            self:drawRectBorder(eraseBtnX, btnY, btnW, btnH, 0.6, 0.6, 0.35, 0.35)
            local queueText = "#" .. eraseQueuePos
            local queueTextW = getTextManager():MeasureStringX(UIFont.Small, queueText)
            self:drawText(queueText, eraseBtnX + (btnW - queueTextW) / 2, btnY + 4, 0.9, 0.7, 0.5, 1, UIFont.Small)
        else
            self:drawRect(eraseBtnX, btnY, btnW, btnH, 0.7, 0.5, 0.15, 0.15)
            self:drawRectBorder(eraseBtnX, btnY, btnW, btnH, 0.8, 0.7, 0.25, 0.25)
            local eraseText = getText("UI_BurdJournals_BtnErase") or "Erase"
            mainPanel:drawPillLabelWithPrompt(self, eraseBtnX, btnY, btnW, btnH, eraseText, {r=1, g=0.9, b=0.9, a=1}, "X")
        end
    end

    if showClaimBtn then
        local mainBtnX = rightmostBtnX
        local isInBatch = isInCurrentAbsorbBatch(learningState, "skill", data.skillName)
        if isQueued then
            self:drawRect(mainBtnX, btnY, btnW, btnH, 0.5, 0.3, 0.4, 0.5)
            self:drawRectBorder(mainBtnX, btnY, btnW, btnH, 0.6, 0.4, 0.5, 0.6)
            local btnText = "#" .. queuePosition
            local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
            self:drawText(btnText, mainBtnX + (btnW - btnTextW) / 2, btnY + 4, 0.8, 0.9, 1, 1, UIFont.Small)
        elseif isInBatch then
            self:drawRect(mainBtnX, btnY, btnW, btnH, 0.6, 0.45, 0.55, 0.45)
            self:drawRectBorder(mainBtnX, btnY, btnW, btnH, 0.8, 0.6, 0.7, 0.6)
            local btnText = getText("UI_BurdJournals_BtnBatching") or "BATCH"
            local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
            self:drawText(btnText, mainBtnX + (btnW - btnTextW) / 2, btnY + 4, 0.95, 1, 0.95, 1, UIFont.Small)
        elseif learningState and learningState.active and not learningState.isAbsorbAll then
            self:drawRect(mainBtnX, btnY, btnW, btnH, 0.6, 0.25, 0.35, 0.5)
            self:drawRectBorder(mainBtnX, btnY, btnW, btnH, 0.8, 0.4, 0.55, 0.7)
            local btnText = getText("UI_BurdJournals_BtnQueue")
            local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
            self:drawText(btnText, mainBtnX + (btnW - btnTextW) / 2, btnY + 4, 0.9, 0.95, 1, 1, UIFont.Small)
        else
            self:drawRect(mainBtnX, btnY, btnW, btnH, 0.7, 0.2, 0.4, 0.5)
            self:drawRectBorder(mainBtnX, btnY, btnW, btnH, 0.8, 0.3, 0.55, 0.65)
            local btnText = getText("UI_BurdJournals_BtnClaim")
            mainPanel:drawPillLabelWithPrompt(self, mainBtnX, btnY, btnW, btnH, btnText, {r=1, g=1, b=1, a=1}, "A")
        end
    end
end

function BurdJournals.UI.MainPanel.doDrawViewItem(self, y, item, alt)
    local mainPanel = self.mainPanel
    if not mainPanel then return y + self.itemheight end

    local data = item.item or {}
    local x = 0
    local scrollBarWidth = 13
    local w = self:getWidth() - scrollBarWidth
    local h = tonumber(item.height) or self.itemheight
    if not shouldDrawListRow(self, y, h) then
        return y + h
    end
    local padding = 12

    if data.isHeader then
        self:drawRect(x, y + 2, w, h - 4, 0.4, 0.12, 0.18, 0.22)
        self:drawText(data.text or getText("UI_BurdJournals_Skills") or "SKILLS", x + padding, y + (h - 18) / 2, 0.7, 0.9, 1.0, 1, UIFont.Medium)
        if data.count then
            local countText = BurdJournals.formatText(getText("UI_BurdJournals_Claimable") or "(%d claimable)", data.count)
            local countWidth = getTextManager():MeasureStringX(UIFont.Small, countText)
            self:drawText(countText, w - padding - countWidth, y + (h - 14) / 2, 0.4, 0.6, 0.7, 1, UIFont.Small)
        end
        return y + h
    end

    if data.isEmpty then
        self:drawText(data.text or getText("UI_BurdJournals_NoContent") or "No content", x + padding, y + (h - 14) / 2, 0.4, 0.5, 0.55, 1, UIFont.Small)
        return y + h
    end

    local cardMargin = 4
    local cardX = x + cardMargin
    local cardY = y + cardMargin
    local cardW = w - cardMargin * 2
    local cardH = h - cardMargin * 2
    local canInteract = (data.isSkill and data.canClaim) or (data.isTrait and not data.alreadyKnown and not data.isClaimed and not data.isPending)
    local bgColor = {r=0.12, g=0.16, b=0.20}
    local borderColor = {r=0.25, g=0.38, b=0.45}
    local accent = {r=0.3, g=0.55, b=0.65}

    if data.isTrait then
        if data.isPositive == true then
            bgColor = {r=0.08, g=0.20, b=0.10}
            borderColor = {r=0.2, g=0.5, b=0.25}
            accent = {r=0.3, g=0.8, b=0.35}
        elseif data.isPositive == false then
            bgColor = {r=0.22, g=0.08, b=0.08}
            borderColor = {r=0.5, g=0.2, b=0.2}
            accent = {r=0.8, g=0.3, b=0.3}
        end
    end

    if not canInteract then
        self:drawRect(cardX, cardY, cardW, cardH, 0.4, 0.12, 0.12, 0.12)
    else
        self:drawRect(cardX, cardY, cardW, cardH, 0.7, bgColor.r, bgColor.g, bgColor.b)
    end

    self:drawRectBorder(cardX, cardY, cardW, cardH, 0.6, borderColor.r, borderColor.g, borderColor.b)

    if canInteract then
        self:drawRect(cardX, cardY, 4, cardH, 0.9, accent.r, accent.g, accent.b)
    else
        self:drawRect(cardX, cardY, 4, cardH, 0.5, 0.3, 0.3, 0.3)
    end

    mainPanel:drawSelectedRowOutline(self, item, cardX, cardY, cardW, cardH)

    local textX = cardX + padding + 4
    local textColor = canInteract and {r=0.95, g=0.95, b=1.0} or {r=0.5, g=0.5, b=0.5}

    if data.isSkill then
        doDrawViewSkillItem(self, mainPanel, item, data, textX, textColor, cardX, cardY, cardW, cardH, padding)
    elseif data.isTrait then
        BurdJournals.doDrawViewTraitItem(self, mainPanel, data, textX, cardX, cardY, cardW, cardH)
    elseif data.isRecipe then
        BurdJournals.doDrawViewRecipeItem(self, mainPanel, data, textX, cardX, cardY, cardW, cardH)
    elseif data.isStat then
        BurdJournals.doDrawViewStatItem(self, mainPanel, data, textX, textColor, cardX, cardY, cardW, cardH, padding, y, cardMargin)
    end

    return y + h
end

function BurdJournals.UI.MainPanel:onClaimAll()
    if self.currentTab == "notes" then
        return
    end
    if not self:startLearningAll() then
        self:showFeedback(getText("UI_BurdJournals_AlreadyReading") or "Already reading...", "warn")
    end
end

function BurdJournals.UI.MainPanel:onClaimTab()
    if self.currentTab == "notes" then
        return
    end
    if (self.currentTab or "skills") == "forget" then
        self:showFeedback(
            getText("UI_BurdJournals_ForgetTabHint") or "Choose a trait in this tab to forget.",
            {r=0.9, g=0.72, b=0.45}
        )
        return
    end
    if not self:startLearningTab(self.currentTab or "skills") then
        self:showFeedback(getText("UI_BurdJournals_AlreadyReading") or "Already reading...", "warn")
    end
end

function BurdJournals.UI.MainPanel:claimSkill(skillName, recordedXP)
    if not self:hasLimitedLootClaimAvailable() then
        return
    end
    if self:shouldBlockLimitedLootQueue() then
        return
    end
    local journalData = BurdJournals.getJournalData(self.journal)
    if not BurdJournals.isSkillVisibleForJournal(journalData, skillName) then
        self:showFeedback(getText("UI_BurdJournals_CantClaimSkill") or "That skill cannot be claimed right now", {r=0.9, g=0.5, b=0.3})
        return
    end

    if self.learningState.active and not self.learningState.isAbsorbAll then
        if self:addToQueue("skill", skillName, recordedXP) then
            self:showFeedback(BurdJournals.formatText(getText("UI_BurdJournals_Queued") or "Queued: %s", BurdJournals.getPerkDisplayName(skillName) or skillName), {r=0.7, g=0.8, b=0.9})
        else
            self:showFeedback(getText("UI_BurdJournals_AlreadyQueued") or "Already queued", "warn")
        end
        return
    end

    if not self:startLearningSkill(skillName, recordedXP) then
        self:showFeedback(getText("UI_BurdJournals_AlreadyReading") or "Already reading...", "warn")
    end
end

function BurdJournals.UI.MainPanel:claimTrait(traitId)
    if not self:hasLimitedLootClaimAvailable() then
        return
    end
    if self:shouldBlockLimitedLootQueue() then
        return
    end

    if BurdJournals.playerHasTrait(self.player, traitId) then
        self:showFeedback(getText("UI_BurdJournals_TraitAlreadyKnownFeedback") or "Trait already known!", "muted")
        return
    end

    if self.learningState.active and not self.learningState.isAbsorbAll then
        if self:addToQueue("trait", traitId) then
            local traitName = safeGetTraitName(traitId)
            self:showFeedback(BurdJournals.formatText(getText("UI_BurdJournals_Queued") or "Queued: %s", traitName), {r=0.7, g=0.8, b=0.9})
        else
            self:showFeedback(getText("UI_BurdJournals_AlreadyQueued") or "Already queued", "warn")
        end
        return
    end

    if not self:startLearningTrait(traitId) then
        self:showFeedback(getText("UI_BurdJournals_AlreadyReading") or "Already reading...", "warn")
    end
end

function BurdJournals.UI.MainPanel:claimForgetTrait(traitId)
    if not self:hasLimitedLootClaimAvailable() then
        return
    end
    if self:shouldBlockLimitedLootQueue() then
        return
    end
    if not traitId then return end
    if not (BurdJournals.playerHasTrait and BurdJournals.playerHasTrait(self.player, traitId)) then
        self:showFeedback(getText("UI_BurdJournals_NoForgetableTraits") or "No removable traits available", {r=0.9, g=0.7, b=0.3})
        return
    end

    if self.learningState and self.learningState.active and not self.learningState.isAbsorbAll then
        if self:addToQueue("forget", traitId) then
            local traitName = safeGetTraitName(traitId)
            self:showFeedback(BurdJournals.formatText(getText("UI_BurdJournals_Queued") or "Queued: %s", traitName), {r=0.7, g=0.8, b=0.9})
        else
            self:showFeedback(getText("UI_BurdJournals_AlreadyQueued") or "Already queued", "warn")
        end
        return
    end

    if not self:startLearningForgetTrait(traitId) then
        self:showFeedback(getText("UI_BurdJournals_AlreadyReading") or "Already reading...", "warn")
    end
end

function BurdJournals.UI.MainPanel:sendClaimForgetSlot(traitId)
    if not self.journal or not self.player or not traitId then return end
    local journalId = self.journal:getID()
    local journalData = BurdJournals.getJournalData(self.journal)
    local journalUUID = journalData and journalData.uuid or nil
    local lookupArgs = BurdJournals.buildJournalCommandPayload
        and BurdJournals.buildJournalCommandPayload(self.journal, journalData, true)
        or { journalId = journalId, journalUUID = journalUUID, journalFingerprint = nil }

    if BurdJournals.clientShouldUseServerAuthority() then
        sendClientCommand(self.player, "BurdJournals", "claimForgetSlot", {
            journalId = lookupArgs.journalId,
            journalUUID = lookupArgs.journalUUID,
            journalFingerprint = lookupArgs.journalFingerprint,
            journalData = lookupArgs.journalData,
            traitId = traitId,
        })
        return
    end

    local journalData = BurdJournals.getJournalData(self.journal)
    local forgetSlotCount = journalData and BurdJournals.getForgetSlotCount and BurdJournals.getForgetSlotCount(journalData) or 0
    if not journalData
        or forgetSlotCount < 1
        or not BurdJournals.isForgetSlotEnabledForJournal
        or not BurdJournals.isForgetSlotEnabledForJournal(journalData) then
        self:showFeedback(getText("UI_BurdJournals_NoTraitsAvailable") or "No traits available", {r=0.9, g=0.7, b=0.3})
        return
    end

    if BurdJournals.hasCharacterClaimedForgetSlot and BurdJournals.hasCharacterClaimedForgetSlot(journalData, self.player) then
        self:showFeedback(getText("UI_BurdJournals_ForgetTraitUsed") or "Forget slot already used", {r=0.9, g=0.7, b=0.3})
        return
    end

    local removed = BurdJournals.safeRemoveTrait and BurdJournals.safeRemoveTrait(self.player, traitId)
    if not removed then
        self:showFeedback(getText("UI_BurdJournals_ForgetTraitFailed") or "Could not forget trait", {r=0.9, g=0.4, b=0.4})
        return
    end

    if BurdJournals.markForgetSlotClaimedByCharacter then
        BurdJournals.markForgetSlotClaimedByCharacter(journalData, self.player, traitId)
    end

    safeTransmitPanelJournalModData(self.journal, "mainPanelCurrentJournal")

    local traitName = safeGetTraitName(traitId)
    self:showFeedback(BurdJournals.formatText(getText("UI_BurdJournals_ForgetSlotClaimed") or "Forgot trait: %s", traitName), {r=0.9, g=0.75, b=0.75})
    self:refreshAbsorptionList()
    if self.checkDissolution then
        self:checkDissolution(true)
    end
end

function BurdJournals.UI.MainPanel:claimRecipe(recipeName)
    if not self:hasLimitedLootClaimAvailable() then
        return
    end
    if self:shouldBlockLimitedLootQueue() then
        return
    end

    if self.learningState.active and not self.learningState.isAbsorbAll then
        if self:addToQueue("recipe", recipeName) then
            local displayName = BurdJournals.getRecipeDisplayName(recipeName) or recipeName
            self:showFeedback(BurdJournals.formatText(getText("UI_BurdJournals_Queued") or "Queued: %s", displayName), {r=0.5, g=0.85, b=0.9})
        else
            self:showFeedback(getText("UI_BurdJournals_AlreadyQueued") or "Already queued", "warn")
        end
        return
    end

    if not self:startLearningRecipe(recipeName) then
        self:showFeedback(getText("UI_BurdJournals_AlreadyReading") or "Already reading...", "warn")
    end
end

-- Claim a stat (zombie kills, hours survived) from a journal - starts timed action
function BurdJournals.UI.MainPanel:claimStat(statId, recordedValue)
    if not self.journal or not self.player then return end
    if not self:hasLimitedLootClaimAvailable() then
        return
    end
    if self:shouldBlockLimitedLootQueue() then
        return
    end

    local modData = self.journal:getModData()
    local journalData = modData and modData.BurdJournals
    if not journalData then
        self:showFeedback("Journal has no data", {r=0.9, g=0.4, b=0.4})
        return
    end

    -- Determine the value to apply
    -- Stats are stored as tables with {value = X, timestamp = Y, recordedBy = Z}
    local valueToApply = recordedValue
    if not valueToApply and journalData.stats then
        local statData = journalData.stats[statId]
        valueToApply = type(statData) == "table" and statData.value or statData
    end

    if not valueToApply or type(valueToApply) ~= "number" then
        self:showFeedback("Stat value not found", {r=0.9, g=0.4, b=0.4})
        return
    end

    -- If already learning something (and not absorb all), queue this stat
    if self.learningState.active and not self.learningState.isAbsorbAll then
        if self:addToQueue("stat", statId, valueToApply) then
            local statName = BurdJournals.getStatDisplayName(statId) or statId
            self:showFeedback(BurdJournals.formatText(getText("UI_BurdJournals_Queued") or "Queued: %s", statName), {r=0.7, g=0.8, b=0.9})
        else
            self:showFeedback(getText("UI_BurdJournals_AlreadyQueued") or "Already queued", "warn")
        end
        return
    end

    -- Start the timed learning action
    if not self:startLearningStat(statId, valueToApply) then
        self:showFeedback(getText("UI_BurdJournals_AlreadyReading") or "Already reading...", "warn")
    end
end

-- Send stat claim to server (called after timed action completes)
function BurdJournals.UI.MainPanel:sendClaimStat(statId, value)
    if not self.journal or not self.player then return end

    local statName = BurdJournals.getStatDisplayName(statId)
    local journalData = BurdJournals.getJournalData(self.journal)
    local journalUUID = journalData and journalData.uuid or nil
    local lookupArgs = BurdJournals.buildJournalCommandPayload
        and BurdJournals.buildJournalCommandPayload(self.journal, journalData, true)
        or { journalId = self.journal:getID(), journalUUID = journalUUID, journalFingerprint = nil }

    -- In multiplayer, route through the server
    if BurdJournals.clientShouldUseServerAuthority() then
        sendClientCommand(self.player, "BurdJournals", "claimStat", {
            journalId = lookupArgs.journalId,
            journalUUID = lookupArgs.journalUUID,
            journalFingerprint = lookupArgs.journalFingerprint,
            journalData = lookupArgs.journalData,
            statId = statId,
            value = value,
        })
        return
    end

    -- Single player: apply directly
    local journalData = BurdJournals.getJournalData(self.journal)
    if BurdJournals.applyStatAbsorption(self.player, statId, value) then
        if journalData then
            BurdJournals.markStatClaimedByCharacter(journalData, self.player, statId)
        end

        safeTransmitPanelJournalModData(self.journal, "mainPanelCurrentJournal")
    end
end

-- Track open MainPanel instances for baseline change notifications
BurdJournals.openMainPanels = BurdJournals.openMainPanels or {}

-- Register this panel when created
function BurdJournals.UI.MainPanel:registerOpenPanel()
    BurdJournals.openMainPanels[self] = true
end

-- Unregister when closed
function BurdJournals.UI.MainPanel:unregisterOpenPanel()
    BurdJournals.openMainPanels[self] = nil
end

-- Notification handler for baseline changes
-- Called from BurdJournals.setSkillBaseline, setTraitBaseline, etc.
function BurdJournals.notifyBaselineChanged(player, changeType, itemName)
    if not BurdJournals.openMainPanels then return end
    
    for panel, _ in pairs(BurdJournals.openMainPanels) do
        if panel and panel.player then
            -- Check if this panel is for the affected player
            local panelPlayerId = 0
            if panel.player.getOnlineID then
                panelPlayerId = panel.player:getOnlineID() or 0
            end
            local affectedPlayerId = 0
            if player and player.getOnlineID then
                affectedPlayerId = player:getOnlineID() or 0
            end
            
            -- Refresh if same player or if we can't determine (SP)
            if panelPlayerId == affectedPlayerId or panelPlayerId == 0 or affectedPlayerId == 0 then
                -- Refresh the current list if we're in recording mode
                if panel.mode == "log" and panel.refreshCurrentList then
                    panel:refreshCurrentList()
                    BurdJournals.debugPrint("[BurdJournals] Refreshed MainPanel due to baseline change: " .. tostring(changeType) .. " " .. tostring(itemName))
                end
            end
        end
    end
end
