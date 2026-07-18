if not BurdJournals then BurdJournals = {} end
BurdJournals.UI = BurdJournals.UI or {}
BurdJournals.UI.MainPanel = BurdJournals.UI.MainPanel or {}

require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISModalDialog"
require "ISUI/ISTextEntryBox"

local SKILL_DETAIL_BASE_ROW_HEIGHT = 52
local SKILL_DETAIL_LINE_HEIGHT = 13

local function setChildVisible(child, visible)
    if not child then
        return
    end
    if child.setVisible then
        child:setVisible(visible == true)
    else
        child.visible = visible == true
    end
end

local function makeNotesButton(panel, x, y, w, h, title, callback)
    local button = ISButton:new(x, y, w, h, title, panel, callback)
    button:initialise()
    button:instantiate()
    button.borderColor = {r=0.25, g=0.50, b=0.60, a=1}
    button.backgroundColor = {r=0.10, g=0.22, b=0.28, a=0.85}
    button.textColor = {r=0.92, g=0.96, b=1, a=1}
    panel:addChild(button)
    return button
end

local function serializeNotesPages(notes)
    local parts = {}
    local pages = notes and notes.pages or {}
    for i, text in ipairs(pages) do
        parts[i] = tostring(text or "")
    end
    return table.concat(parts, "\30")
end

local function getReadOnlyNotesFont()
    return (UIFont and (UIFont.Medium or UIFont.Small)) or nil
end

function BurdJournals.UI.MainPanel:formatBatchFooterCount(activeCount, queuedCount, singularKey, pluralKey, singularFallback, pluralFallback)
    activeCount = math.max(0, tonumber(activeCount) or 0)
    queuedCount = math.max(0, tonumber(queuedCount) or 0)
    local activeFormat = activeCount == 1
        and (getText(singularKey) or singularFallback)
        or (getText(pluralKey) or pluralFallback)
    local text = BurdJournals.formatText(activeFormat, activeCount)
    if queuedCount > 0 then
        local queueFormat = getText("UI_BurdJournals_BatchItemsInQueue") or "%d in Queue"
        text = text .. " - " .. BurdJournals.formatText(queueFormat, queuedCount)
    end
    return text
end

