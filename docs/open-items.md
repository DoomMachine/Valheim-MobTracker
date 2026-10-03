# Open items and future work

The one list of what is untested, unverified, open or only an idea for MobTracker - so none of it has to be worked out
again. It lives with the code, so each release can check it. What a player meets is in the README's "Known limits";
what each release changed is in its "History".

As of **0.8.0**.

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
work, **OQ** open questions - behaviour choices discussed and not taken (yet).

## Not yet tried in play

0.8.0 has not been played yet (LT-20). 0.7.1 ran through short play sessions without errors, in which `VerboseLog` was
turned on while the game ran; the cfg could be written throughout, so none of LT-19's checks was run in them. 0.7.0 ran
through short play sessions without errors, in which `MobTracker.log` was opened at each start, closed at each quit and
kept as `MobTracker-prev.log` at the next start; its logging settings were not changed in them (LT-17). In one, Always
track nearest watched took a creature of another watched type than the one lost, and each of its waits ended in one
`took` line (LT-16). 0.6.0 ran through a play session without errors, but its new rule did not act in it: the log has no
`Always track nearest watched:` line. 0.5.1 ran through a long play session without errors, in which Always track
nearest watched was seen acting (LT-4); none of LT-15's checks was confirmed in it. 0.5.0 ran through a long play
session, with several logouts, without errors: at its first world entry it set back the **Alerts:** filter 0.4.1 had
saved (LT-14), but nothing was watched in it, so a reset at a logout was not seen. 0.4.1 - and with it the changes of
0.4.0 and 0.3.1 - ran through a long play session without errors, in which a watch alert came, the `AlertStarFilter`
held several categories at once, types were watched and unwatched and the guide mode was switched; none of the checks
below was run in it as written. 0.3.0 and 0.2.0 each ran through play sessions without errors; Always track nearest
watched (0.3.0) was first reported acting in 0.5.1's session, not yet checked for taking the nearest, and 0.2.0's new
features have not been confirmed in the game (LT-2, LT-4 to LT-6).

Single player is enough except for LT-7 (another player, on a dedicated server or in a game one of you hosts), and for
LT-11's second check and LT-21 (a dedicated server). Where creatures of a given star level are needed, the console's
`spawn` command (with `devcommands` on) makes them: level 1 is no star, 2 one star, 3 two stars. Afterwards,
`BepInEx/LogOutput.log` should have no exception naming MobTracker, and from 0.7.0 `BepInEx/MobTracker.log` no
`[Error  : Unity Log]` line. With `VerboseLog` on (0.7.0), most checks below can be read from its lines as well: what
was tracked, lost and taken, each alert and what Auto-track did.

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

### LT-16 0.6.0: the nearest creature of any watched type

`spawn` (with `devcommands` on) makes the creatures. Copy `BepInEx/LogOutput.log` before the game starts again (each
start rewrites it), and read its `Always track nearest watched:` lines.

Since 0.8.0 the loss of any tracked creature starts the wait while something is watched, also one of a type not watched
or a tamed one: the two checks of the older rule (`no wait - lost Neck, not on the watchlist (Boar)` and `no wait - lost
tamed <type>`) are gone from here, and LT-20 checks the new one.

- [ ] The log says `MobTracker 0.6.0 loaded`.
- [ ] Watch `Deer` and `Boar`, tick **Always track nearest watched**, and track a Deer that has a Boar nearer than any
  other Deer; kill it. "Lost track of" shows, and about 5 seconds later the arrow and the "Tracking:" label are on that
  Boar. The log has `waiting - lost Deer; watching Boar,Deer`, then `took Boar at <m> m, 5 s after losing Deer`, its
  metres about the label's. The same with the two kinds swapped.
- [ ] With a Deer nearer than any Boar, the same takes that Deer.
- [ ] With no watched creature around after the loss, it takes the first one that turns up, and the `took` line's
  seconds say how long that took.
- [ ] With Auto-track on, a watch alert during the 5 seconds shows and dings but does not take the arrow; then the arrow
  goes to the nearest watched creature, which the `took` line names.
- [ ] Unwatch Deer during the wait with Boar still watched: it still takes a Boar. Unwatch both: nothing is taken, and
  the log says `wait ended after <s> s, nothing taken - nothing is watched`.
- [ ] Click **Stop tracking** during the wait: nothing is taken, and the log says `... nothing taken - Stop tracking`.
- [ ] With the option off, a tracked creature's loss writes no `Always track nearest watched:` line.
- [x] In the whole log, each `waiting` line is followed by one `took` or `wait ended` line before the next `waiting`
  line (the last one may stand alone if the game was closed during a wait), and no exception names MobTracker.

### LT-17 0.7.0: the logs

Copy `BepInEx/MobTracker.log`, `MobTracker-prev.log` and `LogOutput.log` before the game starts again.

- [ ] The log says `MobTracker <version> loaded`. The cfg has `[Logging]` with `ErrorLog = true` and
  `VerboseLog = false`, and ConfigurationManager shows both as Enabled/Disabled toggles, in a **Logging** section listed
  first.
- [x] `BepInEx/MobTracker.log` begins with
  `MobTracker <version> - MobTracker.log opened at the game's start; Valheim ...; BepInEx ...`, a
  `Logging: ErrorLog on, VerboseLog off` line and a `Settings:` line, and every entry starts with the date, the time and
  `f` and the frame.
