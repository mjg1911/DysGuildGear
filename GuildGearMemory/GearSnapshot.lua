local _, GGM = ...

local function validateSlotValue(slotKey, slotValue)
    if type(slotValue) ~= "table" then
        return false, "snapshot-slot-missing:" .. slotKey
    end

    if type(slotValue.inventorySlotID) ~= "number" then
        return false, "snapshot-slot-id-invalid:" .. slotKey
    end

    local hasItem = type(slotValue.itemID) == "number"
    local hasLink = type(slotValue.itemLink) == "string" and slotValue.itemLink ~= ""
    local isEmpty = slotValue.itemID == false and slotValue.itemLink == false

    if hasItem and hasLink then
        return true, nil
    end

    if isEmpty then
        return true, nil
    end

    return false, "snapshot-slot-value-invalid:" .. slotKey
end

function GGM.ValidateCompleteSnapshot(snapshot)
    if type(snapshot) ~= "table" then
        return false, "snapshot-invalid"
    end

    if snapshot.complete ~= true then
        return false, "snapshot-not-complete"
    end

    if type(snapshot.capturedAt) ~= "number" then
        return false, "snapshot-captured-at-invalid"
    end

    if type(snapshot.slots) ~= "table" then
        return false, "snapshot-slots-invalid"
    end

    for _, slot in ipairs(GGM.TRACKED_SLOTS) do
        local valid, err = validateSlotValue(slot.key, snapshot.slots[slot.key])
        if not valid then
            return false, err
        end
    end

    return true, nil
end

function GGM.CapturePlayerGearSnapshot(api)
    local snapshot = {
        complete = true,
        capturedAt = api.GetServerTime(),
        slots = {},
    }

    for _, slot in ipairs(GGM.TRACKED_SLOTS) do
        local inventorySlotID = api.GetInventorySlotInfo(slot.inventoryName)
        if type(inventorySlotID) ~= "number" then
            return nil, "inventory-slot-unavailable:" .. slot.key
        end

        local itemID = api.GetInventoryItemID("player", inventorySlotID)
        local itemLink = api.GetInventoryItemLink("player", inventorySlotID)

        if itemID ~= nil and itemLink == nil then
            return nil, "item-link-unavailable:" .. slot.key
        end

        if itemID == nil and itemLink ~= nil then
            return nil, "item-id-unavailable:" .. slot.key
        end

        snapshot.slots[slot.key] = {
            inventorySlotID = inventorySlotID,
            itemID = itemID or false,
            itemLink = itemLink or false,
        }
    end

    local valid, err = GGM.ValidateCompleteSnapshot(snapshot)
    if not valid then
        return nil, err
    end

    return snapshot, nil
end
