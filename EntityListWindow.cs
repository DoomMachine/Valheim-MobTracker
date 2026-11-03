using System.Collections.Generic;
using BepInEx.Configuration;
using UnityEngine;

namespace MobTracker
{
    internal class EntityListWindow : MonoBehaviour
    {
        private struct Row
        {
            public Character Character;
            public bool IsType; // a creature type from the "All types" view: nothing to track, no distance
            public string Prefab;
            public string Name;
            public string Label;
            public float Distance;
        }

        private const string SearchControl = "MobTracker_Search";
        private const string ListCountsControl = "MobTracker_ListCounts";
        private const string AlertCountsControl = "MobTracker_AlertCounts";

        public static bool IsOpen { get; private set; }

        // The frame in which the list last closed. The key that closed it (Escape, the gamepad's B) is still "down this
        // frame" for every game gate that runs after this component, so those gates stay shut until the frame ends.
        private static int _closedFrame = -1;

        /// <summary>
        /// True while the list is open, and for the rest of the frame in which it closed: what the TextInput.IsVisible,
        /// Chat.HasFocus and mouse-wheel postfixes report (TomTom's WaypointWindow.BlocksGameInput).
        /// </summary>
        public static bool BlocksGameInput
        {
            get { return IsOpen || _closedFrame == Time.frameCount; }
        }

        /// <summary>IMGUI is drawn in pixels; scale it so it is not thumbnail-sized above 1080p.</summary>
        public static float GuiScale
        {
            get { return Mathf.Max(1f, Screen.height / 1080f); }
        }

        private readonly List<Row> _rows = new List<Row>();
        // Static, because the uGUI raycast patch asks about it (Covers). In GUI units, as GUILayout.Window returns it.
        private static Rect _rect = new Rect(60f, 60f, 480f, 560f);
        private Vector2 _scroll;
        private string _query = "";
        private string _appliedQuery = "";
        private float _nextRefresh;
        private bool _refreshNow; // opening the window refreshes at once, wherever the pointer is
        private bool _focusSearch;

        // Whether a text field - the search box or a star-count field - has the keyboard, sampled at each Repaint while the
        // list is open.
        private bool _searchFocused;

        // Console visibility as sampled by the previous Update: Unity does not order this Update against
        // Console.Update, so on the Escape frame the console may already have closed itself.
        private bool _consoleWasVisible;
        private bool _allTypes;
        private bool _appliedAllTypes;

        // Every creature prefab the game knows, for watching things that are not around.
        // Rebuilt when ZNetScene changes, i.e. once per world load.
        private readonly List<Row> _types = new List<Row>();
        private ZNetScene _typesScene;
        private static string _pendingWatchToggle;
        private Row? _pendingFind;
        // Why the list is closing, for the verbose log: set just before Close by the callers that know (Events.ListClosed).
        private string _closeCause;

        // The list's star row - categories and counts - as of the last refresh; a change (the List: row, its field or the
        // cfg) refreshes at once. All to begin with (no category, no count).
        private StarRule _appliedListStars;

        // The two star rows' count fields, after each row's buttons (StarFilter.cs, CountsField).
        private readonly CountsField _listCounts = new CountsField();
        private readonly CountsField _alertCounts = new CountsField();
        // The count fields' style while their text cannot be read: the text field's, with red text. Made at its first use
        // (a GUIStyle needs the GUI skin), then kept.
        private static GUIStyle _unreadable;

        // The star rows' buttons, left to right, and their labels - built once, not on every event.
        private static readonly StarFilter[] StarButtons = StarFilters.Buttons();
        private static readonly GUIContent[] StarChoices = BuildStarChoices();
        private static readonly GUILayoutOption[] RowLabelWidth = { GUILayout.Width(50f) };
        private static readonly GUILayoutOption[] CountsLabelWidth = { GUILayout.Width(52f) };
        private static readonly GUILayoutOption[] CountsFieldWidth = { GUILayout.Width(64f) };

        private static GUIContent[] BuildStarChoices()
        {
            string[] labels = StarFilters.Labels();
            var contents = new GUIContent[labels.Length];
            for (int i = 0; i < labels.Length; i++)
                contents[i] = new GUIContent(labels[i]);
            return contents;
        }

