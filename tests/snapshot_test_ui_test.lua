local T = require("tests.testlib")

local function loadUI()
    local GGM = {}
    T.loadAddonFile("GuildGearMemory/Constants.lua", GGM)
    T.loadAddonFile("GuildGearMemory/SnapshotTestUI.lua", GGM)
    return GGM
end

local function makeRecord(GGM)
    local slots = {}

    for index, slot in ipairs(GGM.TRACKED_SLOTS) do
        slots[slot.key] = {
            inventorySlotID = index,
            itemID = 4000 + index,
            itemLink = "|Hitem:" .. tostring(4000 + index) .. "|h[Test " .. slot.key .. "]|h",
        }
    end

    return {
        complete = true,
        identity = {
            key = "Alice-Silvermoon",
            name = "Alice",
            realm = "Silvermoon",
            guid = "Player-1234-ABCDEF",
        },
        gear = {
            complete = true,
            capturedAt = 1700000100,
            slots = slots,
        },
    }
end

local function newTextControl()
    return {
        text = nil,
        visible = false,
        SetText = function(self, text)
            self.text = text
        end,
        Show = function(self)
            self.visible = true
        end,
        Hide = function(self)
            self.visible = false
        end,
    }
end

local function newRenderableFrame(GGM)
    local frame = {
        emptyState = newTextControl(),
        characterLine = newTextControl(),
        realmLine = newTextControl(),
        capturedLine = newTextControl(),
        completenessLine = newTextControl(),
        slotRows = {},
        shown = false,
    }

    for _ = 1, #GGM.TRACKED_SLOTS do
        table.insert(frame.slotRows, newTextControl())
    end

    function frame:Show()
        self.shown = true
    end

    return frame
end

T.test("snapshot view model exposes saved identity time completeness and every tracked slot", function()
    local GGM = loadUI()
    local record = makeRecord(GGM)

    local model = GGM.BuildSnapshotViewModel(record, function(format, timestamp)
        T.assertEqual(format, "%Y-%m-%d %H:%M:%S")
        T.assertEqual(timestamp, 1700000100)
        return "2023-11-14 22:15:00"
    end)

    T.assertTrue(model.hasSnapshot)
    T.assertEqual(model.characterName, "Alice")
    T.assertEqual(model.realm, "Silvermoon")
    T.assertEqual(model.capturedAtText, "2023-11-14 22:15:00")
    T.assertEqual(model.completenessText, "Complete")
    T.assertEqual(#model.slots, #GGM.TRACKED_SLOTS)
    T.assertEqual(model.slots[1].key, "HEAD")
    T.assertEqual(model.slots[1].valueText, record.gear.slots.HEAD.itemLink)
end)

T.test("snapshot view model displays an empty saved equipment slot explicitly", function()
    local GGM = loadUI()
    local record = makeRecord(GGM)
    record.gear.slots.OFF_HAND.itemID = false
    record.gear.slots.OFF_HAND.itemLink = false

    local model = GGM.BuildSnapshotViewModel(record)

    local offHand
    for _, slot in ipairs(model.slots) do
        if slot.key == "OFF_HAND" then
            offHand = slot
            break
        end
    end

    T.assertNotNil(offHand)
    T.assertEqual(offHand.valueText, "Empty")
end)

T.test("missing or incomplete records become the no saved snapshot state", function()
    local GGM = loadUI()

    local missing = GGM.BuildSnapshotViewModel(nil)
    T.assertFalse(missing.hasSnapshot)
    T.assertEqual(missing.emptyStateText, "No saved snapshot")

    local incomplete = makeRecord(GGM)
    incomplete.complete = false

    local invalid = GGM.BuildSnapshotViewModel(incomplete)
    T.assertFalse(invalid.hasSnapshot)
    T.assertEqual(invalid.emptyStateText, "No saved snapshot")
end)

T.test("malformed identity records become the no saved snapshot state", function()
    local GGM = loadUI()
    local cases = {
        function(record) record.identity.key = "" end,
        function(record) record.identity.key = false end,
        function(record) record.identity.name = "" end,
        function(record) record.identity.realm = false end,
    }

    for _, makeMalformed in ipairs(cases) do
        local record = makeRecord(GGM)
        makeMalformed(record)
        local model = GGM.BuildSnapshotViewModel(record)
        T.assertFalse(model.hasSnapshot)
        T.assertEqual(model.emptyStateText, "No saved snapshot")
    end
end)

T.test("malformed slot records become the no saved snapshot state", function()
    local GGM = loadUI()
    local cases = {
        function(slot) slot.inventorySlotID = "1" end,
        function(slot) slot.itemID = 4001; slot.itemLink = false end,
        function(slot) slot.itemID = false; slot.itemLink = "not-empty" end,
        function(slot) slot.itemID = nil; slot.itemLink = nil end,
    }

    for _, makeMalformed in ipairs(cases) do
        local record = makeRecord(GGM)
        makeMalformed(record.gear.slots.HEAD)
        local model = GGM.BuildSnapshotViewModel(record)
        T.assertFalse(model.hasSnapshot)
        T.assertEqual(model.emptyStateText, "No saved snapshot")
    end
end)

T.test("renderer switches between saved data and no saved snapshot", function()
    local GGM = loadUI()
    local frame = newRenderableFrame(GGM)
    local record = makeRecord(GGM)

    local populated = GGM.BuildSnapshotViewModel(record)
    GGM.RenderSnapshotViewModel(frame, populated)

    T.assertFalse(frame.emptyState.visible)
    T.assertTrue(frame.characterLine.visible)
    T.assertEqual(frame.characterLine.text, "Character: Alice")
    T.assertEqual(frame.realmLine.text, "Realm: Silvermoon")
    T.assertEqual(frame.completenessLine.text, "Completeness: Complete")
    T.assertEqual(frame.slotRows[1].text, "HEAD: " .. record.gear.slots.HEAD.itemLink)

    local missing = GGM.BuildSnapshotViewModel(nil)
    GGM.RenderSnapshotViewModel(frame, missing)

    T.assertTrue(frame.emptyState.visible)
    T.assertEqual(frame.emptyState.text, "No saved snapshot")
    T.assertFalse(frame.characterLine.visible)
    T.assertFalse(frame.slotRows[1].visible)
end)

T.test("renderer renders every tracked slot row in order", function()
    local GGM = loadUI()
    local frame = newRenderableFrame(GGM)
    local record = makeRecord(GGM)

    GGM.RenderSnapshotViewModel(frame, GGM.BuildSnapshotViewModel(record))

    for index, trackedSlot in ipairs(GGM.TRACKED_SLOTS) do
        local savedSlot = record.gear.slots[trackedSlot.key]
        T.assertTrue(frame.slotRows[index].visible)
        T.assertEqual(frame.slotRows[index].text, trackedSlot.key .. ": " .. savedSlot.itemLink)
    end
end)
