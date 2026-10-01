# Open items and future work

The one list of what is untested, unverified, open or only an idea for MobTracker - so none of it has to be worked out
again. It lives with the code, so each release can check it. What a player meets is in the README's "Known limits";
what each release changed is in its "History".

As of **0.5.1**.

## Keeping it up to date

- When an item is done, move it to **Done** with the version that did it, and name it in the README's History line for
  that release if a player could notice the change.
- When one is found, add it to its section under the next free id. Ids are never reused, and an item keeps its id when
  it moves between sections, so commits and release notes can name them ("fixes OI-2").
- An item under **Not yet tried in play** or **Not verified** moves out once it has been seen in the game. If it
  confirms a release, drop "Not yet played in the game." (or the like) from that release's History line - a text-only
  change, the version stays.
- Before each release, compare the README's **Known limits** with this file: every limit there has a row in the table
  under **Known limits** below, and a limit a player can meet that the README does not mention is listed below it.
- Change "As of" to the release's version.

Ids: **OI** open issues, **KL** known limits, **LT** checks in play, **SC** safety checks, **TL** tooling, **FW** future
work.

## Not yet tried in play

0.5.1 has not been played yet. 0.5.0 ran through a long play session, with several logouts, without errors: at its
first world entry it set back the **Alerts:** filter 0.4.1 had saved (LT-14), but nothing was watched in it, so a reset
at a logout was not seen. 0.4.1 - and with it the changes of 0.4.0 and 0.3.1 - ran through a long play session
without errors, in which a watch alert came, the `AlertStarFilter` held several categories at once, types were watched
and unwatched and the guide mode was switched; none of the checks below was run in it as written. 0.3.0 and 0.2.0 each
ran through play sessions without errors, but Always track nearest watched (0.3.0) has not been seen acting, and
0.2.0's new features have not been confirmed in the game (LT-2, LT-4 to LT-6).

Single player is enough except for LT-7 and LT-11's second check (a dedicated server). Where creatures of a given star
level are needed, the console's `spawn` command (with `devcommands` on) makes them: level 1 is no star, 2 one star, 3
two stars. Afterwards, `BepInEx/LogOutput.log` should have no exception naming MobTracker.

### LT-14 0.5.0: one game session

- [x] The log says `MobTracker 0.5.0 loaded`, and the cfg has `KeepBetweenSessions = false` under `[General]`.
- [x] With `KeepBetweenSessions` off, a filter 0.4.1 saved in the cfg is set back at the first world entry, and the log's
  `Game session changed and KeepBetweenSessions is off` line names it.
- [ ] With `KeepBetweenSessions` off, watch a type and set both star rows to something other than *All*. Log out and
  enter a world again: nothing is watched, both rows are on *All*, and the log has a `Game session changed and
  KeepBetweenSessions is off` line naming what was set back.
- [ ] The same, but quit the game from the world and start it again: at the main menu the cfg still holds them
  (KL-23); once you enter a world, nothing is watched and both rows are on *All*.
- [ ] Die and respawn with a type watched and a star row set: both are kept.
- [ ] With `KeepBetweenSessions` on, what you watch and both rows are kept across a logout and across a restart of the
  game, and no `Game session changed` line appears.
- [ ] With a watchlist saved by 0.4.1 or earlier in the cfg, turn `KeepBetweenSessions` on at the main menu, before
  entering a world (in ConfigurationManager, or in the cfg with the game closed - 0.5.0 adds the line at its first
  start), then enter one: the watchlist and both rows are as the older version left them.
- [ ] Log out with text in the list's search and the all-types view on, then enter a world: the list opens with the same
  search and view.

### LT-15 0.5.1's fixes

- [ ] While tracking, Ctrl+F3 hides the arrow, the ground-path line and the "Tracking:" label, and Ctrl+F3 again brings
  them back.
