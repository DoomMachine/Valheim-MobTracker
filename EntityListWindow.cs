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

        /// <summary>IMGUI is drawn in pixels; scale it so it is not thumbnail-sized above 1080p.</summary>
        public static float GuiScale
        {
            get { return Mathf.Max(1f, Screen.height / 1080f); }
        }

        private readonly List<Row> _rows = new List<Row>();
        private Rect _rect = new Rect(60f, 60f, 480f, 560f);
        private Vector2 _scroll;
        private string _query = "";
        private string _appliedQuery = "";
        private float _nextRefresh;
        private bool _focusSearch;
        private bool _allTypes;
        private bool _appliedAllTypes;

        // Every creature prefab the game knows, for watching things that are not around.
        // Rebuilt when ZNetScene changes, i.e. once per world load.
        private readonly List<Row> _types = new List<Row>();
        private ZNetScene _typesScene;
        private static string _pendingWatchToggle;
        private Row? _pendingFind;

        private void Update()
        {
            Player player = Player.m_localPlayer;
            if (player == null)
            {
                IsOpen = false;
                return;
            }

            if (ZInput.GetKeyDown(ModConfig.ListKey.Value))
            {
                IsOpen = !IsOpen;
                _focusSearch = IsOpen;
                _nextRefresh = 0f;
            }

            // The inventory key is the one hotkey that ignores TextInput.IsVisible (vanilla sign
            // editing has the same gap); yield to it rather than stack two cursor UIs.
            if (IsOpen && InventoryGui.IsVisible())
                IsOpen = false;

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
                IsOpen = false; // the answer arrives as a HUD message and map pins
                return;
            }

            // The rows and the watchlist only ever change here, never inside OnGUI: IMGUI lays a frame out in one
            // event and draws it in another, and throws if the control count differs between them.
            if (Time.time < _nextRefresh && _query == _appliedQuery && _allTypes == _appliedAllTypes)
                return;

            _nextRefresh = Time.time + 0.5f;
            _appliedQuery = _query;
            if (_appliedAllTypes != _allTypes)
                _scroll = Vector2.zero;
            _appliedAllTypes = _allTypes;
            if (_allTypes)
                RefreshTypes();
            else
                Refresh(player);
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
                if (!Creature.IsListable(character))
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

        private void OnGUI()
        {
            if (!IsOpen)
                return;

            // Closed here rather than in Update: Menu.Update has already run this frame and saw
            // the window open, so the same Escape press cannot also pop the pause menu.
            Event current = Event.current;
            if (current.type == EventType.KeyDown && current.keyCode == KeyCode.Escape)
            {
                IsOpen = false;
                current.Use();
                return;
            }

            GUI.matrix = Matrix4x4.Scale(Vector3.one * GuiScale);
            _rect = GUILayout.Window(0x4D6F6254, _rect, DrawWindow, "MobTracker - " + _rows.Count + (_appliedAllTypes ? " creature types" : " creatures loaded"));
        }

        private void DrawWindow(int id)
        {
            GUILayout.BeginHorizontal();
            GUILayout.Label("Search", GUILayout.Width(50f));
            GUI.SetNextControlName(SearchControl);
            _query = GUILayout.TextField(_query);
            if (Tracker.IsTracking && GUILayout.Button("Stop tracking", GUILayout.Width(100f)))
                Tracker.Stop();
            GUILayout.EndHorizontal();

            // Both buttons only flip a flag; the rows themselves are swapped in Update.
            GUILayout.BeginHorizontal();
            if (GUILayout.Button(_allTypes ? "View: all types" : "View: nearby"))
                _allTypes = !_allTypes;
            bool path = ModConfig.Guide.Value == GuideMode.GroundPath;
            if (GUILayout.Button(path ? "Guide: ground path" : "Guide: 3D arrow"))
                ModConfig.Guide.Value = path ? GuideMode.Arrow : GuideMode.GroundPath;
            bool autoTrack = GUILayout.Toggle(ModConfig.AutoTrack.Value, " Auto-track watched", GUILayout.ExpandWidth(false));
            if (autoTrack != ModConfig.AutoTrack.Value)
                ModConfig.AutoTrack.Value = autoTrack;
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

                    bool tracked = Tracker.IsTracking && Tracker.Target == row.Character;
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
            GUI.DragWindow();
        }

        /// <summary>The way to unwatch a type that is not around to have a row.</summary>
        private static void DrawWatchlist()
        {
            if (ModConfig.Watchlist.Count == 0)
            {
                GUILayout.Label("Watching: nothing. Watch alerts on every creature of that type.");
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
