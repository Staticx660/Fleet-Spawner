local QBX = exports.qbx_core

-- tracks the single active job-spawned vehicle per player, keyed by source
-- { netId = number, garage = string|nil }  -- garage is nil for throwaway (non-persistent) vehicles
local activeVehicles = {}

-- ═══════════════════════════════════════════════
--  KEY SYSTEM HOOK
--  Edit this function to match whatever key resource your server uses.
--  It's called right after a NEW vehicle is created and given a plate.
--  (Vehicles re-spawned from a garage get keys from qbx_garages itself.)
-- ═══════════════════════════════════════════════

local function GiveVehicleKeys(source, plate)
    if Config.KeySystem == 'qbx' then
        -- example: exports.qbx_vehiclekeys:GiveKeys(source, plate)
        local ok, err = pcall(function()
            exports.qbx_vehiclekeys:GiveKeys(source, plate)
        end)
        if not ok then
            print(('[qbx-jobspawner] Config.KeySystem is "qbx" but exports.qbx_vehiclekeys:GiveKeys failed: %s'):format(err))
        end
    end
    -- Config.KeySystem == 'none' -> vehicle stays unlocked, do nothing
end

local function findVehicleDef(loc, model)
    for _, v in ipairs(loc.vehicles) do
        if v.model == model then return v end
    end
    return nil
end

-- ═══════════════════════════════════════════════
--  STARTUP RECONCILIATION
-- ═══════════════════════════════════════════════
-- qbx_garages tracks a vehicle's state (GARAGED/OUT/IMPOUNDED) in the
-- database. If the server (or just this resource) restarts/crashes while a
-- fleet vehicle is out, its entity is gone but the DB row is still stuck on
-- OUT - qbx_garages then correctly (from its perspective) refuses to spawn
-- it again with "already out". qbx_garages only self-heals this for itself
-- on ITS OWN restart (and only if Config.autoRespawn is enabled in its
-- config), so it doesn't know about vehicles this resource created.
--
-- On start, walk every fleet vehicle in our configured garages and, for any
-- one that isn't actually present in the world right now, force it back into
-- its garage so it can be pulled out again. Safe to run unconditionally:
-- exports.qbx_garages:SetVehicleGarage is a no-op for vehicles that ARE
-- currently spawned.

local function isPlateSpawned(plate)
    local ok, vehicles = pcall(GetAllVehicles)
    if not ok or not vehicles then return false end
    for i = 1, #vehicles do
        if GetVehicleNumberPlateText(vehicles[i]) == plate then
            return true
        end
    end
    return false
end

local function reconcileGarage(garageName)
    local ok, vehicles = pcall(function()
        return exports.qbx_vehicles:GetPlayerVehicles({ garage = garageName })
    end)
    if not ok or not vehicles then
        print(('[qbx-jobspawner] Could not query vehicles for garage "%s" during startup reconciliation.'):format(garageName))
        return
    end

    local fixed = 0
    for _, v in ipairs(vehicles) do
        local plate = v.props and v.props.plate
        if plate and not isPlateSpawned(plate) then
            local set = exports.qbx_garages:SetVehicleGarage(v.id, garageName)
            if set then fixed = fixed + 1 end
        end
    end
    if fixed > 0 then
        print(('[qbx-jobspawner] Reconciled %d stuck fleet vehicle(s) back into garage "%s" on startup.'):format(fixed, garageName))
    end
end

CreateThread(function()
    Wait(2000) -- give qbx_vehicles/qbx_garages a moment to finish their own startup first
    local seen = {}
    for _, loc in ipairs(Config.Locations) do
        if loc.garage and not seen[loc.garage] then
            seen[loc.garage] = true
            reconcileGarage(loc.garage)
        end
    end
end)

local function validateRequest(source, index, model)
    local loc = Config.Locations[index]
    if not loc then return false, 'Unknown location.' end

    local player = QBX:GetPlayer(source)
    if not player then return false, 'Player not found.' end

    local job = player.PlayerData.job
    if loc.job ~= 'any' and loc.job ~= job.name then
        return false, 'Wrong job for this fleet.'
    end

    local vehicleDef = findVehicleDef(loc, model)
    if not vehicleDef then return false, 'Vehicle not in this fleet.' end

    -- A vehicle's own minGrade can raise the bar for that specific vehicle,
    -- but never lowers it below the location's own minGrade.
    local requiredGrade = Config.GetRequiredGrade(loc, vehicleDef)
    if (job.grade and job.grade.level or 0) < requiredGrade then
        return false, 'Grade too low for this vehicle.'
    end

    return true, loc, vehicleDef
end

-- Picks the right pad (and matching qbx_garages access point) for a vehicle:
-- a per-vehicle spawnPoint wins if set, otherwise the category's pad, otherwise
-- the location's default spawnPoint / access point 1.
local function resolveSpawnPad(loc, vehicleDef)
    if vehicleDef and vehicleDef.spawnPoint then
        return vehicleDef.spawnPoint, vehicleDef.accessPoint or 1
    end
    local override = loc.categorySpawns and vehicleDef and loc.categorySpawns[vehicleDef.category]
    if override then
        return override.coords, override.accessPoint or 1
    end
    return loc.spawnPoint, 1
end