- [ ] While tracking, the guide is hidden while you sleep in a bed, and comes back when you wake.
- [ ] While tracking, the guide is hidden through a portal. When the tracking survives the teleport - a Find area does,
  unless you arrive within 30 m of it ("Reached ...") or a watch alert takes it over with Auto-track on (the guide then
  comes back for that creature), and a creature only when it is still within loading range of the arrival portal
  (LT-11: roughly 130 to 290 m) - the guide comes back on arrival. A creature left farther behind is unloaded during
  the teleport and lost: its "Lost track of" message comes while the screen is still dark, so it may not be seen, and
  its guide does not come back.
- [ ] With a bed set, while tracking, the guide is hidden from the moment you die; about 10 seconds later the tracking
  ends (OI-4).
- [ ] With the game closed, set `ArrowSize = 0` and `ArrowHeight = 9` in the cfg: at the next start the arrow is 0.1 m
  long and 5 m up, and the cfg says `0.1` and `5`.

### LT-1 0.4.1's fixes

Run on the current version.

- [ ] The log has no `AlertStarFilter` or `ListStarFilter` warning, and with `KeepBetweenSessions` on, an existing
  cfg's filters show on the star rows as before.
- [ ] Watch `Boar`, set **Alerts:** to *2 stars*, and have plain boars around. Click *2 stars* off and *1 star* on
  within about a second: no "Boar detected" for the plain boars. A one-star boar then alerts.
- [ ] With **Alerts:** on *1 star* and fresh plain boars around, click *1 star* off and wait 3 seconds: the row is on
  *All*, and the plain boars alert (KL-5).
- [ ] With **Alerts:** on *No star*, spawn a one-star boar nearby (it does not alert). Click *1 star* on and *No star*
  off within about a second: its alert comes about 1.5 to 2.5 seconds after the last click, not at once.
- [ ] Always track nearest watched follows the row once it has held still: with the option on, **Alerts:** on *1 star*,
  and a plain and a two-star creature of the watched type around, track a one-star one and kill it; within 2 seconds
  click *1 star* off, then *No star* on. The re-track, 5 seconds after the loss, takes the plain one, never the
  two-star one.
- [ ] At a Barber Station, with its window open, F7 does not open the list; after leaving it, F7 does.
- [ ] Open the list (F7) before ConfigurationManager's window: F7 does not reach the list while that window blocks
  input (KL-17). With `Boar` watched, plain boars and a two-star boar around, and `AlertStarFilter` at `OneStar`, type
  `TwoStars` over it at an ordinary pace: the **Alerts:** marks follow each keystroke, the log warns about each
  half-typed value, no plain boar alerts, and the two-star boar alerts about 1.5 to 2.5 seconds after the last key.
  Then type `Tw`, wait 3 seconds and finish the word: the plain boars alert (KL-5).

### LT-2 0.4.0's star rows

Run on the current version. Nor have 0.2.0's star filters, which the rows replaced, been confirmed in the game.

- [ ] Each row's five buttons show their whole label, and the marked ones look selected.
- [ ] Categories combine in the list and in the alerts: with *No star* and *1 star* marked on **Alerts:**, plain and
  one-star creatures of a watched type alert, and two-star ones do not.
- [ ] In the nearby view the title names the **List:** categories; in the all-types view the **List:** row is greyed
  out.
- [ ] After a click the cfg holds text such as `NoStars, OneStar`.
- [ ] With `KeepBetweenSessions` on, a 0.3.x value such as `TwoStars`, written in the cfg with the game closed, opens
  with that one category marked.
- [ ] ConfigurationManager shows both filters as text boxes.

### LT-3 0.3.1's fixes

Run on the current version.

- [ ] F7, then Escape at once: the list closes and the pause menu does not open. With a gamepad, B closes it and the
  character does not jump.
- [ ] F5 over the list opens the console; the first Escape closes the console and the list stays; the next closes the
  list, and the pause menu does not open.
