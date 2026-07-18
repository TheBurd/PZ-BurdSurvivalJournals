
require "BurdJournals_Shared"
require "ISUI/ISToolTipInv"

BurdJournals = BurdJournals or {}
BurdJournals.Tooltips = BurdJournals.Tooltips or {}
-- Last description applied per item id. item:getTooltip() is not guaranteed to
-- echo back what setTooltip stored (script defaults), so track our own writes
-- to keep repeated presentation passes from re-setting the same text.
BurdJournals.Tooltips._appliedDescriptions = BurdJournals.Tooltips._appliedDescriptions or {}

local function getTooltipText(key, fallback)
    local text = getText(key)
    if text and text ~= "" and text ~= key then
        return text
    end
    return fallback
end

local CURSED_TAG_COLOR = {r=0.82, g=0.58, b=0.95}

local function getHiddenCursedInsightTooltipText(item, journalData)
    local selector = 1
    local seed = type(journalData) == "table" and journalData.uuid
        or (item and item.getID and tostring(item:getID()))
        or ""
    if type(seed) == "string" and seed ~= "" then
        local total = 0
        for i = 1, #seed do
            total = total + string.byte(seed, i)
        end
        selector = (total % 4) + 1
    end
    if selector == 1 then
        return getTooltipText("Tooltip_BurdJournals_CursedInsightHidden1", "Just your average Bloody journal.")
    elseif selector == 2 then
        return getTooltipText("Tooltip_BurdJournals_CursedInsightHidden2", "Feels a bit heavy.")
    elseif selector == 3 then
        return getTooltipText("Tooltip_BurdJournals_CursedInsightHidden3", "Smells like pennies.")
    end
    return getTooltipText("Tooltip_BurdJournals_CursedInsightHidden4", "It stinks.")
end

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
        return BurdJournals.formatText(getText("Tooltip_BurdJournals_AgeDays") or "%d days ago", ageDays)
    end
end

local function normalizeTooltipWorldAgeTimestamp(timestamp)
    local numericTimestamp = tonumber(timestamp)
    if not numericTimestamp or numericTimestamp < 0 then
        return nil
    end

    local currentTime = nil
    if getGameTime then
        local gameTime = getGameTime()
        currentTime = gameTime and gameTime.getWorldAgeHours and tonumber(gameTime:getWorldAgeHours()) or nil
    end

    if currentTime and numericTimestamp > currentTime + 24 then
        return nil
    end

    return numericTimestamp
end

local function addTooltipTimestampLine(lines, key, timestamp, color)
    local normalizedTimestamp = normalizeTooltipWorldAgeTimestamp(timestamp)
    local ageText = normalizedTimestamp and formatAge(normalizedTimestamp) or nil
    if not ageText then
        return nil
    end

    table.insert(lines, {
        text = BurdJournals.formatText(getText(key) or key, ageText),
        color = color or {r=0.6, g=0.6, b=0.6},
    })
    return normalizedTimestamp
end

local function getTooltipLastUpdatedTimestamp(journalData)
    if type(journalData) ~= "table" then
        return nil
    end
    return normalizeTooltipWorldAgeTimestamp(journalData.lastUpdated)
        or normalizeTooltipWorldAgeTimestamp(journalData.lastModified)
end

local function isCurrentPlayerOwner(journalData)
    local player = getPlayer()
    if not player then return false end

    local playerUsername = player:getUsername()
    if not playerUsername then return false end

    if journalData.ownerUsername then
        return journalData.ownerUsername == playerUsername
    end

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

local function getTooltipViewerPlayer()
    return getPlayer and getPlayer() or nil
end

