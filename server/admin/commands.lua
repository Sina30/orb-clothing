-- ═══════════════════════════════════════════════════════════════════════
--                      ADMIN STORE COMMANDS
-- Net events and callbacks for admin store CRUD operations.
-- ═══════════════════════════════════════════════════════════════════════

-- ── Rebuild server-side Config.StoreLocations ───────────────────────────

-- Stores live entirely in the admin storage now (config defaults are seeded
-- into it on first run — see AdminStorage.SeedDefaultsIfNeeded). The config
-- list is only a one-time seed, never the live source.
local function RebuildServerStoreLocations()
    Config.StoreLocations = {}
    for _, s in ipairs(AdminStorage.GetAll()) do
        Config.StoreLocations[#Config.StoreLocations + 1] = {
            coords      = vector4(s.coords.x, s.coords.y, s.coords.z, s.coords.w),
            type        = s.type,
            pedPosition = s.pedPosition and vector4(s.pedPosition.x, s.pedPosition.y, s.pedPosition.z, s.pedPosition.w) or nil,
            size        = s.size and vector2(s.size.x, s.size.y) or nil,
            label       = s.label,
            jobLock     = s.jobLock,
            showBlip    = s.showBlip ~= false,   -- default true; only explicit false hides it
            itemFilter  = s.itemFilter,          -- per-section/gender allow-list (nil = sells all)
            _adminId    = s.id
        }
    end
end

-- ── Callback: get admin stores list ─────────────────────────────────────

lib.callback.register('orb-clothing:server:getAdminStores', function(source)
    return AdminStorage.GetAll()
end)

-- ── Net event: save (create or update) ──────────────────────────────────

RegisterNetEvent('orb-clothing:server:adminSaveStore', function(data)
    local src = source
    if not AdminStorage.IsAdmin(src) then
        lib.print.warn(('[AdminCommands] Non-admin %s attempted adminSaveStore'):format(tostring(src)))
        return
    end

    -- Validate
    local valid, err = AdminStorage.ValidateStoreData(data)
    if not valid then
        TriggerClientEvent('orb-clothing:client:adminNotify', src, {
            title = L('store_admin_title'), description = err, type = 'error'
        })
        return
    end

    -- Normalise the blip toggle to a real boolean — never trust the NUI's shape.
    -- Absent = true (a store saved before this option keeps its blip).
    data.showBlip = data.showBlip ~= false

    local result
    if data.id then
        -- Update existing
        result = AdminStorage.Update(data.id, data)
    else
        -- Create new — attach admin identity
        local identifiers = GetPlayerIdentifiers(src)
        local license = nil
        for _, id in ipairs(identifiers) do
            if id:find('license:') then
                license = id
                break
            end
        end
        data.createdBy = license or ('source:' .. tostring(src))
        result = AdminStorage.Add(data)
    end

    if result then
        -- Rebuild server store list
        RebuildServerStoreLocations()
        -- Notify all clients to reload
        TriggerClientEvent('orb-clothing:client:reloadStores', -1, AdminStorage.GetAll())
        -- Confirm to the admin
        TriggerClientEvent('orb-clothing:client:adminSaveResult', src, {
            success = true,
            store = result,
            stores = AdminStorage.GetAll()
        })
    else
        TriggerClientEvent('orb-clothing:client:adminNotify', src, {
            title = L('store_admin_title'), description = L('store_save_failed'), type = 'error'
        })
    end
end)

-- ── Net event: delete ───────────────────────────────────────────────────

RegisterNetEvent('orb-clothing:server:adminDeleteStore', function(data)
    local src = source
    if not AdminStorage.IsAdmin(src) then
        lib.print.warn(('[AdminCommands] Non-admin %s attempted adminDeleteStore'):format(tostring(src)))
        return
    end

    if not data or not data.id then
        TriggerClientEvent('orb-clothing:client:adminNotify', src, {
            title = L('store_admin_title'), description = L('store_no_id'), type = 'error'
        })
        return
    end

    local success = AdminStorage.Delete(data.id)
    if success then
        RebuildServerStoreLocations()
        TriggerClientEvent('orb-clothing:client:reloadStores', -1, AdminStorage.GetAll())
        TriggerClientEvent('orb-clothing:client:adminDeleteResult', src, {
            success = true,
            stores = AdminStorage.GetAll()
        })
    else
        TriggerClientEvent('orb-clothing:client:adminNotify', src, {
            title = L('store_admin_title'), description = L('store_not_found'), type = 'error'
        })
    end
end)

