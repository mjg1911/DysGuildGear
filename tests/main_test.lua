local T = require("tests.testlib")

local NIL = {}

local function withGlobals(replacements, fn)
    local originals = {}

    for key, value in pairs(replacements) do
        originals[key] = {
            existed = rawget(_G, key) ~= nil,
            value = rawget(_G, key),
        }

        if value == NIL then
            _G[key] = nil
        else
            _G[key] = value
        end
    end

    local ok, err = pcall(fn)

    for key, original in pairs(originals) do
        if original.existed then
            _G[key] = original.value
        else
            _G[key] = nil
        end
    end

    if not ok then
        error(err, 0)
    end
end

local function stubSnapshotUI(GGM, registerFn)
    GGM.RegisterSnapshotTestSlashCommand = registerFn or function() end
end

T.test("main registers Phase 3 local gear events and no addon-message event", function()
    local registered = {}
    local onEvent
    local frame = {
        RegisterEvent = function(_, event)
            registered[event] = true
        end,
        SetScript = function(_, scriptName, handler)
            T.assertEqual(scriptName, "OnEvent")
            onEvent = handler
        end,
    }

    withGlobals({
        CreateFrame = function(frameType)
            T.assertEqual(frameType, "Frame")
            return frame
        end,
    }, function()
        local GGM = {}
        stubSnapshotUI(GGM)
        GGM.InitializeDatabase = function(existing)
            return existing or { schemaVersion = 1, characters = {} }, nil
        end
        GGM.StartLocalPlayerGearTracking = function()
            return {}, nil
        end
        GGM.HandlePlayerEquipmentChanged = function()
            return "ignored", nil
        end

        T.loadAddonFile("GuildGearMemory/Main.lua", GGM)

        T.assertTrue(registered.ADDON_LOADED == true)
        T.assertTrue(registered.PLAYER_LOGIN == true)
        T.assertTrue(registered.PLAYER_EQUIPMENT_CHANGED == true)
        T.assertFalse(registered.CHAT_MSG_ADDON == true)
        T.assertNotNil(onEvent)
    end)
end)

T.test("addon loaded registers the snapshot slash command", function()
    local onEvent
    local registeredApi
    local frame = {
        RegisterEvent = function() end,
        SetScript = function(_, _, handler)
            onEvent = handler
        end,
    }

    withGlobals({
        CreateFrame = function()
            return frame
        end,
        GuildGearMemoryDB = NIL,
    }, function()
        local GGM = {}
        GGM.InitializeDatabase = function(existing)
            return existing or { schemaVersion = 1, characters = {} }, nil
        end
        GGM.StartLocalPlayerGearTracking = function()
            return nil, nil
        end
        GGM.HandlePlayerEquipmentChanged = function()
            return "ignored", nil
        end
        GGM.RegisterSnapshotTestSlashCommand = function(api)
            registeredApi = api
        end

        T.loadAddonFile("GuildGearMemory/Main.lua", GGM)
        onEvent(frame, "ADDON_LOADED", "GuildGearMemory")

        T.assertTrue(registeredApi == _G)
    end)
end)

T.test("addon loaded initializes the SavedVariables database", function()
    local onEvent
    local frame = {
        RegisterEvent = function() end,
        SetScript = function(_, _, handler)
            onEvent = handler
        end,
    }

    withGlobals({
        CreateFrame = function()
            return frame
        end,
        GuildGearMemoryDB = NIL,
    }, function()
        local GGM = {}
        stubSnapshotUI(GGM)
        GGM.InitializeDatabase = function(existing)
            T.assertNil(existing)
            return { schemaVersion = 1, characters = {} }, nil
        end
        GGM.StartLocalPlayerGearTracking = function()
            return nil, nil
        end
        GGM.HandlePlayerEquipmentChanged = function()
            return "ignored", nil
        end

        T.loadAddonFile("GuildGearMemory/Main.lua", GGM)
        onEvent(frame, "ADDON_LOADED", "GuildGearMemory")

        T.assertNotNil(_G.GuildGearMemoryDB)
        T.assertTrue(GGM.db == _G.GuildGearMemoryDB)
        T.assertNil(GGM.startupError)
    end)
end)