- [ ] With the list open, Tab opens nothing, and the mouse wheel scrolls the list but never zooms the camera, over the
  window or off it.
- [ ] With a gamepad and the list open, Y and the D-pad do nothing.
- [ ] Open the large map with one of your own pins under where the window will be, then F7. A right click on the list
  over the pin leaves the pin; a middle click pings no one; a double click opens no pin-name box; dragging the list by
  its title does not pan the map. The map beside the list still drags.
- [ ] A map drag begun beside the window and let go over it stops panning.
- [ ] At a trader, a click on the list over the trader's window does nothing to it, and typing `e` in the search leaves
  it open. Escape closes the list, then the trader.
- [ ] F7 does nothing while you type in chat, or over the pause menu, the build menu or the inventory.
- [ ] With a hammer and a piece selected, typing `qe` in the search does not cycle the snap point.
- [ ] With TomTom installed, the log has a line ending `found: its keys work while the MobTracker list is open.`, and
  F11 opens TomTom's window over the list, with W, A, S and D still not moving the character.
- [ ] With TomTom's window open, F7 opens the list over it. With chat open and text typed, F11 does not open TomTom's
  window.
- [ ] With Wayfinder instead of TomTom: its log line, and F11 over the list, as for TomTom.
- [ ] Rows hold still while the pointer rests on the window, and update as soon as it leaves.
- [ ] Dragged off the right or bottom edge, the window keeps a strip and its title on screen.
- [ ] On a screen taller than 1080 pixels: a click on the window near its right or bottom edge does not reach the map
  under it, and dragged off the right edge the window keeps a strip on screen.
- [ ] With nothing watched and **Always track nearest watched** ticked, the window's last line names the option and
  wraps rather than widening the window.
- [ ] With `AlertVolume` above 0, an alert dings and the log names the mixer group it plays on; with the game's Effect
  volume at 0, the next alert does not ding.
- [ ] A `ListKey` of `WheelUp` or `Mouse0` gives one warning in the log, not one per frame, and attacking does not
  open the list.
- [ ] Setting `ListKey` back to `F7` in ConfigurationManager, then closing its window, makes F7 work at once.
- [ ] Auto-track and Always track nearest watched never take a creature on the other side of a dungeon entrance
  (needs a dungeon whose creatures are loaded, and `devcommands`).

### LT-4 Always track nearest watched acting

It has run in play sessions without errors, but has never been seen acting.

- [ ] Watch a type, tick **Always track nearest watched**, track one of that type and kill it: "Lost track of" shows,
  and about 5 seconds later the arrow points at the nearest one of that type that the **Alerts:** stars let through.
- [ ] With none of that type around, it takes the first one that turns up.

### LT-5 Find area completing a search

- [ ] In the all-types view, **Find area** on a creature of the open land (Greydwarf, say): up to five pins, the
  nearest in the biome the HUD message's rule names, the arrow pointing at the nearest, and the log's `world spawn,
  nearest area by:` and `area at` lines.
- [ ] On a creature whose rule waits for a boss your world has not beaten: the HUD says it spawns in the wild only once
  this world has the key it names, and any earlier area pins and the area arrow are cleared.

### LT-6 Find area's pins: right click and Clear pins, with TomTom

Needs LT-5 first.

- [ ] On the large map, a right click on an area pin removes it and none of your own pins.
- [ ] **Clear pins** removes the rest and the area arrow.
- [ ] With TomTom, one right click where a TomTom waypoint and an area pin are both in reach removes exactly one of
  them, TomTom's first.

### LT-7 Multiplayer: area pins stay local

Find area's pins are added with the game's save flag off and no owner, so they are never written to a Cartography Table
or seen by another player. The code and the safety checks show this; no multiplayer session has.

- [ ] In multiplayer, after a Find area, the area pins do not reach a Cartography Table or another player's map.

### LT-8 The ground-path guide

`GuideMode = GroundPath` has never been seen working on the current game version. It reaches navigation members the
game does not make public, and whether the game's runtime allows that has not been tested.