- [x] Start the game again: the last start's file is now `MobTracker-prev.log`, and `MobTracker.log` starts afresh.
- [ ] With the game closed, set `ListStarFilter = Foo` and `GuideMode = Foo` in the cfg. At the next start
  `MobTracker.log` has MobTracker's `General.ListStarFilter is 'Foo'` warning and BepInEx's `Config value of setting
  "Tracking.GuideMode" could not be parsed` warning, as `LogOutput.log` does (set both back afterwards).
- [ ] Set `ListKey` to `WheelUp`: the warning is in `LogOutput.log` and in `MobTracker.log`, with the same text after
  the date, time and frame.
- [ ] Turn `VerboseLog` on in ConfigurationManager: both logs get `Logging: VerboseLog turned on - ...` and a
  `Settings:` line. Then open the list, track a creature, let a watched one alert, click Find area: each has its
  `List:`, `Track:`, `Alert:`, `Auto-track:`, `Ding:` and `Find area:` lines in both logs, in the order they happened.
- [ ] With `VerboseLog` on, kill a tracked creature:
  `Track: lost <name> (<prefab>) - gone from this client (killed, despawned, or out of range)`, or
  `seen dead on this client` for a creature with a death animation. Track another and walk away until it unloads: the
  same `gone from this client` line.
- [ ] With `VerboseLog` on, drag `ArrowSize` in ConfigurationManager: one `Setting: Tracking.ArrowSize` line at once
  and one more about a second after you let go, not one per step.
- [ ] With `VerboseLog` on, press F7 while typing in chat: `List: F7 pressed - the list stays shut: you are typing ...`.
- [ ] With `VerboseLog` on and **Always track nearest watched** ticked, lose a tracked watched creature with none other
  around: an `Always track nearest watched: look found nothing to take - ...` line after the `waiting` line, and
  another only when what the looks see changes.
- [ ] With `VerboseLog` on, Ctrl+F3 while tracking: `Guide: hidden - HUD hidden (Ctrl+F3)`, then `Guide: shown again`.
- [ ] Turn both settings off while the game runs: the last line of `MobTracker.log` is then `Logging: ... turned off -
  MobTracker.log gets only these Logging notes and its closing line until ErrorLog or VerboseLog is turned on`, and
  until one is turned on again only such notes and, at quit, the closing line are added. Start the game with both
  off: `MobTracker.log` and `MobTracker-prev.log` keep their times and contents; turning `ErrorLog` on then opens the
  file (`opened when ErrorLog was turned on`) and keeps the last one as `MobTracker-prev.log`.
- [ ] Open `MobTracker.log` in Notepad while the game runs: it opens, and the game goes on writing to it.
- [x] Quit the game normally: the last line of `MobTracker.log` is `MobTracker.log closed - the game is quitting`
  (LT-18).
- [ ] Nothing in `MobTracker.log` names your Windows user folder in full, a player, a character or a world.

### LT-20 0.8.0: the loss of any tracked creature, and a taming

`spawn` (with `devcommands` on) makes the creatures. `tame` (also with `devcommands`) tames, in single player, every
tameable creature loaded, however far - its 20 m is not used - and the world keeps them tamed: use a test world, and
spawn the wild creatures after it. A tamed creature can attack a wild one nearby: spawn the wild Boar out of its sight,
or after the loss, so that it is alive when the wait looks. Copy `BepInEx/LogOutput.log` before the game starts again,
and read its `Always track nearest watched:` lines.

- [ ] The log says `MobTracker 0.8.0 loaded`.
- [ ] With only `Boar` watched and **Always track nearest watched** ticked, track a wild `Neck` by hand, with a Boar
  around, and kill it: "Lost track of" shows, about 5 seconds later the arrow and the "Tracking:" label are on the
  nearest Boar, and the log has `waiting - lost Neck; watching Boar`, then `took Boar at <m> m, 5 s after losing Neck`.
- [ ] The same, but walk away until the Neck is no longer loaded: the same `waiting` line, and a `took` line once a Boar
  is loaded where you are.
- [ ] With no Boar around after the Neck's loss: after "Lost track of", nothing on screen shows the wait,
  **Stop tracking** is still in the window, and when a Boar is spawned the arrow goes to it; the `took` line's seconds
  say how long that took.
- [ ] Tame a Wolf (`tame`), then spawn a Boar; track the Wolf by hand: it stays tracked while it is loaded and alive,
  tamed before its tracking began. Walk away until it is no longer loaded (or, with PvP on, kill it): the log has
  `waiting - lost tamed Wolf; watching Boar`, and a wild Boar is taken once one is loaded where you are.
- [ ] Tame a Boar (`tame`), then spawn a wild one farther off; after a loss the wait takes the wild one, never the tamed
  one.
- [ ] Track a wild Boar by hand and tame it while it is tracked (`tame`, or by feeding it), then spawn a wild Boar:
  "Lost track of Boar - it was tamed" shows at the taming, the log has `waiting - lost tamed Boar; watching Boar`, and
  the arrow goes to the wild Boar once it is there, never to the one just tamed; with `VerboseLog` on,
  `Track: Boar (Boar) is tamed now - the tracking ends, as at a loss` comes before the `waiting` line.
- [ ] With the option off, track a wild Boar and tame it: "Lost track of Boar - it was tamed" shows, the tracking ends,
  and the log has no `Always track nearest watched:` line.
- [ ] Track a watched creature outside the **Alerts:** stars by hand and kill it: a wait starts, and it takes only a
  creature inside the stars.
- [ ] With nothing watched and the option ticked, kill a tracked creature: `no wait - lost <type>, nothing is watched`.
- [ ] While a creature of a type not watched is tracked: **Stop tracking**, a row's Track on another creature and Find
  area each write no `waiting` line.
