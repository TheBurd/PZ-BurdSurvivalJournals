if not BurdJournals then BurdJournals = {} end

function BurdJournals.doDrawViewTraitItem(self, mainPanel, data, textX, cardX, cardY, cardW, cardH)
    local learningState = mainPanel.learningState
    local isLearningThis = learningState and learningState.active and not learningState.isAbsorbAll
        and learningState.traitId == data.traitId
    local erasingState = mainPanel.erasingState
    local isErasingThis = erasingState and erasingState.active
        and erasingState.entryType == "trait" and erasingState.entryName == data.traitId
    local traitName = data.traitName or data.traitId or getText("UI_BurdJournals_UnknownTrait") or "Unknown Trait"
    local traitTextX = textX

    if data.traitTexture then
        local iconSize = 24
        local iconX = textX
        local iconY = cardY + (cardH - iconSize) / 2
        local iconAlpha = data.alreadyKnown and 0.4 or 1.0
        self:drawTextureScaledAspect(data.traitTexture, iconX, iconY, iconSize, iconSize, iconAlpha, 1, 1, 1)
        traitTextX = textX + iconSize + 6
    end

    local queuePosition = mainPanel:getQueuePosition(data.traitId)
    local isQueued = queuePosition ~= nil
    local traitColor

    if data.alreadyKnown then
        traitColor = {r=0.5, g=0.5, b=0.5}
    elseif data.isPositive == true then
        traitColor = {r=0.5, g=0.9, b=0.5}
    elseif data.isPositive == false then
        traitColor = {r=0.9, g=0.5, b=0.5}
    else
        traitColor = {r=0.8, g=0.9, b=1.0}
    end

    self:drawText(traitName, traitTextX, cardY + 6, traitColor.r, traitColor.g, traitColor.b, 1, UIFont.Small)

    if isErasingThis then
        local progressFormat = getText("UI_BurdJournals_ErasingProgress") or "Erasing... %d%%"
        local progressText = BurdJournals.normalizeProgressPercentLabel(BurdJournals.formatText(progressFormat, math.floor((erasingState.progress or 0) * 100)))
        local barX = traitTextX + 100
        local barY = cardY + 25
        local barW = cardW - barX - 20
        local barH = 10

        self:drawText(progressText, traitTextX, cardY + 22, 0.9, 0.5, 0.5, 1, UIFont.Small)
        self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)
        self:drawRect(barX, barY, barW * (erasingState.progress or 0), barH, 0.9, 0.7, 0.3, 0.3)
        self:drawRectBorder(barX, barY, barW, barH, 0.7, 0.6, 0.3, 0.3)
    elseif isLearningThis then
        local progressText = BurdJournals.normalizeProgressPercentLabel(BurdJournals.formatText("Learning... %d%%", math.floor(learningState.progress * 100)))
        local barX = traitTextX + 100
        local barY = cardY + 25
        local barW = cardW - barX - 20
        local barH = 10

        self:drawText(progressText, traitTextX, cardY + 22, 0.3, 0.7, 0.9, 1, UIFont.Small)
        self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)
        self:drawRect(barX, barY, barW * learningState.progress, barH, 0.9, 0.25, 0.5, 0.7)
        self:drawRectBorder(barX, barY, barW, barH, 0.7, 0.35, 0.6, 0.8)
    elseif isQueued then
        local queuedText = BurdJournals.formatText(getText("UI_BurdJournals_QueuedNumber") or "Queued #%d", queuePosition)
        self:drawText(queuedText, traitTextX, cardY + 22, 0.6, 0.75, 0.9, 1, UIFont.Small)
    elseif data.alreadyKnown then
        self:drawText(getText("UI_BurdJournals_StatusAlreadyKnown") or "Already known", traitTextX, cardY + 22, 0.4, 0.45, 0.45, 1, UIFont.Small)
    elseif data.isClaimed then
        self:drawText(getText("UI_BurdJournals_StatusAlreadyClaimed") or "Already claimed", traitTextX, cardY + 22, 0.4, 0.45, 0.45, 1, UIFont.Small)
    else
        self:drawText(getText("UI_BurdJournals_RecordedTrait") or "Recorded trait", traitTextX, cardY + 22, 0.5, 0.7, 0.8, 1, UIFont.Small)
    end

    local btnW = 55
    local btnH = 24
    local btnGap = 4
    local hasEraser = BurdJournals.hasEraser(mainPanel.player)
    local rightmostBtnX = cardX + cardW - btnW - 10
    local btnY = cardY + (cardH - btnH) / 2
    local canClaimTrait = not data.alreadyKnown and not data.isClaimed and not data.isPending
    local showClaimBtn = canClaimTrait and not isLearningThis
    local eraseBtnX = showClaimBtn and (rightmostBtnX - btnW - btnGap) or rightmostBtnX
    local eraseQueuePos = mainPanel:getEraseQueuePosition(data.traitId)
    local isEraseQueued = eraseQueuePos ~= nil

    if hasEraser and not isErasingThis then
        if isEraseQueued then
            local queueText = "#" .. eraseQueuePos
            local queueTextW = getTextManager():MeasureStringX(UIFont.Small, queueText)
            self:drawRect(eraseBtnX, btnY, btnW, btnH, 0.5, 0.4, 0.25, 0.25)
            self:drawRectBorder(eraseBtnX, btnY, btnW, btnH, 0.6, 0.6, 0.35, 0.35)
            self:drawText(queueText, eraseBtnX + (btnW - queueTextW) / 2, btnY + 4, 0.9, 0.7, 0.5, 1, UIFont.Small)
        else
            local eraseText = getText("UI_BurdJournals_BtnErase") or "Erase"
            self:drawRect(eraseBtnX, btnY, btnW, btnH, 0.7, 0.5, 0.15, 0.15)
            self:drawRectBorder(eraseBtnX, btnY, btnW, btnH, 0.8, 0.7, 0.25, 0.25)
            mainPanel:drawPillLabelWithPrompt(self, eraseBtnX, btnY, btnW, btnH, eraseText, {r=1, g=0.9, b=0.9, a=1}, "X")
        end
    end

    if showClaimBtn then
        local mainBtnX = rightmostBtnX
        local isInBatch = BurdJournals.isInCurrentAbsorbBatch(learningState, "trait", data.traitId)

        if isQueued then
            local btnText = "#" .. queuePosition
            local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
            self:drawRect(mainBtnX, btnY, btnW, btnH, 0.5, 0.4, 0.35, 0.5)
            self:drawRectBorder(mainBtnX, btnY, btnW, btnH, 0.6, 0.5, 0.45, 0.6)
            self:drawText(btnText, mainBtnX + (btnW - btnTextW) / 2, btnY + 4, 0.9, 0.85, 0.7, 1, UIFont.Small)
        elseif isInBatch then
            local btnText = getText("UI_BurdJournals_BtnBatching") or "BATCH"
            local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
            self:drawRect(mainBtnX, btnY, btnW, btnH, 0.6, 0.5, 0.45, 0.45)
            self:drawRectBorder(mainBtnX, btnY, btnW, btnH, 0.8, 0.65, 0.55, 0.6)
            self:drawText(btnText, mainBtnX + (btnW - btnTextW) / 2, btnY + 4, 1, 0.95, 0.85, 1, UIFont.Small)
        elseif learningState and learningState.active and not learningState.isAbsorbAll then
            local btnText = getText("UI_BurdJournals_BtnQueue")
            local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
            self:drawRect(mainBtnX, btnY, btnW, btnH, 0.6, 0.35, 0.4, 0.5)
            self:drawRectBorder(mainBtnX, btnY, btnW, btnH, 0.8, 0.5, 0.55, 0.65)
            self:drawText(btnText, mainBtnX + (btnW - btnTextW) / 2, btnY + 4, 1, 0.95, 0.9, 1, UIFont.Small)
        else
            local btnText = getText("UI_BurdJournals_BtnClaim")
            self:drawRect(mainBtnX, btnY, btnW, btnH, 0.7, 0.35, 0.45, 0.55)
            self:drawRectBorder(mainBtnX, btnY, btnW, btnH, 0.8, 0.5, 0.6, 0.7)
            mainPanel:drawPillLabelWithPrompt(self, mainBtnX, btnY, btnW, btnH, btnText, {r=1, g=1, b=1, a=1}, "A")
        end
    end