        private void Update()
        {
            bool consoleVisible = Console.IsVisible();
            bool consoleWasVisible = _consoleWasVisible;
            _consoleWasVisible = consoleVisible;

            Player player = Player.m_localPlayer;
            if (player == null)
            {
                Close(); // also drops a click not yet applied, so it never reaches the next game session
                return;
            }

            // The star rows' count fields, before the keys: text typed in the last OnGUI is written even when this
            // frame's key closes the list.
            if (IsOpen)
                SyncCounts();

            HandleKeys(consoleVisible, consoleWasVisible);

            // A safety net, not the Tab gate: Tab and the gamepad's Y are read under Chat.HasFocus, which
            // ChatHasFocusPatch holds true while the list is open. Should another mod open the inventory anyway, its own
            // close keys would be shut by the same flag - so the list gives way.
            if (IsOpen && InventoryGui.IsVisible())
                Close();

            if (!IsOpen)
                return;

            if (_pendingWatchToggle != null)
            {
                ModConfig.ToggleWatch(_pendingWatchToggle);
                _pendingWatchToggle = null;
            }

            if (_pendingFind != null)
            {
                SpawnFinder.Find(_pendingFind.Value.Prefab, _pendingFind.Value.Name);
                _pendingFind = null;
                _closeCause = EventLines.ClosedByFind;
                Close(); // the answer arrives as a HUD message and map pins
                return;
            }

            // The rows and the watchlist only ever change here, never inside OnGUI: IMGUI lays a frame out in one
            // event and draws it in another, and throws if the control count differs between them.
            // The twice-a-second refresh waits while the pointer is over the window or a mouse button is held (hotControl:
            // a button pressed, the scroll bar or the window dragged); see Rules.ShouldRefresh. Each argument is a plain
            // read preflight can trace.
            if (!Rules.ShouldRefresh(PlayerChanged(), Time.time >= _nextRefresh, Covers(ZInput.pointerPosition), GUIUtility.hotControl != 0))
                return;

            _refreshNow = false;
            _nextRefresh = Time.time + 0.5f;
            _appliedQuery = _query;
            _appliedListStars = ModConfig.ListStars;
            if (_appliedAllTypes != _allTypes)
                _scroll = Vector2.zero;
            _appliedAllTypes = _allTypes;
            if (_allTypes)
                RefreshTypes();
            else
                Refresh(player);
        }

        /// <summary>
        /// The two star rows' count fields, once a frame while the list is open (CountsField.Sync): typed text that can be
        /// read is written to the row's own setting, whose handler re-reads the row, and the cfg is saved; a change made
        /// elsewhere is shown instead. A keystroke in the Alerts: field that writes nothing restarts that row's wait, as a
        /// write does through its setting's handler.
        /// </summary>
        private void SyncCounts()
        {
            ApplyCounts(_listCounts, ModConfig.ListCountsText, "List:");
            if (ApplyCounts(_alertCounts, ModConfig.AlertCountsText, "Alerts:"))
                ModConfig.AlertRowChanged();
        }

        /// <summary>
        /// One field and its own setting: writes what the field hands back; with VerboseLog on, says once that typing
        /// turned the field to text it cannot read. True when typing changed the field and nothing was written.
        /// </summary>
        private static bool ApplyCounts(CountsField field, ConfigEntry<string> entry, string row)
        {
            string write = field.Sync(entry.Value);
            if (write != null)
            {
                entry.Value = write;
                return false;
            }
            if (field.TurnedUnreadable)
                Events.CountsUnreadable(row, field.Text);
            return field.TypedNotWritten;
        }