- [ ] With Auto-track on, kill a Neck tracked by hand and let a watched creature alert within the 5 seconds: the alert
  shows and dings but does not take the arrow (with `VerboseLog` on: `Auto-track: not taken - Always track nearest
  watched is waiting ...`), and the `took` line names the nearest.
- [ ] Through a portal that leaves a creature of a type not watched, tracked by hand, behind: after the arrival the
  arrow goes to the nearest watched creature there, and the `took` line names it.
- [ ] In the whole log, each `waiting` line is followed by one `took` or `wait ended` line before the next `waiting`
  line (the last one may stand alone if the game was closed during a wait), and no exception names MobTracker.

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

Seen acting in 0.5.1's play session, by a player's report: after a tracked creature died it pointed at another
of the same type - the rule before 0.6.0, which looked only for the lost creature's type, so a nearer creature of
another watched type could not be taken. Nothing was logged then: before 0.6.0 MobTracker wrote nothing about which
creature it tracked. Whether it takes the nearest has not been checked; under 0.6.0's rule that is LT-16, and this
item closes with it.

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

If it fails: fall back to the game's public path query, or turn GroundPath off with a reason in the log. Since 0.7.0,
with `VerboseLog` on, a `Ground path:` line says whether the line was complete, stopped short or was not built, and why.

## Not verified

Worked out from the code, or only expected, and not seen in play. The check under each would settle it.

### LT-9 A respawn with no bed, near the start

Tracking stops on any frame with no player; the alert memory is cleared only when its once-a-second check finds none.
After a death with no bed set, the new character may appear at the start so quickly that this lasts about a frame, and
whether either then carries over to the new character is not known.

- [ ] With no bed set, track a creature and let a watched one alert; die close to the start, where you will respawn.
  After the respawn, check whether the arrow still shows and whether that creature alerts again.

If either carries over: also reset both when the local player changes. Since 0.7.0, with `VerboseLog` on, the `Player:`
lines and `Alert: no local player, so the alert memory of ... is cleared` show whether the memory was cleared between
the death and the respawn.

### LT-10 A ding on every alert

The ding is made by a sample-reader callback whose position is never reset. Unity is expected to read such a clip
once; if it ever read it again, later dings would be silent. A position-reset callback would remove the question.

- [ ] With `AlertVolume` above 0, let several alerts come in one session: each one dings. (Since 0.7.0, with
  `VerboseLog` on, a `Ding: played` line shows each ding was started; whether it was heard is still the check.)

### LT-11 How far creatures load

The README's "roughly 130 to 290 m" comes from the game's code, not from measurement.

- [ ] At the default Draw distance, and one step up, note the farthest creature the list shows outside dungeons.
- [ ] The same on a dedicated server. The game lets a server lower the range (you get the smaller of its value and
  yours); a dedicated server started without `-simulationdistance` uses the game's original range
  (`SimulationDistance.OriginalDistance`, level 2 in the code) - read from the code, not measured.
- [ ] In a game you join, with the host's Draw distance at the default and yours one step up: the farthest creature the
  list shows outside dungeons is under about 270 m. Read from the code, not measured; so is this: a host that raises its
  Draw distance after you joined keeps capping you at its old value until you join again.

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

### LT-19 0.7.1: a cfg that cannot be written

Copy `com.mobtracker.plugin.cfg` before these checks, and make it writable again (Properties, untick Read-only)
afterwards.

- [ ] With the game closed, make the cfg read-only and start the game: `LogOutput.log` says
  `Settings could not be saved to com.mobtracker.plugin.cfg at the game's start (UnauthorizedAccessException; ...` and
  then `MobTracker 0.7.1 loaded`, and `MobTracker.log` has the same warning; the cfg's contents and time do not change.
- [ ] Still read-only, in a world: Watch a creature type, click a star on each row, untick Auto-track: each takes effect
  (the Watching row, the rows' marks, a watched creature's alert) and no error appears in either log.
- [ ] Turn `VerboseLog` on in ConfigurationManager: `Logging: VerboseLog turned on - ...` in both logs, then the verbose
  lines; ConfigurationManager shows no `Failed to draw setting MobTracker - ...` error and no
  `Failed to draw this field` text.
- [ ] Make the cfg writable while the game runs and change any setting: the log says
  `Settings saved to com.mobtracker.plugin.cfg again after a change, ...`, and the cfg holds every change made while it
  was read-only.
- [ ] Make it read-only again, change a setting, make it writable, and quit from inside the world (from the game's
  menu), not by logging out first, with `VerboseLog` still on, which the line needs to reach `MobTracker.log`:
  `MobTracker.log` ends with `Settings saved to com.mobtracker.plugin.cfg again as the game quits, ...` before its
  closing line, and the cfg holds that change.
- [ ] With `KeepBetweenSessions` off, a type watched and the cfg read-only, go back to the main menu: the log says
  `Game session changed and KeepBetweenSessions is off, ...`, with no error, and entering a world again nothing is
  watched.

### LT-18 MobTracker.log on the game's runtime

How `MobTracker.log` is taken, copied to `MobTracker-prev.log` and shared was proved by `tools/log-harness/` on .NET
Framework on Windows; on the game's own runtime its opening at each start, the copy to `MobTracker-prev.log` and its
closing line at each normal quit were seen in 0.7.0's play sessions (LT-17), its sharing not yet. That an error of
MobTracker's code nobody caught reaches the file is decompiled and unit-tested on sample text, never seen: no such error
has happened in a log kept so far.

