Config = {}

-- ═══════════════════════════════════════════════
--  GENERAL OPTIONS
-- ═══════════════════════════════════════════════

Config.OpenKey = 38          -- E  (see docs.fivem.net/game-references/controls/ for other IDs)
Config.InteractDistance = 3.0 -- distance at which the "[E] Open Fleet" prompt appears
Config.DeletePreviousVehicle = true -- despawn the player's last spawned job vehicle when they pull a new one
Config.EngineRunning = true   -- spawn vehicles with the engine already on
Config.SpawnWarpDelay = 300   -- ms to wait for the vehicle to load before warping the player in

-- Which key system to hook into when a vehicle is spawned.
-- 'qbx'    -> exports.qbx_vehiclekeys:GiveKeys / whatever your key resource exports
-- 'none'   -> vehicle is left unlocked, no key resource called (edit server/main.lua GiveVehicleKeys to hook yours)
Config.KeySystem = 'none'

-- ═══════════════════════════════════════════════
--  GARAGE INTEGRATION (qbx_vehicles + qbx_garages)
-- ═══════════════════════════════════════════════
-- If a location has a `garage` set below, spawned vehicles are registered as
-- real qbx_vehicles rows (owned by the player pulling them) instead of throw-
-- away entities. That means:
--   - "Store Active Vehicle" hands the vehicle to qbx_garages' own parkVehicle
--     flow, which saves mods/props to the database instead of just deleting it.
--   - The vehicle keeps the SAME plate every time it's pulled, so a trunk/glove
--     box stash keyed by plate (ox_inventory, qb-inventory) keeps its contents
--     across store/retrieve instead of getting a fresh empty stash each spawn.
--   - Requesting a model the player already has parked in that garage re-spawns
--     that exact vehicle (with its saved mods) instead of creating a new one.
-- `garage` must match a garage name registered in qbx_garages (see README for
-- a matching example config). That garage needs one access point per unique
-- pad used below (spawnPoint / categorySpawns / per-vehicle spawnPoint) - the
-- `accessPoint` number on each is the 1-based index into that garage's
-- accessPoints list.
-- Set `garage = nil` on a location to keep the old throwaway behaviour for it.

-- ═══════════════════════════════════════════════
--  JOB SPAWN LOCATIONS
-- ═══════════════════════════════════════════════
-- job            = qbx job name (must match qbx_core jobs), or 'any' to let every job use this point
-- minGrade       = minimum job grade required to see/use this location at ALL
--                  (per-vehicle minGrade below can raise the bar further for
--                  specific vehicles, but never lowers it under this)
-- label          = shown in the NUI header
-- zone           = where the player stands to trigger the prompt
-- spawnPoint     = vector4 (x, y, z, heading) - DEFAULT pad (access point 1),
--                  used by any vehicle that doesn't get a more specific one
-- categorySpawns = optional per-category pad override, keyed by the `category`
--                  used in vehicle entries below:
--                    ['Air'] = { coords = vector4(...), accessPoint = 3 }
-- garage         = qbx_garages garage name to integrate with (nil = no persistence)
-- blip           = optional map blip
-- vehicles       = each entry:
--     model      = spawn name
--     label      = display name
--     category   = tab it appears under (also picks its categorySpawns pad)
--     minGrade   = optional. Overrides the location's minGrade for just this
--                  vehicle - use it to gate specific units behind rank (e.g.
--                  a SWAT chopper) without raising the bar for the rest of
--                  the fleet. Players below this see the card locked with the
--                  rank shown, rather than the vehicle just disappearing.
--     spawnPoint = optional vector4. Overrides BOTH the location's spawnPoint
--                  AND its categorySpawns pad for just this one vehicle - use
--                  it when a single vehicle needs its own dedicated spot even
--                  though it shares a category with others (e.g. a second,
--                  rank-locked helicopter that shouldn't spawn on top of the
--                  regular one).
--     accessPoint = the matching qbx_garages access point index for that
--                  vehicle-specific spawnPoint (only read if spawnPoint is set)

Config.Locations = {
Garages = {
    lspd_motorpool = {
        label = 'LSPD Motor Pool',
        type = 'private', -- or 'public'/'depot' per your qbx_garages version
        job = 'police',
        vehicleTypes = { 'car', 'helicopter' },
        accessPoints = {
            { coords = vec4(454.6, -1017.0, 28.4, 90.0), spawn = vec4(454.6, -1017.0, 28.4, 90.0) },  -- 1: Cruiser (spawnPoint)
            { coords = vec4(432.9, -1023.4, 28.4, 250.0), spawn = vec4(432.9, -1023.4, 28.4, 250.0) }, -- 2: Tactical
            { coords = vec4(441.4, -981.2, 45.6, 250.0), spawn = vec4(441.4, -981.2, 45.6, 250.0) },  -- 3: Air (roof helipad)
            { coords = vec4(452.9, -981.4, 45.6, 70.0), spawn = vec4(452.9, -981.4, 45.6, 70.0) },   -- 4: buzzard (per-vehicle override)
        },
    },
    ems_depot = {
        label = 'Pillbox EMS Depot',
        type = 'private',
        job = 'ambulance',
        vehicleTypes = { 'car', 'helicopter' },
        accessPoints = {
            { coords = vec4(292.0, -601.0, 43.2, 70.0), spawn = vec4(292.0, -601.0, 43.2, 70.0) },   -- 1: Rescue (spawnPoint)
            { coords = vec4(305.9, -595.4, 52.9, 160.0), spawn = vec4(305.9, -595.4, 52.9, 160.0) },  -- 2: Air
        },
    },
    mechanic_fleet = {
        label = 'Bennys Fleet Garage',
        type = 'private',
        job = 'mechanic',
        vehicleTypes = { 'car' },
        accessPoints = {
            { coords = vec4(-206.0, -1300.0, 31.3, 210.0), spawn = vec4(-206.0, -1300.0, 31.3, 210.0) }, -- 1: Recovery (spawnPoint)
            { coords = vec4(-227.8, -1287.6, 31.3, 40.0), spawn = vec4(-227.8, -1287.6, 31.3, 40.0) },  -- 2: Utility
        },
    },
}
-- Shared so both client (for the locked/rank UI) and server (for the actual
-- gate) always agree on what a vehicle requires. A vehicle's own minGrade can
-- only raise the bar above the location's minGrade, never lower it.
function Config.GetRequiredGrade(loc, vehicleDef)
    local required = loc.minGrade or 0
    if vehicleDef and vehicleDef.minGrade ~= nil and vehicleDef.minGrade > required then
        required = vehicleDef.minGrade
    end
    return required
end
