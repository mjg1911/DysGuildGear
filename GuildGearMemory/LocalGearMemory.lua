local _, GGM = ...

function GGM.CaptureAndStoreLocalPlayer(api, db)
    local identity, identityErr = GGM.BuildPlayerIdentity(api)
    if not identity then
        return nil, identityErr
    end

    local snapshot, snapshotErr = GGM.CapturePlayerGearSnapshot(api)
    if not snapshot then
        return nil, snapshotErr
    end

    local saved, saveErr = GGM.SaveCompleteCharacterRecord(db, identity, snapshot)
    if not saved then
        return nil, saveErr
    end

    return GGM.GetCompleteCharacterRecord(db, identity.key)
end

function GGM.GetLocalPlayerRecord(api, db)
    local identity, identityErr = GGM.BuildPlayerIdentity(api)
    if not identity then
        return nil, identityErr
    end

    return GGM.GetCompleteCharacterRecord(db, identity.key)
end
