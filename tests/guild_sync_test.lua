local T = require("tests.testlib")

local function loadModules()
    local GGM = {}
    T.loadAddonFile("GuildGearMemory/Constants.lua", GGM)
    T.loadAddonFile("GuildGearMemory/CharacterIdentity.lua", GGM)
    T.loadAddonFile("GuildGearMemory/GearSnapshot.lua", GGM)
    T.loadAddonFile("GuildGearMemory/Storage.lua", GGM)
    T.loadAddonFile("GuildGearMemory/SyncProtocol.lua", GGM)
    T.loadAddonFile("GuildGearMemory/SyncTransport.lua", GGM)
    T.loadAddonFile("GuildGearMemory/GuildSync.lua", GGM)
    return GGM
end

local function identity(name, realm, guid)
    return { key = name .. "-" .. realm, name = name, realm = realm, guid = guid }
end

local function snapshot(GGM, base, capturedAt)
    local result = { complete = true, capturedAt = capturedAt or 1700002000, slots = {} }
    for index, slot in ipairs(GGM.TRACKED_SLOTS) do
        local itemID = base + index
        result.slots[slot.key] = {
            inventorySlotID = index,
            itemID = itemID,
            itemLink = "|Hitem:" .. itemID .. "|h[" .. slot.key .. "]|h",
        }
    end
    return result
end

