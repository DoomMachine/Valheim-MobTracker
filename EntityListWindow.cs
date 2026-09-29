using System.Collections.Generic;
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

        // Whether the search box has the keyboard, sampled at each Repaint while the list is open.
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

        // The list's star filter as of the last refresh; a change (the List: row or the cfg) refreshes at once.
        private StarSet _appliedListStars = StarSet.All;

        // The star rows' buttons, left to right, and their labels - built once, not on every event.
        private static readonly StarFilter[] StarButtons = StarFilters.Buttons();
        private static readonly GUIContent[] StarChoices = BuildStarChoices();
        private static readonly GUILayoutOption[] RowLabelWidth = { GUILayout.Width(50f) };

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
                // A Watch click not yet applied is dropped with the player (dead or logged out), never carried into the
                // next game session's watchlist.
                _pendingWatchToggle = null;
                Close();
                return;
            }

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
                Close();
                return;
            }

            if (ListKeys.MayToggle(IsOpen, Hotkeys.TypesText(ModConfig.ListKey.Value), _searchFocused, GameTyping.Any(),
                    Menu.IsVisible(), Hud.IsPieceSelectionVisible(), InventoryGui.IsVisible(), PlayerCustomizaton.IsBarberGuiVisible())
                && Hotkeys.Pressed(ModConfig.ListKey))
            {
                if (IsOpen)
                    Close();
                else
                    Open();
            }
        }

        private void Open()
        {
            if (IsOpen)
                return;
            IsOpen = true;
            _focusSearch = true;
            _refreshNow = true; // the rows of this opening at once, wherever the pointer is (Rules.ShouldRefresh)
        }

        /// <summary>Every way the list closes comes here, so the closing frame is always recorded.</summary>
        private void Close()
        {
            if (!IsOpen)
                return;
            IsOpen = false;
            _closedFrame = Time.frameCount;
            _focusSearch = false;
            _searchFocused = false;
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
                // marked - with KeepBetweenSessions on, the filter may be one set in an earlier session.
                string what = _appliedAllTypes ? " creature types"
                    : _appliedListStars == StarSet.All ? " creatures loaded"
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
                Tracker.Stop();
                NearestWatched.Cancel();
            }
            // Called straight from here: nothing drawn after it depends on HasPins, so the layout and the
            // events of this frame still see the same controls.
            if (SpawnFinder.HasPins && GUILayout.Button("Clear pins", GUILayout.Width(80f)))
                SpawnFinder.Clear();
            GUILayout.EndHorizontal();

            // Both buttons only flip a flag; the rows themselves are swapped in Update.
            GUILayout.BeginHorizontal();
            if (GUILayout.Button(_allTypes ? "View: all types" : "View: nearby"))
                _allTypes = !_allTypes;
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

            // Star filters: each row is five toggle buttons, All and the four categories. A click on a category adds it
            // or takes it off (taking off the last one gives All), a click on All resets. Not a button that cycles
            // through the choices: the alert poll runs every second and alerts each creature once,
            // so every choice passed on the way alerts for real. Toggles pass through states too - taking off the only
            // marked category passes through All - so the alerts do not read this row's set as it is, but as
            // WatchAlerts.EffectiveAlertStars, once it has held still (AlertsRow). The row itself and the cfg change at
            // once. Five controls on every event, whatever is marked: IMGUI needs the same controls in its layout and
            // its drawing. A type in the all-types view has no level, so the list's filter does not apply there and is
            // greyed out.
            GUILayout.BeginHorizontal();
            GUILayout.Label("List:", RowLabelWidth);
            bool enabled = GUI.enabled;
            GUI.enabled = enabled && !_allTypes;
            StarSet listStars = ModConfig.ListStars;
            for (int i = 0; i < StarButtons.Length; i++)
            {
                bool marked = StarSets.IsMarked(listStars, StarButtons[i]);
                if (GUILayout.Toggle(marked, StarChoices[i], GUI.skin.button) != marked)
                    ModConfig.ListStarsText.Value = StarSets.Format(StarSets.Toggle(listStars, StarButtons[i]));
            }
            GUI.enabled = enabled;
            GUILayout.EndHorizontal();

            GUILayout.BeginHorizontal();
            GUILayout.Label("Alerts:", RowLabelWidth);
            StarSet alertStars = ModConfig.AlertStars;
            bool emptyIsNothing = AlertsRow.EmptyIsNothing(AlertsRow.AlertsChangeMode);
            for (int i = 0; i < StarButtons.Length; i++)
            {
                bool marked = StarSets.IsMarked(alertStars, StarButtons[i]);
                if (GUILayout.Toggle(marked, StarChoices[i], GUI.skin.button) != marked)
                    ModConfig.AlertStarsText.Value = StarSets.Format(StarSets.Toggle(alertStars, StarButtons[i], emptyIsNothing));
            }
            GUILayout.EndHorizontal();

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
                        _pendingFind = row;
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
                            Tracker.Stop();
                        else if (row.Character != null)
                            Tracker.Track(row.Character);
                    }
                }

                bool watched = ModConfig.Watchlist.Contains(row.Prefab);
                if (GUILayout.Button(watched ? "Unwatch" : "Watch", GUILayout.Width(70f)))
                    _pendingWatchToggle = row.Prefab;

                GUILayout.EndHorizontal();
            }
            GUILayout.EndScrollView();

            DrawWatchlist();

            // Only the search box takes the keyboard in this window (buttons and toggles do not).
            if (Event.current.type == EventType.Repaint)
                _searchFocused = GUIUtility.keyboardControl != 0;

            GUI.DragWindow();
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