local function hasTooltipCharacterClaim(journalData, player, claimType, claimId)
    if type(journalData) ~= "table" or claimId == nil then
        return false
    end

    if player then
        if claimType == "skills" and BurdJournals.hasCharacterClaimedSkill then
            return BurdJournals.hasCharacterClaimedSkill(journalData, player, claimId) == true
        elseif claimType == "traits" and BurdJournals.hasCharacterClaimedTrait then
            return BurdJournals.hasCharacterClaimedTrait(journalData, player, claimId) == true
        elseif claimType == "recipes" and BurdJournals.hasCharacterClaimedRecipe then
            return BurdJournals.hasCharacterClaimedRecipe(journalData, player, claimId) == true
        elseif claimType == "stats" and BurdJournals.hasCharacterClaimedStat then
            return BurdJournals.hasCharacterClaimedStat(journalData, player, claimId) == true
        end
    end

    local legacyClaims = nil
    if claimType == "skills" then
        legacyClaims = journalData.claimedSkills
    elseif claimType == "traits" then
        legacyClaims = journalData.claimedTraits
    elseif claimType == "recipes" then
        legacyClaims = journalData.claimedRecipes
    elseif claimType == "stats" then
        legacyClaims = journalData.claimedStats
    end

    return type(legacyClaims) == "table" and legacyClaims[claimId] == true
end

local function isWrappedYuletideTooltipState(item, journalData)
    if type(journalData) ~= "table" or journalData.isYuletideJournal ~= true then
        return false
    end
    return BurdJournals.getYuletideState
        and BurdJournals.getYuletideState(item or journalData) == BurdJournals.YULETIDE_STATE_WRAPPED
        or false
end

local function shouldPresentRawCursedTooltipAsHidden(item, journalData)
    if not item then
        return false
    end
    if BurdJournals.isHiddenCursedJournal and BurdJournals.isHiddenCursedJournal(item) then
        return true
    end
    if not (BurdJournals.isDisguiseCursedJournalsAsBloodyEnabled and BurdJournals.isDisguiseCursedJournalsAsBloodyEnabled()) then
        return false
    end
    local fullType = item.getFullType and tostring(item:getFullType() or "") or ""
    local cursedType = BurdJournals.CURSED_ITEM_TYPE or "BurdJournals.CursedJournal"
    if fullType ~= cursedType then
        return false
    end
    if type(journalData) == "table"
        and (journalData.isDebugSpawned == true or journalData.debugBackupEnabled == true)
        and (journalData.isCursedJournal == true or journalData.cursedState == "dormant")
    then
        return false
    end
    return type(journalData) ~= "table"
        or (journalData.isCursedReward ~= true and journalData.cursedState ~= "unleashed")
end

local function normalizeHiddenCursedPendingRewards(rawPendingRewards)
    local pendingRewards = rawPendingRewards
    if pendingRewards ~= nil and BurdJournals.normalizeTable then
        pendingRewards = BurdJournals.normalizeTable(pendingRewards) or pendingRewards
    end
    return type(pendingRewards) == "table" and pendingRewards or nil
end

local function shouldReplaceHiddenCursedAuthor(author, unknownAuthorText)
    if type(author) ~= "string" or author == "" then
        return true
    end
    return author == unknownAuthorText or author == "Unknown Survivor"
end

local function shouldReplaceHiddenCursedProfessionName(journalData, professionName, unknownProfessionText)
    if type(professionName) ~= "string" or professionName == "" then
        return true
    end
    if professionName == unknownProfessionText or professionName == "Unknown Profession" then
        return true
    end

    local professionId = type(journalData) == "table" and tostring(journalData.profession or "") or ""
    return string.lower(professionId) == "survivor" and professionName == "Survivor"
end

local function normalizeTooltipJournalData(item)
    local modData = item and item.getModData and item:getModData() or nil
    local journalData = (BurdJournals.getJournalData and BurdJournals.getJournalData(item))
        or (modData and modData.BurdJournals)
    if journalData ~= nil and BurdJournals.normalizeTable then
        journalData = BurdJournals.normalizeTable(journalData) or journalData
    end
    if type(journalData) == "table" and BurdJournals.normalizeJournalData then
        journalData = BurdJournals.normalizeJournalData(journalData) or journalData
    end
    return journalData
end

