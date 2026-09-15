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

T.test("main registers only Phase 1 startup events", function()
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
        GGM.InitializeDatabase = function(existing)
            return existing or { schemaVersion = 1, characters = {} }, nil
        end
        GGM.CaptureAndStoreLocalPlayer = function()
            return { complete = true }, nil
        end

        T.loadAddonFile("GuildGearMemory/Main.lua", GGM)

        T.assertTrue(registered.ADDON_LOADED == true)
        T.assertTrue(registered.PLAYER_LOGIN == true)
        T.assertFalse(registered.PLAYER_EQUIPMENT_CHANGED == true)
        T.assertNotNil(onEvent)
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
        GGM.InitializeDatabase = function(existing)
            T.assertNil(existing)
            return { schemaVersion = 1, characters = {} }, nil
        end
        GGM.CaptureAndStoreLocalPlayer = function()
            return nil, nil
        end

        T.loadAddonFile("GuildGearMemory/Main.lua", GGM)
        onEvent(frame, "ADDON_LOADED", "GuildGearMemory")

        T.assertNotNil(_G.GuildGearMemoryDB)
        T.assertTrue(GGM.db == _G.GuildGearMemoryDB)
        T.assertNil(GGM.startupError)
    end)
end)

T.test("player login performs one capture after database initialization", function()
    local onEvent
    local frame = {
        RegisterEvent = function() end,
        SetScript = function(_, _, handler)
            onEvent = handler
        end,
    }

    local captureCount = 0

    withGlobals({
        CreateFrame = function()
            return frame
        end,
        GuildGearMemoryDB = NIL,
    }, function()
        local GGM = {}
        GGM.InitializeDatabase = function()
            return { schemaVersion = 1, characters = {} }, nil
        end
        GGM.CaptureAndStoreLocalPlayer = function(api, db)
            T.assertTrue(api == _G)
            T.assertTrue(db == GGM.db)
            captureCount = captureCount + 1
            return { complete = true }, nil
        end

        T.loadAddonFile("GuildGearMemory/Main.lua", GGM)
        onEvent(frame, "ADDON_LOADED", "GuildGearMemory")
        onEvent(frame, "PLAYER_LOGIN")

        T.assertEqual(captureCount, 1)
        T.assertNil(GGM.lastCaptureError)
    end)
end)

T.test("unsupported saved schema blocks login capture instead of overwriting data", function()
    local onEvent
    local frame = {
        RegisterEvent = function() end,
        SetScript = function(_, _, handler)
            onEvent = handler
        end,
    }

    local captureCount = 0

    withGlobals({
        CreateFrame = function()
            return frame
        end,
        GuildGearMemoryDB = { schemaVersion = 99, characters = {} },
    }, function()
        local GGM = {}
        GGM.InitializeDatabase = function()
            return nil, "unsupported-schema-version:99"
        end
        GGM.CaptureAndStoreLocalPlayer = function()
            captureCount = captureCount + 1
            return nil, nil
        end

        T.loadAddonFile("GuildGearMemory/Main.lua", GGM)
        onEvent(frame, "ADDON_LOADED", "GuildGearMemory")
        onEvent(frame, "PLAYER_LOGIN")

        T.assertEqual(captureCount, 0)
        T.assertEqual(GGM.startupError, "unsupported-schema-version:99")
    end)
end)