        /// <summary>
        /// The list's keys, read from ZInput here rather than from IMGUI events in OnGUI: the search box, focused on open,
        /// takes Escape's KeyDown event first (GUI.HandleTextFieldEventForDesktop uses up every key it does not type), so
        /// an Escape test in OnGUI never saw it. TomTom's rules (Plugin.Update); the decisions are ListKeys'.
        /// </summary>
        private void HandleKeys(bool consoleVisible, bool consoleWasVisible)
        {
            if (ListKeys.ClosesOnBack(IsOpen, consoleVisible, consoleWasVisible,
                    ZInput.GetKeyDown(KeyCode.Escape, false), ZInput.GetButtonDown("JoyButtonB")))
            {
                // Consume B, so a map or a trader underneath does not close with it (InventoryGui does the same) - a
                // ZInput button stays "pressed" until the next Game.Update - and pause the controls briefly on a gamepad,
                // as Menu.Hide does. Escape is a raw key, down in this frame only: BlocksGameInput covers the rest of it.
                ZInput.ResetButtonStatus("JoyButtonB");
                if (ZInput.IsGamepadActive())
                    PlayerController.SetTakeInputDelay(0.1f);
                _closeCause = EventLines.ClosedByBack;
                Close();
                return;
            }

            if (ListKeys.MayToggle(IsOpen, Hotkeys.TypesText(ModConfig.ListKey.Value), _searchFocused, GameTyping.Any(),
                    Menu.IsVisible(), Hud.IsPieceSelectionVisible(), InventoryGui.IsVisible(), PlayerCustomizaton.IsBarberGuiVisible())
                && Hotkeys.Pressed(ModConfig.ListKey))
            {
                _closeCause = EventLines.ClosedByKey;
                if (IsOpen)
                    Close();
                else
                    Open();
            }
            else
                Events.ListKeyCheck(IsOpen, _searchFocused); // verbose only: a press refused, and why
        }

        private void Open()
        {
            if (IsOpen)
                return;
            IsOpen = true;
            _focusSearch = true;
            _refreshNow = true; // the rows of this opening at once, wherever the pointer is (Rules.ShouldRefresh)
            _closeCause = null;
            // The count fields show their settings as they are now: text typed and not applied before the last close is gone.
            _listCounts.Show(ModConfig.ListCountsText.Value);
            _alertCounts.Show(ModConfig.AlertCountsText.Value);
            Events.ListOpened(_allTypes);
        }

        /// <summary>
        /// Every way the list closes comes here, so the closing frame is always recorded. A Watch or Find area click not
        /// yet applied (they are applied in the next Update, while the list is open) is dropped first - also when the list
        /// is already shut, as on every frame without a player - so it never runs at a later opening, possibly in
        /// another world.
        /// </summary>
        private void Close()
        {
            _pendingWatchToggle = null;
            _pendingFind = null;
            if (!IsOpen)
                return;
            IsOpen = false;
            _closedFrame = Time.frameCount;
            _focusSearch = false;
            _searchFocused = false;
            Events.ListClosed(_closeCause);
            _closeCause = null;
        }

        /// <summary>The player changed what the list shows - the search, the view or the list's stars - or opened it.</summary>
        private bool PlayerChanged()
        {
            return _refreshNow || _query != _appliedQuery || _allTypes != _appliedAllTypes
                   || ModConfig.ListStars != _appliedListStars;
        }

        private void RefreshTypes()
        {
            if (_typesScene != ZNetScene.instance)
            {
                _typesScene = ZNetScene.instance;
                _types.Clear();
                if (_typesScene != null)
                {
                    foreach (GameObject prefab in _typesScene.m_prefabs)
                    {
                        Character character = prefab != null ? prefab.GetComponent<Character>() : null;
                        if (character == null || character.IsPlayer())
                            continue;

                        // Prefab name alongside: several prefabs share a display name
                        // (Skeleton / Skeleton_Poison), and the prefab is what gets watched.
                        _types.Add(new Row
                        {
                            IsType = true,
                            Prefab = prefab.name,
                            Name = Creature.DisplayName(character),
                            Label = Creature.DisplayName(character) + "  [" + prefab.name + "]"
                        });
                    }
                    _types.Sort((a, b) => string.Compare(a.Label, b.Label, System.StringComparison.OrdinalIgnoreCase));
                }
            }

            _rows.Clear();
            foreach (Row type in _types)
            {
                if (Rules.Matches(_appliedQuery, type.Label, type.Prefab))
                    _rows.Add(type);
            }
        }

        private void Refresh(Player player)
        {
            _rows.Clear();
            foreach (Character character in Character.GetAllCharacters())
            {
                if (!Creature.IsListable(character) || !StarSets.Accepts(_appliedListStars, character.GetLevel()))
                    continue;

                string prefab = Creature.PrefabName(character);
                string label = Creature.DisplayName(character);
                if (!Rules.Matches(_appliedQuery, label, prefab))
                    continue;

                if (character.IsTamed())
                    label += " (tamed)";

                _rows.Add(new Row
                {
                    Character = character,
                    Prefab = prefab,
                    Label = label,
                    Distance = Vector3.Distance(player.transform.position, character.transform.position)
                });
            }

            _rows.Sort((a, b) => a.Distance.CompareTo(b.Distance));
        }

