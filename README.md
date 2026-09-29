# MobTracker

Client-side creature list, tracker and spawn alerts for Valheim. Plain BepInEx, no other
dependencies, nothing to install on a server. Source, releases and issues:
https://github.com/DoomMachine/Valheim-MobTracker

- **F7** opens the list of every creature loaded around you - creatures further away do not exist on your
  client. How far that reaches follows the game's "Draw distance" graphics setting: roughly 130 to 290 m at
  the default and one step up. Creatures inside a dungeon above or below you are loaded too, and show about
  5 km away, because distances are measured in 3D. They alert like any other watched creature, but Auto-track
  and Always track nearest watched only ever take a creature on your side of the dungeon's entrance; a row's
  Track button still takes any. Type to search by name or prefab name. **Esc** or F7 closes it (the
  gamepad's B too).
- **While the list is open** your character and camera stand still: Tab does not open the inventory, the
  mouse wheel does not zoom, and the keys you type in the search do not reach a trader or the build
  controls (a few exceptions are under Known limits). A click, drag or scroll on the window never reaches
  the map, a trader or another game window under it; the map still takes clicks and drags beside the
  window. The rows hold still while the pointer is on the window, so Track and Watch act on the row you
  aimed at; they catch up as soon as it leaves. F7 does not open the list while you type in chat, a sign or a
  map pin's name, while the console is open, or over the pause menu, the build menu, the inventory or the Barber
  Station.
- **With TomTom or Wayfinder** installed, their window key (F11 by default) and skip key (if you bound one) keep
  working while the list is open, and F7 opens the list over TomTom's window.
- **Star filters**: two rows of toggle buttons in the window, *All*, *No star*, *1 star*, *2 stars* and
  *2+ stars* (two stars and above - natural spawns stop at two; the spawn command and mods can go higher).
  **List:** filters the nearby list (greyed out in the all-types view: a creature type has no stars); **Alerts:**
  filters which watched creatures alert, are auto-tracked and are picked by Always track nearest watched.
  The categories you mark combine: mark *No star* and *1 star* to list, or be alerted for, both, or *1 star*
  and *2 stars* for only those two. The marked buttons show as selected. With *All* marked, a click on a
  category marks it alone; a click on a marked category takes it off, and taking off the last one returns
  the row to *All*; a click on *All* resets the row. A change on the **Alerts:** row takes effect once the row
  has stayed the same for 1.5 seconds (see Known limits). With categories marked on the **List:** row, the nearby
  view's title names them ("MobTracker - 12 creatures, No star + 1 star"). The two rows are independent, so
  you can browse every star level while being alerted only for, say, two-star Trolls. Stars are shown as
  asterisks: `Deer` has none, `Deer *` one.
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
  get map pins, the arrow points at the nearest (until a watched creature's alert takes it over, with
  Auto-track on), and the HUD message says which rule placed it ("Swamp, 2000-8000m from centre,
  day+night"). Only the zone you are standing in rolls for spawns, so walk *through* the area rather
  than waiting beside it.
  Creatures that only come from spawners, raids, summons or breeding have no rule to find.
- **Find area's pins** are yours alone: they are never saved with your map or shared through a
  Cartography Table. Adding them turns the map's filter for that pin icon back on if you had it off.
  They go with **Clear pins** in the window (which also drops the area arrow), the next Find area, or
  leaving the world. The map's own delete (right click or the gamepad button) removes an area pin in
  reach rather than a pin of yours next to it; a touch long press does so only while a saved pin shown on
  the map (yours or a shared one) is also in reach, since the game starts it only near one.
- **Find area's limits**: sub-biomes (Bat Swamp, Goblin Plains and the like) have spawn lists of their
  own, which it does not read - Bat_Swamp, TentaRoot_wild, Skeleton_Poison and Skeleton_Mountains are
  reported as having no rule - nor does it know which creatures a sub-biome keeps out, so a Lox area
  can be pinned inside Goblin Plains, where Lox never spawn. The game decides a spot's biome from the
  corners of its zone; Find area asks the seed at a few points, so at a biome border it can miss a zone
  that would do, and now and then pin one that will not. Terrain it cannot see from the seed (slope,
  lava, player bases, water depth) is not checked, so an area is "can spawn here", not "will".
- **Guide: 3D arrow / ground path** switches the tracking guide from the window (the choice is saved
  as `Tracking.GuideMode`).
- **Watch** alerts on that creature *type*: a centre-screen message and a ding (`AlertVolume`, under the
  game's Volume and Effect volume settings) whenever one
  starts existing near you (spawned or walked into range - the same thing to a client). Tamed
  creatures never alert. Watched types are listed at the bottom of the window; click one to remove it.
- **Always track nearest watched** (a checkbox in the window, off by default) is for hunting one kind of
  creature for its drops. When the creature you are tracking is of a watched type and is lost - killed, or no
  longer loaded on your client (out of range, despawned) - the tracker says "Lost track of" as always, waits 5
  seconds, then points at the nearest creature of that type that passes the watch alert's filters: the
  **Alerts:** stars, `AlertRadius`, never a tamed one, and only on your side of a dungeon entrance. If there
  is none yet, it keeps looking once a second,
  without a message, and points at the nearest one as soon as one turns up. A watch alert that names that type
  during the wait still shows and dings, but leaves the choice to the wait; with an `AlertRadius` set, a creature
  that alerted and has walked out of the radius by then is taken only once it is back inside. The wait ends when
  you track something else (by hand, Find area, or Auto-track on an alert for another watched type), turn the
  option off, unwatch the type or die. **Stop tracking** stays in the window (F7) while it waits, and calls it
  off; nothing else shows that it is waiting. Losing a tamed creature, or stopping the tracking yourself, never
  starts one.

## Installing

MobTracker needs BepInEx 5 for Valheim (the BepInExPack for Valheim, for example). Download
`MobTracker-<version>.zip` from this repository's Releases, remove any older `MobTracker.dll` from
`BepInEx/plugins/`, and put the `MobTracker.dll` from the zip there; the zip also holds this README and the
licence. The settings in `BepInEx/config/com.mobtracker.plugin.cfg` are kept from one version to the next, and
a new version adds its own with their defaults. When the game starts, `BepInEx/LogOutput.log` says
`MobTracker <version> loaded`. To remove it, delete `MobTracker.dll`, and the .cfg too to forget the settings.

## Configuration (`BepInEx/config/com.mobtracker.plugin.cfg`)

| Setting | Default | |
|---|---|---|
| `General.ListKey` | `F7` | Toggle the list (Escape or the gamepad's B also close it). A key the game cannot read (WheelUp, F13, Plus...), or the left, right or middle mouse button, does nothing and says so once in the log; keys the game ignores outright - Mouse5, Mouse6, F16 to F24 and the numbered-joystick buttons - never fire, with no warning |
| `General.ListStarFilter` | `All` | The list's star filter (also the **List:** row): `All`, or one or more of `NoStars`, `OneStar`, `TwoStars` and `TwoOrMoreStars` separated by commas, e.g. `NoStars, OneStar` for both. Any case; the window's labels (`No star`, `1 star`, `2 stars`, `2+ stars`) work too, and a number counts stars: 0-3, 3 = two or more, 4 = All. `All` anywhere in the list means All; anything else is ignored with a warning in the log, and with nothing valid the filter works as All. A text setting since 0.4.0 (a single name or number from a 0.3.x file reads as before), so ConfigurationManager shows a text box for it rather than a list, and applies it at every keystroke |
| `Tracking.GuideMode` | `Arrow` | `Arrow` or `GroundPath` |
| `Tracking.ArrowSize` / `ArrowHeight` | `0.6` / `2.6` | Metres |
| `Alerts.Watchlist` | empty | Prefab names, e.g. `Troll,Serpent`. The all-types view's Watch button adds any type. Edit the file by hand with the game closed: it takes effect at the next start, and while the game runs a setting changed in the window (Watch or Unwatch, the star rows, Guide, the two tracking checkboxes) rewrites the file |
| `Alerts.AlertRadius` | `0` | Only alert (or re-track, below) within this many metres; 0 = anywhere loaded |
| `Alerts.AlertVolume` | `0.8` | Ding volume; the game's Volume and Effect volume settings apply on top of it |
| `Alerts.AutoTrack` | `true` | Start tracking a watched creature when it alerts (also a checkbox in the window). Never replaces a creature you are already tracking, nor the choice Always track nearest watched is waiting to make for that type, nor takes a creature on the other side of a dungeon entrance |
| `Alerts.AlertStarFilter` | `All` | The alerts' star filter (also the **Alerts:** row), written the same way: e.g. `OneStar, TwoStars` alerts only for one- and two-star creatures. A text setting since 0.4.0, like `ListStarFilter`, except that a change in the window or in ConfigurationManager takes effect only once the filter has stayed the same for 1.5 seconds (see Known limits); edit the file by hand with the game closed, as for `Watchlist` |
| `Alerts.AlwaysTrackNearestWatched` | `false` | When a tracked creature of a watched type, not a tamed one, is lost, track the nearest one of that type that passes the watch alert's filters and is on your side of a dungeon entrance: 5 seconds later, or, if there is none then, at the first once-a-second look that finds one (also a checkbox in the window) |

## Known limits

- The list, alerts and tracking see only what your client has loaded (see **F7**); a creature near the edge of
  that range can be out of sight.
- In multiplayer, for a creature another player's game runs: it stays listed through its death animation, and
  "Lost track of" comes only when it is removed; and its tamed state reaches your game up to about a second late,
  so with an `AlertRadius` set one tamed just before it comes within the radius can alert, and losing one just
  tamed can start Always track nearest watched.
- A watched creature inside a dungeon still alerts while you are outside it, and the other way round, but is not
  auto-tracked; with `AlertRadius` at 0 it has then had its alert, so going in does not alert it again.
- While the pointer rests on the window its rows do not update: a creature killed meanwhile keeps its row, and
  its Track button does nothing, until the pointer leaves the window.
- A change on the **Alerts:** row reaches the alerts, Auto-track and Always track nearest watched once the row
  has stayed the same for 1.5 seconds - 1.5 seconds after your last click that changed it (seconds of game time,
  which stands still while the game is paused); the buttons and the cfg change at once, and watched creatures
  are checked every second. So what the row passes through while you click is not seen, as long as each click
  comes within 1.5 seconds of the one before: taking off the only marked category, which returns the row to
  *All*, no longer lets every watched creature alert before your next click. Pause for 1.5 seconds or more
  between two clicks, though, and the row as it stands then applies: a creature it lets through can alert, and
  has then had its alert. Marking the new category before taking the old one off never passes through *All*.
  Typed in ConfigurationManager, which changes the setting at every keystroke, `AlertStarFilter` works the same
  way: the text applies 1.5 seconds after it last changed, so a half-typed value (a text with no word it knows
  yet reads as *All*) is not seen as long as each keystroke comes within 1.5 seconds of the one before. Pause that
  long while typing, though, and what is typed so far applies (*All*, for text it cannot read). Each value it
  cannot read logs a warning.
- Over a runestone's or a readable item's text, Escape closes the list and the text together, and typing `e` in
  the search closes the text.
- With TomTom's, Wayfinder's or MeasurementTracker's window open as well, one Escape closes both windows. F5
  opens the console over the list; the first Escape then closes the console, the next one the list.
- A TomTom or Wayfinder key bound to a letter, a digit or another key that types also acts while you type that
  character in the list's search (their default keys - F11, and no skip key - are not such keys).
- A drag begun on the map beside the window and let go over it at once counts as a click on the map where you
  let go.
- With a gamepad, the left stick still pans an open map under the list, and the alternative layouts' alternate
  placement toggle still reaches the game.
- With `GuideMode = GroundPath`, the game's navigation tiles along the line are kept from being rebuilt while you
  track, so a change made meanwhile - a wall built, ground levelled, a tree cut - may not show in the line, nor in
  how creatures on those tiles find their way. The arrow (the default) leaves them alone.
- The window and the tracking label grow with your screen height above 1080p; they do not follow the game's GUI
  scale setting. The window's size and place are not kept from one start of the game to the next.

## Building

`dotnet build MobTracker.csproj -c Release` (needs the game with BepInEx; see the comment at the top of
`MobTracker.csproj`; run it from Windows PowerShell or cmd - from a PowerShell 7 session the build's publicize
step fails). `tools/preflight.ps1` checks a build against the installed game - run it after every
Valheim update - and `tools/deploy.ps1` installs one, moving the DLL it replaces into `retired/` in this folder
(`-KeepDir` to choose another). The tools find the game the way the build does: `-ValheimDir`, else the
`VALHEIM` environment variable; they take named arguments only, and reject a misspelt one. When a tool is
started with `powershell -File ...`, write a quoted game path without a trailing backslash: `"...\Valheim\"`
can end in an escaped quote there (always from `cmd.exe` or a shortcut; from Windows PowerShell when the path
has a space). `tools/mutants.ps1` plants the defects preflight is there to catch, one at a time in a copy under
`build/`, and checks that each one fails it. `tools/package.ps1` makes a release's zip from a clean checkout.
Run in Windows PowerShell 5.1, in a plain shell, with the same .NET SDK and against the same Valheim and
BepInEx files, the same commit gives the same bytes, so a downloaded zip can be checked against its tag; each
release's notes name the versions used. `tests/` holds the rules that need no game (`dotnet run` there), and
`tools/unit-mutants.ps1` plants defects in those rules, one at a time in a copy under `build/`, and checks that
the tests fail on each.

## Credits

MobTracker is by **null** (also **nullptr**) and **DoomMachine**.

- **null** (**nullptr**): the original idea, concept and initial version (0.1.0), published here with their
  permission.
- **DoomMachine**: the build tooling and the extensions from 0.2.0 on, conceived and directed by DoomMachine.
  The code, tests and docs of the tooling and of these extensions were written by Claude, Anthropic's AI
  model, in Claude Code under DoomMachine's direction; the commits are DoomMachine's, and Claude is
  credited here rather than as a co-author.

The copyright holder is DoomMachine (see `LICENSE`).

## History

- **0.4.1** - fixes. Taking off the only marked category on the **Alerts:** row no longer lets every watched
  creature alert until your next click: a change on that row, or to `AlertStarFilter` in ConfigurationManager,
  now takes effect once it has stayed the same for 1.5 seconds, so what the row passes through while you click,
  or a half-typed value, is not seen. F7 no longer opens the list over the Barber Station, where the Escape that
  closed the list also cancelled the barber and put back the hair and beard you had. The safety checks catch more
  planted defects, and `tools/unit-mutants.ps1` checks the unit tests the same way. Not yet played in the game.
- **0.4.0** - star filters take several categories at once: the **List:** and **Alerts:** rows are five toggle
  buttons each, so you can list or be alerted for, say, no-star and one-star creatures together, or only one-
  and two-star ones; a click on *All* resets a row, and the window's title names the categories the list shows.
  `ListStarFilter` and `AlertStarFilter` are now text, such as `NoStars, OneStar`; a single name or number
  from a 0.3.x configuration reads as before. Not yet played in the game.
- **0.3.1** - fixes. While the list is open: the mouse wheel no longer zooms the camera, Tab no longer opens
  the inventory, and a click on the window no longer reaches the map or a game window under it (on the map a
  right click deleted a pin, a middle click pinged everyone, a double click left a pin the Cartography Table
  shares); Escape now closes the list, as this README already said, and so does the gamepad's B; F7 no longer
  opens the list while you type or over the pause menu, the build menu or the inventory; TomTom's and Wayfinder's
  keys work. A ListKey the game cannot read no longer throws on every frame. Auto-track and Always track nearest
  watched no longer point the arrow at a creature on the other side of a dungeon entrance; the rows hold still
  under the pointer; the window keeps a corner on screen; the ding follows the game's Volume and Effect volume;
  a creature another mod broke can no longer stop the alerts; setting descriptions corrected or brought up to date. Not yet
  played in the game.
- **0.3.0** - Always track nearest watched (an option, off by default): when a tracked creature of a watched
  type is lost, the tracker moves on to the nearest one of that type. Ran through play sessions without errors;
  the new option has not yet been seen acting in the game.
- **0.2.0** - star filters for the list and for watch alerts. Find area follows boss progression and
  events, names the rule that placed the nearest pin, and its pins can be cleared; a right click on one
  used to delete the nearest pin of yours instead. Ran through a play session without errors; its new features
  not yet confirmed in the game.
- **0.1.0** - the original MobTracker by null: creature list, watch alerts, tracking arrow and ground path
  (up to 250 m), and Find area.