end

function BurdJournals.doDrawViewRecipeItem(self, mainPanel, data, textX, cardX, cardY, cardW, cardH)
    local learningState = mainPanel.learningState
    local isLearningThis = learningState and learningState.active and not learningState.isAbsorbAll
        and learningState.recipeName == data.recipeName
    local erasingState = mainPanel.erasingState
    local isErasingThis = erasingState and erasingState.active
        and erasingState.entryType == "recipe" and erasingState.entryName == data.recipeName
    local recipeName = data.displayName or data.recipeName or "Unknown Recipe"
    local recipeTextX = textX
    local magazineTexture = BurdJournals.getMagazineTexture(data.magazineSource)

    if magazineTexture then
        local iconSize = 24
        local iconX = textX
        local iconY = cardY + (cardH - iconSize) / 2
        local iconAlpha = (data.alreadyKnown or data.isClaimed) and 0.4 or 1.0
        self:drawTextureScaledAspect(magazineTexture, iconX, iconY, iconSize, iconSize, iconAlpha, 1, 1, 1)
        recipeTextX = textX + iconSize + 6
    end

    local queuePosition = mainPanel:getQueuePosition(data.recipeName)
    local isQueued = queuePosition ~= nil
    local recipeColor = (data.alreadyKnown or data.isClaimed) and {r=0.5, g=0.5, b=0.5} or {r=0.5, g=0.9, b=0.95}
    self:drawText(recipeName, recipeTextX, cardY + 6, recipeColor.r, recipeColor.g, recipeColor.b, 1, UIFont.Small)

    if isErasingThis then
        local progressFormat = getText("UI_BurdJournals_ErasingProgress") or "Erasing... %d%%"
        local progressText = BurdJournals.normalizeProgressPercentLabel(BurdJournals.formatText(progressFormat, math.floor((erasingState.progress or 0) * 100)))
        local barX = recipeTextX + 100
        local barY = cardY + 25
        local barW = cardW - barX - 20
        local barH = 10

        self:drawText(progressText, recipeTextX, cardY + 22, 0.9, 0.5, 0.5, 1, UIFont.Small)
        self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)
        self:drawRect(barX, barY, barW * (erasingState.progress or 0), barH, 0.9, 0.7, 0.3, 0.3)
        self:drawRectBorder(barX, barY, barW, barH, 0.7, 0.6, 0.3, 0.3)
    elseif isLearningThis then
        local progressText = BurdJournals.normalizeProgressPercentLabel(BurdJournals.formatText("Learning... %d%%", math.floor(learningState.progress * 100)))
        local barX = recipeTextX + 100
        local barY = cardY + 25
        local barW = cardW - barX - 20
        local barH = 10

        self:drawText(progressText, recipeTextX, cardY + 22, 0.3, 0.8, 0.85, 1, UIFont.Small)
        self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)
        self:drawRect(barX, barY, barW * learningState.progress, barH, 0.9, 0.25, 0.65, 0.75)
        self:drawRectBorder(barX, barY, barW, barH, 0.7, 0.35, 0.75, 0.85)
    elseif isQueued then
        local queuedText = BurdJournals.formatText(getText("UI_BurdJournals_QueuedNumber") or "Queued #%d", queuePosition)
        self:drawText(queuedText, recipeTextX, cardY + 22, 0.5, 0.8, 0.9, 1, UIFont.Small)
    elseif data.alreadyKnown then
        self:drawText(getText("UI_BurdJournals_RecipeAlreadyKnown") or "Already known", recipeTextX, cardY + 22, 0.4, 0.45, 0.45, 1, UIFont.Small)
    elseif data.isClaimed then
        self:drawText(getText("UI_BurdJournals_StatusAlreadyClaimed") or "Already claimed", recipeTextX, cardY + 22, 0.4, 0.45, 0.45, 1, UIFont.Small)
    else
        local sourceText = getText("UI_BurdJournals_RecordedRecipe") or "Recorded recipe"
        if data.magazineSource then
            local magazineName = BurdJournals.getMagazineDisplayName(data.magazineSource)
            sourceText = BurdJournals.formatText(getText("UI_BurdJournals_RecipeFromMagazine") or "From: %s", magazineName)
        end
        self:drawText(sourceText, recipeTextX, cardY + 22, 0.4, 0.65, 0.7, 1, UIFont.Small)
    end

    local btnW = 55
    local btnH = 24
    local btnGap = 4
    local hasEraser = BurdJournals.hasEraser(mainPanel.player)
    local rightmostBtnX = cardX + cardW - btnW - 10
    local btnY = cardY + (cardH - btnH) / 2
    local canClaimRecipe = not data.alreadyKnown and not data.isClaimed and not data.isPending
    local showClaimBtn = canClaimRecipe and not isLearningThis
    local eraseBtnX = showClaimBtn and (rightmostBtnX - btnW - btnGap) or rightmostBtnX
    local eraseQueuePos = mainPanel:getEraseQueuePosition(data.recipeName)
    local isEraseQueued = eraseQueuePos ~= nil

    if hasEraser and not isErasingThis then
        if isEraseQueued then
            local queueText = "#" .. eraseQueuePos
            local queueTextW = getTextManager():MeasureStringX(UIFont.Small, queueText)
            self:drawRect(eraseBtnX, btnY, btnW, btnH, 0.5, 0.4, 0.25, 0.25)
            self:drawRectBorder(eraseBtnX, btnY, btnW, btnH, 0.6, 0.6, 0.35, 0.35)
            self:drawText(queueText, eraseBtnX + (btnW - queueTextW) / 2, btnY + 4, 0.9, 0.7, 0.5, 1, UIFont.Small)
        else
            local eraseText = getText("UI_BurdJournals_BtnErase") or "Erase"
            self:drawRect(eraseBtnX, btnY, btnW, btnH, 0.7, 0.5, 0.15, 0.15)
            self:drawRectBorder(eraseBtnX, btnY, btnW, btnH, 0.8, 0.7, 0.25, 0.25)
            mainPanel:drawPillLabelWithPrompt(self, eraseBtnX, btnY, btnW, btnH, eraseText, {r=1, g=0.9, b=0.9, a=1}, "X")
        end
    end

    if showClaimBtn then
        local mainBtnX = rightmostBtnX
        local isInBatch = BurdJournals.isInCurrentAbsorbBatch(learningState, "recipe", data.recipeName)

        if isQueued then
            local btnText = "#" .. queuePosition
            local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
            self:drawRect(mainBtnX, btnY, btnW, btnH, 0.5, 0.3, 0.5, 0.55)
            self:drawRectBorder(mainBtnX, btnY, btnW, btnH, 0.6, 0.4, 0.6, 0.7)
            self:drawText(btnText, mainBtnX + (btnW - btnTextW) / 2, btnY + 4, 0.8, 0.95, 1, 1, UIFont.Small)
        elseif isInBatch then
            local btnText = getText("UI_BurdJournals_BtnBatching") or "BATCH"
            local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
            self:drawRect(mainBtnX, btnY, btnW, btnH, 0.6, 0.45, 0.55, 0.5)
            self:drawRectBorder(mainBtnX, btnY, btnW, btnH, 0.8, 0.55, 0.7, 0.7)
            self:drawText(btnText, mainBtnX + (btnW - btnTextW) / 2, btnY + 4, 0.95, 1, 0.95, 1, UIFont.Small)
        elseif learningState and learningState.active and not learningState.isAbsorbAll then
            local btnText = getText("UI_BurdJournals_BtnQueue")
            local btnTextW = getTextManager():MeasureStringX(UIFont.Small, btnText)
            self:drawRect(mainBtnX, btnY, btnW, btnH, 0.6, 0.25, 0.45, 0.55)
            self:drawRectBorder(mainBtnX, btnY, btnW, btnH, 0.8, 0.35, 0.6, 0.7)
            self:drawText(btnText, mainBtnX + (btnW - btnTextW) / 2, btnY + 4, 0.9, 1, 1, 1, UIFont.Small)
        else
            local btnText = getText("UI_BurdJournals_BtnClaim")
            self:drawRect(mainBtnX, btnY, btnW, btnH, 0.7, 0.2, 0.45, 0.55)
            self:drawRectBorder(mainBtnX, btnY, btnW, btnH, 0.8, 0.3, 0.6, 0.7)
            mainPanel:drawPillLabelWithPrompt(self, mainBtnX, btnY, btnW, btnH, btnText, {r=0.9, g=1, b=1, a=1}, "A")
        end
    end
