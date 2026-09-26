# MobTracker

Client-side creature list, tracker and spawn alerts for Valheim. Plain BepInEx, no other
dependencies, nothing to install on a server.

- **F7** opens the list of every creature loaded around you (roughly the zones within ~100-200 m -
  creatures further away do not exist on your client). Type to search by name or prefab name.
  **Esc** or F7 closes it.
- **Track** follows that one creature: a 3D arrow over your head, or with `GuideMode = GroundPath`
  a walkable line on the ground. The path builds over a few seconds on long distances; while it
  is missing or incomplete (flying/swimming targets, cliffs) the arrow shows as well.
- **View: nearby / all types** switches the list to every creature type the game has (including
  other mods' creatures), so you can Watch something that is not around. Search works there too.
- **Find area** (in the all-types view) works out where that creature's world-spawn rule can be met -
  biome, biome interior/edge, distance from the world centre, altitude, forest - straight from the
  world seed, so it covers unexplored and unloaded land and works on dedicated servers. The five
  nearest areas (at least 400 m apart) get map pins, the arrow points at the nearest, and the HUD
  message says what the rule is ("Swamp, 5000-8000m from centre, day+night"). Only the zone you
  are standing in rolls for spawns, so walk *through* the area rather than waiting beside it.
  Creatures that only come from spawners, raids or summons have no rule to find.
- **Guide: 3D arrow / ground path** switches the tracking guide without touching the config file.
- **Watch** alerts on that creature *type*: a centre-screen message and a ding whenever one
  starts existing near you (spawned or walked into range - the same thing to a client). Tamed
  creatures never alert. Watched types are listed at the bottom of the window; click one to remove it.

## Configuration (`BepInEx/config/com.mobtracker.plugin.cfg`)

| Setting | Default | |
|---|---|---|
| `General.ListKey` | `F7` | Toggle the list |
| `Tracking.GuideMode` | `Arrow` | `Arrow` or `GroundPath` |
| `Tracking.ArrowSize` / `ArrowHeight` | `0.6` / `2.6` | Metres |
| `Alerts.Watchlist` | empty | Prefab names, e.g. `Troll,Serpent`. Edit by hand to watch something not currently around |
| `Alerts.AlertRadius` | `0` | Only alert within this many metres; 0 = anywhere loaded |
| `Alerts.AlertVolume` | `0.8` | Ding volume |
| `Alerts.AutoTrack` | `true` | Start tracking a watched creature when it alerts (also a checkbox in the window). Never replaces a creature you are already tracking |

Build and deploy: `./deploy.ps1 -Project MobTracker`.
