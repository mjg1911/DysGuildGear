local ADDON_NAME, GGM = ...

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then
            return
        end

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

        local _, err = GGM.CaptureAndStoreLocalPlayer(_G, GGM.db)
        GGM.lastCaptureError = err
    end
end)