-- ── Net event: save a store's item allow-list ───────────────────────────
-- Client-sent shape: { [sectionId] = { male = {int…}, female = {int…} } }. NEVER
-- trusted: sanitised into plain int arrays with hard caps before it's stored.
local function sanitizeItemFilter(raw)
    if type(raw) ~= 'table' then return nil end
    local out = {}
    local sectionCount = 0
    for sectionId, perGender in pairs(raw) do
        if type(sectionId) == 'string' and #sectionId <= 64 and type(perGender) == 'table'
            and sectionCount < 64 then
            local entry = {}
            for _, gender in ipairs({ 'male', 'female' }) do
                local list = perGender[gender]
                if type(list) == 'table' then
                    local ids, seen = {}, {}
                    for _, v in ipairs(list) do
                        local n = tonumber(v)
                        if n then
                            n = math.floor(n)
                            if n >= 0 and n < 10000 and not seen[n] then
                                seen[n] = true
                                ids[#ids + 1] = n
                            end
                        end
                        if #ids >= 5000 then break end
                    end
                    if #ids > 0 then entry[gender] = ids end
                end
            end
            if next(entry) then
                out[sectionId] = entry
                sectionCount = sectionCount + 1
            end
        end
    end
    if next(out) then return out end
    return nil   -- empty → nil so the store goes back to selling everything
end

RegisterNetEvent('orb-clothing:server:saveItemFilter', function(storeId, itemFilter)
    local src = source
    if not AdminStorage.IsAdmin(src) then
        lib.print.warn(('[AdminCommands] Non-admin %s attempted saveItemFilter'):format(tostring(src)))
        return
    end
    if type(storeId) ~= 'string' then return end

    local store = AdminStorage.FindById(storeId)
    if not store then
        TriggerClientEvent('orb-clothing:client:adminNotify', src, {
            title = L('store_admin_title'), description = L('store_not_found'), type = 'error' })
        return
    end

    store.itemFilter = sanitizeItemFilter(itemFilter)   -- nil clears the restriction
    AdminStorage.Update(storeId, store)
    RebuildServerStoreLocations()
    TriggerClientEvent('orb-clothing:client:reloadStores', -1, AdminStorage.GetAll())
    TriggerClientEvent('orb-clothing:client:adminNotify', src, {
        title = L('store_admin_title'), description = L('filter_saved'), type = 'success' })
end)

-- ── /skin [id] — admin: open the FULL creator on a player ────────────────
-- No id  → opens it on yourself.
-- With id → opens it on that player (must be online).
-- Permission is checked HERE, server-side, so the client event can't be abused
-- to force the editor onto someone else.

local function notifyAdmin(src, key, arg)
    if src == 0 then
        lib.print.info(('[orb-clothing] %s'):format(arg and L(key, arg) or L(key)))
        return
    end
    TriggerClientEvent('orb-clothing:client:adminNotify', src, {
        title = L('skin_title'),
        description = arg and L(key, arg) or L(key),
        type = 'inform',
    })
end

RegisterCommand('skin', function(source, args)
    local src = source

    -- Console (src 0) is always allowed but MUST name a target — it has no ped.
    if src ~= 0 and not AdminStorage.IsAdmin(src) then
        notifyAdmin(src, 'skin_no_perm')
        return
    end

    -- Resolve target: explicit id, else the caller. A non-numeric arg falls back
    -- to self rather than silently doing nothing.
    local target = args[1] and tonumber(args[1]) or src
    if not target or target == 0 then
        notifyAdmin(src, 'skin_need_id')   -- console with no id
        return
    end

    if not GetPlayerName(target) then
        notifyAdmin(src, 'skin_offline', tostring(args[1] or target))
        return
    end

    TriggerClientEvent('orb-clothing:client:openFullEditor', target)

    if target == src then
        notifyAdmin(src, 'skin_opened_self')
    else
        notifyAdmin(src, 'skin_opened_target', GetPlayerName(target) or tostring(target))
    end
end, false)  -- permission enforced inside via AdminStorage.IsAdmin

-- ── Initial rebuild on resource start ───────────────────────────────────

RebuildServerStoreLocations()
