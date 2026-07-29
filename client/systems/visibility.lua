-- ═══════════════════════════════════════════════════════════════════════
--                   CLOTHING VISIBILITY TOGGLES (preview)
-- ═══════════════════════════════════════════════════════════════════════
-- Hide/show WORN components in the creator so a player can peek at what's
-- underneath (e.g. do the arms clip through this top?). Purely visual: nothing is
-- ever saved hidden — RestoreAll() runs before every save snapshot and on close,
-- and picking a new item for a slot un-hides it. While a slot is hidden we keep its
-- real (drawable, texture) so we can put it back exactly.

ClothingVisibility = {}

-- Per-gender "invisible" drawable for each toggleable component — the same values
-- the tattoo strip uses. Props hide via ClearPedProp, so they need no value.
local HIDE_COMPONENT = {
    male   = { [1] = 0, [3] = 15, [4] = 14, [8] = 15, [9] = 0, [10] = 0, [11] = 15 },
    female = { [1] = 0, [3] = 15, [4] = 14, [8] = 14, [9] = 0, [10] = 0, [11] = 14 },
}

local snapshot = { components = {}, props = {} }

function ClothingVisibility.Reset()
    snapshot = { components = {}, props = {} }
end

function ClothingVisibility.IsHidden(kind, id)
    if kind == 'prop' then return snapshot.props[id] ~= nil end
    return snapshot.components[id] ~= nil
end

-- Toggle a slot and return the NEW hidden state (true = now hidden).
function ClothingVisibility.Toggle(ped, kind, id)
    if not DoesEntityExist(ped) then return false end

    if kind == 'prop' then
        if snapshot.props[id] then
            local s = snapshot.props[id]
            if s.d >= 0 then SetPedPropIndex(ped, id, s.d, s.t, true) else ClearPedProp(ped, id) end
            snapshot.props[id] = nil
            return false
        end
        snapshot.props[id] = { d = GetPedPropIndex(ped, id), t = GetPedPropTextureIndex(ped, id) }
        ClearPedProp(ped, id)
        return true
    end

    if snapshot.components[id] then
        local s = snapshot.components[id]
        SetPedComponentVariation(ped, id, s.d, s.t, 2)
        snapshot.components[id] = nil
        return false
    end
    snapshot.components[id] = { d = GetPedDrawableVariation(ped, id), t = GetPedTextureVariation(ped, id) }
    local map = Config.IsMale(ped) and HIDE_COMPONENT.male or HIDE_COMPONENT.female
    SetPedComponentVariation(ped, id, map[id] or 0, 0, 2)
    return true
end

-- Put every hidden slot back to its real look and forget the snapshot. MUST run
-- before the save snapshot (BuildSnapshot reads the live ped) and on close.
function ClothingVisibility.RestoreAll(ped)
    if DoesEntityExist(ped) then
        for id, s in pairs(snapshot.components) do
            SetPedComponentVariation(ped, id, s.d, s.t, 2)
        end
        for id, s in pairs(snapshot.props) do
            if s.d >= 0 then SetPedPropIndex(ped, id, s.d, s.t, true) else ClearPedProp(ped, id) end
        end
    end
    ClothingVisibility.Reset()
end

-- A slot just received a new selection (it's now shown with that item) — drop its
-- hidden record so a later RestoreAll can't overwrite the new choice. Returns true
-- if it HAD been hidden (so the caller can re-sync the NUI button).
function ClothingVisibility.ClearSlot(kind, id)
    local was
    if kind == 'prop' then
        was = snapshot.props[id] ~= nil
        snapshot.props[id] = nil
    else
        was = snapshot.components[id] ~= nil
        snapshot.components[id] = nil
    end
    return was
end