local function prepareHiddenCursedTooltipData(item, journalData)
    local pendingRewards = normalizeHiddenCursedPendingRewards(journalData.cursedPendingRewards)
    local unknownAuthorText = getText("UI_BurdJournals_UnknownSurvivor") or "Unknown Survivor"
    local unknownProfessionText = getText("UI_BurdJournals_UnknownProfession") or "Unknown Profession"
    local pendingProfessionName = pendingRewards and BurdJournals.resolveProfessionName
        and BurdJournals.resolveProfessionName(pendingRewards)
        or (pendingRewards and pendingRewards.professionName)
    if shouldReplaceHiddenCursedAuthor(journalData.author, unknownAuthorText) then
        journalData.author = (pendingRewards and pendingRewards.author) or unknownAuthorText
    end
    if shouldReplaceHiddenCursedProfessionName(journalData, journalData.professionName, unknownProfessionText) then
        journalData.professionName = pendingProfessionName or unknownProfessionText
    end
    if pendingRewards and (not journalData.profession or journalData.profession == "" or string.lower(tostring(journalData.profession or "")) == "survivor") then
        journalData.profession = pendingRewards.profession or journalData.profession
    end
    journalData.sourceType = journalData.sourceType or (pendingRewards and pendingRewards.sourceType) or "zombie"
end

local function shouldHideRewardDetailsForTooltip(item, journalData, isHiddenCursed)
    -- A sealed archetype (e.g. Blessed) conceals its rewards until the seal is
    -- broken, mirroring cursed/yuletide mystery.
    if BurdJournals.shouldHideSealedContents
        and BurdJournals.shouldHideSealedContents(item or journalData) then
        return true
    end
    if BurdJournals.shouldHideLootRewardDetails and BurdJournals.shouldHideLootRewardDetails(item) then
        return true
    end
    local hasRewardContent = (BurdJournals.hasAnyEntries and BurdJournals.hasAnyEntries(journalData.skills))
        or (BurdJournals.hasAnyEntries and BurdJournals.hasAnyEntries(journalData.traits))
        or (BurdJournals.hasAnyEntries and BurdJournals.hasAnyEntries(journalData.recipes))
        or (BurdJournals.hasAnyEntries and BurdJournals.hasAnyEntries(journalData.stats))
        or journalData.forgetSlot == true
    local isLootJournal = (BurdJournals.isLootRewardJournal and BurdJournals.isLootRewardJournal(item))
        or isHiddenCursed
    local rewardsRevealed = BurdJournals.isLootRewardsRevealed
        and BurdJournals.isLootRewardsRevealed(item)
        or (journalData.lootRewardsRevealed == true)
    return journalData.isPlayerCreated ~= true
        and not rewardsRevealed
        and (hasRewardContent or isLootJournal)
end

local function addTooltipIdentityLines(lines, item, journalData, isWrappedYuletide)
    if (not isWrappedYuletide) and journalData.ownerUsername then
        local ownerText = journalData.ownerUsername
        local ownerColor = {r=0.7, g=0.7, b=0.9}
        if isCurrentPlayerOwner(journalData) then
            ownerText = ownerText .. " " .. (getText("Tooltip_BurdJournals_OwnerYou") or "(You)")
            ownerColor = {r=0.4, g=0.8, b=1.0}
        end
        table.insert(lines, {
            text = BurdJournals.formatText(getText("Tooltip_BurdJournals_Owner") or "Owner: %s", ownerText),
            color = ownerColor,
        })
    end

    local displayAuthor = BurdJournals.getJournalDisplayAuthor and BurdJournals.getJournalDisplayAuthor(journalData) or journalData.author
    if (not isWrappedYuletide) and displayAuthor then
        if not (journalData.ownerUsername and displayAuthor == journalData.ownerUsername) then
            table.insert(lines, {
                text = BurdJournals.formatText(getText("Tooltip_BurdJournals_Author") or "Author: %s", displayAuthor),
                color = {r=0.8, g=0.8, b=0.6},
            })
        end
    end

    if (not isWrappedYuletide) and journalData.contributors then
        local contributorNames = {}
        for _, contribData in pairs(journalData.contributors) do
            if contribData.characterName then
                table.insert(contributorNames, contribData.characterName)
            elseif contribData.username then
                table.insert(contributorNames, contribData.username)
            end
        end
        if #contributorNames > 0 then
            table.sort(contributorNames)
            table.insert(lines, {
                text = BurdJournals.formatText(getText("Tooltip_BurdJournals_Contributors") or "Contributors: %s", table.concat(contributorNames, ", ")),
                color = {r=0.6, g=0.8, b=0.6},
            })
        end
    end

    local resolvedProfessionName = BurdJournals.resolveProfessionName(journalData)
    if (not isWrappedYuletide) and resolvedProfessionName then
        table.insert(lines, {
            text = BurdJournals.formatText(getText("Tooltip_BurdJournals_Profession") or "Profession: %s", resolvedProfessionName),
            color = {r=0.7, g=0.7, b=0.7},
        })
    end
