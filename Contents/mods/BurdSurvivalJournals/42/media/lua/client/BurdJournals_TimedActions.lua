
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISTimedActionQueue"
require "BurdJournals_Shared"

BurdJournals = BurdJournals or {}

local bsjFallbackPrint = print
local RECORD_ALL_ACK_TIMEOUT_MS = 15000

local function getEffectiveRecordBatchSize(mainPanel)
    local batchSize = tonumber(BurdJournals.getSandboxOption("RecordBatchSize"))
        or tonumber(BurdJournals.RECORD_ALL_MP_BATCH_SIZE)
        or 10
    if batchSize < 1 then batchSize = 1 end
    return batchSize
end

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

local function clearRecordAllContinuationWatchdog(panel)
    if not panel then
        return
    end
    local watchdog = panel.recordAllContinuationWatchdog
    if watchdog and watchdog.tick and Events and Events.OnTick then
        Events.OnTick.Remove(watchdog.tick)
    end
    panel.recordAllContinuationWatchdog = nil
end

-- Release only the client-side authority wait. Keep the queued records on the
-- interrupted state so cancellation/error recovery never silently discards the
-- player's remaining work.
function BurdJournals.clearRecordContinuationState(panel, reason)
    if not panel then return false end
    clearRecordAllContinuationWatchdog(panel)
    if panel.recordAllAuthoritySettleTick and Events and Events.OnTick then
        Events.OnTick.Remove(panel.recordAllAuthoritySettleTick)
    end
    panel.recordAllAuthoritySettleTick = nil
    panel.pendingRecordAllContinuation = nil
    panel.pendingRecordSingleContinuation = nil
    panel.pendingRecordAllReconcile = nil
    panel.pendingRecordBulkIntent = nil
    panel.processingRecordQueue = false
    BurdJournals.pendingRecordAllContinuation = nil
    if type(panel.recordingState) == "table" then
        panel.recordingState.active = false
        panel.recordingState.awaitingServerAck = false
        panel.recordingState.timedAction = nil
        panel.recordingState.interrupted = true
        panel.recordingState.terminalReason = tostring(reason or "cancelled")
    end
    return true
end

local function scheduleRecordAllContinuationWatchdog(panel, player)
    if not panel or not player or not Events or not Events.OnTick then
        return
    end

    clearRecordAllContinuationWatchdog(panel)

    local startedAt = getTimestampMs and getTimestampMs() or 0
    local tick
    tick = function()
        if not panel.pendingRecordAllContinuation and not panel.pendingRecordSingleContinuation then
            clearRecordAllContinuationWatchdog(panel)
            return
        end

        local now = getTimestampMs and getTimestampMs() or startedAt
        if now - startedAt < RECORD_ALL_ACK_TIMEOUT_MS then
            return
        end

        local continuation = panel.pendingRecordAllContinuation or panel.pendingRecordSingleContinuation
        clearRecordAllContinuationWatchdog(panel)
        BurdJournals.debugPrint("[BurdJournals] Record All ack watchdog fired after "
            .. tostring(RECORD_ALL_ACK_TIMEOUT_MS) .. "ms; reconciling before retry")

        local journalForSync = panel.journal
        local syncRequested = false
        if journalForSync and BurdJournals.Client and BurdJournals.Client.requestJournalSync then
            local journalData = BurdJournals.getJournalData and BurdJournals.getJournalData(journalForSync) or nil
            syncRequested = BurdJournals.Client.requestJournalSync(journalForSync, "recordAllAckTimeout", journalData, panel.player) == true
        end

        panel.pendingRecordAllContinuation = nil
        panel.pendingRecordSingleContinuation = nil
        BurdJournals.pendingRecordAllContinuation = nil
        if panel.recordingState then
            panel.recordingState.active = false
            panel.recordingState.timedAction = nil
        end
        panel.processingRecordQueue = false
        if syncRequested then
            panel.pendingRecordAllReconcile = {
                journalId = continuation.journalId,
                journalUUID = continuation.journalUUID,
            }
        else
            panel.pendingRecordAllReconcile = nil
            if panel.showFeedback then
                panel:showFeedback(BurdJournals.safeGetText("UI_BurdJournals_JournalSyncFailed", "Error: Journal sync failed"), {r=0.8, g=0.3, b=0.3})
            end
        end
    end

    panel.recordAllContinuationWatchdog = {
        startedAt = startedAt,
        tick = tick,
    }
    Events.OnTick.Add(tick)
end

local function getTooDarkMessage()
    return BurdJournals.safeGetText("ContextMenu_TooDark", "Too dark to read.")
end

local function notifyTooDark(player, reason)
    local message = reason or getTooDarkMessage()
    if HaloTextHelper and HaloTextHelper.addBadText and player then
        HaloTextHelper.addBadText(player, message)
    elseif player and player.Say then
        player:Say(message)
    end
end

local function isJournalLightAllowed(player)
    if not BurdJournals.canUseJournalInCurrentLight then
        return true, nil
    end
    return BurdJournals.canUseJournalInCurrentLight(player)
end

local function isPlayerInVehicleForJournalAction(player)
    if not player or not player.getVehicle then
        return false
    end
    local ok, vehicle = pcall(function()
        return player:getVehicle()
    end)
    return ok and vehicle ~= nil
end

local function configureJournalActionInterrupts(action, player)
    local interruptOnMovement = not isPlayerInVehicleForJournalAction(player)
    action.stopOnWalk = interruptOnMovement
    action.stopOnRun = interruptOnMovement
    action.stopOnAim = interruptOnMovement
end

local function shouldUseJournalActionAnimation(player)
    return not isPlayerInVehicleForJournalAction(player)
end

local function setJournalActionHandModels(action, player, leftHand, rightHand)
    if not action or not action.setOverrideHandModels or isPlayerInVehicleForJournalAction(player) then
        return
    end
    action:setOverrideHandModels(leftHand, rightHand)
end

local function getLootJournalActionText(key, fallback)
    local text = getText and getText(key) or nil
    if text and text ~= "" and text ~= key then
        return text
    end
    return fallback
end

local function showLootJournalActionMessage(player, key, fallback, isError)
    if not player then
        return
    end

    local message = getLootJournalActionText(key, fallback)
    if HaloTextHelper then
        if isError and HaloTextHelper.addBadText then
            HaloTextHelper.addBadText(player, message)
            return
        end
        if not isError and HaloTextHelper.addGoodText then
            HaloTextHelper.addGoodText(player, message)
            return
        end
    end

    if player.Say then
        player:Say(message)
    end
end

local function normalizeLootJournalLookupRequest(journalRequest)
    local request = nil
    if type(journalRequest) == "table" then
        request = {
            journalId = tonumber(journalRequest.journalId),
            journalUUID = type(journalRequest.journalUUID) == "string" and journalRequest.journalUUID ~= ""
                and journalRequest.journalUUID
                or nil,
            journalFingerprint = type(journalRequest.journalFingerprint) == "string" and journalRequest.journalFingerprint ~= ""
                and journalRequest.journalFingerprint
                or nil,
            exactJournalItem = journalRequest.exactJournalItem == true,
        }
    else
        request = {
            journalId = tonumber(journalRequest),
            journalUUID = nil,
            journalFingerprint = nil,
            exactJournalItem = false,
        }
    end

    if not request.journalId and not request.journalUUID and not request.journalFingerprint then
        return nil
    end
    return request
end

local function resolveLootJournalLookup(player, journalRequest)
    local request = normalizeLootJournalLookupRequest(journalRequest)
    if not player or not request then
        return nil, nil
    end

    local journal = nil
    if request.journalId and BurdJournals.findItemByIdInPlayerInventory then
        journal = BurdJournals.findItemByIdInPlayerInventory(player, request.journalId)
    end
    if not journal and not request.exactJournalItem and request.journalUUID and BurdJournals.findJournalByUUIDInPlayerInventory then
        journal = BurdJournals.findJournalByUUIDInPlayerInventory(player, request.journalUUID)
    end
    if not journal and not request.exactJournalItem and request.journalFingerprint and BurdJournals.findJournalByLookupFingerprintInPlayerInventory then
        journal = BurdJournals.findJournalByLookupFingerprintInPlayerInventory(player, request.journalFingerprint)
    end

    return journal, request
end

local function stopTrackedLootJournalSounds(character, trackedSounds)
    if not character or type(trackedSounds) ~= "table" then
        return
    end

    local emitter = character.getEmitter and character:getEmitter() or nil
    if not emitter or not emitter.stopSound then
        return
    end

    for i = 1, #trackedSounds do
        local soundId = trackedSounds[i]
        if soundId and soundId ~= 0 then
            pcall(function()
                emitter:stopSound(soundId)
            end)
        end
    end
end

