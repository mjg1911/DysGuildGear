local ADDON_NAME, GGM = ...

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then
            return
        end

        GGM.RegisterSnapshotTestSlashCommand(_G)

        local db, err = GGM.InitializeDatabase(GuildGearMemoryDB)
        if not db then
            GGM.startupError = err
            return
        end

        GuildGearMemoryDB = db
        GGM.db = db
        GGM.startupError = nil
        return
    end

    if event == "PLAYER_LOGIN" then
        if not GGM.db or GGM.startupError then
            return
        end

        C_Timer.After(1, function()
            if GGM.gearTracker or GGM.startupError or not GGM.db then
                return
            end

            local tracker, err = GGM.StartLocalPlayerGearTracking(
                _G,
                GGM.db,
                GGM.DEFAULT_STABILITY_DELAY_SECONDS
            )
            GGM.gearTracker = tracker
            GGM.lastGearTrackingError = err
            GGM.lastCaptureError = err
        end)
        return
    end

    if event == "PLAYER_EQUIPMENT_CHANGED" then
        if not GGM.gearTracker or GGM.startupError then
            return
        end

        local _, err = GGM.HandlePlayerEquipmentChanged(GGM.gearTracker, arg1)
        GGM.lastGearTrackingError = err
    end
end)
