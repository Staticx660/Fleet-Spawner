local QBX = exports.qbx_core

local menuOpen = false
local nearLocation = nil      -- index into Config.Locations of the zone we're currently inside
local promptShown = false
local currentVehicleNet = nil    -- netId of the last vehicle this client pulled from a job spawner
local currentVehicleGarage = nil -- qbx_garages garage name that vehicle belongs to, or nil (throwaway vehicle)

-- ═══════════════════════════════════════════════
--  HELPERS
-- ═══════════════════════════════════════════════

local function getPlayerJob()
    local data = QBX:GetPlayerData()
    if not data or not data.job then return nil, 0 end
    return data.job.name, (data.job.grade and data.job.grade.level) or 0
end

local function locationUsableByPlayer(loc)
    local job, grade = getPlayerJob()
    if not job then return false end
    if loc.job ~= 'any' and loc.job ~= job then return false end
    if grade < (loc.minGrade or 0) then return false end
    return true
end

local function buildVehiclePayload(loc)
    local _, grade = getPlayerJob()
    local categories = {}
    for _, v in ipairs(loc.vehicles) do
        categories[v.category] = categories[v.category] or {}
        local requiredGrade = Config.GetRequiredGrade(loc, v)
        table.insert(categories[v.category], {
            model = v.model,
            label = v.label,
            requiredGrade = requiredGrade,
            locked = grade < requiredGrade
        })
    end
    return categories
end

local function waitForVehicle(netId, timeoutMs)
    local waited = 0
    local veh = NetToVeh(netId)
    while not DoesEntityExist(veh) and waited < (timeoutMs or 3000) do
        Wait(100)
        waited = waited + 100
        veh = NetToVeh(netId)
    end
    return DoesEntityExist(veh) and veh or nil
end

-- Applies the client-only flags a freshly created (non-garage) vehicle needs.
local function finalizeNewVehicle(veh)
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    SetVehicleNeedsToBeHotwired(veh, false)
    SetVehRadioStation(veh, 'OFF')
    SetPedIntoVehicle(PlayerPedId(), veh, -1)
    if Config.EngineRunning then
        SetVehicleEngineOn(veh, true, true, false)
    end
end

-- Stores the player's currently tracked vehicle. Uses qbx_garages' own park
-- flow (saves mods/props to the DB) when the vehicle belongs to a garage;
-- otherwise falls back to a plain delete for throwaway (non-persistent) fleet
-- vehicles. Returns true/false for success.
local function storeCurrentVehicle()
    if not currentVehicleNet then return true end
    local veh = NetToVeh(currentVehicleNet)

    if not DoesEntityExist(veh) then
        currentVehicleNet = nil
        currentVehicleGarage = nil
        return true
    end

    if currentVehicleGarage then
        local props = lib.getVehicleProperties(veh)
        local netId = currentVehicleNet
        lib.callback.await('qbx_garages:server:parkVehicle', false, netId, props, currentVehicleGarage)
        Wait(400)
        local stored = not DoesEntityExist(NetToVeh(netId))
        if stored then
            TriggerServerEvent('jobspawner:server:clearActiveVehicle', netId)
            currentVehicleNet = nil
            currentVehicleGarage = nil
        end
        return stored
    end

    TriggerServerEvent('jobspawner:server:deleteVehicle', currentVehicleNet)
    currentVehicleNet = nil
    currentVehicleGarage = nil
    return true
end

-- ═══════════════════════════════════════════════
--  BLIPS
-- ═══════════════════════════════════════════════

CreateThread(function()
    for _, loc in ipairs(Config.Locations) do
        if loc.blip then
            local blip = AddBlipForCoord(loc.zone.x, loc.zone.y, loc.zone.z)
            SetBlipSprite(blip, loc.blip.sprite)
            SetBlipColour(blip, loc.blip.color)
            SetBlipScale(blip, loc.blip.scale)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(loc.blip.label)
            EndTextCommandSetBlipName(blip)
        end
    end
end)

-- ═══════════════════════════════════════════════
--  ZONE / PROMPT LOOP
-- ═══════════════════════════════════════════════

CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local closest, closestDist = nil, Config.InteractDistance

        for i, loc in ipairs(Config.Locations) do
            local dist = #(coords - loc.zone)
            if dist < Config.InteractDistance then
                sleep = 0
                if dist < closestDist then
                    closest, closestDist = i, dist
                end
            end
        end

        if closest and locationUsableByPlayer(Config.Locations[closest]) then
            if not promptShown or nearLocation ~= closest then
                lib.showTextUI(('[E] Open %s'):format(Config.Locations[closest].label), {
                    position = 'left-center',
                    icon = 'car-side'
                })
                promptShown = true
            end
            nearLocation = closest

            if IsControlJustReleased(0, Config.OpenKey) and not menuOpen then
                OpenFleetMenu(closest)
            end
        elseif promptShown then
            lib.hideTextUI()
            promptShown = false
            nearLocation = nil
        end

        Wait(sleep)
    end
