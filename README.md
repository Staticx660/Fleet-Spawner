# qbx-jobspawner

A NoPixel 5-styled job vehicle spawner for **QBox**. No vMenu involved — players
walk up to a marked location for their job, press **E**, and pick a vehicle
from a themed popup. Everything (job check, vehicle whitelist, spawning) is
validated server-side.

## Changelog
- **1.0.5** — corrected the example `qbx_garages` config: every access point
  needs a `spawn` field (where the vehicle is actually created), not just
  `coords` (the walk-up zone qbx_garages' own UI draws a marker at). Missing
  `spawn` makes `qbx_garages:server:spawnVehicle` fail internally and return
  `nil`, which is indistinguishable, from our side, from "already out" - if
  you were seeing that error for a vehicle that clearly wasn't out, this was
  why. Also recommends `enableClient = false` in qbx_garages so its own
  markers don't double up with this resource's UI, and reworded the client
  error message so it no longer claims "already out" as the sole cause.
- **1.0.4** — fixes "That vehicle could not be pulled from the garage (it may
  already be out)" after a server/resource restart: on startup, any fleet
  vehicle whose database row says OUT but isn't actually spawned anywhere
  gets forced back into its garage automatically (see "Fixing stuck 'already
  out' vehicles" below).
- **1.0.3** — per-vehicle spawn point/access point overrides (finer than the
  category pads from 1.0.2), and per-vehicle `minGrade` so specific units in a
  fleet can be rank-gated independently of the rest.
- **1.0.2** — `categorySpawns`: separate spawn pads per vehicle category
  (e.g. helicopters no longer spawn on top of cruisers), plus qbx_garages
  access-point mapping to match.
- **1.0.1** — `qbx_vehicles`/`qbx_garages` persistence: store/re-pull vehicles
  through the real garage system instead of hard-deleting on store.
- **1.0.0** — initial release.

## Requirements
- [ox_lib](https://github.com/overextended/ox_lib)
- [qbx_core](https://github.com/Qbox-project/qbx_core)
- [qbx_vehicles](https://github.com/Qbox-project/qbx_vehicles) + [qbx_garages](https://github.com/Qbox-project/qbx_garages) — **only needed if you want vehicles to persist** (see below). Without them, leave `garage = nil` on a location and it behaves like a throwaway spawner.

## Install
1. Drop this folder into your `resources` directory as `qbx-jobspawner`.
2. Add to your `server.cfg`, **after** `ox_lib`, `qbx_core`, `qbx_vehicles` and `qbx_garages`:
   ```
   ensure qbx-jobspawner
   ```
3. Edit `shared/config.lua`:
   - `Config.Locations` — one entry per job. Set `job`, `zone`, `spawnPoint`,
     an optional `blip`, `vehicles`, and `garage` (see next section).
   - `Config.KeySystem` — set to `'qbx'` and edit `GiveVehicleKeys` in
     `server/main.lua` to match whatever vehicle-keys resource you run.
     Only used for brand-new (non-garage) vehicles — vehicles pulled back out
     of a garage get keys from qbx_garages itself.
   - `Config.DeletePreviousVehicle` — if `true`, pulling a new fleet vehicle
     automatically **stores** the player's last one first (via the garage, if
     configured — see below) rather than deleting it outright.

## Persistence: keeping mods and trunk items

Previously "Store Active Vehicle" just deleted the entity — any modifications
done at a shop, and anything left in the trunk/glovebox, were gone the moment
you stored the car, because a brand new random plate was generated on every
pull (a fresh plate = a fresh, empty inventory stash for scripts like
ox_inventory/qb-inventory that key stashes off plate).

Setting `garage` on a location fixes this properly:

- The first time a player pulls a given model from that location, it's
  registered as a real row in `qbx_vehicles` (owned by that player, plate
  fixed) instead of a throwaway entity.
- **Store Active Vehicle** now calls `qbx_garages:server:parkVehicle`, which
  saves the vehicle's current mods/props to the database and only then
  deletes the entity.
- Pulling the *same model* again finds that existing vehicle and re-spawns it
  through `qbx_garages:server:spawnVehicle` — same plate, same mods, same
  trunk stash, exactly like taking a personal car out of a normal garage.
- If `Config.DeletePreviousVehicle` swaps out an active vehicle for a new
  one, the old one is stored (not deleted) the same way, so nothing is lost
  there either.

### Setting up the matching qbx_garages config

Each `garage` name in `shared/config.lua` needs a matching entry in your
`qbx_garages` config. Since locations can now have more than one spawn pad
(see "Multiple spawn pads per category" below), that garage needs one access
point per pad, **in the same order** the `accessPoint` numbers in
`categorySpawns` expect - `spawnPoint` is always access point 1.

**Every access point needs a `spawn` field, not just `coords`.** `coords` is
only the walk-up zone qbx_garages' own UI uses to draw its marker; the actual
vehicle-creation location it reads is a separate `spawn` field
(`garage.accessPoints[i].spawn` - see `qbx_garages/server/spawn-vehicle.lua`).
Leave `spawn` off and `qbx_garages:server:spawnVehicle` fails internally and
returns `nil` - which looks identical, from our side, to the vehicle already
being out. If you're seeing "could not be pulled from the garage (it may
already be out)" for a vehicle that clearly isn't out, this is almost always
why. Since we don't use qbx_garages' own on-screen markers at all (we have
our own zone/prompt), it's simplest to just set both to the same coords:

```lua
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
```

Since this resource has its own zone/prompt and menu, you almost certainly
don't want qbx_garages' own markers/blips/interact prompts showing up on top
of it too. Set `enableClient = false` in `qbx_garages`'s `config/client.lua`
to turn all of that off globally and use it purely as a backend - that's
what it's designed for third-party UIs like this one to do.

Check the exact field names against the `qbx_garages` version you're running
(its config shape has changed between releases) — the important part is that
each garage name lines up with `Config.Locations[i].garage`, and each access
point's `spawn` coords line up with the matching pad here (`spawnPoint` = 1,
then `categorySpawns` entries in `accessPoint` order).

If a location's `garage` is left as `nil`, it keeps the original simple
behaviour: a throwaway vehicle that gets hard-deleted on store, with no
database row and no persistence. That's a reasonable choice for a location
that hands out disposable pool cars on purpose.

### Multiple spawn pads, down to individual vehicles

By default every vehicle at a location spawns at `spawnPoint`. To keep
helicopters off the same pad as cruisers, or tactical rigs off the same spot
as either, add a `categorySpawns` table to that location keyed by the
vehicle's `category` field:

```lua
categorySpawns = {
    Tactical = { coords = vector4(432.9, -1023.4, 28.4, 250.0), accessPoint = 2 },
    Air      = { coords = vector4(441.4, -981.2, 45.6, 250.0), accessPoint = 3 },
},
```

Any category not listed there just falls back to `spawnPoint`. This applies
to both brand-new vehicles and vehicles pulled back out of the garage - a
saved helicopter always comes back on the helipad, never wherever it happened
to be parked when it was stored, since the pad is picked from the model's
category every time, not remembered per-vehicle.

If even that's not granular enough - say two helicopters share the `Air`
category but shouldn't spawn on top of each other - give the vehicle its own
`spawnPoint`/`accessPoint` directly, which wins over everything else:

```lua
{ model = 'buzzard', label = 'SWAT Buzzard', category = 'Air', minGrade = 4,
  spawnPoint = vector4(452.9, -981.4, 45.6, 70.0), accessPoint = 4 },
```

Resolution order for every spawn/re-spawn is: **vehicle's own `spawnPoint`**
→ **category's `categorySpawns` pad** → **location's default `spawnPoint`**.
Whatever access point number wins that lookup is what's requested from
`qbx_garages` too, so keep your garage's `accessPoints` list lined up with
every pad you actually use (see the example above - `buzzard` needs a 4th
access point added to `lspd_motorpool` at the same coords).

### Grade-gated vehicles

`minGrade` on a location gates the whole fleet - below it, a player doesn't
even see the `[E] Open` prompt. `minGrade` on an individual vehicle raises
the bar further for just that one vehicle (it can never go below the
location's own `minGrade`), e.g.:

```lua
{ model = 'polmav', label = 'Police Maverick', category = 'Air', minGrade = 3 },
```

Vehicles a player doesn't qualify for aren't hidden - they show up dimmed
with a lock icon and a `RANK n+` badge instead of a Deploy button, so players
can see what they're working toward. Clicking a locked card just shows the
required rank; the server independently re-checks grade on every spawn
request regardless of what the client sends, so this can't be bypassed by
editing the NUI.

### Fixing stuck "already out" vehicles

If you ever see **"That vehicle could not be pulled from the garage (it may
already be out)"** for a vehicle that clearly isn't out - most commonly right
after a server (or just this resource) restart - here's why: `qbx_garages`
tracks each vehicle's state (`GARAGED` / `OUT` / `IMPOUNDED`) in the database.
A restart wipes every vehicle entity in the world, but it does **not** touch
that database row, so a vehicle that was out when the server went down stays
marked `OUT` forever - and `qbx_garages` then (correctly, from its point of
view) refuses to spawn what it thinks is already a live vehicle.

`qbx_garages` has its own fix for this (`Config.autoRespawn` in its config,
which re-garages any stuck OUT vehicle on **its own** resource restart), but
that only helps if it's enabled and only runs when qbx_garages itself
restarts. Since this resource creates fleet vehicles independently, it can't
rely on that alone.

To cover it directly, `server/main.lua` runs a short startup routine (2s after
this resource starts) that checks every vehicle registered under each
configured `garage`: if a vehicle's plate isn't actually present in the world
right now, it's forced back into `GARAGED` via `exports.qbx_garages:SetVehicleGarage`,
regardless of what the database currently says. This is safe to run
unconditionally - that export is a no-op for anything that genuinely is
spawned. You'll see a line like:

```
[qbx-jobspawner] Reconciled 2 stuck fleet vehicle(s) back into garage "bwpd_motorpool" on startup.
```

in the server console right after a restart if it had to fix anything. It's
also worth turning on `Config.autoRespawn = true` in your `qbx_garages`
config as a second line of defense - it covers every personal vehicle on the
server too, not just fleet ones, and runs even earlier (on qbx_garages' own
restart rather than waiting on this resource's startup thread).


## How it works
- `client/main.lua` checks proximity to every configured zone, shows an
  ox_lib text prompt (`[E] Open <label>`) only to players whose job/grade
  matches that location, and opens the NUI on key press.
- The popup (`html/`) posts the chosen model + location index back to the
  client, which forwards it to an `ox_lib` server callback.
- `server/main.lua` re-validates the player's job, grade, and that the model
  is actually part of that location's fleet before spawning anything, then
  either creates a fresh vehicle (registering it in `qbx_vehicles` if a
  garage is configured) or tells the client to pull an existing one back out
  of the garage.
- "Store Active Vehicle" routes through `qbx_garages:server:parkVehicle` when
  the vehicle belongs to a garage (saving mods/props), or falls back to a
  plain delete for non-persistent locations. Either way it only ever acts on
  the vehicle the server itself tagged as that player's active job vehicle,
  so it can't be used to store/delete someone else's car.

## Customizing the look
All theme colors live at the top of `html/style.css` as CSS variables
(`--accent`, `--teal`, `--panel`, etc.) if you want to retint it away from
the amber/dark-navy NoPixel 5-inspired look.