end

local function addTooltipRewardLines(lines, journalData, tooltipPlayer)
    local skillCount, unclaimedSkills, totalXP = 0, 0, 0
    if journalData.skills then
        for skillName, skillData in pairs(journalData.skills) do
            skillCount = skillCount + 1
            if not hasTooltipCharacterClaim(journalData, tooltipPlayer, "skills", skillName) then
                unclaimedSkills = unclaimedSkills + 1
                totalXP = totalXP + (skillData.xp or 0)
            end
        end
    end
    local skillDetailsResident = skillCount > 0
    if skillCount <= 0 and journalData.entryStoreEnabled == true and type(journalData.entryStoreEntryCounts) == "table" then
        skillCount = math.max(0, tonumber(journalData.entryStoreEntryCounts.skills) or 0)
        unclaimedSkills = skillCount
    end
    if skillCount > 0 then
        local skillText = nil
        if skillDetailsResident and unclaimedSkills > 0 and BurdJournals.formatXP then
            skillText = BurdJournals.formatText(getText("Tooltip_BurdJournals_SkillsLineXP") or "Skills: %d/%d (%s XP)", unclaimedSkills, skillCount, BurdJournals.formatXP(totalXP))
        else
            skillText = BurdJournals.formatText(getText("Tooltip_BurdJournals_SkillsLine") or "Skills: %d/%d", unclaimedSkills, skillCount)
            if unclaimedSkills <= 0 then
                skillText = skillText .. " " .. (getText("Tooltip_BurdJournals_AllClaimed") or "(all claimed)")
            end
        end
        table.insert(lines, {text = skillText, color = unclaimedSkills > 0 and {r=0.4, g=0.9, b=0.4} or {r=0.5, g=0.5, b=0.5}})
    end

    local traitCount, unclaimedTraits = 0, 0
    if journalData.traits then
        for traitId in pairs(journalData.traits) do
            traitCount = traitCount + 1
            if not hasTooltipCharacterClaim(journalData, tooltipPlayer, "traits", traitId) then
                unclaimedTraits = unclaimedTraits + 1
            end
        end
    end
    if traitCount <= 0 and journalData.entryStoreEnabled == true and type(journalData.entryStoreEntryCounts) == "table" then
        traitCount = math.max(0, tonumber(journalData.entryStoreEntryCounts.traits) or 0)
        unclaimedTraits = traitCount
    end
    if traitCount > 0 then
        local traitText = BurdJournals.formatText(getText("Tooltip_BurdJournals_TraitsLine") or "Traits: %d/%d", unclaimedTraits, traitCount)
        if unclaimedTraits <= 0 then
            traitText = traitText .. " " .. (getText("Tooltip_BurdJournals_AllClaimed") or "(all claimed)")
        end
        table.insert(lines, {text = traitText, color = unclaimedTraits > 0 and {r=0.9, g=0.7, b=0.3} or {r=0.5, g=0.5, b=0.5}})
    end

    local recipeCount, unclaimedRecipes = 0, 0
    if journalData.recipes then
        for recipeName in pairs(journalData.recipes) do
            recipeCount = recipeCount + 1
            if not hasTooltipCharacterClaim(journalData, tooltipPlayer, "recipes", recipeName) then
                unclaimedRecipes = unclaimedRecipes + 1
            end
        end
    end
    if recipeCount <= 0 and journalData.entryStoreEnabled == true and type(journalData.entryStoreEntryCounts) == "table" then
        recipeCount = math.max(0, tonumber(journalData.entryStoreEntryCounts.recipes) or 0)
        unclaimedRecipes = recipeCount
    end
    if recipeCount > 0 then
        local recipeText = BurdJournals.formatText(getText("Tooltip_BurdJournals_RecipesLine") or "Recipes: %d/%d", unclaimedRecipes, recipeCount)
        if unclaimedRecipes <= 0 then
            recipeText = recipeText .. " " .. (getText("Tooltip_BurdJournals_AllClaimed") or "(all claimed)")
        end
        table.insert(lines, {text = recipeText, color = unclaimedRecipes > 0 and {r=0.5, g=0.85, b=0.9} or {r=0.5, g=0.5, b=0.5}})
    end
