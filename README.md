# MobTracker

Client-side creature list, tracker and spawn alerts for Valheim. Plain BepInEx, no other
dependencies, nothing to install on a server.

- **F7** opens the list of every creature loaded around you - creatures further away do not exist on your
  client. How far that reaches follows the game's "Draw distance" graphics setting: roughly 130 to 290 m at
  the default and one step up. Creatures inside a dungeon above or below you are loaded too, and show about
  5 km away, because distances are measured in 3D. Type to search by name or prefab name. **Esc** or F7
  closes it.
- **Star filters**: two rows in the window, each a choice of *All*, *No star*, *1 star*, *2 stars* and
  *2+ stars* (two stars and above - natural spawns stop at two; the spawn command and mods can go higher).
  **List:** filters the nearby list; **Alerts:** filters which watched creatures alert and are auto-tracked.
  They are independent, so you can browse every star level while being alerted only for, say, two-star
  Trolls. Stars are shown as asterisks: `Deer` has none, `Deer *` one.
- **Track** follows that one creature: a 3D arrow over your head, or with `GuideMode = GroundPath`
  a walkable line on the ground. The path builds over a few seconds on long distances; while it
  is missing or incomplete (flying/swimming targets, cliffs) the arrow shows as well. Beyond 250 m
  only the arrow shows.
- **View: nearby / all types** switches the list to every creature type the game has (including
  other mods' creatures), so you can Watch something that is not around. Search works there too.
- **Find area** (in the all-types view) works out where that creature's world-spawn rule can be met -
  biome, biome interior/edge, distance from the world centre, altitude, forest - straight from the
  world seed, so it covers unexplored and unloaded land and works on dedicated servers. It follows
  your world's progress: a rule that waits for a boss (a world key such as `defeated_bonemass`)
  counts only once your world has that key, and a rule for an event (the Jotun invasion) is left
  out, since it spawns only inside the event's area. The five nearest areas (at least 400 m apart)
  get map pins, the arrow points at the nearest (until a watched creature's alert takes it over), and
  the HUD message says which rule placed it ("Swamp, 2000-8000m from centre, day+night"). Only the
  zone you are standing in rolls for spawns, so walk *through* the area rather than waiting beside it.
  Creatures that only come from spawners, raids, summons or breeding have no rule to find.
- **Find area's pins** are yours alone: they are never saved with your map or shared through a
  Cartography Table. Adding them turns the map's filter for that pin icon back on if you had it off.
  They go with **Clear pins** in the window (which also drops the area arrow), the next Find area, or
  leaving the world; the map's own delete (right click, long press, the gamepad button) removes an area
  pin in reach rather than a pin of yours next to it.
- **Find area's limits**: sub-biomes (Bat Swamp, Goblin Plains and the like) have spawn lists of their
  own, which it does not read - Bat_Swamp, TentaRoot_wild, Skeleton_Poison and Skeleton_Mountains are
  reported as having no rule - nor does it know which creatures a sub-biome keeps out, so a Lox area
  can be pinned inside Goblin Plains, where Lox never spawn. The game decides a spot's biome from the
  corners of its zone; Find area asks the seed at a few points, so at a biome border it can miss a zone
  that would do, and now and then pin one that will not. Terrain it cannot see from the seed (slope,
  lava, player bases, water depth) is not checked, so an area is "can spawn here", not "will".
- **Guide: 3D arrow / ground path** switches the tracking guide without touching the config file.
- **Watch** alerts on that creature *type*: a centre-screen message and a ding whenever one
  starts existing near you (spawned or walked into range - the same thing to a client). Tamed
  creatures never alert. Watched types are listed at the bottom of the window; click one to remove it.

## Configuration (`BepInEx/config/com.mobtracker.plugin.cfg`)

| Setting | Default | |
|---|---|---|
| `General.ListKey` | `F7` | Toggle the list |
| `General.ListStarFilter` | `All` | The list's star filter: `All`, `NoStars`, `OneStar`, `TwoStars` or `TwoOrMoreStars`, typed exactly (also the **List:** row) |
| `Tracking.GuideMode` | `Arrow` | `Arrow` or `GroundPath` |
| `Tracking.ArrowSize` / `ArrowHeight` | `0.6` / `2.6` | Metres |
| `Alerts.Watchlist` | empty | Prefab names, e.g. `Troll,Serpent`. The all-types view's Watch button adds any type; a hand edit of the file takes effect at the next start |
| `Alerts.AlertRadius` | `0` | Only alert within this many metres; 0 = anywhere loaded |
| `Alerts.AlertVolume` | `0.8` | Ding volume |
| `Alerts.AutoTrack` | `true` | Start tracking a watched creature when it alerts (also a checkbox in the window). Never replaces a creature you are already tracking |
| `Alerts.AlertStarFilter` | `All` | The alerts' star filter, same choices (also the **Alerts:** row) |

## Building

`dotnet build MobTracker.csproj -c Release` (needs the game with BepInEx; see the comment at the top of
`MobTracker.csproj`). `tools/preflight.ps1` checks a build against the installed game - run it after every
Valheim update - and `tools/deploy.ps1` installs one, moving the DLL it replaces into `retired/` in this folder
(`-KeepDir` to choose another). The tools find the game the way the build does: `-ValheimDir`, else the
`VALHEIM` environment variable. `tools/mutants.ps1` plants the defects preflight is there to catch, one at a
time in a copy under `build/`, and checks that each one fails it. `tests/` holds the rules that need no game
(`dotnet run` there).

## Credits

The original idea, concept and initial version of MobTracker are by **null** (also **nullptr**), published
here with their permission. The build tooling and the extensions from 0.2.0 on are conceived and directed by
DoomMachine and written by Claude, Anthropic's AI model, in Claude Code under DoomMachine's direction; the
commits are DoomMachine's, and Claude is credited here rather than as a co-author.

## History

- **0.2.0** - star filters for the list and for watch alerts. Find area follows boss progression and
  events, names the rule that placed the nearest pin, and its pins can be cleared; a right click on one
  used to delete the nearest pin of yours instead.
- **0.1.0** - the original MobTracker by null: creature list, watch alerts, tracking arrow and ground path
  (up to 250 m), and Find area.
