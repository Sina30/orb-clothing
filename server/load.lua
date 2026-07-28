-- ═══════════════════════════════════════════════════════════════════════
--                       SERVER LOAD - APPEARANCE LOADER
-- ═══════════════════════════════════════════════════════════════════════

lib.callback.register('orb-clothing:server:loadAppearance', function(source)
    local identifier = Bridge.GetIdentifier(source)
    if not identifier then
        lib.print.warn('[orb-clothing] loadAppearance: no identifier for source ' .. tostring(source))
        return nil
    end

    local result = MySQL.scalar.await(
        'SELECT appearance FROM character_appearance WHERE identifier = ?',
        { identifier }
    )
    if not result then return nil end   -- brand-new character, nothing saved yet

    local data = json.decode(result)
    if not data then
        lib.print.warn('[orb-clothing] loadAppearance: failed to decode saved appearance for ' .. identifier)
        return nil
    end

    -- Guarantee a selections table so every caller (spawn, /rs, store open) can
    -- index it without a nil check.
    data.selections = data.selections or {}

    -- Broadcast ped scale to other players via state bag
    if data.sliders and data.sliders['bodyHeight'] then
        local scale = 0.85 + (data.sliders['bodyHeight'] / 100.0 * 0.30)
        local player = Player(source)
        if player then
            player.state:set('orb-clothing:scale', scale, true)
        end
    end

    return data
end)