end

local function addTooltipCursedInsightLine(lines, item, journalData, tooltipPlayer, isHiddenCursed)
    local isDormantCursed = (journalData
            and journalData.isCursedJournal == true
            and journalData.isCursedReward ~= true)
        or (item and BurdJournals.isCursedJournalItem and BurdJournals.isCursedJournalItem(item))
    if not (isHiddenCursed or isDormantCursed) then
        return
    end
    local insightLevel = BurdJournals.getCursedInsightLevel
        and select(1, BurdJournals.getCursedInsightLevel(tooltipPlayer))
        or 0
    if insightLevel <= 0 then
        return
    end
    if isHiddenCursed and insightLevel < 2 then
        return
    end
    if isDormantCursed and not isHiddenCursed and insightLevel < 2 then
        return
    end

    local text = nil
    local color = {r=0.82, g=0.58, b=0.95}
    local preview = nil
    if BurdJournals.Client and BurdJournals.Client.getCachedCursedInsightPreviewForItem then
        preview = BurdJournals.Client.getCachedCursedInsightPreviewForItem(item, journalData)
    end
    if BurdJournals.Client and BurdJournals.Client.requestCursedInsightPreview and insightLevel >= 2 then
        BurdJournals.Client.requestCursedInsightPreview(tooltipPlayer, item, journalData)
    end

    local effectType = preview and type(preview.effectType) == "string" and preview.effectType
        or (type(journalData.cursedInsightEffectType) == "string" and journalData.cursedInsightEffectType or nil)
    local omenCategory = preview and type(preview.omenCategory) == "string" and preview.omenCategory
        or (type(journalData.cursedOmenCategory) == "string" and journalData.cursedOmenCategory or nil)
    if insightLevel >= 3 and effectType then
        local effectName = BurdJournals.getCursedEffectInsightDisplayName
            and BurdJournals.getCursedEffectInsightDisplayName(effectType)
            or effectType
        text = BurdJournals.formatText(
            getTooltipText("Tooltip_BurdJournals_CursedInsightExact", "Curse: %s"),
            effectName
        )
        color = {r=0.95, g=0.42, b=0.42}
    elseif insightLevel >= 2 and omenCategory then
        local category = string.lower(omenCategory)
        if category == "ruin" then
            text = getTooltipText("Tooltip_BurdJournals_CursedInsightOmenRuin", "The seal leans toward ruin.")
        elseif category == "loss" then
            text = getTooltipText("Tooltip_BurdJournals_CursedInsightOmenLoss", "The seal leans toward loss.")
        else
            text = getTooltipText("Tooltip_BurdJournals_CursedInsightOmenPain", "The seal leans toward pain.")
        end
    else
        text = getTooltipText("Tooltip_BurdJournals_CursedInsightFaint", "The seal hints at a specific kind of punishment.")
    end

    if text and text ~= "" then
        table.insert(lines, {text = text, color = color})
    end
end