-- Looks for a fleet vehicle this player already owns in this garage/model,
-- so pulling the "same" vehicle twice re-spawns their actual car (with its
-- saved mods) instead of minting a brand new one every time.
local function getExistingFleetVehicle(citizenid, model, garageName)
    if not garageName then return nil end
    local ok, vehicles = pcall(function()
        return exports.qbx_vehicles:GetPlayerVehicles({
            citizenid = citizenid,
            model = model,
            garage = garageName
        })
    end)
    if not ok or not vehicles or #vehicles == 0 then return nil end
    return vehicles[1]
end

-- ═══════════════════════════════════════════════
--  SPAWN
-- ═══════════════════════════════════════════════
-- Returns one of:
--   { ok = true,  mode = 'existing', vehicleId = n, garage = 'name' }
--     -> client must call qbx_garages:server:spawnVehicle itself with this id
--   { ok = true,  mode = 'new', netId = n, plate = 'str', garage = 'name'|nil }
--     -> a brand new entity was created here, client just warps in
--   { ok = false, message = 'reason' }

lib.callback.register('jobspawner:server:spawnVehicle', function(source, index, model)
    local ok, loc, vehicleDef = validateRequest(source, index, model)
    if not ok then
        return { ok = false, message = loc } -- `loc` holds the error message on failure
    end

    local player = QBX:GetPlayer(source)
    local citizenid = player.PlayerData.citizenid
    local spawnCoords, accessPoint = resolveSpawnPad(loc, vehicleDef)

    if loc.garage then
        local existing = getExistingFleetVehicle(citizenid, model, loc.garage)
        if existing then
            -- Hand off to qbx_garages' own spawn flow so it applies the saved
            -- props/mods and hands out keys the same way a normal garage pull does.
            -- Use the pad matching THIS vehicle's category, not wherever it was
            -- originally parked, so a helicopter always comes back on the helipad.
            return { ok = true, mode = 'existing', vehicleId = existing.id, garage = loc.garage, accessPoint = accessPoint }
        end
    end

    local modelHash = GetHashKey(model)
    local sp = spawnCoords

    local veh = CreateVehicleServerSetter(modelHash, 'automobile', sp.x, sp.y, sp.z, sp.w)
    if not DoesEntityExist(veh) then
        return { ok = false, message = 'Failed to create vehicle (bad model name?).' }
    end

    -- Note: SetEntityAsMissionEntity / SetVehicleHasBeenOwnedByPlayer / hotwire / radio
    -- are all client-only natives - they're applied on the client in client/main.lua
    -- once the vehicle has streamed in for the player, not here.
    local plate = ('JOB%02d%02d'):format(index, math.random(10, 99))
    SetVehicleNumberPlateText(veh, plate)

    local netId = NetworkGetNetworkIdFromEntity(veh)

    if loc.garage then
        local vehicleId, errResult = exports.qbx_vehicles:CreatePlayerVehicle({
            model = model,
            citizenid = citizenid,
            garage = loc.garage,
            props = { plate = plate, model = modelHash }
        })
        if vehicleId then
            -- qbx_garages/qbx_vehicles look for this statebag first before
            -- falling back to a plate lookup - set it so parking/ownership
            -- checks recognise this entity immediately.
            Entity(veh).state:set('vehicleid', vehicleId, true)
        else
            print(('[qbx-jobspawner] Could not register fleet vehicle in qbx_vehicles for garage "%s": %s')
                :format(loc.garage, errResult and errResult.message or 'unknown error'))
        end
    end

    activeVehicles[source] = { netId = netId, garage = loc.garage }
    GiveVehicleKeys(source, plate)

    return { ok = true, mode = 'new', netId = netId, plate = plate, garage = loc.garage }
end)

-- ═══════════════════════════════════════════════
--  TRACK VEHICLES SPAWNED VIA THE "EXISTING" (qbx_garages) PATH
-- ═══════════════════════════════════════════════
-- The client calls qbx_garages' own spawn callback directly for these, so it
-- reports the resulting netId back here to keep activeVehicles accurate for
-- the "store"/"replace previous vehicle" flows.

RegisterNetEvent('jobspawner:server:registerActiveVehicle', function(netId, garageName)
    local source = source
    activeVehicles[source] = { netId = netId, garage = garageName }
end)

-- ═══════════════════════════════════════════════
--  DELETE (fallback for locations with no garage configured)
-- ═══════════════════════════════════════════════

RegisterNetEvent('jobspawner:server:deleteVehicle', function(netId)
    local source = source
    -- only allow deleting the vehicle the server itself tagged as this player's active job vehicle
    if not activeVehicles[source] or activeVehicles[source].netId ~= netId then return end

    local veh = NetworkGetEntityFromNetworkId(netId)
    if veh and DoesEntityExist(veh) then
        DeleteEntity(veh)
    end
    activeVehicles[source] = nil
end)

-- Called after a successful qbx_garages:server:parkVehicle so our own tracking
-- table stops pointing at a now-deleted entity.
RegisterNetEvent('jobspawner:server:clearActiveVehicle', function(netId)
    local source = source
    if activeVehicles[source] and activeVehicles[source].netId == netId then
        activeVehicles[source] = nil
    end
end)

exports('GetActiveVehicle', function(source)
    return activeVehicles[source]
end)

AddEventHandler('playerDropped', function()
    local source = source
    activeVehicles[source] = nil
end)