function BurdJournals.UI.MainPanel:getEditableNotesDraft(journalData)
    if self.mode ~= "log" then
        local source = journalData
            or self.pendingRecordJournalData
            or (self.journal and BurdJournals.getJournalData and BurdJournals.getJournalData(self.journal))
            or {}
        local draft = BurdJournals.normalizeJournalNotes and BurdJournals.normalizeJournalNotes(source.notes, false) or nil
        if source.isPlayerCreated == true and BurdJournals.sanitizePlayerJournalNotes then
            draft = BurdJournals.sanitizePlayerJournalNotes(draft)
        end
        if type(draft) ~= "table" then
            draft = {pages = {""}}
        end
        if type(draft.pages) ~= "table" or #draft.pages <= 0 then
            draft.pages = {""}
        end
        self.notesDraft = draft
        self.notesPageIndex = math.max(1, math.min(tonumber(self.notesPageIndex) or 1, #draft.pages))
        self.notesLastSavedKey = serializeNotesPages(draft)
        return draft
    end

    if type(self.notesDraft) == "table" then
        return self.notesDraft
    end
    local source = journalData
        or self.pendingRecordJournalData
        or (self.journal and BurdJournals.getJournalData and BurdJournals.getJournalData(self.journal))
        or {}
    self.notesDraft = BurdJournals.normalizeJournalNotes and BurdJournals.normalizeJournalNotes(source.notes, self.mode == "log") or {pages = {""}}
    if source.isPlayerCreated == true and BurdJournals.sanitizePlayerJournalNotes then
        self.notesDraft = BurdJournals.sanitizePlayerJournalNotes(self.notesDraft)
    end
    if type(self.notesDraft) ~= "table" then
        self.notesDraft = {pages = {""}}
    end
    if type(self.notesDraft.pages) ~= "table" or #self.notesDraft.pages <= 0 then
        self.notesDraft.pages = {""}
    end
    self.notesPageIndex = math.max(1, math.min(tonumber(self.notesPageIndex) or 1, #self.notesDraft.pages))
    self.notesLastSavedKey = self.notesLastSavedKey or serializeNotesPages(self.notesDraft)
    return self.notesDraft
end

function BurdJournals.UI.MainPanel:updateCurrentNotesDraftFromEntry()
    if not self.notesTextEntry then
        return false
    end
    local draft = self:getEditableNotesDraft()
    local pageIndex = math.max(1, math.min(tonumber(self.notesPageIndex) or 1, #draft.pages))
    local rawText = self.notesTextEntry.getText and self.notesTextEntry:getText() or ""
    local cleanText = BurdJournals.sanitizeJournalNoteText and BurdJournals.sanitizeJournalNoteText(rawText) or tostring(rawText or "")
    if rawText ~= cleanText and self.notesTextEntry.setText then
        self.notesTextEntry:setText(cleanText)
        if self.showFeedback then
            self:showFeedback(getText("UI_BurdJournals_NotesTooLong") or "Notes were shortened to fit the page limit.", {r=0.9, g=0.72, b=0.45})
        end
    end
    if draft.pages[pageIndex] ~= cleanText then
        draft.pages[pageIndex] = cleanText
        return true
    end
    return false
end

function BurdJournals.UI.MainPanel:getNotesControlRect()
    local x = self.skillList and self.skillList:getX() or 16
    local y = self.skillList and self.skillList:getY() or 170
    local w = self.skillList and self.skillList:getWidth() or (self.width - 32)
    local h = self.skillList and self.skillList:getHeight() or 220
    return x, y, w, h
end

function BurdJournals.UI.MainPanel:ensureNotesControls()
    local x, y, w, h = self:getNotesControlRect()
    local buttonY = y + h - 28
    local textH = math.max(80, h - 36)
    if not self.notesTextEntry then
        self.notesTextEntry = ISTextEntryBox:new("", x, y, w, textH)
        self.notesTextEntry:initialise()
        self.notesTextEntry:instantiate()
        self.notesTextEntry.font = UIFont.Small
        if self.notesTextEntry.setMultipleLine then
            self.notesTextEntry:setMultipleLine(true)
        end
        self.notesTextEntry.onTextChange = function()
            if not self._suppressNotesTextChange then
                self.notesDirty = true
            end
        end
        self:addChild(self.notesTextEntry)
    else
        self.notesTextEntry:setX(x)
        self.notesTextEntry:setY(y)
        self.notesTextEntry:setWidth(w)
        self.notesTextEntry:setHeight(textH)
    end

    if not self.notesPrevBtn then
        self.notesPrevBtn = makeNotesButton(self, x, buttonY, 44, 24, "<", BurdJournals.UI.MainPanel.onNotesPrevPage)
        self.notesNextBtn = makeNotesButton(self, x + 48, buttonY, 44, 24, ">", BurdJournals.UI.MainPanel.onNotesNextPage)
        self.notesAddBtn = makeNotesButton(self, x + w - 176, buttonY, 82, 24, getText("UI_BurdJournals_NotesAddPage") or "Add Page", BurdJournals.UI.MainPanel.onNotesAddPage)
        self.notesDeleteBtn = makeNotesButton(self, x + w - 88, buttonY, 88, 24, getText("UI_BurdJournals_NotesDeletePage") or "Delete", BurdJournals.UI.MainPanel.onNotesDeletePage)
        self.notesPageLabel = ISLabel:new(x + 102, buttonY + 4, 16, "", 0.75, 0.88, 0.95, 1, UIFont.Small, true)
        self:addChild(self.notesPageLabel)
    else
        self.notesPrevBtn:setX(x)
        self.notesPrevBtn:setY(buttonY)
        self.notesNextBtn:setX(x + 48)
        self.notesNextBtn:setY(buttonY)
        self.notesAddBtn:setX(x + w - 176)
        self.notesAddBtn:setY(buttonY)
        self.notesDeleteBtn:setX(x + w - 88)
        self.notesDeleteBtn:setY(buttonY)
        self.notesPageLabel:setX(x + 102)
        self.notesPageLabel:setY(buttonY + 4)
    end
end

function BurdJournals.UI.MainPanel:hideNotesControls()
    setChildVisible(self.notesTextEntry, false)
    setChildVisible(self.notesPrevBtn, false)
    setChildVisible(self.notesNextBtn, false)
    setChildVisible(self.notesAddBtn, false)
    setChildVisible(self.notesDeleteBtn, false)
    setChildVisible(self.notesPageLabel, false)
    setChildVisible(self.skillList, true)
end

function BurdJournals.UI.MainPanel:refreshNotesTab(journalData)
    self:ensureNotesControls()
    setChildVisible(self.skillList, false)
    setChildVisible(self.notesTextEntry, true)
    setChildVisible(self.notesPrevBtn, true)
    setChildVisible(self.notesNextBtn, true)
    setChildVisible(self.notesPageLabel, true)

    local editable = self.mode == "log"
    setChildVisible(self.notesAddBtn, editable)
    setChildVisible(self.notesDeleteBtn, editable)
    self.notesTextEntry.font = editable and UIFont.Small or getReadOnlyNotesFont()
    self.notesTextEntry.backgroundColor = {r=0.02, g=0.04, b=0.05, a=0.75}
    self.notesTextEntry.borderColor = {r=0.25, g=0.50, b=0.60, a=1}
    self.notesTextEntry.textColor = {r=0.92, g=0.96, b=1.0, a=1}
    if self.notesTextEntry.setEditable then
        self.notesTextEntry:setEditable(editable)
    else
        self.notesTextEntry.editable = editable
    end

    if editable and type(self.notesDraft) == "table" then
        self:updateCurrentNotesDraftFromEntry()
    end
    local draft = self:getEditableNotesDraft(journalData)
    self.notesPageIndex = math.max(1, math.min(tonumber(self.notesPageIndex) or 1, #draft.pages))
    local localizedText = nil
    if not editable and BurdJournals.getLocalizedGeneratedLorePage then
        localizedText = BurdJournals.getLocalizedGeneratedLorePage(draft, self.notesPageIndex)
    end
    local text = tostring(localizedText or draft.pages[self.notesPageIndex] or "")
    if self.notesTextEntry.setText and (self.notesTextEntry:getText() or "") ~= text then
        self._suppressNotesTextChange = true
        self.notesTextEntry:setText(text)
        self._suppressNotesTextChange = false
    end

    local pageText = BurdJournals.formatText(getText("UI_BurdJournals_NotesPageLabel") or "Page %d / %d", self.notesPageIndex, #draft.pages)
    if self.notesPageLabel.setName then
        self.notesPageLabel:setName(pageText)
    else
        self.notesPageLabel.name = pageText
    end
    if self.notesPrevBtn then self.notesPrevBtn:setEnable(self.notesPageIndex > 1) end
    if self.notesNextBtn then self.notesNextBtn:setEnable(self.notesPageIndex < #draft.pages) end
    local maxPages = BurdJournals.getJournalNotesMaxPages and BurdJournals.getJournalNotesMaxPages()
        or (BurdJournals.JOURNAL_NOTES_MAX_PAGES or 30)
    if self.notesAddBtn then self.notesAddBtn:setEnable(editable and #draft.pages < maxPages) end
    if self.notesDeleteBtn then self.notesDeleteBtn:setEnable(editable and #draft.pages > 1) end
    if self.setPaginatedListEntries then
        self:setPaginatedListEntries({}, nil)
    end
end

function BurdJournals.UI.MainPanel:saveNotesIfDirty(sourceTag, forceFeedback)
    if self.mode ~= "log" then
        return false
    end
    self:updateCurrentNotesDraftFromEntry()
    local draft = self:getEditableNotesDraft()
    local normalized = BurdJournals.normalizeJournalNotes and BurdJournals.normalizeJournalNotes(draft, false) or draft
    local currentKey = serializeNotesPages(normalized or {pages = {}})
    if currentKey == tostring(self.notesLastSavedKey or "") and forceFeedback ~= true then
        return false
    end
    self.notesLastSavedKey = currentKey

    local journalData = self.pendingRecordJournalData or (self.journal and BurdJournals.getJournalData and BurdJournals.getJournalData(self.journal)) or {}
    journalData.notes = normalized
    self.pendingRecordJournalData = journalData

    local lookupArgs = BurdJournals.buildJournalCommandPayload
        and BurdJournals.buildJournalCommandPayload(self.journal, journalData, true)
        or {
            journalId = self.journal and self.journal.getID and self.journal:getID() or nil,
            journalUUID = journalData and journalData.uuid or nil,
            journalFingerprint = nil,
        }
    lookupArgs.journalData = nil
    lookupArgs.notes = normalized
    lookupArgs.source = sourceTag

    if BurdJournals.Client and BurdJournals.Client.sendToServer then
        self.notesSavePending = BurdJournals.Client.sendToServer("saveJournalNotes", lookupArgs) == true
    else
        self.notesSavePending = false
    end
    if forceFeedback == true and self.showFeedback then
        self:showFeedback(getText("UI_BurdJournals_NotesSaved") or "Notes saved", {r=0.5, g=0.8, b=0.6})
    end
    self.notesDirty = false
    return true
end

function BurdJournals.UI.MainPanel:markNotesSaveAcknowledged()
    self.notesSavePending = false
    if self.pendingNotesContinuation then
        self:continuePendingNotesAction()
    end
end

function BurdJournals.UI.MainPanel:hasUnsavedNotesDraft()
    if self.mode ~= "log" or type(self.notesDraft) ~= "table" then
        return self.notesSavePending == true
    end
    self:updateCurrentNotesDraftFromEntry()
    local normalized = BurdJournals.normalizeJournalNotes and BurdJournals.normalizeJournalNotes(self.notesDraft, false) or self.notesDraft
    local currentKey = serializeNotesPages(normalized or {pages = {}})
    return self.notesSavePending == true or currentKey ~= tostring(self.notesLastSavedKey or "")
end

function BurdJournals.UI.MainPanel:onUnsavedNotesConfirm(button)
    self.notesConfirmDialog = nil
    if not button or button.internal ~= "YES" then
        self.pendingNotesContinuation = nil
        return
    end
    local sent = self:saveNotesIfDirty("beforeRecord", true)
    if not sent or self.notesSavePending ~= true then
        self:continuePendingNotesAction()
    end
end

function BurdJournals.UI.MainPanel:confirmNotesBeforeAction(actionName, tabId)
    if self.mode ~= "log" or not self:hasUnsavedNotesDraft() then
        return false
    end

    self.pendingNotesContinuation = {
        actionName = actionName,
        tabId = tabId,
    }

    if self.notesSavePending == true then
        if self.showFeedback then
            self:showFeedback(getText("UI_BurdJournals_NotesSavingBeforeAction") or "Saving notes before continuing...", {r=0.75, g=0.88, b=1})
        end
        return true
    end

    if not ISModalDialog then
        self:onUnsavedNotesConfirm({internal = "YES"})
        return true
    end

    if self.notesConfirmDialog then
        if self.notesConfirmDialog.bringToTop then
            self.notesConfirmDialog:bringToTop()
        end
        return true
    end

    local prompt = getText("UI_BurdJournals_ConfirmUnsavedNotes") or "You have unsaved journal notes. Save them before recording?"
    local baseX = self.getAbsoluteX and self:getAbsoluteX() or self.x or 0
    local baseY = self.getAbsoluteY and self:getAbsoluteY() or self.y or 0
    local dialog = ISModalDialog:new(
        baseX + 40,
        baseY + 120,
        360,
        150,
        prompt,
        true,
        self,
        BurdJournals.UI.MainPanel.onUnsavedNotesConfirm
    )
    dialog:initialise()
    if dialog.yes and dialog.yes.setTitle then
        dialog.yes:setTitle(getText("UI_BurdJournals_NotesSaveContinue") or "Save & Continue")
    elseif dialog.yes then
        dialog.yes.title = getText("UI_BurdJournals_NotesSaveContinue") or "Save & Continue"
    end
    if dialog.no and dialog.no.setTitle then
        dialog.no:setTitle(getText("UI_BurdJournals_BtnCancel") or "Cancel")
    elseif dialog.no then
        dialog.no.title = getText("UI_BurdJournals_BtnCancel") or "Cancel"
    end
    dialog:addToUIManager()
    self.notesConfirmDialog = dialog
    return true
end

function BurdJournals.UI.MainPanel:continuePendingNotesAction()
    local pending = self.pendingNotesContinuation
    self.pendingNotesContinuation = nil
    if type(pending) ~= "table" then
        return
    end
    if pending.actionName == "recordAll" and self.onRecordAll then
        self:onRecordAll(true)
    elseif pending.actionName == "recordTab" and self.onRecordTab then
        self:onRecordTab(true, pending.tabId)
    elseif pending.actionName == "recordItem" and self.performPrimaryListAction then
        self:performPrimaryListAction(pending.tabId)
    end
end

function BurdJournals.UI.MainPanel:onNotesPrevPage()
    self:saveNotesIfDirty("page")
    local draft = self:getEditableNotesDraft()
    self.notesPageIndex = math.max(1, (tonumber(self.notesPageIndex) or 1) - 1)
    self:refreshNotesTab({notes = draft})
end

function BurdJournals.UI.MainPanel:onNotesNextPage()
    self:saveNotesIfDirty("page")
    local draft = self:getEditableNotesDraft()
    self.notesPageIndex = math.min(#draft.pages, (tonumber(self.notesPageIndex) or 1) + 1)
    self:refreshNotesTab({notes = draft})
end

function BurdJournals.UI.MainPanel:onNotesAddPage()
    self:updateCurrentNotesDraftFromEntry()
    local draft = self:getEditableNotesDraft()
    local maxPages = BurdJournals.getJournalNotesMaxPages and BurdJournals.getJournalNotesMaxPages()
        or (BurdJournals.JOURNAL_NOTES_MAX_PAGES or 30)
    if #draft.pages >= maxPages then
        if self.showFeedback then
            self:showFeedback(getText("UI_BurdJournals_NotesPageLimit") or "Page limit reached", {r=0.9, g=0.72, b=0.45})
        end
        return
    end
    draft.pages[#draft.pages + 1] = ""
    self.notesPageIndex = #draft.pages
    self:refreshNotesTab({notes = draft})
    self:saveNotesIfDirty("addPage")
end

function BurdJournals.UI.MainPanel:onNotesDeletePage()
    self:updateCurrentNotesDraftFromEntry()
    local draft = self:getEditableNotesDraft()
    if #draft.pages <= 1 then
        return
    end
    table.remove(draft.pages, tonumber(self.notesPageIndex) or #draft.pages)
    self.notesPageIndex = math.max(1, math.min(tonumber(self.notesPageIndex) or 1, #draft.pages))
    self:refreshNotesTab({notes = draft})
    self:saveNotesIfDirty("deletePage")
end

local function syncViewRowsListBoxScrollGeometry(listbox)
    if not listbox then
        return
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

function BurdJournals.UI.MainPanel:getSelectedSkillDetailLines()
    if not self.skillList or type(self.skillList.items) ~= "table" then
        return nil
    end
    self._skillDetailSelectedIndex = tonumber(self.skillList.selected) or -1
    self._skillDetailRow = self._skillDetailSelectedIndex >= 1 and self.skillList.items[self._skillDetailSelectedIndex] or nil
    self._skillDetailData = self._skillDetailRow and self._skillDetailRow.item or nil
    if type(self._skillDetailData) ~= "table" or self._skillDetailData.isSkill ~= true then
        return nil
    end
    self._skillDetailLines = BurdJournals.buildSkillDetailLines(
        self._skillDetailData.skillName,
        self._skillDetailData,
        self.journal and BurdJournals.getJournalData and BurdJournals.getJournalData(self.journal) or nil,
        self.player,
        self.mode == "log" and "record" or "view"
    )
    if type(self._skillDetailLines) ~= "table" or #self._skillDetailLines <= 1 then
        return nil
    end
    return self._skillDetailLines
end

function BurdJournals.UI.MainPanel:updateSkillDetailRowHeight()
    if not self.skillList then
        return
    end

    self._skillDetailBaseHeight = tonumber(self.skillList.itemheight) or SKILL_DETAIL_BASE_ROW_HEIGHT
    if self._skillDetailBaseHeight < SKILL_DETAIL_BASE_ROW_HEIGHT then
        self._skillDetailBaseHeight = SKILL_DETAIL_BASE_ROW_HEIGHT
    end
    self._skillDetailSelectedIndex = tonumber(self.skillList.selected) or -1
    local listItems = self.skillList.items or {}
    local selectedRow = self._skillDetailSelectedIndex >= 1 and listItems[self._skillDetailSelectedIndex] or nil
    local selectedData = selectedRow and selectedRow.item or nil
    local journalData = self.journal and BurdJournals.getJournalData and BurdJournals.getJournalData(self.journal) or nil
    local journalUUID = type(journalData) == "table" and journalData.uuid or nil
    local cache = self._skillDetailHeightCache
    if type(cache) == "table"
        and cache.listItems == listItems
        and cache.itemCount == #listItems
        and cache.selectedIndex == self._skillDetailSelectedIndex
        and cache.selectedRow == selectedRow
        and cache.selectedData == selectedData
        and cache.mode == self.mode
        and cache.journalUUID == journalUUID
        and cache.baseHeight == self._skillDetailBaseHeight
    then
        return
    end

    self._skillDetailChanged = false
    self._skillDetailTotalHeight = 0

    for index, row in ipairs(listItems) do
        self._skillDetailTargetHeight = self._skillDetailBaseHeight
        if index == self._skillDetailSelectedIndex and row and row.item and row.item.isSkill then
            self._skillDetailLines = BurdJournals.buildSkillDetailLines(
                row.item.skillName,
                row.item,
                journalData,
                self.player,
                self.mode == "log" and "record" or "view"
            )
            if type(self._skillDetailLines) == "table" and #self._skillDetailLines > 1 then
                self._skillDetailTargetHeight = BurdJournals.getSkillDetailRowHeight(#self._skillDetailLines)
            end
        end

        if row and tonumber(row.height) ~= self._skillDetailTargetHeight then
            row.height = self._skillDetailTargetHeight
            self._skillDetailChanged = true
        end
        self._skillDetailTotalHeight = self._skillDetailTotalHeight + self._skillDetailTargetHeight
    end

    if self._skillDetailChanged then
        self.skillList.itemheight = self._skillDetailBaseHeight
        self.skillList:setScrollHeight(self._skillDetailTotalHeight)
        syncViewRowsListBoxScrollGeometry(self.skillList)
    end

    self._skillDetailLines = nil
    self._skillDetailHeightCache = {
        listItems = listItems,
        itemCount = #listItems,
        selectedIndex = self._skillDetailSelectedIndex,
        selectedRow = selectedRow,
        selectedData = selectedData,
        mode = self.mode,
        journalUUID = journalUUID,
        baseHeight = self._skillDetailBaseHeight,
    }
end

function BurdJournals.UI.MainPanel:drawSkillDetailLines(listbox, data, lines, x, y, maxWidth, font)
    if not listbox or type(lines) ~= "table" or #lines <= 0 then
        return
    end
    self._skillDetailFont = font or UIFont.Small
    self._skillDetailY = y
    for _, line in ipairs(lines) do
        self._skillDetailText = tostring(line or "")
        if BurdJournals.UI and BurdJournals.UI.truncateText then
            self._skillDetailText = BurdJournals.UI.truncateText(
                self._skillDetailText,
                math.max(40, tonumber(maxWidth) or 40),
                self._skillDetailFont
            )
        end
        listbox:drawText(self._skillDetailText, x, self._skillDetailY, 0.55, 0.68, 0.72, 1, self._skillDetailFont)
        self._skillDetailY = self._skillDetailY + SKILL_DETAIL_LINE_HEIGHT
    end
end

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
    local hasEraser = (mainPanel.hasCachedEraser and mainPanel:hasCachedEraser()) or BurdJournals.hasEraser(mainPanel.player)
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
    local magazineTexture = data.magazineTexture or BurdJournals.getMagazineTexture(data.magazineSource)

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
        local sourceText = data.sourceText or (getText("UI_BurdJournals_RecordedRecipe") or "Recorded recipe")
        if not data.sourceText and data.magazineSource then
            local magazineName = BurdJournals.getMagazineDisplayName(data.magazineSource)
            sourceText = BurdJournals.formatText(getText("UI_BurdJournals_RecipeFromMagazine") or "From: %s", magazineName)
        end
        self:drawText(sourceText, recipeTextX, cardY + 22, 0.4, 0.65, 0.7, 1, UIFont.Small)
    end

    local btnW = 55
    local btnH = 24
    local btnGap = 4
    local hasEraser = (mainPanel.hasCachedEraser and mainPanel:hasCachedEraser()) or BurdJournals.hasEraser(mainPanel.player)
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
            local queueTextW = mainPanel:getCachedSmallTextWidth(queueText)
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
            local btnTextW = mainPanel:getCachedSmallTextWidth(btnText)
            self:drawRect(mainBtnX, btnY, btnW, btnH, 0.5, 0.3, 0.5, 0.55)
            self:drawRectBorder(mainBtnX, btnY, btnW, btnH, 0.6, 0.4, 0.6, 0.7)
            self:drawText(btnText, mainBtnX + (btnW - btnTextW) / 2, btnY + 4, 0.8, 0.95, 1, 1, UIFont.Small)
        elseif isInBatch then
            local btnText = getText("UI_BurdJournals_BtnBatching") or "BATCH"
            local btnTextW = mainPanel:getCachedSmallTextWidth(btnText)
            self:drawRect(mainBtnX, btnY, btnW, btnH, 0.6, 0.45, 0.55, 0.5)
            self:drawRectBorder(mainBtnX, btnY, btnW, btnH, 0.8, 0.55, 0.7, 0.7)
            self:drawText(btnText, mainBtnX + (btnW - btnTextW) / 2, btnY + 4, 0.95, 1, 0.95, 1, UIFont.Small)
        elseif learningState and learningState.active and not learningState.isAbsorbAll then
            local btnText = getText("UI_BurdJournals_BtnQueue")
            local btnTextW = mainPanel:getCachedSmallTextWidth(btnText)
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
    local hasEraser = (mainPanel.hasCachedEraser and mainPanel:hasCachedEraser()) or BurdJournals.hasEraser(mainPanel.player)
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