local function addTooltipConditionLine(lines, journalData, isHiddenCursed, isWrappedYuletide)
    local text, color, suffixText, suffixColor = nil, nil, nil, nil

    -- Registered sealed archetypes (e.g. Blessed) own their condition line so
    -- they don't fall through to the bloody/clean chain. The theme header's
    -- flavor/rarity is set elsewhere; here we just present a condition label
    -- and (below) any registered condition tag suffix like "[Blessed]".
    local sealedEntry = BurdJournals.getSealedJournalType
        and BurdJournals.getSealedJournalType(journalData) or nil
    local sealedCondKey = sealedEntry and sealedEntry.themeKey
        and ("Tooltip_BurdJournals_Condition_" .. sealedEntry.themeKey) or nil

    -- Add-on condition tag suffix (gold "[Blessed]", etc.), resolved generically.
    local regTagText, regTagColor = nil, nil
    if BurdJournals.resolveConditionTag then
        regTagText, regTagColor = BurdJournals.resolveConditionTag(journalData)
    end

    if sealedEntry then
        local sealedFallback = getTooltipText("Tooltip_BurdJournals_ConditionBlessed", nil)
            or getTooltipText("Tooltip_BurdJournals_ConditionClean", nil)
        text = sealedCondKey and getTooltipText(sealedCondKey, sealedFallback) or sealedFallback
        color = {r=0.86, g=0.78, b=0.52}
        if regTagText then
            suffixText = " " .. regTagText
            suffixColor = regTagColor
        end
    elseif journalData.isBloody == true or journalData.wasFromBloody == true or isHiddenCursed then
        text = getText("Tooltip_BurdJournals_ConditionBloody") or "Condition: Bloody"
        color = {r=0.8, g=0.2, b=0.2}
        if journalData.isCursedReward == true and not isHiddenCursed then
            suffixText = " " .. getTooltipText("Tooltip_BurdJournals_TagCursed", "[Cursed]")
            suffixColor = CURSED_TAG_COLOR
        elseif regTagText then
            suffixText = " " .. regTagText
            suffixColor = regTagColor
        end
    elseif journalData.isWorn == true or journalData.wasWorn == true then
        text = getText("Tooltip_BurdJournals_ConditionWorn") or "Condition: Worn"
        color = {r=0.7, g=0.5, b=0.3}
    elseif BurdJournals.isRestoredJournalData
        and BurdJournals.isRestoredJournalData(journalData)
    then
        text = getText("Tooltip_BurdJournals_ConditionRestored") or "Condition: Restored"
        color = {r=0.6, g=0.7, b=0.5}
    elseif not isWrappedYuletide then
        text = getText("Tooltip_BurdJournals_ConditionClean") or "Condition: Clean"
        color = {r=0.5, g=0.8, b=0.5}
    end
    if text then
        table.insert(lines, {text = text, color = color, suffixText = suffixText, suffixColor = suffixColor})
    end
end

local function addTooltipOriginLine(lines, journalData)
    local originText = nil
    local originColor = {r=0.6, g=0.6, b=0.6}
    local sourceType = type(journalData.sourceType) == "string" and string.lower(journalData.sourceType) or nil
    if sourceType == "personal" then
        originText = getText("Tooltip_BurdJournals_OriginPersonal") or "Origin: Personal"
        originColor = {r=0.3, g=0.6, b=0.8}
    elseif sourceType == "zombie" or journalData.wasFromBloody then
        originText = getText("Tooltip_BurdJournals_OriginZombie") or "Origin: Recovered from zombie"
        originColor = {r=0.6, g=0.4, b=0.3}
    elseif sourceType == "world" or sourceType == "found" then
        originText = getText("Tooltip_BurdJournals_OriginWorld") or "Origin: Found in world"
        originColor = {r=0.5, g=0.5, b=0.6}
    elseif sourceType == "crafted" then
        originText = getText("Tooltip_BurdJournals_OriginCrafted") or "Origin: Crafted"
        originColor = {r=0.5, g=0.6, b=0.5}
    elseif not journalData.ownerUsername and journalData.author then
        originText = getText("Tooltip_BurdJournals_OriginFound") or "Origin: Found"
        originColor = {r=0.5, g=0.5, b=0.6}
    elseif isCurrentPlayerOwner(journalData) then
        originText = getText("Tooltip_BurdJournals_OriginPersonal") or "Origin: Personal"
        originColor = {r=0.3, g=0.6, b=0.8}
    end
    if originText then
        table.insert(lines, {text = originText, color = originColor})
    end
end