- [ ] LT-17's Notepad check settles the sharing.
- [ ] If an error naming MobTracker ever reaches `LogOutput.log` (only with BepInEx's `WriteUnityLog` on, which is off
  by default - with it off, `MobTracker.log` is the one BepInEx-side log that holds it) or `Player.log`,
  `MobTracker.log` has it as an `[Error  : Unity Log]` line.
- [x] After a normal quit, the last line of `MobTracker.log` is `MobTracker.log closed - the game is quitting`.

### LT-21 On a dedicated server

MobTracker goes only into each player's game. A dedicated server needs nothing and can be vanilla: the game checks no
mods when a player joins, and MobTracker sends nothing over the network. A client of a dedicated server builds its world
generator from the seed the server sends at the join, so Find area works there as in single player, and the server's
range caps the client's (LT-11). All of this is read from the code: MobTracker has not been played on a dedicated
server, which LT-11's second check needs as well; LT-7 needs another player, there or in a game one of you hosts.

- [ ] Join a vanilla dedicated server (no BepInEx on it) with MobTracker installed: the join works, F7 lists
  creatures, and the log has no exception naming MobTracker.
- [ ] Find area there: up to five pins, the arrow at the nearest and the HUD message naming the rule, as in LT-5.
- [ ] On a server started without `-simulationdistance`, with your Draw distance one step above the default: the
  farthest creature the list shows outside dungeons is under about 270 m (LT-11's second check).
- [ ] With `KeepBetweenSessions` off, a type watched and a star row set, lose the connection (stop the server, say):
  the game goes back to the main menu, and the log has a `Game session changed and KeepBetweenSessions is off` line;
  joined again, nothing is watched and both rows are on *All*.

A copy in the server's own `BepInEx/plugins/` is not needed, and the README says to leave it out. Read from the Windows
server's code (the Linux server's was not examined): BepInEx would load it there, since MobTracker names no process
(OQ-14); the server never has a player of its own, so none of MobTracker's features that need a player starts; at each
start it would write `MobTracker.log` and its cfg in the server's `BepInEx` folder, and, with TomTom or Wayfinder on the
server, its line saying their keys work while the list is open. With a cfg copied from a player's game,
`KeepBetweenSessions` off and a watchlist or star filter set, the server's world start would also set those back, with
the `Game session changed` line, and save the cfg. Not known without a server start: whether the server's build of the
game finds a shader for the arrow (if not, one `No usable shader found` error at each start), whether it can make the
ding's sound (if not, expected: one error at the start, after which MobTracker does nothing more there), and whether
`MobTracker.log` gets its closing line when the server is stopped with Ctrl+C.

### OI-3 Edge cases never seen

These would matter only if they happen:

- A creature without the usual root collider could make the arrow's aim fail on every frame and freeze the arrow. A
  fallback to the creature's position would remove that.
- A creature the game deactivates while it is alive would stay listed.

## Small fixes still open

None is serious. The OI items were found by reading the code, not seen in the game; the SC items are for contributors.

**In the game**

### OI-4 Tracking ends at a death