- [ ] Track a creature within 250 m and click **Guide: 3D arrow** to switch to the ground path: a line appears, and the
  log shows no access error.

If it fails: fall back to the game's public path query, or turn GroundPath off with a reason in the log.

## Not verified

Worked out from the code, or only expected, and not seen in play. The check under each would settle it.

### LT-9 A respawn with no bed, near the start

Tracking stops on any frame with no player; the alert memory is cleared only when its once-a-second check finds none.
After a death with no bed set, the new character may appear at the start so quickly that this lasts about a frame, and
whether either then carries over to the new character is not known.

- [ ] With no bed set, track a creature and let a watched one alert; die close to the start, where you will respawn.
  After the respawn, check whether the arrow still shows and whether that creature alerts again.

If either carries over: also reset both when the local player changes.

### LT-10 A ding on every alert

The ding is made by a sample-reader callback whose position is never reset. Unity is expected to read such a clip
once; if it ever read it again, later dings would be silent. A position-reset callback would remove the question.

- [ ] With `AlertVolume` above 0, let several alerts come in one session: each one dings.

### LT-11 How far creatures load

The README's "roughly 130 to 290 m" comes from the game's code, not from measurement.

- [ ] At the default Draw distance, and one step up, note the farthest creature the list shows outside dungeons.
- [ ] The same on a dedicated server. The game lets a server lower the range (you get the smaller of its value and
  yours); a dedicated server started without `-simulationdistance` uses the game's original range
  (`SimulationDistance.OriginalDistance`, level 2 in the code) - read from the code, not measured.

### LT-12 Layout and the window's mouse state

- [ ] With the list open and its window at its default place, lose a tracked creature: the "Lost track of" message at
  the top left can be read.
- [ ] During a boss fight or an event, the tracking label does not cover the boss bar or the event text.
- [ ] Close the list with F7 while holding the mouse button down on one of its buttons, let go and reopen it: the rows
  update as usual, not only after the next click.

### LT-13 Right button while hanging from a grappling line