local function addTooltipAgeLine(lines, journalData)
    local createdTimestamp = addTooltipTimestampLine(
        lines,
        "Tooltip_BurdJournals_Created",
        journalData.timestamp,
        {r=0.6, g=0.6, b=0.6}
    )

    local updatedTimestamp = getTooltipLastUpdatedTimestamp(journalData)
    if updatedTimestamp and (not createdTimestamp or math.abs(updatedTimestamp - createdTimestamp) > 0.01) then
        addTooltipTimestampLine(
            lines,
            "Tooltip_BurdJournals_LastUpdated",
            updatedTimestamp,
            {r=0.6, g=0.6, b=0.6}
        )
    end
end

function BurdJournals.Tooltips.getExtraInfo(item)
    if not item then return nil end

    local fullType = item:getFullType()
    if not fullType or not string.find(fullType, "BurdJournals") then
        return nil
    end

    local journalData = normalizeTooltipJournalData(item)
    local isHiddenCursed = shouldPresentRawCursedTooltipAsHidden(item, journalData)
    local isRawCursed = BurdJournals.isCursedJournalItem and BurdJournals.isCursedJournalItem(item) or false
    local hasJournalData = type(journalData) == "table"

    if not journalData and not isHiddenCursed and not isRawCursed then
        return nil
    end

    journalData = hasJournalData and journalData or {}

    if isHiddenCursed then
        -- Tooltip rendering is read-only: apply disguise fields to a display
        -- copy so live journal/ModData tables are never mutated from render.
        local displayData = {}
        for key, value in pairs(journalData) do
            displayData[key] = value
        end
        journalData = displayData
        prepareHiddenCursedTooltipData(item, journalData)
    end

    local lines = {}
    local tooltipPlayer = getTooltipViewerPlayer()
    local isWrappedYuletide = isWrappedYuletideTooltipState(item, journalData)
    addTooltipIdentityLines(lines, item, journalData, isWrappedYuletide)
    if not shouldHideRewardDetailsForTooltip(item, journalData, isHiddenCursed) then
        addTooltipRewardLines(lines, journalData, tooltipPlayer)
    end
    addTooltipCursedInsightLine(lines, item, journalData, tooltipPlayer, isHiddenCursed)
    if isRawCursed and not isHiddenCursed and not hasJournalData then
        return lines
    end
    addTooltipConditionLine(lines, journalData, isHiddenCursed, isWrappedYuletide)
    addTooltipOriginLine(lines, journalData)
    addTooltipAgeLine(lines, journalData)

    return lines
end

-- Event-driven description sync. Called from BurdJournals.updateJournalIcon so
-- every existing presentation sweep (container refresh, init, server-response
-- paths) refreshes the item description. This must NEVER be called from
-- ISToolTipInv.render: mutating inventory items during render destabilizes
-- rendering and input.
function BurdJournals.Tooltips.applyItemDescription(item)
    if not (item and item.getFullType and item.setTooltip) then
        return
    end
    local fullType = item:getFullType()
    if not fullType or not string.find(fullType, "BurdJournals") then
        return
    end

    local journalData = BurdJournals.getJournalData and BurdJournals.getJournalData(item) or nil

    local tooltipText = nil
    if BurdJournals.isWrappedYuletideJournal and BurdJournals.isWrappedYuletideJournal(item) then
        tooltipText = BurdJournals.safeGetText("Tooltip_BurdJournals_YuletideJournalDesc", "A wrapped holiday journal. Unwrap it to reveal the journal and its bundled supplies.")
    elseif BurdJournals.isUnwrappedYuletideJournal and BurdJournals.isUnwrappedYuletideJournal(item) then
        tooltipText = BurdJournals.safeGetText("Tooltip_BurdJournals_YuletideJournalOpenedDesc", "A festive loot journal filled with rewards and notes from Santa.")
    elseif shouldPresentRawCursedTooltipAsHidden(item, journalData) then
        local insightLevel = BurdJournals.getCursedInsightLevel
            and select(1, BurdJournals.getCursedInsightLevel(getTooltipViewerPlayer()))
            or 0
        if insightLevel >= 1 then
            tooltipText = getHiddenCursedInsightTooltipText(item, journalData)
        else
            tooltipText = BurdJournals.safeGetText("Tooltip_BurdJournals_BloodyDesc", "Rare find! May contain valuable traits.")
        end
    elseif BurdJournals.isCursedJournalItem and BurdJournals.isCursedJournalItem(item) then
        tooltipText = BurdJournals.safeGetText("Tooltip_BurdJournals_CursedJournalDesc", "Breaking the seal marks the first reader, but unlocks a richer bloody reward journal.")
    elseif BurdJournals.isBloody and BurdJournals.isBloody(item) then
        tooltipText = BurdJournals.safeGetText("Tooltip_BurdJournals_BloodyJournalDesc", "A journal from a fallen survivor. Contains skills and traits that can be absorbed.")
    end

    if tooltipText and tooltipText ~= "" then
        local itemId = item.getID and item:getID() or nil
        if itemId ~= nil then
            if BurdJournals.Tooltips._appliedDescriptions[itemId] == tooltipText then
                return
            end
            BurdJournals.Tooltips._appliedDescriptions[itemId] = tooltipText
        end
        item:setTooltip(tooltipText)
    end