About 10 seconds after you die the game removes your body, and the tracking usually ends with it, with no message;
after the respawn nothing is tracked until you track something again (a row's Track button, or Find area), or a watch
alert does with Auto-track on. After a respawn at once (no bed, near the start) it may carry on (LT-9). (Always track
nearest watched ends its wait at a death by design.)
Whether tracking should carry on after the respawn is open: the tracker would have to keep its target while there is
no player, and say so.

### OI-6 A log listener that throws at quit

Since 0.7.1, `OnDestroy` first retries a save of the cfg that failed; when that retry works, its line goes through
BepInEx's log before `MobTracker.log` is closed. A log listener of another plugin that threw on that line would end
`OnDestroy` there, leaving `MobTracker.log` without its closing line. No such listener is known; guarding the retry is a
hardening for a later release.

**Safety checks**

`tools/preflight.ps1` checks a build's IL against what the code must do, and `tools/mutants.ps1` plants defects to
prove that each check fails when it should. These are the known gaps.

### SC-3 A re-track variant the checks do not model

A `NearestWatched.Update` that, with no player, returns early after cancelling something else. (Ways of picking a
creature other than the nearest that keep the shapes the checks look for - leaving the creature loop early, or
skipping creatures once one is kept - are checked since 0.6.0.)

### SC-4 What a new check needs

Many checks match exact IL shapes, so a legitimate rewrite of the code they cover (the re-track, Auto-track's line, the
star rows, the window clamp, the game session) fails them: re-read the IL and rewrite the check rather than loosen it.
The unit tests link only `StarFilter.cs` and `Rules.cs`, and since 0.7.0 `LogRules.cs` and `EventLines.cs`; the rest is
proved by preflight and planted defects (and `MobTracker.log`'s file handling, and since 0.7.1 the cfg's saving, by
`tools/log-harness/`). So prove each new check with defects planted in how its answer is used, its true path, how two
tested facts combine, its loop bounds and its operands - not only in its wiring.

### SC-6 What the logging checks cannot see

The checks hold where each verbose line may be written from, that each returns first while `VerboseLog` is off, catches
its own failure and changes nothing it describes, and, instruction by instruction, the listener, the file's opening, the
catch round the settings line written at the game's start, and the file's failure paths: `Shut` (which `Open`'s catch
reaches in `Awake`), `Dispose`, `Broke`, `Stop`, the stop notice said once, `CloseQuietly`. The guards that keep a line
from repeating every frame, second, look or keystroke are held to their methods' exact shapes: a failure warned about
once per site, the loss line only at a loss, the not-alerting line once per creature, the empty look's line only when it
changes, the refused-key line only on a press, a setting's burst through the settler, the cleared alert memory only when
it held some, and `LogObserver`'s and the ground path's lines only on a change; and four that sit in the caller - the
list's close line only past `Close`'s `IsOpen` test (with no local player `Close` runs every frame), the reached line
only inside the reached block, the alert memory's line only in the alert poll's no-player block, and the alert and
Auto-track lines only after the poll's return when nothing alerted. The wording of every verbose line and of the file's
own lines, and the decisions behind three of them - what Auto-track did, which test turned a watched creature away, why
the list closed when no caller said - are in `EventLines` and unit-tested; the game side hands over only names and
values (a button's name, a setting's key, a creature's label, the HUD's answer, a count).

What they still do not see:
- Where a site sits in its caller, beyond the places checked - the alert poll's lines after its once-a-second return,
  the Auto-track line right after Auto-track's test (0.7.1), the tracking lines first in `Tracker.Track`, `TrackPoint`
  and `Stop` (0.7.1), the loss line before the lost block, the window's clicks inside their buttons, the ground path's
  and the empty look's lines, the list's close, the reached line and the alert poll's no-player block and
  nothing-alerted return: elsewhere the site table holds only which methods call a site, and how many times. Find area's
  done line moved into its search loop would repeat once per zone searched; it passes every check today.
- What the walk that finds no throw and no log call does not reach: it starts at the listener (`LogEvent`) and reads
  only explicit throws. The file's other paths - `Start`, `Bound`, `Open`, `Switched`, `Stop` and the failure paths
  above - are held by their exact shapes and catches instead, so a new method on one of them needs a shape of its own.
- Inside the other `Events` methods, held only to the guard, the catch, no forbidden call and their own fields: a defect
  there - the area-pin line without its count test, the stop line without its tracking test, the guide line reading
  the wrong reason - writes a wrong or an extra line unseen. None of them runs every frame except the settings flush,
  whose settler the tests pin.
- Whether a site hands over the right value: at most sites the checks see that each argument is a plain value, not which
  one - the empty look's are traced to their source, and `LogObserver`'s, the ground path's and the ding's sites are
  held to exact shapes - so Find area's two counts swapped at its site would pass.
- What `LogObserver` writes over time: its "on change only" is checked by its shape, not by driving frames.
- Whether an inference is true of the moment: Auto-track's outcome is read from `Tracker.Generation`, and is only as
  true as the code that counts it.
- The clocks the rules are given: the repeat limit's and the settler's timing is unit-tested, but which clock each is
  fed is seen only in the methods held to exact shapes - not in the settings flush.
- The file's handling on the game's own runtime: `tools/log-harness/` runs on .NET Framework (LT-18).

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
| KL-12 | Always track nearest watched: its rules | Chosen when it was made (0.3.0), and each could change if players ask; the dungeon side (0.3.1) and the settled **Alerts:** stars (0.4.1) are fixes. Since 0.6.0 it takes the nearest creature of any watched type, not only of the lost one's (asked for after play); every watch alert during its wait leaves the choice to it, and unwatching the lost type no longer ends the wait (unwatching every type does). A setting for the lost type only would be a new feature; watching only that type does much the same for the re-track, at the cost of the other types' alerts. Taking a creature that alerted during the wait and then left the `AlertRadius` would need the wait to remember that creature. Since 0.8.0 the loss of any tracked creature starts the wait while something is watched - one of a type not watched, or a tamed one, too - and taming the tracked creature ends its tracking as a loss does (asked for after play; OQ-3 for the first). |
| KL-26 | `MobTracker.log`'s reach | An error nobody caught comes through BepInEx's "Unity Log" source, so `UnityLogListening` must be on and only main-thread messages arrive; a Unity log callback of MobTracker's own would remove the setting's part, as a second capture route (FW-9). The 5 MB cap keeps the next start's copy to -prev small (OQ-9). A second copy of the game fails at the open and touches nothing (OQ-11). The folder scrub replaces full spellings only. |
| KL-28 | A cfg that cannot be written | MobTracker saves it itself since 0.7.1, after each change; while it cannot be written, changes take effect but wait for the next save that works (a later change, or quitting the game), and are lost if none does. BepInEx writes the file in place, emptying it as it opens it, so a save that fails part-way (a full disk, the game killed mid-save) can leave it cut short: while the game runs, the next save that works rewrites it from the settings in use; after the game was killed mid-save, the settings cut off are back at their defaults at the next start, and one cut part-way through its value keeps the part written when that still reads as a value. Since 0.7.1 the game's start writes it once, not at each setting read. Writing elsewhere (a second file, the registry) would leave two places a setting lives. |
| KL-27 | What `VerboseLog` does not say yet | See FW-9; the README names each of its items but the last, which KL-26's limit covers. States it learns by watching are read once a frame, after the code that changes them (Tracker works the guide out in its `LateUpdate`), and taken as they are, without a line, when `VerboseLog` is turned on and in each tracking's first two frames. |
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
while you are tracking a creature, while Always track nearest watched waits, or in the same check as a nearer one, has
had its alert: Auto-track does not take it later, nor when you turn Auto-track on afterwards (Always track nearest
watched can, at a look after a loss), until it alerts again - and every watched creature can alert again once a
once-a-second alert check finds no local player: after a death with a respawn slow enough for it (the body is removed
about 10 seconds after it, and a bed respawn takes at least 8 seconds more; a respawn at once at the start may leave no
such check: LT-9) and when you leave the world. So if Stop tracking or turning the option off ends such a wait without a
take, a creature that alerted during it is not auto-tracked later unless it alerts again. The ding and Auto-track also
act while the HUD is hidden, when the message is not shown; skipping them then would be a behaviour change, not taken so
far.

### KL-19 Watchlist and AlertRadius matching

The watchlist matches prefab names exactly, in any case: `Greydwarf` does not cover `Greydwarf_Elite` or
`Greydwarf_Shaman` - watch each. `AlertRadius` at 0 or below, or a value that is not a number, means no limit.

### KL-20 Always track nearest watched after a creature tracked by hand

A wait starts whatever the lost creature, tracked by hand, was: outside the **Alerts:** stars, of a type you do not
watch, or tamed (the last two since 0.8.0) - and, since 0.8.0, taming it while you track it is a loss too. It then takes
only a creature a watch alert would take - of a watched type, inside the stars, never a tamed one - so after such a loss
the arrow can go to a creature of quite another kind than the one you followed, or wait until one turns up. The README
says so where it describes Always track nearest watched.

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
while the watchlist or a star filter is away from its default, and so does quitting the game after a save that failed
(0.7.1). The README says so for `Watchlist` and `AlertStarFilter`; it holds for every setting. With
`KeepBetweenSessions` off, a hand edit of `Watchlist`, `ListStarFilter` or `AlertStarFilter` lasts only until the next
world is entered, even one made with the game closed.

### KL-29 A cfg BepInEx cannot read when the game starts

BepInEx reads `com.mobtracker.plugin.cfg` while it creates the plugin, before any MobTracker code runs. A file another
program holds open for writing then, or without sharing, or one whose section name was edited by hand to start or end
with a space or to hold `=`, or whose section or setting name holds a tab, `\`, `"`, `'`, `[` or `]`, makes that read
throw, and MobTracker cannot catch it (decompiled; BepInEx 5.4.23.3). Unverified: whether Unity then drops the plugin,
as BepInEx expects, or keeps it without its settings; either way MobTracker does not start. The README's Known limits
say so.

### KL-23 Closing the game keeps the last session's choices until the next world

With `KeepBetweenSessions` off, the watchlist and both star filters are set back when you enter a world or go back to
the main menu, not when the game closes. Quitting from a world - from the game's menu, or by closing its window - ends
the game without going back to the main menu, so `com.mobtracker.plugin.cfg` keeps that session's watchlist and star
filters through the next start and the main menu, where nothing is listed, alerted or tracked, until you enter a world.
The README says so in the `KeepBetweenSessions` row of its settings table, not under Known limits. What would change
it: setting them back when the game quits as well. LT-14 checks it in the game.

### KL-25 The log's reason for a wait that took nothing

The `wait ended ... nothing taken - <reason>` line names the first that holds, when the wait ends, of: something else
is tracked, the option is off, nothing is watched; otherwise it says the player died or left the world. At a logout
with `KeepBetweenSessions` off and something watched, the session reset that empties the watchlist may run first in
that frame (Unity does not order the two components), and the line then says `nothing is watched`. Inferred from the
code; not seen in play. Since 0.7.0, with `VerboseLog` on, the `Session:` line and the frame numbers in `MobTracker.log`
show which ran first.

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
  list (KL-17). It lists MobTracker's **Logging** section first: sections in the order they are bound, unless its
  "Sort by name" is on (OQ-10).
- **BepInEx:** `MobTracker.log` hangs on BepInEx 5's log - its listeners, the `UnityLogListening` setting, the "Unity
  Log" source's `Stack trace:` text - and on its config's change events (BepInEx 5.4.23.3). A BepInEx update should be
  checked against them; `tools/preflight.ps1` checks that the members it uses still exist and that its level values
  are BepInEx's.
- **Server mods:** a server that runs a mod checking joining players' mods may refuse a player with MobTracker; the game
  itself does not check (LT-21), and no such mod has been tried.

## Open questions for future releases

Behaviour choices that have been discussed but not made. Each says what MobTracker does now, which is what stays unless
the question is answered otherwise, and what the other answer would change. An answer that changes behaviour is a new
feature (a minor version).

### OQ-1 Auto-track's choice when nothing is tracked

Now: with nothing tracked and no Always track nearest watched wait running (after Stop tracking, or at a world start),
Auto-track takes the nearest of the creatures that alert in one once-a-second check - the ones that just came into
range. A watched creature that alerted earlier and stands nearer is not taken, because each creature alerts once
(KL-18). Example: a Boar alerting at 150 m is taken while a Deer that alerted before stands at 30 m.
The other answer: Auto-track takes the nearest loaded watched creature whenever nothing is tracked. Auto-track would
then follow the nearest watched creature rather than the one that just turned up.

### OQ-2 Moving on to a nearer watched creature while tracking

Now: Always track nearest watched chooses only after a loss. Once it has taken a creature it stays on it, even when a
nearer watched creature comes along (it stays on a Boar at 80 m when a Deer walks up to 5 m), so the arrow does not
jump in the middle of a chase.
The other answer: while it tracks a creature it took itself, it moves to any nearer watched creature, at once or after
a margin or a delay that stops the arrow flicking between two creatures at about the same distance.

### OQ-4 Keeping the choice to the lost creature's type

Now: since 0.6.0 Always track nearest watched takes the nearest creature of any watched type; before, it looked only
for the lost creature's type. Watching only that type does much the same, at the cost of the other types' alerts.
The other answer: a setting that keeps the choice to the lost creature's type when that type is watched, as before
0.6.0.

### OQ-5 Choices 0.6.0 made with the change

Now, each reversible if players ask:
- every watch alert during a wait leaves the choice to the wait, also with Auto-track on (before 0.6.0, an alert for
  another watched type took the arrow at once and ended the wait);
- unwatching the lost type no longer ends the wait, unwatching every type does;
- at equal distances no type is preferred: the nearer creature wins, whatever kind was lost.

### OQ-6 Tracking after a death

OI-4 asks whether tracking should carry on after the respawn: today it usually ends when the game removes your body.

### OQ-7 MobTracker.log with both logging settings off

Now (0.7.0): with `ErrorLog` and `VerboseLog` both off from the game's start, neither `MobTracker.log` nor
`MobTracker-prev.log` is touched; the file opens the first time a setting is on in a game start, and at most once.
The other answer: start a fresh file, holding only its first lines, at every start of the game - which then moves the
last real log to -prev even with logging off.

### OQ-8 The level of the verbose lines

Now: Info, so they reach `LogOutput.log` too, as asked ("the same lines still go to LogOutput.log"). The other answer:
BepInEx's Debug level, which BepInEx's default settings leave out of `LogOutput.log` and its console; `MobTracker.log`
and the game's `Player.log` would still have them, and `LogOutput.log` would stay as quiet as before with
`VerboseLog` on.

### OQ-9 MobTracker.log's size and repeated errors

Now: at most 5 MB per game start, then one last line and nothing more until the next start; one earlier start kept
(`MobTracker-prev.log`); an error of MobTracker's code that repeats written at most once a minute, with a count of
those left out. The other answers: a larger cap, starting a fresh file at the cap, keeping more than one earlier start,
or another pace for repeats. MobTracker's own warnings are not thinned - one per ConfigurationManager keystroke in a
star filter, as in `LogOutput.log` - except a failed save of the cfg (0.7.1), said once until a save works again.

### OQ-10 Where the Logging settings show

Now: ConfigurationManager lists MobTracker's **Logging** section first, because its two settings are bound before the
others, so that `MobTracker.log` is open when the others are read and their warnings reach it. The other answer: bind
them last (listed last) and hold the warnings that come before in memory until the file opens.

### OQ-11 A second copy of the game

Now: a second copy of the game running at the same time writes no `MobTracker.log`, and says so in its own
`LogOutput.log`; the first copy's two files are untouched. The other answer: a file of its own, numbered as BepInEx
numbers `LogOutput.log`'s.

### OQ-12 What VerboseLog writes on its own lines, and what ErrorLog covers

Now: with `VerboseLog` on, `MobTracker.log` gets every MobTracker line, the warnings and errors too, whatever `ErrorLog`
says; `ErrorLog` alone does not write `MobTracker <version> loaded` (an Info line) - the file's own line at its opening
names the version instead; the window's Watch, Unwatch, Guide and checkbox clicks show as the `Setting:` lines they
cause. The other answers: verbose lines only, separate from the errors; a line per click as well.

### OQ-13 Telling the player in the game that the cfg cannot be saved

Now (0.7.1): only the logs say it; in the game the change takes effect as usual. The other answer: a message on the
screen once per run of failed saves - a new behaviour, and one more message over the game.

### OQ-14 Skipping a dedicated server

Now: MobTracker names no process, so BepInEx loads it in any game process, a dedicated server's too, where it has
nothing to do (LT-21). The other answer: `[BepInProcess("valheim.exe")]`, so that a server skips it with one BepInEx
warning (`Skipping [...] because of process filters`). BepInEx compares the name without its extension, so a client
whose program is named `valheim` on another system still loads it. The game's program names on Linux have not been
checked.

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

### FW-9 What VerboseLog does not say yet

- A Watch or Find area click dropped because the list closed in the same frame: `EntityListWindow.Close` is an exact
  shape the checks hold.
- A failing cutscene test: `Tracker.InCutscene` swallows the exception, and its exact shape and four planted defects
  pin that.
- Which of Escape and the gamepad's B closed the list: both are read inside one call the checks trace.
- Why a watched creature was passed over for a reason other than the four `Alert: none for ...` names.
- The search changing the list: the row count after the search applied changes (the search text itself is left out of
  the log on purpose). It can change at each refresh while you type, twice a second, so a line would need a settle like
  the `Setting:` lines', inside the list's refresh, which the checks trace argument by argument.
- The alert poll finding nothing watched: it returns before its creature loop once a second while the watchlist is
  empty. The watchlist is in the `Settings:` and `Setting:` lines, so that state can be read from them; a line of its
  own would need an on-change guard and checks of its own.
- The map's delete gesture already taken by another mod's prefix (TomTom's, say) before MobTracker's turn: that is
  decided in MobTracker's Harmony prefix, where the checks allow no verbose line. LT-6's last check would read it.
- The map's delete gesture with no area pin in reach: every other use of the gesture, after which the game removes one
  of your own pins, or none, as before - a line at each would not say anything MobTracker did.
- An error nobody caught without BepInEx's `UnityLogListening`: a Unity log callback of MobTracker's own, kept to one
  capture route.
- Not yet: each needs safety checks re-read from the compiled code for little gain, or it is rare.
- Would take: those re-derivations, and planted defects for each new line.

### FW-10 Errors still said once, or not at all

The cutscene test's error (counted as no cutscene) is not logged; a creature that cannot be checked for an alert is
said once per start of the game, not once per session; and the list's refresh and the re-track's look have no
per-creature catch, so a creature another mod breaks repeats its error at each look or refresh (`MobTracker.log` writes
it at most once a minute, with a count).

- Not yet: each sits in code the safety checks pin exactly.
- Would take: a once-only warning in the cutscene test, a per-session count for the alert check, and per-creature
  catches as the alert check has, with the checks re-derived.

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
- **Always track nearest watched takes the nearest creature of any watched type** (0.6.0), and every watch alert during
  its wait leaves the choice to it; to hunt one kind only, watch only that kind. It chooses only after a loss: it does
  not move on to a nearer creature while the one it took is tracked.
- **The loss of any tracked creature starts Always track nearest watched's wait while something is watched** (0.8.0,
  OQ-3's other answer, asked for after play): one of a type not watched, or a tamed one, too - as one outside the
  **Alerts:** stars already did. Taming the tracked creature ends the tracking and starts the wait, as a loss does: one
  tracked wild and tamed now, by anyone. One already tamed when its tracking began is not lost by that: like any other,
  it stays tracked until it is killed, no longer loaded, or you stop or replace the tracking. Stopping the tracking, or
  tracking something else, never starts the wait, and the wait still takes only a creature a watch alert would take,
  never a tamed one.

## Done

- 0.8.0: OQ-3 - the loss of any tracked creature starts Always track nearest watched's wait while something is watched,
  whatever its type, stars or tameness, and taming the tracked creature - one tracked wild, tamed by anyone - ends its
  tracking as a loss does, "Lost track of" saying that it was tamed, and starts the wait too (both asked for after a
  0.7.0 play session, in which a creature of another kind, tracked by hand, was lost and the log said
  `no wait - lost <type>, not on the watchlist (...)`); what the wait may take is as before - any watched type, the
  watch alert's filters, never a tamed one - and KL-20 says what that means after a creature tracked by hand.
  `Retrack.Lost` is handed the watchlist's count, neither whether it holds the lost type nor the tameness; the loss line
  names a tamed creature as tamed, and its `no wait` names only an empty watchlist (or a creature of no known type,
  `Retrack.Lost`'s own guard). The taming is the lost test's last question (`Tracker.TamedNow`), asked once a frame only
  of a creature tracked wild, still there and alive - its tameness read as often as before, and no longer each frame for
  one tracked tamed; with `VerboseLog` on, `Tracker` says the taming itself
  (`is tamed now - the tracking ends, as at a loss`) before the stop, and nothing watches for the tamed state any more.
  Preflight holds the values `Retrack.Lost` is handed, the exact start of `NearestWatched.Lost`, where the recorded type
  and tameness are written (only where a tracking starts, and in the taming test), and the exact shapes of
  `Tracker.Track`, the taming test and the lost block; planted defects put each old gate back - as a value, as an early
  return and through `Tracker`, also by a second write of the recorded type in `Track` or on every frame - hand it a
  count that is not the watchlist's, start a wait from Stop tracking, a row's Track or Find area, keep a tamed creature
  tracked, end its tracking without the wait or without its message, or end the tracking of one tamed before it began;
  the unit tests pin the rule and the words of the lines and the message, and planted defects prove each of them.

- 0.7.1: OI-5 - MobTracker saves its cfg itself: BepInEx's saving is off from before the first setting is bound, and
  the file is saved once when every setting is bound, then after each change - the window's, ConfigurationManager's or
  any other plugin's - by MobTracker's last handler on the cfg; a failed save is caught and said once until a save works
  again, and tried once more as the game quits. So a cfg that cannot be written no longer throws out of a click, leaves
  a parsed watchlist or star filter behind its setting, or keeps `VerboseLog` from taking effect, and a read-only cfg at
  the start no longer stops MobTracker loading. Preflight holds who binds, saves and listens to the cfg, the order in
  Awake, and the saver's shapes; planted defects prove each, and `tools/log-harness/` runs the real settings on a
  read-only cfg. Also: Find area's done line counts the frame its search starts in; the Auto-track line is handed the
  dungeon-side answer Auto-track's test read and names it before the wait; preflight holds the Auto-track line right
  after Auto-track's test, and each tracking line first in `Tracker.Track`, `TrackPoint` and `Stop`.

- 0.7.0, asked for on 2026-10-02: `BepInEx/MobTracker.log` with every MobTracker warning and error, an error of its code
  the game or BepInEx reports (KL-26 says which) and BepInEx's warnings about its cfg (`ErrorLog`, on by default; the
  start before kept as `MobTracker-prev.log`), and `VerboseLog` (off by default) for the events the README lists (what
  it does not say yet: KL-27, FW-9), in it and in `LogOutput.log`; the error lines about a patch, and about TomTom's and
  Wayfinder's keys, give their cause. Preflight checks the switches, the file's opening and its failure paths, the
  listener, every log line by level, every verbose site, the guards inside the verbose methods that keep a line from
  repeating, and those in the callers round the list's close, the reached and loss lines, the window's clicks, the
  ground path, the empty look, the alert poll's once-a-second return, its no-player block and its nothing-alerted return
  (SC-6 names a caller's guard it does not hold); planted defects prove each check, the unit tests pin the lines' words
  and the decisions they report, and `tools/log-harness/` proves the file's handling outside the game.
- 0.6.0, asked for during 0.5.1's play session: Always track nearest watched takes the nearest creature of any watched
  type, not only of the lost one's; during its wait every watch alert leaves the choice to it, also with Auto-track on;
  unwatching the lost type no longer ends the wait (unwatching every type does); with the option on, each loss of a
  tracked creature, and what each wait took or why it ended, is written to the log. SC-3 in part: preflight checks that
  the re-track's creature loop runs to its end and keeps only the nearest, and every call NearestWatched.Update makes.
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