        /// <summary>
        /// True while the list is open and a screen point - pixels, y up from the bottom, as the EventSystem, the Input
        /// System and ZInput.pointerPosition give it - is on the window. The window's rect is in GUI units, y down from
        /// the top and scaled by GuiScale (GUI.matrix), so the point is converted to it. TomTom's test does not divide:
        /// it draws unscaled.
        /// </summary>
        public static bool Covers(Vector2 screenPoint)
        {
            return IsOpen && Rules.PointerOverWindow(_rect.x, _rect.y, _rect.width, _rect.height, GuiScale,
                Screen.height, screenPoint.x, screenPoint.y);
        }

        private void OnGUI()
        {
            if (!IsOpen)
                return;

            // GUI.matrix is IMGUI's global state: set for this window only, and put back for whatever draws next.
            float scale = GuiScale;
            Matrix4x4 matrix = GUI.matrix;
            GUI.matrix = Matrix4x4.Scale(Vector3.one * scale);
            try
            {
                // With a list star filter on, the count is what it lets through, and the title names the categories
                // marked and the counts typed - with KeepBetweenSessions on, the filter may be one set in an earlier session.
                string what = _appliedAllTypes ? " creature types"
                    : StarSets.IsAll(_appliedListStars) ? " creatures loaded"
                    : " creatures, " + StarSets.Label(_appliedListStars);
                _rect = GUILayout.Window(0x4D6F6254, _rect, DrawWindow, "MobTracker - " + _rows.Count + what);
            }
            finally
            {
                GUI.matrix = matrix;
            }

            // A corner of the window always stays on screen, as TomTom keeps its own: moved aside at one resolution or
            // window size, it could otherwise open off-screen at the next - unseen, and holding the keyboard and mouse.
            // In GUI units, like the rect.
            _rect.x = Mathf.Clamp(_rect.x, 60f - _rect.width, Screen.width / scale - 60f);
            _rect.y = Mathf.Clamp(_rect.y, 0f, Screen.height / scale - 40f);
        }