end

local function isJournalTooltipItem(item)
    if not (item and item.getFullType) then
        return false
    end
    local fullType = item:getFullType()
    return fullType and string.find(fullType, "BurdJournals") ~= nil
end

local function drawTooltipLine(self, lineData, y, font)
    local lineText = tostring(lineData.text or "")
    local lineColor = lineData.color or {r=1, g=1, b=1}
    self:drawText(lineText, 12, y, lineColor.r, lineColor.g, lineColor.b, 1.0, font)
    if lineData.suffixText and tostring(lineData.suffixText) ~= "" then
        local suffixColor = lineData.suffixColor or lineColor
        local baseWidth = getTextManager():MeasureStringX(font, lineText)
        self:drawText(tostring(lineData.suffixText), 12 + baseWidth, y, suffixColor.r, suffixColor.g, suffixColor.b, 1.0, font)
    end
end

local function drawTooltipExtraLines(self, extraLines)
    local font = UIFont.Small
    local lineHeight = getTextManager():getFontHeight(font) + 2
    local extraHeight = (#extraLines * lineHeight) + 12
    local originalHeight = self:getHeight()
    local bgColor = self.backgroundColor
    local borderColor = self.borderColor
    if not bgColor or not borderColor then
        return
    end

    self:drawRect(0, originalHeight, self:getWidth(), extraHeight, bgColor.a, bgColor.r, bgColor.g, bgColor.b)
    self:drawRect(0, originalHeight, 1, extraHeight, borderColor.a, borderColor.r, borderColor.g, borderColor.b)
    self:drawRect(self:getWidth() - 1, originalHeight, 1, extraHeight, borderColor.a, borderColor.r, borderColor.g, borderColor.b)
    self:drawRect(0, originalHeight + extraHeight - 1, self:getWidth(), 1, borderColor.a, borderColor.r, borderColor.g, borderColor.b)
    self:drawRect(1, originalHeight - 1, self:getWidth() - 2, 1, bgColor.a, bgColor.r, bgColor.g, bgColor.b)

    local startY = originalHeight + 5
    self:drawRect(10, startY - 3, self:getWidth() - 20, 1, 0.5, 0.6, 0.6, 0.6)
    for i, lineData in ipairs(extraLines) do
        drawTooltipLine(self, lineData, startY + (i - 1) * lineHeight, font)
    end
    self:setHeight(originalHeight + extraHeight)
end

BurdJournals.Tooltips.originalRender = BurdJournals.Tooltips.originalRender or ISToolTipInv.render

-- Read-only render hook: draw extra journal lines below the vanilla tooltip.
-- Do not mutate the hovered item here (no setTooltip/setName/setTexture and no
-- updateJournalName/updateJournalIcon) -- per-frame item mutation from render
-- caused world flicker and input loss.
ISToolTipInv.render = function(self)
    BurdJournals.Tooltips.originalRender(self)
    if not isJournalTooltipItem(self.item) then
        return
    end
    local extraLines = BurdJournals.Tooltips.getExtraInfo(self.item)
    if not extraLines or #extraLines == 0 then
        return
    end
    drawTooltipExtraLines(self, extraLines)
end

BurdJournals.debugPrint("[BurdJournals] Tooltip hook installed idempotent")