local function tryPlayLootJournalActionSound(character, soundCandidates, trackedSounds)
    if not character or type(soundCandidates) ~= "table" then
        return false
    end

    local emitter = character.getEmitter and character:getEmitter() or nil
    if not emitter or not emitter.playSound then
        return false
    end

    for i = 1, #soundCandidates do
        local soundName = soundCandidates[i]
        if type(soundName) == "string" and soundName ~= "" then
            local ok, soundId = pcall(function()
                return emitter:playSound(soundName)
            end)
            if ok and (soundId == nil or soundId ~= 0) then
                if type(trackedSounds) == "table" and soundId and soundId ~= 0 then
                    trackedSounds[#trackedSounds + 1] = soundId
                end
                return true
            end
        end
    end

    return false
end

local LOOT_JOURNAL_OPEN_PROFILES = {
    cursed = {
        duration = 5.5,
        command = "openCursedJournal",
        jobTextKey = "UI_BurdJournals_CursedOpeningAction",
        jobTextFallback = "Breaking seal...",
        startTextKey = "UI_BurdJournals_CursedOpeningStart",
        startTextFallback = "You begin breaking the seal...",
        cancelTextKey = "UI_BurdJournals_CursedOpeningCancelled",
        cancelTextFallback = "You stop before the seal breaks.",
        startSounds = {"PaperRip", "RummageInInventory", "PageTurn"},
        progressSounds = {
            {progress = 0.38, candidates = {"BreakMetalItem", "RepairWithWrench", "BuildMetalStructureSmallScrap", "BuildMetalStructureSmall", "PaperRip", "RummageInInventory"}},
            {progress = 0.76, candidates = {"PageTurn", "PaperRip", "RummageInInventory"}},
        },
    },
    yuletide = {
        duration = 5.5,
        command = "openYuletideJournal",
        jobTextKey = "UI_BurdJournals_YuletideUnwrapAction",
        jobTextFallback = "Unwrapping gift...",
        startTextKey = "UI_BurdJournals_YuletideUnwrapStart",
        startTextFallback = "You start unwrapping the gift...",
        cancelTextKey = "UI_BurdJournals_YuletideUnwrapCancelled",
        cancelTextFallback = "You stop unwrapping the gift.",
        startSounds = {"RummageInInventory", "PaperRip", "PageTurn"},
        progressSounds = {
            {progress = 0.36, candidates = {"PaperRip", "PageTurn", "RummageInInventory"}},
            {progress = 0.74, candidates = {"PageTurn", "PaperRip", "RummageInInventory"}},
        },
    },
    sealed = {
        duration = 5.5,
        command = "breakJournalSeal",
        jobTextKey = "UI_BurdJournals_CursedOpeningAction",
        jobTextFallback = "Breaking seal...",
        startTextKey = "UI_BurdJournals_CursedOpeningStart",
        startTextFallback = "You begin breaking the seal...",
        cancelTextKey = "UI_BurdJournals_CursedOpeningCancelled",
        cancelTextFallback = "You stop before the seal breaks.",
        startSounds = {"PaperRip", "RummageInInventory", "PageTurn"},
        progressSounds = {
            {progress = 0.38, candidates = {"BreakMetalItem", "RepairWithWrench", "BuildMetalStructureSmallScrap", "BuildMetalStructureSmall", "PaperRip", "RummageInInventory"}},
            {progress = 0.76, candidates = {"PageTurn", "PaperRip", "RummageInInventory"}},
        },
    },
}

local function getLootJournalOpenProfile(actionKind)
    if actionKind == "yuletide" then return LOOT_JOURNAL_OPEN_PROFILES.yuletide end
    if actionKind == "sealed" then return LOOT_JOURNAL_OPEN_PROFILES.sealed end
    return LOOT_JOURNAL_OPEN_PROFILES.cursed
end

BurdJournals.OpenLootJournalAction = ISBaseTimedAction:derive("BurdJournals_OpenLootJournalAction")

function BurdJournals.OpenLootJournalAction:new(character, journalRequest, actionKind, capturedJournal)
    local profile = getLootJournalOpenProfile(actionKind)
    local o = ISBaseTimedAction.new(self, character)

    o.journalRequest = normalizeLootJournalLookupRequest(journalRequest)
    o.journalId = o.journalRequest and o.journalRequest.journalId or nil
    o.journalUUID = o.journalRequest and o.journalRequest.journalUUID or nil
    o.journalFingerprint = o.journalRequest and o.journalRequest.journalFingerprint or nil
    o.exactJournalItem = o.journalRequest and o.journalRequest.exactJournalItem == true or false
    o.journal = capturedJournal
    o.actionKind = actionKind == "yuletide" and "yuletide" or actionKind == "sealed" and "sealed" or "cursed"
    configureJournalActionInterrupts(o, character)
    o.maxTime = math.floor((tonumber(profile.duration) or 5.5) * 33)
    o._progressSoundIndex = 0
    o._trackedSounds = {}
    o._completed = false

    return o
end

function BurdJournals.OpenLootJournalAction:isValid()
    local player = self.character
    if not player then
        return false
    end

    local journal = resolveLootJournalLookup(player, self)
    if journal then self.journal = journal end
    if self.actionKind == "sealed" then
        return journal ~= nil
            and BurdJournals.getSealedState
            and BurdJournals.getSealedState(journal) == BurdJournals.SEALED_STATE_SEALED
    end
    return journal ~= nil
end

function BurdJournals.OpenLootJournalAction:update()
    self.character:setMetabolicTarget(Metabolics.LightWork)

    local profile = getLootJournalOpenProfile(self.actionKind)
    if self.setJobType then
        self:setJobType(getLootJournalActionText(profile.jobTextKey, profile.jobTextFallback))
    end

    local progress = self.getJobDelta and self:getJobDelta() or 0
    local stages = profile.progressSounds or {}
    while stages[self._progressSoundIndex + 1] and progress >= (stages[self._progressSoundIndex + 1].progress or 1) do
        self._progressSoundIndex = self._progressSoundIndex + 1
        tryPlayLootJournalActionSound(self.character, stages[self._progressSoundIndex].candidates, self._trackedSounds)
    end
end

function BurdJournals.OpenLootJournalAction:start()
    local profile = getLootJournalOpenProfile(self.actionKind)
    local journal = resolveLootJournalLookup(self.character, self)
    if journal then self.journal = journal end

    if shouldUseJournalActionAnimation(self.character) then
        self:setActionAnim("Loot")
        self.character:reportEvent("EventCrafting")
        setJournalActionHandModels(self, self.character, nil, journal)
    end

    showLootJournalActionMessage(self.character, profile.startTextKey, profile.startTextFallback, false)
    tryPlayLootJournalActionSound(self.character, profile.startSounds, self._trackedSounds)
end

function BurdJournals.OpenLootJournalAction:stop()
    local profile = getLootJournalOpenProfile(self.actionKind)

    stopTrackedLootJournalSounds(self.character, self._trackedSounds)
    self._trackedSounds = {}

    if not self._completed then
        showLootJournalActionMessage(self.character, profile.cancelTextKey, profile.cancelTextFallback, true)
    end

    ISBaseTimedAction.stop(self)
end

function BurdJournals.OpenLootJournalAction:perform()
    local player = self.character
    local profile = getLootJournalOpenProfile(self.actionKind)
    local request = normalizeLootJournalLookupRequest(self)
    local liveJournal = resolveLootJournalLookup(player, self)
    if liveJournal then
        local liveData = BurdJournals.getJournalData and BurdJournals.getJournalData(liveJournal) or nil
        request = BurdJournals.buildJournalCommandPayload
            and BurdJournals.buildJournalCommandPayload(liveJournal, liveData, true)
            or {
                journalId = liveJournal.getID and liveJournal:getID() or request.journalId,
                journalUUID = liveData and liveData.uuid or request.journalUUID,
                journalFingerprint = request.journalFingerprint,
            }
    end
    if request then
        request.exactJournalItem = self.exactJournalItem == true
    end

    stopTrackedLootJournalSounds(player, self._trackedSounds)
    self._trackedSounds = {}
    self._completed = true

    if player and request and sendClientCommand then
        sendClientCommand(player, "BurdJournals", profile.command, {
            journalId = request.journalId,
            journalUUID = request.journalUUID,
            journalFingerprint = request.journalFingerprint,
            exactJournalItem = request.exactJournalItem == true,
            confirm = true,
        })
    end

    ISBaseTimedAction.perform(self)
end

function BurdJournals.queueLootJournalOpenAction(player, journalRequest, actionKind)
    if not player or not ISTimedActionQueue or not ISTimedActionQueue.add then
        return false
    end

    local journal, request = resolveLootJournalLookup(player, journalRequest)
    if not journal or not request then
        return false
    end

    local action = BurdJournals.OpenLootJournalAction:new(player, request, actionKind, journal)
    if not action or not action.character then
        return false
    end
    if action.isValid then
        if action:isValid() ~= true then
            return false
        end
    end

    ISTimedActionQueue.add(action)
    return true
end

function BurdJournals.queueBreakJournalSealAction(player, journal)
    if not player or not journal then return false end

    local request = nil
    if type(journal) == "table" and not journal.getModData then
        request = normalizeLootJournalLookupRequest(journal)
    else
        if not BurdJournals.getSealedState
            or BurdJournals.getSealedState(journal) ~= BurdJournals.SEALED_STATE_SEALED then
            return false
        end
        local journalData = BurdJournals.getJournalData and BurdJournals.getJournalData(journal) or nil
        request = BurdJournals.buildJournalCommandPayload
            and BurdJournals.buildJournalCommandPayload(journal, journalData, true)
            or { journalId = journal.getID and journal:getID() or nil, journalUUID = journalData and journalData.uuid or nil, journalFingerprint = nil }
    end
    return BurdJournals.queueLootJournalOpenAction(player, request, "sealed")
end

BurdJournals.ConvertToCleanAction = ISBaseTimedAction:derive("BurdJournals_ConvertToCleanAction")

function BurdJournals.ConvertToCleanAction:new(character, journal)
    local o = ISBaseTimedAction.new(self, character)

    o.journal = journal
    o.journalId = journal and journal.getID and journal:getID() or nil
    configureJournalActionInterrupts(o, character)

    local convertTime = BurdJournals.getSandboxOption("ConvertTime") or 15.0
    o.maxTime = math.floor(convertTime * 33)

    return o
end

function BurdJournals.ConvertToCleanAction:isValid()
    local player = self.character
    if not player then return false end

    local journal = BurdJournals.findItemByIdInPlayerInventory(player, self.journal:getID())
    if not journal then return false end

    if not BurdJournals.isWorn(journal) then return false end

    return BurdJournals.canConvertToClean(player)
end

function BurdJournals.ConvertToCleanAction:update()
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function BurdJournals.ConvertToCleanAction:start()
    self:setActionAnim("Loot")
    self.character:reportEvent("EventCrafting")

    self.sound = self.character:getEmitter():playSound("Sewing")
end

function BurdJournals.ConvertToCleanAction:stop()

    if self.sound and self.sound ~= 0 then
        self.character:getEmitter():stopSound(self.sound)
    end
    ISBaseTimedAction.stop(self)
end

function BurdJournals.ConvertToCleanAction:perform()

    if self.sound and self.sound ~= 0 then
        self.character:getEmitter():stopSound(self.sound)
    end

    local player = self.character

    if BurdJournals.clientShouldUseServerAuthority() then
        local lookupArgs = BurdJournals.buildJournalCommandLookupArgs(self.journal, nil, false)
        sendClientCommand(
            player,
            "BurdJournals",
            "convertToClean",
            lookupArgs
        )
    else

        local inventory = player:getInventory()
        local journal = BurdJournals.findItemByIdInPlayerInventory(player, self.journal:getID())
        if journal then
            local leather = BurdJournals.findRepairItem(player, "leather")
            local thread = BurdJournals.findRepairItem(player, "thread")
            local needle = BurdJournals.findRepairItem(player, "needle")
            if not leather or not thread or not needle then
                ISBaseTimedAction.perform(self)
                return
            end

            local sourceJournalData = nil
            do
                local sourceModData = journal:getModData()
                sourceJournalData = sourceModData and sourceModData.BurdJournals or nil
            end

            local inheritedWasFromBloody = false
            local inheritedWasCleaned = false
            local inheritedRestoredBy = player and player:getUsername() or "Unknown"
            if type(sourceJournalData) == "table" then
                inheritedWasFromBloody = sourceJournalData.wasFromBloody == true or sourceJournalData.isBloody == true
                inheritedWasCleaned = sourceJournalData.wasCleaned == true
                if type(sourceJournalData.restoredBy) == "string" and sourceJournalData.restoredBy ~= "" then
                    inheritedRestoredBy = sourceJournalData.restoredBy
                end
            end

            local cleanJournal = inventory:AddItem("BurdJournals.BlankSurvivalJournal")
            if cleanJournal then
                local modData = cleanJournal:getModData()
                if modData then
                    modData.BurdJournals = {
                        uuid = (BurdJournals.generateUUID and BurdJournals.generateUUID())
                            or ("journal-" .. tostring(getTimestampMs and getTimestampMs() or os.time()) .. "-" .. tostring(cleanJournal:getID())),
                        isWorn = false,
                        isBloody = false,
                        wasFromWorn = true,
                        wasFromBloody = inheritedWasFromBloody,
                        wasRestored = true,
                        wasCleaned = inheritedWasCleaned,
                        restoredBy = inheritedRestoredBy,
                        isPlayerCreated = true,
                    }
                    BurdJournals.updateJournalName(cleanJournal)
                    BurdJournals.updateJournalIcon(cleanJournal)

                    -- Commit only after the replacement is completely ready.
                    inventory:Remove(leather)
                    BurdJournals.consumeItemUses(thread, 1, player)
                    BurdJournals.consumeItemUses(needle, 1, player)
                    inventory:Remove(journal)
                    player:Say(getText("UI_BurdJournals_JournalRestored") or "Journal restored!")
                else
                    inventory:Remove(cleanJournal)
                end
            end
        end
    end

    ISBaseTimedAction.perform(self)
end

BurdJournals.EraseJournalAction = ISBaseTimedAction:derive("BurdJournals_EraseJournalAction")

function BurdJournals.EraseJournalAction:new(character, journal)
    local o = ISBaseTimedAction.new(self, character)

    o.journal = journal
    configureJournalActionInterrupts(o, character)

    local eraseTime = BurdJournals.getSandboxOption("EraseTime") or 10.0
    o.maxTime = math.floor(eraseTime * 33)

    return o
end

function BurdJournals.EraseJournalAction:isValid()
    local player = self.character
    if not player then return false end

    local journal = BurdJournals.findItemByIdInPlayerInventory(player, self.journal:getID())
    if not journal then return false end

    return BurdJournals.hasEraser(player)
end

function BurdJournals.EraseJournalAction:update()
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function BurdJournals.EraseJournalAction:start()
    self:setActionAnim("Loot")
    self.character:reportEvent("EventCrafting")

    self.sound = self.character:getEmitter():playSound("RummageInInventory")
end

function BurdJournals.EraseJournalAction:stop()

    if self.sound and self.sound ~= 0 then
        self.character:getEmitter():stopSound(self.sound)
    end
    ISBaseTimedAction.stop(self)
end

function BurdJournals.EraseJournalAction:perform()

    if self.sound and self.sound ~= 0 then
        self.character:getEmitter():stopSound(self.sound)
    end

    local player = self.character
    local journal = BurdJournals.findItemByIdInPlayerInventory(player, self.journal:getID())

    if not journal then
        ISBaseTimedAction.perform(self)
        return
    end

    if BurdJournals.clientShouldUseServerAuthority() then
        local lookupArgs = BurdJournals.buildJournalCommandLookupArgs(journal, nil, false)
        sendClientCommand(
            player,
            "BurdJournals",
            "eraseJournal",
            lookupArgs
        )
    else

        local inventory = player:getInventory()
        local journalType = journal:getFullType()

        inventory:Remove(journal)

        local blankJournal = inventory:AddItem("BurdJournals.BlankSurvivalJournal")
        if blankJournal then
            local modData = blankJournal:getModData()
            modData.BurdJournals = {
                isWorn = false,
                isBloody = false,
                wasFromBloody = false,
                isPlayerCreated = true,
            }
            BurdJournals.updateJournalName(blankJournal)
            BurdJournals.updateJournalIcon(blankJournal)
        end

        player:Say(getText("UI_BurdJournals_JournalErased") or "Journal erased...")
    end

    ISBaseTimedAction.perform(self)
end

BurdJournals.DisassembleJournalAction = ISBaseTimedAction:derive("BurdJournals_DisassembleJournalAction")

local DISASSEMBLE_JOURNAL_TIME_SECONDS = 30.0
local DISASSEMBLE_JOURNAL_OUTPUT = "Base.SheetPaper2:2|Base.LeatherStrips:1"

function BurdJournals.DisassembleJournalAction:new(character, journal)
    local o = ISBaseTimedAction.new(self, character)

    o.journal = journal
    configureJournalActionInterrupts(o, character)

    local disassembleTime = DISASSEMBLE_JOURNAL_TIME_SECONDS
    o.maxTime = math.floor(disassembleTime * 33)

    return o
end

function BurdJournals.DisassembleJournalAction:isValid()
    local player = self.character
    if not player then return false end

    local journal = BurdJournals.findItemByIdInPlayerInventory(player, self.journal:getID())
    if not journal then return false end

    return BurdJournals.isBlankJournal(journal)
end

function BurdJournals.DisassembleJournalAction:update()
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function BurdJournals.DisassembleJournalAction:start()
    self:setActionAnim("Loot")
    self.character:reportEvent("EventCrafting")

    self.sound = self.character:getEmitter():playSound("PaperRip")
end

function BurdJournals.DisassembleJournalAction:stop()
    if self.sound and self.sound ~= 0 then
        self.character:getEmitter():stopSound(self.sound)
    end
    ISBaseTimedAction.stop(self)
end

function BurdJournals.DisassembleJournalAction:perform()
    if self.sound and self.sound ~= 0 then
        self.character:getEmitter():stopSound(self.sound)
    end

    local player = self.character
    local inventory = player:getInventory()
    local journal = BurdJournals.findItemByIdInPlayerInventory(player, self.journal:getID())

    if not journal then
        ISBaseTimedAction.perform(self)
        return
    end

    inventory:Remove(journal)

    local outputStr = DISASSEMBLE_JOURNAL_OUTPUT
    local outputs = BurdJournals.ContextMenu and BurdJournals.ContextMenu.parseRecipeString and
                    BurdJournals.ContextMenu.parseRecipeString(outputStr) or {}

    local itemsGiven = {}
    for _, mat in ipairs(outputs) do

        if mat.type and not mat.type:match("^tag:") then
            for i = 1, mat.count do
                inventory:AddItem(mat.type)
            end
            table.insert(itemsGiven, mat.count .. "x " .. mat.name)
        end
    end

    if #itemsGiven > 0 then
        local msg = BurdJournals.formatText(getText("UI_BurdJournals_Salvaged") or "Salvaged: %s", table.concat(itemsGiven, ", "))
        if HaloTextHelper and HaloTextHelper.addTextWithArrow then
            HaloTextHelper.addTextWithArrow(player, msg, true, HaloTextHelper.getColorGreen())
        else
            player:Say(msg)
        end
    else
        player:Say(getText("UI_BurdJournals_JournalDisassembled") or "Journal disassembled.")
    end

    ISBaseTimedAction.perform(self)
end

BurdJournals.LearnFromJournalAction = ISBaseTimedAction:derive("BurdJournals_LearnFromJournalAction")

BurdJournals.LearnActionPayloads = BurdJournals.LearnActionPayloads or {}

local function storeLearnActionPayload(rewards, queuedRewards)
    BurdJournals._learnActionPayloadSeq = (tonumber(BurdJournals._learnActionPayloadSeq) or 0) + 1
    local payloadId = "learn-" .. tostring(getTimestampMs and getTimestampMs() or (os and os.time and os.time() or 0)) .. "-" .. tostring(BurdJournals._learnActionPayloadSeq)
    BurdJournals.LearnActionPayloads[payloadId] = {
        rewards = type(rewards) == "table" and rewards or {},
        queuedRewards = type(queuedRewards) == "table" and queuedRewards or {},
    }
    return payloadId
end

local function getLearnActionPayload(action)
    if not action or not action._learnPayloadId then
        return nil
    end
    return BurdJournals.LearnActionPayloads and BurdJournals.LearnActionPayloads[action._learnPayloadId] or nil
end

local function getLearnActionRewards(action)
    local payload = getLearnActionPayload(action)
    if payload and type(payload.rewards) == "table" then
        return payload.rewards
    end
    return type(action and action.rewards) == "table" and action.rewards or {}
end

local function getLearnActionQueuedRewards(action)
    local payload = getLearnActionPayload(action)
    if payload and type(payload.queuedRewards) == "table" then
        return payload.queuedRewards
    end
    return type(action and action.queuedRewards) == "table" and action.queuedRewards or {}
end

local function clearLearnActionPayload(action)
    if action and action._learnPayloadId and BurdJournals.LearnActionPayloads then
        BurdJournals.LearnActionPayloads[action._learnPayloadId] = nil
        action._learnPayloadId = nil
    end
end

local function markPanelRewardsPending(panel, rewards)
    if not panel or type(rewards) ~= "table" then
        return
    end
    panel.pendingClaims = panel.pendingClaims or { skills = {}, traits = {}, recipes = {}, stats = {} }
    panel.pendingClaims.skills = panel.pendingClaims.skills or {}
    panel.pendingClaims.traits = panel.pendingClaims.traits or {}
    panel.pendingClaims.recipes = panel.pendingClaims.recipes or {}
    panel.pendingClaims.stats = panel.pendingClaims.stats or {}
    panel.sessionClaimedSkills = panel.sessionClaimedSkills or {}
    panel.sessionClaimedTraits = panel.sessionClaimedTraits or {}
    panel.sessionClaimedRecipes = panel.sessionClaimedRecipes or {}
    panel.sessionClaimedStats = panel.sessionClaimedStats or {}

    for _, reward in ipairs(rewards) do
        if reward and reward.type == "skill" and reward.name then
            panel.pendingClaims.skills[reward.name] = true
        elseif reward and reward.type == "trait" and reward.name then
            local normalizedTraitId = BurdJournals.normalizeTraitId and BurdJournals.normalizeTraitId(reward.name) or reward.name
            local traitSessionKey = string.lower(tostring(normalizedTraitId or reward.name))
            panel.pendingClaims.traits[reward.name] = true
            panel.pendingClaims.traits[traitSessionKey] = true
        elseif reward and reward.type == "recipe" and reward.name then
            panel.pendingClaims.recipes[reward.name] = true
        elseif reward and reward.type == "stat" and reward.name then
            panel.pendingClaims.stats[reward.name] = true
        end
    end
end

local function markPanelLearningQueued(panel, action, rewards, queuedRewards, isAbsorbAll)
    if not panel then
        return
    end
    local rewardList = type(rewards) == "table" and rewards or {}
    local queuedRewardList = type(queuedRewards) == "table" and queuedRewards or {}
    local firstReward = rewardList[1]
    local existingClaimSessionId = panel.learningState and panel.learningState.claimSessionId or nil
    panel.learningState = {
        active = true,
        skillName = firstReward and firstReward.type == "skill" and firstReward.name or nil,
        traitId = firstReward and firstReward.type == "trait" and firstReward.name or nil,
        forgetTraitId = firstReward and firstReward.type == "forget" and firstReward.name or nil,
        recipeName = firstReward and firstReward.type == "recipe" and firstReward.name or nil,
        statId = firstReward and firstReward.type == "stat" and firstReward.name or nil,
        isAbsorbAll = isAbsorbAll == true,
        progress = 0,
        totalTime = action and action.totalTimeSeconds or 0,
        startTime = getTimestampMs and getTimestampMs() or 0,
        pendingRewards = rewardList,
        currentIndex = 1,
        queue = queuedRewardList,
        timedAction = action,
        claimSessionId = existingClaimSessionId,
        queued = true,
    }
    markPanelRewardsPending(panel, rewardList)
end

function BurdJournals.LearnFromJournalAction:new(character, journal, rewards, isAbsorbAll, mainPanel, queuedRewards)
    local o = ISBaseTimedAction.new(self, character)
    local rewardList = type(rewards) == "table" and rewards or {}
    local queuedRewardList = type(queuedRewards) == "table" and queuedRewards or {}

    o.journal = journal
    o._learnPayloadId = storeLearnActionPayload(rewardList, queuedRewardList)
    o.rewardCount = #rewardList
    o.queuedRewardCount = #queuedRewardList
    o.isAbsorbAll = isAbsorbAll or false
    o.mainPanel = mainPanel
    configureJournalActionInterrupts(o, character)

    local totalTime = 0
    for _, reward in ipairs(rewardList) do
        if reward.type == "skill" then
            totalTime = totalTime + (mainPanel and mainPanel:getSkillLearningTime() or 3.0)
        elseif reward.type == "trait" then
            totalTime = totalTime + (mainPanel and mainPanel:getTraitLearningTime() or 5.0)
        elseif reward.type == "forget" then
            totalTime = totalTime + (mainPanel and mainPanel:getTraitLearningTime() or 5.0)
        elseif reward.type == "recipe" then
            totalTime = totalTime + (mainPanel and mainPanel:getRecipeLearningTime() or 0.7)
        elseif reward.type == "stat" then
            totalTime = totalTime + (mainPanel and mainPanel:getStatLearningTime() or 5.0)
        end
    end

    -- Apply batch time multiplier for "Absorb All" operations with multiple items
    if isAbsorbAll and #rewardList > 1 then
        local batchMultiplier = BurdJournals.getSandboxOption("BatchTimeMultiplier") or 0.25
        totalTime = totalTime * batchMultiplier
    end

    totalTime = math.max(1.0, totalTime)
    o.totalTimeSeconds = totalTime
    o.maxTime = math.floor(totalTime * 33)

    return o
end

function BurdJournals.LearnFromJournalAction:isValid()
    local player = self.character
    if not player then return false end

    local journal = BurdJournals.findItemByIdInPlayerInventory(player, self.journal:getID())
    if not journal then return false end

    local currentPanel = BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance
    if currentPanel then

        if self.mainPanel ~= currentPanel then
            self.mainPanel = currentPanel
        end

        if not currentPanel:isVisible() then
            return false
        end
    elseif self.mainPanel and not self.mainPanel:isVisible() then

        return false
    end

    local canUseLight, lightReason = isJournalLightAllowed(player)
    if not canUseLight then
        if not self._lightWarned then
            notifyTooDark(player, lightReason)
            self._lightWarned = true
        end
        return false
    end

    return true
end

function BurdJournals.LearnFromJournalAction:update()
    self.character:setMetabolicTarget(Metabolics.LightWork)

    if self.mainPanel and self.mainPanel.learningState then
        local progress = self:getJobDelta()
        if self.usesServerBatchProgress == true then
            progress = progress * 0.85
        end
        self.mainPanel.learningState.progress = progress
    end
end

function BurdJournals.LearnFromJournalAction:start()

    if shouldUseJournalActionAnimation(self.character) then
        self:setAnimVariable("ReadType", "book")
        self:setActionAnim(CharacterActionAnims.Read)
        setJournalActionHandModels(self, self.character, nil, self.journal)
        self.character:setReading(true)
        self.character:reportEvent("EventRead")
    end

    self.character:playSound("OpenBook")

    if self.mainPanel then
        local rewards = getLearnActionRewards(self)
        local queuedRewards = getLearnActionQueuedRewards(self)
        local journalData = BurdJournals.getJournalData and BurdJournals.getJournalData(self.journal) or nil
        local hasForgetReward = false
        for _, reward in ipairs(rewards) do
            if reward and reward.type == "forget" then hasForgetReward = true; break end
        end
        self.usesServerBatchProgress = BurdJournals.clientShouldUseServerAuthority()
            and not (journalData and journalData.isDebugSpawned)
            and not hasForgetReward
        markPanelLearningQueued(self.mainPanel, self, rewards, queuedRewards, self.isAbsorbAll)
        if self.mainPanel.learningState then
            self.mainPanel.learningState.queued = false
        end
    end
end

function BurdJournals.LearnFromJournalAction:stop()

    self.character:setReading(false)
    self.character:playSound("CloseBook")

    if self.mainPanel then
        local rewards = getLearnActionRewards(self)
        local queuedRewards = getLearnActionQueuedRewards(self)
        local firstReward = rewards[1]
        local claimSessionId = self.mainPanel.learningState and self.mainPanel.learningState.claimSessionId or nil
        self.mainPanel.learningState = {
            active = false,
            skillName = firstReward and firstReward.type == "skill" and firstReward.name or nil,
            traitId = firstReward and firstReward.type == "trait" and firstReward.name or nil,
            forgetTraitId = firstReward and firstReward.type == "forget" and firstReward.name or nil,
            recipeName = firstReward and firstReward.type == "recipe" and firstReward.name or nil,
            statId = firstReward and firstReward.type == "stat" and firstReward.name or nil,
            isAbsorbAll = self.isAbsorbAll == true,
            progress = 0,
            totalTime = 0,
            startTime = 0,
            pendingRewards = rewards,
            currentIndex = #rewards > 0 and 1 or 0,
            queue = queuedRewards,
            timedAction = nil,
            claimSessionId = claimSessionId,
            interrupted = true,
        }

        if self.mainPanel.refreshCurrentList then
            self.mainPanel:refreshCurrentList()
        end
    end

    clearLearnActionPayload(self)
    ISBaseTimedAction.stop(self)
end

function BurdJournals.LearnFromJournalAction:perform()
    local player = self.character
    local panel = self.mainPanel
    local rewards = getLearnActionRewards(self)
    local queuedRewards = getLearnActionQueuedRewards(self)

    if not player then
        BurdJournals.debugPrint("[BurdJournals] LearnFromJournalAction:perform - no player character, aborting")
        clearLearnActionPayload(self)
        ISBaseTimedAction.perform(self)
        return
    end

    if player.setReading then
        player:setReading(false)
    end
    if player.playSound then
        player:playSound("CloseBook")
    end

    if not panel then
        clearLearnActionPayload(self)
        ISBaseTimedAction.perform(self)
        return
    end

    local isPlayerJournal = panel.isPlayerJournal or panel.mode == "view"
    local claimSessionId = panel.learningState and panel.learningState.claimSessionId or nil
    if not claimSessionId
        and panel.learningState
        and panel.learningState.active
        and BurdJournals.getXPRecoveryMode
        and BurdJournals.getXPRecoveryMode() == 2
        and BurdJournals.getDiminishingTrackingMode
        and BurdJournals.getDiminishingTrackingMode() == 2 then
        local now = getTimestampMs and getTimestampMs() or 0
        local rand = ZombRand and ZombRand(1000000) or math.floor(math.random() * 1000000)
        claimSessionId = tostring(now) .. "-" .. tostring(rand)
        panel.learningState.claimSessionId = claimSessionId
    end

    -- Collect all skill rewards for batch processing
    local skillRewards = {}
    local otherRewards = {}
    local hasForgetReward = false
    
    for _, reward in ipairs(rewards) do
        if reward.type == "skill" then
            table.insert(skillRewards, reward)
        else
            table.insert(otherRewards, reward)
            if reward.type == "forget" then
                hasForgetReward = true
            end
        end
    end
    
    BurdJournals.debugPrint("[BurdJournals] TimedAction: " .. #skillRewards .. " skill rewards, " .. #otherRewards .. " other rewards")
    BurdJournals.debugPrint("[BurdJournals] TimedAction: isPlayerJournal=" .. tostring(isPlayerJournal))

    local isMultiplayerClient = BurdJournals.clientShouldUseServerAuthority()
    local journalData = BurdJournals.getJournalData and BurdJournals.getJournalData(self.journal) or nil
    local lookupArgs = BurdJournals.buildJournalCommandPayload
        and BurdJournals.buildJournalCommandPayload(self.journal, journalData, true)
        or {
            journalId = self.journal and self.journal.getID and self.journal:getID() or nil,
            journalUUID = type(journalData) == "table" and journalData.uuid or nil,
            journalFingerprint = nil,
            journalData = nil,
            itemFullType = self.journal and self.journal.getFullType and self.journal:getFullType() or nil,
        }
    local canUseBatchServerCommand = isMultiplayerClient and not (journalData and journalData.isDebugSpawned)
    local batchRequestSent = false
    local batchRequestId = nil
    local manualSingleQueue = {}
    if self.isAbsorbAll ~= true then
        for _, reward in ipairs(queuedRewards or {}) do manualSingleQueue[#manualSingleQueue + 1] = reward end
        if panel.learningState and type(panel.learningState.queue) == "table" then
            for _, reward in ipairs(panel.learningState.queue) do
                local duplicate = false
                for _, existing in ipairs(manualSingleQueue) do
                    if existing.type == reward.type and existing.name == reward.name then duplicate = true; break end
                end
                if not duplicate then manualSingleQueue[#manualSingleQueue + 1] = reward end
            end
        end
    end
    if canUseBatchServerCommand and hasForgetReward then
        -- Forget-slot claims are single-use and not part of batch claim payloads.
        canUseBatchServerCommand = false
    end

    if canUseBatchServerCommand then
        local batchPayload = {
            journalId = lookupArgs.journalId,
            journalUUID = lookupArgs.journalUUID,
            journalFingerprint = lookupArgs.journalFingerprint,
            journalData = lookupArgs.journalData,
            itemFullType = lookupArgs.itemFullType,
            claimSessionId = claimSessionId,
            skills = {},
            traits = {},
            recipes = {},
            stats = {},
        }

        for _, reward in ipairs(skillRewards) do
            if reward and reward.name then
                table.insert(batchPayload.skills, {skillName = reward.name})
            end
        end
        for _, reward in ipairs(otherRewards) do
            if reward and reward.type == "trait" and reward.name then
                table.insert(batchPayload.traits, reward.name)
            elseif reward and reward.type == "recipe" and reward.name then
                table.insert(batchPayload.recipes, reward.name)
            elseif reward and reward.type == "stat" and reward.name then
                table.insert(batchPayload.stats, {statId = reward.name, value = reward.value})
            end
        end

        local commandName = isPlayerJournal and "batchClaimRewards" or "batchAbsorbRewards"
        BurdJournals.debugPrint("[BurdJournals] TimedAction using " .. commandName
            .. " (skills=" .. tostring(#batchPayload.skills)
            .. ", traits=" .. tostring(#batchPayload.traits)
            .. ", recipes=" .. tostring(#batchPayload.recipes)
            .. ", stats=" .. tostring(#batchPayload.stats) .. ")")
        -- Arm client state before sending. Hosted MP can return the completion
        -- quickly enough that setting these fields afterwards leaves a permanent
        -- reading latch which the response handler never saw.
        panel.pendingBatchRewardMode = isPlayerJournal and "claim" or "absorb"
        batchPayload.requestId = batchPayload.requestId or BurdJournals.Client.createBatchRewardRequestId()
        panel.pendingBatchRewardRequestId = batchPayload.requestId
        panel.isProcessingRewards = true
        markPanelRewardsPending(panel, rewards)
        batchRequestId = batchPayload.requestId
        if self.isAbsorbAll ~= true then
            panel.pendingLearnSingleContinuation = {
                requestId = batchRequestId,
                journalId = lookupArgs.journalId,
                journalUUID = lookupArgs.journalUUID,
                rewards = manualSingleQueue,
            }
            panel.learningState = {
                active = true,
                isAbsorbAll = false,
                awaitingServerAck = true,
                progress = 1,
                pendingRewards = {},
                queue = manualSingleQueue,
                claimSessionId = claimSessionId,
            }
        end
        batchRequestSent = BurdJournals.Client.sendBatchRewardRequest(player, commandName, batchPayload)
        if batchRequestSent and panel.learningState then
            local serverBatchTotal = #batchPayload.skills + #batchPayload.traits
                + #batchPayload.recipes + #batchPayload.stats
            -- The reading action is complete; the same bar now represents the
            -- bounded authoritative server job instead of sitting at 100%.
            panel.learningState.active = true
            panel.learningState.awaitingServerAck = true
            panel.learningState.serverProcessing = true
            panel.learningState.serverProcessed = 0
            panel.learningState.serverTotal = serverBatchTotal
            panel.learningState.serverProgressBase = 0.85
            panel.learningState.progress = panel.learningState.serverProgressBase
        end
        if not batchRequestSent then
            panel.pendingBatchRewardRequestId = nil
            panel.pendingBatchRewardMode = nil
            panel.isProcessingRewards = false
            panel.pendingLearnSingleContinuation = nil
            if panel.learningState then panel.learningState.active = false end
        elseif self.isAbsorbAll and #queuedRewards > 0 then
            -- Do not start another timed action until this server batch is
            -- acknowledged. Pre-queuing let the first completion tear down the
            -- shared learning state underneath the next action.
            panel.pendingLearnAllContinuation = {
                requestId = batchPayload.requestId,
                journalId = lookupArgs.journalId,
                journalUUID = lookupArgs.journalUUID,
                rewards = queuedRewards,
            }
            clearLearnActionPayload(self)
            ISBaseTimedAction.perform(self)
            return
        end
    else
        -- Process skills individually so claim authority always comes from journal data on server.
        for _, reward in ipairs(skillRewards) do
            BurdJournals.debugPrint("[BurdJournals] TimedAction processing skill: " .. tostring(reward.name))
            if isPlayerJournal then
                panel:sendClaimSkill(reward.name, reward.xp, true)
            else
                panel:sendAbsorbSkill(reward.name, reward.xp, true)
            end
        end

        -- Process non-skill rewards (traits, recipes, stats) individually.
        -- Keep this path for debug-spawned journals where server cannot resolve item IDs.
        for _, reward in ipairs(otherRewards) do
            BurdJournals.debugPrint("[BurdJournals] TimedAction processing " .. tostring(reward.type) .. ": " .. tostring(reward.name))
            if reward.type == "trait" then
                if isPlayerJournal then
                    panel:sendClaimTrait(reward.name, true)
                else
                    panel:sendAbsorbTrait(reward.name, true)
                end
            elseif reward.type == "forget" then
                panel:sendClaimForgetSlot(reward.name)
            elseif reward.type == "recipe" then
                if isPlayerJournal then
                    panel:sendClaimRecipe(reward.name, true)
                else
                    panel:sendAbsorbRecipe(reward.name, true)
                end
            elseif reward.type == "stat" then
                panel:sendClaimStat(reward.name, reward.value)
            end
        end
    end

    if not panel:isVisible() or not panel.journal then

        clearLearnActionPayload(self)
        ISBaseTimedAction.perform(self)
        return
    end

    panel:refreshPlayer()
    if isPlayerJournal then
        if panel.refreshJournalData then
            panel:refreshJournalData()
        end
    else
        if panel.refreshAbsorptionList then
            panel:refreshAbsorptionList()
        end
    end

    -- Get batch size for next batch (only matters for isAbsorbAll mode)
    local batchSize = BurdJournals.getSandboxOption("AbsorbBatchSize") or 15
    if batchSize < 1 then batchSize = 1 end

    local savedQueue = {}
    if not self.isAbsorbAll then
        -- For individual clicks, process one-at-a-time queue (legacy behavior)
        for _, item in ipairs(queuedRewards or {}) do
            table.insert(savedQueue, item)
        end

        if panel.learningState and panel.learningState.queue then
            for _, item in ipairs(panel.learningState.queue) do
                local isDupe = false
                for _, existing in ipairs(savedQueue) do
                    if existing.name == item.name then
                        isDupe = true
                        break
                    end
                end
                if not isDupe then
                    table.insert(savedQueue, item)
                end
            end
        end

        if canUseBatchServerCommand and batchRequestSent then
            -- A one-item claim still uses the authoritative batch command in MP.
            -- Wait for that requestId before starting the next manually queued
            -- reward so completion handlers cannot overwrite one another.
            if panel.pendingLearnSingleContinuation then
                panel.pendingLearnSingleContinuation.rewards = savedQueue
            end
            clearLearnActionPayload(self)
            ISBaseTimedAction.perform(self)
            return
        end

        -- Process one item at a time for individual clicks
        if #savedQueue > 0 then
            local nextReward = table.remove(savedQueue, 1)

            panel.learningState = {
                active = true,
                skillName = nextReward.type == "skill" and nextReward.name or nil,
                traitId = nextReward.type == "trait" and nextReward.name or nil,
                forgetTraitId = nextReward.type == "forget" and nextReward.name or nil,
                recipeName = nextReward.type == "recipe" and nextReward.name or nil,
                isAbsorbAll = false,
                progress = 0,
                totalTime = 0,
                startTime = 0,
                pendingRewards = {nextReward},
                currentIndex = 1,
                queue = savedQueue,
                claimSessionId = claimSessionId,
            }

            if panel.skillList and panel.journal then
                panel:refreshPlayer()
                if panel.mode == "view" or panel.isPlayerJournal then
                    panel:populateViewList()
                else
                    panel:populateAbsorptionList()
                end
            end

            local nextRewards = {nextReward}
            local action = BurdJournals.LearnFromJournalAction:new(player, self.journal, nextRewards, false, panel, savedQueue)
            if action and action.character then
                if panel.learningState then
                    panel.learningState.timedAction = action
                end
                ISTimedActionQueue.add(action)
            else
                BurdJournals.debugPrint("[BurdJournals] LearnFromJournalAction:perform - failed to queue next single reward action")
            end

            clearLearnActionPayload(self)
            ISBaseTimedAction.perform(self)
            return
        end
    else
        -- For "Absorb All" mode, process in batches
        savedQueue = queuedRewards or {}

        if #savedQueue > 0 then
            -- Extract next batch
            local nextBatch = {}
            local remaining = {}

            for i, item in ipairs(savedQueue) do
                if i <= batchSize then
                    table.insert(nextBatch, item)
                else
                    table.insert(remaining, item)
                end
            end

            BurdJournals.debugPrint("[BurdJournals] LearnFromJournalAction:perform - Next batch: " .. #nextBatch .. " items, remaining: " .. #remaining)

            local firstReward = nextBatch[1]
            panel.learningState = {
                active = true,
                skillName = firstReward and firstReward.type == "skill" and firstReward.name or nil,
                traitId = firstReward and firstReward.type == "trait" and firstReward.name or nil,
                forgetTraitId = firstReward and firstReward.type == "forget" and firstReward.name or nil,
                recipeName = firstReward and firstReward.type == "recipe" and firstReward.name or nil,
                isAbsorbAll = true,
                progress = 0,
                totalTime = 0,
                startTime = 0,
                pendingRewards = nextBatch,
                currentIndex = 1,
                queue = remaining,
                claimSessionId = claimSessionId,
            }

            if panel.skillList and panel.journal then
                panel:refreshPlayer()
                if panel.mode == "view" or panel.isPlayerJournal then
                    panel:populateViewList()
                else
                    panel:populateAbsorptionList()
                end
            end

            local action = BurdJournals.LearnFromJournalAction:new(player, self.journal, nextBatch, true, panel, remaining)
            if action and action.character then
                if panel.learningState then
                    panel.learningState.timedAction = action
                end
                ISTimedActionQueue.add(action)
            else
                BurdJournals.debugPrint("[BurdJournals] LearnFromJournalAction:perform - failed to queue next absorb-all batch")
            end

            clearLearnActionPayload(self)
            ISBaseTimedAction.perform(self)
            return
        end
    end

    panel.learningCompleted = true
    panel.learningState = {
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

    if panel.playSound and BurdJournals.Sounds then
        panel:playSound(BurdJournals.Sounds.LEARN_COMPLETE)
    end

    if panel.skillList and panel.journal then
        panel:refreshPlayer()
        if panel.mode == "view" or panel.isPlayerJournal then
            panel:populateViewList()
        else
            panel:populateAbsorptionList()
        end
    end
    clearLearnActionPayload(self)

    if panel.refreshJournalData then
        panel:refreshJournalData()
    end
    if panel.checkDissolution then
        panel:checkDissolution(true)
    end

    ISBaseTimedAction.perform(self)
end

BurdJournals.RecordToJournalAction = ISBaseTimedAction:derive("BurdJournals_RecordToJournalAction")

function BurdJournals.RecordToJournalAction:new(character, journal, records, isRecordAll, mainPanel, queuedRecords)
    local o = ISBaseTimedAction.new(self, character)

    o.journal = journal
    o.journalId = journal and journal.getID and journal:getID() or nil
    local journalData = BurdJournals.getJournalData and BurdJournals.getJournalData(journal) or nil
    if type(journalData) == "table" and BurdJournals.resolveJournalUUIDForRuntime then
        o.journalUUID = BurdJournals.resolveJournalUUIDForRuntime(journalData, journal, false)
    else
        o.journalUUID = type(journalData) == "table" and journalData.uuid or nil
    end
    o.records = records or {}
    o.isRecordAll = isRecordAll or false
    o.mainPanel = mainPanel
    o.queuedRecords = queuedRecords or {}
    configureJournalActionInterrupts(o, character)

    local totalTime = 0
    for _, record in ipairs(records) do
        if record.type == "skill" then
            totalTime = totalTime + (mainPanel and mainPanel:getSkillRecordingTime() or 3.0)
        elseif record.type == "trait" then
            totalTime = totalTime + (mainPanel and mainPanel:getTraitRecordingTime() or 5.0)
        elseif record.type == "stat" then
            totalTime = totalTime + (mainPanel and mainPanel:getStatRecordingTime() or 2.0)
        elseif record.type == "recipe" then
            totalTime = totalTime + (mainPanel and mainPanel:getRecipeRecordingTime() or 0.8)
        end
    end

    -- Apply batch time multiplier for "Record All" operations with multiple items
    if isRecordAll and #records > 1 then
        local batchMultiplier = BurdJournals.getSandboxOption("BatchTimeMultiplier") or 0.25
        totalTime = totalTime * batchMultiplier
        if BurdJournals.clientShouldUseServerAuthority() then
            totalTime = math.max(totalTime, tonumber(BurdJournals.RECORD_ALL_MP_MIN_BATCH_SECONDS) or 3.5)
        end
    end

    totalTime = math.max(1.0, totalTime)
    o.totalTimeSeconds = totalTime
    o.maxTime = math.floor(totalTime * 33)

    return o
end

function BurdJournals.RecordToJournalAction:resolveJournalForRecordAction(player, currentPanel)
    if not player then return nil end

    local journal = nil
    if self.journalId and BurdJournals.findItemByIdInPlayerInventory then
        journal = BurdJournals.findItemByIdInPlayerInventory(player, self.journalId)
    end
    if journal then
        self.journal = journal
        self.journalId = journal.getID and journal:getID() or self.journalId
        return journal
    end

    if self.journalUUID and BurdJournals.findJournalByUUIDInPlayerInventory then
        journal = BurdJournals.findJournalByUUIDInPlayerInventory(player, self.journalUUID)
        if journal then
            BurdJournals.debugPrint("[BurdJournals] RecordToJournalAction: resolved journal by UUID after item swap")
            self.journal = journal
            self.journalId = journal.getID and journal:getID() or self.journalId
            return journal
        end
    end

    if currentPanel then
        if currentPanel.pendingNewJournalId and BurdJournals.findItemByIdInPlayerInventory then
            journal = BurdJournals.findItemByIdInPlayerInventory(player, currentPanel.pendingNewJournalId)
            if journal then
                BurdJournals.debugPrint("[BurdJournals] RecordToJournalAction: resolved pending materialized journal")
                currentPanel.journal = journal
                currentPanel.pendingNewJournalId = nil
                currentPanel.pendingRecordJournalData = nil
                self.journal = journal
                self.journalId = journal.getID and journal:getID() or currentPanel.pendingNewJournalId
                return journal
            end
        end

    end

    return nil
end

function BurdJournals.buildRecordProgressCommandPayload(player, journal, records, isRecordAll, recordQueueRemaining)
    if not player or not journal or type(records) ~= "table" or #records <= 0 then
        return nil
    end

    local skillsToRecord = {}
    local traitsToRecord = {}
    local statsToRecord = {}
    local recipesToRecord = {}
    local skillCount = 0
    local traitCount = 0
    local statCount = 0
    local recipeCount = 0

    for _, record in ipairs(records) do
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

            local magazineType = BurdJournals.getMagazineForRecipe and BurdJournals.getMagazineForRecipe(record.name) or nil
            recipesToRecord[record.name] = {
                name = record.name,
                source = magazineType
            }
            recipeCount = recipeCount + 1
        end
    end

    local journalId = journal and journal:getID() or nil
    local journalType = journal and journal:getFullType() or "nil"
    local journalData = BurdJournals.getJournalData and BurdJournals.getJournalData(journal) or nil
    local lookupArgs = BurdJournals.buildJournalCommandPayload
        and BurdJournals.buildJournalCommandPayload(journal, journalData, true)
        or {
            journalId = journalId,
            journalUUID = type(journalData) == "table" and journalData.uuid or nil,
            journalFingerprint = nil,
            journalData = nil,
            itemFullType = journalType,
        }

    if not lookupArgs.journalId and not lookupArgs.journalUUID and not lookupArgs.journalFingerprint then
        bsjWriteLogLine("[BurdJournals] ERROR: Cannot send recordProgress - journal lookup is missing!")
        return nil
    end

    local writingToolPayload = BurdJournals.buildWritingToolCommandPayload
        and BurdJournals.buildWritingToolCommandPayload(player)
        or nil

    return {
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
        isRecordAll = isRecordAll == true,
        recordBatchSize = #(records or {}),
        recordQueueRemaining = math.max(0, tonumber(recordQueueRemaining) or 0),
        _debugSkillCount = skillCount,
        _debugTraitCount = traitCount,
        _debugStatCount = statCount,
        _debugRecipeCount = recipeCount,
        _debugJournalId = journalId,
        _debugJournalType = journalType,
        _lookupJournalUUID = lookupArgs.journalUUID,
    }
end

function BurdJournals.sendRecordProgressCommand(player, journal, records, isRecordAll, recordQueueRemaining)
    local payload = BurdJournals.buildRecordProgressCommandPayload(player, journal, records, isRecordAll, recordQueueRemaining)
    if not payload then
        return nil
    end

    BurdJournals.debugPrint("[BurdJournals] sendRecordProgressCommand - journalId="
        .. tostring(payload._debugJournalId)
        .. ", type=" .. tostring(payload._debugJournalType)
        .. ", skills=" .. tostring(payload._debugSkillCount)
        .. ", traits=" .. tostring(payload._debugTraitCount)
        .. ", recipes=" .. tostring(payload._debugRecipeCount)
        .. ", remaining=" .. tostring(payload.recordQueueRemaining))

    payload._debugSkillCount = nil
    payload._debugTraitCount = nil
    payload._debugStatCount = nil
    payload._debugRecipeCount = nil
    payload._debugJournalId = nil
    payload._debugJournalType = nil
    local lookupJournalUUID = payload._lookupJournalUUID
    payload._lookupJournalUUID = nil

    sendClientCommand(player, "BurdJournals", "recordProgress", payload)
    return payload, lookupJournalUUID
end

function BurdJournals.RecordToJournalAction:isValid()
    local player = self.character
    if not player then
        BurdJournals.debugPrint("[BurdJournals] RecordToJournalAction:isValid FAILED - no player")
        return false
    end

    local currentPanel = BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance
    if currentPanel then

        if self.mainPanel ~= currentPanel then
            self.mainPanel = currentPanel
        end

        if not currentPanel:isVisible() then
            BurdJournals.debugPrint("[BurdJournals] RecordToJournalAction:isValid FAILED - panel not visible")
            return false
        end
    elseif self.mainPanel and not self.mainPanel:isVisible() then

        BurdJournals.debugPrint("[BurdJournals] RecordToJournalAction:isValid FAILED - panel not visible (no global instance)")
        return false
    end

    local journal = self:resolveJournalForRecordAction(player, currentPanel)
    if not journal then

        BurdJournals.debugPrint("[BurdJournals] RecordToJournalAction:isValid FAILED - journal not found in inventory")
        return false
    end

    local requirePen = BurdJournals.getSandboxOption("RequirePenToWrite")
    if requirePen ~= false then
        if not BurdJournals.hasWritingTool(player) then
            BurdJournals.debugPrint("[BurdJournals] RecordToJournalAction:isValid FAILED - no writing tool")
            return false
        end
    end

    local canUseLight, lightReason = isJournalLightAllowed(player)
    if not canUseLight then
        if not self._lightWarned then
            notifyTooDark(player, lightReason)
            self._lightWarned = true
        end
        BurdJournals.debugPrint("[BurdJournals] RecordToJournalAction:isValid FAILED - too dark to read")
        return false
    end

    -- Only log periodically to avoid spam (every ~30 ticks = 1 second)
    if not self._lastValidLog or (getTimestampMs and (getTimestampMs() - self._lastValidLog > 1000)) then
        self._lastValidLog = getTimestampMs and getTimestampMs() or 0
        BurdJournals.debugPrint("[BurdJournals] RecordToJournalAction:isValid PASSED")
    end

    return true
end

function BurdJournals.RecordToJournalAction:update()
    self.character:setMetabolicTarget(Metabolics.LightWork)

    if self.mainPanel and self.mainPanel.recordingState then
        local progress = self:getJobDelta()
        self.mainPanel.recordingState.progress = progress
    end
end

function BurdJournals.RecordToJournalAction:start()
    BurdJournals.debugPrint("[BurdJournals] RecordToJournalAction:start() called with " .. #self.records .. " records")

    if shouldUseJournalActionAnimation(self.character) then
        self:setAnimVariable("ReadType", "book")
        self:setActionAnim(CharacterActionAnims.Read)
        setJournalActionHandModels(self, self.character, nil, self.journal)
        self.character:setReading(true)
        self.character:reportEvent("EventRead")
    end

    self.character:playSound("OpenBook")

    if self.mainPanel then
        local firstRecord = self.records[1]
        self.mainPanel.recordingState = {
            active = true,
            skillName = firstRecord and firstRecord.type == "skill" and firstRecord.name or nil,
            traitId = firstRecord and firstRecord.type == "trait" and firstRecord.name or nil,
            statId = firstRecord and firstRecord.type == "stat" and firstRecord.name or nil,
            recipeName = firstRecord and firstRecord.type == "recipe" and firstRecord.name or nil,
            isRecordAll = self.isRecordAll,
            progress = 0,
            totalTime = self.totalTimeSeconds,
            startTime = getTimestampMs and getTimestampMs() or 0,
            pendingRecords = self.records,
            currentIndex = 1,
            queue = self.queuedRecords,
            timedAction = self,
        }
    end
end

function BurdJournals.RecordToJournalAction:stop()
    BurdJournals.debugPrint("[BurdJournals] RecordToJournalAction:stop() called - ACTION CANCELLED")

    self.character:setReading(false)
    self.character:playSound("CloseBook")

    if self.isRecordAll == true
        and self.journal
        and BurdJournals.Client
        and BurdJournals.Client.requestJournalSync
    then
        local journalData = BurdJournals.getJournalData and BurdJournals.getJournalData(self.journal) or nil
        BurdJournals.Client.requestJournalSync(self.journal, "recordAllCancelled", journalData, self.character)
        BurdJournals.debugPrint("[BurdJournals] RecordToJournalAction:stop() requested record-all cancellation sync")
    end

    if self.mainPanel then
        local records = type(self.records) == "table" and self.records or {}
        local queuedRecords = type(self.queuedRecords) == "table" and self.queuedRecords or {}
        local firstRecord = records[1]
        self.mainPanel.recordingState = {
            active = false,
            skillName = firstRecord and firstRecord.type == "skill" and firstRecord.name or nil,
            traitId = firstRecord and firstRecord.type == "trait" and firstRecord.name or nil,
            statId = firstRecord and firstRecord.type == "stat" and firstRecord.name or nil,
            recipeName = firstRecord and firstRecord.type == "recipe" and firstRecord.name or nil,
            isRecordAll = self.isRecordAll == true,
            progress = 0,
            totalTime = 0,
            startTime = 0,
            pendingRecords = records,
            currentIndex = #records > 0 and 1 or 0,
            queue = queuedRecords,
            timedAction = nil,
            interrupted = true,
        }
        self.mainPanel.processingRecordQueue = false
        self.mainPanel.pendingRecordAllContinuation = nil
        self.mainPanel.pendingRecordSingleContinuation = nil
        BurdJournals.pendingRecordAllContinuation = nil
        clearRecordAllContinuationWatchdog(self.mainPanel)

        if self.mainPanel.refreshCurrentList then
            self.mainPanel:refreshCurrentList()
        end
    end

    ISBaseTimedAction.stop(self)
end

function BurdJournals.RecordToJournalAction:perform()
    BurdJournals.debugPrint("[BurdJournals] RecordToJournalAction:perform() called with " .. #self.records .. " records")

    self.character:setReading(false)
    self.character:playSound("CloseBook")

    local player = self.character
    local panel = self.mainPanel

    if not panel then
        BurdJournals.debugPrint("[BurdJournals] RecordToJournalAction:perform() - no panel, returning early")
        ISBaseTimedAction.perform(self)
        return
    end

    local resolvedJournal = self:resolveJournalForRecordAction(player, panel)
    if resolvedJournal then
        self.journal = resolvedJournal
    end

    local recordsForCommand = self.records or {}

    local skillCount = 0
    local traitCount = 0
    local statCount = 0
    local recipeCount = 0
    for _, record in ipairs(recordsForCommand) do
        if record.type == "skill" then
            skillCount = skillCount + 1
        elseif record.type == "trait" then
            traitCount = traitCount + 1
        elseif record.type == "stat" then
            statCount = statCount + 1
        elseif record.type == "recipe" then
            recipeCount = recipeCount + 1
        end
    end

    panel.pendingRecordFeedback = {
        skills = skillCount,
        traits = traitCount,
        stats = statCount,
        recipes = recipeCount
    }

    local savedQueue = {}
    if not self.isRecordAll then
        for _, item in ipairs(self.queuedRecords or {}) do savedQueue[#savedQueue + 1] = item end
        if panel.recordingState and type(panel.recordingState.queue) == "table" then
            for _, item in ipairs(panel.recordingState.queue) do
                local duplicate = false
                for _, existing in ipairs(savedQueue) do
                    if existing.type == item.type and existing.name == item.name then duplicate = true; break end
                end
                if not duplicate then savedQueue[#savedQueue + 1] = item end
            end
        end
        panel.pendingRecordSingleContinuation = {
            journalId = self.journal and self.journal:getID() or nil,
            journalUUID = self.journalUUID,
            records = savedQueue,
        }
        panel.recordingState = {
            active = true,
            isRecordAll = false,
            awaitingServerAck = true,
            progress = 1,
            pendingRecords = {},
            queue = savedQueue,
        }
        scheduleRecordAllContinuationWatchdog(panel, player)
    end
    local recordQueueRemaining = self.isRecordAll and #(self.queuedRecords or {}) or #savedQueue
    local payload, lookupJournalUUID = BurdJournals.sendRecordProgressCommand(
        player,
        self.journal,
        recordsForCommand,
        self.isRecordAll == true,
        recordQueueRemaining
    )
    if not payload then
        panel.pendingRecordSingleContinuation = nil
        clearRecordAllContinuationWatchdog(panel)
        if panel.recordingState then panel.recordingState.active = false end
        ISBaseTimedAction.perform(self)
        return
    end

    local journalId = self.journal and self.journal:getID() or nil
    BurdJournals.debugPrint("[BurdJournals] RecordToJournalAction:perform() - sendClientCommand completed for journalId=" .. tostring(journalId))

    -- Get batch size for next batch (only matters for isRecordAll mode)
    local batchSize = getEffectiveRecordBatchSize(panel)

    if not self.isRecordAll then
        -- Record All continuation should not rebuild the current list here.
        -- Serialize manually queued singles behind the authoritative response.
        -- Starting the next action here allowed its response to race the entry
        -- delta and materialization from the operation that just completed.
        if panel.pendingRecordSingleContinuation then
            panel.pendingRecordSingleContinuation.journalId = journalId
            panel.pendingRecordSingleContinuation.journalUUID = lookupJournalUUID or self.journalUUID
        end
        ISBaseTimedAction.perform(self)
        return
    else
        -- For "Record All" mode, process in batches. The next batch is queued
        -- after the server ack so later full-data responses cannot overwrite
        -- an earlier lightweight delta with stale journal state.
        savedQueue = self.queuedRecords or {}

        if #savedQueue > 0 then
            -- Extract next batch
            local nextBatch = {}
            local remaining = {}

            for i, item in ipairs(savedQueue) do
                if i <= batchSize then
                    table.insert(nextBatch, item)
                else
                    table.insert(remaining, item)
                end
            end

            BurdJournals.debugPrint("[BurdJournals] RecordToJournalAction:perform - Next batch: " .. #nextBatch .. " items, remaining: " .. #remaining)

            local firstRecord = nextBatch[1]
            panel.recordingState = {
                active = true,
                skillName = firstRecord and firstRecord.type == "skill" and firstRecord.name or nil,
                traitId = firstRecord and firstRecord.type == "trait" and firstRecord.name or nil,
                statId = firstRecord and firstRecord.type == "stat" and firstRecord.name or nil,
                recipeName = firstRecord and firstRecord.type == "recipe" and firstRecord.name or nil,
                isRecordAll = true,
                progress = 0,
                totalTime = 0,
                startTime = 0,
                pendingRecords = nextBatch,
                currentIndex = 1,
                queue = remaining,
            }

            panel.pendingRecordAllContinuation = {
                remaining = savedQueue,
                records = savedQueue,
                journalId = journalId,
                journalUUID = lookupJournalUUID,
            }
            BurdJournals.pendingRecordAllContinuation = panel.pendingRecordAllContinuation
            scheduleRecordAllContinuationWatchdog(panel, player)
            BurdJournals.debugPrint("[BurdJournals] RecordToJournalAction:perform - Waiting for recordSuccess before queueing next record-all batch")

            ISBaseTimedAction.perform(self)
            return
        end
    end

    panel.processingRecordQueue = false
    panel.recordingCompleted = true

    panel.recordingState = {
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

    ISBaseTimedAction.perform(self)
end

function BurdJournals.isRecordAllAuthorityStateConverged(player, journal, args)
    local writingToolState = type(args) == "table" and args.writingToolState or nil
    if type(writingToolState) == "table" and writingToolState.itemId ~= nil then
        local localTool = BurdJournals.findItemByIdInPlayerInventory and BurdJournals.findItemByIdInPlayerInventory(player, writingToolState.itemId) or nil
        if writingToolState.removed == true then
            if localTool then return false end
        elseif not localTool then return false
        elseif writingToolState.usedDelta ~= nil and localTool.getUsedDelta and (tonumber(localTool:getUsedDelta()) or 0) > (tonumber(writingToolState.usedDelta) or 0) + 0.0001 then return false
        elseif writingToolState.drainableUses ~= nil and localTool.getDrainableUsesFloat and (tonumber(localTool:getDrainableUsesFloat()) or 0) > (tonumber(writingToolState.drainableUses) or 0) + 0.0001 then return false end
    end
    local expectedRevision = type(args) == "table" and tonumber(args.entryStoreUpdatedAt) or nil
    if expectedRevision then
        local journalData = journal and BurdJournals.getJournalData and BurdJournals.getJournalData(journal) or nil
        if type(journalData) ~= "table" or journalData.entryStoreEnabled ~= true or (tonumber(journalData.entryStoreUpdatedAt) or 0) < expectedRevision then return false end
    end
    return true
end

function BurdJournals.cancelRecordAllAuthoritySettle(panel)
    if not panel then return end
    local settleTick = panel.recordAllAuthoritySettleTick
    if settleTick and Events and Events.OnTick then
        Events.OnTick.Remove(settleTick)
    end
    panel.recordAllAuthoritySettleTick = nil
    panel.processingRecordQueue = false
    panel.pendingRecordAllContinuation = nil
    BurdJournals.pendingRecordAllContinuation = nil
    if panel.recordingState and panel.recordingState.isRecordAll == true then
        panel.recordingState.active = false
        panel.recordingState.timedAction = nil
        panel.recordingState.interrupted = true
    end
end

function BurdJournals.queueRecordAllContinuationAfterAuthority(panel, player, action, args)
    if BurdJournals.isRecordAllAuthorityStateConverged(player, action and action.journal, args) then ISTimedActionQueue.add(action); return true end
    if not (panel and player and action and Events and Events.OnTick) then return false end
    if panel.recordAllAuthoritySettleTick then
        Events.OnTick.Remove(panel.recordAllAuthoritySettleTick)
        panel.recordAllAuthoritySettleTick = nil
    end
    local startedAt = (getTimestampMs and getTimestampMs()) or ((os.time() or 0) * 1000)
    local tick
    tick = function()
        local currentPanel = BurdJournals.UI and BurdJournals.UI.MainPanel and BurdJournals.UI.MainPanel.instance or nil
        local nowMs = (getTimestampMs and getTimestampMs()) or ((os.time() or 0) * 1000)
        if currentPanel ~= panel
            or (panel.isVisible and not panel:isVisible())
            or not panel.recordingState
            or panel.recordingState.active ~= true
        then
            BurdJournals.cancelRecordAllAuthoritySettle(panel)
            return
        end
        local journal = panel.journal or action.journal
        if BurdJournals.isRecordAllAuthorityStateConverged(player, journal, args) then
            Events.OnTick.Remove(tick); panel.recordAllAuthoritySettleTick = nil; action.journal = journal
            if BurdJournals.getSandboxOption("RequirePenToWrite") and not BurdJournals.hasWritingTool(player) then
                panel.processingRecordQueue = false; if panel.recordingState then panel.recordingState.active = false; panel.recordingState.interrupted = true end
                if panel.showFeedback then panel:showFeedback(getText("UI_BurdJournals_NeedWritingTool") or "You need a pen or pencil to write.", {r=0.8, g=0.3, b=0.3}) end
                return
            end
            ISTimedActionQueue.add(action); BurdJournals.debugPrint("[BurdJournals] Record All authority state converged; started next batch"); return
        end
        if nowMs - startedAt >= 5000 then
            Events.OnTick.Remove(tick); panel.recordAllAuthoritySettleTick = nil; panel.processingRecordQueue = false
            if panel.recordingState then panel.recordingState.active = false; panel.recordingState.interrupted = true end
            if BurdJournals.Client and BurdJournals.Client.requestJournalSync and journal then BurdJournals.Client.requestJournalSync(journal, "recordAllInventorySettleTimeout", nil, player) end
            if panel.showFeedback then panel:showFeedback(getText("UI_BurdJournals_JournalSyncFailed") or "Error: Journal sync failed", {r=0.8, g=0.3, b=0.3}) end
        end
    end
    panel.recordAllAuthoritySettleTick = tick; Events.OnTick.Add(tick)
    BurdJournals.debugPrint("[BurdJournals] Record All waiting for authoritative inventory and journal shell updates")
    return true
end

function BurdJournals.continueRecordSinglesAfterServerAck(panel, player, args)
    if not panel or not player or type(args) ~= "table" or args.isRecordAll == true then return false end
    local continuation = panel.pendingRecordSingleContinuation
    if type(continuation) ~= "table" then return false end

    local expectedUUID = continuation.journalUUID
    local responseUUID = args.journalUUID or args.entryStoreUUID
    if expectedUUID and responseUUID and tostring(expectedUUID) ~= tostring(responseUUID) then
        return false
    end

    clearRecordAllContinuationWatchdog(panel)
    panel.pendingRecordSingleContinuation = nil
    local queue = type(continuation.records) == "table" and continuation.records or {}
    if panel.recordingState and type(panel.recordingState.queue) == "table" then
        queue = panel.recordingState.queue
    end

    if #queue > 0 then
        local nextRecord = table.remove(queue, 1)
        local journal = panel.journal
        if not journal then return false end
        local action = BurdJournals.RecordToJournalAction:new(player, journal, {nextRecord}, false, panel, queue)
        panel.recordingState = {
            active = true,
            isRecordAll = false,
            pendingRecords = {nextRecord},
            currentIndex = 1,
            queue = queue,
            timedAction = action,
        }
        ISTimedActionQueue.add(action)
        return true
    end

    panel.recordingState = { active = false, isRecordAll = false, pendingRecords = {}, queue = {} }
    panel.processingRecordQueue = false
    local bulkIntent = panel.pendingRecordBulkIntent
    panel.pendingRecordBulkIntent = nil
    if type(bulkIntent) == "table" then
        if bulkIntent.mode == "tab" and panel.startRecordingTab then
            panel:startRecordingTab(bulkIntent.tabId)
        elseif panel.startRecordingAll then
            panel:startRecordingAll()
        end
    end
    return true
end

function BurdJournals.continueRecordAllAfterServerAck(panel, player, args)
    if not panel or not player then return false end

    local function rebuildActiveRecordAllRemaining()
        if not panel.recordingState
            or panel.recordingState.active ~= true
            or panel.recordingState.isRecordAll ~= true
        then
            return nil
        end

        local rebuilt = {}
        if type(panel.recordingState.pendingRecords) == "table" then
            for _, record in ipairs(panel.recordingState.pendingRecords) do
                rebuilt[#rebuilt + 1] = record
            end
        end
        if type(panel.recordingState.queue) == "table" then
            for _, record in ipairs(panel.recordingState.queue) do
                rebuilt[#rebuilt + 1] = record
            end
        end
        return #rebuilt > 0 and rebuilt or nil
    end

    local continuation = panel.pendingRecordAllContinuation or BurdJournals.pendingRecordAllContinuation
    if args and args.ackTimedOut == true and type(panel.pendingRecordAllContinuation) ~= "table" and type(BurdJournals.pendingRecordAllContinuation) == "table" then
        panel.pendingRecordAllContinuation = BurdJournals.pendingRecordAllContinuation
    end
    BurdJournals.debugPrint("[BurdJournals] continueRecordAllAfterServerAck: entered isRecordAll="
        .. tostring(args and args.isRecordAll)
        .. ", serverRemaining=" .. tostring(args and args.recordQueueRemaining)
        .. ", hasContinuation=" .. tostring(type(continuation) == "table"))
    if type(continuation) ~= "table"
        and args
        and math.max(0, tonumber(args.recordQueueRemaining) or 0) > 0
        and panel.recordingState
        and panel.recordingState.active == true
        and panel.recordingState.isRecordAll == true
    then
        local rebuiltRecords = rebuildActiveRecordAllRemaining()
        if type(rebuiltRecords) ~= "table" then
            BurdJournals.debugPrint("[BurdJournals] continueRecordAllAfterServerAck: cannot rebuild missing continuation from active record state")
            clearRecordAllContinuationWatchdog(panel)
            return false
        end
        continuation = {
            remaining = rebuiltRecords,
            records = rebuiltRecords,
            journalId = args.newJournalId or args.journalId,
            journalUUID = args.journalUUID,
        }
        panel.pendingRecordAllContinuation = continuation
        BurdJournals.pendingRecordAllContinuation = continuation
        BurdJournals.debugPrint("[BurdJournals] continueRecordAllAfterServerAck: rebuilt missing continuation from active record state")
    end
    if type(continuation) ~= "table" then
        clearRecordAllContinuationWatchdog(panel)
        return false
    end

    local remainingRecords = continuation.remaining or continuation.records
    if type(remainingRecords) ~= "table" or #remainingRecords <= 0 then
        local serverRemaining = args and math.max(0, tonumber(args.recordQueueRemaining) or 0) or 0
        if serverRemaining > 0
            and panel.recordingState
            and panel.recordingState.active == true
            and panel.recordingState.isRecordAll == true
        then
            remainingRecords = rebuildActiveRecordAllRemaining()
        end
        if type(remainingRecords) == "table" and #remainingRecords > 0 then
            continuation.remaining = remainingRecords
            continuation.records = remainingRecords
            panel.pendingRecordAllContinuation = continuation
            BurdJournals.pendingRecordAllContinuation = continuation
            BurdJournals.debugPrint("[BurdJournals] continueRecordAllAfterServerAck: repaired empty continuation from active record state")
        else
            panel.pendingRecordAllContinuation = nil
            BurdJournals.pendingRecordAllContinuation = nil
            clearRecordAllContinuationWatchdog(panel)
            return false
        end
    end

    local responseJournalId = args and (args.newJournalId or args.journalId) or nil
    local responseJournalUUID = args and args.journalUUID or nil
    local uuidMatches = continuation.journalUUID
        and responseJournalUUID
        and tostring(continuation.journalUUID) == tostring(responseJournalUUID)
    if continuation.journalId and responseJournalId and tostring(continuation.journalId) ~= tostring(responseJournalId) and not uuidMatches then
        panel.pendingRecordAllContinuation = nil
        BurdJournals.pendingRecordAllContinuation = nil
        clearRecordAllContinuationWatchdog(panel)
        BurdJournals.debugPrint("[BurdJournals] continueRecordAllAfterServerAck: abandoning continuation for mismatched journalId")
        return false
    end
    if continuation.journalUUID and responseJournalUUID and tostring(continuation.journalUUID) ~= tostring(responseJournalUUID) then
        panel.pendingRecordAllContinuation = nil
        BurdJournals.pendingRecordAllContinuation = nil
        clearRecordAllContinuationWatchdog(panel)
        BurdJournals.debugPrint("[BurdJournals] continueRecordAllAfterServerAck: abandoning continuation for mismatched journalUUID")
        return false
    end

    local batchSize = getEffectiveRecordBatchSize()
    local records = {}
    local remaining = {}
    for i, item in ipairs(remainingRecords) do
        if i <= batchSize then
            records[#records + 1] = item
        else
            remaining[#remaining + 1] = item
        end
    end
    if #records <= 0 then
        panel.pendingRecordAllContinuation = nil
        BurdJournals.pendingRecordAllContinuation = nil
        clearRecordAllContinuationWatchdog(panel)
        return false
    end

    local firstRecord = records[1]
    local journalForNextAction = panel.journal
    if not journalForNextAction and responseJournalId and BurdJournals.findItemById then
        journalForNextAction = BurdJournals.findItemByIdInPlayerInventory(player, responseJournalId)
    end
    if not journalForNextAction and responseJournalUUID and BurdJournals.findJournalByUUIDInPlayerInventory then
        journalForNextAction = BurdJournals.findJournalByUUIDInPlayerInventory(player, responseJournalUUID)
    end
    if journalForNextAction then
        panel.journal = journalForNextAction
    else
        panel.pendingRecordAllContinuation = nil
        BurdJournals.pendingRecordAllContinuation = nil
        clearRecordAllContinuationWatchdog(panel)
        BurdJournals.debugPrint("[BurdJournals] continueRecordAllAfterServerAck: no panel journal for continuation")
        return false
    end

    panel.recordingState = {
        active = true,
        skillName = firstRecord and firstRecord.type == "skill" and firstRecord.name or nil,
        traitId = firstRecord and firstRecord.type == "trait" and firstRecord.name or nil,
        statId = firstRecord and firstRecord.type == "stat" and firstRecord.name or nil,
        recipeName = firstRecord and firstRecord.type == "recipe" and firstRecord.name or nil,
        isRecordAll = true,
        progress = 0,
        totalTime = 0,
        startTime = 0,
        pendingRecords = records,
        currentIndex = 1,
        queue = remaining,
    }

    -- Do not rebuild the record list between Record All batches. On heavily
    -- modded characters, populateRecordList can rescan large recipe/trait sets
    -- and stall the client/network loop while the server is waiting for the next
    -- small intent command.

    panel.pendingRecordAllContinuation = nil
    BurdJournals.pendingRecordAllContinuation = nil
    clearRecordAllContinuationWatchdog(panel)
    local action = BurdJournals.RecordToJournalAction:new(player, journalForNextAction, records, true, panel, remaining)
    if panel.recordingState then
        panel.recordingState.timedAction = action
    end
    if not BurdJournals.queueRecordAllContinuationAfterAuthority(panel, player, action, args) then return false end
    BurdJournals.debugPrint("[BurdJournals] continueRecordAllAfterServerAck: queued or deferred next record-all batch with "
        .. tostring(#records) .. " records, remaining=" .. tostring(#remaining))
    return true
end

function BurdJournals.queueLearnAction(player, journal, rewards, isAbsorbAll, mainPanel)
    if not player or not journal then return false end
    if not rewards or #rewards == 0 then return false end

    local canUseLight, lightReason = isJournalLightAllowed(player)
    if not canUseLight then
        notifyTooDark(player, lightReason)
        -- Return true so callers don't show unrelated "already reading" errors.
        return true
    end

    -- Get batch size from sandbox option (default 15, min 1)
    local batchSize = BurdJournals.getSandboxOption("AbsorbBatchSize") or 15
    if batchSize < 1 then batchSize = 1 end

    if isAbsorbAll and #rewards > 1 then
        -- Extract first batch of rewards
        local batch = {}
        local remaining = {}

        for i, reward in ipairs(rewards) do
            if i <= batchSize then
                table.insert(batch, reward)
            else
                table.insert(remaining, reward)
            end
        end

        BurdJournals.debugPrint("[BurdJournals] queueLearnAction: Batching - batch size=" .. #batch .. ", remaining=" .. #remaining)
        local action = BurdJournals.LearnFromJournalAction:new(
            player, journal, batch, true, mainPanel, remaining
        )
        if action and action.character then
            markPanelLearningQueued(mainPanel, action, batch, remaining, true)
            ISTimedActionQueue.add(action)
        else
            BurdJournals.debugPrint("[BurdJournals] queueLearnAction: FAILED - invalid learn action (missing character)")
            return false
        end
    else
        -- Single item absorbing (individual clicks)
        local action = BurdJournals.LearnFromJournalAction:new(
            player, journal, rewards, isAbsorbAll, mainPanel
        )
        if action and action.character then
            markPanelLearningQueued(mainPanel, action, rewards, {}, isAbsorbAll)
            ISTimedActionQueue.add(action)
        else
            BurdJournals.debugPrint("[BurdJournals] queueLearnAction: FAILED - invalid learn action (missing character)")
            return false
        end
    end
    return true
end

function BurdJournals.continueLearnSinglesAfterServerAck(panel, args)
    local continuation = panel and panel.pendingLearnSingleContinuation or nil
    if type(continuation) ~= "table" or type(args) ~= "table"
        or continuation.requestId ~= args.requestId
    then
        return false
    end

    panel.pendingLearnSingleContinuation = nil
    local remaining = type(continuation.rewards) == "table" and continuation.rewards or {}
    if args.dissolved == true then
        panel.pendingLearnBulkIntent = nil
        return false
    end

    if #remaining > 0 then
        local nextReward = table.remove(remaining, 1)
        local journal = panel.journal
        if not journal then return false end
        local action = BurdJournals.LearnFromJournalAction:new(panel.player, journal, {nextReward}, false, panel, remaining)
        markPanelLearningQueued(panel, action, {nextReward}, remaining, false)
        ISTimedActionQueue.add(action)
        return true
    end

    if panel.learningState then
        panel.learningState.active = false
        panel.learningState.isAbsorbAll = false
    end
    local bulkIntent = panel.pendingLearnBulkIntent
    panel.pendingLearnBulkIntent = nil
    if type(bulkIntent) == "table" then
        if bulkIntent.mode == "tab" and panel.startLearningTab then
            panel:startLearningTab(bulkIntent.tabId)
        elseif panel.startLearningAll then
            panel:startLearningAll()
        end
    end
    return true
end

function BurdJournals.continueLearnAllAfterServerAck(panel, args)
    local continuation = panel and panel.pendingLearnAllContinuation or nil
    if type(continuation) ~= "table" then
        return false
    end
    if type(args) ~= "table" or continuation.requestId ~= args.requestId then
        return false
    end

    panel.pendingLearnAllContinuation = nil
    local remaining = type(continuation.rewards) == "table" and continuation.rewards or {}
    if args.dissolved == true or (args.reason ~= nil and args.reason ~= "complete") then
        return false
    end

    local journal = panel.journal
    if (not journal or not BurdJournals.isValidItem(journal)) and BurdJournals.findItemById then
        journal = BurdJournals.findItemByIdInPlayerInventory(panel.player, (args and args.journalId) or continuation.journalId)
    end
    if (not journal or not BurdJournals.isValidItem(journal))
        and continuation.journalUUID and BurdJournals.findJournalByUUIDInPlayerInventory then
        journal = BurdJournals.findJournalByUUIDInPlayerInventory(panel.player, continuation.journalUUID)
    end
    if not journal or #remaining == 0 then
        return false
    end

    panel.journal = journal
    if panel.learningState then
        panel.learningState.active = false
    end
    local queued = BurdJournals.queueLearnAction(panel.player, journal, remaining, true, panel) == true
    if queued then
        BurdJournals.debugPrint("[BurdJournals] Claim All: queued next acknowledged batch; remaining=" .. tostring(#remaining))
    end
    return queued
end

function BurdJournals.queueRecordAction(player, journal, records, isRecordAll, mainPanel)
    BurdJournals.debugPrint("[BurdJournals] queueRecordAction called with " .. #records .. " records, isRecordAll=" .. tostring(isRecordAll))
    if not player or not journal then
        BurdJournals.debugPrint("[BurdJournals] queueRecordAction: FAILED - player or journal is nil")
        return false
    end
    if not records or #records == 0 then
        BurdJournals.debugPrint("[BurdJournals] queueRecordAction: FAILED - no records to queue")
        return false
    end

    local canUseLight, lightReason = isJournalLightAllowed(player)
    if not canUseLight then
        notifyTooDark(player, lightReason)
        -- Return true so callers don't show unrelated "cannot record" errors.
        return true
    end

    -- Get batch size from sandbox option (default 15, min 1)
    local batchSize = getEffectiveRecordBatchSize()

    if isRecordAll and #records > 1 then
        -- Extract first batch of records
        local batch = {}
        local remaining = {}

        for i, record in ipairs(records) do
            if i <= batchSize then
                table.insert(batch, record)
            else
                table.insert(remaining, record)
            end
        end

        BurdJournals.debugPrint("[BurdJournals] queueRecordAction: Batching - batch size=" .. #batch .. ", remaining=" .. #remaining)
        local action = BurdJournals.RecordToJournalAction:new(
            player, journal, batch, true, mainPanel, remaining
        )
        if action and action.character then
            ISTimedActionQueue.add(action)
        else
            BurdJournals.debugPrint("[BurdJournals] queueRecordAction: FAILED - invalid record action (missing character)")
            return false
        end
        BurdJournals.debugPrint("[BurdJournals] queueRecordAction: Batch action added to queue")
    else
        -- Single item recording (individual clicks)
        BurdJournals.debugPrint("[BurdJournals] queueRecordAction: Single item - " .. tostring(records[1] and records[1].name))
        local action = BurdJournals.RecordToJournalAction:new(
            player, journal, records, isRecordAll, mainPanel
        )
        if action and action.character then
            ISTimedActionQueue.add(action)
        else
            BurdJournals.debugPrint("[BurdJournals] queueRecordAction: FAILED - invalid record action (missing character)")
            return false
        end
        BurdJournals.debugPrint("[BurdJournals] queueRecordAction: Action added to queue")
    end
    return true
end

BurdJournals.EraseEntryAction = ISBaseTimedAction:derive("BurdJournals_EraseEntryAction")

function BurdJournals.EraseEntryAction:new(character, journal, entryType, entryName, mainPanel)
    local o = ISBaseTimedAction.new(self, character)

    o.journal = journal
    o.entryType = entryType
    o.entryName = entryName
    o.mainPanel = mainPanel
    configureJournalActionInterrupts(o, character)

    local eraseTime = 2.0
    o.maxTime = math.floor(eraseTime * 33)

    return o
end

function BurdJournals.EraseEntryAction:isValid()
    local player = self.character
    if not player then return false end

    local journal = BurdJournals.findItemByIdInPlayerInventory(player, self.journal:getID())
    if not journal then return false end

    if not BurdJournals.hasEraser(player) then return false end

    if self.mainPanel and not self.mainPanel:isVisible() then
        return false
    end

    return true
end

function BurdJournals.EraseEntryAction:update()
    self.character:setMetabolicTarget(Metabolics.LightWork)

    if self.mainPanel and self.mainPanel.erasingState then
        local progress = self:getJobDelta()
        self.mainPanel.erasingState.progress = progress
    end
end

function BurdJournals.EraseEntryAction:start()

    if shouldUseJournalActionAnimation(self.character) then
        self:setAnimVariable("ReadType", "book")
        self:setActionAnim(CharacterActionAnims.Read)
        setJournalActionHandModels(self, self.character, nil, self.journal)
        self.character:setReading(true)
        self.character:reportEvent("EventRead")
    end

    self.character:playSound("OpenBook")

    if self.mainPanel then
        -- Preserve the queue when setting erasingState
        local existingQueue = self.mainPanel.erasingState and self.mainPanel.erasingState.queue or {}
        self.mainPanel.erasingState = {
            active = true,
            entryType = self.entryType,
            entryName = self.entryName,
            progress = 0,
            queue = existingQueue,
        }
    end
end

function BurdJournals.EraseEntryAction:stop()

    self.character:setReading(false)
    self.character:playSound("CloseBook")

    if self.mainPanel then
        -- Preserve the queue when resetting erasingState
        local existingQueue = self.mainPanel.erasingState and self.mainPanel.erasingState.queue or {}
        self.mainPanel.erasingState = {
            active = false,
            entryType = nil,
            entryName = nil,
            queue = existingQueue,
        }
    end

    ISBaseTimedAction.stop(self)
end

function BurdJournals.EraseEntryAction:perform()

    self.character:setReading(false)
    self.character:playSound("CloseBook")

    local player = self.character
    local panel = self.mainPanel

    if panel then
        -- Preserve the queue when resetting erasingState
        local existingQueue = panel.erasingState and panel.erasingState.queue or {}
        panel.erasingState = {
            active = false,
            entryType = nil,
            entryName = nil,
            queue = existingQueue,
        }
    end

    -- Check if this is a debug-spawned journal
    -- Debug-spawned journals created on the client can't be found by the server,
    -- so we handle the erase locally (same pattern as claim/absorb operations)
    local journalData = BurdJournals.getJournalData and BurdJournals.getJournalData(self.journal)
    local isDebugSpawned = journalData and journalData.isDebugSpawned

    if BurdJournals.clientShouldUseServerAuthority() then
        if isDebugSpawned then
            -- Debug-spawned journals: erase locally since server can't find them
            BurdJournals.debugPrint("[BurdJournals] Debug-spawned journal - erasing locally")
            if panel and panel.eraseEntryDirectly then
                panel:eraseEntryDirectly(self.entryType, self.entryName)
            end
        else
            -- Normal journals: send to server for authoritative erase
            sendClientCommand(player, "BurdJournals", "eraseEntry", {
                journalId = self.journal:getID(),
                entryType = self.entryType,
                entryName = self.entryName
            })
        end
    else
        -- Single-player/host: erase directly
        if panel and panel.eraseEntryDirectly then
            panel:eraseEntryDirectly(self.entryType, self.entryName)
        end
    end

    -- Process next item in erase queue
    if panel and panel.processNextEraseInQueue then
        panel:processNextEraseInQueue()
    end

    ISBaseTimedAction.perform(self)
end

function BurdJournals.queueEraseAction(player, journal, entryType, entryName, mainPanel)
    if not player or not journal then return false end
    if not entryType or not entryName then return false end

    local action = BurdJournals.EraseEntryAction:new(player, journal, entryType, entryName, mainPanel)
    ISTimedActionQueue.add(action)
    return true
end