end)

-- ═══════════════════════════════════════════════
--  MENU
-- ═══════════════════════════════════════════════

function OpenFleetMenu(index)
    local loc = Config.Locations[index]
    if not loc then return end

    menuOpen = true
    if promptShown then
        lib.hideTextUI()
        promptShown = false
    end

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        label = loc.label,
        locationIndex = index,
        categories = buildVehiclePayload(loc),
        hasActiveVehicle = currentVehicleNet ~= nil and DoesEntityExist(NetToVeh(currentVehicleNet))
    })
end

RegisterNUICallback('closeMenu', function(_, cb)
    menuOpen = false
    SetNuiFocus(false, false)
    cb({})
end)

RegisterNUICallback('spawnVehicle', function(data, cb)
    local index = data.locationIndex
    local model = data.model
    local loc = Config.Locations[index]

    if not loc or not locationUsableByPlayer(loc) then
        cb({ ok = false, message = 'You are not authorised to use this fleet.' })
        return
    end

    local vehicleDef = nil
    for _, v in ipairs(loc.vehicles) do
        if v.model == model then vehicleDef = v break end
    end
    if not vehicleDef then
        cb({ ok = false, message = 'That vehicle is not part of this fleet.' })
        return
    end

    local _, grade = getPlayerJob()
    local requiredGrade = Config.GetRequiredGrade(loc, vehicleDef)
    if grade < requiredGrade then
        cb({ ok = false, message = ('Requires rank %d.'):format(requiredGrade) })
        return
    end

    if Config.DeletePreviousVehicle and currentVehicleNet then
        local stored = storeCurrentVehicle()
        if not stored then
            cb({ ok = false, message = 'Could not store your current vehicle - try storing it manually first.' })
            return
        end
    end

    local result = lib.callback.await('jobspawner:server:spawnVehicle', false, index, model)
    if not result or not result.ok then
        cb({ ok = false, message = (result and result.message) or 'Spawn failed.' })
        return
    end

    if result.mode == 'existing' then
        -- Re-spawning a fleet vehicle this player already owns in that garage -
        -- let qbx_garages do it so saved mods/props and keys come along for free.
        local netId = lib.callback.await('qbx_garages:server:spawnVehicle', false, result.vehicleId, result.garage, result.accessPoint or 1)
        if not netId then
            cb({ ok = false, message = 'Vehicle spawn failed - it may already be out, or this garage/access point is misconfigured in qbx_garages (check the server console).' })
            return
        end

        currentVehicleNet = netId
        currentVehicleGarage = result.garage
        TriggerServerEvent('jobspawner:server:registerActiveVehicle', netId, result.garage)

        local veh = waitForVehicle(netId)
        if veh and not IsPedInAnyVehicle(PlayerPedId(), false) then
            SetPedIntoVehicle(PlayerPedId(), veh, -1)
        end
        if veh and Config.EngineRunning then
            SetVehicleEngineOn(veh, true, true, false)
        end
    else
        -- Brand new throwaway or freshly-registered vehicle.
        currentVehicleNet = result.netId
        currentVehicleGarage = result.garage
        SetTimeout(Config.SpawnWarpDelay, function()
            local veh = waitForVehicle(result.netId)
            if veh then finalizeNewVehicle(veh) end
        end)
    end

    cb({ ok = true })
    menuOpen = false
    SetNuiFocus(false, false)
end)

RegisterNUICallback('storeVehicle', function(_, cb)
    if not currentVehicleNet then
        cb({ ok = false, message = 'No active fleet vehicle to store.' })
        return
    end
    local veh = NetToVeh(currentVehicleNet)
    if DoesEntityExist(veh) and #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(veh)) > 10.0 then
        cb({ ok = false, message = 'You need to be near the vehicle to store it.' })
        return
    end

    local stored = storeCurrentVehicle()
    if not stored then
        cb({ ok = false, message = 'Storing failed - make sure this location\'s garage is registered in qbx_garages.' })
        return
    end

    cb({ ok = true })
    menuOpen = false
    SetNuiFocus(false, false)
end)

-- Fallback ESC close (NUI also listens for Escape, this just guarantees focus drops)
CreateThread(function()
    while true do
        if menuOpen then
            if IsControlJustReleased(0, 322) then -- ESC
                menuOpen = false
                SetNuiFocus(false, false)
                SendNUIMessage({ action = 'close' })
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if promptShown then lib.hideTextUI() end
end)