        private void DrawWindow(int id)
        {
            GUILayout.BeginHorizontal();
            GUILayout.Label("Search", GUILayout.Width(50f));
            GUI.SetNextControlName(SearchControl);
            _query = GUILayout.TextField(_query);
            // Also while "always track nearest watched" waits for the next creature: the way to call that off.
            if ((Tracker.IsTracking || NearestWatched.IsPending) && GUILayout.Button("Stop tracking", GUILayout.Width(100f)))
            {
                Events.Clicked("Stop tracking");
                Tracker.Stop();
                NearestWatched.Cancel();
            }
            // Called straight from here: nothing drawn after it depends on HasPins, so the layout and the
            // events of this frame still see the same controls.
            if (SpawnFinder.HasPins && GUILayout.Button("Clear pins", GUILayout.Width(80f)))
            {
                Events.Clicked("Clear pins");
                SpawnFinder.Clear();
            }
            GUILayout.EndHorizontal();

            // Both buttons only flip a flag; the rows themselves are swapped in Update.
            GUILayout.BeginHorizontal();
            if (GUILayout.Button(_allTypes ? "View: all types" : "View: nearby"))
            {
                _allTypes = !_allTypes;
                Events.ViewSwitched(_allTypes);
            }
            bool path = ModConfig.Guide.Value == GuideMode.GroundPath;
            if (GUILayout.Button(path ? "Guide: ground path" : "Guide: 3D arrow"))
                ModConfig.Guide.Value = path ? GuideMode.Arrow : GuideMode.GroundPath;
            GUILayout.EndHorizontal();

            GUILayout.BeginHorizontal();
            bool autoTrack = GUILayout.Toggle(ModConfig.AutoTrack.Value, " Auto-track watched", GUILayout.ExpandWidth(false));
            if (autoTrack != ModConfig.AutoTrack.Value)
                ModConfig.AutoTrack.Value = autoTrack;
            bool always = GUILayout.Toggle(ModConfig.AlwaysTrackNearest.Value, " Always track nearest watched", GUILayout.ExpandWidth(false));
            if (always != ModConfig.AlwaysTrackNearest.Value)
                ModConfig.AlwaysTrackNearest.Value = always;
            GUILayout.EndHorizontal();

            // Star filters: each row is five toggle buttons, All and the four categories, then "Exactly:" and the row's
            // star-count field (0.9.0). A click on a category adds it or takes it off (taking off the last one leaves no
            // category marked: the row is back to All when it has no count, and lets only its counts through when it
            // has some), a click on All resets the row and empties its field - the field's sync in Update then writes
            // the empty text. Not a button that cycles through the choices: the alert poll runs every second and alerts
            // each creature once, so every choice passed on the way alerts for real. Toggles pass through states too -
            // taking off the only marked category passes through no category - so the alerts do not read this row as it
            // is, but as WatchAlerts.EffectiveAlertStars, once it has held still (AlertsRow). The row itself and the cfg
            // change at once. Seven controls on every event, whatever is marked or typed: IMGUI needs the same controls in
            // its layout and its drawing. A type in the all-types view has no level, so the list's row does not apply
            // there and is greyed out, its field taking nothing typed.
            GUILayout.BeginHorizontal();
            GUILayout.Label("List:", RowLabelWidth);
            bool enabled = GUI.enabled;
            GUI.enabled = enabled && !_allTypes;
            StarRule listStars = ModConfig.ListStars;
            for (int i = 0; i < StarButtons.Length; i++)
            {
                bool marked = StarSets.IsMarked(listStars, StarButtons[i]);
                if (GUILayout.Toggle(marked, StarChoices[i], GUI.skin.button) != marked)
                {
                    ModConfig.ListStarsText.Value = StarSets.Format(StarSets.Toggle(listStars, StarButtons[i]));
                    if (StarButtons[i] == StarFilter.All)
                        _listCounts.Clear();
                }
            }
            DrawCounts(_listCounts, !_allTypes, ListCountsControl);
            GUI.enabled = enabled;
            GUILayout.EndHorizontal();

            GUILayout.BeginHorizontal();
            GUILayout.Label("Alerts:", RowLabelWidth);
            StarRule alertStars = ModConfig.AlertStars;
            bool emptyIsNothing = AlertsRow.EmptyIsNothing(AlertsRow.AlertsChangeMode);
            for (int i = 0; i < StarButtons.Length; i++)
            {
                bool marked = StarSets.IsMarked(alertStars, StarButtons[i]);
                if (GUILayout.Toggle(marked, StarChoices[i], GUI.skin.button) != marked)
                {
                    ModConfig.AlertStarsText.Value = StarSets.Format(StarSets.Toggle(alertStars, StarButtons[i], emptyIsNothing));
                    if (StarButtons[i] == StarFilter.All)
                        _alertCounts.Clear();
                }
            }
            DrawCounts(_alertCounts, true, AlertCountsControl);
            GUILayout.EndHorizontal();

            // The List: row greys out in the all-types view: while its count field has the keyboard there - the view just
            // switched with the field in use - the search box takes it. Asked here, after the field is drawn in this
            // event, so the field's name is known to GUI.GetNameOfFocusedControl whatever IMGUI keeps between events.
            if (_allTypes && GUI.GetNameOfFocusedControl() == ListCountsControl)
                _focusSearch = true;

            if (_focusSearch && Event.current.type == EventType.Repaint)
            {
                GUI.FocusControl(SearchControl);
                _focusSearch = false;
            }

            _scroll = GUILayout.BeginScrollView(_scroll);
            foreach (Row row in _rows)
            {
                GUILayout.BeginHorizontal();
                GUILayout.Label(row.Label);
                if (row.IsType)
                {
                    if (GUILayout.Button("Find area", GUILayout.Width(80f)))
                    {
                        Events.RowClicked("Find area", row.Label, row.Prefab);
                        _pendingFind = row;
                    }
                }
                else
                {
                    GUILayout.Label(Mathf.RoundToInt(row.Distance) + "m", GUILayout.Width(50f));

                    // Not just Target == Character: while a spawn area is tracked Target is null, and so, to
                    // Unity's ==, is a creature destroyed since the last refresh.
                    bool tracked = Tracker.IsTrackingCreature && row.Character != null && Tracker.Target == row.Character;
                    if (GUILayout.Button(tracked ? "Untrack" : "Track", GUILayout.Width(70f)))
                    {
                        if (tracked)
                        {
                            Events.RowClicked("Untrack", row.Label, row.Prefab);
                            Tracker.Stop();
                        }
                        else if (row.Character != null)
                        {
                            Events.RowClicked("Track", row.Label, row.Prefab);
                            Tracker.Track(row.Character);
                        }
                    }
                }

                bool watched = ModConfig.Watchlist.Contains(row.Prefab);
                if (GUILayout.Button(watched ? "Unwatch" : "Watch", GUILayout.Width(70f)))
                    _pendingWatchToggle = row.Prefab;

                GUILayout.EndHorizontal();
            }
            GUILayout.EndScrollView();

            DrawWatchlist();

            // Only the search box and the two star-count fields take the keyboard in this window (buttons and toggles do
            // not).
            if (Event.current.type == EventType.Repaint)
                _searchFocused = GUIUtility.keyboardControl != 0;

            GUI.DragWindow();
        }