local function clientApi(who, results)
    local timers, sends, now = {}, {}, 200
    local api = {
        C_ChatInfo = {}, C_Timer = {},
        UnitFullName = function() return who.name, who.realm end,
        GetRealmName = function() return who.realm end,
        UnitGUID = function() return who.guid end,
        GetTime = function() return now end,
    }
    api.C_ChatInfo.RegisterAddonMessagePrefix = function() return 0 end
    api.C_ChatInfo.SendAddonMessage = function(prefix, message, channel, target)
        table.insert(sends, { prefix = prefix, message = message, channel = channel, target = target })
        return results and results[#sends] or 0
    end
    api.C_Timer.NewTimer = function(delay, callback)
        local timer = { delay = delay, fired = false }
        function timer:Fire()
            if not self.fired then self.fired = true; callback() end
        end
        table.insert(timers, timer)
        return timer
    end
    local function drain()
        local index = 1
        while index <= #timers do timers[index]:Fire(); index = index + 1 end
    end
    return api, sends, drain, function(value) now = value end
end

local function deliver(GGM, sync, sends, sender)
    local state, err
    for _, send in ipairs(sends) do
        state, err = GGM.HandleGuildSyncAddonMessage(sync, send.prefix, send.message, send.channel, sender)
    end
    return state, err
end

T.test("incremental updates require a complete compatible baseline", function()
    local GGM = loadModules()
    local alice = identity("Alice", "Silvermoon", "A" )
    local bob = identity("Bob", "Silvermoon", "B")
    local db = assert(GGM.InitializeDatabase(nil))
    local sync = assert(GGM.CreateGuildSync(clientApi(bob), db))
    local changed = { inventorySlotID = 1, itemID = 9901, itemLink = "|Hitem:9901|h[Remote]|h" }
    local payload = assert(GGM.EncodeSyncSlotUpdate(alice, 5, "HEAD", changed, 1700002300))
    local state, err = GGM.HandleGuildSyncPayload(sync, alice.key, payload)
    T.assertNil(state); T.assertEqual(err, "record-missing")
    assert(GGM.SaveCompleteCharacterRecord(db, alice, snapshot(GGM, 6000), 4))
    state, err = GGM.HandleGuildSyncPayload(sync, alice.key, payload)
    T.assertEqual(state, "slot-applied"); T.assertNil(err)
    T.assertEqual(db.characters[alice.key].gear.slots.HEAD.itemID, 9901)
    T.assertEqual(db.characters[alice.key].confirmedSequence, 5)
end)

T.test("incremental sender identity mismatch fails closed", function()
    local GGM = loadModules()
    local alice, bob = identity("Alice", "Silvermoon", "A"), identity("Bob", "Silvermoon", "B")
    local db = assert(GGM.InitializeDatabase(nil))
    assert(GGM.SaveCompleteCharacterRecord(db, alice, snapshot(GGM, 6000), 1))
    local sync = assert(GGM.CreateGuildSync(clientApi(bob), db))
    local payload = assert(GGM.EncodeSyncSlotUpdate(alice, 2, "HEAD", { inventorySlotID = 1, itemID = 9902, itemLink = "|Hitem:9902|h[Spoof]|h" }, 1700002400))
    local state, err = GGM.HandleGuildSyncPayload(sync, "Mallory-Silvermoon", payload)
    T.assertNil(state); T.assertEqual(err, "sync-sender-identity-mismatch")
    T.assertEqual(db.characters[alice.key].gear.slots.HEAD.itemID, 6001)
end)

T.test("explicit request receives a complete offline cached record", function()
    local GGM = loadModules()
    local alice, bob, carol = identity("Alice", "Silvermoon", "A"), identity("Bob", "Silvermoon", "B"), identity("Carol", "Silvermoon", "C")
    local bobDb = assert(GGM.InitializeDatabase(nil)); local bobApi, bobSends, drainBob = clientApi(bob)
    local bobSync = assert(GGM.CreateGuildSync(bobApi, bobDb))
    local carolDb = assert(GGM.InitializeDatabase(nil)); assert(GGM.SaveCompleteCharacterRecord(carolDb, alice, snapshot(GGM, 7000), 6))
    local carolApi, carolSends, drainCarol = clientApi(carol); local carolSync = assert(GGM.CreateGuildSync(carolApi, carolDb))
    assert(GGM.RequestCompleteSnapshot(bobSync, alice)); drainBob()
    local state, err = deliver(GGM, carolSync, bobSends, bob.key)
    T.assertEqual(state, "snapshot-response-queued"); T.assertNil(err)
    drainCarol(); state, err = deliver(GGM, bobSync, carolSends, carol.key)
    T.assertEqual(state, "snapshot-saved"); T.assertNil(err)
    T.assertEqual(bobDb.characters[alice.key].confirmedSequence, 6)
end)

T.test("all eligible cached clients may answer the same request", function()
    local GGM = loadModules()
    local alice, bob, carol, dave = identity("Alice", "Silvermoon", "A"), identity("Bob", "Silvermoon", "B"), identity("Carol", "Silvermoon", "C"), identity("Dave", "Silvermoon", "D")
    local requestApi, requestSends, drain = clientApi(bob); local requester = assert(GGM.CreateGuildSync(requestApi, assert(GGM.InitializeDatabase(nil))))
    assert(GGM.RequestCompleteSnapshot(requester, alice)); drain()
    local carolDb = assert(GGM.InitializeDatabase(nil)); assert(GGM.SaveCompleteCharacterRecord(carolDb, alice, snapshot(GGM, 7100), 3))
    local carolApi, carolSends = clientApi(carol); local carolSync = assert(GGM.CreateGuildSync(carolApi, carolDb))
    local daveDb = assert(GGM.InitializeDatabase(nil)); assert(GGM.SaveCompleteCharacterRecord(daveDb, alice, snapshot(GGM, 7100), 3))
    local daveApi, daveSends = clientApi(dave); local daveSync = assert(GGM.CreateGuildSync(daveApi, daveDb))
    deliver(GGM, carolSync, requestSends, bob.key); deliver(GGM, daveSync, requestSends, bob.key)
    T.assertTrue(#carolSends > 0); T.assertTrue(#daveSends > 0)
end)

T.test("responder cooldown is bounded per requester and target", function()
    local GGM = loadModules()
    local alice, bob, carol = identity("Alice", "Silvermoon", "A"), identity("Bob", "Silvermoon", "B"), identity("Carol", "Silvermoon", "C")
    local db = assert(GGM.InitializeDatabase(nil)); assert(GGM.SaveCompleteCharacterRecord(db, alice, snapshot(GGM, 7150), 3))
    local api, sends, drain, setTime = clientApi(carol); local sync = assert(GGM.CreateGuildSync(api, db))
    local request = assert(GGM.EncodeSyncSnapshotRequest(bob, alice))
    local state, err = GGM.HandleGuildSyncPayload(sync, bob.key, request)
    T.assertEqual(state, "snapshot-response-queued"); T.assertNil(err); drain(); local count = #sends
    setTime(200 + GGM.SYNC_SNAPSHOT_RESPONSE_COOLDOWN_SECONDS - 0.01)
    state, err = GGM.HandleGuildSyncPayload(sync, bob.key, request)
    T.assertEqual(state, "ignored"); T.assertNil(err); T.assertEqual(#sends, count)
    setTime(200 + GGM.SYNC_SNAPSHOT_RESPONSE_COOLDOWN_SECONDS)
    state, err = GGM.HandleGuildSyncPayload(sync, bob.key, request)
    T.assertEqual(state, "snapshot-response-queued"); T.assertNil(err); drain(); T.assertTrue(#sends > count)
end)

T.test("unavailable or malformed request produces no response", function()
    local GGM = loadModules()
    local alice, bob, carol = identity("Alice", "Silvermoon", "A"), identity("Bob", "Silvermoon", "B"), identity("Carol", "Silvermoon", "C")
    local db = assert(GGM.InitializeDatabase(nil)); local api, sends = clientApi(carol); local sync = assert(GGM.CreateGuildSync(api, db))
    local request = assert(GGM.EncodeSyncSnapshotRequest(bob, alice)); local state, err = GGM.HandleGuildSyncPayload(sync, bob.key, request)
    T.assertEqual(state, "ignored"); T.assertNil(err); T.assertEqual(#sends, 0)
    db.characters[alice.key] = { complete = true, identity = alice, gear = { complete = true, capturedAt = 1, slots = {} }, confirmedSequence = 0 }
    state, err = GGM.HandleGuildSyncPayload(sync, bob.key, request)
    T.assertNil(state); T.assertEqual(err, "snapshot-slot-missing:HEAD"); T.assertEqual(#sends, 0)
end)

T.test("lower sequence response cannot replace newer record", function()
    local GGM = loadModules()
    local alice, bob = identity("Alice", "Silvermoon", "A"), identity("Bob", "Silvermoon", "B")
    local db = assert(GGM.InitializeDatabase(nil)); assert(GGM.SaveCompleteCharacterRecord(db, alice, snapshot(GGM, 8000), 9))
    local sync = assert(GGM.CreateGuildSync(clientApi(bob), db)); local payload = assert(GGM.EncodeSyncSnapshotResponse(alice, snapshot(GGM, 9000, 1700003000), 8))
    local state, err = GGM.HandleGuildSyncPayload(sync, "Carol-Silvermoon", payload)
    T.assertNil(state); T.assertEqual(err, "confirmed-sequence-regression"); T.assertEqual(db.characters[alice.key].gear.slots.HEAD.itemID, 8001)
end)

T.test("confirmed publication uses the persisted sequence and slot", function()
    local GGM = loadModules()
    local alice = identity("Alice", "Silvermoon", "A"); local db = assert(GGM.InitializeDatabase(nil)); assert(GGM.SaveCompleteCharacterRecord(db, alice, snapshot(GGM, 10000), 4))
    local changed = { inventorySlotID = 1, itemID = 10999, itemLink = "|Hitem:10999|h[Published]|h" }
    assert(GGM.ApplyReceivedCharacterSlot(db, alice.key, "HEAD", changed, 1700003300, 5))
    local api, sends, drain = clientApi(alice); local sync = assert(GGM.CreateGuildSync(api, db))
    local ok, err = GGM.PublishConfirmedSlot(sync, alice.key, "HEAD", changed, 1700003300, 5)
    T.assertTrue(ok); T.assertNil(err); drain(); T.assertTrue(#sends > 0)
end)
