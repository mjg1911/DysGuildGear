local _, GGM = ...

local function identitiesCompatible(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then return false end
    if left.key ~= right.key or left.name ~= right.name or left.realm ~= right.realm then return false end
    local leftGuid = type(left.guid) == "string" and left.guid or nil
    local rightGuid = type(right.guid) == "string" and right.guid or nil
    return not (leftGuid and rightGuid and leftGuid ~= rightGuid)
end

local function getResponseTime(sync)
    local ok, now = pcall(sync.api.GetTime)
    if not ok or type(now) ~= "number" or now < 0 then return nil, "sync-time-unavailable" end
    return now, nil
end

local function clearExpiredCooldowns(sync, now)
    for requesterKey, targetTimes in pairs(sync.snapshotResponseCooldowns) do
        for targetKey, queuedAt in pairs(targetTimes) do
            if type(queuedAt) ~= "number" or (now >= queuedAt and now - queuedAt >= GGM.SYNC_SNAPSHOT_RESPONSE_COOLDOWN_SECONDS) then
                targetTimes[targetKey] = nil
                sync.snapshotResponseCooldownEntryCount = sync.snapshotResponseCooldownEntryCount - 1
            end
        end
        if next(targetTimes) == nil then sync.snapshotResponseCooldowns[requesterKey] = nil end
    end
end

local function rateLimited(sync, requesterKey, targetKey)
    local targetTimes = sync.snapshotResponseCooldowns[requesterKey]
    return targetTimes and targetTimes[targetKey] ~= nil
end

local function rememberResponse(sync, requesterKey, targetKey, now)
    local targetTimes = sync.snapshotResponseCooldowns[requesterKey]
    if not targetTimes then targetTimes = {}; sync.snapshotResponseCooldowns[requesterKey] = targetTimes end
    targetTimes[targetKey] = now
    sync.snapshotResponseCooldownEntryCount = sync.snapshotResponseCooldownEntryCount + 1
end

local function handleSlotUpdate(sync, sender, message)
    if sender ~= message.identity.key then return nil, "sync-sender-identity-mismatch" end
    local record, recordErr = GGM.GetCompleteCharacterRecord(sync.db, message.identity.key)
    if not record then return nil, recordErr end
    if not identitiesCompatible(record.identity, message.identity) then return nil, "identity-mismatch" end
    local applied, applyErr = GGM.ApplyReceivedCharacterSlot(sync.db, message.identity.key, message.slotKey, message.slotValue, message.confirmedAt, message.confirmedSequence)
    if not applied then return nil, applyErr end
    return "slot-applied", nil
end

local function handleSnapshotRequest(sync, sender, message)
    if sender ~= message.requester.key then return nil, "sync-sender-identity-mismatch" end
    local record, recordErr = GGM.GetCompleteCharacterRecord(sync.db, message.target.key)
    if not record then
        if recordErr == "record-missing" then return "ignored", nil end
        return nil, recordErr
    end
    if not identitiesCompatible(record.identity, message.target) then return "ignored", nil end
    local sequence, sequenceErr = GGM.GetConfirmedSequence(record)
    if sequence == nil then return nil, sequenceErr end
    local payload, encodeErr = GGM.EncodeSyncSnapshotResponse(record.identity, record.gear, sequence)
    if not payload then return nil, encodeErr end
    local now, timeErr = getResponseTime(sync)
    if now == nil then return nil, timeErr end
    clearExpiredCooldowns(sync, now)
    if rateLimited(sync, message.requester.key, message.target.key) then return "ignored", nil end
    if sync.snapshotResponseCooldownEntryCount >= GGM.SYNC_MAX_SNAPSHOT_RESPONSE_COOLDOWN_ENTRIES then return "ignored", nil end
    local queued, queueErr = GGM.SendSyncPayload(sync.transport, payload)
    if not queued then return nil, queueErr end
    rememberResponse(sync, message.requester.key, message.target.key, now)
    return "snapshot-response-queued", nil
end

local function handleSnapshotResponse(sync, message)
    local saved, saveErr = GGM.SaveReceivedCompleteCharacterRecord(sync.db, message.target, message.snapshot, message.confirmedSequence)
    if not saved then return nil, saveErr end
    return "snapshot-saved", nil
end

function GGM.CreateGuildSync(api, db)
    if type(db) ~= "table" or type(db.characters) ~= "table" then return nil, "database-invalid" end
    local sync = { api = api, db = db, transport = nil, snapshotResponseCooldowns = {}, snapshotResponseCooldownEntryCount = 0 }
    local transport, transportErr = GGM.CreateSyncTransport(api, function(sender, payload)
        return GGM.HandleGuildSyncPayload(sync, sender, payload)
    end)
    if not transport then return nil, transportErr end
    sync.transport = transport
    return sync, nil
end

function GGM.RegisterGuildSync(sync)
    return GGM.RegisterSyncPrefix(sync.transport)
end

function GGM.PublishConfirmedSlot(sync, characterKey, slotKey, slotValue, confirmedAt, confirmedSequence)
    local record, recordErr = GGM.GetCompleteCharacterRecord(sync.db, characterKey)
    if not record then return false, recordErr end
    local persistedSequence, sequenceErr = GGM.GetConfirmedSequence(record)
    if persistedSequence == nil then return false, sequenceErr end
    if persistedSequence ~= confirmedSequence then return false, "confirmed-sequence-mismatch" end
    local persistedSlot = record.gear.slots[slotKey]
    if not persistedSlot or not GGM.AreGearSlotValuesEqual(persistedSlot, slotValue) then return false, "confirmed-slot-mismatch" end
    local payload, encodeErr = GGM.EncodeSyncSlotUpdate(record.identity, confirmedSequence, slotKey, slotValue, confirmedAt)
    if not payload then return false, encodeErr end
    return GGM.SendSyncPayload(sync.transport, payload)
end

function GGM.RequestCompleteSnapshot(sync, targetIdentity)
    local requester, requesterErr = GGM.BuildPlayerIdentity(sync.api)
    if not requester then return false, requesterErr end
    local payload, encodeErr = GGM.EncodeSyncSnapshotRequest(requester, targetIdentity)
    if not payload then return false, encodeErr end
    return GGM.SendSyncPayload(sync.transport, payload)
end

function GGM.HandleGuildSyncPayload(sync, sender, payload)
    local message, decodeErr = GGM.DecodeSyncMessage(payload)
    if not message then return nil, decodeErr end
    if message.type == "SLOT_UPDATE" then return handleSlotUpdate(sync, sender, message) end
    if message.type == "SNAPSHOT_REQUEST" then return handleSnapshotRequest(sync, sender, message) end
    if message.type == "SNAPSHOT_RESPONSE" then return handleSnapshotResponse(sync, message) end
    return nil, "sync-message-type-unknown"
end

function GGM.HandleGuildSyncAddonMessage(sync, prefix, text, channel, sender)
    return GGM.HandleSyncTransportMessage(sync.transport, prefix, text, channel, sender)
end