end

function BurdJournals.doDrawViewStatItem(self, mainPanel, data, textX, textColor, cardX, cardY, cardW, cardH, padding, y, cardMargin)
    local learningState = mainPanel.learningState
    local isLearningThis = learningState and learningState.active and not learningState.isAbsorbAll
        and learningState.statId == data.statId
    local queuePosition = mainPanel:getQueuePosition(data.statId)
    local isQueued = queuePosition ~= nil
    local statName = data.statName or data.statId or "Unknown Stat"

    self:drawText(statName, textX, cardY + 6, textColor.r, textColor.g, textColor.b, 1, UIFont.Small)

    if isLearningThis then
        local progressText = BurdJournals.normalizeProgressPercentLabel(BurdJournals.formatText(getText("UI_BurdJournals_AbsorbingProgress") or "Absorbing... %d%%", math.floor(learningState.progress * 100)))
        local barX = textX + 100
        local barY = cardY + 25
        local barW = cardW - barX - 20
        local barH = 10

        self:drawText(progressText, textX, cardY + 22, 0.3, 0.8, 0.7, 1, UIFont.Small)
        self:drawRect(barX, barY, barW, barH, 0.6, 0.1, 0.1, 0.1)
        self:drawRect(barX, barY, barW * learningState.progress, barH, 0.9, 0.2, 0.7, 0.6)
        self:drawRectBorder(barX, barY, barW, barH, 0.7, 0.4, 0.8, 0.7)
    elseif isQueued then
        local queuedText = BurdJournals.formatText(getText("UI_BurdJournals_QueuedPosition") or "Queued #%d", queuePosition)
        self:drawText(queuedText, textX, cardY + 22, 0.6, 0.75, 0.9, 1, UIFont.Small)
    elseif data.claimReason == "already_claimed" then
        self:drawText(getText("UI_BurdJournals_StatusAlreadyClaimed") or "Already claimed", textX, cardY + 22, 0.5, 0.5, 0.5, 1, UIFont.Small)
    elseif data.claimReason == "not_absorbable" or not data.isAbsorbable then
        local recordedText = BurdJournals.formatText(getText("UI_BurdJournals_RecordedValue") or "Recorded: %s", data.recordedFormatted or "?")
        self:drawText(recordedText, textX, cardY + 22, 0.5, 0.5, 0.5, 1, UIFont.Small)
    else
        local currentValue = tonumber(data.currentValue) or 0
        local recordedValue = tonumber(data.recordedValue) or 0
        local statusText
        local r, g, b

        if currentValue < recordedValue then
            statusText = BurdJournals.formatText(
                getText("UI_BurdJournals_RecordedNotReached") or "Recorded: %s | Current: %s (not there yet)",
                data.recordedFormatted or "?",
                data.currentFormatted or "?"
            )
            r, g, b = 0.55, 0.55, 0.55
        elseif currentValue == recordedValue then
            statusText = BurdJournals.formatText(
                getText("UI_BurdJournals_RecordedAtPoint") or "Recorded: %s | Current: %s (at this point)",
                data.recordedFormatted or "?",
                data.currentFormatted or "?"
            )
            r, g, b = 0.75, 0.72, 0.55
        else
            statusText = BurdJournals.formatText(
                getText("UI_BurdJournals_RecordedSurpassed") or "Recorded: %s | Current: %s (surpassed)",
                data.recordedFormatted or "?",
                data.currentFormatted or "?"
            )
            r, g, b = 0.4, 0.6, 0.4
        end

        self:drawText(statusText, textX, cardY + 22, r, g, b, 1, UIFont.Small)
    end

    local erasingState = mainPanel.erasingState
    local isErasingThis = erasingState and erasingState.active
        and erasingState.entryType == "stat" and erasingState.entryName == data.statId
    local hasEraser = BurdJournals.hasEraser(mainPanel.player)
    local btnW = 55
    local btnH = 22
    local btnGap = 4
    local rightmostBtnX = cardX + cardW - btnW - padding
    local btnY = cardY + (cardH - btnH) / 2
    local showClaimBtn = data.canClaim and not isLearningThis
    local eraseBtnX = showClaimBtn and (rightmostBtnX - btnW - btnGap) or rightmostBtnX
    local eraseQueuePos = mainPanel:getEraseQueuePosition(data.statId)
    local isEraseQueued = eraseQueuePos ~= nil

    if hasEraser and not isErasingThis then
        if isEraseQueued then
            local queueText = "#" .. eraseQueuePos
            local queueTextW = getTextManager():MeasureStringX(UIFont.Small, queueText)
            self:drawRect(eraseBtnX, btnY, btnW, btnH, 0.5, 0.4, 0.25, 0.25)
            self:drawRectBorder(eraseBtnX, btnY, btnW, btnH, 0.6, 0.6, 0.35, 0.35)
            self:drawText(queueText, eraseBtnX + (btnW - queueTextW) / 2, btnY + 4, 0.9, 0.7, 0.5, 1, UIFont.Small)
        else
            local eraseText = getText("UI_BurdJournals_BtnErase") or "Erase"
            self:drawRect(eraseBtnX, btnY, btnW, btnH, 0.7, 0.5, 0.15, 0.15)
            self:drawRectBorder(eraseBtnX, btnY, btnW, btnH, 0.8, 0.7, 0.25, 0.25)
            mainPanel:drawPillLabelWithPrompt(self, eraseBtnX, btnY, btnW, btnH, eraseText, {r=1, g=0.9, b=0.9, a=1}, "X")
        end
    end

    if showClaimBtn then
        local mainBtnX = rightmostBtnX

        if isQueued then
            local queueText = BurdJournals.formatText("#%d", queuePosition)
            local queueTextW = getTextManager():MeasureStringX(UIFont.Small, queueText)
            self:drawRect(mainBtnX, btnY, btnW, btnH, 0.5, 0.4, 0.5, 0.55)
            self:drawRectBorder(mainBtnX, btnY, btnW, btnH, 0.6, 0.5, 0.6, 0.65)
            self:drawText(queueText, mainBtnX + (btnW - queueTextW) / 2, btnY + 4, 0.8, 0.9, 1, 1, UIFont.Small)
        else
            local mx = self:getMouseX()
            local my = self:getMouseY()
            local isHover = mx >= mainBtnX and mx <= mainBtnX + btnW and my >= y + cardMargin + (cardH - btnH) / 2 and my <= y + cardMargin + (cardH - btnH) / 2 + btnH
            local btnText = getText("UI_BurdJournals_Absorb") or "CLAIM"

            if isHover then
                self:drawRect(mainBtnX, btnY, btnW, btnH, 0.9, 0.3, 0.6, 0.4)
            else
                self:drawRect(mainBtnX, btnY, btnW, btnH, 0.7, 0.25, 0.45, 0.35)
            end

            self:drawRectBorder(mainBtnX, btnY, btnW, btnH, 1, 0.4, 0.7, 0.55)
            mainPanel:drawPillLabelWithPrompt(self, mainBtnX, btnY, btnW, btnH, btnText, {r=0.9, g=1, b=1, a=1}, "A")
        end
    end
end
