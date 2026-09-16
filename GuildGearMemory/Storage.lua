local _, GGM = ...

local function copyIdentity(identity)
    return {
        key = identity.key,
        name = identity.name,
        realm = identity.realm,
        guid = identity.guid,
    }
end

local function copySlotValue(source)
    return {
        inventorySlotID = source.inventorySlotID,
        itemID = source.itemID,
        itemLink = source.itemLink,
    }
end

local function isTrackedSlotKey(slotKey)
    for _, slot in ipairs(GGM.TRACKED_SLOTS) do
        if slot.key == slotKey then
            return true
        end
    end

    return false
end

local function copySnapshot(snapshot)
    local copied = {
        complete = snapshot.complete,
        capturedAt = snapshot.capturedAt,
        slots = {},
    }

    for _, slot in ipairs(GGM.TRACKED_SLOTS) do
        copied.slots[slot.key] = copySlotValue(snapshot.slots[slot.key])
    end

    return copied
end

local function validateIdentity(identity)
    if type(identity) ~= "table" then
        return false, "identity-invalid"
    end

    if type(identity.key) ~= "string" or identity.key == "" then
        return false, "identity-key-invalid"
    end

    if type(identity.name) ~= "string" or identity.name == "" then
        return false, "identity-name-invalid"
    end

    if type(identity.realm) ~= "string" or identity.realm == "" then
        return false, "identity-realm-invalid"
    end

    return true, nil
end

function GGM.InitializeDatabase(existing)
    if existing == nil then
        return {
            schemaVersion = GGM.SCHEMA_VERSION,
            characters = {},
        }, nil
    end

    if type(existing) ~= "table" then
        return nil, "database-invalid"
    end

    if existing.schemaVersion ~= GGM.SCHEMA_VERSION then
        return nil, "unsupported-schema-version:" .. tostring(existing.schemaVersion)
    end

    if type(existing.characters) ~= "table" then
        return nil, "database-characters-invalid"
    end

    return existing, nil
end

function GGM.SaveCompleteCharacterRecord(db, identity, snapshot)
    if type(db) ~= "table" or type(db.characters) ~= "table" then
        return false, "database-invalid"
    end

    if db.schemaVersion ~= GGM.SCHEMA_VERSION then
        return false, "unsupported-schema-version:" .. tostring(db.schemaVersion)
    end

    local identityValid, identityErr = validateIdentity(identity)
    if not identityValid then
        return false, identityErr
    end

    local snapshotValid, snapshotErr = GGM.ValidateCompleteSnapshot(snapshot)
    if not snapshotValid then
        return false, snapshotErr
    end

    db.characters[identity.key] = {
        complete = true,
        identity = copyIdentity(identity),
        gear = copySnapshot(snapshot),
    }

    return true, nil
end

function GGM.GetCompleteCharacterRecord(db, characterKey)
    if type(db) ~= "table" or type(db.characters) ~= "table" then
        return nil, "database-invalid"
    end

    if db.schemaVersion ~= GGM.SCHEMA_VERSION then
        return nil, "unsupported-schema-version:" .. tostring(db.schemaVersion)
    end

    local record = db.characters[characterKey]
    if type(record) ~= "table" or record.complete ~= true then
        return nil, "record-missing"
    end

    local identityValid, identityErr = validateIdentity(record.identity)
    if not identityValid then
        return nil, identityErr
    end

    if record.identity.key ~= characterKey then
        return nil, "record-key-mismatch"
    end

    local snapshotValid, snapshotErr = GGM.ValidateCompleteSnapshot(record.gear)
    if not snapshotValid then
        return nil, snapshotErr
    end

    return record, nil
end

function GGM.UpdateConfirmedCharacterSlot(db, characterKey, slotKey, slotValue, confirmedAt)
    if not isTrackedSlotKey(slotKey) then
        return false, "tracked-slot-unknown:" .. tostring(slotKey)
    end

    if type(confirmedAt) ~= "number" then
        return false, "confirmed-at-invalid"
    end

    local record, recordErr = GGM.GetCompleteCharacterRecord(db, characterKey)
    if not record then
        return false, recordErr
    end

    local slotValid, slotErr = GGM.ValidateGearSlotValue(slotKey, slotValue)
    if not slotValid then
        return false, slotErr
    end

    local sharedSlot = record.gear.slots[slotKey]
    if slotValue.inventorySlotID ~= sharedSlot.inventorySlotID then
        return false, "snapshot-slot-id-mismatch:" .. slotKey
    end

    record.gear.slots[slotKey] = copySlotValue(slotValue)
    record.gear.capturedAt = confirmedAt

    return true, nil
end