Not known: whether anything a player can get in the current game version fires a grappling line. If something does,
holding the block button (the right mouse button, or the gamepad's) while the list is open and you hang from one would
let go of it: the game reads that button there with no test the list can hold shut.

- [ ] If you can hang from a grappling line: open the list and hold the right mouse button on the window. If the
  character lets go, add it to the README's Known limits.

### OI-3 Edge cases never seen

These would matter only if they happen:

- A creature without the usual root collider could make the arrow's aim fail on every frame and freeze the arrow. A
  fallback to the creature's position would remove that.
- A creature the game deactivates while it is alive would stay listed.

## Small fixes still open

None is serious. The OI item was found by reading the code, not seen in the game; the SC items are for contributors.

**In the game**

### OI-4 Tracking ends at a death

About 10 seconds after you die the game removes your body, and the tracking usually ends with it, with no message;
after the respawn nothing is tracked until you track something again (a row's Track button, or Find area), or a watch
alert does with Auto-track on. After a respawn at once (no bed, near the start) it may carry on (LT-9). (Always track
nearest watched ends its wait at a death by design.)
Whether tracking should carry on after the respawn is open: the tracker would have to keep its target while there is
no player, and say so.

**Safety checks**

`tools/preflight.ps1` checks a build's IL against what the code must do, and `tools/mutants.ps1` plants defects to
prove that each check fails when it should. These are the known gaps.

### SC-3 Two re-track variants the checks do not model

A `NearestWatched.Update` that, with no player, returns early after cancelling something else; and ways of picking a
creature other than the nearest that keep the instruction shape the checks look for.

### SC-4 What a new check needs

Many checks match exact IL shapes, so a legitimate rewrite of the code they cover (the re-track, Auto-track's line,
the star rows, the window clamp, the game session) fails them: re-read the IL and rewrite the check rather than loosen
it. The unit tests link only `StarFilter.cs` and `Rules.cs`; the rest is proved by preflight and planted defects. So
prove each new check with defects planted in how its answer is used, its true path, how two tested facts combine, its
loop bounds and its operands - not only in its wiring.

## Known limits

The README's **Known limits** section, with the **Find area's limits** and **Always track nearest watched** paragraphs
above it, says what a player meets. It is not repeated here. The table gives, for each of those limits, why it stays
and what would change it; the items after it are limits that section does not list - where another part of the README
states one, the item says so.

| Id | README limit | Why it stays, or what would change it |
|---|---|---|
| KL-1 | Only what your client has loaded | The game's own loading; a client-side mod cannot see further. |
| KL-2 | Multiplayer: another player's creatures | The game's own multiplayer behaviour: a creature's death and tamed state reach the other players' games later. |
| KL-3 | A dungeon's creatures alert across its entrance | Auto-track and Always track nearest watched keep to your side since 0.3.1. Filtering the alerts by side as well would change what alerts, so it is left for players to ask for. |
| KL-4 | Rows hold still under the pointer | How 0.3.1 stopped the rows re-sorting under the pointer. Updating the distances but not the order is the alternative, if players ask. |
| KL-5 | An **Alerts:** change takes effect after 1.5 seconds | The rule since 0.4.1. LT-1 tests it in the game. |
| KL-6 | Escape over a runestone's or readable item's text | The game closes that text on Escape or the Use key (E) with no test the list can hold shut. What would change it: refusing F7 while that text shows, as 0.4.1 does over the Barber Station; the game's public `TextViewer.instance.IsVisible()` and `TextViewer.IsShowingIntro()` tell it from the intro text. |
| KL-7 | Two mod windows; F5 over the list | One Escape closing only one window would need each mod to know about the other's window; the game opens the console with no test a mod window can hold shut. |
| KL-8 | A TomTom or Wayfinder key that types | Stopping it would take a second patch, on a private part of TomTom. Their default keys do not type. |
| KL-9 | A map drag let go over the window | Two more patches, on the map's click and double-click, would remove it; not worth it for so brief a gesture. |
| KL-10 | Gamepad: map stick and alternate placement | The game reads both outside the input test the list holds shut. TomTom's window behaves the same. |
| FW-3 | `GuideMode = GroundPath` holds the navigation tiles | See FW-3. |
| FW-1, FW-2 | The window's place not kept; GUI scale | See FW-1 and FW-2. |
| KL-11 | Find area's limits | Sub-biomes and the game's corner biome test: see FW-5 and FW-6. The rest is how Find area works: it tells the land from the world seed, not from the loaded ground, and the terrain it cannot check (slope, lava, player bases, water depth) is known only where the land is loaded. |
| KL-12 | Always track nearest watched: its rules | Chosen when it was made (0.3.0), and each could change if players ask; the dungeon side (0.3.1) and the settled **Alerts:** stars (0.4.1) are fixes. Taking a creature that alerted during the wait and then left the `AlertRadius` would need the wait to remember that creature. |
| KL-24 | Tracking usually ends at a death | The game removes the body about 10 seconds after a death, and with it the local player the tracker follows (a respawn at once may carry it on: LT-9); OI-4 asks whether tracking should carry on after the respawn. |

### KL-13 Touch screens

On a touch screen, a long press on the window over the large map can still delete a pin under it: the game's touch
gesture does not go through the pointer events the window blocks. And the large map can be closed while the list is
open, which at a Barber Station brings the barber back under the list, where the Escape that closes the list also
cancels the barber. Mouse, keyboard and gamepad players cannot meet either. Read from the code; not seen.

### KL-14 Console key binds run while you type in the search

Console key binds (made with the console's `bind` command) can still run when their key is typed in the list's search:
the game checks them against its own chat field, not against the list, and no flag the list sets can stop them. This
matters only with binds on keys you type. Server Devcommands' mouse-wheel binds are stopped since 0.3.1.

### KL-15 An auto-run already going keeps going

An auto-run started before the list opens keeps the character running while the list is open, and a block toggled on
(rather than held) stays up: the list stops new movement and look input, not a run already under way. A movement key
pressed after the list closes stops the run. The README's "your character and camera stand still" does not mention
this; its next release should.

### KL-16 Other mods' keys stand down while the list is open

While the list is open it tells the game a text field is in use, so other mods whose hotkeys stand down while you type
also stand down until the list closes. That is how the list keeps keys from the game. TomTom's and Wayfinder's window
and skip keys are the exception: they keep working over the list.

### KL-17 ListKey is one key

`ListKey` is a single key: Shift, Ctrl or Alt held with it are ignored (Shift+F7 also toggles the list), and it cannot
be set to a key combination. While ConfigurationManager's window is open with its input blocking on, F7 does not reach
the list. A key-combination setting is possible future work.

### KL-18 How alerts batch and get used up

Alerts come from a once-a-second check: one centre message, naming the nearest new creature with "(+N more)" for the
others found in the same check, and one ding. Auto-track takes only that nearest one. A watched creature that alerts
while you are tracking a creature, or in the same check as a nearer one, has had its alert: Auto-track does not take it
later, nor when you turn Auto-track on afterwards (Always track nearest watched can, after a loss). The ding and
Auto-track also act while the HUD is hidden, when the message is not shown; skipping them then would be a behaviour
change, not taken so far.

### KL-19 Watchlist and AlertRadius matching

The watchlist matches prefab names exactly, in any case: `Greydwarf` does not cover `Greydwarf_Elite` or
`Greydwarf_Shaman` - watch each. `AlertRadius` at 0 or below, or a value that is not a number, means no limit.

### KL-20 Always track nearest watched after a creature tracked by hand

A wait starts even when the lost creature, tracked by hand, was outside the **Alerts:** stars; it then takes only
creatures inside them. Whether it should start at all then is an open design question.

### KL-21 List details

The search matches the name and the prefab name, not the "(tamed)" mark. A pet shows its creature's name, not the name
you gave it. Names are fixed when first built, so after a language change the all-types view keeps the old language
until you next enter a world, and the tracking label until the next Track. The list keeps its search, view and scroll position
when reopened, also in another world. The title counts the rows shown, also under a search. The Watching row does not
wrap, so a long watchlist is best edited in the cfg, with `KeepBetweenSessions` on and the game closed (with it off,
the next world you enter empties the watchlist).

### KL-22 The cfg is read when the game starts

A setting edited in `com.mobtracker.plugin.cfg` while the game runs takes effect at the next start, and is lost if the
file is written before then: any setting changed in the window or in ConfigurationManager writes the whole file back
from the values in use, and so, with `KeepBetweenSessions` off, does entering a world or going back to the main menu
while the watchlist or a star filter is away from its default. The README says so for `Watchlist` and
`AlertStarFilter`; it holds for every setting. With `KeepBetweenSessions` off, a hand edit of `Watchlist`,
`ListStarFilter` or `AlertStarFilter` lasts only until the next world is entered, even one made with the game closed.

### KL-23 Closing the game keeps the last session's choices until the next world

With `KeepBetweenSessions` off, the watchlist and both star filters are set back when you enter a world or go back to
the main menu, not when the game closes. Quitting from a world - from the game's menu, or by closing its window - ends
the game without going back to the main menu, so `com.mobtracker.plugin.cfg` keeps that session's watchlist and star
filters through the next start and the main menu, where nothing is listed, alerted or tracked, until you enter a world.
The README says so in the `KeepBetweenSessions` row of its settings table, not under Known limits. What would change
it: setting them back when the game quits as well. LT-14 checks it in the game.

## Watching the game

- A Valheim update can change what MobTracker patches or reads. `tools/preflight.ps1` checks a build against the
  installed game, and the README says to run it after every update.
- The ground-path guide reaches navigation members the game does not make public (LT-8), which an update can change.

## Watching other mods

- **TomTom and Wayfinder:** their keys work over the list through a patch on their public `IsTypingElsewhere()`. For
  each TomTom or Wayfinder DLL it reads, preflight checks that this is still their only reader of the two flags the list
  sets (KL-8); since 0.5.1 `tools/mutants.ps1` names the DLLs a run was checked against.
- **ConfigurationManager:** it applies MobTracker's two star filters, which are text settings, at every keystroke - one
  reason an **Alerts:** change waits until it holds still (KL-5). While its window blocks input, F7 does not reach the
  list (KL-17).

## Ideas (not planned)

Each with why it is not done yet and what it would take. Fixes come first, as their own patch release; a new feature or
setting bumps the minor version.

### FW-1 Keep the window's place and size between starts

The window's size and place are not kept from one start of the game to the next; moved aside, it always keeps a corner
on screen.

- Not yet: a behaviour change, kept out of the 0.3.1 fixes.
- Would take: saving the window's rect, in the cfg or a small state file, and restoring it at the next start; the
  existing clamp keeps a restored rect on screen.

### FW-2 Follow the game's GUI scale

The window and the tracking label grow with the screen height above 1080p but do not follow the game's GUI scale
setting, and below 1080p the window keeps its size and covers much of the screen.

- Not yet: a behaviour change; at 1920x1080 with GUI scale 1 nothing would differ.
- Would take: scaling by the game's own rule (screen size relative to 1920x1080, times its GUI scale setting) in
  `EntityListWindow.GuiScale`, which the window, its pointer test and the tracking label share.

### FW-3 Ground path: stop holding the navigation tiles

With `GuideMode = GroundPath` the game's navigation tiles along the line are kept from being rebuilt while you track,
so a wall built, ground levelled or tree cut meanwhile may not show in the line, nor in how creatures on those tiles
find their way.

- Not yet: a behaviour change that needs its own checks, and the ground path has never been seen running (LT-8).
- Would take: keeping the tiles alive without holding back their rebuild, accepting the game's rebuild cadence. The
  5 s and 30 s in `Tracker.cs`'s comments are the game's code defaults; the game itself runs with other values, so
  check those before relying on them.

### FW-4 Ground-path line quality

The line keeps a corridor of navigation tiles one tile (32 m) wide alive, so a detour wider than that stays a partial
path and the arrow shows as well. The line is capped at about 512 points and past that ends with a straight segment to
the path's end. Its points are only ever lifted to the terrain, never lowered. Beyond 250 m only the arrow shows.

- Not yet: the ground path has never been seen running (LT-8).
- Would take: widening the corridor round a partial path's end is the next step noted in the code.

### FW-5 Find area: sub-biome spawn lists

Find area does not read the spawn lists of sub-biomes (Bat Swamp, Goblin Plains and the like), nor which creatures a
sub-biome keeps out: `Bat_Swamp`, `TentaRoot_wild`, `Skeleton_Poison` and `Skeleton_Mountains` are reported as having
no rule, and a Lox area can be pinned inside Goblin Plains.

- Not yet: kept as a known limit since 0.2.0.
- Would take: for each candidate zone, adding the rules of the sub-biomes that can occur there and dropping the
  creatures they keep out.

### FW-6 Find area: the game's biome test

The game decides a spot's biome from the corners of its zone; Find area asks the seed at a few points in the zone, so
at a biome border it can miss a zone that would do, and now and then pin one that will not.

- Not yet: kept as a known limit since 0.2.0.
- Would take: reading each zone's biome the way the game does, from its corners.

### FW-7 Allocations and memory

While the list is open it makes small amounts of garbage on every IMGUI event: the title, and for every row (also rows
scrolled out of view) layout options and the distance text. The list refresh and the alert check make a few strings
per creature. The alert memory grows by one entry per alerted creature until its once-a-second check finds no player -
when you leave the world, and at a respawn slow enough for it (LT-9). The arrow's mesh and materials live until the game
exits.

- Not yet: none of it is known to be noticeable.
- Would take: cached layout options, distance texts made at each refresh rather than at each event, and skipping rows
  out of view would remove most of it.

### FW-8 An integration surface for other plugins

Other plugins can read and change MobTracker's settings through its BepInEx config, but its runtime state (the
tracker, the window, the alerts) is internal, and it raises no events.

- Not yet: no other plugin uses MobTracker yet.
- Would take: a small public API - track, stop, is-tracking, a target-lost event - or a documented reflection
  contract. `Tracker.Track` would then need a null guard: given no creature today, it leaves tracking switched on, and
  the next frame reports the old target lost. An integration that patches MobTracker should first check with a
  Harmony test that the members it patches can be patched on the game's runtime.

## Decided or not planned - reopen only with a new reason

- **The list keeps the game out while it is open:** Tab, the mouse wheel and the keys typed in its search do not reach
  the game, and a click, drag or scroll on the window never reaches the map or a game window under it. The exceptions
  are under Known limits.
- **Escape and the gamepad's B close the list.**
- **F7 does not open the list** while you type in chat, a sign or a map pin's name, while the console is open, or over
  the pause menu, the build menu, the inventory or the Barber Station.
- **The star rows are toggle buttons that combine categories**, and a click on *All* resets a row. There is no single
  button that cycles through the choices: the alerts check once a second and alert each creature once, so every choice
  passed on the way would alert for real.
- **A change on the Alerts: row takes effect once the row has held still for 1.5 seconds** (KL-5).
- **What you watch and both star rows last one game session:** they go back to nothing watched and *All* whenever you
  enter a world or go back to the main menu, unless `KeepBetweenSessions` is on. It is off by default.
- **Find area's pins are yours alone:** they are added with the game's save flag off and no owner, so they are never
  saved with your map or shared through a Cartography Table.
- **Open items live in this file** rather than a GitHub wiki, so they are versioned with the code.

## Done

- 0.5.1: OI-1 - the tracking arrow, the ground-path line and the "Tracking:" label hide while the HUD is hidden, in a
  cutscene (sleep included), while the player is dead, in the frame the body is removed for the respawn, and during a
  teleport; `ArrowSize` (0.1 to 3) and `ArrowHeight` (0 to 5) have allowed ranges. Its earlier wording - the arrow
  "keeps pointing from where you fell until you respawn" - was wrong: the tracking usually ends when the body is
  removed (OI-4).
- 0.5.1: OI-2 - a Watch or Find area click still waiting when the list closes is dropped, also on every frame without
  a player, so it never runs at a later opening.
- 0.5.1: SC-1, SC-2, SC-5 - preflight checks that Auto-track asks "a creature is tracked", that the re-track starts only
  in the lost-creature branch after its message, and the session reset's gate, its `Held` test and the
  `SaveOnConfigSet` value it puts back; planted defects prove each.
- 0.5.1: TL-1 to TL-7 - `tools/publicize.ps1` hashes with .NET, so a build from PowerShell 7 works, and refreshes its
  copies when it changes; `tools/mutants.ps1` copies untracked files that git does not ignore too, empties its builds
  when it ends or is stopped and names the TomTom or Wayfinder DLLs it checked against; `tools/mutants.ps1` and
  `tools/deploy.ps1` run preflight in the same PowerShell process, without starting a second one;
  `tools/compare-il.ps1 -All` lists every line that differs, and the script compares names by exact case.
- 0.5.0: a Watch or Unwatch click still waiting when the player is gone is dropped, so it no longer reaches another
  game session (part of OI-2; the rest - a late Watch click within a session, and the Find area click - came in
  0.5.1).

Everything before that is in the README's History. From here on, a finished item moves here with its version.
