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
  {
        job = 'police',
        minGrade = 0,
        label = Fleet Garage',
        zone = vector3(-481.5995, 5976.5439, 30.9561),
        spawnPoint = vector4(-481.5995, 5976.5439, 30.9561, 313.3084), -- access point 1: cruisers/default
        garage = 'name_motorpool',
        categorySpawns = {
            Tactical = { coords = vector4(-469.1562, 6049.1011, 30.9942, 233.8854), accessPoint = 2 }, -- side yard
            Air      = { coords = vector4(-495.2672, 6002.4087, 32.7460, 182.7075), accessPoint = 3 },  -- roof helipad
        },
        blip = { sprite = 56, color = 29, scale = 0.8, label = 'name Garage' },
        vehicles = {
            --- { model = 'police3',  label = 'Rpolice33',              category = 'Cruiser', minGrade = 0 },


            -- Example of a vehicle-level spawnPoint override: this second
            -- chopper is rank-locked AND gets its own pad (access point 4)
            -- instead of stacking on the regular Air pad above.
            { model = 'buzzard',  label = 'SWAT Buzzard',                 category = 'Air', minGrade = 4,
              spawnPoint = vector4(452.9, -981.4, 45.6, 70.0), accessPoint = 4 },
        }
    },
    {
        job = 'ambulance',
        minGrade = 0,
        label = 'Name',
        zone = vector3(2522.3843, 4221.5757, 40.4175),
        spawnPoint = vector4(2521.0078, 4231.1318, 40.4180, 252.2602), -- access point 1: cruisers/default
        garage = 'name_motorpool',
        categorySpawns = {
            Tactical = { coords = vector4(-469.1562, 6049.1011, 30.9942, 233.8854), accessPoint = 2 }, -- side yard
            Air      = { coords = vector4(-495.2672, 6002.4087, 32.7460, 182.7075), accessPoint = 3 },  -- roof helipad
        },
        blip = { sprite = 56, color = 75, scale = 0.8, label = 'Garage' },
        vehicles = {
            --{ model = 'ambulance',  label = 'ambulance',              category = 'Rescue', minGrade = 0 },

        }
    },
    {
        job = 'mechanic',
        minGrade = 0,
        label = 'Bennys Fleet Garage',
        zone = vector3(-215.9, -1307.0, 31.3),
        spawnPoint = vector4(-206.0, -1300.0, 31.3, 210.0), -- access point 1: recovery trucks
        garage = 'mechanic_fleet',
        categorySpawns = {
            Utility = { coords = vector4(-227.8, -1287.6, 31.3, 40.0), accessPoint = 2 }, -- back lot
        },
        blip = { sprite = 446, color = 5, scale = 0.8, label = 'Fleet Garage' },
        vehicles = {
            { model = 'flatbed', label = 'Flatbed Tow Truck', category = 'Recovery', minGrade = 1 },
            { model = 'towtruck2', label = 'Tow Truck',       category = 'Recovery' },
            { model = 'sadler',  label = 'Service Sadler',    category = 'Utility' },
        }
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
