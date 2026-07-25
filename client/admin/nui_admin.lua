-- ═══════════════════════════════════════════════════════════════════════
--                    ADMIN NUI CALLBACKS
-- ═══════════════════════════════════════════════════════════════════════

RegisterNUICallback('adminClosePanel', function(_, cb)
    CloseAdminPanel()
    cb('ok')
end)

RegisterNUICallback('adminStartPlacement', function(data, cb)
    StartPlacement(data.field)  -- 'zone' or 'ped'
    cb('ok')
end)

RegisterNUICallback('adminPreviewCamera', function(data, cb)
    StartCameraPreview(data.pedPosition, data.cameraPreset)
    cb('ok')
end)

RegisterNUICallback('adminTeleport', function(data, cb)
    TeleportToStore(data.coords)
    cb('ok')
end)

RegisterNUICallback('adminSaveStore', function(data, cb)
    TriggerServerEvent('orb-clothing:server:adminSaveStore', data)
    cb('ok')
end)

RegisterNUICallback('adminDeleteStore', function(data, cb)
    TriggerServerEvent('orb-clothing:server:adminDeleteStore', data)
    cb('ok')
end)

-- Update zone marker size when admin changes it in the NUI
RegisterNUICallback('adminUpdateMarkerSize', function(data, cb)
    UpdateMarkerZoneSize(data.width, data.length)
    cb('ok')
end)

-- ── Store item picker ────────────────────────────────────────────────────
-- "Restrict items": open the creator in filter-edit mode for a store, so the
-- owner can tick which drawables it sells (per gender), instead of hunting IDs.
RegisterNUICallback('adminEditFilter', function(data, cb)
    cb('ok')
    local storeId = data and data.id
    if not storeId then return end

    -- Find the store (merged into Config.StoreLocations by MergeAdminStores).
    local store
    for _, s in ipairs(Config.StoreLocations or {}) do
        if s._adminId == storeId then store = s break end
    end
    if not store then return end
    local storeType = Config.StoreTypes[store.type]
    if not storeType then return end

    CloseAdminPanel()

    -- Open like /tc (no teleport, no store index) but restricted to this store's
    -- tabs and in filter-edit mode, seeded with its current allow-list.
    TriggerEvent('orb-clothing:client:openCreator', {
        storeType     = store.type,
        allowedTabs   = storeType.tabs,
        openCamera    = storeType.openCamera or 'full',
        itemFilter    = store.itemFilter,
        filterEdit    = true,
        filterStoreId = storeId,
    })
end)

-- Persist the picked allow-list and close the editing session.
RegisterNUICallback('saveItemFilter', function(data, cb)
    cb('ok')
    TriggerServerEvent('orb-clothing:server:saveItemFilter', data.storeId, data.itemFilter)
    TriggerEvent('orb-clothing:client:close')   -- cancel-style close: appearance is restored
end)