        /// <summary>
        /// A star row's count field (0.9.0): its label - "Exactly:", or "Invalid:" while its text cannot be read - and the
        /// field, its text red then. The same two controls whatever it holds: IMGUI needs the same controls in its layout
        /// and its drawing. No length cap: IMGUI's would cut a longer value set in ConfigurationManager, and the cut text
        /// would be written back. takesTyping false: the List: row's field in the all-types view, greyed out, takes
        /// nothing. Named (control), so DrawWindow can tell whether the List: row's field has the keyboard.
        /// </summary>
        private static void DrawCounts(CountsField field, bool takesTyping, string control)
        {
            GUILayout.Label(CountsLabel(field), CountsLabelWidth);
            GUI.SetNextControlName(control);
            string typed = GUILayout.TextField(field.Text, CountsStyle(field), CountsFieldWidth);
            if (takesTyping)
                field.Typed(typed);
        }

        private static string CountsLabel(CountsField field)
        {
            return field.Unreadable ? "Invalid:" : "Exactly:";
        }

        /// <summary>
        /// The skin's text field, or the same with red text while the field's text cannot be read - the same size either
        /// way. Made at its first use, in OnGUI, where GUI.skin can be read. Unreadable changes only in Update (Show,
        /// Sync), so every GUI event of one frame draws the same.
        /// </summary>
        private static GUIStyle CountsStyle(CountsField field)
        {
            if (!field.Unreadable)
                return GUI.skin.textField;
            if (_unreadable == null)
            {
                _unreadable = new GUIStyle(GUI.skin.textField);
                Color red = new Color(1f, 0.45f, 0.4f);
                _unreadable.normal.textColor = red;
                _unreadable.hover.textColor = red;
                _unreadable.focused.textColor = red;
                _unreadable.active.textColor = red;
            }
            return _unreadable;
        }

        /// <summary>The way to unwatch a type that is not around to have a row.</summary>
        private static void DrawWatchlist()
        {
            if (ModConfig.Watchlist.Count == 0)
            {
                // One label either way, so the control count does not change with the checkbox.
                GUILayout.Label(ModConfig.AlwaysTrackNearest.Value
                    ? "Watching: nothing, so 'Always track nearest watched' has nothing to do. Watch alerts on every creature of that type the 'Alerts:' stars and AlertRadius allow, never a tamed one."
                    : "Watching: nothing. Watch alerts on every creature of that type the 'Alerts:' stars and AlertRadius allow, never a tamed one.");
                return;
            }

            // ponytail: one unwrapped row; a watchlist too long for it is edited in the cfg file.
            GUILayout.BeginHorizontal();
            GUILayout.Label("Watching (click to remove):", GUILayout.ExpandWidth(false));
            foreach (string name in ModConfig.Watchlist)
            {
                if (GUILayout.Button(name, GUILayout.ExpandWidth(false)))
                    _pendingWatchToggle = name;
            }
            GUILayout.EndHorizontal();
        }
    }
}
