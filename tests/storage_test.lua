local T = require("tests.testlib")

local function loadModules()
    local GGM = {}
    T.loadAddonFile("GuildGearMemory/Constants.lua", GGM)
    T.loadAddonFile("GuildGearMemory/GearSnapshot.lua", GGM)
    T.loadAddonFile("GuildGearMemory/Storage.lua", GGM)
    return GGM
end

local function makeSnapshot(GGM)
    local slots = {}
    for index, slot in ipairs(GGM.TRACKED_SLOTS) do
        slots[slot.key] = {
            inventorySlotID = index,
            itemID = 2000 + index,
            itemLink = "|Hitem:" .. tostring(2000 + index) .. "|h[Test]|h",
        }
    end

    return {
        complete = true,
        capturedAt = 1700000000,
        slots = slots,
    }
end

local function makeIdentity()
    return {
        key = "Alice-Silvermoon",
        name = "Alice",
        realm = "Silvermoon",
        guid = "Player-1234-ABCDEF",
    }
end

T.test("database initialization creates the Phase 1 schema on first run", function()
    local GGM = loadModules()

    local db, err = GGM.InitializeDatabase(nil)

    T.assertNil(err)
    T.assertEqual(db.schemaVersion, 1)
    T.assertEqual(type(db.characters), "table")
end)

T.test("database initialization reuses a valid existing SavedVariables table", function()
    local GGM = loadModules()
    local existing = {
        schemaVersion = 1,
        characters = {},
    }

    local db, err = GGM.InitializeDatabase(existing)

    T.assertNil(err)
    T.assertTrue(db == existing)
end)

T.test("database initialization rejects an unsupported schema version", function()
    local GGM = loadModules()
    local existing = {
        schemaVersion = 99,
        characters = {},
    }

    local db, err = GGM.InitializeDatabase(existing)

    T.assertNil(db)
    T.assertEqual(err, "unsupported-schema-version:99")
end)

T.test("saving rejects a database with an unsupported schema version", function()
    local GGM = loadModules()
    local db = {
        schemaVersion = 99,
        characters = {},
    }

    local ok, err = GGM.SaveCompleteCharacterRecord(db, makeIdentity(), makeSnapshot(GGM))

    T.assertFalse(ok)
    T.assertEqual(err, "unsupported-schema-version:99")
    T.assertNil(db.characters["Alice-Silvermoon"])
end)

T.test("reading rejects a database with an unsupported schema version", function()
    local GGM = loadModules()
    local db = assert(GGM.InitializeDatabase(nil))
    local identity = makeIdentity()
    assert(GGM.SaveCompleteCharacterRecord(db, identity, makeSnapshot(GGM)))
    db.schemaVersion = 99

    local record, err = GGM.GetCompleteCharacterRecord(db, identity.key)

    T.assertNil(record)
    T.assertEqual(err, "unsupported-schema-version:99")
end)

T.test("saving a complete snapshot creates a usable character record", function()
    local GGM = loadModules()
    local db = assert(GGM.InitializeDatabase(nil))
    local identity = makeIdentity()
    local snapshot = makeSnapshot(GGM)

    local ok, err = GGM.SaveCompleteCharacterRecord(db, identity, snapshot)

    T.assertTrue(ok)
    T.assertNil(err)

    local record = GGM.GetCompleteCharacterRecord(db, identity.key)
    T.assertNotNil(record)
    T.assertTrue(record.complete)
    T.assertEqual(record.identity.key, "Alice-Silvermoon")
    T.assertEqual(record.gear.capturedAt, 1700000000)
end)

T.test("saving a snapshot stores a defensive copy", function()
    local GGM = loadModules()
    local db = assert(GGM.InitializeDatabase(nil))
    local identity = makeIdentity()
    local snapshot = makeSnapshot(GGM)

    assert(GGM.SaveCompleteCharacterRecord(db, identity, snapshot))
    snapshot.capturedAt = 1800000000
    snapshot.slots.HEAD.itemID = 9999

    local record = assert(GGM.GetCompleteCharacterRecord(db, identity.key))

    T.assertEqual(record.gear.capturedAt, 1700000000)
    T.assertEqual(record.gear.slots.HEAD.itemID, 2001)
end)

T.test("an incomplete snapshot is never saved over a complete record", function()
    local GGM = loadModules()
    local db = assert(GGM.InitializeDatabase(nil))
    local identity = makeIdentity()
    local original = makeSnapshot(GGM)
    assert(GGM.SaveCompleteCharacterRecord(db, identity, original))

    local broken = makeSnapshot(GGM)
    broken.slots.HEAD = nil

    local ok, err = GGM.SaveCompleteCharacterRecord(db, identity, broken)

    T.assertFalse(ok)
    T.assertEqual(err, "snapshot-slot-missing:HEAD")
    T.assertEqual(db.characters[identity.key].gear.capturedAt, 1700000000)
    T.assertNotNil(db.characters[identity.key].gear.slots.HEAD)
end)

T.test("reading a malformed saved record returns no usable data", function()
    local GGM = loadModules()
    local db = assert(GGM.InitializeDatabase(nil))
    db.characters["Alice-Silvermoon"] = {
        complete = true,
        identity = makeIdentity(),
        gear = {
            complete = true,
            capturedAt = 1700000000,
            slots = {},
        },
    }

    local record, err = GGM.GetCompleteCharacterRecord(db, "Alice-Silvermoon")

    T.assertNil(record)
    T.assertEqual(err, "snapshot-slot-missing:HEAD")
end)