T.test("player login defers stable gear tracking until equipment is ready", function()
    local onEvent
    local frame = {
        RegisterEvent = function() end,
        SetScript = function(_, _, handler)
            onEvent = handler
        end,
    }

    local startCount = 0
    local deferredStartup
    local tracker = { pendingBySlot = {} }

    withGlobals({
        CreateFrame = function()
            return frame
        end,
        C_Timer = {
            After = function(delay, callback)
                T.assertEqual(delay, 1)
                deferredStartup = callback
            end,
        },
        GuildGearMemoryDB = NIL,
    }, function()
        local GGM = {
            DEFAULT_STABILITY_DELAY_SECONDS = 300,
        }
        stubSnapshotUI(GGM)
        GGM.InitializeDatabase = function()
            return { schemaVersion = 1, characters = {} }, nil
        end
        GGM.StartLocalPlayerGearTracking = function(api, db, delay)
            T.assertTrue(api == _G)
            T.assertTrue(db == GGM.db)
            T.assertEqual(delay, 300)
            startCount = startCount + 1
            return tracker, nil
        end
        GGM.HandlePlayerEquipmentChanged = function()
            return "ignored", nil
        end

        T.loadAddonFile("GuildGearMemory/Main.lua", GGM)
        onEvent(frame, "ADDON_LOADED", "GuildGearMemory")
        onEvent(frame, "PLAYER_LOGIN")

        T.assertEqual(startCount, 0)
        T.assertNotNil(deferredStartup)
        deferredStartup()

        T.assertEqual(startCount, 1)
        T.assertTrue(GGM.gearTracker == tracker)
        T.assertNil(GGM.lastGearTrackingError)
    end)
end)

T.test("equipment change routes the changed inventory slot to the active tracker", function()
    local onEvent
    local frame = {
        RegisterEvent = function() end,
        SetScript = function(_, _, handler)
            onEvent = handler
        end,
    }

    local tracker = { pendingBySlot = {} }
    local routedTracker
    local routedSlotID

    withGlobals({
        CreateFrame = function()
            return frame
        end,
        GuildGearMemoryDB = NIL,
    }, function()
        local GGM = {
            DEFAULT_STABILITY_DELAY_SECONDS = 300,
        }
        stubSnapshotUI(GGM)
        GGM.InitializeDatabase = function()
            return { schemaVersion = 1, characters = {} }, nil
        end
        GGM.StartLocalPlayerGearTracking = function()
            return tracker, nil
        end
        GGM.HandlePlayerEquipmentChanged = function(activeTracker, equipmentSlotID)
            routedTracker = activeTracker
            routedSlotID = equipmentSlotID
            return "pending", nil
        end

        T.loadAddonFile("GuildGearMemory/Main.lua", GGM)
        onEvent(frame, "ADDON_LOADED", "GuildGearMemory")
        onEvent(frame, "PLAYER_LOGIN")
        onEvent(frame, "PLAYER_EQUIPMENT_CHANGED", 16, true)

        T.assertTrue(routedTracker == tracker)
        T.assertEqual(routedSlotID, 16)
        T.assertNil(GGM.lastGearTrackingError)
    end)
end)

T.test("equipment change before tracker startup is ignored", function()
    local onEvent
    local routed = false
    local frame = {
        RegisterEvent = function() end,
        SetScript = function(_, _, handler)
            onEvent = handler
        end,
    }

    withGlobals({
        CreateFrame = function()
            return frame
        end,
    }, function()
        local GGM = {}
        stubSnapshotUI(GGM)
        GGM.InitializeDatabase = function(existing)
            return existing or { schemaVersion = 1, characters = {} }, nil
        end
        GGM.StartLocalPlayerGearTracking = function()
            return {}, nil
        end
        GGM.HandlePlayerEquipmentChanged = function()
            routed = true
            return "pending", nil
        end

        T.loadAddonFile("GuildGearMemory/Main.lua", GGM)
        onEvent(frame, "PLAYER_EQUIPMENT_CHANGED", 16, true)

        T.assertFalse(routed)
    end)
end)

T.test("unsupported saved schema blocks tracking instead of overwriting data", function()
    local onEvent
    local frame = {
        RegisterEvent = function() end,
        SetScript = function(_, _, handler)
            onEvent = handler
        end,
    }

    local startCount = 0

    withGlobals({
        CreateFrame = function()
            return frame
        end,
        GuildGearMemoryDB = { schemaVersion = 99, characters = {} },
    }, function()
        local GGM = {
            DEFAULT_STABILITY_DELAY_SECONDS = 300,
        }
        stubSnapshotUI(GGM)
        GGM.InitializeDatabase = function()
            return nil, "unsupported-schema-version:99"
        end
        GGM.StartLocalPlayerGearTracking = function()
            startCount = startCount + 1
            return nil, nil
        end
        GGM.HandlePlayerEquipmentChanged = function()
            return "ignored", nil
        end

        T.loadAddonFile("GuildGearMemory/Main.lua", GGM)
        onEvent(frame, "ADDON_LOADED", "GuildGearMemory")
        onEvent(frame, "PLAYER_LOGIN")

        T.assertEqual(startCount, 0)
        T.assertEqual(GGM.startupError, "unsupported-schema-version:99")
    end)
end)
